#--------------------------------------------------------
# gitMUI Frame
#--------------------------------------------------------
# TODO: get rid of obsolete "git_changes.bat" that uses this repository, but which I never use
# TODO: get rid of obsolete "git_repos.bat" which denormalizes this code:
#
#	It provides a report with the size and overall usage on github in kb
#	It searches for repos on the machine which dont exist on github.
#	It provides a tabular condensed form showing errors, notes, and warning in one place


package apps::gitMUI::Frame;
use strict;
use warnings;
use threads;
use threads::shared;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_MENU_RANGE
	EVT_UPDATE_UI_RANGE
	EVT_COMMAND );
use Pub::Utils;
use Pub::WX::Frame;
use Pub::WX::Dialogs;
use Pub::WX::AppConfig;
use apps::gitMUI::repo;
use apps::gitMUI::repos;
use apps::gitMUI::reposGithub;
use apps::gitMUI::utils;
use apps::gitMUI::Resources;
use apps::gitMUI::command;
use apps::gitMUI::monitor;
use apps::gitMUI::winRepos;
use apps::gitMUI::winInfo;
use apps::gitMUI::winCommit;
use apps::gitMUI::progressDialog;
use apps::gitMUI::dialogDisplay;
use base qw(Pub::WX::Frame);


my $dbg_frame = 0;
	# lifecycle
my $dbg_cmd = 0;
	# onCommand
my $dbg_mon = 1;
	# monitor callback
my $dbg_notify = 1;
	# notifications to panes

my $MONITOR_EVENT:shared = Wx::NewEventType;


use Win32::OLE;
Win32::OLE::prhSetThreadNum(1);
	# I found this old fix in my own build, under /src/wx/Win32_OLE.
	# This prevents threads from crashing on return (i.e. in HTTPServer
	# 	connections) by setting a flag into my version of Win32::OLE
	# 	that causees it to short return from it's AtExit() method,
	# 	not deleting anything. Otherwise threads get messed up.
	# Presumably everytinng is deleted when the main Perl interpreter
	# 	realy exits.
	# I *may* not have needed to enclose $mp in a loop, but it's
	#	done now so I'm not changing it!



#--------------------------------------
# methods
#--------------------------------------

sub new
{
	my ($class, $parent) = @_;
	display($dbg_frame,0,"apps::gitMUI::Frame->new()");

	setAppFrame(1);
		# allow errors to be reported during startup
	if (!apps::gitMUI::utils::checkInitSystem())
	{
		setAppFrame(undef);
		return;
	}

	my $dlg = apps::gitMUI::dialogDisplay->new(undef,'gitMUI display');
	setRepoUI($dlg);

	return if !parseRepos();
	doGitHub($HOW_GITHUB_INIT);  	# use cachefiles with no network hit if possible

	setRepoUI(undef);
	apps::gitMUI::dialogDisplay::closeSelfIfNoErrors();

	Pub::WX::Frame::setHowRestore($RESTORE_ALL);

	my $this = $class->SUPER::new($parent);

    $this->CreateStatusBar();
	$this->SetMinSize([100,100]);

	EVT_MENU_RANGE($this, $ID_REPOS_WINDOW, $ID_STATUS_WINDOW, \&onOpenWindowById);
	EVT_MENU_RANGE($this, $ID_COMMAND_RESCAN, $ID_COMMAND_PULL_ALL, \&onCommand);
	EVT_UPDATE_UI_RANGE($this, $ID_COMMAND_RESCAN, $ID_COMMAND_PULL_ALL, \&onUpdateUI);

	EVT_COMMAND($this, -1, $THREAD_EVENT, \&onThreadEvent );
	EVT_COMMAND($this, -1, $MONITOR_EVENT, \&onMonitorEvent );

	return if !monitorInit(\&monitor_callback);

	return $this;
}

sub onCloseFrame
{
	my ($this) = @_;
	apps::gitMUI::dialogDisplay::closeSelf();
	$this->SUPER::onCloseFrame();
}


sub createPane
	# Overloaded with "createOrActivatePane" semantic.
	# See Pub::Wx::Frame::activateSingleInstancePane()
{
	my ($this,$id,$book,$data) = @_;
	display($dbg_frame+1,0,"gitMUI::Frame::createPane($id)".
		" book="._def($book).
		" data="._def($data) );

	if ($id == $ID_REPOS_WINDOW)
	{
		my $pane = $this->activateSingleInstancePane($id,$book,$data);
		return $pane if $pane;
	    $book ||= $this->{book};
        return apps::gitMUI::winRepos->new($this,$id,$book,$data);
    }
	elsif ($id == $ID_INFO_WINDOW || $id == $ID_SUBS_WINDOW)
	{
		my $pane = $this->activateSingleInstancePane($id,$book,$data);
		return $pane if $pane;
		$book ||= $this->{book};
        return apps::gitMUI::winInfo->new($this,$id,$book,$data);
	}
	elsif ($id == $ID_COMMIT_WINDOW)
	{
		$book ||= $this->{book};
        return apps::gitMUI::winCommit->new($this,$id,$book,$data);
	}

    return $this->SUPER::createPane($id,$book,$data);
}


sub onOpenWindowById
{
	my ($this,$event) = @_;
	my $window_id = $event->GetId();
	display($dbg_frame,0,"gitMUI::Frame::onOpenWindowById($window_id)");
	$this->createPane($window_id);
}


sub onUpdateUI
{
	my ($this,$event) = @_;
	my $id = $event->GetId();
	my $enable = 0;

	$enable = 1 if $id == $ID_COMMAND_RESCAN && !monitorBusy();
	$enable = 1 if $id == $ID_COMMAND_REFRESH_STATUS && !monitorBusy();
	$enable = 1 if $id == $ID_COMMAND_REBUILD_CACHE && !monitorBusy();
	$enable = 1 if $id == $ID_COMMAND_PUSH_ALL && canPushRepos();
	$enable = 1 if $id == $ID_COMMAND_PULL_ALL && canPullRepos();

	$enable &&= monitorRunning();
	$event->Enable($enable);
}


sub onCommand
{
	my ($this,$event) = @_;
	my $id = $event->GetId();
	$this->onCommandId($id);
}

sub onCommandId
{
	my ($this,$id) = @_;
	my $name = $resources->{command_data}->{$id}->[0];
	display($dbg_cmd,0,"gitMUI::Frame::onCommand($id,$name)");
	if ($id == $ID_COMMAND_PUSH_ALL ||
		$id == $ID_COMMAND_PULL_ALL ||
		$id == $ID_COMMAND_PUSH_SELECTED ||
		$id == $ID_COMMAND_PULL_SELECTED )
	{
		$this->doThreadedCommand($id);
	}
	elsif ($id == $ID_COMMAND_COMMIT_SELECTED_PARENTS)
	{
		$this->commitSelectedParents();
	}
	elsif ($id == $ID_COMMAND_RESCAN ||
		   $id == $ID_COMMAND_REBUILD_CACHE)
	{
		monitorStop();

		my $dlg = apps::gitMUI::dialogDisplay->new($this,'gitMUI display');
		setRepoUI($dlg);

		# destroy the cache if $ID_COMMAND_REBUILD_CACHE,
		# try Etag/304 hits if just $ID_COMMAND_RESCAN
		
		return if !parseRepos();
		my $how = $id == $ID_COMMAND_REBUILD_CACHE ?
			$HOW_GITHUB_REBUILD : $HOW_GITHUB_NORMAL;
		doGitHub($how);
	
		setRepoUI(undef);
		# could leave the dialog open and require manual close
		apps::gitMUI::dialogDisplay::closeSelfIfNoErrors();

		for my $pane (@{$this->{panes}})
		{
			$pane->populate() if $pane->can('populate');
		}
		monitorStart();
	}
	elsif ($id == $ID_COMMAND_REFRESH_STATUS)
	{
		doMonitorUpdate();
	}
}




sub commitSelectedParents
{
	my ($this) = @_;
	display($dbg_cmd,0,"commitSelectedParents()");
	monitorPause(1);
	my $selected_repos = getSelectedCommitParentRepos();
	for my $path (sort keys %$selected_repos)
	{
		my $repo = $selected_repos->{$path};
		last if !$this->commitOneParent($repo);
	}
	monitorPause(0);
}


sub commitOneParent
{
	my ($this,$repo) = @_;
	my $parent = $repo->{parent_repo};
	warning($dbg_cmd,0,"commitOneParent($repo->{path},$parent->{path})");
	$this->SetStatusText("commitOneParent: $repo->{path}");

	my $parent_unstaged = $parent->{unstaged_changes};

	my $commit = ${$repo->{local_commits}}[0];
	my $commit_id = $commit->{sha};
	my $commit_msg = $commit->{msg};
	my $commit8 = _lim($commit_id,8);

	my $found;
	my $rel_path = $repo->{rel_path};
	for my $path (keys %$parent_unstaged)
	{
		if ($path eq $rel_path)
		{
			$found = $parent_unstaged->{$path};
			last;
		}
	}

	my $msg = "submodule($rel_path) auto_commit($commit8) $commit_msg";
	display(0,3,"msg=$msg");

	my $rslt = gitIndex($parent,0,[$rel_path]);
	$rslt &&= gitCommit($parent,$msg);
	gitChanges($parent);

	display($dbg_cmd,1,"AUTO-COMMIT-COMPLETED: $commit8."._lim($commit_msg,40))
		if $rslt;
	$this->notifyRepoChanged($repo);
	return 1;
}



#------------------------------
# monitor
#------------------------------
# A notification of a repo changing that has submodules means
# that we also need to notify on all the submodule repos,
# as the parent could change the canCommitParent status
# of the submodules.

sub notifyRepoChanged
{
	my ($this,$repo,$changed) = @_;
	display($dbg_notify,0,"notifyRepoChanged("._def($changed).",$repo->{path})");
	$changed = 1 if !defined($changed);

	my $notifies = [ $repo ];
	my $submodules = $repo->{submodules};
	if ($submodules)
	{
		for my $path (@$submodules)
		{
			my $sub = getRepoByPath($path);
			push @$notifies,$sub;
		}
	}

	for my $pane (@{$this->{panes}})
	{
		my $can = $pane && $pane->can("notifyRepoChanged") ? 1 : 0;
		my $wants = $changed || ($pane && $pane->{wants_null_changes});
		next if !$can || !$wants;

		display($dbg_notify+1,1,"pane($pane) can($can)");

		for my $notify (@$notifies)
		{
			$pane->notifyRepoChanged($notify,$changed);
		}
	}
}



sub onMonitorEvent
{
	my ($this,$event) = @_;
	my $data = $event->GetData();
	my $repo = $data->{repo};
	my $is_repo = $repo ? 1 : 0;
	my $show = $data->{status} || $repo->{path};
	$this->SetStatusText("monitor: $show");
	display($dbg_mon,0,"onMonitorEvent($is_repo,$show)");
	$this->notifyRepoChanged($repo,$data->{changed}) if $repo;
}



sub monitor_callback
{
	my ($data) = @_;
	my $this = getAppFrame();

	my $repo = $data->{repo};
	my $repo_path = $repo ? $repo->{path} : '';
	my $show = $data->{status} || $repo_path;
	display($dbg_mon,0,"monitor_callback($show");

	setRepoState($data->{repo}) if $repo_path;

	my $evt = new Wx::PlThreadEvent( -1, $MONITOR_EVENT, shared_clone($data) );
	Wx::PostEvent( $this, $evt );
}


#----------------------------
# global Copy functionality
#----------------------------
# These methods are currently unused.
# These methods are only needed if we put Copy in
# the application menu. Otherwise the ctrl itself
# implements a EVT_CHAR(3) handler for CTRL-C, and
# it's contextMenu() calls back to it directly
#
#	sub canCopy
#	{
#		my ($this) = @_;
#		my $pane = $this->{current_pane};
#		display($dbg_copy,0,"canCopy "._def($pane));
#		return $pane->canCopy() if $pane && $pane->can('canCopy');
#		return 0;
#	}
#
#	sub doCopy
#	{
#		my ($this) = @_;
#		$this->{current_pane}->doCopy() if $this->canCopy();
#	}



#----------------------------------------------------
# gitMUI App
#----------------------------------------------------
# For some reason, to exit with CTRL-C from the console
# we need to set PERL_SIGNALS=unsafe in the environment.

package apps::gitMUI::App;
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Utils;
use Pub::WX::Main;
use apps::gitMUI::utils;
use base 'Wx::App';


$USE_SHARED_LOCK_SEM = 1;
# createSTDOUTSemaphore('gitUISTDOUT');


my $dbg_app = 0;

my $frame;


sub OnInit
{
	$frame = apps::gitMUI::Frame->new();
	if (!$frame)
	{
		error("unable to create frame");
		return undef;
	}
	setAppFrame($frame);
	$frame->Show( 1 );
	display($dbg_app,0,"gitUIApp started");
	return 1;
}


my $app = apps::gitMUI::App->new();

Pub::WX::Main::run($app);

$frame = undef;
display($dbg_app,0,"finished gitUIApp");


1;
