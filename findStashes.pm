#----------------------------------------------------
# find any repos that have stashes
#----------------------------------------------------

use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Utils;
use Pub::Prefs;
use apps::gitUI::utils;
use apps::gitUI::repo;
use apps::gitUI::repos;
use apps::gitUI::repoGit;
use apps::gitUI::reposGithub;


if (parseRepos())
{
	my $repo_list = getRepoList();
	for my $repo (@$repo_list)
	{
		my $text = `git -C "$repo->{path}" stash list 2>&1` || '';
		my $exit_code = $? || 0;

		display(0,0,"repo($repo->{path}} stash=$text") if $text;
	}
}



1;