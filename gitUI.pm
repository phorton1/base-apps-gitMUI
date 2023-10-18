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
	EVT_COMMAND
	EVT_IDLE );
use Pub::Utils;
use Pub::WX::Frame;
use Pub::WX::Dialogs;
use apps::gitUI::repo;
use apps::gitUI::repos;
use apps::gitUI::Resources;
use apps::gitUI::pathWindow;
use apps::gitUI::progressDialog;
use base qw(Pub::WX::Frame);

my $dbg_frame = 0;
	# lifecycle, major commands
my $dbg_cmds = 0;
	# 0 = main command functions
	# -1 = details
my $dbg_thread = -1;
	# 0 = msin thread calls
	# -1 = details
our $dbg_idle = 1;
	# 0 = show onIdle stuff


# THREADING SETUP

my $USE_THREADS = 1;

my $command_thread;

my $THREAD_EVENT:shared = Wx::NewEventType;
my $command_aborted:shared = 0;
my $command_error_abort_reported:shared = 0;


#--------------------------------------
# methods
#--------------------------------------


sub new
{
	my ($class, $parent) = @_;

	Pub::WX::Frame::setHowRestore($RESTORE_MAIN_RECT);

	my $this = $class->SUPER::new($parent);	# ,-1,'gitUI',[50,50],[600,680]);

    $this->CreateStatusBar();
	$this->createPane($ID_PATH_WINDOW);

	EVT_IDLE($this,\&onIdle);
	EVT_MENU_RANGE($this, $COMMAND_CHANGES, $COMMAND_TAGS, \&onGitCommand);
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



#################################################################
# onGitCommand
#################################################################


sub initCommand
{
	my ($this) = @_;
	$command_aborted = 0;
	$command_error_abort_reported = 0;
}


sub abortCommand
{
	my ($this) = @_;
	if (!$command_aborted)
	{
		warning(0,0,"abortCommand()");
		$command_aborted = 1;
		$this->sendThreadEvent({ aborted => 1});
	}
}


sub onGitCommand
{
	my ($this,$event) = @_;
	my $command_id = $event->GetId();
	$this->{command_id} = $command_id;
	$this->{command_name} = $resources->{command_data}->{$command_id}->[0];
	display($dbg_cmds,0,"onGitCommand($command_id)=$this->{command_name}");

	$this->initCommand();
	$command_thread = undef;

	return if !parseRepos();
	my $repo_list = getRepoList();
	my $data = '';
		# Commit needs to get the description

	my $progress = $this->{progress} = apps::gitUI::progressDialog->new(
		$this,
		$this->{command_name},
		\&abortCommand);

	if ($USE_THREADS)
	{
		display($dbg_thread,1,"starting THREAD");
		@_ = ();
		$command_thread = threads->create(	# barfs: my $thread = threads->create(
			\&doThreadedCommand,$this,$repo_list,$data);
		$command_thread->detach(); 			# barfs;
		display($dbg_thread,1,"THREAD_STARTED");
	}
	else
	{
		$this->doThreadedCommand($repo_list,$data);
	}

	# $this->{progress}->Destroy();
	# $this->{progress} = '';
	display($dbg_cmds,0,"onGitCommand() returning");
}


sub doThreadedCommand
{
	my ($this,$repo_list,$data) = @_;
	my $command_id = $this->{command_id};
	display($dbg_cmds,0,"doThreadedCommand($command_id)=$this->{command_name}");
	display($dbg_cmds+1,1,"data='$data'");

	my $num_repos = @$repo_list;
	my $action_name =
		$command_id == $COMMAND_PUSH ? "Pushing" :
		$command_id == $COMMAND_COMMIT ? "Commit" : '';

	my $repo_num = 0;
	my $num_actions = 0;
	my $num_changed_repos = 0;
	my $num_changed_local_files = 0;
	my $num_changed_remote_files = 0;
	my $num_changed_local_repos = 0;
	my $num_changed_remote_repos = 0;
	for my $repo (@$repo_list)
	{
		# Commit and Push are currently disabled except for /junk
		# see $TEST_JUNK_ONLY in repo.pm

		# comment in following line to save time doing push(junk) over and over again
		# to not call gitChanges on every repo every time.
		#
		# next if $repo->{path} !~ /junk/;

		last if $command_aborted;

		$repo->gitChanges();

		$repo_num++;

		my $num_local = @{$repo->{local_changes}};
		my $num_remote = @{$repo->{local_changes}};

		$num_changed_local_files += $num_local;
		$num_changed_remote_files += $num_remote;
		$num_changed_local_repos++ if $num_local;
		$num_changed_remote_repos++ if $num_remote;
		$num_changed_repos++ if $num_local || $num_remote;

		$num_actions++ if
			($command_id == $COMMAND_PUSH && $repo->canPush()) ||
			($command_id == $COMMAND_COMMIT && $repo->canCommit());

		my $status_msg =
			$command_id == $COMMAND_PUSH ? "$num_actions/$num_repos canPush" :
			$command_id == $COMMAND_COMMIT ? "$num_actions/$num_repos canCommit" :
			"$num_changed_repos/$num_repos changed";

		$this->sendThreadEvent({
			main_msg    => 'Checking',
			main_name   => $repo->{path},
			main_status => $status_msg,
			main_range  => $num_repos,
			main_done   => $repo_num });

		last if $command_aborted;
	}

	my $rslt = 1;
	if ($num_actions)
	{
		$this->sendThreadEvent({
			main_msg    => $this->{command_name},
			main_name   => '',
			main_status => "$num_actions repos",
			main_range  => $num_actions,
			main_done   => 0 });

		my $num_actions_done = 0;
		for my $repo (@$repo_list)
		{
			# next if $repo->{path} ne '/junk/junk_repository';

			my $doit = 0;
			$doit = 1 if $command_id == $COMMAND_PUSH && $repo->canPush();
			$doit = 1 if $command_id == $COMMAND_COMMIT && $repo->canCommit();

			if ($doit)
			{
				display($dbg_cmds+1,2,"doThreadedCommand($this->{command_name}) doing($repo->{path})");

				last if $command_aborted;

				if ($command_id == $COMMAND_PUSH)
				{
					$this->sendThreadEvent({
						main_name   => $repo->{path},
						sub_name    => $action_name });

					$rslt = $repo->gitPush($this,\&push_callback);
					last if !$rslt;		# error was reported via callback

					if (!$command_aborted)
					{
						$num_actions_done++;
						$this->sendThreadEvent({
							main_status => "$num_actions_done/$num_actions repos",
							main_done   => $num_actions_done });
					}

				}	# PUSH
			}	# doit
		}	# for each repo
	}	# $num_actions


	# The abort sequence from aborting Transfer is strange.
	# The progressDialog calls abortCommand() which sets
	# $command_aborted, which sendThreadedEvent(aborted),
	# which then tells the dialog to display the message
	# in red.  However, the process continues until the
	# next $PUSH_CB_TRANSFER which then returns GIT_EUSER
	# to the libgit2 C code, which then terminates the Push,
	# and ends up here, which calls sendThreadedEvent(aborted)
	# again.

	if ($rslt)
	{
		my $params = $command_aborted ? { aborted => 1} : {
			done => 1,
			num_actions => $num_actions,
			num_changed_repos		 => $num_changed_repos,
			num_changed_local_files  => $num_changed_local_files,
			num_changed_remote_files => $num_changed_remote_files,
			num_changed_local_repos  => $num_changed_local_repos,
			num_changed_remote_repos => $num_changed_remote_repos };
		$this->sendThreadEvent( $params );
	}


	display($dbg_cmds,0,"doThreadedCommand() finished");

}	# doThreadedCommand()



#-----------------------------------------
# doThreadedCommand support
#-----------------------------------------

sub sendThreadEvent
{
	my ($this,$params) = @_;
	my $show = join(",",keys %$params);
	display($dbg_thread+1,1,"sendThreadEvent($show)");

	if ($USE_THREADS)
	{
		my $evt = new Wx::PlThreadEvent( -1, $THREAD_EVENT, shared_clone($params) );
		Wx::PostEvent( $this, $evt );
	}
	else
	{
		$this->updateProgress($params);
	}

}


sub onThreadEvent
	# only called if $USE_FORK
{
	my ($this, $event ) = @_;
	if (!$event)
	{
		error("No event in onThreadEvent!!");
		return;
	}
	if (!$this->{progress})
	{
		error("No progress in onThreadEvent!!");
		return;
	}

	my $params = $event->GetData();
	my $show = join(",",keys %$params);
	display($dbg_thread+1,0,"onThreadEvent($show)");

	$this->updateProgress($params);
}


sub updateProgress
{
	my ($this,$params) = @_;
	my $progress = $this->{progress};
	my $command_id = $this->{command_id};
	return if !$progress;

	my $show = join(",",keys %$params);
	display($dbg_thread+1,1,"updateProgress($show)");

	# we prevent more than one error/abort window
	# from popping up here .. we have to use $already_reported
	# to set the shared $command_error_abort_reported BEFORE
	# we pop up the error/abort dialog to prevent re-entering.

	if ($params->{error})
	{
		my $err = $params->{error};
		my $already_reported = $command_error_abort_reported;
		$command_error_abort_reported = 1;

		# for some reason the original error() in repo.pm
		# does not show in the UI, and so we need to show it here

		$this->showError($err)
			if !$already_reported;
		$progress->setParams({
			main_msg => 'Error !!!',
			main_name => $err });
		$progress->setDone('Close');
	}
	elsif ($params->{aborted})
	{
		my $already_reported = $command_error_abort_reported;
		$command_error_abort_reported = 1;

		$progress->setParams({
			main_msg => 'Aborted!' });
		$progress->setDone('Close');
		okDialog($this,
			"$this->{command_name} command was aborted.",
			"$this->{command_name} ABORTED!")
			if !$already_reported;
	}
	elsif ($params->{done})
	{
		if ($command_id == $COMMAND_CHANGES)
		{
			$progress->setDone('Done');

			my $use_name = '';
			$use_name .= "local($params->{num_changed_local_repos},$params->{num_changed_local_files}) "
				if $params->{num_changed_local_repos};
			$use_name .= "remote($params->{num_changed_remote_repos},$params->{num_changed_remote_files}) "
				if $params->{num_changed_remote_repos};
			my $final = { main_name => $use_name };
			$final->{main_message} = "NO CHANGES!!"
				if !$params->{num_changed_local_repos} &&
				   !$params->{num_changed_remote_repos};
			$progress->setParams($final);
		}
		else
		{
			my $num_actions = $params->{num_actions};
			my $what = $command_id == $COMMAND_PUSH ?
				"pushed" : "committed" ;
			my $use_name = $num_actions ?
				"$num_actions repos $what" :
				"NOTHING TO DO!!";
			my $main_msg = $num_actions ?
				"Done!!" :
				"Done";
			$progress->setParams({
				main_msg => $main_msg,
				main_name => $use_name });

			$progress->setDone('Close');
		}

		for my $pane (@{$this->{panes}})
		{
			my $id = $pane->GetId();
			$pane->updateLinks() if $id == $ID_PATH_WINDOW;
		}
	}
	else
	{
		$progress->setParams($params);
	}
}


#---------------------------------------------
# push_callback
#----------------------------------------------
# PACK is called first, stage is 0 on first, 1 thereafter
# 	when done, $total = the number of objects for the push
# TRANSFER show the current, and total objects and bytes
#   transferred thus far.
# REFERENCE is the last (set of) messages as git updates
#   the local repository's origin/$branch to the HEAD.
#   There could be multiple, but I usually only see one.
#   The push is complete when REFERENCE $msg is undef.

my $transfer_start:shared = 0;

sub pct_msg
{
	my ($lval,$rval) = @_;
	my $pct = $lval && $rval ? int(($lval * 100) / $rval) : 0;
	return sprintf("%3d%%  $lval/$rval",$pct);
}

sub push_callback
{
	my ($this, $CB, $repo, @params) = @_;
	my $show = join(",",@params);
	display($dbg_thread+1,0,"push_callback($CB,$show)");

	# ABORTING PUSH FROM CALLBACK.
	# We give priority to abort and short return here.
	#
	# from libgit2  errors.h
	# 	"GIT_EUSER is a special error that is never generated by libgit2
	#  	 code.  You can return it from a callback (e.g to stop an iteration)
	#  	 to know that it was generated by the callback and not by libgit2."
	#
	# The error is not returned to libgit2 except for $PUSH_CB_TRANSFER,
	# where I specifically modified Raw.xs to pass it back.
	# That causes the push to actually end.

	my $GIT_EUSER = -7;
	if ($command_aborted)
	{
		warning($dbg_thread,-1,"push_callback returning GIT_EUSER=-7");
		return $GIT_EUSER;
	}

	# display(0,0,"push_callback $CB ".join(',',@params));
	# print "push_callback $CB ".join(',',@params);

	if ($CB == $PUSH_CB_PACK)
	{
		my ($stage, $current, $total) = @params;
		my $values = {
			sub_msg => 'Packing',
			sub_name => '',
			sub_status => '',
			sub_range => $total,
			sub_done => $current };
		$this->sendThreadEvent($values);
	}
	elsif ($CB == $PUSH_CB_TRANSFER)
	{
		my ($current, $total, $bytes) = @params;
		$transfer_start ||= time();
		my $denom = time() - $transfer_start;
		my $rate = $current && $denom ?
			int($bytes / ($denom * 1024))." kBs" : '';
		my $kb = int(($bytes + 512) / 1024)." kB";
		my $pct_msg = pct_msg($current,$total);
		my $values = {
			sub_msg => 'Transfer',
			sub_name => $pct_msg."   ".$kb,
			sub_status => $rate,
			sub_range => $total,
			sub_done => $current };
		$this->sendThreadEvent($values);
	}
	elsif ($CB == $PUSH_CB_REFERENCE)
	{
		my ($ref, $msg) = @params;
		my $values = {
			sub_msg => defined($msg) ? 'Refs' : "PUSH DONE!!" };
		$this->sendThreadEvent($values);
	}
	elsif ($CB == $PUSH_CB_ERROR)
	{
		my ($err) = @params;
		$this->sendThreadEvent({error => $err});
	}
	else
	{
		error("UNKNOWN PUSH CB($CB)!!");
	}

	return 0;
}





#-----------------------------------------------
# onIdle()
#-----------------------------------------------

sub onIdle
{
	my ($this, $event ) = @_;

	# $event->RequestMore();
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
