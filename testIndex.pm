#----------------------------------------------------
# find any repos that have stashes
#----------------------------------------------------

use strict;
use warnings;
use threads;
use threads::shared;
use Git::Raw;
use Pub::Utils;


my $repo_path = "/base/apps/gitUI";


display(0,0,"repo($repo_path)");
my $git_repo = Git::Raw::Repository->open($repo_path);
exit 0 if !$git_repo;

display(0,0,"getting index");
my $index = $git_repo->index();
exit 0 if !$index;

display(0,0,"getting entries");
my @entries = $index->entries();
exit 0 if !@entries;


for my $entry (@entries)
{
	my $path = $entry->path();
	my $size = $entry->size();
	my $mode = $entry->mode();
	my $octal = sprintf("%O",$mode);
	my $stage = $entry->stage();
	display(0,1,"stage($stage) mode($octal) size($size) path($path)");
}


1;