#-------------------------------------------------------------------------
# Window to invoke gitUI from my /bat/git_repositories.txt
#-------------------------------------------------------------------------

package apps::gitUI::hyperlink;
use strict;
use warnings;
use Wx qw(:everything);
use apps::gitUI::styles;
use base qw(Wx::StaticText);


sub new
{
	my ($class,$parent,$id,$text,$pos,$size,$color) = @_;
	$color = $color_blue if !defined($color);
	my $this = $class->SUPER::new($parent,$id,$text,$pos,$size);
	$this->SetForegroundColour($color);
	return $this;
}


1;
