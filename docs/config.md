# gitUI - Repository Configuration File

The **repository configuration file** contains a *list*
of all the repos you want gitUI to work with, and
specifies individual *characteristics* of each repo.

The default name is of the file is **gitUI_config.txt**
in the *data directory*. We will simply refer to it as
gitUI_config hereafter, but it can be any name, in any
location.

The gitUI_config file:

- is a line oriented, human readable, simple text file
- can contain # comments and blank lines
- uses *tabs* (\t) as a delimiter for fields on lines
- is indented by convention

It is, essentially, a list of repositories with verbs that
describe things about them, and their relationship.


## Repo Path Line

The main line in the text file is a path to a repo, identified
by a leading forward slash.  It may optionally include a tab
delimited default branch if that is other than 'master'

	/some/path/to/a/repo  (optional_default_branch)

The *Repo Path Lines* create the basic list of repos on your local
machine that gitUI will know about.

The *Repo Path* also determines the gitHub ID that will be used
for accessing the remote repo on gitHub. There is a one-to-one
mapping between a repo **path** and its gitHub **ID**. By default
this mapping gets the ID from the path by replacing path *slashes*
'/' with *dashes* '-', So

	path: base/apps/gitUI   becomes
	id: base-apps-gitUI

There are preferences that allow you to specifiy a series of
regular expressions to help in the mapping of paths to gitHub IDs
and back.  Please see the [preferences](prefs.md) page for more
information.


## SECTION

The SECTION verb comes *before* a *Repo Path Line* and allows you to group
related repos together into sections in the various gitUI windows.

	SECTION path (optional name if different)

If the *path* does not start with a forward slash then it will
be considered the section **name**.

If the *path* does start with a forward slash, an *optional
name* may be provided for the section.

In any case, the section path will be used, when appropriate,
to lessen the horizontal space needed to show the repos within
the section in various gitUI Windows. The path will be *subtracted*
from the Repo Paths that follow it\ by subtracting the section
path from the Repo Path. For example, given a SECTION with two
paths as follows:

	SECTION	/src/Arduino/libraries
	/src/Arduino/libraries/FluidNC
	/src/Arduino/libraries/FluidNC_Extensions

A non-clickable header, and two links (which fit better in the
various gitUI windows) will be created as follows

	/src/Arduino/libraries
	FluidNC
	FluidNC_Extensions

The optional (name) will be shown as the SECTION HEADER if
one is provided.  To further save vertical space, if the
first repo listed within a section has the same path as
the SECTION, the section name becomes a clickable link
to the given repo.


## SUBMODULE rel_path  main_module_path

This verb defines a submodule within a repo.

In our vision of subModules, there is one repo
someplace on our machine that represents the
'master' repository for the submodule.  Typically
this will be a .gitignored subfolder of some
other repo.

We do not, per-se, use, or depend on GIT's own definition
and usage of submodules.  By NOT getting our notion of what
submodules exist directly from GIT, but instead forcing you
to explicitly re-declare it in the gitUI_config file,
we allow for GIT submodule configurations that do not match
our vision, which will not be managed by gitUI, but will
still work as expected.

However, within our vision, the presence of the SUBMODULE
verb defines several key facts for gitUI to use:

- it defines a **separate repo** that exists on the machine,
  which is independently monitored for changes, and which
  has it's own separate status, lists of staged and
  unstaged changes which can be staged, unstaged, reverted
  and/or committed, Pushed, or Pulled independently of hte
  parent (super) repo.
- it **groups** the main_module and all of the cloned submodules
  together into a group that can be monitored and
  acted on as a whole in the *subsWindow*, making it
  much easier to *normalize* a change in a submodule,
  or the main_module, to all of the clones of it,
  as well as providing a mechanism to automatically
  *commit the submodule change* within the parent (super)
  repos that use it.
- it **builds a list** of the submodules within each parent
  repo, which is important for determining when it is
  possible to automatically *commit the submodule change*
  to the parent repo.

*following to be moved to design.md or implementation.md*

Internally, implementation wise, it does the following
As mentioned, it will CREATE a new 'submodule repo'
within the *repoList*. The submodule repo have the
following members:

- path - the path will be the absoluate path
  of the submodule, which will be within the
  parent repo's path.
- id (overloaded) - the id of the submodule repo will be that of the
  main submodule, i.e. where it lives on gitHub.
- parent_repo (added) - will be set as a pointer to
  the actual parent repo object in the gitUI program
- rel_path (added) - will be stored on the object.

By convention, the presence of {parent_repo} is
used within the program to indicate a submodule repo.
In addition, the path of the submodule repo will be pushed
onto lists in the parent repo and the main module repo:

- parent repo - {submodules} list gets all it's fully qualified submodules paths
- main_module repo - {used_in} gets a list of all cloned copies of the main module


## Important VERBS within Repos

These verbs are used for integrity checks, and to
to help getting more information abou the repo from gitHub

- **PRIVATE** - is an integrity check against the visibility
  of the repo on gitHub, to make sure it is what I think
  it should be.  Private repos are shown in blue, public
  ones in green.
- **FORKED** - indicates that the repository is a fork of
  some other, likely public, repository (library).
  A forked repository will have a {parent} gitHub
  repository, and a separate gitHub request will be
  made to get information about the fork.
  FORKED may be binary, or contain text that is shown
  in the infoWindow.
- **USES** abs_repo_path - speficies that this repo USES
  another repo. In turn creates USED_BY members
  on those repos, both of which end up being shortcuts
  to opening the refererd repo in the infoWindow.
  *USES* creates a repository dependency graph.
- **NEEDS** abs_path - an absolute path to a directory that
  must exist on the local machine. For dependencies other
  than repos. Provides shortcut to Windows Explorer
  in the infoWindow.
- **NOTES|WARNINGS|ERRORS** (value) - arbitrary
  keywords that let you push the rest of the line onto
  one of the arrays on the repo object. These are then,
  in turn, added to any Notes, Warnings, or Errors
  found while scanning the repos or getting information
  from gitHub, all of which affect the color of the repo's
  links, and are shown in the infoWindow for the repo.


## Less important VERBS within Repos

- **MINE|NOT MINE** - repos default to 'mine'. Forked
  repos then default to 'not mine'. I like to keep
  track of repos I totally own verus ones I have
  may have copied or cloned and/or modified.
- **GROUP|FRIEND** - whatever follows the verb is
  added to a array {groups} or {friends} on the
  repo.  This is intended to support a future scheme
  for describing relationships between repos other
  than dependencies.
- **DOC** relative_path - part of nascent scheme, builds
  a list of Documents associated with the repo.
  A DOC is a *file* that must exist at this time.
  It can be anything, but I typically use *.md* files
  for my published repo's documentation.
- **PAGE_HEADER** - boolean, or arbitrary value,
  This is part of a nascent scheme to implement
  automatically created, organized headers at the top
  of my .MD files.


## Description Mapping

*this goes into design.md or implementation.md*

The *description* of a repo is gotten from GitHub.

IF the description includes "Copied from blah" followed
by a space, the {parent} member will be display as (blah),
and like a FORKED repo, a Browser link to the GitHub repo
will be provided in the infoWindow.


## Example

Here is my current gitUI_config.txt, in it's entirety.
As you can see I am managing just about 100 repositories on gitHub.
I often make related changes to 3-5 repos every few hours.

``` conf
#-------------------------------------------------------
# This file contains a list of all my git repositories
#-------------------------------------------------------
# The root project is /src/phorton1
# GROUPS are recursive through USES and FRIEND.
# 	only the highest level repos need to be specified as groups.
# 	The recursion should be handled in parseRepos()

#-------------------------------------------------------
SECTION	/junk
#-------------------------------------------------------

/junk/test_repo
	PRIVATE
	SUBMODULE	copy_sub0	/junk/test_repo/test_sub1
/junk/test_repo/test_sub1
	PRIVATE
/junk/test_repo/test_sub2
	PRIVATE
/junk/test_repo2
	PRIVATE
	# ERRORS an artificially generated error in git_repositories.txt
	SUBMODULE	copy_sub1	/junk/test_repo/test_sub1

#-------------------------------------------------------
SECTION	/src/phorton1
#-------------------------------------------------------
# All MD links are now absolute from the root
# MD files can have multiple levels of recursion (subdirectories)
# /docs/readme.md is always called 'Home'

/src/phorton1
	DOCS /readme.md
	DOCS /vGuitar.md
	DOCS /Artisan.md

#-------------------------------------------------------
SECTION	/base
#-------------------------------------------------------

/base
	PRIVATE
	# DOCS /bat/readme.md
	# Doc is not proper Markdown
	USES /Perl
/base/apps/artisan
	GROUP Artisan
	DOCS /docs/readme.md
	USES /Perl
	USES /base/Pub
	USES /src/fpcalc/releases
/base/apps/artisanWin
	GROUP Artisan
	DOCS /docs/readme.md
	USES /Perl
	USES /base		# base/MyWX
	USES /base/My
	USES /base/apps/artisan
/base/apps/buddy
	DOCS /docs/readme.md
	DOCS /docs/design.md
	DOCS /releases/readme.md
	USES /Perl
	USES /base/Pub
/base/apps/ebay
	PRIVATE
	USES /Perl
	USES /base/My
/base/apps/file
	PRIVATE
	USES /Perl
	USES /base
	USES /base/My
/base/apps/fileClient
	DOCS /docs/readme.md
	USES /Perl
	USES /base/Pub
/base/apps/gitUI
	DOCS /docs/readme.md
	PRIVATE
	USES /Perl
	USES /base/Pub
/base/apps/inventory
	DOCS /docs/readme.md
	PRIVATE
	USES /Perl
	USES /base/Pub
/base/apps/minimum
	PRIVATE
	USES /Perl
	USES /base
	USES /base/My
/base/apps/myIOTServer
	SUBMODULE	site/myIOT	/src/Arduino/libraries/myIOT/data_master
	USES /Perl
	USES /base/Pub

/base/MBE
	PRIVATE
	USES /Perl
	USES /base
	USES /base/My
/base/MBE/CM
	PRIVATE
	USES /Perl
	USES /base
	USES /base/MBE
	USES /base/MBE/PA
	USES /base/My
/base/MBE/PA
	PRIVATE
	USES /Perl
	USES /base
	USES /base/MBE
	USES /base/My
/base/MBE/Server
	PRIVATE
	USES /Perl
	USES /base/My
/base/My
	PRIVATE
	USES /Perl
/base/Pub
	DOCS /docs/readme.md
	DOCS /docs/folders.md
	DOCS /docs/fs_issues.md
	DOCS /docs/fs_protocol.md
	DOCS /docs/fs_transfers.md
	DOCS /docs/prefs.md
	USES /Perl

#-------------------------------------------------------
SECTION	/src/Arduino
#-------------------------------------------------------
# an Arduino library NEED with a "version" is installable
#    from the Arduino IDE

/src/Arduino
	PRIVATE
	DOCS /readme.md
	DOCS /_esp8266/readme.md
	DOCS /random_clock/docs/period.md
	DOCS /vacuum1/docs/readme.md
	NEEDS /src/Arduino/libraries/APDS9930	# version=1.5.1
		# used by _test/ProximitySensor
/src/Arduino/_vMachine
	PAGE_HEADER
	DOCS /docs/readme.md
	DOCS /docs/history.md
	DOCS /docs/hardware.md
	DOCS /docs/electronics.md
	DOCS /docs/software.md
	DOCS /docs/installation.md
	DOCS /docs/notes.md  UNLINKED
	USES /src/Arduino/libraries/FluidNC
	USES /src/Arduino/libraries/FluidNC_Extensions
	USES /src/Arduino/libraries/FluidNC_UI
	NEEDS /src/Arduino/libraries/Adafruit_NeoPixel version 1.7.0
/src/Arduino/bilgeAlarm
	SUBMODULE	data	/src/Arduino/libraries/myIOT/data_master
	PAGE_HEADER
	DOCS /docs/readme.md
	DOCS /docs/history.md
	DOCS /docs/previous.md
	DOCS /docs/design.md
	DOCS /docs/hardware.md
	DOCS /docs/software.md
	DOCS /docs/user_interface.md
	USES /src/Arduino/libraries/myIOT
	NEEDS /src/Arduino/libraries/Adafruit_NeoPixel version 1.7.0
	NEEDS /src/Arduino/libraries/LiquidCrystal_I2C version 1.1.2

/src/Arduino/CoilWindingMachine
	DOCS /docs/readme.md
	USES /src/Arduino/libraries/myDebug
	NEEDS /src/Arduino/libraries/AccelStepper version 1.61.0

/src/Arduino/esp32_cnc20mm
	PAGE_HEADER
	DOCS /docs/readme.md
	DOCS /docs/design.md
	DOCS /docs/details.md
	DOCS /docs/electronics.md
	DOCS /docs/box.md
	DOCS /docs/spindle.md
	DOCS /docs/y_axis.md
	DOCS /docs/table.md
	DOCS /docs/build.md
	DOCS /docs/laser.md
	DOCS /docs/accessories.md
	DOCS /docs/software.md
	DOCS /docs/notes.md
	DOCS /docs/projects.md
	USES /src/Arduino/libraries/FluidNC
	USES /src/Arduino/libraries/FluidNC_Extensions
	USES /src/Arduino/libraries/FluidNC_UI
	NEEDS /src/Arduino/libraries/Adafruit_NeoPixel version 1.7.0
/src/Arduino/esp32_cnc3018
	PAGE_HEADER
	DOCS /docs/readme.md
	DOCS /docs/history.md
	DOCS /docs/hardware.md
	DOCS /docs/electronics.md
	DOCS /docs/software.md
	DOCS /docs/installation.md
	DOCS /docs/version2.md
	USES /src/Arduino/libraries/FluidNC
	USES /src/Arduino/libraries/FluidNC_Extensions
	USES /src/Arduino/libraries/FluidNC_UI
	NEEDS /src/Arduino/libraries/Adafruit_NeoPixel version 1.7.0

/src/Arduino/teensyExpression
	GROUP vGuitar
	DOCS /docs/readme.md
	DOCS /docs/hardware.md
	DOCS /docs/design.md
	DOCS /docs/ui.md
	DOCS /docs/filesystem.md
	DOCS /docs/3d.md
	DOCS /docs/ftp.md
	DOCS /docs/songmachine.md
	USES /src/Arduino/libraries/ILI9341_fonts
	USES /src/Arduino/libraries/my_LCDWIKI_GUI
	USES /src/Arduino/libraries/my_LCDWIKI_KBV
	USES /src/Arduino/libraries/my_LCDWIKI_TouchScreen
	USES /src/Arduino/libraries/myDebug
	USES /src/Arduino/libraries/SdFat
	USES /src/Arduino/libraries/USBHost_t36
	NEEDS /src/Arduino/libraries/base64	version 1.0.0
/src/Arduino/teensyExpression2
	GROUP vGuitar
	PRIVATE		# temporary
	DOCS /docs/readme.md
	DOCS /docs/rewrite.md
	DOCS /docs/rig_language.md
	DOCS /docs/rig_language_old.md
	DOCS /docs/rig_parser.md
	DOCS /docs/teensyDuino.md
	USES /src/Arduino/libraries/ILI9341_fonts
	USES /src/Arduino/libraries/my_LCDWIKI_TouchScreen
	USES /src/Arduino/libraries/myLCD
	USES /src/Arduino/libraries/myDebug
	USES /src/Arduino/libraries/SdFat
	USES /src/Arduino/libraries/USBHost_t36
	NEEDS /src/Arduino/libraries/base64	version 1.0.0
/src/Arduino/teensyPi
	DOCS /docs/readme.md
	USES /src/Arduino/libraries/myDebug
/src/Arduino/teensyPiLooper
	GROUP vGuitar
	DOCS /docs/readme.md
	USES /src/Arduino/libraries/myDebug
/src/Arduino/theClock
	SUBMODULE	data	/src/Arduino/libraries/myIOT/data_master
	DOCS /docs/readme.md
	USES /src/Arduino/libraries/myIOT
	NEEDS /src/Arduino/libraries/Adafruit_NeoPixel version 1.7.0
/src/Arduino/theClock3
	SUBMODULE	data	/src/Arduino/libraries/myIOT/data_master
	PAGE_HEADER
	DOCS /docs/readme.md
	DOCS /docs/design.md
	DOCS /docs/plan.md
	DOCS /docs/wood.md
	DOCS /docs/coils.md
	DOCS /docs/electronics.md
	DOCS /docs/firmware.md
	DOCS /docs/assemble.md
	DOCS /docs/build.md
	DOCS /docs/tuning.md
	DOCS /docs/ui.md
	DOCS /docs/software.md
	DOCS /docs/troubles.md
	DOCS /docs/notes.md
	USES /src/Arduino/libraries/myIOT
	NEEDS /src/Arduino/libraries/Adafruit_NeoPixel version 1.7.0
	NEEDS /src/Arduino/libraries/AS5600 version 0.3.5

/src/Arduino/Tumbller
	# complicated - dependencies not resolved
	PRIVATE
	DOCS /readme.md
	DOCS /esp8266Client/readme.md
	DOCS /esp8266Server/readme.md
	DOCS /tumblerRemote/readme.md
	DOCS /Tumbller2/readme.md
/src/Arduino/useless
	PAGE_HEADER
	DOCS /docs/readme.md
	DOCS /docs/electronics.md
	DOCS /docs/wood.md
	DOCS /docs/top.md
	DOCS /docs/bottom.md
	DOCS /docs/software.md
	USES /src/Arduino/libraries/myDebug
	NEEDS /src/Arduino/libraries/VarSpeedServo
	NEEDS /src/Arduino/libraries/Adafruit_NeoPixel version 1.7.0

#-------------------------------------------------------
SECTION	/src/Arduino/libraries
#-------------------------------------------------------
# MINE FIRST

/src/Arduino/libraries/FluidNC
	NOT_MINE
	DOCS /readme.md
	DOCS /gcodes.md
	NEEDS  /src/Arduino/libraries/ESP32SSDP	# version 1.1.0
	NEEDS /src/Arduino/libraries/WebSockets version 2.3.6
		# the one from FluidNC is v2.1.2
	NEEDS /src/Arduino/libraries/TMCStepper version 0.7.1
/src/Arduino/libraries/FluidNC_Extensions
	DOCS /readme.md
	USES /src/Arduino/libraries/FluidNC
/src/Arduino/libraries/FluidNC_UI
	PAGE_HEADER
	DOCS /docs/readme.md
	DOCS /docs/overview.md
	DOCS /docs/software.md
	DOCS /docs/installation.md
	USES /src/Arduino/libraries/FluidNC
	USES /src/Arduino/libraries/FluidNC_Extensions
	USES /src/Arduino/libraries/TFT_eSPI
/src/Arduino/libraries/my_LCDWIKI_GUI
	NOT_MINE
	USES /src/Arduino/libraries/myDebug
	USES /src/Arduino/libraries/ILI9341_t3   				# ifdef __MK66FX1M0__ (teensy3.6)
/src/Arduino/libraries/my_LCDWIKI_KBV
	NOT_MINE
	USES /src/Arduino/libraries/myDebug   					# ifdef __MK66FX1M0__ (teensy3.6)
	USES /src/Arduino/libraries/my_LCDWIKI_GUI
/src/Arduino/libraries/my_LCDWIKI_TouchScreen
	NOT_MINE
/src/Arduino/libraries/myDebug
	DOCS /docs/readme.md

/src/Arduino/libraries/myIOT
	SUBMODULE	data	/src/Arduino/libraries/myIOT/data_master
	SUBMODULE	examples/testDevice/data	/src/Arduino/libraries/myIOT/data_master
	PAGE_HEADER
	DOCS /docs/readme.md
	DOCS /docs/getting_started.md
	DOCS /docs/wifi.md
	DOCS /docs/basics.md
	DOCS /docs/how_to.md
	DOCS /docs/design.md
	DOCS /docs/details.md
	USES  /src/Arduino/libraries/ESPTelnet								# if WITH_TELNET
	NEEDS /src/Arduino/libraries/ArduinoJson version 6.18.5				# if WITH_WS
	NEEDS /src/Arduino/libraries/WebSockets version 2.3.6				# if WITH_WS
		# the one from FluidNC is v2.1.2
	NEEDS /src/Arduino/libraries/PubSubClient version 2.8.0				# if WITH_MQTT
/src/Arduino/libraries/myIOT/data_master
	# the master /data submodule for all myIOT projects
	# including Perl myIOTServer

/src/Arduino/libraries/myLCD
	DOCS /docs/readme.md
	USES /src/Arduino/libraries/myDebug
	USES /src/Arduino/libraries/ILI9341_t3								# if __LCD_TEENSY__ (teensy3.6 and 4.0)

# Slightly modified

/src/Arduino/libraries/ESPTelnet	main
	FORKED modified version 2.1.2
	DOCS /CHANGELOG.md
	DOCS /README.md
/src/Arduino/libraries/SdFat
	FORKED modified version 1.1.4
	# version number from Arduino IDE
	# version number is not in library.properties
	DOCS /LICENSE.md
	DOCS /README.md
/src/Arduino/libraries/USBHost_t36	prhChanges
	FORKED modified version 0.1 ha ha ha
    # Note prhChanges branch; needed after I reforked
	DOCS /examples/Bluetooth/Pacman-Teensy-BT/README.md

# Unmodified, but kept as forks anyways

/src/Arduino/libraries/ILI9341_fonts
	# not installable or reported by Arduino IDE
	FORKED unmodified unversioned version
	DOCS /README.md
	USES /src/Arduino/libraries/ILI9341_t3
/src/Arduino/libraries/ILI9341_t3
	# reported and installable by Arduino IDE
	# but i'm keeping the fork anyways
	FORKED unmodified version 1.0
	DOCS /docs/issue_template.md
	DOCS /examples/DemoSauce/README.md
/src/Arduino/libraries/TFT_eSPI
	# shouldn't need to modify this in order to use it
	FORKED modified version 2.3.70
	DOCS /README.md
	DOCS /Tools/Images/README.md

# TODO: Unmodified but forks cuz not installable from Arduino IDE
#
# /src/Arduino/libraries/VarSpeedServo
#       # not installable or reported by Arduino IDE
#		# currently from /zip VarSpeedServo-master
# /src/Arduino/libraries/ESP32SSSDP
#       # not installable or reported by Arduino IDE
#       # currently from /zip/arduino/libraries version 1.1.0
#		# from FluidNC:  version 1.0
# /src/Arduino/libraries/ESP32SSDP	# version 1.1.0
#       # not installable or reported by Arduino IDE
#		# from FluidNC:  version 1.0


#-------------------------------------------------------
SECTION	Miscellaneous
#-------------------------------------------------------

/base_dist/buddy
	PRIVATE
	USES /Perl
	USES /base/apps/buddy
	USES /base/apps/fileClient
/base_dist/cm
	PRIVATE
	USES /Perl
	USES /base/MBE
	USES /base/MBE/CM
/dat/Rhapsody
	PRIVATE
/etc
	PRIVATE
/Users/Patrick/AppData/Local/ActiveState/KomodoEdit/8.5/tools
	PRIVATE
/mbeSystems/masterServer
	PRIVATE
/Perl
	PRIVATE
	NOT_MINE
	USES /src/wx/Win32_OLE
	USES /src/wx/wxActiveX
	USES /src/wx/wxAlien/wxWidgets-3.0.2
	USES /src/wx/wxPerl
/Strawberry
	NOT_MINE
	DOCS /readme.md

#-------------------------------------------------------
SECTION	/src/Android	Android
#-------------------------------------------------------

/src/Android/Artisan
	GROUP Artisan
	DOCS /docs/readme.md
	USES /src/fpcalc/releases	 # for fpCalxXXX.exe
/src/Android/BtTest
	PRIVATE
/src/Android/cmWorker
	PRIVATE
/src/Android/testFpCalc
	DOCS /docs/readme.md
	USES /src/fpcalc/releases	 # for fpCalxXXX.exe
/src/Android/testMySQL
	PRIVATE
/src/Android/Tumbler2
	PRIVATE


#-------------------------------------
SECTION	/src
#-------------------------------------

/src/circle
	FORKED
	MINE
	DOCS /README.md
/src/circle/_prh
	DOCS /readme.md
	DOCS /audio/readme.md
	DOCS /bootloader/README.md
	DOCS /lcd/readme.md
	DOCS /examples/07-LinkerTest/readme.md
	DOCS /examples/07-testProgram/readme.md
	DOCS /examples/08-LinkerTest2/testProgram1/readme.md
	DOCS /examples/08-LinkerTest2/testProgram2/readme.md
	USES /src/circle
/src/circle/_prh/_apps/Looper
	GROUP vGuitar
	PAGE_HEADER
	DOCS /readme.md  UNLINKED SHOULD BE REMOVED
	DOCS /docs/readme.md
	DOCS /docs/hardware.md
	DOCS /docs/software.md
	DOCS /docs/ui.md
	DOCS /docs/protocols.md
	DOCS /docs/details.md
	DOCS /docs/looper1.md
	DOCS /docs/looper2.md
	DOCS /docs/junk.md	UNLINKED
	USES /src/circle/_prh

/src/FluidNC	prhChanges
	FORKED
	DOCS /README.md
	DOCS /CodingStyle.md
	DOCS /VisualStudio.md
	NEEDS  /src/Arduino/libraries/ESP32SSDP	# version 1.1.0
	NEEDS /src/Arduino/libraries/WebSockets version 2.3.6
		# the one from FluidNC is v2.1.2
	NEEDS /src/Arduino/libraries/TMCStepper version 0.7.1
/src/FluidNC_WebUI
	PRIVATE
	DOCS /readme.md

/src/kiCad/libraries
	PRIVATE

/src/fpcalc/chromaprint
	NOT_MINE
	DOCS /README.md
	USES /src/fpcalc/ffmpeg
/src/fpcalc/ffmpeg
	NOT_MINE
	DOCS /INSTALL.md
	DOCS /LICENSE.md
	DOCS /README.md
/src/fpcalc/releases
	DOCS /README.md
	USES /src/fpcalc/chromaprint
/src/fpcalc/stuff
	USES /base/My		# Utils
/src/fpcalc/test

/src/projects/fan1
	DOCS /readme.md
	DOCS /survey.md
/src/projects/synthbox1
	# no source just stl for thingyverse
	DOCS /readme.md
/src/projects/ws2812bSwitchArray1
	# has local copy of old /src/Arduino/libraries/myDebug
	DOCS /docs/readme.md
	DOCS /docs/src.md
	DOCS /docs/stl.md

/src/rPi		# c++ rPi RPIOTServer - obsolete?
	PRIVATE

/src/wx/Win32_OLE
	NOT_MINE
/src/wx/wxActiveX
	NOT_MINE
	DOCS /readme.md
/src/wx/wxAlien
	NOT_MINE
	DOCS /README.md
/src/wx/wxAlien/wxWidgets-3.0.2
	NOT_MINE
	DOCS /README.md
/src/wx/wxPerl
	NOT_MINE
	DOCS /readme.md
	USES /src/wx/wxAlien/wxWidgets-3.0.2

#----------------------------------------------------------------------------------
SECTION	/Users/Patrick/AppData/Roaming/Autodesk/Autodesk Fusion 360/API/AddIns/	 Fusion-Addins
#--------------------------------------------------------------------------------

/Users/Patrick/AppData/Roaming/Autodesk/Autodesk Fusion 360/API/AddIns/prhParams
/Users/Patrick/AppData/Roaming/Autodesk/Autodesk Fusion 360/API/AddIns/pyJoints
	PAGE_HEADER
	DOCS /docs/readme.md
	DOCS /docs/getting_started.md
	DOCS /docs/basics.md
	DOCS /docs/inputs.md
	DOCS /docs/steps.md
	DOCS /docs/gifs.md
	DOCS /docs/details.md

#-------------------------------
SECTION	/var/www
#-------------------------------

/var/www/mbebocas
	PRIVATE  # very nearly obsolete
/var/www/mbesystems
	PRIVATE
/var/www/phnet
	PRIVATE
	USES /Perl
	USES /base/My
/var/www/phorton
	PRIVATE		# possibly to become public

#-------------------------------------------------
SECTION	/src/obs	Obsolete
#-------------------------------------------------

/base/apps/backup
	PRIVATE			# obsolete
	USES /Perl
	USES /base
	USES /base/My
/base/apps/songManager
	PRIVATE			# obsolete
	USES /Perl
	USES /base
	USES /base/My

/src/obs/Arduino/libraries/myIOT
	PRIVATE		# nearly obsolete
	# History before fresh commit for public myIOT library

/src/obs/base/MBE/ST
	PRIVATE 	# obsolete
	USES /Perl
	USES /base/MBE
	USES /base/My
/src/obs/base/MBE/ST/Common
	PRIVATE 	# obsolete
	USES /Perl
	USES /base/MBE
	USES /base/My
/src/obs/base/MBE/Store
	PRIVATE 	# obsolete
	USES /Perl
	USES /base/MBE
	USES /base/My
/src/obs/base/MBE/Web
	PRIVATE 	# obsolete
	USES /Perl
	USES /base/MBE
	USES /base/My
```


-- end of readme ---
