# Shared JS, CSS, and HTML files

The myIOT/data directory contains a version of jquery, bootstrap,
and some common JS, CSS, and HTML that is shared between Esp32
myIOT projects, as well as to the Perl apps::myIOTServer project.

The file captive.html is self contained and does not load any
additional JS, CSS, or HTML, and is only used in Esp32 projects.

In Esp32 projects, the entire contents of the /data directory
are uploaded to the **flat** SPIFFS file system and served from
there statically. A request to '/' gets turned into **index.html**,
which theen causes the browser to request the JS and CSS from the
HTTP Server.

The directory is called 'data' becuase that is the standard name
of an Arduino project directory that you upload to a SPIFFS
file system.


## Vestigial Design

Because SPIFFS is a flat file system, in the initial implentation
we simply mapped '/' to 'index.html' and serve any otherwise unhandled
requests as simple absolute file requests, thus serving any files that
are found on the SPIFFS system as 'root' files.

The bilgeAlarm stores the history.dat file in the root of the
SPIFFS as well, but it is never uploaded to the ESP32.  The clocks
don't upload anything special to, or otherwise use, the SPIFFS.

Super duper care was taken when implementing the Perl myIOTServer
to use the same common index.HTML, and the JS and CSS from the
/data directory.  The JS and CSS are *slightly* but **significantly**
modified to work with the myIOTServer to redirect to a given specific
device that is known to the myIOTServer.

The myIOTServer does not make use of captive.html. Care would have to
be taken to change the Wifi Host or Credentials in any myIOT thing
via any UI, as the very act of doing so **may** cause the connection
to be lost (the wifi host and credentials should only be picked up
in a reboot).


# New design with submodules

I have normalized the source for myIOT data.
It begins in /src/Arduino/libraries/myIOT/data_master,
and exists as submodules at the following locations

	/src/Arduino/libraries/myIOT/data
	/src/Arduino/libraries/myIOT/examples/testDevice/data
	/src/Arduino/bilgeAlarm/data
	/src/Arduino/theClock/data
	/src/Arduino/theClock3/data
	/base/apps/myIOTServer/site

I also want to normalize 'standard_system.h' somehow, and, in fact,
change it to 'standard_utils.js'.  Also of significance is that
the entire Inventory jquery is essentially a copy of that from Artisan with
an added 'DataTables', and minus 'fancyTree'.

There are a few other 'denormalized' files in my git repos, including
/src/circle/_prh/_apps/Looper/commonDefines.h which is copied to
/src/Arduino/teensyExpression and /src/Arduino/teensyExpression2, but
for now I am not going to worry about that, and just try to think about
the common HTML, JS, and CSS.



## Incorporation into my gitUI

The SUBMODULE specifier in git_repositories.txt tells
the system what submodules exist, and where to find them.

	SUBMODULE	rel_path	/actual/repository/path



## USING SUBMODULES

Adding a submodule to an existing project. For example, to add
the /src/Arduino/libraries/myIOT/data submodule to the myIOT/examples
folder, after removing and commiting the removal of the old data folder,

	cd /src/Arduino/libraries/myIOT
	git submodule add https://github.com/phorton1/Arduino-libraries-myIOT-data_master data
	git submodule add https://github.com/phorton1/Arduino-libraries-myIOT-data_master examples/testDevice/data

Cloning a repository that contains submodules is done automatically
if you pass --recursive on the command line:

	git clone --recursive https://github.com/phorton1/junk-test_repo2 some_other_name

After cloning a new submodules you *may* checkout the 'master' branch before proceeding,
possibly from the directory:

	git checkout master

Updating a repository that has submodules that are out of date, i.e.
after committing and pushing the /junk/test_repo1/test_sub1 repo,
the copy in test_repo2 can be updated by chdir /junk/test_repo2
and running:

	git submodule update --recursive --remote

On the rPi, which alreaady had a myIOT project, after my built-in
ServiceUpdate, it had the submodule, but an empty directy. ServiceUpdate.pm,
of course, did not handle the submodule update. I had to the submodule
update with --init

	git submodule update --init --recursive --remote

to get it to download the submodule. I may only need to do
that the first time. In any case I'm pretty sure as long as I
don't change the myIOT folder, the ServiceUpdate mechanism will
still get the rest of the myIOTServer source code changes ok.

My ServiceUpdate mechanism, and updating submodules in general
is "Work in Progress" as part of the GIT STATUS  project, currently
under the umbrella of this apps/gitUI project.


## EXPERIMENTS

- Status
- gitHub Events

More to be written.  Following comments are a bit stale.


## MANAGING CHANGES IN MULTIPLE REPOS

The rubber meets the road.

Submodules highlight the problem, but the issue of multiple changes
to the same repo from different copies existed already in my work
with rPi versus the Windows machine.

Each repo can (pretty) easily determine the number of changes it is
behind, or ahead, of the remote with the git commands command

	git remote update
	git status -b --porcelain'))

Git status returns an easily parsed message that looks like this:
(note the bracket needs to be escaped for MD file):

	master...origin/master \[ahead 1, behind 1]
	?? untracked_file
	_M modified file

### not BEHIND

As long as the local copy is not behind the remote,
commits make sense, at least for THIS local copy,
and a push will work.  Every commit will put you
one more 'ahead' of the remote, and the push will
make them the same.


### BEHIND and not AHEAD - STASH

Likewise, if behind != 0, and there are no local commits
(ahead==0) then  it is possible to update the local repo
from the remote using one of the git commands.

If there are local unstaged or staged changes, the process
can proceed as long as a 'stash' is done on the local first.
It is possible to then use that 'stash' against the new
repo to generate a new list of unstaged changes (I think).

### BEHIND AND AHEAD

The real problem arises when the local repository is both
behind, and ahead of the remote.  In otherwords, there are
local unpushed commits, and remote commits that need to be
merged.

I am not sure of all of the details, but I *think* an update
(fetch and automatic merge) can be done when the changes are
not on the same files.

But a PUSH will fail as the local repo is not starting at
the same commit as the remote repo, and it PUSH will tell
you that:

	ERROR - cannot push because a reference that you are trying
	to update on the remote contains commits that are not present
	locally.

This is a complicated situation that requires a merge, and
one I have not learned enough about.

### Initial Helper Implementation

To begin with I am going to try to implement a 'Status' button
in the repo info window that will add AHEAD and BEHIND fields
to the repo and redisplay it.

This *may* be done via new methods in repoGit, making use of
Git::Raw, or it may be implemented via backtick commands as is
currently don in Pub::ServiceUpdate.pm.







--------- end of readme ------------
