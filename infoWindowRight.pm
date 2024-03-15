#-------------------------------------------
# apps::gitUI::infoWindowRight
#-------------------------------------------
# The right side of the infoWindow myTextCtrl display area
# and a Pane with possible future command buttons

package apps::gitUI::infoWindowRight;
use strict;
use warnings;
use threads;
use threads::shared;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_SIZE
	EVT_LEFT_DOWN
	EVT_BUTTON
	EVT_UPDATE_UI );
use Pub::Utils;
use apps::gitUI::utils;
use apps::gitUI::repos;
use apps::gitUI::repoHistory;
use apps::gitUI::monitor;
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
my $RIGHT_MARGIN = 10;



sub new
{
    my ($class,$parent,$splitter) = @_;
	display($dbg_life,0,"new infoWindowRight()");
    my $this = $class->SUPER::new($splitter);
    $this->{parent} = $parent;

	$this->{repo} = '';
	$this->{frame} = $parent->{frame};
	$this->{sub_mode} = $parent->{sub_mode};

	$this->SetBackgroundColour($color_cyan);

	$this->{title_ctrl} = Wx::StaticText->new($this,-1,'Repo:',[5,8],[$TITLE_LEFT_MARGIN-10,20]);
	my $repo_name = $this->{repo_name} = apps::gitUI::myHyperlink->new($this,-1,'',[$TITLE_LEFT_MARGIN + $TITLE_WIDTH,7]);
	$this->{text_ctrl} = apps::gitUI::myTextCtrl->new($this, $this->{sub_mode} ?
		$ID_SUBS_WINDOW :
		$ID_INFO_WINDOW);

	# we use a panel for the buttons so they will show OVER
	# the title and repo_name controls

	my $panel = $this->{button_panel} = Wx::Panel->new($this,-1,[0,0],[320,$PANE_TOP]);
	my $commit_parent = $this->{commit_parent_button} =
	Wx::Button->new($panel,$INFO_RIGHT_COMMAND_COMMIT_PARENT,	'CommitParent',	[0,5],  [100,20]);
	Wx::Button->new($panel,$INFO_RIGHT_COMMAND_PULL,			'Pull',			[110,5],[70, 20]);
	Wx::Button->new($panel,$INFO_RIGHT_COMMAND_PUSH,			'Push',			[190,5],[60, 20]);
	Wx::Button->new($panel,$ID_COMMAND_REFRESH_STATUS,			'Refresh',		[260,5],[60, 20]);
	$commit_parent->Hide();

	$this->doLayout();

	EVT_SIZE($this, \&onSize);
	EVT_BUTTON($this, $ID_COMMAND_REFRESH_STATUS, 	\&onButton);
	EVT_BUTTON($this, $INFO_RIGHT_COMMAND_PUSH,	\&onButton);
	EVT_BUTTON($this, $INFO_RIGHT_COMMAND_PULL, 	\&onButton);
	EVT_BUTTON($this, $INFO_RIGHT_COMMAND_COMMIT_PARENT, 	\&onButton);

	EVT_UPDATE_UI($this, $ID_COMMAND_REFRESH_STATUS,\&onUpdateUI);
	EVT_UPDATE_UI($this, $INFO_RIGHT_COMMAND_PUSH,	\&onUpdateUI);
	EVT_UPDATE_UI($this, $INFO_RIGHT_COMMAND_PULL, \&onUpdateUI);
	EVT_UPDATE_UI($this, $INFO_RIGHT_COMMAND_COMMIT_PARENT, \&onUpdateUI);

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

	my $panel = $this->{button_panel};
	my $panel_sz = $panel->GetSize();
    my $panel_width = $panel_sz->GetWidth();
	$panel->Move($width-$panel_width-$RIGHT_MARGIN,0);

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
	$enable = 1 if $id == $ID_COMMAND_REFRESH_STATUS &&
		!monitorBusy();
	$enable = 1 if $id == $INFO_RIGHT_COMMAND_PUSH &&
		$repo &&
		$repo->canPush();

	if ($id == $INFO_RIGHT_COMMAND_COMMIT_PARENT)
	{
		$enable = 1 if $repo && $repo->canCommitParent();
		my $button_title = $repo && $repo->{is_subgroup} ?
			'CommitParents' :
			'CommitParent';
		$event->SetText($button_title) if
			$event->GetText() ne $button_title;
	}

	# allow pull on individual repo even
	# it is not known to be BEHIND

	if ($id == $INFO_RIGHT_COMMAND_PULL)
	{
		$enable = 1 if 	$repo &&
			$repo->isLocalAndRemote() &&
			!$repo->{AHEAD};
		my $button_title =
			$repo && $repo->needsStash() ? 'Stash+Pull' :
			$repo && $repo->canPull() ? 'Needs Pull' :
			'Pull';
		$event->SetText($button_title) if
			$event->GetText() ne $button_title;
	}

	$enable &&= monitorRunning();
	$event->Enable($enable);
}


sub onButton
{
	my ($this,$event) = @_;
	my $id = $event->GetId();
	display($dbg_cmds,0,"infoWindowRight::onButton($id) repo=".($this->{repo}?$this->{repo}->{path}:'undef'));

	if ($id == $ID_COMMAND_REFRESH_STATUS)
	{
		$this->{frame}->onCommand($event);
	}
	elsif ($id == $INFO_RIGHT_COMMAND_PUSH)
	{
		clearSelectedPushRepos();
		$this->{repo}->{is_subgroup} ?
			$this->{repo}->setSelectedPushRepos() :
			setSelectedPushRepo($this->{repo});
		$this->{frame}->doThreadedCommand($ID_COMMAND_PUSH_SELECTED);
	}
	elsif ($id == $INFO_RIGHT_COMMAND_PULL)
	{
		clearSelectedPullRepos();
		$this->{repo}->{is_subgroup} ?
			$this->{repo}->setSelectedPullRepos() :
			setSelectedPullRepo($this->{repo});
		$this->{frame}->doThreadedCommand($ID_COMMAND_PULL_SELECTED);
	}
	elsif ($id == $INFO_RIGHT_COMMAND_COMMIT_PARENT)
	{
		clearSelectedCommitParentRepos();
		$this->{repo}->{is_subgroup} ?
			$this->{repo}->setSelectedCommitParentRepos() :
			setSelectedCommitParentRepo($this->{repo});
		$this->{frame}->onCommandId($ID_COMMAND_COMMIT_SELECTED_PARENTS);
	}
}


sub notifyObjectSelected
{
	my ($this,$obj) = @_;
	display($dbg_notify,0,"infoWindowRight::notifyObjectSelected($obj->{path})");

	my $text_ctrl = $this->{text_ctrl};
	$text_ctrl->clearContent();

	my $repo = $obj->{is_subgroup} ? '' : $obj;
	my $kind = $obj->{is_subgroup} ? 'Group' : 'Repo';

	$this->{repo} = $obj;
	$this->{sub_mode} || $obj->{is_subgroup} || $obj->{parent_repo} ?
		$this->{commit_parent_button}->Show() :
		$this->{commit_parent_button}->Hide();

	$obj->toTextCtrl($text_ctrl, $this->{sub_mode} ?
		$ID_SUBS_WINDOW :
		$ID_INFO_WINDOW );
	historyToTextCtrl($text_ctrl,$repo,0) if
		!$obj->{is_subgroup} &&
		$obj->isLocal();

	$text_ctrl->setRepoContext($obj);

	$text_ctrl->Refresh();
	my $uuid = $obj->uuid();
	$this->{repo_name}->SetLabel($uuid);
	$this->{title_ctrl}->SetLabel("$kind\[$obj->{num}]");
}




1;
