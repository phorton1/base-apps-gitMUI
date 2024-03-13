# gitUI - a UI for working on multiple GIT repositories simultaneously

- config.md
- prefs.md


**gitUI** is a User Interface, written in *Perl*, for working with multiple
different GIT repositories from within a single program.

I have provided a **Windows Installer** to install an executable
version of the program without needing to install Perl or any
additional dependencies.

It runs on **Microsoft Windows** machines, and is intended
to manage multiple local repositories that have remotes
on **gitHub**.  It is very simliar in look, feel, and
functionality, to the *gitGUI* program that comes with
a standard GIT installation, except that it works with *many
different repositories simultaneously*, without requiring you to
open a new gitGUI window to each one.

Some of its main features that facilitate working on
multiple repositories simultaneously include:

- **Single commit window that works across multiple repos**.
  This feature allows you to see ALL files you have changed,
  in ANY repo on your machine, in a single place. You can
  *stage, unstage, revert, and commit* changes
  to multiple different repos in a single operation.
- **Automatic monitoring of file changes** in all your repos
  so that you don't need to **rescan** or do any manual
  operations to see new *changes* or *diffs*.
  Anytime you save a changed file to the disk, gitUI will automatically
  notice it, and update the system to reflect the changed file,
  including adding it to the *unstaged changes* and updating
  the *diff pannel* in the *commitWindow* if that file happens
  to be showing.
- The ability to **Push** and **Pull** multiple different
  repos in a single operation, including the ability to
  easily Push *any repos that **need pushing*** or Pull
  *any repos that are **out of date*** with respect to
  gitHub.
- A Single Window that shows you the **status** of all of
  your repositories in a single glance, showing, by color,
  for example, any repos that have **unstaged or staged
  changes**, repos that **need pushing or pulling**, repos
  that present potential **merge conflicts**, as well as
  providing **many navigation options** for viewing those
  repos, and files within them, in the regular gitGUI program,
  on gitHub, opening them in an Editor, in Windows Explorer,
  or via a Shell command.
- **Management of Submodules**, where you may have clones
  of one of your repos inserted as submodules into
  other repos, and you would like to make changes in the
  master, or any of the clones you happen to be working on,
  and then **normalize** those changes to all of the other
  repos that use the submodule. In gitUI this can be done
  in a **few simple operations** rather than the unweildly
  processes that would be required using git manuallly
  from the command line or in multiple gitGUI windows.

If any of these features sound interesting, or if you happen
to be managing a large number of local and gitHub repositories
on a Windows machine, you may find this program useful.


## Motivation and History

This program started as a simple list of all the repositories on
my local machine.  I didn't like the way gitUI manages the list of
"recent repos", and I often ended up having to go to Windows Explorer
to navigate to a folder containing a repo, and then right-click
to select the "Git GUI Here* option.  So, at first I merely had
a process of modifying my system-wide git_config to replace the
list of recent repos with a list of all the repos on my machine.
Then I added a program showing that list of repos that could
"shell" to the gitUI command.

I continued to fight with gitUI, as anytime you modify any repo,
it re-orders the list of 'recentRepos' into what it *thinks* you
want to see, which was *never* what i wanted to see, which would
have simply been an alphabetical list of all the repos on my machine.
So this program began it's life as a simple app that merely
served as a launcher for gitUI, listing all my repos, and
allowing me to open a new gitUI window to any of them.

Over time I found that I would have many gitGUI windows open,
often be making a set of changes that crossed several different repos,
yet would have the same **commit message**.
I would have to open, and go to, each relevant gitUI window, do a **rescan**
to see the changes, *paste* in the *copied* commit message, and
make the commits. Then I would need to manually **push** each repo
to gitHub. In order to do all of this I had to **remember** which
repos I modified, which I pushed, and so on.

There was no systematic way for me to determine whether or not any
repos had changes that needed to be committed, or which needed to be
pushed, or later, which needed to be pulled as I made changes to that
repo on a different machine.

So I expanded the program from a simple list of repos
that linked to gitGUI into a multi-window application,
where the list became the **pathWindow** as I added the
new **commitWindow**.  At first I used "shell" commands
to call git command line operations, but I had several
issues running git as a shell command from within a wxPerl UI.

I spent several months implementing the commitWindow, as well as the
ability to Diff and Push repos using the Perl Git::Raw module.
Git::Raw allows me to directly manipulate repos from Perl without
doing shell commands all over the place.

But, even though I implemented
the basic **commit, stage, unstage, and revert** process
across multiple repos, it was still onerous to use
as I had to **rescan all of my repos** every time I
wanted to see any changes.

So the program then evolved to use a background thread
to **constantly rescan** all of my repos for changes. It
worked, but was slow, and used a significant
percentage of my machine's CPU just sitting there
checking ALL my repos for changes, over and over again,
even though I typically only work on a few repos at a time.

A major breakthrough was discovering, and utilizing
the MS Windows built-in directory change notification technology,
**Win32::ChangeNotify**.  With that my thread could scan all
the repos at startup, and then anytime a file was modified
in any of the repos, I would get an event, and I could just
rescan THAT paricular repo.

The final breakthrough that I recently implemented,
which has motivated me to make this program **public**,
was the use of **gitHub Events** to determine whether
any of my local repos are *out of date* with respect to their
gitHub repos (*without having to **fetch** them first)*.
It was really important to me that **nothing on my local
machine is modified** in the process of determing if
it **should** be modified. This breakthrough, in turn,
let me do all kinds of interesting things,
like, for instance, giving a **warning if I attempt to
make a commit that would require a merge** so that I
dont run into **that problem**, WITHOUT modifying anything
on my local machine.

The program still has some **serious limitations**, but
I don't enounter them in my usage.  Mainly, it does
NOT support simlutantously working on *multiple branches*
or clones of the same repo on the local machine, and does not
do any kind of *Merge conflict resolution*. Note that
*I avoid Merge Conflicts like I would the **bubonic plague**!*

So, after all this, I think, now, that **other people may
find this program useful**, so I am making it **public**.

It may not be ideal for an *enterprise* where many
people are simultaneously working on many related repos,
or for people who work on many branches and clones of the
same repo. But for a single person who has dozens, or even 100's
of related repos, who typically works on a single branch
of each, and makes changes to many repos every few hours,
I find it **very useful** indeed.


## Overview

The program is driven by the [**repository configuration
file**](config.md) which has a list of *all the repos* on your machine,
and *characteristics* you define for them. There is also
a [**preferences**](prefs.md) file which (can) contain your gitHub
*user name and credentials* and other parameters which
affect the way gitGUI works.

The program consists of four main windows:

- **pathsWinow** - shows all of the repos on your machine
  in a single glance.
- **commitWindow** - shows any *unstaged* or *staged* changes
  in *any repo* on your machine, allowing you to
  *stage, unstage, revert, or commit* those changes.
  This window also contains the **diffPanel** which
  allows you to see changes to any individual file.
- **infoWindow** - presents a list of all the repos on
  your machine in a left *infoList* panel, and shows
  information about the selected repo, including its
  *status and history* in the right *information* panel.
- **subsWindow** - presents a list of the *submodules*
  on your machine, grouped together by their gitHub
  ID, and allows you to push, pull, and/or *commit
  the submodule changes* to their parent (super)
  repos in a series of simple operations.

Whenever a **repository** is shown in gitUI, it will
be presented as a *hyperlink* of a certain *color*.
The colors are important enough that we present them
here, even though gitHub has no good way for a readme
to show colors. This is the order of priorities:

- **red** - if the repo is **BEHIND** (out of date
  with respect to) gitHub and needs to be *Pulled*.
  It will also be red if there were any **errors** encounted while
  scanning or getting information about the repo from gitHub
  or the repo violates one of the **invariants** required to
  use the repo wihtin gitUI (no detached HEADS, must
  have the default branch checked out, etc).
- **orange** - if the repo is **AHEAD** of gitHub,
  meaning that one or more commits have been made to it
  and it needs to be *Pushed* to gitHub.
- **magenta** - if there are any **staged or unstaged
  changes** indicating it needs review and likely
  *commits*.  It will also be magenta for the special
  case where a *submodule* has been updated and the
  parent (super) repo needs a *submodule commit* for
  the new updated changed submodule.
- **blue** - if the repo is *up to date* and is **private**.
- **green** - if the rrepo is *up to date* and **public**.


## Also See (Dependencies)

Besides being run as an installed EXE file, for developers
gitUI can be run directly from the **Perl source**
in this folder.

From a Perl point of view, gitUI **depends** on my
[base-Pub](https://gitHub.com/phorton1/base-Pub) library,
which must also be installed.  And there are many other
Perl libraries that must be installed for gitUI to work,
notably:

- Git::Raw
- Win32::ChangeNotify
- wxPerl

gitUI and all of my other Windows GUI applications depend on
[wxPerl](https://gitHub.com/phorton1/src-wx-wxPerl). My repo
contains a slighly modified version of wxPerl that I have worked
with for years, but the program *should* work with any Perl
that supports Wx::Perl.

You can also see my
[Strawberry Perl](https://gitHub.com/phorton1/Strawberry) repository for
an example of how to install a **Wx enabled** Perl Interpreter with the
required *Perl Modules* in order to run gitUI directly from the source.


## License

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License Version 3 as published by
the Free Software Foundation.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

Please see [**LICENSE.TXT**](../LICENSE.TXT) for more information.


---- end of readme ----
