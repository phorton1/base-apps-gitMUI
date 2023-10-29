#-------------------------------------------
# apps::gitUI::myTextCtrl
#-------------------------------------------

package apps::gitUI::myTextCtrl;
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


sub clearContent
{
	my ($this) = @_;
	$this->{content} = [];
	$this->{width} = 0;
	$this->SetVirtualSize([0,0]);
}

sub addLine
{
	my ($this) = @_;
	my $content = $this->{content};
	my $line = {
		width => 0,
		parts => [] };
	push @$content,$line;
	$this->SetVirtualSize([$this->{width},@$content * $LINE_HEIGHT]);
	return $line;
}


sub addPart
{
	my ($this,$line,$bold,$color,$text,$link) = @_;
	$text =~ s/\t/    /g;
	my $part = {
		text  => $text,
		color => $color || $color_black,
		bold  => $bold || 0,
		link  => $link || '' };
	push @{$line->{parts}},$part;
	my $width = $line->{width} += length($text) * $CHAR_WIDTH;
	$this->{width} = $width if $width > $this->{width};
}


sub addSingleLine
{
	my ($this,$bold,$color,$text,$link) = @_;
	my $line = $this->addLine();
	$this->addPart($line,$bold,$color,$text,$link);
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

	$this->clearContent();

	$this->SetVirtualSize([0,0]);
	$this->SetBackgroundColour($color_white);
	$this->SetScrollRate($CHAR_WIDTH,$LINE_HEIGHT);

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

	# the dc uses virtual (unscrolled) coordinates

	my $dc = Wx::PaintDC->new($this);
	$this->DoPrepareDC($dc);

	# so, we clear the update rectangle in unscrolled coords

	my $region = $this->GetUpdateRegion();
	my $box = $region->GetBox();
	my ($xstart,$ystart) = $this->CalcUnscrolledPosition($box->x,$box->y);
	my $update_rect = Wx::Rect->new($xstart,$ystart,$box->width,$box->height);
	my $bottom = $update_rect->GetBottom();
	display_rect($dbg_draw,0,"onPaint(bottom=$bottom) update_rect=",$update_rect);

	$dc->SetPen(wxWHITE_PEN);
	$dc->SetBrush(wxWHITE_BRUSH);
	$dc->DrawRectangle($update_rect->x,$update_rect->y,$update_rect->width,$update_rect->height);

	# we gather all the lines that intersect the unscrolled rectangle
	# it is important to use int() to prevent artifacts

	my $first_line = int($ystart / $LINE_HEIGHT);
	my $last_line = int($bottom / $LINE_HEIGHT) + 1;
	my $content = $this->{content};
	$last_line = @$content-1 if $last_line > @$content-1;

	# drawing could be optimized to clip in X direction

	$dc->SetFont($font_fixed);
	for (my $i=$first_line; $i<=$last_line; $i++)
	{
		display($dbg_draw+1,1,"line($i)");

		my $xpos = 5;
		my $parts = $content->[$i]->{parts};
		for (my $j=0; $j<@$parts; $j++)
		{
			my $part = $parts->[$j];
			my $text = $part->{text};
			display($dbg_draw,2,"part($text})");

			$dc->SetFont($part->{bold} ? $font_fixed_bold : $font_fixed);
			$dc->SetTextForeground($part->{color});
			$dc->DrawText($text,$xpos,$i * $LINE_HEIGHT);
			$xpos += length($text) * $CHAR_WIDTH;
		}
	}


}	# onPaint()




1;