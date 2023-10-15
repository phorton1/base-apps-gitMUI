#----------------------------------------------------
# base::apps::gitUI::repo
#----------------------------------------------------

package apps::gitUI::repo;
use strict;
use warnings;
use threads;
use threads::shared;
use Time::Hires qw(sleep);
use IPC::Open3;
use Symbol qw(gensym);
use Pub::Utils;
use apps::gitUI::git;


my $dbg_new = 1;
	# ctor
my $dbg_config = 1;
	# 0 show header in checkConfig
	# -1 = show details in checkConfig

my $dbg_git_funcs = 0;
	# debug gitCommit(), gitPush()
my $dbg_git_changes = 1;
	# specific to git_changes - output is appropriate for git_changes.pm

my $dbg_git_calls = 1;
	# 0 = show gitCalls
	# -1 = show gitCallDetails (for $DO_ASYNCH_PUSH)


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
	);
}

my $DO_ASYNCH_PUSH = 0;



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
	my ($this,$msg,$quiet,$call_level) = @_;
	$call_level ||= 0;
	$call_level++;
	error($msg,$call_level) if !$quiet;
	push @{$this->{errors}},$msg;
}

sub repoWarning
{
	my ($this,$dbg_level,$indent,$msg,$quiet,$call_level) = @_;
	$call_level ||= 0;
	$call_level++;
	warning($dbg_level,$indent,$msg,$call_level) if !$quiet;
	push @{$this->{warnings}},$msg;
}


sub repoNote
{
	my ($this,$dbg_level,$indent,$msg,$quiet,$call_level) = @_;
	$call_level ||= 0;
	$call_level++;
	LOG($indent,$msg,$call_level) if !$quiet && $dbg_level <= $debug_level;
	push @{$this->{notes}},$msg;
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




#-------------------------------------------------------
# git CHANGES, COMMIT, TAG, and PUSH
#-------------------------------------------------------
# Some commom git commands:
#
#    diff --name-status
#       or git "status show modified files"
#       shows any local changes to the repo
#    diff master origin/master --name-status","remote differences"
#       show any differences from bitbucket
#    fetch
#       update the local repository from the net ... dangerous?
#    stash
#       stash any local changes
#    update
#       pull any differences from bitbucket
#    add .
#       add all uncommitted changes to the staging area
#    commit  -m "checkin message"
#       calls "git add ." to add any uncommitted changes to the staging area
#       and git $command to commit the changes under the given comment
#    push -u origin master
#       push the repository to bitbucket
#
# TO INITIALIZE REMOTE REPOSITORY
#
#      git remote add origin https://github.com/phorton1/Arduino.git
#
# Various dangerous commands
#
#    git reset --hard HEAD
#    git pull -u origin master



sub hasChanges
{
	my ($this) = @_;
	return @{$this->{local_changes}} || @{$this->{remote_changes}} ? 1 : 0;
}
sub canCommit
{
	my ($this) = @_;
	return @{$this->{local_changes}} ? 1 : 0;
}
sub canPush
{
	my ($this) = @_;
	return @{$this->{remote_changes}} ? 1 : 0;
}





sub gitCall
    # does the given git_command,
    # displays and returns shell text
{
	my ($this,$command) = @_;

    if (!chdir $this->{path})
    {
        error("Could not chdir to '$this->{path}'");
        return;
    }

	my $rslt = '';
	display($dbg_git_calls,0,"calling 'git $command' for($this->{path})");

	my $app_frame = getAppFrame();

	if (!$DO_ASYNCH_PUSH ||
		!$command !~ /^push/ ||
		!$app_frame)
	{
		# $ENV{GIT_REDIRECT_STDERR} = "2>&1";	 # "/junk/stderr.txt";
		# $ENV{GIT_REDIRECT_STDERR} = ">/junk/stderr.txt";

		my $got_sem = waitSTDOUTSemaphore();
		$rslt = `git $command` || '';
		releaseSTDOUTSemaphore() if $got_sem;
	}
	else
	{
		my $child_command = "git $command";
		display($dbg_git_calls,0,"calling open3($child_command)");
		my $pid = open3(\*CHILD_STDIN, \*CHILD_STDOUT, \*CHILD_STDERR, $child_command);

		my $start = time();
		my $last_time = '';
		while (1)	# time() < $start + 30)
		{
			my $buf;
			my $bytes1 = sysread(*CHILD_STDERR,$buf,10000);
			if ($bytes1)
			{
				display($dbg_git_calls+1,1,"buf=$buf",0,$display_color_light_magenta);
				my $aborted = !$app_frame->notifyPushProgress($buf);
				if ($aborted)
				{
					warning($dbg_git_calls+1,1,"gitCall() aborted");
					last;
				}
			}

			last if !$bytes1;

			my $now = time();
			if ($now ne $last_time)
			{
				$last_time = $now;
				display($dbg_git_calls+2,1,"loop(".($now-$start).")");
			}
		}

		my $buf;
		my $bytes0 = sysread(*CHILD_STDOUT,$buf,10000);
		if ($bytes0)
		{
			display($dbg_git_calls+1,1,"buf=$buf",0,$display_color_light_cyan);
			$rslt .= $buf;
		}

		close(*CHILD_STDIN);
		close(*CHILD_STDOUT);
		close(*CHILD_STDERR);
		waitpid($pid, 0);		# I think WNOHANG is 1
	}


    if (defined($rslt))
    {
        $rslt =~ s/\s*$//s;
        display($dbg_git_calls,1,"'git $command' returned rslt=".length($rslt)." bytes");
    }
    else
    {
        error("git '$command' returned undef");
    }
	return $rslt;
}



########################
# gitPush
########################

sub gitPush
	# At the present time, the push works well from a dos box
	# because I get to see the STDOUT or STDERR output in real time
	# with fancy characters ... as well as 'Everything up-to-date' message
{
	my ($this) = @_;
	my $branch = $this->{branch};
	display($dbg_git_funcs,0,"gitPush($this->{path} $branch)");
	my $rslt = $this->gitCall("push --progress -u origin $branch");
	$rslt ||= '';
	display($dbg_git_funcs,0,"gitPush() returning $rslt");
	# instead of this meaningless message
	# Branch 'master' set up to track remote branch 'master' from 'origin'.
}



########################
# gitCommit
########################


sub gitCommit
{
	my ($this,$msg) = @_;
	my $branch = $this->{branch};
	display($dbg_git_funcs,0,"gitCommit($this->{path})");
	$this->gitCall("add -A");
	my $rslt = $this->gitCall("commit  -m \"$msg\"");
	# [master 9c8685f] test commit 1 file changed, 5 insertions(+), 5 deletions(-)
}



########################
# gitChanges
########################

sub gitChanges
{
	my ($this,$for_git_changes_pm) = @_;
	display($dbg_git_changes+1,0,"gitChanges($this->{path})");

	my $started = 0;
	$this->getSpecificChanges(0,\$started,$for_git_changes_pm);
	$this->getSpecificChanges(1,\$started,$for_git_changes_pm);

	my $local_changes = scalar(@{$this->{local_changes}});
	my $remote_changes = scalar(@{$this->{remote_changes}});

	display($dbg_git_changes+1,0,"gitChanges($this->{path}) local($local_changes) remote($remote_changes)")
		if $local_changes || $remote_changes;
}


sub getSpecificChanges
{
	my ($this,$local,$pstarted,$for_git_changes_pm) = @_;

	my $path = $this->{path};
	my $branch = $this->{branch};
	my $key = $local ? 'local_changes' : 'remote_changes';

	# THIS DOES NOT SHOW unstaged files that would be added
	# $chg->{local_diff} = git_call($dbg_git,2,$project,"diff --name-status");
	# so I changed to "status -s  == 'show status concisely'
	# which returns ?? for Additions, which I then map to ' A'

	my $command = $local ?
		"status -s" :
		"diff $branch origin/$branch --name-status";
	my $text = $this->gitCall($command);
	$text =~ s/\?\?/ A/g if $local;

	# parse returned lines

	for my $line (split(/\n/,$text))
    {
        $line ||= '';
        $line =~ s/\s|$//;

		if ($line)
		{
			my $array = $this->{$key};
			my $use_dbg = $for_git_changes_pm ? 0 : $dbg_git_changes;

			if (!$$pstarted)
			{
				$$pstarted = 1;
				display($use_dbg,0,"gitChanges($this->{path})");
			}

			display($use_dbg,1,($local?"local:  ":"remote: ").$line);

			push @$array,$line;
		}
	}
}


if (0)
{
	my $repo = apps::gitUI::repo->new(0,'',"/junk/junk_repository",'master');
	#$repo->gitChanges();
	$repo->gitPush();
}



1;
