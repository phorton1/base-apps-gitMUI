#--------------------------------------------------------
# gitUI Frame
#--------------------------------------------------------

package apps::gitUI::Frame;		# continued
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Utils;
use apps::gitUI::repo;
use apps::gitUI::styles; 	# for $THREAD_EVENT!!
use apps::gitUI::progressDialog;
use base qw(Pub::WX::Frame);

my $dbg_cmds = 0;
	# 0 = main command functions
	# -1 = details
my $dbg_thread = -1;
	# 0 = msin thread calls
	# -1 = details

our $USE_THREADED_COMMANDS = 1;


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

sub onGitCommand
{
	my ($this,$event) = @_;
	my $command_id = $event->GetId();
	$this->{command_id} = $command_id;
	$this->{command_name} = $resources->{command_data}->{$command_id}->[0];
	display($dbg_cmds,0,"onGitCommand($command_id)=$this->{command_name}");

	$this->initCommand();
	$command_thread = undef;

	my $repo_list = getRepoList();
	my $data = 'test commit '.localtime();
		# Commit needs to get the description

	my $progress = $this->{progress} = apps::gitUI::progressDialog->new(
		$this,
		$this->{command_name},
		\&abortCommand);

	if ($USE_THREADED_COMMANDS)
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


#-------------------------------------------------
# doThreadedCommand (or maybe on main thread)
#-------------------------------------------------

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


	# DO THE CHANGES FIRST AS A FULL GAUGE
	# obtaining $num_actions for other $command-ids

	my $repo_num = 0;
	my $num_actions = 0;
	my $num_changed_repos = 0;
	my $num_unstaged_files = 0;
	my $num_staged_files = 0;
	my $num_remote_files = 0;
	my $num_unstaged_repos = 0;
	my $num_staged_repos = 0;
	my $num_remote_repos = 0;

	for my $repo (@$repo_list)
	{
		# Commands disaabled except for /junk if $TEST_JUNK_ONLY
		# see $TEST_JUNK_ONLY in repo.pm

		next if $TEST_JUNK_ONLY && $repo->{path} !~ /junk/;

		last if $command_aborted;

		$repo->gitChanges();

		$repo_num++;

		my $num_unstaged = keys %{$repo->{unstaged_changes}};
		my $num_staged =   keys %{$repo->{staged_changes}};
		my $num_remote =   keys %{$repo->{remote_changes}};

		$num_unstaged_files += $num_unstaged;
		$num_staged_files   += $num_staged;
		$num_remote_files   += $num_remote;
		$num_unstaged_repos ++ if $num_unstaged;
		$num_staged_repos   ++ if $num_staged;
		$num_remote_repos   ++ if $num_remote;

		$num_changed_repos  ++ if $num_unstaged || $num_staged || $num_remote;

		$num_actions++ if
			($command_id == $COMMAND_ADD && $repo->canAdd()) ||
			($command_id == $COMMAND_COMMIT && $repo->canCommit()) ||
			($command_id == $COMMAND_PUSH && $repo->canPush());

		my $status_msg =
			$command_id == $COMMAND_ADD ? "$num_actions/$num_repos canAdd" :
			$command_id == $COMMAND_COMMIT ? "$num_actions/$num_repos canCommit" :
			$command_id == $COMMAND_PUSH ? "$num_actions/$num_repos canPush" :
			"$num_changed_repos/$num_repos changed";

		$this->sendThreadEvent({
			main_msg    => 'Checking',
			main_name   => $repo->{path},
			main_status => $status_msg,
			main_range  => $num_repos,
			main_done   => $repo_num });

		last if $command_aborted;
	}

	# DO THE COMMAND if $num_actions

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
			# canXXX() disaabled except for /junk if $TEST_JUNK_ONLY

			my $doit = 0;
			$doit = 1 if $command_id == $COMMAND_ADD && $repo->canAdd();
			$doit = 1 if $command_id == $COMMAND_COMMIT && $repo->canCommit();
			$doit = 1 if $command_id == $COMMAND_PUSH && $repo->canPush();

			if ($doit)
			{
				display($dbg_cmds+1,2,"doThreadedCommand($this->{command_name}) doing($repo->{path})");

				last if $command_aborted;

				$this->sendThreadEvent({
					main_name   => $repo->{path},
					sub_name    => $action_name });

				$rslt = $repo->gitAdd() if $command_id == $COMMAND_ADD;
				$rslt = $repo->gitCommit($data) if $command_id == $COMMAND_COMMIT;
				$rslt = $repo->gitPush($this,\&push_callback) if $command_id == $COMMAND_PUSH;

				last if $command_aborted || !$rslt;

				$num_actions_done++;
				$this->sendThreadEvent({
					main_status => "$num_actions_done/$num_actions repos",
					main_done   => $num_actions_done });

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
			num_changed_repos	=> $num_changed_repos,
			num_unstaged_files 	=> $num_unstaged_files,
			num_staged_files 	=> $num_staged_files,
			num_remote_files 	=> $num_remote_files,
			num_unstaged_repos 	=> $num_unstaged_repos,
			num_staged_repos 	=> $num_staged_repos,
			num_remote_repos 	=> $num_remote_repos };
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
		if ($command_id == $COMMAND_CHANGES)
		{
			$progress->setDone('Done');

			my $use_name = '';
			$use_name .= "unstaged($params->{num_unstaged_repos},$params->{num_unstaged_files}) "
				if $params->{num_unstaged_repos};
			$use_name .= "staged($params->{num_staged_repos},$params->{num_staged_files}) "
				if $params->{num_staged_repos};
			$use_name .= "remote($params->{num_remote_repos},$params->{num_remote_files}) "
				if $params->{num_remote_repos};

			my $final = { main_name => $use_name };
			$final->{main_msg} = $params->{num_changed_repos} ?
				"CHANGES" :"NO CHANGES!!";
			$progress->setParams($final);
		}
		else
		{
			my $num_actions = $params->{num_actions};

			my $what =
				$command_id == $COMMAND_PUSH ? "pushed" :
				$command_id == $COMMAND_COMMIT ? "committed" :
				$command_id == $COMMAND_ADD ? "added" : '';
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
