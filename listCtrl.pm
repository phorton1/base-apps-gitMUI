#!/usr/bin/perl
#
# PRH TODO: StageAll and UnstageAll buttons in headers
# PRH TODO: NEED ARROW KEYS
# PRH TODO: need implement stub for diff window
# PRH TODO: then can work on stage, unstage, and revert
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
#		clicking it will stage the thing
#       if repo has no selected items, will act on all
#       if repo has selected items will act on only those
#  short clicking on entry will
#	 repo: will open regular gitUI to the repo
#    toggle selection of repo items
#  TODO: context menu for right clicks
#    repo: show repo detils
#    file: call the shell except for certain overidden types
#		.pm, .md -> komodo



package apps::gitUI::listCtrl;
use strict;
use warnings;
use threads;
use threads::shared;
use Win32::GUI;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_PAINT
	EVT_LEFT_DOWN );
use apps::gitUI::styles;
use Pub::Utils;
use base qw(Wx::ScrolledWindow);	# qw(Wx::Window);


my $dbg_ctrl = 0;
my $dbg_draw = 1;
my $dbg_sel = 1;
	# 0  == everything except
	# -1 == addShiftSel() adding of individual shift-sel items
my $dbg_actions = 0;



my $ROW_HEIGHT  = 18;


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}

my $selected_brush = Wx::Brush->new($color_item_selected,wxBRUSHSTYLE_SOLID);
my $selected_pen = Wx::Pen->new($color_item_selected,1,wxPENSTYLE_SOLID);


sub new
{
    my ($class,$parent,$name,$PAGE_TOP,$data) = @_;
	display($dbg_ctrl,0,"new listCtrl($name,$PAGE_TOP) data="._def($data));
	$data ||= { contracted => {} };
	display_hash($dbg_ctrl,0,"expanded",$data->{contracted});

    my $this = $class->SUPER::new($parent,-1,[0,$PAGE_TOP]);	# [$w,$h]); # ,wxVSCROLL | wxHSCROLL);
	bless $this,$class;

    $this->{parent} = $parent;
	$this->{name} = $name;
	$this->{data} = $data;
	$this->{trees} = {};
	$this->{selection} = {};
		# a nested hash of trees by id and 1 by filename
		# of ALL durrently selected files.
	$this->{anchor} = '';
		# the anchor item, if any for SHIFT selection

	$this->SetVirtualSize([0,0]);
	$this->SetBackgroundColour($color_white);
	$this->SetScrollRate(0,$ROW_HEIGHT);

	EVT_PAINT($this, \&onPaint);
	EVT_LEFT_DOWN($this,\&onLeftDown);

	return $this;
}


sub getDataForIniFile
{
	my ($this) = @_;
	my $contracted = {};
	my $data = { contracted => $contracted };
	my $trees = $this->{trees};
	for my $id (sort keys %$trees)
	{
		$contracted->{$id} = 1
			if !$trees->{$id}->{expanded};
	}
	display_hash($dbg_ctrl,0,"getDataForIniFile(expanded)",$contracted);
	return $data;
}




#-----------------------------------------------
# building
#-----------------------------------------------

sub item
{
	my ($tree,$fn,$type) = @_;
	my $item = {
		tree => $tree,
		fn	 => $fn,
		type => $type,
		exists => 1 };
	return $item;
}


sub tree
{
	my ($repo,$changes) = @_;

	my $items = {};

	my $tree = {
		id => $repo->{id},
		repo => $repo,		# unused so far
		items => $items,
		exists => 1,
		expanded => 1,
		num_selected => 0 };
	for my $fn (keys %$changes)
	{
		my $type = $changes->{$fn};
		$items->{$fn} = item($tree,$fn,$type);
	}
	return $tree;
}


sub startUpdate
	# called before a bunch or addRepos
	# to effect updating without losing selected, expanded, etc
{
	my ($this) = @_;
	my $trees = $this->{trees};
	my $num_trees = scalar(keys %$trees);
	display($dbg_ctrl,0,"startUpdate($this->{name}) trees($num_trees)");
	for my $id (keys %$trees)
	{
		my $tree = $trees->{$id};
		$tree->{exists} = 0;		# does it still exist
		$tree->{changed} = 0;

		my $items = $tree->{items};
		for my $fn (keys %$items)
		{
			my $item = $items->{$fn};
			$item->{exists} = 0;		# does it still exist
		}
	}
}


sub updateRepo
{
	my ($this,$repo,$changes) = @_;
	my $num_changes = scalar(keys %$changes);
	display($dbg_ctrl,0,"updateRepo($this->{name},$repo->{id}) num_changes($num_changes) path=$num_changes");

	my $id = $repo->{id};
	my $trees = $this->{trees};
	my $tree = $trees->{$id};
	if (!$tree)
	{
		$trees->{$id} = tree($repo,$changes);
		if ($this->{data}->{contracted}->{$id})
		{
			display($dbg_ctrl,1,"contracting $id");
			$trees->{$id}->{expanded} = 0;
			delete $this->{data}->{contracted}->{$id};
		}
	}
	else
	{
		$tree->{exists} = 1;
		my $items = $tree->{items};
		for my $fn (keys %$changes)
		{
			my $type = $changes->{$fn};
			my $item = $items->{$fn};
			if (!$item)
			{
				$items->{$fn} = item($tree,$fn,$type);
			}
			else
			{
				$item->{exists} = 1;
				$item->{type} = $type;
			}
		}
	}
}


sub endUpdate
{
	my ($this) = @_;
	my $vheight = 0;
	my @delete_trees;
	my $trees = $this->{trees};
	my $num_trees = scalar(keys %$trees);
	display($dbg_ctrl,0,"endUpdate($this->{name}) trees($num_trees)");
	for my $id (sort keys %$trees)
	{
		my $tree = $trees->{$id};
		if ($tree->{exists})
		{
			$vheight += $ROW_HEIGHT;

			my @delete_items;
			my $items = $tree->{items};
			for my $fn (sort keys %$items)
			{
				my $item = $items->{$fn};
				if ($item->{exists})
				{
					if ($tree->{expanded})
					{
						$vheight += $ROW_HEIGHT;
					}
				}
				else
				{
					display($dbg_ctrl,1,"delete_item($fn) from $tree($id)");
					push @delete_items,$fn;
				}
			}
			for my $fn (@delete_items)
			{
				delete $items->{$fn};
			}
		}
		else
		{
			display($dbg_ctrl,0,"delete tree($id)");
			push @delete_trees,$id;
		}
	}
	for my $id (@delete_trees)
	{
		delete $trees->{$id};
	}

	my $sz = $this->GetSize();
    my $width = $sz->GetWidth();
    my $height = $sz->GetHeight();
	$this->SetVirtualSize([$width,$vheight]);
	$this->Refresh();

	$num_trees = scalar(keys %$trees);
	display($dbg_ctrl,0,"endUpdate($this->{name}) finished with num_trees($num_trees) vheight($vheight)");

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

	my $trees = $this->{trees};
	my $num_trees = scalar(keys %$trees);

	display($dbg_draw,0,"onPaint($width,$height) num_trees($num_trees)");
		# above in pixels

	my $dc = Wx::PaintDC->new($this);
	$this->DoPrepareDC($dc);

	# get update rectangle in unscrolled coords

	my $region = $this->GetUpdateRegion();
	my $box = $region->GetBox();
	my ($xstart,$ystart) = $this->CalcUnscrolledPosition($box->x,$box->y);
	my $update_rect = Wx::Rect->new($xstart,$ystart,$box->width,$box->height);
	my $bottom = $update_rect->GetBottom();
	display_rect($dbg_draw,1,"onPaint(bottom=$bottom) update_rect=",$update_rect);

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

	# Draw the Tree

	my $ypos = 0;
	my $item_rect = Wx::Rect->new(0,$ypos,$width,$ROW_HEIGHT);
	for my $id (sort keys %$trees)
	{
		my $tree = $trees->{$id};

		$item_rect->SetY($ypos);
		$this->drawTree($dc,$item_rect,$id,$tree) if $update_rect->Intersects($item_rect);

		$ypos += $ROW_HEIGHT;
		last if $ypos >= $bottom;

		if ($tree->{expanded})
		{
			my $items = $tree->{items};
			for my $fn (sort keys %$items)
			{
				$item_rect->SetY($ypos);

				$this->drawItem($dc,$item_rect,$fn,$items->{$fn})
					if $update_rect->Intersects($item_rect);

				$ypos += $ROW_HEIGHT;
				last if $ypos >= $bottom;
			}
		}
		last if $ypos >= $bottom;
	}

}	# onPaint()



my $TOGGLE_LEFT  = 4;			# icon location
my $TOGGLE_RIGHT = 11;			# mouse area
my $ICON_LEFT    = 12;			# icon location
my $ICON_RIGHT   = 27;			# mouse area - selected rectangle is two to left of TEXT left
my $TEXT_LEFT    = 30;


sub drawTree
{
	my ($this,$dc,$rect,$id,$tree) = @_;

	display($dbg_draw,0,"drawTree($rect,$id,$tree)");

	my $ypos = $rect->y;
	my $width = $rect->width;
	my $expanded = $tree->{expanded};
	my $num_items = scalar(keys %{$tree->{items}});
	my $num_selected = $tree->{num_selected};
	my $name = "$id (".($num_selected?"$num_selected/":'')."$num_items)";

	display($dbg_draw,0,"drawTree($ypos) exp($expanded) num($num_items) $id");

	$dc->SetFont($font_bold);
	$dc->SetTextForeground($color_blue);

	$dc->DrawText($expanded?"^":">",$TOGGLE_LEFT,$ypos);
	$dc->DrawText($name,$TEXT_LEFT,$ypos);
}


sub drawItem
{
	my ($this,$dc,$rect,$fn,$item) = @_;

	my $ypos = $rect->y();
	my $width = $rect->width();
	my $type = $item->{type};
	my $tree = $item->{tree};
	my $id = $tree->{id};
	my $tree_sel = $this->{selection}->{$id};
	my $selected = $tree_sel ? $tree_sel->{$fn} : 0;
	$selected ||= 0;

	display($dbg_draw,0,"drawItem($ypos) sel($selected) $type $fn");

	my $staged = $this->{name} eq 'staged';
	my $bm_color =
		$type eq 'M' ? $staged ? $color_green : $color_blue :
		$type eq 'D' ? $color_red :
		$color_black;
	my $bm =
		$type eq 'M' ? $staged ? $bm_folder_check : $bm_folder_lines :
		$type eq 'D' ? $staged ? $bm_folder_x : $bm_folder_question :
		$bm_folder;

	# bitmaps are drawn using the text foreground color

	# display(0,0,"Drawing bitmap");
	# display(0,0,"width=".$bm->GetWidth()." height=".$bm->GetHeight());
	# display(0,0,"ok=".$bm->IsOk());
	# display(0,0,"calling DrawBitmap");

	$dc->SetTextForeground($bm_color);
	$dc->DrawBitmap($bm, $ICON_LEFT, $ypos, 0);

	# display(0,0,"back from DrawBitmap");

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
#    We either refresh a single item, and the tree if it is visible
#    during a single item toggle, or we refresh the whole window.
#    during any complicated actions.


sub onLeftDown
{
	my ($this,$event) = @_;

	return if !(keys %{$this->{trees}});
		# nothing in the window

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

	display($dbg_sel,0,"onLeftDown($ux,$uy) ctrl($ctrl_key) shift($shift_key)");

	# find the tree and/or item for unscrolled position $x,$y

	my $ypos = 0;
	$this->{found_tree} = '';
	$this->{found_item} = '';
	$this->{tree_uy} = 0;
	$this->{item_uy} = 0;

	my $trees = $this->{trees};

	for my $id (sort keys %$trees)
	{
		my $tree = $trees->{$id};
		my $items = $tree->{items};
		my $tree_height = $tree->{expanded} ?
			(scalar(keys %$items) + 1) * $ROW_HEIGHT : $ROW_HEIGHT;

		if ($uy >= $ypos && $uy <= $ypos + $tree_height-1)
		{
			$this->{found_tree} = $tree;
			$this->{tree_uy} = $ypos;
			display($dbg_sel,1,"foundTree($id) at ypos($ypos) with height($tree_height)");
			if ($uy >= $ypos + $ROW_HEIGHT)
			{
				my $items = $tree->{items};
				my $off = $uy - $ypos - $ROW_HEIGHT;		# mouse y offset within tree's items
				my $idx = int($off / $ROW_HEIGHT);			# index into tree's items
				my $found_fn = (sort keys %$items)[$idx];	# found filename
				$this->{found_item} = $items->{$found_fn};	# found item

				$this->{item_uy} = $ypos + $ROW_HEIGHT + $idx * $ROW_HEIGHT;
					# save off the item position for optimized refresh
					# it is $idx+1 cuz the 0th item is below the tree header

				display($dbg_sel,1,"foundItem($found_fn,$this->{found_item}->{type}) at off($off) idx($idx) item_uy($this->{item_uy})");
				last;
			}
			last;
		}
		else
		{
			$ypos += $tree_height;
		}
	}

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
	#   from the anchor to the selected tree/item (or the last visible
	#   tree/item if in the white space).

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
		# ctrl key currently does nothing if clicked on a repo tree
	}
	elsif ($this->{found_item})
	{
		if ($ux <= $ICON_RIGHT)
		{
			if ($ux >= $ICON_LEFT)
			{
				display($dbg_actions,0,"ACTION_ON_ALL_SELECTED");
			}
		}
		else
		{
			if (!$shift_key && !$ctrl_key)
			{

				$this->{refresh_rect} = $this->{win_srect} 	# refresh whole window
					if $this->deleteSectionsExcept();       # if this wasn't already the only selection
			}

			$this->toggleSelection();
		}
	}
	elsif ($this->{found_tree})
	{
		if ($ux <= $TOGGLE_RIGHT)
		{
			$this->{found_tree}->{expanded} = !$this->{found_tree}->{expanded};
			$this->{refresh_rect} = $this->{win_srect}; 	# refresh whole window
		}
		elsif ($ux <= $ICON_RIGHT)
		{
			if ($ux >= $ICON_LEFT)
			{
				display($dbg_actions,0,"ACTION_ON_SELECTED_WITHIN($this->{found_tree}->{id})");
			}
		}
	}

	# DONE - REFRESH AS NEEDED AND RETURN

	if ($this->{refresh_rect}->x >= 0)
	{
		display_rect($dbg_sel,0,"REFRESH_RECT",$this->{refresh_rect});
		$this->RefreshRect($this->{refresh_rect})
	}

	$event->Skip();
}


sub addShiftSelection
{
	my ($this) = @_;

	my $found_tree  = $this->{found_tree};
	my $found_item  = $this->{found_item};
	my $anchor_item = $this->{anchor};
	my $anchor_fn   = $anchor_item->{fn};
	my $anchor_tree = $anchor_item->{tree};
	my $anchor_id   = $anchor_tree->{id};

	display($dbg_sel,0,"addShiftSelection anchor($anchor_id,$anchor_fn) found(".
		($found_tree?$found_tree->{id}:'').",".
		($found_item?$found_item->{fn}:'').")");

	my $first_tree = $anchor_tree;
	my $first_item = $anchor_item;
	my $last_tree;
	my $last_item;

	# set the first and last items if a tree or item was found

	my $stop_on_last = 0;

	if ($found_tree)
	{
		# we determine the direction based on comparing the ids
		# if going up and no item, then the whole repo was selected
		# but its the opossite going down.

		my $found_id = $found_tree->{id};

		if ($found_id lt $anchor_id)
		{
			# going up, will include all items in the found tree
			# if no item was specified.
			display($dbg_sel,2,"found_id($found_id) lt anchor_id($anchor_id)");
			$first_tree = $found_tree;
			$found_item = $found_item;
			$last_tree = $anchor_tree;
			$last_item = $anchor_item;
		}
		elsif ($found_id gt $anchor_id)
		{
			# going down will STOP on the last tree if no item
			display($dbg_sel,2,"found_id($found_id) gt anchor_id($anchor_id)");
			$last_tree = $found_tree;
			$last_item = $found_item;
			$stop_on_last = 1 if !$found_item;
		}

		# within the same tree

		elsif ($found_item)
		{
			my $found_fn = $found_item->{fn};
			if ($found_fn lt $anchor_fn)
			{
				display($dbg_sel,2,"found_fn($found_fn) lt anchor_fn($anchor_fn)");
				$first_tree = $found_tree;
				$first_item = $found_item;
				$last_tree = $anchor_tree;
				$last_item = $anchor_item;
			}
			elsif ($found_fn gt $anchor_fn)
			{
				display($dbg_sel,2,"found_fn($found_fn) gt anchor_fn($anchor_fn)");
				$last_tree = $found_tree;
				$last_item = $found_item;
			}
			else
			{
				display($dbg_sel,2,"same SHIFT_ITEM($anchor_id,$anchor_fn) RETURNING with no change!");
				return 0;
			}
		}
	}

	# else its (!$found_tree && !$found_item) so
	# we elect all items from anchor to end
	# by using initial assignments and null ends
	# since they clicked PAST the last repo

	# LOOP THROUGH ALL TREES

	my $any_changes = 0;
	my $trees = $this->{trees};

	my $first_id = $first_tree->{id};
	my $first_fn = $first_item ? $first_item->{fn} : '';
	my $last_id = $last_tree ? $last_tree->{id} : '';
	my $last_fn = $last_item ? $last_item->{fn} : '';

	display($dbg_sel,1,"first($first_id,$first_fn) last($last_id,$last_fn)");

	my @ids = sort keys %$trees;
	my $id = shift @ids;
	my $tree = $trees->{$id};
	my $items = $tree->{items};
	my $last = !@ids || $id eq $last_id ? 1 : 0;

	while (1)
	{
		if ($id ge $first_id)
		{
			my $first = $id eq $first_id ? 1 : 0;
			my $between = $id gt $first_id ? 1 : 0;

			display($dbg_sel,1,"REPO($id) first($first) between($between) last($last) stop_on_last($stop_on_last)");
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

				$any_changes += $this->addShiftSel($tree,$fn)
					if $addit;
			}
			last if $last;
		}

		# next tree

		$id = shift @ids;
		$tree = $trees->{$id};
		$items = $tree->{items};
		$last = !@ids || $id eq $last_id ? 1 : 0;
	}

	display($dbg_sel,0,"addShiftSelection() returning $any_changes");
	return $any_changes;
}


sub addShiftSel
{
	my ($this,$tree,$fn) = @_;
	my $selection = $this->{selection};
	my $id = $tree->{id};
	display($dbg_sel+1,0,"addShiftSel($id,$fn)");

	my $tree_sel = $selection->{$id};
	if (!$tree_sel)
	{
		display($dbg_sel+1,1,"creating new tree_sel");
		$selection->{$id} = { $fn => 1 };
		$tree->{num_selected}++;	# = 1
		return 1;
	}
	elsif (!$tree_sel->{$fn})
	{
		display($dbg_sel+1,1,"adding to existing tree_sel");
		$tree_sel->{$fn} = 1;
		$tree->{num_selected}++;	# = 1
		return 1;
	}
	else
	{
		display($dbg_sel+1,1,"already selected");
	}
	return 0;
}



sub deleteSectionsExcept
{
	my ($this) = @_;
	my $selection = $this->{selection};
	my $num_sels = scalar(keys %$selection);

	my $item = $this->{found_item};
	my $tree = $item->{tree};
	my $fn = $item->{fn};
	my $id = $tree->{id};

	my $tree_sel = $this->{selection}->{$id};
	my $num_tree_sels = $tree_sel ? scalar(keys %$tree_sel) : 0;
	my $cur_sel = $tree_sel ? $tree_sel->{$fn} : 0;
	$cur_sel ||= 0;

	display($dbg_sel,0,"deleteSectionsExcept($id,$fn) num_sels() num_tree_sels($num_tree_sels) cur_sel($cur_sel)");

	return 0 if !$num_sels;
	return 0 if $cur_sel && $num_sels == 1 && $num_tree_sels == 1;

	$this->{selection} = {};

	my $trees = $this->{trees};
	for my $clear_id (keys %$trees)
	{
		$trees->{$clear_id}->{num_selected} = 0;
	}

	if ($cur_sel)
	{
		$tree_sel = $this->{selection}->{$id} = {};
		$tree_sel->{$fn} = 1;
		$tree->{num_selected} = 1;
	}
	return 1;
}


sub toggleSelection
{
	my ($this) = @_;

	my $item = $this->{found_item};
	my $fn = $item->{fn};

	my $tree = $item->{tree};
	my $id = $tree->{id};
	my $selection = $this->{selection};
	my $tree_sel = $selection->{$id};
	my $selected = $tree_sel ? $tree_sel->{$fn} : 0;
	$selected |= 0;

	display($dbg_sel,0,"toggleSelection($id,$fn) selected=$selected");

	if ($selected)	# unselecting
	{
		$tree->{num_selected}--;
		if (!$tree->{num_selected})
		{
			delete $selection->{$id};
		}
		else
		{
			delete $tree_sel->{$fn};
		}
		$this->{anchor} = '';
	}
	elsif (!$tree_sel)
	{
		$tree_sel = { $fn => 1 };
		$selection->{$id} = $tree_sel;
		$tree->{num_selected}++;
		$this->{anchor} = $item;
	}
	else
	{
		$tree_sel->{$fn} = 1;
		$tree->{num_selected}++;
		$this->{anchor} = $item;
	}

	# optimized refresh if whole screen not already done

	my $refresh_rect = $this->{refresh_rect};		# scrolled position (0..$height-1)
	if ($refresh_rect->x < 0)
	{
		my $width = $this->{win_srect}->width;
		my ($unused1,$tree_sy) = $this->CalcScrolledPosition(0,$this->{tree_uy});
		my ($unused2,$item_sy) = $this->CalcScrolledPosition(0,$this->{item_uy});
		my $tree_srect = Wx::Rect->new(0,$tree_sy,$width,$ROW_HEIGHT);
		my $item_srect = Wx::Rect->new(0,$item_sy,$width,$ROW_HEIGHT);

		display_rect($dbg_sel,0,"refresh_rect",$item_srect);

		$this->{refresh_rect} = $item_srect;		# refresh the item
		$this->RefreshRect($tree_srect)				# and the tree if it is visible
			if $this->{win_srect}->Intersects($tree_srect);
	}
}



1;