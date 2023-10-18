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

my $TEST_JUNK_ONLY = 1;
	# limits canCommit and canPush to /junk

my $MAX_SHOW_CHANGES = 30;


my $dbg_new = 1;
	# ctor
my $dbg_config = 1;
	# 0 show header in checkConfig
	# -1 = show details in checkConfig

my $dbg_chgs:shared = 0;
my $dbg_commit:shared = 0;
my $dbg_push:shared = 0;
my $dbg_tag:shared = 0;

my $dbg_creds:shared = 0;
	# push credentials callback
my $dbg_cb:shared = 0;
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
	my $this = shared_clone({
		num 	=> $num,
		path 	=> $path,
		id      => repoPathToId($path),
		section => $section,
		branch	=> $branch || 'master',

		private  => 0,						# if PRIVATE in file
		forked   => 0,						# if FORKED [optional_blah] in file
		selected => 0,						# if selected for commit, tag, push
		parent   => '',						# "Forked from ..." or "Copied from ..."
		descrip  => '',						# description from github
		uses 	 => shared_clone([]),		# a list of the repositories this repository USES
		needs	 => shared_clone([]),       # a list of the abitrary dependencies this repository has
		friend   => shared_clone([]),       # a hash of repositories this repository relates to or can use
		group    => shared_clone([]),       # a list of arbitrary groups that this repository belongs to
		local_changes =>  shared_clone([]),	# list of lines of change text matching 'local: ...'
		remote_changes => shared_clone([]),	# list of lines of change text matching 'remote: ...'
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
	return 0;
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
	return @{$this->{local_changes}} + @{$this->{remote_changes}};
}
sub canCommit
{
	my ($this) = @_;
	return 0 if $TEST_JUNK_ONLY && $this->{path} !~ /junk/;
	return @{$this->{local_changes}};
}
sub canPush
{
	my ($this) = @_;
	return 0 if $TEST_JUNK_ONLY && $this->{path} !~ /junk/;
	return @{$this->{remote_changes}};
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

    if (!(-d $path))
    {
        $this->repoError("validateGitConfig($path) path not found");
        return;
    }

    my $git_config_file = "$path/.git/config";
    my $text = getTextFile($git_config_file);
    if (!$text)
    {
        $this->repoError("checkGitConfig($path) could not open .git/config");
        return;
    }

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



#--------------------------------------------
# gitCommit
#--------------------------------------------


sub gitCommit
	# callback gets $path, $pattern
	# callback returns -1 to abort, 0 to add, 1 to skip
	# git add -A
	# git commit  -m \"$msg\"
{
	my ($this,$call_back,$msg) = @_;
	display($dbg_commit,0,"gitCommit($this->{path}) msg='$msg'");
	my $git_repo = Git::Raw::Repository->open($this->{path});
	return $this->repoError("Could not create git_repo") if !$git_repo;

	# build the add_opts

	my $add_opts = { paths => ['*']};
	$add_opts->{notification} = $call_back if $call_back;

	# add files to the repository default index

	my $index = $git_repo->index();
	$index->add_all($add_opts);
	$index->write;

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
	display($dbg_commit,0,"gitCommit() returning $commit");
	return 1;
}



#--------------------------------------------
# gitChanges
#--------------------------------------------

sub gitChanges
{
	my ($this) = @_;
	display($dbg_chgs,0,"getChanges($this->{path})");
	my $git_repo = Git::Raw::Repository->open($this->{path});
	return $this->repoError("Could not create git_repo") if !$git_repo;

	$this->{local_changes} = shared_clone([]);
	$this->{remote_changes} = shared_clone([]);
	return if !$this->getLocalChanges($git_repo);
	return if !$this->getRemoteChanges($git_repo);
	return $this->hasChanges();
}


sub getLocalChanges
	# git status -s
{
	my ($this,$git_repo) = @_;
	display($dbg_chgs,0,"getLocalChanges($this->{path})");

	my $opts = { flags => { include_untracked => 1 }};
	my $status = $git_repo->status($opts);
	return $this->repoError("No result from git_status")
		if !$status;

	my $num_changes = keys %$status;
	display($dbg_chgs,2,"local:  $num_changes changed files")
		if $num_changes > $MAX_SHOW_CHANGES;

	for my $fn (sort keys %$status)
	{
		my $change .= "$fn ";
		my $values = $status->{$fn};
		my $flags = $values->{flags};
		for my $flag (@$flags)
		{
			$change .= "$flag;";
		}
		display($dbg_chgs,2,"local: $change")
			if $num_changes <= $MAX_SHOW_CHANGES;
		push @{$this->{local_changes}},$change;
	}

	return 1;
}


sub getRemoteChanges
	# git diff $branch origin/$branch --name-status
{
	my ($this,$git_repo) = @_;
	my $branch = $this->{branch};
	display($dbg_chgs,0,"getRemoteChanges($this->{path}) branch=$branch");

	my $ref_remote = Git::Raw::Reference->lookup("origin/$branch", $git_repo);
	return $this->repoError("Could not get ref_remote($branch)")
		if !$ref_remote;

	my $id_remote = $ref_remote->target();
	return $this->repoError("Could not get id_remote($branch)")
		if !$id_remote;

	my $commit = Git::Raw::Commit->lookup($git_repo,$id_remote);
	return $this->repoError("Could not get commit($id_remote)")
		if !$commit;

	my $tree = $commit->tree();
	return $this->repoError("Could not get tree($commit)")
		if !$tree;

	my $diff = $git_repo->diff({ tree => $tree });
	return $this->repoError("Could not get diff($tree)")
		if !$diff;

	my $text = $diff->buffer("name_status");
	return $this->repoError("Could not get diff text($diff)")
		if !defined($text);

	$text =~ s/^\s+|\s$//g;
	return 1 if !$text;

	my @changes = split(/\n/,$text);
	my $num_changes = @changes;
	display($dbg_chgs,2,"remote: $num_changes changed files")
		if $num_changes > $MAX_SHOW_CHANGES;

	for my $change (sort @changes)
	{
		display($dbg_chgs,2,"remote: $change")
			if $num_changes <= $MAX_SHOW_CHANGES;
		push @{$this->{remote_changes}},$change;
	}

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
	display($dbg_push,0,"gitPush($this->{path},$branch)".
		") user_obj("._def($user_obj).
		") user_cb("._def($user_cb).")");

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

	display($dbg_push,1,"gitPush() returning rslt="._def($rslt));
	return $rslt;
}














1;
