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
# Assumes someone else has parsed the repo() and possibly
#    called gitChanges() on each repo.
#
# There are two basic schemes in play, based on $USE_WIN32_NOTIFY.
#
# $USE_WIN32_NOTIFY == 0 uses a 'pure' datetime checking algorithm,
# 	with a cache file, and the notion of a number of 'recent' repos
#   that should be always be checked with gitChanges(), to provide
#   a 'pretty good' solution to the problem.
#
# 	The files with timestamps that are checked are as follows:
#
#		/.git/index - change indicates a change to/from {staged_changes}
#		/.git/refs/heads/$branch - change indicates a "commit" was performed
#		/.git/remotes/origin/$branch indicates a "push" was performed
#
#   The timestamps on these files tell us everything we need to know
#   	EXCEPT for identifying {unstaged_changes}.
#
#   The cache file keeps a list of the most recent timestamp for each
#       repository path.  In memory, the cache also keeps track of the
#       number of unstaged, staged, and remote changes for each repo
#       since the monitor object was created.
#
#   In the thread, we sort the cache by the most recent timestamp first,
#       and for the most recent $NUM_RECENT_REPOS we call gitChanges().
#       For the rest of the repositories we check the datetime stamps
#       and if they have changed, then we call gitChanges().
#
#       When we call gitChanges(), we compare the number of unstaged,
#       staged, and remote changes from the cache to the repo, and if
#       any of them has changed, we trigger the callback.
#
#       Overall, for each time through the loop, if we made any callbacks
#       (any repos changed), then we also write the cache out to disk
#       for subsequent use.
#
#	The main problem with this approach is that we cannot detect
#   unstaged changes to any but the top $NUM_RECENT_REPOS, with the
#   idea that the user will notice that changes are missing, and
#   run a full change scan at that point. ** note, once again, that
#   there needs to be a way for the UI to notify this object about
#   changes it already knows about to prevent superfluous callbacks.
#
#   Another problem with this approach is that it still takes a significant
#   amount of time, and cpu cycles, to get 91*3 timestamps and call gitChanges()
# 	on 10 repos over and over until the cows come home.
#
# $USE_WIN32_NOTIFY == 1 attempts to solve the these two problems
#	by monitoring all repo directories for changes using Win32::ChangeNotify,
#   and using that to update the timestamps and call gitChanges(), rather
#   than looping through all 90+ repos to check timestamps and calling gitChanges
#   on the top 10 repos, for every loop in the thread.
#
#   It still uses the cache for comparing change hashes, and writes it
#   if any changes are found, but it does not CHECK all timestamps.
#
#   Win32::ChangeNotify() can register on a flat folder, or a folder tree,
#   including subfolders.  An issue arises if a repo has subfolders that are,
#   in fact, separate repos. If we wer to register on the folder tree for
#   the outer level repo (i.e. /base), then we would receive notifications
#   for the outer level repo when any files in the inner repo (i.e. /base/apps/gitUI)
#   changed, and there is no good way to combine the two events and make
#   the distinction.
#
#   SO, this scheme requires knowledge about repos that contain other repos.
#   It gets this info by reading the .gitignore files that it (may) find in
#   a repo's (main) path.  If the file contains an ignore of the form
#
#                       blah**
#
#   this object assumes that means that the repo contains sub repos, and
#   instead of registering on the folder tree for the outer path, we
#   register on the flat folder, and then register explicitly on any
#   subtrees that are NOT excluded by RE's like the one above.
#
#   So, the /base repo actually registers FLAT for the /base directory,
#   but then makes separate TREE registrations for the subfolders that
#   are NOT separate repos ... /base/bat, /base/MyMS, /base/MyVPN, and
#   /base/MyWX, in such a way that when noficiations are received for
#   those subfolders we map them back to /base and generate our 'event'
#   on that.
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

# temporary for test main()

$temp_dir = "/base_data/temp/gitUI";
$data_dir = "/base_data/data/gitUI";


my $dbg_mon = -1;
my $dbg_win32 = 0;


# constants

my $USE_WIN32_NOTIFY = 1;
	# combined technology
my $CHECK_CHANGES_ON_INIT = 1;
	# will call gitChanges() on each repo during initCache()


my $NUM_RECENT_REPOS = 10;
my $DT_CACHEFILE = "$temp_dir/repoTimestamps.txt";
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
my $cache:shared = shared_clone({});

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
		# next if $entry =~/^\.git$/;
			# do include .git itself
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


sub checkReposWin32
	# loops through monitors looking for any that
	# have been notified about directory changes.
	# gets timestamp
	# call checkRepo() on first $NUM_RECENT_REPOS or if ts changes.
	# 	which does the callback
	# returns 1 if cache file needs writing, 0 if not
	# returns undef on any errors
{
	my ($this) = @_;
	my $needs_write = 0;
	for my $m (@monitors)
	{
		my $rslt = $m->{mon}->wait(0);
		if (defined($rslt) && $rslt>0)
		{
			$m->{mon}->reset();
			my $path = $m->{path};

			display($dbg_win32,0,"win_notify($path)");
			my $entry = $cache->{$path};
			if (!$entry)
			{
				error("Could not get entry($path)");
				return undef;
			}
			my $repo = $entry->{repo};
			my $cur_ts = $entry->{ts};
			my $new_ts = getMostRecentTimestamp($repo);
			if ($new_ts gt $cur_ts)
			{
				$entry->{ts} = $new_ts;
				$needs_write = 1;
			}

			my $rslt = checkRepo($entry,$repo);
			return if !defined($rslt);
		}
	}
	return $needs_write;
}


#-------------------------------------------------------
# Timestamp based stuff (also used for win32)
#-------------------------------------------------------

sub getMostRecentTimestamp
{
	my ($repo) = @_;
	my $path = $repo->{path};
	my $branch = $repo->{branch};
	my $ts1 = getTimestamp("$path/.git/index");
	my $ts2 = getTimestamp("$path/.git/refs/head/$branch");
	my $ts3 = getTimestamp("$path/.git/remotes/origin/head/$branch");

	display($dbg_mon+2,0,"$path ts1($ts1) ts2($ts2) ts3($ts3)")
		if $path eq "/base/apps/gitUI";

	$ts1 = $ts2 if $ts2 gt $ts1;
	$ts1 = $ts3 if $ts3 gt $ts1;
	return $ts1;
}



sub cacheEntry
{
	my ($repo,$ts) = @_;
	my $entry = shared_clone({
		repo => $repo,
		ts   => $ts,
		unstaged_changes => scalar(keys %{$repo->{unstaged_changes}}),
		staged_changes => scalar(keys %{$repo->{staged_changes}}),
		remote_changes => scalar(keys %{$repo->{remote_changes}}),
	});
	return $entry;
}


sub writeCache
{
	display($dbg_mon+1,0,"writeCache()");
	return !error("Could not open $DT_CACHEFILE for writing")
		if !open(OUT,">$DT_CACHEFILE");
	for my $path (sort keys %$cache)
	{
		my $entry = $cache->{$path};
		print OUT "$path\t$entry->{ts}\n";
	}
	close(OUT);
	return 1;
}


sub readCache
{
	display($dbg_mon+1,0,"readCache()");
	my $text = getTextFile($DT_CACHEFILE);
	return !warning(0,0,"Empty $DT_CACHEFILE")
		if !$text;
	my $repo_hash = getRepoHash();
	my @lines = split("\n",$text);
	for my $line (@lines)
	{
		my ($path,$ts) = split("\t",$line);
		my $repo = $repo_hash->{$path};
		return !error("Could not get repo($path)")
			if !$repo;
		$cache->{$path} = cacheEntry($repo,$ts);
		return 0 if !$cache->{$path};
	}
	return 1;
}


sub initCache
{
	display($dbg_mon+1,0,"initCache()");
	return 1 if readCache();
	my $repo_list = getRepoList();
	for my $repo (@$repo_list)
	{
		my $path = $repo->{path};
		my $ts = getMostRecentTimestamp($repo);
		$cache->{$path} = cacheEntry($repo,$ts);
	}
	return writeCache();
}




sub checkReposTS
	# loops through cache in most-recent-first order,
	# gets timestamp
	# call checkRepo() on first $NUM_RECENT_REPOS or if ts changes.
	# 	which does the callback
	# returns 1 if cache file needs writing, 0 if not
	# returns undef on any errors
{
	my ($this) = @_;
	my $count = 0;
	my $needs_write = 0;

	for my $path (reverse sort {$cache->{$a} cmp $cache->{$b}} (keys %$cache))
	{
		my $entry = $cache->{$path};
		my $repo = $entry->{repo};
		my $cur_ts = $cache->{ts} || '';
		my $new_ts = getMostRecentTimestamp($repo);
		my $later = $new_ts > $cur_ts ? 1 : 0;
		if ($later)
		{
			$entry->{ts} = $new_ts;
			$needs_write = 1;
		}

		my $rslt = checkRepo($entry,$repo);
		return if !defined($rslt);

		display($dbg_mon+2,0,"$path cur_ts($cur_ts) new_ts($new_ts)")
			if ($path eq "/base/apps/gitUI");

		if ($later || $count < $NUM_RECENT_REPOS)
		{
			my $rslt = checkRepo($entry,$repo);
			return if !defined($rslt);
		}
		$count++;
	}
	return $needs_write;
}



#----------------------------------------------
# Combined stuff
#----------------------------------------------

sub checkChanges
	# checks if one hash in one repo has changed
{
	my ($entry,$repo,$field,$pstarted) = @_;
	my $num_entry = $entry->{$field};
	my $num_repo = scalar(keys %{$repo->{$field}});
	if ($num_entry != $num_repo)
	{
		display($dbg_mon+1,0,"CHANGED REPO($repo->{path})")
			if !$$pstarted;
		$$pstarted = 1;
		display($dbg_mon+1,1,"$field($num_repo) changed from($num_entry)");
		$entry->{$field} = $num_repo;
		return 1;
	}
	return 0;
}


sub checkRepo
	# calls gitChanges() and determines if any hash has changed.
	# returns 1 if changes and it DOES THE USER CALLBACK,
	# 0 if no changes, or undef if there is an error calling gitChanges()
{
	my ($entry,$repo) = @_;

	my $rslt = $repo->gitChanges();
	return if !defined($rslt);
	my $started = 0;
	my $repo_changed = 0;
	$repo_changed = 1 if checkChanges($entry,$repo,'unstaged_changes',\$started);
	$repo_changed = 1 if checkChanges($entry,$repo,'staged_changes',\$started);
	$repo_changed = 1 if checkChanges($entry,$repo,'remote_changes',\$started);
	&$the_callback($repo) if $repo_changed;

	return $repo_changed;
}







sub run
{
	my ($this) = @_;
	$this->{running} = 1;
	display($dbg_mon,0,"thread running");
	while ($this->{running} && !$this->{stopping})
	{
		display($dbg_mon+2,0,"thread top");

		my $rslt;
		if (!$this->{started})		# ==> $CHECK_CHANGES_ON_INIT
		{
			for my $path (sort keys %$cache)
			{
				my $entry = $cache->{$path};
				my $repo = $entry->{repo};
				display($dbg_mon,0,"CHECK_CHANGES_ON_INIT($repo->{path})");
				$rslt = $repo->gitChanges();
				last if !defined($rslt);
			}
			$this->{started} = 1;
		}
		elsif (!$this->{paused})
		{

			if ($USE_WIN32_NOTIFY)
			{
				$rslt = $this->checkReposWin32();
			}
			else
			{
				$rslt = $this->checkReposTS();
			}

		}
		if (!defined($rslt))
		{
			warning($dbg_mon,0,"Existing thread due to error");
			$this->{running} = 0;
			return;
		}
		sleep($USE_WIN32_NOTIFY ? 0.2 : 1);
	}
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

	return if !initCache();
	return if $USE_WIN32_NOTIFY && !startWin32();
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
	endWin32() if $USE_WIN32_NOTIFY;
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

my $chg_num:shared = 0;
sub callback
{
	my ($repo) = @_;
	$chg_num++;
	print "CHANGE($chg_num) $repo->{path}\n";
}



if (0)
{
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
