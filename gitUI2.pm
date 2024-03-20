#!/usr/bin/perl
#------------------------------------------------------------------
# a shell around apps::gitUI::gitUI.pm
#------------------------------------------------------------------
# because CAVA requries a separate script for separate executables,
# and I want a version that will popup a dos command window for
# debugging.

package apps::gitUI::gitUI2;
use strict;
use warnings;

require "/base/apps/gitUI/gitUI.pm";

1;
