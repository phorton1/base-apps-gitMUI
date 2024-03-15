#-------------------------------------------------------------------------
# Window to show repos by path with section breaks
#-------------------------------------------------------------------------

package apps::gitUI::submoduleWindow;
use strict;
use warnings;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_LEFT_DOWN
	EVT_RIGHT_DOWN
	EVT_ENTER_WINDOW
	EVT_LEAVE_WINDOW);
use Pub::Utils;
use Pub::WX::Window;
use apps::gitUI::repos;
use apps::gitUI::utils;
use apps::gitUI::repoMenu;
use apps::gitUI::Resources;
use apps::gitUI::myHyperlink;
use base qw(Wx::ScrolledWindow Pub::WX::Window apps::gitUI::repoMenu);

my $dbg_win = 0;
my $dbg_pop = 1;
my $dbg_notify = 1;

my $GROUP_BASE_ID = 100000;
my $GROUP_ID_SPACE = 1000;


my $TOP_MARGIN = 10;
my $LINE_SPACING = 20;

my $LEFT_MARGIN = 10;
my $INDENT_MARGIN  = 50;



sub new
	# single instance scrolling top level window
	# To scroll a simple window with controls you must
	# (a) derive from Wx::ScrolledWindow
	# (b) call SetScrollRate
	# (c) call SetVirtualSize
{
	my ($class,$frame,$id,$book,$data) = @_;
	my $name = 'Subs';

	display($dbg_win,0,"submoduleWindow::new($frame,$id,"._def($book).","._def($data).")");
	my $this = $class->SUPER::new($book,$id);
	$this->MyWindow($frame,$book,$id,$name,$data);

	$this->SetBackgroundColour($color_white);
	$this->SetScrollRate(0,$LINE_SPACING);
	$this->populate();

	$this->addRepoMenu();

	return $this;
}





sub repoFromIdNum
{
	my ($this,$id_num) = @_;
	$id_num -= $GROUP_BASE_ID;

	my $group_num = int($id_num / $GROUP_ID_SPACE);
	my $sub_num = int($id_num % $GROUP_ID_SPACE);

	my $group = $this->{groups}->[$group_num];
	my $repo = $sub_num ?
		$group->{subs}->[$sub_num-1] :
		$group->{master};
	return $repo;

}


sub onEnterLink
{
	my ($ctrl,$event) = @_;
	my $event_id = $event->GetId();
	my $this = $ctrl->GetParent();
	my $repo = $this->repoFromIdNum($event_id);
	my $path = $repo->{path};
	my $show = "$repo->{path} = $repo->{id}";

	$this->{frame}->SetStatusText($show);
	my $font = Wx::Font->new($this->GetFont());
	$font->SetWeight (wxFONTWEIGHT_BOLD );
	$ctrl->SetFont($font);
	$ctrl->Refresh();
}


sub onLeaveLink
{
	my ($ctrl,$event) = @_;
	my $this = $ctrl->GetParent();
	$this->{frame}->SetStatusText('');
	$ctrl->SetFont($this->GetFont());
	$ctrl->Refresh();
}


sub onLeftDown
{
	my ($ctrl,$event) = @_;
	my $event_id = $event->GetId();
	my $this = $ctrl->GetParent();
	my $repo = $this->repoFromIdNum($event_id);
	my $uuid = $repo->uuid();
	display($dbg_win,0,"onLeftDown($event_id,$uuid)");
	$this->{frame}->createPane($ID_INFO_WINDOW,undef,{repo_uuid=>$uuid});
}


sub onRightDown
{
	my ($ctrl,$event) = @_;
	my $event_id = $event->GetId();
	my $this = $ctrl->GetParent();
	my $repo = $this->repoFromIdNum($event_id);
	display($dbg_win,0,"onRightDown($event_id,$repo->{path}");
	$this->popupRepoMenu($repo);

}




#----------------------------------------
# populate
#----------------------------------------

sub populate
{
	my ($this) = @_;

	display($dbg_pop,0,"populate()");
	my $groups = $this->{groups} = [];
	$this->DestroyChildren();

	my $group_num = 0;
	my $ypos = $TOP_MARGIN;
	my $repo_list = getRepoList();
	for my $repo (@$repo_list)
	{
		my $used_in = $repo->{used_in};
		next if !$used_in;

		display($dbg_pop,1,"master($repo->{path})");

		my $base_id = $GROUP_BASE_ID + ($group_num * $GROUP_ID_SPACE);
		my $color = $color_black;
		my $title = $repo->pathWithinSection();

		my $ctrl = apps::gitUI::myHyperlink->new(
			$this,
			$base_id,
			"GROUP $title",
			[$LEFT_MARGIN,$ypos],
			[-1,-1],
			$color);
		$ypos += $LINE_SPACING;

		EVT_LEFT_DOWN($ctrl, \&onLeftDown);
		EVT_RIGHT_DOWN($ctrl, \&onRightDown);
		EVT_ENTER_WINDOW($ctrl, \&onEnterLink);
		EVT_LEAVE_WINDOW($ctrl, \&onLeaveLink);

		my $subs = [];
		my $ctrls = [];

		my $group = {
			name => $repo->{path},
			master => $repo,
			subs => $subs,
			ctrls => $ctrls,
			ANY_AHEAD => 0,
			ANY_BEHIND => 0,
			ANY_REBASE => 0,
			changed => 0, };

		push @$groups,$group;
		push @$ctrls,$ctrl;

		my $ctrl_num = 1;
		for my $path ($repo->{path}, @$used_in)
		{
			display($dbg_pop,2,"sub($path)");
			my $sub = getRepoByPath($path);
			return !error("Could not find repo($repo->{path}) used_in($path)")
				if !$sub;
			push @$subs,$sub;

			my $id_num = $base_id + $ctrl_num;
			my $color = linkDisplayColor($sub);
			my $title = $sub->pathWithinSection();

			my $ctrl = apps::gitUI::myHyperlink->new(
				$this,
				$id_num,
				$title,
				[$INDENT_MARGIN,$ypos],
				[-1,-1],
				$color);
			push @$ctrls,$ctrl;
			$ypos += $LINE_SPACING;

			EVT_LEFT_DOWN($ctrl, \&onLeftDown);
			EVT_RIGHT_DOWN($ctrl, \&onRightDown);
			EVT_ENTER_WINDOW($ctrl, \&onEnterLink);
			EVT_LEAVE_WINDOW($ctrl, \&onLeaveLink);


			$group->{ANY_AHEAD}++ if $sub->{AHEAD};
			$group->{ANY_BEHIND}++ if $sub->{BEHIND};
			$group->{ANY_REBASE}++ if $sub->{BEHIND};
			my $changes =
				scalar(keys %{$sub->{staged_changes}}) +
				scalar(keys %{$sub->{unstaged_changes}});
			$group->{changed}++ if $changes;
			$ctrl_num++;

		}	# for each sub

		$ypos += $LINE_SPACING;
		$group_num++;

	}	# for each master module

	$this->SetVirtualSize([5000,$ypos]);


}	# populate()



sub notifyRepoChanged
{
	my ($this,$repo) = @_;
	display($dbg_notify,0,"notifyRepoChanged($repo->{path})");

	for my $group (@{$this->{groups}})
	{
		updateColor($group->{ctrls}->[0],$group->{master})
			if $repo->{path} eq $group->{master}->{path};

		my $ctrl_num = 1;
		my $subs = $group->{subs};
		for my $sub (@$subs)
		{
			updateColor($group->{ctrls}->[$ctrl_num],$sub)
				if $repo->{path} eq $sub->{path};
		}
	}
}



sub updateColor
{
	my ($ctrl,$repo) = @_;
	my $color = linkDisplayColor($repo);
	$ctrl->SetForegroundColour($color);
	$ctrl->Refresh();
}




1;
