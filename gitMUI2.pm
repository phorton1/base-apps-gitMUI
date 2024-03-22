#!/usr/bin/perl
#------------------------------------------------------------------
# a shell around apps::gitMUI::gitMUI.pm
#------------------------------------------------------------------
# because CAVA requries a separate script for separate executables,
# and I want a version that will popup a dos command window for
# debugging.

package apps::gitMUI::gitMUI2;
use strict;
use warnings;

require "/base/apps/gitMUI/gitMUI.pm";

1;
