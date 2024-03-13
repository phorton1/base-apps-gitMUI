#----------------------------------------------------
# a Parser and Validator for my git repositories
#----------------------------------------------------
# the repos collection is represented as a
# - HASH by path of repos
# - a LIST in order of parsed repos
# - a set of SECTION containing a number of repos organized for display in my apps
#
# This file can parse them from the file and
# add members from local git/config files.
#
# parseRepos(1) takes an optional parameter indicating
# that it should start a UI window if it encounters
# any errors, yet this package remains usable without WX.


package apps::gitUI::repos;
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Utils;
use apps::gitUI::repo;
use apps::gitUI::utils;



my $dbg_parse = 0;
	# -1 for repos
	# -2 for lines
my $dbg_notify = 1;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		parseRepos

		getRepoList
		getRepoById
		getRepoByPath
		addRepoToSystem

		canPushRepos
		canPullRepos

		getSelectedPushRepos
		clearSelectedPushRepos
		setSelectedPushRepo
		clearSelectedPushRepo
		canPushSelectedRepos

		getSelectedPullRepos
		clearSelectedPullRepos
		setSelectedPullRepo
		clearSelectedPullRepo
		canPullSelectedRepos

		getSelectedCommitParentRepos
		clearSelectedCommitParentRepos
		setSelectedCommitParentRepo
		clearSelectedCommitParentRepo

		setCanPushPull

		groupReposBySection
	);
}

my $repo_filename = '/base/bat/git_repositories.txt';

my $repo_list:shared;
my $repos_by_path:shared;
my $repos_by_id:shared;

my $repos_can_push:shared;
my $repos_can_pull:shared;
my $repos_do_push:shared;
my $repos_do_pull:shared;
my $repos_commit_parent:shared;


sub initParse
{
	$repo_list = shared_clone([]);
	$repos_by_path = shared_clone({});
	$repos_by_id = shared_clone({});

	$repos_can_push = shared_clone({});
	$repos_can_pull = shared_clone({});
	$repos_do_push = shared_clone({});
	$repos_do_pull = shared_clone({});
	$repos_commit_parent = shared_clone({});
}

initParse();


#----------------------------------
# accessors
#----------------------------------

sub getRepoList
{
	return $repo_list;
}

sub getRepoByPath
{
	my ($path) = @_;
	return $repos_by_path->{$path};
}

sub getRepoById
{
	my ($id) = @_;
	return $repos_by_id->{$id};
}


sub addRepoToSystem
{
	my ($repo,$id) = @_;
	push @$repo_list,$repo;
	$repos_by_path->{$repo->{path}} = $repo
		if $repo->{path};
	$repos_by_id->{$id} = $repo if $id;
}



sub canPushRepos
{
	return scalar(keys %$repos_can_push);
}
sub canPullRepos
{
	return scalar(keys %$repos_can_pull);
}



sub getSelectedPushRepos
{
	return $repos_do_push;
}
sub clearSelectedPushRepos
{
	$repos_do_push = shared_clone({});
}
sub setSelectedPushRepo
{
	my ($repo) = @_;
	$repos_do_push->{$repo->{path}} = $repo;
}
sub clearSelectedPushRepo
{
	my ($repo) = @_;
	delete $repos_do_push->{$repo->{path}};
}
sub canPushSelectedRepos
{
	return scalar(keys %$repos_do_push);
}



sub getSelectedPullRepos
{
	return $repos_do_pull;
}
sub clearSelectedPullRepos
{
	$repos_do_pull = shared_clone({});
}
sub setSelectedPullRepo
{
	my ($repo) = @_;
	$repos_do_pull->{$repo->{path}} = $repo;
}
sub clearSelectedPullRepo
{
	my ($repo) = @_;
	delete $repos_do_pull->{$repo->{path}};
}
sub canPullSelectedRepos
{
	return scalar(keys %$repos_do_pull);
}


sub getSelectedCommitParentRepos
{
	return $repos_commit_parent;
}
sub clearSelectedCommitParentRepos
{
	$repos_commit_parent = shared_clone({});
}
sub setSelectedCommitParentRepo
{
	my ($repo) = @_;
	$repos_commit_parent->{$repo->{path}} = $repo;
}
sub clearSelectedCommitParentRepo
{
	my ($repo) = @_;
	delete $repos_commit_parent->{$repo->{path}};
}


sub setCanPushPull
{
	my ($repo) = @_;
	return if !$repo->isLocalAndRemote();
		# TODO: I don't think this handles localOnly commitParent
	display($dbg_notify,0,"setCanPushPull($repo->{path})");
	$repo->canPush() ?
		$repos_can_push->{$repo->{path}} = 1 :
		delete $repos_can_push->{$repo->{path}};
	$repo->canPull() ?
		$repos_can_pull->{$repo->{path}} = 1 :
		delete $repos_can_pull->{$repo->{path}};
	$repo->setCanCommitParent() if $repo->{parent};

	my $submodules = $repo->{submodules};
	if ($submodules)
	{
		for my $path (@$submodules)
		{
			my $sub = getRepoByPath($path);
			$sub->setCanCommitParent();
		}
	}
}


#------------------------------------------
# parseRepos
#------------------------------------------

sub parseRepos
{
    repoDisplay($dbg_parse,0,"parseRepos($repo_filename)");

	initParse();

	my $text = getTextFile($repo_filename);
    if ($text)
    {
		my $repo_num = 0;

		my $repo;
		my $section_path = '';
		my $section_id = '';

        for my $line (split(/\n/,$text))
        {
			$line =~ s/#.*$//;
			$line =~ s/^\s+//;
			$line =~ s/\s+$//;

			if ($line =~ /SUBMODULE\t(.*)\t(.*)$/)
			{
				my ($rel_path,$sub_path) = ($1,$2);
				my $path = makePath($repo->{path},$rel_path);
				repoWarning(undef,$dbg_parse+1,1,"SUBMODULE($repo_num, $repo->{path}) = $rel_path ==> $sub_path");
				my $sub_module = apps::gitUI::repo->new(
					$REPO_LOCAL,
					$repo_num++,
					$path,
					$section_path,
					$section_id,
					$repo,
					$rel_path,
					$sub_path);
				addRepoToSystem($sub_module,'');
			}

			# get section path RE and optional name if different
			# SECTION and path-branch delimiter is TAB!!

			elsif ($line =~ /^SECTION\t/i)
			{
				my @parts = split(/\t/,$line);
				$section_path = $parts[1];
				$section_path =~ s/^\s+|\s+$//g;
				$section_id = $parts[2] || '';
			}

			# Repos start with a forward slash

			elsif ($line =~ /^\//)
			{
				repoDisplay($dbg_parse+1,1,"repo($repo_num,$line,$section_path,$section_id)");
				$repo = apps::gitUI::repo->new($REPO_LOCAL,$repo_num++,$line,$section_path,$section_id);
				addRepoToSystem($repo,$repo->{id});
			}
			elsif ($repo)
			{
				# set PRIVATE bit

				if ($line =~ /^PRIVATE$/i)
				{
					repoDisplay($dbg_parse+2,2,"PRIVATE");
					$repo->{private} = 1;
				}

				# set FORKED = 1 or whatever follows

				elsif ($line =~ s/^FORKED\s*//i)
				{
					$line ||= 1;
					repoDisplay($dbg_parse+2,2,"FORKED $line");
					$repo->{forked} = $line;
					$repo->{mine} = '';
				}
				elsif ($line =~ /^MINE/i)
				{
					repoDisplay($dbg_parse+2,2,"MINE");
					$repo->{mine} = 1;
				}
				elsif ($line =~ /^NOT_MINE/i)
				{
					repoDisplay($dbg_parse+2,2,"NOT_MINE");
					$repo->{mine} = '';
				}
				elsif ($line =~ /^PAGE_HEADER/i)
				{
					repoDisplay($dbg_parse+2,2,"PAGE_HEADER");
					$repo->{page_header} = 1;
				}

				# arrayed things with error checking
				# DOCS and NEEDS cannot have any spaces in them
				# but may have trailing data

				elsif ($line =~ s/^(DOCS)\s+//i)
				{
					my $what = $1;
					repoDisplay($dbg_parse+2,2,"$what $line");
					$repo->{lc($what)} ||= shared_clone([]);
					push @{$repo->{lc($what)}},$line;

					my ($root) = split(/\s+/,$line);
					my $path = $repo->{path}.$root;
					$repo->repoError("$what $root does not exist")
						if !(-f $path);
				}
				elsif ($line =~ s/^(NEEDS)\s+//i)
				{
					my $what = $1;
					repoDisplay($dbg_parse+2,2,"$what $line");
					$repo->{lc($what)} ||= shared_clone([]);
					push @{$repo->{lc($what)}},$line;
					my ($path) = split(/\s+/,$line);
					$repo->repoError("$what $path does not exist")
						if !(-d $path);
				}

				# unchecked (here) arrayed things

				elsif ($line =~ s/^(USES|GROUP|FRIEND|NOTES|WARNINGS|ERRORS)\s+//i)
				{
					my $what = $1;
					repoDisplay($dbg_parse+2,2,"$what $line");
					$repo->{lc($what)} ||= shared_clone([]);
					push @{$repo->{lc($what)}},$line;
				}
			}
		}
    }
    else
    {
        error("Could not open $repo_filename");
        return;
    }

	# Call gitStart() to set head, master, and remote id's
	# Set used_by list from USES modules
	# For submodules, set
	#		{submodules} list of paths on parent
	#		{used_in} list of paths on master module

	for my $repo (@$repo_list)
	{
		apps::gitUI::repoGit::gitStart($repo);

		my $uses = $repo->{uses};
		if ($uses)
		{
			for my $use (@$uses)
			{
				my $used_repo = $repos_by_path->{$use};
				if (!$used_repo)
				{
					$repo->repoError("invalid USES: $use");
				}
				else
				{
					$used_repo->{used_by} ||= shared_clone([]);
					push @{$used_repo->{used_by}},$repo->{path};
				}
			}
		}

		my $parent_repo = $repo->{parent_repo};
		if ($parent_repo)
		{
			repoDisplay($dbg_parse,1,"submodule repo($repo->{path}");
			repoDisplay($dbg_parse,2,"added to parent($parent_repo->{path}} submodules");
			$parent_repo->{submodules} ||= shared_clone([]);
			push @{$parent_repo->{submodules}},$repo->{path};
			my $master_repo = getRepoById($repo->{id});
			if (!$master_repo)
			{
				repoError(undef,"Could not find master module($repo->{id}) for submodule($repo->{path}");
			}
			else
			{
				repoDisplay($dbg_parse,2,"added to master_repo($master_repo->{path}} used_in");
				$master_repo->{used_in} ||= shared_clone([]);
				push @{$master_repo->{used_in}},$repo->{path};
			}
		}
	}

    if (!@$repo_list)
    {
        error("No paths found in $repo_filename");
        return;
    }
	return 1;
}



#--------------------------------------------------------------------
# repo grouping utilities
#--------------------------------------------------------------------


sub section
{
	my ($name) = @_;
	return
}


sub groupReposBySection
{
	my $section = '';
	my $section_path = 'invalid_initial_value';
	my $sections = shared_clone([]);
	for my $repo (@$repo_list)
	{
		if ($section_path ne $repo->{section_path})
		{
			$section_path = $repo->{section_path};
			$section = shared_clone({
				path => $section_path,
				id => $repo->{section_id},
				repos => shared_clone([]),
			});
			push @$sections,$section;
		}
		push @{$section->{repos}},$repo;
	}
	return $sections;
}



#--------------------------------------------------------------------
# test main - developing 'all tags across repositories' function
#--------------------------------------------------------------------

use Git::Raw;

my $all_tags = {};


sub addRepoTags
{
	my ($repo) = @_;

	my $git_repo = Git::Raw::Repository->open($repo->{path});
	if (!$git_repo)
	{
		return $repo->repoError("Could not create git_repo");
		return 0;
	}
	my @tag_refs = $git_repo->tags( 'all' );

	my $started = 0;
	for my $tag_ref (@tag_refs)
	{
		my $commit = $tag_ref->target();
		my $sig = $commit->author();
		my $author = $sig->name();
		next if $author !~ /phorton1|Patrick Horton/;

		my $tag_name = $tag_ref->name();
		$tag_name =~ s/^.*\///;
		my $summary = $commit->summary();
		$summary = substr($summary,0,50) if length($summary)>50;
		my $time = timeToStr($commit->time());

		$started = tagHeader($repo,$started);
		print pad('',8)._plim($tag_name,15)." "._plim($time,20)." "._plim($author,20)." ".$summary."\n";

		#my $id = $tag->id() || '';
		#my $name = $tag->name() || '';
		#my $msg = $tag->message() || '';
		# print pad('',8).pad($name,12).pad($id.20).$msg."\n";

		my $tag = $all_tags->{$tag_name};
		if (!$tag)
		{
			$tag = {
				name => $tag_name,
				time => $time,
				paths => {} };
			$all_tags->{$tag_name} = $tag;
		}

		$tag->{time} = $time if $time lt $tag->{time};
		$tag->{paths}->{$repo->{path}} = 1;
	}

	return 1;
}


if (0)
{
	if (parseRepos())
	{
		my $repo_list = getRepoList();
		for my $repo (@$repo_list)
		{
			addRepoTags($repo);
		}

		print "\nALL TAGS\n";
		for my $tag (sort {$a->{time} cmp $b->{time}} values %$all_tags)
		{
			print _plim($tag->{name},15)." ".$tag->{time}."\n";
			for my $path (sort keys %{$tag->{paths}})
			{
				print pad('',4).$path."\n";
			}
		}
	}
}


1;
