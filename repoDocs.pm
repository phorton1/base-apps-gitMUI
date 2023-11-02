#----------------------------------------------------
# apps::gitUI::repoDocs
#----------------------------------------------------
# Any time I add a page of documentation I have to modify
# git_repositories.txt.  Page Headers and Footers are
# another issue.


package apps::gitUI::repoDocs;
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Utils;
use apps::gitUI::repos;
use apps::gitUI::utils;
use apps::gitUI::monitor;


my $dbg_find = 0;
my $dbg_md = 0;


my $JUST_DO_MY_REPOS = 1;
	# The list of documents that I actively present, publicly,
	# or perhaps privately, on GitHub
my $DONT_DISPLAY_REPO_LINKS = 0;



BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
	);
}


#------------------------------------------------------------
# parseMD
#------------------------------------------------------------

sub copyTo
{
	my ($repo,$file_msg,$line,$len,$ppos,$ptext,$openers,$closer,$where) = @_;
	return $repo->repoError("Unexpected end of line1 at $where($$ppos) $file_msg")
		if $$ppos >= $len;
	for my $opener (@$openers)
	{
		my $c = substr($line,$$ppos++,1);
		return $repo->repoError("$file_msg Expected opener '$opener'")
			if $c ne $opener;
		return $repo->repoError("$file_msg Unexpected end of line2")
			if $$ppos >= $len;
	}
	while (1)
	{
		my $c = substr($line,$$ppos++,1);
		last if $c eq $closer;
		$$ptext .= $c;
		return $repo->repoError("$file_msg Unexpected end of line3")
			if $$ppos >= $len;
	}

	return 1;
}



sub parseMD
	# sections by level
	# links to my repos
	# links to anchors
	# external link verification
{
	my ($repo,$doc,$other) = @_;
	display($dbg_md,0,"DOC($doc) $other");
	my $filename = $repo->{path}.$doc;
	my $text = getTextFile($filename);
	return $repo->repoError("Empty or missing MD $filename")
		if !$text;

	my $level = 0;
	my $in_code = 0;
	my $line_num = 0;
	my @lines = split(/\n/,$text);
	for my $line (@lines)
	{
		$line_num++;

		if (!$in_code && $line =~ /^```/)
		{
			$in_code = 1;
		}
		elsif ($in_code && $line =~ /^```/)
		{
			$in_code = 0;
		}
		next if $in_code;

		if ($line =~ s/^(#+)\s+//)
		{
			my $pounds = $1;
			$level = length($pounds);
			display($dbg_md+1,$level,"$pounds $line");
		}

		# we assume entire links are on one line
		# there are a few basic types of links
		#
		# 	[blah](blah)				- a regular link
		#	![blah](blah.jpg)			- an image
		#   [![blah](blah.jpg)](blah2)	- a link from an image

		# get rid of possibly escaped brackets

		$line =~ s/\\\[/--LEFT_BRACKET--/g;

		my $cpos = 0;
		my $len = length($line);
		while ($cpos < $len)
		{
			my @offs = (
				index($line,"[",$cpos),
				index($line,"![",$cpos),
				index($line,"[![",$cpos) );

			my $first = -1;
			my $which = -1;
			my $num = 2;
			for my $off (reverse @offs)
			{
				if ($off >= 0 && ($first == -1 || $off < $first))
				{
					$which = $num;
					$first = $off;
				}
				$num--;
			}

			if ($which >= 0)		# found one
			{
				display($dbg_md+1,$level+1,"len($len) cpos($cpos) found which($which) at first($first) '$line'");

				$cpos = $first + $which + 1;	# move past opener
				my $text = '';
				my $link1 = '';
				my $link2 = '';

				# get text

				my $file_msg = "$filename($line_num)";
				last if !copyTo($repo,$file_msg,$line,$len,\$cpos,\$text,[],']',"inner_text");
				last if !copyTo($repo,$file_msg,$line,$len,\$cpos,\$link1,['('],')',"inner_link");
				last if $which == 2 && !copyTo($repo,$file_msg,$line,$len,\$cpos,\$link2,[']','('],')',"outer_link");

				checkLink($repo,$filename,$line_num,1,$link1);
				checkLink($repo,$filename,$line_num,2,$link2) if $which == 2;

			}
			else
			{
				last;	#done
			}

		}	# whlle ($cpos < $len)
	}	# for each $line
}	# parseMD


sub splitPath
	# its a kludge to assume /\.(.*)$/ is a filename
	# the only way to really tell is -d
	# we skip any thing that ends in numbers for now
{
	my ($path) = @_;
	my $file = '';
	my @parts = split("/",$path);
	if (@parts)
	{
		my $leaf = pop @parts;
		if ($leaf !~ /\.(\d+)$/ && $leaf =~ /\.(.*)$/)
		{

			$file = $leaf;
		}
		else
		{
			push @parts,$leaf;
		}
		$path = join("/",@parts);
	}
	return ($path,$file);
}


sub checkLink
{
	my ($repo,$filename,$line_num,$which,$link) = @_;

	my $is_img = $link =~ /\.(png|gif|jpg|jpeg|pdf)$/i ? 1 : 0;
	my $is_extern = $link =~ /^http/ ? 1 : 0;
	my $doc_path = pathOf($filename);

	if ($is_img && !$is_extern)
	{
		display($dbg_md+1,1,"img($which:$line_num) $link");
		my $img_filename = $doc_path."/".$link;
		$repo->repoError("$filename($line_num) could not find image($img_filename)")
			if !-f $img_filename;
	}
	else
	{
		# I have identified certain kinds of cannonical links
		#
		# GitHub repos
		#
		#		https://github.com/phorton1/base-apps-buddy
		#			reference to a repo
		#		https://github.com/phorton1/base-apps-buddy/tree/master/releases
		#		https://github.com/phorton1/Arduino-_vMachine/tree/master/LICENSE.TXT
		#			reference to a path within a repo
		#		https://github.com/phorton1/Arduino-esp32_cnc20mm/tree/master/docs/design.md#y-axis-bearing
		#			link to anchor in in different repo MD document
		#
		# Other external links
		#
		#		https://www.putty.org
		#			typical
		#		https://youtu.be/bSlaEzazfRE
		#			my YouTube videos
		#		https://www.ebay.com/itm/392298131168
		#
		# relative MD files
		#
		#		design.md
		#	    docs/vGuitar.md
		#
		# anchors
		#
		#		#a-controler-schematic
		#		firmware.md#c-serial-monitor
		#
		# BAD THINGS
		#
		#	/blob/master should be /tree/master
		#		and should match $branch
		#
		#   absolute links to same-repo doc relative files should be removed
		#
		#		https://github.com/phorton1/Arduino-esp32_cnc20mm/tree/master/docs/design.md#y-axis-bearing
		#
		# ../ should be eliminated
		#
		#		../LICENSE.TXT
		#			better: https://github.com/phorton1/Arduino-libraries-FluidNC_UI/tree/master/LICENSE.TXT
		#
		# ./ should be eliminated:
		#
		#		./firmware.md#c-serial-monitor
		#			theClock3::ui.md

		my $is_external = $link =~ /^https:\/\//;

		my $repo_id = '';
		my $repo_path = '';
		my $repo_file = '';
		my $anchor = '';

		my $work = $link;
		$anchor = $1 if $work =~ s/#(.*$)//;

		if ($work =~ s/^https:\/\/github\.com\/phorton1\///)
		{
			my @parts = split("/",$work);
			$repo_id = shift(@parts);
			if (@parts)
			{
				my $leaf = pop @parts;
				if ($leaf !~ /\.(\d+)$/ && $leaf =~ /\.(.*)$/)
				{
					$repo_file = $leaf;
				}
				else
				{
					push @parts,$leaf;
				}
				$repo_path = join("/",@parts);
				$repo_path =~ s/^(tree|blob)\/master//;
			}
		}
		elsif ($work !~ /^(http:|https:)/)
		{
			$repo_id = $repo->{id};
			my $repo_re = $repo->{path};
			$repo_re =~ s/\//\\\//g;

			$repo_path = $doc_path;
			$repo_path =~ s/$repo_re//;

			# display(0,3,"doc_path($doc_path) repo_re($repo_re) repo_path($repo_path)");

			my $add_part = '';
			($add_part,$repo_file) = splitPath($work);
			$repo_path .= "/$add_part" if $add_part;
		}

		if ($repo_id)
		{
			display($dbg_md,1,pad("REPO($which:$line_num)",14).$link) if $DONT_DISPLAY_REPO_LINKS;
				# for now, just assume that verifying them is good enough
				# TODO: still need to gather and verify anchors in a 2nd pass

			display($dbg_md+1,1,pad("REPO($which:$line_num)",14)."repo($repo_id) path($repo_path) file($repo_file) anchor($anchor)");
			display($dbg_md+1,2,"from '$link'");

			my $link_repo = getRepoById($repo_id);
			if (!$link_repo)
			{
				$repo->repoError("$filename($line_num) Could not find repo($repo_id) in link($link)");
			}
			else
			{
				my $link_path = $link_repo->{path};
				$link_path .= $repo_path;
				if (!-d $link_path)
				{
					$repo->repoError("$filename($line_num) Could not find directory($link_path) in link($link)");
				}
				elsif ($repo_file)
				{
					my $link_file = $link_path."/".$repo_file;
					if (!-f $link_file)
					{
						$repo->repoError("$filename($line_num) Could not find file($link_file) in link($link)");
					}
				}

			}

		}
		else
		{
			display($dbg_md,1,pad("LINK($which:$line_num)",14).$link);
		}
	}
}


#----------------------------------------------------------------
# getRepoDocs()
#----------------------------------------------------------------

sub getRepoDocs
{
	my ($repo) = @_;
	if (!$JUST_DO_MY_REPOS || $repo->{mine})
	{
		my $path = $repo->{path};
		my $docs = $repo->{docs};
		display($dbg_find,0,"getRepoDocs($repo->{path})") if @$docs;
		for my $doc_spec (@$docs)
		{
			my ($doc,@other) = split(/\s+/,$doc_spec);
			parseMD($repo,$doc,join(' ',@other));
		}
	}
	return 1;
}



#------------------
# test main()
#------------------

if (1)
{
	if (parseRepos())
	{
		my $repo_list = getRepoList();
		for my $repo (@$repo_list)
		{
			last if !getRepoDocs($repo);
		}
	}
}




1;
