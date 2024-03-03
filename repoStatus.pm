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
my $dbg_mon = 1;
	# monitor busy work
my $dbg_status = 0;
	# the actual infor in an update

# details about updates

my $dbg_local_commits = 1;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		repoStatusInit
		repoStatusGet
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
my $stopping = 0;
my $last_update:shared = 0;


#---------------------------------------------
# API
#---------------------------------------------

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
	$status_thread = threads->create(\&_run);
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
	_setRepoStatus($REPO_STATUS_START);
}


sub repoStatusStop
{
	display($dbg_thread,0,"repoStatusStop");

	$stopping = 1;

	my $start = time();
	while ($repo_status &&
		$repo_status != $REPO_STATUS_STOPPED &&
		time() < $start + $STOP_TIMEOUT)
	{
		display($dbg_thread,1,"waiting for repoStatus monitor to stop ...");
		sleep(0.1);
	}

	warning(0,0,"timed out($STOP_TIMEOUT) trying to stop repoStatus monitor")
		if $repo_status != $REPO_STATUS_STOPPED;

}



#-----------------------------------------------------
# implementation
#-----------------------------------------------------

sub _setRepoStatus
{
	my ($status) = @_;
	display($dbg_mon,0,"_setRepoStatus("._repoStatusToString($status).")");
	$repo_status = $status;
}


sub _repoStatusToString
{
	my ($status) = @_;
	return
		$status == $REPO_STATUS_NONE  	    ? 'NONE' :
		$status == $REPO_STATUS_START 	    ? 'START' :
		$status == $REPO_STATUS_GET_EVENTS 	? 'GET_EVENTS' :
		$status == $REPO_STATUS_WAIT_MON    ? 'WAIT_MON' :
		$status == $REPO_STATUS_MON_READY   ? 'MON_READY' :
		$status == $REPO_STATUS_READY 	    ? 'READY' :
		$status == $REPO_STATUS_STOPPED 	? 'STOPPED' :
		'unknown repo status';
}



sub _run
{
	display($dbg_thread,0,"repoStatus::_run() started");

	my $events;

	while (1)
	{
		my $now = time();
		if ($stopping)
		{
			$stopping = 0;
			display($dbg_mon,0,"_run(STOPPING)");
			_setRepoStatus($REPO_STATUS_STOPPED);
		}
		elsif ($repo_status == $REPO_STATUS_START)
		{
			display($dbg_mon,0,"_run(START)");
			_setRepoStatus($REPO_STATUS_GET_EVENTS);
		}
		elsif ($repo_status == $REPO_STATUS_GET_EVENTS)
		{
			display($dbg_mon,0,"_run(GET_EVENTS)");
			my $git_user = getPref('GIT_USER');
			my $got_events = gitHubRequest('events',"users/$git_user/events?per_page=30",0,undef,\$etag);
			if (!defined($got_events))
			{
				error("Could not get github events");
				_setRepoStatus($REPO_STATUS_STOPPED);
			}
			else
			{
				!ref($got_events) ?
					display($dbg_status,1,"got status($got_events) events (no changes)") :
					($events = $got_events);
				_setRepoStatus($REPO_STATUS_WAIT_MON);
			}
		}
		elsif ($repo_status == $REPO_STATUS_WAIT_MON)
		{
			display($dbg_mon,0,"_run(MON_WAIT_MON)");
			if (!monitorStarted())
			{
				display($dbg_mon + 1,1,"waiting for monitorStarted");
				sleep(1);
			}
			else
			{
				_setRepoStatus($REPO_STATUS_MON_READY);
			}
		}
		elsif ($repo_status == $REPO_STATUS_MON_READY)
		{
			display($dbg_mon,0,"_run(MON_READY)");
			my $rslt = _doRepoStatus($events);
			if ($rslt)
			{
				_setRepoStatus($REPO_STATUS_READY);
				display($dbg_status,1,"will auto-update in $REFRESH_INTERVAL seonds")
					if $REFRESH_INTERVAL;
				$last_update = time();
			}
			elsif (!$stopping)
			{
				error("Could not get _doRepoStatus()");
				_setRepoStatus($REPO_STATUS_STOPPED);
			}
		}
		elsif ($repo_status == $REPO_STATUS_READY)
		{
			if ($REFRESH_INTERVAL && time() > $last_update + $REFRESH_INTERVAL)
			{
				display($dbg_status,0,"_run(HAVE_READY) doing automatic start ..");
				_setRepoStatus($REPO_STATUS_START) if !$stopping;
			}
			else
			{
				display($dbg_mon+1,0,"_run(HAVE_READY) sleeping for one second ..");
				sleep(1);
			}
		}
	}	# while (1)
}



sub _doRepoStatus
{
	my ($events) = @_;
	my $num_events = @$events;
	display($dbg_status,0,"_doRepoStatus() for $num_events events");

	my $repo_list = getRepoList();
	for my $repo (@$repo_list)
	{
		delete $repo->{AHEAD};
		delete $repo->{BEHIND};
		delete $repo->{local_commits};
		delete $repo->{remote_commits};

		# could do a gitStart, or even gitChanges here,
		# but lets go with whatever is on the repo for
		# MASTER_ID, REMOTE_ID, and unused (unused HEAD_ID)

		return 0 if $stopping;

		return 0 if !_addLocalCommits($repo);

	}

	return 1;
}




sub _addLocalCommitFound
{
	my ($ptext,$sha,$repo,$field) = @_;
	if ($sha eq $repo->{$field})
	{
		$$ptext .= ' ' if $$ptext;
		$$ptext .= $field;
		return 1;
	}
	return 0;
}


sub _addLocalCommits
{
	my ($repo,$git_repo) = @_;
	my $branch = $repo->{branch};
	$git_repo ||= Git::Raw::Repository->open($repo->{path});
	return !error("Could not open git_repo($repo->{path})")
		if !$git_repo;

	display($dbg_local_commits,0,"_addLocalCommits($repo->{path})");

	my $head_commit = Git::Raw::Reference->lookup("HEAD", $git_repo)->peel('commit') || '';

	my ($head_id_found,
		$master_id_found,
		$remote_id_found) = (0,0,0);

	my $log = $git_repo->walker();
	# $log->sorting(["time","reverse"]);
	$log->push($head_commit);

	my $com = $log->next();
	my $ahead = 0;

	while ($com && (
		!$head_id_found ||
		!$master_id_found ||
		!$remote_id_found ))
	{
		my $sha = $com->id();
		my $msg = $com->summary();
		my $time = timeToStr($com->time());
		my $extra = '';

		$head_id_found ||= _addLocalCommitFound(\$extra,$sha,$repo,'HEAD_ID');
		$master_id_found ||= _addLocalCommitFound(\$extra,$sha,$repo,'MASTER_ID');
		$remote_id_found ||= _addLocalCommitFound(\$extra,$sha,$repo,'REMOTE_ID');

		# these are from newest to oldest

		my $ahead_str = '';
		if ($master_id_found && !$remote_id_found)
		{
			$ahead++;
			$ahead_str = "AHEAD($ahead) ";
		}

		display($dbg_local_commits+1,1,pad($ahead_str,10)."$time ".pad($extra,30)._lim($sha,8)." "._lim($msg,20));

		$repo->{local_commits} ||= shared_clone([]);
		push @{$repo->{local_commits}},shared_clone({
			sha => $sha,
			msg => $msg,
		});

		$com = $log->next();
	}

	if ($ahead)
	{
		warning(0,1,"repo($repo->{path}) is AHEAD($ahead)") if $ahead;
		$repo->{AHEAD} = $ahead;
	}

	return $git_repo
}






1;
