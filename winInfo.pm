#------------------------------------------------------------
# apps::gitMUI::winInfo
#------------------------------------------------------------
# A window that shows a list of repos on the left,
# 	and details on the right.
# Operates in two modes based on creation ID
#	$ID_INFO_WINDOW = list of all repos, sorted with spaces
#   $ID_SUBS_WINDOW = list of MAIN_MODULES, with SUBMODULES under them


package apps::gitMUI::winInfo;
use strict;
use warnings;
use threads;
use threads::shared;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_SPLITTER_SASH_POS_CHANGED
	EVT_SIZE );
use Pub::Utils;
use Pub::WX::Window;
use apps::gitMUI::utils;
use apps::gitMUI::Resources;
use apps::gitMUI::winInfoLeft;
use apps::gitMUI::winInfoRight;
use base qw(Pub::WX::Window);


my $dbg_life = 0;
my $dbg_splitters = 0;
my $dbg_pop = 1;
my $dbg_notify = 1;


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}



my $MIN_LEFT_WIDTH 	        = 5;
my $MIN_RIGHT_WIDTH         = 5;
my $INITIAL_LEFT_WIDTH  	= 200;

#---------------------------
# new
#---------------------------

sub new
	# single instance window
	# the 'data' member is the name of the connection information
{
	my ($class,$frame,$id,$book,$data) = @_;
	display($dbg_life,0,"winInfo:new($id,"._def($data).")");
	$data ||= {};

	# use $data if provided

	my $left_width = $data->{left_width} ? $data->{left_width} : $INITIAL_LEFT_WIDTH;

	# construct $this and set data members

	my $name = $id == $ID_SUBS_WINDOW ? 'Subs' : 'Info';
	my $this = $class->SUPER::new($book,$id);
	$this->MyWindow($frame,$book,$id,$name,$data);

	$this->{name} = $name;
	$this->{data} = $data;
	$this->{left_width} = $left_width;
	$this->{sub_mode} = $id == $ID_SUBS_WINDOW ? 1 : 0;

	# Create splitter and child windows
	# We set a minimum pane size of 20 pixels merely
	# to prevent them from dragging the splitters to
	# a closed position.  The actual minimums are set
	# via onSashPosChanged() and doLayout();

	my $vert_splitter  = $this->{vert_splitter}  = Wx::SplitterWindow->new($this, 		   $ID_INFO_SPLITTER_VERT, [0, 0]);
	$vert_splitter->SetMinimumPaneSize(20);

	my $left = $this->{left} = apps::gitMUI::winInfoLeft->new($this,$vert_splitter);
	my $right = $this->{right} = apps::gitMUI::winInfoRight->new($this,$vert_splitter);

    $vert_splitter->SplitVertically($left,$right,300);

	$this->doLayout();
	$left->selectObject($data->{repo_uuid}) if $data->{repo_uuid};

    EVT_SIZE($this,\&onSize);
	EVT_SPLITTER_SASH_POS_CHANGED($this, $ID_INFO_SPLITTER_VERT, \&onSashPosChanged);

	return $this;
}



sub setPaneData
	# Called when via Wx::Frame::createPane() when
	# the window is activated with new data.
	# Prototype of this approach does more than
	# it needs to for future reference.
{
	my ($this,$data) = @_;
	if ($data && ref($data))
	{
		mergeHash($this->{data},$data);
		my $repo_uuid = $data->{repo_uuid};
		$this->{left}->selectObject($repo_uuid) if $repo_uuid;
	}
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

	$this->{vert_splitter}->SetSize([$width,$height]);
	$this->{vert_splitter}->SetSashPosition($this->{left_width});
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

	$pos = $MIN_LEFT_WIDTH if $pos < $MIN_LEFT_WIDTH;
	$pos = $width - $MIN_RIGHT_WIDTH if $pos > $width - $MIN_RIGHT_WIDTH;
	$this->{left_width} = $pos;

	$this->doLayout();
}



sub populate
{
	my ($this) = @_;
	display($dbg_pop,0,"winInfo::populate()");
	$this->{left}->populate();
}


sub notifyRepoChanged
{
	my ($this,$repo) = @_;
	display($dbg_notify,0,"notifyRepoChanged($repo->{path})");
	$this->{left}->notifyRepoChanged($repo);
}



sub getDataForIniFile
{
	my ($this) = @_;
	my $data = {};

	$data->{left_width} = $this->{left_width};
	$data->{repo_uuid} = $this->{left}->{selected_uuid};

	return $data;
}


#----------------------------
# global Copy functionality
#----------------------------
# These methods are currently unused.
# These methods are only needed if we put Copy in
# the application menu. Otherwise the ctrl itself
# implements a EVT_CHAR(3) handler for CTRL-C, and
# it's contextMenu() calls back to it directly
#
#	sub canCopy
#	{
#		my ($this) = @_;
#		display($dbg_copy,0,"canCopy()");
#		return $this->{right}->{text_ctrl}->canCopy();
#	}
#
#	sub doCopy
#	{
#		my ($this) = @_;
#		display($dbg_copy,0,"doCopy()");
#		return $this->{right}->{text_ctrl}->doCopy();
#	}



1;
