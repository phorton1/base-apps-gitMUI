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
	EVT_UPDATE_UI );
use Pub::Utils;
use apps::gitUI::utils;
use apps::gitUI::repos;
use apps::gitUI::repoStatus;
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
	$COMMAND_PULL_LOCAL,
	$COMMAND_UPDATE_SUBMODULES) = (8323..9000);
	# apparently local events are needed for
	# update UI ?!?

my $in_update_submodules:shared = 0;

# $COMMAND_UPDATE_SUBMODULES is really a global command
# but I am testing it here ...


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
	my $repo_name = $this->{repo_name} = apps::gitUI::myHyperlink->new($this,-1,'',[$TITLE_LEFT_MARGIN + $TITLE_WIDTH,7]);
	$this->{text_ctrl} = apps::gitUI::myTextCtrl->new($this);

	# Buttons added from right to left

	$this->{buttons} = [
		Wx::Button->new($this,$ID_COMMAND_REFRESH_STATUS,	'Refresh Status',	[0,5],	[85,20]),
		Wx::Button->new($this,$COMMAND_PUSH_LOCAL,			'Push',				[0,5],	[75,20]),
		Wx::Button->new($this,$COMMAND_PULL_LOCAL,			'Pull',				[0,5],	[60,20]),
		Wx::Button->new($this,$COMMAND_UPDATE_SUBMODULES,	'UpdateSubs',		[0,5],	[75,20]),
		# Wx::Button->new($this,-1,						'Scan Docs',		[0,5],	[80,20]),
		# Wx::Button->new($this,-1,						'Update Docs',		[0,5],	[80,20]),
	];

	$this->doLayout();

	EVT_SIZE($this, \&onSize);
	EVT_BUTTON($this, $ID_COMMAND_REFRESH_STATUS, 	\&onButton);
	EVT_BUTTON($this, $COMMAND_PUSH_LOCAL,	\&onButton);
	EVT_BUTTON($this, $COMMAND_PULL_LOCAL, 	\&onButton);
	EVT_BUTTON($this, $COMMAND_UPDATE_SUBMODULES, \&onButton);

	EVT_UPDATE_UI($this, $ID_COMMAND_REFRESH_STATUS,\&onUpdateUI);
	EVT_UPDATE_UI($this, $COMMAND_PUSH_LOCAL,	\&onUpdateUI);
	EVT_UPDATE_UI($this, $COMMAND_PULL_LOCAL, \&onUpdateUI);
	EVT_UPDATE_UI($this, $COMMAND_UPDATE_SUBMODULES, \&onUpdateUI);

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
		monitorStarted() && !repoStatusBusy();
	$enable = 1 if $id == $COMMAND_PUSH_LOCAL &&
		$repo &&
		$repo->canPush();
	$enable = 1 if $id == $COMMAND_PULL_LOCAL &&
		$repo &&
		$repo->canPull();
	$enable = 1 if $id == $COMMAND_UPDATE_SUBMODULES &&
		monitorStarted() && !$in_update_submodules;

	if ($id == $COMMAND_PULL_LOCAL)
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
	elsif ($id == $COMMAND_UPDATE_SUBMODULES)
	{
		$this->doUpdateSubmodules();
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


#-----------------------------------------------------------
# doUpdateSubmodules
#-----------------------------------------------------------

use apps::gitUI::repoGit;

sub doUpdateSubmodules
	# For each submodules that is 'up to date' locally ... that is they have
	# no unstaged or staged changes ... see if the parent has a unstaged
	# change of that submodule pending, and if so, create a commit that
	# references the most recent commit in the submodule.
{
	my ($this) = @_;
	display(0,0,"doUpdateSubmodules()");
	$in_update_submodules = 1;
	freezeMonitors(1);
	my $repo_list = getRepoList();
	for my $sub (@$repo_list)
	{
		my $parent = $sub->{parent_repo};
		next if !$parent;

		my $rel_path = $sub->{rel_path};
		my $ahead = $sub->{AHEAD};
		my $behind = $sub->{BEHIND};
		my $rebase = $sub->{REBASE};
		my $master_id = $sub->{MASTER_ID};
		my $staged = keys %{$sub->{staged_changes}};
		my $unstaged = keys %{$sub->{unstaged_changes}};

		my $commit = ${$sub->{local_commits}}[0];
		my $commit_id = $commit->{sha};
		my $commit_msg = $commit->{msg};

		my $master8 = _lim($master_id,8);
		my $commit8 = _lim($commit_id,8);

		display(0,1,"submodule($sub->{path} unstaged($unstaged) staged($staged) ahead($ahead) behind($behind) rebase($rebase) master_id="._lim($master_id,8));

		if ($commit_id ne $master_id)
		{
			error("submodule($rel_path) most recent commit($commit8) != master_id($master8)");
			next;
		}

		if ($staged || $unstaged || $behind || $rebase)
		{
			display(0,2,"submodule($rel_path) cannot be automatically committed");
			next
		}

		my $found;
		my $parent_staged = keys %{$parent->{staged_changes}};
		my $parent_unstaged = $parent->{unstaged_changes};
		for my $path (keys %$parent_unstaged)
		{
			if ($path eq $rel_path)
			{
				$found = $parent_unstaged->{$path};
				last;
			}
		}

		if (!$found)
		{
			display(0,2,"parent does not have $rel_path unstaged_change");
			next;
		}
		if ($parent_staged)
		{
			error("Cannot auto-commit submodule($sub->{path}) because parent has $parent_staged staged changes");
			next;
		}

		warning(0,2,"AUTO-COMMITTING($parent->{path}) submodule($rel_path) = $found->{type}");

		my $msg = "submodule($rel_path) auto_commit($commit8) $commit_msg";
		display(0,3,"msg=$msg");

		my $rslt = gitIndex($parent,0,[$rel_path]);
		$rslt &&= gitCommit($parent,$msg);

		display(0,3,"AUTO-COMMIT completed") if $rslt;

		last if !$rslt;
	}
	freezeMonitors(0);
	$in_update_submodules = 0;
}



1;
