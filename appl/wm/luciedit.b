implement Luciedit;

#
# luciedit - Draw-based text editor with 9P interface
#
# A simple text editor with a Styx (9P) filesystem interface for
# programmatic access by Veltro agents and other tools.
#
# The 9P filesystem is mounted at /mnt/luciedit and bound to /edit.
# The filesystem layout uses per-document directories to support
# future multi-document/split-view without protocol changes:
#
#   /edit/
#     ctl          Global control (open, new, quit)
#     index        List open documents
#     1/           Per-document directory
#       body       Read/write document text
#       ctl        Document control (save, goto, find, etc.)
#       event      Blocking read for editor events
#       addr       Cursor position (line col)
#
# Keyboard:
#   Type to insert text at cursor
#   Backspace    delete char before cursor
#   Delete       delete char at cursor
#   Enter        insert newline
#   Arrow keys   move cursor
#   Home/End     start/end of line
#   Ctrl-S       save
#   Ctrl-Q       quit
#   Ctrl-Z       undo last edit
#   Ctrl-F       find (prompts in status bar)
#   Ctrl-G       find next
#   Ctrl-X       cut selection
#   Ctrl-C       copy selection
#   Ctrl-V       paste
#   Ctrl-A       select all
#   Ctrl-Home    go to top of file
#   Ctrl-End     go to end of file
#   Page Up/Down scroll by screenful
#
# Mouse:
#   Button 1     place cursor / select text
#   Button 2     paste (snarf buffer)
#   Button 3     context menu (save, find, quit)
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

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "string.m";
	str: String;

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;

include "styxservers.m";
	styxservers: Styxservers;
	Fid, Styxserver, Navigator, Navop: import styxservers;

Luciedit: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

# Colors
BG:	con int 16rFFFDF6FF;		# warm off-white background
FG:	con int 16r333333FF;		# dark text
CURSORCOL: con int 16r2266CCFF;	# blue cursor
SELCOL:	con int 16rB4D5FEFF;		# light blue selection
LNCOL:	con int 16rBBBBBBFF;		# line number color
STATUSBG: con int 16rE8E8E8FF;		# status bar background
STATUSFG: con int 16r555555FF;		# status bar text
DIRTYCOL: con int 16rCC4444FF;		# dirty indicator

# Dimensions
MARGIN: con 4;				# text margin
LNWIDTH: con 48;			# line number gutter width
TABSTOP: con 4;			# tab width in spaces
SCROLLW: con 12;			# scrollbar width

# Key constants (Inferno keyboard codes)
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

# Undo types
UndoInsert, UndoDelete, UndoReplace, UndoJoinLine, UndoSplitLine: con iota;
MAXUNDO: con 100;

Undo: adt {
	kind: int;
	line: int;
	col: int;
	text: string;
	oldtext: string;
};

# ---------- Document ADT ----------
# All per-document state is in Doc. Today there is one Doc;
# the per-document directory scheme (doc.id) supports future multi-doc.

Doc: adt {
	id:		int;
	lines:		array of string;
	nlines:		int;
	curline:	int;
	curcol:		int;
	topline:	int;
	dirty:		int;
	filepath:	string;

	# Selection
	selactive:	int;
	selstartline:	int;
	selstartcol:	int;
	selendline:	int;
	selendcol:	int;

	# Undo
	undostack:	array of ref Undo;
	undocount:	int;

	# Find
	searchstr:	string;
	findmode:	int;
	findbuf:	string;

	# Snarf
	snarf:		string;
};

newdoc(id: int): ref Doc
{
	d := ref Doc;
	d.id = id;
	d.lines = array[1024] of string;
	d.lines[0] = "";
	d.nlines = 1;
	d.curline = 0;
	d.curcol = 0;
	d.topline = 0;
	d.dirty = 0;
	d.filepath = "";
	d.selactive = 0;
	d.selstartline = 0;
	d.selstartcol = 0;
	d.selendline = 0;
	d.selendcol = 0;
	d.undostack = array[MAXUNDO] of ref Undo;
	d.undocount = 0;
	d.searchstr = "";
	d.findmode = 0;
	d.findbuf = "";
	d.snarf = "";
	return d;
}

# ---------- QID encoding ----------
# Path = (docid << 8) | filetype
# docid=0 for global files, docid>=1 for per-document files.

QSHIFT: con 8;

# File types within a document directory
Fdir, Fbody, Fctl, Fevent, Faddr: con iota;

# Global file types (docid=0)
Groot: con 0;		# root dir
Ggctl: con 1;		# global ctl
Gindex: con 2;		# index

mkqpath(docid, ftype: int): big
{
	return big ((docid << QSHIFT) | ftype);
}

qiddoc(path: big): int
{
	return (int path) >> QSHIFT;
}

qidfile(path: big): int
{
	return (int path) & 16rFF;
}

# ---------- 9P ↔ Editor communication ----------

Rgetbody, Rsetbody, Rgetaddr, Rsetaddr, Rdoctl, Rgetindex, Rgctl: con iota;

EditReq: adt {
	op:	int;
	docid:	int;
	data:	string;
	reply:	chan of string;
};

editreq: chan of ref EditReq;
eventch: chan of string;

# ---------- Display resources (global) ----------
display: ref Display;
font: ref Font;
bgcolor: ref Image;
fgcolor: ref Image;
cursorcolor: ref Image;
selcolor: ref Image;
lncolor: ref Image;
statusbgcolor: ref Image;
statusfgcolor: ref Image;
dirtycolor: ref Image;

w: ref Window;
vislines: int;
kbdescstate: int;	# ANSI escape decode state (0=normal)
kbdescarg:   int;
doc: ref Doc;
stderr: ref Sys->FD;

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;
	menumod = load Menu Menu->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
	stderr = sys->fildes(2);

	if(ctxt == nil) {
		sys->fprint(stderr, "luciedit: no window context\n");
		raise "fail:no context";
	}

	sys->pctl(Sys->NEWPGRP, nil);
	wmclient->init();

	# Initialize document
	doc = newdoc(1);

	# Parse args
	argv = tl argv;
	if(argv != nil)
		doc.filepath = hd argv;

	# Start 9P server before creating window (so it's available immediately)
	editreq = chan of ref EditReq;
	eventch = chan of string;
	spawn startfsys();

	# Create window
	sys->sleep(100);
	w = wmclient->window(ctxt, titlestr(), Wmclient->Appl);
	display = w.display;

	# Load font
	font = Font.open(display, "/fonts/combined/unicode.14.font");
	if(font == nil)
		font = Font.open(display, "/fonts/10646/9x15/9x15.font");
	if(font == nil)
		font = Font.open(display, "*default*");
	if(font == nil) {
		sys->fprint(stderr, "luciedit: cannot load any font\n");
		raise "fail:no font";
	}

	# Create color images
	bgcolor = display.color(BG);
	fgcolor = display.color(FG);
	cursorcolor = display.color(CURSORCOL);
	selcolor = display.color(SELCOL);
	lncolor = display.color(LNCOL);
	statusbgcolor = display.color(STATUSBG);
	statusfgcolor = display.color(STATUSFG);
	dirtycolor = display.color(DIRTYCOL);

	# Load file if specified
	if(doc.filepath != "")
		loadfile(doc.filepath);

	# Set up window
	w.reshape(Rect((0, 0), (640, 480)));
	w.startinput("kbd" :: "ptr" :: nil);
	w.onscreen(nil);

	if(menumod != nil)
		menumod->init(display, font);
	menu := menumod->new(array[] of {"save", "find", "goto line", "select all", "cut", "copy", "paste", "exit"});

	redraw();

	# Cursor blink timer
	ticks := chan of int;
	spawn timer(ticks, 500);
	cursorvis := 1;

	# Track mouse for selection
	mousedown := 0;

	for(;;) alt {
	ctl := <-w.ctl or
	ctl = <-w.ctxt.ctl =>
		w.wmctl(ctl);
		if(ctl != nil && ctl[0] == '!')
			redraw();
	rawkey := <-w.ctxt.kbd =>
		key := filterkbd(rawkey);
		if(key >= 0) {
			cursorvis = 1;
			if(doc.findmode)
				handlefindkey(key);
			else
				handlekey(key);
			redraw();
		}
	p := <-w.ctxt.ptr =>
		if(!w.pointer(*p)) {
			if(p.buttons & 4 && menumod != nil && menu != nil) {
				n := menu.show(w.image, p.xy, w.ctxt.ptr);
				case n {
				0 => dosave();
				1 => startfind();
				2 => ;  # goto line (TODO)
				3 => selectall();
				4 => docut();
				5 => docopy();
				6 => dopaste();
				7 =>
					if(!checkdirty())
						break;
					postnote(1, sys->pctl(0, nil), "kill");
					exit;
				}
				redraw();
			} else if(p.buttons & 2) {
				buf := wmclient->snarfget();
				if(buf != "")
					doc.snarf = buf;
				if(doc.snarf != "") {
					insertstring(doc.snarf);
					doc.dirty = 1;
				}
				redraw();
			} else if(p.buttons & 8) {
				# Mouse wheel scroll up
				doc.topline -= 3;
				if(doc.topline < 0)
					doc.topline = 0;
				redraw();
			} else if(p.buttons & 16) {
				# Mouse wheel scroll down
				doc.topline += 3;
				maxtl := doc.nlines - vislines;
				if(maxtl < 0) maxtl = 0;
				if(doc.topline > maxtl) doc.topline = maxtl;
				redraw();
			} else if(p.buttons & 1) {
				pr := w.image.r;
				stath := font.height + MARGIN * 2;
				scrollr := Rect((pr.min.x, pr.min.y), (pr.min.x + SCROLLW, pr.max.y - stath));
				if(scrollr.contains(p.xy)) {
					# Scrollbar click: page up/down based on thumb position
					if(doc.nlines > 0 && vislines > 0) {
						totalh := scrollr.dy();
						thumbh := (vislines * totalh) / doc.nlines;
						if(thumbh < 10) thumbh = 10;
						if(thumbh > totalh) thumbh = totalh;
						thumby := scrollr.min.y;
						if(doc.nlines > vislines)
							thumby = scrollr.min.y + (doc.topline * (totalh - thumbh)) / (doc.nlines - vislines);
						if(p.xy.y < thumby) {
							doc.topline -= vislines;
							if(doc.topline < 0) doc.topline = 0;
						} else if(p.xy.y > thumby + thumbh) {
							doc.topline += vislines;
							maxtl := doc.nlines - vislines;
							if(maxtl < 0) maxtl = 0;
							if(doc.topline > maxtl) doc.topline = maxtl;
						}
					}
				} else if(mousedown) {
					# Drag: anchor is fixed, update selection end live
					(ml, mc2) := pos2cursor(p.xy);
					doc.curline = ml;
					doc.curcol = mc2;
					doc.selactive = (ml != doc.selstartline || mc2 != doc.selstartcol);
					if(doc.selactive) {
						doc.selendline = ml;
						doc.selendcol = mc2;
					}
				} else {
					# New click: set anchor
					(ml, mc2) := pos2cursor(p.xy);
					doc.curline = ml;
					doc.curcol = mc2;
					doc.selactive = 0;
					doc.selstartline = ml;
					doc.selstartcol = mc2;
					mousedown = 1;
				}
				redraw();
			} else if(mousedown) {
				# Button released: finalise selection
				(ml, mc2) := pos2cursor(p.xy);
				if(ml != doc.selstartline || mc2 != doc.selstartcol) {
					doc.selactive = 1;
					doc.selendline = ml;
					doc.selendcol = mc2;
					doc.curline = ml;
					doc.curcol = mc2;
				}
				mousedown = 0;
				redraw();
			}
		}
	<-ticks =>
		cursorvis = !cursorvis;
		drawcursor(cursorvis);
		changed := checkctlfile();
		writeeditstate();
		if(changed)
			redraw();
	req := <-editreq =>
		handleeditreq(req);
		redraw();
	}
}

# ---------- Handle 9P requests on the main thread ----------

handleeditreq(req: ref EditReq)
{
	case req.op {
	Rgetbody =>
		req.reply <-= getbodytext();
	Rsetbody =>
		setbodytext(req.data);
		postevent("modified");
		req.reply <-= "ok";
	Rgetaddr =>
		req.reply <-= sys->sprint("%d %d", doc.curline + 1, doc.curcol + 1);
	Rsetaddr =>
		(line, rest) := splitfirst(req.data);
		(col, nil) := splitfirst(rest);
		(ln, nil) := str->toint(line, 10);
		(cn, nil) := str->toint(col, 10);
		if(ln > 0) {
			doc.curline = ln - 1;
			if(doc.curline >= doc.nlines)
				doc.curline = doc.nlines - 1;
		}
		if(cn > 0) {
			doc.curcol = cn - 1;
			fixcol();
		}
		scrolltocursor();
		req.reply <-= "ok";
	Rdoctl =>
		req.reply <-= handledocctl(req.data);
	Rgetindex =>
		d := sys->sprint("%d %s %d\n", doc.id, doc.filepath, doc.dirty);
		req.reply <-= d;
	Rgctl =>
		req.reply <-= handlegctl(req.data);
	}
}

getbodytext(): string
{
	s := "";
	for(i := 0; i < doc.nlines; i++) {
		if(i > 0)
			s += "\n";
		s += doc.lines[i];
	}
	return s;
}

setbodytext(text: string)
{
	doc.nlines = 0;
	doc.lines = array[1024] of string;
	start := 0;
	for(i := 0; i < len text; i++) {
		if(text[i] == '\n') {
			growbuf();
			doc.lines[doc.nlines] = text[start:i];
			doc.nlines++;
			start = i + 1;
		}
	}
	growbuf();
	if(start < len text)
		doc.lines[doc.nlines] = text[start:];
	else
		doc.lines[doc.nlines] = "";
	doc.nlines++;
	doc.dirty = 1;
	doc.curline = 0;
	doc.curcol = 0;
	doc.topline = 0;
	doc.selactive = 0;
	doc.undocount = 0;
}

handledocctl(cmd: string): string
{
	(op, rest) := splitfirst(cmd);
	op = str->tolower(op);
	case op {
	"save" =>
		dosave();
		return "ok";
	"goto" =>
		(lns, nil) := str->toint(rest, 10);
		if(lns > 0) {
			doc.curline = lns - 1;
			if(doc.curline >= doc.nlines)
				doc.curline = doc.nlines - 1;
			doc.curcol = 0;
			scrolltocursor();
		}
		return "ok";
	"find" =>
		if(rest != "") {
			doc.searchstr = rest;
			findnext();
		}
		return "ok";
	"name" =>
		if(rest != "") {
			doc.filepath = rest;
			w.settitle(titlestr());
		}
		return "ok";
	"clean" =>
		doc.dirty = 0;
		return "ok";
	"dirty" =>
		doc.dirty = 1;
		return "ok";
	"insert" =>
		# insert <line> <col> <text>
		(ls, r2) := splitfirst(rest);
		(cs, text) := splitfirst(r2);
		(ln, nil) := str->toint(ls, 10);
		(cn, nil) := str->toint(cs, 10);
		if(ln > 0 && cn > 0) {
			doc.curline = ln - 1;
			doc.curcol = cn - 1;
			if(doc.curline >= doc.nlines)
				doc.curline = doc.nlines - 1;
			fixcol();
			insertstring(text);
			doc.dirty = 1;
			postevent("modified");
		}
		return "ok";
	"delete" =>
		# delete <startline> <startcol> <endline> <endcol>
		(sls, r2) := splitfirst(rest);
		(scs, r3) := splitfirst(r2);
		(els, r4) := splitfirst(r3);
		(ecs, nil) := splitfirst(r4);
		(sl, nil) := str->toint(sls, 10);
		(sc, nil) := str->toint(scs, 10);
		(el, nil) := str->toint(els, 10);
		(ec, nil) := str->toint(ecs, 10);
		if(sl > 0 && sc > 0 && el > 0 && ec > 0) {
			doc.selactive = 1;
			doc.selstartline = sl - 1;
			doc.selstartcol = sc - 1;
			doc.selendline = el - 1;
			doc.selendcol = ec - 1;
			deletesel();
			postevent("modified");
		}
		return "ok";
	* =>
		return "error: unknown ctl command: " + op;
	}
}

handlegctl(cmd: string): string
{
	(op, rest) := splitfirst(cmd);
	op = str->tolower(op);
	case op {
	"open" =>
		if(rest != "") {
			doc.filepath = rest;
			loadfile(doc.filepath);
			w.settitle(titlestr());
			postevent("opened " + doc.filepath);
		}
		return "ok";
	"new" =>
		doc.lines = array[1024] of string;
		doc.lines[0] = "";
		doc.nlines = 1;
		doc.curline = 0;
		doc.curcol = 0;
		doc.topline = 0;
		doc.dirty = 0;
		doc.filepath = "";
		doc.selactive = 0;
		doc.undocount = 0;
		w.settitle(titlestr());
		postevent("new");
		return "ok";
	"quit" =>
		if(checkdirty()) {
			postevent("quit");
			postnote(1, sys->pctl(0, nil), "kill");
			exit;
		}
		return "ok";
	* =>
		return "error: unknown global ctl: " + op;
	}
}

postevent(msg: string)
{
	# Non-blocking send — if nobody is reading events, drop it
	alt {
	eventch <-= msg =>
		;
	* =>
		;
	}
}

# ---------- 9P File Server ----------

# --- Real-file IPC for Veltro tool access ---
# /tmp/veltro/edit/ is inside the restricted agent namespace (/tmp/veltro/ is always granted).
EDIT_DIR:  con "/tmp/veltro/edit";
EDIT_INST: con "/tmp/veltro/edit/1";

MNTPT: con "/mnt/luciedit";
BINDPT: con "/edit";
user: string;

startfsys()
{
	# Initialise real-file state directories first
	initeditdir();
	styx = load Styx Styx->PATH;
	if(styx == nil) {
		sys->fprint(stderr, "luciedit: can't load Styx: %r\n");
		return;
	}
	styx->init();

	styxservers = load Styxservers Styxservers->PATH;
	if(styxservers == nil) {
		sys->fprint(stderr, "luciedit: can't load Styxservers: %r\n");
		return;
	}
	styxservers->init(styx);

	user = readf("/dev/user");
	if(user == nil)
		user = "inferno";

	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0) {
		sys->fprint(stderr, "luciedit: pipe: %r\n");
		return;
	}

	navops := chan of ref Navop;
	spawn navigator(navops);

	(tchan, srv) := Styxserver.new(fds[0], Navigator.new(navops), big 0);
	fds[0] = nil;

	pidc := chan of int;
	spawn serveloop(tchan, srv, pidc, navops);
	<-pidc;

	# Mount and bind
	if(sys->mount(fds[1], nil, MNTPT, Sys->MREPL|Sys->MCREATE, nil) < 0)
		sys->fprint(stderr, "luciedit: mount %s: %r\n", MNTPT);
	else if(sys->bind(MNTPT, BINDPT, Sys->MREPL|Sys->MCREATE) < 0)
		sys->fprint(stderr, "luciedit: bind %s %s: %r\n", MNTPT, BINDPT);
}

# Static directory tables for the navigator

PERM_DIR: con 8r755 | Sys->DMDIR;
PERM_RW: con 8r666;
PERM_RO: con 8r444;

# File info for stat/walk
FileInfo: adt {
	name:	string;
	qpath:	big;
	qtype:	int;
	perm:	int;
};

# Root directory entries
# qpath values: mkqpath(docid, ftype) = big ((docid << QSHIFT) | ftype)
# mkqpath(0, Ggctl)=big 1, mkqpath(0, Gindex)=big 2, mkqpath(1, Fdir)=big 256
rootfiles := array[] of {
	FileInfo("ctl",   big 1,   Sys->QTFILE, PERM_RW),
	FileInfo("index", big 2,   Sys->QTFILE, PERM_RO),
	FileInfo("1",     big 256, Sys->QTDIR,  PERM_DIR),
};

# Per-document directory entries
docfiles := array[] of {
	FileInfo("body",  big 0, Sys->QTFILE, PERM_RW),    # qpath filled in per-doc
	FileInfo("ctl",   big 0, Sys->QTFILE, PERM_RW),
	FileInfo("event", big 0, Sys->QTFILE, PERM_RO),
	FileInfo("addr",  big 0, Sys->QTFILE, PERM_RW),
};

mkfilestat(fi: FileInfo, qpath: big): ref Sys->Dir
{
	d := ref sys->zerodir;
	d.name = fi.name;
	d.uid = user;
	d.gid = user;
	d.qid.path = qpath;
	d.qid.vers = 0;
	d.qid.qtype = fi.qtype;
	d.mode = fi.perm;
	return d;
}

mkdirstat(name: string, qpath: big): ref Sys->Dir
{
	d := ref sys->zerodir;
	d.name = name;
	d.uid = user;
	d.gid = user;
	d.qid.path = qpath;
	d.qid.vers = 0;
	d.qid.qtype = Sys->QTDIR;
	d.mode = PERM_DIR;
	return d;
}

navigator(navops: chan of ref Navop)
{
	while((m := <-navops) != nil) {
		pick n := m {
		Stat =>
			n.reply <-= dostat(n.path);

		Walk =>
			did := qiddoc(n.path);
			fid := qidfile(n.path);

			if(n.name == "..") {
				if(did > 0)
					n.reply <-= (mkdirstat(".", big Groot), nil);
				else
					n.reply <-= (mkdirstat(".", big Groot), nil);
				continue;
			}

			# Walking from root dir
			if(did == 0 && fid == Groot) {
				found := 0;
				for(i := 0; i < len rootfiles; i++) {
					if(rootfiles[i].name == n.name) {
						n.reply <-= (mkfilestat(rootfiles[i], rootfiles[i].qpath), nil);
						found = 1;
						break;
					}
				}
				if(!found)
					n.reply <-= (nil, Styxservers->Enotfound);
				continue;
			}

			# Walking from a doc dir
			if(did > 0 && fid == Fdir) {
				found := 0;
				for(i := 0; i < len docfiles; i++) {
					if(docfiles[i].name == n.name) {
						# Compute actual qpath for this doc
						ft: int;
						case n.name {
						"body"  => ft = Fbody;
						"ctl"   => ft = Fctl;
						"event" => ft = Fevent;
						"addr"  => ft = Faddr;
						* => ft = 0;
						}
						qp := mkqpath(did, ft);
						fi := FileInfo(n.name, qp, docfiles[i].qtype, docfiles[i].perm);
						n.reply <-= (mkfilestat(fi, qp), nil);
						found = 1;
						break;
					}
				}
				if(!found)
					n.reply <-= (nil, Styxservers->Enotfound);
				continue;
			}

			n.reply <-= (nil, Styxservers->Enotfound);

		Readdir =>
			did := qiddoc(m.path);
			fid := qidfile(m.path);

			if(did == 0 && fid == Groot) {
				# Root directory
				i := n.offset;
				count := n.count;
				for(j := i; j < len rootfiles && count > 0; j++) {
					n.reply <-= (mkfilestat(rootfiles[j], rootfiles[j].qpath), nil);
					count--;
				}
				n.reply <-= (nil, nil);
				continue;
			}

			if(did > 0 && fid == Fdir) {
				# Doc directory
				i := n.offset;
				count := n.count;
				for(j := i; j < len docfiles && count > 0; j++) {
					ft: int;
					case docfiles[j].name {
					"body"  => ft = Fbody;
					"ctl"   => ft = Fctl;
					"event" => ft = Fevent;
					"addr"  => ft = Faddr;
					* => ft = 0;
					}
					qp := mkqpath(did, ft);
					fi := FileInfo(docfiles[j].name, qp, docfiles[j].qtype, docfiles[j].perm);
					n.reply <-= (mkfilestat(fi, qp), nil);
					count--;
				}
				n.reply <-= (nil, nil);
				continue;
			}

			n.reply <-= (nil, "not a directory");
		}
	}
}

dostat(path: big): (ref Sys->Dir, string)
{
	did := qiddoc(path);
	fid := qidfile(path);

	# Root
	if(did == 0 && fid == Groot)
		return (mkdirstat(".", big Groot), nil);

	# Global files
	if(did == 0) {
		for(i := 0; i < len rootfiles; i++)
			if(rootfiles[i].qpath == path)
				return (mkfilestat(rootfiles[i], path), nil);
		return (nil, Styxservers->Enotfound);
	}

	# Doc directory
	if(fid == Fdir)
		return (mkdirstat(string did, mkqpath(did, Fdir)), nil);

	# Doc files
	for(i := 0; i < len docfiles; i++) {
		ft: int;
		case docfiles[i].name {
		"body"  => ft = Fbody;
		"ctl"   => ft = Fctl;
		"event" => ft = Fevent;
		"addr"  => ft = Faddr;
		* => ft = 0;
		}
		if(fid == ft) {
			qp := mkqpath(did, ft);
			fi := FileInfo(docfiles[i].name, qp, docfiles[i].qtype, docfiles[i].perm);
			return (mkfilestat(fi, qp), nil);
		}
	}

	return (nil, Styxservers->Enotfound);
}

serveloop(tchan: chan of ref Tmsg, srv: ref Styxserver,
	pidc: chan of int, navops: chan of ref Navop)
{
	pidc <-= sys->pctl(Sys->FORKNS|Sys->NEWFD, 1 :: 2 :: srv.fd.fd :: nil);

Serve:
	while((gm := <-tchan) != nil) {
		pick m := gm {
		Readerror =>
			break Serve;

		Open =>
			c := srv.getfid(m.fid);
			if(c == nil) {
				srv.open(m);
				break;
			}
			mode := styxservers->openmode(m.mode);
			if(mode < 0) {
				srv.reply(ref Rmsg.Error(m.tag, Styxservers->Ebadarg));
				break;
			}
			qid := Sys->Qid(c.path, 0, c.qtype);
			c.open(mode, qid);
			srv.reply(ref Rmsg.Open(m.tag, qid, srv.iounit()));

		Read =>
			(c, rerr) := srv.canread(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, rerr));
				break;
			}
			if(c.qtype & Sys->QTDIR) {
				srv.read(m);
				break;
			}
			handlefsread(srv, m, c);

		Write =>
			(c, werr) := srv.canwrite(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, werr));
				break;
			}
			handlefswrite(srv, m, c);

		Clunk =>
			srv.clunk(m);

		* =>
			srv.default(gm);
		}
	}
	navops <-= nil;
}

handlefsread(srv: ref Styxserver, m: ref Tmsg.Read, c: ref Fid)
{
	did := qiddoc(c.path);
	fid := qidfile(c.path);

	# Global files
	if(did == 0) {
		case fid {
		Ggctl =>
			srv.reply(styxservers->readstr(m, "luciedit\n"));
			return;
		Gindex =>
			reply := chan of string;
			editreq <-= ref EditReq(Rgetindex, 0, "", reply);
			data := <-reply;
			srv.reply(styxservers->readstr(m, data));
			return;
		}
		srv.reply(ref Rmsg.Error(m.tag, Styxservers->Eperm));
		return;
	}

	# Per-doc files
	case fid {
	Fbody =>
		reply := chan of string;
		editreq <-= ref EditReq(Rgetbody, did, "", reply);
		data := <-reply;
		srv.reply(styxservers->readstr(m, data));
	Fctl =>
		srv.reply(styxservers->readstr(m, ""));
	Fevent =>
		# Block until an event arrives
		ev := <-eventch;
		srv.reply(styxservers->readstr(m, ev + "\n"));
	Faddr =>
		reply := chan of string;
		editreq <-= ref EditReq(Rgetaddr, did, "", reply);
		data := <-reply;
		srv.reply(styxservers->readstr(m, data + "\n"));
	* =>
		srv.reply(ref Rmsg.Error(m.tag, Styxservers->Eperm));
	}
}

handlefswrite(srv: ref Styxserver, m: ref Tmsg.Write, c: ref Fid)
{
	did := qiddoc(c.path);
	fid := qidfile(c.path);
	data := string m.data;

	# Global ctl
	if(did == 0 && fid == Ggctl) {
		reply := chan of string;
		editreq <-= ref EditReq(Rgctl, 0, data, reply);
		result := <-reply;
		if(len result >= 6 && result[0:6] == "error:")
			srv.reply(ref Rmsg.Error(m.tag, result));
		else
			srv.reply(ref Rmsg.Write(m.tag, len m.data));
		return;
	}

	if(did == 0) {
		srv.reply(ref Rmsg.Error(m.tag, Styxservers->Eperm));
		return;
	}

	# Per-doc files
	case fid {
	Fbody =>
		reply := chan of string;
		editreq <-= ref EditReq(Rsetbody, did, data, reply);
		<-reply;
		srv.reply(ref Rmsg.Write(m.tag, len m.data));
	Fctl =>
		reply := chan of string;
		editreq <-= ref EditReq(Rdoctl, did, data, reply);
		result := <-reply;
		if(len result >= 6 && result[0:6] == "error:")
			srv.reply(ref Rmsg.Error(m.tag, result));
		else
			srv.reply(ref Rmsg.Write(m.tag, len m.data));
	Faddr =>
		reply := chan of string;
		editreq <-= ref EditReq(Rsetaddr, did, data, reply);
		<-reply;
		srv.reply(ref Rmsg.Write(m.tag, len m.data));
	* =>
		srv.reply(ref Rmsg.Error(m.tag, Styxservers->Eperm));
	}
}

# ---------- Title ----------

titlestr(): string
{
	s := "Luciedit";
	if(doc.filepath != "")
		s += " " + doc.filepath;
	else
		s += " (new)";
	if(doc.dirty)
		s += " *";
	return s;
}

# ---------- Cursor position from screen coords ----------

pos2cursor(p: Point): (int, int)
{
	if(w.image == nil)
		return (doc.curline, doc.curcol);

	textr := textrect();
	maxw := textr.dx();

	vy := p.y - textr.min.y;
	if(vy < 0)
		vy = 0;
	clickvrow := vy / font.height;

	vrow := 0;
	for(i := doc.topline; i < doc.nlines; i++) {
		expanded := expandtabs(doc.lines[i]);
		start := 0;
		first := 1;
		while(start < len expanded || first) {
			first = 0;
			k := wrapend(expanded, start, maxw);
			if(vrow == clickvrow) {
				x := p.x - textr.min.x;
				w2 := 0;
				ek := start;
				while(ek < k) {
					cw := font.width(expanded[ek:ek+1]);
					if(w2 + cw/2 > x)
						break;
					w2 += cw;
					ek++;
				}
				return (i, unexpandcol(doc.lines[i], ek));
			}
			vrow++;
			start = k;
		}
	}
	return (doc.nlines - 1, len doc.lines[doc.nlines - 1]);
}

textrect(): Rect
{
	if(w.image == nil)
		return Rect((0,0),(0,0));
	r := w.image.r;
	statusheight := font.height + MARGIN * 2;
	return Rect((r.min.x + SCROLLW + LNWIDTH, r.min.y + MARGIN),
		    (r.max.x - MARGIN, r.max.y - statusheight));
}

# ---------- Keyboard handling ----------

# filterkbd: decode ANSI escape sequences to Inferno key codes.
# Returns the decoded key, or -1 if the character was part of an incomplete sequence.
# Inferno key codes (>= 0xFF00) are passed through unchanged.
filterkbd(c: int): int
{
	if(c >= 16rFF00)
		return c;
	case kbdescstate {
	0 =>
		if(c == 27) {
			kbdescstate = 1;
			return -1;
		}
	1 =>
		kbdescstate = 0;
		if(c == '[') {
			kbdescstate = 2;
			kbdescarg = 0;
			return -1;
		}
		# bare ESC + char: deliver the char
	2 =>
		kbdescstate = 0;
		if(c == 'A') return 16rFF52;	# up
		if(c == 'B') return 16rFF54;	# down
		if(c == 'C') return 16rFF53;	# right
		if(c == 'D') return 16rFF51;	# left
		if(c == 'H') return 16rFF61;	# home
		if(c == 'F') return 16rFF57;	# end
		if(c == '1' || c == '4' || c == '5' || c == '6' || c == '7' || c == '8') {
			kbdescarg = c - '0';
			kbdescstate = 3;
			return -1;
		}
		return -1;	# unknown sequence, discard
	3 =>
		if(c == '~') {
			kbdescstate = 0;
			if(kbdescarg == 1 || kbdescarg == 7) return 16rFF61;	# home
			if(kbdescarg == 4 || kbdescarg == 8) return 16rFF57;	# end
			if(kbdescarg == 5) return 16rFF55;			# pgup
			if(kbdescarg == 6) return 16rFF56;			# pgdn
			return -1;
		}
		if(c >= '0' && c <= '9') {
			kbdescarg = kbdescarg * 10 + (c - '0');
			return -1;
		}
		kbdescstate = 0;
		return -1;
	}
	return c;
}

handlekey(key: int)
{
	ctrl := 0;
	if(key >= 1 && key <= 26 && key != Kbs && key != '\n' && key != '\t')
		ctrl = 1;

	if(ctrl) {
		case key {
		1 =>	# Ctrl-A: select all
			selectall();
		3 =>	# Ctrl-C: copy
			docopy();
		6 =>	# Ctrl-F: find
			startfind();
		7 =>	# Ctrl-G: find next
			findnext();
		17 =>	# Ctrl-Q: quit
			if(checkdirty()) {
				postevent("quit");
				postnote(1, sys->pctl(0, nil), "kill");
				exit;
			}
		19 =>	# Ctrl-S: save
			dosave();
		22 =>	# Ctrl-V: paste
			dopaste();
		24 =>	# Ctrl-X: cut
			docut();
		26 =>	# Ctrl-Z: undo
			doundo();
		}
		return;
	}

	case key {
	Kbs =>
		deletesel();
		if(doc.curcol > 0) {
			pushundo(UndoDelete, doc.curline, doc.curcol-1, doc.lines[doc.curline][doc.curcol-1:doc.curcol]);
			doc.lines[doc.curline] = doc.lines[doc.curline][0:doc.curcol-1] + doc.lines[doc.curline][doc.curcol:];
			doc.curcol--;
			doc.dirty = 1;
		} else if(doc.curline > 0) {
			pushundo(UndoJoinLine, doc.curline-1, len doc.lines[doc.curline-1], doc.lines[doc.curline]);
			doc.curcol = len doc.lines[doc.curline-1];
			doc.lines[doc.curline-1] += doc.lines[doc.curline];
			deleteline(doc.curline);
			doc.curline--;
			doc.dirty = 1;
		}
	Kdel =>
		deletesel();
		if(doc.curcol < len doc.lines[doc.curline]) {
			pushundo(UndoDelete, doc.curline, doc.curcol, doc.lines[doc.curline][doc.curcol:doc.curcol+1]);
			doc.lines[doc.curline] = doc.lines[doc.curline][0:doc.curcol] + doc.lines[doc.curline][doc.curcol+1:];
			doc.dirty = 1;
		} else if(doc.curline < doc.nlines - 1) {
			pushundo(UndoJoinLine, doc.curline, len doc.lines[doc.curline], doc.lines[doc.curline+1]);
			doc.lines[doc.curline] += doc.lines[doc.curline+1];
			deleteline(doc.curline+1);
			doc.dirty = 1;
		}
	'\n' =>
		deletesel();
		rest := "";
		if(doc.curcol < len doc.lines[doc.curline])
			rest = doc.lines[doc.curline][doc.curcol:];
		pushundo(UndoSplitLine, doc.curline, doc.curcol, "");
		doc.lines[doc.curline] = doc.lines[doc.curline][0:doc.curcol];
		insertline(doc.curline+1, rest);
		doc.curline++;
		doc.curcol = 0;
		doc.dirty = 1;
	'\t' =>
		deletesel();
		insertchar('\t');
		doc.dirty = 1;
	Kup =>
		if(doc.curline > 0) {
			doc.curline--;
			fixcol();
		}
		doc.selactive = 0;
	Kdown =>
		if(doc.curline < doc.nlines - 1) {
			doc.curline++;
			fixcol();
		}
		doc.selactive = 0;
	Kleft =>
		if(doc.curcol > 0)
			doc.curcol--;
		else if(doc.curline > 0) {
			doc.curline--;
			doc.curcol = len doc.lines[doc.curline];
		}
		doc.selactive = 0;
	Kright =>
		if(doc.curcol < len doc.lines[doc.curline])
			doc.curcol++;
		else if(doc.curline < doc.nlines - 1) {
			doc.curline++;
			doc.curcol = 0;
		}
		doc.selactive = 0;
	Khome =>
		doc.curcol = 0;
		doc.selactive = 0;
	Kend =>
		doc.curcol = len doc.lines[doc.curline];
		doc.selactive = 0;
	Kpgup =>
		if(vislines > 0) {
			doc.curline -= vislines;
			if(doc.curline < 0)
				doc.curline = 0;
			fixcol();
		}
		doc.selactive = 0;
	Kpgdown =>
		if(vislines > 0) {
			doc.curline += vislines;
			if(doc.curline >= doc.nlines)
				doc.curline = doc.nlines - 1;
			fixcol();
		}
		doc.selactive = 0;
	Kesc =>
		doc.selactive = 0;
	* =>
		if(key >= 16r20 || key == '\t') {
			deletesel();
			insertchar(key);
			doc.dirty = 1;
		}
	}

	scrolltocursor();
}

handlefindkey(key: int)
{
	case key {
	'\n' =>
		doc.findmode = 0;
		doc.searchstr = doc.findbuf;
		findnext();
	Kesc =>
		doc.findmode = 0;
	Kbs =>
		if(len doc.findbuf > 0)
			doc.findbuf = doc.findbuf[0:len doc.findbuf-1];
	* =>
		if(key >= 16r20)
			doc.findbuf[len doc.findbuf] = key;
	}
}

# ---------- Buffer manipulation ----------

insertchar(c: int)
{
	s := "";
	s[0] = c;
	pushundo(UndoInsert, doc.curline, doc.curcol, s);
	if(doc.curcol >= len doc.lines[doc.curline])
		doc.lines[doc.curline] += s;
	else
		doc.lines[doc.curline] = doc.lines[doc.curline][0:doc.curcol] + s + doc.lines[doc.curline][doc.curcol:];
	doc.curcol++;
}

insertstring(s: string)
{
	for(i := 0; i < len s; i++) {
		if(s[i] == '\n') {
			rest := "";
			if(doc.curcol < len doc.lines[doc.curline])
				rest = doc.lines[doc.curline][doc.curcol:];
			doc.lines[doc.curline] = doc.lines[doc.curline][0:doc.curcol];
			insertline(doc.curline+1, rest);
			doc.curline++;
			doc.curcol = 0;
		} else {
			if(doc.curcol >= len doc.lines[doc.curline])
				doc.lines[doc.curline] += s[i:i+1];
			else
				doc.lines[doc.curline] = doc.lines[doc.curline][0:doc.curcol] + s[i:i+1] + doc.lines[doc.curline][doc.curcol:];
			doc.curcol++;
		}
	}
}

insertline(at: int, s: string)
{
	growbuf();
	for(i := doc.nlines; i > at; i--)
		doc.lines[i] = doc.lines[i-1];
	doc.lines[at] = s;
	doc.nlines++;
}

deleteline(at: int)
{
	for(i := at; i < doc.nlines - 1; i++)
		doc.lines[i] = doc.lines[i+1];
	doc.lines[doc.nlines-1] = "";
	doc.nlines--;
	if(doc.nlines == 0) {
		doc.lines[0] = "";
		doc.nlines = 1;
	}
}

growbuf()
{
	if(doc.nlines >= len doc.lines) {
		newlines := array[len doc.lines * 2] of string;
		newlines[0:] = doc.lines;
		doc.lines = newlines;
	}
}

fixcol()
{
	if(doc.curcol > len doc.lines[doc.curline])
		doc.curcol = len doc.lines[doc.curline];
}

scrolltocursor()
{
	if(vislines <= 0)
		return;
	if(doc.curline < doc.topline)
		doc.topline = doc.curline;
	else if(doc.curline >= doc.topline + vislines)
		doc.topline = doc.curline - vislines + 1;
}

# ---------- Selection ----------

selectall()
{
	doc.selactive = 1;
	doc.selstartline = 0;
	doc.selstartcol = 0;
	doc.selendline = doc.nlines - 1;
	doc.selendcol = len doc.lines[doc.nlines - 1];
	doc.curline = doc.selendline;
	doc.curcol = doc.selendcol;
}

getsel(): (int, int, int, int)
{
	if(!doc.selactive)
		return (0, 0, 0, 0);
	sl := doc.selstartline;
	sc := doc.selstartcol;
	el := doc.selendline;
	ec := doc.selendcol;
	if(sl > el || (sl == el && sc > ec)) {
		(sl, el) = (el, sl);
		(sc, ec) = (ec, sc);
	}
	return (sl, sc, el, ec);
}

getseltext(): string
{
	(sl, sc, el, ec) := getsel();
	if(!doc.selactive)
		return "";
	if(sl == el)
		return doc.lines[sl][sc:ec];
	s := doc.lines[sl][sc:];
	for(i := sl + 1; i < el; i++)
		s += "\n" + doc.lines[i];
	s += "\n" + doc.lines[el][0:ec];
	return s;
}

deletesel(): int
{
	if(!doc.selactive)
		return 0;
	(sl, sc, el, ec) := getsel();
	if(sl == el) {
		doc.lines[sl] = doc.lines[sl][0:sc] + doc.lines[sl][ec:];
	} else {
		doc.lines[sl] = doc.lines[sl][0:sc] + doc.lines[el][ec:];
		for(i := sl + 1; i <= el; i++)
			deleteline(sl + 1);
	}
	doc.curline = sl;
	doc.curcol = sc;
	doc.selactive = 0;
	doc.dirty = 1;
	return 1;
}

docopy()
{
	s := getseltext();
	if(s != "") {
		doc.snarf = s;
		wmclient->snarfput(s);
	}
}

docut()
{
	docopy();
	deletesel();
}

dopaste()
{
	buf := wmclient->snarfget();
	if(buf != "")
		doc.snarf = buf;
	if(doc.snarf != "") {
		deletesel();
		insertstring(doc.snarf);
		doc.dirty = 1;
	}
}

# ---------- Undo ----------

pushundo(kind, line, col: int, text: string)
{
	if(doc.undocount >= MAXUNDO) {
		for(i := 0; i < MAXUNDO - 1; i++)
			doc.undostack[i] = doc.undostack[i+1];
		doc.undocount = MAXUNDO - 1;
	}
	doc.undostack[doc.undocount] = ref Undo(kind, line, col, text, "");
	doc.undocount++;
}

doundo()
{
	if(doc.undocount <= 0)
		return;
	doc.undocount--;
	u := doc.undostack[doc.undocount];
	case u.kind {
	UndoInsert =>
		doc.lines[u.line] = doc.lines[u.line][0:u.col] + doc.lines[u.line][u.col + len u.text:];
		doc.curline = u.line;
		doc.curcol = u.col;
	UndoDelete =>
		doc.lines[u.line] = doc.lines[u.line][0:u.col] + u.text + doc.lines[u.line][u.col:];
		doc.curline = u.line;
		doc.curcol = u.col + len u.text;
	UndoJoinLine =>
		rest := doc.lines[u.line][u.col:];
		doc.lines[u.line] = doc.lines[u.line][0:u.col];
		insertline(u.line + 1, rest);
		doc.curline = u.line + 1;
		doc.curcol = 0;
	UndoSplitLine =>
		if(u.line + 1 < doc.nlines) {
			doc.lines[u.line] += doc.lines[u.line + 1];
			deleteline(u.line + 1);
		}
		doc.curline = u.line;
		doc.curcol = u.col;
	}
	doc.dirty = 1;
}

# ---------- Find ----------

startfind()
{
	doc.findmode = 1;
	doc.findbuf = doc.searchstr;
}

findnext()
{
	if(doc.searchstr == "")
		return;
	for(line := doc.curline; line < doc.nlines; line++) {
		startcol := 0;
		if(line == doc.curline)
			startcol = doc.curcol + 1;
		idx := strindex(doc.lines[line], doc.searchstr, startcol);
		if(idx >= 0) {
			doc.curline = line;
			doc.curcol = idx;
			doc.selactive = 1;
			doc.selstartline = line;
			doc.selstartcol = idx;
			doc.selendline = line;
			doc.selendcol = idx + len doc.searchstr;
			scrolltocursor();
			return;
		}
	}
	for(line = 0; line <= doc.curline; line++) {
		idx := strindex(doc.lines[line], doc.searchstr, 0);
		if(idx >= 0) {
			doc.curline = line;
			doc.curcol = idx;
			doc.selactive = 1;
			doc.selstartline = line;
			doc.selstartcol = idx;
			doc.selendline = line;
			doc.selendcol = idx + len doc.searchstr;
			scrolltocursor();
			return;
		}
	}
}

strindex(s, sub: string, start: int): int
{
	if(len sub == 0 || len s == 0)
		return -1;
	for(i := start; i <= len s - len sub; i++) {
		if(s[i:i+len sub] == sub)
			return i;
	}
	return -1;
}

# ---------- File I/O ----------

loadfile(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return;

	(ok, d) := sys->fstat(fd);
	if(ok < 0)
		return;
	if(d.mode & Sys->DMDIR)
		return;

	BLEN: con 8192;
	buf := array[BLEN + Sys->UTFmax] of byte;
	content := "";
	inset := 0;
	for(;;) {
		n := sys->read(fd, buf[inset:], BLEN);
		if(n <= 0)
			break;
		n += inset;
		nutf := sys->utfbytes(buf, n);
		content += string buf[0:nutf];
		inset = n - nutf;
		buf[0:] = buf[nutf:n];
	}

	doc.nlines = 0;
	start := 0;
	for(i := 0; i < len content; i++) {
		if(content[i] == '\n') {
			growbuf();
			doc.lines[doc.nlines] = content[start:i];
			doc.nlines++;
			start = i + 1;
		}
	}
	growbuf();
	if(start < len content)
		doc.lines[doc.nlines] = content[start:];
	else
		doc.lines[doc.nlines] = "";
	doc.nlines++;

	doc.curline = 0;
	doc.curcol = 0;
	doc.topline = 0;
	doc.dirty = 0;
}

dosave()
{
	if(doc.filepath == "")
		return;
	savefile(doc.filepath);
}

savefile(path: string): int
{
	fd := sys->create(path, Sys->OWRITE, 8r664);
	if(fd == nil)
		return 0;

	for(i := 0; i < doc.nlines; i++) {
		data := array of byte doc.lines[i];
		sys->write(fd, data, len data);
		if(i < doc.nlines - 1) {
			nl := array of byte "\n";
			sys->write(fd, nl, len nl);
		}
	}

	doc.dirty = 0;
	w.settitle(titlestr());
	postevent("save " + doc.filepath);
	return 1;
}

checkdirty(): int
{
	if(!doc.dirty)
		return 1;
	if(doc.filepath != "") {
		savefile(doc.filepath);
		return 1;
	}
	return 1;
}

# ---------- Tab expansion ----------

expandtabs(s: string): string
{
	result := "";
	col := 0;
	for(i := 0; i < len s; i++) {
		if(s[i] == '\t') {
			spaces := TABSTOP - (col % TABSTOP);
			for(j := 0; j < spaces; j++) {
				result[len result] = ' ';
				col++;
			}
		} else {
			result[len result] = s[i];
			col++;
		}
	}
	return result;
}

unexpandcol(s: string, expcol: int): int
{
	col := 0;
	ecol := 0;
	for(i := 0; i < len s && ecol < expcol; i++) {
		if(s[i] == '\t') {
			spaces := TABSTOP - (col % TABSTOP);
			ecol += spaces;
			col += spaces;
		} else {
			ecol++;
			col++;
		}
		if(ecol >= expcol)
			return i + 1;
	}
	return len s;
}

expandedcol(s: string, col: int): int
{
	ecol := 0;
	for(i := 0; i < col && i < len s; i++) {
		if(s[i] == '\t')
			ecol += TABSTOP - (ecol % TABSTOP);
		else
			ecol++;
	}
	return ecol;
}

# ---------- Drawing ----------

redraw()
{
	if(w.image == nil)
		return;

	screen := w.image;
	r := screen.r;
	statusheight := font.height + MARGIN * 2;

	screen.draw(r, bgcolor, nil, Point(0, 0));

	textr := textrect();
	maxvrows := 1;
	if(font.height > 0)
		maxvrows = textr.dy() / font.height;

	drawscrollbar(screen, Rect((r.min.x, r.min.y), (r.min.x + SCROLLW, r.max.y - statusheight)));

	y := textr.min.y;
	vrow := 0;
	for(i := doc.topline; i < doc.nlines && vrow < maxvrows; i++) {
		lns := string (i + 1);
		lnw := font.width(lns);
		screen.text(Point(r.min.x + SCROLLW + LNWIDTH - MARGIN - lnw, y), lncolor, Point(0, 0), font, lns);

		expanded := expandtabs(doc.lines[i]);
		start := 0;
		first := 1;
		while((start < len expanded || first) && vrow < maxvrows) {
			first = 0;
			k := wrapend(expanded, start, textr.dx());
			chunk := expanded[start:k];
			if(doc.selactive)
				drawselectionchunk(screen, i, expanded, start, k, textr.min.x, y);
			screen.text(Point(textr.min.x, y), fgcolor, Point(0, 0), font, chunk);
			y += font.height;
			vrow++;
			start = k;
		}
	}
	vislines = maxvrows;

	drawcursor(1);
	drawstatus(screen, Rect((r.min.x, r.max.y - statusheight), r.max));
	screen.flush(Draw->Flushnow);
}

drawscrollbar(screen: ref Image, r: Rect)
{
	screen.draw(r, statusbgcolor, nil, Point(0, 0));

	if(doc.nlines <= 0 || vislines <= 0)
		return;

	totalh := r.dy();
	thumbh := (vislines * totalh) / doc.nlines;
	if(thumbh < 10)
		thumbh = 10;
	if(thumbh > totalh)
		thumbh = totalh;
	thumby := r.min.y;
	if(doc.nlines > vislines)
		thumby = r.min.y + (doc.topline * (totalh - thumbh)) / (doc.nlines - vislines);

	thumbr := Rect((r.min.x + 2, thumby), (r.max.x - 2, thumby + thumbh));
	screen.draw(thumbr, lncolor, nil, Point(0, 0));
}

drawselection(screen: ref Image, line, textx, y: int)
{
	(sl, sc, el, ec) := getsel();
	if(line < sl || line > el)
		return;

	expanded := expandtabs(doc.lines[line]);
	startx := textx;
	endx := textx + font.width(expanded);

	if(line == sl) {
		ecol := expandedcol(doc.lines[line], sc);
		prefix := "";
		if(ecol <= len expanded)
			prefix = expanded[0:ecol];
		startx = textx + font.width(prefix);
	}
	if(line == el) {
		ecol := expandedcol(doc.lines[line], ec);
		prefix := "";
		if(ecol <= len expanded)
			prefix = expanded[0:ecol];
		endx = textx + font.width(prefix);
	}

	selr := Rect((startx, y), (endx, y + font.height));
	screen.draw(selr, selcolor, nil, Point(0, 0));
}

drawcursor(vis: int)
{
	if(w.image == nil)
		return;
	if(doc.curline < doc.topline)
		return;

	textr := textrect();
	maxw := textr.dx();

	# Walk visual rows from topline to find y for curline
	y := textr.min.y;
	for(i := doc.topline; i < doc.curline; i++) {
		expanded := expandtabs(doc.lines[i]);
		start := 0;
		first := 1;
		while(start < len expanded || first) {
			first = 0;
			k := wrapend(expanded, start, maxw);
			y += font.height;
			if(y >= textr.max.y)
				return;
			start = k;
		}
	}
	if(y >= textr.max.y)
		return;

	# Find which wrapped chunk of curline contains the cursor
	expanded := expandtabs(doc.lines[doc.curline]);
	ecol := expandedcol(doc.lines[doc.curline], doc.curcol);
	start := 0;
	first := 1;
	while(start < len expanded || first) {
		first = 0;
		k := wrapend(expanded, start, maxw);
		if(ecol >= start && (ecol < k || k >= len expanded)) {
			x := textr.min.x + font.width(expanded[start:ecol]);
			col := cursorcolor;
			if(!vis)
				col = bgcolor;
			w.image.line(Point(x, y), Point(x, y + font.height - 1), 0, 0, 0, col, Point(0, 0));
			w.image.flush(Draw->Flushnow);
			return;
		}
		y += font.height;
		if(y >= textr.max.y)
			return;
		start = k;
	}
}

drawstatus(screen: ref Image, r: Rect)
{
	screen.draw(r, statusbgcolor, nil, Point(0, 0));
	screen.line(Point(r.min.x, r.min.y), Point(r.max.x, r.min.y), 0, 0, 0, lncolor, Point(0, 0));

	x := r.min.x + MARGIN;
	y := r.min.y + MARGIN;

	if(doc.findmode) {
		prompt := "Find: " + doc.findbuf + "_";
		screen.text(Point(x, y), fgcolor, Point(0, 0), font, prompt);
	} else {
		info := doc.filepath;
		if(info == "")
			info = "(new file)";
		if(doc.dirty) {
			screen.text(Point(x, y), dirtycolor, Point(0, 0), font, info + " [modified]");
		} else {
			screen.text(Point(x, y), statusfgcolor, Point(0, 0), font, info);
		}

		pos := sys->sprint("Ln %d, Col %d  (%d lines)", doc.curline + 1, doc.curcol + 1, doc.nlines);
		pw := font.width(pos);
		screen.text(Point(r.max.x - pw - MARGIN, y), statusfgcolor, Point(0, 0), font, pos);
	}
}

# ---------- Helpers ----------

timer(c: chan of int, ms: int)
{
	for(;;) {
		sys->sleep(ms);
		c <-= 1;
	}
}

postnote(t: int, pid: int, note: string): int
{
	fd := sys->open("#p/" + string pid + "/ctl", Sys->OWRITE);
	if(fd == nil)
		return -1;
	if(t == 1)
		note += "grp";
	sys->fprint(fd, "%s", note);
	fd = nil;
	return 0;
}

splitfirst(s: string): (string, string)
{
	# Strip leading whitespace
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n'))
		i++;
	s = s[i:];
	# Find first space
	for(j := 0; j < len s; j++) {
		if(s[j] == ' ' || s[j] == '\t') {
			rest := s[j+1:];
			# Strip leading whitespace from rest
			k := 0;
			while(k < len rest && (rest[k] == ' ' || rest[k] == '\t'))
				k++;
			return (s[0:j], rest[k:]);
		}
	}
	return (s, "");
}

readf(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	s := string buf[0:n];
	# Strip trailing newline
	while(len s > 0 && s[len s - 1] == '\n')
		s = s[0:len s - 1];
	return s;
}

# ---------- Word wrap helpers ----------

# wrapend returns the end index (exclusive) of the next wrapped visual chunk
# starting at position start in expanded string, fitting within maxpx pixels.
wrapend(expanded: string, start, maxpx: int): int
{
	if(start >= len expanded)
		return len expanded;
	w2 := 0;
	k := start;
	while(k < len expanded) {
		cw := font.width(expanded[k:k+1]);
		if(w2 + cw > maxpx)
			break;
		w2 += cw;
		k++;
	}
	if(k == start)
		k++;		# guarantee at least one char (very wide char edge case)
	return k;
}

# drawselectionchunk draws the selection highlight for one visual chunk [cs,ce)
# of logical line `line`, where expanded is the tab-expanded line string.
drawselectionchunk(screen: ref Image, line: int, expanded: string, cs, ce, textx, y: int)
{
	(sl, sc, el, ec) := getsel();
	if(line < sl || line > el)
		return;

	selstart_ex := 0;
	if(line == sl)
		selstart_ex = expandedcol(doc.lines[line], sc);
	selend_ex := len expanded;
	if(line == el)
		selend_ex = expandedcol(doc.lines[line], ec);

	# Clip to this chunk
	cselstart := selstart_ex;
	if(cselstart < cs)
		cselstart = cs;
	cselend := selend_ex;
	if(cselend > ce)
		cselend = ce;
	if(cselstart >= cselend)
		return;

	startx := textx + font.width(expanded[cs:cselstart]);
	endx   := textx + font.width(expanded[cs:cselend]);
	selr := Rect((startx, y), (endx, y + font.height));
	screen.draw(selr, selcolor, nil, Point(0, 0));
}

# ---------- Real-file IPC helpers ----------
# /tmp/veltro/edit/ is inside the restricted agent namespace.
# The tick loop polls command files and writes state files so the
# Veltro luciedit tool can read/write the editor across namespace forks.

initeditdir()
{
	mkdirq(EDIT_DIR);
	mkdirq(EDIT_INST);
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

writeeditstate()
{
	body := getbodytext();
	writestatefile(EDIT_INST + "/body", body);
	addr := sys->sprint("%d %d", doc.curline + 1, doc.curcol + 1);
	writestatefile(EDIT_INST + "/addr", addr);
	idx := sys->sprint("%d %s %d\n", doc.id, doc.filepath, doc.dirty);
	writestatefile(EDIT_DIR + "/index", idx);
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
	changed := 0;

	# Global ctl: open <path>, quit
	gcmd := readrmfile(EDIT_DIR + "/ctl");
	if(gcmd != nil && gcmd != "") {
		handlegctl(gcmd);
		changed = 1;
	}

	# Per-doc ctl: save, goto <n>, find <s>, name <p>, insert, delete
	dcmd := readrmfile(EDIT_INST + "/ctl");
	if(dcmd != nil && dcmd != "") {
		handledocctl(dcmd);
		changed = 1;
	}

	# body.in: replace document body
	newbody := readrmfile(EDIT_INST + "/body.in");
	if(newbody != nil) {
		setbodytext(newbody);
		changed = 1;
	}

	return changed;
}

readrmfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[65536] of byte;
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
		s = s[0:len s - 1];
	return s;
}
