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

BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = ( qw(
		$ID_PATH_WINDOW
		$COMMAND_PUSH

		$COMMAND_PATHS
		$COMMAND_REPOS
		$COMMAND_CHANGES
		$COMMAND_REPOS
		$COMMAND_DEPENDENCIES
	),

	@Pub::WX::Resources::EXPORT );
}


# derived class decides if wants viewNotebook
# commands added to the view menu, by setting
# the 'command_id' member on the notebook info.

our ($ID_PATH_WINDOW,

	$COMMAND_CHANGES,
		# currently modal with ?!? reporting ?!?
		# should be done automatically after COMMIT, PUSH, or TAG

	$COMMAND_COMMIT,
	$COMMAND_PUSH,		# only one actually implemented
	$COMMAND_TAGS,

	$COMMAND_REPOS,

	# idas for windows

	$COMMAND_PATH_WIN,
	$COMMAND_SHOW_CHANGES,
	$COMMAND_INFO,
	$COMMAND_DEPENDS,
)= (10000..11000);



# Command data for this application.
# Notice the merging that takes place

my %command_data = (%{$resources->{command_data}},

	$COMMAND_CHANGES		=> ['Changes',	'Update local and remote changes for repositories'],

	$COMMAND_COMMIT			=> ['Commit',	'Commit repositories with a comment'],
	$COMMAND_PUSH			=> ['Push',		'Push any commited local changes'],
	$COMMAND_TAGS			=> ['Tags',		'Add Tag to selected repositories'],

    $COMMAND_REPOS      	=> ['Repos',	'Update local repository info cache from github'],

	$COMMAND_PATH_WIN		=> ['Paths',	'Show repos organized by Sections'],
    $COMMAND_SHOW_CHANGES   => ['Deltas',	'Show the current changes. Could also be dialog with context menu item'],
    $COMMAND_INFO    		=> ['Info',		'Maybe a tree? table? Showing info for each repository. Could also be dialog with context menu item'],
    $COMMAND_DEPENDS    	=> ['Depends',	'Show Dependency tree, etc'],
);


my %pane_data = (
	# $ID_CLIENT_WINDOW	=> ['client_window',	'content'	],
);


#-------------------------------------
# Menus
#-------------------------------------

my @main_menu = ( 'view_menu,&View' );



unshift @{$resources->{view_menu}},(
	$COMMAND_CHANGES,
		$ID_SEPARATOR,
	$COMMAND_COMMIT,
	$COMMAND_PUSH,		# only one actually implemented
	$COMMAND_TAGS,
		$ID_SEPARATOR,
	$COMMAND_REPOS,
	    $ID_SEPARATOR,
	$COMMAND_PATH_WIN,
	$COMMAND_SHOW_CHANGES,
	$COMMAND_INFO,
	$COMMAND_DEPENDS,
		$ID_SEPARATOR,
		# .... default view menu
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
    command_data => \%command_data,
    win_context_menu => \@win_context_menu,
};


1;
