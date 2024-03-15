# gitUI - context

The system has several notions of context for selecting getting to a repo.

It used to be an invariant that all repos had Path members, and could
always be located using that Path.  Along with the subversion caused by
repoGroups, now with REMOTE_ONLY repos, some repos don't have Paths.

**I think there is a currently a blink-out-of-existence bug when the
  infoWindow() cannot restore the context from the INI file**

- The commitListCtrl on works on LOCAL repos, which always have a Path.
  Since it saves and restores the expanded state of the showing repos
  by PATH in the INI file, this continues to work.
- The repoMenu::popupRepoMenu() takes a $repo, so it is never
  confused.


## The infoWindow (aka the subsWindow)

The infoWindow currently keeps a list of all controls
by Path, has a selectObject($path) method, and remembers
the {selected_path}.   Furthermore, repoGroups() use the
'master_submodule' ID as their Path and have numbers that
start over at 0 (as compared to the repo_list).

This *may* be fixable using the "pathOrId" notion more
generally. If a repo has a Path they are guaranteed to
be unique.   If it does not have a path, then it's ID
on GitHub is guaranteed to be unique.

Internal to the system (not in the INI file), we can
unambiguously pass $repos around.

I think I'm gonna call the repo_path_or_id the REPO_UUID.


## contextMenu

The contexts are build in the repo.pm and repoGroup.pm
**toTextCtrl()** methods.

They are retrieved during mouseOvers and leftClicks in
myTextCtrl.pm, and rightClicks in contextMenu.pm (which
is only used from myTextCtrl).


$ID_CONTEXT_OPEN_INFO

$ID_CONTEXT_OPEN_SUBS
	can use a repo_uuid because all submodules
	are local repos, and only the groups use an
	id.

$ID_CONTEXT_OPEN_GITUI
$ID_CONTEXT_BRANCH_HISTORY
$ID_CONTEXT_ALL_HISTORY
$ID_CONTEXT_OPEN_EXPLORER

$ID_CONTEXT_OPEN_GITHUB

$ID_CONTEXT_OPEN_IN_EDITOR
$ID_CONTEXT_OPEN_IN_SHELL
$ID_CONTEXT_OPEN_IN_NOTEPAD






--- end of readme ---