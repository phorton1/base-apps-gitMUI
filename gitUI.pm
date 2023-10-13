#--------------------------------------------------------
# gitUI Frame
#--------------------------------------------------------

package apps::gitUI::Frame;
use strict;
use warnings;
use Wx qw(:everything);
use apps::gitUI::pathWindow;
use Pub::Utils;
use base qw(Wx::Frame);


sub new
{
	my ($class, $parent) = @_;
	my $this = $class->SUPER::new($parent,-1,'gitUI title',[50,50],[600,680]);

    $this->CreateStatusBar();

	apps::gitUI::pathWindow->new($this);
	return $this;
}


#----------------------------------------------------
# gitUI App
#----------------------------------------------------
# For some reason, to exit with CTRL-C from the console
# we need to set PERL_SIGNALS=unsafe in the environment.

package apps::gitUI::App;
use strict;
use warnings;
use Pub::Utils;
use Pub::WX::Main;
use base 'Wx::App';

my $dbg_app = 0;

my $frame;


sub OnInit
{
	$frame = apps::gitUI::Frame->new();
	if (!$frame)
	{
		error("unable to create frame");
		return undef;
	}
	setAppFrame($frame);
	$frame->Show( 1 );
	display($dbg_app,0,"gitUIApp started");
	return 1;
}


my $app = apps::gitUI::App->new();

Pub::WX::Main::run($app);

$frame = undef;
display($dbg_app,0,"finished gitUIApp");


1;
