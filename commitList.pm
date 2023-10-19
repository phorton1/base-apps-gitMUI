#!/usr/bin/perl
#-------------------------------------------
# apps::gitUI::commitList
#-------------------------------------------
# The two 'staged' and 'unstaged' areas
# in the left hand part of the commitWindow

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

    my $list_ctrl = $this->{list_ctrl} =
		Wx::ListCtrl->new($this,-1,[0,$PANE_TOP],[-1,-1],wxLC_REPORT | wxLC_NO_HEADER);
	$list_ctrl->InsertColumn(0,'',wxLIST_FORMAT_LEFT,100);

	display($dbg_life,1,"commitList::new after ctrls");

	$this->setContent();
	$this->populate();
	$this->doLayout();

	EVT_SIZE($this, \&onSize);

	return $this;

}




sub onSize
{
    my ($this,$event) = @_;
	$this->doLayout();
    $event->Skip();
}


sub doLayout
{
    my ($this) = @_;
	my $sz = $this->GetSize();
    my $width = $sz->GetWidth();
    my $height = $sz->GetHeight();
    $this->{list_ctrl}->SetSize([$width,$height-$PANE_TOP]);
	$this->{list_ctrl}->SetColumnWidth(0,$width);
}



sub setContent
{
    my ($this) = @_;
	my $key = $this->{is_staged} ? 'staged_changes' : 'unstaged_changes';
	display($dbg_pop,0,"setContent($key)");

	# repos are indicated with a terminating slash

	my $content = $this->{content} = [];
	my $repo_list = getRepoList();
	for my $repo (@$repo_list)
	{
		my $changes = $repo->{$key};
		if (keys %$changes)
		{
			display($dbg_pop,1,"repo($repo->{path})");
			push @$content,$repo->{path}."/";
			for my $fn (keys %$changes)
			{
				display($dbg_pop,2,"file($fn)");
				push @$content,$fn;
			}
		}
	}

}   # setContent




sub addListRow
{
    my ($this,$row,$entry) = @_;
	display($dbg_pop,0,"addListRow($row,$entry)");

    my $ctrl = $this->{list_ctrl};
    my $is_repo = $entry =~ /\/$/;
	my $color = $is_repo ? $color_blue : $color_black;
	my $font = $is_repo ? $font_bold : $font_normal;
	my $use_entry = $is_repo ? $entry : "   $entry";

	$ctrl->InsertStringItem($row,$use_entry);
	$ctrl->SetItemData($row,$row);

    my $item = $ctrl->GetItem($row);
    $item->SetFont($font);
    $item->SetTextColour($color);
	$ctrl->SetItem($item);

}   # addListRow()





sub populate
{
	my ($this) = @_;
	display($dbg_pop,0,"populate($this->{is_staged},$this->{content})");

	my $list_ctrl = $this->{list_ctrl};
	$list_ctrl->DeleteAllItems();

	my $content = $this->{content};
	my $num_content = @$content;
	display($dbg_pop,1,"content has $num_content items");

	for my $row (0..$num_content-1)
	{
		$this->addListRow($row,$content->[$row]);
	}

    $this->Refresh();
}




1;