#----------------------------------------------------
# a Parser and Validator for my git repositories
#----------------------------------------------------
# the repos collection is represented as a
# - HASH by path of repos
# - a LIST in order of parsed repos
# - a set of SECTION containing a number of repos organized for display in my apps
#
# This file can parse them from the file and
# add members from local git/config files.


package apps::gitUI::repos;
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Utils;
use apps::gitUI::repo;
use apps::gitUI::utils;



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

		canPushRepos
		setCanPush
		clearSelected

		groupReposBySection
	);
}

my $repo_filename = '/base/bat/git_repositories.txt';

my $repo_hash:shared = shared_clone({});
my $repo_list:shared = shared_clone([]);
my $repos_can_push = shared_clone({});

sub getRepoHash		{ return $repo_hash; }
sub getRepoList		{ return $repo_list; }



sub canPushRepos
{
	return scalar(keys %$repos_can_push);
}

sub setCanPush
{
	my ($repo) = @_;
	my $num = keys %{$repo->{remote_changes}};
	if ($num)
	{
		$repos_can_push->{$repo->{path}} = $num;
	}
	else
	{
		delete $repos_can_push->{$repo->{path}};
	}
}

sub clearSelected
{
	for my $repo (@$repo_list)
	{
		$repo->{selected} = 0;
	}
}



sub parseRepos
{
    display($dbg_parse,0,"parseRepos($repo_filename)");
	$repo_hash = shared_clone({});
	$repo_list = shared_clone([]);

	my $text = getTextFile($repo_filename);
    if ($text)
    {
		my $repo_num = 0;

		my $repo;
		my $section_path = '';
		my $section_name = '';

        for my $line (split(/\n/,$text))
        {
			$line =~ s/#.*$//;
			$line =~ s/^\s+//;
			$line =~ s/\s+$//;

			# get section path RE and optional name if different

			if ($line =~ /^SECTION\t/i)
			{
				my @parts = split(/\t/,$line);
				$section_path = $parts[1];
				$section_path =~ s/^\s+|\s+$//g;
				$section_name = $parts[2] || '';
			}

			# Repos start with a forward slash

			elsif ($line =~ /^\//)
			{
				my @parts = split(/\t/,$line);
				my ($path,$branch) = @parts;
				$branch ||= 'master';

				if (!$TEST_JUNK_ONLY || $path =~ /junk/)
				{
					display($dbg_parse+1,1,"repo($repo_num,$path,$branch,$section_path,$section_name)");
					$repo = apps::gitUI::repo->new($repo_num++,$path,$branch,$section_path,,$section_name);

					push @$repo_list,$repo;
					$repo_hash->{$path} = $repo;
				}
				else
				{
					# support for TEST_JUNK_ONLY, set repo to ''
					# so that the rest of the stuff won't be added
					# as it goes through the file.

					$repo = '';
				}
			}
			elsif ($repo)
			{
				# set PRIVATE bit

				if ($line =~ /^PRIVATE$/i)
				{
					display($dbg_parse+2,2,"PRIVATE");
					$repo->{private} = 1;
				}

				# set FORKED = 1 or whatever follows

				elsif ($line =~ s/^FORKED\s*//i)
				{
					$line ||= 1;
					display($dbg_parse+2,2,"FORKED $line");
					$repo->{forked} = $line;
				}

				# add USES, NEEDS, GROUP, FRIEND

				elsif ($line =~ s/^(USES|NEEDS|GROUP|FRIEND|NOTES|WARNINGS|ERRORS)\s+//i)
				{
					my $what = $1;
					display($dbg_parse+2,2,"$what $line");
					push @{$repo->{lc($what)}},$line;
				}
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



#--------------------------------------------------------------------
# repo grouping utilities
#--------------------------------------------------------------------


sub section
{
	my ($name) = @_;
	return shared_clone({
		name  => $name,
		repos => shared_clone([]),
	});
}


sub groupReposBySection
{
	my $sections = shared_clone([]);
	my $section = '';
	my $section_name = 'invalid_initial_value';
	for my $repo (@$repo_list)
	{
		if ($section_name ne $repo->{section_name})
		{
			$section_name = $repo->{section_name};
			$section = section($section_name);
			push @$sections,$section;
		}
		push @{$section->{repos}},$repo;
	}
	return $sections;
}



#--------------------------------------------------------------------
# test main - developing 'all tags across repositories' function
#--------------------------------------------------------------------

use Git::Raw;


my $all_tags = {};


sub addRepoTags
{
	my ($repo) = @_;

	my $git_repo = Git::Raw::Repository->open($repo->{path});
	return $repo->repoError("Could not create git_repo") if !$git_repo;

	my @tag_refs = $git_repo->tags( 'all' );

	my $started = 0;
	for my $tag_ref (@tag_refs)
	{
		my $commit = $tag_ref->target();
		my $sig = $commit->author();
		my $author = $sig->name();
		next if $author !~ /phorton1|Patrick Horton/;

		my $tag_name = $tag_ref->name();
		$tag_name =~ s/^.*\///;
		my $summary = $commit->summary();
		$summary = substr($summary,0,50) if length($summary)>50;
		my $time = timeToStr($commit->time());

		$started = tagHeader($repo,$started);
		print pad('',8)._plim($tag_name,15)." "._plim($time,20)." "._plim($author,20)." ".$summary."\n";

		#my $id = $tag->id() || '';
		#my $name = $tag->name() || '';
		#my $msg = $tag->message() || '';
		# print pad('',8).pad($name,12).pad($id.20).$msg."\n";

		my $tag = $all_tags->{$tag_name};
		if (!$tag)
		{
			$tag = {
				name => $tag_name,
				time => $time,
				paths => {} };
			$all_tags->{$tag_name} = $tag;
		}

		$tag->{time} = $time if $time lt $tag->{time};
		$tag->{paths}->{$repo->{path}} = 1;
	}

}









if (0)
{
	if (parseRepos())
	{
		my $repo_list = getRepoList();
		for my $repo (@$repo_list)
		{
			addRepoTags($repo);
		}

		print "\nALL TAGS\n";
		for my $tag (sort {$a->{time} cmp $b->{time}} values %$all_tags)
		{
			print _plim($tag->{name},15)." ".$tag->{time}."\n";
			for my $path (sort keys %{$tag->{paths}})
			{
				print pad('',4).$path."\n";
			}
		}
	}
}




1;
