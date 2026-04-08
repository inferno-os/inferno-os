implement Ftree;

#
# wm/ftree - Draw-based file tree viewer
#
# Browse the Inferno namespace as an expandable tree.
# Uses the native widget toolkit — no Tk.
#
# Usage:
#   wm/ftree [root]
#
# Keyboard:
#   Up/Down      move selection
#   Left         collapse directory / move to parent
#   Right/Enter  expand directory / plumb file
#   Page Up/Down scroll one screenful
#   Home/End     go to top/bottom
#   Ctrl-G       goto path prompt
#   Ctrl-Q       quit
#
# Mouse:
#   Button 1     select item; double-click to expand/plumb
#   Button 3     context menu
#   Scroll wheel scroll up/down
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Font, Image, Point, Rect: import draw;

include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;

include "menu.m";
	menumod: Menu;
	Popup: import menumod;

include "readdir.m";
	readdir: Readdir;

include "string.m";
	str: String;

include "lucitheme.m";

include "widget.m";
	widgetmod: Widget;
	Scrollbar, Statusbar, Kbdfilter: import widgetmod;

include "arg.m";
	arg: Arg;

include "plumbmsg.m";
	plumbmod: Plumbmsg;

Ftree: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

# Veltro IPC directory
FTREE_DIR: con "/tmp/veltro/ftree";

# Fallback colours (overridden by theme)
BG:	con int 16rFFFDF6FF;
FG:	con int 16r333333FF;
DIRCOL:	con int 16r1A1A1AFF;	# directory name colour (bold)
SELCOL:	con int 16rB4D5FEFF;	# selection highlight
DIMCOL:	con int 16r999999FF;	# metadata colour

# Dimensions
MARGIN:		con 6;
INDENT:		con 16;		# pixels per indent level
ICON_W:		con 14;		# expand/collapse indicator width

# Key constants
Khome:		con 16rFF61;
Kend:		con 16rFF57;
Kup:		con 16rFF52;
Kdown:		con 16rFF54;
Kleft:		con 16rFF51;
Kright:		con 16rFF53;
Kpgup:		con 16rFF55;
Kpgdown:	con 16rFF56;
Kdel:		con 16rFF9F;
Kins:		con 16rFF63;
Kbs:		con 8;
Kesc:		con 27;

# ---------- Tree node ----------

Node: adt {
	path:		string;		# full path
	name:		string;		# display name
	depth:		int;		# indent level (0 = root)
	isdir:		int;		# 1 = directory
	expanded:	int;		# 1 = children visible
	mode:		int;		# file mode bits
	length:		big;		# file size
	loaded:		int;		# 1 = children have been read
	nchildren:	int;		# number of direct children
	parent:		int;		# index of parent in nodes[], or -1
};

# ---------- Global state ----------

nodes:		array of ref Node;	# all nodes (tree structure flattened)
nnodes:		int;			# number of nodes
visible:	array of int;		# indices into nodes[] of visible rows
nvisible:	int;			# number of visible rows

topline:	int;			# first visible row (scroll offset)
vislines:	int;			# rows that fit on screen
selected:	int;			# index into visible[] (-1 = none)

# Display resources
display:	ref Display;
font:		ref Font;
bfont:		ref Font;
bgcolor:	ref Image;
fgcolor:	ref Image;
dircol:		ref Image;
selcolor:	ref Image;
dimcolor:	ref Image;

scrollbar:	ref Scrollbar;
statbar:	ref Statusbar;
kbdfilter:	ref Kbdfilter;

w:		ref Window;
stderr:		ref Sys->FD;

rootpath:	string;

# Prompt mode: 0=none, 1=goto
promptmode := 0;

# ---------- Initialisation ----------

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;
	menumod = load Menu Menu->PATH;
	readdir = load Readdir Readdir->PATH;
	str = load String String->PATH;
	stderr = sys->fildes(2);

	if(wmclient == nil) {
		sys->fprint(stderr, "wm/ftree: cannot load Wmclient: %r\n");
		raise "fail:init";
	}
	if(readdir == nil) {
		sys->fprint(stderr, "wm/ftree: cannot load Readdir: %r\n");
		raise "fail:init";
	}

	widgetmod = load Widget Widget->PATH;
	if(widgetmod == nil) {
		sys->fprint(stderr, "wm/ftree: cannot load Widget: %r\n");
		raise "fail:init";
	}
	kbdfilter = Kbdfilter.new();

	if(ctxt == nil) {
		sys->fprint(stderr, "wm/ftree: no window context\n");
		raise "fail:no context";
	}

	sys->pctl(Sys->NEWPGRP, nil);
	wmclient->init();

	# Parse arguments
	rootpath = "/";
	arg = load Arg Arg->PATH;
	if(arg != nil) {
		arg->init(argv);
		while(arg->opt())
			;
		argv = arg->argv();
	} else
		argv = tl argv;
	if(argv != nil)
		rootpath = hd argv;

	# Create window
	w = wmclient->window(ctxt, "ftree", Wmclient->Appl);
	display = w.display;

	# Load fonts
	font = Font.open(display, "/fonts/combined/unicode.sans.14.font");
	if(font == nil)
		font = Font.open(display, "*default*");
	bfont = Font.open(display, "/fonts/combined/unicode.sans.bold.14.font");
	if(bfont == nil)
		bfont = font;

	# Load theme colours
	loadcolors();
	widgetmod->init(display, font);
	scrollbar = Scrollbar.new(Rect((0,0),(0,0)), 1);
	statbar = Statusbar.new(Rect((0,0),(0,0)));

	# Initialise tree
	nodes = array[4096] of ref Node;
	nnodes = 0;
	visible = array[4096] of int;
	nvisible = 0;
	topline = 0;
	selected = 0;

	addnode(rootpath, basename(rootpath), 0, 1, -1);
	if(nnodes > 0) {
		nodes[0].expanded = 1;
		loadchildren(0);
		rebuildvisible();
	}

	w.reshape(Rect((0, 0), (400, 520)));
	w.startinput("kbd" :: "ptr" :: nil);
	w.onscreen(nil);

	if(menumod != nil)
		menumod->init(display, bfont);
	menu := menumod->new(array[] of {"open", "expand all", "collapse all", "refresh", "goto", "exit"});

	# Veltro IPC
	initftreedir();
	writeftreestate();
	ticks := chan of int;
	spawn timer(ticks, 500);

	# Theme listener
	themech := chan[1] of int;
	spawn themelistener(themech);

	redraw();

	for(;;) alt {
	<-themech =>
		reloadcolors();
		redraw();
	<-ticks =>
		if(checkctlfile())
			redraw();
	ctl := <-w.ctl or
	ctl = <-w.ctxt.ctl =>
		w.wmctl(ctl);
		if(ctl != nil && ctl[0] == '!')
			redraw();

	rawkey := <-w.ctxt.kbd =>
		key := kbdfilter.filter(rawkey);
		if(key >= 0) {
			if(statbar.prompt != nil) {
				(done, val) := statbar.key(key);
				if(done == 1) {
					statbar.prompt = nil;
					if(promptmode == 1)
						gotopath(val);
					promptmode = 0;
				} else if(done < 0) {
					statbar.prompt = nil;
					promptmode = 0;
				}
				redraw();
			} else
				handlekey(key);
		}

	p := <-w.ctxt.ptr =>
		if(p.buttons == 0 && scrollbar.isactive()) {
			newo := scrollbar.track(p);
			if(newo >= 0) {
				topline = newo;
				redraw();
			}
		} else if(scrollbar.isactive()) {
			newo := scrollbar.track(p);
			if(newo >= 0) {
				topline = newo;
				redraw();
			}
		} else if(p.buttons & 16r18) {
			# Scroll wheel
			scrollbar.total = nvisible;
			scrollbar.visible = vislines;
			scrollbar.origin = topline;
			topline = scrollbar.wheel(p.buttons, 3);
			redraw();
		} else if(p.buttons & 4) {
			# Button 3 — context menu
			if(menu != nil) {
				n := menu.show(w.image, p.xy, w.ctxt.ptr);
				case n {
				0 =>	plumbselected();
				1 =>	expandall();
				2 =>	collapseall();
				3 =>	refreshtree();
				4 =>	startgoto();
				5 =>	exit;
				}
			}
		} else if(p.buttons & 1) {
			sr := scrollrect();
			if(sr.contains(p.xy)) {
				scrollbar.total = nvisible;
				scrollbar.visible = vislines;
				scrollbar.origin = topline;
				newo := scrollbar.event(p);
				if(newo >= 0) {
					topline = newo;
					redraw();
				}
			} else {
				clicktree(p.xy);
			}
		} else
			w.pointer(*p);
	}
}

# ---------- Keyboard ----------

handlekey(key: int)
{
	case key {
	Kup =>
		if(selected > 0) selected--;
		scrolltoselected();
	Kdown =>
		if(selected < nvisible - 1) selected++;
		scrolltoselected();
	Kpgup =>
		selected -= vislines;
		if(selected < 0) selected = 0;
		scrolltoselected();
	Kpgdown =>
		selected += vislines;
		if(selected >= nvisible) selected = nvisible - 1;
		scrolltoselected();
	Khome =>
		selected = 0;
		topline = 0;
	Kend =>
		selected = nvisible - 1;
		scrolltoselected();
	Kright or '\n' =>
		activateselected();
	Kleft =>
		collapseselected();
	'q' & 16r1f =>	# Ctrl-Q
		exit;
	'g' & 16r1f =>	# Ctrl-G
		startgoto();
	'q' or 'Q' =>
		exit;
	'r' or 'R' =>
		refreshtree();
	* =>
		return;
	}
	redraw();
}

scrolltoselected()
{
	if(selected < 0)
		selected = 0;
	if(selected >= nvisible)
		selected = nvisible - 1;
	if(selected < topline)
		topline = selected;
	else if(selected >= topline + vislines)
		topline = selected - vislines + 1;
	clamptop();
}

activateselected()
{
	if(selected < 0 || selected >= nvisible)
		return;
	ni := visible[selected];
	n := nodes[ni];
	if(n.isdir) {
		if(n.expanded)
			collapse(ni);
		else
			expand(ni);
		rebuildvisible();
	} else
		plumbfile(n.path);
}

collapseselected()
{
	if(selected < 0 || selected >= nvisible)
		return;
	ni := visible[selected];
	n := nodes[ni];
	if(n.isdir && n.expanded) {
		collapse(ni);
		rebuildvisible();
	} else if(n.parent >= 0) {
		# Move selection to parent
		pi := n.parent;
		for(i := 0; i < nvisible; i++) {
			if(visible[i] == pi) {
				selected = i;
				break;
			}
		}
		scrolltoselected();
	}
}

# ---------- Mouse ----------

clicktree(p: Point)
{
	tr := textrect();
	if(!tr.contains(p))
		return;
	fh := font.height;
	row := (p.y - tr.min.y) / fh;
	idx := topline + row;
	if(idx < 0 || idx >= nvisible)
		return;
	selected = idx;

	# Check if click is on the expand/collapse indicator
	ni := visible[idx];
	n := nodes[ni];
	ix := tr.min.x + n.depth * INDENT;
	if(n.isdir && p.x >= ix && p.x < ix + ICON_W) {
		if(n.expanded)
			collapse(ni);
		else
			expand(ni);
		rebuildvisible();
	}
	redraw();
}

plumbselected()
{
	if(selected < 0 || selected >= nvisible)
		return;
	ni := visible[selected];
	n := nodes[ni];
	if(n.isdir)
		activateselected();
	else
		plumbfile(n.path);
}

plumbfile(path: string)
{
	if(plumbmod == nil) {
		plumbmod = load Plumbmsg Plumbmsg->PATH;
		if(plumbmod != nil)
			plumbmod->init(0, nil, 0);
	}
	if(plumbmod == nil) {
		statbar.right = "no plumber";
		redraw();
		return;
	}
	msg := ref Plumbmsg->Msg(
		"ftree",
		nil,
		"/",
		"text",
		nil,
		array of byte path
	);
	if(msg.send() < 0)
		statbar.right = "plumb failed";
	else
		statbar.right = "plumbed " + path;
	redraw();
}

# ---------- Tree operations ----------

addnode(path, name: string, depth, isdir, parent: int): int
{
	if(nnodes >= len nodes) {
		newnodes := array[len nodes * 2] of ref Node;
		newnodes[0:] = nodes;
		nodes = newnodes;
	}
	n := ref Node(path, name, depth, isdir, 0, 0, big 0, 0, 0, parent);
	idx := nnodes;
	nodes[idx] = n;
	nnodes++;
	return idx;
}

loadchildren(pi: int)
{
	p := nodes[pi];
	if(p.loaded)
		return;
	p.loaded = 1;

	(dirs, n) := readdir->init(p.path, Readdir->NAME);
	if(n <= 0)
		return;

	# Insert children right after parent.
	# First, count existing children to find insertion point.
	insert := pi + 1;
	# Skip past any existing subtree rooted at pi
	for(i := pi + 1; i < nnodes; i++) {
		if(nodes[i].depth <= p.depth)
			break;
		insert = i + 1;
	}

	# Make room
	count := n;
	if(nnodes + count > len nodes) {
		newnodes := array[(nnodes + count) * 2] of ref Node;
		newnodes[0:] = nodes[0:nnodes];
		nodes = newnodes;
	}
	# Shift nodes after insertion point
	if(insert < nnodes) {
		for(i := nnodes - 1; i >= insert; i--)
			nodes[i + count] = nodes[i];
		# Fix parent indices that shifted
		for(i := 0; i < nnodes + count; i++) {
			if(i >= insert && i < insert + count)
				continue;
			if(nodes[i] != nil && nodes[i].parent >= insert)
				nodes[i].parent += count;
		}
	}

	# Add directory entries first, then files (dirs sort to top)
	j := insert;
	# Directories first
	for(i := 0; i < n; i++) {
		d := dirs[i];
		if(d.mode & Sys->DMDIR) {
			childpath := p.path;
			if(childpath != "/" && len childpath > 0)
				childpath += "/";
			else if(childpath == "/")
				childpath = "/";
			childpath += d.name;
			nodes[j] = ref Node(childpath, d.name, p.depth + 1,
				1, 0, d.mode, big d.length, 0, 0, pi);
			j++;
		}
	}
	# Then files
	for(i := 0; i < n; i++) {
		d := dirs[i];
		if(!(d.mode & Sys->DMDIR)) {
			childpath := p.path;
			if(childpath != "/" && len childpath > 0)
				childpath += "/";
			else if(childpath == "/")
				childpath = "/";
			childpath += d.name;
			nodes[j] = ref Node(childpath, d.name, p.depth + 1,
				0, 0, d.mode, big d.length, 0, 0, pi);
			j++;
		}
	}
	nnodes += count;
	p.nchildren = count;
}

expand(ni: int)
{
	n := nodes[ni];
	if(!n.isdir)
		return;
	if(!n.loaded)
		loadchildren(ni);
	n.expanded = 1;
}

collapse(ni: int)
{
	n := nodes[ni];
	if(!n.isdir)
		return;
	# Recursively collapse children
	for(i := ni + 1; i < nnodes; i++) {
		if(nodes[i].depth <= n.depth)
			break;
		if(nodes[i].isdir)
			nodes[i].expanded = 0;
	}
	n.expanded = 0;
}

expandall()
{
	if(selected < 0 || selected >= nvisible)
		return;
	ni := visible[selected];
	expandsubtree(ni);
	rebuildvisible();
	redraw();
}

expandsubtree(ni: int)
{
	n := nodes[ni];
	if(!n.isdir)
		return;
	expand(ni);
	# Expand children recursively
	for(i := ni + 1; i < nnodes; i++) {
		if(nodes[i].depth <= n.depth)
			break;
		if(nodes[i].isdir)
			expand(i);
	}
}

collapseall()
{
	# Collapse everything except root
	for(i := 0; i < nnodes; i++) {
		if(nodes[i].isdir && i > 0)
			nodes[i].expanded = 0;
	}
	selected = 0;
	topline = 0;
	rebuildvisible();
	redraw();
}

refreshtree()
{
	# Remember selected path
	selpath := "";
	if(selected >= 0 && selected < nvisible)
		selpath = nodes[visible[selected]].path;

	# Rebuild from root
	nnodes = 0;
	addnode(rootpath, basename(rootpath), 0, 1, -1);
	if(nnodes > 0) {
		nodes[0].expanded = 1;
		nodes[0].loaded = 0;
		loadchildren(0);
		# Re-expand paths that were expanded before
		# (simplified: just expand first level)
		rebuildvisible();
	}

	# Try to restore selection
	selected = 0;
	for(i := 0; i < nvisible; i++) {
		if(nodes[visible[i]].path == selpath) {
			selected = i;
			break;
		}
	}
	scrolltoselected();
	redraw();
}

rebuildvisible()
{
	if(nvisible > len visible)
		visible = array[nnodes * 2] of int;
	nvisible = 0;
	for(i := 0; i < nnodes; i++) {
		# A node is visible if all its ancestors are expanded
		vis := 1;
		pi := nodes[i].parent;
		while(pi >= 0) {
			if(!nodes[pi].expanded) {
				vis = 0;
				break;
			}
			pi = nodes[pi].parent;
		}
		if(vis) {
			if(nvisible >= len visible) {
				newvis := array[len visible * 2] of int;
				newvis[0:] = visible[0:nvisible];
				visible = newvis;
			}
			visible[nvisible] = i;
			nvisible++;
		}
	}
	if(selected >= nvisible)
		selected = nvisible - 1;
	if(selected < 0 && nvisible > 0)
		selected = 0;
}

# ---------- Rendering ----------

textrect(): Rect
{
	r := w.image.r;
	sth := widgetmod->statusheight();
	sw := widgetmod->scrollwidth();
	return Rect((r.min.x + sw + MARGIN, r.min.y + MARGIN),
		    (r.max.x - MARGIN, r.max.y - sth));
}

scrollrect(): Rect
{
	r := w.image.r;
	sth := widgetmod->statusheight();
	return Rect((r.min.x, r.min.y), (r.min.x + widgetmod->scrollwidth(), r.max.y - sth));
}

redraw()
{
	screen := w.image;
	if(screen == nil)
		return;

	r := screen.r;
	ZP := Point(0, 0);

	# Clear background
	screen.draw(r, bgcolor, nil, ZP);

	# Calculate text area
	tr := textrect();
	fh := font.height;
	maxvrows := tr.dy() / fh;
	if(maxvrows < 1)
		maxvrows = 1;
	vislines = maxvrows;

	# Draw tree rows
	y := tr.min.y;
	for(i := topline; i < nvisible && (y + fh) <= tr.max.y; i++) {
		ni := visible[i];
		n := nodes[ni];

		# Selection highlight
		if(i == selected) {
			hr := Rect((tr.min.x - 2, y), (tr.max.x, y + fh));
			screen.draw(hr, selcolor, nil, ZP);
		}

		x := tr.min.x + n.depth * INDENT;

		# Expand/collapse indicator for directories
		if(n.isdir) {
			drawexpander(screen, Point(x, y), fh, n.expanded);
		}
		x += ICON_W;

		# Name
		f := font;
		col := fgcolor;
		if(n.isdir) {
			f = bfont;
			col = dircol;
		}

		# Truncate if needed
		name := n.name;
		if(n.isdir)
			name += "/";
		maxw := tr.max.x - x;
		if(maxw > 0) {
			tw := f.width(name);
			if(tw > maxw) {
				for(k := len name; k > 0; k--) {
					if(f.width(name[:k]) <= maxw - font.width("...")) {
						name = name[:k] + "...";
						break;
					}
				}
			}
			screen.text(Point(x, y), col, ZP, f, name);

			# File size for non-directories
			if(!n.isdir && n.length >= big 0) {
				sz := fmtsize(n.length);
				szw := font.width(sz);
				szx := tr.max.x - szw;
				namex := x + f.width(name) + 8;
				if(szx > namex)
					screen.text(Point(szx, y), dimcolor, ZP, font, sz);
			}
		}

		y += fh;
	}

	# Update and draw scrollbar
	sr := scrollrect();
	scrollbar.resize(sr);
	scrollbar.total = nvisible;
	scrollbar.visible = vislines;
	scrollbar.origin = topline;
	scrollbar.draw(screen);

	# Status bar
	sth := widgetmod->statusheight();
	statbar.resize(Rect((r.min.x, r.max.y - sth), (r.max.x, r.max.y)));
	if(selected >= 0 && selected < nvisible)
		statbar.left = nodes[visible[selected]].path;
	else
		statbar.left = rootpath;
	statbar.right = sys->sprint("%d items", nvisible);
	statbar.draw(screen);
	widgetmod->contentborder(screen);

	screen.flush(Draw->Flushnow);
}

drawexpander(screen: ref Image, p: Point, fh: int, expanded: int)
{
	# Draw a small triangle: right-pointing (collapsed) or down-pointing (expanded)
	ZP := Point(0, 0);
	cx := p.x + ICON_W / 2;
	cy := p.y + fh / 2;
	sz := 4;	# half-size of triangle

	if(expanded) {
		# Down-pointing triangle: three lines
		for(i := 0; i <= sz; i++) {
			x0 := cx - sz + i;
			x1 := cx + sz - i;
			screen.line(Point(x0, cy - sz/2 + i), Point(x1, cy - sz/2 + i),
				0, 0, 0, dimcolor, ZP);
		}
	} else {
		# Right-pointing triangle
		for(i := 0; i <= sz; i++) {
			y0 := cy - sz + i;
			y1 := cy + sz - i;
			screen.line(Point(cx - sz/2 + i, y0), Point(cx - sz/2 + i, y1),
				0, 0, 0, dimcolor, ZP);
		}
	}
}

fmtsize(n: big): string
{
	if(n < big 1024)
		return sys->sprint("%bd", n);
	if(n < big 1048576)
		return sys->sprint("%bdK", n / big 1024);
	if(n < big 1073741824)
		return sys->sprint("%bdM", n / big 1048576);
	return sys->sprint("%bdG", n / big 1073741824);
}

# ---------- Navigation ----------

startgoto()
{
	promptmode = 1;
	statbar.prompt = "Path: ";
	statbar.buf = "";
	redraw();
}

gotopath(path: string)
{
	if(path == nil || len path == 0)
		return;
	# Check if path is a directory
	(ok, d) := sys->stat(path);
	if(ok < 0) {
		statbar.right = path + ": not found";
		return;
	}
	if(!(d.mode & Sys->DMDIR)) {
		# It's a file — plumb it
		plumbfile(path);
		return;
	}
	# Change root to new path
	rootpath = path;
	nnodes = 0;
	addnode(rootpath, basename(rootpath), 0, 1, -1);
	if(nnodes > 0) {
		nodes[0].expanded = 1;
		loadchildren(0);
		rebuildvisible();
	}
	selected = 0;
	topline = 0;
	w.settitle("ftree \u2014 " + rootpath);
}

# ---------- Helpers ----------

clamptop()
{
	max := nvisible - vislines;
	if(max < 0)
		max = 0;
	if(topline > max)
		topline = max;
	if(topline < 0)
		topline = 0;
}

basename(path: string): string
{
	if(path == "/")
		return "/";
	for(i := len path - 1; i >= 0; i--) {
		if(path[i] == '/') {
			if(i < len path - 1)
				return path[i+1:];
		}
	}
	return path;
}

# ---------- Colour management ----------

loadcolors()
{
	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme != nil) {
		th := lucitheme->gettheme();
		bgcolor = display.color(th.editbg);
		fgcolor = display.color(th.edittext);
		dircol = display.color(th.text);
		selcolor = display.color(th.accent);
		dimcolor = display.color(th.dim);
	} else {
		bgcolor = display.color(BG);
		fgcolor = display.color(FG);
		dircol = display.color(DIRCOL);
		selcolor = display.color(SELCOL);
		dimcolor = display.color(DIMCOL);
	}
}

reloadcolors()
{
	loadcolors();
	widgetmod->retheme(display);
	wmclient->retheme(w);
	if(menumod != nil)
		menumod->init(display, bfont);
}

# ---------- Theme listener ----------

themelistener(ch: chan of int)
{
	fd := sys->open("/n/ui/event", Sys->OREAD);
	if(fd == nil)
		return;
	buf := array[256] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		ev := string buf[0:n];
		if(len ev >= 6 && ev[0:6] == "theme ")
			alt { ch <-= 1 => ; * => ; }
	}
}

# ---------- Timer ----------

timer(c: chan of int, ms: int)
{
	for(;;) {
		sys->sleep(ms);
		c <-= 1;
	}
}

# ---------- Veltro real-file IPC ----------

initftreedir()
{
	mkdirq("/tmp/veltro");
	mkdirq(FTREE_DIR);
}

mkdirq(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd != nil) {
		fd = nil;
		return;
	}
	fd = sys->create(path, Sys->OREAD, Sys->DMDIR | 8r755);
	fd = nil;
}

writeftreestate()
{
	state := sys->sprint("root %s\n", rootpath);
	if(selected >= 0 && selected < nvisible)
		state += sys->sprint("selected %s\n", nodes[visible[selected]].path);
	state += sys->sprint("items %d\n", nvisible);
	state += sys->sprint("topline %d\n", topline);
	state += sys->sprint("visible %d\n", vislines);

	# Plain text listing of visible items for AI context
	view := sys->sprint("File tree: %s\n", rootpath);
	view += sys->sprint("Items %d-%d of %d\n\n", topline + 1,
		min(topline + vislines, nvisible), nvisible);
	end := topline + vislines;
	if(end > nvisible)
		end = nvisible;
	for(i := topline; i < end; i++) {
		ni := visible[i];
		n := nodes[ni];
		indent := "";
		for(j := 0; j < n.depth; j++)
			indent += "  ";
		marker := "";
		if(n.isdir) {
			if(n.expanded)
				marker = "v ";
			else
				marker = "> ";
		} else
			marker = "  ";
		sel := "";
		if(i == selected)
			sel = "* ";
		view += sel + indent + marker + n.name;
		if(n.isdir)
			view += "/";
		view += "\n";
	}

	writestatefile(FTREE_DIR + "/state", state);
	writestatefile(FTREE_DIR + "/view", view);
}

writestatefile(path, data: string)
{
	fd := sys->create(path, Sys->OWRITE, 8r666);
	if(fd == nil)
		return;
	b := array of byte data;
	sys->write(fd, b, len b);
	fd = nil;
}

checkctlfile(): int
{
	cmd := readrmfile(FTREE_DIR + "/ctl");
	if(cmd == nil || cmd == "")
		return 0;

	(nil, toks) := sys->tokenize(cmd, " \t\n");
	if(toks == nil)
		return 0;

	verb := hd toks;
	toks = tl toks;

	case verb {
	"cd" or "goto" =>
		if(toks == nil)
			return 0;
		gotopath(hd toks);
		return 1;
	"select" =>
		if(toks == nil)
			return 0;
		path := hd toks;
		for(i := 0; i < nvisible; i++) {
			if(nodes[visible[i]].path == path) {
				selected = i;
				scrolltoselected();
				return 1;
			}
		}
	"expand" =>
		if(selected >= 0 && selected < nvisible) {
			ni := visible[selected];
			if(nodes[ni].isdir) {
				expand(ni);
				rebuildvisible();
				return 1;
			}
		}
	"collapse" =>
		if(selected >= 0 && selected < nvisible) {
			ni := visible[selected];
			if(nodes[ni].isdir) {
				collapse(ni);
				rebuildvisible();
				return 1;
			}
		}
	"refresh" =>
		refreshtree();
		return 1;
	"scroll" =>
		if(toks == nil)
			return 0;
		case hd toks {
		"up" =>
			topline -= vislines;
			clamptop();
		"down" =>
			topline += vislines;
			clamptop();
		"top" =>
			topline = 0;
			selected = 0;
		"bottom" =>
			topline = nvisible - vislines;
			clamptop();
			selected = nvisible - 1;
		}
		return 1;
	}
	return 0;
}

readrmfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[4096] of byte;
	n := sys->read(fd, buf, len buf);
	fd = nil;
	if(n <= 0)
		return nil;
	s := string buf[0:n];
	# Truncate file to consume the command
	fd = sys->create(path, Sys->OWRITE, 8r666);
	fd = nil;
	# Strip trailing whitespace
	while(len s > 0 && (s[len s - 1] == '\n' || s[len s - 1] == ' ' || s[len s - 1] == '\t'))
		s = s[:len s - 1];
	return s;
}

min(a, b: int): int
{
	if(a < b) return a;
	return b;
}
