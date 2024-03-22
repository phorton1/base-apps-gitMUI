#----------------------------------------------------
# find any repos that have stashes
#----------------------------------------------------

use strict;
use warnings;
use threads;
use threads::shared;
use Win32::ChangeNotify;
use Pub::Utils;
use Pub::Prefs;
use apps::gitMUI::utils;
use apps::gitMUI::repo;
use apps::gitMUI::repos;
use apps::gitMUI::repoGit;
use apps::gitMUI::reposGithub;


my $WIN32_FILTER =
	# FILE_NOTIFY_CHANGE_ATTRIBUTES |  # Any attribute change
	FILE_NOTIFY_CHANGE_DIR_NAME   	|  # Any directory name change
	FILE_NOTIFY_CHANGE_FILE_NAME  	|  # Any file name change (creating/deleting/renaming)
	FILE_NOTIFY_CHANGE_LAST_WRITE 	|  # Any change to a file's last write time
	# FILE_NOTIFY_CHANGE_SECURITY   |  # Any security descriptor change
	#=FILE_NOTIFY_CHANGE_SIZE   	|  # Any file size changed
	0;


if (parseRepos())
{
	my $monitors;
	my $monitor_groups = [];

	my $repo_list = getRepoList();
	my $count = 0;
	for my $repo (@$repo_list)
	{
		if ($count % 64 == 0)
		{
			$monitors = [];
			push @$monitor_groups,$monitors;
		}

		$count++;
		my $mon = Win32::ChangeNotify->new($repo->{path},1,$WIN32_FILTER);
		push @$monitors,$mon;
		print "mon[$count]=$mon $repo->{path}\n";
	}



	while (1)
	{
		my $rslt;
		my $group =0;
		for $monitors (@$monitor_groups)
		{
			# print "group($group)\n";
			$rslt = Win32::ChangeNotify::wait_any(@$monitors,100);
			my $err = $^E;
			print "err=$err\n" if !defined($rslt);
			last if !defined($rslt);
			if ($rslt)
			{
				my $num = $group * 64 + $rslt - 1;
				my $repo = $repo_list->[$num];
				print "[$rslt] repo=$repo->{path}\n";
				$monitors->[$rslt-1]->reset();
			}
			$group++;
		}
		last if !defined($rslt);
	}
}




1;