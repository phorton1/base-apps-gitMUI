#!/usr/bin/perl
#-------------------------------------------
# apps::gitUI::commitRight
#-------------------------------------------
# The right side of the commitWindow contains
# the diff and command portions

package apps::gitUI::commitRight;
use strict;
use warnings;
use threads;
use threads::shared;
use Wx qw(:everything);
use apps::gitUI::styles;
use Pub::Utils;
use base qw(Wx::Window);


my $dbg_life = 0;

BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
		$MIN_DIFF_AREA_HEIGHT
		$COMMAND_AREA_HEIGHT
	);
}

our $MIN_DIFF_AREA_HEIGHT  = 80;
our $COMMAND_AREA_HEIGHT   = 120;


sub new
{
    my ($class,$parent,$splitter) = @_;
	display($dbg_life,0,"new commitRight()");
    my $this = $class->SUPER::new($splitter);

    $this->{parent} = $parent;

	$this->SetBackgroundColour($color_white);
	Wx::StaticText->new($this,-1,'commitRight',[5,5]);

    return $this;

}


1;
