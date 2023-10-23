#----------------------------------------------------
# base::apps::gitUI::repo
#----------------------------------------------------
# The client must implement ABORT.
# To abort a PUSH, the push must be in a thread
# 		and the user should kill the thread.

package apps::gitUI::repo;
use strict;
use warnings;
use threads;
use threads::shared;
use Time::HiRes qw(sleep);
use Git::Raw;
use Pub::Utils;
use apps::gitUI::git;

our $TEST_JUNK_ONLY = 0;
	# limits visible repos to /junk

my $MAX_SHOW_CHANGES = 30;


my $dbg_new = 1;
	# ctor
my $dbg_config = 1;
	# 0 show header in checkConfig
	# -1 = show details in checkConfig

my $dbg_chgs = 1;
my $dbg_add = 0;
my $dbg_commit = 0;
my $dbg_push = 0;
my $dbg_tag = 0;

my $dbg_creds = 0;
	# push credentials callback
my $dbg_cb = 1;
	# push callbacks


my $CREDENTIAL_FILENAME = '/dat/Private/git/git_credentials.txt';


# PUSH callbacks
#
# PACK is called first, stage is 0 on first, 1 thereafter
# 	when done, $total = the number of objects for the push
# TRANSFER show the current, and total objects and bytes
#   transferred thus far.
# REFERENCE is the last (set of) messages as git updates
#   the local repository's origin/$branch to the HEAD.
#   There could be multiple, but I usually only see one.
#   The push is complete when REFERENCE $msg is undef.
#
# NEGOTIATE is not seen in my usages
# SIDEBAND (Resolving deltas) had too many problems,
#   very quick, so I don't use it.

our $PUSH_CB_ERROR      = -1;		# $msg
our $PUSH_CB_PACK		= 0;		# $stage, $current, $total
our $PUSH_CB_TRANSFER	= 1;		# $current, $total, $bytes
our $PUSH_CB_REFERENCE  = 2;		# $ref, $msg



# The callback method is of the form
#
#     push_callback($object, $CB, $repo, $params...)
#
# We specifically use non-shared global variables to
# hold the users $object and $repo so that it should
# work with multiple simulatneous threaded pushes



BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(

		$TEST_JUNK_ONLY

		setRepoQuiet

		$PUSH_CB_ERROR
		$PUSH_CB_PACK
        $PUSH_CB_TRANSFER
        $PUSH_CB_REFERENCE
	);
}



my $repo_quiet:shared = 0;

sub setRepoQuiet { $repo_quiet = shift; }
	# turns off repoErrors, repoWarnings, and repoNotes
	# for calling from gitUI windows without reporting
	# those kinds of errors

my $git_user:shared = '';
my $git_api_token:shared = '';
my $credential_error = 0;

my $push_cb;
my $push_cb_object;
my $push_cb_repo;



#---------------------------
# ctor
#---------------------------

sub new
{
	my ($class, $num, $section, $path, $branch) = @_;
	$branch ||= 'master';
	my $this = shared_clone({
		num 	=> $num,
		path 	=> $path,
		id      => repoPathToId($path),
		section => $section,
		branch	=> $branch || 'master',

		private  => 0,						# if PRIVATE in file
		forked   => 0,						# if FORKED [optional_blah] in file
		selected => 0,						# if selected for push, tag
		parent   => '',						# "Forked from ..." or "Copied from ..."
		descrip  => '',						# description from github
		uses 	 => shared_clone([]),		# a list of the repositories this repository USES
		needs	 => shared_clone([]),       # a list of the abitrary dependencies this repository has
		friend   => shared_clone([]),       # a hash of repositories this repository relates to or can use
		group    => shared_clone([]),       # a list of arbitrary groups that this repository belongs to
		unstaged_changes => shared_clone({}),	# changes pending Add
		staged_changes   => shared_clone({}),	# changes pending Commit
		remote_changes   => shared_clone({}),	# changes pending Push
		errors   => shared_clone([]),
		warnings => shared_clone([]),
		notes 	 => shared_clone([]), });
	display($dbg_new,0,"repo->new($num,$section,$path,$branch)");
	bless $this,$class;
	return $this;
}



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


#----------------------------
# accessors
#----------------------------

sub clearErrors
{
	my ($this) = @_;
	$this->{errors}   = shared_clone([]);
	$this->{warnings} = shared_clone([]);
	$this->{notes} = shared_clone([]);
}


sub repoError
{
	my ($this,$msg,$call_level) = @_;
	$call_level ||= 0;
	$call_level++;
	error("repo($this->{path}): ".$msg,$call_level)
		if !$repo_quiet;
	push @{$this->{errors}},$msg;
	return undef;
}

sub repoWarning
{
	my ($this,$dbg_level,$indent,$msg,$call_level) = @_;
	$call_level ||= 0;
	$call_level++;
	warning($dbg_level,$indent,"repo($this->{path}): ".$msg,$call_level)
		if !$repo_quiet;
	push @{$this->{warnings}},$msg;
}


sub repoNote
{
	my ($this,$dbg_level,$indent,$msg,$call_level,$color) = @_;
	$call_level ||= 0;
	$call_level++;
	$color |= $display_color_white;
	display($dbg_level,$indent,"repo($this->{path}): ".$msg,$call_level,$color)
		if !$repo_quiet;
	push @{$this->{notes}},$msg;
}



sub hasChanges
{
	my ($this) = @_;
	return
		scalar(keys %{$this->{unstaged_changes}}) +
		scalar(keys %{$this->{staged_changes}}) +
		scalar(keys %{$this->{remote_changes}});
}
sub canAdd
{
	my ($this) = @_;
	# return 0 if $TEST_JUNK_ONLY && $this->{path} !~ /junk/;
	return scalar(keys %{$this->{unstaged_changes}});
}
sub canCommit
{
	my ($this) = @_;
	# return 0 if $TEST_JUNK_ONLY && $this->{path} !~ /junk/;
	return scalar(keys %{$this->{staged_changes}});
}
sub canPush
{
	my ($this) = @_;
	# return 0 if $TEST_JUNK_ONLY && $this->{path} !~ /junk/;
	return scalar(keys %{$this->{remote_changes}});
}




#------------------------------------------
# check git/.config files
#------------------------------------------

sub checkGitConfig
	# ugh.  Validate
	#
	# - config file exists
	# - it has exactly one [remote "origin"] that points to our repository
	# - it has a [branch "blah"] that matches $this->{branch}
	# - that all braches have "remote = origin"
	#
	# Note any additional branches
{
    my ($this) = @_;

	my $path = $this->{path};
    display($dbg_config+1,0,"checkGitConfig($path)");

    return $this->repoError("validateGitConfig($path) path not found")
		if !(-d $path);

    my $git_config_file = "$path/.git/config";
    my $text = getTextFile($git_config_file);
    return $this->repoError("checkGitConfig($path) no text in .git/config")
		if !$text;


	my $branch;
	my %branches;
	my $errors = 0;
	my $has_url = 0;
    my $remote_count = 0;
	my $has_remote_origin = 0;
    my $has_branch_master = 0;

	my $in_remote = 0;
	my $in_branch = 0;

    for my $line (split(/\n/,$text))
    {
		$line =~ s/^\s+|\s+$//g;
		if ($line =~ /^\[remote \"(.*)"\]/)
        {
            my $remote = $1;
			display($dbg_config+1,1,"remote = $remote");

			$remote_count++;
			$in_remote = 1;
			$in_branch = 0;
			if ($remote eq 'origin')
			{
				$has_remote_origin = 1;
			}
			else
			{
				$errors++;
				$this->repoError("checkGitConfig($path) remote($remote) != origin");
			}
		}
		elsif ($line =~ /^\[branch \"(.*)"\]/)
        {
            $branch = $1;
			display($dbg_config+1,1,"branch = $branch");

			$branches{$branch} = '';
			$in_remote = 0;
			$in_branch = 1;
			if ($branch eq $this->{branch})
			{
				$has_branch_master = 1;
			}
			else
			{
				$this->repoNote($dbg_config,1,"$git_config_file: branch($branch) != master");
			}
        }
		elsif ($line =~ /^\[/)
		{
			$in_remote = 0;
			$in_branch = 0;
		}
		elsif ($line =~ /^url = (.*)$/)
		{
			my $url = $1;
			display($dbg_config+1,1,"url = $url");

			if (!$in_remote)
			{
				$errors++;
				$this->repoError("checkGitConfig($path) url= outside of [remote]: $url");
			}
			elsif ($url !~ s/^https:\/\/github.com\/phorton1\///)
			{
				$errors++;
				$this->repoError("checkGitConfig($path) invalid url: $url");
			}

			# the .git extension on the url is optional

			else
			{
				$url =~ s/\.git$//;
				if ($url ne repoPathToId($path))
				{
					$errors++;
					$this->repoError("checkGitConfig($path) incorrect url: $url != ".repoPathToId($path));
				}
			}
		}
		elsif ($line =~ /^remote = (.*)$/)
		{
			my $remote = $1;
			display($dbg_config+1,1,"branh($branch) remote = $remote");
			if (!$in_branch)
			{
				$errors++;
				$this->repoError("checkGitConfig($path) remote= outside of [branch]: $remote");
			}
			elsif ($remote ne 'origin')
			{
				$errors++;
				$this->repoError("checkGitConfig($path) branch($branch) has remote($remote)");
			}
			else
			{
				$branches{$branch} = $remote;
			}
		}
	}

	if (!$has_remote_origin)
	{
		$errors++;
		$this->repoError("checkGitConfig($path) Could not find [remote \"origin\"]");
	}
	if (!$has_branch_master)
	{
		$errors++;
		$this->repoError("checkGitConfig($path) Could not find [branch \"$this->{branch}\"]");
	}
	for my $br (sort keys %branches)
	{
		if ($branches{$br} ne 'origin')
		{
			$errors++;
			$this->repoError("checkGitConfig($path) branch($br) remote($branches{$br}) != 'origin'");
		}
	}

	return !$errors;

}   # checkGitConfig()




#--------------------------------------------
# gitChanges
#--------------------------------------------

sub gitChanges
	# returns undef if any problems
	# returns 1 if the any of the hashes of changes has changed
	# returns 0 otherwise
	## places advisory lock on $repo_list during atomic change assignment
{
	my ($this) = @_;
	display($dbg_chgs,0,"getChanges($this->{path})");
	my $git_repo = Git::Raw::Repository->open($this->{path});
	return $this->repoError("Could not create git_repo") if !$git_repo;

	my $changes_changed = 0;

	my $rslt = $this->getLocalChanges($git_repo);
	return if !defined($rslt);
	$changes_changed += $rslt;

	$rslt = $this->getRemoteChanges($git_repo);
	return if !defined($rslt);
	$changes_changed += $rslt;

	display($dbg_chgs,0,"gitChanges($this->{path}) returning $changes_changed");
	return $changes_changed;
}


sub assignHashIfChanged
{
	my ($this,$key,$changes,$changed) = @_;
	my $hash = $this->{$key};
	$changed ||= scalar(keys %$hash) != scalar(keys %$changes);
	if ($changed)
	{
		display($dbg_chgs,0,"assignHashIfChanged($key,$this->{path})");
		my $repo_list = apps::gitUI::repos::getRepoList();
		## lock $repo_list;
		$this->{$key} = $changes;
		return 1;
	}
	return 0;
}



sub getLocalChanges
	# git status -s
{
	my ($this,$git_repo) = @_;
	display($dbg_chgs,0,"getLocalChanges($this->{path})");

	my $opts = { flags => {
		include_untracked => 1,
		recurse_untracked_dirs => 1 }};
	my $status = $git_repo->status($opts);
	return $this->repoError("No result from git_status")
		if !$status;

	my $unstaged_changed = 0;
	my $staged_changed = 0;
	my $unstaged_changes = $this->{unstaged_changes};
	my $staged_changes = $this->{staged_changes};
	my $new_unstaged_changes = shared_clone({});
	my $new_staged_changes = shared_clone({});

	my $num_changes = keys %$status;
	display($dbg_chgs,2,"local:  $num_changes changed files")
		if $num_changes > $MAX_SHOW_CHANGES;

	# I assume that only one flag is given per file

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

			my $what =
				$flag eq 'new' ? "A" :
				$flag eq 'modified' ? "M" :
				$flag eq 'deleted' ? "D" :
				$flag eq 'renamed' ? "R" : "?";

			display($dbg_chgs,2,"$show: $what $fn")
				if $num_changes <= $MAX_SHOW_CHANGES;
			$new_hash->{$fn} = $what;
			$$pbool = 1 if
				!$old_hash->{$fn} ||
				$old_hash->{$fn} ne $new_hash->{$fn};
		}
	}

	my $changes_changed = 0;
	$changes_changed += $this->assignHashIfChanged('unstaged_changes',$new_unstaged_changes,$unstaged_changed);
	$changes_changed += $this->assignHashIfChanged('staged_changes',$new_staged_changes,$staged_changed);
	display($dbg_chgs,0,"getLocalChanges($this->{path}) returning $changes_changed");
	return $changes_changed;
}




sub getTree
	# get a tree for diff/tag
	# $name may be HEAD or origin/$branch
{
	my ($this, $git_repo, $name) = @_;

	my $ref = Git::Raw::Reference->lookup($name, $git_repo);
	return $this->repoError("Could not get ref($name)")
		if !$ref;

	my $id = $ref->target();
	return $this->repoError("Could not get id for ref($name)")
		if !$id;

	# recurse once on $id for HEAD

	if ($name eq 'HEAD')
	{
		$id = $id->target();
		return $this->repoError("Could not get id2 for ref($name)")
			if !$id;
	}

	my $commit = Git::Raw::Commit->lookup($git_repo,$id);
	return $this->repoError("Could not get commit($name) for id($id)")
		if !$commit;

	my $tree = $commit->tree();
	return $this->repoError("Could not get tree($name) from commit($commit)")
		if !$tree;

	return $tree;
}



sub getRemoteChanges
	# git diff $branch origin/$branch --name-status
{
	my ($this,$git_repo) = @_;
	my $branch = $this->{branch};
	display($dbg_chgs,0,"getRemoteChanges($this->{path}) branch=$branch");

	# Get the local HEAD and 'remote' origin/$branch trees

	my $tree_remote = $this->getTree($git_repo, "origin/$branch");
	return if !$tree_remote;

	my $tree_head = $this->getTree($git_repo, "HEAD");
	return if !$tree_head;

	# Diff the Remote tree against HEAD
	# short return if no changes

	my $diff = $tree_remote->diff({ tree => $tree_head });
	return $this->repoError("Could not get diff()")
		if !$diff;

	my $text = $diff->buffer("name_status");
	return $this->repoError("Could not get diff text($diff)")
		if !defined($text);

	$text =~ s/^\s+|\s$//g;
	return 0 if !$text;

	# Split the text into lines and process them
	# Occasionallly I get an asterisk at the end of the filename
	# and I don't knowo aht it means.

	my $remote_changed = 0;
	my $remote_changes = $this->{remote_changes};
	my $new_remote_changes = shared_clone({});

	my @changes = split(/\n/,$text);
	my $num_changes = @changes;
	display($dbg_chgs,2,"remote: $num_changes changed files")
		if $num_changes > $MAX_SHOW_CHANGES;

	for my $change (sort @changes)
	{
		# next if $change =~ /\*$/;
		my ($what,$fn) = split("\t",$change);
		display($dbg_chgs,2,"change($change) remote: $what $fn")
			if $num_changes <= $MAX_SHOW_CHANGES;


		$new_remote_changes->{$fn} = $what;
		$remote_changed = 1 if
			!$remote_changes->{$fn} ||
			$remote_changes->{$fn} ne $new_remote_changes->{$fn};

	}

	my $changes_changed = $this->assignHashIfChanged('remote_changes',$new_remote_changes,$remote_changed);
	display($dbg_chgs,0,"getRemoteChanges($this->{path}) returning $changes_changed");
	return $changes_changed;
}



#--------------------------------------------
# gitAdd
#--------------------------------------------

sub gitAdd
	# git add -A
{
	my ($this,$msg) = @_;
	my $num = scalar(keys %{$this->{unstaged_changes}});
	display($dbg_add,0,"gitAdd($this->{path}) $num unstaged_changes");

	my $git_repo = Git::Raw::Repository->open($this->{path});
	return $this->repoError("Could not create git_repo") if !$git_repo;

	# add files to the repository default index

	my $index = $git_repo->index();
	return $this->repoError("Could not get index") if !$index;

	$index->add_all({ paths => ['*']});
	$index->write;

	# move the changes from 'unstaged' to 'staged'

	display($dbg_add+1,1,"moving $num unstaged_changes to staged_changes");
	mergeHash($this->{staged_changes},$this->{unstaged_changes});
	$this->{unstaged_changes} = shared_clone({});

	display($dbg_add,0,"gitCommit() returning 1");
	return 1;
}



#--------------------------------------------
# gitCommit
#--------------------------------------------

sub gitCommit
	# git commit  -m \"$msg\"
{
	my ($this,$msg) = @_;
	my $num = scalar(keys %{$this->{staged_changes}});
	display($dbg_commit,0,"gitCommit($this->{path}) $num staged_changes msg='$msg'");

	my $git_repo = Git::Raw::Repository->open($this->{path});
	return $this->repoError("Could not create git_repo") if !$git_repo;

	my $index = $git_repo->index();
	return $this->repoError("Could not get index") if !$index;

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

	return $this->repoError("Could not create git_commit")
		if !$commit;

	# move the changes from 'staged' to 'remote'

	display($dbg_commit+1,1,"moving $num staged_changes to remote_changes");
	mergeHash($this->{remote_changes},$this->{staged_changes});
	$this->{staged_changes} = shared_clone({});

	display($dbg_commit,0,"gitCommit() returning 1");
	return 1;
}



#-------------------------------------------------------
# gitPush
#-------------------------------------------------------

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
{
	my ($this,$user_obj,$user_cb) = @_;

	$push_cb = $user_cb;
	$push_cb_object = $user_obj;
	$push_cb_repo = $this;

	my $branch = $this->{branch};
	my $num = scalar(keys %{$this->{remote_changes}});
	display($dbg_push,0,"gitPush($branch,$this->{path}) $num remote_chanes)");

	my $git_repo = Git::Raw::Repository->open($this->{path});
	return $this->repoError("Could not create git_repo")
		if !$git_repo;

	my $remote = Git::Raw::Remote->load($git_repo, 'origin');
	return $this->repoError("Could not create remote")
		if !$remote;

	my $refspec_str = "refs/heads/$branch";
	my $refspec = Git::Raw::RefSpec->parse($refspec_str,0);
	return $this->repoError("Could not create refspec($refspec_str)")
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

	if ($rslt)
	{
		display($dbg_commit+1,1,"clearing $num remote_changes");
		$this->{remote_changes} = shared_clone({});
	}
	display($dbg_push,1,"gitPush() returning rslt="._def($rslt));
	return $rslt;
}




#--------------------------------------------
# gitTag
#--------------------------------------------

sub gitTag
{
	my ($this,$tag) = @_;
	display($dbg_tag,0,"gitTag($tag,$this->{path})");
	my $git_repo = Git::Raw::Repository->open($this->{path});
	return $this->repoError("Could not create git_repo") if !$git_repo;

	my $config = $git_repo->config();
	my $name   = $config->str('user.name');
	my $email  = $config->str('user.email');
	display($dbg_tag+1,1,"name($name) email($email)");
	my $sig = Git::Raw::Signature->new($name, $email, time(), 0);

	my $ref = Git::Raw::Reference->lookup("HEAD", $git_repo);
	return $this->repoError("Could not get ref(HEAD)")
		if !$ref;
	my $ref2 = $ref->target();
	my $id = $ref2->target();
	return $this->repoError("Could not get id_remote(HEAD)")
		if !$id;

	print "ref=$ref id=$id\n";

	my $msg = '';
	my $rslt = $git_repo->tag($tag, $msg, $sig, $id );
	display($dbg_tag,0,"gitTag($tag) returning"._def($rslt));

	return $rslt;
}




###########################################
# test main
###########################################


if (0)
{
	my $repo = apps::gitUI::repo->new(0,'',"/junk/junk_repository");
	$repo->gitChanges();
}









1;
