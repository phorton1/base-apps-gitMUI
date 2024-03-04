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
		$ID_REPOS_WINDOW
		$ID_COMMIT_WINDOW
		$ID_STATUS_WINDOW

		$ID_COMMAND_RESCAN
		$ID_COMMAND_REFRESH_STATUS
		$ID_COMMAND_REBUILD_CACHE

		$ID_COMMAND_PUSH_ALL
		$ID_COMMAND_PULL_ALL
		$ID_COMMAND_PUSH_SELECTED
		$ID_COMMAND_PULL_SELECTED
	),

	@Pub::WX::Resources::EXPORT );
}



our (

	# Windows handled by appFrame::createPane

	$ID_PATH_WINDOW,
	$ID_COMMIT_WINDOW,
	$ID_REPOS_WINDOW,
	$ID_STATUS_WINDOW,

	# ideas for windows that allow you to do things to selected repositories
	# 	$ID_PUSH_WINDOW,
	# 	$ID_TAG_WINDOW,

	# UI Commands handled by appFrame::onCommand

	$ID_COMMAND_RESCAN,
	$ID_COMMAND_REFRESH_STATUS,
	$ID_COMMAND_REBUILD_CACHE,

	$ID_COMMAND_PUSH_ALL,
	$ID_COMMAND_PULL_ALL,

	$ID_COMMAND_PUSH_SELECTED,
	$ID_COMMAND_PULL_SELECTED,
		# No UI.  Implemented on a window-by-window basis

	# pushing or pulling one repo is a special case
	# of pushing or pulling selected repos, and
	# the menu should reflect "Push N repos" or
	# Push /base/apps/artisan

	# $COMMAND_TAG,			# tag selected

)= (10000..11000);



# Command data for this application.
# Notice the merging that takes place

mergeHash($resources->{command_data},{
	$ID_PATH_WINDOW			=> ['Paths',	'View all repositories by path grouped by sections'],
	$ID_COMMIT_WINDOW       => ['Commit',	'A gitUI like window that allows staging, commit, and push' ],
	$ID_REPOS_WINDOW		=> ['Repos',	'List of Repos with Details' ],
	$ID_STATUS_WINDOW		=> ['Status',	'DOES PULLS! A tabular report of Repos showing their status vis-a-vis github' ],

	$ID_COMMAND_RESCAN			=> ['Rescan',			'Re-initialize repository information'],
	$ID_COMMAND_REFRESH_STATUS  => ['Refresh Status',	'Refresh the gitStatus'],
	$ID_COMMAND_REBUILD_CACHE	=> ['Rebuild Cache',	'Re-build the cache from github'],

	$ID_COMMAND_PUSH_ALL		=> ['PushAll',		'Push All commited changes'],
	$ID_COMMAND_PULL_ALL		=> ['PullAll',		'Pull All repos that can be pulled'],
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
	$ID_REPOS_WINDOW,
	$ID_COMMIT_WINDOW,
	$ID_STATUS_WINDOW,
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
