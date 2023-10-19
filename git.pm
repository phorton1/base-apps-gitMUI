#----------------------------------------------------
# base::apps::gitUI::git
#----------------------------------------------------
# Some commom git commands:
#
#    diff --name-status
#       or git "status show modified files"
#       shows any local changes to the repo
#    diff master origin/master --name-status","remote differences"
#       show any differences from bitbucket
#    fetch
#       update the local repository from the net ... dangerous?
#    stash
#       stash any local changes
#    update
#       pull any differences from bitbucket
#    add .
#       add all uncommitted changes to the staging area
#    commit  -m "checkin message"
#       calls "git add ." to add any uncommitted changes to the staging area
#       and git $command to commit the changes under the given comment
#    push -u origin master
#       push the repository to bitbucket
#
# TO INITIALIZE REMOTE REPOSITORY
#
#      git remote add origin https://github.com/phorton1/Arduino.git
#
# Various dangerous commands
#
#    git reset --hard HEAD
#    git pull -u origin master


package apps::gitUI::git;
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Utils;

$temp_dir = "/base_data/temp/gitUI";
$data_dir = "/base_data/data/gitUI";
	# we set these here, even though they aren't used
	# until gitUI::github.pm, cuz it's easy to find.

my $dbg_ids = 1;
	# 0 = debug repoPathToId() and repoIdToPath()


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(

		$repo_filename

		repoPathToId
		repoIdToPath
	);
}


my @id_path_mappings = (
	"obs-"             , "/src/obs/",
    "Android"      	   , "/src/Android",
	"Arduino"          , "/src/Arduino",
    "circle-prh-apps"  , "/src/circle/_prh/_apps",
    "circle-prh"       , "/src/circle/_prh",
    "circle"           , "/src/circle",
	"phorton1"	       , "/src/phorton1",
    "projects"         , "/src/projects",
    "www"              , "/var/www",
	"komodoEditTools", , "/Users/Patrick/AppData/Local/ActiveState/KomodoEdit/8.5/tools",
	"fusionAddIns"	   , "/Users/Patrick/AppData/Roaming/Autodesk/Autodesk Fusion 360/API/AddIns",
);


sub repoPathToId
{
    my ($path) = @_;
    my $id = $path;
    my $i = 0;
    while ($i < @id_path_mappings)
    {
        my $repl = $id_path_mappings[$i++];
        my $pat = $id_path_mappings[$i++];
        last if $id =~ s/^$pat/$repl/e;
    }
    $id =~ s/\//-/g;
    $id =~ s/^-//;
	display($dbg_ids,0,"repoPathToId($path)=$id");
    return $id;
}


sub repoIdToPath
{
    my ($id) = @_;
    my $path = $id;
    my $i = 0;
    while ($i < @id_path_mappings)
    {
        my $pat = $id_path_mappings[$i++];
        my $repl = $id_path_mappings[$i++];
        last if $path =~ s/^$pat/$repl/e;
    }
    $path =~ s/-/\//g;
    $path = "/".$path if $path !~ /^\//;

    # one project has a dash in their terminal directory name

    $path =~ s/wxWidgets\/3.0.2$/wxWidgets-3.0.2/;

	display($dbg_ids,0,"repoIdToPath($id)=$path");
    return $path;
}



1;
