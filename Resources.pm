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
		$ID_PUSH_WINDOW
		$ID_TAG_WINDOW

		$ID_COMMAND_RESCAN
		$ID_COMMAND_PUSH_ALL

		$COMMAND_ADD
		$COMMAND_COMMIT
		$COMMAND_PUSH
		$COMMAND_TAG
	),

	@Pub::WX::Resources::EXPORT );
}



our (

	# Windows handled by appFrame::createPane

	$ID_PATH_WINDOW,
	$ID_COMMIT_WINDOW,
	$ID_REPOS_WINDOW,
	$ID_PUSH_WINDOW,
	$ID_TAG_WINDOW,

	# UI Commands handled by appFrame::onCommand

	$ID_COMMAND_RESCAN,
	$ID_COMMAND_PUSH_ALL,

	# specific commands handled by appFrame::doGitCommand()

	$COMMAND_PUSH,			# push selected
	$COMMAND_COMMIT,		# commit all
	$COMMAND_TAG,			# tag selected

)= (10000..11000);



# Command data for this application.
# Notice the merging that takes place

mergeHash($resources->{command_data},{
	$ID_PATH_WINDOW			=> ['Paths',	'View all repositories by path grouped by sections'],
	$ID_COMMIT_WINDOW       => ['Commit',	'A gitUI like window that allows staging, commit, and push' ],
	$ID_REPOS_WINDOW		=> ['Repos',	'List of Repos with Details' ],
	$ID_PUSH_WINDOW			=> ['Push',		'Push selected repositories' ],
	$ID_TAG_WINDOW 			=> ['Tag',		'Apply Tags to selected repositories' ],

	$ID_COMMAND_RESCAN			=> ['Rescan',	'Re-initialize repository information'],
	$ID_COMMAND_PUSH_ALL		=> ['PushAll',	'Push All commited changes'],

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
	$ID_SEPARATOR,
);


my @actions_menu = (
	$ID_COMMAND_RESCAN,
    $ID_SEPARATOR,
	$ID_TAG_WINDOW,
	$ID_PUSH_WINDOW,
	$ID_COMMAND_PUSH_ALL,		# only one actually implemented
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
