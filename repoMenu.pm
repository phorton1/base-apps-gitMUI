#---------------------------------------------
# apps::gitMUI::repoMenu;
#---------------------------------------------
# Add-in class for Context menu for repos

package apps::gitMUI::repoMenu;
use strict;
use warnings;
use threads;
use threads::shared;
use Win32::GUI;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_MENU_RANGE );
use Pub::Utils;
use Pub::Prefs;
use apps::gitMUI::Resources;


my $dbg_menu = 1;		# context menu and commands



my $menu_desc = {
	$ID_REPO_OPEN_INFO		=> ['Info',				'Open the repository in the Info Window' ],
	$ID_REPO_OPEN_SUBS		=> ['Subs',				'Open the repository in the Subs Window' ],
	$ID_REPO_OPEN_EXPLORER	=> ['Explorer',			'Open the repository in the Windows Explorer' ],
	$ID_REPO_OPEN_GITUI		=> ['GitGUI',			'Open the repository in original GitGUI' ],
	$ID_REPO_BRANCH_HISTORY	=> ['Branch History',	'Show Branch History' ],
	$ID_REPO_ALL_HISTORY	=> ['All History',		'Show All History' ],
	$ID_REPO_OPEN_GITHUB    => ['Github',			'Open the repository in Github' ],
};


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}


sub addRepoMenu
{
	my ($this,$window_id) = @_;
	$this->{window_id} = $window_id;
	EVT_MENU_RANGE($this, $ID_REPO_OPEN_INFO, $ID_REPO_OPEN_GITHUB, \&onRepoMenu);
}


sub popupRepoMenu
{
	my ($this,$repo) = @_;
	display($dbg_menu,1,"popupRepoMenu($this->{window_id},$repo->{path})");

	my $menu = Wx::Menu->new();
	foreach my $id ($ID_REPO_OPEN_INFO..$ID_REPO_OPEN_GITHUB)
	{
		next if $id == $ID_REPO_OPEN_INFO &&
			$this->{window_id} == $ID_INFO_WINDOW;
		next if $id == $ID_REPO_OPEN_SUBS && (
			$this->{window_id} == $ID_SUBS_WINDOW ||
			(!$repo->{parent_repo} && !$repo->{used_in}));
		next if $id == $ID_REPO_OPEN_EXPLORER && !$repo->{path};
		next if $id == $ID_REPO_OPEN_GITUI && !$repo->{path};
		next if $id == $ID_REPO_BRANCH_HISTORY && !$repo->{path};
		next if $id == $ID_REPO_ALL_HISTORY && !$repo->{path};
		next if $id == $ID_REPO_OPEN_GITHUB && !$repo->{id};

		my $desc = $menu_desc->{$id};
		my ($text,$hint) = @$desc;
		$menu->Append($id,$text,$hint,wxITEM_NORMAL);
		$menu->AppendSeparator() if $id == $ID_REPO_OPEN_EXPLORER;
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

	if ($command_id == $ID_REPO_OPEN_INFO)
	{
		getAppFrame->createPane($ID_INFO_WINDOW,undef,{repo_path=>$repo->{path}});
	}
	elsif ($command_id == $ID_REPO_OPEN_SUBS)
	{
		getAppFrame->createPane($ID_SUBS_WINDOW,undef,{repo_path=>$repo->{path}});
	}
	elsif ($command_id == $ID_REPO_OPEN_EXPLORER)
	{
		execExplorer($repo->{path});
	}
	elsif ($command_id == $ID_REPO_OPEN_GITUI)
	{
		execNoShell('git gui',$repo->{path});
	}
	elsif ($command_id == $ID_REPO_BRANCH_HISTORY)
	{
		execNoShell('gitk',$repo->{path});
	}
	elsif ($command_id == $ID_REPO_ALL_HISTORY)
	{
		execNoShell('gitk --all',$repo->{path});
	}
	elsif ($command_id == $ID_REPO_OPEN_GITHUB)
	{
		my $user = getPref("GIT_USER");
		my $path = "https://github.com/$user/$repo->{id}";
		my $command = "\"start $path\"";
		system(1,$command);
	}

}	# onRepoMenu()







1;