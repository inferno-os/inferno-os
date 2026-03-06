implement WmEdit;

#
# wm/edit - Draw-based text editor for Inferno
#
# A simple text editor that uses wmclient and the Draw module directly,
# with no Tk dependency. Can run under Lucifer's wmsrv or any window
# manager that provides a Draw->Context.
#
# Usage:
#   wm/edit [file]
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

include "menuhit.m";
	menuhit: Menuhit;
	Menu, Mousectl: import menuhit;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "string.m";
	str: String;

WmEdit: module
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

# Editor state
lines: array of string;	# text buffer (one string per line)
nlines: int;			# number of lines in use
curline: int;			# cursor line (0-indexed)
curcol: int;			# cursor column (0-indexed)
topline: int;			# first visible line
dirty: int;			# file modified flag
filepath: string;		# current file path
vislines: int;			# number of visible text lines

# Selection state
selactive: int;			# selection in progress
selstartline: int;
selstartcol: int;
selendline: int;
selendcol: int;

# Undo state
MAXUNDO: con 100;
UndoInsert, UndoDelete, UndoReplace, UndoJoinLine, UndoSplitLine: con iota;
Undo: adt {
	kind: int;
	line: int;
	col: int;
	text: string;		# for delete: what was deleted; for insert: what was inserted
	oldtext: string;	# for replace: previous content
};
undostack: array of ref Undo;
undocount: int;

# Find state
searchstr: string;
findmode: int;			# 1 = typing search string in status bar
findbuf: string;

# Snarf buffer
snarf: string;

# Display resources
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

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;
	menuhit = load Menuhit Menuhit->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;

	if(ctxt == nil) {
		sys->fprint(sys->fildes(2), "wm/edit: no window context\n");
		raise "fail:no context";
	}

	sys->pctl(Sys->NEWPGRP, nil);
	wmclient->init();

	# Initialize buffer
	lines = array[1024] of string;
	lines[0] = "";
	nlines = 1;
	curline = 0;
	curcol = 0;
	topline = 0;
	dirty = 0;
	filepath = "";
	selactive = 0;
	undostack = array[MAXUNDO] of ref Undo;
	undocount = 0;
	searchstr = "";
	findmode = 0;
	snarf = "";

	# Parse args
	argv = tl argv;
	if(argv != nil)
		filepath = hd argv;

	# Create window
	sys->sleep(100);
	w = wmclient->window(ctxt, titlestr(), Wmclient->Appl);
	display = w.display;

	# Load font - try monospace first
	font = Font.open(display, "/fonts/dejavu/DejaVuSansMono/unicode.14.font");
	if(font == nil)
		font = Font.open(display, "/fonts/10646/9x15/9x15.font");
	if(font == nil)
		font = Font.open(display, "*default*");
	if(font == nil) {
		sys->fprint(sys->fildes(2), "wm/edit: cannot load any font\n");
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
	if(filepath != "")
		loadfile(filepath);

	# Set up window
	w.reshape(Rect((0, 0), (640, 480)));
	w.startinput("kbd" :: "ptr" :: nil);
	w.onscreen(nil);

	menuhit->init(w);
	menu := ref Menu(array[] of {"save", "find", "goto line", "select all", "cut", "copy", "paste", "exit"}, nil, 0);

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
	key := <-w.ctxt.kbd =>
		cursorvis = 1;
		if(findmode)
			handlefindkey(key);
		else
			handlekey(key);
		redraw();
	p := <-w.ctxt.ptr =>
		if(!w.pointer(*p)) {
			if(p.buttons & 4) {
				# Button 3 - context menu
				mc := ref Mousectl(w.ctxt.ptr, p.buttons, p.xy, p.msec);
				n := menuhit->menuhit(p.buttons, mc, menu, nil);
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
				# Button 2 - paste
				buf := wmclient->snarfget();
				if(buf != "")
					snarf = buf;
				if(snarf != "") {
					insertstring(snarf);
					dirty = 1;
				}
				redraw();
			} else if(p.buttons & 1) {
				# Button 1 - click to position cursor / start selection
				(ml, mc2) := pos2cursor(p.xy);
				curline = ml;
				curcol = mc2;
				selactive = 0;
				selstartline = ml;
				selstartcol = mc2;
				mousedown = 1;
				redraw();
			} else if(mousedown) {
				# Button release - end selection
				(ml, mc2) := pos2cursor(p.xy);
				if(ml != selstartline || mc2 != selstartcol) {
					selactive = 1;
					selendline = ml;
					selendcol = mc2;
					curline = ml;
					curcol = mc2;
				}
				mousedown = 0;
				redraw();
			}
		}
	<-ticks =>
		cursorvis = !cursorvis;
		drawcursor(cursorvis);
	}
}

titlestr(): string
{
	s := "Edit";
	if(filepath != "")
		s += " " + filepath;
	else
		s += " (new)";
	if(dirty)
		s += " *";
	return s;
}

# Convert screen position to buffer line,col
pos2cursor(p: Point): (int, int)
{
	if(w.image == nil)
		return (curline, curcol);

	textr := textrect();
	y := p.y - textr.min.y;
	line := topline + y / font.height;
	if(line < 0)
		line = 0;
	if(line >= nlines)
		line = nlines - 1;

	# Find column from x position
	x := p.x - textr.min.x;
	col := 0;
	if(line < nlines) {
		s := expandtabs(lines[line]);
		w2 := 0;
		for(col = 0; col < len s; col++) {
			cw := font.width(s[col:col+1]);
			if(w2 + cw/2 > x)
				break;
			w2 += cw;
		}
		# Map back from expanded position to real position
		col = unexpandcol(lines[line], col);
	}
	return (line, col);
}

# Compute the text area rectangle (excluding status bar, line numbers, scrollbar)
textrect(): Rect
{
	if(w.image == nil)
		return Rect((0,0),(0,0));
	r := w.image.r;
	statusheight := font.height + MARGIN * 2;
	return Rect((r.min.x + SCROLLW + LNWIDTH, r.min.y + MARGIN),
		    (r.max.x - MARGIN, r.max.y - statusheight));
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
		if(curcol > 0) {
			pushundo(UndoDelete, curline, curcol-1, lines[curline][curcol-1:curcol]);
			lines[curline] = lines[curline][0:curcol-1] + lines[curline][curcol:];
			curcol--;
			dirty = 1;
		} else if(curline > 0) {
			# Join with previous line
			pushundo(UndoJoinLine, curline-1, len lines[curline-1], lines[curline]);
			curcol = len lines[curline-1];
			lines[curline-1] += lines[curline];
			deleteline(curline);
			curline--;
			dirty = 1;
		}
	Kdel =>
		deletesel();
		if(curcol < len lines[curline]) {
			pushundo(UndoDelete, curline, curcol, lines[curline][curcol:curcol+1]);
			lines[curline] = lines[curline][0:curcol] + lines[curline][curcol+1:];
			dirty = 1;
		} else if(curline < nlines - 1) {
			# Join with next line
			pushundo(UndoJoinLine, curline, len lines[curline], lines[curline+1]);
			lines[curline] += lines[curline+1];
			deleteline(curline+1);
			dirty = 1;
		}
	'\n' =>
		deletesel();
		# Split line at cursor
		rest := "";
		if(curcol < len lines[curline])
			rest = lines[curline][curcol:];
		pushundo(UndoSplitLine, curline, curcol, "");
		lines[curline] = lines[curline][0:curcol];
		insertline(curline+1, rest);
		curline++;
		curcol = 0;
		dirty = 1;
	'\t' =>
		deletesel();
		insertchar('\t');
		dirty = 1;
	Kup =>
		if(curline > 0) {
			curline--;
			fixcol();
		}
		selactive = 0;
	Kdown =>
		if(curline < nlines - 1) {
			curline++;
			fixcol();
		}
		selactive = 0;
	Kleft =>
		if(curcol > 0)
			curcol--;
		else if(curline > 0) {
			curline--;
			curcol = len lines[curline];
		}
		selactive = 0;
	Kright =>
		if(curcol < len lines[curline])
			curcol++;
		else if(curline < nlines - 1) {
			curline++;
			curcol = 0;
		}
		selactive = 0;
	Khome =>
		curcol = 0;
		selactive = 0;
	Kend =>
		curcol = len lines[curline];
		selactive = 0;
	Kpgup =>
		if(vislines > 0) {
			curline -= vislines;
			if(curline < 0)
				curline = 0;
			fixcol();
		}
		selactive = 0;
	Kpgdown =>
		if(vislines > 0) {
			curline += vislines;
			if(curline >= nlines)
				curline = nlines - 1;
			fixcol();
		}
		selactive = 0;
	Kesc =>
		selactive = 0;
	* =>
		if(key >= 16r20 || key == '\t') {
			deletesel();
			insertchar(key);
			dirty = 1;
		}
	}

	# Ensure cursor is visible
	scrolltocursor();
}

handlefindkey(key: int)
{
	case key {
	'\n' =>
		# Execute search
		findmode = 0;
		searchstr = findbuf;
		findnext();
	Kesc =>
		findmode = 0;
	Kbs =>
		if(len findbuf > 0)
			findbuf = findbuf[0:len findbuf-1];
	* =>
		if(key >= 16r20)
			findbuf[len findbuf] = key;
	}
}

insertchar(c: int)
{
	s := "";
	s[0] = c;
	pushundo(UndoInsert, curline, curcol, s);
	if(curcol >= len lines[curline])
		lines[curline] += s;
	else
		lines[curline] = lines[curline][0:curcol] + s + lines[curline][curcol:];
	curcol++;
}

insertstring(s: string)
{
	# Insert possibly multi-line string at cursor
	for(i := 0; i < len s; i++) {
		if(s[i] == '\n') {
			rest := "";
			if(curcol < len lines[curline])
				rest = lines[curline][curcol:];
			lines[curline] = lines[curline][0:curcol];
			insertline(curline+1, rest);
			curline++;
			curcol = 0;
		} else {
			if(curcol >= len lines[curline])
				lines[curline] += s[i:i+1];
			else
				lines[curline] = lines[curline][0:curcol] + s[i:i+1] + lines[curline][curcol:];
			curcol++;
		}
	}
}

insertline(at: int, s: string)
{
	growbuf();
	for(i := nlines; i > at; i--)
		lines[i] = lines[i-1];
	lines[at] = s;
	nlines++;
}

deleteline(at: int)
{
	for(i := at; i < nlines - 1; i++)
		lines[i] = lines[i+1];
	lines[nlines-1] = "";
	nlines--;
	if(nlines == 0) {
		lines[0] = "";
		nlines = 1;
	}
}

growbuf()
{
	if(nlines >= len lines) {
		newlines := array[len lines * 2] of string;
		newlines[0:] = lines;
		lines = newlines;
	}
}

fixcol()
{
	if(curcol > len lines[curline])
		curcol = len lines[curline];
}

scrolltocursor()
{
	if(vislines <= 0)
		return;
	if(curline < topline)
		topline = curline;
	else if(curline >= topline + vislines)
		topline = curline - vislines + 1;
}

# Selection helpers

selectall()
{
	selactive = 1;
	selstartline = 0;
	selstartcol = 0;
	selendline = nlines - 1;
	selendcol = len lines[nlines - 1];
	curline = selendline;
	curcol = selendcol;
}

# Get normalized selection (start before end)
getsel(): (int, int, int, int)
{
	if(!selactive)
		return (0, 0, 0, 0);
	sl := selstartline;
	sc := selstartcol;
	el := selendline;
	ec := selendcol;
	if(sl > el || (sl == el && sc > ec)) {
		(sl, el) = (el, sl);
		(sc, ec) = (ec, sc);
	}
	return (sl, sc, el, ec);
}

getseltext(): string
{
	(sl, sc, el, ec) := getsel();
	if(!selactive)
		return "";
	if(sl == el)
		return lines[sl][sc:ec];
	s := lines[sl][sc:];
	for(i := sl + 1; i < el; i++)
		s += "\n" + lines[i];
	s += "\n" + lines[el][0:ec];
	return s;
}

deletesel(): int
{
	if(!selactive)
		return 0;
	(sl, sc, el, ec) := getsel();
	if(sl == el) {
		lines[sl] = lines[sl][0:sc] + lines[sl][ec:];
	} else {
		lines[sl] = lines[sl][0:sc] + lines[el][ec:];
		for(i := sl + 1; i <= el; i++)
			deleteline(sl + 1);
	}
	curline = sl;
	curcol = sc;
	selactive = 0;
	dirty = 1;
	return 1;
}

docopy()
{
	s := getseltext();
	if(s != "") {
		snarf = s;
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
		snarf = buf;
	if(snarf != "") {
		deletesel();
		insertstring(snarf);
		dirty = 1;
	}
}

# Undo

pushundo(kind, line, col: int, text: string)
{
	if(undocount >= MAXUNDO) {
		# Shift everything down
		for(i := 0; i < MAXUNDO - 1; i++)
			undostack[i] = undostack[i+1];
		undocount = MAXUNDO - 1;
	}
	undostack[undocount] = ref Undo(kind, line, col, text, "");
	undocount++;
}

doundo()
{
	if(undocount <= 0)
		return;
	undocount--;
	u := undostack[undocount];
	case u.kind {
	UndoInsert =>
		# Undo insert: delete the inserted character(s)
		lines[u.line] = lines[u.line][0:u.col] + lines[u.line][u.col + len u.text:];
		curline = u.line;
		curcol = u.col;
	UndoDelete =>
		# Undo delete: re-insert the deleted text
		lines[u.line] = lines[u.line][0:u.col] + u.text + lines[u.line][u.col:];
		curline = u.line;
		curcol = u.col + len u.text;
	UndoJoinLine =>
		# Undo join: split the line again
		rest := lines[u.line][u.col:];
		lines[u.line] = lines[u.line][0:u.col];
		insertline(u.line + 1, rest);
		curline = u.line + 1;
		curcol = 0;
	UndoSplitLine =>
		# Undo split: rejoin the lines
		if(u.line + 1 < nlines) {
			lines[u.line] += lines[u.line + 1];
			deleteline(u.line + 1);
		}
		curline = u.line;
		curcol = u.col;
	}
	dirty = 1;
}

# Find

startfind()
{
	findmode = 1;
	findbuf = searchstr;
}

findnext()
{
	if(searchstr == "")
		return;
	# Search forward from cursor
	for(line := curline; line < nlines; line++) {
		startcol := 0;
		if(line == curline)
			startcol = curcol + 1;
		idx := strindex(lines[line], searchstr, startcol);
		if(idx >= 0) {
			curline = line;
			curcol = idx;
			selactive = 1;
			selstartline = line;
			selstartcol = idx;
			selendline = line;
			selendcol = idx + len searchstr;
			scrolltocursor();
			return;
		}
	}
	# Wrap around from top
	for(line = 0; line <= curline; line++) {
		idx := strindex(lines[line], searchstr, 0);
		if(idx >= 0) {
			curline = line;
			curcol = idx;
			selactive = 1;
			selstartline = line;
			selstartcol = idx;
			selendline = line;
			selendcol = idx + len searchstr;
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

# File I/O

loadfile(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil) {
		# New file - that's ok
		return;
	}

	# Read file
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

	# Parse into lines
	nlines = 0;
	start := 0;
	for(i := 0; i < len content; i++) {
		if(content[i] == '\n') {
			growbuf();
			lines[nlines] = content[start:i];
			nlines++;
			start = i + 1;
		}
	}
	# Last line (may not have trailing newline)
	growbuf();
	if(start < len content)
		lines[nlines] = content[start:];
	else
		lines[nlines] = "";
	nlines++;

	curline = 0;
	curcol = 0;
	topline = 0;
	dirty = 0;
}

dosave()
{
	if(filepath == "") {
		# No file path - can't save (TODO: file dialog)
		return;
	}
	savefile(filepath);
}

savefile(path: string): int
{
	fd := sys->create(path, Sys->OWRITE, 8r664);
	if(fd == nil)
		return 0;

	for(i := 0; i < nlines; i++) {
		data := array of byte lines[i];
		sys->write(fd, data, len data);
		if(i < nlines - 1) {
			nl := array of byte "\n";
			sys->write(fd, nl, len nl);
		}
	}

	dirty = 0;
	w.settitle(titlestr());
	return 1;
}

checkdirty(): int
{
	if(!dirty)
		return 1;
	# TODO: proper dialog - for now just save
	if(filepath != "") {
		savefile(filepath);
		return 1;
	}
	return 1;  # allow quit even if dirty and no path
}

# Tab expansion for display
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

# Map expanded column back to real column
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

# Get the expanded column for a real column
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

# Drawing

redraw()
{
	if(w.image == nil)
		return;

	screen := w.image;
	r := screen.r;
	statusheight := font.height + MARGIN * 2;

	# Clear background
	screen.draw(r, bgcolor, nil, Point(0, 0));

	# Calculate visible lines
	textr := textrect();
	if(font.height > 0)
		vislines = textr.dy() / font.height;
	else
		vislines = 1;

	# Draw scrollbar
	drawscrollbar(screen, Rect((r.min.x, r.min.y), (r.min.x + SCROLLW, r.max.y - statusheight)));

	# Draw text lines
	y := textr.min.y;
	for(i := topline; i < nlines && i < topline + vislines; i++) {
		lnr := Rect((r.min.x + SCROLLW, y), (r.min.x + SCROLLW + LNWIDTH - MARGIN, y + font.height));

		# Line number
		lns := string (i + 1);
		lnw := font.width(lns);
		screen.text(Point(lnr.max.x - lnw, y), lncolor, Point(0, 0), font, lns);

		# Selection highlight
		if(selactive)
			drawselection(screen, i, textr.min.x, y);

		# Text
		expanded := expandtabs(lines[i]);
		screen.text(Point(textr.min.x, y), fgcolor, Point(0, 0), font, expanded);

		y += font.height;
	}

	# Draw cursor
	drawcursor(1);

	# Draw status bar
	drawstatus(screen, Rect((r.min.x, r.max.y - statusheight), r.max));

	screen.flush(Draw->Flushnow);
}

drawscrollbar(screen: ref Image, r: Rect)
{
	# Background
	screen.draw(r, statusbgcolor, nil, Point(0, 0));

	if(nlines <= 0 || vislines <= 0)
		return;

	# Thumb
	totalh := r.dy();
	thumbh := (vislines * totalh) / nlines;
	if(thumbh < 10)
		thumbh = 10;
	if(thumbh > totalh)
		thumbh = totalh;
	thumby := r.min.y;
	if(nlines > vislines)
		thumby = r.min.y + (topline * (totalh - thumbh)) / (nlines - vislines);

	thumbr := Rect((r.min.x + 2, thumby), (r.max.x - 2, thumby + thumbh));
	screen.draw(thumbr, lncolor, nil, Point(0, 0));
}

drawselection(screen: ref Image, line, textx, y: int)
{
	(sl, sc, el, ec) := getsel();
	if(line < sl || line > el)
		return;

	expanded := expandtabs(lines[line]);
	startx := textx;
	endx := textx + font.width(expanded);

	if(line == sl) {
		ecol := expandedcol(lines[line], sc);
		prefix := "";
		if(ecol <= len expanded)
			prefix = expanded[0:ecol];
		startx = textx + font.width(prefix);
	}
	if(line == el) {
		ecol := expandedcol(lines[line], ec);
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
	if(curline < topline || curline >= topline + vislines)
		return;

	textr := textrect();
	y := textr.min.y + (curline - topline) * font.height;

	# Calculate x position from expanded column
	expanded := expandtabs(lines[curline]);
	ecol := expandedcol(lines[curline], curcol);
	prefix := "";
	if(ecol <= len expanded)
		prefix = expanded[0:ecol];
	x := textr.min.x + font.width(prefix);

	# Draw cursor line
	col := cursorcolor;
	if(!vis)
		col = bgcolor;
	w.image.line(Point(x, y), Point(x, y + font.height - 1), 0, 0, 0, col, Point(0, 0));
	w.image.flush(Draw->Flushnow);
}

drawstatus(screen: ref Image, r: Rect)
{
	# Background
	screen.draw(r, statusbgcolor, nil, Point(0, 0));

	# Separator line
	screen.line(Point(r.min.x, r.min.y), Point(r.max.x, r.min.y), 0, 0, 0, lncolor, Point(0, 0));

	x := r.min.x + MARGIN;
	y := r.min.y + MARGIN;

	if(findmode) {
		# Show find prompt
		prompt := "Find: " + findbuf + "_";
		screen.text(Point(x, y), fgcolor, Point(0, 0), font, prompt);
	} else {
		# File info
		info := filepath;
		if(info == "")
			info = "(new file)";
		if(dirty) {
			screen.text(Point(x, y), dirtycolor, Point(0, 0), font, info + " [modified]");
		} else {
			screen.text(Point(x, y), statusfgcolor, Point(0, 0), font, info);
		}

		# Position info on right
		pos := sys->sprint("Ln %d, Col %d  (%d lines)", curline + 1, curcol + 1, nlines);
		pw := font.width(pos);
		screen.text(Point(r.max.x - pw - MARGIN, y), statusfgcolor, Point(0, 0), font, pos);
	}
}

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
