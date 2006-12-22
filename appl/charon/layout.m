Layout: module
{
PATH: con "/dis/charon/layout.dis";

ReliefBd: con 2;
ReliefSunk, ReliefRaised : con iota;

# Frames

Frame: adt
{
	id: int;					# unique id
	doc: ref Build->Docinfo;		# various global attributes from HTML and headers
	src: ref Url->Parsedurl;
	name: string;				# current name (assigned by parent frame, or by default)
	marginw: int;				# margin on sides
	marginh: int;				# margin on top and bottom
	framebd: int;				# frame border desired
	flags: int;					# Build->FRnoresize, etc.
	layout: ref Lay;				# representation of layout
	sublays: array of ref Lay;		# table cells, captions
	sublayid: int;				# next sublayid to use
	controls: cyclic array of ref Control;	# controls
	controlid: int;				# next control id to use
	cim: ref Draw->Image;		# image where we draw contents
	r: Draw->Rect;				# part of cimage.r for this frame (including scrollbars)
	cr: Draw->Rect;			# part of r for contents (excluding scrollbars, including margins)
	totalr: Draw->Rect;			# total rectangle for page -- (0,0) is top left
	viewr: Draw->Rect;			# view: subrect of totalr currently on screen
	vscr: cyclic ref Control;		# vertical scrollbar
	hscr: cyclic ref Control;		# horizontal scrollbar
	parent: cyclic ref Frame;		# if this frame is in a frameset
	kids: cyclic list of ref Frame;	# if this frame is a frameset
	animpid: int;				# image animating thread
	prctxt: ref Printcontext;		# nil if not printing

# TEMP
dirtyr: Draw->Rect;
dirty: fn (f: self ref Frame, r: Draw->Rect);
isdirty: int;

	# reset() clears everything but parent, cim and r
	# new() and newkid() call reset
	# newkid() fills in name, etc., from ki, and copies cim from parent
	new: fn() : ref Frame;
	newkid: fn(parent: ref Frame, ki: ref Build->Kidinfo, r: Draw->Rect) : ref Frame;
	reset: fn(f: self ref Frame);
	addcontrol: fn(f: self ref Frame, c: ref Control) : int;
	lptosp: fn(f: self ref Frame, lp: Draw->Point) : Draw->Point;
	sptolp: fn(f: self ref Frame, sp: Draw->Point) : Draw->Point;
	xscroll: fn(f: self ref Frame, kind, val: int); # kind is CAscrollpage, etc
	yscroll: fn(f: self ref Frame, kind, val: int);
	scrollabs: fn(f : self ref Frame, p : Draw->Point);
	scrollrel: fn(f : self ref Frame, p : Draw->Point);
	find: fn(f: self ref Frame, p: Draw->Point, it: ref Build->Item) : ref Loc;
	swapimage: fn(f: self ref Frame, it: ref Build->Item.Iimage, src: string);
	focus: fn(f : self ref Frame, focus, raisex : int);
};

Printcontext: adt {
	mask: ref Draw->Image;
	endy: int;
};

# Line flags
Ldrawn, Lmoved, Lchanged: con byte (1<<iota);

# Layout engine organizes Items into Lines
Line: adt
{
	items: ref Build->Item;
	next: cyclic ref Line;
	prev: cyclic ref Line;
	pos: Draw->Point;
	width: int;
	height: int;
	ascent: int;
	flags: byte;

	new: fn() : ref Line;
};

# A place where an item, or a where mouse or keyboard focus could be.
Loc: adt
{
	le:		array of Locelem;
	n:		int;					# locs[0:n] form access path
	pos:		Draw->Point;				# offset in final item

	new:		fn() : ref Loc;
	add:		fn(loc: self ref Loc, kind: int, pos: Draw->Point);
	lastframe:	fn(loc: self ref Loc) : ref Frame;
	print:	fn(loc: self ref Loc, msg: string);
};

# Don't use pick so that can make array of Locelems (rather than ref Locelems),
# which saves a lot of alloc/frees in search functions.
# (Also, saves memory overall, in Limbo).
Locelem: adt
{
	kind:	int;				# LEframe, etc.
	pos: Draw->Point;			# position in screen coords of this element
	frame: ref Frame;		# root, or kid of previous (a frame)
	line: ref Line;			# a line in lay of previous
	item: ref Build->Item;		# an item in previous (a line or item)
	tcell: ref Build->Tablecell;	# a cell in previous (a table item)
	control: ref Control;		# a control in previous item, or scrollbar in previous frame
};

# Locelem kinds
LEframe, LEline, LEitem, LEtablecell, LEcontrol : con iota;

# One of the possible controls, and possible associated form field
Control: adt {
	f: cyclic ref Frame;
	ff: ref Build->Formfield;
	r: Draw->Rect;			# coords in f.cim coord system
	flags:	int;
	popup:	ref Gui->Popup;
	pick {
		Cbutton =>
			pic:		ref Draw->Image;		# picture on button (if no label)
			picmask:	ref Draw->Image;		# mask for pic
			dpic:	ref Draw->Image;		# disabled ("greyed out") pic
			dpicmask:	ref Draw->Image;	# mask for dpic
			label:	string;		# label on button (if no pic), or else flyover hint
			dorelief:	int;			# draw background & relief?
		Centry =>
			scr:		ref Control;
			s:		string;		# current contents
			sel:		(int,int);	# range of characters in s that are selected
			left:		int;			# index of character in s that is at left of window
			linewrap:	int;			# true if supposed to line-wrap
			onchange:	int;		# true if want onchange event
		Ccheckbox=>
			isradio: 	int;			# true if for radio button
		Cselect =>
			#
			owner:	ref Control;	# if this is a popup
			scr:		ref Control;	# if needed
			nvis:		int;			# number of visible options
			first:		int;			# index of current top visible option
			options:	array of Build->Option;
#			onchange:	int;		# true if want onchange event
		Clistbox =>
			hscr:		ref Control;
			vscr:		ref Control;
			nvis:		int;
			first:		int;			# index of current top visible option
			start:		int;			# index of current start column
			maxcol:		int;			# max column
			options:	array of Build->Option;
			grab:		cyclic ref Control;
		Cscrollbar =>
			top:		int;			# pixels in trough above/left of slider
			bot:		int;			# pixels in trough below/right of slider
			mindelta:	int;			# need delta of at least this (pixels)
			deltaval: int;
			ctl:		cyclic ref Control;	# if non-nil, scrolls this control
			holdstate: (int, int);
		Canimimage =>
			cim:		ref CharonUtils->CImage;
			cur:		int;				# current frame
			redraw:	int;				# need to redraw all?
			ts:		big;				# timestamp of current frame
			bg:		Build->Background;	# if need restore-to-background
		Clabel =>
			s:		string;
	}

	newff: fn(f: ref Frame, ff: ref Build->Formfield) : ref Control;
	newscroll: fn(f: ref Frame, isvert, length, breadth: int) : ref Control;
	newentry: fn(f: ref Frame, nh, nv, linewrap: int) : ref Control;
	newbutton: fn(f: ref Frame, pic, picmask: ref Draw->Image, lab: string, it: ref Build->Item.Iimage, candisable, dorelief: int) : ref Control;
	newcheckbox: fn(f: ref Frame, isradio: int) : ref Control;
	newselect: fn(f: ref Frame, nvis: int, options: array of Build->Option) : ref Control;
	newlistbox: fn(f: ref Frame, nvis, w: int, options: array of Build->Option) : ref Control;
	newanimimage: fn(f: ref Frame, cim: ref CharonUtils->CImage, bg: Build->Background) : ref Control;
	newlabel: fn(f: ref Frame, s: string) : ref Control;
	disable: fn(b: self ref Control);
	enable: fn(b: self ref Control);
	losefocus: fn(b: self ref Control, raisex: int);
	gainfocus: fn(b: self ref Control, raisex: int);
	scrollset: fn(sc: self ref Control, v1, v2, vmax, nsteps, draw: int);
	entryset: fn(e: self ref Control, s: string);
	# returns CAnone, etc.
	dokey: fn(c: self ref Control, keychar: int) : int;
	# domouse returns (action, grab) action = CAnone etc, grab = control that has grabbed mouse
	domouse: fn(c: self ref Control, p: Draw->Point, mtype: int, oldgrab : ref Control) : (int, ref Control);
	dopopup: fn(c: self ref Control): ref Control;
	donepopup: fn(c: self ref Control): ref Control;
	reset: fn(c: self ref Control);
	draw: fn(c: self ref Control, flush: int);
};

# Control flags
CFactive, CFenabled, CFsecure, CFhasfocus, CFscrvert, CFscracta1, CFscracta2, CFscracttr1, CFscracttr2: con (1<<iota);
CFscrallact : con (CFactive|CFscracta1|CFscracta2|CFscracttr1|CFscracttr2);

# Control Actions
CAnone, CAscrollpage, CAscrollline, CAscrolldelta, CAscrollabs,
CAbuttonpush, CAflyover, CAreturnkey, CAtabkey, CAkeyfocus, CAselected, CAchanged, CAdopopup, CAdonepopup: con iota;

# Result of layout
Lay: adt
{
	start: ref Line;			# fake before-the-first-line
	end: ref Line;			# fake after-the-last-line
	targetwidth: int;		# target width
	width: int;				# actual width
	height: int;			# actual height
	margin: int;			# extra space on all four sides
	floats:list of ref Build->Item.Ifloat;	# floats, from bottom up
	background: Build->Background;	# background for layout
	just: byte;				# default line justification
	flags: byte;			# Lchanged

	new: fn(targetwidth: int, just: byte, margin: int, bg: Build->Background) : ref Lay;
};

#B: Build;

init: fn(cu: CharonUtils);
layout: fn(f: ref Frame, bs: ref CharonUtils->ByteSource, linkclick: int) : array of byte;

drawrelief: fn(im: ref Draw->Image, r: Draw->Rect, style: int);
drawborder: fn(im: ref Draw->Image, r: Draw->Rect, n, color: int);
drawfill: fn(im: ref Draw->Image, r: Draw->Rect, color: int);
drawstring: fn(im: ref Draw->Image, p: Draw->Point, s: string);
measurestring: fn(s: string) : Draw->Point;
drawall: fn(f: ref Frame);
relayout: fn(f: ref Frame, l: ref Lay, targetw: int, just: byte);

stringwidth: fn(s: string): int;
};
