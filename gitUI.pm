#--------------------------------------------------------
# gitUI Frame
#--------------------------------------------------------

package apps::gitUI::Frame;
use strict;
use warnings;
use Wx qw(:everything);
use apps::gitUI::pathWindow;
use Pub::Utils;
use Pub::WX::Frame;
use apps::gitUI::Resources;
use base qw(Pub::WX::Frame);

my $dbg_frame = 0;


sub new
{
	my ($class, $parent) = @_;
	Pub::WX::Frame::setHowRestore($RESTORE_MAIN_RECT);
	my $this = $class->SUPER::new($parent);	# ,-1,'gitUI',[50,50],[600,680]);

    $this->CreateStatusBar();
	$this->createPane($ID_PATH_WINDOW);

	return $this;
}


sub createPane
{
	my ($this,$id,$book,$data) = @_;
	display($dbg_frame,0,"gitUI::Frame::createPane($id)".
		" book="._def($book).
		" data="._def($data) );

	if ($id == $ID_PATH_WINDOW)
	{
	    $book ||= $this->{book};
        return apps::gitUI::pathWindow->new($this,$id,$book,$data);
    }
    return $this->SUPER::createPane($id,$book,$data);
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
use Pub::WX::AppConfig;
use base 'Wx::App';

$temp_dir = "/base/temp/gitUI";
$data_dir = "/base/temp/gitUI";
$ini_file = "$data_dir/gitUI.ini";


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
