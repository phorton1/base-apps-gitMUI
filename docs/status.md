# gitMUI - Status and Updating

TODO: implement an actual *statusWindow*


Maintaining the status of the local repositories versus gitHub
is rather complicated, and a bit time consuming.

This document describes how the general scheme by which
monitorUpdate() sets the repo gitHub ID, remote_commits,
and {BEHIND} members. {BEHIND} indicates that a repo is
out of date with respect to gitHub and needs to be pulled.

By the structure of the monitor, which calls gitChanges()
on each repo at startup, which in turn calls gitStart()
on each repo, the HEAD_ID, MASTER_ID, REMOTE_ID, local_commits,
and {AHEAD} members have already been added to everr repo
befor the monitor does an monitorUpdate(). which sets
the , and maintained, for every repo in repoGit().


## Automatic Status Updating

There is a preference, gitHub_UPDATE_INTERVAL, default 90,
which *should* be set to 0 or a minimum of 60, that will cause
the monitor thread to check for changes to gitHub events.

If there is a problem (i.e. no internet connection) doing
a monitorUpdate(), the system will report an error and stop
trying to do automaic updates.  If this happens, it can
be restarted by merely issuing anotheer monitorUpdate()
command.


# Fields Involved

The monitor thread does the behind-the-scenes work
to call gitChanges(), which sets local members, and
to process gitHub events to set remote members,
necessary to determine the status of a repo.

- HEAD_ID, MASTER_ID, REMOTE_ID - local commit ids
  are automatically gotten during gitParse() and updated
  during gitXXX() methods by virtue of them calling gitStart()

- local_commits - an abreviated list of the local repo history
  containing the local commits back to the eearlist of HEAD_ID,
  MASTER_ID, AND REMOTE_ID. also set during gitStart().

- AHEAD - number of local_commits between REMOTE_ID and MASTER_ID -
  this is the number of unpushed commits, set in gitStart().

Once every so often, or at the users request, monitorUpdate()
is called which hits gitHub for a list of events, and updates
the remote members on all repos.

- gitHub events - is a json data structure containing a list
  of the most recent pushes to gitHub, and the commits within
  those pushes.  We get it initially into a cache at program startup,
  and then update the cache, using the ETag header, which will only
  return events if they have changed since the last ETag, therafter.

- gitHub_ID - the SHA of the most recent commit found for a
  given repo in the gitHub events.

- remote_commits - a list of any commits that we find in the
  gitHub events for the given repo.

- BEHIND - number of remote commits between REMOTE_ID and gitHub_ID
  this is the number of commits made to the repo from other sources
  that are not present on the machine



### Invariants

The following invariaants are maintained, and reported
as errors if they are broken, in gitStart() and monitorUpdate():

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

- For any repo that have events in the gitHub event list some
  event in the list *should* match the the REMOTE_ID of the repo.
  That is to say that for every list of events returned by gitHub,
  there should be at least ONE commit for any mentioned repo,
  that has the same SHA as the most recent sync (push or pull)
  we did to/from gitHub.


### Remote Commits

Note that the gitHub event API history is limited to 100 in
current implementation, 300 if I implement paging, and never
goes back more than 90 days.  By default I get the most recent
30 events.

THEREFORE, if there are NO EVENTS (pushes) to a given repo in
the current event list, we ASSUME it is NOT BEHIND gitHub.
If I leave commits unpushed for more than 90 days, the system
may not notice it is behind and a push *might* fail, needing
a merge.  Unlikely, but possible.

Otherwise, for each repo, we can now determine BEHIND by
noting any remote commits since REMOTE_ID.

gitHub_ID will be set to the most recent commit, if any
found in the gitHub event list.


## Thread vs. Explicit Command

An explicit command, monitorUpdate() may be called
to invoke a manual refresh of the status.


## gitPull()

Added a gitPull() method, analagous to the existing gitPush()
method, to repoGit.pm.  Stashing is done automatically,
if needed, in gitPull().  It is upto the UI to not Pull
repos that need stashing if that's what the user desires.

A Pull is allowed even if the repo is not explicitly {BEHIND},
in case the gitHub events are not updated, which can take
a minute or more on gitHub.


gitPull() uses the same Progress dialog and callbacks as gitPush().
Pulls can be done on all, or selected repos, including the nominal
case of pulling a single selected repo.

### Pull == Fetch and Rebase

There is no single Git::Raw operation for a Pull.

It is implemented in terms of a Fetch (Git::Remote Download
and update 'tips') followed by a Rebase of the repo.


### Automatic Commit and Push of Parent Repo Submodule updates.

There is an define that is currently set to zero in gitPull():

	$AUTO_UPDATE_SUBMODULE_PARENTS = 0

A Pull of a submodule results in an unstaged change pending
commit in the parent.  Ignoring the case of a parent that has
several submodule pulls in a single instance, If we detect that
the only change to a Parent after doing a Pull to a submodule
is an unstaged change of the submodule then gitPull() will
start a secondary process that will, in turn, automatically
Stage, Commit, and Push that change to the submodule.

If there are any other unstaged or staged changes in the
parent, or if the parent is otherwise BEHIND or AHEAD of the
net, then the user will need to handle the parents submodule
delta manually.

In practice I found this to be somewhat nonsensical, especially if
(a) a parent has more than one copy of the same submodules, and
(b) becausee it messes up the Progress UI ... doing a Commit and
Push in the middle of a commit.

This approach has been superceded by an explicit Window that tracks
Submodules inconsistencies and helps the user to correct them.



--- end of readme ---