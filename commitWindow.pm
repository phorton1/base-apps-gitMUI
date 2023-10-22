#!/usr/bin/perl
#------------------------------------------------------------
# apps::gitUI::commitWindow
#------------------------------------------------------------
# A gitUI like window that acts on multiple repositories


package apps::gitUI::commitWindow;
use strict;
use warnings;
use threads;
use threads::shared;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_SPLITTER_SASH_POS_CHANGED
	EVT_SIZE );
use apps::gitUI::commitList;
use apps::gitUI::commitRight;
use Pub::Utils;
use Pub::WX::Window;
use base qw(Wx::Window Pub::WX::Window);


my $dbg_life = 0;
my $dbg_splitters = 0;


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
		$WIN_MIN_WIDTH
		$WIN_MIN_HEIGHT
	);
}


my (
	$ID_SPLITTER_VERT,
	$ID_SPLITTER_LEFT ) = (9000..9100);


my $MIN_LEFT_WIDTH 	        = 80;
my $MIN_RIGHT_WIDTH         = 240;
my $MIN_LEFT_TOP_PCT        = 20;
my $MAX_LEFT_TOP_PCT        = 80;
my $INITIAL_LEFT_WIDTH  	= 200;
my $INITIAL_LEFT_TOP_PCT    = 50;


our $WIN_MIN_WIDTH = $MIN_LEFT_WIDTH + $MIN_RIGHT_WIDTH + 1;
our $WIN_MIN_HEIGHT = $COMMAND_AREA_HEIGHT + $MIN_DIFF_AREA_HEIGHT;
	# $COMMAND_AREA_HEIGHT and $MIN_DIFF_AREA_HEIGHT are from commitRight.pm
	# These values are used by the gitUI Frame::SetMinimumSize();


my $win_instance = 0;

#---------------------------
# new
#---------------------------

sub new
	# the 'data' member is the name of the connection information
{
	my ($class,$frame,$id,$book,$data) = @_;
	display($dbg_life,0,"commitWindow:new("._def($data).")");

	# parse $data if provided

	my $left_width 	 = $INITIAL_LEFT_WIDTH;
	my $left_top_pct = $INITIAL_LEFT_TOP_PCT;
	if ($data)
	{
		$left_width = $data->{left_width} if $data->{left_width};
		$left_top_pct = $data->{left_top_pct} if $data->{left_top_pct};
	}

	# construct $this and set data members

	my $instance = $win_instance++;
	my $name = 'Commit';
	$name .= "($instance)" if $instance;

	my $this = $class->SUPER::new($book,$id);
	$this->MyWindow($frame,$book,$id,$name,$data,$instance);

	$this->{name} = $name;
	$this->{data} = $data;
	$this->{left_width} = $left_width;
	$this->{left_top_pct} = $left_top_pct;

	# Create splitters and child windows
	# We set a minimum pane size of 20 pixels merely
	# to prevent them from dragging the splitters to
	# a closed position.  The actual minimums are set
	# via onSashPosChanged() and doLayout();

	my $vert_splitter  = $this->{vert_splitter}  = Wx::SplitterWindow->new($this, 		   $ID_SPLITTER_VERT, [0, 0]);
	my $left_splitter  = $this->{left_splitter}  = Wx::SplitterWindow->new($vert_splitter, $ID_SPLITTER_LEFT, [0, 0]);
	$vert_splitter->SetMinimumPaneSize(20);
	$left_splitter->SetMinimumPaneSize(20);

	my $unstaged  = $this->{unstaged} = apps::gitUI::commitList->new($this,0,$left_splitter);
	my $staged    = $this->{staged}   = apps::gitUI::commitList->new($this,1,$left_splitter);
	my $right     = $this->{right} 	  = apps::gitUI::commitRight->new($this,$vert_splitter);

    $vert_splitter->SplitVertically($left_splitter,$right,300);
    $left_splitter->SplitHorizontally($unstaged,$staged,100);

	# Continue ...

    $this->doLayout();

    EVT_SIZE($this,\&onSize);
	EVT_SPLITTER_SASH_POS_CHANGED($this, $ID_SPLITTER_VERT, \&onSashPosChanged);
	EVT_SPLITTER_SASH_POS_CHANGED($this, $ID_SPLITTER_LEFT, \&onSashPosChanged);

	return $this;
}



sub onClose
{
	my ($this,$event) = @_;
	display($dbg_life,0,"commitWindow::onClose() called");
	$this->SUPER::onClose($event);
	$event->Skip();
}


#------------------------------------------
# spiitter handline
#------------------------------------------

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

	my $left_pos = int($height * ($this->{left_top_pct}/100));

	$this->{vert_splitter}->SetSize([$width,$height]);
	$this->{vert_splitter}->SetSashPosition($this->{left_width});
	$this->{left_splitter}->SetSashPosition($left_pos);
}


sub onSashPosChanged
{
	my ($this,$event) = @_;
	my $id = $event->GetId();
	my $pos = $event->GetSashPosition();

	my $sz = $this->GetSize();
    my $width = $sz->GetWidth();
    my $height = $sz->GetHeight();
	display($dbg_splitters,0,"this($this) onSashPosChanged($id) pos($pos) width($width) height($height)");

	if ($id == $ID_SPLITTER_VERT)
	{
		$pos = $MIN_LEFT_WIDTH if $pos < $MIN_LEFT_WIDTH;
		$pos = $width - $MIN_RIGHT_WIDTH if $pos > $width - $MIN_RIGHT_WIDTH;
		$this->{left_width} = $pos
	}
	elsif ($id == $ID_SPLITTER_LEFT)
	{
		my $pct = (100*$pos) / $height;
		$pct = $MIN_LEFT_TOP_PCT if $pct < $MIN_LEFT_TOP_PCT;
		$pct = $MAX_LEFT_TOP_PCT if $pct > $MAX_LEFT_TOP_PCT;
		$this->{left_top_pct} = $pct;
	}
	$this->doLayout();
}



my $dbg_notify = 0;

sub notifyRepoChanged
{
	my ($this,$repo) = @_;

	display($dbg_notify,0,"notifyRepoChanged($repo->{path})");
	$this->{unstaged}->populate();
	$this->{staged}->populate();
}



1;
