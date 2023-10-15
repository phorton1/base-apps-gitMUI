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
	EVT_MENU
	EVT_COMMAND
	EVT_IDLE );
use Pub::Utils;
use Pub::WX::Frame;
use apps::gitUI::repo;
use apps::gitUI::repos;
use apps::gitUI::Resources;
use apps::gitUI::pathWindow;
use apps::gitUI::pushDialog;
use base qw(Pub::WX::Frame);

my $dbg_frame = 0;
	# lifecycle, major commands
my $dbg_push = 1;
	# 0 = main push functions
	# -1 = details
my $dbg_thread = 1;
	# 0 = msin thread calls
	# -1 = dtails
our $dbg_idle = 1;
	# 0 = show onIdle stuff


# THREADING SETUP

my $REDIRECT_STDERR = 1;
	# redirect STDER to $stderr_filename for push command

my $THREADED_NONE = 0;
my $THREADED_FORK = 1;
my $THREADED_THREAD = 2;
	# how to do threading ($THREADED_THREAD curreently working)

my $HOW_THREADED = $THREADED_THREAD;
my $THREAD_EVENT:shared = Wx::NewEventType;

my $fork_num = 0;
	# if $HOW_THREADED == $THREADED_FORK
my $push_thread;
	# if $HOW_THREADED == $THREADED_THREAD

my $stderr_filename;
my $stderr_handle;
	# if $REDIRECT_STDERR
my $last_size:shared = 0;
	# last bytes read from $stderr_handle in onIdle();

my $push_aborted:shared = 0;
	# abortPush() called by pushDialog.pm


#--------------------------------------
# methods
#--------------------------------------


sub new
{
	my ($class, $parent) = @_;

	Pub::WX::Frame::setHowRestore($RESTORE_MAIN_RECT);
	$stderr_filename= "$temp_dir/stderr_for_push_command.txt";
		# after $temp_dir setup in gitUI::git.pm

	my $this = $class->SUPER::new($parent);	# ,-1,'gitUI',[50,50],[600,680]);

    $this->CreateStatusBar();
	$this->createPane($ID_PATH_WINDOW);

	EVT_IDLE($this,\&onIdle);
	EVT_MENU($this, $COMMAND_PUSH, \&onCommandPush);
	EVT_COMMAND($this, -1, $THREAD_EVENT, \&onThreadEvent );

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
    return $this->SUPER::createPane($id,$book,$data);
}



#######################
# commandPush
#######################


sub initPush
{
	my ($this) = @_;

	close($stderr_handle) if $stderr_handle;
	$stderr_handle = undef;
	unlink $stderr_filename;
	$push_aborted = 0;
	$last_size = 0;
}


sub abortPush
{
	my ($this) = @_;
	if (!$push_aborted)
	{
		warning(0,0,"abortPush()");
		$push_aborted = 1;
	}
}



sub onCommandPush
{
	my ($this,$event) = @_;
	display($dbg_push,0,"onCommandPush()");

	$this->initPush();

	return if !parseRepos();
	my $repo_list = getRepoList();


	$this->{progress} = apps::gitUI::pushDialog->new($this,scalar(@$repo_list));


	if ($HOW_THREADED == $THREADED_FORK)
	{
		$fork_num++;
		my $child_pid = fork();
		if (!defined($child_pid))
		{
			error("FS_FORK($fork_num) FAILED!");
			return;
		}
		if (!$child_pid)	# child fork
		{
			display($dbg_thread,0,"THREADED_FORK_START($fork_num) pid=$$");
			$this->doThreadedPush($repo_list);
			display($dbg_thread,0,"THREADED_FORK_END($fork_num) pid=$$");
			exit();
		}
	}
	elsif ($HOW_THREADED == $THREADED_THREAD)
	{
		display($dbg_thread,1,"starting THREAD");
		@_ = ();
		$push_thread = threads->create(	# barfs: my $thread = threads->create(
			\&doThreadedPush,$this,$repo_list);
		$push_thread->detach(); 			# barfs;
		display($dbg_thread,1,"THREAD_STARTED");
	}
	else
	{
		$this->doThreadedPush($repo_list);
	}

	# $this->{progress}->Destroy();
	# $this->{progress} = '';
	display($dbg_push,0,"onCommandPush() returning");
}



sub updateProgress
{
	my ($this,$what,$data) = @_;
	return if !$this->{progress};
	if ($what eq 'checkRepo')
	{
		$this->{progress}->checkRepo($data);
	}
	elsif ($what eq 'incPushNeeded')
	{
		$this->{progress}->incPushNeeded();
	}
	elsif ($what eq 'startPush')
	{
		$this->{progress}->startPush($data);
	}
	elsif ($what eq 'handleMessage')
	{
		$this->{progress}->handleMessage($data);
	}
	elsif ($what =~ /^done|noChanges|aborted$/)
	{
		$this->{progress}->finish($what);
		$this->initPush();
	}
}


sub sendThreadEvent
{
	my ($this,$packet) = @_;
	display($dbg_thread+1,1,"sendThreadEvent() $packet->{what})");

	if ($HOW_THREADED)
	{
		my $evt = new Wx::PlThreadEvent( -1, $THREAD_EVENT, shared_clone($packet) );
		Wx::PostEvent( $this, $evt );
	}
	else
	{
		$this->updateProgress($packet->{what},$packet->{data});
	}

}


sub doThreadedPush
{
	my ($this,$repo_list) = @_;
	display($dbg_push,0,"doThreadedPush()");


	my $num_pushes = 0;
	for my $repo (@$repo_list)
	{
		last if $push_aborted;
		$this->sendThreadEvent({
			what => 'checkRepo',
			data  => $repo->{path} });

		last if $push_aborted;
		$repo->gitChanges();

		last if $push_aborted;

		if ($repo->canPush())
		{
			$this->sendThreadEvent({what => 'incPushNeeded'});
			$num_pushes++;
		}
	}



	if ($num_pushes)
	{
		local *SAVED_STDERR;
		if ($REDIRECT_STDERR)
		{
			open(*SAVED_STDERR, ">&", STDERR);
			open(STDERR, ">",  $stderr_filename );
		}

		for my $repo (@$repo_list)
		{
			# next if $repo->{path} ne '/junk/junk_repository';
			if ($repo->canPush())
			{
				display($dbg_push+1,2,"doThreadedPush() startPush($repo->{path})");

				last if $push_aborted;
				$this->sendThreadEvent({
					what => 'startPush',
					data  => $repo->{path} });

				display($dbg_push+1,2,"doThreadedPush() calling repo->gitPush()");

				last if $push_aborted;

				# There's some convoluted logic to get 'git push' messages
				# to display in the pushDialog() progress ..
				#
				# We generally use both the local $USE_SHARED_LOCK_SEM
				# AND $WITH_SEMAPHORES = $HOW_SEMAPHORE_LOCAL to prevent
				# calls to STDOUT from overlapping, and especially, separately,
				# in repo::gitCall() where it pipes input in from backticks.
				# That was necessary to get gitChanges() to work with threads.
				#
				# We redirect STDERR to a file called $stderr, above, AFTER we
				# have called gitChanges, so that we can capture the STDERR
				# output the 'git_push call' from $repo->gitPush() below.
				# We then temporarily turn off the semaphores so that, in this
				# case, other process (onIdle()) can run while the backticks
				# are underway.
				#
				# The use of debugging output in this is probably problematic.
				# I currently have all debugging from onIdle(() to pushDialog::
				# handleMessage() turned off.  It seems to be working.

				my $save_with = $WITH_SEMAPHORES;
				my $save_local = $USE_SHARED_LOCK_SEM;
				$WITH_SEMAPHORES = 0;
				$USE_SHARED_LOCK_SEM = 0;

				$repo->gitPush();

				$WITH_SEMAPHORES = $save_with;
				$USE_SHARED_LOCK_SEM = $save_local;
			}
		}


		open( STDERR, ">&", SAVED_STDERR) if $REDIRECT_STDERR;
		display($dbg_push,0,"doThreadedPush() finished");
	}


	$this->sendThreadEvent({ what =>
		$push_aborted ? "aborted" :
		!$num_pushes ? "noChanges" :
		"done" });

	$this->initPush();

}



sub notifyPushProgress
	# only called from repo.pm if $DO_ASYNCH_PUSH
{
	my ($this,$buf) = @_;
	display($dbg_push+1,0,"notifyPushProgress($buf)");
	$this->sendThreadEvent({
		what => 'handleMessage',
		data  => $buf });
	return !$push_aborted;
}




my $no_progess_reported:shared = 0;


sub onThreadEvent
	# only called if $USE_FORK
{
	my ($this, $event ) = @_;
	if (!$event)
	{
		error("No event in onThreadEvent!!");
		return;
	}
	if (!$this->{progress} && !$no_progess_reported)
	{
		error("No progress in onThreadEvent!!");
		$no_progess_reported = 1;
		return;
	}

	my $hash = $event->GetData();
	my $what = $hash->{what};
	my $data = $hash->{data} || '';
	display($dbg_thread+1,0,"onThreadEvent($what) data=".length($data)." bytes");

	$this->updateProgress($what,$data);
}





sub onIdle
{
	my ($this, $event ) = @_;

	if ($this->{progress} && -f $stderr_filename)
	{
		# display($dbg_push,0,"onIdle() checking $stderr");

		my ($dev,$ino,$in_mode,$nlink,$uid,$gid,$rdev,$size,
			$atime,$mtime,$ctime,$blksize,$blocks) = stat($stderr_filename);

		if ($last_size != $size)
		{
			display($dbg_idle,1,"onIdle() $last_size to $size");
			my $bytes = $size - $last_size;
			$last_size = $size;
			return if $bytes <= 0;

			if (!$stderr_handle)
			{
				display($dbg_idle,2,"onIdle() opening $stderr_filename for input");
				if (!open($stderr_handle,"<$stderr_filename"))
				{
					error("Could not open $stderr_filename for input");
					$this->{progress} = '';
					return;
				}
				if (!$stderr_handle)
				{
					error("no stderr_handle to $stderr_filename");
					$this->{progress} = '';
					return;
				}
			}


			my $buf;
			my $got = sysread($stderr_handle,$buf,$bytes);
			if ($got != $bytes)
			{
				error("STDERR FILE ERROR got($got) expected($bytes)");
				$this->{progress} = '';
				return;
			}
			else
			{
				display($dbg_idle,3,"onIdle() got (((($buf))))");
				$this->{progress}->handleMessage($buf);

			}	# $got == $bytes
		}	# $last_size != $size
	}	# $this->{progress} && -f $stderr

	# shut the handle if it's open

	elsif ($stderr_handle)
	{
		display($dbg_push,2,"onIdle() closing $stderr_filename");
		close($stderr_handle);
		$stderr_handle = undef;
	}

	$event->RequestMore();
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
use apps::gitUI::git;	# for $temp_dir and $data_dir
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
