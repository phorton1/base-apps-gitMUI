#----------------------------------------------------
# a Parser and Validator for my git repositories
#----------------------------------------------------
# the repos collection is represented as a
# - HASH by path of repos
# - a LIST in order of parsed repos
# - a set of SECTION containing a number of repos organized for display in my apps

package apps::gitUI::section;
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Utils;

my $dbg_sections = 1;
my $MAX_DISPLAY_NAME = 28;
	# not including elipses


sub new
{
	my ($class, $num, $path, $name) = @_;
	my $re = $path;
	$re =~ s/\//\\\//g;
	display($dbg_sections,1,"SECTION($path,$name) re=$re");
	my $this = shared_clone({
		num => $num,
		count => 0,
		path => $path,
		name => $name,
		re   => $re,
		repos => shared_clone([]), });
	bless $this,$class;
	return $this;
}

sub addRepo
{
	my ($this,$repo) = @_;
	$this->{count}++;
	push @{$this->{repos}},$repo;
}

sub displayName
{
	my ($this,$repo) = @_;
	my $name = $repo->{path};
	$name =~ s/^$this->{re}//;
	$name ||= $repo->{path};
	$name = '...'.substr($name,-$MAX_DISPLAY_NAME)
		if length($name) >= $MAX_DISPLAY_NAME;
	display($dbg_sections,1,"displayName($repo->{path}) = $name");
	return $name;
}



package apps::gitUI::repos;
use strict;
use warnings;
use threads;
use threads::shared;
use apps::gitUI::git;
use apps::gitUI::repo;
use Pub::Utils;


my $dbg_parse = 0;
	# -1 for repos
	# -2 for lines


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		parseRepos
		getRepoHash
		getRepoList
		getRepoSections
	);
}


my $repo_hash:shared = shared_clone({});
my $repo_list:shared = shared_clone([]);
my $repo_sections:shared = shared_clone([]);

sub getRepoHash		{ return $repo_hash; }
sub getRepoList		{ return $repo_list; }
sub getRepoSections	{ return $repo_sections; }




sub parseRepos
{
    display($dbg_parse,0,"parseRepos($repo_filename)");
	my $text = getTextFile($repo_filename);
    if ($text)
    {
		my $repo_num = 0;

		my $repo;
		my $section;
		my $section_num = 0;
		my $section_path = '';
		my $section_name = '';
		my $section_started = 0;

        for my $line (split(/\n/,$text))
        {
			$line =~ s/#.*$//;
			$line =~ s/^\s+//;
			$line =~ s/\s+$//;

			# get section path RE and optional name if different

			if ($line =~ /^SECTION\t/)
			{
				my @parts = split(/\t/,$line);
				$section_path = $parts[1];
				$section_path =~ s/^\s+|\s+$//g;
				$section_name = $parts[2] || $section_path;
				$section_started = 0;
			}

			# Repos start with a forward slash

			elsif ($line =~ /^\//)
			{
				my @parts = split(/\t/,$line);
				my ($path,$branch) = @parts;
				$branch ||= 'master';

				display($dbg_parse+1,1,"repo($repo_num,$section_name,$path,$branch)");

				$repo = apps::gitUI::repo->new($repo_num++,$section_name,$path,$branch);

				push @$repo_list,$repo;
				$repo_hash->{$path} = $repo;

				if (!$section_started)
				{
					$section = apps::gitUI::section->new($section_num++,$section_path,$section_name);
					push @$repo_sections,$section;
					$section_started = 1;
				}

				$section->addRepo($repo);
			}

			# set PRIVATE bit

			elsif ($line =~ /^PRIVATE$/i)
			{
				display($dbg_parse+2,2,"PRIVATE");
				$repo->{private} = 1;
			}


			# add USES, NEEDS, GROUP, FRIEND

			elsif ($line =~ s/^(USES|NEEDS|GROUP|FRIEND)\s+//)
			{
				my $what = $1;
				display($dbg_parse+2,2,"$what $line");
				push @{$repo->{lc($what)}},$line;
			}
		}
    }
    else
    {
        error("Could not open $repo_filename");
        return;
    }

    if (!@$repo_list)
    {
        error("No paths found in $repo_filename");
        return;
    }
	return 1;
}




1;
