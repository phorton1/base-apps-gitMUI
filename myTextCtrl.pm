#-------------------------------------------
# apps::gitUI::myTextCtrl
#-------------------------------------------
# context may be:
#
#    path => a fully qualified folder path
#		execExplorer
#       maybe show in komodo places somehow
#    filename => a fully qualified filename
#       fileMenu
#       	komodo, explorer shell, notepad
#    repo_path => a fully qualified repo path
#		repoMenu
#    repo,file => a repo and a relative filename

package apps::gitUI::myTextCtrl;
use strict;
use warnings;
use threads;
use threads::shared;
use Win32::GUI;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_PAINT
	EVT_MOUSE_EVENTS );
use Pub::Utils;
use apps::gitUI::utils;
use apps::gitUI::repos;
use apps::gitUI::Resources;
use apps::gitUI::contextMenu;
use base qw(Wx::ScrolledWindow apps::gitUI::contextMenu);


my $dbg_ctrl = 0;
my $dbg_draw = 1;
my $dbg_mouse = 1;

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

	$this->addContextMenu();

    $this->{parent} = $parent;
	$this->{frame} = $parent->{frame};
	$this->{hits} = [];
	$this->{hit} = '';

	$this->clearContent();

	$this->SetVirtualSize([0,0]);
	$this->SetBackgroundColour($color_white);
	$this->SetScrollRate($CHAR_WIDTH,$LINE_HEIGHT);

	EVT_PAINT($this, \&onPaint);
	EVT_MOUSE_EVENTS($this, \&onMouse);
	return $this;
}


sub setRepoContext
{
	my ($this,$repo) = @_;
	$this->{repo_context} = $repo;
}


sub clearContent
{
	my ($this) = @_;
	$this->{content} = [];
	$this->{hits} = [];
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
			$line->{width},
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
	$dc->SetBackgroundMode(wxSOLID);
		# background mode for text

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
			$dc->SetTextBackground($part->{hit} ? $color_medium_grey : $color_white);

			$dc->DrawText($text,$xpos,$i * $LINE_HEIGHT);
			$xpos += length($text) * $CHAR_WIDTH;
		}
	}


}	# onPaint()


#------------------------------------------------
# Mouse Event Handling
#------------------------------------------------


sub onMouse
{
	my ($this,$event) = @_;
	my $cp = $event->GetPosition();
	my ($sx,$sy) = ($cp->x,$cp->y);
	my ($ux,$uy) = $this->CalcUnscrolledPosition($sx,$sy);
	my $lclick = $event->LeftDown() || $event->LeftDClick();
	my $rclick = $event->RightDown() || $event->RightDClick();
	display($dbg_mouse,0,"onMouse($sx,$sy) unscrolled($ux,$uy) left($lclick) right($rclick)");

	my $hit = '';
	for my $h (@{$this->{hits}})
	{
		if ($h->{rect}->Contains([$ux,$uy]))
		{
			$hit = $h;
			last;
		}
	}

	$this->mouseOver($hit);
	$this->mouseClick($hit->{part},$lclick,$rclick) if $hit && $hit->{part} && ($lclick || $rclick);
}



sub mouseOver
{
	my ($this,$hit) = @_;
	my $cur_hit = $this->{hit};
	return if $hit eq $cur_hit;
	display($dbg_mouse,0,"mouseOver($hit)");

	if ($cur_hit)
	{
		$this->Refresh($cur_hit->{rect});
		$cur_hit->{part}->{hit} = 0;
	}

	my $status = '';
	if ($hit)
	{
		$this->Refresh($hit->{rect});
		$hit->{part}->{hit} = 1;
		my $context = $hit->{part}->{context};
    	if ($context->{path})
		{
			$status = "path: $context->{path}";
		}
		elsif ($context->{filename})
		{
			$status = "filename: $context->{filename}";
		}
		elsif ($context->{repo_path})
		{
			$status = "repo_path: $context->{repo_path}";
		}
		elsif ($context->{repo})
		{
			my $repo = $context->{repo};
			if ($context->{file})
			{
				$status = "repo_file: $repo->{path}$context->{file}";
			}
			else
			{
				$status = "repo: $repo->{id}";
			}
		}
	}

	$this->{hit} = $hit;
	$this->{frame}->SetStatusText($status);
	$this->Update();
}


sub mouseClick
{
	my ($this,$part,$lclick,$rclick)  = @_;
	display($dbg_mouse,0,"mouseClick($part->{text}) lclick($lclick) rclick($rclick)");

	my $repo = '';
	my $path = '';

	my $context = $part->{context};
	$repo = $context->{repo} if $context->{repo};
	$repo = getRepoHash()->{$context->{repo_path}} if $context->{repo_path};
	$repo ||= '';

	$path = $context->{path} if $context->{path};
	$path = $context->{filename} if $context->{filename};
	$path = "$repo->{path}$context->{file}" if $repo && $context->{file};

	if ($rclick)
	{
		$this->popupContextMenu($repo,$path);
	}

	# decide the best thing to do on a left click
	# path = md,gif,png,jpg,jpeg,pdf - shell
	# path = txt,pm,pl,cpp,c,h - komodo
	# repo - show repo details if not in that window, open gitUI otherwise
	# otherwise, show in explorer

	elsif ($path =~ /\.(md|gif|png|jpg|jpeg|pdf)$/)
	{
		chdir $path;
		system(1,"\"$path\"");
	}
	elsif ($path =~ /\.(txt|pm|pl|ino|cpp|c|h|hpp)$/)
	{
		my $command = $komodo_exe." \"$path\"";
		execNoShell($command);
	}
	elsif ($repo)
	{
		my $repo_context = $this->{repo_context};
		my $is_this_repo = $repo_context &&
			$repo->{id} eq $repo_context->{id};

		$is_this_repo ?
			execNoShell('git gui',$repo->{path}) :
			$this->{frame}->createPane($ID_REPOS_WINDOW,undef,{repo_id=>$repo->{id}});
	}
	elsif ($path)
	{
		execExplorer($path);
	}

}


1;