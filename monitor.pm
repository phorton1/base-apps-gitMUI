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
# In practice this ia efficient enough and does away with previous
# exclude and create submonitor hassles.  I am not cleaning that
# code up today, but much of this file is no longer needed.
#
# HAVE TO SEE if active processes like builds are upset by this,
# but they already have their own .git_ignores that I wasn't utilizing,
# and would have received all those notifications anyways.

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

my $USE_SUBMONITORS = 0;
	# Turned off for now, code to be removed in the future.

my $DELAY_MONITOR_STARTUP = 0;
	# Set this to number of seconds to delay monitor thread
	# actually starting, to see what happens to other threads
	# and program functions.

my $dbg_thread = 0;
	# monitor thread lifecycle
my $dbg_pause = 0;
	# debug the pause
my $dbg_mon = 1;
	# TODO: /Arduino/libraries/myIOT/data is not getting a monitor
	# monitor creation of monitors
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
my %monitors;
	# NOT SHARED, yet BUILT BY THE THREAD!

my $running:shared = 0;
my $started:shared = 0;
my $stopping:shared = 0;
my $pause:shared = 0;			# command
my $paused:shared = 0;			# state

my $PAUSE_TIMEOUT = 2;

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
# Win32::ChangeNotify stuff
#------------------------------------------------------

sub parseGitIgnore
	# find patterns like blah** and turn the
	# blah portion into an re and push it on a list
{
	my ($path) = @_;
	my $retval = '';
	my $text = getTextFile("$path/.gitignore") || '';
	my @lines = split(/\n/,$text);
	for my $line (@lines)
	{
		$line =~ s/^\s+|\s+$//g;
		if ($line =~ /^(.*)\*\*$/)
		{
			my $re = $1;
			$re =~ s/\(/\\\(/g;		# change parents to RE
			$re =~ s/\)/\\\)/g;
			$retval ||= [];
			push @$retval,$re;
			display($dbg_mon,0,"exclude='$re'");
		}
	}
	return $retval;
}


sub createMonitor
{
	my ($path,$parent) = @_;
	$parent ||= '';

	if (!$monitors{$path})
	{
		my $excludes = '';
		my $include_subfolders = 1;
		if ($parent)
		{
			display($dbg_mon,0,"CREATE SUB_MONITOR($path,$parent->{path})");
		}
		else
		{
			$excludes =  $USE_SUBMONITORS ? parseGitIgnore($path) : '';
			$include_subfolders = 0 if $excludes;
			display($dbg_mon,0,"CREATE MONITOR($path) excludes("._def($excludes).")");
		}

		my $mon = Win32::ChangeNotify->new($path,$include_subfolders,$WIN32_FILTER);
		if (!$mon)
		{
			error("apps::gitUI::monitor::createMonitor() - Could not create monitor($path)");
			return 0;
		}

		my $monitor = $monitors{$path} = {
			mon => $mon,
			path => $path,
			parent => $parent,
			excludes => $excludes,
			exists => 1};

		if ($excludes)
		{
			display($dbg_mon,0,"EXCLUDE SUBDIRS on path($path)");
			return 0 if !createSubMonitors($monitor);
		}
	}
	else
	{
		$monitors{$path}->{exists} = 1;
	}
	return 1;
}


sub createSubMonitors
{
	my ($monitor) = @_;
	my $path = $monitor->{path};
	my $excludes = $monitor->{excludes};

	return !error("createSubMonitors() not opendir $path")
		if !opendir(DIR,$path);

	# set exists=0 on all monitors
	# for delete pass at end

	for my $p (keys %monitors)
	{
		my $m = $monitors{$p};
		$m->{exists} = 0;
	}

    while (my $entry=readdir(DIR))
    {
        next if $entry =~ /^(\.|\.\.)$/;
		next if $entry =~/^\.git$/;
			# do include .git itself
		my $sub_path = "$path/$entry";
		my $is_dir = -d $sub_path ? 1 : 0;
		if ($is_dir)
		{
			my $skipit = 0;
			for my $exclude (@$excludes)
			{
				if ($entry =~ /^$exclude$/)
				{
					$skipit = 1;
					last;
				}
			}

			if ($skipit)
			{
				display($dbg_mon,0,"skipping subdir $entry");
			}
			else
			{
				if (!createMonitor($sub_path,$monitor))
				{
					closedir DIR;
					return 0;
				}
			}
		}
	}
	closedir DIR;

	# Harvest any unused monitors

	for my $p (keys %monitors)
	{
		my $m = $monitors{$p};
		my $parent = $m->{parent};
		if (($parent eq $monitor) && !$m->{exists})
		{
			display($dbg_mon,0,"DELETING UNUSED MONITOR($p");
			delete $monitors{$p}
		}
	}

	return 1;
}



sub run
	# we never actually stop the monitor due to problems with threads.
	# rather we tell it to stop and it clears the monitor list, and
	# rebuilds it on started
{
	display($dbg_thread,0,"monitor::run()");

	if ($DELAY_MONITOR_STARTUP)		# to see startup before any events occur
	{
		warning(0,0,"Delaying monitor startup by $DELAY_MONITOR_STARTUP seconds");
		sleep($DELAY_MONITOR_STARTUP);
	}

	my $rslt = 1;
	while (1)
	{
		display($dbg_thread+1,0,"thread top");

		if ($stopping)
		{
			display($dbg_thread,0,"thread {stopping}");
			%monitors = ();
			$stopping = 0;
			$running = 0;
			$started = 0;
			$paused = 0;
		}
		elsif ($running)
		{
			if (!$started)		# ==> $CHECK_CHANGES_ON_INIT
			{
				display($dbg_thread,0,"thread {starting}");
				&$the_callback({ status =>"starting" });
				my $repo_list = getRepoList();

				for my $repo (@$repo_list)
				{
					&$the_callback({ status =>"monitor: $repo->{path}" });
					$rslt = undef if !createMonitor($repo->{path});
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

				if (defined($rslt))
				{
					$started = 1;
					display($dbg_thread,0,"thread {started}");
					&$the_callback({ status =>"started" }) ;
				}
			}
			elsif ($pause)
			{
				display($dbg_thread,0,"thread {pausing}");
				$pause = 0;
				$paused = 1;
			}
			elsif (!$paused)
			{
				my $repo_hash = getRepoHash();
				for my $path (sort keys %monitors)
				{
					my $m = $monitors{$path};
					next if !$m;	# could be deleted during loop

					my $rslt = $m->{mon}->wait(0);
					if (defined($rslt) && $rslt>0)
					{
						$m->{mon}->reset();

						my $parent = $m->{parent};
						my $report_path = $parent ? $parent->{path} : $m->{path};
						my $repo = $repo_hash->{$report_path};
						display($dbg_cb,0,"win_notify($path,$report_path)");

						if (!$repo)
						{
							error("Could not get repo $repo($report_path)");
							$rslt = undef;
							last;
						}
						$rslt = gitChanges($repo);
						last if !defined($rslt);
						if ($rslt)
						{
							setCanPushPull($repo);
							&$the_callback({ repo=>$repo });
						}

						# create/remove monitors based on file system changes

						if ($m->{excludes})
						{
							$rslt = undef if !createSubMonitors($m);
							last if !$rslt;
						}

					}	# got result from monitor
				}	# for each monitor
			}	# ! paused

			if (!defined($rslt))
			{
				%monitors = ();
				$stopping = 0;
				$running = 0;
				$started = 0;
				$paused = 0;

				warning($dbg_thread,0,"STOPPING MONITOR DUE TO ERROR!!");
				&$the_callback({ status =>"STOPPING MONITOR DUE TO ERROR!!" });

				sleep(10)
			}

		}	# running

		sleep(defined($rslt)?0.2:10);
	}

	display($dbg_mon,0,"thread exited abnormally!!");
}



#--------------------------------------
# API
#--------------------------------------


sub monitorStarted
{
	return $started;
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

	$started = 0;
	$stopping = 0;
	$paused = 0;

	if (!$thread)
	{
		display($dbg_mon,0,"starting thread");
		$thread = threads->create(\&run);
		$thread->detach();
		display($dbg_mon,0,"thread started");
	}

	$running = 1;
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



#---------------------------------------------
# test main
#---------------------------------------------

if (0)
{
	my $chg_num:shared = 0;
	sub callback
	{
		my ($repo) = @_;
		$chg_num++;
		print "CHANGE($chg_num) $repo->{path}\n";
	}

	if (parseRepos())
	{
		my $mon = apps::gitUI::monitor->new(\&callback);
		if ($mon)
		{
			if ($mon->start())
			{
				while (1)
				{
					sleep(1);
				}
			}
		}
	}
}



1;
