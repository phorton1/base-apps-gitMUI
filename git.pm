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
use JSON;
use HTTP::Request;
use LWP::UserAgent;
use LWP::Protocol::http;
use Mozilla::CA;
use Pub::Utils;


my $dbg_ids = 1;


our $repo_filename = '/base/bat/git_repositories.txt';
our $GET_GITHUB_FORK_PARENTS = 1;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		$repo_filename

		$GET_GITHUB_FORK_PARENTS

		repoError
		repoWarning
		repoPathToId
		repoIdToPath
	);
}


my $git_user = 'phorton';
my $git_api_token = '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';


my @id_path_mappings = (
	"obs-"             ,    "/src/obs/",
    "Arduino"          ,    "/src/Arduino",
    "circle-prh-apps"  ,    "/src/circle/_prh/_apps",
    "circle-prh"       ,    "/src/circle/_prh",
    "circle"           ,    "/src/circle",
    "projects"         ,    "/src/public",
    "src-android"      ,    "/src/AndroidStudio",
    "www"              ,    "/var/www",
	"Grbl"			   ,    "/src/Grbl",
	"FluidNC"		   ,    "/src/FluidNC",
	"kiCad"			   ,    "/src/kiCad",
	"phorton1"	       ,	"/src/phorton1",
	"fusionAddIns",		"/Users/Patrick/AppData/Roaming/Autodesk/Autodesk Fusion 360/API/AddIns",
);




sub repoError
{
	my ($repo,$msg,$quiet,$call_level) = @_;
	$call_level ||= 0;
	$call_level++;
	error($msg,$call_level) if !$quiet;
	push @{$repo->{errors}},$msg;
}

sub repoWarning
{
	my ($repo,$dbg_level,$msg,$quiet,$call_level) = @_;
	$call_level ||= 0;
	$call_level++;
	warning($dbg_level,-1,$msg,$call_level) if !$quiet;
	push @{$repo->{warnings}},$msg;
}


sub repo_note
{
	my ($repo,$dbg_level,$msg,$quiet,$call_level) = @_;
	$call_level ||= 0;
	$call_level++;
	LOG($msg,$call_level) if !$quiet && $dbg_level <= $debug_level;
	push @{$repo->{notes}},$msg;
}



sub repoPathToId
{
    my ($path) = @_;
    my $id = $path;
    my $i = 0;
    while ($i < @id_path_mappings)
    {
        my $repl = $id_path_mappings[$i++];
        my $pat = $id_path_mappings[$i++];
        $id =~ s/^$pat/$repl/e;
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
        $path =~ s/^$pat/$repl/e;
    }
    $path =~ s/-/\//g;
    $path = "/".$path if $path !~ /^\//;

    # two projects have dashes in their terminal directory name

    $path =~ s/Win32\/OLE$/Win32-OLE/;
    $path =~ s/wxWidgets\/3.0.2$/wxWidgets-3.0.2/;

	display($dbg_ids,0,"repoIdToPath($id)=$path");
    return $path;
}





1;
