#-------------------------------------------------------------------------
# Window to invoke gitUI from my /bat/git_repositories.txt
#-------------------------------------------------------------------------

package gitUIWindow;
use strict;
use warnings;
use Win32::Process;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_SIZE
	EVT_HYPERLINK
	EVT_ENTER_WINDOW
	EVT_LEAVE_WINDOW);
use Pub::Utils;
use base qw(Wx::Window);


my $BASE_ID = 1000;

my $ROW_START 	 = 10;
my $ROW_HEIGHT   = 18;
my $COLUMN_START = 10;
my $COLUMN_WIDTH = 180;

my $repos_file = "/base/bat/git_repositories.txt";

our $color_red     = Wx::Colour->new(0xc0 ,0x00, 0x00);  # red
our $color_green   = Wx::Colour->new(0x00 ,0x90, 0x00);  # green
our $color_blue    = Wx::Colour->new(0x00 ,0x00, 0xc0);  # blue



my @paths;



sub new
{
	my ($class, $frame) = @_;
	my $this = $class->SUPER::new($frame);
	#bless $this,$class;

	$this->{frame} = $frame;
	$this->{ctrls} = [];
	$this->populate();
	$this->doLayout();

	EVT_SIZE($this, \&onSize);
	EVT_HYPERLINK($this, -1, \&onLink);

	return $this;
}



sub onLink
{
	my ($this,$event) = @_;
	my $id = $event->GetId();
	my $path = $paths[$id  - $BASE_ID];
	display(0,0,"onLink($id) = path-$path");
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

	for my $ctrl (@{$this->{ctrls}})
	{
		my $num = $ctrl->{num};
		my $row = int($num % $NUM_PER);
		my $col = int($num / $NUM_PER);
		my $x = $COLUMN_START + $col * $COLUMN_WIDTH;
		my $y = $ROW_START + $row * $ROW_HEIGHT;
		$ctrl->{ctrl}->Move($x,$y);
	}
}



sub populate
{
	my ($this) = @_;
	my $text = getTextFile($repos_file);
    if ($text)
    {
		my $id_num = 0;
		my $display_num = 0;
		my $section = '';
		my $section_name = '';
		my $section_started = 0;
		my $ctrls = $this->{ctrls};
        for my $line (split(/\n/,$text))
        {
			$line =~ s/#.*$//;
			$line =~ s/^\s+//;
			$line =~ s/\s+$//;

			# get section path RE and optional name if different

			if ($line =~ /^SECTION\t/)
			{
				my @parts = split(/\t/,$line);
				$section = $parts[1];
				$section =~ s/^\s+|\s+$//g;
				$section_name = $parts[2] || $section;
				$section =~ s/\//\\\//g;
				$section_started = 0;
			}

			# Repos start with a forward slash

			elsif ($line =~ /^\//)
			{
				my @parts = split(/\t/,$line);
				my $path = shift @parts;
				my $display = $path;
				my $elipses = $section && $display =~ s/^$section// ? 1 : 0;

				# display a break for the section

				if ($section && !$section_started)
				{
					$section_started = 1;
					$display_num ++;

					# if the section is NOT the same as the first path
					# throw out a static text ..

					if ($display)	# RE did not absorb the whole thing
					{
						my $ctrl = Wx::StaticText->new($this,-1,$section_name,[0,0]);
						push @$ctrls,{
							num => $display_num++,
							ctrl => $ctrl };
					}
				}

				my $MAX_LEN = 28;
					# not including elipses

				# if the whole path was matched, restore it

				if (!$display)
				{
					$display = $path;
				}

				# if was not replaced, and won't fit,
				# set replaced and shrink it

				if (length($display)>$MAX_LEN)
				{
					$display = substr($display,-$MAX_LEN);
					$elipses = 1;
				}

				$display = '...'.$display if $elipses;

				# push the path and ctrl

				push @paths,$path;
				my $ctrl = Wx::HyperlinkCtrl->new($this,$BASE_ID+$id_num++,$display,'',[0,0],[$COLUMN_WIDTH-2,16]);
				$ctrl->SetHoverColour($color_green);

				EVT_ENTER_WINDOW($ctrl, \&onEnterLink);
				EVT_LEAVE_WINDOW($ctrl, \&onLeaveLink);

				push @$ctrls,{
					num => $display_num++,
					ctrl => $ctrl };
			}
		}
    }
    else
    {
        error("Could not open $repos_file");
        return;
    }

    if (!@paths)
    {
        error("No repositories found in $repos_file");
        return;
    }
}



sub onEnterLink
{
	my ($ctrl,$event) = @_;
	my $id = $event->GetId();
	my $this = $ctrl->GetParent();
	my $path = $paths[$id  - $BASE_ID];
	$this->{frame}->SetStatusText($path);
}
sub onLeaveLink
{
	my ($ctrl,$event) = @_;
	my $this = $ctrl->GetParent();
	$this->{frame}->SetStatusText('');
}




#--------------------------------------------------------
# frame
#--------------------------------------------------------

package gitUIFrame;
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


	gitUIWindow->new($this);
	return $this;
}


#----------------------------------------------------
# application
#----------------------------------------------------
# For some reason, to exit with CTRL-C from the console
# we need to set PERL_SIGNALS=unsafe in the environment.

package gitUIApp;
use strict;
use warnings;
use Pub::Utils;
use Pub::WX::Main;
use base 'Wx::App';


my $frame;


sub OnInit
{
	$frame = gitUIFrame->new();
	if (!$frame)
	{
		error("unable to create frame");
		return undef;
	}
	setAppFrame($frame);
	$frame->Show( 1 );
	display(0,0,"gitUIApp started");
	return 1;
}


my $app = gitUIApp->new();

Pub::WX::Main::run($app);


display(0,0,"ending gitUIApp");
$frame = undef;
display(0,0,"finished gitUIApp");


1;
