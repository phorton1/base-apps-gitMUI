#!/usr/bin/perl
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
#  long clicking on entry will
#    repo: show repo detils
#    file: call the shell except for certain overidden types
#		.pm, .md -> komodo
# some other ideas
#
# 		use shorter {id} for repos
#       show number of items for repos


package apps::gitUI::listCtrl;
use strict;
use warnings;
use threads;
use threads::shared;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_PAINT
	EVT_LEFT_DOWN
	EVT_LEFT_UP);
use apps::gitUI::styles;
use Pub::Utils;
use base qw(Wx::ScrolledWindow);	# qw(Wx::Window);


my $dbg_ctrl = 0;
my $dbg_draw = 0;
my $dbg_sel = 0;


my $ROW_HEIGHT  = 20;


BEGIN {
    use Exporter qw( import );
	our @EXPORT = qw (
	);
}




my $selected_brush = Wx::Brush->new($color_dark_cyan,wxBRUSHSTYLE_SOLID);


sub new
{
    my ($class,$parent,$name,$PAGE_TOP) = @_;
	display($dbg_ctrl,0,"new listCtrl($name,$PAGE_TOP)");
    my $this = $class->SUPER::new($parent,-1,[0,$PAGE_TOP]);	# [$w,$h]); # ,wxVSCROLL | wxHSCROLL);
	bless $this,$class;

    $this->{parent} = $parent;
	$this->{name} = $name;
	$this->{trees} = {};

	$this->SetVirtualSize([0,0]);
	$this->SetBackgroundColour($color_white);
	$this->SetScrollRate(0,$ROW_HEIGHT);

	EVT_PAINT($this, \&onPaint);
	EVT_LEFT_DOWN($this,\&onLeftClick);
    EVT_LEFT_UP($this,\&onLeftUp);

	return $this;
}


#-----------------------------------------------
# building
#-----------------------------------------------

sub item
{
	my ($type) = @_;
	my $item = {
		type => $type,
		exists => 1,
		selected => 0, };
	return $item;
}


sub tree
{
	my ($repo,$changes) = @_;

	my $items = {};

	my $tree = {
		repo => $repo,
		items => $items,
		exists => 1,
		expanded => 1, };
	for my $fn (keys %$changes)
	{
		my $type = $changes->{$fn};
		$items->{$fn} = item($type);
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
				$items->{$fn} = item($type);
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

	$dc->SetPen(wxTRANSPARENT_PEN);
	$dc->SetBrush(wxWHITE_BRUSH);
	$dc->DrawRectangle($update_rect->x,$update_rect->y,$update_rect->width,$update_rect->height);

	# Draw the Tree

	my $ypos = 0;
	my $item_rect = Wx::Rect->new(0,$ypos,$width,$ROW_HEIGHT);
	for my $id (sort keys %$trees)
	{
		my $tree = $trees->{$id};
		display(0,0,"trees($id)=$tree");

		$item_rect->SetY($ypos);
		drawTree($dc,$item_rect,$id,$tree) if $update_rect->Intersects($item_rect);

		$ypos += $ROW_HEIGHT;
		last if $ypos >= $bottom;

		if ($tree->{expanded})
		{
			my $items = $tree->{items};
			for my $fn (sort keys %$items)
			{
				$item_rect->SetY($ypos);

				drawItem($dc,$item_rect,$fn,$items->{$fn})
					if $update_rect->Intersects($item_rect);

				$ypos += $ROW_HEIGHT;
				last if $ypos >= $bottom;
			}
		}
		last if $ypos >= $bottom;
	}

}	# onPaint()



my $TOGGLE_LEFT = 5;
my $TOGGLE_RIGHT = 14;
my $TEXT_LEFT   = 15;

sub drawTree
{
	my ($dc,$rect,$id,$tree) = @_;

	display($dbg_draw,0,"drawTree($rect,$id,$tree)");

	my $ypos = $rect->y;
	my $width = $rect->width;
	my $expanded = $tree->{expanded};
	my $num_items = scalar(keys %{$tree->{items}});

	display($dbg_draw,0,"drawTree($ypos) exp($expanded) num($num_items) $id");

	$dc->SetFont($font_bold);
	$dc->SetTextForeground($color_blue);

	$dc->DrawText($expanded?"^":">",$TOGGLE_LEFT,$ypos);
	$dc->DrawText("$id ($num_items)",$TEXT_LEFT,$ypos);
}




sub drawItem
{
	my ($dc,$rect,$fn,$item) = @_;

	my $ypos = $rect->y();
	my $width = $rect->width();
	my $type = $item->{type};

	display($dbg_draw,0,"drawItem($ypos) sel($item->{selected}) $type $fn");

	my $fg_color =
		$item->{selected} ? $color_white :
		$type eq 'repo' ? $color_blue :
		$type eq 'A'    ? $color_green :
		$type eq 'D'	? $color_red :
		$type eq 'R'	? $color_purple :
		$color_black;
	my $font = $type eq 'repo' ? $font_bold : $font_normal;

	$dc->SetBrush($item->{selected} ? $selected_brush : wxWHITE_BRUSH);
	$dc->DrawRectangle($TEXT_LEFT,$ypos,$width-$TEXT_LEFT,$ROW_HEIGHT);

	$dc->SetFont($font);
	$dc->SetTextForeground($fg_color);
	$dc->DrawText($fn,$TEXT_LEFT,$ypos);
}



#-----------------------------------------------
# Mouse Handling
#-----------------------------------------------

sub mouseCommon
{
	my ($this,$event,$down) = @_;
	my $cp = $event->GetPosition();
	my ($x,$y) = $this->CalcUnscrolledPosition($cp->x,$cp->y);
	display($dbg_sel,0,"mouseCommon($down) xy($x,$y)");

	# find the tree and/or item for unscrolled position $x,$y

	my $ypos = 0;
	my $found_tree = '';
	my $toggle_tree = '';
	my $found_item = '';
	my $item_ypos = 0;
	my $trees = $this->{trees};

	for my $id (sort keys %$trees)
	{
		my $tree = $trees->{$id};
		my $items = $tree->{items};
		my $tree_height = $tree->{expanded} ?
			(scalar(keys %$items) + 1) * $ROW_HEIGHT : $ROW_HEIGHT;

		if ($y >= $ypos && $y <= $ypos + $tree_height-1)
		{
			$found_tree = $tree;
			display($dbg_sel,1,"foundTree($id) at ypos($ypos) with height($tree_height)");
			if ($y < $ypos + $ROW_HEIGHT)
			{
				$toggle_tree = $tree
					if $x >= $TOGGLE_LEFT && $x <= $TOGGLE_RIGHT;
			}
			else	# assert(expanded)
			{
				my $items = $tree->{items};
				my $off = $y - $ypos - $ROW_HEIGHT;
				my $idx = int($off / $ROW_HEIGHT);
				$item_ypos = $ypos + ($idx + 1) * $ROW_HEIGHT;
					# save off the item position for optimized refresh
					# it is $idx+1 cuz the 0th item is below the tree header
				my $fn = (sort keys %$items)[$idx];
				$found_item = $items->{$fn};
				display($dbg_sel,1,"foundItem($fn,$found_item->{type}) at off($off) idx($idx)");
				last;
			}
			last;
		}
		else
		{
			$ypos += $tree_height;
		}
	}


	if ($down)
	{
		$this->{found_tree} = $found_tree;
		$this->{found_item} = $found_item;
		$this->{toggle_tree} = $toggle_tree;
	}
	elsif ($toggle_tree && $toggle_tree eq $this->{toggle_tree})
	{
		$toggle_tree->{expanded} = !$toggle_tree->{expanded};
		$this->Refresh();
	}
	elsif ($found_item && $found_item eq $this->{found_item})
	{
		$found_item->{selected} = !$found_item->{selected};

		my $sz = $this->GetSize();
		my $width = $sz->GetWidth();
		my ($unused_atx,$aty) = $this->CalcScrolledPosition(0,$item_ypos);
			# turn the unscrolled $item_pos into it's scrolled position
			# to build rectangle to call refreshRect
		my $rect = Wx::Rect->new(0,$aty,$width,$ROW_HEIGHT);
		$this->RefreshRect($rect);
	}
}


sub onLeftClick
{
	my ($this,$event) = @_;
	$this->mouseCommon($event,1);
	$event->Skip();
}

sub onLeftUp
{
	my ($this,$event) = @_;
	$this->mouseCommon($event,0);
	$event->Skip();
}




1;