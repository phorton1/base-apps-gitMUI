#-------------------------------------------
# apps::gitUI::reposWindowRight
#-------------------------------------------
# The right side of the reposWindow myTextCtrl display area
# and a Pane with possible future command buttons

package apps::gitUI::reposWindowRight;
use strict;
use warnings;
use threads;
use threads::shared;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_SIZE
	EVT_LEFT_DOWN
	EVT_BUTTON
	EVT_UPDATE_UI_RANGE );
use apps::gitUI::utils;
use apps::gitUI::repos;
use apps::gitUI::myTextCtrl;
use apps::gitUI::myHyperlink;
use apps::gitUI::repoHistory;
use apps::gitUI::Resources;
use Pub::Utils;
use base qw(Wx::Window);


my $dbg_life = 0;
my $dbg_notify = 0;
my $dbg_cmds = 0;


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}

my $PANE_TOP = 30;
my $NAME_LEFT = 45;
my $BUTTON_OFFSET = 90;

my (
	$COMMAND_STATUS,
	# $COMMAND_SCAN_DOCS,
	# $COMMAND_UPDATE_DOCS,
) = (17000..17999);


sub new
{
    my ($class,$parent,$splitter) = @_;
	display($dbg_life,0,"new reposWindowRight()");
    my $this = $class->SUPER::new($splitter);
    $this->{parent} = $parent;

	$this->{cur_repo} = '';
	$this->{frame} = $parent->{frame};

	$this->SetBackgroundColour($color_cyan);

	$this->{title_ctrl} = Wx::StaticText->new($this,-1,'Repo:',[5,5],[$NAME_LEFT-10,20]);
	my $repo_name = $this->{repo_name} = apps::gitUI::myHyperlink->new($this,-1,'',[$NAME_LEFT,5]);
	$this->{text_ctrl} = apps::gitUI::myTextCtrl->new($this);

	$this->{buttons} = [
		Wx::Button->new($this,$COMMAND_STATUS,'Update Remote Status',		[0,5],	[120,20]),
		# Wx::Button->new($this,$COMMAND_SCAN_DOCS,'Scan Docs',		[0,5],	[80,20]),
		# Wx::Button->new($this,$COMMAND_UPDATE_DOCS,'Update Docs',	[90,5],	[80,20]),
	];


	$this->doLayout();

	EVT_SIZE($this, \&onSize);

	EVT_BUTTON($this, $COMMAND_STATUS, \&onButton);
	# EVT_BUTTON($this, $COMMAND_SCAN_DOCS, \&onButton);
	# EVT_BUTTON($this, $COMMAND_UPDATE_DOCS, \&onButton);
	EVT_UPDATE_UI_RANGE($this, $COMMAND_STATUS, $COMMAND_STATUS, \&onUpdateUI);

	return $this;
}


sub doLayout
{
	my ($this) = @_;
	my $sz = $this->GetSize();
    my $width = $sz->GetWidth();
    my $height = $sz->GetHeight();
    $this->{text_ctrl}->SetSize([$width,$height-$PANE_TOP]);
	$this->{text_ctrl}->Move(0,$PANE_TOP);

	my $buttons = $this->{buttons};
	my $buttons_xpos = $width - (@$buttons * $BUTTON_OFFSET) - 10;
	for my $button (@$buttons)
	{
		$button->Move($buttons_xpos,5);
		$buttons_xpos += $BUTTON_OFFSET;
	}
	$this->Refresh();
}


sub onSize
{
    my ($this,$event) = @_;
	$this->doLayout();
    $event->Skip();
}



sub onUpdateUI
{
	my ($this,$event) = @_;
	my $id = $event->GetId();
	my $enable = $this->{repo} ? 1 : 0;
	$event->Enable($enable);
}


sub onButton
{
	my ($this,$event) = @_;
	my $id = $event->GetId();
	display($dbg_cmds,0,"reposWindowRight::onButton($id)");

	if ($id == $COMMAND_STATUS)
	{
		$this->doStatus();
	}
	# if ($id == $COMMAND_SCAN_DOCS)
	# {
	# }
	# if ($id == $COMMAND_UPDATE_DOCS)
	# {
	# }
}


sub notifyRepoSelected
{
	my ($this,$repo) = @_;
	display($dbg_notify,0,"reposWindowRight::notifyItemSelected($repo->{path}=$repo->{id} called");

	my $path = $repo ? $repo->{path} : '';
	my $text_ctrl = $this->{text_ctrl};
	$text_ctrl->clearContent();

	if (!$path)
	{
		if ($this->{repo})
		{
			$this->{repo} = '';
			$this->{repo_name}->SetLabel('');
			$text_ctrl->Refresh();
		}
		return;
	}

	$this->{repo} = $repo;

	$text_ctrl->setRepoContext($repo);
	$repo->toTextCtrl($text_ctrl);
	historyToTextCtrl($text_ctrl,$repo,0);
	$text_ctrl->Refresh();

	my $kind =
		$repo->{parent_repo} ? "SUBMODULE " :
		$repo->{used_in} ? "MAIN_MODULE " : '';

	$this->{repo_name}->SetLabel($kind.$path);
}



#--------------------------------------------------------
# doStatus - prototype
#--------------------------------------------------------

my $dbg_git = -1;


sub doStatus
{
	my ($this) = @_;
	my $repo = $this->{repo};
	my $path = $repo->{path};
	my $text = '';

	display($dbg_git,0,"doStatus($path)");

	if (!gitCommand(0,\$text,$path,'remote update'))
	{
		error($text);
		return 0;
	}

	# git status
	# -b == include branch info
	# --porcelain s== stable simple paraseable result

	if (!gitCommand(1,\$text,$path,'status -b --porcelain'))
	{
		error($text);
		return 0;
	}

	# master...origin/master [ahead 1, behind 1]
	# ?? untracked_file
	# _M modified file

	my @lines = split(/\n/,$text);
	my $status_text = shift @lines;
	my $commits = $status_text =~ /\[(.*)\]/ ? $1 : '';
	my $ahead = $commits =~ /ahead (\d+)/ ? $1 : 0;
	my $behind = $commits =~ /behind (\d+)/ ? $1 : 0;

	display($dbg_git,1,"AHEAD($ahead) BEHIND($behind)");
	$repo->{ahead} = $ahead;
	$repo->{behind} = $behind;
	$this->notifyRepoSelected($repo);

	return 1;
}




sub gitCommand
	# returns 0 on error, 1 on success
	# always sets the $$retval text
	# it is an error if:
	#
	#	the command returns undef
	#	the backtick command exited with a non-zero exit code
	#	$no_blank && the command returns ''
{
	my ($no_blank,$ptext,$repo,$command) = @_;
	display($dbg_git,0,"gitCommand($no_blank,$repo) $command");
	$$ptext = `git -C $repo $command 2>&1`;
	my $exit_code = $?;

	if (!defined($$ptext))
	{
		$$ptext = "ERROR repo($repo) command($command) returned undef\n";
		return 0;
	}
	if ($exit_code)
	{
		$$ptext .= "\n" if $ptext;
		$$ptext = "ERROR repo($repo) command($command) returned exit_code($exit_code)\n$$ptext";
		return 0;
	}
	if ($no_blank && !$$ptext)
	{
		$$ptext = "ERROR repo($repo) command($command) returned blank\n";
		return 0;
	}

	display($dbg_git+1,1,"text=$$ptext");
	return 1;
}




1;
