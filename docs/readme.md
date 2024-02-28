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

	SECTION path (name)

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





- MINE, NOT MINE - change the colors in the repo list












##


	SECTION


