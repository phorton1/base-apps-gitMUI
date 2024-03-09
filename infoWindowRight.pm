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
my $BUTTON_SPACE = 10;


my ($COMMAND_PUSH_LOCAL,
	$COMMAND_PULL_LOCAL, ) = (8323..9000);
	# apparently local events are needed for
	# update UI ?!?


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

	$this->{title_ctrl} = Wx::StaticText->new($this,-1,'Repo:',[5,5],[$TITLE_LEFT_MARGIN-10,20]);
	my $repo_name = $this->{repo_name} = apps::gitUI::myHyperlink->new($this,-1,'',[$TITLE_LEFT_MARGIN + $TITLE_WIDTH,7]);
	$this->{text_ctrl} = apps::gitUI::myTextCtrl->new($this, $this->{sub_mode} ?
		$ID_SUBS_WINDOW :
		$ID_INFO_WINDOW);

	# Buttons added from right to left

	$this->{buttons} = [
		Wx::Button->new($this,$ID_COMMAND_REFRESH_STATUS,	'Refresh',	[0,5],	[60,20]),
		Wx::Button->new($this,$COMMAND_PUSH_LOCAL,			'Push',		[0,5],	[70,20]),
		Wx::Button->new($this,$COMMAND_PULL_LOCAL,			'Pull',		[0,5],	[60,20]),
		# Wx::Button->new($this,-1,						'Scan Docs',	[0,5],	[80,20]),
		# Wx::Button->new($this,-1,						'Update Docs',	[0,5],	[80,20]),
	];

	$this->doLayout();

	EVT_SIZE($this, \&onSize);
	EVT_BUTTON($this, $ID_COMMAND_REFRESH_STATUS, 	\&onButton);
	EVT_BUTTON($this, $COMMAND_PUSH_LOCAL,	\&onButton);
	EVT_BUTTON($this, $COMMAND_PULL_LOCAL, 	\&onButton);

	EVT_UPDATE_UI($this, $ID_COMMAND_REFRESH_STATUS,\&onUpdateUI);
	EVT_UPDATE_UI($this, $COMMAND_PUSH_LOCAL,	\&onUpdateUI);
	EVT_UPDATE_UI($this, $COMMAND_PULL_LOCAL, \&onUpdateUI);

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
	$enable = 1 if $id == $ID_COMMAND_REFRESH_STATUS &&
		monitorRunning() && !monitorBusy();
	$enable = 1 if $id == $COMMAND_PUSH_LOCAL &&
		$repo &&
		$repo->canPush();
	$enable = 1 if $id == $COMMAND_PULL_LOCAL &&
		monitorRunning() &&
		$repo && !$repo->{AHEAD};

	# allow pull on individual repo even
	# it is not known to be BEHIND

	if ($id == $COMMAND_PULL_LOCAL)
	{
		my $button_title =
			$repo && $repo->needsStash() ? 'Stash+Pull' :
			$repo && $repo->canPull() ? 'Needs Pull' :
			'Pull';
		$event->SetText($button_title) if
			$event->GetText() ne $button_title;
	}

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
	elsif ($id == $COMMAND_PUSH_LOCAL)
	{
		clearSelectedPushRepos();
		setSelectedPushRepo($this->{repo});
		$this->{frame}->doThreadedCommand($ID_COMMAND_PUSH_SELECTED);
	}
	elsif ($id == $COMMAND_PULL_LOCAL)
	{
		clearSelectedPullRepos();
		setSelectedPullRepo($this->{repo});
		$this->{frame}->doThreadedCommand($ID_COMMAND_PULL_SELECTED);
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

	$this->{repo} = $repo;
	$text_ctrl->setRepoContext($repo);

	if ($repo)
	{
		$repo->toTextCtrl($text_ctrl, $this->{sub_mode} ?
			$ID_SUBS_WINDOW :
			$ID_INFO_WINDOW );
		historyToTextCtrl($text_ctrl,$repo,0);
	}
	else
	{
		$text_ctrl->clearContent();
	}

	$text_ctrl->Refresh();
	$this->{repo_name}->SetLabel($obj->{path});
	$this->{title_ctrl}->SetLabel("$kind\[$obj->{num}]");
}




1;
