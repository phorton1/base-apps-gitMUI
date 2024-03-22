#----------------------------------------------------
# base::apps::gitMUI::repoGit
#----------------------------------------------------
# Contains gitXXX methods that change repositories using Git::Raw
# Some changes (i.e. real 'gitChanges') will generate monitor events,
# but many others will not, and so we generate them manually here.
#
# REBASE
#
# Rebasing is not an atomic operation in this module.
# Rebasing is only done during a Pull in our system.
# If a repo needs to be manually rebased, use "git rebase"
# from the command line.
#
# SUBMODULE PARENT COMMITS
#
# Also, be careful about needlessly committing the parent module's
# submodule while in the middle of mods.  Only after the submodules
# changes are committed should the parent module's commit of the
# submodule occur.
#
# STASH
#
# Stashes automatically get cleaned up after two weeks, by default,
# in gc_prune during repository cleanup.
# I am going to not call 'git stash clear' at this time.
# They slightly pollute the regular git history, but are probably
# useful.

package apps::gitMUI::repoGit;
use strict;
use warnings;
use threads;
use threads::shared;
use Time::HiRes qw(sleep);
use Git::Raw;
use Pub::Utils;
use Pub::Prefs;
use apps::gitMUI::repos;
use apps::gitMUI::utils;


my $STASH_UNTRACKED_FILES = 1;
	# Whether, when pulling, to Stash untracked files.
	# Pros: all submodules will be the same
	# Cons: I could lose work-in-progress.
	# For now, the sanctity of submodules is more important,
	# and if needed, the untracked files will be in the
	# stash, so this is set to 1 and untracked files will
	# be deleted during a Stash.


my $dbg_start = 1;
my $dbg_chgs = 1;
my $dbg_diff = 1;
my $dbg_index = 1;
my $dbg_revert = 1;
my $dbg_commit = 1;
my $dbg_tag = 0;
my $dbg_push = 0;
my $dbg_pull = 0;
	# -1 to show diff details

my $dbg_creds = 0;
	# push credentials callback
my $dbg_cb = 1;
	# push callbacks


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		gitStart
		gitChanges
		gitDiff
		gitIndex
		gitRevert
		gitCommit
		gitTag
		gitPush
		gitPull

		$GIT_EXE_RE
	);
}

our $GIT_EXE_RE = '\.pm$|\.pl$|\.$cgi';


my $MAX_SHOW_CHANGES = 30;

my $credential_error:shared = 0;

my $user_cb;
my $user_cb_object;
my $user_cb_repo;
	# We specifically use non-shared global variables to
	# hold the users $object and $repo so that it should
	# work with multiple simulatneous threaded pushes


sub gitError
{
	my ($repo,$msg,$call_level) = @_;
	$call_level ||= 0;
	$call_level++;
	my $show_path = $repo ? "repo($repo->{path}): " : '';
	error($show_path.$msg,$call_level);
	return undef;
}

sub gitWarning
{
	my ($repo,$msg,$call_level) = @_;
	$call_level ||= 0;
	$call_level++;
	my $show_path = $repo ? "repo($repo->{path}): " : '';
	warning(0,-1,$show_path.$msg,$call_level);
	return undef;
}


#--------------------------------------------
# utilities for calling Git::Raw stuff
#--------------------------------------------

sub getTree
	# get a 'Tree' from a git_repo
	# $name may be HEAD or origin/$branch
{
	my ($repo, $git_repo, $name) = @_;

	my $id = Git::Raw::Reference->lookup($name, $git_repo)->peel('commit');
	return gitError($repo,"Could not get id for ref($name)")
		if !$id;

	my $commit = Git::Raw::Commit->lookup($git_repo,$id);
	return gitError($repo,"Could not get commit($name) for id($id)")
		if !$commit;

	my $tree = $commit->tree();
	return gitError($repo,"Could not get tree($name) from commit($commit)")
		if !$tree;

	return $tree;
}


#--------------------------------------------
# gitStart
#--------------------------------------------
# Sets the initial head_id, master_id, and remote_id members

sub gitStart
	# returns undef if any problems
	# returns the $git_repo otherwise
{
	my ($repo,$git_repo) = @_;
	return if !$repo->{path};

	# my $branch = $repo->{branch};

	display($dbg_start,0,"gitStart($repo->{path}) branch=$repo->{branch}");
	$git_repo ||= Git::Raw::Repository->open($repo->{path});
	return gitError($repo,"Could not create git_repo") if !$git_repo;

	my $branch_changed = 0;
	my $head = $git_repo->head();
	my $branch = $head->shorthand() || '';
	if ($repo->{branch} ne $branch)
	{
		$branch_changed = 1;
		gitWarning($repo,"repo[$repo->{num}] branch($repo->{branch}) changed to($branch)");
		$repo->{branch} = $branch;

		# re-init remote portion repo

		$repo->{BEHIND} = 0;
		delete $repo->{remote_commits};
		$repo->{branch_changed} = 1;
	}

	my $head_ref = Git::Raw::Reference->lookup("HEAD", $git_repo);
	my $head_commit = $head_ref ? $head_ref->peel('commit') : '';
	display($dbg_start+1,1,"head_id="._def($head_commit));

	my $master_ref = Git::Raw::Reference->lookup("refs/heads/$branch", $git_repo);
	my $master_commit = $master_ref ? $master_ref->peel('commit') : '';
	display($dbg_start+1,1,"master_id="._def($master_commit));

	my $remote_ref = Git::Raw::Reference->lookup("remotes/origin/$branch", $git_repo);
	my $remote_commit = $remote_ref ? $remote_ref->peel('commit') : '';
	display($dbg_start+1,1,"remote_id="._def($remote_commit));

	gitWarning($repo,"Remote branch($branch) not found")
		if !$remote_commit && $branch_changed;

	my $head_id = "$head_commit";
	my $master_id = "$master_commit";
	my $remote_id = "$remote_commit";

	$repo->{HEAD_ID} = $head_id;
	$repo->{MASTER_ID} = $master_id;
	$repo->{REMOTE_ID} = $remote_id;

	# note invariants, but don't stop using this repo

	gitWarning($repo,"DETACHED HEAD!!")
		if $git_repo->is_head_detached();
	gitWarning($repo,"NO MASTER_ID($branch)!")
		if !$master_id;
	gitWarning($repo,"HEAD_ID <> MASTER_ID!!")
		if $head_id ne $master_id;

	# rebuild/add local_commits and AHEAD

	delete $repo->{local_commits};

	my $head_id_found = $head_id ? 0 : 1;
	my $master_id_found = $master_id ? 0 : 1;
	my $remote_id_found = $remote_id ? 0 : 1;

	# push all branches on the walker to do history
	# and sort it in time order (most recent first)

	my $log = $git_repo->walker();
	$log->push($head_commit) if $head_commit;
	$log->push($master_commit) if $master_commit;
	$log->push($remote_commit) if $remote_commit;
	$log->sorting(["time"]);	# ,"reverse"]);

	my $ahead = 0;
	my $rebase = 0;
	my $com = $log->next();
	while ($com && (
		!$head_id_found ||
		!$master_id_found ||
		!$remote_id_found ))
	{
		my $sha = $com->id();
		my $msg = $com->summary();
		my $time = $com->time();
		my $extra = '';

		$head_id_found = 1 if $sha eq $head_id;
		$master_id_found = 1 if $sha eq $master_id;
		$remote_id_found = 1 if $sha eq $remote_id;

		# These are from newest to oldest
		# AHEAD is if there are local commits and MASTERS is AFTER the REMOTE.
		# BEHIND is only set by gitStatus ..

		# After the Fetch during a Pull, REMOTE will be BEFORE the MASTER, indicating
		# that a Rebase is necessary. It is SIGNIFICANT, that the repo is now in a state
		# where no commits should be allowed, lest we create a state where a Merge is
		# required. Since a Fetch may be done from the command line, the system needs to
		# know about this possibility, grr, so I am adding a member variable
		#
		# 		REBASE
		#
		# For lack of a better word, this indicates that the repo is now out of date
		# with respect to itself locally, and needs to be REBASED.

		my $ahead_str = '';
		my $rebase_str = '';
		if ($master_id_found && !$remote_id_found)
		{
			$ahead++;
			$ahead_str = "AHEAD($ahead) ";
		}
		if ($remote_id_found && !$master_id_found)
		{
			$rebase++;
			$rebase_str = "REBASE($rebase) ";
		}

		display($dbg_start+1,1,pad($ahead_str.$rebase_str,10)."$time ".pad($extra,30)._lim($sha,8)." "._lim($msg,20));

		$repo->{local_commits} ||= shared_clone([]);
		push @{$repo->{local_commits}},shared_clone({
			sha => $sha,
			msg => $msg,
			time => $time,
		});

		$com = $log->next();
	}

	warning($dbg_start,1,"repo($repo->{path}) is AHEAD($ahead)")
		if $ahead;
	warning($dbg_start-1,1,"repo($repo->{path}) needs REBASE($rebase)")
		if $rebase;
	$repo->{AHEAD} = $ahead;
	$repo->{REBASE} = $rebase;

	display($dbg_start+1,0,"gitStart($repo->{path}) returning");

	return $git_repo;
}



#--------------------------------------------
# gitChanges
#--------------------------------------------

sub gitChanges
	# returns undef if any problems
	# returns 0 if no new changes
	# returns 1 if changes have changed
	# only called from the monitor, which handles the callback
{
	my ($repo,$git_repo) = @_;
	display($dbg_chgs,0,"gitChanges($repo->{path})");
	$git_repo ||= gitStart($repo);
	return if !$git_repo;

	my $opts = { flags => {
		include_untracked => 1,
		recurse_untracked_dirs => 1 }};
	my $status = $git_repo->status($opts);
	return gitError($repo,"No result from git_status")
		if !$status;

	# this keeps the changes to near-atomic in nature

	my $unstaged_changed = 0;
	my $staged_changed = 0;
	my $unstaged_changes = $repo->{unstaged_changes};
	my $staged_changes = $repo->{staged_changes};
	my $new_unstaged_changes = shared_clone({});
	my $new_staged_changes = shared_clone({});

	my $num_changes = keys %$status;
	display($dbg_chgs,2,"local:  $num_changes changed files")
		if $num_changes > $MAX_SHOW_CHANGES;

	# more than one area may given per file

	# flags
	#  	index_new
	#	index_modified
	#	index_deleted
	#	index_renamed
	#	worktree_new
	#	worktree_modified
	#	worktree_deleted
	#	worktree_renamed
	#	worktree_unreadable
	#	conflicted				# this probably happens during a merge
	#	ignored					# I wont get these cuz I don't ask for em

	for my $fn (sort keys %$status)
	{
		my $values = $status->{$fn};
		my $flags = $values->{flags};

		for my $flag (@$flags)
		{
			my $show = 'unstaged';
			my $old_hash = $unstaged_changes;
			my $new_hash = $new_unstaged_changes;
			my $pbool = \$unstaged_changed;

			if ($flag =~ s/^index_//)
			{
				$show = 'staged';
				$old_hash = $staged_changes;
		        $new_hash = $new_staged_changes;
                $pbool = \$staged_changed;
			}
			elsif ($flag !~ s/^worktree_//)
			{
				warning(0,0,"unknown change $fn - $flag");
				next;
			}

			my $type =
				$flag eq 'new' ? "A" :
				$flag eq 'modified' ? "M" :
				$flag eq 'deleted' ? "D" :
				$flag eq 'renamed' ? "R" : "?";

			display($dbg_chgs,2,"$show: $type $fn")
				if $num_changes <= $MAX_SHOW_CHANGES;

			$new_hash->{$fn} =	shared_clone({
				repo => $repo,
				fn	 => $fn,
				type => $type });

			$$pbool = 1 if
				!$old_hash->{$fn} ||
				$type ne $old_hash->{$fn}->{type};
		}
	}

	my $changed = 0;

	if ($repo->{branch_changed})
	{
		display(0,0,"gitChanges reporting branch changed");
		$repo->{branch_changed} = 0;
		$changed = 1;
	}
	$changed++ if assignHashIfChanged($repo,'unstaged_changes',$new_unstaged_changes,$unstaged_changed);
	$changed++ if assignHashIfChanged($repo,'staged_changes',$new_staged_changes,$staged_changed);
	display($dbg_chgs-$changed,0,"gitChanges($repo->{path}) returning $changed");
	return $changed;
}


sub assignHashIfChanged
{
	my ($repo,$key,$changes,$changed) = @_;
	my $hash = $repo->{$key};
	$changed ||= scalar(keys %$hash) != scalar(keys %$changes);
	if ($changed)
	{
		display($dbg_chgs,0,"assignHashIfChanged($key,$repo->{path})");
		my $repo_list = apps::gitMUI::repos::getRepoList();
		$repo->{$key} = $changes;
	}
	return $changed;
}



#------------------------------------------------
# gitDiff
#------------------------------------------------

sub showDiffFile
{
	my ($old_new,$git_file) = @_;
	my $size = $git_file ? $git_file->size() : '' ;
	my $mode = $git_file ? $git_file->mode() : '' ;
	display($dbg_diff,1,"$old_new git_file("._def($git_file).") size($size) mode($mode)");
}

sub gitDiff
{
	my ($repo,$is_staged,$fn) = @_;
	display($dbg_diff,0,"gitDiff($is_staged,$fn)");

	# get the git_repo and its index

	my $git_repo = Git::Raw::Repository->open($repo->{path});
	return gitError($repo,"Could not create git_repo") if !$git_repo;

	# the options

	my $opts = {
		paths => [ $fn ],
		reverse => !$is_staged,
			include_typechange => 1,
		include_untracked => 1,	# !$is_staged,
			recurse_untracked_dirs => 1,
			show_untracked_content => 1, # !$is_staged,
		# show_binary => 1,
			# skip_binary_check => 1,
		context_lines => 5,
		prefix => {
			a => $is_staged ? 'index' : 'work' ,
			b => $is_staged ? 'HEAD'  : 'index' }};

	$opts->{tree} = getTree($repo, $git_repo, 'HEAD')
		if $is_staged;

	my $diff = $git_repo->diff($opts);
	return gitError($repo,"Could not do diff()") if !$diff;

	if ($dbg_diff < 0)
	{
		my @deltas = $diff->deltas();
		my $delta_count = @deltas;	# $diff->delta_count();
		display($dbg_diff,1,"DELTAS($delta_count)");
		for my $delta (@deltas)
		{
			my $status = $delta->status();
			my $flags = $delta->flags();
			my $flag_text = join(',',@$flags);
			display($dbg_diff,2,"status($status) flags("._def($flags).") flag_text("._def($flag_text).")");
			showDiffFile("old",$delta->old_file());
			showDiffFile("new",$delta->new_file());
		}
		my @patches = $diff->patches();
		my $patch_count = @patches;
		display($dbg_diff,1,"PATCHES($patch_count)");
		for my $patch (@patches)
		{
			my $stats = $patch->line_stats();
			my $context = $stats->{context};
			my $additions = $stats->{additions};
			my $deletions = $stats->{deletions};
			my @hunks = $patch->hunks();
			my $hunk_count = @hunks;
			display($dbg_diff,2,"PATCH context($context) additions($additions) deletions($deletions) hunks($hunk_count)");
			for my $hunk (@hunks)
			{
				my $old_start = $hunk->old_start();
				my $old_lines = $hunk->old_lines();
				my $new_start = $hunk->old_start();
				my $new_lines = $hunk->old_lines();
				display($dbg_diff,3,"hunk old($old_start,$old_lines) new($new_start,$new_lines)");
				print $hunk->header();
			}
		}
	}

	my $text = $diff->buffer( 'patch' );
	my $length = length($text);

	display($dbg_diff,0,"gitDiff($fn) returning $length bytes");
	return $text;
}


#--------------------------------------------
# gitIndex
#--------------------------------------------
# Move things from staged to unstaged and back

sub addEXEFile
	# the only way I found to Add a file with EXE bits is
	# to read the file into memory and add it as a buffer
{
	my ($index,$repo,$path) = @_;
	my $fullpath = makePath($repo->{path},$path);
	my $text = getTextFile($fullpath,1);
	my $MODE_EXE = 0100755;
	$index->add_frombuffer($path,$text,$MODE_EXE);
}


sub gitIndex
	# git add paths, or -A (all)
	# Note that we manually call notifyRepoChanged() after we
	# 	manually adjust the repo hashes, becuase the change would
	#   NOT get caught in gitChanges otherwise.
	# CHMOD NOTE:  Git::Raw does not have a 'chmod' function or
	#   hooks which support setting the executable bit on new files
	#   from windows, as is done with the pre-commit
	#   script for .pm/pl/cgi files in the regular git/gitGUI.
	#   The only way I was able to find to set the EXE bits
	#   was to Add the file as a single path, using add_frombuffer.
	#	THEREFORE, if there are any EXE files (pm|pl|cgi) in the
	#   commit, the *paths* version MUST be used.
{
	my ($repo,$is_staged,$paths) = @_;
	my $show = $is_staged ? 'staged' : 'unstaged';

	display($dbg_index,0,"gitIndex($show) paths="._def($paths));

	# Create the repo and get the index

	my $git_repo = Git::Raw::Repository->open($repo->{path});
	return gitError($repo,"Could not create git_repo") if !$git_repo;

	my $index = $git_repo->index();
	return gitError($repo,"Could not get index") if !$index;

	# Move particular $paths.
	# Call $index->add() or remove() to move from unstaged to staged,
	# or call $repo->unstage() to move from staged to unstaged ...

	if ($paths)
	{
		my $unstaged = $repo->{unstaged_changes};
		my $staged = $repo->{staged_changes};
		for my $path (@$paths)
		{
			my $uchange = $unstaged->{$path};
			my $schange = $staged->{$path};
			my $u_type = $uchange ? $uchange->{type} : ' ';
			my $s_type = $schange ? $schange->{type} : ' ';

			display($dbg_index,1,"---> u($u_type) s($s_type) $path");

			if (!$is_staged)
			{
				$u_type eq 'D' ?
					$index->remove($path) :
					# Add a single file
					# and use addFromBuffer for executable bits
					$path =~ /$GIT_EXE_RE/i ?
						addEXEFile($index,$repo,$path) :
						$index->add($path);

				$index->write;
				$staged->{$path} = $uchange;
				delete $unstaged->{$path};
			}
			else
			{
				return if !unstage($repo,$git_repo,$path);
				$unstaged->{$path} = $schange;
				delete $staged->{$path};
			}
		}
	}

	# Move all items in the repository.
	# Call $index->add_all() to move from unstaged to staged
	# or call $repo->unstage() to move from staged to unstaged

	elsif (!$is_staged)
	{
		$index->add_all({ paths => ['*'] });	# Add all files
		$index->write;
		mergeHash($repo->{staged_changes},$repo->{unstaged_changes});
		$repo->{'unstaged_changes'} = shared_clone({});
	}
	else					# Remove everything from the index by using unstage(*)
	{
		return if !unstage($repo,$git_repo,'*');
		mergeHash($repo->{unstaged_changes},$repo->{staged_changes});
		$repo->{'staged_changes'} = shared_clone({});
	}

	# it is a tossup if manually adjusting the hashes is a good idea
	# PROS: theoretically faster response in the commit window
	# CONS: lots of callbacks on big lists of commits

	getAppFrame()->notifyRepoChanged($repo)
		if getAppFrame();

	display($dbg_index,0,"gitIndex() returning 1");
	return 1;
}


sub unstage
	# for unstaging tems, we reset the index back to the HEAD commit.
	# A 'mixed' reset changes the index without changing the working
	# directory.
{
	my ($repo, $git_repo, $path) = @_;
	display($dbg_index,0,"unstage($path");

	# get the ID of the HEAD commit

	my $head_id = Git::Raw::Reference->lookup("HEAD", $git_repo)->peel('commit');
	return gitError($repo,"Could not get ref(HEAD)")
		if !$head_id;

	$git_repo->reset( $head_id, {
		type => 'mixed',			# forced by git if paths are specified
		paths => [ $path ] });

	return 1;
}



#------------------------------------------------
# gitRevert
#------------------------------------------------

sub gitRevert
	# Revert changes to unstaged files.
	# My version always gets a list of paths.
	# Implemented by doing a checkout from the $index
	# Does NOT call notifyReposChanged() as we do NOT manually adjust the hashes
{
	my ($repo,$paths) = @_;
	my $num_paths = @$paths;
	display($dbg_revert,0,"gitRevert($repo->{path},$num_paths)");

	# get the git_repo and its index

	my $git_repo = Git::Raw::Repository->open($repo->{path});
	return gitError($repo,"Could not create git_repo") if !$git_repo;
	my $index = $git_repo->index();
	return gitError($repo,"Could not get index") if !$index;

	# the options

	my $opts = {
		paths => $paths,
		checkout_strategy => {
			# none => 1,					# Dry run only
			force => 1,						# Take any action to make the working directory match the targe
			# safe_create => 1,				# Recreate missing files.
			# safe => 1,					# Make only modifications that will not lose changes (to be used in order to simulate "git checkout").
			# allow_conflicts => 1,			# Apply safe updates even if there are conflicts
			remove_untracked => 1,			# Remove untracked files from the working directory.
			remove_ignored => 0,			# Remove ignored files from the working directory.
			# update_only => 1,				# Only update files that already exist (files won't be created or deleted).
			# dont_update_index => 1,		# Do not write the updated files' info to the index
			# dont_write_index => 1,		# Prevent writing of the index upon completion
			# no_refresh => 1,				# Do not reload the index and git attrs from disk before operations.
			# skip_unmerged => 1,			# Skip files with unmerged index entries, instead of treating them as conflicts
			# notify => {					# Flags for what will be passed to notify
			#	conflict => 1,				# Notifies about conflicting paths.
			#	dirty => 1,					# Notifies about files that don't need an update but no longer match the baseline.# },
			#	updated => 1,				# Notification on any file changed
			#   untracked => 1,				# Notification about untracked files.
			#	ignored	 => 1,				# Notifies about ignored files.
			#	all	=> 1					# All of the above
		},
		# notify => 						# This callback is called for each file matching one of the "notify" options selected
		# progres =>						# The callback receives a string containing the path of the file $path, an integer $completed_steps and an integer $total_steps.
	};

	# DO THE REVERT - the monitor *should* generate
	# a notifyCallback on gitChanges()

	my $undef = $index->checkout( $opts );

	display($dbg_revert,0,"gitRevert($num_paths) returning 1");
	return 1;
}



#--------------------------------------------
# gitCommit
#--------------------------------------------

sub gitCommit
	# git commit  -m \"$msg\"
	# Note that we manually generate a monitor_callback
	# after adjusting repo hashes
{
	my ($repo,$msg) = @_;
	my $num = scalar(keys %{$repo->{staged_changes}});
	display($dbg_commit,0,"gitCommit($repo->{path}) $num staged_changes msg='$msg'");

	my $git_repo = Git::Raw::Repository->open($repo->{path});
	return gitError($repo,"Could not create git_repo") if !$git_repo;

	my $index = $git_repo->index();
	return gitError($repo,"Could not get index") if !$index;

	# create a new tree out of the repository index

	my $tree_id = $index->write_tree();
	my $tree 	= $git_repo->lookup($tree_id);

	# retrieve user's name and email from the Git configuration

	my $config = $git_repo->config();
	my $name   = $config->str('user.name');
	my $email  = $config->str('user.email');
	display($dbg_commit+1,1,"name($name) email($email)");

	# create a new Git signature

	my $sig = Git::Raw::Signature->new($name, $email, time(), 0);

	# create a new commit out of the above tree,
	# with the repository HEAD as parent

	my $commit = $git_repo->commit(
		$msg,
		$sig, $sig,
		[ $git_repo->head()->target() ],
		$tree );

	return gitError($repo,"Could not create git_commit")
		if !$commit;

	# clear the 'staged' changes
	# and generate a callback if in the appFrame

	$repo->{staged_changes} = shared_clone({});
	gitStart($repo,$git_repo);
	setCanPushPull($repo);
	getAppFrame()->notifyRepoChanged($repo)
		if getAppFrame();

	display($dbg_commit,0,"gitCommit() returning 1");
	return 1;
}



#--------------------------------------------
# gitTag
#--------------------------------------------

sub gitTag
	# Note that we manually generate a monitor_callback
{
	my ($repo,$tag) = @_;
	display($dbg_tag,0,"gitTag($tag,$repo->{path})");
	my $git_repo = Git::Raw::Repository->open($repo->{path});
	return gitError($repo,"Could not create git_repo") if !$git_repo;

	my $config = $git_repo->config();
	my $name   = $config->str('user.name');
	my $email  = $config->str('user.email');
	display($dbg_tag+1,1,"name($name) email($email)");
	my $sig = Git::Raw::Signature->new($name, $email, time(), 0);

	my $ref = Git::Raw::Reference->lookup("HEAD", $git_repo);
	return gitError($repo,"Could not get ref(HEAD)")
		if !$ref;
	my $ref2 = $ref->target();
	my $id = $ref2->target();
	return gitError($repo,"Could not get id_remote(HEAD)")
		if !$id;

	display($dbg_tag+1,1,"ref=$ref id=$id");

	my $msg = '';
	my $undef = $git_repo->tag($tag, $msg, $sig, $id );
	display($dbg_tag,0,"git_repo->tag() returned"._def($undef));

	# monitor_callback() for good measure

	gitStart($repo,$git_repo);
	setCanPushPull($repo);
	getAppFrame()->notifyRepoChanged($repo)
		if getAppFrame();

	display($dbg_tag,0,"gitTag($tag) returning 1");
	return 1;
}



#-------------------------------------------------------
# gitPush
#-------------------------------------------------------

sub cb_credentials
{
	my ($url) = @_;
	display($dbg_creds,0,"cb_credentials($url)");
	my $git_user = getPref('GIT_USER');
	my $git_api_token = getPref('GIT_API_TOKEN');
	my $credentials = Git::Raw::Cred->userpass($git_user,$git_api_token);
	return !error("Could not create git credentials")
		if !$credentials;
	display($dbg_cb,0,"cb_credentials() returning $credentials");
	return $credentials;
}


sub user_callback
{
	my ($CB,@params) = @_;
	my $show = join(",",@params);
	display($dbg_cb,0,"user_callback($CB,$show)");
	my $rslt = 0;
	$rslt = &$user_cb($user_cb_object,$CB,$user_cb_repo,@params)
		if $user_cb;
	display($dbg_cb,0,"user_callback() returning $rslt");
	return $rslt;
}



sub cb_pack
{
	my ($stage, $current, $total) = @_;
	display($dbg_cb,0,"cb_pack($stage, $current, $total)");
	my $rslt = user_callback($GIT_CB_PACK,$stage, $current, $total);
	display($dbg_cb,0,"cb_pack() returning $rslt");
	return $rslt;
}
sub cb_transfer
{
	my ($current, $total, $bytes) = @_;
	display($dbg_cb,0,"cb_transfer($current, $total, $bytes)");
	my $rslt = user_callback($GIT_CB_TRANSFER,$current,$total,$bytes);
	display($dbg_cb,0,"cb_transfer() returning $rslt");
	return $rslt;
}
sub cb_reference
{
	my ($ref, $msg) = @_;
	display($dbg_cb,0,"cb_reference($ref,"._def($msg).")");
	# change semantic of &msg == undef meaning "done" to
	# setting the message itself to "done". to prevent
	# "use of undefined variable" errors when trying to
	# show params by simple join.
	$msg = 'done' if !defined($msg);
	my $rslt = user_callback($GIT_CB_REFERENCE,$ref,$msg);
	display($dbg_cb,0,"cb_reference() returning $rslt");
	return $rslt;
}


sub gitPush
	# Note that we manually generate a monitor_callback
	# after adjusting repo hashes
{
	my ($repo,$u_obj,$u_cb) = @_;

	$user_cb = $u_cb;
	$user_cb_object = $u_obj;
	$user_cb_repo = $repo;

	my $branch = $repo->{branch};
	display($dbg_push,0,"gitPush($branch,$repo->{path}) with $repo->{AHEAD} commits");

	my $git_repo = Git::Raw::Repository->open($repo->{path});
	return gitError($repo,"Could not create git_repo")
		if !$git_repo;

	my $remote = Git::Raw::Remote->load($git_repo, 'origin');
	return gitError($repo,"Could not create remote")
		if !$remote;

	my $refspec_str = "refs/heads/$branch";
	my $refspec = Git::Raw::RefSpec->parse($refspec_str,0);
	return gitError($repo,"Could not create refspec($refspec_str)")
		if !$refspec;

	my $callback_options = { callbacks => {
		credentials => \&cb_credentials,
		pack_progress 			=> \&cb_pack,
		push_transfer_progress 	=> \&cb_transfer,
		push_update_reference 	=> \&cb_reference,
		# push_negotation 		=> \&cb_negotiate,
		# sideband_progress		=> \&cb_sideband,
	}};

	my $rslt;
	eval
	{
		$rslt = $remote->push([ $refspec ], $callback_options);
		1;
	}
	or do
	{
		my $err = $@;

		# THIS IS LIKELY A Git::Raw::Error
		# from which have to get the scalar message
		# to pass back through shared memory threads

		my $msg = ref($err) =~ /Git::Raw::Error/ ?
			$err->message() : $err;

		# For some reason this error does not show in ui

		error($msg);

		# strip off the 'at /base/apps/xxx.pm line XXX part
		# and pass it as a callback.

		$msg =~ s/at \/base.*$//;
		user_callback($GIT_CB_ERROR,$msg);
	};

	# We call gitStart() and generate an event in any case
	# to keep the system as consistent as possible, but we only
	# clear BEHIND if it worked. We tell the monitor to update as
	# soon as possible after a push or pull

	gitStart($repo,$git_repo);
	$repo->{BEHIND} = 0 if $rslt;
		# pre-empt the next monitorUpdate() call
	setCanPushPull($repo);
	getAppFrame()->notifyRepoChanged($repo)
		if getAppFrame();
	apps::gitMUI::monitor::monitorUpdate(1);

	display($dbg_push,1,"gitPush() returning rslt="._def($rslt));
	return $rslt;
}



#--------------------------------------------------
# gitPull
#--------------------------------------------------

sub gitPull
	# Note that we manually generate a monitor_callback
	# after adjusting repo hashes
{
	my ($repo,$u_obj,$u_cb) = @_;

	$user_cb = $u_cb;
	$user_cb_object = $u_obj;
	$user_cb_repo = $repo;

	my $branch = $repo->{branch};
	my $need_stash = $repo->needsStash();
	display($dbg_pull,0,"gitPull($branch,$repo->{path}) $repo->{BEHIND} commits needs_stash=$need_stash");

	my $git_repo = Git::Raw::Repository->open($repo->{path});
	return gitError($repo,"Could not create git_repo")
		if !$git_repo;

	if ($need_stash)
	{
		display($dbg_pull,1,"STASHING($repo->{path})");

		my $config = $git_repo->config();
		my $name   = $config->str('user.name');
		my $email  = $config->str('user.email');
		my $sig = Git::Raw::Signature->new($name, $email, time(), 0);
		my $msg = "Stashed at ".now()." from repoGit::Pull()";

		# We call Git::Raw::Stash::save() directly
		# with an 'include_untracked' option. Oh it's a class method.
		# so use a pointer.

		my $options = $STASH_UNTRACKED_FILES ? ['include_untracked'] : [];
		my $sha = Git::Raw::Stash->save($git_repo,$sig,$msg,$options);
		if (!$sha)
		{
			$STASH_UNTRACKED_FILES ?
				return gitError($repo,"No SHA returned from Stash") :
				warning(0,0,"No SHA returned from Stash($repo->{path})");
		}

	}

	my $remote = Git::Raw::Remote->load($git_repo, 'origin');
	return gitError($repo,"Could not create remote")
		if !$remote;

	my $callback_options = { callbacks => {
		credentials 			=> \&cb_credentials,
		pack_progress 			=> \&cb_pack,
		push_transfer_progress 	=> \&cb_transfer,
		push_update_reference 	=> \&cb_reference,
		# push_negotation 		=> \&cb_negotiate,
		# sideband_progress		=> \&cb_sideband,
	}};

	# Do the fetch.  If it has any problems, they
	# will be reported via the exception

	my $rslt;
	eval
	{
		$remote->fetch($callback_options);
		$rslt = 1;
		1;
	}
	or do
	{
		my $err = $@;
		my $msg = ref($err) =~ /Git::Raw::Error/ ?
			$err->message() : $err;
		error($msg);
		$msg =~ s/at \/base.*$//;
		user_callback($GIT_CB_ERROR,$msg);
	};

	# If the fetch worked, do the rebase
	# Rather than figure oiut Git::Raw::Rebase,
	# with not a single example or any clear idea of how
	# to use it on the entire internet, and which I would
	# have to spend hours figuring out, I simply call the
	# command line git from backticks.
	#
	# This is currently one of only very few places that my
	# gitMUI calls the git command line ....

	if ($rslt)
	{

		my $text = `git -C "$repo->{path}" rebase 2>&1` || '';
		my $exit_code = $? || 0;
		my $msg = "rebase exit_code($exit_code) text($text)";
		display($dbg_pull+1,2,$msg);
		if ($text =~ /Current branch $branch is up to date/)
		{
			display($dbg_pull,1,"gitPull() no changes returning 1");
			gitError($repo,"Repo is up to date!");
			return 1;
		}
		if ($exit_code || $text !~ /Successfully rebased and updated/)
		{
			gitError($repo,$msg);
			# user_callback($GIT_CB_ERROR,$msg);
			$rslt = 0;
		}
	}

	# We call gitStart() and generate an event in any case
	# to keep the system as consistent as possible, but we only
	# clear BEHIND if it worked. We tell the monitor to update as
	# soon as possible after a push or pull

	gitStart($repo,$git_repo);
	$repo->{BEHIND} = 0 if $rslt;
		# pre-empt the next repoStatus() call
	setCanPushPull($repo);
	getAppFrame()->notifyRepoChanged($repo)
		if getAppFrame();
	apps::gitMUI::monitor::monitorUpdate(1);

	display($dbg_pull,1,"gitPull() returning rslt="._def($rslt));
	return $rslt;

}



1;
