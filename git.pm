#----------------------------------------------------
# base::apps::gitUI::git
#----------------------------------------------------
# - parses {path}/,git/config files
# - calls github to get list of all repositories
# - calls github to get info about fork-parent of a repository
# - calls local git for changes, commits, tags, and pushes

package apps::gitUI::git;
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Utils;

$temp_dir = "/base/temp/gitUI";
$data_dir = "/base/temp/gitUI";
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
