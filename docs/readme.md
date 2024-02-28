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






## repoDocs.pm

Is currently a stand-alone program that was a start at
parsing MD's to automatically create and update headers.
It requires all the DOC = lines to be setup correctly,
and for the repo to have a


	SECTION
