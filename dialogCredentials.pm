#!/usr/bin/perl

package apps::gitMUI::dialogCredentials;
use strict;
use warnings;
use threads;
use warnings;
use Wx qw(:everything);
use Wx::Event qw(EVT_UPDATE_UI EVT_TEXT_ENTER);
use Pub::Utils;
use Pub::Prefs;
use base qw(Wx::Dialog);


my $PS_WIDTH = 400;
my $PS_HEIGHT = 130;


sub getCredentials
{
	my ($class,$parent) = @_;
	$parent ||= undef;

	my $dlg = $class->new($parent);
	my $rslt = $dlg->ShowModal();

	if ($rslt == wxID_OK)
	{
		my $user = $dlg->{user}->GetValue();
		my $token = $dlg->{token}->GetValue();
		setPref('GIT_USER',$user);
		setPref('GIT_API_TOKEN',$token);
		writePrefs();
	}
	$dlg->Destroy();
	return ($rslt == wxID_OK) ? 1 : 0;
}


sub new
{
    my ($class,$parent) = @_;

	my $position = [-1,-1];
	if (!$parent)
	{
		my $size = Wx::GetDisplaySize();	# Wx::GetScreenSize();
		$position = [
			($size->x() - $PS_WIDTH) / 2,
			($size->y() - $PS_HEIGHT) / 2 ];
	}

	my $this = $class->SUPER::new(
        $parent,
        -1,
		"gitMUI requires gitHub Credentials",
        $position,
        [$PS_WIDTH,$PS_HEIGHT],
        wxDEFAULT_DIALOG_STYLE); #  | wxRESIZE_BORDER);

	my $user = getPref('GIT_USER') || '';
	my $token = getPref('GIT_API_TOKEN') || '';

    Wx::StaticText->new($this,-1,'User:',[10,12]);
    $this->{user} = Wx::TextCtrl->new($this,-1,$user,[70,10],[85,20],wxTE_PROCESS_ENTER);

    Wx::StaticText->new($this,-1,'API Token:',[10,32]);
    $this->{token} = Wx::TextCtrl->new($this,-1,$token,[70,30],[300,20],wxTE_PROCESS_ENTER);
		# |wxTE_PASSWORD);

    Wx::Button->new($this,wxID_CANCEL,'Cancel',[50,70],[60,20]);
    Wx::Button->new($this,wxID_OK,'OK',[290,70],[60,20]);

	EVT_TEXT_ENTER($this,-1,\&onEnter);
	EVT_UPDATE_UI($this,wxID_OK,\&onUpdateButtonOK);
	return $this;
}


sub onUpdateButtonOK
{
    my ($this,$event) = @_;
    my $enable =
		$this->{user}->GetValue() &&
		$this->{token}->GetValue();
    $event->Enable($enable);
}


sub onEnter
{
	my ($this,$event)= @_;
    $this->EndModal(wxID_OK) if
		$this->{user}->GetValue() &&
		$this->{token}->GetValue();
}


1;
