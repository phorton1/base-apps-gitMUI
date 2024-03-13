#----------------------------------------------------
# base::apps::gitUI::repoGroup
#----------------------------------------------------
# An object that is orthogonal to a 'section' which has
# {name} and {repo} members, and somethwat orthogonal to
# a repo object, that has {id}, and other members, and
# canPush() and other methods that are called from the
# infoWindow for UpdateUI and to gather sub-repos that
# need pushing and pulling.
#
# It has a {is_subgroup} member to allow clients to
# differentiate between it and a 'real' repo object as
# needed.
#
# NOTE THAT THE {path} MEMBER OF A SUBGROUP IS SPECIAL.
# It is the ID of the master module to keep it separate
# in the infoWindowList, and must be turned into a real
# path when a path is needed.
#
# # Used only in the sub_mode of the infoWindow, it is also
# WX aware and adds buttons, updateUI, and a commandHandler
# to the myTextCtrl for repoGroups.


package apps::gitUI::repoGroup;
use strict;
use warnings;
use threads;
use threads::shared;
use Time::HiRes qw(sleep);
use Wx qw(:everything);
use Pub::Utils;
use Pub::Prefs;
use apps::gitUI::Resources;
use apps::gitUI::repo;
use apps::gitUI::repos;
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
		groupReposAsSubmodules
	);
}


sub groupReposAsSubmodules
{
	my $groups = shared_clone([]);
	my $group_num = 0;
	my $repo_list = getRepoList();
	for my $repo (@$repo_list)
	{
		next if !$repo->{used_in};
		my $group = apps::gitUI::repoGroup->new($group_num++,$repo);
		push @$groups,$group;
	}
	return $groups;
}




#---------------------------
# ctor
#---------------------------

sub new
{
	my ($class, $group_num, $master_module) = @_;
	my $id = $master_module->{id};
	display($dbg_new,0,"repoGroup->new($id)");

	my $subs = $master_module->{used_in};
	my $repos = shared_clone([]);

	my ($this) = shared_clone({
		num => $group_num,			# as if it were a repo
		id => $id,					# as if it were a repo
		path => $id,				# as if it were a repo, we overload the path to the id of the master_module
		name => $id,				# as if it was a section
		repos => $repos,			# as if it was a section
		is_subgroup => 1,			# to differentiate from regular repo

		# inherited from master

		private => $master_module->{private},

		# debugging

		dbg_last_can_commit_parent => -1,
	});

	bless $this,$class;
	push @$repos,$master_module;
	for my $path (@$subs)
	{
		my $repo = getRepoByPath($path);
		push @$repos,$repo;
	}

	$this->setStatus();
	return $this;
}


sub matchesPath
	# this thing changes if the $path matches the submodules
	# OR their parents, both of which can affect canCommitParent.
{
	my ($this,$path) = @_;
	for my $repo (@{$this->{repos}})
	{
		return 1 if $path eq $repo->{path};
		return 1 if $repo->{parent_repo} && $path eq $repo->{parent_repo}->{path};
	}
	return 0;
}

sub setStatus
	# One half of the equation.  Sets various fields
	# on the group item for supporting the Update user
	# interface generated in toTextCtrl.
{
	my ($this) = @_;

	$this->{AHEAD}	 = 0;
	$this->{BEHIND}  = 0;
	$this->{REBASE}	 = 0;
	$this->{changed} = 0;

	for my $repo (@{$this->{repos}})
	{
		$this->{AHEAD}++ if $repo->{AHEAD};
		$this->{BEHIND}++ if $repo->{BEHIND};
		$this->{REBASE}++ if $repo->{REBASE};
		$this->{changed}++ if
			scalar(keys %{$repo->{staged_changes}}) ||
			scalar(keys %{$repo->{unstaged_changes}});
	}
}


sub setSelectedPushRepos
{
	my ($this) = @_;
	for my $repo (@{$this->{repos}})
	{
		setSelectedPushRepo($repo)
			if $repo->canPush();
	}
}

sub setSelectedPullRepos
{
	my ($this) = @_;
	for my $repo (@{$this->{repos}})
	{
		setSelectedPullRepo($repo)
			if $repo->canPull();
	}
}

sub setSelectedCommitParentRepos
{
	my ($this) = @_;
	for my $repo (@{$this->{repos}})
	{
		setSelectedCommitParentRepo($repo)
			if $repo->canCommitParent();
	}
}






#----------------------------
# orthogonal accessors
#----------------------------
# These orthogonal accessors need counterparts to
# select the given repos for Pushing and Pulling.

# TODO: Currently assuming a subgroup is REMOTE and LOCAL

sub isLocal
{
	my ($this) = @_;
	return 1;
}
sub isRemote
{
	my ($this) = @_;
	return 1;
}
sub isLocalOnly
{
	my ($this) = @_;
	return 0;
}
sub isRemoteOnly
{
	my ($this) = @_;
	return 0;
}
sub isLocalAndRemote
{
	my ($this) = @_;
	return ;
}



sub canAdd
{
	my ($this) = @_;
	return 0;
}
sub canCommit
{
	my ($this) = @_;
	return 0;
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
	return 0 if !$this->canPull();
	for my $repo (@{$this->{repos}})
	{
		return 1 if
			$repo->canPull() &&
			(keys %{$repo->{staged_changes}} ||
			 keys %{$repo->{unstaged_changes}});
	}
	return 0;
}
sub canCommitParent
	# We only commit the entire group if no repos,
	# have any changes, and all repos are up-to-date with
	# respect with github (!AHEAD,!BEHIND, && !REBASE),
	# and at least one repo canCommitParent().
{
	my ($this) = @_;
	my $any_bad = 0;
	my $can_count = 0;

	for my $repo (@{$this->{repos}})
	{
		next if $repo->{used_in};
			# the master cannot update it's parent
			# it is a regular repo just sitting there
		if ($repo->{AHEAD} ||
			$repo->{BEHIND} ||
			$repo->{REBASE} ||
			keys %{$repo->{staged_changes}} ||
			keys %{$repo->{unstaged_changes}} )
		{
			$any_bad = 1;
			last;
		}
		$can_count ++ if $repo->canCommitParent();
	}

	my $can_commit = $any_bad ? 0 : $can_count;

	my $DBG_UI = 0;
	if ($DBG_UI && $this->{dbg_last_can_commit_parent} != $can_commit)
	{
		$this->{dbg_last_can_commit_parent} = $can_commit;
		display(0,0,"canCommitParent($this->{path}) CHANGED TO $can_commit");
	}

	return $can_commit;
}


sub displayColor
{
	my ($this) = @_;
	return
		$this->{BEHIND} || $this->{REBASE} ? $color_red :
			# errors or merge conflict
		$this->canPush() || $this->{AHEAD} ? $color_orange :
			# needs push
		$this->{changed} || $this->canCommitParent() ? $color_magenta :
			# can commit
		$this->{private} ? $color_blue :
		$color_green;
}



#---------------------------------------
# toTextCtrl()
#---------------------------------------


my $CHAR_INDENT = 7;





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


sub getShortStatus
{
	my ($obj) = @_;
	my $short_status = '';
	$short_status = addTextForNum($obj,$short_status,'changed');
	$short_status = addTextForNum($obj,$short_status,'AHEAD');
	$short_status = addTextForNum($obj,$short_status,'BEHIND');
	$short_status = addTextForNum($obj,$short_status,'REBASE');
	$short_status = addTextForFxn($obj,$short_status,'canAdd');
	$short_status = addTextForFxn($obj,$short_status,'canCommit');
	$short_status = addTextForFxn($obj,$short_status,'canPush');
	$short_status = addTextForFxn($obj,$short_status,'canPull');
	$short_status = addTextForFxn($obj,$short_status,'needsStash');
	$short_status = addTextForFxn($obj,$short_status,'canCommitParent');
	$short_status ||= 'Up To Date';
	return $short_status;
}


sub toTextCtrl
	# text ctrl has been cleared by infoWindowRight

{
	my ($this,$text_ctrl) = @_;	#,$window_id) = @_;
	# display(0,0,"toTextCtrl()");
	$text_ctrl->addLine();	# blank first line

	my $color = $this->displayColor();
	$this->subToTextCtrl('GROUP',$color,$this,$text_ctrl);
	my $type = 'MAIN';
	for my $repo (@{$this->{repos}})
	{
		$color = linkDisplayColor($repo);
		$this->subToTextCtrl($type,$color,$repo,$text_ctrl);
		$type = 'SUB';
	}

	$text_ctrl->addLine();	# blank line at end
	# display(0,0,"toTextCtrl() returning");
}


sub subToTextCtrl
{
	my ($this, $type, $color, $repo, $text_ctrl) = @_;
	my $CHAR_WIDTH = $text_ctrl->getCharWidth();
	my $LEFT_MARGIN = 5;	# need accessors?

	my $fill_indent = pad("",$CHAR_INDENT);
	my $short_status = getShortStatus($repo);

	my $line = $text_ctrl->addLine();
	my $context = $type eq 'GROUP' ?
		{ repo => getRepoById($repo->{path}) } :
		{ repo => $repo, path => "subs:$repo->{path}" } ;

	$text_ctrl->addPart($line, 0, $color_black, pad("$type:",$CHAR_INDENT));
	$text_ctrl->addPart($line, 1, $color, $repo->{path},$context);

	$text_ctrl->addSingleLine(1, $color, $fill_indent.$short_status);

	if ($type ne 'GROUP')
	{
		my $ypos = $text_ctrl->nextYPos();
		my $button_x = $LEFT_MARGIN + $CHAR_INDENT * $CHAR_WIDTH;

		my $button = Wx::Button->new($text_ctrl, $INFO_RIGHT_COMMAND_SINGLE_PULL, 'Pull', [$button_x,$ypos], [70,16]);
		$button->{repo} = $repo;
		$button_x += 80;

		$button = Wx::Button->new($text_ctrl, $INFO_RIGHT_COMMAND_SINGLE_PUSH, 'Push',	[$button_x,$ypos],	[60,16]);
		$button->{repo} = $repo;
		$button_x += 70;

		# the master has no parent to update

		if ($type eq 'SUB')
		{
			$button = Wx::Button->new($text_ctrl, $INFO_RIGHT_COMMAND_SINGLE_COMMIT_PARENT, 'CommitParent',[$button_x,$ypos],	[90,16]);
			$button->{repo} = $repo;
			$button_x += 100;
		}

		$text_ctrl->addLine();	# blank line for buttons
	}

	# $text_ctrl->addLine();	# blank line after sub

}




1;
