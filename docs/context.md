# gitMUI - Context Implementation Details

The system has several notions of context for selecting getting to a repo.

It used to be an invariant that all repos had Path members, and could
always be located using that Path.  Along with the subversion caused by
repoGroups, now REMOTE_ONLY repos may exizt without paths,

- The commitListCtrl on works on LOCAL repos, which always have a Path.
  Since it saves and restores the expanded state of the showing repos
  by PATH in the INI file, this continues to work.
- The repoMenu::popupRepoMenu() takes a $repo, so it is never
  confused.


## The infoWindow (aka the subsWindow)

The infoWindow currently keeps a list of all controls
by uuid, which is the path if one exists, or the id if
not.  It has a selectObject($uuid) method, and remembers
the {selected_uuid}.   Furthermore, repoGroups() use the
'master' gitHub ID as their Path and have numbers that
start over at 0 (as compared to the repo_list).


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