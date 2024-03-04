#----------------------------------------------------
# repoStatus.pm
#----------------------------------------------------
# thread and methods to monitor and update remote git
# changes and local submodules.
#
# uses same notifyRepoChanged() method as the monitor
# thread.
#
# can be restarted in the middle of an existing 'update'


package apps::gitUI::repoStatus;
use strict;
use warnings;
use threads;
use threads::shared;
use Time::HiRes qw(time sleep);
use Pub::Utils;
use Pub::Prefs;
use apps::gitUI::utils;
use apps::gitUI::repo;
use apps::gitUI::repos;
use apps::gitUI::repoGit;
use apps::gitUI::reposGithub;
use apps::gitUI::monitor;

my $STOP_TIMEOUT = 2;
my $DEFAULT_REFRESH_INTERVAL = 90;


my $dbg_thread = 0;
	# thread and API commans
my $dbg_mon = 0;
	# monitor busy work
my $dbg_status = 0;
	# the actual info in an update
my $dbg_events = 1;
	# the adding of remote_commits
my $dbg_notify = -1;
	# noitification if repo changed


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		repoStatusBusy
		repoStatusInit
		repoStatusStart
		repoStatusStop
		repoStatusReady
	);
}


my $REPO_STATUS_NONE = 0;
my $REPO_STATUS_START = 1;
my $REPO_STATUS_GET_EVENTS = 2;
my $REPO_STATUS_WAIT_MON = 4;
my $REPO_STATUS_MON_READY = 5;
my $REPO_STATUS_READY = 6;
my $REPO_STATUS_STOPPED = 7;


my $etag = '';
my $status_thread;
my $the_callback;
my $REFRESH_INTERVAL = 0;

my $repo_status:shared = $REPO_STATUS_NONE;
my $stopping:shared = 0;
my $last_update:shared = 0;


#---------------------------------------------
# API
#---------------------------------------------

sub repoStatusBusy
{
	return
		$repo_status &&
		$repo_status < $REPO_STATUS_READY;
}

sub repoStatusInit
{
	my ($callback) = @_;
	display($dbg_thread,0,"repoStatusInit()");
	return !error("callback not specified")
		if !$callback;
	$the_callback = $callback,

	$REFRESH_INTERVAL = getPref('GITHUB_UPDATE_INTERVAL');
	$REFRESH_INTERVAL = $DEFAULT_REFRESH_INTERVAL if !defined($REFRESH_INTERVAL);

	display($dbg_thread,0,"starting status_thread INTERVAL($REFRESH_INTERVAL)");
	$status_thread = threads->create(\&run);
	$status_thread->detach();
	display($dbg_thread,0,"status_thread started");

	# always do at least one repoStatus() per program
	# invocation

	repoStatusStart();
	return 1;
}



sub repoStatusStart
	# stop it if it's running
{
	display($dbg_thread,0,"repoStatusStart");
	repoStatusStop();
	setStatusState($REPO_STATUS_START);
}


sub repoStatusStop
{
	display($dbg_thread,0,"repoStatusStop");

	$stopping = 1;

	my $start = time();
	while ($repo_status != $REPO_STATUS_STOPPED &&
		time() < $start + $STOP_TIMEOUT)
	{
		display($dbg_thread,1,"waiting for repoStatus monitor to stop ...");
		sleep(0.1);
	}
	$stopping = 0;
	warning(0,0,"timed out($STOP_TIMEOUT) trying to stop repoStatus monitor")
		if $repo_status && $repo_status != $REPO_STATUS_STOPPED;


}



#-----------------------------------------------------
# implementation
#-----------------------------------------------------

sub setStatusState
{
	my ($state) = @_;
	display($dbg_mon,0,"setStatusState(".statusStateToString($state).")");
	$repo_status = $state;
}


sub statusStateToString
{
	my ($state) = @_;
	return
		$state == $REPO_STATUS_NONE  	    ? 'NONE' :
		$state == $REPO_STATUS_START 	    ? 'START' :
		$state == $REPO_STATUS_GET_EVENTS 	? 'GET_EVENTS' :
		$state == $REPO_STATUS_WAIT_MON    ? 'WAIT_MON' :
		$state == $REPO_STATUS_MON_READY   ? 'MON_READY' :
		$state == $REPO_STATUS_READY 	    ? 'READY' :
		$state == $REPO_STATUS_STOPPED 	? 'STOPPED' :
		'unknown repo status';
}



sub run
{
	display($dbg_thread,0,"repoStatus::run() started");

	my $events;

	while (1)
	{
		my $now = time();
		if ($stopping)
		{
			display($dbg_thread,0,"run(STOPPING)");
			setStatusState($REPO_STATUS_STOPPED);
			$stopping = 0;
		}
		elsif ($repo_status == $REPO_STATUS_START)
		{
			display($dbg_mon,0,"run(START)");
			setStatusState($REPO_STATUS_GET_EVENTS);
		}
		elsif ($repo_status == $REPO_STATUS_GET_EVENTS)
		{
			display($dbg_mon,0,"run(GET_EVENTS)");
			my $git_user = getPref('GIT_USER');
			my $got_events = gitHubRequest('events',"users/$git_user/events?per_page=30",0,undef,\$etag);
			if (!defined($got_events))
			{
				error("Could not get github events");
				setStatusState($REPO_STATUS_STOPPED);
			}
			else
			{
				!ref($got_events) ?
					display($dbg_status,1,"got status($got_events) events (no changes)") :
					($events = $got_events);
				setStatusState($REPO_STATUS_WAIT_MON);
			}
		}
		elsif ($repo_status == $REPO_STATUS_WAIT_MON)
		{
			display($dbg_mon,0,"run(MON_WAIT_MON)");
			if (!monitorStarted())
			{
				display($dbg_mon + 1,1,"waiting for monitorStarted");
				sleep(1);
			}
			else
			{
				setStatusState($REPO_STATUS_MON_READY);
			}
		}
		elsif ($repo_status == $REPO_STATUS_MON_READY)
		{
			display($dbg_mon,0,"run(MON_READY)");
			my $rslt = updateStatusAll($events);
			if ($rslt)
			{
				setStatusState($REPO_STATUS_READY);
				display($dbg_status,1,"will auto-update in $REFRESH_INTERVAL seonds")
					if $REFRESH_INTERVAL;
				$last_update = time();
			}
			elsif (!$stopping)
			{
				error("Could not get updateStatusAll()");
				setStatusState($REPO_STATUS_STOPPED);
			}
		}
		elsif ($repo_status == $REPO_STATUS_READY)
		{
			if ($REFRESH_INTERVAL && time() > $last_update + $REFRESH_INTERVAL)
			{
				display($dbg_status,0,"run(HAVE_READY) doing automatic start ..");
				setStatusState($REPO_STATUS_START) if !$stopping;
			}
			else
			{
				display($dbg_mon+1,0,"run(HAVE_READY) sleeping for one second ..");
				sleep(1);
			}
		}
	}	# while (1)
}



#---------------------------------------------------------------------------
# status workers
#---------------------------------------------------------------------------

sub initRepoStatus
{
	my ($repo) = @_;
	$repo->{save_AHEAD} 	= $repo->{AHEAD};
	$repo->{save_BEHIND} 	= $repo->{BEHIND};
	$repo->{save_HEAD_ID} 	= $repo->{HEAD_ID};
	$repo->{save_MASTER_ID} = $repo->{MASTER_ID};
	$repo->{save_REMOTE_ID} = $repo->{REMOTE_ID};
	$repo->{save_GITHUB_ID} = $repo->{GITHUB_ID};
	$repo->{save_REMOTE_COMMITS} = $repo->{remote_commits};

	$repo->{AHEAD} = 0;
	$repo->{BEHIND} = 0;
	$repo->{found_REMOTE_ID_on_github} = 0;

	delete $repo->{local_commits};
	delete $repo->{remote_commits};
	return gitStart($repo);
}


sub checkChanged
{
	my ($numeric,$pchanged,$repo,$field) = @_;
	my $save_field = "save_$field";
	my $val = $repo->{$field};
	my $save_val = $repo->{$save_field};
	my $eq = $numeric ?
		($val == $save_val) :
		($val eq $save_val);
	if (!$eq)
	{
		$$pchanged = 1;
		display($dbg_notify,0,"changed($field) from $save_val to $val on repo($repo->{path})",0,$UTILS_COLOR_CYAN);
	}
}

sub checkRemoteCommitsChanged
	# if two subsequent events lists return the same
	# number of events for a repo, I consider it unchanged
{
	my ($pchanged,$repo) = @_;
	my $remote_commits = $repo->{remote_commits};
	my $saved_commits = $repo->{save_REMOTE_COMMITS};
	$$pchanged = 1 if
		($remote_commits && !$saved_commits) ||
		(!$remote_commits && $saved_commits) ||
		($remote_commits && scalar(@$remote_commits) != scalar(@$saved_commits));
	delete $repo->{save_REMOTE_COMMITS};
}


sub finishRepoStatus
{
	my ($repo) = @_;
	my $changed = 0;
	checkChanged(1,\$changed,$repo,'AHEAD');
	checkChanged(1,\$changed,$repo,'BEHIND');
	checkChanged(0,\$changed,$repo,'HEAD_ID');
	checkChanged(0,\$changed,$repo,'MASTER_ID');
	checkChanged(0,\$changed,$repo,'REMOTE_ID');
	checkChanged(0,\$changed,$repo,'GITHUB_ID');
	checkRemoteCommitsChanged(\$changed,$repo);
	delete $repo->{found_REMOTE_ID_on_github};

	if ($changed)
	{
		display($dbg_notify+1,0,"STATUS_REPO_CHANGED($repo->{path})",0,$UTILS_COLOR_CYAN);
		&$the_callback({ repo=>$repo });
	}
}


sub updateStatusAll
	# the main method that updates the status for all repos
{
	my ($events) = @_;
	my $num_events = @$events;
	display($dbg_status,0,"updateStatusAll() for $num_events events");

	my $repo_list = getRepoList();
	for my $repo (@$repo_list)
	{
		return 0 if !initRepoStatus($repo);
		return 0 if $stopping;
	}

	for my $event (reverse @$events)
	{
		oneEvent($event);
	}

	for my $repo (@$repo_list)
	{
		finishRepoStatus($repo);
	}

	return 1;
}



sub oneEvent
{
	my ($event) = @_;
	my $event_id = $event->{id};
	my $type = $event->{type};
	return if $type ne 'PushEvent';
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
	return !error("No commits in event($event_id) path($repo->{path})")
		if !$commits || !@$commits;

	display($dbg_events,0,"commits for repo($repo_id=$repo->{path}) at $time_str");
	display($dbg_events,1,"before=$before") if $before;

	return if !oneRepoEvent($repo,$event_id,$time,$head,$before,$commits);

	# add the event analogously to all submodules

	if ($repo->{used_in})
	{
		for my $sub_path (@{$repo->{used_in}})
		{
			my $sub_repo = getRepoByPath($sub_path);
			return !error("Could not find submodule($sub_path) in event($event_id) path($repo->{path})")
				if !$sub_repo;
			return if !oneRepoEvent($sub_repo,$event_id,$time,$head,$before,$commits);
		}
	}

	return 1;
}


sub oneRepoEvent
{
	my ($repo,$event_id,$time,$head,$before,$commits) = @_;
	my $num_commits = @$commits;
	display($dbg_events,0,"onRepoEvent($repo->{path}) for $num_commits commits");

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
		push @{$repo->{remote_commits}},shared_clone({
			sha => $sha,
			msg => $msg,
			time => $time });

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

		display($dbg_events,2,pad($behind_str,10)._lim($sha,8)._lim($msg,40));
	}

	return !error("head($head)<>last_commit($sha) in event($event_id) path($repo->{path})")
		if $sha ne $head;

	$repo->{GITHUB_ID} = $sha;
	return 1;

}






1;
