#-------------------------------------------------------------------------
# fonts and colors commot to gitUI
#-------------------------------------------------------------------------

package apps::gitUI::styles;
use strict;
use warnings;
use Wx qw(:everything);

BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(

		$font_normal
        $font_bold

		$color_black
		$color_red
		$color_green
		$color_blue
		$color_cyan
		$color_magenta
		$color_yellow
		$color_grey
		$color_purple
		$color_orange
		$color_white
		$color_light_grey
		$color_dark_cyan

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

our $font_normal = Wx::Font->new(9,wxFONTFAMILY_DEFAULT,wxFONTSTYLE_NORMAL,wxFONTWEIGHT_NORMAL);
our $font_bold = Wx::Font->new(9,wxFONTFAMILY_DEFAULT,wxFONTSTYLE_NORMAL,wxFONTWEIGHT_BOLD);


our $color_black 	 = Wx::Colour->new(0x00, 0x00, 0x00);
our $color_red     	 = Wx::Colour->new(0xE0, 0x00, 0x00);		# listCtrl deletes, pathWindow staged_changes
our $color_green   	 = Wx::Colour->new(0x00, 0x90, 0x00);		# listCtrl staged M's, pathWindow: public
our $color_blue    	 = Wx::Colour->new(0x00, 0x00, 0xC0);		# listCtrl icons and repo line, pathWindow: private
our $color_cyan      = Wx::Colour->new(0x00, 0xC0, 0xC0);		# unused
our $color_magenta   = Wx::Colour->new(0xC0, 0x00, 0xC0);		# path_window: remote_changes
our $color_yellow    = Wx::Colour->new(0xFF, 0xD7, 0x00);		# commitRight title
our $color_grey      = Wx::Colour->new(0x99, 0x99, 0x99);		# unused
our $color_purple    = Wx::Colour->new(0x60, 0x00, 0xC0);		# unused
our $color_orange    = Wx::Colour->new(0xC0, 0x60, 0x00);		# path_window: unstaged_changes
our $color_white     = Wx::Colour->new(0xFF, 0xFF, 0xFF);
our $color_dark_cyan = Wx::Colour->new(0x00, 0x80, 0x80);		# unused
our $color_light_grey= Wx::Colour->new(0xF0, 0xF0, 0xF0);		# commitRight panel

our $color_git_staged   = Wx::Colour->new(0xA0, 0xFF, 0xA0);	# commitList(staged) green headeer
our $color_git_unstaged = Wx::Colour->new(0xff, 0xB0, 0xA0);	# commitList(unstqaged) orange header
our $color_item_selected = Wx::Colour->new(0x00, 0x78, 0xD7);	# commitList selected item background
	# 120, 215 from git highlight


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
# The bit patterns in gitUI on screen are 12x15

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
