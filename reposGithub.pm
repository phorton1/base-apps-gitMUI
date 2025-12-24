#----------------------------------------------------
# call github APIs to flesh out repos
#----------------------------------------------------

package apps::gitMUI::reposGithub;
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
use apps::gitMUI::utils;
use apps::gitMUI::repo;
use apps::gitMUI::repos;
use apps::gitMUI::repoGit;
use apps::gitMUI::monitor;


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
		gitHubRequest
	);
}

my $event_thread;



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
	# this method returns a scalar 304 indicating there were no
	# new events.
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

		my $my_ua = new LWP::UserAgent (
			agent => 'Mozilla/5.0',
			cookie_jar =>{});
		$my_ua->timeout(15);
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
			my $show_rate = $response->header('X-RateLimit-Remaining') || '';

			my $etag = $response->headers()->header('Etag') || '';
			$$petag = $etag if $etag;

			repoDisplay($dbg_request+1,1,"response = $status_line");
			repoDisplay($dbg_request,1,"rate remaining=$show_rate");

			if ($what eq 'events' && $status_line =~ /304/)
			{
				repoDisplay(0,1,"returning [] for 304 for events");
				return 304;
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
					# print "RESPONSE_HEADERS=$headers";
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
# doGitHub()
#-----------------------------------------------


sub doGitHub
{
	my ($use_cache) = @_;
	$use_cache ||= 0;

    repoDisplay($dbg_github,0,"doGitHub($use_cache)");

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
	}

	my $page = 0;
	my $next_page = 1;
	my $total_size = 0;
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
			$total_size += $entry->{size};
			my $found_local = 0;

			my $parent = '';
			if ($GET_GITHUB_FORK_PARENTS && $entry->{fork})
			{
				my $git_user = getPref("GIT_USER");
				my $info = gitHubRequest($id,"repos/$git_user/$id",$use_cache);
				if (!$info)
				{
					repoError(undef,"doGitHub($id) - could not get forked repo");
				}
				elsif (!$info->{parent})
				{
					repoError(undef,"doGitHub($id) - no parent for forked repo");
				}
				elsif (!$info->{parent}->{full_name})
				{
					repoWarning(undef,0,2,"doGitHub($id) - No parent->full_name for forked repo");
				}
				else
				{
					$parent = $info->{parent}->{full_name};
					repoDisplay($dbg_github,2,"fork parent = $parent");
				}
			}


			for my $repo (@$repo_list)
			{
				next if $repo->{id} ne $id;
				$repo->{exists} |= $REPO_REMOTE;
				oneRepoEntry($id,$entry,$repo,$parent);
				$found_local = 1;
			}

			# 2025-12-23 Don't add remoteOnly repos from github if $SUBSET
			
			if (!$found_local)
			{
				if ($SUBSET)
				{
					repoDisplay($dbg_github,0,"skipping SUBSET($SUBSET) remoteOnlyRepo($entry->{name})");
				}
				else
				{
					my $dbg_num = scalar(@$repo_list);
					repoDisplay($dbg_github,0,"creating remoteOnlyRepo($dbg_num,$entry->{name})");

					my $repo = apps::gitMUI::repo->new({
						where => $REPO_REMOTE,
						id => $id,
						section_id => 'danglingRepos',
						section_path => 'danglingRepos', });

					next if !$repo;

					$repo->repoError("dangling gitHub repo does not exist locally!!");
					oneRepoEntry($id,$entry,$repo,$parent);
					addRepoToSystem($repo);
				}
			}	# !$found_local
        }   # foreach $entry
    }   # while $page

	for my $repo (@$repo_list)
	{
		# explicit local_only repos and
		# submodules (rel_path} are allowed to exist without
		# an explicit repo on git hub.

		$repo->repoWarning(0,0,"repo not found on github!")
			if $repo->{opts} !~ /$LOCAL_ONLY/ &&
			   !$repo->{rel_path} &&
			   ($repo->{exists} & $REPO_LOCAL) &&
			   !($repo->{exists} & $REPO_REMOTE);
	}

	display(0,-1,"doGitHub() total used on gitHub=".prettyBytes($total_size*1024));

}   #   doGitHub()




sub oneRepoEntry
{
	my ($id,$entry,$repo,$parent) = @_;

	my $is_forked = $entry->{fork} ? 1 : 0;
	my $is_private = $entry->{visibility} eq 'private' ? 1 : 0;
	my $default_branch = $entry->{default_branch} || '';

	$repo->{size} = $entry->{size} || 0;
	$repo->{default_branch} = $default_branch;
	$repo->{descrip} = $entry->{description} || '';

	if ($repo->{descrip} =~ /Copied from (.*?)\s/i)
	{
		$repo->repoNote($dbg_github,2,"Copied from $parent");
		$parent =~ s/https:\/\/github.com\///;
		$parent = "($parent)";
	}

	$repo->{parent} = $parent if $parent;

	if ($repo->isRemoteOnly())
	{
		$repo->{private} = 1 if $is_private;
		$repo->{forked} = 1 if $is_forked;
	}
	else
	{
		$repo->repoError("validateGitHub($id) - local private($repo->{private}) != github($is_private)")
			if $repo->{private} != $is_private;
		my $repo_forked = $repo->{forked} ? 1 : 0;
		$repo->repoError("validateGitHub($id) - local forked($repo_forked) != github($is_forked)")
			if $repo_forked != $is_forked;
	}

}




1;
