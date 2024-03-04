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
use Pub::Utils;
use apps::gitUI::utils;
use apps::gitUI::repos;
use apps::gitUI::repoStatus;
use apps::gitUI::repoHistory;
use apps::gitUI::myTextCtrl;
use apps::gitUI::myHyperlink;
use apps::gitUI::Resources;
use base qw(Wx::Window);


my $dbg_life = 0;
my $dbg_notify = 1;
my $dbg_cmds = 0;


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}

my $PANE_TOP = 30;
my $TITLE_LEFT_MARGIN = 6;
my $TITLE_WIDTH = 60;
my $BUTTON_SPACE = 10;


my (
	$COMMAND_REFRESH_STATUS,
	$COMMAND_PUSH_ONE,
	$COMMAND_PULL_ONE,

	# $COMMAND_SCAN_DOCS,
	# $COMMAND_UPDATE_DOCS,
) = (17000..17999);


sub new
{
    my ($class,$parent,$splitter) = @_;
	display($dbg_life,0,"new reposWindowRight()");
    my $this = $class->SUPER::new($splitter);
    $this->{parent} = $parent;

	$this->{repo} = '';
	$this->{frame} = $parent->{frame};

	$this->SetBackgroundColour($color_cyan);

	$this->{title_ctrl} = Wx::StaticText->new($this,-1,'Repo:',[5,5],[$TITLE_LEFT_MARGIN-10,20]);
	my $repo_name = $this->{repo_name} = apps::gitUI::myHyperlink->new($this,-1,'',[$TITLE_LEFT_MARGIN + $TITLE_WIDTH,5]);
	$this->{text_ctrl} = apps::gitUI::myTextCtrl->new($this);

	# Buttons added from right to left

	$this->{buttons} = [
		Wx::Button->new($this,$COMMAND_REFRESH_STATUS,	'Refresh Status',	[0,5],	[85,20]),
		Wx::Button->new($this,$COMMAND_PUSH_ONE,		'Push',				[0,5],	[75,20]),
		Wx::Button->new($this,$COMMAND_PULL_ONE,		'Pull',				[0,5],	[60,20]),
		# Wx::Button->new($this,-1,						'Scan Docs',		[0,5],	[80,20]),
		# Wx::Button->new($this,-1,						'Update Docs',		[0,5],	[80,20]),
	];


	$this->doLayout();

	EVT_SIZE($this, \&onSize);

	EVT_BUTTON($this, $COMMAND_REFRESH_STATUS, 	\&onButton);
	EVT_BUTTON($this, $COMMAND_PUSH_ONE,		\&onButton);
	EVT_BUTTON($this, $COMMAND_PULL_ONE, 		\&onButton);
	EVT_UPDATE_UI_RANGE($this, $COMMAND_REFRESH_STATUS, $COMMAND_PULL_ONE, \&onUpdateUI);

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

	my $button_xpos = $width - $BUTTON_SPACE;
	my $buttons = $this->{buttons};
	for my $button (@$buttons)
	{
		my $bsz = $button->GetSize();
		my $bwidth = $bsz->GetWidth();
		$button_xpos -= $bwidth;

		$button->Move($button_xpos,5);
		$button_xpos -= $BUTTON_SPACE;
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
	my $repo = $this->{repo};

	my $enable = 0;
	$enable = 1 if $id == $COMMAND_REFRESH_STATUS &&
		!repoStatusBusy();
	$enable = 1 if $id == $COMMAND_PUSH_ONE &&
		$repo &&
		$repo->canPush();
	$enable = 1 if $id == $COMMAND_PULL_ONE &&
		$repo &&
		$repo->canPull();

	if ($id == $COMMAND_PULL_ONE)
	{
		my $button_title =
			$enable && $repo->needsStash() ?
			'Stash+Pull' : 'Pull';
		$event->SetText($button_title) if
			$event->GetText() ne $button_title;
	}

	$event->Enable($enable);
}


sub onButton
{
	my ($this,$event) = @_;
	my $id = $event->GetId();
	display($dbg_cmds,0,"reposWindowRight::onButton($id) repo=".($this->{repo}?$this->{repo}->{path}:'undef'));

	if ($id == $COMMAND_REFRESH_STATUS)
	{
		repoStatusStart();
	}
	elsif ($id == $COMMAND_PUSH_ONE)
	{
		clearSelectedPushRepos();
		setSelectedPushRepo($this->{repo});
		$this->{frame}->doThreadedCommand($ID_COMMAND_PUSH_SELECTED);
	}
	elsif ($id == $COMMAND_PULL_ONE)
	{
		clearSelectedPullRepos();
		setSelectedPullRepo($this->{repo});
		$this->{frame}->doThreadedCommand($ID_COMMAND_PULL_SELECTED);
	}
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
			$this->{title_ctrl}->SetLabel('');
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
	$this->{title_ctrl}->SetLabel("Repo[$repo->{num}]");
}



1;
