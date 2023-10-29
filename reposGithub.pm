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
use apps::gitUI::utils;
use apps::gitUI::repo;
use apps::gitUI::repos;
use apps::gitUI::repoGit;
use Pub::Utils;

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


my $git_user = 'phorton';
my $git_api_token = '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';
	# Created from my github account under Settings-Developer Options
	# Personal Access Tokensuse strict;



#----------------------------------------------------
# github access
#----------------------------------------------------

sub gitHubRequest
{
    my ($what,$location,$use_cache) = @_;
	$use_cache ||= 0;

	display($dbg_request,0,"gitHubRequest($what,$location) use_cache($use_cache)");

	my $cache_filename = "$temp_dir/$what.txt";

	my $content = $use_cache || $USE_TEST_CACHE ?
		getTextFile($cache_filename) : '';
	my $from_cache = $content ? 1 : 0;

    # my $url = 'https://api.github.com/users/phorton1/repos?per_page=100';
        # lists public repositories, can be hit from browser
    # my $url = 'https://api.github.com/user/repos?per_page=100';
        # requires authentication that is not done on browser

    if (!$content)
	{
		my $url = 'https://api.github.com/' . $location;

		my $request = HTTP::Request->new(GET => $url);
		$request->content_type('application/json');
		$request->authorization_basic($git_user,$git_api_token); # my_decrypt($mbes_pass));

		# unused REQUEST CONTENT
		# my $request_data = '';
		# my $json = encode_json($request_data);
		# $request->content($json);

		# DO THE REQUEST

		my $my_ua = new LWP::UserAgent (agent => 'Mozilla/5.0', cookie_jar =>{});
		$my_ua->ssl_opts( SSL_ca_file => Mozilla::CA::SSL_ca_file() );
		$my_ua->ssl_opts( verify_hostname => 1 );
		my $response = $my_ua->request($request);

		if (!$response)
		{
			error("gitHubRequest($location) - no response");
		}
		else
		{
			my $status_line = $response->status_line();
			display($dbg_request+1,1,"response = $status_line");
			if ($status_line !~ /200/)
			{
				error("gitHubRequest($location) bad_status: $status_line");
			}
			else
			{
				$content = $response->content() || '';
				my $content_type = $response->headers()->header('Content-Type') || 'unknown';
				my $content_len = length($content);
				display($dbg_request+1,1,"content bytes($content_len) type=$content_type");
				if (!$content)
				{
					error("gitHubRequest($location) - no content returned");
				}
				elsif ($response->headers()->header('Content-Type') !~ 'application/json')
				{
					printVarToFile(1,"$temp_dir/$what.error.txt",$content);
					error("gitHubRequest($location) unexpected content type: $content_type; see $temp_dir/$what.error.txt");
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
			error("gitHubRequest($location) could not json_decode");
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
				printVarToFile(1,"$temp_dir/$what.json.txt",$text);
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

    display($dbg_github,0,"doGitHub($use_cache)");

	my $repo_list = getRepoList();
	if (!$repo_list)
	{
		error("No repo_list in doGitHub!!");
		return;
	}

	for my $repo (@$repo_list)
	{
		$repo->{found_on_github} = 0;
		$repo->clearErrors();
		$repo->checkGitConfig();
	}


    my $data = gitHubRequest("repos",'user/repos?per_page=100',$use_cache);
        # returns an array of hashes (upto 100)
        # prh - will need to do it multiple times if I get more than 100 repositories

    if ($data)
    {
        display($dbg_github,1,"found ".scalar(@$data)." github repos");

        for my $entry (@$data)
        {
            my $id = $entry->{name};
            my $path = repoIdToPath($id);
			my $repo = getRepoHash()->{$path};

			next if $TEST_JUNK_ONLY && $path !~ /junk/;

			if (!$repo)
			{
				error("doGitHub() cannot find repo($id) = path($path)");
			}
			else
			{
				$repo->{found_on_github} = 1;
				$repo->{descrip} = $entry->{description} || '';
				my $is_private = $entry->{visibility} eq 'private' ? 1 : 0;
				my $is_forked = $entry->{fork} ? 1 : 0;
				my $repo_forked = $repo->{forked} ? 1 : 0;

				display($dbg_github+1,1,"doGitHub($id) private($is_private) forked($is_forked)");

				$repo->repoError("validateGitHub($id) - local private($repo->{private}) != github($is_private)")
					if $repo->{private} != $is_private;
				$repo->repoError("validateGitHub($id) - local forked($repo_forked) != github($is_forked)")
					if $repo_forked != $is_forked;

				# if it's forked, do a separate request to get the parent information

				if ($GET_GITHUB_FORK_PARENTS && $is_forked)
				{
					my $info = gitHubRequest($id,"repos/phorton1/$id",$use_cache);
					if (!$info)
					{
						$repo->repoError("doGitHub($id) - could not get forked repo");
					}
					elsif (!$info->{parent})
					{
						repoError("doGitHub($id) - no parent for forked repo");
					}
					elsif (!$info->{parent}->{full_name})
					{
						$repo->repoWarning(0,2,"doGitHub($id) - No parent->full_name for forked repo");
					}
					else
					{
						$repo->{parent} = $info->{parent}->{full_name};
						display($dbg_github,2,"fork parent = $repo->{parent}");
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
    }   # got $data

	for my $repo (@$repo_list)
	{
		$repo->repoError("repo($repo->{id} not found on github!")
			if !$repo->{found_on_github};
	}

}   #   getGitHubRepos()




#-----------------------------------------------
# test main
#-----------------------------------------------
# Currently only place checkGitConfig() is called, and
# only one that would check that

if (0)
{
	display($dbg_github,0,"github.pm test_main()");
	if (parseRepos())
	{
		doGitHub(1,1);
	}
}


1;
