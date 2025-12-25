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

package apps::gitMUI::monitor;
use strict;
use warnings;
use threads;
use threads::shared;
use Win32::ChangeNotify;
use Time::HiRes qw(sleep time);
use apps::gitMUI::repo;
use apps::gitMUI::repos;
use apps::gitMUI::repoGit;
use apps::gitMUI::reposGithub;
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
my $dbg_thread2 = 0;
	# monitor the 2nd thread


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (

		monitorRunning
		monitorBusy

		monitorInit
		monitorStart
		monitorStop
		monitorPause

		doMonitorUpdate

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
	$MONITOR_STATE_PAUSING,
	$MONITOR_STATE_PAUSED,
	$MONITOR_STATE_STOPPING,
	$MONITOR_STATE_STOPPED,
	$MONITOR_STATE_ERROR, ) = (0..100);

# vars

my $thread;
my $thread2;
my $the_callback;

my $monitors;
my $monitor_groups;
my $monitor_state:shared = $MONITOR_STATE_NONE;
my $update_busy:shared = 1;


#------------------------------------------------
# API
#------------------------------------------------


sub monitorRunning
	# monitorRunning() indicates that a command can
	# take place, which *might* pause the monitor
	# or take place while the monitor is in an update.
{
	return
	$update_busy ||
		$monitor_state == $MONITOR_STATE_RUNNING ? 1 : 0;
}


sub monitorBusy
	# monitoryBusy() is specifically intended to allow
	# commands that might stop and restart the monitor.
{
	return
		!$update_busy &&
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

	my $update_interval = getPref("GIT_UPDATE_INTERVAL");
	if ($update_interval)
	{
		$thread2 = threads->create(\&githubThread);
		$thread2->detach();
		display($dbg_thread2,-2,"githubThread detached");
	}
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
		elsif ($monitor_state == $MONITOR_STATE_RUNNING)
		{
			display($dbg_thread+1,-1,"thread {running}");
			$rslt = doMonitorRun();
			last if !$rslt;
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
			error("apps::gitMUI::monitor::createMonitor() - Could not create monitor($group:$num) $path");
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






#--------------------------------------------------------
# GITHUB UPDATE
#--------------------------------------------------------

my $DELAY_GITHUB_THREAD = 4;

my $last_update:shared = 0;
my $update_step:shared = 0;

sub doMonitorUpdate
{
	display($dbg_thread2,-1,"doMonitorUpdate()");
	$last_update = 0;
}


sub githubThread
{
	if ($DELAY_GITHUB_THREAD)		# to see startup before any events occur
	{
		warning(0,0,"Delaying githubThread startup by $DELAY_GITHUB_THREAD seconds");
		sleep($DELAY_GITHUB_THREAD);
	}
 
	display($dbg_thread2,0,"monitor::githubThread() starting");
	my $update_interval = getPref("GIT_UPDATE_INTERVAL");
	while (1)
	{
		if ($monitor_state == $MONITOR_STATE_STOPPING)
		{
			display($dbg_thread2,0,"githubThread {stopping}");
			last;
		}
		elsif ($monitor_state != $MONITOR_STATE_RUNNING)
		{
			$update_step = 0;
			sleep(1);
		}
		elsif ($update_step)
		{
			doUpdateStep();
		}
		elsif (time() > $last_update + $update_interval)
		{
			$last_update = time();
			$update_busy = 1;
			warning($dbg_thread2,0,"starting GitHub update");
			&$the_callback({ status =>"starting GitHub update" });
			$update_step = 1;
		}
		else
		{
			sleep(1);
		}
	}

	display($dbg_thread2,0,"monitor::githubThread() exiting");
}


sub doUpdateStep
	# the first N steps get bulk pages and note any new
	# 	pushed_at times, marking those repos as needing new SHAs
	# steps starting at 100 iterate through any repos that need
	# 	sha's and get them.
	# a single update cycle is then finished and we wait
	#	$update_interval seconds to start another one.
{
	display($dbg_thread2,0,"doUpdateStep($update_step)");
	my $repo_list = getRepoList();

	if ($update_step < 100)		# synonymous with page number
	{
		my $same_page = $update_step;
		display($dbg_thread2,1,"getting page($update_step)");
		&$the_callback({ status =>"get GitHub repos page($update_step)" });
		my $data = gitHubRequest(1,$HOW_GITHUB_NORMAL,"repos","user/repos?per_page=50",\$update_step);
		if ($data)
		{
			my %pushed_ats;
			for my $entry (@$data)
			{
				my $id = $entry->{name};
				$pushed_ats{$id} = $entry->{pushed_at};
			}
			for my $repo (@$repo_list)
			{
				next if !($repo->{exists} & $REPO_LOCAL);
					# don't touch REMOTE_ONLY repos
					# also of interest is {rel_path} local submodules
				my $id = $repo->{id};
				my $pushed_at = $pushed_ats{$id};
				my $repo_pushed_at = $repo->{pushed_at} || '';
				if ($pushed_at && $repo_pushed_at ne $pushed_at)
				{
					warning($dbg_thread2,2,"repo($repo->{id}) pushed_at($repo_pushed_at) changed to $pushed_at");
					$repo->{needs_update} = 1;
					$repo->{pushed_at} = $pushed_at;
				}
			}
			if ($update_step == $same_page)
			{
				warning($dbg_thread2,1,"finished getting pages");
				$update_step = 100;
			}
		}
		else
		{
			warning($dbg_thread2,1,"NO DATA getting page($same_page)");
			$update_step = 0;
			$update_busy = 0;
		}
	}
	else
	{
		my $repo;
		for my $try (sort {$a->{pushed_at} cmp $b->{pushed_at}} @$repo_list)
		{
			if ($try->{needs_update})
			{
				delete $try->{needs_update};
				$repo = $try;
				last;
			}
		}
		if ($repo)
		{
			# GET https://api.github.com/repos/{owner}/{repo}/branches/master

			my $id = $repo->{id};
			my $branch = $repo->{branch};
			my $what = "sha_$id";
			my $git_user = getPref("GIT_USER");
			display($dbg_thread2,2,"getting SHA($id)");
			&$the_callback({ status =>"get GitHub SHA($id)" });
			my $data = gitHubRequest(1,$HOW_GITHUB_NORMAL,$what,"repos/$git_user/$id/branches/$branch");
			my $commit = $data ? $data->{commit} : '';
			my $sha = $commit ? $commit->{sha} : '';
			if ($sha)
			{
				if ($repo->{GITHUB_ID} ne $sha)
				{
					warning($dbg_thread2,2,"SHA($id) changed from($repo->{GITHUB_ID}) to $sha");
					$repo->{GITHUB_ID} = $sha;
					if ($repo->{GITHUB_ID} eq $repo->{REMOTE_ID})
					{
						if ($repo->{BEHIND})
						{
							warning($dbg_thread2,2,"clearing BEHIND($id)=0");
							$repo->{BEHIND} = 0;
						}
					}
					else
					{
						if (!$repo->{BEHIND})
						{
							warning($dbg_thread2,2,"setting BEHIND($id)=1");
							$repo->{BEHIND} = 1;
						}
					}

					&$the_callback({ repo=>$repo });
				}
			}
			else
			{
				warning($dbg_thread2,1,"Could not get SHA($id)");
			}
		}
		else
		{
			warning($dbg_thread2,1,"finished getting SHA's");
			&$the_callback({ status =>"GitHub update finished" });
			$update_step = 0;
			$update_busy = 0;
		}
	}

	$last_update = time();
}


1;
