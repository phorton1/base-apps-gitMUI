#!/usr/bin/perl
#--------------------------------------------------
# apps::gitUI::progressDialog
#--------------------------------------------------
# A progress dialog for a Push
#
# there are 5 basic stages to pushing a repository
#
#		buf=Counting objects:   0% (1/5600)
#		buf=Compressing objects:   1% (54/5323)
#		buf=Writing objects:   4% (253/5599), 984.00 KiB | 767.00 KiB/s
#
# Where everything after the comma is optional during Writing
#
# besides those messages, there are several very quick ones
#
# 		buf=Enumerating objects: 5600, done.
#       .. counting
#		buf=Counting objects: 100% (5600/5600), done.
#		buf=Delta compression using up to 16 threadsCompressing objects:   0% (1/5323)
#       .. compressing
#		buf=Compressing objects: 100% (5323/5323), done.
#		.. writing
#		buf=Writing objects: 100% (5599/5599), 40.16 MiB | 741.00 KiB/s, done.
# 		buf=Total 5599 (delta 1708), reused 0 (delta 0), pack-reused 0
# 		buf=remote: Resolving deltas:   0% (0/1708)
# 		... quick enough to get multiple lines in one read
# 		buf=remote: Resolving deltas: 100% (1708/1708), done.
# 		buf=To https://github.com/phorton1/junk.git   4b9f5ab..01c7327  master -> master
#
# We up this to 5 stages where the beginning and end stages don't have any actual progress
# I also have no idea how ERRORS or ABORT are going to work.

package apps::gitUI::progressDialog;
use strict;
use warnings;
use threads;
use threads::shared;
use Time::HiRes qw( sleep );
use Wx qw(:everything);
use Wx::Event qw(EVT_CLOSE EVT_BUTTON);
use Pub::Utils qw(getAppFrame display warning);
use Pub::WX::Dialogs;
use apps::gitUI::Resources;
use base qw(Wx::Dialog);


my $dbg_dlg = 0;
my $dbg_update = 1;


my $ID_WINDOW = 18000;
my $ID_CANCEL = 4567;

my $PUSH_RANGE = 301;
	# see notes below

my @stages = (
	'Checking',		# in the main thread, calls to $repo->gitChanges()
	# the following are per-pushed-repository

	'Starting',
	'Counting',
	'Compressing',
	'Writing',
	'Finishing',
	'Finished', );

# stats

my $local_changed:shared = 0;
my $remote_changed:shared = 0;
	# repos
my $local_changes:shared = 0;
my $remote_changes:shared = 0;
	# files

#------------------------------------------------
# ctor
#------------------------------------------------

sub new
{
    my ($class,
		$parent,
		$command_id,
		$num_repos) = @_;

	my $command_name = $resources->{command_data}->{$command_id}->[0];
	display($dbg_dlg,0,"progressDialog::new($command_id,$command_name) for $num_repos repos)");

    my $this = $class->SUPER::new(
		$parent,
		$ID_WINDOW,
		"$command_name for $num_repos repos",
		[-1,-1],
		[480,180]);

	$this->{command_id} = $command_id;
	$this->{command_name} = $command_name;
	$this->{window_done} = 0;
		# set during finish()

	$this->{parent}  	= $parent;
	$this->{aborted} 	= 0;
	$this->{main_msg}   = $this->{command_name};	# generally shows the stage we are in ..
	$this->{repo}       = '';			# shows the current repo name while checking and pushing

	# stats

	$local_changed = 0;
	$remote_changed = 0;
	$local_changes = 0;
	$remote_changes = 0;

	# These are the range and done for the main_gauge

	$this->{main_done}   = 0;
	$this->{main_range}  = $num_repos;

	# The app calls $this->checkRepo($path) which
	# displays the path and increments {main_done}.
	# The app then calls $repo->gitChanges() for each repo,
	# and if it needs pushing it calls $this->incPushNeeded()
	# which updates {action_todo} and displays it.

	$this->{action_todo} = 0;
	$this->{action_finished} = 0;

	# Then, for each repository needing a push, the app calls
	# $this->startPush(path).  The first time it is called, startPush()
	# 	changes the {main_msg} to 'Pushing'
	#   resets {main_range} to {action_todo}
	# Every time startPush() is called it
	#	sets the {repo} path
	#   zeros out {action_done}
	#   sets {action_range} to $PUSH_RANGE
	#   sets {push_msg} to 'Starting'
	#   clears {action_pct} and {action_rate}

	$this->{action_done} = 0;
	$this->{action_range} = '';
	$this->{action_msg} = '';
	$this->{action_pct} = '';
	$this->{action_rate} = '';

	# After that, for the duration of the push, the app
	# calls handleMessage() which updates the above
	# {members} appropriately.
	#
	# The last push will be left sitting on the screen.


	$this->{ctrl_main_msg} = Wx::StaticText->new($this,-1,'',  	[20,10],  [60,20]);
	$this->{ctrl_repo} 	   = Wx::StaticText->new($this,-1,'',  	[120,10], [190,20]);
	$this->{ctrl_todo} 	   = Wx::StaticText->new($this,-1,'',  	[360,10], [100,20]);
    $this->{ctrl_gauge1}   = Wx::Gauge->new($this,-1,$num_repos,[20,30],  [420,20]);

	$this->{ctrl_msg} 	   = Wx::StaticText->new($this,-1,'',	[20,65],  [60,20]);
	$this->{ctrl_pct} 	   = Wx::StaticText->new($this,-1,'',	[90,65],  [150,20]);
	$this->{ctrl_rate} 	   = Wx::StaticText->new($this,-1,'',	[320,65], [180,20]);
    $this->{ctrl_gauge2}   = Wx::Gauge->new($this,-1,0,			[20,85],  [420,20]);

	$this->{ctrl_msg}->Hide();
	$this->{ctrl_pct}->Hide();
	$this->{ctrl_rate}->Hide();
	$this->{ctrl_gauge2}->Hide();

    $this->{cancel_button} = Wx::Button->new($this,$ID_CANCEL,'Cancel',[380,115],[60,20]);

    EVT_BUTTON($this,$ID_CANCEL,\&onButton);
    EVT_CLOSE($this,\&onClose);

    $this->Show();
	$this->update();

	display($dbg_dlg,0,"ProgressDialog::new() finished");
    return $this;
}

sub addChanges
{
	my ($this,$num_local,$num_remote) = @_;
	$local_changed++ if $num_local;
	$remote_changed++ if $num_remote;
	$local_changes += $num_local;
	$remote_changes += $num_remote;
}


sub aborted()
{
	my ($this) = @_;
	# $this->update();
		# to try to fix guage problem
	return $this->{aborted};
}

sub onClose
{
    my ($this,$event) = @_;
	display($dbg_dlg,0,"ProgressDialog::onClose()");
    # $event->Veto() if !$this->{aborted};
	$event->Skip();
}




sub onButton
{
    my ($this,$event) = @_;
	if (!$this->{window_done})
	{
		warning($dbg_dlg-1,0,"ProgressDialog::ABORTING");
		$this->{aborted} = 1;
		getAppFrame()->abortCommand();
	}
	else
	{
		$this->EndModal($ID_CANCEL);
		$this->Destroy();
	}
	$event->Skip();
}



#----------------------------------------------------
# update()
#----------------------------------------------------


sub update
{
	my ($this) = @_;
	display($dbg_update,0,"progressDialog::update()");

	$this->{ctrl_main_msg}->SetLabel($this->{main_msg});
	$this->{ctrl_repo}->SetLabel($this->{repo});
	$this->{ctrl_todo}->SetLabel("push $this->{action_finished}/$this->{action_todo} repos")
		if $this->{action_todo};

	$this->{ctrl_gauge1}->SetRange($this->{main_range});
	$this->{ctrl_gauge1}->SetValue($this->{main_done});

	if ($this->{action_range})
	{
		$this->{ctrl_msg}->Show();
		$this->{ctrl_pct}->Show();
		$this->{ctrl_rate}->Show();
		$this->{ctrl_gauge2}->Show();

		$this->{ctrl_msg}->SetLabel($this->{action_msg});
		$this->{ctrl_pct}->SetLabel($this->{action_pct});
		$this->{ctrl_rate}->SetLabel($this->{action_rate});

		$this->{ctrl_gauge2}->SetRange($this->{action_range});
		$this->{ctrl_gauge2}->SetValue($this->{action_done});
	}
	else
	{
		$this->{ctrl_msg}->Hide();
		$this->{ctrl_pct}->Hide();
		$this->{ctrl_rate}->Hide();
		$this->{ctrl_gauge2}->Hide();
	}

	# yield occasionally

	Wx::App::GetInstance()->Yield();

	display($dbg_update,0,"progressDialog::update() finished");

	getAppFrame()->abortCommand() if $this->{aborted};
}


#----------------------------------------------------
# UI accessors
#----------------------------------------------------


sub checkRepo
{
	my ($this,$path) = @_;
	display($dbg_dlg+1,0,"checkRepo($path)");
	$this->{repo} = $path;
	$this->{main_done}++;
	$this->update();
}


sub incActionNeeded
{
	my ($this) = @_;
	display($dbg_dlg+1,0,"incActionNeeded(}");
	$this->{action_todo}++;
	$this->update();
}


sub startAction
{
	my ($this,$path) = @_;
	warning($dbg_dlg,0,"startAction($path} todo($this->{action_todo}) main_msg($this->{main_msg})");

	# first push changes the message to Push
	# and activates the 2nd guage and message

	$this->{main_done} = 0
		if $this->{main_msg} eq 'Checking';

	$this->{main_range} = $this->{action_todo};
	$this->{main_msg} = $this->{command_name};
	$this->{repo} = $path;
	$this->{action_finished}++;	# pre-increment
	$this->{main_done}++;		# these are now synchronized

	# set the constant $PUSH_RANGE which will cause
	# the second bar to be displayed

	$this->{action_range} = $PUSH_RANGE;
	$this->{action_done} = 0;
	$this->{action_msg} = 'Starting';
	$this->{action_pct} = '';
	$this->{action_rate} = '';

	$this->update();
}



sub handleMessage
{
	my ($this,$text) = @_;
	my $length = length($text);
	my @lines = split(/(\r)|(\r\n)/,$text);
	my $num_lines = scalar(@lines);

	display($dbg_dlg+1,0,"handleMessage() length($length) lines($num_lines)");
	for my $line (@lines)
	{
		next if !$line;
		$line =~ s/^\s+|\s$//g;
		if ($line =~ s/^(Counting|Compressing|Writing)\s*objects:\s*//)
		{
			my $stage = $1;
			my $pct_msg = $line =~ s/^(.*?)(,|$)// ? $1 : '';
			my $pct = $pct_msg =~ /^(\d+)/ ? $1 : '';
			my $rate = $line || '';

			$rate = '' if $rate =~ /done./;
			$rate =~ s/^,//;
			$rate =~ s/,(.*)$//;
			$pct +=
				$stage eq 'Writing' ? 200 :
				$stage eq 'Compressing' ? 100 : 0;

			display($dbg_dlg+1,1,"$stage($pct)  msg($pct_msg) rate($rate)");

			$this->{action_done} = $pct;
			$this->{action_msg} = $stage;
			$this->{action_pct} = $pct_msg;
			$this->{action_rate} = $rate;
		}
		elsif ($line =~ /^remote:/)
		{
			if ($line =~ /,\s+completed/)
			{
				$this->{action_msg} = "Done";
				$this->finish('done') if
					$this->{main_done} == $this->{main_range};
			}
			else
			{
				$this->{action_msg} = "Finishing";
			}
		}
		$this->update();
	}
}



sub finish
{
	my ($this,$what) = @_;
	$this->{cancel_button}->SetLabel("Close");
	$this->{window_done} = 1;

	my $msg = 'unknown finish message';

	$msg = "Done!" if $what eq 'done';
	$msg = "ABORTED !!!" if $what eq 'aborted';

	if ($what eq 'noActions')
	{
		if ($this->{command_id} == $COMMAND_CHANGES)
		{
			if (!$local_changes && !$remote_changes)
			{
				$msg = 'No changes!';
			}
			else
			{
				$msg = 'Done';
			}
		}
		else
		{
			$msg = "Nothing to do!!";
		}
	}

	my $msg2 = '';
	$msg2 = "local($local_changed:$local_changes) " if $local_changes;
	$msg2 .= "remote($remote_changed:$remote_changes) " if $remote_changes;

	$this->{repo} = $msg2 if $this->{command_id} == $COMMAND_CHANGES;

	$this->{main_msg} = $msg;
	$this->update();

	okDialog($this,"Push aborted by user","Push Aborted")
		if $what eq 'aborted';
}


1;
