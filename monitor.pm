#-----------------------------------------------
# Monitor all repo paths for changes
#-----------------------------------------------
# Uses a thread to watch for changes to repos.
# Notifies via a callback with the $repo that has changed.
# In general, the thread can be started (if not already running),
# paused, and stopped.
#
#    ** note .. we probably need a way for the client to tell
#    the monitor that IT modified one or more repos to prevent
#    supeflous callbacks.
#
# Assumes someone else has parsed the repo().
# Calls gitChanges() on each repo during thread initialization.
#
# uses Win32::ChangeNotify to monitor changes to all repo directories.
# For any directory that has changed, it calls gitChanges() on that
# directory, and if gitChanges() reports that the CHANGES have CHANGED,
# calls the user callback.
#
# Win32::ChangeNotify() can register on a flat folder, or a folder tree,
# including subfolders.  An issue arises if a repo has subfolders that are,
# in fact, separate repos. If we wer to register on the folder tree for
# the outer level repo (i.e. /base), then we would receive notifications
# for the outer level repo when any files in the inner repo (i.e. /base/apps/gitUI)
# changed, and there is no good way to combine the two events and make
# the distinction.
#
# SO, this scheme requires knowledge about repos that contain other repos.
# It gets this info by reading the .gitignore files that it (may) find in
# a repo's (main) path.  If the file contains an ignore of the form
#
#                     blah**
#
# this object assumes that means that the repo contains sub repos, and
# instead of registering on the folder tree for the outer path, we
# register on the flat folder, and then register explicitly on any
# subtrees that are NOT excluded by RE's like the one above.
#
# So, the /base repo actually registers FLAT for the /base directory,
# but then makes separate TREE registrations for the subfolders that
# are NOT separate repos ... /base/bat, /base/MyMS, /base/MyVPN, and
# /base/MyWX, in such a way that when noficiations are received for
# those subfolders we map them back to /base and generate our 'event'
# on that.
#
# The (probable) main downside to using Win32::ChangeNotify is that
# it *may* "lock" the directories against renaming or moving, and
# will fail if directores ARE moved or renamed. However, it is assumed
# that the worst case, in either scheme, is that the UI program has
# some way of turning everything off, removing the cache, retarting.
#
# Those are details yet to be implemented.


package apps::gitUI::monitor;
use strict;
use warnings;
use threads;
use threads::shared;
use Win32::ChangeNotify;
use Time::HiRes qw(sleep);
use apps::gitUI::repos;
use Pub::Utils;

my $dbg_mon = -1;
my $dbg_win32 = 0;


# constants

my $CHECK_CHANGES_ON_INIT = 1;
	# will call gitChanges() on each repo during initCache()

my $WIN32_FILTER =
	# FILE_NOTIFY_CHANGE_ATTRIBUTES |  # Any attribute change
	FILE_NOTIFY_CHANGE_DIR_NAME   	|  # Any directory name change
	FILE_NOTIFY_CHANGE_FILE_NAME  	|  # Any file name change (creating/deleting/renaming)
	FILE_NOTIFY_CHANGE_LAST_WRITE 	|  # Any change to a file's last write time
	# FILE_NOTIFY_CHANGE_SECURITY   |  # Any security descriptor change
	# FILE_NOTIFY_CHANGE_SIZE   	|  # Any file size changed
	0;

# vars

my $thread;
my $the_callback;
my @monitors;	# if $USE_WIN32_NOTIFY


#------------------------------------------------------
# Win32::ChangeNotify stuff
#------------------------------------------------------

sub parseGitIgnore
{
	my ($path) = @_;
	my $retval = [];
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
			push @$retval,$re
		}
	}
	return $retval;
}


sub createMonitor
{
	my ($path,$report_path) = @_;

	$report_path ||= $path;

	my $include_subfolders = 1;
	my $exclude_subdirs =  parseGitIgnore($path);
	if (@$exclude_subdirs)
	{
		$include_subfolders = 0;
		display($dbg_win32,0,"EXCLUDE SUBDIRS on path($path)");
		return 0 if !createSubMonitors($path,$exclude_subdirs);
	}

    my $monitor = Win32::ChangeNotify->new($path,$include_subfolders,$WIN32_FILTER);
    if (!$monitor)
    {
        error("apps::gitUI::monitor::creeateMonitor() - Could not create monitor($path)");
        return 0;
    }
	push @monitors,{ path => $report_path, mon => $monitor };
	return 1;
}



sub createSubMonitors
{
	my ($path,$exclude_subdirs) = @_;

	return !error("createSubMonitors() not opendir $path")
		if !opendir(DIR,$path);

    while (my $entry=readdir(DIR))
    {
        next if $entry =~ /^(\.|\.\.)$/;
		next if $entry =~/^\.git$/;
			# don't include .git itself
		my $sub_path = "$path/$entry";
		my $is_dir = -d $sub_path ? 1 : 0;
		if ($is_dir)
		{
			my $skipit = 0;
			for my $exclude (@$exclude_subdirs)
			{
				if ($entry =~ /^$exclude$/)
				{
					$skipit = 1;
					last;
				}
			}

			if ($skipit)
			{
				display($dbg_win32,0,"skipping subdir $entry");
			}
			else
			{
				display($dbg_win32,0,"CREATING SUB_MONITOR $entry");
				if (!createMonitor($sub_path,$path))
				{
					closedir DIR;
					return 0;
				}
			}
		}
	}

	closedir DIR;
	return 1;
}



sub startWin32
{
	display($dbg_win32,0,"startWin32()");
 	my $repo_list = getRepoList();
	return if !$repo_list;
	for my $repo (@$repo_list)
	{
		return if !createMonitor($repo->{path});
	}
	return 1;
}


sub endWin32
{
	display($dbg_win32,0,"endWin32()");
	for my $m (@monitors)
	{
		$m->{mon}->close();
	}
	@monitors = ();
}



sub run
{
	my ($this) = @_;
	$this->{running} = 1;
	display($dbg_mon,0,"thread running");

	my $rslt = 1;
	while ($this->{running} && !$this->{stopping})
	{
		display($dbg_mon+2,0,"thread top");

		if (!$this->{started})		# ==> $CHECK_CHANGES_ON_INIT
		{
			my $repo_list = getRepoList();
			for my $repo (@$repo_list)
			{
				display($dbg_mon,0,"CHECK_CHANGES_ON_INIT($repo->{path})");
				$rslt = $repo->gitChanges();
				last if !defined($rslt);
			}
			$this->{started} = 1;
		}
		elsif (!$this->{paused})
		{
			my $repo_hash = getRepoHash();
			for my $m (@monitors)
			{
				my $rslt = $m->{mon}->wait(0);
				if (defined($rslt) && $rslt>0)
				{
					$m->{mon}->reset();
					my $path = $m->{path};
					my $repo = $repo_hash->{$path};

					display($dbg_win32,0,"win_notify($path)");
					if (!$repo)
					{
						error("Could not get $repo($path)");
						$rslt = undef;
						last;
					}

					$rslt = $repo->gitChanges();
					last if !defined($rslt);
					&$the_callback($repo) if $rslt;
				}
			}
		}

		last if !defined($rslt);
		sleep(0.2);
	}

	warning($dbg_mon,0,"Existing thread due to error")
		if !defined($rslt);
	$this->{running} = 0;
	display($dbg_mon,0,"thread stopped");
}





sub new
{
	my ($class,$callback) = @_;
	display($dbg_mon,0,"new()");
	return !error("callback not specified")
		if !$callback;
	$the_callback = $callback,
	my $this = shared_clone({
		started => !$CHECK_CHANGES_ON_INIT,
		running => 0,
		stopping => 0,
		paused => 0 });
	bless $this,$class;
	return if !startWin32();
	return $this;
}



sub start
{
	my ($this) = @_;
	return !error("already running")
		if $this->{running};
	$this->{running} = 0;
	$this->{stopping} = 0;
	$this->{paused} = 0;

	display($dbg_mon,0,"starting thread");
	$thread = threads->create(\&run,$this);
	$thread->detach();
	display($dbg_mon,0,"thread started");
	return 1;
}


sub stop
{
	my ($this) = @_;
	display($dbg_mon,0,"stop()");
	$this->{stopping} = 1;
	endWin32();
	while ($this->{running})
	{
		display($dbg_mon,0,"waiting for thread to stop ...");
		sleep(1);
	}
	$thread = undef;
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
