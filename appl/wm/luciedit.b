implement LuciEdit;

#
# luciedit — simple Draw-based text editor for Lucifer
#
# A minimal editor that uses the Draw module directly (no Tk).
# Designed to run as a GUI app in Lucifer's presentation zone.
#
# Usage: luciedit [path]
#   Opens path for editing.  If no path, starts with empty buffer.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Font, Point, Rect, Image, Display, Pointer: import draw;

include "keyboard.m";

include "menu.m";

include "wmclient.m";
	wmclient: Wmclient;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

LuciEdit: module
{
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

# --- Color constants (Lucifer dark palette) ---
COLBG:		con int 16r0D0D0DFF;
COLTEXT:	con int 16rCCCCCCFF;
COLCURSOR:	con int 16rE8553AFF;	# accent orange
COLLINENO:	con int 16r444444FF;
COLSTATUS:	con int 16r0A0A0AFF;
COLSTATTEXT:	con int 16r999999FF;
COLSCROLL:	con int 16r1A1A1AFF;
COLTHUMB:	con int 16r444444FF;

# --- IPC via real files in /tmp/veltro/edit/ (accessible from agent namespace) ---
EDIT_DIR:  con "/tmp/veltro/edit";
EDIT_INST: con "/tmp/veltro/edit/1";

# --- Module state ---
stderr: ref Sys->FD;
display_g: ref Display;
win: ref Wmclient->Window;
mainwin: ref Image;
font: ref Font;
menumod: Menu;
Popup: import menumod;
quitreq := 0;
tickch: chan of int;

# Colors
bgcol: ref Image;
textcol: ref Image;
cursorcol: ref Image;
linenocol: ref Image;
statuscol: ref Image;
stattextcol: ref Image;
scrollcol: ref Image;
thumbcol: ref Image;

# Buffer: array of lines
lines: array of string;
nlines := 0;
MAXLINES: con 65536;

# Cursor position
curline := 0;	# line index
curcol := 0;	# column (byte offset in line)

# Scroll offset (first visible line)
scrolloff := 0;

# File path
filepath := "";
dirty := 0;

# Layout constants
LMARGIN: con 8;		# left margin for line numbers
RMARGIN: con 4;		# right margin
STATUSH: con 20;	# status bar height
SCROLLW: con 12;	# scrollbar width

# Computed layout
linenowidth := 0;	# width of line number column
textx := 0;		# x offset where text starts
vislines := 0;		# number of visible lines

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	stderr = sys->fildes(2);

	wmclient = load Wmclient Wmclient->PATH;
	if(wmclient == nil) {
		sys->fprint(stderr, "luciedit: cannot load wmclient: %r\n");
		return;
	}
	wmclient->init();

	bufio = load Bufio Bufio->PATH;

	# Parse args
	a := args;
	if(a != nil) a = tl a;	# skip program name
	if(a != nil) {
		filepath = hd a;
		a = tl a;
	}

	if(ctxt == nil)
		ctxt = wmclient->makedrawcontext();
	display_g = ctxt.display;

	# Colors
	bgcol = display_g.color(COLBG);
	textcol = display_g.color(COLTEXT);
	cursorcol = display_g.color(COLCURSOR);
	linenocol = display_g.color(COLLINENO);
	statuscol = display_g.color(COLSTATUS);
	stattextcol = display_g.color(COLSTATTEXT);
	scrollcol = display_g.color(COLSCROLL);
	thumbcol = display_g.color(COLTHUMB);

	# Font — prefer monospace
	font = Font.open(display_g, "/fonts/dejavu/DejaVuSansMono/unicode.14.font");
	if(font == nil)
		font = Font.open(display_g, "*default*");

	# Context menu
	menumod = load Menu Menu->PATH;
	if(menumod != nil)
		menumod->init(display_g, font);

	# Init buffer
	lines = array[MAXLINES] of string;
	nlines = 1;
	lines[0] = "";

	# Load file if specified
	if(filepath != "")
		loadfile(filepath);

	# Create window
	win = wmclient->window(ctxt, "Edit", Wmclient->Plain);
	wmclient->win.reshape(((0, 0), (100, 100)));
	wmclient->win.onscreen("max");
	wmclient->win.startinput("kbd" :: "ptr" :: nil);
	mainwin = win.image;

	computelayout();
	redraw();

	# IPC: write initial state and start command-poll ticker
	initeditdir();
	tickch = chan[1] of int;
	spawn tickproc(tickch);

	# Event loop
	for(;;) alt {
	ctl := <-win.ctl or
	ctl = <-win.ctxt.ctl =>
		if(ctl == "exit")
			return;
		wmclient->win.wmctl(ctl);
		if(ctl != nil && ctl[0] == '!') {
			mainwin = win.image;
			computelayout();
			redraw();
		}
	c := <-win.ctxt.kbd =>
		handlekey(c);
	p := <-win.ctxt.ptr =>
		if(!wmclient->win.pointer(*p))
			handleptr(p);
		if(quitreq) return;
	<-tickch =>
		checkctlfile();
	}
}

# --- File I/O ---

loadfile(path: string)
{
	if(bufio == nil)
		return;
	fd := bufio->open(path, Bufio->OREAD);
	if(fd == nil) {
		sys->fprint(stderr, "luciedit: cannot open %s: %r\n", path);
		return;
	}
	nlines = 0;
	for(;;) {
		s := fd.gets('\n');
		if(s == nil)
			break;
		# Strip trailing newline
		if(len s > 0 && s[len s - 1] == '\n')
			s = s[0:len s - 1];
		if(nlines >= MAXLINES)
			break;
		lines[nlines++] = s;
	}
	fd.close();
	if(nlines == 0) {
		nlines = 1;
		lines[0] = "";
	}
	curline = 0;
	curcol = 0;
	scrolloff = 0;
	dirty = 0;
}

savefile(): string
{
	if(filepath == "")
		return "no file path";
	fd := sys->create(filepath, Sys->OWRITE, 8r666);
	if(fd == nil)
		return sys->sprint("cannot create %s: %r", filepath);
	for(i := 0; i < nlines; i++) {
		b := array of byte (lines[i] + "\n");
		if(sys->write(fd, b, len b) < 0)
			return sys->sprint("write error: %r");
	}
	fd = nil;
	dirty = 0;
	return nil;
}

# --- Layout ---

computelayout()
{
	if(mainwin == nil || font == nil)
		return;
	r := mainwin.r;

	# Line number width: enough for max line number
	digits := 1;
	n := nlines;
	while(n >= 10) { digits++; n /= 10; }
	if(digits < 3) digits = 3;
	linenowidth = font.width("0") * digits + LMARGIN * 2;
	textx = r.min.x + linenowidth;

	# Visible lines
	texth := r.dy() - STATUSH;
	if(texth < 0) texth = 0;
	vislines = texth / font.height;
	if(vislines < 1) vislines = 1;
}

# --- Drawing ---

redraw()
{
	if(mainwin == nil || font == nil)
		return;
	r := mainwin.r;

	# Background
	mainwin.draw(r, bgcol, nil, (0, 0));

	# Draw lines
	for(i := 0; i < vislines && scrolloff + i < nlines; i++) {
		li := scrolloff + i;
		y := r.min.y + i * font.height;

		# Line number
		lnostr := string (li + 1);
		lnow := font.width(lnostr);
		lnox := r.min.x + linenowidth - LMARGIN - lnow;
		mainwin.text((lnox, y), linenocol, (0, 0), font, lnostr);

		# Text content
		line := lines[li];
		mainwin.text((textx, y), textcol, (0, 0), font, line);

		# Cursor
		if(li == curline) {
			cc := curcol;
			if(cc > len line) cc = len line;
			prefix := "";
			if(cc > 0 && cc <= len line)
				prefix = line[0:cc];
			cx := textx + font.width(prefix);
			# Draw cursor bar (2px wide)
			cr := Rect((cx, y), (cx + 2, y + font.height));
			mainwin.draw(cr, cursorcol, nil, (0, 0));
		}
	}

	# Scrollbar
	drawscrollbar(r);

	# Status bar
	drawstatus(r);

	mainwin.flush(Draw->Flushnow);

	# Sync state files for IPC
	if(tickch != nil)
		writeeditstate();
}

drawscrollbar(r: Rect)
{
	sbr := Rect((r.max.x - SCROLLW, r.min.y), (r.max.x, r.max.y - STATUSH));
	mainwin.draw(sbr, scrollcol, nil, (0, 0));

	if(nlines <= vislines)
		return;

	# Thumb
	sbh := sbr.dy();
	thumbh := sbh * vislines / nlines;
	if(thumbh < 8) thumbh = 8;
	thumby := sbr.min.y + sbh * scrolloff / nlines;
	if(thumby + thumbh > sbr.max.y)
		thumby = sbr.max.y - thumbh;
	tr := Rect((sbr.min.x + 2, thumby), (sbr.max.x - 2, thumby + thumbh));
	mainwin.draw(tr, thumbcol, nil, (0, 0));
}

drawstatus(r: Rect)
{
	sr := Rect((r.min.x, r.max.y - STATUSH), r.max);
	mainwin.draw(sr, statuscol, nil, (0, 0));

	if(font == nil)
		return;

	y := sr.min.y + (STATUSH - font.height) / 2;
	status := "";
	if(filepath != "")
		status = filepath;
	else
		status = "[new]";
	if(dirty)
		status += " [modified]";
	status += sys->sprint("  Ln %d, Col %d", curline + 1, curcol + 1);

	mainwin.text((sr.min.x + 8, y), stattextcol, (0, 0), font, status);
}

# --- Keyboard handling ---

handlekey(c: int)
{
	case c {
	# Ctrl+S: save
	16r13 =>
		err := savefile();
		if(err != nil)
			sys->fprint(stderr, "luciedit: save: %s\n", err);
		redraw();
		return;

	# Ctrl+Q: quit
	16r11 =>
		return;

	# Backspace
	'\b' or 16r7f =>
		if(curcol > 0) {
			line := lines[curline];
			lines[curline] = line[0:curcol-1] + line[curcol:];
			curcol--;
			dirty = 1;
		} else if(curline > 0) {
			# Join with previous line
			prev := lines[curline - 1];
			curcol = len prev;
			lines[curline - 1] = prev + lines[curline];
			deleteline(curline);
			curline--;
			dirty = 1;
		}
		redraw();

	# Enter
	'\n' or '\r' =>
		line := lines[curline];
		rest := "";
		if(curcol < len line)
			rest = line[curcol:];
		lines[curline] = line[0:curcol];
		insertline(curline + 1, rest);
		curline++;
		curcol = 0;
		dirty = 1;
		ensurevisible();
		redraw();

	# Tab
	'\t' =>
		insertchar('\t');
		redraw();

	# Arrow keys
	Keyboard->Up =>
		if(curline > 0) {
			curline--;
			clampcolumn();
			ensurevisible();
			redraw();
		}
	Keyboard->Down =>
		if(curline < nlines - 1) {
			curline++;
			clampcolumn();
			ensurevisible();
			redraw();
		}
	Keyboard->Left =>
		if(curcol > 0)
			curcol--;
		else if(curline > 0) {
			curline--;
			curcol = len lines[curline];
			ensurevisible();
		}
		redraw();
	Keyboard->Right =>
		if(curcol < len lines[curline])
			curcol++;
		else if(curline < nlines - 1) {
			curline++;
			curcol = 0;
			ensurevisible();
		}
		redraw();

	# Home
	Keyboard->Home =>
		curcol = 0;
		redraw();

	# End
	Keyboard->End =>
		curcol = len lines[curline];
		redraw();

	# Page Up
	Keyboard->Pgup =>
		curline -= vislines;
		if(curline < 0) curline = 0;
		scrolloff -= vislines;
		if(scrolloff < 0) scrolloff = 0;
		clampcolumn();
		redraw();

	# Page Down
	Keyboard->Pgdown =>
		curline += vislines;
		if(curline >= nlines) curline = nlines - 1;
		scrolloff += vislines;
		if(scrolloff > nlines - vislines)
			scrolloff = nlines - vislines;
		if(scrolloff < 0) scrolloff = 0;
		clampcolumn();
		redraw();

	# Delete (Ctrl+D or Del key)
	16r04 or Keyboard->Del =>
		line := lines[curline];
		if(curcol < len line) {
			lines[curline] = line[0:curcol] + line[curcol+1:];
			dirty = 1;
		} else if(curline < nlines - 1) {
			# Join with next line
			lines[curline] = line + lines[curline + 1];
			deleteline(curline + 1);
			dirty = 1;
		}
		redraw();

	* =>
		# Printable character
		if(c >= 16r20 && c != 16r7f) {
			insertchar(c);
			redraw();
		}
	}
}

insertchar(c: int)
{
	line := lines[curline];
	ch := "";
	ch[0] = c;
	lines[curline] = line[0:curcol] + ch + line[curcol:];
	curcol++;
	dirty = 1;
}

# --- Line operations ---

insertline(at: int, s: string)
{
	if(nlines >= MAXLINES)
		return;
	# Shift lines down
	for(i := nlines; i > at; i--)
		lines[i] = lines[i - 1];
	lines[at] = s;
	nlines++;
}

deleteline(at: int)
{
	if(nlines <= 1)
		return;
	for(i := at; i < nlines - 1; i++)
		lines[i] = lines[i + 1];
	lines[nlines - 1] = nil;
	nlines--;
}

# --- Cursor helpers ---

clampcolumn()
{
	if(curline >= 0 && curline < nlines) {
		if(curcol > len lines[curline])
			curcol = len lines[curline];
	}
}

ensurevisible()
{
	if(curline < scrolloff)
		scrolloff = curline;
	else if(curline >= scrolloff + vislines)
		scrolloff = curline - vislines + 1;
	if(scrolloff < 0)
		scrolloff = 0;
}

# --- Mouse handling ---

handleptr(p: ref Pointer)
{
	if(mainwin == nil || font == nil)
		return;
	r := mainwin.r;

	# Right-click: context menu
	if(p.buttons == 4 && menumod != nil) {
		items := array[] of {"Save", "Close"};
		pop := menumod->new(items);
		n := pop.show(mainwin, p.xy, win.ctxt.ptr);
		case n {
		0 =>
			err := savefile();
			if(err != nil)
				sys->fprint(stderr, "luciedit: save: %s\n", err);
			redraw();
		1 =>
			quitreq = 1;
		}
		return;
	}

	# Scrollbar click
	sbr := Rect((r.max.x - SCROLLW, r.min.y), (r.max.x, r.max.y - STATUSH));
	if(sbr.contains(p.xy) && (p.buttons & 1)) {
		# Click in scrollbar: jump to proportional position
		frac := p.xy.y - sbr.min.y;
		total := sbr.dy();
		if(total > 0) {
			scrolloff = nlines * frac / total;
			if(scrolloff > nlines - vislines)
				scrolloff = nlines - vislines;
			if(scrolloff < 0)
				scrolloff = 0;
			redraw();
		}
		return;
	}

	# Scroll wheel (button 4 = scroll up, button 8 = scroll down)
	if(p.buttons & 8) {
		scrolloff += 3;
		if(scrolloff > nlines - vislines)
			scrolloff = nlines - vislines;
		if(scrolloff < 0) scrolloff = 0;
		redraw();
		return;
	}
	if(p.buttons & 16) {
		scrolloff -= 3;
		if(scrolloff < 0) scrolloff = 0;
		redraw();
		return;
	}

	# Text area click: set cursor
	if((p.buttons & 1) && p.xy.x >= textx && p.xy.x < r.max.x - SCROLLW &&
			p.xy.y >= r.min.y && p.xy.y < r.max.y - STATUSH) {
		# Line
		clickline := scrolloff + (p.xy.y - r.min.y) / font.height;
		if(clickline >= nlines)
			clickline = nlines - 1;
		if(clickline < 0)
			clickline = 0;
		curline = clickline;

		# Column — find character position from x coordinate
		line := lines[curline];
		clickx := p.xy.x - textx;
		col := 0;
		for(ci := 0; ci < len line; ci++) {
			cw := font.width(line[0:ci+1]);
			if(cw > clickx)
				break;
			col = ci + 1;
		}
		curcol = col;
		redraw();
	}
}

# --- IPC: real-file state export and command poll ---

initeditdir()
{
	mkdirq(EDIT_DIR);
	mkdirq(EDIT_INST);
	writeeditstate();
}

mkdirq(path: string)
{
	(ok, nil) := sys->stat(path);
	if(ok < 0)
		sys->create(path, Sys->OREAD, 8r777|Sys->DMDIR);
}

writeeditstate()
{
	# body: full buffer content
	fd := sys->create(EDIT_INST + "/body", Sys->OWRITE, 8r666);
	if(fd != nil) {
		for(i := 0; i < nlines; i++) {
			line := lines[i];
			if(i < nlines - 1) line += "\n";
			b := array of byte line;
			sys->write(fd, b, len b);
		}
		fd = nil;
	}
	# addr: cursor position as "line col"
	fd = sys->create(EDIT_INST + "/addr", Sys->OWRITE, 8r666);
	if(fd != nil) {
		b := array of byte sys->sprint("%d %d\n", curline + 1, curcol + 1);
		sys->write(fd, b, len b);
		fd = nil;
	}
	# index: status summary
	fd = sys->create(EDIT_DIR + "/index", Sys->OWRITE, 8r666);
	if(fd != nil) {
		path := filepath;
		if(path == "") path = "[new]";
		b := array of byte sys->sprint("file:%s dirty:%d line:%d col:%d lines:%d\n",
			path, dirty, curline + 1, curcol + 1, nlines);
		sys->write(fd, b, len b);
		fd = nil;
	}
}

# tickproc: fires on tickch every 500ms for command polling
tickproc(ch: chan of int)
{
	for(;;) {
		sys->sleep(500);
		alt { ch <-= 1 => ; * => ; }
	}
}

# checkctlfile: called on each tick; processes pending commands
checkctlfile()
{
	# Global ctl: "open path", "quit"
	gctl := readrmfile(EDIT_DIR + "/ctl");
	if(gctl != nil) {
		(op, arg) := splitword(string gctl);
		if(op == "quit" || op == "close") {
			quitreq = 1;
		} else if(op == "open") {
			arg = stripws(arg);
			if(arg != "") {
				filepath = arg;
				loadfile(filepath);
				computelayout();
				redraw();
			}
		}
	}
	if(quitreq) return;

	# Per-instance ctl: "save", "goto N", "find str", "name path", "insert...", "delete..."
	ctl1 := readrmfile(EDIT_INST + "/ctl");
	if(ctl1 != nil) {
		(op, arg) := splitword(string ctl1);
		if(op == "save") {
			savefile();
		} else if(op == "goto") {
			n := int stripws(arg);
			if(n > 0) {
				curline = n - 1;
				if(curline >= nlines) curline = nlines - 1;
				clampcolumn();
				ensurevisible();
			}
			redraw();
		} else if(op == "find") {
			needle := stripws(arg);
			if(needle != "")
				findinbuf(needle);
			redraw();
		} else if(op == "name") {
			filepath = stripws(arg);
			redraw();
		}
		writeeditstate();
	}

	# body.in: replace entire buffer
	body := readrmfile(EDIT_INST + "/body.in");
	if(body != nil) {
		setbodyfromtext(string body);
		computelayout();
		redraw();
		writeeditstate();
	}
}

# readrmfile: read a file and remove it; returns nil if not found
readrmfile(path: string): array of byte
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil) return nil;
	buf := array[65536] of byte;
	total := 0;
	for(;;) {
		n := sys->read(fd, buf[total:], len buf - total);
		if(n <= 0) break;
		total += n;
	}
	fd = nil;
	sys->remove(path);
	if(total <= 0) return nil;
	return buf[0:total];
}

# setbodyfromtext: replace buffer contents with newline-separated text
setbodyfromtext(text: string)
{
	nlines = 0;
	i := 0;
	while(i <= len text) {
		j := i;
		while(j < len text && text[j] != '\n') j++;
		if(nlines < MAXLINES)
			lines[nlines++] = text[i:j];
		i = j + 1;
		if(i > len text) break;
	}
	if(nlines == 0) {
		nlines = 1;
		lines[0] = "";
	}
	curline = 0;
	curcol = 0;
	scrolloff = 0;
	dirty = 1;
}

# findinbuf: search forward for needle, move cursor to first match
findinbuf(needle: string)
{
	nl := len needle;
	for(i := 1; i <= nlines; i++) {
		li := (curline + i) % nlines;
		line := lines[li];
		for(j := 0; j + nl <= len line; j++) {
			if(line[j:j+nl] == needle) {
				curline = li;
				curcol = j;
				clampcolumn();
				ensurevisible();
				return;
			}
		}
	}
}

# splitword: split "word rest" at first whitespace
splitword(s: string): (string, string)
{
	s = stripws(s);
	for(i := 0; i < len s; i++) {
		if(s[i] == ' ' || s[i] == '\t' || s[i] == '\n')
			return (s[0:i], s[i+1:]);
	}
	return (s, "");
}

# stripws: strip leading/trailing whitespace
stripws(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n')) i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\n')) j--;
	if(i >= j) return "";
	return s[i:j];
}
