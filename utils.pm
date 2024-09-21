#-------------------------------------------------------------------------
# apps::gitMUI::utils
#-------------------------------------------------------------------------
# Contains common defines, styles, and methods used by gitMUI
#
# Some commom git commands:
#
#    diff --name-status
#       or git "status show modified files"
#       shows any local changes to the repo
#    diff master origin/master --name-status","remote differences"
#       show any differences from bitbucket
#    fetch
#       update the local repository from the net ... dangerous?
#    stash
#       stash any local changes
#    update
#       pull any differences from bitbucket
#    add .
#       add all uncommitted changes to the staging area
#    commit  -m "checkin message"
#       calls "git add ." to add any uncommitted changes to the staging area
#       and git $command to commit the changes under the given comment
#    push -u origin master
#       push the repository to bitbucket
#
# TO INITIALIZE REMOTE REPOSITORY
#
#      git remote add origin https://github.com/phorton1/Arduino.git
#
# Various dangerous commands
#
#    git reset --hard HEAD
#    git pull -u origin master


package apps::gitMUI::utils;
use strict;
use warnings;
use Wx qw(:everything);
use Pub::Utils;
use Pub::Prefs;
use Pub::WX::AppConfig;
use Pub::WX::Dialogs;
use apps::gitMUI::dialogCredentials;


my $dbg_ids = 1;


our $INIT_SYSTEM = 0;

our $TEST_INIT_SYSTEM = 0;
	# if set, command line 'init' will force a rebuild of git_repos.txt,
	# but will use the caches if present.  Otherwise, $INIT_SYSTEM will
	# clear the temp direotory.


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(

		$INIT_SYSTEM
		$TEST_INIT_SYSTEM

		$THREAD_EVENT

		$GIT_CB_ERROR
		$GIT_CB_PACK
        $GIT_CB_TRANSFER
        $GIT_CB_REFERENCE

		$DEFAULT_EDITOR
        $DEFAULT_SHELL_EXTS
        $DEFAULT_EDITOR_EXTS

		$font_normal
        $font_bold

		$color_black
		$color_red
		$color_green
		$color_blue
		$color_cyan
		$color_magenta
		$color_yellow
		$color_dark_yellow
		$color_grey
		$color_purple
		$color_orange
		$color_white
		$color_lime
		$color_light_grey
		$color_medium_grey
		$color_medium_cyan
		$color_dark_cyan

		linkDisplayColor
		lctilde

		$color_git_staged
        $color_git_unstaged
		$color_item_selected

		$bm_right_arrow
		$bm_up_arrow
		$bm_plus
		$bm_minus
		$bm_folder
		$bm_folder_lines
		$bm_folder_x
		$bm_folder_check
		$bm_folder_question

	);
}


#----------------------------------
# directories
#----------------------------------

my $program_name = 'gitMUI';

setStandardTempDir($program_name);
setStandardDataDir($program_name);

$ini_file = "$temp_dir/$program_name.ini";

$logfile = "$temp_dir/$program_name.log";



#----------------------------------------------
# DEFAULT PREFERENCES
#----------------------------------------------

my $DEFAULT_UPDATE_INTERVAL = 90;
	# seconds for default update interval
	# getPref("GIT_UPDATE_INTERVAL") == 0 will turn off automatic updates
my $DEFAULT_ADD_UNTRACKED_REPOS = 0;
	# Set this to one to scan the entire machine for untracked repos.
	# Nascent feature to bootstrap the system for other users.
my $DEFAULT_EDITOR = "\"C:\\Windows\\notepad.exe\"";
	# program gets passed multiple filenames

my $DEFAULT_SHELL_EXTS = 'md|gif|png|jpg|jpeg|pdf';
my $DEFAULT_EDITOR_EXTS = 'txt|pm|pl|ino|cpp|c|h|hpp|md';
	# shell extensions are checked before editor extensions for
	# default click behavior



my $default_prefs = {

	# main prefs
	# GIT_USER
	# GIT_API_TOKEN

	GIT_REPO_FILENAME => "$data_dir/git_repos.txt",
	GIT_UPDATE_INTERVAL => $DEFAULT_UPDATE_INTERVAL,

	GIT_EDITOR => $DEFAULT_EDITOR,
	GIT_SHELL_EXTS => $DEFAULT_SHELL_EXTS,
	GIT_EDITOR_EXTS => $DEFAULT_EDITOR_EXTS,


	# prefs related to adding untracked repos

	GIT_ADD_UNTRACKED_REPOS => $DEFAULT_ADD_UNTRACKED_REPOS,
	GIT_UNTRACKED_USE_CACHE => 0,
	GIT_UNTRACKED_SHOW_TRACKED_REPOS => 0,
	GIT_UNTRACKED_SHOW_DIR_WARNINGS => 1,
	GIT_UNTRACKED_USE_SYSTEM_EXCLUDES => 1,
	GIT_UNTRACKED_USE_OPT_SYSTEM_EXCLUDES => 1,
	GIT_UNTRACKED_COLLAPSE_COPIES => 0,

};


Pub::Prefs::initPrefs(
	"$data_dir/$program_name.prefs",
	$default_prefs,
	'',		# crypt file "/base_data/_ssl/PubCryptKey.txt",
	0 );	# 1 == show_init_prefs


sub checkInitSystem
{
	# credentials must exist in preferences

	if (!getPref('GIT_USER') || !getPref('GIT_API_TOKEN'))
	{
		return 0 if !apps::gitMUI::dialogCredentials->getCredentials()
	}

	# and then if no repo filename, they get an option to
	# init the system

	my $repo_filename = getPref('GIT_REPO_FILENAME');
	unlink $repo_filename if $TEST_INIT_SYSTEM;
	my $repo_file_exists = -f $repo_filename ? 1 : 0;

	if (!$repo_file_exists)
	{
		my $msg = "Could not find $repo_filename.\n".
			"Do you want to scan the entire hard-drive for\n".
			"repos and create a new $repo_filename?";
		my $title = 'INIT_SYSTEM';
		my $dlg = Wx::MessageDialog->new(undef,$msg,$title,wxCANCEL|wxOK|wxICON_EXCLAMATION);
		my $rslt = $dlg->ShowModal();
		return 0 if $rslt != wxID_OK;
		warning(0,0,"INITIALIZING SYSTEM to new ".getPref('GIT_REPO_FILENAME'));
		$INIT_SYSTEM = 1;
	}

	if ($INIT_SYSTEM && !$TEST_INIT_SYSTEM)
	{
		warning(0,0,"INIT SYSTEM CLEARING temp directory");
		my $dirh;
		my @unlinks;
		if (opendir($dirh,$temp_dir))
		{
			while (my $entry=readdir($dirh))
			{
				next if $entry !~ /\.txt$/;
				push @unlinks,$entry;
			}
			closedir($dirh);

			for my $unlink (@unlinks)
			{
				my $path = "$temp_dir/$unlink";
				display(0,1,"unlinking $unlink");
				unlink $path;
			}
		}
	}

	return 1;
}


#-------------------------------------------
# constants
#-------------------------------------------


our $THREAD_EVENT:shared = Wx::NewEventType;
	# This is a weird place for this, but it is includable by both gitMUI.pm & command.pm

# PUSH callback types
# PACK is called first, stage is 0 on first, 1 thereafter
# 	when done, $total = the number of objects for the push
# TRANSFER show the current, and total objects and bytes
#   transferred thus far.
# REFERENCE is the last (set of) messages as git updates
#   the local repository's origin/$branch to the HEAD.
#   There could be multiple, but I usually only see one.
#   The push is complete when REFERENCE $msg is undef.
# NEGOTIATE is not seen in my usages
# SIDEBAND (Resolving deltas) had too many problems,
#   very quick, so I don't use it.

our $GIT_CB_ERROR      = -1;		# $msg
our $GIT_CB_PACK		= 0;		# $stage, $current, $total
our $GIT_CB_TRANSFER	= 1;		# $current, $total, $bytes
our $GIT_CB_REFERENCE  = 2;		# $ref, $msg


#-----------------------------------------------------
# styles
#-----------------------------------------------------


our $font_normal = Wx::Font->new(9,wxFONTFAMILY_DEFAULT,wxFONTSTYLE_NORMAL,wxFONTWEIGHT_NORMAL);
our $font_bold = Wx::Font->new(9,wxFONTFAMILY_DEFAULT,wxFONTSTYLE_NORMAL,wxFONTWEIGHT_BOLD);


our $color_black 	     = Wx::Colour->new(0x00, 0x00, 0x00);

our $color_red     	     = Wx::Colour->new(0xE0, 0x00, 0x00);		# commit: deletes; link: errors or needs pull; dialog: repoError
our $color_green   	     = Wx::Colour->new(0x00, 0x60, 0x00);		# commit: staged M's; link: public
our $color_blue    	     = Wx::Colour->new(0x00, 0x00, 0xC0);		# commit: icons and repo line; link: private
our $color_cyan          = Wx::Colour->new(0x00, 0xE0, 0xE0);		# winInfoRight header
our $color_magenta       = Wx::Colour->new(0xC0, 0x00, 0xC0);		# link: staged or unstaged changes
our $color_yellow        = Wx::Colour->new(0xFF, 0xD7, 0x00);		# winCommitRight title background; dialog: repoWarning
our $color_dark_yellow   = Wx::Colour->new(0xA0, 0xA0, 0x00);		# default branch warning
our $color_grey          = Wx::Colour->new(0x99, 0x99, 0x99);		# unused
our $color_purple        = Wx::Colour->new(0x60, 0x00, 0xC0);		# unused
our $color_orange        = Wx::Colour->new(0xC0, 0x60, 0x00);		# link: needs Push; history: tags
our $color_white         = Wx::Colour->new(0xFF, 0xFF, 0xFF);		# dialog: repoNote
our $color_medium_cyan   = Wx::Colour->new(0x00, 0x60, 0xC0);		# repo: forked
our $color_dark_cyan     = Wx::Colour->new(0x00, 0x60, 0x60);		# unused
our $color_lime  	     = Wx::Colour->new(0x50, 0xA0, 0x00);		# hitory: tags
our $color_light_grey    = Wx::Colour->new(0xF0, 0xF0, 0xF0);		# winCommitRight panel; dialog: repoDisplay
our $color_medium_grey   = Wx::Colour->new(0xC0, 0xC0, 0xC0);		# winInfoLeft selected item

our $color_git_staged    = Wx::Colour->new(0xA0, 0xFF, 0xA0);		# winCommitList(staged) green headeer
our $color_git_unstaged  = Wx::Colour->new(0xff, 0xB0, 0xA0);		# winCommitList(unstqaged) orange header
our $color_item_selected = Wx::Colour->new(0x00, 0x78, 0xD7);		# winCommitList selected item background
	# 120, 215 from git highlight


sub linkDisplayColor
{
	my ($repo) = @_;
	return
		@{$repo->{errors}} || $repo->{BEHIND} || $repo->{REBASE} ? $color_red :
			# errors or merge conflict
		$repo->canPush() || $repo->{AHEAD} ? $color_orange :
			# needs push
		$repo->canCommitParent() || keys %{$repo->{unstaged_changes}} ?  $color_magenta :
			# parent ready for commit unstaged changes
		keys %{$repo->{staged_changes}} ? $color_magenta :
			# can commit
		($repo->{branch} && $repo->{default_branch} &&
		 $repo->{branch} ne $repo->{default_branch} ||
		 @{$repo->{warnings}})
			# $repo->isLocalOnly() ||
			# $repo->isRemoteOnly())
			? $color_dark_yellow :
		$repo->{forked} ? $color_medium_cyan :
		$repo->{private} ? $color_blue :
		$color_green;
}


sub lctilde
	# for sorting paths or ids
	# replace dashes or forward slashes with tildes
	# so that they sort after any characters
	# and lowercase for case insensitive compare
{
	my ($path) = @_;
	$path =~ s/\/|-/~/g;
	return lc($path);
}


#----------------------------------------------------------
# images needed by list ctrl
#----------------------------------------------------------
#							unstaged				staged
#	- tri_right
#   - tri_up
#   - folder_blank			black add item			black add item
#   - folder_check      							green modified item
#	- folder_question		black deleted item
#   - folder_x										red deleted item
#   - folder_lines			blue modified item
#
# The bit patterns in gitMUI on screen are 12x15

sub myBitMapToWxBitmap
	# Convert my format to XBM for Wx::Bitmap ctor and return a Wx::Bitmap.
	# XBM image data consists of a line of pixel values stored in a static array.
	# Because a single bit represents each pixel (0 for white or 1 for black),
	# each byte in the array contains the information for eight pixels,
	# with the upper left pixel in the bitmap represented by the low bit of the
	# first byte in the array. If the image width does not match a multiple of 8,
	# the extra bits in the last byte of each row are ignored.
	#
	# Algorithm is limited to width == 16
{
	my ($pattern) = @_;
	my $out = '';
	my $width = shift @$pattern;
	my $height = shift @$pattern;
	for (my $i=0; $i<$height; $i++)
	{
		my $bits = shift @$pattern;
		my $word = 0;
		my $mask = 1; # << $width;
		for (my $j=0; $j<$width; $j++)
		{
			$word <<= 1;
			$word |= 1 if $bits & $mask;
			$mask <<= 1;
		}
		#push @$out,$byte if !$odd;
		$out .= chr($word & 0xff).chr($word >> 8);
	}

	return Wx::Bitmap->newFromBits($out, $width, $height, 1);
}



my $icon_blank = [
	12,15,
	0b000000000000,
	0b000000000000,
	0b000000000000,
	0b000000000000,
	0b000000000000,
	0b000000000000,
	0b000000000000,
	0b000000000000,
	0b000000000000,
	0b000000000000,
	0b000000000000,
	0b000000000000,
	0b000000000000,
	0b000000000000,
	0b000000000000 ];


my $icon_right_arrow = [
	9,9,
	0b001000000,
	0b001100000,
	0b001110000,
	0b001111000,
	0b001111100,
	0b001111000,
	0b001110000,
	0b001100000,
	0b001000000, ];
my $icon_up_arrow = [
	9,9,
	0b000000000,
	0b000000000,
	0b000010000,
	0b000111000,
	0b001111100,
	0b011111110,
	0b111111111,
	0b000000000,
	0b000000000, ];
my $icon_plus = [
	12,9,
	0b000011100000,
	0b000011100000,
	0b000011100000,
	0b011111111110,
	0b011111111110,
	0b011111111110,
	0b000011100000,
	0b000011100000,
	0b000011100000 ];
my $icon_minus = [
	12,9,
	0b000000000000,
	0b000000000000,
	0b011111111110,
	0b011111111110,
	0b011111111110,
	0b011111111110,
	0b000000000000,
	0b000000000000,
	0b000000000000 ];


my $icon_folder = [
	12,15,
	0b111111110000,
	0b100000011000,
	0b100000010100,
	0b100000010010,
	0b100000011111,
	0b100000000001,
	0b100000000001,
	0b100000000001,
	0b100000000001,
	0b100000000001,
	0b100000000001,
	0b100000000001,
	0b100000000001,
	0b100000000001,
	0b111111111111 ];

my $icon_folder_lines = [
	12,15,
	0b111111110000,
	0b100000011000,
	0b101111010100,
	0b100000010010,
	0b101111011111,
	0b100000000001,
	0b101111111101,
	0b100000000001,
	0b101111111101,
	0b100000000001,
	0b101111111101,
	0b100000000001,
	0b101111111101,
	0b100000000001,
	0b111111111111 ];

my $icon_folder_x = [
	12,15,
	0b111111110000,
	0b100000011000,
	0b100000010100,
	0b100000010010,
	0b100000011111,
	0b100000000001,
	0b100110011001,
	0b100110011001,
	0b100011110001,
	0b100001100001,
	0b100011110001,
	0b100110011001,
	0b100110011001,
	0b100000000001,
	0b111111111111 ];

my $icon_folder_check = [
	12,15,
	0b111111100000,
	0b100000010111,
	0b100000000110,
	0b100000000110,
	0b100000001101,
	0b100000001101,
	0b100000011001,
	0b000000011001,
	0b110000110001,
	0b011000110001,
	0b001101100001,
	0b100111100001,
	0b100011000001,
	0b100000000001,
	0b111111111111 ];

my $icon_folder_question = [
	12,15,
	0b111111110000,
	0b100000001000,
	0b100011100100,
	0b100111110010,
	0b101100011011,
	0b101000011001,
	0b100000110001,
	0b100001100001,
	0b100011000001,
	0b100011000001,
	0b100000000001,
	0b100011000001,
	0b100011000001,
	0b100000000001,
	0b111111111111 ];


our $bm_right_arrow 	= myBitMapToWxBitmap($icon_right_arrow);
our $bm_up_arrow 		= myBitMapToWxBitmap($icon_up_arrow);
our $bm_plus 			= myBitMapToWxBitmap($icon_plus);
our $bm_minus 			= myBitMapToWxBitmap($icon_minus);
our $bm_folder 			= myBitMapToWxBitmap($icon_folder);
our $bm_folder_lines 	= myBitMapToWxBitmap($icon_folder_lines);
our $bm_folder_x 		= myBitMapToWxBitmap($icon_folder_x);
our $bm_folder_check 	= myBitMapToWxBitmap($icon_folder_check);
our $bm_folder_question = myBitMapToWxBitmap($icon_folder_question);



1;
