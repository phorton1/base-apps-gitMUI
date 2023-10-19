# gitUI

-------------------------------------b-
Interesting.  I am starting to understand.

In the /.git repository there are two files
	/.git/index - can check date time stamp for staged changes
	/.git/HEAD - contains "ref: refs/heads/master"

Then you can go to the "refs" folder to get the commit_id
	/.git/refs/heads/master	contains "022a3906a60d79c9d26fcace09836dfb810333b7"

Likewise, there is a directory called "remotes" that has and "origin" subfolder
	in which there are "HEAD" and "master" files
	/.git/remotes/origin/HEAD contains "ref: refs/remotes/origin/master", and
	/.git/remotes/origin/master contains "022a3906a60d79c9d26fcace09836dfb810333b7"

So I can cache the timestamps of the following files
	/.git/index - change indicates a change to/from {staged_changes}
	/.git/refs/heads/master - change indicates a "commit" was performed
		- implies clearing of {staged_changes}
		- sort of implies changes to {remote_changes'}
		  and a push is (probably) needed.
	/.git/remotes/origin/master indicates a "push" was performed
		- implies clearing of {remote_changes}

I don't have a fast way of determining if "unstaged_changes" were
	added due to new/delete/changed files









I can use the datetime stamps on /.git/index, /.git/HEAD

--------------------------------------

The repo list is quickly built when the program is started, including
using a cached version of the data from github (descriptons, fork status,
etc).

There are certain operations that refresh the list that take significant itme.

- Scanning all repositories for changes
- Refreshing the information from github.
- Looking for broken links, and other as-yet undetermined utilities

Particularly, scanning repositories for changes takes 5-15 seconds.
There is a difference betwen "my" code and "copies/forks/libraries".
Certain repositories change infrequently and take the most time.

- Forks and Copies
- Perl / Strawberry

Often my focus is on a particular set of programs. i.e. MBE

Presentation is an issue I have not gotten my head around.
I think of several different presentation paradigmns:

- Repository Overview
  - shows all repositories on a single non-scrolling page
- Repository Tree
  - shows a tree like structure that can be expanded to
    show details, like dependencies, descriptions, etc
- Stage/Commit/Diff ui
  - like current gitUI but works on multiple repositories
    with tree like structures in the left hand windows.
- Details
  - tree like structure in left, details on right
- Modeless dialogs - for repository details


## wxWidget objects vs. roll-my-own

- The wxWidgets list object allows multiple selection.
- it is tempting to use HTML for presentation
- Tree structures are complicated










## Maintaining the REPO_LIST

Assuming single program (process).

With Multiple windows presenting the list.

With Commands that can modify it.


- current pathWindow ALL BY SECTIONS
- CHANGED REPOS showing files
- whole UI with STAGE and FILE DIFFS splitters

I'm pretty sure Git::Raw can do all the things that the
real gitui uses to show DIFFS.

It's almost as if I want a MULTI-REPOSITORY GIT_UE

Upper left shows expandable TREE of repos with changes
that allows for multi selections including whole subtrees

Bottom left shows similar expandable TREE of repos with
changes.

Right side shows the diffs in either



ALL REPOS BY SECTIONS
ALL CHANGED REPOS (by sections)
separate out MY source code from COPIES/FORKS
big difference between

- UNMODIFIED FORKS (i.e. base64),
- SLIGHTLY MODIFIED FORKS (i.e. TFT_eSPI), and
- HEAVILY MODIFIED FORKS.

"COPIES" should not exist.

WORRIES about Arduio IDE installed libraries
and versioning if I need to make a new machine.

- AccelStepper
- Adafruit_NeoPixel
- APDS9930 (nearly unused)
- ArduinoJson
- AS5600
- cnc_TMCStepper (denormalized from FluidNC)
- ESP32SSDP-1.1.0
- ESP_Telnet
- LiquidCrystal_I2C
- PubSubClient
- Servo
- VarSpeedServo-master
- XPT2046_Touchscreen-master

and, of course, TeensyDuino and SdFat versus
my (old, slightly modified fork).


Perl is it's whole own animal, especially around
the notion that I have rigidly maintain MBE cmManager
and the complications of my own WxWidgets and things
like mods to IO::Socket, or Win32::ComPort, and
the recent complicated install of Git::Raw

WORRIED about historical CREDENTIALS in repositories
from old Wifi passwords, to EBAY api tokens, to the
rigid and crucial encryption of existing fileServers
and fileClient all over the place.

STILL have the issue of MBE licensing, use of my MIAMI
SERVER and more security issues there.























This program is all about presenting ALL or certain SUBSETS of my
repositories for viewing, analysis, and actions.

It started as GIT_CHANGES .. a script that could check for CHANGES
across all my repos, and then do COMMITS, and/or PUSHES on those that
had local or remote changes.

It presently adds the ability to SEE the repositories sorted by
SECTIONS and to invoke the actual GITUI by clicking on a link,
as well as do those sem GIT_CHANGES commands with a progress window.

The following are well defined

- PRIVATE/public
- FORKED (or copied)

The following is currently used, but too rigid

- SECTION

The following are in the repo list, but not shown in UI

- USES
- NEEDS

The following are not in repo list, but are in parser.

- GROUP
- FRIEND


## Command Processor

SELECTED repos versus WILDCARD repo patterns
PRESENTATION versus ACTIONS
STAGING (Add) verus COMMITTING
Visualing FILE diffs



## Other analysis ideas

- CORRECT GITHUB LINKS in MD files
- Libraries that SHOULD BE FORKS


------------------------------------------------


A COMMAND could be an object.
It could be threaded, or not.
It could have a progress dialog, or not.


MAINTAINING THE REPO LIST in memory
- i.e. a COMMIT clears local-changes?!?
