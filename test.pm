#----------------------------------------------------
# test program to try some things
#----------------------------------------------------

use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Utils;
use Pub::Prefs;
use apps::gitUI::utils;
use apps::gitUI::repo;
use apps::gitUI::repos;
use apps::gitUI::repoGit;
use apps::gitUI::reposGithub;

# normally all of these should be X-Poll-Limit which is typically 60 seconds

my $SLEEP_AFTER_INIT = 60;
my $SLEEP_AFTER_304 = 60;
my $SLEEP_AFTER_GET = 60;


my $DO_ALL = 1;

my $dbg_head_commits = 0;
my $dbg_head_history = 0;


sub doRepoPath
{
	my ($path) = @_;
	return 1 if $DO_ALL || $path =~ /\/data$|\/data_master$|\/site\/myIOT$/;
	return 0;
}


sub addHistoryFound
{
	my ($ptext,$id,$comp,$what) = @_;
	if ($id eq $comp)
	{
		$$ptext .= ' ' if $$ptext;
		$$ptext .= $what;
		return 1;
	}
	return 0;
}


sub addHeadHistory
{
	my ($repo,$git_repo) = @_;
	my $branch = $repo->{branch};
	$git_repo ||= Git::Raw::Repository->open($repo->{path});
	display($dbg_head_history,0,"addHeadHistory($repo->{path})");

	my $head_commit = Git::Raw::Reference->lookup("HEAD", $git_repo)->peel('commit') || '';

	my ($head_id_found,
		$master_id_found,
		$remote_id_found) = (0,0,0);

	my $log = $git_repo->walker();
	# $log->sorting(["time","reverse"]);
	$log->push($head_commit);

	my $com = $log->next();

	while ($com && (
		!$head_id_found ||
		!$master_id_found ||
		!$remote_id_found ))
	{
		my $id = $com->id();
		my $summary = $com->summary();
		my $time = timeToStr($com->time());
		my $msg = '';

		$head_id_found ||= addHistoryFound(\$msg,$id,$repo->{head_id},'HEAD');
		$master_id_found ||= addHistoryFound(\$msg,$id,$repo->{master_id},'MASTER');
		$remote_id_found ||= addHistoryFound(\$msg,$id,$repo->{remote_id},'REMOTE');

		display($dbg_head_history,2,"$time ".pad($msg,20)."$id == "._lim($summary,20));

		$repo->{history} ||= shared_clone([]);
		push @{$repo->{history}},shared_clone({
			id => $id,
			summary => $summary,
			time => $time,
			msg => $msg,
		});

		$com = $log->next();
	}

	return $git_repo
}


sub checkSubmodules
	# checks main module against the submodules it is 'used_in', if any
	# at this time, called from doGitHub() at startup, there gitChanges()
	# has not yet been called.
{
	my ($repo) = @_;
	return if !$repo->{used_in};
	repoDisplay(0,0,"checkSubmodules($repo->{path})");
	for my $sub_path (@{$repo->{used_in}})
	{
		my $sub_repo = getRepoByPath($sub_path);
		return repoError($repo,"Could not find used_in($sub_path)")
			if !$sub_repo;

		repoDisplay(0,2,"used in $sub_path");

		# instead of reporting this as an error, we push it directly
		# onto the error lists of both repos.

		if ($sub_repo->{master_id} ne $repo->{master_id})
		{
			my $msg = "SUB_MODULE($sub_repo->{master_id})) <> MASTER_MODULE($repo->{master_id})";
			# repoError($repo,$msg);
			push @{$repo->{errors}},$msg;
			push @{$sub_repo->{errors}},$msg;
		}
	}
}



#----------------------------------------------
# Event Thread
#----------------------------------------------

my $dbg_event = 0;


sub oneEvent
{
	my ($event) = @_;
	my $event_id = $event->{id};
	my $type = $event->{type};
	return if $type ne 'PushEvent';
		# We are only interested in PushEvents
		# see https://docs.github.com/en/rest/using-the-rest-api/github-event-types?apiVersion=2022-11-28

	my $git_user = getPref('GIT_USER');

	my $time = $event->{created_at} || '';
	my $github_repo = $event->{repo} || '';
	my $repo_id = $github_repo->{name} || '';
	$repo_id =~ s/^$git_user\///;

	my $repo = getRepoById($repo_id) || '';
	my $repo_path = $repo ? $repo->{path} : '';

	my $payload = $event->{payload} || '';
	my $head = $payload ? $payload->{head} || '' : '';
	my $before = $payload ? $payload->{before} || '' : '';
	my $commits = $payload ? $payload->{commits} : '';

	return !repoError(undef,"Could not find repo($repo_id) in event($event_id)")
		if !$repo_path;

	return if !doRepoPath($repo_path);

	return repoError($repo,"No 'before' in event($event_id) path($repo_path)")
		if !$before;
	return repoError($repo,"No 'head' in event($event_id) path($repo_path)")
		if !$head;
	return repoError($repo,"No commits in event($event_id) path($repo_path)")
		if !$commits || !@$commits;

	repoDisplay($dbg_event+1,0,"commits for repo($repo_id=$repo_path) at $time");
	repoDisplay($dbg_event+1,1,"before=$before") if $before;

	$repo->{before} ||= $before;
	$repo->{commits} ||= shared_clone([]);

	# the head will always be the last commit in the commit list
	# repoDisplay(0,1,"head=$head") if $head;
	# checkEventCommit($repo,$head,'payload_head');

	my $last_commit = '';
	for my $commit (@$commits)
	{
		$last_commit= $commit->{sha} || '';
		my $msg = $commit->{message} || '';
		$msg =~ s/\n/ /g;
		$msg =~ s/\t/ /g;
		push @{$repo->{commits}},"$last_commit\t$msg";
		repoDisplay($dbg_event+1,2,pad($last_commit,42)._lim($msg,40));
	}

	return repoError($repo,"head($head)<>last_commit($last_commit) in event($event_id) path($repo_path)")
		if $last_commit ne $head;

	$repo->{last_commit} = $last_commit;
	return 1;

}




sub processEvents
	# events are from newest to oldest
	# commits are from oldest to newest
{
	my ($events) = @_;
	display(0,0,"processEvents()");
	my $repo_list = getRepoList();

	for my $repo (@$repo_list)
	{
		delete $repo->{commits};
		delete $repo->{before};
		delete $repo->{last_commit};
	}

	for my $event (reverse @$events)
	{
		oneEvent($event);
	}

	for my $repo (@$repo_list)
	{
		if ($repo->{before})
		{
			repoDisplay(0,0,"repo($repo->{path} before=$repo->{before}");
			checkEventCommit($repo,$repo->{before},'before');
			for my $commit (@{$repo->{commits}})
			{
				my ($sha,$msg) = split(/\t/,$commit);
				repoDisplay(0,1,pad($sha,42)._lim($msg,40));
				checkEventCommit($repo,$sha,$msg);
			}
		}
	}
}


sub addEventCommitText
{
	my ($ptext,$repo,$sha,$id) = @_;
	my $repo_sha = $repo->{$id};
	if ($repo_sha eq $sha)
	{
		$$ptext .= ' ' if $$ptext;
		$$ptext .= uc($id);
		return 1;
	}
	return 0;
}



sub checkEventCommit
{
	my ($repo,$sha,$msg) = @_;
	my $text = '';

	addEventCommitText(\$text,$repo,$sha,'head_id');
	addEventCommitText(\$text,$repo,$sha,'master_id');
	addEventCommitText(\$text,$repo,$sha,'remote_id');

	warning(0,2,"$repo->{path} $text == "._lim($msg,30)) if $text;
}





sub initEventMonitor
{
	display(0,0,"initEventMonitor()");
	my $git_user = getPref('GIT_USER');
	my $etag = '';
	my $events = gitHubRequest('events',"users/$git_user/events?per_page=100",0,undef,\$etag);
	display(0,1,"initial etag=$etag");
	return '' if !$etag;
	return '' if !processEvents($events);
	return $etag;
}

sub checkEvents
{
	my ($petag) = @_;
	display(0,0,"checkEvents($$petag)");
	my $git_user = getPref('GIT_USER');
	my $events = gitHubRequest('events',"users/$git_user/events?per_page=30",0,undef,$petag);
	display(0,1,"new etag=$$petag  events="._def($events));
	return 0 if !$events;
	return $events if !ref($events);
		# return the 304 from gitHubRequest()
	return 0 if !proceessEvents($events);
	return 1;
}




#----------------------------------------------
# main
#----------------------------------------------

sub showChanges
{
	my ($repo) = @_;
	gitChanges($repo);
	my $unstaged_changes = keys %{$repo->{unstaged_changes}};
	my $staged_changes = keys %{$repo->{staged_changes}};
	my $remote_changes = keys %{$repo->{remote_changes}};
	display(0,0,"unstaged($unstaged_changes) staged($staged_changes) remote($remote_changes)");
}

sub showBranches
{
	my ($git_repo) = @_;
	my @branch_refs = $git_repo->branches( 'all' );
	for my $branch_ref (@branch_refs)
	{
		my $commit = $branch_ref->target();
		$commit = $commit->peel('commit')
			if ref($commit) =~ /Git::Raw::Reference/;
		my $branch_name = $branch_ref->name();
		display(0,0,"branch($branch_name)=$commit");
	}
}




if (parseRepos())
{
	if (0)
	{
		my $repo_list = getRepoList();
		for my $repo (@$repo_list)
		{
			next if !doRepoPath($repo->{path});
			display(0,0,"repo($repo->{path})  branch=$repo->{branch}");

			showChanges($repo) if 1;

			my $git_repo = Git::Raw::Repository->open($repo->{path});
			my $detached = $git_repo->is_head_detached();
			repoError($repo,"DETACHED HEAD") if $detached;

			showBranches($git_repo) if 1;
			addHeadHistory($repo,$git_repo) if 1;;
		}
	}

	if (1)
	{
		my $repo_list = getRepoList();
		for my $repo (@$repo_list)
		{
			next if !doRepoPath($repo->{path});
			addHeadHistory($repo);
		}
	}


	if (1)
	{
		my $etag = initEventMonitor();
		if ($etag)
		{
			my $sleep_time = $SLEEP_AFTER_INIT;
			while (1)
			{
				display(0,0,"sleeping $sleep_time seconds");
				sleep($sleep_time);
				my $rslt = checkEvents(\$etag);
				last if !$rslt;
				$sleep_time = $rslt == 304 ?
					$SLEEP_AFTER_304 :
					$SLEEP_AFTER_GET;
			}
		}
	}
}

1;
