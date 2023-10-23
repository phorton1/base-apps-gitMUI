#-------------------------------------------
# apps::gitUI::diffCtrl
#-------------------------------------------

package apps::gitUI::diffCtrl;
use strict;
use warnings;
use threads;
use threads::shared;
use Win32::GUI;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_PAINT );
use apps::gitUI::styles;
use Pub::Utils;
use base qw(Wx::ScrolledWindow);	# qw(Wx::Window);


my $dbg_ctrl = 0;
my $dbg_draw = 0;

my $LINE_HEIGHT = 16;


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}


my $font_fixed = Wx::Font->new(9,wxFONTFAMILY_MODERN,wxFONTSTYLE_NORMAL,wxFONTWEIGHT_NORMAL);

sub new
{
    my ($class,$parent) = @_;
	display($dbg_ctrl,0,"new diffCtrl()");

    my $this = $class->SUPER::new($parent);	# ,-1,[0,0],[100,100],wxVSCROLL | wxHSCROLL);
	bless $this,$class;

    $this->{parent} = $parent;
	$this->{lines} = [];

	$this->SetVirtualSize([1000,0]);
	$this->SetBackgroundColour($color_white);
	$this->SetScrollRate($LINE_HEIGHT,$LINE_HEIGHT);

	EVT_PAINT($this, \&onPaint);
	return $this;
}



sub setContent
{
	my ($this,$text) = @_;
	my @lines = split(/\n/,$text);
	my $num_lines = @lines;
	$this->{lines} = [@lines];
	$this->SetVirtualSize([1000,$num_lines * $LINE_HEIGHT]);
	$this->Refresh();
}



#-----------------------------------------------
# onPaint
#-----------------------------------------------

sub onPaint
{
	my ($this, $event) = @_;

 	my $sz = $this->GetSize();
    my $width = $sz->GetWidth();
    my $height = $sz->GetHeight();

	my $dc = Wx::PaintDC->new($this);
	$this->DoPrepareDC($dc);

	# get update rectangle in unscrolled coords

	my $region = $this->GetUpdateRegion();
	my $box = $region->GetBox();
	my ($xstart,$ystart) = $this->CalcUnscrolledPosition($box->x,$box->y);
	my $update_rect = Wx::Rect->new($xstart,$ystart,$box->width,$box->height);
	my $bottom = $update_rect->GetBottom();
	display_rect($dbg_draw,1,"onPaint(bottom=$bottom) update_rect=",$update_rect);

	$dc->SetPen(wxWHITE_PEN);
	$dc->SetBrush(wxWHITE_BRUSH);
	$dc->DrawRectangle($update_rect->x,$update_rect->y,$update_rect->width,$update_rect->height);

	my $first_line = $ystart / $LINE_HEIGHT;
	my $last_line = ($bottom / $LINE_HEIGHT) + 1;
	my $lines = $this->{lines};
	$last_line = @$lines-1 if $last_line > @$lines-1;

	$dc->SetFont($font_fixed);
	for (my $i=$first_line; $i<=$last_line; $i++)
	{
		$dc->DrawText($lines->[$i],5,$i * $LINE_HEIGHT);
	}


}	# onPaint()




1;