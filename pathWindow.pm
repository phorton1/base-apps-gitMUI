#-------------------------------------------------------------------------
# Window to show repos by path with section breaks
#-------------------------------------------------------------------------

package apps::gitUI::pathWindow;
use strict;
use warnings;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_SIZE
	EVT_LEFT_DOWN
	EVT_RIGHT_DOWN
	EVT_ENTER_WINDOW
	EVT_LEAVE_WINDOW);
use Pub::Utils;
use Pub::WX::Window;
use apps::gitUI::repos;
use apps::gitUI::utils;
use apps::gitUI::repoMenu;
use apps::gitUI::Resources;
use apps::gitUI::myHyperlink;
use base qw(Pub::WX::Window apps::gitUI::repoMenu);

my $dbg_win = 0;
my $dbg_pop = 1;
my $dbg_layout = 1;
my $dbg_notify = 1;

my $USE_IDS_FOR_DISPLAY = 1;

my $ROW_START 	 = 10;
my $ROW_HEIGHT   = 18;
my $COLUMN_START = 10;
my $COLUMN_WIDTH = 180;


sub new
	# single instance window
{
	my ($class,$frame,$id,$book,$data) = @_;
	my $name = 'Paths';

	display($dbg_win,0,"pathWindow::new($frame,$id,"._def($book).","._def($data).")");
	my $this = $class->SUPER::new($book,$id);
	$this->MyWindow($frame,$book,$id,$name,$data);

	$this->SetBackgroundColour($color_white);
	$this->{ctrl_sections} = [];
	$this->{ctrls_by_path} = {};

	$this->populate();

	$this->addRepoMenu($ID_PATH_WINDOW);
	EVT_SIZE($this, \&onSize);
	return $this;
}


sub onEnterLink
{
	my ($ctrl,$event) = @_;
	my $event_id = $event->GetId();
	my $this = $ctrl->GetParent();
	my $repo = $ctrl->{repo};
	$this->{frame}->SetStatusText("INFO $repo->{path}");
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


sub onLeftDown
{
	my ($ctrl,$event) = @_;
	my $event_id = $event->GetId();
	my $this = $ctrl->GetParent();
	my $repo = $ctrl->{repo};
	my $path = $repo->{path};
	display($dbg_win,0,"onLeftDown($event_id,$path)");
	$this->{frame}->createPane($ID_INFO_WINDOW,undef,{repo_path=>$path});
}


sub onRightDown
{
	my ($ctrl,$event) = @_;
	my $event_id = $event->GetId();
	my $this = $ctrl->GetParent();
	my $repo = $ctrl->{repo};
	display($dbg_win,0,"onRightDown($event_id,$repo->{path}");
	$this->popupRepoMenu($repo);

}




sub onSize
{
	my ($this,$event) = @_;
	$this->doLayout();
    $event->Skip();
}


sub doLayout
{
	my ($this) = @_;
	my $sz = $this->GetSize();
    my $width = $sz->GetWidth();
    my $height = $sz->GetHeight();
	my $NUM_PER = int(($height - $ROW_START) / $ROW_HEIGHT);
	return if $NUM_PER < 2;

	display($dbg_layout,0,"doLayout() NUM_PER=$NUM_PER");

	# always start new sections at top of the screen
	# each column has at least one section
	# do not start a section unless at least two items will fit

	my $row = 0;
	my $col = 0;
	for my $ctrl_section (@{$this->{ctrl_sections}})
	{
		my $ctrls = $ctrl_section->{ctrls};
		my $num_ctrls = @$ctrls;
		display($dbg_layout,1,"ctrl_section($ctrl_section->{section}->{name}) row=$row col=$col  num=$num_ctrls");

		if ($row + 2 >= $NUM_PER)	# to fit each section fully: $num_ctrls > $NUM_PER)
		{
			$row = 0;
			$col++;
		}

		$row++ if $row;		# blank line for subsequent sections in same column

		for my $ctrl (@$ctrls)
		{
			my $x = $COLUMN_START + $col * $COLUMN_WIDTH;
			my $y = $ROW_START + $row * $ROW_HEIGHT;
			$ctrl->Move($x,$y);

			$row++;
			if ($row >= $NUM_PER)
			{
				$row = 0;
				$col++;
			}
		}
	}
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

	for my $section (@$sections)
	{
		my $started = 0;
		my $ctrl_section = newCtrlSection($this,$section);
		for my $repo (@{$section->{repos}})
		{
			if (!$started && $section->{name} ne $repo->{path})
			{
				my $name = $section->{name};
				$name =~ s/^\/|^-//;
				$name =~ s/\//-/g if $USE_IDS_FOR_DISPLAY;
				display($dbg_pop,1,"staticText($name)");
				my $ctrl = Wx::StaticText->new($this,-1,$name,[0,0]);
				addSectionCtrl($ctrl_section,$ctrl,$name);
			}

			my $display_name = $USE_IDS_FOR_DISPLAY ?
				$repo->idWithinSection() :
				$repo->pathWithinSection();
			display($dbg_pop,1,"hyperLink($display_name)");

			my $color = linkDisplayColor($repo);
			my $ctrl = apps::gitUI::myHyperlink->new(
				$this,
				-1,
				$display_name,
				[0,0],
				[$COLUMN_WIDTH-2,16],
				$color);
			addSectionCtrl($ctrl_section,$ctrl,$display_name);
			$this->{ctrls_by_path}->{$repo->{path}} = $ctrl;
			$ctrl->{repo} = $repo;
			$started = 1;

			EVT_LEFT_DOWN($ctrl, \&onLeftDown);
			EVT_RIGHT_DOWN($ctrl, \&onRightDown);
			EVT_ENTER_WINDOW($ctrl, \&onEnterLink);
			EVT_LEAVE_WINDOW($ctrl, \&onLeaveLink);
		}
	}
	$this->doLayout();
}



sub notifyRepoChanged
{
	my ($this,$repo) = @_;
	display($dbg_notify,0,"notifyRepoChanged($repo->{path})");

	my $path = $repo->{path};
	my $ctrl = $this->{ctrls_by_path}->{$path};
	if ($ctrl)
	{
		my $color = linkDisplayColor($repo);
		$ctrl->SetForegroundColour($color);
		$ctrl->Refresh();
	}
}




1;
