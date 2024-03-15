#----------------------------------------------------
# find any repos that are not in git_repos.txt
#----------------------------------------------------

package apps::gitUI::reposUntracked;
use strict;
use warnings;
use threads;
use threads::shared;
use Win32;
use Pub::Utils;
use Pub::Prefs;
use apps::gitUI::utils;
use apps::gitUI::repo;
use apps::gitUI::repos;
use apps::gitUI::repoGit;
use apps::gitUI::reposGithub;

my $dbg_scan = 1;
my $dbg_opts = 0;
my $dbg_cache = 0;
my $dbg_excludes = 1;

my $untracked_cache_file = "$temp_dir/untrackedRepos.txt";

my $user_name = $ENV{USERNAME};


my $opt_excludes = [
	"/Users/$user_name/AppData/Local/Temp",
	"/Users/$user_name/AppData/LocalLow/Temp",
	"/Program Files",
	"/Program Files \(x86\)",
	"/Windows", ];

my $admin_excludes = [
	"/Documents and Settings",
	"/ProgramData",
	"/System Volume Information",
	"/Users/All Users",
	"/Users/Default",
	"/Users/$user_name/AppData/Local/Application Data",
	"/Users/$user_name/AppData/Local/ElevatedDiagnostics",
	"/Users/$user_name/AppData/Local/History",
	"/Users/$user_name/AppData/Local/Microsoft/Windows/INetCache/Content.IE5",
	"/Users/$user_name/AppData/Local/Microsoft/Windows/INetCache/Low/Content.IE5",
	"/Users/$user_name/AppData/Local/Microsoft/Windows/Temporary Internet Files",
	"/Users/$user_name/AppData/Local/Temporary Internet Files",
	"/Users/$user_name/Application Data",
	"/Users/$user_name/Cookies",
	"/Users/$user_name/Documents/My Music",
	"/Users/$user_name/Documents/My Pictures",
	"/Users/$user_name/Documents/My Videos",
	"/Users/$user_name/Local Settings",
	"/Users/$user_name/My Documents",
	"/Users/$user_name/NetHood",
	"/Users/$user_name/PrintHood",
	"/Users/$user_name/Recent",
	"/Users/$user_name/SendTo",
	"/Users/$user_name/Start Menu",
	"/Users/$user_name/Templates",
	"/Users/Public/Documents/My Music",
	"/Users/Public/Documents/My Pictures",
	"/Users/Public/Documents/My Videos",
 ];


my $user_excludes = [
	"/\\\$Recycle.Bin",
	"/Program Data",
	"/Recovery", ];


sub buildExcludes
{
	my ($opts) = @_;
	my $excludes = $opts->{excludes} = [];
	my $run_as_admin = Win32::IsAdminUser() ? 1 : 0;
	repoDisplay($dbg_opts,0,"USER($user_name) RUN_AS_ADMIN($run_as_admin)");

	push @$excludes,@$admin_excludes;
	push @$excludes,@$user_excludes
		if !$run_as_admin;
	push @$excludes,@{$opts->{GIT_UNTRACKED_EXCLUDES}}
		if $opts->{GIT_UNTRACKED_EXCLUDES};
	push @$excludes,@$opt_excludes
		if $opts->{GIT_UNTRACKED_USE_OPT_SYSTEM_EXCLUDES};

	for my $exclude (@$excludes)
	{
		$exclude =~ s/\//\\\//g;
		$exclude = "^$exclude";
	}
	for my $exclude (@$excludes)
	{
		repoDisplay($dbg_excludes,0,"exclude=$exclude");
	}
}




sub excludeDir
{
	my ($opts,$dir) = @_;
	for my $re (@{$opts->{excludes}})
	{
		return 1 if $dir =~/$re/;
	}
	return 0;
}




sub findUntrackedRepos
	# recurse through the directory tree and
	# add or update folders and tracks
{
	my ($opts,$dir,$untracked) = @_;
	my $level_0 = 0;
	if (!$untracked)
	{
		$level_0 = 1;
		$dir = '/';
		$untracked = {};

		display_hash($dbg_opts,-1,"findUntrackedRepos",$opts);

		if ($opts->{GIT_UNTRACKED_USE_CACHE} &&
			-f $untracked_cache_file)
		{
			my $num = 0;
			my @lines = getTextLines($untracked_cache_file);
			for my $line (@lines)
			{
				$num++;
				$untracked->{$line} = 1;
			}
			repoDisplay($dbg_cache,-1,"findUntrackedRepos() returning $num cached paths");
			return $untracked;
		}

		buildExcludes($opts) if
			$opts->{GIT_UNTRACKED_USE_SYSTEM_EXCLUDES} ||
			$opts->{GIT_UNTRACKED_EXCLUDES};
	}
	repoDisplay($dbg_scan,0,"dir=$dir");
	return if $opts->{excludes} &&
		excludeDir($opts,$dir);

	my $dirh;
    my @subdirs;
    if (!opendir($dirh,$dir))
    {
        repoWarning(undef,0,-1,"Could not opendir $dir")
			if $opts->{GIT_UNTRACKED_SHOW_DIR_WARNINGS};
        return;
    }
    while (my $entry=readdir($dirh))
    {
        next if ($entry =~ /^\.\.?$/);
        my $path = "$dir/$entry";
		$path =~ s/^\/\//\//;
		repoDisplay($dbg_scan,1,"path=$path");
		if ($entry =~ /^\.git$/)
		{
			my $use_dir = $dir;
			$use_dir =~ s/ - Copy( \(\d+\))*//
				if $opts->{GIT_UNTRACKED_COLLAPSE_COPIES};
			my $repo = getRepoByPath($use_dir);
			if (!$repo)
			{
				my $already = $untracked->{$use_dir};
				$untracked->{$use_dir} = 1;
				repoDisplay(0,-1,"UNTRACKED REPO: $use_dir") if !$already;
			}
			elsif ($opts->{GIT_UNTRACKED_SHOW_TRACKED_REPOS})
			{
				repoDisplay(0,-1,"EXISTING REPO: $use_dir");
			}
		}
		elsif (-d $path)
        {
			findUntrackedRepos($opts,$path,$untracked);
		}
	}
    closedir $dirh;

	if ($level_0 && $opts->{GIT_UNTRACKED_USE_CACHE})
	{
		my $num = 0;
		my $text = '';
		for my $path (sort keys %$untracked)
		{
			$num++;
			$text .= "$path\n";
		}
		repoDisplay($dbg_cache,-1,"findUntrackedRepos() writing $num cached paths");
		printVarToFile(1,$untracked_cache_file,$text,1);
	}


	return $untracked;
}



#----------------------------------------
# test main
#----------------------------------------


if (0)
{
	if (parseRepos())
	{
		my $my_excludes = [
			"/base_data",
			"/junk/_maybe_save",
			"/MBEBack",
			"/MBEDocs",
			"/mbeSystems",
			"/mp3s",
			"/mp3s_mini",
			"/zip/_teensy/_SdFat_unused_libraries", ];

		my $opts = {
			GIT_UNTRACKED_USE_CACHE => 0,
				# whether to use a cachefile

			GIT_UNTRACKED_SHOW_TRACKED_REPOS => 0,
				# whether to print tracked repos
			GIT_UNTRACKED_SHOW_DIR_WARNINGS => 1,
				# whether to show warnings on unreadable directories

			GIT_UNTRACKED_EXCLUDES => $my_excludes,
				# A list of root directories to exclude from the scan.

			GIT_UNTRACKED_USE_SYSTEM_EXCLUDES => 1,
				# Exclude directories from the scan, starting with
				# known system directories that cannot be opened,
				# based on $run_as_admin and the $user_name, even as admin,
				# like /ProgramData and /System Volume Information, and
				# if not run as admin, directories like /Users/All Users.
			GIT_UNTRACKED_USE_OPT_SYSTEM_EXCLUDES => 1,
				# if GIT_UNTRACKED_USE_SYSTEM_EXCLUDES, whether to exclude exclude common
				# directories that the user should not place repos in, including
				# /Windows, /Program Files, and so on.

			GIT_UNTRACKED_COLLAPSE_COPIES => 1,
				# whether to collapse BLAH - Copy dirs into
				# BLAH to ignore directories that are Copies
				# of other directories (since I often like to
				# make backup copies of my repos while working).
		};


		my $untracked = findUntrackedRepos($opts);
		my $num_untracked = scalar(keys %$untracked);
		repoDisplay(0,0,"FOUND $num_untracked untracked repos");
	}
}


1;