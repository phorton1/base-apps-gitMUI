#!/usr/bin/perl
#--------------------------------------------------
# apps::gitUI::progressDialog
#--------------------------------------------------
# A somewhat generic progress dialog
#
#    [TITLE]
#
#    [main_msg]      [main_name]          [main_status]
#    [main_gauge   main_done ... main_range          ]
#
#    [sub_msg]       [sub_name]            [sub_status]
#    [sub_gauge   sub_done ... sub_range             ]
#

package apps::gitUI::progressDialog;
use strict;
use warnings;
use threads;
use threads::shared;
use Time::HiRes qw( sleep );
use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON);
use Pub::Utils;
use apps::gitUI::styles;
use apps::gitUI::Resources;
use base qw(Wx::Dialog);


my $dbg_dlg = 0;
my $dbg_update = 1;


my $ID_WINDOW = 18000;
my $ID_CANCEL = 4567;


#------------------------------------------------
# ctor
#------------------------------------------------

sub new
{
    my ($class,
		$parent,
		$title,
		$abort_cb) = @_;

	display($dbg_dlg,0,"progressDialog::new($title) abort_cb="._def($abort_cb));

    my $this = $class->SUPER::new(
		$parent,
		$ID_WINDOW,
		$title,
		[-1,-1],
		[480,180]);

	$this->{parent}   = $parent;
	$this->{abort_cb} = $abort_cb;
	$this->{aborted}  = 0;

	$this->{window_done} = 0;
		# invalidates abort, changes button semantic to 'close'

	$this->{main_msg}    = '';
	$this->{main_name}   = '';
	$this->{main_status} = '';
	$this->{main_done}   = 0;
	$this->{main_range}  = 0;

	$this->{sub_msg}     = '';
	$this->{sub_name}    = '';
	$this->{sub_status}  = '';
	$this->{sub_done}    = 0;
	$this->{sub_range}   = 0;

	$this->{ctrl_main_msg}    = Wx::StaticText->new($this,-1,'',  	[20,10],  [60,20]);
	$this->{ctrl_main_name}   = Wx::StaticText->new($this,-1,'',  	[120,10], [190,20]);
	$this->{ctrl_main_status} = Wx::StaticText->new($this,-1,'',  	[320,10], [120,20], wxALIGN_RIGHT);
    $this->{ctrl_main_gauge}  = Wx::Gauge->new($this,-1,0,			[20,30],  [420,20]);

	$this->{ctrl_sub_msg}     = Wx::StaticText->new($this,-1,'',	[20,65],  [60,20]);
	$this->{ctrl_sub_name}    = Wx::StaticText->new($this,-1,'',	[120,65], [150,20]);
	$this->{ctrl_sub_status}  = Wx::StaticText->new($this,-1,'',	[320,65], [120,20], wxALIGN_RIGHT);
    $this->{ctrl_sub_gauge}   = Wx::Gauge->new($this,-1,0,			[20,85],  [420,20]);

	$this->{ctrl_sub_msg}    ->Hide();
	$this->{ctrl_sub_name}   ->Hide();
	$this->{ctrl_sub_status} ->Hide();
	$this->{ctrl_sub_gauge}  ->Hide();

    $this->{cancel_button} = Wx::Button->new($this,$ID_CANCEL,'Cancel',[380,115],[60,20]);

    EVT_BUTTON($this,$ID_CANCEL,\&onButton);

    $this->Show();
	$this->update();

	display($dbg_dlg,0,"ProgressDialog::new() finished");
    return $this;
}


sub setParams
{
	my ($this,$params) = @_;
	mergeHash($this,$params);
	$this->update();
}


sub aborted()
{
	my ($this) = @_;
	return $this->{aborted};
}


sub setDone
{
	my ($this,$button_title) = @_;
	$this->{window_done} = 1;
	$button_title ||= 'Close';
	$this->{cancel_button}->SetLabel($button_title);
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
	if ($this->{abort_cb} && !$this->{window_done})
	{
		warning($dbg_dlg-1,0,"ProgressDialog::ABORTING");
		$this->{aborted} = 1;
		&{$this->{abort_cb}}($this->{parent});
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

	# special handling for Error/Abort

	$this->{main_name} = substr($this->{main_name},0,50)
		if length($this->{main_name}) > 50;
	if ($this->{main_msg} =~ /^(error|abort)/i)
	{
		$this->{ctrl_main_msg}	-> SetForegroundColour($color_red);
	    $this->{ctrl_main_name} -> SetForegroundColour($color_red);
	}

	$this->{ctrl_main_msg}	 ->SetLabel($this->{main_msg});
	$this->{ctrl_main_name}	 ->SetLabel($this->{main_name});
	$this->{ctrl_main_status}->SetLabel($this->{main_status});
	$this->{ctrl_main_gauge} ->SetRange($this->{main_range});
	$this->{ctrl_main_gauge} ->SetValue($this->{main_done});

	if ($this->{sub_range})
	{
		$this->{ctrl_sub_msg}	 ->SetLabel($this->{sub_msg});
		$this->{ctrl_sub_name}	 ->SetLabel($this->{sub_name});
		$this->{ctrl_sub_status} ->SetLabel($this->{sub_status});
		$this->{ctrl_sub_gauge}  ->SetRange($this->{sub_range});
		$this->{ctrl_sub_gauge}  ->SetValue($this->{sub_done});
		$this->{ctrl_sub_msg}	  ->Show();
		$this->{ctrl_sub_name}	  ->Show();
		$this->{ctrl_sub_status}  ->Show();
		$this->{ctrl_sub_gauge}   ->Show();
	}
	else
	{
		$this->{ctrl_sub_msg}	  ->Hide();
		$this->{ctrl_sub_name}	  ->Hide();
		$this->{ctrl_sub_status}  ->Hide();
		$this->{ctrl_sub_gauge}   ->Hide();
	}

	# yield occasionally

	Wx::App::GetInstance()->Yield();

	display($dbg_update,0,"progressDialog::update() finished");
}




1;
