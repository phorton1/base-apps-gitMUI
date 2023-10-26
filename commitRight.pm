#!/usr/bin/perl
#-------------------------------------------
# apps::gitUI::commitRight
#-------------------------------------------
# The right side of the commitWindow contains
# the diff and command portions

package apps::gitUI::commitRight;
use strict;
use warnings;
use threads;
use threads::shared;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_SIZE
	EVT_BUTTON );
use apps::gitUI::utils;
use apps::gitUI::diffCtrl;
use apps::gitUI::gitHistory;
use Pub::Utils;
use base qw(Wx::Window);


my $dbg_life = 0;
my $dbg_notify = 1;


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
		$MIN_DIFF_AREA_HEIGHT
		$COMMAND_AREA_HEIGHT
	);
}

my $PANE_TOP = 25;
our $MIN_DIFF_AREA_HEIGHT  = 80;
our $COMMAND_AREA_HEIGHT   = 120;


sub new
{
    my ($class,$parent,$splitter) = @_;
	display($dbg_life,0,"new commitRight()");
    my $this = $class->SUPER::new($splitter);
    $this->{parent} = $parent;

	$this->SetBackgroundColour($color_yellow);

	$this->{status} = Wx::StaticText->new($this,-1,'commitRight',[5,5]);
	my $diff = $this->{diff} = apps::gitUI::diffCtrl->new($this);
	$diff->setContent("test");

	my $panel = $this->{panel} = Wx::Panel->new($this);
	$panel->SetBackgroundColour($color_light_grey);


	$this->doLayout();
	EVT_SIZE($this, \&onSize);
    return $this;

}


sub doLayout
{
	my ($this) = @_;
	my $sz = $this->GetSize();
    my $width = $sz->GetWidth();
    my $height = $sz->GetHeight();
	my $panel_start = $height-$COMMAND_AREA_HEIGHT;
    $this->{diff}->SetSize([$width,$panel_start-$PANE_TOP]);
	$this->{diff}->Move(0,$PANE_TOP);
	$this->{panel}->SetSize([$width,$COMMAND_AREA_HEIGHT]);
	$this->{panel}->Move(0,$panel_start);
	# $this->Refresh();
}

sub onSize
{
    my ($this,$event) = @_;
	$this->doLayout();
    $event->Skip();
}



sub notifyContent
{
	my ($this,$data) = @_;
	display($dbg_notify,0,"commitRight::notifyContent() called");

	my $repo = $data->{repo};
	my $filename = $data->{filename};
	my $text = '';
	if ($filename)
	{
		$this->{status}->SetLabel("file: $filename");
		$text = getTextFile($filename);
	}
	elsif ($repo)
	{
		$this->{status}->SetLabel("repo: <b>$repo->{id}</b>  branch: <b>".gitCurrentBranch($repo)."</b>");
		$text = $repo->toText();
		$text .= "\nHISTORY:\n".gitHistoryText($repo,0);
	}
	$this->{diff}->setContent($text);
}




1;
