#-------------------------------------------------------------------------
# Window to invoke gitUI from my /bat/git_repositories.txt
#-------------------------------------------------------------------------

package apps::gitUI::myHyperlink;
use strict;
use warnings;
use Wx qw(:everything);
use Pub::Utils;
use base qw(Wx::StaticText);


our $color_red     = Wx::Colour->new(0xc0 ,0x00, 0x00);  # red
our $color_green   = Wx::Colour->new(0x00 ,0x90, 0x00);  # green
our $color_blue    = Wx::Colour->new(0x00 ,0x00, 0xc0);  # blue

BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		$color_red
		$color_green
		$color_blue
	);
}


sub new
{
	my ($class,$parent,$id,$text,$pos,$size,$color) = @_;
	$color = $color_blue if !defined($color);
	my $this = $class->SUPER::new($parent,$id,$text,$pos,$size);
	$this->SetForegroundColour($color);
	return $this;
}




package apps::gitUI::Window;
use strict;
use warnings;
use Win32::Process;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_SIZE
	EVT_LEFT_DOWN
	EVT_ENTER_WINDOW
	EVT_LEAVE_WINDOW);
use Pub::Utils;
use apps::gitUI::repos;
use base qw(Wx::Window);

my $dbg_win = 0;
my $dbg_pop = 1;
my $dbg_layout = 1;


my $BASE_ID = 1000;

my $ROW_START 	 = 10;
my $ROW_HEIGHT   = 18;
my $COLUMN_START = 10;
my $COLUMN_WIDTH = 180;


sub new
{
	my ($class, $frame) = @_;
	my $this = $class->SUPER::new($frame);
	#bless $this,$class;

	$this->{frame} = $frame;
	$this->{ctrl_sections} = [];
	$this->populate();
	$this->doLayout();

	EVT_SIZE($this, \&onSize);

	return $this;
}



sub repoPathFromId
{
	my ($id) = @_;
	my $repo_list = getRepoList();
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


sub onLink
{
	my ($ctrl,$event) = @_;
	my $id = $event->GetId();
	my $this = $ctrl->GetParent();
	my $path = repoPathFromId($id);
	display($dbg_win,0,"onLink($id) = path-$path");
	chdir($path);

	# This, not system(), is how I figured out how to start
	# git gui without opening an underlying DOS box.

	my $p;
	Win32::Process::Create(
		$p,
		"C:\\Windows\\System32\\cmd.exe",
		"/C git gui",
		0,
		CREATE_NO_WINDOW |
		NORMAL_PRIORITY_CLASS,
		$path );
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

	return if !parseRepos();
	my $sections = getRepoSections();

	display($dbg_pop,0,"populate()");

	for my $section (@$sections)
	{
		my $started = 0;
		my $ctrl_section = newCtrlSection($this,$section);
		for my $repo (@{$section->{repos}})
		{
			if (!$started && $section->{name} ne $repo->{path})
			{
				display($dbg_pop,1,"staticText($section->{name})");
				my $ctrl = Wx::StaticText->new($this,-1,$section->{name},[0,0]);
				addSectionCtrl($ctrl_section,$ctrl,$section->{name});
			}

			my $id = $repo->{num} + $BASE_ID;
			my $display_name = $section->displayName($repo);
			display($dbg_pop,1,"myHyperLink($id,$display_name)");

			my $ctrl = apps::gitUI::myHyperlink->new($this,$id,$display_name,[0,0],[$COLUMN_WIDTH-2,16]);
			addSectionCtrl($ctrl_section,$ctrl,$display_name);
			$started = 1;

			EVT_LEFT_DOWN($ctrl, \&onLink);
			EVT_ENTER_WINDOW($ctrl, \&onEnterLink);
			EVT_LEAVE_WINDOW($ctrl, \&onLeaveLink);
		}
	}
}




#--------------------------------------------------------
# frame
#--------------------------------------------------------

package apps::gitUI::Frame;
use strict;
use warnings;
use Wx qw(:everything);
use Pub::Utils;
use base qw(Wx::Frame);


sub new
{
	my ($class, $parent) = @_;
	my $this = $class->SUPER::new($parent,-1,'gitUI title',[50,50],[600,680]);

    $this->CreateStatusBar();

	apps::gitUI::Window->new($this);
	return $this;
}


#----------------------------------------------------
# application
#----------------------------------------------------
# For some reason, to exit with CTRL-C from the console
# we need to set PERL_SIGNALS=unsafe in the environment.

package apps::gitUI::App;
use strict;
use warnings;
use Pub::Utils;
use Pub::WX::Main;
use base 'Wx::App';

my $dbg_app = 0;

my $frame;


sub OnInit
{
	$frame = apps::gitUI::Frame->new();
	if (!$frame)
	{
		error("unable to create frame");
		return undef;
	}
	setAppFrame($frame);
	$frame->Show( 1 );
	display($dbg_app,0,"gitUIApp started");
	return 1;
}


my $app = apps::gitUI::App->new();

Pub::WX::Main::run($app);

$frame = undef;
display($dbg_app,0,"finished gitUIApp");


1;
