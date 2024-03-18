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
	my (@pref_excludes) = @_;
	my $excludes = [];
	my $run_as_admin = Win32::IsAdminUser() ? 1 : 0;
	repoDisplay($dbg_opts,-2,"USER($user_name) RUN_AS_ADMIN($run_as_admin)");

	push @$excludes,@$admin_excludes;
	push @$excludes,@$user_excludes
		if !$run_as_admin;
	push @$excludes,@pref_excludes
		if @pref_excludes;
	push @$excludes,@$opt_excludes
		if getPref('GIT_UNTRACKED_USE_OPT_SYSTEM_EXCLUDES');

	for my $exclude (@$excludes)
	{
		$exclude =~ s/\//\\\//g;
		$exclude = "^$exclude";
	}
	for my $exclude (@$excludes)
	{
		repoDisplay($dbg_excludes,0,"exclude=$exclude");
	}

	return $excludes;
}




sub excludeDir
{
	my ($dir,$excludes) = @_;
	for my $re (@$excludes)
	{
		return 1 if $dir =~/$re/;
	}
	return 0;
}




sub findUntrackedRepos
	# recurse through the directory tree and
	# add or update folders and tracks
{
	my ($dir,$untracked,$excludes) = @_;

	my $level_0 = 0;
	if (!$untracked)
	{
		$level_0 = 1;
		$dir = '/';
		$untracked = {};
		$excludes = [];

		repoDisplay(0,-1,"findUntrackedRepos()");
		repoDisplay($dbg_opts,-2,'GIT_UNTRACKED_USE_CACHE => '.getPref('GIT_UNTRACKED_USE_CACHE'));
		repoDisplay($dbg_opts,-2,'GIT_UNTRACKED_SHOW_TRACKED_REPOS => '.getPref('GIT_UNTRACKED_SHOW_TRACKED_REPOS'));
		repoDisplay($dbg_opts,-2,'GIT_UNTRACKED_SHOW_DIR_WARNINGS => '.getPref('GIT_UNTRACKED_SHOW_DIR_WARNINGS'));
		repoDisplay($dbg_opts,-2,'GIT_UNTRACKED_USE_SYSTEM_EXCLUDES => '.getPref('GIT_UNTRACKED_USE_SYSTEM_EXCLUDES'));
		repoDisplay($dbg_opts,-2,'GIT_UNTRACKED_USE_OPT_SYSTEM_EXCLUDES => '.getPref('GIT_UNTRACKED_USE_OPT_SYSTEM_EXCLUDES'));
		repoDisplay($dbg_opts,-2,'GIT_UNTRACKED_COLLAPSE_COPIES => '.getPref('GIT_UNTRACKED_COLLAPSE_COPIES'));

		if (getPref('GIT_UNTRACKED_USE_CACHE') &&
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

		my @pref_excludes = getSequencedPref('GIT_UNTRACKED_EXCLUDES');
		if (@pref_excludes)
		{
			repoDisplay($dbg_opts,-2,'GIT_UNTRACKED_EXCLUDES');
			for my $pref_exclude (@pref_excludes)
			{
				repoDisplay($dbg_opts,-3,$pref_exclude);
			}
		}

		$excludes = buildExcludes(@pref_excludes) if
			@pref_excludes ||
			getPref('GIT_UNTRACKED_USE_SYSTEM_EXCLUDES');
	}

	repoDisplay($dbg_scan,0,"dir=$dir");

	my $dirh;
    my @subdirs;
    if (!opendir($dirh,$dir))
    {
        repoWarning(undef,0,-1,"Could not opendir $dir")
			if getPref('GIT_UNTRACKED_SHOW_DIR_WARNINGS');
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
				if getPref('GIT_UNTRACKED_COLLAPSE_COPIES');
			my $repo = getRepoByPath($use_dir);
			if (!$repo)
			{
				my $already = $untracked->{$use_dir};
				$untracked->{$use_dir} = 1;
				repoDisplay(0,-1,"UNTRACKED REPO: $use_dir") if !$already;
			}
			elsif (getPref('GIT_UNTRACKED_SHOW_TRACKED_REPOS'))
			{
				repoDisplay(0,-1,"EXISTING REPO: $use_dir");
			}
		}
		elsif (-d $path)
        {
			if (!$excludes || !excludeDir($path,$excludes))
			{
				repoDisplay(0,-2,"scanning $path") if $level_0;
				findUntrackedRepos($path,$untracked,$excludes);
			}
		}
	}
    closedir $dirh;

	if ($level_0 && getPref('GIT_UNTRACKED_USE_CACHE'))
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





1;