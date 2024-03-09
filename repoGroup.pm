#----------------------------------------------------
# base::apps::gitUI::repoGroup
#----------------------------------------------------
# An object that is orthogonal to a 'section' which has
# {name} and {repo} members, and somethwat orthogonal to
# a repo object, that has {id}, etc members, and canPush()
# etc methods.
#
# Used in the Subs Window.


package apps::gitUI::repoGroup;
use strict;
use warnings;
use threads;
use threads::shared;
use Time::HiRes qw(sleep);
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


sub setStatus
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


sub matchesPath
{
	my ($this,$path) = @_;
	for my $repo (@{$this->{repos}})
	{
		return 1 if $path eq $repo->{path};
	}
	return 0;
}


#----------------------------
# orthogonal accessors
#----------------------------

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


sub displayColor
{
	my ($this) = @_;
	return
		$this->{BEHIND} || $this->{REBASE} ? $color_red :
			# errors or merge conflict
		$this->canPush() || $this->{AHEAD} ? $color_orange :
			# needs push
		$this->{changed}  ? $color_magenta :
			# can commit
		$this->{private} ? $color_blue :
		$color_green;
}



#---------------------------------------
# toTextCtrl()
#---------------------------------------

sub contentLine
{
	my ($this,$text_ctrl,$bold,$key) = @_;
	my $label = $key;
	my $value = $this->{$key} || '';
	return if !defined($value) || $value eq '';
	my $line = $text_ctrl->addLine();
	my $fill = pad("",12-length($label));

	$text_ctrl->addPart($line, 0, $color_black, $label);
	$text_ctrl->addPart($line, 0, $color_black, $fill." = ");
	$text_ctrl->addPart($line, $bold, $color_blue, $value );
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




sub toTextCtrl
{
	my ($this,$text_ctrl,$window_id) = @_;
	display(0,0,"toTextCtrl()");

	my $content = [];

	$text_ctrl->addLine();

	# MAIN FIELDS FIRST including the $short_status

	$this->contentLine($text_ctrl,1,'id');

	my $short_status = '';
	$short_status = $this->addTextForNum($short_status,'changed');
	$short_status = $this->addTextForNum($short_status,'AHEAD');
	$short_status = $this->addTextForNum($short_status,'BEHIND');
	$short_status = $this->addTextForNum($short_status,'REBASE');

	$short_status = $this->addTextForFxn($short_status,'canPush');
	$short_status = $this->addTextForFxn($short_status,'canPull');
	$short_status = $this->addTextForFxn($short_status,'needsStash');

	$short_status ||= 'Up To Date';
	my $color = $this->displayColor();
	$short_status = pad('status',12)." = ".$short_status;
	$text_ctrl->addSingleLine(1, $color, $short_status);

	display(0,0,"toTextCtrl() returning");
}


1;
