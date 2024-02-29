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
	EVT_LEFT_DOWN
	EVT_BUTTON
	EVT_UPDATE_UI
	EVT_SPLITTER_SASH_POS_CHANGED );
use apps::gitUI::utils;
use apps::gitUI::repos;
use apps::gitUI::myTextCtrl;
use apps::gitUI::myHyperlink;
use apps::gitUI::repoGit;
use apps::gitUI::repoHistory;
use apps::gitUI::Resources;
use Pub::Utils;
use base qw(Wx::Window);


my $dbg_life = 0;
my $dbg_layout = 1;
my $dbg_notify = 1;
my $dbg_cmds = 0;


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}

my $ID_RIGHT_SPLITTER = 9292;
my $COMMAND_COMMIT = 9293;


my $PANE_TOP = 25;
my $FILENAME_LEFT = 150;
my $NOTE_LEFT = 400;
my $DEFAULT_COMMAND_AREA_HEIGHT   = 120;


my $COMMIT_MSG_TOP = 5;
my $COMMIT_MSG_LEFT  = 80;
my $COMMIT_MSG_HEIGHT = $DEFAULT_COMMAND_AREA_HEIGHT - 10;

sub new
{
    my ($class,$parent,$main_splitter) = @_;
	display($dbg_life,0,"new commitRight()");
		# $parent,$main_splitter) frame="._def($parent->{frame}));
    my $this = $class->SUPER::new($main_splitter);
    $this->{parent} = $parent;
	$this->{frame} = $parent->{frame};

	$this->{diff_repo} = '';
	$this->{diff_item} = '';
	$this->{bottom_height} = $DEFAULT_COMMAND_AREA_HEIGHT;

	my $right_splitter  = $this->{right_splitter}  = Wx::SplitterWindow->new($this, $ID_RIGHT_SPLITTER, [0, 0]);
	$right_splitter->SetMinimumPaneSize($DEFAULT_COMMAND_AREA_HEIGHT);
	# $right_splitter->{frame} = $this->{frame};
	# if I wanted to be consistent
	warning(0,0,"right_splitter->frame="._def($right_splitter->{frame}));

	my $top_panel = $this->{top_panel} = Wx::Panel->new($right_splitter);
	my $bottom_panel = $this->{bottom_panel} = Wx::Panel->new($right_splitter);

	$top_panel->{frame} = $this->{frame};
		# needed to pass to myTextCtrl for $frame->SetStatusText() calls

	# $bottom_panel->{frame} = $this->{frame};
	# if I wanted to be consistent
	$top_panel->SetBackgroundColour($color_yellow);
	$bottom_panel->SetBackgroundColour($color_light_grey);

	$this->{what_ctrl} = Wx::StaticText->new($top_panel,-1,'',[5,5],[$FILENAME_LEFT-10,20]);
	my $hyperlink = $this->{hyperlink} = apps::gitUI::myHyperlink->new($top_panel,-1,'',[$FILENAME_LEFT,5]);
	my $diff_ctrl = $this->{diff_ctrl} = apps::gitUI::myTextCtrl->new($top_panel);

	Wx::Button->new($bottom_panel,$ID_COMMAND_RESCAN,'Rescan',		[5,5],	[65,20]);
	Wx::Button->new($bottom_panel,$COMMAND_COMMIT,'Commit',			[5,30],	[65,20]);
	Wx::Button->new($bottom_panel,$ID_COMMAND_PUSH_ALL,'PushAll',	[5,55],	[65,20]);

	$this->{commit_msg} = Wx::TextCtrl->new($bottom_panel, -1, '', [$COMMIT_MSG_LEFT,$COMMIT_MSG_TOP],[-1,-1],
		wxTE_MULTILINE | wxHSCROLL );

    $right_splitter->SplitHorizontally($top_panel,$bottom_panel,300);

	$this->doLayout();

	EVT_SIZE($this, \&onSize);
	EVT_BUTTON($this, $ID_COMMAND_RESCAN, \&onButton);
	EVT_BUTTON($this, $COMMAND_COMMIT, \&onButton);
	EVT_BUTTON($this, $ID_COMMAND_PUSH_ALL, \&onButton);
	EVT_UPDATE_UI($this, $COMMAND_COMMIT, \&onUpdateUI);
	EVT_UPDATE_UI($this, $ID_COMMAND_PUSH_ALL, \&onUpdateUI);
	EVT_SPLITTER_SASH_POS_CHANGED($this, $ID_RIGHT_SPLITTER, \&onSashPosChanged);

    return $this;
}


my $started = 0;

sub doLayout
{
	my ($this) = @_;
	my $sz = $this->GetSize();
    my $width = $sz->GetWidth();
    my $height = $sz->GetHeight();
	my $bottom_height = $this->{bottom_height};
	my $top_height = $height - $bottom_height;

	display($dbg_layout,0,"doLayout() width($width) height($height) bottom_height($bottom_height) top_height($top_height)");

	$this->{right_splitter}->SetSize([$width,$height]);

	$this->{top_panel}->SetSize([$width,$top_height]);
	# $this->{top_panel}->Move(0,0);

    $this->{diff_ctrl}->SetSize([$width,$top_height-$PANE_TOP]);
	$this->{diff_ctrl}->Move(0,$PANE_TOP);

	$this->{bottom_panel}->SetSize([$width,$DEFAULT_COMMAND_AREA_HEIGHT]);
	# $this->{bottom_panel}->Move(0,$top_height);

	$this->{right_splitter}->SetSashPosition($top_height);

	my $msg_width = $width-$COMMIT_MSG_LEFT;
	$msg_width = 30 if $msg_width < 30;
	$this->{commit_msg}->SetSize([$msg_width,$bottom_height-10]);

	$this->Refresh();
}


sub onSize
{
    my ($this,$event) = @_;
	$this->doLayout();
    $event->Skip();
}

sub onSashPosChanged
{
	my ($this,$event) = @_;
	my $id = $event->GetId();
	my $pos = $event->GetSashPosition();

	my $sz = $this->GetSize();
    my $width = $sz->GetWidth();
    my $height = $sz->GetHeight();

	$this->{bottom_height} = $height - $pos;
	display($dbg_layout,0,"onSashPosChanged() pos($pos) height($width) bottom_height($this->{bottom_height})");

	$this->doLayout();
}



sub onUpdateUI
{
	my ($this,$event) = @_;
	my $id = $event->GetId();
	my $enable = 1;
	$enable = 0 if $id == $ID_COMMAND_PUSH_ALL && !canPushRepos();
	$enable = 0 if $id == $COMMAND_COMMIT && (
		!$this->{parent}->canCommit() ||
		!$this->{commit_msg}->GetValue());
	$event->Enable($enable);
}


sub onButton
{
	my ($this,$event) = @_;
	my $id = $event->GetId();
	display($dbg_cmds,0,"commitRight::onButton($id)");

	my $frame = $this->{frame};
	if ($id == $ID_COMMAND_RESCAN)
	{
		$frame->onCommand($event);
	}
	if ($id == $ID_COMMAND_PUSH_ALL)
	{
		$frame->doPushCommand($id);
	}
	if ($id == $COMMAND_COMMIT)
	{
		# $app_frame->doGitCommand($COMMAND_COMMIT,$this->{commit_msg}->GetValue());
		my $commit_msg = $this->{commit_msg}->GetValue();
		$this->{commit_msg}->SetValue('');

		display($dbg_cmds,0,"COMMIT_BUTTON doing commit on repos");
		my $repo_list = getRepoList();
		for my $repo (@$repo_list)
		{
			my $rslt = $repo->canCommit() ?
				gitCommit($repo,$commit_msg) : 1;
			last if !$rslt;
		}
	}
}



#-------------------------------------------------------
# notifyContent, Diffs, etc
#-------------------------------------------------------

my $MAX_FILE_BYTES = 100000;
my $LINE_ENDING_CR = 1;
my $LINE_ENDING_LF = 2;
my $LINE_ENDING_CRLF = 3;
my $LINE_ENDING_MIXED = 4;



sub determineType
{
	my ($this,$repo,$item,$file_type) = @_;
	my $diff_ctrl = $this->{diff_ctrl};

	$this->{diff_binary} = 0;

	my $filename = $repo->{path}."/".$item->{fn};
	display($dbg_notify,0,"determineType($filename)");

	my @stat = stat($filename);
	if (!@stat)
	{
		$diff_ctrl->addSingleLine(1,$color_red,error("Could not stat($filename)"));
	}
	else
	{
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
			$atime,$mtime,$ctime,$blksize,$blocks) = @stat;

		my $fh;
		if (!open($fh,"<$filename"))
		{
			$diff_ctrl->addSingleLine(1,$color_red,error("Could not open($filename)"));
		}
		else
		{
			binmode($fh);
			my $bytes = $size > $MAX_FILE_BYTES ? $MAX_FILE_BYTES : $size;
			my $buffer;
			my $got = sysread($fh,$buffer,$bytes);
			if ($bytes != $got)
			{
				$diff_ctrl->addSingleLine(1,$color_red,error("Could not read($filename) got($got) expected($bytes)"));
			}
			else
			{
				if ($buffer =~ /([\x00-\x08\x0B-\x0C\x0E-\x1F])/)
				{
					$this->{diff_binary} = 1;
					$diff_ctrl->addSingleLine(1,$color_blue,$file_type."Binary File $size bytes");
				}
				else
				{
					$buffer =~ s/\s+$// if $bytes < $size;	# prevent false detections
					my $eol_type = 0;
					my $has_cr = $buffer =~ /\r[^\n]/s ? 1 : 0;
					my $has_lf = $buffer =~ /[^\r]\n/s ? 1 : 0;
					my $has_crlf = $buffer =~ /\r\n/s ? 1 : 0;

					display($dbg_notify,0,"has_cr($has_cr) has_lf($has_lf) has_crlf($has_crlf)");

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
							$diff_ctrl->addSingleLine(0,$color_red,error("Could not read last two bytes)$filename) got($got)"));
						}
					}
					$has_eof = $buffer2 =~ /(\r|\n)$/ ? 1 : 0;
					$diff_ctrl->addSingleLine(1,$color_blue,$file_type."Text File $size bytes EOL($eol_text) EOF($has_eof)");

					my @lines = split(/\r\n|\r|\n/,$buffer);
					for my $line (@lines)
					{
						$diff_ctrl->addSingleLine(0,$color_green,"+$line");
					}


				}	# text file
			}	# read ok

			close($fh);

		}	# file opened
	}	# got @stat
}



sub startDiffContent
{
	my ($this,$started,$file_type) = @_;
	my $binary = $this->{diff_binary} ? "Binary " : '';
	$this->{diff_ctrl}->addSingleLine(1,$color_blue,$file_type.$binary."File")
		if !$started;
	return 1;
}


sub parseDiffText
{
	my ($this,$text,$file_type) = @_;
	my $diff_ctrl = $this->{diff_ctrl};

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
			$started = $this->startDiffContent($started,$file_type);
			$diff_ctrl->addSingleLine(0,$color_black,'');
			$diff_ctrl->addSingleLine(1,$color_blue,"CHANGE old($old_start,$old_lines) to new($new_start,$new_lines)");
		}
		else
		{
			my $color =
				$line =~ /^\+/ ? $color_green :
				$line =~ /^-/ ? $color_red :
				$color_black;

			my $text_line = $diff_ctrl->addLine();
			$diff_ctrl->addPart($text_line, 1, $color_blue,"| ");
			$diff_ctrl->addPart($text_line, 0, $color, $line );
		}
	}
}



sub notifyItemSelected
{
	my ($this,$data) = @_;

	my $repo = $data->{repo};
	my $item = $data->{item};
	my $is_staged = $data->{is_staged};
	my $id = $repo ? $repo->{id} : '';
	my $fn = $item ? $item->{fn} : '';
	my $type = $item ? $item->{type} : '';
	display($dbg_notify,0,"commitRight::notifyItemSelected($is_staged,$id,$fn,$type) called");

	$this->{diff_binary} = 0;
	my $diff_ctrl = $this->{diff_ctrl};
	$diff_ctrl->clearContent();

	# '','' means to clear the diff window if it is showing an item.
	# If it is showing a repo, we leave it.

	if (!$id && !$fn)
	{
		if ($this->{diff_item})
		{
			$this->{diff_repo} = '';
			$this->{diff_item} = '';;
			$this->{what_ctrl}->SetLabel('');
			$this->{hyperlink}->SetLabel('');
			$diff_ctrl->Refresh();
		}
		return;
	}

	my $file_type = '';
	$file_type = 'New ' if $item && $type eq 'A';
	$file_type = 'Deleted ' if $item && $type eq 'D';
	$file_type = 'Changed ' if $item && $type eq 'M';
	$file_type = 'Renamed ' if $item && $type eq 'R';

	# for Adds in Unstaged, determine the file type
	# otherwise do the diff and parse it

	if ($item)
	{
		if (!$this->{is_staged} && $type eq 'A')
		{
			$this->determineType($repo,$item,$file_type);
		}
		else
		{
			my $text = gitDiff($repo,$is_staged,$fn);
			$this->parseDiffText($text,$file_type);
		}
	}
	else
	{
		$repo->toTextCtrl($diff_ctrl);
		historyToTextCtrl($diff_ctrl,$repo,0);
	}

	$diff_ctrl->Refresh();

	my $where = $is_staged ? "Staged " : "Unstaged ";
	my $kind = $item && $this->{diff_binary} ? "Binary " : '';
	my $what = $item ? "File" : "Repo";

	$this->{diff_repo} = $repo;
	$this->{diff_item} = $item;
	$this->{what_ctrl}->SetLabel($file_type.$where.$kind.$what);
	$this->{hyperlink}->SetLabel($fn || $id);
}





1;
