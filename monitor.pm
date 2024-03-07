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
use Pub::Utils;



my $DELAY_MONITOR_STARTUP = 0;
	# Set this to number of seconds to delay monitor thread
	# actually starting, to see what happens to other threads
	# and program functions.
my $MONITOR_WAIT = 100;
	# milliseconds 100 milliseconds does not seem
	# to tax the machine (task manager)
my $MONITOR_PAUSE_SLEEP = 0.2;
	# seconds to sleep in pause loop

my $MAXIMUM_WAIT_OBJECTS = 64;
	# Windows limitation

my $dbg_thread = 0;
	# monitor thread lifecycle
my $dbg_pause = 0;
	# debug the pause
my $dbg_mon = 1;
	# see creation of monitors
my $dbg_cb = 1;
	# debug callbacks and events


our $MON_CB_TYPE_STATUS = 0;
our $MON_CB_TYPE_REPO = 1;


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (

		monitorInit
		monitorStart
		monitorStop
		monitorStarted
		monitorPause

		$MON_CB_TYPE_STATUS
		$MON_CB_TYPE_REPO
	);
}



# constants

my $WIN32_FILTER =
	# FILE_NOTIFY_CHANGE_ATTRIBUTES |  # Any attribute change
	FILE_NOTIFY_CHANGE_DIR_NAME   	|  # Any directory name change
	FILE_NOTIFY_CHANGE_FILE_NAME  	|  # Any file name change (creating/deleting/renaming)
	FILE_NOTIFY_CHANGE_LAST_WRITE 	|  # Any change to a file's last write time
	# FILE_NOTIFY_CHANGE_SECURITY   |  # Any security descriptor change
	#=FILE_NOTIFY_CHANGE_SIZE   	|  # Any file size changed
	0;

# vars

my $thread;
my $the_callback;
my $running:shared = 0;
my $started:shared = 0;
my $stopping:shared = 0;
my $pause:shared = 0;			# command
my $paused:shared = 0;			# state

my $PAUSE_TIMEOUT = 2;


#--------------------------------------
# API
#--------------------------------------

sub monitorStarted
{
	return $running && $started;
}


sub monitorInit
{
	my ($callback) = @_;
	display($dbg_mon,0,"monitorInit()");
	return !error("callback not specified")
		if !$callback;
	$the_callback = $callback,
	return monitorStart();
}


sub monitorStart
{
	display($dbg_mon,0,"monitor::start()");
	return !error("already running")
		if $running;

	$running = 1;
	$started = 0;
	$stopping = 0;
	$paused = 0;

	# if (!$thread)
	{
		display($dbg_mon,0,"starting thread");
		$thread = threads->create(\&run);
		$thread->detach();
		display($dbg_mon,0,"thread started");
	}

	display($dbg_mon,0,"monitor::start() returning");
	return 1;
}


sub monitorStop
{
	display($dbg_mon,0,"monitor::stop()");
	return error("monitor not running")
		if !$running;
	$stopping = 1;
	while ($running)
	{
		display($dbg_mon,0,"waiting for monitor thread to stop ...");
		sleep(0.2);
	}
	display($dbg_thread,0,"monitor stopped()");
}


sub monitorPause
{
	my ($p) = @_;
	display($dbg_pause,0,"monitorPause($p)");
	if ($p)
	{
		if (!$paused)
		{
			$pause = $p;
			my $start = time();
			while (!$paused && time() < $start + $PAUSE_TIMEOUT)
			{
				display($dbg_pause+1,1,"waiting for monitor paused");
				sleep(0.1);
			}
			error("timeout waiting for monitor pause") if !$paused;
		}
		else
		{
			warning($dbg_pause,0,"monitor already paused");
		}
		return $paused;
	}
	$pause = 0;
	$paused = 0;
	return 1;
}



#------------------------------------------------------
# run()
#------------------------------------------------------

sub run
{
	display($dbg_thread,0,"monitor::run()");

	my $monitors = [];
	my $monitor_groups = [];
	push @$monitor_groups,$monitors;
	my $repo_list = getRepoList();

	if ($DELAY_MONITOR_STARTUP)		# to see startup before any events occur
	{
		warning(0,0,"Delaying monitor startup by $DELAY_MONITOR_STARTUP seconds");
		sleep($DELAY_MONITOR_STARTUP);
	}

	my $rslt = 1;
	while (1)
	{
		display($dbg_thread+1,0,"thread {top}");

		if ($stopping)
		{
			display($dbg_thread,0,"thread {stopping}");
			last;
		}
		elsif ($pause)
		{
			display($dbg_thread,0,"thread {pausing}");
			$pause = 0;
			$paused = 1;
		}
		elsif ($paused)
		{
			display($dbg_thread+1,0,"thread {paused}");
			sleep($MONITOR_PAUSE_SLEEP);
		}

		#------------------------------------
		# initialization
		#------------------------------------

		elsif (!$started)
		{
			display($dbg_thread,0,"thread {starting}");
			&$the_callback({ status =>"starting" });

			my $num = 0;
			my $group = 0;
			for my $repo (@$repo_list)
			{
				if ($num == $MAXIMUM_WAIT_OBJECTS)
				{
					$num = 0;
					$group++;
					$monitors = [];
					push @$monitor_groups,$monitors;
				}

				&$the_callback({ status =>"monitor: $repo->{path}" });
				display($dbg_mon,0,"CREATE MONITOR[$group:$num] $repo->{path}");
				my $mon = Win32::ChangeNotify->new($repo->{path},1,$WIN32_FILTER);
				if (!$mon)
				{
					error("apps::gitUI::monitor::createMonitor() - Could not create monitor($group:$num) $repo->{path}");
					$rslt = undef;
					last;
				}
				push @$monitors,$mon;
				$num++;
			}

			for my $repo (@$repo_list)
			{
				last if !defined($rslt);
				display($dbg_mon,0,"initial call to gitChanges($repo->{path})");
				&$the_callback({ status =>"checking: $repo->{path}" });
				$rslt = gitChanges($repo);
				last if !defined($rslt);
				if ($rslt)
				{
					setCanPushPull($repo);
					&$the_callback({ repo=>$repo });
				}
			}

			last if !defined($rslt);

			$started = 1;
			display($dbg_thread,0,"thread {started}");
			&$the_callback({ status =>"started" }) ;
		}

		#------------------------------------
		# normal running
		#------------------------------------

		else
		{
			my $group = 0;
			for $monitors (@$monitor_groups)
			{
				my $ready = Win32::ChangeNotify::wait_any(@$monitors,$MONITOR_WAIT);
				if (!defined($ready))
				{
					error("Error in Win32::ChangeNotify() group($group): $^E");
					$rslt = undef;
					last;
				}
				if ($ready)
				{
					$monitors->[$ready-1]->reset();
					my $num = $group * $MAXIMUM_WAIT_OBJECTS + $ready-1;
					my $repo = $repo_list->[$num];
					display($dbg_cb,0,"win_notify[$group:".($ready-1)."] $repo->{path}");

					$rslt = gitChanges($repo);
					display($dbg_cb,1,"gitChanges="._def($rslt));

					last if !defined($rslt);
					if ($rslt)
					{
						setCanPushPull($repo);
						&$the_callback({ repo=>$repo });
					}
				}	# a monitor is reaady

				$group++;

			}	# for each monitor_group

			last if !defined($rslt);

		}	# normal running
	}	# while 1

	if (!$stopping)
	{
		error("MONITOR STOPPED  DUE TO ERROR!!");
		&$the_callback({ status =>"MONITOR STOPPED DUE TO ERROR!!" });
	}
	else
	{
		display($dbg_thread,0,"thread {stopped}");
	}

	$monitors = undef;
	$monitor_groups = [];
	$running = 0;
	$started = 0;
	$stopping = 0;
	$paused = 0;

	# program used to crash if thread exits
    #
	# while (0)
	# {
	# 	warning($dbg_thread,0,"STOPPED MONITOR DUE TO ERROR!!");
	# 	sleep(10)
	# }

	display($dbg_thread,0,"thread {exiting}");

}	# monitor::run()





1;
