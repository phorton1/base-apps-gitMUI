#!/usr/bin/perl
#
# PRH TODO: NEED ARROW KEYS
#
#-------------------------------------------
# apps::gitUI::listCtrl
#-------------------------------------------
# custom listCtrl for use by commitList
#
# layout:
#
#  > [ ] /base/apps/gitUI
#    [ ] some_change.txt
#
#  > = toggle button for repositories
#      expand / contract
#  [ ] = icon showing type of thing
#       repo: shows '+' if any selected items
#             clicking on '+' acts on repo's selected items
#       item: if item is selected, this means to
#             act on ALL selected items.
#           if item is not selected, it acts on the
#             given item without otherwise changing
#             the selection set.
#  left clicking on entry will
#	 repo: shows repo details
#    item: toggle toggle selection state
#          see comments on onLeftDown() for gruesome
#          details of SHIFT and CTRL handling

package apps::gitUI::listCtrl;
use strict;
use warnings;
use threads;
use threads::shared;
use Win32::GUI;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_PAINT
	EVT_LEFT_DOWN
	EVT_LEFT_DCLICK
	EVT_RIGHT_DOWN
	EVT_MENU_RANGE );
	use Pub::Utils;
use Pub::WX::Dialogs;
use apps::gitUI::utils;
use apps::gitUI::repos;
use apps::gitUI::repoGit;
use apps::gitUI::repoMenu;
use base qw(Wx::ScrolledWindow apps::gitUI::repoMenu);


my $dbg_ctrl = 1;		# life cycle
my $dbg_pop = 1;		# update (populate)
my $dbg_draw = 1;		# drawing
my $dbg_sel = 1;		# selection
	# 0  == everything except
	# -1 == addShiftSel() adding of individual shift-sel items
my $dbg_actions = 0;	# actions on index
my $dbg_cmd = 1;		# context menu and commands


my $ROW_HEIGHT  = 18;

my $ACTION_DO_ALL = 0;				# do all files in all repos
my $ACTION_DO_REPO = 1;				# do selected files within repo
my $ACTION_DO_SELECTED = 2;			# do all selected files
my $ACTION_DO_SINGLE_FILE = 3;		# do a single (unselected) file


# watch out for conflicts with repoMenu.pm IDs

my ($ID_REVERT_CHANGES,
	$ID_OPEN_IN_KOMODO,
	$ID_OPEN_IN_SHELL,
	$ID_OPEN_IN_NOTEPAD ) = (9000..9999);
my $menu_desc = {
	$ID_REVERT_CHANGES  => ['Revert',			'Revert changes to one or more items' ],
	$ID_OPEN_IN_KOMODO	=> ['Komodo',			'Open one or more items in Komodo Editor' ],
	$ID_OPEN_IN_SHELL   => ['Shell',			'Open single item in the Windows Shell' ],
	$ID_OPEN_IN_NOTEPAD => ['Notepad',			'Open single item in the Windows Notepad' ],
};


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}

my $selected_brush = Wx::Brush->new($color_item_selected,wxBRUSHSTYLE_SOLID);
my $selected_pen = Wx::Pen->new($color_item_selected,1,wxPENSTYLE_SOLID);


sub new
{
    my ($class,$parent,$is_staged,$PAGE_TOP,$data) = @_;
    my $name = $is_staged ? 'staged' : 'unstaged';

	display($dbg_ctrl,0,"new listCtrl($name,$PAGE_TOP) data="._def($data));
	$data ||= { contracted => {} };
	display_hash($dbg_ctrl,0,"expanded",$data->{contracted});

    my $this = $class->SUPER::new($parent,-1,[0,$PAGE_TOP]);	# [$w,$h]); # ,wxVSCROLL | wxHSCROLL);
	bless $this,$class;

    $this->{parent} = $parent;
	$this->{is_staged} = $is_staged;
	$this->{key} = $is_staged ? 'staged_changes' : 'unstaged_changes';
	$this->{name} = $name;
	$this->{data} = $data;
	$this->{repos} = {};
	$this->{expanded} = {};
		# hash by id of expanded state of repos
	$this->{selection} = {};
		# a nested hash of repos by id and 1 by filename
		# of ALL durrently selected files.
	$this->{anchor} = '';
		# the anchor item, if any for SHIFT selection

	$this->SetVirtualSize([0,0]);
	$this->SetBackgroundColour($color_white);
	$this->SetScrollRate(0,$ROW_HEIGHT);

	EVT_PAINT($this, \&onPaint);
	EVT_LEFT_DOWN($this,\&onLeftDown);
	EVT_LEFT_DCLICK($this,\&onLeftDown);
		# We have to register DCLICK or else we 'lose'
		# mouse down events.
	EVT_RIGHT_DOWN($this,\&onRightDown);
	EVT_MENU_RANGE($this, $ID_REVERT_CHANGES, $ID_OPEN_IN_NOTEPAD, \&onItemMenu);

	$this->addRepoMenu();

	return $this;
}


sub getDataForIniFile
{
	my ($this) = @_;
	my $contracted = {};
	my $data = { contracted => $contracted };
	my $repos = $this->{repos};
	for my $id (sort keys %$repos)
	{
		$contracted->{$id} = 1
			if !$this->{expanded}->{$id};
	}
	display_hash($dbg_ctrl,0,"getDataForIniFile(expanded)",$contracted);
	return $data;
}


sub isSelected
{
	my ($this,$id,$fn) = @_;
	my $sel_repo = $this->{selection}->{$id};
	my $selected = $sel_repo && $sel_repo->{$fn} ? 1 : 0;
	return $selected;
}


sub clearOtherSelection
{
	my ($this) = @_;
	my $other = $this->{is_staged} ?
		$this->{parent}->{parent}->{unstaged}->{list_ctrl} :
		$this->{parent}->{parent}->{staged}->{list_ctrl};
	return if !(keys %{$other->{selection}});

	$other->{selection} = {};
	$other->{anchor} = '';
	$other->{found_repo} = '';
	$other->{found_item} = '';
	$other->Refresh();
}


#-----------------------------------------------
# updateRepos
#-----------------------------------------------

sub updateRepos
	# essentially populate(), add or update any repos to
	# the list without losing selected, expanded, etc
{
	my ($this) = @_;
	display($dbg_pop,0,"updateRepos($this->{name})");

	my $vheight = 0;
	my $num_repos = 0;
	$this->{repos} = {};
	my $save_expanded = $this->{expanded};
	$this->{expanded} = {};

	my $repo_list = getRepoList();
	for my $repo (@$repo_list)
	{
		my $id = $repo->{id};
		my $items = $repo->{$this->{key}};
		my $num_items = scalar(keys %$items);
		if ($num_items)
		{
			$num_repos++;
			$vheight += $ROW_HEIGHT;
			$this->{repos}->{$id} = $repo;
			if ($this->{data}->{contracted}->{$id})
			{
				display($dbg_ctrl,1,"contracting $id");
				$this->{expanded}->{$id} = 0;
				delete $this->{data}->{contracted}->{$id};
			}
			else
			{
				$this->{expanded}->{$id} = defined($save_expanded->{$id}) ?
					$save_expanded->{$id} : 1;
			}
			$vheight += $num_items * $ROW_HEIGHT
				if $this->{expanded}->{$id};
		}
	}

	my $sz = $this->GetSize();
    my $width = $sz->GetWidth();
    my $height = $sz->GetHeight();
	$this->SetVirtualSize([$width,$vheight]);
	$this->Refresh();

	display($dbg_pop,0,"endUpdate($this->{name}) finished with num_repos($num_repos) vheight($vheight)");
}



#-----------------------------------------------
# onPaint
#-----------------------------------------------

sub onPaint
{
	my ($this, $event) = @_;

 	my $sz = $this->GetSize();
    my $width = $sz->GetWidth();
    my $height = $sz->GetHeight();

	my $repos = $this->{repos};
	my $num_repos = scalar(keys %$repos);

	display($dbg_draw,0,"onPaint($this->{name},$width,$height) num_repos($num_repos)");
		# above in pixels

	my $dc = Wx::PaintDC->new($this);
	$this->DoPrepareDC($dc);

	# get update rectangle in unscrolled coords

	my $region = $this->GetUpdateRegion();
	my $box = $region->GetBox();
	my ($xstart,$ystart) = $this->CalcUnscrolledPosition($box->x,$box->y);
	my $update_rect = Wx::Rect->new($xstart,$ystart,$box->width,$box->height);
	my $bottom = $update_rect->GetBottom();
	display_rect($dbg_draw,1,"onPaint($this->{name}) bottom=$bottom update_rect=",$update_rect);

	# clear the update rectangle
	# not using $dc->Clear();
	#
	# the 9pt font I am using is 11 pixels high, from 3..13 when drawn at 0
	# the proper ROW_HEIGHT for equidistant spacing would be 17 with 3
	# above and 3 below the text, but I use 18 and allow one extra pixel
	# at the bottom

	$dc->SetPen(wxWHITE_PEN);
	$dc->SetBrush(wxWHITE_BRUSH);
	$dc->DrawRectangle($update_rect->x,$update_rect->y,$update_rect->width,$update_rect->height);

	# Draw the Repo

	my $ypos = 0;
	my $item_rect = Wx::Rect->new(0,$ypos,$width,$ROW_HEIGHT);
	for my $id (sort keys %$repos)
	{
		my $repo = $repos->{$id};

		$item_rect->SetY($ypos);
		$this->drawRepo($dc,$item_rect,$repo)
			if $update_rect->Intersects($item_rect);

		$ypos += $ROW_HEIGHT;
		last if $ypos >= $bottom;

		if ($this->{expanded}->{$id})
		{
			my $items = $repo->{$this->{key}};
			for my $fn (sort keys %$items)
			{
				$item_rect->SetY($ypos);

				$this->drawItem($dc,$item_rect,$items->{$fn})
					if $update_rect->Intersects($item_rect);

				$ypos += $ROW_HEIGHT;
				last if $ypos >= $bottom;
			}
		}
		last if $ypos >= $bottom;
	}

}	# onPaint()



my $TOGGLE_LEFT  = 1;			# icon location
my $TOGGLE_RIGHT = 11;			# mouse area
my $ICON_LEFT    = 12;			# icon location
my $ICON_RIGHT   = 27;			# mouse area - selected rectangle is two to left of TEXT left
my $TEXT_LEFT    = 30;


sub drawRepo
{
	my ($this,$dc,$rect,$repo) = @_;
	my $id = $repo->{id};
	display_rect($dbg_draw,0,"drawRepo($this->{name},$id)",$rect);

	my $ypos = $rect->y;
	my $width = $rect->width;
	my $expanded = $this->{expanded}->{$id};
	my $num_items = scalar(keys %{$repo->{$this->{key}}});
	my $repo_sel = $this->{selection}->{$id};
	my $num_selected = $repo_sel ? scalar(keys %$repo_sel) : 0;
	my $name = "$id (".($num_selected?"$num_selected/":'')."$num_items)";

	display($dbg_draw,0,"drawRepo($this->{name},$ypos) exp($expanded) sel($num_selected) num($num_items) $id");

	my $bm = $expanded ? $bm_up_arrow : $bm_right_arrow;

	if ($num_selected)
	{
		my $bm2 = $this->{is_staged} ? $bm_minus : $bm_plus;
		my $color2 = $this->{is_staged} ? $color_red : $color_green;
		$dc->SetTextForeground($color2);
		$dc->DrawBitmap($bm2, $ICON_LEFT, $ypos+4, 0);
	}
	$dc->SetFont($font_bold);
	$dc->SetTextForeground($color_blue);
	$dc->DrawBitmap($bm, $TOGGLE_LEFT, $ypos+3, 0);
	$dc->DrawText($name,$TEXT_LEFT,$ypos);
}


sub drawItem
{
	my ($this,$dc,$rect,$item) = @_;

	my $fn = $item->{fn};
	my $ypos = $rect->y();
	my $width = $rect->width();
	my $type = $item->{type};
	my $repo = $item->{repo};
	my $id = $repo->{id};
	my $selected = $this->isSelected($id,$fn);

	display($dbg_draw,0,"drawItem($this->{name},$ypos) sel($selected) $type $fn");

	my $staged = $this->{is_staged};
	my $bm_color =
		$type eq 'M' ? $staged ? $color_green : $color_blue :
		$type eq 'D' ? $color_red :
		$color_black;
	my $bm =
		$type eq 'M' ? $staged ? $bm_folder_check : $bm_folder_lines :
		$type eq 'D' ? $staged ? $bm_folder_x : $bm_folder_question :
		$bm_folder;

	# bitmaps are drawn using the text foreground color

	$dc->SetTextForeground($bm_color);
	$dc->DrawBitmap($bm, $ICON_LEFT, $ypos, 0);

	# draw the selected rectangle
	# an extra two pixels to the left

	$dc->SetPen($selected ? $selected_pen : wxWHITE_PEN);
	$dc->SetBrush($selected ? $selected_brush : wxWHITE_BRUSH);
	$dc->DrawRectangle($TEXT_LEFT-2,$ypos,$width-$TEXT_LEFT+2,$ROW_HEIGHT);

	# draw the text

	$dc->SetFont($font_normal);
	$dc->SetTextForeground($selected ? $color_white : $color_black);
	$dc->DrawText($fn,$TEXT_LEFT,$ypos);
}



#-----------------------------------------------
# Mouse Handling
#-----------------------------------------------
# The window is single selection if no keys pressed,
# multiple selection if keys pressed, and handles
# SHIFT selection:
#
#   We save the last_selected item in terms of it's unscrolled Y position
#		if they toggle an item to selected. where -1 means none
#	A click on anything except for another file (or repo name) invalidates last_selected
#   A click on the same item toggles its state.
#
# See comments below for details.
#
# REFRESH
#    We either refresh a single item, and the repo if it is visible
#    during a single item toggle, or we refresh the whole window.
#    during any complicated actions.


sub findClickItem
{
	my ($this,$ux,$uy) = @_;

	# find the repo and/or item for unscrolled position $x,$y

	my $ypos = 0;
	$this->{found_repo} = '';
	$this->{found_item} = '';
	$this->{repo_uy} = 0;
	$this->{item_uy} = 0;

	my $repos = $this->{repos};
	for my $id (sort keys %$repos)
	{
		my $repo = $repos->{$id};
		my $items = $repo->{$this->{key}};
		my $num_items = scalar(keys %$items);
		my $repo_height = $this->{expanded}->{$id} ?
			($num_items + 1) * $ROW_HEIGHT : $ROW_HEIGHT;

		if ($uy >= $ypos && $uy <= $ypos + $repo_height-1)
		{
			$this->{found_repo} = $repo;
			$this->{repo_uy} = $ypos;
			display($dbg_sel,1,"foundRepo($this->{name},$id) at ypos($ypos) with height($repo_height)");
			if ($uy >= $ypos + $ROW_HEIGHT)
			{
				my $off = $uy - $ypos - $ROW_HEIGHT;		# mouse y offset within repo's items
				my $idx = int($off / $ROW_HEIGHT);			# index into repo's items
				my $fn = (sort keys %$items)[$idx];			# found filename
				$this->{found_item} = $items->{$fn};		# found item

				$this->{item_uy} = $ypos + $ROW_HEIGHT + $idx * $ROW_HEIGHT;
					# save off the item position for optimized refresh
					# it is $idx+1 cuz the 0th item is below the repo header

				display($dbg_sel,1,"foundItem($this->{name},$fn,$this->{found_item}->{type}) at off($off) idx($idx) item_uy($this->{item_uy})");
				last;
			}
			last;
		}
		else
		{
			$ypos += $repo_height;
		}
	}
}



sub onLeftDown
{
	my ($this,$event) = @_;

	$this->clearOtherSelection();

	my $cp = $event->GetPosition();
	my ($sx,$sy) = ($cp->x,$cp->y);
	my ($ux,$uy) = $this->CalcUnscrolledPosition($sx,$sy);

	my $sz = $this->GetSize();
	my $win_width = $sz->GetWidth();
	my $win_height = $sz->GetHeight();
	$this->{win_srect} = Wx::Rect->new(0,0,$win_width,$win_height);

	my $VK_SHIFT = 0x10;
	my $VK_CONTROL = 0x11;
	my $anchor = $this->{anchor};
	my $selection = $this->{selection};
	my $shift_key = Win32::GUI::GetAsyncKeyState($VK_SHIFT)?1:0;
	my $ctrl_key = Win32::GUI::GetAsyncKeyState($VK_CONTROL)?1:0;

	display($dbg_sel,0,"onLeftDown($this->{name},$ux,$uy) ctrl($ctrl_key) shift($shift_key)");

	# find the repo and/or item for unscrolled position $x,$y

	$this->findClickItem($ux,$uy);

	# gitGUI always has an item selected and remembers the last item
	#	actually selected between reboots
	# 	our window does not remember any selection between reboots
	#
	# No SHIFT or CTRL deletes all selection except the current
	#   item (if it happens to be selected), as well as the anchor
	#
	# if not both SHIFT and an anchor, toggle the state of the
	#   item.  If it item gets selected, set the anchor, otherwise
	#   clear the anchor.
	# else (SHIFT and anchor)
	#	select all items between the anchor and the current item, inclusive
	#
	# NOTE that we allow a SHIFT with an anchor to end on a repo or blank
	#	space at the end of window and treat it as a selection command
	#   from the anchor to the selected repo/item (or the last visible
	#   repo/item if in the white space).

	$this->{refresh_rect} = Wx::Rect->new(-1,-1,$win_width,$win_height);
		# in scrolled coordinates
		# x == -1 implies unitialized for optimized single selection toggle case

	if ($shift_key && $anchor)
	{
		$this->{refresh_rect} = $this->{win_srect} 	# refresh whole window
			if $this->addShiftSelection();			# if selection changed
	}
	elsif ($ctrl_key && !$this->{found_item})
	{
		# ctrl key currently does nothing if clicked on a repo
	}
	elsif ($this->{found_item})
	{
		if ($ux <= $ICON_RIGHT)
		{
			if ($ux >= $ICON_LEFT)
			{
				my $fn = $this->{found_item}->{fn};
				my $id = $this->{found_repo}->{id};
				my $selected = $this->isSelected($id,$fn);
				my $how = $selected ?
					$ACTION_DO_SELECTED :
					$ACTION_DO_SINGLE_FILE;
				my $show = $selected ?
					'ACTION_DO_SELECTED' :
					'ACTION_DO_SINGLE_FILE';
				display($dbg_actions,0,$show);
				$this->doAction($how);
			}
		}
		else
		{
			if (!$shift_key && !$ctrl_key)
			{
				$this->{refresh_rect} = $this->{win_srect} 	# refresh whole window
					if $this->deleteSelectionsExcept();       # if this wasn't already the only selection
			}

			$this->toggleSelection();
		}
	}
	elsif ($this->{found_repo})
	{
		my $repo = $this->{found_repo};
		my $id = $repo->{id};
		if ($ux <= $TOGGLE_RIGHT)
		{
			$this->{expanded}->{$id} = !$this->{expanded}->{$id};
			$this->{refresh_rect} = $this->{win_srect}; 	# refresh whole window
		}
		elsif ($ux <= $ICON_RIGHT)
		{
			if ($ux >= $ICON_LEFT)
			{
				display($dbg_actions,0,"ACTION_DO_REPO");
				$this->doAction($ACTION_DO_REPO)
					if $this->{selection}->{$id};
			}
		}
		else	# expand and ICON do not count as selecting the repo
		{
			$this->notifyRepoSelected($this->{found_repo});
		}
	}

	# DONE - REFRESH AS NEEDED AND RETURN

	if ($this->{refresh_rect}->x >= 0)
	{
		display_rect($dbg_sel,0,"REFRESH_RECT($this->{name})",$this->{refresh_rect});
		$this->RefreshRect($this->{refresh_rect})
	}

	$event->Skip();
}


sub notifyRepoSelected
{
	my ($this,$repo) = @_;
	$this->{parent}->{parent}->{right}->notifyItemSelected({
		is_staged => $this->{is_staged},
		repo =>$repo,
		item => '' });
}



sub addShiftSelection
{
	my ($this) = @_;

	my $found_repo  = $this->{found_repo};
	my $found_item  = $this->{found_item};
	my $anchor_item = $this->{anchor};
	my $anchor_fn   = $anchor_item->{fn};
	my $anchor_repo = $anchor_item->{repo};
	my $anchor_id   = $anchor_repo->{id};

	display($dbg_sel,0,"addShiftSelection($this->{name}) anchor($anchor_id,$anchor_fn) found(".
		($found_repo?$found_repo->{id}:'').",".
		($found_item?$found_item->{fn}:'').")");

	my $first_repo = $anchor_repo;
	my $first_item = $anchor_item;
	my $last_repo;
	my $last_item;

	# set the first and last items if a repo or item was found

	my $stop_on_last = 0;

	if ($found_repo)
	{
		# we determine the direction based on comparing the ids
		# if going up and no item, then the whole repo was selected
		# but its the opossite going down.

		my $found_id = $found_repo->{id};

		if ($found_id lt $anchor_id)
		{
			# going up, will include all items in the found repo
			# if no item was specified.
			display($dbg_sel,2,"found_id($found_id) lt anchor_id($anchor_id)");
			$first_repo = $found_repo;
			$found_item = $found_item;
			$last_repo = $anchor_repo;
			$last_item = $anchor_item;
		}
		elsif ($found_id gt $anchor_id)
		{
			# going down will STOP on the last repo if no item
			display($dbg_sel,2,"found_id($found_id) gt anchor_id($anchor_id)");
			$last_repo = $found_repo;
			$last_item = $found_item;
			$stop_on_last = 1 if !$found_item;
		}

		# within the same repo

		elsif ($found_item)
		{
			my $found_fn = $found_item->{fn};
			if ($found_fn lt $anchor_fn)
			{
				display($dbg_sel,2,"found_fn($found_fn) lt anchor_fn($anchor_fn)");
				$first_repo = $found_repo;
				$first_item = $found_item;
				$last_repo = $anchor_repo;
				$last_item = $anchor_item;
			}
			elsif ($found_fn gt $anchor_fn)
			{
				display($dbg_sel,2,"found_fn($found_fn) gt anchor_fn($anchor_fn)");
				$last_repo = $found_repo;
				$last_item = $found_item;
			}
			else
			{
				display($dbg_sel,2,"same SHIFT_ITEM($anchor_id,$anchor_fn) RETURNING with no change!");
				return 0;
			}
		}
	}

	# else its (!$found_repo && !$found_item) so
	# we elect all items from anchor to end
	# by using initial assignments and null ends
	# since they clicked PAST the last repo

	# LOOP THROUGH ALL TREES

	my $any_changes = 0;
	my $repos = $this->{repos};

	my $first_id = $first_repo->{id};
	my $first_fn = $first_item ? $first_item->{fn} : '';
	my $last_id = $last_repo ? $last_repo->{id} : '';
	my $last_fn = $last_item ? $last_item->{fn} : '';

	display($dbg_sel,1,"first($first_id,$first_fn) last($last_id,$last_fn)");

	my @ids = sort keys %$repos;
	my $id = shift @ids;
	my $repo = $repos->{$id};
	my $items = $repo->{$this->{key}};
	my $last = !@ids || $id eq $last_id ? 1 : 0;

	while (1)
	{
		if ($id ge $first_id)
		{
			my $first = $id eq $first_id ? 1 : 0;
			my $between = $id gt $first_id ? 1 : 0;

			display($dbg_sel,1,"REPO($this->{name},$id) first($first) between($between) last($last) stop_on_last($stop_on_last)");
			last if $stop_on_last && $last;

			for my $fn (sort keys %$items)
			{
				my $addit = 0;

				if ($first)
				{
					$addit = $fn ge $first_fn;
					$addit = 0 if $last && $last_fn && $last_fn lt $fn;
				}
				elsif ($last)
				{
					$addit = !$last_fn || $fn le $last_fn;
				}
				else
				{
					$addit = 1;
				}

				$any_changes += $this->addShiftSel($repo,$fn)
					if $addit;
			}
			last if $last;
		}

		# next repo

		$id = shift @ids;
		$repo = $repos->{$id};
		$items = $repo->{$this->{key}};
		$last = !@ids || $id eq $last_id ? 1 : 0;
	}

	display($dbg_sel,0,"addShiftSelection($this->{name},) returning $any_changes");
	return $any_changes;
}


sub addShiftSel
{
	my ($this,$repo,$fn) = @_;
	my $selection = $this->{selection};
	my $id = $repo->{id};
	display($dbg_sel+1,0,"addShiftSel($this->{name},$id,$fn)");

	my $repo_sel = $selection->{$id};
	if (!$repo_sel)
	{
		display($dbg_sel+1,1,"creating new repo_sel");
		$selection->{$id} = { $fn => 1 };
		return 1;
	}
	elsif (!$repo_sel->{$fn})
	{
		display($dbg_sel+1,1,"adding to existing repo_sel");
		$repo_sel->{$fn} = 1;
		return 1;
	}
	else
	{
		display($dbg_sel+1,1,"already selected");
	}
	return 0;
}



sub deleteSelectionsExcept
{
	my ($this) = @_;
	my $selection = $this->{selection};
	my $num_sels = scalar(keys %$selection);

	my $item = $this->{found_item};
	my $repo = $item->{repo};
	my $fn = $item->{fn};
	my $id = $repo->{id};

	my $repo_sel = $this->{selection}->{$id};
	my $num_repo_sels = $repo_sel ? scalar(keys %$repo_sel) : 0;
	my $cur_sel = $repo_sel ? $repo_sel->{$fn} : 0;
	$cur_sel ||= 0;

	display($dbg_sel,0,"deleteSectionsExcept($this->{name},$id,$fn) num_sels($num_sels) num_repo_sels($num_repo_sels) cur_sel($cur_sel)");

	return 0 if !$num_sels;
	return 0 if $cur_sel && $num_sels == 1 && $num_repo_sels == 1;

	$this->{selection} = {};

	if ($cur_sel)
	{
		$repo_sel = $this->{selection}->{$id} = {};
		$repo_sel->{$fn} = 1;
	}
	return 1;
}


sub notifyItemSelected
{
	my ($this,$repo,$item) = @_;
	my $id = $repo ? $repo->{id} : '';
	my $fn = $item ? $item->{fn} : '';
	display($dbg_sel,0,"notifyItemSelected($this->{name},$id,$fn)");
	$this->{parent}->{parent}->{right}->notifyItemSelected({
		is_staged => $this->{is_staged},
		repo =>$repo,
		item =>$item });
}


sub toggleSelection
{
	my ($this) = @_;

	my $item = $this->{found_item};
	my $fn = $item->{fn};

	my $repo = $item->{repo};
	my $id = $repo->{id};
	my $selection = $this->{selection};
	my $repo_sel = $selection->{$id};
	my $selected = $repo_sel ? $repo_sel->{$fn} : 0;
	$selected |= 0;

	display($dbg_sel,0,"toggleSelection($this->{name},$id,$fn) selected=$selected");

	if ($selected)	# unselecting
	{
		delete $repo_sel->{$fn};
		delete $selection->{$id} if !keys %$repo_sel;
		$this->{anchor} = '';
	}
	elsif (!$repo_sel)
	{
		$repo_sel = { $fn => 1 };
		$selection->{$id} = $repo_sel;
		$this->{anchor} = $item;
		$this->notifyItemSelected($repo,$item);
	}
	else
	{
		$repo_sel->{$fn} = 1;
		$this->{anchor} = $item;
		$this->notifyItemSelected($repo,$item);
	}

	# optimized refresh if whole screen not already done

	my $refresh_rect = $this->{refresh_rect};		# scrolled position (0..$height-1)
	if ($refresh_rect->x < 0)
	{
		my $width = $this->{win_srect}->width;
		my ($unused1,$repo_sy) = $this->CalcScrolledPosition(0,$this->{repo_uy});
		my ($unused2,$item_sy) = $this->CalcScrolledPosition(0,$this->{item_uy});
		my $repo_srect = Wx::Rect->new(0,$repo_sy,$width,$ROW_HEIGHT);
		my $item_srect = Wx::Rect->new(0,$item_sy,$width,$ROW_HEIGHT);

		display_rect($dbg_sel,0,"refresh_rect",$item_srect);

		$this->{refresh_rect} = $item_srect;		# refresh the item
		$this->RefreshRect($repo_srect)				# and the repo if it is visible
			if $this->{win_srect}->Intersects($repo_srect);
	}
}


#-----------------------------------------
# doAction
#-----------------------------------------
# my $ACTION_DO_ALL = 0;				# do all files in all repos
#	  optimized to call gitIndex() with no paths
# my $ACTION_DO_REPO = 1;				# do selected files within repo
# my $ACTION_DO_SELECTED = 2;			# do all selected files
# my $ACTION_DO_SINGLE_FILE = 3;		# do a single (unselected) file


sub doActionRepo
	# in all cases, the repo's selection is going away
{
	my ($this,$how,$repo) = @_;
	my $id = $repo->{id};
	display($dbg_actions,0,"doActionRepo($this->{name},$how,$id)");

	my $repo_sel = $this->{selection}->{$id};
	delete $this->{selection}->{$id};

	my $doit = 1;						# do all by default
	my $paths = '';
	if ($how == $ACTION_DO_REPO ||		# do all selected files within repo
		$how == $ACTION_DO_SELECTED)	# do all selected files
	{
		$doit = 0;
		$paths = [];
		for my $fn (sort keys %$repo_sel)
		{
			$doit = 1;
			push @$paths,$fn;
		}
	}

	if ($doit)
	{
		display($dbg_actions,1,"calling gitIndex($this->{is_staged},$paths)");
		return gitIndex($repo,$this->{is_staged},$paths);
	}
	return 0;
}



sub doAction
{
	my ($this,$how) = @_;

	$how ||= $ACTION_DO_ALL;
	display($dbg_actions,0,"doAction($this->{name},$how)");
	$this->{selection} = {} if $how == $ACTION_DO_ALL;
	$this->{anchor} = '';

	if ($how == $ACTION_DO_SINGLE_FILE)
	{
		my $repo = $this->{found_repo};
		my $item = $this->{found_item};
		my $fn = $item->{fn};

		# getAppFrame()->getMonitor()->suppressPath($repo->{path});
			# possible optimization for single item action

		gitIndex($repo,$this->{is_staged},[$fn]);
	}
	elsif ($how == $ACTION_DO_REPO)
	{
		$this->doActionRepo($how,$this->{found_repo});
	}
	else
	{
		my $repos = $this->{repos};
		my $selection = $this->{selection};
		for my $id (sort keys %$repos)
		{
			my $doit = $how == $ACTION_DO_ALL;
			$doit = 1 if $selection->{$id};	# $ACTION_DO_SELECTED
			return if $doit && !$this->doActionRepo($how,$repos->{$id});

			# we currently wait for the callback to delete
			# unused repos, but we know they went away
			# if $ACTION_DO_ALL and or we could determine
			# if all items were selected for $ACTION_DO_SELECTED
		}
	}

	$this->notifyItemSelected('','');
}


#---------------------------------------------
# context menu
#---------------------------------------------
# I build a custom menu that only shows the
# allowed commands depending on the context.
#
# We can also open repos in other as yet created windows:
#
#		Dependencies,
#		Doc Analysis,
#		etc
#
# Items can be opened in komodo, the shell, or the notepad.
# Only the clicked item is opned in the shell or notepad,
# but if they click on a selection all selected items are opend in komodo,
# and it is up to the user to not open multiple files of the


sub onRightDown
{
	my ($this,$event) = @_;
	my $cp = $event->GetPosition();
	my ($sx,$sy) = ($cp->x,$cp->y);
	my ($ux,$uy) = $this->CalcUnscrolledPosition($sx,$sy);
	display($dbg_cmd,0,"onRightDown($this->{name},$ux,$uy)");

	$this->findClickItem($ux,$uy);
	my $repo = $this->{found_repo};
	return if !$repo;
	my $item = $this->{found_item};

	if (!$item)
	{
		$this->popupRepoMenu($repo);
		return;
	}

	display($dbg_cmd,1,"buildMenu repo($repo->{id}) fn(".($item?$item->{fn}:'').")");

	my $menu = Wx::Menu->new();
	foreach my $id ($ID_REVERT_CHANGES..$ID_OPEN_IN_NOTEPAD)
	{
		my $desc = $menu_desc->{$id};
		my ($text,$hint) = @$desc;
		if ($id != $ID_REVERT_CHANGES || !$this->{is_staged})
		{
			$menu->Append($id,$text,$hint,wxITEM_NORMAL);
			$menu->AppendSeparator() if $id == $ID_REVERT_CHANGES;
		}
	}
	$this->PopupMenu($menu,[-1,-1]);
}



sub onItemMenu
{
	my ($this,$event) = @_;
	my $command_id = $event->GetId();

	my $repo = $this->{found_repo};
	my $item = $this->{found_item};
	my $id = $repo->{id};
	my $fn = $item->{fn};
	my $selection = $this->{selection};
	my $repo_sel = $this->{selection}->{$id};
	my $selected = $repo_sel ? $repo_sel->{$fn} : 0;
	$selected ||= 0;
	my $multiple = 0;

	$multiple = 1 if $selected &&
		scalar(keys %$repo_sel) > 1 ||
		scalar(keys %$selection) > 1;

	display($dbg_cmd,0,"onItemMenu($this->{name},$command_id) repo($id) fn($fn) selected($selected) multiple($multiple)");

	if ($command_id == $ID_OPEN_IN_SHELL)
	{
		chdir $repo->{path};
		system(1,"\"$repo->{path}/$fn\"");
	}
	elsif ($command_id == $ID_OPEN_IN_NOTEPAD)
	{
		execNoShell("notepad \"$repo->{path}/$fn\"");
		# system(1,"notepad \"$repo->{path}/$fn\"");
	}
	elsif ($command_id == $ID_OPEN_IN_KOMODO)
	{
		my $filenames = [];
		if (!$multiple)
		{
			my $path = $repo->{path};
			push @$filenames,"\"$path/$fn\"";;
		}
		else
		{
			for my $id (sort keys %$selection)
			{
				my $repo = $this->{repos}->{$id};
				my $path = $repo->{path};
				my $repo_sel = $this->{selection}->{$id};
				for my $fn (sort keys %$repo_sel)
				{
					push @$filenames,"\"$path/$fn\"";;
				}
			}
		}
		my $komodo = "\"C:\\Program Files (x86)\\ActiveState Komodo Edit 8\\komodo.exe\"";
		my $command = $komodo." ".join(" ",@$filenames);
		display($dbg_cmd,1,"calling '$command'");
		execNoShell($command);
		# system(1,$command);
	}

	#-----------------------
	# revert
	#-----------------------

	elsif ($command_id == $ID_REVERT_CHANGES)
	{
		if (!$multiple)
		{
			my $path = $repo->{path};
			my $filename = "$path/$fn";
			my $ok = $item->{type} eq 'A' ?
				yesNoDialog($this,
					"Do you want to delete the untracked file\n'$filename' ??",
					"Revert changes to single file") :
				yesNoDialog($this,
					"Revert changes to\n'$filename' ?",
					"Revert changes to single file");
			gitRevert($repo,[ $fn ]) if $ok;
		}
		else
		{
			# first pass to ask questions

			my $count_repos = 0;
			my $count_files = 0;
			my $count_deletes = 0;
			for my $id (sort keys %$selection)
			{
				$count_repos++;
				my $repo = $this->{repos}->{$id};
				my $repo_sel = $this->{selection}->{$id};
				for my $fn (keys %$repo_sel)
				{
					$count_files++;
					my $item = $repo->{unstaged_changes}->{$fn};
					$count_deletes++ if $item->{type} eq 'A';
				}
			}
			my $ok = yesNoDialog($this,
				"Revert changes to $count_files files in $count_repos repos ?",
				"Revert multiple changes");
			$ok &&= yesNoDialog($this,
				"Do you want to delete $count_deletes untracked files ???",
				"Delete untracked files?") if $count_deletes;
			return if !$ok;

			# second pass to actually do it

			for my $id (sort keys %$selection)
			{
				my $paths = [];
				my $repo = $this->{repos}->{$id};
				my $repo_sel = $this->{selection}->{$id};
				for my $fn (keys %$repo_sel)
				{
					push @$paths,$fn;
				}
				last if !gitRevert($repo,$paths);

			}	# for each repo with selections
		}	# if multiple files
	}	# $ID_REVERT_CHANGES
}	# onCommand()



1;