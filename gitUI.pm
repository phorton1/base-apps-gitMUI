#--------------------------------------------------------
# gitUI Frame
#--------------------------------------------------------

package apps::gitUI::Frame;
use strict;
use warnings;
use threads;
use threads::shared;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_MENU_RANGE
	EVT_UPDATE_UI
	EVT_COMMAND );
use Pub::Utils;
use Pub::WX::Frame;
use Pub::WX::Dialogs;
use apps::gitUI::repo;
use apps::gitUI::repos;
use apps::gitUI::github;
use apps::gitUI::utils;
use apps::gitUI::Resources;
use apps::gitUI::command;
use apps::gitUI::monitor;
use apps::gitUI::pathWindow;
use apps::gitUI::commitWindow;
use apps::gitUI::progressDialog;
use base qw(Pub::WX::Frame);

$TEST_JUNK_ONLY = 1;

my $dbg_frame = 0;
	# lifecycle, major commands
my $dbg_mon = 1;


my $USE_MONITOR = 1;


my $monitor;

my $MONITOR_EVENT:shared = Wx::NewEventType;

sub getMonitor
{
	return $monitor;
}

#--------------------------------------
# methods
#--------------------------------------


sub new
{
	my ($class, $parent) = @_;

	return if !parseRepos();
	doGitHub(1,1);

	Pub::WX::Frame::setHowRestore($RESTORE_ALL);
		# $RESTORE_MAIN_RECT);

	my $this = $class->SUPER::new($parent);	# ,-1,'gitUI',[50,50],[600,680]);

    $this->CreateStatusBar();
	$this->SetMinSize([100,100]);

	EVT_MENU_RANGE($this, $ID_PATH_WINDOW, $ID_TAG_WINDOW, \&onOpenWindowById);
	EVT_MENU_RANGE($this, $ID_COMMAND_RESCAN, $ID_COMMAND_PUSH_ALL, \&onCommand);
	EVT_UPDATE_UI($this, $ID_COMMAND_PUSH_ALL, \&onUpdateUI);

	EVT_COMMAND($this, -1, $THREAD_EVENT, \&onThreadEvent );
	EVT_COMMAND($this, -1, $MONITOR_EVENT, \&onMonitorEvent );

	if ($USE_MONITOR)
	{
		$monitor = apps::gitUI::monitor->new(\&monitor_callback);
		return if !$monitor;
		return if !$monitor->start();
	}

	return $this;
}



sub createPane
{
	my ($this,$id,$book,$data) = @_;
	display($dbg_frame,0,"gitUI::Frame::createPane($id)".
		" book="._def($book).
		" data="._def($data) );

	if ($id == $ID_PATH_WINDOW)
	{
	    $book ||= $this->{book};
        return apps::gitUI::pathWindow->new($this,$id,$book,$data);
    }
	elsif ($id == $ID_COMMIT_WINDOW)
	{
		$book ||= $this->{book};
        return apps::gitUI::commitWindow->new($this,$id,$book,$data);
	}
    return $this->SUPER::createPane($id,$book,$data);
}


sub onOpenWindowById
{
	my ($this,$event) = @_;
	my $window_id = $event->GetId();
	display($dbg_frame,0,"gitUI::Frame::onOpenWindowById($window_id)");
	$this->createPane($window_id);
}

sub onCommand
{
	my ($this,$event) = @_;
	my $id = $event->GetId();
	display($dbg_frame,0,"gitUI::Frame::onCommand($id)");
	if ($id == $ID_COMMAND_PUSH_ALL)
	{
		$this->doPushCommand($id);
	}
	elsif ($id == $ID_COMMAND_RESCAN)
	{
	}
}

sub onUpdateUI
{
	my ($this,$event) = @_;
	my $id = $event->GetId();
	my $enable = 0;
	$enable = 1 if $id == $ID_COMMAND_PUSH_ALL && canPushRepos();
	$event->Enable($enable);
}



#------------------------------
# monitor
#------------------------------

sub onMonitorEvent
{
	my ($this,$event) = @_;
	my $data = $event->GetData();
	my $repo = $data->{repo};
	my $is_repo = $repo ? 1 : 0;
	my $show = $data->{status} || $repo->{path};
	$this->SetStatusText("monitor: $show");
	display($dbg_mon,0,"onMonitorEvent($is_repo,$show)");
	if ($is_repo)
	{
		for my $pane (@{$this->{panes}})
		{
			display($dbg_mon,1,"pane($pane) can=".$pane->can("notifyRepoChanged"));
			if ($pane && $pane->can("notifyRepoChanged"))
			{
				$pane->notifyRepoChanged($repo);
			}
		}
	}
}


sub monitor_callback
{
	my ($data) = @_;
	my $this = getAppFrame();

	my $show = $data->{status} || $data->{repo}->{path};
	display($dbg_mon,0,"monitor_callback($show");

	my $evt = new Wx::PlThreadEvent( -1, $MONITOR_EVENT, shared_clone($data) );
	Wx::PostEvent( $this, $evt );
}




#----------------------------------------------------
# gitUI App
#----------------------------------------------------
# For some reason, to exit with CTRL-C from the console
# we need to set PERL_SIGNALS=unsafe in the environment.

package apps::gitUI::App;
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Utils;
use Pub::WX::Main;
use Pub::WX::AppConfig;
use apps::gitUI::utils;
use base 'Wx::App';

$ini_file = "$data_dir/gitUI.ini";


$USE_SHARED_LOCK_SEM = 1;
createSTDOUTSemaphore($HOW_SEMAPHORE_LOCAL);


my $dbg_app = 0;

my $frame;


sub OnInit
{
	$frame = apps::gitUI::Frame->new();
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


my $app = apps::gitUI::App->new();

Pub::WX::Main::run($app);

$frame = undef;
display($dbg_app,0,"finished gitUIApp");


1;
