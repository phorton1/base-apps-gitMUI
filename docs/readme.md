# gitUI

git_repositories.txt is called the config file.

The config file can contain # comments.
The config file is line oriented.
It is indented by convention, but only the structure matters.
It is, essentially, a list of repositories with verbs that
describe things about them, and their relationship.


## Repo Path Line

The main line in the text file is a path to a repo, identified
by a leading forward slash.  It may optionally include a tab
delimited default branch if that is other than 'master'
This path must map to a git-hub repo name as defined
in gitUI::utils.pm.

	/some/path/which/maps/to/a/repo	(\t optional_default_branch)

Various information about the repository (i.e. its description)
is gotten from github, and cached, for display in my system.


## SECTION

The SECTION verb is used to create a 'break' in the listing of
repos, grouping repos together into sections in the main windows
of repos.

	SECTION path (optional name)

If the **path** starts with a forward slash, it will
be used within the windows to lessen the horizontal space
needed to show the repos by subtracting it from repos in
that section.  For example

	SECTION	/src/Arduino/libraries
	/src/Arduino/libraries/FluidNC
	/src/Arduino/libraries/FluidNC_Extensions

Will result in a blank line followed by a non-clickable header,
followed by shortened names as links to the repos:

	(blank line)
	/src/Arduino/libraries			- non clickable SECTION HEADER
	FluidNC							- shortened link to repo
	FluidNC_Extensions				- shortened link to repo

The optional (name) will be shown as the SECTION HEADER if
one is provided.  To further save vertical space, if the
first repo listed within a section has the same path as
the SECTION, the link becomes the clickable link to the
repo, serving both as the SECTION HEADER and the repo link.

## SUBMODULE rel_path  main_module_path

This verb defines a submodule within a repo.
The rel_path is the path relative to the repo, and
the main_module_path is the repo for the 'main'
repository, which is usually an ignored sub-repo
in another repository.

This verb will CREATE a new 'submodule repo'.
The submodule repo have the following:

- path - the path will be the absoluate path
  of the submodule, which will be within the
  parent repo's path.
- id - the id of the repo will be that of the
  main submodule, i.e. where it goes to github
  to check for source changes.
- parent_repo - will be set as a pointer to
  the actual parent repo object
- rel_path - will be stored on the object.

By convention, the presence of {parent_repo} is
used to indicate a submodule repo.  In addition,
the path of the submodule repo will be pushed onto
lists in the parent repo and the main module repo:

- parent -repo - {submodules} list has submodule path
- main_module repo - {used_in} gets the submodule path


## Other VERBS at this time

All other verbs at this time are used for integrity checks,
to help getting more information from github,
or to support dependency schemes:

- PRIVATE - is an integrity check against the visibility
  of the repo in github, to make sure it is what I think
  it should be.  Private repos are shown in blue, public
  ones in green.

- FORKED - indicates that the repository is a fork of
  some other, likely public, repository (library).
  A forked repository will have a {parent} github
  repository, and a separate github request will be
  made to get information about the fork.

- MINE, NOT MINE - repos default to 'mine'. Forked
  repos then default to 'not mine'.  Basically unused
  at this time, except for repoDocs.pm, which allows
  for working only {mine} repos.

- PAGE_HEADER - nascent scheme to implement self fixing
  Document Headers. See repoDocs section below.

- DOC relative_path - part of nascent scheme, but the
  file, at least, ARE checked for existence, with shortcuts
  in the repo info window to opening them in the browser.


- NEEDS abs_path - an absolute path to a directory that
  must exist.  For dependencies other than repos.
  does not exist (but not necessarily the repo),
  and provides shortcuts in the repo info window.
  No shortcut at this time, but *could* open the
  directory in Windows Explorer

- USES abs_repo_path - speficies that this repo USES
  another repo. In turn creates USED_BY members
  on those repos, both of which end up being shortcuts
  to opening the refererd repo in the repo info window.


- GROUP|FRIEND|NOTES|WARNINGS|ERRORS (value) - arbitrary
  keywords that let you push the rest of the line onto
  one of the arrays on the repo object.

  GROUP and FRIEND are intended to support a scheme.
  NOTES, WARNINGS, and ERRORS, can allow you to push
  these things (like an error) WITHOUT generating the
  actual error message during scanning.  Only ERRORS
  are currently useful as, without a tabular display,
  there is no good way to see everything that has
  NOTES and WARNINGS.


## Other funny stuff

IF my description includes "Copied from blah" followed
by a space, the {parent} member will be display as (blah)
as a reminder of where i got it

TODO: This needs to get built into the eventual tabular display.


## New Status Window, Repo Status in general

I want a tabular display of all the repos, and the errors,
notes, warnings, as well as the sizes and the total space
consumed on github, more or less as now exists in the
git_repos.bat/pm program, in a single display window
within gitUI.  I would then eliminate the bat/pm programs

- git_changes.pm/bat
- git_repos.pm/bat

Apart from duplicating code, all **git_repos** does is
modifies the list of recent repos for slightly easier use
of the regular gitGUI program, a feature I hardly use anymore,
and one that could be incorporated into my gitUI program
if so desired.

Now that Submodules have been implemented, there should be
an easy way to check if they are normalized across all usages,
and or to normalize them.   This is a subset of the general
issue, noted when working on the rPi versus Windows machine,
of identifying repos that need to be updated (pulled) from
github.  This capability follows the 'update_system' and
'update_system_stash' functions recently added to Pub::
ServiceUpdate and HTTP::ServerBase, that is used in Artisan,
the Inventory application, and myIOTServer.

I envision a new repoGit updateStatus() method that works
on a repo and adds various fields to it:

	status_time : when a status was last run
	commits_ahead and commits_behind : compared to github

along with at least displaying the big three, prominetly
in the info window

	HAS_UNSTAGED_CHANGES
	HAS_STAGED_CHANGE
	CAN_PUSH

and/or having additional colors, or some other artifacts for links
that present these (all links to repos should get the utils::color)
consisttently throughout the UI.

It may be easier to impleent this after I have a practical
example of submodules, a task I have yet to undertake,
starting with /src/Arduino/libraries/myIOT/data.



## repoDocs.pm

Is currently a stand-alone program that was a start at
parsing MD's to automatically create and update headers.
It requires all the DOC = lines to be setup correctly,
and for the repo to have a


	SECTION
