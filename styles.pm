#-------------------------------------------------------------------------
# fonts and colors commot to gitUI
#-------------------------------------------------------------------------

package apps::gitUI::styles;
use strict;
use warnings;
use Wx qw(:everything);


our $color_red     = Wx::Colour->new(0xc0 ,0x00, 0x00);  # red
our $color_green   = Wx::Colour->new(0x00 ,0x90, 0x00);  # green
our $color_blue    = Wx::Colour->new(0x00 ,0x00, 0xc0);  # blue

BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		$color_red
		$color_green
		$color_blue
	);
}




1;
