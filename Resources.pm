#!/usr/bin/perl
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
		$ID_COMMIT_WINDOW
		$ID_REPO_DETAILS

		$COMMAND_CHANGES
		$COMMAND_REPOS

		$COMMAND_ADD
		$COMMAND_COMMIT
		$COMMAND_PUSH
		$COMMAND_TAG

		$COMMAND_PATH_WIN
		$COMMAND_SHOW_CHANGES
		$COMMAND_INFO
		$COMMAND_DEPENDS
	),

	@Pub::WX::Resources::EXPORT );
}


# derived class decides if wants viewNotebook
# commands added to the view menu, by setting
# the 'command_id' member on the notebook info.

our (

	$ID_PATH_WINDOW,
	$ID_COMMIT_WINDOW,
	$ID_REPO_DETAILS,

	# Refresh

	$COMMAND_CHANGES,
	$COMMAND_REPOS,

	# Actions

	$COMMAND_ADD,
	$COMMAND_COMMIT,
	$COMMAND_PUSH,		# only one actually implemented
	$COMMAND_TAG,

	# idas for windows

	$COMMAND_PATH_WIN,
	$COMMAND_SHOW_CHANGES,
	$COMMAND_INFO,
	$COMMAND_DEPENDS,
)= (10000..11000);



# Command data for this application.
# Notice the merging that takes place

mergeHash($resources->{command_data},{
	$ID_PATH_WINDOW			=> ['Paths',		'View all repositories by path grouped by sections'],
	$ID_COMMIT_WINDOW       => ['Commit',		'A gitUI like window that allows staging, commit, and push' ],
	$ID_REPO_DETAILS		=> ['Repo Details',	'List of Repos that allows viewing all details for a given repo'],

	$COMMAND_CHANGES		=> ['Changes',	'Update local and remote changes for repositories'],
    $COMMAND_REPOS      	=> ['Repos',	'Update local repository info cache from github'],

	$COMMAND_ADD			=> ['Add',		'Add unstaged changes to staged'],
	$COMMAND_COMMIT			=> ['Commit',	'Commit staged changes with a comment'],
	$COMMAND_PUSH			=> ['Push',		'Push commited changes'],
	$COMMAND_TAG			=> ['Tags',		'Add Tag to selected repositories'],

	$COMMAND_PATH_WIN		=> ['Paths',	'Show repos organized by Sections'],
    $COMMAND_SHOW_CHANGES   => ['Deltas',	'Show the current changes. Could also be dialog with context menu item'],
    $COMMAND_INFO    		=> ['Info',		'Maybe a tree? table? Showing info for each repository. Could also be dialog with context menu item'],
    $COMMAND_DEPENDS    	=> ['Depends',	'Show Dependency tree, etc'],
});


my %pane_data = (
	# $ID_CLIENT_WINDOW	=> ['client_window',	'content'	],
);


#-------------------------------------
# Menus
#-------------------------------------

my @main_menu = (
	'view_menu,&View',
	'update_menu,&Update',
	'actions_menu,&Actions',
);

unshift @{$resources->{view_menu}},(
	$ID_PATH_WINDOW,
	$ID_COMMIT_WINDOW,
	$ID_REPO_DETAILS,
	$ID_SEPARATOR,
);


my @update_menu = (
	$COMMAND_CHANGES,
	$COMMAND_REPOS,
);

my @actions_menu = (
	$COMMAND_ADD,
	$COMMAND_COMMIT,
	$COMMAND_PUSH,		# only one actually implemented
	$COMMAND_TAG,
);


my @win_context_menu = (
    $ID_SEPARATOR,
);


#-----------------------------------------
# Merge and reset the single public object
#-----------------------------------------

$resources = { %$resources,
    app_title => 'gitUI',
    main_menu => \@main_menu,
	update_menu => \@update_menu,
	actions_menu => \@actions_menu,
    win_context_menu => \@win_context_menu,
};


1;
