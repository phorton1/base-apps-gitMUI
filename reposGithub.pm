#----------------------------------------------------
# call github APIs to flesh out repos
#----------------------------------------------------

package apps::gitUI::reposGithub;
use strict;
use warnings;
use threads;
use threads::shared;
use JSON;
use Data::Dumper;
use HTTP::Request;
use LWP::UserAgent;
use LWP::Protocol::http;
use Mozilla::CA;
use Pub::Utils;
use Pub::Prefs;
use apps::gitUI::utils;
use apps::gitUI::repo;
use apps::gitUI::repos;
use apps::gitUI::repoGit;


$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;
	# use fixed size indents and sort hash keys

my $USE_TEST_CACHE = 0;

my $dbg_github = 0;
	# 0 = show major validation steps
	# -1 = show validation details
my $dbg_request = 0;
	# 0 = show gitHubRequest() calls
	# -1 = show gitHubRequest() details

my $GET_GITHUB_FORK_PARENTS = 1;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		doGitHub
	);
}



#----------------------------------------------------
# github access
#----------------------------------------------------
# Using paged requests requires an all or none approach
# to deleting cachefiles.

sub gitHubRequest
	# if $ppage is specified it will contain the page number to get
	# and will be appended to the location as '&page=$$ppage' and
	# the cachefile as '_$$page'.
{
    my ($what,$location,$use_cache,$ppage,$petag) = @_;
	$use_cache ||= 0;

	my $use_page = $ppage ? $$ppage : '';
	$location .= "&page=$use_page" if $use_page;
	my $cache_page = $use_page ? "_$use_page" : '';

	repoDisplay($dbg_request,0,"gitHubRequest($what$cache_page,$location) use_cache($use_cache)");

	my $cache_filename = "$temp_dir/$what$cache_page.txt";
	my $content = $use_cache || $USE_TEST_CACHE ?
		getTextFile($cache_filename) : '';
	my $from_cache = $content ? 1 : 0;

	# if using the cache and we get a hit, we have to check for
	# the next page and return that. Remember all or none on delete
	# of the repo_N cache files.

    if ($content)
	{
		repoDisplay($dbg_request,1,"found cachefile($cache_filename) in cache");
		if ($ppage)
		{
			my $next_filename = "$temp_dir/$what"."_".($$ppage+1).".txt";
			if (-f $next_filename)
			{
				$$ppage = $$ppage + 1;
				repoDisplay($dbg_request,1,"found next page($$ppage) in cache");
			}
		}
	}
	else
	{
		my $git_user = getPref("GIT_USER");
		my $git_api_token = getPref("GIT_API_TOKEN");
		my $url = 'https://api.github.com/' . $location;

		# display(0,0,"git_user($git_user) api_token($git_api_token)");

		my $request = HTTP::Request->new(GET => $url);
		$request->content_type('application/json');
		$request->authorization_basic($git_user,$git_api_token);

		if ($petag && $$petag)
		{
			display(0,1,"setting etag headers");
			$request->header('If-None-Match' => $$petag);
			# $request->header('X-Poll-Interval' => 60);
		}


		# unused REQUEST CONTENT
		# my $request_data = '';
		# my $json = encode_json($request_data);
		# $request->content($json);

		# DO THE REQUEST

		my $my_ua = new LWP::UserAgent (agent => 'Mozilla/5.0', cookie_jar =>{});
		$my_ua->ssl_opts( SSL_ca_file => Mozilla::CA::SSL_ca_file() );
		$my_ua->ssl_opts( verify_hostname => 1 );

		if ($what eq 'events')
		{
			my $req_headers = $request->headers_as_string()."\n";
			print "REQUEST_HEADERS=$req_headers";
		}

		my $response = $my_ua->request($request);

		if (!$response)
		{
			repoError(undef,"gitHubRequest($location) - no response");
		}
		else
		{
			my $status_line = $response->status_line();
			my $etag = $response->headers()->header('Etag') || '';
			$$petag = $etag if $etag;


			repoDisplay($dbg_request+1,1,"response = $status_line");
			if ($what eq 'events' && $status_line =~ /304/)
			{
				repoDisplay(0,1,"returning [] for 304 for events");
				return [];
			}
			elsif ($status_line !~ /200/)
			{
				repoError(undef,"gitHubRequest($location) bad_status: $status_line");
			}
			else
			{
				# check for the 'Link' header which indictes that more gets are needed,
				# and return it in the case of doing the main repos list ...

				if ($what eq 'events')
				{
					my $headers = $response->headers_as_string()."\n";
					print "RESPONSE_HEADERS=$headers";
					printVarToFile(1,"$temp_dir/$what.headers.txt",$headers,1);
				}

				if ($ppage)
				{
					my $link = $response->headers()->header('Link') || '';
					# Link: <https://api.github.com/user/repos?per_page=50&page=2>; rel="next", <https://api.github.com/user/repos?per_page=50&page=2>; rel="last"
					# repoDisplay(0,0,"link=$link");
					if ($link =~ /&page=(\d+)>; rel="next"/)
					{
						$$ppage = $1;
						repoDisplay($dbg_request,1,"next_page=$$ppage");
					}
				}

				$content = $response->content() || '';
				my $content_type = $response->headers()->header('Content-Type') || 'unknown';
				my $content_len = length($content);
				repoDisplay($dbg_request+1,1,"content bytes($content_len) type=$content_type");
				if (!$content)
				{
					repoError(undef,"gitHubRequest($location) - no content returned");
				}
				elsif ($response->headers()->header('Content-Type') !~ 'application/json')
				{
					printVarToFile(1,"$temp_dir/$what.error.txt",$content);
					repoError(undef,"gitHubRequest($location) unexpected content type: $content_type; see $temp_dir/$what.error.txt");
					$content = '';
				}
				else
				{
					printVarToFile(1,$cache_filename,$content) if $content;
				}

			}	# good 200 status line
 		}	# got a response
	}	# try to get $content from github

	# got something to decode

	if ($content)
	{
		my $rslt = decode_json($content);
		if (!$rslt)
		{
			repoError(undef,"gitHubRequest($location) could not json_decode");
		}
		else
		{
			if (!$from_cache)
			{
				my $text = '';
				my @lines = split(/\n/,Dumper($rslt));
				for my $line (@lines)
				{
					chomp($line);
					$line =~ s/\s*$//;
					$text .= $line."\n";
				}
				printVarToFile(1,"$temp_dir/$what$cache_page.json.txt",$text);
			}

			return $rslt;

		}	# decoded json
	}   # got $content

	return undef;

}	# gitHubRequest()





#-----------------------------------------------
# validate versus github
#-----------------------------------------------

sub doGitHub
{
	my ($use_cache,$validate_configs) = @_;
	$use_cache ||= 0;
	$validate_configs ||= 0;

    repoDisplay($dbg_github,0,"doGitHub($use_cache,$validate_configs)");

	my $repo_list = getRepoList();
	if (!$repo_list)
	{
		error("No repo_list in doGitHub!!");
		return;
	}

	for my $repo (@$repo_list)
	{
		$repo->{found_on_github} = 0;
			# retain {errors} from parseRepos, which
			# is always called just before doGithub()
			# (they are always paired).
			# $repo->clearErrors();
		$repo->checkGitConfig();
			# Currently only place checkGitConfig() is called
			# ignore return value
	}



	my $page = 0;
	my $next_page = 1;
	while ($page != $next_page)
	{
		$page = $next_page;
		my $data = gitHubRequest("repos","user/repos?per_page=50",$use_cache,\$next_page);
		last if !$data;

        # returns an array of hashes (upto 100)
        # prh - will need to do it multiple times if I get more than 100 repositories

        repoDisplay($dbg_github,1,"found ".scalar(@$data)." github repos on page($page)");

        for my $entry (@$data)
        {
            my $id = $entry->{name};
            my $path = repoIdToPath($id);
			my $repo = getRepoHash()->{$path};

			next if $TEST_JUNK_ONLY && $path !~ /junk/;

			if (!$repo)
			{
				repoError(undef,"doGitHub() cannot find repo($id) = path($path)");
			}
			else
			{
				$repo->{found_on_github} = 1;
				$repo->{size} = $entry->{size} || 0;
				$repo->{descrip} = $entry->{description} || '';
				my $is_private = $entry->{visibility} eq 'private' ? 1 : 0;
				my $is_forked = $entry->{fork} ? 1 : 0;
				my $repo_forked = $repo->{forked} ? 1 : 0;

				repoDisplay($dbg_github+1,1,"doGitHub($id) private($is_private) forked($is_forked)");

				$repo->repoError("validateGitHub($id) - local private($repo->{private}) != github($is_private)")
					if $repo->{private} != $is_private;
				$repo->repoError("validateGitHub($id) - local forked($repo_forked) != github($is_forked)")
					if $repo_forked != $is_forked;

				# if it's forked, do a separate request to get the parent information

				if ($GET_GITHUB_FORK_PARENTS && $is_forked)
				{
					my $git_user = getPref("GIT_USER");
					my $info = gitHubRequest($id,"repos/$git_user/$id",$use_cache);
					if (!$info)
					{
						$repo->repoError("doGitHub($id) - could not get forked repo");
					}
					elsif (!$info->{parent})
					{
						$repo->repoError("doGitHub($id) - no parent for forked repo");
					}
					elsif (!$info->{parent}->{full_name})
					{
						$repo->repoWarning(0,2,"doGitHub($id) - No parent->full_name for forked repo");
					}
					else
					{
						$repo->{parent} = $info->{parent}->{full_name};
						repoDisplay($dbg_github,2,"fork parent = $repo->{parent}");
					}

				}   # $GET_GITHUB_PARENTS


				# IF my description includes "Copied from blah [space],
				# parent contents will be displayed (blah) as a reminder
				# of where i got it

				elsif ($entry->{description} &&
					   $entry->{description} =~ /Copied from (.*?)\s/i)
				{
					my $parent = $1;
					$parent =~ s/https:\/\/github.com\///;
					$entry->{parent} = "($parent)";
				}

			} 	# found $repo
        }   # foreach $entry
    }   # while $page

	for my $repo (@$repo_list)
	{
		# submodules (rel_path} are allowed to exist without
		# an explicit repo on git hub.  This whole thing is messy

		$repo->repoError("repo($repo->{id} not found on github!")
			if !$repo->{rel_path} && !$repo->{found_on_github};
	}


	# get the head commits and determine if we are at behind by at least 1

	# updateHeadCommits($use_cache);



}   #   getGitHubRepos()




#-----------------------------------------------
# updateHeadCommits
#-----------------------------------------------

my $DO_ALL = 1;


# We care about X-Poll-Interval and ETag headers.
#
# We should not make an events request more often than X-Poll-Interfaal seconds
#
# By passing the ETag header back in, we will only get new events,
# and will get a 304 response (not modified) if there are no new
# events.
#
# We can use pages to get more than the default of 30 events at a time.
#
# To implement this somewhat correctly we need an ACTUAL CACHE file for
# the repos or we might miss events.  In addition, we need to bootstrap
# the cachefile the hard way, I think, with a fetch on every repo.
#
# With event tracking, we can determine that we are NOT BEHIND and
# that we are AHEAD, without having to do a fetch, much less a fetch on
# every repository.
#
# We know one other 'fact' that can help in initializing the cache file.
# After a successful push-all, we can get the heads from git.   Or, for
# that matter, we can use whatever technique we use to get the history to
# initialize the repo.
#
# This scheme will implicitly assume that we are only using one branch,
# as specified in git_repositories.txt.

use apps::gitUI::repoHistory;


sub updateHeadCommits()
{
	my ($use_cache) = @_;
	$use_cache ||= 0;
	repoWarning(undef,0,0,"updateHeadCommits($use_cache)");

	# time how long it takes to get all repos histories

	if (0)
	{
		my $repo_list = getRepoList();
		for my $repo (@$repo_list)
		{
			my $history = gitHistory($repo,1);
		}
		repoWarning(undef,0,0,"got all histories");
		return;
	}

	my $git_user = getPref('GIT_USER');
	my $events = gitHubRequest('events',"users/$git_user/events",0); #$use_cache);
	return if !$events;
	for my $event (@$events)
	{
		oneEvent($event);
	}
}

sub oneEvent
{
	my ($event) = @_;

	my $git_user = getPref('GIT_USER');

	my $time = $event->{created_at} || '';
	my $github_repo = $event->{repo} || '';
	my $repo_id = $github_repo->{name} || '';
	$repo_id =~ s/^$git_user\///;

	my $payload = $event->{payload} || '';
	my $before = $payload ? $payload->{before} || '' : '';
	my $head = $payload ? $payload->{head} || '' : '';

	my $repo = getRepoById($repo_id) || '';
	my $repo_path = $repo ? $repo->{path} : '';

	return if !$DO_ALL && $repo_path !~ /\/data$|\/data_master$/;

	repoError(undef,"Could not find repo($repo_id)") if !$repo_path;

	repoDisplay(0,0,"commits for repo($repo_id=$repo_path) at $time");
	repoDisplay(0,1,"head=$head") if $head;
	repoDisplay(0,1,"before=$before") if $before;

	if ($repo)
	{
		warning(0,1,"before=repo->{remote_id}")
			if ($before eq $repo->{remote_id});
	}

	my $commits = $payload ? $payload->{commits} : '';
	if ($commits && @$commits)
	{
		for my $commit (@$commits)
		{
			my $sha = $commit->{sha} || '';
			my $msg = $commit->{message} || '';
			repoDisplay(0,2,pad($sha,42)._lim($msg,60));
		}
	}
}




use Git::Raw;


sub addHistoryFields
	# opening a repo is relatively quick
{
	my ($repo) = @_;
	my $path = $repo->{path};
	my $branch = $repo->{branch};
	display(0,0,"addHistoryFields($path) branch=$branch");

	if (0)
	{
		gitChanges($repo);
		my $unstaged_changes = keys %{$repo->{unstaged_changes}};
		my $staged_changes = keys %{$repo->{staged_changes}};
		my $remote_changes = keys %{$repo->{remote_changes}};
		display(0,1,"unstaged($unstaged_changes) staged($staged_changes) remote($remote_changes)");
	}

	my $git_repo = Git::Raw::Repository->open($path);
	my $detached = $git_repo->is_head_detached();
	error("DETACHED HEAD") if $detached;

	# I typically get three branches from my repos:
	#
	#	branch(refs/heads/$branch)=e7aa555ed30e050ef81782723cf5d0753789ae6e
	#	branch(refs/remotes/origin/HEAD)=e7aa555ed30e050ef81782723cf5d0753789ae6e
	#	branch(refs/remotes/origin/$branch=e7aa555ed30e050ef81782723cf5d0753789ae6e
	#
	# because I always check into the default branch on gitup
	# refs/remotes/origin/HEAD should always == refs/remotes/origin/$branch,
	# even if they are both out of date on the local machine.
	#
	# The only time refs/heads/$branch should be different than refs/remotes/origin/$branch
	# is when I have made a commit locally and not pushed it (local is AHEAD), or if I am in the
	# middle of updating a submodule (i.e. I have fetched, but not yet pulled or rebased
	# (local is BEHIND).

	if (0)
	{
		my @branch_refs = $git_repo->branches( 'all' );
		for my $branch_ref (@branch_refs)
		{
			my $commit = $branch_ref->target();
			$commit = $commit->peel('commit')
				if ref($commit) =~ /Git::Raw::Reference/;
			my $branch_name = $branch_ref->name();
			display(0,1,"branch($branch_name)=$commit");
		}
	}

	# I am so struggling to understand this.
	#
	# If local HEAD != refs/heads/$branch it basically means that I have commits that
	# are not to the repo's specified $branch, and something is out of whack.  Very
	# rarely I *might* have to deal with multiple branches, but by and large I ONLY
	# use the default branch of my repos.

	# I guess what I am trying to do is keep track of the history and analyze needed
	# merges, in terms of unstaged_changes, AHEAD and BEHIND, without having to do
	# a fetch, or modify anything in my local repositories.

	# However, this amounts to me building, and caching, the entire history of
	# every repo.  If I KNOW that the system is completely stable, then I COULD,
	# I suppose, and then mark that with an ETag (that I pass back to the event
	# to only get changes AFTER that).

	# the whole notion of determining AHEAD and BEHIND relies on having a common
	# starting position, and then monitoring events to add pushes to the remote.
	# I have to remember how to get refs

	my $head_commit = Git::Raw::Reference->lookup("HEAD", $git_repo)->peel('commit') || '';
	display(0,1,"head_id="._def($head_commit));

	my $master_commit = Git::Raw::Reference->lookup("refs/heads/$branch", $git_repo)->peel('commit') || '';
	display(0,1,"master_id="._def($master_commit));

	my $remote_commit = Git::Raw::Reference->lookup("remotes/origin/$branch", $git_repo)->peel('commit') || '';
	display(0,1,"remote_id="._def($remote_commit));

	my $head_id = "$head_commit";
	my $master_id = "$master_commit";
	my $remote_id = "$remote_commit";

	$repo->{head_id} = $head_id;
	$repo->{master_id} = $master_id;
	$repo->{remote_id} = $remote_id;

	if (0)
	{
		error("repository($path) has uncommited changes")
			if $head_id ne $master_id;
		error("repository($path) has unpushed commits")
			if $master_id ne $remote_id;
	}

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

		$head_id_found ||= addFound(\$msg,$id,$head_id,'HEAD');
		$master_id_found ||= addFound(\$msg,$id,$master_id,'MASTER');
		$remote_id_found ||= addFound(\$msg,$id,$remote_id,'REMOTE');

		display(0,2,"$time ".pad($msg,20)."$id == "._lim($summary,20));

		$repo->{history} ||= shared_clone([]);
		push @{$repo->{history}},shared_clone({
			id => $id,
			summary => $summary,
			time => $time,
			msg => $msg,
		});

		$com = $log->next();
	}



	# my $refspec_str = "refs/heads/$branch";
	# my $refspec = Git::Raw::RefSpec->parse($refspec_str,0);
	# display(0,1,"refspec=$refspec");

	# my $history = gitHistory($repo,1);
}


sub addFound
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







sub addAllHistoryFields
{
	repoDisplay(0,0,"addAllHistoryFields()");
	my $repo_list = getRepoList();
	for my $repo (@$repo_list)
	{
		addHistoryFields($repo)
			if $DO_ALL || $repo->{path} =~ /\/data$|\/data_master$|\/site\/myIOT$/;
	}
	repoDisplay(0,0,"addAllHistoryFields() finished");
	return;
}



sub checkSubmodules
{
	repoDisplay(0,0,"checkSubmodules()");
	my $repo_list = getRepoList();
	for my $repo (@$repo_list)
	{
		if (@{$repo->{used_in}})
		{
			next if !$DO_ALL && $repo->{path} !~ /\/data$|\/data_master$/;
			repoDisplay(0,1,"checking used_in for $repo->{path}");
			for my $sub_path (@{$repo->{used_in}})
			{

				my $sub_repo = getRepoByPath($sub_path);
				return repoError($repo,"Could not find used_in($sub_path)")
					if !$sub_repo;
				repoDisplay(0,2,"used in $sub_path");
				error("sub_repo master_id "._def($sub_repo->{master_id})." <> "._def($repo->{master_id}))
					if $sub_repo->{master_id} ne $repo->{master_id};
			}
		}
	}
	repoDisplay(0,0,"addAllHistoryFields() finished");
	return;
}



#----------------------------------------------
# test main (for sanity)
#----------------------------------------------

sub initEventMonitor
{
	display(0,0,"initEventMonitor()");
	my $git_user = getPref('GIT_USER');
	my $etag = '';
	my $events = gitHubRequest('events',"users/$git_user/events",0,undef,\$etag);
	display(0,1,"etag=$etag");
	return $etag;
}

sub checkEvents
{
	my ($petag) = @_;
	display(0,0,"checkEvents($$petag)");
	my $git_user = getPref('GIT_USER');
	my $events = gitHubRequest('events',"users/$git_user/events",0,undef,$petag);
	display(0,1,"new etag=$$petag");
	return 0 if !$events;
	for my $event (@$events)
	{
		oneEvent($event);
	}
	return 1;
}




if (1)
{
	if (parseRepos())
	{
		addAllHistoryFields();
		# checkSubmodules();
		# updateHeadCommits();

		my $etag = initEventMonitor();
		while (1)
		{
			sleep(65);
			last if !checkEvents(\$etag);
		}
	}
}



1;
