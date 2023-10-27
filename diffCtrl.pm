#-------------------------------------------
# apps::gitUI::diffCtrl
#-------------------------------------------
# The content is a reference to an array of 'lines'
# where each 'line' is itself an array ref, and consists
# of groups of 3 scalars ($bold, $color, $text)
# to write out the line in different styles.
#
# i.e. $content = [
#     [ 0, $color_black, 'blah' ],	 		# line is 'blah' in normal black
#     [ 1, $color_blue,  'Blue_Bold',		# line is 'Blue Bold normal_red'
#       0, $color_red,	 ' normal_red' ],	# with style & colors
#	];


package apps::gitUI::diffCtrl;
use strict;
use warnings;
use threads;
use threads::shared;
use Win32::GUI;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_PAINT );
use Pub::Utils;
use apps::gitUI::utils;
use base qw(Wx::ScrolledWindow);	# qw(Wx::Window);


my $dbg_ctrl = 0;
my $dbg_draw = 1;

my $LINE_HEIGHT = 16;
my $CHAR_WIDTH  = 7;


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}


my $font_fixed = Wx::Font->new(9,wxFONTFAMILY_MODERN,wxFONTSTYLE_NORMAL,wxFONTWEIGHT_NORMAL);
my $font_fixed_bold = Wx::Font->new(9,wxFONTFAMILY_MODERN,wxFONTSTYLE_NORMAL,wxFONTWEIGHT_BOLD);

sub new
{
    my ($class,$parent) = @_;
	display($dbg_ctrl,0,"new diffCtrl()");

    my $this = $class->SUPER::new($parent);	# ,-1,[0,0],[100,100],wxVSCROLL | wxHSCROLL);
	bless $this,$class;

    $this->{parent} = $parent;
	$this->{content} = [];

	$this->SetVirtualSize([1000,0]);
	$this->SetBackgroundColour($color_white);
	$this->SetScrollRate($LINE_HEIGHT,$LINE_HEIGHT);

	EVT_PAINT($this, \&onPaint);
	return $this;
}



sub setContent
{
	my ($this,$content) = @_;
	$this->{content} = $content;
	my $num_lines = @$content;
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
	display_rect($dbg_draw,0,"onPaint(bottom=$bottom) update_rect=",$update_rect);

	$dc->SetPen(wxWHITE_PEN);
	$dc->SetBrush(wxWHITE_BRUSH);
	$dc->DrawRectangle($update_rect->x,$update_rect->y,$update_rect->width,$update_rect->height);

	my $first_line = $ystart / $LINE_HEIGHT;
	my $last_line = ($bottom / $LINE_HEIGHT) + 1;
	my $content = $this->{content};
	$last_line = @$content-1 if $last_line > @$content-1;

	$dc->SetFont($font_fixed);
	for (my $i=$first_line; $i<=$last_line; $i++)
	{
		display($dbg_draw+1,1,"line($i)");

		my $xpos = 5;
		my $lines = $content->[$i];
		my $num_lines = @$lines / 3;
		for (my $j=0; $j<$num_lines; $j++)
		{
			my $bold  = $lines->[$j*3];
			my $color = $lines->[$j*3 + 1];
			my $text  = $lines->[$j*3 + 2];

			display($dbg_draw,2,"part($text)");

			$dc->SetFont($bold ? $font_fixed_bold : $font_fixed);
			$dc->SetTextForeground($color);
			$dc->DrawText($text,$xpos,$i * $LINE_HEIGHT);
			$xpos += length($text) * $CHAR_WIDTH;
		}
	}


}	# onPaint()




1;