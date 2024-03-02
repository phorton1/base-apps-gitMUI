#----------------------------------------------------
# call github APIs to flesh out repos
#----------------------------------------------------

package apps::gitUI::reposGithub;
use strict;
use warnings;
use threads;
use threads::shared;
use JSON;
use Git::Raw;
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
# to deleting cachefiles.  $use_cache should be set to
# zero for $what == 'events'.

sub gitHubRequest
	# if $ppage is specified it will contain the page number to get
	# and will be appended to the location as '&page=$$ppage' and
	# the cachefile as '_$$page'.
	#
	# $petag is an input-output variable for $what == 'events'.
	#
	# if $petag is provided, a 'If-None-Match' header will be
	# added to the request as per the github event api standard,
	# to only return content if there are new pushes (events)
	# since we last got the ETag header.
	#
	# if $petag and the response contains an ETag header, the
	# value of the etag (with included quotes) will be returned
	# in $$petag.
	#
	# if $petag and we receive a 304 (not modified) response,
	# this method returns [] indicating there were no new events.
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

		if (0 && $what eq 'events')
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
					print "RESPONSE_HEADERS=$headers" if 0;
					printVarToFile(1,"$temp_dir/$what.headers.txt",$headers,1);
				}

				if ($ppage)
				{
					my $link = $response->headers()->header('Link') || '';
					# Link: <https://api.github.com/user/repos?per_page=50&page=2>; rel="next",
					#	    <https://api.github.com/user/repos?per_page=50&page=2>; rel="last"
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
					repoError(undef,"gitHubRequest($location) unexpected content type: $content_type; ".
							  "see $temp_dir/$what.error.txt");
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
		# $repo->clearErrors();
			# retain {errors} from parseRepos, which
			# is always called just before doGithub()
			# (they are always paired).
		$repo->{found_on_github} = 0;
		$repo->checkGitConfig();
			# Of questionable value, this is currently the only place
			# checkGitConfig() is called. We ignore any return value.
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
				# parent contents will display (blah) as a reminder
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
		# an explicit repo on git hub.

		$repo->repoError("repo($repo->{id} not found on github!")
			if !$repo->{rel_path} && !$repo->{found_on_github};

		# initial check for submodules out of date

		checkSubmodules($repo);
	}
}   #   doGitHub()




#-----------------------------------------------
# History, events, and change detection
#-----------------------------------------------
# The experimental methods in this section try to accomplish
# several goals.
#
# We use the github events API on a thread to detect pushes
# to github that might take place on other machines, or from
# other submodules on the same machine, and if so, determine
# whether the local repo is AHEAD and or BEHIND,
# which, along with HAS_CHANGES, which is set if the repo has
# any uncommitted (unstaged or staged) changes determines whether
# we can automatically Update the repo(s) and if so, whether we
# would need a Stash to do so.
#
# The system does not handle repos that require Merges, that
# is, where commits to the same repo HEAD revision of a repo
# have been made from two different machines, or submodules
# on the same machine.
#
# We try to do all of this in a performant manner (i.e. quickly).
#
# The case of normalizing submodules locally can additionally
# detect not only if there pushes have occured and Updates
# are needed, but can detect denormalization due to uncommitted
# changes and commits before they are pushed.
#
# CHANGE DETECTION WITHOUT FETCHING
#
# Proper detection and implementation of repo normalization
# requires a somewhat complicated comparison of the two repo's histories,
# finding the most recent common ancestor, and then counting the
# commits after that for each repo, something that git is good
# at, to the degree that you first 'fetch' the the (remote) repo
# and then use standard git commands to identify and/or update-merge
# the two repos.
#
# However, I want this process to work without making ANY changes
# to the local machine. Once you do a Fetch you can find yourself
# in a situation where you MUST merge two repos with disparate
# changes, itself a complicated process that can backfire.
#
# What I am looking for is a way to determine if a repo is out
# of date with respect to the remote, and if I can SAFELY
# Fetch and Update it, possibly with a Stash, automatically.
# Thus I want it to detect whether a Merge would be needed,
# and to notify me about that.
#
# This can sort-of be done by gathering key commit identifiers,
# SHA's, from the local repos, which can be done relatively
# quickly, and then, by using a cache and github events,
# compared to the remote (github) repository for change detection.
#
# KEY COMMIT ID'S
#
# For each I get the following commit ids:
#
#		head_id = HEAD - the commit the repo is at
#		master_id = refs/heads/$branch - the most recent commit in the main branch
#		remote_id = refs/remotes/origin/$branch - the last sync with github
#
# Invariants:
#
# 	Because I always check into the default branch on gitup
# 	I don't need to additionally get the refs/remotes/origin/HEAD
#	commit id, as it should always be the same as the
#	refs/remotes/origin/$branch id, even if they both happen
#	to be out of date on the local machine.
#
#	When my system is in a stable state, i.e. I am not in the middle
#   of doing an Update (Fetch, possible Stash, and then Pull or Rebase),
#   then head_id should always equal the master_id. That is to say that
#   the HEAD commit should always be the same as the $branch commit
#   in any repos.
#
#	This last one is furthered by the fact that my repos should NEVER
#   have a Detached HEAD, that is a repo that is not checked out to the
#   main $branch.  This can occur (early) in submodule development when
#   cloning a new submodule, care must be taken to make sure that it is
#	checked out to the main $branch.
#
# We can use the existing gitChanges() and the new head_id to quickly
# determine when submodules are denormalized.  These id's will need to
# be updated locally in gitPush() and gitComit() after the system is
# initialized (scanned).
#
# GITHUB EVENTS
#
# The github event API will give us a list of the most recent pushes
# to github, along with the repo paths and commit_ids in those pushes.
# The event history goes back a maximum of 90 days.
#
# It is **safe** to assume that if a repo has not been pushed in
# a long time, that I have the current version on the local machine,
# i.e. BEHIND === 0
#
# At this point I need to switch to experimental code to continue.
# It seems like, especially since I will be in a thread, that I
# can analyze every push event and use the local git history to
# determine the most recent common ancestor and the AHEAD and
# BEHIND numbers.

my $DO_ALL = 1;

my $dbg_head_commits = 0;
my $dbg_head_history = 0;

sub doRepoPath
{
	my ($path) = @_;
	return 1 if $DO_ALL || $path =~ /\/data$|\/data_master$|\/site\/myIOT$/;
	return 0;
}


sub addHeadCommits
{
	my ($repo,$git_repo) = @_;
	$git_repo ||= Git::Raw::Repository->open($repo->{path});
	my $branch = $repo->{branch};
	display($dbg_head_commits,0,"addHeadCommits($repo->{path})");

	my $head_commit = Git::Raw::Reference->lookup("HEAD", $git_repo)->peel('commit') || '';
	display($dbg_head_commits,1,"head_id="._def($head_commit));

	my $master_commit = Git::Raw::Reference->lookup("refs/heads/$branch", $git_repo)->peel('commit') || '';
	display($dbg_head_commits,1,"master_id="._def($master_commit));

	my $remote_commit = Git::Raw::Reference->lookup("remotes/origin/$branch", $git_repo)->peel('commit') || '';
	display($dbg_head_commits,1,"remote_id="._def($remote_commit));

	my $head_id = "$head_commit";
	my $master_id = "$master_commit";
	my $remote_id = "$remote_commit";

	$repo->{head_id} = $head_id;
	$repo->{master_id} = $master_id;
	$repo->{remote_id} = $remote_id;

	return $git_repo;
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

	return if !doRepoPath();

	repoError(undef,"Could not find repo($repo_id)") if !$repo_path;

	repoDisplay(0,0,"commits for repo($repo_id=$repo_path) at $time");
	repoDisplay(0,1,"head=$head") if $head;
	repoDisplay(0,1,"before=$before") if $before;

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



if (0)
{
	if (parseRepos())
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
			addHeadCommits($repo,$git_repo);
			addHeadHistory($repo,$git_repo) if 1;;
		}

		if (1)
		{
			for my $repo (@$repo_list)
			{
				next if !doRepoPath($repo->{path});
				checkSubmodules($repo);
			}
		}

		if (0)
		{
			my $etag = initEventMonitor();
			while (1)
			{
				sleep(65);
				last if !checkEvents(\$etag);
			}
		}
	}
}














1;
