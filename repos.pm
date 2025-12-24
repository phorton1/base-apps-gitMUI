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
# 2025-12-23 Implment SUBSET repos, for boat laptop LENOVO4.
#
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
#
#   git_repositories.txt
#
#		/some repo name \t BOAT,OTHER	# tab, then comma delimited list of SUBSETS
#
# In the case that a SUBSET is specified, gitMUI will not attempt to identify
#	dangling github repos.
# It will still constitute an ERROR if a local repo *should* be found, and is not.
#
# I am leaving the REMOTE_ONLY code, but not the ability to create one, in place.
# This is a messy program at this point, PRIVATE, and not usefully built as a
# windows installable.



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

			#	No more REMOTE_ONLY repo definitions
			#
			#	elsif ($line =~ s/^-//)
			#	{
			#		my @parts = split(/\t/,$line);
			#		my ($id,$opts) = ($parts[0],$parts[1] || '');
			#		repoDisplay($dbg_parse+1,1,"remote_only repo($dbg_num,$id,$section_path,$section_id)");
			#		$repo = apps::gitMUI::repo->new({
			#			where => $REPO_REMOTE,
			#			id => $id,
			#			section_path => $section_path,
			#			section_id => $section_id,
			#			opts => $opts, });
			#		addRepoToSystem($repo) if $repo;
			#	}


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
    elsif (!$INIT_SYSTEM)
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

    if (!$INIT_SYSTEM && !@$repo_list)
    {
        error("No paths found in $repo_filename");
        return;
    }

	# We don't list untracked repos if $SUBSET

	if (!$SUBSET)
	{
		if ($INIT_SYSTEM || getPref('GIT_ADD_UNTRACKED_REPOS'))
		{
			my $untracked = apps::gitMUI::reposUntracked::findUntrackedRepos();
			my $num_untracked = scalar(keys %$untracked);
			repoDisplay($dbg_parse,1,"ADDING $num_untracked untracked repos");
			for my $path (sort {lc($a) cmp lc($b)} keys %$untracked)
			{
				my $section_id = 'untrackedRepos';
				my $section_path = 'untrackedRepos';
				my $opts = $UNTRACKED_REPO;

				if ($INIT_SYSTEM)
				{
					$section_id = '';
					$section_path = '';
					$opts = '';
				}

				repoDisplay($dbg_parse+1,2,"adding untracked_repo($path)");
				my $repo = apps::gitMUI::repo->new({
					where => $REPO_LOCAL,
					path  => $path,
					section_id => $section_id,
					section_path => $section_id,
					opts => $opts, });
				if ($repo)
				{
					addRepoToSystem($repo);
					if ($INIT_SYSTEM)
					{
						repoNote($repo,$dbg_parse,2,"INIT_SYSTEM repo($path)");
						apps::gitMUI::repoGit::gitStart($repo);
					}
					else
					{
						repoWarning($repo,$dbg_parse,2,"untracked repo($path)");
					}
				}
			}
		}	# $INIT_SYSTEM || GIT_ADD_UNTRACKED_REPOS
	}	# !$SUBSET

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



#-------------------------------------------
# INIT_SYSTEM - writeNewReposFile()
#-------------------------------------------
# Attempts to create sections based on a topological
# analysis, grouping things together if they have a
# certain number of similar characteristics.
#
# THE RUBBER MEETS THE ROAD
#
# This algorithm actually attempts to come up with the old
# path<->id mappings for any repos which exist both remotely
# and locally, giving priority to grouping local repos (with paths)
# first.
#
# SUBMODULES IDENTIFICATION
#
# To work reasonably, we should (can) identify submodules
# within the system using GIT on each repo.  We *could*
# then, theoretically, identify the main submodule as
# having that ID, but not being a submodule. At very least
# it is part of the submodule group (all such repos being
# treated as MASTER_MODULE).
#
# Of course, during this process, we have completely broken
# the list, so we call addRepoToSystem after clearing
# both hashes at the end.



my $dbg_topo = -1;
my $dbg_subs = 0;
my $dbg_use_xxx = 0;
my $dbg_path_id_map = 0;
my $dbg_apply = 0;
my $dbg_topo_map = 0;
my $dbg_topo_ids = 0;
my $dbg_sections = 0;
my $dbg_final = 0;


my $NUM_FOR_GROUP = 5;
	# any repeated patterns that have 3 items will break into
	# a new section.  This is done by re-iterating the list at
	# each level backwards.




sub buildPathIdMap
{
	my ($repo,$path_id_map,$path_id_hash) = @_;

	my $id = $repo->{use_id};
	my $path = $repo->{use_path};
	display($dbg_path_id_map,0,"use_path($path) use_id($id)");

	my $cannonical_id = $path;
	$cannonical_id =~ s/^\///;
	$cannonical_id =~ s/\//-/g;
	if ($id eq $cannonical_id)
	{
		display($dbg_path_id_map,1,"matches cannonical id");
		return;
	}

	# try applying previous mappings (in reverse order)

	my $did_sub = 0;
	my $use_path = $path;
	for my $map (reverse @$path_id_map)
	{
		my $map_id = $map->{id};
		my $map_path = $map->{path};
		my $map_re = $map_path;
		$map_re =~ s/\//\\\//g;

		display($dbg_path_id_map+2,2,"check use_path($use_path) versus map_path($map_path) re($map_re) map_id=$map_id");

		if ($use_path =~ /^$map_re/)
		{
			$did_sub = 1;
			my $new_path = $use_path;
			$new_path =~ s/^$map_re/$map_id/;
			display($dbg_path_id_map,3,"substitute re($map_re) for id($map_id) = new_path($new_path)",0,$UTILS_COLOR_LIGHT_CYAN);
			$use_path = $new_path;
		}
	}

	display($dbg_path_id_map+1,1,"path after substitutions=$use_path") if $did_sub;

	$cannonical_id = $use_path;
	$cannonical_id =~ s/^\///;
	$cannonical_id =~ s/\//-/g;

	if ($id eq $cannonical_id)
	{
		display($dbg_path_id_map,1,"id($id) now matches cannonical_id($cannonical_id)",0,$UTILS_COLOR_LIGHT_CYAN);
		return;
	}

	# if still no match, use the raw path and id and
	# push a mapping onto the list if it doesn't already exist

	$path =~ s/^\///;
	$id =~ s/^-//;

	# my @id_parts = split(/-/,$id);
	# my @path_parts = split(/\//,$path);
	# pop @id_parts if @id_parts > 1;
	# pop @path_parts if @path_parts > 1;
	# $id = join('-',@id_parts);
	# $path = '/'.join('/',@path_parts);

	$path = '/'.$path;

	if (!$path_id_hash->{$path})
	{
		display($dbg_path_id_map,1,"new path_id_map($path) => $id",0,$UTILS_COLOR_YELLOW);
		my $map = {
			path => $path,
			id => $id, };
		push @$path_id_map,$map;
		$path_id_hash->{$path} = $id;
	}
	else
	{
		display($dbg_path_id_map,1,"path_id_map($path) => $id  already exists");
	}
}



sub applyPathIdMap
{
	my ($repo,$path_id_map) = @_;

	my $id = $repo->{use_id};
	my $path = $repo->{use_path};
	display($dbg_apply,0,"use_path($path) use_id($id)");

	my $cannonical_id = $path;
	$cannonical_id =~ s/^\///;
	$cannonical_id =~ s/\//-/g;
	if ($id eq $cannonical_id)
	{
		display($dbg_apply,1,"matches cannonical id");
		return;
	}

	# try applying previous mappings (in reverse order)

	my $did_sub = 0;
	my $use_path = $path;
	for my $map (reverse @$path_id_map)
	{
		my $map_id = $map->{id};
		my $map_path = $map->{path};
		my $map_re = $map_path;
		$map_re =~ s/\//\\\//g;

		display($dbg_apply+2,2,"check use_path($use_path) versus map_path($map_path) re($map_re) map_id=$map_id");

		if ($use_path =~ /^$map_re/)
		{
			$did_sub = 1;
			my $new_path = $use_path;
			$new_path =~ s/^$map_re/$map_id/;
			display($dbg_apply,3,"substitute re($map_re) for id($map_id) = new_path($new_path)",0,$UTILS_COLOR_LIGHT_CYAN);
			$use_path = $new_path;
		}
	}

	display($dbg_apply+1,1,"path after substitutions=$use_path") if $did_sub;

	$cannonical_id = $use_path;
	$cannonical_id =~ s/^\///;
	$cannonical_id =~ s/\//-/g;

	if ($id eq $cannonical_id)
	{
		display($dbg_apply,1,"id($id) now matches cannonical_id($cannonical_id)",0,$UTILS_COLOR_LIGHT_CYAN);
		$repo->{use_path} = $use_path;
		return;
	}

	warning($dbg_apply,1,"no cannonical mapping available");
}




sub buildTopoRepos
{
	my ($repo,$topo_id_map) = @_;

	my $id = $repo->{cannonical_id};
	my $path = $repo->{cannonical_path};

	# cannonical id and path will exist as a pair at this point
	# so, if either is missing we use the defaults from setup

	if (!$id)
	{
		$id = $repo->{use_id};
		$path = $repo->{use_path};
	}

	if ($id)
	{
		my $len = 0;
		my @parts = split(/-/,$id);
		my $built_id = '';
		for my $part (@parts)
		{
			$len++;
			$built_id .= '-' if $built_id;
			$built_id .= $part;
			$topo_id_map->{$built_id} ||= {
				topo_id => $built_id,
				len => $len,
				repos => [] };
			push @{$topo_id_map->{$built_id}->{repos}},$repo;
		}
	}
}




sub buildSections
{
	my ($repo,$path_id_map) = @_;
	my $section_id = $repo->{topo_id};
	my $section_path = $section_id;

	# now we do the reverse substitution mapping for section path

	my $did_sub = 0;
	for my $map (reverse @$path_id_map)
	{
		my $map_id = $map->{id};
		my $map_path = $map->{path};

		display($dbg_sections+1,2,"check section_path($section_path) versus map_path($map_path) and map_id($map_id)");

		if ($section_path =~ /^$map_id/)
		{
			$did_sub = 1;
			my $new_path = $section_path;
			$new_path =~ s/^$map_id/$map_path/;
			display($dbg_sections,1,"substitute re($map_id) for path($map_path) = new_path($new_path)",0,$UTILS_COLOR_LIGHT_CYAN);
			$section_path = $new_path;
		}
	}


	$section_path =~ s/-/\//g;
	$section_path =~ s/-/\//g;
	$section_path = '/'.$section_path if $section_path !~ /^\//;

	$repo->{section_id} = $section_id;
	$repo->{section_path} = $section_path;
	my $uuid = $repo->uuid();
	display($dbg_sections,0,"sections($uuid) section_path($repo->{section_path}) section_id($repo->{section_id})");
}



sub getPossibleSubmodules
	#	[submodule "data"]
	#		path = data
	#		url = https://github.com/phorton1/Arduino-libraries-myIOT-data_master
{
	my ($repo) = @_;
	return undef if !$repo->{path};

	my $possible_relpaths;
	my $filename = "$repo->{path}/.gitmodules";
	if (-f $filename)
	{
		display($dbg_subs,0,"getPossibleSubmodules($repo->{path})");
		my @lines = getTextLines($filename);
		for my $line (@lines)
		{
			if ($line =~ s/path\s*=\s*//)
			{
				$line =~ s/^\s+//;
				display($dbg_subs,1,"possible_relpath=$line");
				$possible_relpaths ||= [];
				push @$possible_relpaths,$line;
			}
		}
	}
	return $possible_relpaths;
}



sub writeNewReposFile()
{
	display(0,0,"writeNewReposFile(".scalar(@$repo_list).")");

	# (-1) start by setting up submodule relationships

	display($dbg_topo,0,"build submodule relationships");

	my $USED_IN; # = {};
		# I don't think this is needed

	for my $repo (@$repo_list)
	{
		my $possible_relpaths = getPossibleSubmodules($repo);
		if ($possible_relpaths)
		{
			for my $rel_path (@$possible_relpaths)
			{
				my $sub_path = "$repo->{path}/$rel_path";
				my $sub_repo = getRepoByPath($sub_path);
				if ($sub_repo)
				{
					warning($dbg_subs,2,"found submodule($rel_path) in $repo->{path}");
					$repo->{submodules} ||= shared_clone([]);
					push @{$repo->{submodules}},$sub_path;

					$sub_repo->{parent_repo} = $repo;
					$sub_repo->{rel_path} = $rel_path;
					$sub_repo->{can_commit_parent} = 0;
					$sub_repo->{first_time} = 1;
					$sub_repo->{private} = $repo->{private};

					my $id = $sub_repo->{id};

					if ($USED_IN)
					{
						$USED_IN->{$id} ||= [];
						push @{$USED_IN->{$id}},$sub_repo->{path};
					}
				}
			}
		}
	}


	# (0) create use_path and use_id members with slash-dash mappings
	# also set used_in for ANY master-modules

	display($dbg_topo,0,"build use_id and use_path");

	my $new_repos = [];
	for my $repo (@$repo_list)
	{
		my $id = $repo->{parent_repo} ? '' : $repo->{id};
		if ($USED_IN && $id && $USED_IN->{$id})
		{
			$repo->{used_in} = shared_clone($USED_IN->{$id});
		}

		my $path = $repo->{path};
		if (!$id)
		{
			$id = $repo->{path};
			$id =~ s/\//-/g;
			$id =~ s/^-//;
		}
		if (!$path)
		{
			$path = $repo->{id};
			$path =~ s/^-//;
			$path =~ s/-/\//g;
			$path = '/'.$path;
		}
		$repo->{use_id} = $id;
		$repo->{use_path} = $path;
		push @$new_repos,$repo;

		my $uuid = $repo->uuid();
		display($dbg_use_xxx,1,"repo($uuid) use_id($id) use_path($path)".($repo->{private}?" PRIVATE":''));
	}


	# (1) build the path_id_map

	my $path_id_map = [];
	my $path_id_hash = {};

	display($dbg_topo,0,"buildPathIdMap()");
	for my $repo (sort {lctilde($a->{use_path}) cmp lctilde($b->{use_path})} @$new_repos)
	{
		buildPathIdMap($repo,$path_id_map,$path_id_hash);
	}

	# (1b) add boiled down sub paths to the path_id_map, i.e. for the mapping
	#	   path(/src/Android/Artisan) => id{Android-Artisan)
	#      create a sub-mapping /src/Android => id(Android),
	#      insert them in the map and re-sort it.

	display($dbg_topo,0,"boilPathIdMap()");
	my @add_boiled;
	for my $map (@$path_id_map)
	{
		my $id = $map->{id};
		my $path = $map->{path};
		$path =~ s/^\///;
		my @id_parts = split(/-/,$id);
		my @path_parts = split(/\//,$path);
		while (@id_parts > 1 &&
			   @path_parts>1 &&
			   $id_parts[@id_parts-1] eq $path_parts[@path_parts-1])
		{
			pop @id_parts;
			pop @path_parts;
		}

		my $new_id = join("-",@id_parts);
		my $new_path = '/'.join("/",@path_parts);

		if (!$path_id_hash->{$new_path})
		{
			$path_id_hash->{$new_path} = $new_id;
			display($dbg_path_id_map,1,"adding boiled map path($new_path) => id($new_id)");
			push @add_boiled,{
				id => $new_id,
				path => $new_path };
		}
	}

	if (@add_boiled)
	{
		warning($dbg_path_id_map,1,"adding ".scalar(@add_boiled)." path_id_maps");
		push @$path_id_map,@add_boiled;
		$path_id_map = [ sort {lctilde($a->{path}) cmp lctilde($b->{path})} @$path_id_map ];
	}

	if ($dbg_path_id_map <= 0)
	{
		display($dbg_path_id_map,0,"path_id_map");
		for my $map (@$path_id_map)
		{
			display($dbg_path_id_map,1,"path($map->{path}) => id{$map->{id})");
		}
	}

	# (2) - apply the path_id_map
	# modifying use_path and use_id if they can be modified

	display($dbg_topo,0,"applyPathIdMap()");
	for my $repo (sort {lctilde($a->{use_path}) cmp lctilde($b->{use_path})} @$new_repos)
	{
		applyPathIdMap($repo,$path_id_map);
	}
	if ($dbg_apply <= 0)
	{
		display($dbg_apply,0,"applied_map");
		for my $repo (sort {lctilde($a->{use_path}) cmp lctilde($b->{use_path})} @$repo_list)
		{
			display($dbg_apply,1,"id($repo->{id}) use_id($repo->{use_id}) use_path($repo->{use_path}) path($repo->{path}}");
		}
	}

	# (3) build hash of by partial ids with {len} and {repos} members

	display($dbg_topo,0,"buildTopoRepos()");
	my $topo_id_map = {};
	for my $repo (sort {lctilde($a->{use_path}) cmp lctilde($b->{use_path})} @$new_repos)
	{
		buildTopoRepos($repo,$topo_id_map);
	}
	if ($dbg_topo_map < 0)
	{
		display($dbg_topo_map,0,"topo_id_map");
		for my $built_id (sort {lctilde($a) cmp lctilde($b)} keys %$topo_id_map)
		{
			my $all = $topo_id_map->{$built_id};
			display($dbg_topo_map,1,"topo_id_map($built_id} has ".scalar(@{$all->{repos}})." repos");
		}
	}


	# (4) sort the topo_id_map list by highest topographical length first
	# and create topo_ids for each repo that has that has more
	# than $NUM_FOR_GROUP elements

	display($dbg_topo,0,"buildTopoIds()");

	sub sortTopo
	{
		my ($aa,$bb) = @_;
		my $cmp = $bb->{len} <=> $aa->{len};	# descending
		return $cmp if $cmp;
		return lctilde($aa->{topo_id}) cmp lctilde($bb->{topo_id});
	}

	my $last_len = -1;
	for my $map (sort {sortTopo($a,$b)} values %$topo_id_map)
	{
		my $len = $map->{len};
		if ($last_len != $len)
		{
			$last_len = $len;
			display($dbg_topo_ids,1,"build topoIds at len($len)")
		}

		my $topo_id = $map->{topo_id};
		my $repos = $map->{repos};
		next if $len>1 && scalar(@$repos) < $NUM_FOR_GROUP;
			# the problem is that Arduino-Libraries-myIOT has 8 items,
			# of which 7 happen to be submodules grouped together by the
			# master_module_id.  Without calling GIT we cannot figure out
			# that one of them is the 'data_master', and the other 7 belongtten
			#
			# Another (general) problem is that sections with only one element
			# probably should be grouped together, somehow, at beginning or end
			# under a "Misc" name while still retaining their path/within/section
			# stuff.

		for my $repo (@$repos)
		{
			next if $repo->{topo_id};
			my $uuid = $repo->uuid();
			display($dbg_topo_ids,2,"len($len) repo($uuid) topo_id=$topo_id",0,$UTILS_COLOR_CYAN);
			$repo->{topo_id} = $topo_id;
		}
	}


	# (5) build sections

	display($dbg_topo,0,"buildSections()");
	for my $repo (sort {lctilde($a->{topo_id}) cmp lctilde($b->{topo_id})} @$new_repos)
	{
		buildSections($repo,$path_id_map);
	}


	# (6) one more sort by section information
	#     and we re-add them to the system

	sub sortSections
	{
		my ($aa,$bb) = @_;
		my $cmp = lctilde($aa->{section_path}) cmp lctilde($bb->{section_path});
		return $cmp if $cmp;
		my $uuid_a = $aa->uuid();
		my $uuid_b = $bb->uuid();
		$uuid_a =~ s/^(\/|-)//;
		$uuid_b =~ s/^(\/|-)//;
		return lctilde($uuid_a) cmp lctilde($uuid_b);
	}


	display($dbg_topo,0,"finalSort()");

	initParse();
	my $new_num = 0;
	for my $repo (sort {sortSections($a,$b)} @$new_repos)
	{
		my $uuid = $repo->uuid();
		display($dbg_final,1,"final[$new_num] section_path($repo->{section_path}) section_id($repo->{section_id}) uuid($uuid)");

		my $use_blank_id = $repo->{parent_repo} ? '' : undef;
		addRepoToSystem($repo,$use_blank_id);
	}


	# (7) WRITE THE TEXT FILE

	display($dbg_topo,0,"writing ".getPref('GIT_REPO_FILENAME'));

	my $text = '';
	my $last_section = '';
	for my $repo (@$repo_list)
	{
		next if $repo->{parent_repo};

		my $section_id = $repo->{section_id};
		my $section_path = $repo->{section_path};
		if ($section_path ne $last_section)
		{
			$last_section = $section_path;

			$text .= "\n";
			$text .= "#---------------------------------------------------------------------------\n";
			$text .= "SECTION\t$section_path\t$section_id\n";
			$text .= "#---------------------------------------------------------------------------\n";
			$text .= "\n";
		}


		my $line0 = $repo->{path};
		$line0 ||= "-".$repo->{id}."\tREMOTE_ONLY";
		$text .= "$line0\n";
		$text .= "    FORKED\n" if $repo->{forked};
		$text .= "    PRIVATE\n" if $repo->{private};

		my $submodules = $repo->{submodules};
		if ($submodules)
		{
			my $re = $repo->{path};
			$re =~ s/\//\\\//g;
			$re .= "\\/";

			display($dbg_topo,1,"parent($repo->{path}) re($re)");

			for my $rel_path (@$submodules)
			{
				$rel_path =~ s/^$re//;
				display($dbg_topo,2,"rel_path = $rel_path");
				$text .= "    SUBMODULE\t$rel_path\n";
			}
		}
	}

	printVarToFile(1,getPref('GIT_REPO_FILENAME'),$text,1);

	# RE-INITIALIZE

	$INIT_SYSTEM = 0;
	warning($dbg_topo,0,"REPARSING ...");
	parseRepos();
	apps::gitMUI::reposGithub::doGitHub(1);

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
