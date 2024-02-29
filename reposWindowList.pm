
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
my $dbg_sel = -2;



my $BASE_ID = 1000;

my $LINE_HEIGHT   = 18;


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}


sub new
{
    my ($class,$parent,$splitter) = @_;
	display($dbg_life,0,"new reposWindowList()");

    my $this = $class->SUPER::new($splitter,-1,[0,0],[-1,-1]);
	$this->addRepoMenu(1);
		# 1 == this is the reposWindow

	$this->{parent} = $parent;
	$this->{frame} = $parent->{frame};
	$this->{ctrls} = [];
	$this->{ctrls_by_path} = {};
	$this->{selected_path} = '';
	$this->{bold_font} = $this->GetFont();
	$this->{bold_font}->SetWeight(wxFONTWEIGHT_BOLD);

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


sub repoFromCtrlId
{
	my ($ctrl_id) = @_;
	my $repo_list = getRepoList();
	return $repo_list->[$ctrl_id-$BASE_ID];
}


sub onEnterLink
{
	my ($ctrl,$event) = @_;
	my $this = $ctrl->GetParent();
	my $ctrl_id = $event->GetId();
	my $repo = repoFromCtrlId($ctrl_id);
	my $show = "$repo->{path} = $repo->{id}";

	$this->{frame}->SetStatusText($show);
	$ctrl->SetFont($this->{bold_font});
	$ctrl->Refresh();
	$event->Skip();
}


sub onLeaveLink
{
	my ($ctrl,$event) = @_;
	my $this = $ctrl->GetParent();
	my $ctrl_id = $event->GetId();
	my $repo = repoFromCtrlId($ctrl_id);
	my $path = $repo->{path};

	$this->{frame}->SetStatusText('');
	$ctrl->SetFont($this->GetFont())
		if $repo->{path} ne $this->{selected_path};
	$ctrl->Refresh();
	$event->Skip();
}


sub onRightDown
{
	my ($ctrl,$event) = @_;
	my $this = $ctrl->GetParent();
	my $event_id = $event->GetId();
	my $repo = repoFromCtrlId($event_id);
	display($dbg_life,0,"onRightDown($repo->{path}");
	$this->popupRepoMenu($repo);
}


sub selectRepo
{
	my ($this,$path) = @_;
	display($dbg_sel,0,"selectRepo($path)");

	my $ctrl = $this->{ctrls_by_path}->{$path};
	return !error("Could not find ctrl($path)")
		if !$ctrl;
	my $repo = getRepoByPath($path);
	return !error("Could not find repo($path)")
		if !$repo;

	my $selected_path = $this->{selected_path};
	if ($selected_path && $selected_path ne $path)
	{
		my $prev_sel = $this->{ctrls_by_path}->{$selected_path};
		$prev_sel->SetBackgroundColour($color_white);
		$prev_sel->SetFont($this->GetFont());
		$prev_sel->Refresh();
	}

	$this->{selected_path} = $path;
	$ctrl->SetBackgroundColour($color_medium_grey);
	$ctrl->SetFont($this->{bold_font});
	$ctrl->Update();

	# if the repo is not visible, scroll it into view
	# as close to middle of view as possible

	my $sz = $this->GetSize();
    my $height = $sz->GetHeight();
	my $ctrl_y = $ctrl->GetPosition()->y;						# ctrl PIXEL y position relative to view
	display($dbg_sel+1,1,"Scroll($ctrl_y) height($height)");

	if ($ctrl_y < 0 || $ctrl_y > $height-$LINE_HEIGHT)
	{
		# I could boil these calculations down but
		# I'm leaving them fleshed out for clarity

		my ($unused,$start_y) = $this->GetViewStart();			# starting LINE number showing in view
		my $lines = int($height / $LINE_HEIGHT);
		my $middle = int($lines / 2);							# LINE number of middle of view
		my $abs_y = $ctrl_y + ($start_y * $LINE_HEIGHT);		# absolute ctrl PIXEL position
		my $abs_line = int($abs_y / $LINE_HEIGHT);				# absolute LINE number of ctrl
		my $start_line = $abs_line - $middle;					# starting LINE number to bring ctrl to middle of view
		$start_line = 0 if $start_line < 0;						# better if it's not less than zero

		display($dbg_sel+1,1,"Scroll start_y($start_y) lines($lines) middle($middle) abs_y($abs_y) abs_line($abs_line) start_line($start_line)");

		$this->Scroll(0,$start_line);
		$this->Update();
	}

	display($dbg_sel+1,1,"finishing select($path)=$repo->{id}");
	$this->{frame}->SetStatusText("$path == $repo->{id}");
	$this->{parent}->{right}->notifyRepoSelected($repo);

}



sub onLeftDown
{
	my ($ctrl,$event) = @_;
	my $this = $ctrl->GetParent();
	my $ctrl_id = $event->GetId();
	my $repo = repoFromCtrlId($ctrl_id);
	$this->selectRepo($repo->{path});
	$event->Skip();
}


sub onSize
{
	my ($this,$event) = @_;
	my $sz = $this->GetSize();
    my $width = $sz->GetWidth();
    my $height = $sz->GetHeight();
	for my $ctrl (@{$this->{ctrls}})
	{
		$ctrl->SetSize([$width-10,$height]);
	}
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
	$this->DestroyChildren();
	$this->{ctrls} = [];
	$this->{ctrls_by_path} = {};

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
				Wx::StaticText->new($this,-1,$section->{name},[5,$ypos]);
				$ypos += $LINE_HEIGHT;
			}

			my $id_num = $repo->{num} + $BASE_ID;
			my $display_name = $repo->pathWithinSection();
			display($dbg_pop,1,"hyperLink($id_num,$display_name)");

			my $color = linkDisplayColor($repo);
			my $ctrl = apps::gitUI::myHyperlink->new(
				$this,
				$id_num,
				$display_name,
				[5,$ypos],
				[-1,-1],
				$color);
			push @{$this->{ctrls}},$ctrl;
			$this->{ctrls_by_path}->{$repo->{path}} = $ctrl;
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
					my $color = linkDisplayColor($repo);
					$ctrl->SetForegroundColour($color);
					$ctrl->Refresh();
					return;
				}
			}
		}
	}
}



1;