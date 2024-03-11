#--------------------------------------------------
# apps::gitUI::dialogDisplay
#--------------------------------------------------
# A somewhat generic display dialog.
# Candidate for Pub::WX
#
# As always handling the case for NOT automatically
# scrolling is tricky.
#
# Is currently a single instance window that can
# close itself.


package apps::gitUI::genericTextCtrl;
	# the text control that is a child of the dialog
	# does all the hard work.
use strict;
use warnings;
use threads;
use threads::shared;
use Time::HiRes qw(sleep);
use Win32::GUI;
use Win32::Clipboard;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_PAINT
	EVT_IDLE
	EVT_MOUSE_EVENTS
	EVT_CHAR );
use Pub::Utils;
use apps::gitUI::utils;
use base qw(Wx::ScrolledWindow);

my $dbg_ctrl = 1;
my $dbg_draw = 1;
my $dbg_scroll = 1;


my $LINE_HEIGHT = 16;
my $CHAR_WIDTH  = 7;
my $LEFT_MARGIN = 5;

my $CHARS_PER_INDENT = 2;
my $PAD_FILENAMES = 30;


my $font_fixed = Wx::Font->new(9,wxFONTFAMILY_MODERN,wxFONTSTYLE_NORMAL,wxFONTWEIGHT_NORMAL);


sub new
{
    my ($class,$parent) = @_;
	display($dbg_ctrl,0,"new genericTextCtrl()");

    my $this = $class->SUPER::new($parent);	# ,-1,[0,0],[100,100],wxVSCROLL | wxHSCROLL);
	bless $this,$class;

	$this->{content} = [];
	$this->{width} = 0;
	$this->{height} = 0;

	$this->SetVirtualSize([$LEFT_MARGIN,0]);
	$this->SetBackgroundColour($color_black);
	$this->SetScrollRate($CHAR_WIDTH,$LINE_HEIGHT);

	# EVT_IDLE($this, \&onIdle);
	EVT_PAINT($this, \&onPaint);

	return $this;
}



sub addLine
{
	my ($this,$indent_level,$msg,$color) = @_;
	my $content = $this->{content};
	my $draw_line = @$content;

	display($dbg_ctrl,-1,"addLine($draw_line)=$msg)");

    my ($indent,$file,$line_num,$tree) = Pub::Utils::get_indent(3);
		# skip this, the dialog, and the repo method
	my $file_part = "$file\[$line_num\]";

    $indent = 1-$indent_level if $indent_level < 0;
	$indent_level = 0 if $indent_level < 0;

	my $fill = pad("",($indent+$indent_level) * $CHARS_PER_INDENT);
	my $text = pad($file_part,$PAD_FILENAMES) . $fill . $msg;
	my $width = length($text) * $CHAR_WIDTH;

	$this->{width} = $LEFT_MARGIN + $width
		if $LEFT_MARGIN + $width > $this->{width};

	my $line = {
		width => $width,
		text  => $text,
		color => $color };

	push @$content,$line;
	$this->{height} = @$content * $LINE_HEIGHT;
	$this->SetVirtualSize([$this->{width}+$LEFT_MARGIN,$this->{height} + $LINE_HEIGHT]);
	$this->updateScroll($draw_line);

	# calling Update() after Refresh() causes an immediate repaint
	# and the refrehesh rectangle must be in "Scrolled" (Window) coordinates

	my $ys = $draw_line * $LINE_HEIGHT;
	my ($unused_x,$scrolled_y) = $this->CalcScrolledPosition(0,$ys);
	my $update_rect = Wx::Rect->new(0,$scrolled_y, $LEFT_MARGIN + $width,$LINE_HEIGHT);
	display($dbg_ctrl,-1,"updateRect(0,$scrolled_y,".($LEFT_MARGIN + $width).",$LINE_HEIGHT)");

	$this->RefreshRect($update_rect);
	$this->Update();
}


sub updateScroll
{
	my ($this,$line_num) = @_;

	my $sz = $this->GetSize();
	my $height = $sz->height;
	my ($cur_x, $cur_y) = $this->GetViewStart();

	my $first_line = int($cur_y / $LINE_HEIGHT);			# window always scrolled to start of line
	my $num_lines = int($height / $LINE_HEIGHT);			# number of full lines that fit
	my $last_line = $first_line + $num_lines - 1;			# last full line showing

	if ($line_num > $last_line)
	{
		my $new_first = $line_num + 1 - $num_lines;
		my $new_y = $new_first * $LINE_HEIGHT;
		display($dbg_ctrl,-1,"updateScroll($line_num) first($first_line==$cur_y) num($num_lines==$height) last($last_line) new_first($new_first==$new_y)");
		$this->Scroll($cur_x,$new_y);
	}
}




#-----------------------------------------------
# onPaint
#-----------------------------------------------

sub onPaint
{
	my ($this, $event) = @_;

	# the dc uses virtual (unscrolled) coordinates

	my $dc = Wx::PaintDC->new($this);
	$this->DoPrepareDC($dc);

	# so, we clear the update rectangle in unscrolled coords

	my $region = $this->GetUpdateRegion();
	my $box = $region->GetBox();
	my ($ux,$uy) = $this->CalcUnscrolledPosition($box->x,$box->y);
	my ($uw,$uh) = ($box->width,$box->height);
	my ($xe,$ye) = ($ux + $uw - 1, $uy + $uh - 1);
	# my $urect = Wx::Rect->new($ux,$uy,$uw,$uh);

	display($dbg_draw,-1,"PAINT rect($ux,$uy,$uw,$uh) xe($xe) ye($ye)");

	# $dc->SetPen(wxWHITE_PEN);
	# $dc->SetBrush(wxWHITE_BRUSH);
	# $dc->DrawRectangle($ux,$uy,$uw,$uh);
	# $dc->SetBackgroundMode(wxSOLID);
	# $dc->SetBackgroundMode(wxTRANSPARENT);

	$dc->SetFont($font_fixed);

	# we gather all the lines that intersect the unscrolled rectangle
	# it is important to use int() to prevent artifacts

	my $first_line = int($uy / $LINE_HEIGHT);
	my $last_line_calc  = int($ye / $LINE_HEIGHT);
	my $last_line = $last_line_calc;

	my $content = $this->{content};
	$last_line = @$content-1 if $last_line > @$content-1;

	display($dbg_draw,-1,"first_line($first_line) last_line_calc($last_line_calc)  last_line($last_line)");

	# drawing not optimized to clip in X direction

	$dc->SetFont($font_fixed);

	for (my $i=$first_line; $i<=$last_line; $i++)
	{
		my $xs = $LEFT_MARGIN;
		my $ys = $i * $LINE_HEIGHT;

		display($dbg_draw+1,-2,"line($i) at ys($ys)");

		my $line = $content->[$i];
		my $text = $line->{text};
		my $color = $line->{color};

		# my $len  = length($text);
		# my $tw   = $len * $CHAR_WIDTH;
		# my $te   = $xs + $tw - 1;

		$dc->SetTextForeground($color);
		$dc->DrawText($text,$xs,$ys);
	}

	# $event->Skip();

}	# onPaint()




package apps::gitUI::dialogDisplay;
use strict;
use warnings;
use threads;
use threads::shared;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_CLOSE
	EVT_BUTTON);
use Pub::Utils;
use apps::gitUI::utils;
use apps::gitUI::Resources;
use base qw(Wx::Dialog);


my $dbg_dlg = 0;


my $self;


#------------------------------------------------
# ctor
#------------------------------------------------

sub new
{
    my ($class,
		$parent,
		$title) = @_;

	display($dbg_dlg,0,"dialogDisplay->new($title)");

	closeSelf();	# limit to single instance

    my $this = $class->SUPER::new(
		$parent,
		$ID_DIALOG_DISPLAY,
		$title,
		[-1,-1],
		[900,700],
		wxCAPTION | wxCLOSE_BOX | wxRESIZE_BORDER);
	# wxSYSTEM_MENU |

	$this->SetBackgroundColour($color_black);
	$this->SetForegroundColour($color_white);

	$this->{title} = $title;
	$this->{any_errors} = 0;
	$this->{win} = apps::gitUI::genericTextCtrl->new($this);

	$this->{parent} = $parent;
    $this->Show();
	$self = $this;

	EVT_CLOSE($this,\&onClose);
	display($dbg_dlg,0,"ProgressDialog::new() finished");
    return $this;
}



sub onClose
{
	my ($this,$event) = @_;
	display($dbg_dlg,0,"dialogDisplay::onClose()");
	closeSelf();
}

sub closeSelfIfNoErrors
{
	display($dbg_dlg,0,"dialogDisplay::closeSelfIfNoErrors");
	closeSelf() if $self && !$self->{any_errors};
}


sub closeSelf
{
	display($dbg_dlg,0,"dialogDisplay::closeSelf");
	if ($self)
	{
		$self->Destroy();
		$self = undef;
	}
}



#----------------------------------------------------
# update()
#----------------------------------------------------

sub do_display
{
	my ($this,$dbg,$indent,$msg,$color) = @_;
	$color ||= $color_light_grey;
	$this->{win}->addLine($indent,$msg,$color)
		if $debug_level >= $dbg
}

sub do_error
{
	my ($this,$msg) = @_;
	$this->SetTitle($this->{title}." HAS ERRORS!!!")
		if !$this->{any_errors};
	$this->{any_errors}++;
	$this->{win}->addLine(-1,"ERROR: $msg",$color_red);
}

sub do_warning
{
	my ($this,$dbg,$indent,$msg) = @_;
	$this->{win}->addLine($indent,"WARNING: $msg",$color_yellow)
		if $debug_level >= $dbg
}






1;
