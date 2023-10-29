#--------------------------------------------------------
# gitUI Frame  command.pm
#--------------------------------------------------------
# doPushCommand() - implements a gitCommand with a progress Dialog.
#   currently only used for gitPush as gitTag and gitCommit are
# 	known to be quick (or at least workabele without threads/dialogs)

package apps::gitUI::Frame;		# continued
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Utils;
use apps::gitUI::repo;
use apps::gitUI::utils;
use apps::gitUI::repoGit;
use apps::gitUI::Resources;
use apps::gitUI::progressDialog;
use base qw(Pub::WX::Frame);

my $dbg_cmds = 0;
	# 0 = main command functions
	# -1 = details
my $dbg_thread = 0;
	# 0 = msin thread calls
	# -1 = details

our $USE_THREADED_COMMANDS = 0;
	# THERE ARE DEFINITELY PROBLEMS USING THREADS VIS-A-VIS THE MONITOR
	# the thread dying seems to call Wx::Frame::DESTROY(), for example,
	# and somthing when the thread stops causes the moniotr to stop working
	# correctly.  For now I am proceeding with non-threaded commands.


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		$THREAD_EVENT
	);
}

my $command_thread;
my $command_aborted:shared = 0;
my $command_error_abort_reported:shared = 0;


#------------------------------------------
# utilities
#------------------------------------------

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



#------------------------------------------
# main entry point
#------------------------------------------


sub doPushCommand
	# is actually nearly generic for calling gitCommands with Dialog
{
	my ($this,$command_id) = @_;

	$this->{command_id} = $command_id;
	$this->{command_verb} = "Pushing";
	$this->{command_name} =
		$command_id == $ID_COMMAND_PUSH_ALL ? "PushAll" :  "PushSelected";

	display($dbg_cmds,0,"doGitCommand($command_id)=$this->{command_name}");

	$this->{num_actions} = 0;
	my $repo_list = getRepoList();
	for my $repo (@$repo_list)
	{
		my $can_push 	= $repo->canPush();
		my $selected 	= $repo->{selected};
		$repo->{selected} = 0;
			# switch 'selected' to invariant for 'doit'

		my $doit = 0;
		$doit = 1 if $can_push && (
			$command_id == $ID_COMMAND_PUSH_ALL || (
			$command_id == $COMMAND_PUSH && $selected ));

		if ($doit)
		{
			$repo->{selected} = 1;
			$this->{num_actions}++;
		}
	}

	display($dbg_cmds,1,"$this->{command_verb} $this->{num_actions} repos");

	$this->initCommand();

	my $progress = $this->{progress} = apps::gitUI::progressDialog->new(
		$this,
		$this->{command_name},
		\&abortCommand);

	$progress->setParams({
		main_msg    => $this->{command_name},
		main_name   => '',
		main_status => "$this->{num_actions} repos",
		main_range  => $this->{num_actions},
		main_done   => 0 });

	if ($USE_THREADED_COMMANDS)
	{
		display($dbg_thread,1,"starting THREAD");
		@_ = ();
		$command_thread = threads->create(	# barfs: my $thread = threads->create(
			\&doThreadedPush,$this,$repo_list);
		$command_thread->detach(); 			# barfs;
		display($dbg_thread,1,"THREAD_STARTED");
		$command_thread = undef;
	}
	else
	{
		$this->doThreadedPush($repo_list);
	}

	# $this->{progress}->Destroy();
	# $this->{progress} = '';
	display($dbg_cmds,0,"onGitCommand() returning");
}


#-------------------------------------------------
# doThreadedPush (or maybe on main thread)
#-------------------------------------------------

sub doThreadedPush
{
	my ($this,$repo_list,$data) = @_;
	my $command_id = $this->{command_id};
	display($dbg_cmds,0,"doThreadedPush($command_id)=$this->{command_name}");
	display($dbg_cmds+1,1,"data("._def($data).")");

	my $rslt = 1;
	my $act_num = 0;
	for my $repo (@$repo_list)
	{
		if ($repo->{selected})
		{
			$this->sendThreadEvent({
				main_name   => $repo->{path},
				sub_name    => $this->{command_verb} });

			# other commands possible:
			# 	$rslt = gitCommit($repo,$data)
			# 		if $command_id == $COMMAND_COMMIT;
			# 	$rslt = gitTag($repo,$data)
			# 		if $command_id == $COMMAND_TAG;

			$rslt = gitPush($repo,$this,\&push_callback)
				if $command_id == $COMMAND_PUSH ||
				    $command_id == $ID_COMMAND_PUSH_ALL;

			last if $command_aborted || !$rslt;

			$act_num++;
			$this->sendThreadEvent({
				main_status => "$act_num/$this->{num_actions} repos",
				main_done   => $act_num });

		}	# selected
	}	# for each repo

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
		my $params = $command_aborted ?
			{ aborted => 1} :
			{ done => 1 };
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

	if ($USE_THREADED_COMMANDS)
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
		my $num_actions = $this->{num_actions};

		my $use_name = $num_actions ?
			"$this->{command_completed} $num_actions repos" :
			"NOTHING TO DO!!";
		my $main_msg = $num_actions ?
			"Done!!" :
			"Done";
		$progress->setParams({
			main_msg => $main_msg,
			main_name => $use_name });
			$progress->setDone('Close');
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
		# prh changed undef to 'done'  in repo.pm

		my $values = {
			sub_msg => $msg eq 'done' ? "PUSH DONE!!" : 'Refs' };
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




1;
