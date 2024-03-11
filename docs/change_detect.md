


#-----------------------------------------------
# History, events, and change detection
#-----------------------------------------------
# The experimental methods in this section try to accomplish
# several goals.
#
# We use the gitHub events API on a thread to detect pushes
# to gitHub that might take place on other machines, or from
# other submodules on the same machine, and if so, determine
# whether the local repo is AHEAD and or BEHIND,
# which, along with HAS_CHANGES, which is set if the repo has
# any uncommitted (unstaged or staged) changes determines whether
# we can automatically Update the repo(s) and if so, whether we
# would need a Stash to do so.
#
# The system does not handle repos that require Merges, that
# is, where commits to the same repo HEAD revision of a repo
# have been made from two different machines, or submodules
# on the same machine.
#
# We try to do all of this in a performant manner (i.e. quickly).
#
# The case of normalizing submodules locally can additionally
# detect not only if there pushes have occured and Updates
# are needed, but can detect denormalization due to uncommitted
# changes and commits before they are pushed.
#
# CHANGE DETECTION WITHOUT FETCHING
#
# Proper detection and implementation of repo normalization
# requires a somewhat complicated comparison of the two repo's histories,
# finding the most recent common ancestor, and then counting the
# commits after that for each repo, something that git is good
# at, to the degree that you first 'fetch' the the (remote) repo
# and then use standard git commands to identify and/or update-merge
# the two repos.
#
# However, I want this process to work without making ANY changes
# to the local machine. Once you do a Fetch you can find yourself
# in a situation where you MUST merge two repos with disparate
# changes, itself a complicated process that can backfire.
#
# What I am looking for is a way to determine if a repo is out
# of date with respect to the remote, and if I can SAFELY
# Fetch and Update it, possibly with a Stash, automatically.
# Thus I want it to detect whether a Merge would be needed,
# and to notify me about that.
#
# This can sort-of be done by gathering key commit identifiers,
# SHA's, from the local repos, which can be done relatively
# quickly, and then, by using a cache and gitHub events,
# compared to the remote (gitHub) repository for change detection.
#
# KEY COMMIT ID'S
#
# For each I get the following commit ids:
#
#		head_id = HEAD - the commit the repo is at
#		master_id = refs/heads/$branch - the most recent commit in the main branch
#		remote_id = refs/remotes/origin/$branch - the last sync with gitHub
#
# Invariants:
#
# 	Because I always check into the default branch on gitup
# 	I don't need to additionally get the refs/remotes/origin/HEAD
#	commit id, as it should always be the same as the
#	refs/remotes/origin/$branch id, even if they both happen
#	to be out of date on the local machine.
#
#	When my system is in a stable state, i.e. I am not in the middle
#   of doing an Update (Fetch, possible Stash, and then Pull or Rebase),
#   then head_id should always equal the master_id. That is to say that
#   the HEAD commit should always be the same as the $branch commit
#   in any repos.
#
#	This last one is furthered by the fact that my repos should NEVER
#   have a Detached HEAD, that is a repo that is not checked out to the
#   main $branch.  This can occur (early) in submodule development when
#   cloning a new submodule, care must be taken to make sure that it is
#	checked out to the main $branch.
#
# We can use the existing gitChanges() and the new head_id to quickly
# determine when submodules are denormalized.  These id's will need to
# be updated locally in gitPush() and gitComit() after the system is
# initialized (scanned).
#
# gitHub EVENTS
#
# The gitHub event API will give us a list of the most recent pushes
# to gitHub, along with the repo paths and commit_ids in those pushes.
# The event history goes back a maximum of 90 days.
#
# It is **safe** to assume that if a repo has not been pushed in
# a long time, that I have the current version on the local machine,
# i.e. BEHIND === 0
#
# At this point I need to switch to experimental code to continue.
# It seems like, especially since I will be in a thread, that I
# can analyze every push event and use the local git history to
# determine the most recent common ancestor and the AHEAD and
# BEHIND numbers.