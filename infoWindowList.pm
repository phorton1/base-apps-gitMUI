#-------------------------------------------
# apps::gitUI::infoWindowList
#-------------------------------------------
# The left portion of the infoWindow sections
# containing lists of repos. Based on {sub_mode}
# these will be the entire list of repos, with
# possibly unclickable black section headers,
# or groups of Submodules with a clickable colored
# header.
#
# The addition of a clickable header is a big change,
# requiring a new toTextCtrl() method for subGroups.


package apps::gitUI::infoWindowList;
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
use apps::gitUI::Resources;
use base qw(Wx::ScrolledWindow apps::gitUI::repoMenu);

my $dbg_life = 0;
my $dbg_pop = 1;
my $dbg_layout = 1;
my $dbg_notify = 1;
my $dbg_sel = -2;



my $REPO_BASE_ID = 10000;
my $SUB_BASE_ID = 1000;


my $LINE_HEIGHT   = 18;


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}


sub new
{
    my ($class,$parent,$splitter) = @_;
	display($dbg_life,0,"new infoWindowList()");

    my $this = $class->SUPER::new($splitter,-1,[0,0],[-1,-1]);

	$this->{parent} = $parent;
	$this->{frame} = $parent->{frame};
	$this->{sub_mode} = $parent->{sub_mode};

	$this->{ctrls} = [];
	$this->{ctrls_by_path} = {};
	$this->{groups} = [];
	$this->{groups_by_id} = {};
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
	$this->addRepoMenu($this->{sub_mode}?
		$ID_SUBS_WINDOW :
		$ID_INFO_WINDOW);

	EVT_SIZE($this, \&onSize);
	return $this;

}


sub objFromCtrlId
{
	my ($this,$ctrl_id) = @_;
	my $repo_list = getRepoList();
	my $obj = ($ctrl_id >= $REPO_BASE_ID) ?
		$repo_list->[$ctrl_id-$REPO_BASE_ID] :
		$this->{groups}->[$ctrl_id-$SUB_BASE_ID];
	return $obj;
}


sub onEnterLink
{
	my ($ctrl,$event) = @_;
	my $this = $ctrl->GetParent();
	my $ctrl_id = $event->GetId();
	my $obj = $this->objFromCtrlId($ctrl_id);
	$this->{frame}->SetStatusText($obj->{path});
	$ctrl->SetFont($this->{bold_font});
	$ctrl->Refresh();
	$event->Skip();
}


sub onLeaveLink
{
	my ($ctrl,$event) = @_;
	my $this = $ctrl->GetParent();
	my $ctrl_id = $event->GetId();
	my $obj = $this->objFromCtrlId($ctrl_id);
	$this->{frame}->SetStatusText('');
	$ctrl->SetFont($this->GetFont())
		if $obj->{path} ne $this->{selected_path};
	$ctrl->Refresh();
	$event->Skip();
}


sub onRightDown
{
	my ($ctrl,$event) = @_;
	my $this = $ctrl->GetParent();
	my $ctrl_id = $event->GetId();
	my $obj = $this->objFromCtrlId($ctrl_id);
	display($dbg_life,0,"onRightDown($obj->{path})");
	$this->popupRepoMenu($obj) if !$obj->{is_subgroup};
}



sub selectObject
	# Works with either paths to repo objects, or id's of subgroup 'section' object.
{
	my ($this,$path) = @_;
	display($dbg_sel,0,"selectObject($path)");

	# $this->{parent}->SetFocus();
		# switch to the infoWindow if called
		# from another window

	my $ctrl = $this->{ctrls_by_path}->{$path};
	return !error("Could not find ctrl($path)")
		if !$ctrl;

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

	my $ctrl_id = $ctrl->GetId();
	my $obj = $this->objFromCtrlId($ctrl_id);

	display($dbg_sel+1,1,"finishing selectObject($path)");
	$this->{frame}->SetStatusText($obj->{path});
	$this->{parent}->{right}->notifyObjectSelected($obj);
	$this->Refresh();
}



sub onLeftDown
{
	my ($ctrl,$event) = @_;
	my $this = $ctrl->GetParent();
	my $ctrl_id = $event->GetId();
	my $obj = $this->objFromCtrlId($ctrl_id);
	display($dbg_life,0,"onLeftDown($obj->{path})");
	$this->selectObject($obj->{path});
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

	my $sections = $this->{sub_mode} ?
		groupReposAsSubmodules() :
		groupReposBySection();
	$this->DestroyChildren();
	$this->{ctrls} = [];
	$this->{ctrls_by_path} = {};

	my $ypos = 5;

	my $group_num = 0;
	my $page_started = 0;
	for my $section (@$sections)
	{
		my $section_started = 0;
		my $ctrl_section = newCtrlSection($this,$section);
		$ypos += $LINE_HEIGHT if $page_started;	  # blank line between sections
		$page_started = 1;

		for my $repo (@{$section->{repos}})
		{
			# In {sub_mode} the sections contain the following fields:
			#
			#		name == the id of the main submodule repository
			#		id == ditto
			#		path == ditto
			#
			# This snippet will always be trigger in {sub_mode} as the
			# id will never be equal to the path.
			# A ctrl is created using $SUB_BASE_ID, with both the path, and
			# the display being passed in as that ID.

			if (!$section_started && $section->{name} ne $repo->{path})
			{
				if ($this->{sub_mode})
				{
					my $color = $color_black;
					my $id_num = $SUB_BASE_ID + $group_num;
					$this->newCtrl($ypos,$section->{path},$id_num,$section->{name},$color);
					push @{$this->{groups}},$section;
					$this->{groups_by_id}->{$section->{name}} = $section;
				}
				else
				{
					display($dbg_pop,1,"staticText($section->{name})");
					Wx::StaticText->new($this,-1,$section->{name},[5,$ypos]);
				}
				$ypos += $LINE_HEIGHT;
			}

			my $color = linkDisplayColor($repo);
			my $id_num = $REPO_BASE_ID + $repo->{num};
			my $display_name = $repo->pathWithinSection($this->{sub_mode});
			$this->newCtrl($ypos,$repo->{path},$id_num,$display_name,$color);
			$ypos += $LINE_HEIGHT;
			$section_started = 1;
		}
		$group_num++;
	}

	$this->{ysize} = $ypos + $LINE_HEIGHT;
	$this->SetVirtualSize([1000,$this->{ysize}]);
	$this->Refresh();
}


sub newCtrl
{
	my ($this,$ypos,$path,$id_num,$display_name,$color) = @_;
	display($dbg_pop,1,"hyperLink($id_num,$display_name)");
	my $ctrl = apps::gitUI::myHyperlink->new(
		$this,
		$id_num,
		$display_name,
		[5,$ypos],
		[-1,-1],
		$color);
	push @{$this->{ctrls}},$ctrl;
	$this->{ctrls_by_path}->{$path} = $ctrl;
	EVT_LEFT_DOWN($ctrl, \&onLeftDown);
	EVT_RIGHT_DOWN($ctrl, \&onRightDown);
	EVT_ENTER_WINDOW($ctrl, \&onEnterLink);
	EVT_LEAVE_WINDOW($ctrl, \&onLeaveLink);
}



sub notifyRepoChanged
	# Called by infoWindow when the monitor
	# detects a change to a repo
{
	my ($this,$repo) = @_;
	my $path = $repo->{path};
	display($dbg_notify,0,"$this notifyRepoChanged($path)");
	my $ctrl = $this->{ctrls_by_path}->{$path};
	return if $this->{sub_mode} && !$ctrl;
	return error("Could not find ctrl($path)") if !$ctrl;
	my $color = linkDisplayColor($repo);
	$ctrl->SetForegroundColour($color);
	$ctrl->Refresh();
	$this->Refresh();
	$this->{parent}->{right}->notifyObjectSelected($repo)
		if $path eq $this->{selected_path};
}



1;