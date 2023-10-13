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

our ($COMMAND_PATHS,
	 $COMMAND_REPOS,
	 $COMMAND_CHANGES,
	 $COMMAND_REMOTE,
	 $COMMAND_DEPENDS )= (10000..11000);


# Command data for this application.
# Notice the merging that takes place

my %command_data = (%{$resources->{command_data}},

	$COMMAND_PATHS		=> ['Paths',	'Show local paths with Sections'],
    $COMMAND_REPOS      => ['Repos',	'Show by Repo ID'],
    $COMMAND_CHANGES    => ['Changes',	'Show current Changes'],
    $COMMAND_REMOTE     => ['Remote',	'Validate against Github'],
    $COMMAND_DEPENDS    => ['Depends',	'Show Dependency tree, etc'],
);


my %pane_data = (
	# $ID_CLIENT_WINDOW	=> ['client_window',	'content'	],
);


#-------------------------------------
# Menus
#-------------------------------------

my @main_menu = ( 'view_menu,&View' );

unshift @{$resources->{view_menu}},$COMMAND_PATHS;
unshift @{$resources->{view_menu}},$COMMAND_REPOS;
unshift @{$resources->{view_menu}},$COMMAND_CHANGES;
unshift @{$resources->{view_menu}},$COMMAND_REMOTE;
unshift @{$resources->{view_menu}},$COMMAND_DEPENDS;


my @win_context_menu = (
    $ID_SEPARATOR,
);


#-----------------------------------------
# Merge and reset the single public object
#-----------------------------------------

$resources = { %$resources,
    app_title => 'fileCllient',
    main_menu => \@main_menu,
    command_data => \%command_data,
    win_context_menu => \@win_context_menu,
};


1;
