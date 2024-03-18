#-----------------------------------------------
# Monitor all repo paths for changes
#-----------------------------------------------
# Uses a thread to watch for changes to repos.
# In general, the thread can be started (if not already running),
# paused, and stopped.
#
# Assumes someone else has parsed the repo().
# Calls gitChanges() on every repo during initialization.
# Stops if gitChanges() ever returns undef.
# Notifies via a callback if gitChanges() noted a change.
#
# uses Win32::ChangeNotify to monitor changes to all repo directories.
# For any directory that has changed, it calls gitChanges() and possibly
# notifies on the associated repo.
#
# Win32::ChangeNotify() can register on a flat folder, or a folder tree,
# including subfolders.  Note that for subfolders that are
# separate repos and submodules we will register on both the outer
# level repo and the inner level repo.  The outer level folder will
# receive uselsss ChangeNotifications and call gitChanges(), but that
# will return 0 (no new changes), and NOT call the UI.
#
# In practice this is efficient enough and does away with previous
# exclude and create submonitor hassles.  I am not cleaning that
# code up today, but much of this file is no longer needed.
#
# HAVE TO SEE if active processes like builds are upset by this,
# but they already have their own .git_ignores that I wasn't utilizing,
# and would have received all those notifications anyways.
#
# Note that Win32 MAXIMUM_WAIT_OBJECTS is 64, so they have to be
# broken into groups of 64 for Win32::ChangeNotify::wait_any()
# (Win32::IPC::wait_any) to work on more than 64.

package apps::gitUI::monitor;
use strict;
use warnings;
use threads;
use threads::shared;
use Win32::ChangeNotify;
use Time::HiRes qw(sleep time);
use apps::gitUI::repos;
use apps::gitUI::repoGit;
# use apps::gitUI::reposGithub;
use Pub::Utils;
use Pub::Prefs;


my $DELAY_MONITOR_STARTUP = 0;
	# Set this to number of seconds to delay monitor thread
	# actually starting, to see what happens to other threads
	# and program functions.
my $MONITOR_WAIT = 100;
	# milliseconds to wait for ChangeNotify events per monitor group
	# 100 milliseconds does not seem to tax the machine (task manager)
my $MONITOR_PAUSE_SLEEP = 0.2;
	# seconds to sleep in pause loop
	# determines latency for unpausing
	# 0.2 does not seem to tax the machine (task manager)
my $STATE_CHANGE_TIMEOUT = 2;
	# amount of time to wait for stopMonitor or pauseMonitor



my $dbg_thread = 0;
	# monitor thread lifecycle
my $dbg_mon = 1;
	# see creation of monitors
my $dbg_cb = 1;
	# debug callbacks
my $dbg_update = 0;
	# debug update
my $dbg_events = 1;
	# show event details
my $dbg_chgs = 1;
	# show notifies when gitChanges returns value



BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (

		monitorRunning
		monitorBusy

		monitorInit
		monitorStart
		monitorStop
		monitorPause
		monitorUpdate

		$MON_CB_TYPE_STATUS
		$MON_CB_TYPE_REPO
	);
}


our $MON_CB_TYPE_STATUS = 0;
our $MON_CB_TYPE_REPO = 1;

my $MAXIMUM_WAIT_OBJECTS = 64;
	# Windows limitation

# constants

my $WIN32_FILTER =
	# FILE_NOTIFY_CHANGE_ATTRIBUTES |  # Any attribute change
	FILE_NOTIFY_CHANGE_DIR_NAME   	|  # Any directory name change
	FILE_NOTIFY_CHANGE_FILE_NAME  	|  # Any file name change (creating/deleting/renaming)
	FILE_NOTIFY_CHANGE_LAST_WRITE 	|  # Any change to a file's last write time
	# FILE_NOTIFY_CHANGE_SECURITY   |  # Any security descriptor change
	#=FILE_NOTIFY_CHANGE_SIZE   	|  # Any file size changed
	0;

my ($MONITOR_STATE_NONE,
	$MONITOR_STATE_STARTING,
	$MONITOR_STATE_RUNNING,
	$MONITOR_STATE_UPDATE,
	$MONITOR_STATE_PAUSING,
	$MONITOR_STATE_PAUSED,
	$MONITOR_STATE_STOPPING,
	$MONITOR_STATE_STOPPED,
	$MONITOR_STATE_ERROR, ) = (0..100);

# vars

my $thread;
my $the_callback;

my $monitors;
my $monitor_groups;
my $monitor_state:shared = $MONITOR_STATE_NONE;

my $etag = '';
my $can_update:shared = 1;
my $last_update:shared = 0;


#------------------------------------------------
# API
#------------------------------------------------


sub monitorRunning
	# monitorRunning() indicates that a command can
	# take place, which *might* pause the monitor
	# or take place while the monitor is in an update.
{
	return
		$monitor_state == $MONITOR_STATE_RUNNING ||
		$monitor_state == $MONITOR_STATE_UPDATE ? 1 : 0;
}

sub monitorBusy
	# monitoryBusy() is specifically intended to allow
	# commands that might stop and restart the monitor.
{
	return
		$monitor_state != $MONITOR_STATE_RUNNING &&
		$monitor_state != $MONITOR_STATE_STOPPED ? 1 : 0;
}

sub monitorInit
{
	my ($callback) = @_;
	display($dbg_thread,-1,"monitorInit()");
	return !error("callback not specified")
		if !$callback;
	$the_callback = $callback,
	return monitorStart();
}


sub monitorStart
{
	display($dbg_thread,-1,"monitorStart()");
	return !error("attempt to monitorStart() in state ".monitorStateString($monitor_state)) if
		$monitor_state != $MONITOR_STATE_NONE &&
		$monitor_state != $MONITOR_STATE_STOPPED;

	setMonitorState($MONITOR_STATE_STARTING);
	$thread = threads->create(\&run);
	$thread->detach();
	display($dbg_thread,-2,"thread detached");
	return 1;
}


sub monitorStop
{
	display($dbg_mon,-1,"monitorStop()");
	return !error("attempt to monitorStop() in state ".monitorStateString($monitor_state)) if
		$monitor_state == $MONITOR_STATE_NONE ||
		$monitor_state == $MONITOR_STATE_ERROR;
	setMonitorState($MONITOR_STATE_STOPPING);
	return _waitMonitorState($MONITOR_STATE_STOPPED);
}


sub monitorPause
{
	my ($pause) = @_;
	display($dbg_mon,-1,"monitorPause($pause)");

	if ($pause)
	{
		return !error("attempt to monitorPause(1) in state ".monitorStateString($monitor_state)) if
			$monitor_state == $MONITOR_STATE_NONE ||
			$monitor_state == $MONITOR_STATE_STOPPED ||
			$monitor_state == $MONITOR_STATE_ERROR;
		setMonitorState($MONITOR_STATE_PAUSING);
		return _waitMonitorState($MONITOR_STATE_PAUSED);
	}
	return !error("attempt to monitorPause(0) in state ".monitorStateString($monitor_state)) if
		$monitor_state != $MONITOR_STATE_PAUSED;
	setMonitorState($MONITOR_STATE_RUNNING);
}


sub monitorUpdate
	# $reset_timer merely resets the update timer so
	# that the update will occur 3 seconds after the monitor is
	# re-started as soon as possible after a series of
	# pushes.
{
	my ($reset_timer) = @_;
	$reset_timer ||= 0;
	display($dbg_mon,-1,"monitorUpdate($reset_timer)");
	if ($reset_timer)
	{
		my $update_interval = getPref("GIT_UPDATE_INTERVAL");
		$last_update = time() - $update_interval + 3 if $update_interval;
		return;
	}

	return !error("attempt to monitorUpdate() in state ".monitorStateString($monitor_state)) if
		$monitor_state == $MONITOR_STATE_NONE ||
		$monitor_state == $MONITOR_STATE_STOPPED ||
		$monitor_state == $MONITOR_STATE_ERROR;
	$can_update = 1;
	setMonitorState($MONITOR_STATE_UPDATE);
}




#------------------------------------------------
# State Machine
#------------------------------------------------

sub setMonitorState
{
	my ($state) = @_;
	display($dbg_thread,-2,"setMonitorState(".monitorStateString($state).")");
	$monitor_state = $state;
}


sub monitorStateString
{
	my ($state) = @_;
	return
		$state == $MONITOR_STATE_NONE     ? 'NONE' :
		$state == $MONITOR_STATE_STARTING ? 'STARTING' :
		$state == $MONITOR_STATE_RUNNING  ? 'RUNNING' :
		$state == $MONITOR_STATE_UPDATE   ? 'UPDATE' :
		$state == $MONITOR_STATE_PAUSING  ? 'PAUSING' :
		$state == $MONITOR_STATE_PAUSED   ? 'PAUSED' :
		$state == $MONITOR_STATE_STOPPING ? 'STOPPING' :
		$state == $MONITOR_STATE_STOPPED  ? 'STOPPED' :
		$state == $MONITOR_STATE_ERROR    ? 'ERROR' :
		'unknown monitor state';
}


sub _waitMonitorState
{
	my ($wait_for_state) = @_;
	my $name = monitorStateString($wait_for_state);
	display($dbg_thread,-2,"_waitMonitorState($name)");

	my $start = time();
	while ($monitor_state != $wait_for_state &&
		time() < $start + $STATE_CHANGE_TIMEOUT)
	{
		display($dbg_thread,-3,"waiting for monitorState($name) ...");
		sleep(0.1);
	}

	if ($monitor_state != $wait_for_state)
	{
		warning(0,-3,"timed out($STATE_CHANGE_TIMEOUT) waiting for monitorState($name) ".
			"state=".monitorStateString($monitor_state)." FORCING STATE");
		$monitor_state = $wait_for_state;
		return 0;
	}

	sleep(0.2);
	return 1;
}


#------------------------------------------------------
# run()
#------------------------------------------------------

sub run
{
	display($dbg_thread,0,"monitor::run()");

	$monitors = [];
	$monitor_groups = [];
	push @$monitor_groups,$monitors;

	if ($DELAY_MONITOR_STARTUP)		# to see startup before any events occur
	{
		warning(0,0,"Delaying monitor startup by $DELAY_MONITOR_STARTUP seconds");
		sleep($DELAY_MONITOR_STARTUP);
	}

	my $rslt = 1;
	while (1)
	{
		display($dbg_thread+1,-1,"thread {top}");

		if ($monitor_state == $MONITOR_STATE_STOPPING)
		{
			display($dbg_thread,0,"thread {stopping}");
			last;
		}
		elsif ($monitor_state == $MONITOR_STATE_PAUSING)
		{
			display($dbg_thread,-1,"thread {pausing}");
			setMonitorState($MONITOR_STATE_PAUSED);
		}
		elsif ($monitor_state == $MONITOR_STATE_PAUSED)
		{
			display($dbg_thread+1,-1,"thread {paused}");
			sleep($MONITOR_PAUSE_SLEEP);
		}

		elsif ($monitor_state == $MONITOR_STATE_STARTING)
		{
			display($dbg_thread,-1,"thread {starting}");
			$rslt = doMonitorStartup();
			last if !$rslt;
			display($dbg_thread,-1,"thread {started}");
			setMonitorState($MONITOR_STATE_RUNNING);
		}
		elsif ($monitor_state == $MONITOR_STATE_UPDATE)
		{
			display($dbg_thread,-1,"thread {update}");
			$can_update = doMonitorUpdate();
			$last_update = time();
			setMonitorState($MONITOR_STATE_RUNNING);
		}
		elsif ($monitor_state == $MONITOR_STATE_RUNNING)
		{
			display($dbg_thread+1,-1,"thread {running}");
			my $update_interval = getPref("GIT_UPDATE_INTERVAL");
			if ($can_update && $update_interval &&
				time() > $last_update + $update_interval)
			{
				setMonitorState($MONITOR_STATE_UPDATE);
			}
			else
			{
				$rslt = doMonitorRun();
				last if !$rslt;
			}
		}
		else
		{
			error("unexpected monitor state ".monitorStateString($monitor_state));
			$rslt = 0;
			last;
		}

	}	# while (1)

	if (!$rslt)
	{
		error("MONITOR STOPPED DUE TO ERROR!!");
		&$the_callback({ status =>"MONITOR STOPPED DUE TO ERROR!!" });
		setMonitorState($MONITOR_STATE_ERROR);
	}
	else
	{
		display($dbg_thread,-1,"thread {stopped}");
		setMonitorState($MONITOR_STATE_STOPPED);
	}

	$monitors = undef;
	$monitor_groups = [];

	display($dbg_thread,-1,"thread {exiting}");

}	# monitor::run()




#----------------------------------------------------
# atoms
#----------------------------------------------------

sub getRepoPaths
	# the monitor works on unique repos that have been
	# added to the system with paths.
{
	my $repos_by_path = getReposByPath();
	return sort keys %$repos_by_path;
}

sub doMonitorStartup
{
	display($dbg_thread,-1,"doMonitorStartup()");
	&$the_callback({ status =>"starting" });

	my $num = 0;
	my $group = 0;
	my @repo_paths = getRepoPaths();
	for my $path (@repo_paths)
	{
		if ($num == $MAXIMUM_WAIT_OBJECTS)
		{
			$num = 0;
			$group++;
			$monitors = [];
			push @$monitor_groups,$monitors;
		}

		&$the_callback({ status =>"monitor: $path" });
		display($dbg_mon,-2,"CREATE MONITOR[$group:$num] $path");
		my $mon = Win32::ChangeNotify->new($path,1,$WIN32_FILTER);
		if (!$mon)
		{
			error("apps::gitUI::monitor::createMonitor() - Could not create monitor($group:$num) $path");
			return 0;
		}
		push @$monitors,$mon;
		$num++;
	}

	for my $path (@repo_paths)
	{
		my $repo = getRepoByPath($path);
		display($dbg_mon,-2,"initial call to gitChanges($repo->{path})");
		&$the_callback({ status =>"checking: $repo->{path}" });
		my $rslt = gitChanges($repo);
		return 0 if !defined($rslt);
		if ($rslt)
		{
			display($dbg_chgs,-2,"notifyRepoChanged(init,$repo->{path})");
			setCanPushPull($repo);
		}
		&$the_callback({ repo=>$repo, changed=>$rslt });
	}

	# do an update as part of the startup
	# before any commands are allowed ..

	if ($can_update)
	{
		$can_update = doMonitorUpdate() ;
		$last_update = time();
	}

	&$the_callback({ status =>"started" });
	return 1;
}


sub doMonitorRun
{
	display($dbg_thread+1,-1,"doMonitorRun()");

	my $group = 0;
	my @repo_paths = getRepoPaths();
	for $monitors (@$monitor_groups)
	{
		my $ready = Win32::ChangeNotify::wait_any(@$monitors,$MONITOR_WAIT);
		if (!defined($ready))
		{
			error("Error in Win32::ChangeNotify() group($group): $^E");
			return 0;
		}
		if ($ready)
		{
			$monitors->[$ready-1]->reset();
			my $num = $group * $MAXIMUM_WAIT_OBJECTS + $ready-1;
			my $path = $repo_paths[$num];
			my $repo = getRepoByPath($path);
			display($dbg_cb,-2,"win_notify[$group:".($ready-1)."] $repo->{path}");

			my $rslt = gitChanges($repo);
			display($dbg_cb,-2,"gitChanges="._def($rslt));
			return 0 if !defined($rslt);
			if ($rslt)
			{
				display($dbg_chgs,-2,"notifyRepoChanged($repo->{path})");
				setCanPushPull($repo);
			}

			&$the_callback({ repo=>$repo, changed=>$rslt });

		}	# a monitor is reaady

		$group++;

	}	# for each monitor_group

	return 1;
}


sub doMonitorUpdate
{
	display($dbg_thread,-1,"doMonitorUpdate()");
	&$the_callback({ status =>"doing Update" });

	my $git_user = getPref('GIT_USER');
	my $got_events = apps::gitUI::reposGithub::gitHubRequest(
		'events',
		"users/$git_user/events?per_page=30",
		0,
		undef,
		\$etag);

	if (!defined($got_events))
	{
		error("Could not get github events");
		return 0;
	}

	if (!ref($got_events))
	{
		display($dbg_update,1,"got status($got_events) events (no changes)");
		&$the_callback({ status =>"Update: no changes" });
		return 1;
	}

	my $rslt = updateStatusAll($got_events);
	&$the_callback({ status =>"Update finished" }) if $rslt;
	return $rslt;
}


#------------------------------------------
# update primitives
#------------------------------------------

sub updateStatusAll
	# the main method that updates the status for all repos
{
	my ($events) = @_;
	my $num_events = @$events;
	display($dbg_update,-1,"updateStatusAll() for $num_events events");

	my $repo_list = getRepoList();
	for my $repo (@$repo_list)
	{
		next if !$repo->isLocalAndRemote();
		return 0 if !initRepoStatus($repo);
	}

	for my $event (reverse @$events)
	{
		return 0 if !oneEvent($event);
	}

	for my $repo (@$repo_list)
	{
		next if !$repo->isLocalAndRemote();
		return 0 if !finishRepoStatus($repo);
	}

	return 1;
}



sub initRepoStatus
{
	my ($repo) = @_;

	$repo->{save_BEHIND} 	= $repo->{BEHIND};
	$repo->{save_GITHUB_ID} = $repo->{GITHUB_ID} || '';

	$repo->{BEHIND} = 0;
	$repo->{found_REMOTE_ID_on_github} = 0;

	delete $repo->{remote_commits};
	return gitStart($repo);
}


sub finishRepoStatus
{
	my ($repo) = @_;
	my $changed = 0;

	if ($repo->{BEHIND} != $repo->{save_BEHIND})
	{
		$changed = 1;
		display($dbg_update,-2,"BEHIND_CHANGED(from $repo->{save_BEHIND} to $repo->{BEHIND}) for $repo->{path}",0,$UTILS_COLOR_CYAN);
	}
	if ($repo->{GITHUB_ID} ne $repo->{save_GITHUB_ID})
	{
		$changed = 1;
		display($dbg_update,-2,"GITHUB_ID_CHANGED(from ".
			_lim($repo->{save_GITHUB_ID},8)." to ".
			_lim($repo->{GITHUB_ID},8).") for $repo->{path}",
			0,$UTILS_COLOR_CYAN) if $repo->{save_GITHUB_ID};
	}

	delete $repo->{save_BEHIND};
	delete $repo->{save_GITHUB_ID};
	delete $repo->{found_REMOTE_ID_on_github};

	if ($changed)
	{
		display($dbg_update+1,-2,"STATUS_REPO_CHANGED($repo->{path})",0,$UTILS_COLOR_CYAN);
		setCanPushPull($repo);
		&$the_callback({ repo=>$repo });
	}

	return 1;
}


sub oneEvent
	# Todo: I believe that we now need to pay attention to BRANCHES in gitHub events
{
	my ($event) = @_;
	my $event_id = $event->{id};
	my $type = $event->{type};
	return 1 if $type ne 'PushEvent';
		# We are only interested in PushEvents
		# see https://docs.github.com/en/rest/using-the-rest-api/github-event-types?apiVersion=2022-11-28

	my $git_user = getPref('GIT_USER');

	my $time_str = $event->{created_at} || '';
	my $time = gmtToInt($time_str);
	my $github_repo = $event->{repo} || '';
	my $repo_id = $github_repo->{name} || '';
	$repo_id =~ s/^$git_user\///;

	my $repo = getRepoById($repo_id) || '';
	return !error("Could not find repo($repo_id) in event($event_id)")
		if !$repo;

	my $payload = $event->{payload} || '';
	my $head = $payload ? $payload->{head} || '' : '';
	my $before = $payload ? $payload->{before} || '' : '';
	my $commits = $payload ? $payload->{commits} : '';

	return !error("No 'before' in event($event_id) path($repo->{path})")
		if !$before;
	return !error("No 'head' in event($event_id) path($repo->{path})")
		if !$head;
	if (!$commits || !@$commits)
	{
		warning($dbg_events,-2,"No commits in event($event_id) path($repo->{path})");
		return 1;
	}

	display($dbg_events,-2,"commits for repo($repo_id=$repo->{path}) at $time_str");
	display($dbg_events,-3,"before=$before") if $before;

	return 0 if !oneRepoEvent($repo,$event_id,$time,$head,$before,$commits);

	# add the event analogously to all submodules

	if ($repo->{used_in})
	{
		for my $sub_path (@{$repo->{used_in}})
		{
			my $sub_repo = getRepoByPath($sub_path);
			return !error("Could not find submodule($sub_path) in event($event_id) path($repo->{path})")
				if !$sub_repo;
			return 0 if !oneRepoEvent($sub_repo,$event_id,$time,$head,$before,$commits);
		}
	}

	return 1;
}


sub oneRepoEvent
{
	my ($repo,$event_id,$time,$head,$before,$commits) = @_;
	my $num_commits = @$commits;
	display($dbg_events,-2,"onRepoEvent($repo->{path}) for $num_commits commits");

	# start counting remote commits after those
	# known by the local repo ..

	$repo->{found_REMOTE_ID_on_github} = 1
		if $before eq $repo->{REMOTE_ID};
	$repo->{remote_commits} ||= shared_clone([]);

	# the head will always be the last commit in the commit list
	# repoDisplay(0,1,"head=$head") if $head;
	# checkEventCommit($repo,$head,'payload_head');

	my $sha = '';
	for my $commit (@$commits)
	{
		$sha = $commit->{sha} || '';
		my $msg = $commit->{message} || '';
		$msg =~ s/\n/ /g;
		$msg =~ s/\t/ /g;

		my $behind_str = '';
		if ($sha eq $repo->{REMOTE_ID})
		{
			$repo->{found_REMOTE_ID_on_github} = 1;
		}
		elsif ($repo->{found_REMOTE_ID_on_github})
		{
			$repo->{BEHIND}++;
			$behind_str = "BEHIND($repo->{BEHIND})";
		}

		# only push events starting with the found remote ID
		# we don't need to see, although we debug, the others.

		push @{$repo->{remote_commits}},shared_clone({
			sha => $sha,
			msg => $msg,
			time => $time }) if $repo->{found_REMOTE_ID_on_github};

		display($dbg_events,-3,pad($behind_str,10)._lim($sha,8)._lim($msg,40));
	}

	return !error("head($head)<>last_commit($sha) in event($event_id) path($repo->{path})")
		if $sha ne $head;

	$repo->{GITHUB_ID} = $sha;
	return 1;
}



1;
