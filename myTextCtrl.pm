#-------------------------------------------
# apps::gitMUI::myTextCtrl
#-------------------------------------------

package apps::gitMUI::myTextCtrl;
use strict;
use warnings;
use threads;
use threads::shared;
use Win32::GUI;
use Win32::Clipboard;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_PAINT
	EVT_IDLE
	EVT_MOUSE_EVENTS
	EVT_CHAR
	EVT_BUTTON
	EVT_UPDATE_UI );
use Time::HiRes qw(sleep);
use Pub::Utils;
use Pub::Prefs;
use apps::gitMUI::utils;
use apps::gitMUI::monitor;
use apps::gitMUI::repos;
use apps::gitMUI::repoGroup;
use apps::gitMUI::Resources;
use apps::gitMUI::contextMenu;
use base qw(Wx::ScrolledWindow apps::gitMUI::contextMenu);


my $dbg_ctrl = 0;
my $dbg_draw = 1;
	# -1 to show drag rectangles
my $dbg_mouse = 1;
	# -1 to show moves
my $dbg_click = 0;
	# debug what happens when you click on a link
my $dbg_refresh = 1;
	# -1 to show drag rectangles
my $dbg_word = 1;
my $dbg_scroll = 1;
my $dbg_copy = 1;


my $LINE_HEIGHT = 16;
my $CHAR_WIDTH  = 7;
my $LEFT_MARGIN = 5;



BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}




my $font_fixed = Wx::Font->new(9,wxFONTFAMILY_MODERN,wxFONTSTYLE_NORMAL,wxFONTWEIGHT_NORMAL);
my $font_fixed_bold = Wx::Font->new(9,wxFONTFAMILY_MODERN,wxFONTSTYLE_NORMAL,wxFONTWEIGHT_BOLD);

sub new
{
    my ($class,$parent,$window_id) = @_;
	display($dbg_ctrl,0,"new myTextCtrl($window_id)");
		# $parent) frame="._def($parent->{frame}));

    my $this = $class->SUPER::new($parent);	# ,-1,[0,0],[100,100],wxVSCROLL | wxHSCROLL);
	bless $this,$class;

	$this->addContextMenu();

    $this->{parent} = $parent;
	$this->{frame} = $parent->{frame};
	$this->{window_id} = $window_id;
	$this->{width} = 0;
	$this->{height} = 0;

	$this->{hits} = [];
	$this->{hit} = '';

	# The drag cycle goes like this:
	#
	# 	(0) They left click someplace
	#       This calls init_drag() to start a new drag.
	#		init_drag() calls refreshDrag(undef) to clear any previous drag
	#       We set {drag_start} to indicate a possible new drag
	#       We set {drag_alt} if the shift key (rectangular selection) was pressed at the start
	#
	#   (1) They move the mouse while still having the left button down.
	#		This sets {in_drag} if it's not already set, indicating we are dragging
	#       and calls refreshDrag(new_drag_end) with the current position
	#		which may need to invalidate disjoint regions, or is optimized to only
	#       refresh new additions/subtractions to the drag.
	#
	#	(2) They let the mouse button up. This sets {in_drag} to zero
	#
	# The presence of {drag_end} indicates a selected area.

	$this->{drag_start} = '';			# unscrolled coords of drag_start is set first
	$this->{drag_alt} = 0;				# shift was pressed when starting drag (select rectangle)
	$this->{in_drag} = 0;				# the drag has started
	$this->{drag_end} = '';				# the end position of the drag, set by refreshDrag ONLY

	$this->{scroll_inc} = 0;

	$this->clearContent();

	$this->SetVirtualSize([$LEFT_MARGIN,0]);
	$this->SetBackgroundColour($color_white);
	$this->SetScrollRate($CHAR_WIDTH,$LINE_HEIGHT);

	EVT_IDLE($this, \&onIdle);
	EVT_PAINT($this, \&onPaint);
	EVT_MOUSE_EVENTS($this, \&onMouse);
	EVT_CHAR($this, \&onChar);

	EVT_BUTTON($this, $INFO_RIGHT_COMMAND_SINGLE_PULL, \&onSingleButton);
	EVT_BUTTON($this, $INFO_RIGHT_COMMAND_SINGLE_PUSH, \&onSingleButton);
	EVT_BUTTON($this, $INFO_RIGHT_COMMAND_SINGLE_COMMIT_PARENT, \&onSingleButton);
	EVT_UPDATE_UI($this, $INFO_RIGHT_COMMAND_SINGLE_PUSH, \&onSingleUpdateUI);
	EVT_UPDATE_UI($this, $INFO_RIGHT_COMMAND_SINGLE_PULL, \&onSingleUpdateUI);
	EVT_UPDATE_UI($this, $INFO_RIGHT_COMMAND_SINGLE_COMMIT_PARENT, \&onSingleUpdateUI);

	return $this;
}



sub onSingleUpdateUI
{
	my ($this,$event) = @_;
	my $id = $event->GetId();
	my $ctrl = $event->GetEventObject();
	my $repo = $ctrl->{repo};

	my $enable = 0;
	$enable = 1 if $id == $INFO_RIGHT_COMMAND_SINGLE_PUSH &&
		$repo && $repo->canPush();
	$enable = 1 if $id == $INFO_RIGHT_COMMAND_SINGLE_COMMIT_PARENT &&
		$repo && $repo->canCommitParent();

	if ($id == $INFO_RIGHT_COMMAND_SINGLE_PULL)
	{
		$enable = 1 if $repo && !$repo->{AHEAD};
		my $button_title =
			$repo->needsStash() ? 'Stash+Pull' :
			$repo->canPull() ? 'Needs Pull' :
			'Pull';
		$event->SetText($button_title) if
			$event->GetText() ne $button_title;
	}

	$enable &&= monitorRunning();
	$event->Enable($enable);
}


sub onSingleButton
{
	my ($this,$event) = @_;
	my $id = $event->GetId();
	my $ctrl = $event->GetEventObject();
	my $repo = $ctrl->{repo};

	display($dbg_ctrl,0,"onSingleButton($id,$repo->{path})");

	if ($id == $INFO_RIGHT_COMMAND_SINGLE_PUSH)
	{
		clearSelectedPushRepos();
		setSelectedPushRepo($repo);
		$this->{frame}->doThreadedCommand($ID_COMMAND_PUSH_SELECTED);
	}
	elsif ($id == $INFO_RIGHT_COMMAND_SINGLE_PULL)
	{
		clearSelectedPullRepos();
		setSelectedPullRepo($repo);
		$this->{frame}->doThreadedCommand($ID_COMMAND_PULL_SELECTED);
	}
	elsif ($id == $INFO_RIGHT_COMMAND_SINGLE_COMMIT_PARENT)
	{
		clearSelectedCommitParentRepos();
		setSelectedCommitParentRepo($repo);
		$this->{frame}->onCommandId($ID_COMMAND_COMMIT_SELECTED_PARENTS);
	}
}







sub setRepoContext
{
	my ($this,$repo) = @_;
	$this->{repo_context} = $repo;
}


sub dbgDrag
{
	my ($this,$what) = @_;
	return $this->{$what} ?
		"$this->{$what}->[0],$this->{$what}->[1]" : '';
}

sub init_drag
{
	my ($this) = @_;
	my $dbg_end = $this->dbgDrag('drag_end');
	display($dbg_mouse,0,"init_drag($dbg_end)");
	$this->refreshDrag() if $this->{drag_end};
	$this->{drag_alt} = 0;
	$this->{drag_start} = '';
	$this->{drag_end} = '';
	$this->{in_drag} = 0;
	$this->{scroll_inc} = 0;
}


sub clearContent
{
	my ($this) = @_;
	$this->{content} = [];
	$this->{hits} = [];
	$this->{width} = 0;
	$this->{height} = 0;
	$this->{repo_context} = '';
	$this->init_drag();
	$this->DestroyChildren();
	$this->SetVirtualSize([$LEFT_MARGIN,0]);
}


sub nextYPos
{
	my ($this) = @_;
	return scalar(@{$this->{content}}) * $LINE_HEIGHT;
}

sub getCharWidth
{
	my ($this) = @_;
	return $CHAR_WIDTH;
}


sub addLine
{
	my ($this) = @_;
	my $content = $this->{content};
	my $line = {
		width => 0,
		parts => [] };
	push @$content,$line;
	$this->{height} = @$content * $LINE_HEIGHT;
	$this->SetVirtualSize([$this->{width}+$LEFT_MARGIN,$this->{height} + $LINE_HEIGHT]);
	return $line;
}


sub addPart
{
	my ($this,$line,$bold,$color,$text,$context) = @_;
	$text =~ s/\t/    /g;
	my $part = {
		text  => $text,
		color => $color || $color_black,
		bold  => $bold || 0,
		context  => $context || '' };

	# If there is a context, add a hit_test rectangle.
	# in absolute coordintes. The upper left hand corner
	# will be x == the current $line->{width} and y ==
	# the number_of_lines-1 * $LINE_HEIGHT

	my $char_width = length($text) * $CHAR_WIDTH;
	if ($context)
	{
		my $content = $this->{content};
		my $rect = Wx::Rect->new(
			$line->{width} + $LEFT_MARGIN,
			(@$content-1) * $LINE_HEIGHT,
			$char_width,
			$LINE_HEIGHT);

		my $hit = {
			part => $part,
			rect => $rect };
		push @{$this->{hits}},$hit;
	}

	push @{$line->{parts}},$part;
	my $width = $line->{width} += $char_width;
	$this->{width} = $width if $width > $this->{width};
}


sub addSingleLine
{
	my ($this,$bold,$color,$text,$link) = @_;
	my $line = $this->addLine();
	$this->addPart($line,$bold,$color,$text,$link);
}



#-----------------------------------------------
# onPaint
#-----------------------------------------------

my $dbg_dr = 0;


sub floor
{
	my ($val,$mod) = @_;
	$val = int($val / $mod) * $mod;
	return $val;
}

sub ceil
{
	my ($val,$mod) = @_;
	$val = int($val / $mod) * $mod;
	return $val + $mod - 1;
}

sub floorX  { my ($v)=@_; return floor($v-$LEFT_MARGIN, $CHAR_WIDTH) + $LEFT_MARGIN; }
sub ceilX   { my ($v)=@_; return ceil ($v-$LEFT_MARGIN, $CHAR_WIDTH) + $LEFT_MARGIN; }
sub floorY  { my ($v)=@_; return floor($v, $LINE_HEIGHT); }
sub ceilY   { my ($v)=@_; return ceil ($v, $LINE_HEIGHT); }



sub swap
{
	my ($v1,$v2) = @_;
	my $tmp = $$v1;
	$$v1 = $$v2;
	$$v2 = $tmp;
}



sub drawIntersectRect
{
	my ($dc,$urect,$rect) = @_;
	display_rect($dbg_draw,0,"drawIntersectRect() rect",$urect);

	my $is = Wx::Rect->new($rect->x,$rect->y,$rect->width,$rect->height);
	$is->Intersect($urect);
	$dc->DrawRectangle($is->x,$is->y,$is->width,$is->height)
		if $is->width && $is->height;
}


sub getAltRectangle
{
	my ($this) = @_;
	my ($sx,$sy) = @{$this->{drag_start}};
	my ($ex,$ey) = @{$this->{drag_end}};

	swap(\$sx,\$ex) if $sx > $ex;
	swap(\$sy,\$ey) if $sy > $ey;

	($sx,$sy,$ex,$ey) = (
		floorX($sx),
		floorY($sy),
		ceilX($ex),
		ceilY($ey) );

	display($dbg_draw,0,"getAltRectangle($sx,$sy,$ex,$ey)");

	return Wx::Rect->new($sx,$sy,$ex-$sx+1,$ey-$sy+1);
}


sub getRectangles
{
	my ($this) = @_;
	return ($this->getAltRectangle()) if $this->{drag_alt};

 	my $sz = $this->GetSize();
    my $width = $sz->GetWidth();

	my ($sx,$sy) = @{$this->{drag_start}};
	my ($ex,$ey) = @{$this->{drag_end}};
	my ($sl,$el) = (int($sy/$LINE_HEIGHT), int($ey/$LINE_HEIGHT));
	my $num = abs($el-$sl) + 1;
	my $yplus = 1;

	display($dbg_draw,0,"getRectangles() start($sx,$sy) end($ex,$ey) lines($sl,$el)");

	$sy = floorY($sy);
	$ey = floorY($ey);
		# in all cases we write from the top down

	if ($sy<$ey || ($sy==$ey && $sx<=$ex))	# bottom half from floor(start)
	{
		$sx = floorX($sx);
	}
	else 									# top half to ceil(start)
	{
		$yplus = 0;
		$sx = ceilX($sx);
	}

	my ($fr,$mr,$lr);

	if ($yplus)				# bottom half
	{
		$ex = ceilX($ex);
		my $ex1 = $num>1 ? $width : $ex;
		display($dbg_draw+1,1,"bottom_half start($sx,$sy) end($ex,$ey) ex1($ex1)");

		$fr = Wx::Rect->new($sx,  $sy,                $ex1-$sx+1, $LINE_HEIGHT);
		$mr = Wx::Rect->new(0,    $sy + $LINE_HEIGHT, $width,	  ($num-2) * $LINE_HEIGHT) if $num>2;
		$lr = Wx::Rect->new(0,    $ey, 				  $ex+1,	  $LINE_HEIGHT) if $num>1;
	}
	else 					# top half
	{
		my $sx1 = $num>1 ? 0 : floorX($ex);
		$ex = floorX($ex);

		display($dbg_draw+1,1,"top_half    start($sx,$sy) end($ex,$ey) sx1($sx1)");

		$fr = Wx::Rect->new($sx1, $sy,                $sx-$sx1+1,   $LINE_HEIGHT);
		$mr = Wx::Rect->new(0,    $ey + $LINE_HEIGHT, $width,	    ($num-2) * $LINE_HEIGHT) if $num>2;
		$lr = Wx::Rect->new($ex,  $ey, 				  $width-$ex+1,	$LINE_HEIGHT) if $num > 1;
	}

	display_rect($dbg_draw+1,1,"got fr",$fr) if $fr;
	display_rect($dbg_draw+1,1,"got mr",$mr) if $mr;
	display_rect($dbg_draw+1,1,"got lr",$lr) if $lr;

	return ($fr,$mr,$lr);
}



sub drawDrag
{
	my ($this,$dc,$urect) = @_;

	display_rect($dbg_draw,0,"drawDrag() urect",$urect);

	# $dc->SetBackgroundMode(wxTRANSPARENT) if $this->{in_drag};
	$dc->SetPen(wxLIGHT_GREY_PEN);
	$dc->SetBrush(wxLIGHT_GREY_BRUSH);

	my ($r1,$r2,$r3) = $this->getRectangles();

	drawIntersectRect($dc,$urect,$r1) if $r1;
	drawIntersectRect($dc,$urect,$r2) if $r2;
	drawIntersectRect($dc,$urect,$r3) if $r3;
}



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
	my $urect = Wx::Rect->new($ux,$uy,$uw,$uh);

	display($dbg_draw,0,"onPaint rect($ux,$uy,$uw,$uh) xe($xe) ye($ye)");

	# $dc->SetPen(wxWHITE_PEN);
	# $dc->SetBrush(wxWHITE_BRUSH);
	# $dc->DrawRectangle($ux,$uy,$uw,$uh);
	# $dc->SetBackgroundMode(wxSOLID);
	$dc->SetBackgroundMode(wxTRANSPARENT);

	my $drag_end = $this->{drag_end};
	$this->drawDrag($dc,$urect) if $drag_end;

	# we gather all the lines that intersect the unscrolled rectangle
	# it is important to use int() to prevent artifacts

	my $first_line = int($uy / $LINE_HEIGHT);
	my $last_line  = int($ye / $LINE_HEIGHT);
	my $content = $this->{content};
	$last_line = @$content-1 if $last_line > @$content-1;

	display($dbg_draw,1,"first_line($first_line) last_line($last_line)");

	# drawing optimized to clip in X direction

	$dc->SetFont($font_fixed);

	for (my $i=$first_line; $i<=$last_line; $i++)
	{
		my $ys = $i * $LINE_HEIGHT;
		my $parts = $content->[$i]->{parts};
		display($dbg_draw,1,"line($i) at ys($ys)");

		my $xs = $LEFT_MARGIN;		# where to draw next full part
		for (my $j=0; $j<@$parts; $j++)
		{
			my $part = $parts->[$j];
			my $text = $part->{text};
			my $len  = length($text);
			my $tw   = $len * $CHAR_WIDTH;
			my $te   = $xs + $tw - 1;

			display($dbg_draw,2,"part($j) len($len) tw($tw) te($te) at($xs,$ys) text($text)");

			# if the text starts to the left end of the update rectangle,
			# and ends after the beginning, it overlaps and will be drawn

			if ($xs <= $xe && $te >= $ux)
			{
				# clip the part start pixel to the update rect

				my $ps = $ux > $xs ? $ux : $xs;		# if starts to left of update rect
				my $pe = $te > $xe ? $xe : $te;		# if ends to right of update rect

				# get the character indexes for any chars in view
				# and set cw to the number of chars

				my $cs = int(($ps-$xs) / $CHAR_WIDTH);
				my $ce = int(($pe-$xs) / $CHAR_WIDTH);
				my $cw = $ce - $cs + 1;

				my $txt = substr($text,$cs,$cw);

				display($dbg_draw,3,"ps($ps) pe($pe) cs($cs) ce($ce) cw($cw) at($ps,$ys) txt($txt)");

				if ($part->{hit})
				{
					$dc->SetPen(wxGREEN_PEN);
					$dc->SetBrush(wxGREEN_BRUSH);
					drawIntersectRect($dc,$urect,$part->{hit}->{rect})
				}

				$dc->SetFont($part->{bold} ? $font_fixed_bold : $font_fixed);
				$dc->SetTextForeground($part->{color});
				# $dc->SetTextBackground($part->{hit} ? $color_item_selected : $color_white);
				$dc->DrawText($txt,$ps,$ys);
			}

			$xs += $tw;
		}
	}
}	# onPaint()



sub selectWordAt
{
	my ($this,$ux,$uy) = @_;

	my $l = int($uy / $LINE_HEIGHT);
	my $c = int(($ux-$LEFT_MARGIN) / $CHAR_WIDTH);
	$c = 0 if $c < 0;

	display($dbg_word,0,"selectWordAt($ux,$uy) l($l) c($c)");

	my $line = $this->{content}->[$l];
	if (!$line)
	{
		display($dbg_word,1,"clicked outside of line");
		return;
	}

	my $text = '';
	my $parts = $line->{parts};
	for my $part (@$parts)
	{
		$text .= $part->{text};
	}

	if ($c >= length($text))
	{
		display($dbg_word,1,"clicked outside of line");
		return;
	}

	my $char = substr($text,$c,1);
	if ($char eq ' ')
	{
		display($dbg_word,1,"clicked on space");
		return;
	}

	display($dbg_word,1,"clicked on char($char)");


	my $end = $c;
	my $start = $c;
	my $delim_re = " |,";
	while ($start && substr($text,$start-1,1) !~ /$delim_re/)
	{
		$start--;
	}
	while ($end < length($text)-1 && substr($text,$end+1,1) !~ /$delim_re/)
	{
		$end++;
	}

	my $dbg_text = substr($text,$start,$end-$start+1);
	display($dbg_word,1,"got s($start) e($end) word($dbg_text)");

	my $cw = $end-$start+1;
	my $sy = $l * $LINE_HEIGHT;
	my $sx = $start * $CHAR_WIDTH + $LEFT_MARGIN;
	my $ex = $sx + $cw * $CHAR_WIDTH - 1;
	my $ey = $sy + $LINE_HEIGHT - 1;

	display($dbg_word,1,"selecting $cw chars($sx,$sy,$ex,$ey)");

	$this->{drag_start} = [$sx,$sy];
	$this->{drag_end}   = [$ex,$ey];
	$this->refreshScrolled(Wx::Rect->new($sx,$sy,$ex-$sx+1,$LINE_HEIGHT));
}


#------------------------------------------------
# Optimized Refreshing
#------------------------------------------------

sub samePt
{
	my ($p1,$p2) = @_;
	return (
		$p1 && $p2 &&
		$p1->[0] == $p2->[0] &&
		$p1->[1] == $p2->[1]) ? 1 : 0;
}


sub sameRect
{
	my ($r1,$r2) = @_;
	return (
		$r1 && $r2 &&
		$r1->x==$r2->x &&
		$r1->y==$r2->y &&
		$r1->width==$r2->width &&
		$r1->height==$r2->height) ? 1 : 0;
}


sub refreshScrolled
	# refresh an absolute rectangle in its scrolled position
{
	my ($this,$rect) = @_;
	my ($sx,$sy) = $this->CalcScrolledPosition($rect->x,$rect->y);
	$this->RefreshRect(Wx::Rect->new($sx,$sy,$rect->width,$rect->height));
}


sub refreshAltDiff
	# refresh the diff between two alt (columnar) rectangles
	#
	#			xplus,yplus == 1							  xplus,yplus == 0
	#
    #       <--------- w1 ---------->                   <--------- w1 ---------->
	#    `   x1,x2   ex2                                 x1
	#       +-----------------------+         ^         +-----------------------+
	# y1,y2 |           |           |         |      y1 |           |           |
	#       |           |           |         |         |           |           |
	#       |        h2 |    [1]    |         |         |    [3]    |    [2]    |
	#       |           |           |         |         |           |           |
	#  ey2 `|    w2     |           |         |         |           | x2        |
	#       +-----------------------+         h1        +-----------------------+
	#       |           |                     |`        |        y2 |           |
	#       |           |           |         |         |           |           |
	#       |    [2]    |    [3]    |         |         |    [1]    | h2        |
	#       |           |           |         |         |           |           |
	#       |           |           | ey1     |         |           |    w2     | ey1,ey2
	#       +-----------------------+         v         +-----------------------+
	#                            ex1                                      ex1,ex2
{
	my ($this,$contains,$contained) = @_;

	my $xplus = $contains->x == $contained->x ? 1 : 0;
	my $yplus = $contains->y == $contained->y ? 1 : 0;
	my ($x1,$y1) = ($contains->x,		$contains->y);
	my ($x2,$y2) = ($contained->x,		$contained->y);
	my ($w1,$h1) = ($contains->width,	$contains->height);
	my ($w2,$h2) = ($contained->width,	$contained->height);
	my ($ex1,$ey1) = ($x1 + $w1 - 1,  $y1 + $h1 -1);
	my ($ex2,$ey2) = ($x2 + $w2 - 1,  $y2 + $h2 -1);
	display($dbg_refresh,0,"refreshAltDiff xplus($xplus) yplus($yplus) rect1($x1,$y1,$w1,$h1) rect2($x2,$y2,$w2,$h2)");

	if ($w1 > $w2)
	{
		my $fx = $xplus ? $ex2 + 1  : $x1;
		my $fy = $y2;
		my $w  = $w1 - $w2;
		my $h  = $h2;
		my $rect = Wx::Rect->new($fx,$fy,$w,$h);
		display_rect($dbg_refresh,1,"part1",$rect);
		$this->refreshScrolled($rect);
	}
	if ($h1 > $h2)
	{
		my $fx = $xplus ? $x1   	: $x2;
		my $fy = $yplus ? $ey2 + 1  : $y1;
		my $w  = $w2;
		my $h  = $h1 - $h2;
		my $rect = Wx::Rect->new($fx,$fy,$w,$h);
		display_rect($dbg_refresh,1,"part2",$rect);
		$this->refreshScrolled($rect);
	}
	if ($w1 > $w2 && $h1 > $h2)
	{
		my $fx = $xplus ? $ex2 + 1  : $x1;
		my $fy = $yplus ? $ey2 + 1  : $y1;
		my $w  = $w1 - $w2;
		my $h  = $h1 - $h2;
		my $rect = Wx::Rect->new($fx,$fy,$w,$h);
		display_rect($dbg_refresh,1,"part3",$rect);
		$this->refreshScrolled($rect);
	}
}


sub refreshAlt
	# refresn the alt (columnar) reectangles
{
	my ($this,$or,$nr) = @_;
	if ($nr->Contains($or))		# rectangle grew
	{
		display($dbg_refresh,0,"refreshAlt new_rect contains old_rect");
		$this->refreshAltDiff($nr,$or);
	}
	elsif ($or->Contains($nr))	# rectangle shrank
	{
		display($dbg_refresh,0,"refreshAlt old_rect contains new_rect");
		$this->refreshAltDiff($or,$nr);
	}
	else	# rectangle switched
	{
		my ($l,$t,$r,$b) = (
			$or->x < $nr->x ? $or->x : $nr->x,
			$or->y < $nr->y ? $or->y : $nr->y,
			$or->GetRight > $nr->GetRight ? $or->GetRight : $nr->GetRight,
			$or->GetBottom > $nr->GetBottom ? $or->GetBottom : $nr->GetBottom );
		my $ref_rect = Wx::Rect->new($l,$t,$r-$l+1,$b-$t+1);
		display_rect($dbg_refresh,0,"refreshAlt disjoint refresh_rect",$ref_rect);
		$this->refreshScrolled($ref_rect);
	}
}



sub refreshCur
	# refresh the current line selection
{
	my ($this) = @_;
	display($dbg_refresh+1,2,"refreshCur()");
	my ($r1,$r2,$r3) = $this->getRectangles();
	$this->refreshScrolled($r1) if $r1;
	$this->refreshScrolled($r2) if $r2;
	$this->refreshScrolled($r3) if $r3;
}


sub refreshDiff
	# refresh the difference between old and new line selection
	# we have to resolve everything down to character cells before
	# doing any math or making any comparisons. The default direction
	# within a single cell is forwards.
{
	my ($this,$old,$new) = @_;
	my ($startx,$starty) = @{$this->{drag_start}};
	my ($ox,$oy) = @$old;
	my ($nx,$ny) = @$new;

	# get the character cell and line numbers

	my ($sl,$sc) = (int($starty/$LINE_HEIGHT), 	int(($startx-$LEFT_MARGIN)/$CHAR_WIDTH));
	my ($ol,$oc) = (int($oy/$LINE_HEIGHT), 		int(($ox-$LEFT_MARGIN)/$CHAR_WIDTH));
	my ($nl,$nc) = (int($ny/$LINE_HEIGHT), 		int(($nx-$LEFT_MARGIN)/$CHAR_WIDTH));
	$sc=0 if $sc<0;
	$oc=0 if $oc<0;
	$nc=0 if $oc<0;

	# short ending if the line and character did not change

	if ($ol == $nl && $oc == $nc)
	{
		display($dbg_refresh+1,1,"refreshDiff opos($ol,$oc) npos($nl,$nc) short ending");
		return;
	}

	my $oplus = $ol<$sl || $ol==$sl && $oc<$sc ? 0 : 1;
	my $nplus = $nl<$sl || $nl==$sl && $nc<$sc ? 0 : 1;

	if ($oplus != $nplus)	# disjoint
	{
		display($dbg_refresh,1,"refreshDiff disjoint start($startx,$starty) old($ox,$oy) new($nx,$ny) opos($ol,$oc) npos($nl,$nc) oplus($oplus)");
		display($dbg_refresh,2,"opos($ol,$oc) npos($nl,$nc) oplus($oplus) nplus($nplus)");
		$this->refreshCur();
		$this->{drag_end} = $new;
		$this->refreshCur();
	}
	else
	{
		my $sz = $this->GetSize();
		my $width = $sz->width;

		display($dbg_refresh,1,"refreshDiff start($startx,$starty) old($ox,$oy) new($nx,$ny) opos($ol,$oc) npos($nl,$nc) oplus($oplus)");

		my ($fr,$mr,$lr);
		my $num_old = abs($sl-$ol) + 1;
		my $num_new = abs($nl-$ol) + 1;
		my $mh = ($num_new-2) * $LINE_HEIGHT;

		# in all cases we write from the top down

		$oy = floorY($oy);
		$ny = floorY($ny);

		if ($oplus)				# bottom half
		{
			if ($nl>$ol || ($nl==$ol && $nc>$oc))	# adding to bottom half
			{
				$ox = floorX($ox);		# will redraw first character
				$nx = ceilX($nx);
				my $ex1 = $num_new>1 ? $width : $nx;

				display($dbg_refresh,2,"bottom adding ox($ox) nx($nx) ex1($ex1)");

				$fr = Wx::Rect->new($ox, $oy, $ex1-$ox+1, $LINE_HEIGHT);
				$mr = Wx::Rect->new(0,   $oy + $LINE_HEIGHT, $width, $mh)
					if $num_new > 2;
				$lr = Wx::Rect->new(0,   $ny, $nx+1, 	  $LINE_HEIGHT)
					if $num_new > 1;
			}
			else	# subtracting from bottom half
			{
				$ox = ceilX($ox);
				$nx = floorX($nx>$CHAR_WIDTH ? $nx-$CHAR_WIDTH : $nx);
					# don't erase last character
				my $sx1 = $num_new>1 ? 0 : $nx;

				display($dbg_refresh,2,"bottom subtracting");

				$fr = Wx::Rect->new($sx1, $oy, 	$ox-$sx1+1,   $LINE_HEIGHT);
				$mr = Wx::Rect->new(0,    $ny + $LINE_HEIGHT, $width, $mh)
					if $num_new > 2;
				$lr = Wx::Rect->new($nx,  $ny,  $width-$nx+1, $LINE_HEIGHT)
					if $num_new > 1;
			}
		}
		else	# top half
		{
			if ($nl<$ol || ($nl==$ol && $nc<$oc))	# adding to top half
			{
				$ox = ceilX($ox);	# will redraw first character

				$nx = floorX($nx);
				my $sx1 = $num_new>1 ? 0 : $nx;

				display($dbg_refresh,2,"top adding");

				$fr = Wx::Rect->new($sx1, $oy, 	$ox-$sx1+1,   $LINE_HEIGHT);
				$mr = Wx::Rect->new(0,    $ny + $LINE_HEIGHT, $width, $mh)
					if $num_new > 2;
				$lr = Wx::Rect->new($nx,  $ny,  $width-$nx+1, $LINE_HEIGHT)
					if $num_new > 1;
			}
			else	# subtracting from top half
			{
				$ox = floorX($ox);
				$nx = ceilX($nx>$CHAR_WIDTH ? $nx-$CHAR_WIDTH : $nx);
					# don't erase last character

				my $ex1 = $num_new>1 ? $width : $nx;;

				display($dbg_refresh,2,"top subtracting");

				$fr = Wx::Rect->new($ox, $oy, $ex1-$ox+1, 	$LINE_HEIGHT);
				$mr = Wx::Rect->new(0,   $oy + $LINE_HEIGHT, $width, $mh)
					if $num_new > 2;
				$lr = Wx::Rect->new(0, $ny, $nx+1,	$LINE_HEIGHT)
					if $num_new > 1;
			}
		}

		display_rect($dbg_refresh+1,3,"fr",$fr) if $fr;
		display_rect($dbg_refresh+1,3,"mr",$mr) if $mr;
		display_rect($dbg_refresh+1,3,"lr",$lr) if $lr;

		$this->refreshScrolled($fr) if $fr;
		$this->refreshScrolled($mr) if $mr;
		$this->refreshScrolled($lr) if $lr;

		$this->{drag_end} = $new;
	}
}




sub refreshDrag
	# refresh using current {drag_end}, if any, and $new end,
	# either of which might be ''
{
	my ($this,$new) = @_;
	my $old = $this->{drag_end} || '';
	my $start = $this->{drag_start};

	my $show_old = $old ? $old->[0].",".$old->[1] : '';
	my $show_new = $new ? $new->[0].",".$new->[1] : '';
	my $show_start = $start->[0].",".$start->[1];

	if ($new && !$old)
	{
		warning($dbg_refresh,0,"DRAG_STARTED($show_start} new($show_new)");
	}
	elsif ($old && !$new)
	{
		warning($dbg_refresh,0,"CLEARING_DRAG($show_start} old($show_old)");
	}
	elsif (!$old && !$new)
	{
		warning($dbg_refresh,0,"DRAG_REFRESH CALLED WITH NO OLD OR NEW!");
	}
	else
	{
		display($dbg_refresh,0,"refreshDrag start($show_start) old($show_old) new($show_new)");
	}

	$this->{in_drag} = 1 if $new;

	if ($this->{drag_alt})
	{
		my $or = $old ? $this->getAltRectangle() : '';
		$this->{drag_end} = $new;
		my $nr = $new ? $this->getAltRectangle() : '';

		if (!sameRect($or,$nr))
		{
			display($dbg_refresh,1,"refreshDrag alt");

			if ($or && $nr)
			{
				$this->refreshAlt($or,$nr);
			}
			elsif ($or)
			{
				$this->refreshScrolled($or);
			}
			elsif ($nr)
			{
				$this->refreshScrolled($nr);
			}
		}
	}
	else
	{
		display($dbg_refresh+1,1,"refreshDrag lines");

		if ($old && !$new)
		{
			display($dbg_refresh,2,"refreshCur start($show_start) old($show_old) new($show_new)");
			$this->refreshCur();
			$this->{drag_end} = $new;
		}
		elsif ($new && !$old)
		{
			display($dbg_refresh,2,"refreshCur start($show_start) old($show_old) new($show_new)");
			$this->{drag_end} = $new;
			$this->refreshCur();
		}
		else
		{
			$this->refreshDiff($old,$new);
		}
	}
}



#------------------------------------------------
# Mouse Event Handling and Context
#------------------------------------------------
# Context:
# 		repo = an actual repo
# 		url  = a github url
# 		path = an explorable path
# 		file = a repo relative file
# 		open_main_sub = 0/1 = use the id from the repo in the subs window
#		open_repo_sub = 0/1 = use the path from the repo in the subs window



sub onMouse
{
	my ($this,$event) = @_;
	my $cp = $event->GetPosition();
	my ($sx,$sy) = ($cp->x,$cp->y);
	my ($ux,$uy) = $this->CalcUnscrolledPosition($sx,$sy);
	my $dclick = $event->LeftDClick();
	my $lclick = $dclick || $event->LeftDown();
	my $rclick = $event->RightDown() || $event->RightDClick();
	my $dragging = $event->Dragging();
	my $lup = $event->LeftUp();

	my $VK_ALT = 0x12;
	my $VK_SHIFT = 0x10;
	my $alt = Win32::GUI::GetAsyncKeyState($VK_ALT)?1:0;
	my $shift = Win32::GUI::GetAsyncKeyState($VK_SHIFT)?1:0;

	$this->SetFocus() if $lclick || $rclick;
		# The text ctrl receives focus on any clicks within it
		# so-as to enable the EVT_CHAR.  Note that if the user
		# switches to another pane (or ctrl that takes focus),
		# in order to NOT lose the selection, one has to right
		# click in the window.

	$this->{scroll_inc} = 0;

	my $dbg = $lclick || $rclick || $dragging ? 0 : 1;
	my $dbg_start = $this->dbgDrag('drag_start');
	my $dbg_end = $this->dbgDrag('drag_end');
	display($dbg_mouse + $dbg,0,"onMouse($sx,$sy) unscrolled($ux,$uy) right($rclick) dclick($dclick) left($lclick) lup($lup)".
			" drag($dragging) alt($alt) shift($shift) ".
			" start($dbg_start) end($dbg_end)");

	my $hit = '';
	for my $h (@{$this->{hits}})
	{
		if ($h->{rect}->Contains([$ux,$uy]))
		{
			$hit = $h;
			last;
		}
	}


	my $do_skip = 1;

	if ($this->{in_drag} && $lup)
	{
		$this->{in_drag} = 0;
		warning($dbg_refresh,0,"DRAG_END($dbg_end)");
	}

	# a right click pops up the context menu one way or the other
	# either for the given hit + drag, or the selected_word plus hit

	elsif ($rclick)
	{
		my $context = $hit ? getHitContext($hit) : {};
		$this->selectWordAt($ux,$uy) if !$this->{drag_end};
		$this->popupContextMenu($context);
	}

	# a double click on anything selects the word under the cursor

	elsif ($dclick)
	{
		$this->init_drag();
		$this->selectWordAt($ux,$uy);
	}

	# if they left click,
	#	if (shift) we extend the drag to the new location, and start dragging again
	# otherwise,
	#	if on a hit, the link is activated,
	# 	otherwise a new drag is started

	elsif ($lclick)
	{
		if ($shift)
		{
			warning($dbg_refresh,0,"RESTARTING DRAG FROM SHIFT($dbg_end)");
			$this->{in_drag} = 1;
			$this->refreshDrag([$ux,$uy]);
		}
		else
		{
			$this->init_drag();
			if ($hit)
			{
				$this->mouseClick($hit) ;
				$do_skip = 0;
			}
			else
			{
				$this->{drag_alt} = $alt;
				$this->{drag_start} = [$ux,$uy];
			}
		}
	}


	# a leftUp means the drag has ended
	# in_drag is needed to communicate to onIdle()


	# otherwise, update the drag() and
	# handleScrolling ..

	elsif ($this->{drag_start} && $dragging)
	{
		$this->refreshDrag([$ux,$uy]);
		$this->handleScroll($sx,$sy);
	}
	else
	{
		$this->mouseOver($hit);
	}

	# eat the event if it's a click, so that
	# the window changes appropriate if a link
	# to the winInfo is clicked from the winCommit

	$event->Skip() if $do_skip;
		# needed or else wont get key events
}


sub mouseOver
{
	my ($this,$hit) = @_;
	my $old_hit = $this->{hit};
	return if $hit eq $old_hit;
	display($dbg_mouse,0,"mouseOver(".($old_hit?1:0).",".($hit?1:0).")");

	if ($old_hit)
	{
		display_rect($dbg_mouse,1,"clearing old_hit",$old_hit->{rect});
		$this->refreshScrolled($old_hit->{rect});
		$old_hit->{part}->{hit} = 0;
	}

	my $status = '';

	if ($hit)
	{
		display_rect($dbg_mouse,1,"refreshing hit",$hit->{rect});
		$this->refreshScrolled($hit->{rect});
		$hit->{part}->{hit} = $hit;
		$status = $this->getClickFunction($hit,0);
	}

	$this->{hit} = $hit;
	$this->{frame}->SetStatusText($status);
	$this->Update();

}


sub mouseClick
{
	my ($this,$hit)  = @_;
	my $show_part = $hit->{part};
	display($dbg_click,0,"mouseClick($show_part->{text})");

	my $fxn = $this->getClickFunction($hit,1);
	if ($fxn =~ s/^GITHUB //)
	{
		my $command = "\"start $fxn\"";
		system(1,$command);
	}
	elsif ($fxn =~ s/^SYSTEM //)
	{
		chdir $fxn;
		system(1,"\"$fxn\"");
	}
	elsif ($fxn =~ s/^EDIT //)
	{
		my $command = getPref('GIT_EDITOR')." \"$fxn\"";
		execNoShell($command);
	}
	elsif ($fxn =~ s/^GITUI //)
	{
		execNoShell('git gui',$fxn);
	}
	elsif ($fxn =~ s/^INFO //)
	{
		$this->{frame}->createPane($ID_INFO_WINDOW,undef,{repo_uuid=>$fxn});
	}
	elsif ($fxn =~ s/^MAIN_SUB // ||
		   $fxn =~ s/^REPO_SUB //)
	{
		$this->{frame}->createPane($ID_SUBS_WINDOW,undef,{repo_uuid=>$fxn});
	}
	elsif ($fxn =~ s/^EXPLORE //)
	{
		execExplorer($fxn);
	}
	else
	{
		error("unknown clickFunction($fxn)");
	}
}


sub getClickFunction
{
	my ($this,$hit,$is_click) = @_;

# 		repo = an actual repo
# 		url  = a github url
# 		path = an explorable path
# 		file = a repo relative file
# 		open_main_sub = 0/1 = use the id from the repo in the subs window
#		open_repo_sub = 0/1 = use the path from the repo in the subs window

	my $context = getHitContext($hit);
	return '' if !$context;
	display_hash($dbg_click,1,"getClickFunction",$context)
		if $is_click;

	my $repo = $context->{repo};
	my $filename = $context->{filename} ?
		$context->{filename} :
		$context->{file} ?
			$repo->{path}.$context->{file} : '';

	my $shell_exts = getPref('GIT_SHELL_EXTS');
	my $editor_exts = getPref('GIT_EDITOR_EXTS');

	if ($context->{url})
	{
		return "GITHUB $context->{url}";
	}
	elsif ($filename =~ /\.($shell_exts)$/)
	{
		return "SYSTEM $filename";
	}
	elsif ($filename =~ /\.($editor_exts)$/)
	{
		return "EDIT $filename";
	}
	elsif ($repo)
	{
		my $id = $repo->{id};
		my $uuid = $repo->uuid();
		my $path = $repo->{path};
		my $win_uuid = $this->{repo_context} ?
			$this->{repo_context}->uuid() : '';
		my $is_this_repo = $uuid eq $win_uuid ? 1 : 0;
		my $open_main_sub = $context->{open_main_sub} || 0;
		my $open_repo_sub = $context->{open_repo_sub} || 0;

		if ($is_click)
		{
			display($dbg_click,2,"path($path) id($id)");
			display($dbg_click,2,"uuid($uuid) win_uuid($win_uuid)");
			display($dbg_click,2,"is_this_repo($is_this_repo) open_main_sub($open_main_sub) open_repo_sub($open_repo_sub)");
		}

		return
			$open_main_sub ? "MAIN_SUB $id" :
			$open_repo_sub ? "REPO_SUB $path" :
			$path && $is_this_repo ? "GITUI $path" :
			"INFO $uuid";
	}
	elsif ($context->{path})
	{
		return "EXPLORE $context->{path}";
	}

	# Just in case:

	error("NO FUNCTION FOR CONTEXT");
	display_hash($dbg_click,1,"NO FUNCTION FOR CONTEXT",$context)
		if $is_click;

}




sub getHitContext
{
	my ($hit) = @_;
	my $context = $hit->{part}->{context};
	return $context;
}


#--------------------------------------------------------
# auto scrolling
#--------------------------------------------------------

sub handleScroll
{
	my ($this,$sx,$sy) = @_;
 	my $sz = $this->GetSize();
	my $height = $sz->height;

	my $inc =
		$sy > $height - $LINE_HEIGHT * 2 ? 1 :
		$sy < $LINE_HEIGHT * 2 ? -1 : 0;
	return if !$inc;

	display($dbg_scroll,0,"scroll inc($inc)");

	$this->{scroll_inc} = $inc;

	my ($cur_x, $cur_y) = $this->GetViewStart();
	my $new_y = $cur_y + $inc;
	$new_y = 0 if $new_y < 0;
	if ($new_y != $cur_y)
	{
		$this->Scroll($cur_x,$new_y);
		$this->Update();
	}
}


sub onIdle
{
	my ($this,$event) = @_;
	my $inc = $this->{scroll_inc};
	if ($inc && $this->{in_drag})
	{
		my ($ex,$ey) = @{$this->{drag_end}};
		$ey += $inc * $LINE_HEIGHT;
		return if $ey < 0 || $ey > $this->{height};

		display($dbg_scroll,0,"onIdle autoX($inc)");

		my ($cur_x, $cur_y) = $this->GetViewStart();
		my $new_y = $cur_y + $inc;
		$new_y = 0 if $new_y < 0;

		if ($new_y != $cur_y)
		{
			$this->Scroll($cur_x,$new_y);
			$this->refreshDrag([$ex,$ey]);
			$this->Update();
		}
		sleep(0.02);
		$event->RequestMore();
	}
}


#----------------------------------------------
# copy to clipboard
#-----------------------------------------------
# note that $dbg_copy is in utils.pm

sub onChar
{
	my ($this,$event) = @_;
	my $key_code = $event->GetKeyCode();
	display($dbg_copy,0,"onChar($key_code)");
	$this->init_drag() if $key_code == 27;
	$this->doCopy() if $key_code == 3 && $this->canCopy();
	$event->Skip();
}

sub canCopy
{
	my ($this) = @_;
	my $ret = $this->{drag_end} ? 1 : 0;
	display($dbg_copy,0,"canCopy() returning $ret");
	return $ret
}


sub doCopy
{
	my ($this) = @_;
	display($dbg_copy,0,"doCopy()");
	my $clip = Win32::Clipboard();
	$clip->Set($this->getSelectedText());
}


sub getSelectedText
	# the selection in alt mode is easy. It includes the entire rectangle
	# 	including the start and end.
	# line mode is complicated, and depends on the orientation of the
	# 	selection.  The selection always includes the starting character
	#   and ending character, and any linefeeds between them.
{
	my ($this) = @_;
	my $alt = $this->{drag_alt};
	my ($sx,$sy) = @{$this->{drag_start}};
	my ($ex,$ey) = @{$this->{drag_end}};
	display($dbg_copy,0,"getSelectedText start($sx,$sy) end($ex,$ey)");

	my $fwd = 1;

	my ($sl,$sc,$el,$ec) = (
		int($sy / $LINE_HEIGHT),
		int(($sx - $LEFT_MARGIN) / $CHAR_WIDTH),
		int($ey / $LINE_HEIGHT),
		int(($ex - $LEFT_MARGIN) / $CHAR_WIDTH));
	$sc=0 if $sc<0;
	$ec=0 if $ec<0;

	display($dbg_copy,0,"initial start_lc($sl,$sc) end_lc($el,$ec)");

	if ($alt)
	{
		swap(\$sl,\$el) if $el < $sl;
		swap(\$sc,\$ec) if $ec < $sc;
	}
	elsif ($el<$sl || ($el==$sl && $ec<$sc))
	{
		$fwd = 0;
		swap(\$sl,\$el);
		swap(\$sc,\$ec);
	}

	my $num_lines = $el-$sl+1;

	display($dbg_copy,0,"get($fwd,$num_lines) final start_lc($sl,$sc) end_lc($el,$ec)");

	my $retval = '';
	my $content = $this->{content};

	for my $line_num ($sl..$el)
	{
		$retval .= "\n" if $line_num != $sl;

		# build $text for the full line

		my $text = '';
		my $line = $content->[$line_num];
		my $parts = $line->{parts};
		for my $part (@$parts)
		{
			$text .= $part->{text};
		}

		display($dbg_copy+1,1,"full_line="._lim($text,80));

		if ($alt)
		{
			my $part = substr($text,$sc,$ec-$sc+1);
			display($dbg_copy,2,"alt part=$part");
			$retval .= $part;
		}
		elsif ($line_num == $sl)
		{
			my $part;
			if ($line_num == $el)
			{
				$part = substr($text,$sc,$ec-$sc+1);
				display($dbg_copy,2,"single line part=$part");
			}
			else
			{
				$part = substr($text,$sc);
				display($dbg_copy,2,"first line part=$part");
			}
			$retval .= $part;
		}
		elsif ($line_num == $el)
		{
			my $part = substr($text,0,$ec+1);
			display($dbg_copy,2,"last line part=$part");
			$retval .= $part;
		}
		else
		{
			display($dbg_copy,2,"middle line part=$text");
			$retval .= $text;
		}

	}	# for each line

	return $retval;
}



1;