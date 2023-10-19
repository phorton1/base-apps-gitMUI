#-------------------------------------------------------------------------
# fonts and colors commot to gitUI
#-------------------------------------------------------------------------

package apps::gitUI::styles;
use strict;
use warnings;
use Wx qw(:everything);


our $color_black 	= Wx::Colour->new(0x00, 0x00, 0x00);
our $color_red     	= Wx::Colour->new(0xe0, 0x00, 0x00);
our $color_green   	= Wx::Colour->new(0x00, 0x90, 0x00);
our $color_blue    	= Wx::Colour->new(0x00, 0x00, 0xc0);
our $color_cyan     = Wx::Colour->new(0x00, 0xc0, 0xc0);
our $color_magenta  = Wx::Colour->new(0xc0, 0x00, 0xc0);
our $color_yellow   = Wx::Colour->new(0xc0, 0xc0, 0x00);
our $color_grey     = Wx::Colour->new(0x99, 0x99, 0x99);
our $color_purple   = Wx::Colour->new(0x60, 0x00, 0xc0);
our $color_orange   = Wx::Colour->new(0xc0, 0x60, 0x00);
our $color_white    = Wx::Colour->new(0xff, 0xff, 0xff);

our $color_light_green  = Wx::Colour->new(0xA0, 0xFF, 0xA0);
our $color_light_orange = Wx::Colour->new(0xff, 0xB0, 0xA0);

our $font_normal = Wx::Font->new(9,wxFONTFAMILY_DEFAULT,wxFONTSTYLE_NORMAL,wxFONTWEIGHT_NORMAL);
our $font_bold = Wx::Font->new(9,wxFONTFAMILY_DEFAULT,wxFONTSTYLE_NORMAL,wxFONTWEIGHT_BOLD);


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
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

		$color_light_green
		$color_light_orange

		$font_normal
        $font_bold
	);
}




1;
