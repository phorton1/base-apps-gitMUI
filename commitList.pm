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
	EVT_SIZE
	EVT_BUTTON );
use apps::gitUI::utils;
use apps::gitUI::repo;
use apps::gitUI::repos;
use apps::gitUI::commitListCtrl;
use Pub::Utils;
use base qw(Wx::Window);

my $dbg_life = 0;
my $dbg_pop = 1;


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}


my $PANE_TOP = 25;
my $ID_DO_ALL = 1000;



sub new
{
    my ($class,$parent,$is_staged,$splitter,$data) = @_;
	display($dbg_life,0,"new commitList($is_staged) data="._def($data));
	$data ||= {};

    my $this = $class->SUPER::new($splitter);

    $this->{parent} = $parent;
	$this->{frame} = $parent->{frame};
	$this->{is_staged} = $is_staged;

	$this->SetBackgroundColour(
		$is_staged? $color_git_staged : $color_git_unstaged);

	Wx::Button->new($this,$ID_DO_ALL,$is_staged ?
		"Unstage All" : "Stage All", [5,2],[75,20]);
	Wx::StaticText->new($this,-1, $is_staged ?
		'Staged Changed (Will Commit)' : 'Unstaged Changes',
		[86,5]);

	$this->{list_ctrl} = apps::gitUI::commitListCtrl->new($this,$is_staged,$PANE_TOP,$data->{list_ctrl});

	$this->populate();

	EVT_SIZE($this, \&onSize);
	EVT_BUTTON($this,-1,\&onButton);

	return $this;

}


sub onButton
{
	my ($this,$event) = @_;
	my $id = $event->GetId();
	display($dbg_life,0,"ACTION_ON_ALL");
	$this->{list_ctrl}->doAction();
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
	$this->{list_ctrl}->updateRepos();
    $this->Refresh();
}



sub getDataForIniFile
{
	my ($this) = @_;
	my $data = {};

	$data->{list_ctrl} = $this->{list_ctrl}->getDataForIniFile();

	return $data;
}


1;