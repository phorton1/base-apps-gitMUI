#----------------------------------------------------
# repoHistory
#----------------------------------------------------
# the repos collection is represented as a
# - HASH by path of repos
# - a LIST in order of parsed repos
# - a set of SECTION containing a number of repos organized for display in my apps
#
# This file can parse them from the file and
# add members from local git/config files.


package apps::gitMUI::repoHistory;
use strict;
use warnings;
use threads;
use threads::shared;
use Git::Raw;
use Pub::Utils;
use apps::gitMUI::utils;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		historyToTextCtrl
		gitCurrentBranch
	);
}


my $dbg_hist = 1;


sub gitCurrentBranch
{
	my ($repo) = @_;
	my $path = ref($repo) ? $repo->{path} : $repo;
	my $git_repo = Git::Raw::Repository->open($path);
	my $current_branch = $git_repo->head()->name();
	$current_branch =~ s/\/refs\/heads\///;
	$current_branch =~ s/^refs\/remotes\/origin/r/;
	return $current_branch;
}


my $max_name = 0;

sub gitHistory
	# can be called with a repo(hash) or scalar(path)
	# showing threads is a daunting task and not perhaps
	# not that useful to me.
{
	my ($repo_or_path,$all_branch_history) = @_;
	$max_name = 0;

	my $path = ref($repo_or_path) ? $repo_or_path->{path} : $repo_or_path;
	display($dbg_hist,0,"gitHistory($path,$all_branch_history)");
	my $git_repo = Git::Raw::Repository->open($path);

	# 0. create the walker

	my $log = $git_repo->walker();

	# 1. create hash by commit_id of all branches in the repo
	#    and add them to the walker if $all_branch_history

	display($dbg_hist,0,"BRANCHES");
	my $repo_branches = {};
	my @branch_refs = $git_repo->branches( 'all' );
	for my $branch_ref (@branch_refs)
	{
		my $commit = $branch_ref->target();

		$commit = $commit->peel('commit')
			if ref($commit) =~ /Git::Raw::Reference/;
		my $branch_name = $branch_ref->name();

		$log->push($commit)
			if $all_branch_history;

		$branch_name =~ s/^refs\/heads\///;
		$branch_name =~ s/^refs\/remotes\/origin/r/;

		display($dbg_hist,1,$branch_name);

		# the commit returns its commit_id in a scalar context !?!

		my $branches = $repo_branches->{$commit};
		$branches = $repo_branches->{$commit} = {} if !$branches;
		$branches->{$branch_name} = 1;
	}

	# 2. create hash by commit_id of all tags in the repo
	#	 and add them to the walker if $all_branch_history
	# 	 (apparently a 'tag' can be a 'branch' and need to
	#	 be added to the walker for $all_branch_history)

	display($dbg_hist,0,"TAGS");

	my $repo_tags = {};
	my @tag_refs = $git_repo->tags( 'all' );
	for my $tag_ref (@tag_refs)
	{
		my $tag_name = $tag_ref->name();
		$tag_name =~ s/^.*\///;
		my $commit = $tag_ref->target();
		my $commit_id = $commit->id();
		my $tags = $repo_tags->{$commit_id};

		# visualize 'all branch history'
		$log->push($commit)
			if $all_branch_history;

		display($dbg_hist,1,$tag_name);
		$tags = $repo_tags->{$commit_id} = {} if !$tags;
		$tags->{$tag_name} = 1;
	}

	$log->push_head() if !$all_branch_history;
	$log->sorting(['time','topological','reverse']);
		# gitGUI's list is sorted slightly differently than libgit2

	# 3. Walk the commits in the repo/branch
	#    They will be oldest first in $retval->[commits];

	my $commit_list = [];
	my $commit_hash = {};
	my $com = $log->next();
	while ($com)
	{
		my $id = $com->id();
		my $sig = $com->author();
		my $author = filterPrintable($sig->name());
		my $tags = $repo_tags->{$id} || {};
		my $branches  = $repo_branches->{$id} || {};
		my @parents = $com->parents();

		$author =~ s/\s+$//;
		$max_name = length($author) if length($author)>$max_name;

		my $commit = {
			id			=> $id,
			time		=> timeToStr($com->time()),
			author		=> $author,
			summary		=> $com->summary(),
			tags		=> $tags,
			branches	=> $branches,		# branches that point to this commit as their HEAD
			in_branches => {},				# branches that include this commit
			parents		=> [],
			children	=> [] };

		$commit_hash->{$id} = $commit;
		push @$commit_list,$commit;

		for my $parent_id (@parents)
		{
			my $parent = $commit_hash->{$parent_id};
			next if !$parent;
			push @{$commit->{parents}},$parent_id;
			push @{$parent->{children}},$id;
		}

		$com = $log->next();
	}

	display($dbg_hist,0,"gitHistory($path) max_name($max_name) returning ".scalar(@$commit_list)." commits");
	return $commit_list;
}







sub historyToTextCtrl
{
	my ($text_ctrl,$repo_or_path,$all_branch_history) = @_;
	my $commit_list = gitHistory($repo_or_path,1);

	$max_name = 20 if $max_name > 20;

	$text_ctrl->addSingleLine(1,$color_black,'HISTORY');

	for my $commit (reverse @$commit_list)
	{
		my $content_line = [];

		my @branches = sort keys %{$commit->{branches}};
		my $branch_text = @branches ? "[".join(",",@branches)."]" : '';
		my @tags     = sort keys %{$commit->{tags}};
		my $tag_text = @tags ? "<".join(",",@tags).">" : '';
		my $spacer = $branch_text || $tag_text ? " " : '';

		my $line = $text_ctrl->addLine();
		$text_ctrl->addPart($line,0,$color_blue,
			pad("",4).
			_lim($commit->{id},8)." ".
			_plim($commit->{time},20).
			_plim($commit->{author},$max_name)." ");
		$text_ctrl->addPart($line,1,$color_orange,$branch_text)
			if $branch_text;
		$text_ctrl->addPart($line,1,$color_lime,$tag_text)
			if $tag_text;
		$text_ctrl->addPart($line,0,$color_black,$spacer.$commit->{summary});
	}
}




1;
