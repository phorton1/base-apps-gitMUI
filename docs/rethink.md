# gitUI - BRANCH, LOCAL, and REMOTE repositories

I have re-introduced the notion of LOCAL_ONLY,
and REMOTE_ONLY repos, and removed the parsing
of the BRANCH from the git_repos.txt file.

Also, it is no longer a requirement, starting
with SUBMODULES, but now generally, that there
is only a single instance of a repo with a
particular gitHub ID.

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
used within the program.

LOCAL_ONLY and REMOTE_ONLY repos generate Warnings during
a scan, and hence, show as yellow in lists.


### LOCAL_ONLY restrictions

LOCAL_ONLY repos are, obviously, not be able to be Pushed
or Pulled. LOCAL_ONLY Submodule Maintenance is an *unimplemented
side issue*.


### Repository list change detection

Assuming that changing git_repos.txt already requires a Rescan
and/or Rebuild of the gitHub Cache, the notion that we
can have, add, or delete REMOTE_ONLY repos on gitHub, also
nominally can be considered to require Rescanning, Rebuilding,
and/or rebooting the progam.


## Removed BRANCH from git_repos.txt

Henceforth we determine the 'current branch' for
a given LOCAL repo using Git::Raw::Repository->head() and
the shorthand() method.


There is an explicit warning given in the infoWindow if
the local branch does not match the gitHub default_branch.



---- end of readme ----
