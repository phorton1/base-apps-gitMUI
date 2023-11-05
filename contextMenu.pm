#---------------------------------------------
# apps::gitUI::contextMenu;
#---------------------------------------------
# Add-in class for Context menu for files

package apps::gitUI::contextMenu;
use strict;
use warnings;
use threads;
use threads::shared;
use Win32::GUI;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_MENU_RANGE );
use Pub::Utils;
use apps::gitUI::utils;
use apps::gitUI::Resources;


my $dbg_menu = 0;		# context menu and commands


my ($ID_COPY,				# any
	$ID_OPEN_DETAILS,		# repo
	$ID_OPEN_GITUI,			# repo
	$ID_BRANCH_HISTORY,		# repo
	$ID_ALL_HISTORY,		# repo
	$ID_OPEN_EXPLORER,		# repo, path
	$ID_OPEN_IN_KOMODO,		# path
	$ID_OPEN_IN_SHELL,		# path
	$ID_OPEN_IN_NOTEPAD  ) = (19000..19999);

my $menu_desc = {
	$ID_COPY            => ['Copy',				'Copy selected region to clipboard' ],
	$ID_OPEN_DETAILS	=> ['Details',			'Open the repository in the Repos Window' ],
	$ID_OPEN_GITUI		=> ['GitGUI',			'Open the repository in original GitGUI' ],
	$ID_BRANCH_HISTORY	=> ['Branch History',	'Show Branch History' ],
	$ID_ALL_HISTORY		=> ['All History',		'Show All History' ],
	$ID_OPEN_EXPLORER	=> ['Explorer',			'Open in Windows Explorer' ],
	$ID_OPEN_IN_KOMODO	=> ['Komodo',			'Open one or more items in Komodo Editor' ],
	$ID_OPEN_IN_SHELL   => ['Shell',			'Open single item in the Windows Shell' ],
	$ID_OPEN_IN_NOTEPAD => ['Notepad',			'Open single item in the Windows Notepad' ],
};


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}


sub addContextMenu
{
	my ($this) = @_;
	EVT_MENU_RANGE($this, $ID_COPY, $ID_OPEN_IN_NOTEPAD, \&onContextMenu);
}


sub popupContextMenu
{
	my ($this,$repo,$path) = @_;
	$repo ||= '';
	$path ||= '';

	display($dbg_menu,1,"popupContextMenu)($repo,$path)");
	$this->{popup_repo} = $repo;
	$this->{popup_path} = $path;

	my $repo_context = $this->{repo_context};
	my $is_this_repo = $repo_context && $repo &&
		$repo->{id} eq $repo_context->{id};

	my $menu = Wx::Menu->new();
	foreach my $id ($ID_COPY..$ID_OPEN_IN_NOTEPAD)
	{
		next if $id == $ID_COPY && (!$this->can('canCopy') || !$this->canCopy());
		next if $id == $ID_OPEN_DETAILS && $is_this_repo;
		next if $id > $ID_COPY && $id <= $ID_ALL_HISTORY && !$repo;
		next if $id >= $ID_OPEN_IN_KOMODO && !$path;
		next if $id == $ID_OPEN_EXPLORER && !$repo && !$path;

		my $desc = $menu_desc->{$id};
		my ($text,$hint) = @$desc;
		$menu->Append($id,$text,$hint,wxITEM_NORMAL);
		$menu->AppendSeparator()
			if $id == $ID_COPY && ($repo || $path);
		$menu->AppendSeparator()
			if $id == $ID_ALL_HISTORY && $repo && $path;
	}
	$this->PopupMenu($menu,[-1,-1]);
}



sub onContextMenu
{
	my ($this,$event) = @_;
	my $command_id = $event->GetId();
	my $path = $this->{popup_path};
	my $repo = $this->{popup_repo};
	my $id = $repo ? $repo->{id} : '';

	display($dbg_menu,0,"onContextMenu($command_id,$id,$path)");

	if ($command_id == $ID_COPY)
	{
		$this->doCopy() if $this->can('doCopy');
	}
	if ($command_id == $ID_OPEN_DETAILS)
	{
		getAppFrame->createPane($ID_REPOS_WINDOW,undef,{repo_id=>$repo->{id}});
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

	elsif ($command_id == $ID_OPEN_EXPLORER)
	{
		$path ||= $repo->{path};
		execExplorer($path);
	}

	elsif ($command_id == $ID_OPEN_IN_SHELL)
	{
		chdir $path;
		system(1,"\"$path\"");
	}
	elsif ($command_id == $ID_OPEN_IN_NOTEPAD)
	{
		execNoShell("notepad \"$path\"");
	}
	elsif ($command_id == $ID_OPEN_IN_KOMODO)
	{
		my $command = $komodo_exe." \"$path\"";
		execNoShell($command);
	}
}	# onContextMenu()

1;