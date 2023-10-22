#!/usr/bin/perl
#-------------------------------------------
# apps::gitUI::commitList
#-------------------------------------------
# The two 'staged' and 'unstaged' areas
# in the left hand part of the commitWindow.
#
# Presumably a wxListCtrl is faster than anything I could write.


package apps::gitUI::commitList;
use strict;
use warnings;
use threads;
use threads::shared;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_SIZE );
use apps::gitUI::styles;
use apps::gitUI::repo;
use apps::gitUI::repos;
use apps::gitUI::listCtrl;
use Pub::Utils;
use base qw(Wx::Window);

my $dbg_life = 0;
my $dbg_pop = 0;


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}


my $PANE_TOP = 25;


sub new
{
    my ($class,$parent,$is_staged,$splitter) = @_;
	display($dbg_life,0,"new commitList($is_staged)");

    my $this = $class->SUPER::new($splitter);

    $this->{parent} = $parent;
	$this->{is_staged} = $is_staged;
	$this->{content} = [];

	$this->SetBackgroundColour(
		$is_staged?$color_light_green:$color_light_orange);
	Wx::StaticText->new($this,-1, $is_staged ?
		'Staged Changed (Will Commit)' : 'Unstaged Changes',
		[5,5]);

    my $name = $is_staged ? 'staged' : 'unstaged';
	$this->{list_ctrl} = apps::gitUI::listCtrl->new($this,$name,$PANE_TOP);

	$this->populate();

	EVT_SIZE($this, \&onSize);

	return $this;

}




sub onSize
{
    my ($this,$event) = @_;
	my $sz = $this->GetSize();
    my $width = $sz->GetWidth();
    my $height = $sz->GetHeight();
    $this->{list_ctrl}->SetSize([$width,$height-$PANE_TOP]);
    $event->Skip();
}




sub populate
{
	my ($this) = @_;
	my $key = $this->{is_staged} ? 'staged_changes' : 'unstaged_changes';
	display($dbg_pop,0,"populate($key)");

	my $list_ctrl = $this->{list_ctrl};
	$list_ctrl->startUpdate();

	# repos are indicated with a terminating slash

	my $row = 0;
	my $repo_list = getRepoList();
	for my $repo (@$repo_list)
	{
		my $changes = $repo->{$key};
		$list_ctrl->updateRepo($repo,$changes) if keys %$changes;
	}

	$list_ctrl->endUpdate();
    $this->Refresh();
}




1;