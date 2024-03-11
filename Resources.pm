#-------------------------------------------------------------
# gitUI Resources
#-------------------------------------------------------------
# All appBase applications may provide resources that contain the
# app_title, main_menu, command_data, notebook_data, and so on.
# Derived classes should merge their values into the base
# class $resources member.

package apps::gitUI::Resources;
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::WX::Resources;
use Pub::Utils;

BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = ( qw(

		$ID_PATH_WINDOW
		$ID_INFO_WINDOW
		$ID_COMMIT_WINDOW
		$ID_SUBS_WINDOW
		$ID_STATUS_WINDOW

		$ID_COMMAND_RESCAN
		$ID_COMMAND_REFRESH_STATUS
		$ID_COMMAND_REBUILD_CACHE

		$ID_COMMAND_PUSH_ALL
		$ID_COMMAND_PULL_ALL
		$ID_COMMAND_PUSH_SELECTED
		$ID_COMMAND_PULL_SELECTED
		$ID_COMMAND_COMMIT_SELECTED_PARENTS

		$ID_PROGRESS_DIALOG
		$ID_PROGRESS_CANCEL
		$ID_DIALOG_DISPLAY

		$ID_REPO_OPEN_INFO
		$ID_REPO_OPEN_SUBS
		$ID_REPO_OPEN_EXPLORER
		$ID_REPO_OPEN_GITUI
		$ID_REPO_BRANCH_HISTORY
		$ID_REPO_ALL_HISTORY
		$ID_REPO_OPEN_GITHUB

		$ID_CONTEXT_COPY
	    $ID_CONTEXT_OPEN_INFO
	    $ID_CONTEXT_OPEN_SUBS
	    $ID_CONTEXT_OPEN_GITUI
	    $ID_CONTEXT_BRANCH_HISTORY
	    $ID_CONTEXT_ALL_HISTORY
	    $ID_CONTEXT_OPEN_EXPLORER
		$ID_CONTEXT_OPEN_GITHUB
	    $ID_CONTEXT_OPEN_IN_KOMODO
	    $ID_CONTEXT_OPEN_IN_SHELL
		$ID_CONTEXT_OPEN_IN_NOTEPAD

		$ID_COMMIT_SPLITTER_VERT
		$ID_COMMIT_SPLITTER_LEFT
		$ID_COMMIT_SPLITTER_RIGHT
		$ID_COMMIT_CTRL_REVERT_CHANGES
		$ID_COMMIT_CTRL_OPEN_IN_KOMODO
		$ID_COMMIT_CTRL_SHOW_EXPLORER
		$ID_COMMIT_CTRL_OPEN_IN_SHELL
		$ID_COMMIT_CTRL_OPEN_IN_NOTEPAD
		$ID_COMMIT_LIST_STAGE_ALL
		$ID_COMMAND_COMMIT

		$ID_INFO_SPLITTER_VERT
		$INFO_RIGHT_COMMAND_PUSH
		$INFO_RIGHT_COMMAND_PULL
		$INFO_RIGHT_COMMAND_COMMIT_PARENT
		$INFO_RIGHT_COMMAND_SINGLE_PUSH
		$INFO_RIGHT_COMMAND_SINGLE_PULL
		$INFO_RIGHT_COMMAND_SINGLE_COMMIT_PARENT

	),

	@Pub::WX::Resources::EXPORT );
}


# ALL WINDOW AND COMMAND IDS ARE PRESENTED HERE FOR SANITY
# APPS START AT 200


our (

	# Windows handled by appFrame::createPane

	$ID_PATH_WINDOW,
	$ID_COMMIT_WINDOW,
	$ID_INFO_WINDOW,
	$ID_SUBS_WINDOW,
	$ID_STATUS_WINDOW,	# Not implemented yet

	# UI Commands handled by gitUI.pm

	$ID_COMMAND_RESCAN,
	$ID_COMMAND_REFRESH_STATUS,
	$ID_COMMAND_REBUILD_CACHE,

	$ID_COMMAND_PUSH_ALL,
	$ID_COMMAND_PULL_ALL,

	$ID_COMMAND_PUSH_SELECTED,
	$ID_COMMAND_PULL_SELECTED,
	$ID_COMMAND_COMMIT_SELECTED_PARENTS,
		# These have no direct UI.
		# They are implemented via local command ids
		# in various windows

	# Dialogs

	$ID_PROGRESS_DIALOG,
	$ID_PROGRESS_CANCEL,
	$ID_DIALOG_DISPLAY,

	# repoContext.pm

	$ID_REPO_OPEN_INFO,
	$ID_REPO_OPEN_SUBS,
	$ID_REPO_OPEN_EXPLORER,
	$ID_REPO_OPEN_GITUI,
	$ID_REPO_BRANCH_HISTORY,
	$ID_REPO_ALL_HISTORY,
	$ID_REPO_OPEN_GITHUB,

	# contextMenu.pm

	$ID_CONTEXT_COPY,				# any
	$ID_CONTEXT_OPEN_INFO,			# repo
	$ID_CONTEXT_OPEN_SUBS,			# repo
	$ID_CONTEXT_OPEN_GITUI,			# repo
	$ID_CONTEXT_BRANCH_HISTORY,		# repo
	$ID_CONTEXT_ALL_HISTORY,		# repo
	$ID_CONTEXT_OPEN_EXPLORER,		# repo, path
	$ID_CONTEXT_OPEN_GITHUB, 		# repo, path https://
	$ID_CONTEXT_OPEN_IN_KOMODO,		# path
	$ID_CONTEXT_OPEN_IN_SHELL,		# path
	$ID_CONTEXT_OPEN_IN_NOTEPAD,	# path

	# commands and IDs within windows

	$ID_COMMIT_SPLITTER_VERT,
	$ID_COMMIT_SPLITTER_LEFT,
	$ID_COMMIT_SPLITTER_RIGHT,
	$ID_COMMIT_CTRL_REVERT_CHANGES,
	$ID_COMMIT_CTRL_OPEN_IN_KOMODO,
	$ID_COMMIT_CTRL_SHOW_EXPLORER,
	$ID_COMMIT_CTRL_OPEN_IN_SHELL,
	$ID_COMMIT_CTRL_OPEN_IN_NOTEPAD,
	$ID_COMMIT_LIST_STAGE_ALL,
	$ID_COMMAND_COMMIT,

	$ID_INFO_SPLITTER_VERT,
	$INFO_RIGHT_COMMAND_PUSH,
	$INFO_RIGHT_COMMAND_PULL,
	$INFO_RIGHT_COMMAND_COMMIT_PARENT,
	$INFO_RIGHT_COMMAND_SINGLE_PUSH,
	$INFO_RIGHT_COMMAND_SINGLE_PULL,
	$INFO_RIGHT_COMMAND_SINGLE_COMMIT_PARENT,


)= (200..499);



# Command data for this application.
# Only commands for gitUI.pm have entries
# But notice we merge with the base Resources Class

mergeHash($resources->{command_data},{
	$ID_PATH_WINDOW				=> ['Paths',			'View all repositories by path grouped by sections'],
	$ID_COMMIT_WINDOW       	=> ['Commit',			'A gitUI like window that allows staging, commit, and push' ],
	$ID_INFO_WINDOW				=> ['Info',				'List of Repos with Details' ],
	$ID_SUBS_WINDOW				=> ['Subs',				'Show status of all submodules' ],
	$ID_STATUS_WINDOW			=> ['Status',			'DOES PULLS! A tabular report of Repos showing their status vis-a-vis github' ],

	$ID_COMMAND_RESCAN			=> ['Rescan',			'Re-initialize repository information'],
	$ID_COMMAND_REFRESH_STATUS  => ['Refresh Status',	'Refresh the gitStatus'],
	$ID_COMMAND_REBUILD_CACHE	=> ['Rebuild Cache',	'Re-build the cache from github'],

	$ID_COMMAND_PUSH_ALL		=> ['PushAll',			'Push All commited changes'],
	$ID_COMMAND_PULL_ALL		=> ['PullAll',			'Pull All repos that can be pulled'],

	$ID_COMMAND_PUSH_SELECTED	=> ['PushSelected',		'Push commited changs for selected repos'],
	$ID_COMMAND_PULL_SELECTED   => ['PushSelected',		'Pull selected repos'],
	$ID_COMMAND_COMMIT_SELECTED_PARENTS => ['CommitSelectedParents',	'Commit the parent submodule changs for selected submodules'],
});




#-------------------------------------
# Menus
#-------------------------------------

my @main_menu = (
	'view_menu,&View',
	'actions_menu,&Actions',
);

unshift @{$resources->{view_menu}},(
	$ID_PATH_WINDOW,
	$ID_INFO_WINDOW,
	$ID_COMMIT_WINDOW,
	$ID_SUBS_WINDOW,
	$ID_SEPARATOR,
);


my @actions_menu = (
	$ID_COMMAND_PUSH_ALL,
	$ID_COMMAND_PULL_ALL,
    $ID_SEPARATOR,
	$ID_COMMAND_RESCAN,
	$ID_COMMAND_REFRESH_STATUS,
	$ID_COMMAND_REBUILD_CACHE,
);


#-----------------------------------------
# Merge and reset the single public object
#-----------------------------------------

$resources = { %$resources,
    app_title => 'gitUI',
    main_menu => \@main_menu,
	actions_menu => \@actions_menu,
};


1;
