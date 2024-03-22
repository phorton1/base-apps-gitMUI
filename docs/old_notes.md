# gitMUI - old notes

#-----------------------------------------------
# History, events, and change detection
#-----------------------------------------------
# The experimental methods in this section try to accomplish
# several goals.
#
# We use the gitHub events API on a thread to detect pushes
# to gitHub that might take place on other machines, or from
# other submodules on the same machine, and if so, determine
# whether the local repo is AHEAD and or BEHIND,
# which, along with HAS_CHANGES, which is set if the repo has
# any uncommitted (unstaged or staged) changes determines whether
# we can automatically Update the repo(s) and if so, whether we
# would need a Stash to do so.
#
# The system does not handle repos that require Merges, that
# is, where commits to the same repo HEAD revision of a repo
# have been made from two different machines, or submodules
# on the same machine.
#
# We try to do all of this in a performant manner (i.e. quickly).
#
# The case of normalizing submodules locally can additionally
# detect not only if there pushes have occured and Updates
# are needed, but can detect denormalization due to uncommitted
# changes and commits before they are pushed.
#
# CHANGE DETECTION WITHOUT FETCHING
#
# Proper detection and implementation of repo normalization
# requires a somewhat complicated comparison of the two repo's histories,
# finding the most recent common ancestor, and then counting the
# commits after that for each repo, something that git is good
# at, to the degree that you first 'fetch' the the (remote) repo
# and then use standard git commands to identify and/or update-merge
# the two repos.
#
# However, I want this process to work without making ANY changes
# to the local machine. Once you do a Fetch you can find yourself
# in a situation where you MUST merge two repos with disparate
# changes, itself a complicated process that can backfire.
#
# What I am looking for is a way to determine if a repo is out
# of date with respect to the remote, and if I can SAFELY
# Fetch and Update it, possibly with a Stash, automatically.
# Thus I want it to detect whether a Merge would be needed,
# and to notify me about that.
#
# This can sort-of be done by gathering key commit identifiers,
# SHA's, from the local repos, which can be done relatively
# quickly, and then, by using a cache and gitHub events,
# compared to the remote (gitHub) repository for change detection.
#
# KEY COMMIT ID'S
#
# For each I get the following commit ids:
#
#		head_id = HEAD - the commit the repo is at
#		master_id = refs/heads/$branch - the most recent commit in the main branch
#		remote_id = refs/remotes/origin/$branch - the last sync with gitHub
#
# Invariants:
#
# 	Because I always check into the default branch on gitup
# 	I don't need to additionally get the refs/remotes/origin/HEAD
#	commit id, as it should always be the same as the
#	refs/remotes/origin/$branch id, even if they both happen
#	to be out of date on the local machine.
#
#	When my system is in a stable state, i.e. I am not in the middle
#   of doing an Update (Fetch, possible Stash, and then Pull or Rebase),
#   then head_id should always equal the master_id. That is to say that
#   the HEAD commit should always be the same as the $branch commit
#   in any repos.
#
#	This last one is furthered by the fact that my repos should NEVER
#   have a Detached HEAD, that is a repo that is not checked out to the
#   main $branch.  This can occur (early) in submodule development when
#   cloning a new submodule, care must be taken to make sure that it is
#	checked out to the main $branch.
#
# We can use the existing gitChanges() and the new head_id to quickly
# determine when submodules are denormalized.  These id's will need to
# be updated locally in gitPush() and gitComit() after the system is
# initialized (scanned).
#
# gitHub EVENTS
#
# The gitHub event API will give us a list of the most recent pushes
# to gitHub, along with the repo paths and commit_ids in those pushes.
# The event history goes back a maximum of 90 days.
#
# It is **safe** to assume that if a repo has not been pushed in
# a long time, that I have the current version on the local machine,
# i.e. BEHIND === 0
#
# At this point I need to switch to experimental code to continue.
# It seems like, especially since I will be in a thread, that I
# can analyze every push event and use the local git history to
# determine the most recent common ancestor and the AHEAD and
# BEHIND numbers.


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

Can I quickly determine if a repo is "big"??

I don't think using use Win32::ChangeNotify is a good solution.


What if?
	For each repo I cache the 'most recent dt change' as
		the latet of the above timestamps.
	I have a thread which monitors the timestamps and
		checks for changes and notifies for active repos.
	A certain number of the most recent repos (say 10)
		are considered active, and are checked for local
		unstaged changes in the thread, which also modifies their timestamp.


	The user specifies an amount of time (say 48 hours)
		by which a repo is automatically determined to be 'active'
	A manual scan sets the most recent time if any unstaged changes.
		so infrequent changes to big repos like Perl can be dealt
		with via a manual scan, but normally, the (background threaded)
		scan only works on the 'active' repos.


	I keep track of a number of 'active' repos, say 10
	- a manual rescan will force any new repos with unstaged_changes into
	  'active' mode.

	  changed
		any repo with an add,commit, or push in the last 24 hour (period of time)
			is 'active'.

	I run a full scan (in a thread) on startup
		.. it will take some time for the batch of changes to show








I can use the datetime stamps on /.git/index, /.git/HEAD

--------------------------------------

The repo list is quickly built when the program is started, including
using a cached version of the data from gitHub (descriptons, fork status,
etc).

There are certain operations that refresh the list that take significant itme.

- Scanning all repositories for changes
- Refreshing the information from gitHub.
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
  - like current gitMUI but works on multiple repositories
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

- CORRECT gitHub LINKS in MD files
- Libraries that SHOULD BE FORKS


------------------------------------------------


A COMMAND could be an object.
It could be threaded, or not.
It could have a progress dialog, or not.


MAINTAINING THE REPO LIST in memory
- i.e. a COMMIT clears local-changes?!?
