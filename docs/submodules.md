# Submodules

This readme describes the concepts behind my usage of submodules,
provides a cookbook for using them, and describes how the gitUI
program can facilitate maintenance of them.

The cannonical example is the /src/Arduino/library/myIOT/data_master
library, which is included in a number of other repos as a submodule.


## SUBMODULE specification (SUBMODULE GROUP)

The SUBMODULE specifier within a repo in git_repositories.txt
tells the system what submodules exist, and where to find them.

	/parent_repo_path
		SUBMODULE	rel_path	/master_sub_path

The presence of the SUBMODULE verb will create a new repo object,
and set various members on the parent and 'master'

The new submodule repo object will have

- {rel_path} - the relative path within parent repo
- {path} - the absolute path of the submodule within the parent
  /parent_repo_path/rel_path, so the repo shows up in the system
  as 'just another' repo. It shows up as "++ relpath" in lists
  in the UI.
- {id} - the id of the submodules IS the same as the the ID
  of the 'master submodule'.  As far as much of the system is
  concerned, the submodule is JUST ANOTHER COPY of the master
  submodule.
- {parent_repo} - a pointer to the actual parent repo object
  is included in memory for submodule repos.  This is usually
  the field checked to determine if a repo is, in fact,
  a submodule,

The parent repo will get

- {submodules} - an array of the relative paths to submodules
  within the parent repo.

The 'master' submodule repo will get

- {used_in} - an array of the full paths of all submodules
  that are references to this master submodule.


Thus the 'master' submodule, and all the repos it is {used_in}
constitutes a SUBMODULE GROUP, that can be checked for consistency,
update, etc.



## USING SUBMODULES

Adding a submodule to an existing project. For example, to add
the /src/Arduino/libraries/myIOT/data_master submodule to the myIOT/examples
folder (after removing and commiting the removal of the old data folder,
if one existed):

	cd /src/Arduino/libraries/myIOT
	git submodule add https://gitHub.com/phorton1/Arduino-libraries-myIOT-data_master examples/testDevice/data

Cloning a repository that contains submodules is done automatically
if you pass --recursive on the command line.  Here's how you would
clone the src-Arduino-theClock3 repo into your Arduino projects folder:

	cd /src/Arduino
	git clone --recursive https://gitHub.com/phorton1/src-Arduino-theClock3 theClock3

After cloning a new submodules you *NEED TO* checkout the 'master' branch before proceeding,
possibly from the directory:

	cd /src/Arduino/theClock3/data
	git checkout master

Updating a repository that has submodules that are out of date, i.e.
after modifying, committing and pushing the **myIOT/data_master** repo,
the copy in theClock3 can be updated either by doing a "git pull" from
the submodule directory:

	cd /src/Arduino/theClock3/data
	git pull

Or for all sumodules in theClock3 by:

	cd /src/Arduino/theClock3
	git submodule update --recursive --remote


### Parent Repo Submodule Change

Note that updating a submodule creates an UNSTAGED CHANGE
on the parent repo which then needs to, itself, be committed
and or pushed.


### Notes vis-a-vis Pub::ServiceUpdate

On the rPi, which alreaady had a myIOTServer project, after my built-in
ServiceUpdate, it had the submodule, but an empty directy.
I had to redo the submodule update with --init

	cd /base/apps/myIOTServer
	git submodule update --init --recursive --remote

to get it to download the submodule. I may only need to do
that the first time. In any case I'm pretty sure as long as I
don't change the myIOT folder, the ServiceUpdate mechanism will
still get the rest of the myIOTServer source code changes ok.

My ServiceUpdate mechanism, and updating submodules in general
is "Work in Progress" as part of the GIT STATUS  project, currently
under the umbrella of this apps/gitUI project.



## Normal Pull Notifications (BEHIND)

Because the master submodule and sumodules are just regular
repositories, the [status monitor](status.md) will automatically
notice if any are out of date with respect to gitHub, and they
will show as 'Need Pull' or 'Pull+Stash' (in red).



## Cannonical Example

The myIOT/data_master repo contains a version of jquery, bootstrap,
and some common JS, CSS, and HTML that are served by myIOT projects.
The data_master repo is currently included as a submodule in the
following repos:

- /src/Arduino/libraries/myIOT/examples/testDevice/data
- /src/Arduino/bilgeAlarm/data
- /src/Arduino/theClock/data
- /src/Arduino/theClock3/data
- /base/apps/myIOTServer/site/myIOT

In the cannonical example, we will will:

- make a change to readme.md in /theClock3/data
- commit and push that to gitHub

At this point, all the other **data** submodules will turn red,
indicating that they need to be pulled, and **theClock3** will
have get an unstaged change for its **data** submodule.

**IMPORTANT NOTE** - After the readme.md file is edited
and saved, an unstaged change of the **data** submodule within
the theClock3 repo will show up.  *It is useless, or even
potentially destructive, to commit this change!!.*

The parent repo, theClock3, **data** submodule change
can be committed, if desired, at this point, or via the
automatic process described in the next section.



## Automatic Updating of SUBMODULE_GROUP

The system should flag {unstaged} or {staged} changes
in more than one repo in a SUBMODULE group.

- All the {BEHIND} repos need to be pulled
- A commit needs to be added to every parent_repo for the submodule update.



--------- end of readme ------------
