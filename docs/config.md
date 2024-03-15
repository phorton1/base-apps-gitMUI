# gitUI - Repository Configuration File

The **repository configuration file** contains a *list*
of all the repos you want gitUI to work with, and
specifies individual *characteristics* of each repo.

The default name is of the file is **gitUI_config.txt**
in the *data directory*. We will simply refer to it as
gitUI_config hereafter, but it can be any name, in any
location.

The gitUI_config file:

- is a line oriented, human readable, simple text file
- can contain # comments and blank lines
- uses *tabs* (\t) as a delimiter for fields on lines
- is indented by convention

It is, essentially, a list of repositories with verbs that
describe things about them, and their relationship.


## Repo Path Line

The main line in the text file is a path to a repo, identified
by a leading forward slash.  It may optionally include a tab
delimited set of options

	/some/path/to/a/repo  (LOCAL_ONLY)

LOCAL_ONLY specifies that therepo is not expected to
exist on github, its remote ID will not be checked,
nor will it be updated if it happens to be found
on gitHub.



## Remote Only repo ID line

A line that starts with a dash indicates the ID of (after
removing the leading dash) of a REMOTE_ONLY repo on gitHub.

	-some-repo-id  (REMOTE_ONLY)

The REMOTE_ONLY clause is not required, but recommended.


## SECTION

The SECTION verb comes *before* a *Repo Path Line* and allows you to group
related repos together into sections in the various gitUI windows.

	SECTION path (optional_id_if_slash_dash_substitution_not_good_enough)

The *path* will be removed from following paths, and the ID
from following IDs, in DISPLAY ONLY of the repos in certain
gitUI windows. For example, given a SECTION with two
paths as follows:

	SECTION	/src/Arduino/libraries
	/src/Arduino/libraries/FluidNC
	/src/Arduino/libraries/FluidNC_Extensions

A non-clickable header, and two links (which fit better in the
various gitUI windows) will be created as follows

	/src/Arduino/libraries
	FluidNC
	FluidNC_Extensions

The optional (name) will be shown as the SECTION HEADER if
one is provided.  To further save vertical space, if the
first repo listed within a section has the same path as
the SECTION, the section name becomes a clickable link
to the given repo.


## SUBMODULE rel_path

This verb defines a submodule within a repo, and
telss us where to find it.

In our vision of subModules, there is one repo
someplace on our machine that represents the
'master' repository for the submodule.  Typically
this will be a .gitignored subfolder of some
other repo.

The ID of the submodule is gotten from GIT.
The presence of the SUBMODULE
verb defines several key facts for gitUI to use:

- it defines a **separate repo** that exists on the machine,
  which is independently monitored for changes, and which
  has it's own separate status, lists of staged and
  unstaged changes which can be staged, unstaged, reverted
  and/or committed, Pushed, or Pulled independently of hte
  parent (super) repo.
- it **groups** the main_module and all of the cloned submodules
  together into a group that can be monitored and
  acted on as a whole in the *subsWindow*, making it
  much easier to *normalize* a change in a submodule,
  or the main_module, to all of the clones of it,
  as well as providing a mechanism to automatically
  *commit the submodule change* within the parent (super)
  repos that use it.
- it **builds a list** of the submodules within each parent
  repo, which is important for determining when it is
  possible to automatically *commit the submodule change*
  to the parent repo.

*following to be moved to design.md or implementation.md*

Internally, implementation wise, it does the following
As mentioned, it will CREATE a new 'submodule repo'
within the *repoList*. The submodule repo have the
following members:

- path - the path will be the absoluate path
  of the submodule, which will be within the
  parent repo's path.
- id (overloaded) - the id of the submodule repo will be that of the
  main submodule, i.e. where it lives on gitHub.
- parent_repo (added) - will be set as a pointer to
  the actual parent repo object in the gitUI program
- rel_path (added) - will be stored on the object.

By convention, the presence of {parent_repo} is
used within the program to indicate a submodule repo.
In addition, the path of the submodule repo will be pushed
onto lists in the parent repo and the main module repo:

- parent repo - {submodules} list gets all it's fully qualified submodules paths
- main_module repo - {used_in} gets a list of all cloned copies of the main module


## Important VERBS within Repos

These verbs are used for integrity checks, and to
to help getting more information abou the repo from gitHub

- **PRIVATE** - is an integrity check against the visibility
  of the repo on gitHub, to make sure it is what I think
  it should be.  Private repos are shown in blue, public
  ones in green.
- **FORKED** - indicates that the repository is a fork of
  some other, likely public, repository (library).
  A forked repository will have a {parent} gitHub
  repository, and a separate gitHub request will be
  made to get information about the fork.
  FORKED may be binary, or contain text that is shown
  in the infoWindow.
- **USES** abs_repo_path - speficies that this repo USES
  another repo. In turn creates USED_BY members
  on those repos, both of which end up being shortcuts
  to opening the refererd repo in the infoWindow.
  *USES* creates a repository dependency graph.
- **NEEDS** abs_path - an absolute path to a directory that
  must exist on the local machine. For dependencies other
  than repos. Provides shortcut to Windows Explorer
  in the infoWindow.
- **NOTES|WARNINGS|ERRORS** (value) - arbitrary
  keywords that let you push the rest of the line onto
  one of the arrays on the repo object. These are then,
  in turn, added to any Notes, Warnings, or Errors
  found while scanning the repos or getting information
  from gitHub, all of which affect the color of the repo's
  links, and are shown in the infoWindow for the repo.


## Less important VERBS within Repos

- **MINE|NOT MINE** - repos default to 'mine'. Forked
  repos then default to 'not mine'. I like to keep
  track of repos I totally own verus ones I have
  may have copied or cloned and/or modified.
- **GROUP|FRIEND** - whatever follows the verb is
  added to a array {groups} or {friends} on the
  repo.  This is intended to support a future scheme
  for describing relationships between repos other
  than dependencies.
- **DOC** relative_path - part of nascent scheme, builds
  a list of Documents associated with the repo.
  A DOC is a *file* that must exist at this time.
  It can be anything, but I typically use *.md* files
  for my published repo's documentation.
- **PAGE_HEADER** - boolean, or arbitrary value,
  This is part of a nascent scheme to implement
  automatically created, organized headers at the top
  of my .MD files.


## Description Mapping

*this goes into design.md or implementation.md*

The *description* of a repo is gotten from GitHub.

IF the description includes "Copied from blah" followed
by a space, the {parent} member will be display as (blah),
and like a FORKED repo, a Browser link to the GitHub repo
will be provided in the infoWindow.


## Untracked Repos

There is a function to do a scan of the entire machine
for any untracked repos that might not be in the git_repos.txt
file.   It is currently turned on, and uses a cache file
in the base_data/temp/gitUI folder for re-use without
rescanning.

TODO: reposUntracked.pm is part of the bootstrap process
for a new machine when I do all the Prefs stuff and
make an installer.


-- end of readme ---
