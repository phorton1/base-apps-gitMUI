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

#-----------------------------------------------------------
# 2025-12-23 Implement SUBSET repos, for boat laptop LENOVO4.
#-----------------------------------------------------------
# (1) Got rid of the notion of REMOTE_ONLY repos that start with a dash.
# (2) Got rid of previous "options" following the path of a repo with LOCAL_ONLY/REMOTE_ONLY
#
# The notion remains that the "main" machine (LENOVO3 in this case) still attempts to
# 	identify dangling github repos and/or missing local repos, but
#   the prefs file may specify a SUBSET=blah (i.e. SUBSET=BOAT) preference
#   and only those repos that match that subset will be parsed
#
#   gitMUI.prefs:
#		SUBSET = BOAT	# optional
#   git_repositories.txt
#		/some repo name \t BOAT,OTHER	# tab, then comma delimited list of SUBSETS
#
# In the case that a SUBSET is specified, gitMUI will not attempt to identify
#	dangling github repos.
# It will still constitute an ERROR if a local repo *should* be found, and is not.
#
# I am leaving the REMOTE_ONLY code, but not the ability to create one, in place.
# This is a messy program at this point, PRIVATE, and not usefully built as a
# windows installable.

#-----------------------------------------------------------
# 2025-12-24 PullAll and Pull SUBMODULES
#-----------------------------------------------------------
# It is fairly important now with the BOAT SUBSET to be able
# to easily update the laptop with anything that needs a pull,
# and it was already painful to do so manually with SUBMODULES.
#
# So I am revisiting the "pull all" logic with special attention
# to SUBMODULES.  To begin with, I will make an arbitrary change
# to a file on the boat laptop.
#
# GitHub events are too slow.


package apps::gitMUI::repos;
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Utils;
use Pub::Prefs;
use apps::gitMUI::repo;
use apps::gitMUI::utils;




my $dbg_parse = 0;
	# -1 for repos
	# -2 for lines
my $dbg_notify = 1;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		parseRepos

		$SUBSET

		getRepoList
		getReposByUUID
		getReposByPath

		getRepoById
		getRepoByUUID
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


our $SUBSET:shared;

my $repo_list:shared;
my $repos_by_uuid:shared;
my $repos_by_path:shared;

my $repos_can_push:shared;
my $repos_can_pull:shared;
my $repos_do_push:shared;
my $repos_do_pull:shared;
my $repos_commit_parent:shared;


sub initParse
{
	$SUBSET = '';
	$repo_list = shared_clone([]);
	$repos_by_uuid = shared_clone({});
	$repos_by_path = shared_clone({});

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
sub getReposByUUID
{
	return $repos_by_uuid;
}
sub getReposByPath
{
	return $repos_by_path;
}

sub getRepoByUUID
{
	my ($uuid) = @_;
	return $repos_by_uuid->{$uuid};
}
sub getRepoByPath
{
	my ($path) = @_;
	return $repos_by_path->{$path};
}
sub getRepoById
{
	my ($id) = @_;
	for my $repo (@$repo_list)
	{
		return $repo if $id eq $repo->{id};
	}
	return undef;
}


sub addRepoToSystem
	# We allow submodules to pass in blank for the $id so
	# because they share the $id with the main_submodule.
	# Nonetheless, they have paths and must have unique UUIDs.
{
	my ($repo,$id) = @_;
	$id = $repo->{id} if !defined($id);
	push @$repo_list,$repo;
	my $path = $repo->{path};

	if (1)
	{
		my $uuid = $repo->uuid();
 		my $exists = $repos_by_uuid->{$uuid};
		if ($exists)
		{
			repoError($repo,"Attempt to add duplicate repo_uuid($uuid) prev=[$exists->{num}] ".$exists->uuid());
		}
		else
		{
			$repos_by_uuid->{$uuid} = $repo;
		}
	}
	if ($path)
	{
		my $exists = $repos_by_path->{$path};
		if ($exists)
		{
			repoError($repo,"Attempt to add duplicate repo_path($path) prev=[$exists->{num}] $exists->{id}");
		}
		else
		{
			$repos_by_path->{$path} = $repo;
		}
	}
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
	my $repo_filename = getPref('GIT_REPO_FILENAME');
    repoDisplay($dbg_parse,0,"parseRepos($repo_filename)");

	initParse();

	$SUBSET = getPref('SUBSET');
	if ($SUBSET)
	{
		repoWarning(undef,$dbg_parse,0,"------------------------------------------------");
		repoWarning(undef,$dbg_parse,0,"SUBSET=$SUBSET");
		repoWarning(undef,$dbg_parse,0,"------------------------------------------------");
	}
	
	my $USED_IN = {};

	my $text = getTextFile($repo_filename);
    if ($text)
    {
		my $repo;
		my $section_path = '';
		my $section_id = '';

        for my $line (split(/\n/,$text))
        {
			$line =~ s/#.*$//;
			$line =~ s/^\s+//;
			$line =~ s/\s+$//;

			my $dbg_num = scalar(@$repo_list);

			# get section path RE and optional name if different
			# SECTION and path-branch delimiter is TAB!!

			if ($line =~ /^SECTION\t/i)
			{
				$repo = undef;
				my @parts = split(/\t/,$line);
				$section_path = $parts[1];
				$section_path =~ s/^\s+|\s+$//g;
				$section_id = $parts[2] || '';
			}


			# REPO DEFINITIONS START WITH FORWARD SLASH

			elsif ($line =~ /^\//)
			{
				$repo = undef;
				my @parts = split(/\t/,$line);
				my ($path,$subsets) = ($parts[0],$parts[1] || '');

				if ($SUBSET)
				{
					my $found = 0;
					for my $ss (split(/,/,$subsets))
					{
						if ($ss eq $SUBSET)
						{
							$found = 1;
							last;
						}
					}
					if (!$found)
					{
						repoDisplay($dbg_parse,1,"skipping SUBSET($SUBSET) repo($path)");
						next;
					}
				}

				repoDisplay($dbg_parse+1,1,"repo($dbg_num,$path,$section_path,$section_id)");
				$repo = apps::gitMUI::repo->new({
					where => $REPO_LOCAL,
					path => $path,
					section_path => $section_path,
					section_id => $section_id,
					# opts => $opts,
				});
				if ($repo)
				{
					addRepoToSystem($repo);
				}
			}


			elsif ($repo)
			{
				# handle SUBMODULES

				if ($line =~ /SUBMODULE\t(.*)$/)
				{
					my $rel_path = $1;
					my $path = makePath($repo->{path},$rel_path);
					repoWarning(undef,$dbg_parse+1,1,"SUBMODULE($dbg_num, $repo->{path}) = $rel_path ");
					my $sub_module = apps::gitMUI::repo->new({
						where => $REPO_LOCAL,
						path  => $path,
						section_path => $section_path,
						section_id => $section_id,
						parent_repo => $repo,
						rel_path => $rel_path, });
					addRepoToSystem($sub_module,'') if $sub_module;
					my $main_id = $sub_module->{id};
					$USED_IN->{$main_id} ||= [];
					push @{$USED_IN->{$main_id}},$path;
				}


				# set PRIVATE bit

				elsif ($line =~ /^PRIVATE$/i)
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
					$repo->repoWarning(0,0,"$what $root does not exist")
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
	# Validate that referred FRIEND repos exist
	# For submodules, set
	#		{submodules} list of paths on parent
	#		{used_in} list of paths on master module

	for my $repo (@$repo_list)
	{
		apps::gitMUI::repoGit::gitStart($repo);

		# parent submodules

		my $parent_repo = $repo->{parent_repo};
		if ($parent_repo)
		{
			repoDisplay($dbg_parse,1,"submodule repo($repo->{path}");
			repoDisplay($dbg_parse,2,"added to parent($parent_repo->{path}} submodules");
			$parent_repo->{submodules} ||= shared_clone([]);
			push @{$parent_repo->{submodules}},$repo->{path};
		}

		# master used_in's

		my $id = $repo->{id};
		if (!$repo->{parent_repo} && $USED_IN->{$id})
		{
			repoNote($repo,$dbg_parse,1,"MAIN_MODULE for id($id)");
			display($dbg_parse,2,"used_in=\n".join("\n",@{$USED_IN->{$id}}) );
			$repo->{used_in} = shared_clone($USED_IN->{$id});
		}

		# uses

		setUsedBy($repo);

		# friends

		my $friends = $repo->{friend};
		if ($friends)
		{
			for my $friend (@$friends)
			{
				my $friend_repo = $repos_by_path->{$friend};
				$repo->repoError("invalid FRIEND: $friend")
					if !$friend_repo;
			}
		}
	}

	# sort used_by repos by depth, name

	for my $repo (@$repo_list)
	{
		my $used_by = $repo->{used_by};
		if ($used_by)
		{
			$repo->{used_by} = shared_clone([sort {cmpUsedBy($a,$b)} @$used_by]);
		}
	}

    if (!@$repo_list)
    {
        error("No paths found in $repo_filename");
        return;
    }

	return 1;
}



my $RECURSE_USED_BY = 1;


sub cmpUsedBy
{
	my ($aa,$bb) = @_;
	my $level_a = $aa =~ s/^(-+)// ? length($1) : 0;
	my $level_b = $bb =~ s/^(-+)// ? length($1) : 0;
	return 1 if $level_a > $level_b;
	return -1 if $level_a < $level_b;
	return lctilde($aa) cmp lctilde($bb);
}


sub setUsedBy
{
	my ($repo,$base_repo,$level,$already_used) = @_;

	$level ||= 0;
	$already_used ||= {};
	$base_repo ||= $repo;
	my @recurse;

	my $uses = $repo->{uses};
	if ($uses)
	{
		for my $use (@$uses)
		{
			next if $already_used->{$use};
			$already_used->{$use} = 1;

			my $used_repo = $repos_by_path->{$use};
			if (!$used_repo)
			{
				$repo->repoError("invalid USES: $use");
					# We must still validate USES because other parts
					# of the system depend on USES and USED_BY being
			}
			else
			{
				$used_repo->{used_by} ||= shared_clone([]);
				my $show = ('-' x $level).$base_repo->{path};

				push @{$used_repo->{used_by}},$show;
			}

			setUsedBy($used_repo,$base_repo,$level+1,$already_used)
				if $RECURSE_USED_BY;
		}
	}
}

#--------------------------------------------------------------------
# repo grouping utilities
#--------------------------------------------------------------------


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




1;
