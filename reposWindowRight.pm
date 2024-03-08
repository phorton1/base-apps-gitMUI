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
		monitorRunning() && !monitorBusy();
	$enable = 1 if $id == $COMMAND_PUSH_LOCAL &&
		$repo &&
		$repo->canPush();
	$enable = 1 if $id == $COMMAND_PULL_LOCAL &&
		monitorRunning() &&
		$repo && !$repo->{AHEAD};
	$enable = 1 if $id == $COMMAND_UPDATE_SUBMODULES &&
		monitorRunning() && !$in_update_submodules;

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



sub old_doUpdateSubmodules
	# For each submodules that is 'up to date' locally ... that is they have
	# no unstaged or staged changes ... see if the parent has a unstaged
	# change of that submodule pending, and if so, create a commit that
	# references the most recent commit in the submodule.
{
	my ($this) = @_;
	display(0,0,"doUpdateSubmodules()");
	$in_update_submodules = 1;
	monitorPause(1);
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
	monitorPause(0);
	$in_update_submodules = 0;
}



my $dbg_subs = 0;


sub doUpdateSubmodules
	# HOW FAR TO GO?  One button does everyhing?
	#
	# Note that the state of the modules may change outside of this process.
	#
	# I don't think I should ever automatically commit changes to submodules themselves.
	# There are questions about doing this re-iteratively,
	#
	# The normal situation I see is that I make a changes to a submodule, and commit them.
	# Then I tell the system to fix everything up.
	# At least the system will warn me if I try to commit to a repo that is BEHIND.
	# A Pull will stash any uncommitted changes.
	#
	# Thus here are cases where the automatic process should at least warn me,
	# i.e. I have changes in a submodule that will get stashed by this process.
	#
	# Then there are cases where one sub can't be done (i.e. REBASE), but I
	# *could* still do the other modules.
	#
	# Finally, it is complicated by the monitorUpdate() being an async process,
	# coupled with the potential delay before github events get update (upto 60 seconds).
	#
	# More than one sub could be AHEAD.
	#
	# (1) Identify any situations where I do not want to proceed automatically
	# (2) Push any subs that are AHEAD
	# (3) Do a monitorUpdate() until we get all pushed subs?
	# (4) Pull any subs that are BEHIND
	# (5) Make parent submodule commits for any that need them.


{
	my ($this) = @_;
	display($dbg_subs,0,"doUpdateSubmodules()");


	my $repo_list = getRepoList();
	my $groups = shared_clone([]);
	for my $repo (@$repo_list)
	{
		my $used_in = $repo->{used_in};
		next if !$used_in;

		display($dbg_subs+1,1,"master($repo->{path})");

		my $subs = shared_clone([]);
		my $group = shared_clone({
			name => $repo->{path},
			master => $repo,
			subs => $subs,
			ANY_AHEAD => 0,
			ANY_BEHIND => 0,
			ANY_REBASE => 0,
			changed => 0, });

		push @$groups,$group;

		for my $path ($repo->{path}, @$used_in)
		{
			my $sub = getRepoByPath($path);
			return !repoError($repo,"Could not find used_in($path)")
				if !$sub;
			push @$subs,$sub;

			display($dbg_subs+1,2,"sub($sub->{path})");

			$group->{ANY_AHEAD} ++ if $sub->{AHEAD};
			$group->{ANY_BEHIND} ++ if $sub->{BEHIND};
			$group->{ANY_REBASE} ++ if $sub->{BEHIND};

			my $changes =
				scalar(keys %{$sub->{staged_changes}}) +
				scalar(keys %{$sub->{unstaged_changes}});

			$group->{changed}++ if $changes;
		}
	}


	for my $group (@$groups)
	{
		my $color = $DISPLAY_COLOR_NONE;

		my $subs = $group->{subs};
		display($dbg_subs,-1,"");
		display($dbg_subs,-1,
			"changed($group->{changed}) ".
			"AHEAD($group->{ANY_AHEAD}) ".
			"BEHIND($group->{ANY_BEHIND}) ".
			"REBASE($group->{ANY_REBASE}) ".
			"GROUP($group->{name})");

		warning($dbg_subs,-2,"More than one repo has changes")
			if $group->{changed} > 1;

		for my $sub (@$subs)
		{
			my $changes =
				scalar(keys %{$sub->{staged_changes}}) +
				scalar(keys %{$sub->{unstaged_changes}});

			display($dbg_subs,-1,
				"changes($changes) ".
				"AHEAD($sub->{AHEAD}) ".
				"BEHIND($sub->{BEHIND}) ".
				"REBASE($sub->{REBASE}) ".
				"SUB($sub->{path})");

			display($dbg_subs,-2,"in REBASE state",0,$DISPLAY_COLOR_ERROR)
				if $sub->{REBASE};
			display($dbg_subs,-2,"AHEAD and BEHIND",0,$DISPLAY_COLOR_ERROR)
				if $sub->{AHEAD} && $sub->{BEHIND};
			display($dbg_subs,-2,"changes and BEHIND",0,$DISPLAY_COLOR_ERROR)
				if $sub->{changes} && $sub->{BEHIND};

			display($dbg_subs,-2,"NEEDS PUSH",0,$DISPLAY_COLOR_LOG)
				if $sub->{AHEAD} && !$sub->{BEHIND};
			display($dbg_subs,-2,"NEEDS STASH_PULL",0,$DISPLAY_COLOR_WARNING)
				if $sub->{changes} && $sub->{BEHIND} && !$sub->{AHEAD};
			display($dbg_subs,-2,"NEEDS STASH_PULL",0,$DISPLAY_COLOR_LOG)
				if !$sub->{changes} && $sub->{BEHIND} && !$sub->{AHEAD};

		}
	}

}



1;
