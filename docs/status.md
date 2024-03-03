# gitStatus and Updating

Maintaining the status of the repositories vis-a-vis local versus
github, and the consistency of submodules, is rather complicated,
and a bit time consuming.  Updating, either pulling from github
or normalizing local submodules, is even more complicated.

Checking of the status versus github requires, obviously, an internet
conntection. Automatic realtime checking is/would-be rate limited
to one check per minute.

There are, I believe, currently some problems with the commitWindow
and submodules-within-parents.

This document describes mods to the program 2024-03-03

The head_id, master_id, and remote_id have already been
added to, and maintained, for every repo in repoGit().


## gitStatus.pm

A new module, gitStatus.pm has been created.
It contains the updateStatus thread.

There is a preference, GITHUB_UPDATE_INTERVAL, which *should* be
set to 0 or a minimum of 60, that will cause the thread to watch
for changes to github events, and/or to check the integrity of
local subodules.

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

- head_id *should* always == master_id. Except in the middle
  of a pull, perhaps, on the local machine, the master_id should
  always be the most recent commit, and the head_id should always
  match it.  In other words head_id is only used as an error
  check.

- remote_id *should* always either == master_id, or be
  'behind' it, and from this we determine the 'ahead'
  count for the repo ... that is, how many unpushed
  commits exist.

- canPush() - BEHIND, remote changes and master_id != remote_id -
  these *should* be equivilant concepts.  canPush literally
  means there are local comnits that have not been pushed.
  I currently use remote_changes to determine canPush().
  Note that i think there are problems with that approach.

- All events in the github event list *should* **line up** with
  the remote_id of the repo .. that is to say that for every list
  of events returned by github, there should be at least ONE commit
  for any mentioned repo, that has the same SHA as the most recent
  sync (push or pull) we did to/from github.


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


## Thread vs. Explicit Command

I envision the gitStatus process being run once at program startup
on a Thread, after the monitor has started.  This means that either
we need a short timeout, or a separate threaad, to do the gitStatus,
or else we would hang the monitor loop until an HTTP get timed out.

*perhaps* part of this could be fired off as a one-time detached thread from
doGitHub().

The *full* status requires that gitChanges() has been run, and cannot
take place until the monitor IS started.  However, we can GET the github
events into a cachefile at anytime.  Note that when run from a thread
the displayDialog (WX main thread only object) cannot be used for display.




## Push Button, Status Window with Refresh button

I also enveison a new Status window that ties all of this together.

The repo-info window *should* get Push and (future) Update buttons.

Note that there is a bug in responding to links in the infoPane
when clicked on from the commitWindow.  It updates the contents,
but really *should* switch to the 'Repos' window.
