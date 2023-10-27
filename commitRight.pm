#!/usr/bin/perl
#-------------------------------------------
# apps::gitUI::commitRight
#-------------------------------------------
# The right side of the commitWindow contains
# the diff_ctrl and command portions

package apps::gitUI::commitRight;
use strict;
use warnings;
use threads;
use threads::shared;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_SIZE
	EVT_BUTTON
	EVT_LEFT_DOWN );
use apps::gitUI::utils;
use apps::gitUI::diffCtrl;
use apps::gitUI::hyperlink;
use apps::gitUI::repoGit;
use apps::gitUI::gitHistory;
use Pub::Utils;
use base qw(Wx::Window);


my $dbg_life = 0;
my $dbg_notify = 1;


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}

my $PANE_TOP = 25;
my $FILENAME_LEFT = 150;
my $NOTE_LEFT = 400;
my $COMMAND_AREA_HEIGHT   = 120;



sub new
{
    my ($class,$parent,$splitter) = @_;
	display($dbg_life,0,"new commitRight()");
    my $this = $class->SUPER::new($splitter);
    $this->{parent} = $parent;

	$this->SetBackgroundColour($color_yellow);

	$this->{what_ctrl} = Wx::StaticText->new($this,-1,'',[5,5],[$FILENAME_LEFT-10,20]);
	my $hyperlink = $this->{hyperlink} = apps::gitUI::hyperlink->new($this,-1,'',[$FILENAME_LEFT,5]);
	$this->{note_ctrl} = Wx::StaticText->new($this,-1,'',[$NOTE_LEFT,5]);
	$this->{diff_ctrl} = apps::gitUI::diffCtrl->new($this);

	my $panel = $this->{panel} = Wx::Panel->new($this);
	$panel->SetBackgroundColour($color_light_grey);

	$this->{diff_repo} = '';
	$this->{diff_item} = '';

	$this->doLayout();
	EVT_SIZE($this, \&onSize);
	EVT_LEFT_DOWN($hyperlink, \&onLink);
    return $this;

}


sub doLayout
{
	my ($this) = @_;
	my $sz = $this->GetSize();
    my $width = $sz->GetWidth();
    my $height = $sz->GetHeight();
	my $panel_start = $height-$COMMAND_AREA_HEIGHT;
    $this->{diff_ctrl}->SetSize([$width,$panel_start-$PANE_TOP]);
	$this->{diff_ctrl}->Move(0,$PANE_TOP);
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




#-------------------------------------------------------
# notifyContent, Diffs, etc
#-------------------------------------------------------

my $MAX_FILE_BYTES = 100000;
my $LINE_ENDING_CR = 1;
my $LINE_ENDING_LF = 2;
my $LINE_ENDING_CRLF = 3;
my $LINE_ENDING_MIXED = 4;


sub addContentLine
{
	my ($content,$bold,$color,$text) = @_;
	push @$content,[$bold,$color,$text];
}

sub determineType
{
	my ($this,$repo,$item,$file_type) = @_;
	my $content = [];
	$this->{diff_binary} = 0;

	my $filename = $repo->{path}."/".$item->{fn};
	display($dbg_notify,0,"determineType($filename)");

	my @stat = stat($filename);
	if (!@stat)
	{
		addContentLine($content,1,$color_red,error("Could not stat($filename)"));
	}
	else
	{
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
			$atime,$mtime,$ctime,$blksize,$blocks) = @stat;

		my $fh;
		if (!open($fh,"<$filename"))
		{
			addContentLine($content,1,$color_red,error("Could not open($filename)"));
		}
		else
		{
			binmode($fh);
			my $bytes = $size > $MAX_FILE_BYTES ? $MAX_FILE_BYTES : $size;
			my $buffer;
			my $got = sysread($fh,$buffer,$bytes);
			if ($bytes != $got)
			{
				addContentLine($content,1,$color_red,error("Could not read($filename) got($got) expected($bytes)"));
			}
			else
			{
				if ($buffer =~ /[\x00-\x08|\x0B-\x0C|\x0E-\x1F]/)
				{
					$this->{diff_binary} = 1;
					addContentLine($content,1,$color_blue,$file_type."Binary File $size bytes");
				}
				else
				{
					$buffer =~ s/\s+$// if $bytes < $size;	# prevent false detections
					my $eol_type = 0;
					my $has_cr = $buffer =~ /\r[^\n]/s ? 1 : 0;
					my $has_lf = $buffer =~ /[^\r]\n/s ? 1 : 0;
					my $has_crlf = $buffer =~ /\r\n/s ? 1 : 0;

					display(0,0,"has_cr($has_cr) has_lf($has_lf) has_crlf($has_crlf)");

					if ($has_cr + $has_lf + $has_crlf > 1)
					{
						$eol_type = $LINE_ENDING_MIXED;
					}
					else
					{
						$eol_type = $LINE_ENDING_CR if $has_cr;
						$eol_type = $LINE_ENDING_LF if $has_lf;
						$eol_type = $LINE_ENDING_CRLF if $has_crlf;
					}

					my $eol_text =
						$eol_type == $LINE_ENDING_MIXED ? 'mixed' :
						$eol_type == $LINE_ENDING_CR ? 'CR' :
						$eol_type == $LINE_ENDING_LF ? 'LF' :
						$eol_type == $LINE_ENDING_CRLF ? 'CRLF' : 'none';


					# read the last two bytes of the file if needed

					my $has_eof = 0;
					my $buffer2 = $buffer;
					if ($bytes < $size)
					{
						sysseek($fh,$size-2,0);
						$got = sysread($fh,$buffer2,2);
						if ($got != 2)
						{
							addContentLine($content,0,$color_red,error("Could not read last two bytes)$filename) got($got)"));
						}
					}
					$has_eof = $buffer2 =~ /(\r|\n)$/ ? 1 : 0;
					addContentLine($content,1,$color_blue,$file_type."Text File $size bytes EOL($eol_text) EOF($has_eof)");

					my @lines = split(/\r\n|\r|\n/,$buffer);
					for my $line (@lines)
					{
						addContentLine($content,0,$color_green,"+$line");
					}


				}	# text file
			}	# read ok

			close($fh);

		}	# file opened
	}	# got @stat

	return $content;
}



sub startDiffContent
{
	my ($this,$started,$content,$file_type) = @_;
	my $binary = $this->{diff_binary} ? "Binary " : '';
	addContentLine($content,1,$color_blue,$file_type.$binary."File")
		if !$started;
	return 1;
}


sub parseDiffText
{
	my ($this,$text,$file_type) = @_;


	my $content = [];
	my $started = 0;

	while ($text)
	{
		$text =~ s/(.*?)(\r|\n|$)//;
		my $line = $1;
		$text =~ s/^(\r|\n)//;
		$line =~ s/\s+$//;

		# skip first lines
		next if $line =~ /^(diff|index|---|\+\+\+)/i;
		if ($line =~ /^Binary/)
		{
			$this->{diff_binary} = 1;
			next;
		}

		if ($line =~ /^@@\s+-(.*?)\s+\+(.*?)\s+@@/)
		{
			my ($plus,$minus) = ($1,$2);

			my ($old_start,$old_lines) = split(',',$plus);
			$old_lines ||= 0;
			my ($new_start,$new_lines) = split(',',$minus);
			$new_lines ||= 0;
			$started = $this->startDiffContent($started,$content,$file_type);
			addContentLine($content,0,$color_black,'');
			addContentLine($content,1,$color_blue,"CHANGE old($old_start,$old_lines) to new($new_start,$new_lines)");
		}
		else
		{
			my $color =
				$line =~ /^\+/ ? $color_green :
				$line =~ /^-/ ? $color_red :
				$color_black;

			push @$content,[
				1, $color_blue,"| ",
				0, $color, $line ];
		}
	}
	return $content;
}



sub notifyContent
{
	my ($this,$data) = @_;
	my $is_staged = $data->{is_staged};
	my $repo = $data->{repo};
	my $item = $data->{item};
	my $id = $repo->{id};
	my $fn = $item ? $item->{fn} : '';
	my $type = $item ? $item->{type} : '';
	display($dbg_notify,0,"commitRight::notifyContent($is_staged,$id,$fn,$type) called");

	$this->{diff_binary} = 0;

	my $file_type = '';
	$file_type = 'New ' if $item && $type eq 'A';
	$file_type = 'Deleted ' if $item && $type eq 'D';
	$file_type = 'Changed ' if $item && $type eq 'M';
	$file_type = 'Renamed ' if $item && $type eq 'R';

	# for Adds in Unstaged, determine the file type
	# otherwise do the diff and parse it

	my $content = '';
	if ($item)
	{
		if (!$this->{is_staged} && $type eq 'A')
		{
			$content = $this->determineType($repo,$item,$file_type);
		}
		else
		{
			my $text = gitDiff($repo,$is_staged,$fn);
			$content = $this->parseDiffText($text,$file_type);
		}
	}
	else
	{
		$content = $repo->toContent();
		push @$content,@{gitHistoryContent($repo,0)};
	}

	$this->{diff_ctrl}->setContent($content);

	my $where = $is_staged ? "Staged " : "Unstaged ";
	my $kind = $item && $this->{diff_binary} ? "Binary " : '';
	my $what = $item ? "File" : "Repo";

	$this->{diff_repo} = $repo;
	$this->{diff_item} = $item;
	$this->{what_ctrl}->SetLabel($file_type.$where.$kind.$what);
	$this->{hyperlink}->SetLabel($fn || $id);
}





1;
