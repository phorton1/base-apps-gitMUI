
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
use Pub::Prefs;
use apps::gitUI::Resources;
use apps::gitUI::utils;


my $dbg_new = 1;
	# ctor
my $dbg_config = 1;
	# 0 show header in checkConfig
	# -1 = show details in checkConfig
my $dbg_can_commit = 0;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		repoDisplay
		repoError
		repoWarning
		repoNote

		setRepoUI

		$REPO_LOCAL
		$REPO_REMOTE
	);
}


our $REPO_LOCAL = 1;
our $REPO_REMOTE = 2;
	# bitwise "exists" members

my $repo_ui;

sub setRepoUI { $repo_ui = shift; }
	# call with undef, or an object that supports
	# display, error, and warning


sub isLocal
{
	my ($this) = @_;
	return $this->{exists} & $REPO_LOCAL ? 1 : 0;
}
sub isRemote
{
	my ($this) = @_;
	return $this->{exists} & $REPO_REMOTE ? 1 : 0;
}
sub isLocalOnly
{
	my ($this) = @_;

	# initial implementation is a little kludgy.
	# we allow submodules that don't per-se, have
	# a repo on github. I'm not sure where to best
	# encapsulate this.

	return !$this->{parent_repo} &&
		$this->{exists} == $REPO_LOCAL ? 1 : 0;
}
sub isRemoteOnly
{
	my ($this) = @_;
	return $this->{exists} == $REPO_REMOTE ? 1 : 0;
}
sub isLocalAndRemote
{
	my ($this) = @_;
	return $this->{exists} == ($REPO_LOCAL|$REPO_REMOTE) ? 1 : 0;
}



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
# submodules add the following to OTHER repos in parseRepos:
#
#		parent repo - gets {submodules} with the submodule's paths
#		master_module - gets {used_in} with all submodule paths that denormalize it
#
# For MY submodules, the branch is always 'master'.
#
# Submodules inherit their parents 'private' bits, which
# must be declared BEFORE the SUBMODULE statement, and
# are always assumed to be 'mine'.


use Git::Raw;

sub getId
{
	my ($this) = @_;

	my ($id,$branch) = ('','');

	my $path = $this->{path};
	my $git_repo = Git::Raw::Repository->open($path);
	if ($git_repo)
	{
		my $head = $git_repo->head();
		$branch = $head->shorthand();

		display($dbg_new,0,"branch($path) = $branch");

		my $remote = Git::Raw::Remote->load($git_repo, 'origin');
		if ($remote)
		{
			my $url = $remote->url();
			my $user = getPref("GIT_USER");
			if ($url =~ s/https:\/\/github.com\/$user\///)
			{
				$id = $url;
				$id =~ s/\.git$//;
				display($dbg_new,0,"getId($path) = $id");
			}
			else
			{
				return repoError($this,"Unexpected remote url($id)");
			}
		}
		else
		{
			repoWarning($this,0,0,"Could not get remote($path)");

			# we are going to return a slash/dash substituted id
			# for this repo, but it probably match sections

			$id = $this->{path};
			$id =~ s/\//-/g;
		}
	}
	else
	{
		repoError($this,"Could not open git_repo($path)");
	}
	return ($branch,$id);
}


sub new
{
	my ($class, $where, $num, $path, $section_path, $section_id, $parent_repo, $rel_path, $submodule_path) = @_;

	$section_id ||= $section_path;
	$section_id =~ s/\//-/g;
	$section_id =~ s/^-//;

	display($dbg_new,0,"repo->new($num, $path, $section_path, $section_id,)");

	my $this = shared_clone({

		# main fields

		num 	=> $num,
		exists  => $where,
		path 	=> $path,
		branch	=> '',
		default_branch => '',

		section_path => $section_path,
		section_id => $section_id,

		# Status fields always exist

		HEAD_ID 	=> '',
		MASTER_ID 	=> '',
		REMOTE_ID 	=> '',
		GITHUB_ID 	=> '',

		AHEAD		=> 0,
		BEHIND  	=> 0,
		REBASE		=> 0,

		# parsed fields
		# PRIVATE is inherited for submdules

		mine     => 1,						# if !FORKED && !NOT_MINE in file
		private  => 0,
		forked   => 0,						# if FORKED [optional_blah] in file
		parent   => '',						# "Forked from ..." or "Copied from ..."
		descrip  => '',						# description from github
		size	 => 0,						# size in KB from github

		# fields added in parseRepos()
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

	});


	# optional fields

	if ($parent_repo)
	{
		$this->{parent_repo} = $parent_repo;
		$this->{rel_path}	 = $rel_path;
		$this->{can_commit_parent} = 0;
		$this->{first_time} = 1;

		# inherited from parent

		$this->{private} = $parent_repo->{private};

		# added by parseRepos
		# main_module =>
		# $this->{submodules} = shared_clone([]);
		# $this->{used_in}	  = shared_clone([]);
	}

	# fields added as necessary
	# local_commits, remote_commits

	# known temp fields
	# found_on_github => 0,
	# save_XXX (AHEAD, BEHIND, HEAD_ID, MASTER_ID, REMOTE_ID)

	bless $this,$class;

	if ($where == $REPO_LOCAL)
	{
		my ($cur_branch,$id) = $this->getId();
		$this->{branch} = $cur_branch;
		$this->{id} = $id;
	}
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

sub _repoShow
{
	my ($this) = @_;
	my $show =
		$this && $this->{path} ? "repo($this->{path}): " :
		$this && $this->{id} ? "repo_id($this->{id}): " : '';
}

sub repoError
{
	my ($this,$msg) = @_;
	my $show = _repoShow($this);
	$repo_ui->do_error($show.$msg)
		if $repo_ui;
	error($show.$msg,1); # ,$repo_ui);
	push @{$this->{errors}},$msg if $this;
	return undef;
}
sub repoWarning
{
	my ($this,$dbg_level,$indent,$msg) = @_;
	my $show = _repoShow($this);
	$repo_ui->do_warning($dbg_level,$indent,$show.$msg)
		if $repo_ui;
	warning($dbg_level,$indent,$show.$msg,1);
	push @{$this->{warnings}},$msg if $this;
}
sub repoNote
{
	my ($this,$dbg_level,$indent,$msg) = @_;
	my $show = _repoShow($this);
	$repo_ui->do_display($dbg_level,$indent,$show.$msg,$color_white)
		if $repo_ui;
	display($dbg_level,$indent,$show.$msg,1,$UTILS_COLOR_WHITE);
	push @{$this->{notes}},$msg if $this;
}


sub canAdd
{
	my ($this) = @_;
	return scalar(keys %{$this->{unstaged_changes}});
}
sub canCommit
	# Do we prevent commits when the repo is BEHIND
	# or needs a REBASE?  I think instead I will give
	# a warning message in the only place that Commit
	# occurs - from the commitWindow, warning the user
	# that the commit will cause a need for a Merge,
	# and allowing it if they want to do something weird.
{
	my ($this) = @_;
	return scalar(keys %{$this->{staged_changes}});
}
sub canPush
{
	my ($this) = @_;
	return $this->{AHEAD} && !$this->{BEHIND} ? 1 : 0;
}
sub canPull
{
	my ($this) = @_;
	return $this->{BEHIND} && !$this->{AHEAD} ? 1 : 0;
}
sub needsStash
{
	my ($this) = @_;
	return
		$this->canPull() &&
		(keys %{$this->{staged_changes}} ||
		 keys %{$this->{unstaged_changes}}) ? 1 : 0;
}
sub canCommitParent
{
	my ($this) = @_;
	return $this->{can_commit_parent};
}




sub setCanCommitParent
	# returns true if the SUBMODULE is in a state
	# where it can commit a submodule change to its parent.
	# Such a commit can only be done if the SUBMODULE itself
	# is 'clean' and up-to-date with github
{
	my ($this) = @_;
	my $parent = $this->{parent_repo};
	return if !$parent;

	display($dbg_can_commit+1,0,"setCanCommitParent($this->{path},$parent->{path})");

	my $num_changes =
		scalar(keys %{$this->{staged_changes}}) +
		scalar(keys %{$this->{unstaged_changes}});
	my $parent_unstaged = $parent->{unstaged_changes};
	my $num_parent_unstaged = scalar(keys %$parent_unstaged);

	my $commit = ${$this->{local_commits}}[0];
	my $commit_id = $commit->{sha};
	my $master_matches = $commit_id eq $this->{MASTER_ID};

	# Such a commit can only be done if the SUBMODULE itself
	# is 'clean' (no pending changes) and up-to-date with github.
	# and if the parent itself would allow it and has some untaged
	# changes and only if the most recent commit IS the MASTER_ID

	my $found = '';
	my $repo_ok =
		$this->{BEHIND} ||
		$this->{REBASE} ||
		$num_changes ||
		$parent->{BEHIND} ||
		$parent->{REBASE} ||
		!$num_parent_unstaged ? 0 : 1;

	# and only if we find an unstaged change for
	# the submodule on the parent

	if ($repo_ok && $num_parent_unstaged)
	{
		my $rel_path = $this->{rel_path};
		display($dbg_can_commit+1,0,"LOOKING FOR $rel_path in $num_parent_unstaged unstaged changes");

		for my $fn (sort keys %$parent_unstaged)
		{
			display($dbg_can_commit+1,0,"COMPARE $this->{path} $rel_path TO $parent->{path} CHANGE $fn");
			if ($fn eq $rel_path)
			{
				$found = $parent_unstaged->{$fn};
				last;
			}
		}
	}

	my $can_commit = $repo_ok && $found ? 1 : 0;

	warning($dbg_can_commit,0,"setCanCommitParent($this->{path}) repo_ok($repo_ok) found($found) = $can_commit");
	display($dbg_can_commit+1,1,"BEHIND($this->{BEHIND}) REBASE($this->{REBASE}) changes($num_changes) master_matches($master_matches)");
	display($dbg_can_commit+1,1,"parent BEHIND($parent->{BEHIND}) REBASE($parent->{REBASE}) unstaged($num_parent_unstaged)");

	$this->{first_time} = 0;
	$this->{can_commit_parent} = $can_commit;;
}



sub pathWithinSection
	# for display only
	# if !long (default) submodules show as ++rel_path,
	# otherwise they show as their path within the section
{
	my ($this,$long) = @_;
	$long ||= 0;
	my $MAX_DISPLAY_PATH = 30;
		# not including elipses

	# submodules show ++ relpath
	my $path = $this->{parent_repo} && !$long ?
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

sub idWithinSection
	# for display only
	# if !long (default) submodules show as ++rel_path,
	# otherwise they show as their path within the section
{
	my ($this,$long) = @_;
	$long ||= 0;
	my $MAX_DISPLAY_PATH = 30;
		# not including elipses

	my $id = $this->{id};
	if ($this->{parent_repo})
	{
		$id = "++ $this->{rel_path}";
	}
	else
	{
		my $re = $this->{section_id};
		$id =~ s/^$re//;
		$id =~ s/^-//;
		$id ||= $this->{id};
	}

	$id = '...'.substr($id,-$MAX_DISPLAY_PATH)
		if length($id) >= $MAX_DISPLAY_PATH;
	return $id;
}



#---------------------------------------
# toTextCtrl()
#---------------------------------------

my $LEFT_MARGIN = 14;


sub contentLine
{
	my ($this,$text_ctrl,$bold,$key,$use_label,$label_context) = @_;
	$use_label ||= '';
	my $label = $use_label || $key;
	my $is_main_module_ref =
		$use_label eq 'MAIN_MODULE' &&
		$key eq 'id';

	my $value = $this->{$key} || '';
	return if !defined($value) || $value eq '';

	$value = $value->{path} if $key eq 'parent_repo';

	my $context;
	my $color = $color_blue;

	if ($is_main_module_ref)
	{
		my $repo = apps::gitUI::repos::getRepoById($value);
		$value = $repo->{path};
		$color = linkDisplayColor($repo);
	}
	elsif ($key eq 'section_path')
	{
		$context = { path => $value };
	}
	elsif ($key eq 'path' ||
		$key eq 'parent_repo')
	{
		$context = { repo_path => $value };
		my $repo = apps::gitUI::repos::getRepoByPath($value);
		$color = linkDisplayColor($repo);
	}
	elsif ($key eq 'parent' || $key eq 'id')
	{
		my $clean = $value;
		$clean =~ s/\(|\)//g;
		my $url = "https://github.com/";
		$url .= getPref('GIT_USER')."/" if $key eq 'id';
		$url .= $clean;
		$context = { path => $url };
	}

	my $line = $text_ctrl->addLine();
	my $fill = pad("",$LEFT_MARGIN-length($label));

	$text_ctrl->addPart($line, 0, $color_black, $label, $label_context);
	$text_ctrl->addPart($line, 0, $color_black, $fill." = ");
	$text_ctrl->addPart($line, $bold, $color, $value, $context );
}


sub contentArray
{
	my ($this,$text_ctrl,$bold,$key,$color,$ucase,$sub_context) = @_;
	$ucase ||= 0;
	my $label = $key;
	$label = uc($label) if $ucase;
	my $array = $this->{$key};
	return '' if !$array || !@$array;

	my $line = $text_ctrl->addLine();
	$text_ctrl->addPart($line, $bold, $color_black, $label, $sub_context);

	$color = $color_blue if !defined($color);
	for my $item (@$array)
	{
		my $context;
		my $value = $item;

		if ($key eq 'submodules')
		{
			my $repo = apps::gitUI::repos::getRepoByPath($value);
			$context = { repo => $repo, path=>"subs:$repo->{id}" };
			$color = linkDisplayColor($repo);
		}
		elsif ($key eq 'uses' ||
			$key eq 'used_by' ||
			$key eq 'friend' ||
			$key eq 'used_in')
		{
			$context = { repo_path => $value };
			my $repo = apps::gitUI::repos::getRepoByPath($value);
			$color = linkDisplayColor($repo);
		}
		elsif ($key eq 'docs')
		{
			$context = { repo=>$this, file=>$value };
		}
		elsif ($key eq 'needs')
		{
			$context = { path => $value };
		}
		elsif ($key eq 'group')
		{
			$context = { repo_path => '/src/phorton1', file=>"/$value.md" };
		}

		# GROUPS are recursive through USES and FRIEND.
		# only the highest level repos need to be specified as groups.
		# The recursion should be handled in parseRepos()

		$line = $text_ctrl->addLine();
		$text_ctrl->addPart($line, 0, $color_black, pad('',4));
		$text_ctrl->addPart($line, $bold, $color, $value, $context);
	}
}



sub contentCommits
{
	my ($this,$text_ctrl,$key) = @_;
	my $array = $this->{$key};
	return '' if !$array || !@$array;

	$text_ctrl->addSingleLine(0, $color_black, uc($key));

	for my $commit (@$array)
	{
		my $sha = $commit->{sha};
		my $msg = $commit->{msg};
		my $time = $commit->{time};

		my @branches = ();
		push @branches,"HEAD" if $sha eq $this->{HEAD_ID};
		push @branches,"MASTER" if $sha eq $this->{MASTER_ID};
		push @branches,"REMOTE" if $sha eq $this->{REMOTE_ID};
		push @branches,"GITHUB" if $sha eq $this->{GITHUB_ID};

		my $branch_text = @branches ? "[".join(",",@branches)."] " : '';

		my $line = $text_ctrl->addLine();
		$text_ctrl->addPart($line,0,$color_blue,
			pad("",4).
			_lim($sha,8)." ".
			timeToStr($time)." " );
		$text_ctrl->addPart($line,1,$color_orange,$branch_text)
			if $branch_text;
		$text_ctrl->addPart($line,0,$color_black,_plim($msg,80));
	}

	$text_ctrl->addLine();
}


sub addTextForFxn
{
	my ($this,$text,$fxn) = @_;
	my $rslt = $this->$fxn();
	if ($rslt)
	{
		$text .= ' ' if $text;
		$text .= $fxn;
	}
	return $text;
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
	# text ctrl has been cleared by infoWindowRight
{
	my ($this,$text_ctrl,$window_id) = @_;
	$text_ctrl->addLine();	# blank first line

	# MAIN FIELDS FIRST including the $short_status

	my $kind =
		$this->{parent_repo} ? "SUBMODULE " :
		$this->{used_in} ? "MAIN_MODULE " : 'REPO';
	my $sub_context = $kind ne 'REPO' ?
		{ repo=>$this, path=>"subs:$this->{id}" } : '';

	$this->contentLine($text_ctrl,1,'exists');
		# hopefully temporary

	$this->contentLine($text_ctrl,1,'path',$kind,$sub_context);
	$this->contentLine($text_ctrl,1,'id');
	$this->contentLine($text_ctrl,0,'branch');
	$this->contentLine($text_ctrl,0,'default_branch');

	# add a yellow warning if not on the default branch

	$text_ctrl->addSingleLine(1,$color_orange,
		pad("WARNING:",$LEFT_MARGIN + 3).
		"branch($this->{branch}) is not default_branch($this->{default_branch})")
		if $this->{branch} && $this->{default_branch} &&
		   $this->{branch} ne $this->{default_branch};

	$this->contentLine($text_ctrl,1,'private');

	# short status

	my $short_status = '';
	$short_status = $this->addTextForHashNum($short_status,'unstaged_changes',"UNSTAGED");
	$short_status = $this->addTextForHashNum($short_status,'staged_changes',"STAGED");
	$short_status = $this->addTextForNum($short_status,'AHEAD');
	$short_status = $this->addTextForNum($short_status,'BEHIND');
	$short_status = $this->addTextForNum($short_status,'REBASE');
		# Above determine canCommit, canPush, canPull, and needsStash
	$short_status = $this->addTextForFxn($short_status,'canAdd');
	$short_status = $this->addTextForFxn($short_status,'canCommit');
	$short_status = $this->addTextForFxn($short_status,'canPush');
	$short_status = $this->addTextForFxn($short_status,'canPull');
	$short_status = $this->addTextForFxn($short_status,'needsStash');
	$short_status = $this->addTextForFxn($short_status,'canCommitParent');

	if ($short_status)
	{
		# mimic the 'link' colors for 'canPush',

		my $color = linkDisplayColor($this);
		$short_status = pad('status',$LEFT_MARGIN)." = ".$short_status;
		$text_ctrl->addSingleLine(1, $color, $short_status);
	}

	$this->contentLine($text_ctrl,0,'section_path');
	$this->contentLine($text_ctrl,0,'section_id');
	$this->contentLine($text_ctrl,1,'mine');
	$this->contentLine($text_ctrl,0,'forked');
	$this->contentLine($text_ctrl,0,'parent');
	$this->contentLine($text_ctrl,0,'descrip');
	$this->contentLine($text_ctrl,0,'page_header');

	# SUBMODULE FIELDS SECOND

	if ($this->{parent_repo})
	{
		$text_ctrl->addLine();
		$this->contentLine($text_ctrl,1,'id','MAIN_MODULE',$sub_context);
		$this->contentLine($text_ctrl,1,'parent_repo');
		$this->contentLine($text_ctrl,1,'rel_path');
	}
	elsif ($this->{submodules} || $this->{used_in})
	{
		$text_ctrl->addLine();
		$this->contentArray($text_ctrl,0,'submodules',undef,1);
		$this->contentArray($text_ctrl,0,'used_in',undef,1,$sub_context);
	}

	# 	my ($this,$text_ctrl,$bold,$key,$color,$ucase,$sub_context) = @_;
	# ERRORS AND WARNINGS THIRD

	if (@{$this->{errors}} ||
		@{$this->{warnings}} ||
		@{$this->{notes}})
	{
		$text_ctrl->addLine();
		$this->contentArray($text_ctrl,1,'errors',$color_red);
		$this->contentArray($text_ctrl,1,'warnings',$color_magenta);
		$this->contentArray($text_ctrl,0,'notes');
	}

	# COMMIT INFORMATION for debugging visible without scrolling

	$text_ctrl->addLine();
	$this->contentLine($text_ctrl,1,'HEAD_ID');
	$this->contentLine($text_ctrl,1,'MASTER_ID');
	$this->contentLine($text_ctrl,1,'REMOTE_ID');
	$this->contentLine($text_ctrl,1,'GITHUB_ID');

	$text_ctrl->addLine();
	$this->contentCommits($text_ctrl,'local_commits');
	$this->contentCommits($text_ctrl,'remote_commits');

	# RELATIONSHIP information last before HISTORY

	if ($this->{docs} ||
		$this->{uses} ||
		$this->{used_by} ||
		$this->{needs} ||
		$this->{friend} ||
		$this->{group} )
	{
		$this->contentArray($text_ctrl,0,'docs');
		$this->contentArray($text_ctrl,0,'uses');
		$this->contentArray($text_ctrl,0,'used_by');
		$this->contentArray($text_ctrl,0,'needs');
		$this->contentArray($text_ctrl,0,'friend');
		$this->contentArray($text_ctrl,0,'group');
		$text_ctrl->addLine();
	}

	# HISTORY WILL FOLLOW HERE
}


1;
