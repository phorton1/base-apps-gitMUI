#---------------------------------------------
# apps::gitUI::repoMenu;
#---------------------------------------------
# Add-in class for Context menu for repos

package apps::gitUI::repoMenu;
use strict;
use warnings;
use threads;
use threads::shared;
use Win32::GUI;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_MENU_RANGE );
use Pub::Utils;
use apps::gitUI::Resources;


my $dbg_menu = 1;		# context menu and commands


my ($ID_OPEN_DETAILS,
	$ID_OPEN_EXPLORER,
	$ID_OPEN_GITUI,
	$ID_BRANCH_HISTORY,
	$ID_ALL_HISTORY ) = (19000..19999);
my $menu_desc = {
	$ID_OPEN_DETAILS	=> ['Details',			'Open the repository in the Repos Window' ],
	$ID_OPEN_EXPLORER	=> ['Explorer',			'Open the repository in the Windows Explorer' ],
	$ID_OPEN_GITUI		=> ['GitGUI',			'Open the repository in original GitGUI' ],
	$ID_BRANCH_HISTORY	=> ['Branch History',	'Show Branch History' ],
	$ID_ALL_HISTORY		=> ['All History',		'Show All History' ],
};


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}


sub addRepoMenu
{
	my ($this,$is_repos_window) = @_;
	$this->{is_repos_window} = $is_repos_window;
	EVT_MENU_RANGE($this, $ID_OPEN_DETAILS, $ID_ALL_HISTORY, \&onRepoMenu);
}


sub popupRepoMenu
{
	my ($this,$repo) = @_;
	display($dbg_menu,1,"popupRepoMenu)($repo->{path})");

	my $menu = Wx::Menu->new();
	foreach my $id ($ID_OPEN_DETAILS..$ID_ALL_HISTORY)
	{
		next if $id == $ID_OPEN_DETAILS && $this->{is_repos_window};
		my $desc = $menu_desc->{$id};
		my ($text,$hint) = @$desc;
		$menu->Append($id,$text,$hint,wxITEM_NORMAL);
		$menu->AppendSeparator() if $id == $ID_OPEN_EXPLORER;
	}

	$this->{popup_repo} = $repo;
	$this->PopupMenu($menu,[-1,-1]); # ,$mouse_pos);
}



sub onRepoMenu
{
	my ($this,$event) = @_;
	my $command_id = $event->GetId();
	my $repo = $this->{popup_repo};
	display($dbg_menu,0,"onRepoMenu($command_id,$repo->{path})");

	if ($command_id == $ID_OPEN_DETAILS)
	{
		getAppFrame->createPane($ID_REPOS_WINDOW,undef,{repo_path=>$repo->{path}});
	}
	elsif ($command_id == $ID_OPEN_EXPLORER)
	{
		execExplorer($repo->{path});
	}
	elsif ($command_id == $ID_OPEN_GITUI)
	{
		execNoShell('git gui',$repo->{path});
	}
	elsif ($command_id == $ID_BRANCH_HISTORY)
	{
		execNoShell('gitk',$repo->{path});
	}
	elsif ($command_id == $ID_ALL_HISTORY)
	{
		execNoShell('gitk --all',$repo->{path});
	}

}	# onRepoMenu()







1;