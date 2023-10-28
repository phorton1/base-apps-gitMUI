#----------------------------------------------------
# base::apps::gitUI::repoGit
#----------------------------------------------------
# Contains gitXXX methods that change repositories using Git::Raw
# Some changes (i.e. real 'gitChanges') will generate monitor events,
# but many others will not, and so we generate them manually here.

package apps::gitUI::repoGit;
use strict;
use warnings;
use threads;
use threads::shared;
use Time::HiRes qw(sleep);
use Git::Raw;
use Pub::Utils;
use apps::gitUI::repos;
use apps::gitUI::utils;


my $MAX_SHOW_CHANGES = 30;


my $dbg_chgs = 1;
my $dbg_index = 0;
my $dbg_revert = 0;
my $dbg_commit = 0;
my $dbg_push = 0;
my $dbg_tag = 0;
my $dbg_diff = 1;
	# -1 to show diff details

my $dbg_creds = 0;
	# push credentials callback
my $dbg_cb = 1;
	# push callbacks


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		gitChanges
		gitIndex
		gitRevert
		gitCommit
		gitTag
		gitPush
		gitDiff
	);
}


my $CREDENTIAL_FILENAME = '/dat/Private/git/git_credentials.txt';

my $git_user:shared = '';
my $git_api_token:shared = '';
my $credential_error:shared = 0;

my $push_cb;
my $push_cb_object;
my $push_cb_repo;
	# We specifically use non-shared global variables to
	# hold the users $object and $repo so that it should
	# work with multiple simulatneous threaded pushes


sub new_change
{
	my ($repo,$fn,$type) = @_;
	my $item = shared_clone({
		repo => $repo,
		fn	 => $fn,
		type => $type });
	return $item;
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
	return $repo->repoError("Could not get id for ref($name)")
		if !$id;

	my $commit = Git::Raw::Commit->lookup($git_repo,$id);
	return $repo->repoError("Could not get commit($name) for id($id)")
		if !$commit;

	my $tree = $commit->tree();
	return $repo->repoError("Could not get tree($name) from commit($commit)")
		if !$tree;

	return $tree;
}



#--------------------------------------------
# gitChanges
#--------------------------------------------

sub gitChanges
	# returns undef if any problems
	# returns 1 if the any of the hashes of changes has changed
	# returns 0 otherwise
{
	my ($repo) = @_;
	display($dbg_chgs,0,"getChanges($repo->{path})");
	my $git_repo = Git::Raw::Repository->open($repo->{path});
	return $repo->repoError("Could not create git_repo") if !$git_repo;

	my $changes_changed = 0;

	my $rslt = getLocalChanges($repo, $git_repo);
	return if !defined($rslt);
	$changes_changed += $rslt;

	$rslt = getRemoteChanges($repo,$git_repo);
	return if !defined($rslt);
	$changes_changed += $rslt;

	display($dbg_chgs,0,"gitChanges($repo->{path}) returning $changes_changed");
	return $changes_changed;
}


sub assignHashIfChanged
{
	my ($repo,$key,$changes,$changed) = @_;
	my $hash = $repo->{$key};
	$changed ||= scalar(keys %$hash) != scalar(keys %$changes);
	if ($changed)
	{
		display($dbg_chgs,0,"assignHashIfChanged($key,$repo->{path})");
		my $repo_list = apps::gitUI::repos::getRepoList();
		## lock $repo_list;
		$repo->{$key} = $changes;
		return 1;
	}
	return 0;
}


sub getLocalChanges
	# git status -s
{
	my ($repo,$git_repo) = @_;
	display($dbg_chgs,0,"getLocalChanges($repo->{path})");

	my $opts = { flags => {
		include_untracked => 1,
		recurse_untracked_dirs => 1 }};
	my $status = $git_repo->status($opts);
	return $repo->repoError("No result from git_status")
		if !$status;

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

			$new_hash->{$fn} = new_change($repo,$fn,$type);
			$$pbool = 1 if
				!$old_hash->{$fn} ||
				$type ne $old_hash->{$fn}->{type};
		}
	}

	my $changes_changed = 0;
	$changes_changed += assignHashIfChanged($repo,'unstaged_changes',$new_unstaged_changes,$unstaged_changed);
	$changes_changed += assignHashIfChanged($repo,'staged_changes',$new_staged_changes,$staged_changed);
	display($dbg_chgs,0,"getLocalChanges($repo->{path}) returning $changes_changed");
	return $changes_changed;
}


sub getRemoteChanges
	# git diff $branch origin/$branch --name-status
{
	my ($repo,$git_repo) = @_;
	my $branch = $repo->{branch};
	display($dbg_chgs,0,"getRemoteChanges($repo->{path}) branch=$branch");

	# Get the local HEAD and 'remote' origin/$branch trees

	my $tree_remote = getTree($repo,$git_repo, "origin/$branch");
	return if !$tree_remote;

	my $tree_head = getTree($repo, $git_repo, "HEAD");
	return if !$tree_head;

	# Diff the Remote tree against HEAD
	# short return if no changes

	my $diff = $tree_remote->diff({ tree => $tree_head });
	return $repo->repoError("Could not get diff()")
		if !$diff;

	my $text = $diff->buffer("name_status");
	return $repo->repoError("Could not get diff text($diff)")
		if !defined($text);

	$text =~ s/^\s+|\s$//g;
	return 0 if !$text;

	# Split the text into lines and process them
	# Occasionallly I get an asterisk at the end of the filename
	# and I don't knowo aht it means.

	my $remote_changed = 0;
	my $remote_changes = $repo->{remote_changes};
	my $new_remote_changes = shared_clone({});

	my @changes = split(/\n/,$text);
	my $num_changes = @changes;
	display($dbg_chgs,2,"remote: $num_changes changed files")
		if $num_changes > $MAX_SHOW_CHANGES;

	for my $change (sort @changes)
	{
		# next if $change =~ /\*$/;
		my ($type,$fn) = split("\t",$change);
		display($dbg_chgs,2,"change($change) remote: $type $fn")
			if $num_changes <= $MAX_SHOW_CHANGES;

		$new_remote_changes->{$fn} = new_change($repo,$fn,$type);

		$remote_changed = 1 if
			!$remote_changes->{$fn} ||
			$type ne $remote_changes->{$fn}->{type};
	}

	my $changes_changed = assignHashIfChanged($repo,'remote_changes',$new_remote_changes,$remote_changed);
	display($dbg_chgs,0,"getRemoteChanges($repo->{path}) returning $changes_changed");
	return $changes_changed;
}



#--------------------------------------------
# gitIndex
#--------------------------------------------
# Move things from staged to unstaged and back

sub gitIndex
	# git add -A
	# Note that we manually generate a monitor_callback
	# after adjusting repo hashes
{
	my ($repo,$is_staged,$paths) = @_;
	my $show = $is_staged ? 'staged' : 'unstaged';

	display($dbg_index,0,"gitIndex($show) paths="._def($paths));

	# Create the repo and get the index

	my $git_repo = Git::Raw::Repository->open($repo->{path});
	return $repo->repoError("Could not create git_repo") if !$git_repo;

	my $index = $git_repo->index();
	return $repo->repoError("Could not get index") if !$index;

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
		$index->add_all({ paths => ['*'] });
		$index->write;
		mergeHash($repo->{staged_changes},$repo->{unstaged_changes});
		$repo->{'staged_changes'} = shared_clone({});
	}
	else					# Remove everything from the index by using unstage(*)
	{
		return if !unstage($repo,$git_repo,'*');
		mergeHash($repo->{unstaged_changes},$repo->{staged_changes});
		$repo->{'unstaged_changes'} = shared_clone({});
	}

	apps::gitUI::Frame::monitor_callback({ repo=>$repo })
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
	return $repo->repoError("Could not get ref(HEAD)")
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
	# WILL generate a monitor callback!
{
	my ($repo,$paths) = @_;
	my $num_paths = @$paths;
	display($dbg_revert,0,"gitRevert($repo->{path},$num_paths)");

	# get the git_repo and its index

	my $git_repo = Git::Raw::Repository->open($repo->{path});
	return $repo->repoError("Could not create git_repo") if !$git_repo;
	my $index = $git_repo->index();
	return $repo->repoError("Could not get index") if !$index;

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

	# DO THE REVERT - WILL GENERATE A MONITOR EVENT

	my $rslt = $index->checkout( $opts );

	display($dbg_revert,0,"gitRevert($num_paths) returning "._def($rslt));
	return $rslt;
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
	return $repo->repoError("Could not create git_repo") if !$git_repo;

	my $index = $git_repo->index();
	return $repo->repoError("Could not get index") if !$index;

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

	return $repo->repoError("Could not create git_commit")
		if !$commit;

	# move the changes from 'staged' to 'remote'
	# and generate a callback if in the appFrame

	display($dbg_commit+1,1,"moving $num staged_changes to remote_changes");
	mergeHash($repo->{remote_changes},$repo->{staged_changes});
	$repo->{staged_changes} = shared_clone({});
	setCanPush($repo);
	apps::gitUI::Frame::monitor_callback({ repo=>$repo })
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
	return $repo->repoError("Could not create git_repo") if !$git_repo;

	my $config = $git_repo->config();
	my $name   = $config->str('user.name');
	my $email  = $config->str('user.email');
	display($dbg_tag+1,1,"name($name) email($email)");
	my $sig = Git::Raw::Signature->new($name, $email, time(), 0);

	my $ref = Git::Raw::Reference->lookup("HEAD", $git_repo);
	return $repo->repoError("Could not get ref(HEAD)")
		if !$ref;
	my $ref2 = $ref->target();
	my $id = $ref2->target();
	return $repo->repoError("Could not get id_remote(HEAD)")
		if !$id;

	display($dbg_tag+1,1,"ref=$ref id=$id");

	my $msg = '';
	my $rslt = $git_repo->tag($tag, $msg, $sig, $id );
	display($dbg_tag,0,"gitTag($tag) returning"._def($rslt));

	# monitor_callback() for good measure

	apps::gitUI::Frame::monitor_callback({ repo=>$repo })
		if getAppFrame();

	display($dbg_tag,0,"gitTag($tag) returning "._def($rslt));
	return $rslt;
}



#-------------------------------------------------------
# gitPush
#-------------------------------------------------------

sub getCredentials
{
	return 0 if $credential_error;
	return 1 if $git_user;
	my $text = getTextFile($CREDENTIAL_FILENAME);
	if (!$text)
	{
		error("No text in $CREDENTIAL_FILENAME");
		$credential_error = 1;
		return 0;
	}
	($git_user,$git_api_token) = split(/\n/,$text);
	$git_user ||= '';
	$git_user =~ s/^\s+|\s$//g;
	$git_api_token ||= '';
	$git_api_token =~ s/^\s+|\s$//g;

	if (!$git_user || !$git_api_token)
	{
		error("Could not get git_user("._def($git_user).") or git_token("._def($git_api_token).")");
		$credential_error = 1;
		return 0;
	}
	display($dbg_creds,0,"got git_user($git_user) git_token($git_api_token)");
	return 1;
}


sub cb_credentials
{
	my ($url) = @_;
	display($dbg_creds,0,"cb_credentials($url)");
	return '' if !getCredentials();
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
	$rslt = &$push_cb($push_cb_object,$CB,$push_cb_repo,@params)
		if $push_cb;
	display($dbg_cb,0,"user_callback() returning $rslt");
	return $rslt;
}



sub cb_pack
{
	my ($stage, $current, $total) = @_;
	display($dbg_cb,0,"cb_pack($stage, $current, $total)");
	my $rslt = user_callback($PUSH_CB_PACK,$stage, $current, $total);
	display($dbg_cb,0,"cb_pack() returning $rslt");
	return $rslt;
}
sub cb_transfer
{
	my ($current, $total, $bytes) = @_;
	display($dbg_cb,0,"cb_transfer($current, $total, $bytes)");
	my $rslt = user_callback($PUSH_CB_TRANSFER,$current,$total,$bytes);
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
	my $rslt = user_callback($PUSH_CB_REFERENCE,$ref,$msg);
	display($dbg_cb,0,"cb_reference() returning $rslt");
	return $rslt;
}


sub gitPush
	# Note that we manually generate a monitor_callback
	# after adjusting repo hashes
{
	my ($repo,$user_obj,$user_cb) = @_;

	$push_cb = $user_cb;
	$push_cb_object = $user_obj;
	$push_cb_repo = $repo;

	my $branch = $repo->{branch};
	my $num = scalar(keys %{$repo->{remote_changes}});
	display($dbg_push,0,"gitPush($branch,$repo->{path}) $num remote_chanes)");

	my $git_repo = Git::Raw::Repository->open($repo->{path});
	return $repo->repoError("Could not create git_repo")
		if !$git_repo;

	my $remote = Git::Raw::Remote->load($git_repo, 'origin');
	return $repo->repoError("Could not create remote")
		if !$remote;

	my $refspec_str = "refs/heads/$branch";
	my $refspec = Git::Raw::RefSpec->parse($refspec_str,0);
	return $repo->repoError("Could not create refspec($refspec_str)")
		if !$refspec;

	warning(0,0,"progres_cb=".\&cb_pack);

	my $push_options = { callbacks => {
		credentials => \&cb_credentials,
		pack_progress 			=> \&cb_pack,
		push_transfer_progress 	=> \&cb_transfer,
		push_update_reference 	=> \&cb_reference,
		# push_negotation 		=> \&cb_negotiate,
		# sideband_progress		=> \&cb_sideband,
	}};

	my $rslt ;
	eval
	{
		$rslt = $remote->push([ $refspec ], $push_options);
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

		# strip off the 'at /base/apps/gitUI/repo.pm line XXX part
		# and pass it as a callback.

		$msg =~ s/at \/base.*$//;

		user_callback($PUSH_CB_ERROR,$msg);
	};

	# Note that we manually generate a monitor_callback
	# after adjusting repo hashes

	if ($rslt)
	{
		display($dbg_commit+1,1,"clearing $num remote_changes");
		$repo->{remote_changes} = shared_clone({});
		setCanPush($repo);
		apps::gitUI::Frame::monitor_callback({ repo=>$repo })
			if getAppFrame();
	}

	display($dbg_push,1,"gitPush() returning rslt="._def($rslt));
	return $rslt;
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
	return $repo->repoError("Could not create git_repo") if !$git_repo;

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
		context_lines => 3,
		prefix => {
			a => $is_staged ? 'index' : 'work' ,
			b => $is_staged ? 'HEAD'  : 'index' }};

	$opts->{tree} = getTree($repo, $git_repo, 'HEAD')
		if $is_staged;

	my $diff = $git_repo->diff($opts);
	return $repo->repoError("Could not do diff()") if !$diff;

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




1;
