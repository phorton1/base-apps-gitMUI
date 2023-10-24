#-------------------------------------------------------------------------
# a separate small set of utility functions for gitUI
#-------------------------------------------------------------------------

package apps::gitUI::utils;
use strict;
use warnings;
use Win32::Process;
use Wx qw(:everything);

BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(

		$THREAD_EVENT
		openGitGUI

	);
}



our $THREAD_EVENT:shared = Wx::NewEventType;
	# This is a weird place for this, but it is includable by both gitUI & command


#---------------------------------------------
# methods
#---------------------------------------------

sub openGitGUI
{
	my ($path) = @_;
	chdir($path);

	# This, not system(), is how I figured out how to start
	# git gui without opening an underlying DOS box.

	my $p;
	Win32::Process::Create(
		$p,
		"C:\\Windows\\System32\\cmd.exe",
		"/C git gui",
		0,
		CREATE_NO_WINDOW |
		NORMAL_PRIORITY_CLASS,
		$path );
}






1;
