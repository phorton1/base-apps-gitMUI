#---------------------------------------------
# apps::gitUI::contextMenu;
#---------------------------------------------
# Add-in class for Context menu for myTextCtrl,
# uses {repo_context} and {window_id} from the
# text control

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
use Pub::Prefs;
use apps::gitUI::utils;
use apps::gitUI::Resources;


my $dbg_menu = 0;		# context menu and commands


my $menu_desc = {
	$ID_CONTEXT_COPY            => ['Copy',				1, 'Copy selected region to clipboard' ],
	$ID_CONTEXT_OPEN_INFO		=> ['Info',				1, 'Open the repository in the Info Window' ],
	$ID_CONTEXT_OPEN_SUBS       => ['Subs',				1, 'Open the repository in the Subs Window' ],
	$ID_CONTEXT_OPEN_GITUI		=> ['GitGUI',			2, 'Open the repository in original GitGUI' ],
	$ID_CONTEXT_BRANCH_HISTORY	=> ['Branch History',	2, 'Show Branch History' ],
	$ID_CONTEXT_ALL_HISTORY		=> ['All History',		2, 'Show All History' ],
	$ID_CONTEXT_OPEN_GITHUB     => ['Github',			2, 'Open https:// url in System Browser' ],
	$ID_CONTEXT_OPEN_EXPLORER	=> ['Explorer',			3, 'Open in Windows Explorer' ],
	$ID_CONTEXT_OPEN_IN_EDITOR	=> ['Editor',			3, 'Open one or more items in System Editor' ],
	$ID_CONTEXT_OPEN_IN_SHELL   => ['Shell',			3, 'Open single item in the Windows Shell' ],
	$ID_CONTEXT_OPEN_IN_NOTEPAD => ['Notepad',			3, 'Open single item in the Windows Notepad' ],
};


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}


sub addContextMenu
{
	my ($this) = @_;
	EVT_MENU_RANGE($this, $ID_CONTEXT_COPY, $ID_CONTEXT_OPEN_IN_NOTEPAD, \&onContextMenu);
}



sub popupContextMenu
{
	my ($this,$context) = @_;
	$context ||= {};
	$this->{popup_context} = $context;

	display_hash($dbg_menu,0,"popupContextMenu()",$context);

	if ($context->{no_menu})
	{
		display($dbg_menu,1,"short return for no_menu");
		return;
	}

	my $is_sub_ref = 0;
	my $is_same_repo = 0;
	my $path = $context->{path} || '';
	my $filename = $context->{filename} || '';

	my $repo = $context->{repo};
	my $repo_path = $repo ? $repo->{path} : '';
	my $repo_id = $repo ? $repo->{id} : '';

	if ($repo)
	{
		my $uuid = $repo->uuid();
		my $path = $repo->{path};
		my $win_uuid = $this->{repo_context} ?
			$this->{repo_context}->uuid() : '';
		$is_same_repo = $uuid eq $win_uuid ? 1 : 0;
		$is_sub_ref = $repo->{parent_repo} || $repo->{used_in} ? 1 : 0;
		$filename = $repo->{path}.$context->{file} if $context->{file};
	}

	my $is_this_info = $is_same_repo &&
		$this->{window_id} == $ID_INFO_WINDOW;
	my $is_this_sub = $is_same_repo &&
		$this->{window_id} == $ID_SUBS_WINDOW;

	display($dbg_menu,1,"path($path) filename($filename) rpath($repo_path) rid($repo_id)");
	display($dbg_menu,1,"is_sub($is_sub_ref) is_same($is_same_repo) ".
		"is_this_info($is_this_info) is_this_sub($is_this_sub)");

	my $menu_group_num = 0;
	my $menu = Wx::Menu->new();
	my $shell_exts = getPref('GIT_SHELL_EXTS');
	my $editor_exts = getPref('GIT_EDITOR_EXTS');
	foreach my $id ($ID_CONTEXT_COPY..$ID_CONTEXT_OPEN_IN_NOTEPAD)
	{
		my $desc = $menu_desc->{$id};
		my ($text,$gnum,$hint) = @$desc;

		next if $id == $ID_CONTEXT_COPY && (!$this->can('canCopy') || !$this->canCopy());
		next if $id == $ID_CONTEXT_OPEN_INFO && (!$repo || $is_this_info);
		next if $id == $ID_CONTEXT_OPEN_SUBS && (!$is_sub_ref || $is_this_sub);
		next if $id == $ID_CONTEXT_OPEN_GITUI && ($filename || !$repo_path);
		next if $id == $ID_CONTEXT_BRANCH_HISTORY && ($filename || !$repo_path);
		next if $id == $ID_CONTEXT_ALL_HISTORY && ($filename || !$repo_path);
		next if $id == $ID_CONTEXT_OPEN_GITHUB && ($filename || (!$repo_id && !$context->{url}));
		next if $id == $ID_CONTEXT_OPEN_EXPLORER && !$path && !$filename && !$repo_path;
		next if $id == $ID_CONTEXT_OPEN_IN_EDITOR && (!$filename || $filename !~ /\.($editor_exts)$/);
		next if $id == $ID_CONTEXT_OPEN_IN_SHELL && (!$filename || $filename !~ /\.($shell_exts)$/);
		next if $id == $ID_CONTEXT_OPEN_IN_NOTEPAD && !$filename;

		$menu->AppendSeparator() if $menu_group_num && $menu_group_num != $gnum;
		$menu->Append($id,$text,$hint,wxITEM_NORMAL);
		$menu_group_num = $gnum;
	}
	$this->PopupMenu($menu,[-1,-1]);
}



sub onContextMenu
{
	my ($this,$event) = @_;
	my $command_id = $event->GetId();
	my $context = $this->{popup_context};

	my $repo = $context->{repo};
	my $filename =
		$context->{filename} ? $context->{filename} :
		$repo && $context->{file} ?
			$repo->{path}.$context->{file} : '';

	display_hash($dbg_menu,0,"onContextMenu($command_id)",$context);

	# copy and program navigation

	if ($command_id == $ID_CONTEXT_COPY)
	{
		$this->doCopy();
	}
	elsif ($command_id == $ID_CONTEXT_OPEN_INFO)
	{
		getAppFrame->createPane($ID_INFO_WINDOW,undef,{repo_uuid=>$repo->uuid()});
	}
	elsif ($command_id == $ID_CONTEXT_OPEN_SUBS)
	{
		getAppFrame->createPane($ID_SUBS_WINDOW,undef,{repo_uuid=>$repo->uuid()});
	}

	# external gitGUI and gitHub

	elsif ($command_id == $ID_CONTEXT_OPEN_GITUI)
	{
		execNoShell('git gui',$repo->{path});
	}
	elsif ($command_id == $ID_CONTEXT_BRANCH_HISTORY)
	{
		execNoShell('gitk',$repo->{path});
	}
	elsif ($command_id == $ID_CONTEXT_ALL_HISTORY)
	{
		execNoShell('gitk --all',$repo->{path});
	}
	elsif ($command_id == $ID_CONTEXT_OPEN_GITHUB)
	{
		my $url = $context->{url};
		if (!$url)
		{
			my $user = getPref("GIT_USER");
			$url = "https://github.com/$user/$repo->{id}";
		}
		my $command = "\"start $url\"";
		system(1,$command);
	}

	# Windows Commands

	elsif ($command_id == $ID_CONTEXT_OPEN_EXPLORER)
	{
		my $path = $context->{path} || $filename || $repo->{path};
		execExplorer($path);
	}
	elsif ($command_id == $ID_CONTEXT_OPEN_IN_EDITOR)
	{
		my $command = getPref('GIT_EDITOR')." \"$filename\"";
		execNoShell($command);
	}
	elsif ($command_id == $ID_CONTEXT_OPEN_IN_SHELL)
	{
		chdir(pathOf($filename));
		system(1,"\"$filename\"");
	}
	elsif ($command_id == $ID_CONTEXT_OPEN_IN_NOTEPAD)
	{
		execNoShell("notepad \"$filename\"");
	}


}	# onContextMenu()

1;