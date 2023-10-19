#-----------------------------------------------
# monitor all repo paths for changes
#-----------------------------------------------
# Calls a single callback with the $path that changed.
# The problem of eliminating nested $paths is thorny.
# For leaf nodes we want to create the monitor with
#      1 for the $subfolders parameter to ChangeNotify->new()
# For containers we would need to use $subfolders=0, and then
#      register additional monitors for any subdirectories that
#      are NOT containers. Perhaps .gitignore can help with that.
# For now I am going to test with $subfolers = 0;

# NOTE CHANGE TO
#
#    C:\Program Files (x86)\ActiveState Komodo Edit 8\lib\mozilla\components\koPerlCompileLinter.py
#
# Komodo was creating tmp files in Perl directories for syntax checking.
# I modified Komodo to open create the Perl tmp files in the User/AppData/Local/Temp
# directory by adding the following around line 328 in the above file
#
#	 cwd = "{USERPROFILE}/AppData/Local/Temp/".format(**os.environ)
#

# ISSUE WITH USING .gitignore
#
# 		in git, theee can be placed anywhere
# 		in this system, I only look at the main repo direcotry
#
# EXCLUDED SUBDIRECTORIES MUST BE MARKED WITH
#
#      MBE**
#
# Where MBE is the name of a sub-project, and ** means git
# will ignore everything starting with that.



package apps::gitUI::monitor;
use strict;
use warnings;
use threads;
use threads::shared;
use Win32::ChangeNotify;
use Time::HiRes qw(sleep);
use apps::gitUI::repos;
use Pub::Utils;

my $dbg_mon = 0;

my $filter =
	# FILE_NOTIFY_CHANGE_ATTRIBUTES |  # Any attribute change
	FILE_NOTIFY_CHANGE_DIR_NAME   |  # Any directory name change
	FILE_NOTIFY_CHANGE_FILE_NAME  |  # Any file name change (creating/deleting/renaming)
	FILE_NOTIFY_CHANGE_LAST_WRITE |  # Any change to a file's last write time
	# FILE_NOTIFY_CHANGE_SECURITY   |  # Any security descriptor change
	# FILE_NOTIFY_CHANGE_SIZE ;        # Any file size changed



my @monitors;
my $thread;




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




sub allRepos
{
    my ($class,$callback) = @_;

    my $this = {};
    bless $this,$class;
	$this->{callback} = $callback;
	my $repo_list = getRepoList();
	return if !$repo_list;
	for my $repo (@$repo_list)
	{
		return if !createMonitor($repo->{path});
	}

	$thread = threads->create(\&run,$this);
	$thread->detach();
    return $this;
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
		display($dbg_mon,0,"EXCLUDE SUBDIRS on path($path)");
		return 0 if !createSubMonitors($path,$exclude_subdirs);
	}

    my $monitor = Win32::ChangeNotify->new($path,$include_subfolders,$filter);
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

	return error("createSubMonitors() not opendir $path")
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
				display($dbg_mon,0,"skipping subdir $entry");
			}
			else
			{
				display($dbg_mon,0,"CREATING SUB_MONITOR $entry");
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



sub run
{
    my ($this) = @_;
    display($dbg_mon,1,"apps::gitUI::monitor::run() starting");

	# wait()
	#
	# Waits for $obj to become signalled. $timeout is the maximum time to wait (in milliseconds).
	# If $timeout is omitted or undef, waits forever. If $timeout is 0, returns immediately.
	#
	# Returns:
	# +1    The object is signalled
	# -1    The object is an abandoned mutex
	# 0    Timed out
	# undef  An error occurred (check C<$^E> for details)

    while (1)
    {
		for my $m (@monitors)
		{
			my $rslt = $m->{mon}->wait(0);
			if (defined($rslt) && $rslt>0)
			{
				$m->{mon}->reset();
				&{$this->{callback}}($m->{path});
			}
		}
		sleep(1);
    }
}





#-----------------------------------------------------------------
# test main
#-----------------------------------------------------------------

my $change_num:shared = 0;

sub test_callback
{
	my ($path) = @_;
	$change_num++;
	print "CHANGED($change_num) $path\n";
}



if (1)
{
	if (parseRepos())
	{
		if (apps::gitUI::monitor->allRepos(\&test_callback))
		{
			while (1)
			{
				sleep(1);
			}
		}
	}
}


1;
