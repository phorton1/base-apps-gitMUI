#----------------------------------------------------
# base::apps::gitUI::repo
#----------------------------------------------------
# Facilitates a UI with repoDisplay, repoError,
# repoWarning, and repoNote methods, which can
# yet can be used without including WX.

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
		repoDisplay
		repoError
		repoWarning
		repoNote

		setRepoUI
	);
}



my $repo_ui;

sub setRepoUI { $repo_ui = shift; }
	# call with undef, or an object that supports
	# display, error, and warning


#---------------------------
# ctor
#---------------------------
# Before the introduction of submodules, there was a one-to-one
# correspondence between the path of a repo and it's id on github.
# When constructing a repo for a submodule, the ctor takes three
# additional parameters:
#
#	the parent_repo
#	the relative path of the submodule within the parent
#	the path to the (master) copy of the submodule (for the github id)
#
# The presence of {parent_repo} or {rel_path} indicates it is a submodule.
# submodules add the following to OTHER repos in parseRepos"
#
#		parent repo - gets {submodules} with the submodule's paths
#		master_module - gets {used_in} with all submodule paths that denormalize it
#
# For MY submodules, the branch is always 'master'.
#
# Submodules inherit their parents 'private' bits, which
# must be declared BEFORE the SUBMODULE statement, and
# are always assumed to be 'mine'.


sub new
{
	my ($class, $num, $path, $branch, $section_path, $section_name, $parent_repo, $rel_path, $submodule_path) = @_;
	$branch ||= 'master';
	$section_name ||= $section_path;

	display($dbg_new,0,"repo->new($num, $path, $branch, $section_path, $section_name,)");

	my $this = shared_clone({

		# main fields

		num 	=> $num,
		path 	=> $path,
		id      => repoPathToId($submodule_path || $path),
		branch	=> $branch,

		section_path => $section_path,
		section_name => $section_name,

		# TODO WIP status fields always exist
		# currently set in reposGithub.pm but
		# probably should be moved to repoGit()
		# and called during parseRepos().

		HEAD_ID 	=> '',
		MASTER_ID 	=> '',
		REMOTE_ID 	=> '',
		GITHUB_ID 	=> '',

		AHEAD		=> 0,
		behind  	=> 0,

		# parsed fields
		# PRIVATE is inherited for submdules

		mine     => 1,						# if !FORKED && !NOT_MINE in file
		private  => $parent_repo ? $parent_repo->{private} : 0,
		forked   => 0,						# if FORKED [optional_blah] in file
		parent   => '',						# "Forked from ..." or "Copied from ..."
		descrip  => '',						# description from github
		size	 => 0,						# size in KB from github

		# parsed fields added as necessary
		#
		# page_header => 0,					# PAGE_HEADER for ordered documents
		# docs     => shared_clone([]),		# MD documents in particular order
		# uses 	 => shared_clone([]),		# a list of the repositories this repository USES
		# used_by  => shared_clone([]),		# list of repositorie sthat use this repository
		# needs	 => shared_clone([]),       # a list of the abitrary dependencies this repository has
		# friend   => shared_clone([]),       # a hash of repositories this repository relates to or can use
		# group    => shared_clone([]),       # a list of arbitrary groups that this repository belongs to

		# these arrays always exist

		errors   => shared_clone([]),
		warnings => shared_clone([]),
		notes 	 => shared_clone([]),

		# change arrays always exist

		unstaged_changes => shared_clone({}),	# changes pending Add
		staged_changes   => shared_clone({}),	# changes pending Commit
		remote_changes   => shared_clone({}),	# changes pending Push

		# temporary fields added as necessary
		# by various methods

		# found_on_github => 0,

	});


	# optional fields

	if ($parent_repo)
	{
		$this->{parent_repo} = $parent_repo;
		$this->{rel_path}	 = $rel_path;
		# $this->{submodules} = shared_clone([]);
		# $this->{used_in}	  = shared_clone([]);
	}

	# added at runtime by various methods
	#

	#



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

sub repoDisplay
	# accepts a WX Color, not for use by Utils::display
{
	my ($dbg,$indent,$msg,$color) = @_;
	$repo_ui->do_display($dbg,$indent,$msg,$color)
		if $repo_ui;
	display($dbg,$indent,$msg,1);
}
sub repoError
{
	my ($this,$msg) = @_;
	my $show_path = $this ? "repo($this->{path}): " : '';
	$repo_ui->do_error($show_path.$msg)
		if $repo_ui;
	error($show_path.$msg,1); # ,$repo_ui);
		# $repo_ui == supress_show
	push @{$this->{errors}},$msg if $this;
	return undef;
}
sub repoWarning
{
	my ($this,$dbg_level,$indent,$msg) = @_;
	my $show_path = $this ? "repo($this->{path}): " : '';
	$repo_ui->do_warning($dbg_level,$indent,$show_path.$msg)
		if $repo_ui;
	warning($dbg_level,$indent,$show_path.$msg,1);
	push @{$this->{warnings}},$msg if $this;
}
sub repoNote
{
	my ($this,$dbg_level,$indent,$msg) = @_;
	my $show_path = $this ? "repo($this->{path}): " : '';
	$repo_ui->do_display($dbg_level,$indent,$show_path.$msg,$color_white)
		if $repo_ui;
	display($dbg_level,$indent,$show_path.$msg,1,$UTILS_COLOR_WHITE);
	push @{$this->{notes}},$msg if $this;
}


sub unused_hasChanges
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



sub pathWithinSection
	# for display only
{
	my ($this) = @_;
	my $MAX_DISPLAY_PATH = 28;
		# not including elipses

	# submodules show ++ name
	my $path = $this->{parent_repo} ?
		"++ $this->{rel_path}" :
		$this->{path};

	my $re = $this->{section_path};
	$re =~ s/\//\\\//g;
	$path =~ s/^$re//;
	$path ||= $this->{path};

	$path = '...'.substr($path,-$MAX_DISPLAY_PATH)
		if length($path) >= $MAX_DISPLAY_PATH;
	return $path;
}



#------------------------------------------
# check git/.config files
#------------------------------------------
# Submodules are handled slightly differently.
# The .git/config file is located in the parent repo at
#
#	{parent_path}/.git/modules/{rel_path}/config
#
# And, of course, the url in the [remote] section
# maps to/gives the id of the master module.
#
# There are other files we *could* check for submodules:
#
#	{parent_path}/.gitmodules
#
#		[submodule "copy_sub1"]
#			path = copy_sub1
#			url = https://github.com/phorton1/junk-test_repo-test_sub1
#
#	{parent_patah}/{rel_path}/.git (is a file)
#
#		 gitdir: ../.git/modules/copy_sub1
#
# but we don't.

sub checkGitConfig
	# For every repo, validate that
	#
	# - config file exists
	# - it has exactly one [remote "origin"]
	# - that the remote origin points to our repository
	# - it has a [branch "blah"] that matches $this->{branch}
	# - that the repos' {branch} has "remote = origin"
	#
	# Note any additional branches
{
    my ($this) = @_;

	my $path = $this->{path};
    display($dbg_config+1,0,"checkGitConfig($path)");

    if (!(-d $path))
	{
		$this->repoError("validateGitConfig($path) path not found");
		return 0;
	}

	my $rel_path = $this->{rel_path};
	my $parent_repo = $this->{parent_repo};
    my $git_config_file = "$path/.git/config";

	if ($parent_repo)
	{
		$git_config_file =
			"$parent_repo->{path}/.git/modules/".
			$this->{rel_path}."/config";
	}

    my $text = getTextFile($git_config_file);
	if (!$text)
	{
		$this->repoError("checkGitConfig($path) no text in $git_config_file");
		return 0;
	}

	my $branch;
	my $errors = 0;
	my $has_url = 0;
    my $remote_count = 0;
	my $has_remote_origin = 0;
    my $has_branch_master = 0;
	my $master_has_origin = 0;

	my $in_remote = 0;
	my $in_branch = 0;
	my $in_submodule = 0;

    for my $line (split(/\n/,$text))
    {
		$line =~ s/^\s+|\s+$//g;

		if ($line =~ /^\[/)
		{
			$in_remote = 0;
			$in_branch = 0;
			$in_submodule = 0;
		}

		if ($line =~ /^\[remote \"(.*)"\]/)
        {
            my $remote = $1;
			display($dbg_config+1,1,"remote = $remote");

			$in_remote = 1;
			if ($remote eq 'origin')
			{
				$has_remote_origin = 1;
			}
			else
			{
				$errors++;
				$this->repoError("checkGitConfig($path) remote($remote) != origin");
			}
			if ($remote_count++)
			{
				$errors++;
				$this->repoError("checkGitConfig($path) has more than one remote");
			}
		}
		elsif ($line =~ /^\[branch \"(.*)"\]/)
        {
            $branch = $1;
			display($dbg_config+1,1,"branch = $branch");

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


		elsif ($in_branch && $line =~ /^remote = (.*)$/)
		{
			my $remote = $1;
			display($dbg_config+1,1,"branh($branch) remote = $remote");
			if ($remote ne 'origin')
			{
				$errors++;
				$this->repoError("checkGitConfig($path) branch($branch) has remote($remote)");
			}
			elsif ($branch eq $this->{branch})
			{
				$master_has_origin = 1;
			}
		}


		elsif ($in_remote && $line =~ /^url = (.*)$/)
		{
			my $url = $1;
			display($dbg_config+1,1,"url = $url");

			if ($url !~ s/^https:\/\/github.com\/phorton1\///)
			{
				$errors++;
				$this->repoError("checkGitConfig($path) invalid remote url: $url");
			}

			# the .git extension on the url is optional
			# for submodules we map github id (from the url) to a
			# repo path and make sure it exists.

			else
			{
				$url =~ s/\.git$//;

				if ($this->{parent_repo})
				{
					my $sub_path = repoIdToPath($url);
					# no warnings 'once';
					if (!apps::gitUI::repos::getRepoById($url))
					{
						$errors++;
						$this->repoError("checkGitConfig($path) could not find master module for remote url: $url==$sub_path");
					}
				}

				elsif ($url ne $this->{id})
				{
					$errors++;
					$this->repoError("checkGitConfig($path) incorrect remote url: $url != $this->{id}");
				}
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
	if (!$master_has_origin)
	{
		$errors++;
		$this->repoError("checkGitConfig($path) Could not find remote = origin for [branch \"$this->{branch}\"]");
	}

	return !$errors;
		# return value is currently ignored in only caller: reposGitHub

}   # checkGitConfig()



#---------------------------------------
# toTextCtrl()
#---------------------------------------

sub contentLine
{
	my ($this,$text_ctrl,$bold,$key,$extra_key) = @_;
	my $label = $extra_key || $key;

	my $value = $this->{$key} || '';
	return if !defined($value) || $value eq '';

	$value = $value->{path} if $key eq 'parent_repo';
	$value = repoIdToPath($value)
		if $extra_key && $extra_key eq 'main_module';

	my $context;
	$context = { repo_path => $value } if
		$key eq 'path' ||
		$key eq 'parent_repo' ||
		($extra_key && $extra_key eq 'main_module');

	my $line = $text_ctrl->addLine();
	$text_ctrl->addPart($line, 0, $color_black, pad($label,12)." = " );
	$text_ctrl->addPart($line, $bold, $color_blue, $value, $context );
}


sub contentArray
{
	my ($this,$text_ctrl,$bold,$key,$color) = @_;
	$color ||= $color_blue;
	my $array = $this->{$key};
	return '' if !$array || !@$array;

	$text_ctrl->addSingleLine($bold, $color_black, $key);
	for my $item (@$array)
	{
		my $value = $item;

		my $context;
		$context = { repo=>$this, file=>$value } if $key eq 'docs';
		$context = { repo_path => $value } if
			$key eq 'uses' ||
			$key eq 'used_by' ||
			$key eq 'submodules' ||
			$key eq 'used_in';

		my $line = $text_ctrl->addLine();
		$text_ctrl->addPart($line, 0, $color_black, pad('',10));
		$text_ctrl->addPart($line, $bold, $color, $value, $context);
	}
}


sub addTextForNum
{
	my ($this,$text,$field_name,$show_field) = @_;
	$show_field ||= $field_name;
	my $num = $this->{$field_name};
	if ($num)
	{
		$text .= ' ' if $text;
		$text .= "$show_field($num)";
	}
	return $text;
}

sub addTextForHashNum
{
	my ($this,$text,$field_name,$show_field) = @_;
	my $hash = $this->{$field_name};
	my $num = keys %$hash;
	if ($num)
	{
		$text .= ' ' if $text;
		$text .= "$show_field($num)";
	}
	return $text;
}



sub toTextCtrl
{
	my ($this,$text_ctrl) = @_;
	my $content = [];

	$text_ctrl->addLine();

	$this->contentLine($text_ctrl,1,'path');
	$this->contentLine($text_ctrl,1,'id');

	my $short_status = '';
	$short_status = $this->addTextForHashNum($short_status,'unstaged_changes',"UNSTAGED");
	$short_status = $this->addTextForHashNum($short_status,'staged_changes',"STAGED");
	$short_status = $this->addTextForHashNum($short_status,'remote_changes',"REMOTE");
	$short_status = $this->addTextForNum($short_status,'AHEAD');
	$short_status = $this->addTextForNum($short_status,'BEHIND');

	if ($short_status)
	{
		$short_status = pad('status',12)." = ".$short_status;
		$text_ctrl->addSingleLine(1, $color_black, $short_status);
		$text_ctrl->addLine();
	}

	$this->contentLine($text_ctrl,1,'id','main_module') if $this->{parent_repo};
	$this->contentLine($text_ctrl,1,'parent_repo');
	$this->contentLine($text_ctrl,1,'rel_path');
	$this->contentLine($text_ctrl,0,'num');
	$this->contentLine($text_ctrl,0,'branch');
	$this->contentLine($text_ctrl,0,'section_name');
	$this->contentLine($text_ctrl,0,'section_path');
	$this->contentLine($text_ctrl,1,'private');
	$this->contentLine($text_ctrl,1,'mine');
	$this->contentLine($text_ctrl,0,'forked');
	$this->contentLine($text_ctrl,0,'parent');
	$this->contentLine($text_ctrl,0,'descrip');
	$this->contentLine($text_ctrl,0,'page_header');

	if (1)
	{
		$text_ctrl->addLine();
		$this->contentLine($text_ctrl,1,'HEAD_ID');
		$this->contentLine($text_ctrl,1,'MASTER_ID');
		$this->contentLine($text_ctrl,1,'REMOTE_ID');
		$this->contentArray($text_ctrl,0,'local_commits');
			# TODO this is an array of object with sha, msg, and time
	}

	$this->contentArray($text_ctrl,0,'submodules');
	$this->contentArray($text_ctrl,0,'used_in');

	$this->contentArray($text_ctrl,0,'docs');
	$this->contentArray($text_ctrl,0,'uses');
	$this->contentArray($text_ctrl,0,'used_by');

	$this->contentArray($text_ctrl,0,'needs');
	$this->contentArray($text_ctrl,0,'friend');
	$this->contentArray($text_ctrl,0,'group')
	;
	$this->contentArray($text_ctrl,1,'errors',$color_red);
	$this->contentArray($text_ctrl,1,'warnings',$color_yellow);
	$this->contentArray($text_ctrl,0,'notes');

	$text_ctrl->addLine();
}


1;
