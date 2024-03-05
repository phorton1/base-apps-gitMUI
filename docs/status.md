# gitStatus and Updating

Maintaining the status of the repositories vis-a-vis local versus
github, and the consistency of submodules, is rather complicated,
and a bit time consuming.  Updating, either pulling from github
or normalizing local submodules, is even more complicated.

Checking of the status versus github requires, obviously, an internet
conntection. Automatic realtime checking is rate limited
to one check per minute.

There are, I believe, currently some problems with the commitWindow
and submodules-within-parents.

This document describes mods to the program 2024-03-03

The head_id, master_id, and remote_id have already been
added to, and maintained, for every repo in repoGit().


## gitStatus.pm

A new module, gitStatus.pm has been created.
It contains the updateStatus thread.

There is a preference, GITHUB_UPDATE_INTERVAL, default 90,
which *should* be set to 0 or a minimum of 60, that will cause
the thread to check for changes to github events, and/or to check
the integrity of local subodules.

The updateStatus thread does the behind-the-scenes work
to get github events and place fields on all of the repos
necessary to determine the status of a repo.

- HEAD_ID, MASTER_ID, REMOTE_ID - local commit ids
  are automatically gotten during gitParse() and updated
  during gitChanges(), gitCommits(), and gitCommits.

- github events - is a json data structure containing a list
  of the most recent pushes to github, and the commits within
  those pushes.  We get it initially into a cache at program startup,
  and then update the cache, using the ETag header, which will only
  return events if they have changed since the last ETag, therafter.

- GITHUB_ID - the SHA of the most recent commit found for a
  given repo in the github events.

- local_commits - an abreviated list of the local repo history
  containing the local commits back to the eearlist of HEAD_ID,
  MASTER_ID, AND REMOTE_ID.

- remote_commits - a list of any commits that we find in the
  github events for the given repo.

- AHEAD - number of local_commits between REMOTE_ID and MASTER_ID -
  this is the number of unpushed commits
- BEHIND - number of remote commits between REMOTE_ID and GITHUB_ID
  this is the number of commits made to the repo from other sources
  that are not present on the machine

- SUB_AHEAD AND SUB_BEHIND - possible fields that are analagous
  to AHEAD and BEHIND, but comparing the local version of a
  submodule to the master submodule. Described in more detail
  below.


### Invariants

- none of my repos should have 'detached' heads.
  All repos *should* be checked out to their 'master' $branch.

- HEAD_ID *should* always == MASTER_ID. Except in the middle
  of a pull, perhaps, on the local machine, the MASTER_ID should
  always be the most recent commit, and the HEAD_ID should always
  match it.  In other words HEAD_ID is only used as an error
  check.

- REMOTE_ID *should* always either == MASTER_ID, or be
  'behind' it, and from this we determine the AHEAD
  count for the repo ... that is, how many unpushed
  commits exist.

- canPush() - AHEAD (MASTER_ID != REMOTE_ID) && !BEHIND
  means there are local comnits that have not been pushed.

- For any repo that have events in the github event list some
  event in the list *should* match the the REMOTE_ID of the repo.
  That is to say that for every list of events returned by github,
  there should be at least ONE commit for any mentioned repo,
  that has the same SHA as the most recent sync (push or pull)
  we did to/from github.


### Remote Commits

Note that the github event API history is limited to 100 in
current implementation, 300 if I implement paging, and never
goes back more than 90 days.

THEREFORE, if there are NO EVENTS (pushes) to a given repo in
the current event list, we ASSUME it is NOT BEHIND github.
If I leave commits unpushed for more than 90 days, the system
may not notice it is behind and a push *might* fail, needing
a merge.  Unlikely, but possible.

Otherwise, for each repo, we can now determine BEHIND by
noting any remote commits since REMOTE_ID.

GITHUB_ID will be set to the most recent commit, if any
found in the github event list.


## Thread vs. Explicit Command

The gitStatus process is run at program startup on a Thread.

The gitStatus 'monitor' is built to wait until the disk **monitor**
is started.

An explicit command, repoStatusStart() may be called
to invoke a manual refresh of the status, and is generally only
called if repoStatusBusy() returns false.


## Refresh Status, Push, and Pull Buttons in Info Window

The Info Window (reposWindowRight) has a button that
will refresh the status synchronously outside of the
thread refresh cycle.

It has Push and Pull buttons that are not currently
implemented.



## Sub-Module consistency and updating

The gitStatus::oneEvent() method knows about
submodules, and as it process events for a MAIN_MODULE
it processes those same events through to the USED_IN
submodules,

Remember that changes to a submodule can be pushed
from ANY instance of the submodule, including the
MAIN_MODULE that IS the repository on github.

If changes ARE made, committed, and pushed to a submodule,
then the MAIN_MODULE, and any other submodules
will show as BEHIND and needing a a pull.



## gitPull()

Added a gitPull() method, analagous to the existing gitPush()
method, to repoGit.pm.  Stashing is done automatically,
if needed, in gitPull().  It is upto the UI to not Pull\
repos that need stashing if that's what the user desires.

gitPull() uses the same Progress dialog and callbacks as gitPush().
Pulls can be done on all, or selected repos, including the nominal
case of pulling a single selected repo.

### Pull == Fetch and Rebase

There is no single Git::Raw operation for a Pull.

It is implemented in terms of a Fetch (Git::Remote Download
and update 'tips') followed by a Rebase of the repo.


### Automatic Commit and Push of Parent Repo Submodule updates.

A Pull of a submodule results in an unstaged change pending
commit in the parent.  Ignoring the case of a parent that has
several submodule pulls in a single instance, If we detect that
the only change to a Parent after doing a Pull to a submodule
is an unstaged change of the module, then an a preference

	AUTOMATIC_PARENT_COMMIT_AND_PUSH_ON_SUBMODULE_PULL

or a smaller word, will drive a secondary process that will,
in turn, automatically Stage, Commit, and Push that change
to the submodule, in keeping with my general approach to
updating (pulling).

If there are any other unstaged or staged changes in the
parent, or if the parent is otherwise BEHIND or AHEAD of the
net, then the user will need to handle the parents submodule
delta manually.




## Other UI Mods:

I'm already at the point where I am considering adding a
[] details checkbox to the info window (reposWindowRight)
to hide all the XXX_IDs, local_commits, and remote_commits
unless I really want to look at them to figure out a problem.



# Notes on Parent Submodule commits

Note content:

Changed File
CHANGE old(1,0) to new(1,0)
| -Subproject commit b0d9f9f4e2a0f410c550c24ffcf9aacca6d37fd7
| +Subproject commit b0d9f9f4e2a0f410c550c24ffcf9aacca6d37fd7-dirty
