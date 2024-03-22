#-------------------------------------------------------------------------
# My generic hyperLink control
#-------------------------------------------------------------------------

package apps::gitMUI::myHyperlink;
use strict;
use warnings;
use Wx qw(:everything);
use apps::gitMUI::utils;
use base qw(Wx::StaticText);


sub new
{
	my ($class,$parent,$ctrl_id,$text,$pos,$size,$color) = @_;
	$size ||= [-1,-1];
	$color = $color_blue if !defined($color);
	my $this = $class->SUPER::new($parent,$ctrl_id,$text,$pos,$size);
	$this->SetForegroundColour($color);
	return $this;
}


1;
