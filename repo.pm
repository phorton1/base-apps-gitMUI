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
use Pub::Utils;
use apps::gitUI::utils;


my $dbg_new = 1;
	# ctor
my $dbg_config = 1;
	# 0 show header in checkConfig
	# -1 = show details in checkConfig


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
	);
}



my $repo_quiet:shared = 0;

sub setRepoQuiet { $repo_quiet = shift; }
	# turns off repoErrors, repoWarnings, and repoNotes
	# for calling from gitUI windows without reporting
	# those kinds of errors


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

		# for tagSelected and pushSelected

		selected => 0,

		# for github.pm

		found_on_github => 0,

		private  => 0,						# if PRIVATE in file
		forked   => 0,						# if FORKED [optional_blah] in file
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
	return scalar(keys %{$this->{unstaged_changes}});
}
sub canCommit
{
	my ($this) = @_;
	return scalar(keys %{$this->{staged_changes}});
}
sub canPush
{
	my ($this) = @_;
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



#---------------------------------------
# toText
#---------------------------------------

sub textLine
{
	my ($this,$key) = @_;
	my $line = pad($key,10)." = ".$this->{$key}."\n";
	return $line;
}

sub arrayText
{
	my ($this,$key) = @_;
	my $array = $this->{$key};
	return '' if !@$array;

	my $text = "$key\n";
	for my $item (@$array)
	{
		$text .= pad('',10).$item."\n";
	}
	return $text;
}

sub toText
{
	my ($this) = @_;
	my $text = '';

	$text .= $this->textLine('num');
	$text .= $this->textLine('branch');
	$text .= $this->textLine('section');
	$text .= $this->textLine('path');
	$text .= $this->textLine('private');
	$text .= $this->textLine('forked');
	$text .= $this->textLine('parent');
	$text .= $this->textLine('descrip');

	$text .= $this->arrayText('uses');
	$text .= $this->arrayText('needs');
	$text .= $this->arrayText('friend');
	$text .= $this->arrayText('group');
	$text .= $this->arrayText('errors');
	$text .= $this->arrayText('warnings');
	$text .= $this->arrayText('notes');

	return $text;
}



sub contentLine
{
	my ($this,$content,$bold,$key) = @_;
	my $value = $this->{$key} || '';
	return if !defined($value) || $value eq '';

	# display(0,0,"contentLine($key,$value)");

	my $content_line = [
		0, $color_black, pad($key,10)." = ",
		$bold, $color_blue, $value ];
	push @$content,$content_line;
}

sub contentArray
{
	my ($this,$content,$bold,$key,$color) = @_;
	$color ||= $color_blue;
	my $array = $this->{$key};
	return '' if !@$array;

	# display(0,0,"contentArray($key)");

	push @$content,[$bold, $color_black,$key];
	for my $item (@$array)
	{
		# display(0,1,"item($item)");
		push @$content,[$bold, $color,pad('',10).$item];
	}
}


sub toContent
{
	my ($this) = @_;
	my $content = [];

	# display_hash(0,0,"toContent($this->{path}",$this);

	push @$content,[0,$color_black,''];

	$this->contentLine($content,1,'path');
	$this->contentLine($content,0,'num');
	$this->contentLine($content,0,'branch');
	$this->contentLine($content,0,'section');
	$this->contentLine($content,1,'private');
	$this->contentLine($content,0,'forked');
	$this->contentLine($content,0,'parent');
	$this->contentLine($content,0,'descrip');

	$this->contentArray($content,0,'uses');
	$this->contentArray($content,0,'needs');
	$this->contentArray($content,0,'friend');
	$this->contentArray($content,0,'group');
	$this->contentArray($content,1,'errors',$color_red);
	$this->contentArray($content,1,'warnings',$color_yellow);
	$this->contentArray($content,0,'notes');

	push @$content,[0,$color_black,''];	# blank line at end

	display(0,0,"toContent returning ".scalar(@$content)." lines");
	return $content;
}








1;
