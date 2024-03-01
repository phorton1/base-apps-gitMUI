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

	NOTE THIS DOES NOT MOVE THE LOCAL SUBMODULE TO
	the remote master's head. It merely fetches it,
	allowing you to then do a "git pull" or "git rebase"
	that updates the head. EVEN THOUGH you will still get
	a delta in the parent project, it would be futile to
	'commit' that delta until after the local submodule
	is brought up to the remote head.


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


--------------------------------------------------------------------------


## CONTINING STATUS/CHANGES analysis

OK, so its really complicated.

Here's the current test case:

- make a change to readme.md in /theClock3 data
- commit and push that change from gitGUI in /theClock3/data
- commit and push the parent 'data' change

Even that was a bit like pulling teeth.  In fact, had it
been real work I would have lost my changes, something having
to do with not having the 'master' branch checked out,
and not being able to 'fast-forward' in the push.  Then
I pressed some buttons, trying to get it normalized, and
I ended up 'merging' my changes away, which, uhm, I guess
were lost on some HEAD that no longer exists.

In any case, now the myIOT/data_master, and all of the
other submodules, are out of date with respect to github.
Once again, I would like to try to identify that WITHOUT
doing a fetch or update on the other guys.  Therefore
I am going to experiment some more with github events,
getting the SHA of the commit and comparing it to the
(unchanged and unchanging) information available locally.

BTW, the monitor for myIOT/data was not created correctly.

Here are the SHA's I could dig up, either by looking at git
files, or by calling the 'repoHistory'

/theClock3/data	- the source of the change - has an SHA of:

	2f3c4becfd6e1a46c2887a009c3e7cb7be6d46ca

As gotten from gitGUI's history, and is also the 'full SHA' for
the last commit to /myIOT/data_master on github.

	C:\src\Arduino\theClock3\.git\modules\data\refs\heads\master
	C:\src\Arduino\theClock3\.git\modules\data\refs\remotes\origin\master
	C:\src\Arduino\theClock3\.git\modules\data\FETCH_HEAD as the sha followed by:
		branch 'master' of https://github.com/phorton1/Arduino-libraries-myIOT-data_master
	C:\src\Arduino\theClock3\.git\modules\data\logs\HEAD  as the last commit of 5 in the file
	C:\src\Arduino\theClock3\.git\modules\data\logs\refs\heads\master  as the last commit of 3 in the file
	C:\src\Arduino\theClock3\.git\modules\data\logs\refs\remotes\origin\master  as the last commit of 2 in the file


I am not sure how confident I am that the way I get a repo's history is 'better'
than looking directly in git files.  It would certainly require a 'fetch' to
see whats on the server.  Let's see what comes up in the events file.

The SHA shows up in a current 'event' json file under a commit.

The other projects are

/myIOT/data_master
/myIOT/data
/myIOT/examples/testData/data
/theClock/data
/bilgeAlarm/data
/myIOT/site/myIOT


## Using repoHistory (or variant of it)

There are (upto) four different commits of interest in the local
repository:

	HEAD = $head_id
	refs/heads/$branch = $master_id
	refs/remotes/origin/HEAD ==
	refs/remotes/origin/$branch = $remote_id

We will need to know all the commits in-between the newest, and the oldest, of these,
or, in otherwords, work backwards through the history until we have satisfied gotten all
of the appropiate commits.

All repos will have a common ancestor in the remote.
On the remote HEAD will always equal $branch because I always push to the default repo.

The idea is to 'base' the entire system when I know it is all up-to-date, and set
the ETag for subsequent events.  Then keep track of any pushes to the remote which
then become available to all submodules (all repos).







There should be events that line up with the remotes/origin/HEAD



I guess the facts I am most interested in are:

- what is the SHA of the last 'sync' with the remote (the remote/master head)
- what is the SHA of the current local master/head
  - and is it different than the remote/master head?
  - and if so, how many local commits are we AHEAD by

From the event history, if maintained rigourously, I could see
a list of remote commits made by other machines/modules. Once
again initializing such a cache would easiest be done from the
history when I know all pushes are done and everything is up
to date.  This is a bit of stuff to put on my repos.

	master_head:
	remote_head:
	num_local_commits:

	remote_commits: [] an array of things built by
	event monitoring.






--------- end of readme ------------
