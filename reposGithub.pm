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


use Data::Dumper;
$Data::Dumper::Indent 	= 1;
$Data::Dumper::Sortkeys = 1;
	# use fixed size indents and sort hash keys
$Data::Dumper::Deepcopy	= 1;
$Data::Dumper::Terse	= 1;
	# get rid of removes $VAR1 =
$JSON::PP::true  = 1;
$JSON::PP::false = 0;
	# set json "true" to come out as 1, false as 0


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

		 $HOW_GITHUB_INIT 
         $HOW_GITHUB_NORMAL
         $HOW_GITHUB_REBUILD
	);
}

our $HOW_GITHUB_INIT = 0;		# use the cache with no network hits if possible
our $HOW_GITHUB_NORMAL = 1;		# network hit with Etag and 304 to use cache if possible
our $HOW_GITHUB_REBUILD = 2;	# destroy the cache and start over



sub getEtagFromHeaders
{
	my ($indent,$headers) = @_;
	for my $line (split(/\n/,$headers))
	{
		if ($line =~ /^ETag:\s*"(.*)"$/)
		{
			my $etag = $1;
			repoDisplay($dbg_request,$indent+1,"got etag=$etag");
			return $etag;
		}
	}
	return '';
}

sub getNextPageFromHeaders
{
	my ($indent,$headers) = @_;
	for my $line (split(/\n/,$headers))
	{
		if ($line =~ /^Link/)
		{
			if ($line =~ /&page=(\d+)>; rel="next"/)
			{
				my $next_page = $1;
				repoDisplay($dbg_request,$indent+1,"got next_page=$next_page");
				return $next_page;
			}
			return '';
		}
	}
	return '';
}



#----------------------------------------------------
# github access
#----------------------------------------------------


sub gitHubRequest
{
    my ($indent,$how,$what,$location,$ppage) = @_;

	my $use_page = $ppage ? $$ppage : '';
	$location .= "&page=$use_page" if $use_page;
	my $cache_page = $use_page ? "_$use_page" : '';

	repoDisplay($dbg_request,$indent,"gitHub($how,$what$cache_page,$location)");

	# build cache filenames and unlink them if $HOW_GITHUB_REBUILD

	my $cache_filename = "$temp_dir/$what$cache_page.txt";
	my $dbg_filename = "$temp_dir/$what$cache_page.json.txt";
	my $header_filename = "$temp_dir/$what$cache_page.headers.txt";
	my $error_filename = "$temp_dir/$what$cache_page.error.txt";

	if ($how == $HOW_GITHUB_REBUILD)	# destroy the cache
	{
		unlink $cache_filename;
		unlink $dbg_filename;
		unlink $header_filename;
		unlink $error_filename;
	}

	# process vars
	# note that if the cache_filename exists, it is assumed
	# the header_filename also exists
	
	my $content = '';
	my $write_cache = 0;
	my $cache_exists = (-f $cache_filename) ? 1 : 0;
	my $headers = getTextFile($header_filename);

	# use cachefile without network hit if $HOW_GITHUB_INIT
	# otherwise do "normal" network hit trying Etag and 304 logic

	if ($cache_exists && $how == $HOW_GITHUB_INIT)
	{
		$content = getTextFile($cache_filename);
	}
	else
	{
		my $etag = getEtagFromHeaders($indent,$headers);

		# build the request

		my $git_user = getPref("GIT_USER");
		my $git_api_token = getPref("GIT_API_TOKEN");
		my $url = 'https://api.github.com/' . $location;

		my $request = HTTP::Request->new(GET => $url);
		$request->content_type('application/json');
		$request->authorization_basic($git_user,$git_api_token);
		$request->header('If-None-Match' => "\"$etag\"") if $etag;

		#--------------------------------
		# DO THE REQUEST
		#--------------------------------

		my $my_ua = new LWP::UserAgent (
			agent => 'Mozilla/5.0',
			cookie_jar =>{});
		$my_ua->timeout(15);
		$my_ua->ssl_opts( SSL_ca_file => Mozilla::CA::SSL_ca_file() );
		$my_ua->ssl_opts( verify_hostname => 1 );
		my $response = $my_ua->request($request);


		#--------------------------------
		# Process the response
		#--------------------------------

		my $cache_msg = $cache_exists ? "using cachefile" : "no cachefile";

		if (!$response)
		{
			repoError(undef,"gitHub($location) $cache_msg with no response");
			return undef if !$cache_exists;
			$content = getTextFile($cache_filename);
		}
		else
		{
			my $status_line = $response->status_line();
			my $show_rate = $response->header('X-RateLimit-Remaining') || '';
			repoDisplay($dbg_request+1,$indent+1,"response = $status_line");
			repoDisplay($dbg_request,$indent+1,"rate remaining=$show_rate");

			if ($status_line =~ /304/)
			{
				repoDisplay($dbg_request,$indent+1,"$cache_msg with 304 response");
				return undef if !$cache_exists;
				$content = getTextFile($cache_filename);
			}
			elsif ($status_line !~ /200/)
			{
				repoError(undef,"gitHub($location) $cache_msg  with bad_status: $status_line; see $error_filename");
				printVarToFile(1,$error_filename,$response->{content} || '');
				return undef if !$cache_exists;
				$content = getTextFile($cache_filename);
			}
			else
			{
				repoDisplay($dbg_request,$indent+1,"got 200 response");
				$content = $response->content() || '';
				my $content_type = $response->headers()->header('Content-Type');

				if ($content_type !~ 'application/json')
				{
					printVarToFile(1,$error_filename,$content);
					repoError(undef,"gitHub($location) unexpected content type: $content_type; $cache_msg; see $error_filename");
					return undef if !$cache_exists;
					$content = getTextFile($cache_filename);
				}
				elsif (!$content)
				{
					repoError(undef,"gitHub($location) - $cache_msg with no content returned");
					return undef if !$cache_exists;
					$content = getTextFile($cache_filename);
				}
				else
				{
					my $content_len = length($content);
					repoDisplay($dbg_request,$indent+1,"got content bytes($content_len) type=$content_type");
					$headers = $response->headers_as_string()."\n";
					$write_cache = 1;
					printVarToFile(1,"$header_filename",$headers,1);
					printVarToFile(1,"$cache_filename",$content,1);
				}
			}
		}
	}

	#----------------------------------------------
	# look for a page link and parse/cache the json
	#----------------------------------------------

	if ($ppage)
	{
		my $next_page = getNextPageFromHeaders($indent,$headers);
		$$ppage = $next_page if $next_page;
	}
	if ($content)
	{
		my $rslt = decode_json($content);
		if (!$rslt)
		{
			repoError(undef,"gitHub($location) could not json_decode");
		}
		elsif ($write_cache)
		{
			my $text = '';
			my @lines = split(/\n/,Dumper($rslt));
			for my $line (@lines)
			{
				chomp($line);
				$line =~ s/\s*$//;
				$text .= $line."\n";
			}
			printVarToFile(1,$dbg_filename,$text);
		}

		return $rslt;

	}	# decoded json

	return undef;

}	# gitHubRequest()




#-----------------------------------------------
# doGitHub()
#-----------------------------------------------
# Always called immediately repos::parseRepos(),
# $use_cache==0 allows the UI to wipe out the cache
# 	and start over.

sub doGitHub
{
	my ($how) = @_;

	my $git_user = getPref("GIT_USER");
    repoDisplay($dbg_github,0,"doGitHub($how) user($git_user)");

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
		repoWarning(undef,$dbg_github,1,"doGitHub getting page($next_page)");
		my $data = gitHubRequest(1,$how,"repos","user/repos?per_page=50",\$next_page);
		last if !$data;

        # returns an array of hashes (upto 100)
        # prh - will need to do it multiple times if I get more than 100 repositories

        repoDisplay($dbg_github,2,"found ".scalar(@$data)." github repos on page($page)");

        for my $entry (@$data)
        {
            my $id = $entry->{name};
			$total_size += $entry->{size};
			my $found_local = 0;

			my $parent = '';
			if ($GET_GITHUB_FORK_PARENTS && $entry->{fork})
			{
				my $info = gitHubRequest(2,$how,$id,"repos/$git_user/$id");
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
					repoWarning(undef,0,3,"doGitHub($id) - No parent->full_name for forked repo");
				}
				else
				{
					$parent = $info->{parent}->{full_name};
					repoDisplay($dbg_github,4,"fork parent = $parent");
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
					repoDisplay($dbg_github+1,2,"skipping SUBSET($SUBSET) remoteOnlyRepo($entry->{name})");
				}
				else
				{
					my $dbg_num = scalar(@$repo_list);

					repoDisplay($dbg_github+1,2,"creating dangling GitHub remoteOnlyRepo($dbg_num,$entry->{name})");

					my $repo = apps::gitMUI::repo->new({
						where => $REPO_REMOTE,
						id => $id,
						section_id => 'danglingRepos',
						section_path => 'danglingRepos', });

					# next if !$repo; # SHOULD NEVER HAPPEN

					repoError($repo,"dangling gitHub repo($entry->{name}) does not exist locally!!");
					oneRepoEntry($id,$entry,$repo,$parent);
					addRepoToSystem($repo);
				}
			}	# !$found_local
        }   # foreach $entry
    }   # while $page


	# the following loop gets SHA's which exist both locally and remotely
	# and identifies local repos that are missing on gitHub
	
	repoWarning(undef,$dbg_github,1,"doGitHub getting SHA's");
	for my $repo (@$repo_list)
	{
		if ($repo->{exists} & $REPO_LOCAL)
		{
			# if its on github get the current SHA info
			# or give an error if it does not exist on github

			if ($repo->{exists} & $REPO_REMOTE)
			{
				# GET https://api.github.com/repos/{owner}/{repo}/branches/master

				my $id = $repo->{id};
				my $branch = $repo->{branch};
				my $what = "sha_$id";
				my $data = gitHubRequest(1,$how,$what,"repos/$git_user/$id/branches/$branch");
				my $sha = $data->{commit}->{sha} || '';
				repoDisplay($dbg_github,3,"GITHUB_ID=$sha");
				$repo->{GITHUB_ID} = $sha;

				if ($repo->{GITHUB_ID} eq $repo->{REMOTE_ID})
				{
					if ($repo->{BEHIND})
					{
						repoWarning(undef,$dbg_github,4,"clearing BEHIND($id)=0");
							# note: undef prevents it from being added to the list of
							# warnings on the repo which is REALLY not what we want
							# for normal state changes
						$repo->{BEHIND} = 0;
					}
				}
				else
				{
					if (!$repo->{BEHIND})
					{
						repoWarning(undef,$dbg_github,4,"setting BEHIND($id)=1");
						$repo->{BEHIND} = 1;
					}
				}
			}
			else
			{
				$repo->repoError("repo not found on GitHub!");
			}
		}
		setRepoState($repo);
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
	$repo->{pushed_at} = $entry->{pushed_at};

	# Also very interesting is "updated_at" which tells me if the
	# metadata (i.e. description, visibility, etc) for the repo changed.

	if ($repo->{descrip} =~ /Copied from (.*?)\s/i)
	{
		my $text = $1;
		repoNote(undef,$dbg_github,3,"Copied from $text");
			# note: undef prevents adding to list of notes on repo
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
