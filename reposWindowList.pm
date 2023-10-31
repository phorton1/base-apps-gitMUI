
# NEEDS:
# -	THIS and the pathWindow should really not be multiple instance.
# - THIS window's hyperlink should have and show the notion of a "selected" repo
# - Pub::Wx::Frame() should have createOrActivateWindow({data})
# - THIS windows onSetData() method would select the repo and scroll as necessary
# - The repoMenu would include the menu item IF not from THIS window

#-------------------------------------------
# apps::gitUI::reposWindowList
#-------------------------------------------
# The left portion of the reposWindow showing a list of repos
# Largely cut-and-past from pathWindow.pm

package apps::gitUI::reposWindowList;
use strict;
use warnings;
use threads;
use threads::shared;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_SIZE
	EVT_LEFT_DOWN
	EVT_RIGHT_DOWN
	EVT_ENTER_WINDOW
	EVT_LEAVE_WINDOW);
use Pub::Utils;
use apps::gitUI::repos;
use apps::gitUI::utils;
use apps::gitUI::myHyperlink;
use apps::gitUI::repoMenu;
use base qw(Wx::ScrolledWindow apps::gitUI::repoMenu);

my $dbg_life = 0;
my $dbg_pop = 1;
my $dbg_layout = 1;
my $dbg_notify = 1;


my $BASE_ID = 1000;

my $LINE_HEIGHT   = 18;


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}


sub new
{
    my ($class,$parent,$splitter,$data) = @_;
	display($dbg_life,0,"new reposWindowList() data="._def($data));
	$data ||= {};

    my $this = $class->SUPER::new($splitter,-1,[0,0],[-1,-1]);

	$this->{parent} = $parent;
	$this->{frame} = $parent->{frame};
	$this->{ctrl_sections} = [];

	$this->{ysize} = 0;
	$this->SetScrollRate(0,$LINE_HEIGHT);
		# Learn the hard way.  A simple ScrolledWindow, even
		# with controls, MUST call SetScrollRate() and still
		# call SetVirtualSize() even though the damned window
		# should just KNOW the size from the creation of the controls.

	$this->SetBackgroundColour($color_white);
	$this->populate();

	EVT_SIZE($this, \&onSize);
	return $this;

}


sub repoFromId
{
	my ($id) = @_;
	my $repo_list = getRepoList();
	return $repo_list->[$id  - $BASE_ID];
}


sub repoPathFromId
{
	my ($id) = @_;
	my $repo_list = getRepoList();
	display(0,0,"repoPathFromId($id) num=".scalar(@$repo_list));
	return $repo_list->[$id  - $BASE_ID]->{path};
}


sub onEnterLink
{
	my ($ctrl,$event) = @_;
	my $id = $event->GetId();
	my $this = $ctrl->GetParent();
	my $path = repoPathFromId($id);
	$this->{frame}->SetStatusText($path);
	my $font = Wx::Font->new($this->GetFont());
	$font->SetWeight (wxFONTWEIGHT_BOLD );
	$ctrl->SetFont($font);
	$ctrl->Refresh();
}


sub onLeaveLink
{
	my ($ctrl,$event) = @_;
	my $this = $ctrl->GetParent();
	$this->{frame}->SetStatusText('');
	$ctrl->SetFont($this->GetFont());
	$ctrl->Refresh();
}


sub onRightDown
{
	my ($ctrl,$event) = @_;
	my $id = $event->GetId();
	my $this = $ctrl->GetParent();
	my $repo = repoFromId($id);
	display($dbg_life,0,"onRightDown($id,$repo->{path}");
	$this->popupRepoMenu($repo);

}


sub onLeftDown
{
	my ($ctrl,$event) = @_;
	my $id = $event->GetId();
	my $this = $ctrl->GetParent();
	my $repo = repoFromId($id);
	$this->{parent}->{right}->notifyRepoSelected($repo);
}


sub onSize
{
	my ($this,$event) = @_;
	my $sz = $this->GetSize();
    my $width = $sz->GetWidth();
    my $height = $sz->GetHeight();
	# $this->SetScrollbar(wxVERTICAL,0,3,$this->{ysize});
	$this->SetVirtualSize([$width,$this->{ysize}]);
    $event->Skip();
}


#----------------------------------------
# populate
#----------------------------------------

sub newCtrlSection
{
	my ($this,$section,$name) = @_;
	display($dbg_pop,0,"newCtrlSection($section->{name})");

	my $ctrl_section = {
		section => $section,
		ctrls   => [] };
	push @{$this->{ctrl_sections}},$ctrl_section;
	return $ctrl_section;
}


sub addSectionCtrl
{
	my ($ctrl_section,$ctrl,$name) = @_;
	display($dbg_pop,0,"addSectionCtrl($name)");
	push @{$ctrl_section->{ctrls}},$ctrl;
}


sub populate
{
	my ($this) = @_;

	display($dbg_pop,0,"populate()");

	my $sections = groupReposBySection();
	$this->{ctrl_sections} = [];
	$this->DestroyChildren();

	my $ypos = 5;

	my $page_started = 0;
	for my $section (@$sections)
	{
		my $section_started = 0;
		my $ctrl_section = newCtrlSection($this,$section);
		$ypos += $LINE_HEIGHT if $page_started;	  # blank line between sections
		$page_started = 1;

		for my $repo (@{$section->{repos}})
		{
			if (!$section_started && $section->{name} ne $repo->{path})
			{
				display($dbg_pop,1,"staticText($section->{name})");
				my $ctrl = Wx::StaticText->new($this,-1,$section->{name},[5,$ypos]);
				addSectionCtrl($ctrl_section,$ctrl,$section->{name});
				$ypos += $LINE_HEIGHT;
			}

			my $id = $repo->{num} + $BASE_ID;
			my $display_name = $repo->pathWithinSection();
			display($dbg_pop,1,"hyperLink($id,$display_name)");

			my $color =
				keys %{$repo->{unstaged_changes}} ? $color_orange :
				keys %{$repo->{staged_changes}} ? $color_red :
				keys %{$repo->{remote_changes}} ? $color_magenta :
				$repo->{private} ? $color_blue :
				$color_green;

			my $ctrl = apps::gitUI::myHyperlink->new(
				$this,
				$id,
				$display_name,
				[5,$ypos],
				[-1,-1],
				$color);
			addSectionCtrl($ctrl_section,$ctrl,$display_name);
			$ypos += $LINE_HEIGHT;

			$section_started = 1;
			EVT_LEFT_DOWN($ctrl, \&onLeftDown);
			EVT_RIGHT_DOWN($ctrl, \&onRightDown);
			EVT_ENTER_WINDOW($ctrl, \&onEnterLink);
			EVT_LEAVE_WINDOW($ctrl, \&onLeaveLink);
		}
	}

	$this->{ysize} = $ypos + $LINE_HEIGHT;
	$this->SetVirtualSize([1000,$this->{ysize}]);
	$this->Refresh();
}



sub notifyRepoChanged
	# Called by reposWindow when the monitor
	# detects a change to a repo
{
	my ($this,$repo) = @_;
	display($dbg_notify,0,"notifyRepoChanged($repo->{path})");
	for my $ctrl_section (@{$this->{ctrl_sections}})
	{
		for my $ctrl (@{$ctrl_section->{ctrls}})
		{
			my $id = $ctrl->GetId();
			if ($id > 0)
			{
				my $found_repo = repoFromId($id);
				if ($repo->{path} eq $found_repo->{path})
				{
					my $color =
						keys %{$repo->{unstaged_changes}} ? $color_orange :
						keys %{$repo->{staged_changes}} ? $color_red :
						keys %{$repo->{remote_changes}} ? $color_magenta :
						$repo->{private} ? $color_blue :
						$color_green;
					$ctrl->SetForegroundColour($color);
					$ctrl->Refresh();
					return;
				}
			}
		}
	}
}



1;