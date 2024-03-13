# gitUI - BRANCH, LOCAL, and REMOTE repositories

I have re-introduced the notion of LOCAL_ONLY,
and REMOTE_ONLY repos, and removed the parsing
of the BRANCH from the git_repos.txt file.

The {branch} member (used in gitChanges, gitPush,
gitPull, and so forth) is determined, and monitored
based on the local Git::Raw repository.


## LOCAL_ONLY and REMOTE_ONLY repos

A 'normal' repo exists both locally, and has a remote origin on gitHub,
can be Pushed, Pulled, and used throughout the system.

In addition the system allows for LOCAL_ONLY and REMOTE_ONLY repos.
LOCAL_ONLY repos can be used for Commits, but (obviously) cannot be
Pushed or Pulled.

REMOTE_ONLY repos can be viewed in the infoWindow but are not otherwise
used within the program. Since REMOTE_ONLY do not have an actual local 'path',
and we need to put them into the

LOCAL_ONLY and REMOTE_ONLY repos generate Warnings during
a scan, and hence, show as yellow in lists.

### POTENTIAL CONFLICTS

Because we are making up id's for LOCAL_ONLY repos, and making
up paths for REMOTE_ONLY ones, the possibility exists that that
id or path is in legitimate use for another repo.  For REMOTE_ONLY
repos, we refuse to add the item if the path is already in use.
HOWEVER, for LOCAL_ONLY repos, due to the way we scan, we *could*
check that the generated ID is not in use BEFORE the local_only
repo, but we cannot be sure that the id will not be used legitimately
by a later scanned repo.  The best we could do would be to either]
(a) give an error if any repo id or path is attempted to be added
twice to the list, or (b) save up the local_only repos and add them
at the end of the list, in another section, where we could conceivably
refuse to add it if it conflicted with an existing ID.

TODO: AT THE MOMENT IT IS UP TO THE USER TO NOT INCLUDE ANY LOCAL_ONLY
REPOS whose path would map to an existing, legitimate gitHub repo id.

A bit of thought can probably make this smoother, but I am
checking in the changes "AS-IS"



### REMOTE_ONLY restrictions

gitUI does not support ANY operations (apart from viewing Info)
for REMOTE_ONLY repos.  They would need to be excluded from the
monitor, and all other processes that currently assume all repos
exist on the local machine.

### LOCAL_ONLY restrictions

LOCAL_ONLY repos would, obviously, not be able to be Pushed
or Pulled.  LOCAL_ONLY Submodule Maintenance would be a side
issue.

### Repository list change detection

Assuming that changing git_repos.txt already requires a Rescan
and/or Rebuild of the gitHub Cache, the notion that we
can have, add, or delete REMOTE_ONLY repos on gitHub, also
nominally can be considered to require Rescanning, Rebuilding,
and/or rebooting the progam.


## Remove BRANCH from git_repos.txt

Henceforth we would determine the 'current branch' for
a given LOCAL repo using Git::Raw::Repository->head() and
the shorthand() method.

Preliminary tests have shown that I can monitor repos for
changes to the {branch} member and the system doesn't puke.
I have already added the gitHub {default_branch} member
to each repo.

There is an explicit warning given in the infoWindow if
the local branch does not match the gitHub default_branch.








---- end of readme ----
