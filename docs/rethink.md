# gitUI - BRANCH, LOCAL, and REMOTE repositories

I have re-introduced the notion of LOCAL_ONLY,
and REMOTE_ONLY repos, and removed the parsing
of the BRANCH from the git_repos.txt file.



The {branch} member (used in gitChanges, gitPush,
gitPull, and so forth) is determined, and monitored
based on the local Git::Raw repository.



I am rethinking the way I do the whole thing, removing some of
the invariants, and 'fixed' members in the system.

- The system considers it an invariant that all managed LOCAL
  repos within git_repos.txt have a REMOTE on gitHub.
- The system considers it an invariant that all repos on gitHub
  have a managed LOCAL repository within git_repos.txt
- git_repos.txt has a BRANCH, which defaults to 'master' if
  not otherwise specified.
- The system considers it an invariant that the parsed BRANCH
  for all managed local repos have a correponding remote of
  that branch.
- The system implicitly assumes that the gitHub default branch
  is, or at least *should* be the same as the parsed BRANCH


## LOCAL_ONLY and REMOTE_ONLY repos

A 'normal' repo exists both locally, and has a remote origin on gitHub,
can be Pushed, Pulled, and used throughout the system.

In addition the system allows for LOCAL_ONLY and REMOTE_ONLY repos.
LOCAL_ONLY repos can be used for Commits, but (obviously) cannot be
Pushed or Pulled.

REMOTE_ONLY repos can be viewed in the infoWindow but are not otherwise
used within the program. Since REMOTE_ONLY do not have an actual local 'path',
and we need to put them into the

per se,
we are kind of back to the chicken-and-egg problem of where to
put such repos in the overall list, especially since they are
"discovered" in the separate reposGithub.pm process AFTER the
list of repos has been parsed.  One idea would be to develop
a 'default path' using slash/dash substitution, and then trying
to determine where such a path *might* fit into the list, based
on sections, perhaps from the end of the list backwards to account
for the way I 'nest' sections.  A simple initial solution will be
to place all REMOTE_ONLY repos in a new, system generated "section"
at the end of the list.

LOCAL_ONLY and REMOTE_ONLY repos generate Warnings during
a scan, and hence, show as yellow in lists.


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
