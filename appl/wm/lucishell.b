implement Lucishell;

#
# lucishell - Draw-based shell terminal with 9P interface
#
# A terminal emulator for the Inferno shell, with a file-based interface
# for read-only access by Veltro agents.  The shell process (/dis/sh.dis)
# communicates via synthetic /dev/cons and /dev/consctl created by file2chan.
#
# Real-file IPC at /tmp/veltro/shell/ for Veltro tool access:
#   /tmp/veltro/shell/body      Current transcript (read-only)
#   /tmp/veltro/shell/input     Current input line
#
# Keyboard:
#   Type to send input to shell
#   Enter        send current line to shell
#   Backspace    delete char before cursor
#   Ctrl-C       send interrupt (DEL) to shell
#   Ctrl-D       send EOF to shell
#   Ctrl-U       clear input line
#   Ctrl-L       clear screen (keep prompt)
#   Up/Down      scroll history
#   Page Up/Down scroll transcript
#   Ctrl-Q       quit
#
# Mouse:
#   Button 1     place cursor / select text
#   Button 2     paste (snarf buffer)
#   Button 3     context menu (copy, paste, clear, exit)
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

include "string.m";
	str: String;

include "sh.m";

include "lucitheme.m";

include "widget.m";
	widgetmod: Widget;
	Scrollbar, Statusbar, Kbdfilter: import widgetmod;

Lucishell: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

# Colors (fallback defaults; overridden by theme at runtime)
# Same palette as edit — no "terminal green" affectation.
BG:	con int 16rFFFDF6FF;		# warm off-white background
FG:	con int 16r333333FF;		# dark text
CURSORCOL: con int 16r2266CCFF;	# blue cursor
SELCOL:	con int 16rB4D5FEFF;		# light blue selection
PROMPTCOL: con int 16r555555FF;	# prompt (slightly dimmer than body text)
# Dimensions
MARGIN: con 4;
TABSTOP: con 8;

# Key constants (Inferno keyboard codes — canonical defs in Widget)
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
Kdel_char:	con 16r7F;	# DEL character for Ctrl-C
Keof_char:	con 16r04;	# ^D EOF

# Transcript buffer
MAXLINES: con 4000;
TRIMLINES: con 3000;

# History
MAXHIST: con 100;

# --- Module-level state ---
display_g: ref Display;
font: ref Font;
bgcolor: ref Image;
fgcolor: ref Image;
cursorcolor: ref Image;
selcolor: ref Image;
promptcolor: ref Image;
scrollbar: ref Scrollbar;
statbar: ref Statusbar;

w: ref Window;
vislines: int;
stderr: ref Sys->FD;

# Transcript buffer of output lines
lines: array of string;
nlines: int;		# number of lines in buffer
topline: int;		# first visible line (scroll position)
atbottom: int;		# auto-scroll to bottom

# Input line (what user is typing, not yet sent)
inputbuf: string;
inputcol: int;		# cursor position within inputbuf

# The last partial line from shell output (prompt hint)
promptstr: string;

# Shell I/O
rawon: int;			# written only by rawstateforwarder; reads are word-atomic in Dis
rawlock: chan of int;

# Selection
selactive: int;
selstartline: int;
selstartcol: int;
selendline: int;
selendcol: int;
snarf: string;

# History
history: array of string;
nhist: int;
histpos: int;

# ANSI escape decode state
kbdfilter: ref Kbdfilter;

# Channels
outputch: chan of string;	# shell output arrives here
sendbyteschan: chan of array of byte;	# keyboard → consserver

# Shell dir for Veltro read-only access
SHELL_DIR: con "/tmp/veltro/shell";
shellstatedirty: int;	# set when transcript changes, cleared after writing state

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;
	menumod = load Menu Menu->PATH;
	str = load String String->PATH;
	widgetmod = load Widget Widget->PATH;
	stderr = sys->fildes(2);
	if(widgetmod == nil) {
		sys->fprint(stderr, "lucishell: cannot load Widget: %r\n");
		raise "fail:cannot load Widget";
	}

	if(ctxt == nil) {
		sys->fprint(stderr, "lucishell: no window context\n");
		raise "fail:no context";
	}

	sys->pctl(Sys->NEWPGRP, nil);
	wmclient->init();

	# Initialize state
	lines = array[MAXLINES] of string;
	lines[0] = "";
	nlines = 1;
	topline = 0;
	atbottom = 1;
	inputbuf = "";
	inputcol = 0;
	promptstr = "";
	rawon = 0;
	rawlock = chan[1] of int;
	rawlock <-= 1;
	selactive = 0;
	snarf = "";
	history = array[MAXHIST] of string;
	nhist = 0;
	histpos = -1;

	outputch = chan[32] of string;
	sendbyteschan = chan of array of byte;

	# Start file-based IPC directory
	initshelldirs();

	# Start shell process (uses file2chan, must happen before window)
	spawn startshell();

	# Create window
	w = wmclient->window(ctxt, "Shell", Wmclient->Appl);
	display_g = w.display;

	# Load font
	font = Font.open(display_g, "/fonts/combined/unicode.14.font");
	if(font == nil)
		font = Font.open(display_g, "/fonts/10646/9x15/9x15.font");
	if(font == nil)
		font = Font.open(display_g, "*default*");
	if(font == nil) {
		sys->fprint(stderr, "lucishell: cannot load any font\n");
		raise "fail:no font";
	}

	# Create color images from theme
	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme != nil) {
		th := lucitheme->gettheme();
		bgcolor = display_g.color(th.editbg);
		fgcolor = display_g.color(th.edittext);
		cursorcolor = display_g.color(th.editcursor);
		selcolor = display_g.color(th.accent);
		promptcolor = display_g.color(th.dim);
	} else {
		bgcolor = display_g.color(BG);
		fgcolor = display_g.color(FG);
		cursorcolor = display_g.color(CURSORCOL);
		selcolor = display_g.color(SELCOL);
		promptcolor = display_g.color(PROMPTCOL);
	}
	widgetmod->init(display_g, font);
	kbdfilter = Kbdfilter.new();
	scrollbar = Scrollbar.new(Rect((0,0),(0,0)), 1);
	statbar = Statusbar.new(Rect((0,0),(0,0)));

	# Set up window
	w.reshape(Rect((0, 0), (640, 480)));
	w.startinput("kbd" :: "ptr" :: nil);
	w.onscreen(nil);

	if(menumod != nil)
		menumod->init(display_g, font);
	menu := menumod->new(array[] of {
		"copy", "paste", "clear", "scroll top", "scroll bottom", "exit"});

	redraw();

	# Cursor blink timer
	ticks := chan of int;
	spawn timer(ticks, 500);
	cursorvis := 1;
	mousedown := 0;

	for(;;) alt {
	ctl := <-w.ctl or
	ctl = <-w.ctxt.ctl =>
		w.wmctl(ctl);
		if(ctl != nil && ctl[0] == '!')
			redraw();
	rawkey := <-w.ctxt.kbd =>
		key := kbdfilter.filter(rawkey);
		if(key >= 0) {
			cursorvis = 1;
			handlekey(key);
			shellstatedirty = 1;
			redraw();
		}
	p := <-w.ctxt.ptr =>
		if(!w.pointer(*p)) {
			if(p.buttons & 4 && menumod != nil && menu != nil) {
				n := menu.show(w.image, p.xy, w.ctxt.ptr);
				case n {
				0 => docopy();
				1 => dopaste();
				2 => clearscreen();
				3 =>
					topline = 0;
					atbottom = 0;
				4 => scrolltobottom();
				5 =>
					postnote(1, sys->pctl(0, nil), "kill");
					exit;
				}
				redraw();
			} else if(p.buttons & 2) {
				buf := wmclient->snarfget();
				if(buf != "")
					snarf = buf;
				if(snarf != "")
					insertinput(snarf);
				redraw();
			} else if(p.buttons & 24) {
				# Mouse wheel scroll
				scrollbar.total = nlines;
				scrollbar.visible = vislines;
				scrollbar.origin = topline;
				topline = scrollbar.wheel(p.buttons, 3);
				atbottom = (topline >= nlines - vislines);
				redraw();
			} else if(scrollbar.isactive()) {
				# Continue scrollbar drag
				scrollbar.total = nlines;
				scrollbar.visible = vislines;
				newo := scrollbar.track(p);
				if(newo >= 0) {
					topline = newo;
					atbottom = (topline >= nlines - vislines);
				}
				redraw();
			} else if(p.buttons & 3) {
				# B1 or B2 in scrollbar area
				pr := w.image.r;
				sth := widgetmod->statusheight();
				sw := widgetmod->scrollwidth();
				scrollr := Rect((pr.min.x, pr.min.y),
					(pr.min.x + sw, pr.max.y - sth));
				if(scrollr.contains(p.xy)) {
					scrollbar.total = nlines;
					scrollbar.visible = vislines;
					scrollbar.origin = topline;
					newo := scrollbar.event(p);
					if(newo >= 0) {
						topline = newo;
						atbottom = (topline >= nlines - vislines);
					}
					redraw();
				} else if(p.buttons & 1 && mousedown) {
					(ml, mc) := pos2cursor(p.xy);
					selendline = ml;
					selendcol = mc;
					selactive = (ml != selstartline || mc != selstartcol);
				} else {
					(ml, mc) := pos2cursor(p.xy);
					selstartline = ml;
					selstartcol = mc;
					selendline = ml;
					selendcol = mc;
					selactive = 0;
					mousedown = 1;
				}
				redraw();
			} else if(mousedown) {
				(ml, mc) := pos2cursor(p.xy);
				if(ml != selstartline || mc != selstartcol) {
					selactive = 1;
					selendline = ml;
					selendcol = mc;
				}
				mousedown = 0;
				redraw();
			}
		}
	<-ticks =>
		cursorvis = !cursorvis;
		drawcursor(cursorvis);
		writeshellstate();
	output := <-outputch =>
		appendoutput(output);
		if(atbottom)
			scrolltobottom();
		shellstatedirty = 1;
		redraw();
	}
}

# ---------- Shell process ----------

startshell()
{
	# Fork namespace so our synthetic /dev/cons doesn't affect parent
	sys->pctl(Sys->FORKNS, nil);

	# Bind #s (srv device) so file2chan works
	if(sys->bind("#s", "/chan", Sys->MBEFORE|Sys->MCREATE) < 0) {
		sys->fprint(stderr, "lucishell: bind #s: %r\n");
		outputch <-= "lucishell: cannot bind #s for file2chan\n";
		return;
	}

	# Create synthetic /dev/cons using file2chan
	consio := sys->file2chan("/chan", "cons");
	if(consio == nil) {
		sys->fprint(stderr, "lucishell: file2chan cons: %r\n");
		outputch <-= "lucishell: cannot create synthetic cons\n";
		return;
	}

	# Create synthetic /dev/consctl
	consctlio := sys->file2chan("/chan", "consctl");

	# Bind our synthetic cons over /dev/cons
	if(sys->bind("/chan/cons", "/dev/cons", Sys->MREPL) < 0)
		sys->fprint(stderr, "lucishell: bind cons: %r\n");
	if(consctlio != nil) {
		if(sys->bind("/chan/consctl", "/dev/consctl", Sys->MREPL) < 0)
			sys->fprint(stderr, "lucishell: bind consctl: %r\n");
	}

	# Fork the fd table so our redirections below do not affect the main
	# lucishell goroutine (which still needs its original stdin/stdout/stderr).
	sys->pctl(Sys->FORKFD, nil);

	# Redirect stdin, stdout, and stderr to our synthetic /dev/cons.
	#
	# The shell (sh.dis) reads from sys->fildes(0) (inherited fd 0) and writes
	# prompts to stderr (fd 2).  Without this step, those fds still point to
	# lucifer's original stdin/stderr — the shell gets EOF on stdin and its
	# prompts go nowhere visible.  isconsole() also fails (fd0 qid ≠ /dev/cons
	# qid) so the shell runs non-interactively and exits on first EOF.
	#
	# After pctl(FORKFD) + dup:
	#   fd 0/1/2 in this goroutine (and any it spawns) = synthetic cons
	#   isconsole(fd0): fstat(fd0).qid == stat("/dev/cons").qid  → interactive
	#   Shell reads input from consserver via consio.read
	#   Shell writes output/prompts via consio.write → outputch → display
	newcons := sys->open("/dev/cons", Sys->ORDWR);
	if(newcons != nil) {
		sys->dup(newcons.fd, 0);	# stdin  → synthetic cons
		sys->dup(newcons.fd, 1);	# stdout → synthetic cons
		sys->dup(newcons.fd, 2);	# stderr → synthetic cons (prompts go here)
		newcons = nil;
	}

	# Start the file server for cons reads/writes
	spawn consserver(consio, consctlio);

	# Give consserver a moment to start
	sys->sleep(50);

	# Load and run the shell
	sh := load Command "/dis/sh.dis";
	if(sh == nil) {
		sys->fprint(stderr, "lucishell: cannot load /dis/sh.dis: %r\n");
		outputch <-= "lucishell: cannot load shell\n";
		return;
	}

	spawn sh->init(nil, "sh" :: "-i" :: nil);
}

# consserver: services reads and writes on synthetic /dev/cons and /dev/consctl.
# Shell writes → outputch → display.
# User keyboard → sendbyteschan → shell reads.
consserver(consio, consctlio: ref Sys->FileIO)
{
	# Pending shell read requests: (nbytes, reply channel) pairs
	rdqueue: list of (int, Sys->Rread);

	# Pending input bytes (user typed, shell hasn't read yet)
	inputqueue: list of array of byte;

	# Channel for rawon state changes (communicated to main goroutine)
	rawch := chan of int;
	spawn rawstateforwarder(rawch);

	if(consctlio != nil) {
		spawn consctlserver(consctlio, rawch);
	}

	for(;;) alt {
	(nil, nbytes, nil, rc) := <-consio.read =>
		if(rc == nil)
			continue;
		# Shell wants to read from cons
		if(inputqueue != nil) {
			data := hd inputqueue;
			inputqueue = tl inputqueue;
			if(len data > nbytes)
				data = data[0:nbytes];
			rc <-= (data, nil);
		} else {
			rdqueue = (nbytes, rc) :: rdqueue;
		}

	(nil, data, nil, wc) := <-consio.write =>
		if(wc == nil)
			continue;
		# Shell wrote output
		s := string data;
		wc <-= (len data, nil);
		outputch <-= s;

	ibytes := <-sendbyteschan =>
		# Try to satisfy pending shell read requests
		if(rdqueue != nil) {
			# Reverse to deliver in FIFO order
			rds: list of (int, Sys->Rread);
			for(rl := rdqueue; rl != nil; rl = tl rl)
				rds = (hd rl) :: rds;
			rdqueue = nil;

			for(; rds != nil && len ibytes > 0; rds = tl rds) {
				(rnb, rq) := hd rds;
				chunk := ibytes;
				if(len chunk > rnb)
					chunk = chunk[0:rnb];
				rq <-= (chunk, nil);
				if(len chunk < len ibytes)
					ibytes = ibytes[len chunk:];
				else
					ibytes = nil;
			}
			# Re-queue unserviced reads
			for(; rds != nil; rds = tl rds)
				rdqueue = (hd rds) :: rdqueue;
		}
		if(ibytes != nil && len ibytes > 0)
			inputqueue = ibytes :: inputqueue;
	}
}

# consctlserver handles /dev/consctl reads and writes in a separate goroutine,
# preventing nil dereference when consctlio is nil and avoiding blocking consserver.
consctlserver(consctlio: ref Sys->FileIO, rawch: chan of int)
{
	for(;;) alt {
	(nil, nil, nil, rc) := <-consctlio.read =>
		if(rc == nil)
			continue;
		rc <-= (nil, "permission denied");

	(nil, data, nil, wc) := <-consctlio.write =>
		if(wc == nil)
			continue;
		s := string data;
		if(s == "rawon")
			rawch <-= 1;
		else if(s == "rawoff")
			rawch <-= 0;
		wc <-= (len data, nil);
	}
}

# rawstateforwarder receives rawon state changes and updates the shared variable.
# This serialises access to rawon through a single goroutine.
rawstateforwarder(rawch: chan of int)
{
	for(;;) {
		v := <-rawch;
		<-rawlock;
		rawon = v;
		rawlock <-= 1;
	}
}

sendinput(s: string)
{
	b := array of byte s;
	sendbyteschan <-= b;
}

# ---------- Keyboard handling ----------

handlekey(key: int)
{
	ctrl := 0;
	if(key >= 1 && key <= 26 && key != Kbs && key != '\n' && key != '\t')
		ctrl = 1;

	<-rawlock;
	israw := rawon;
	rawlock <-= 1;
	if(israw) {
		# In raw mode, send every keystroke directly to shell
		s := "";
		s[0] = key;
		sendinput(s);
		return;
	}

	if(ctrl) {
		case key {
		3 =>	# Ctrl-C: interrupt
			s := "";
			s[0] = Kdel_char;
			sendinput(s);
			inputbuf = "";
			inputcol = 0;
			appendoutput("^C\n");
			;
		4 =>	# Ctrl-D: EOF
			if(inputbuf == "") {
				s := "";
				s[0] = Keof_char;
				sendinput(s);
			}
		12 =>	# Ctrl-L: clear
			clearscreen();
		17 =>	# Ctrl-Q: quit
			postnote(1, sys->pctl(0, nil), "kill");
			exit;
		21 =>	# Ctrl-U: clear input line
			inputbuf = "";
			inputcol = 0;
		}
		return;
	}

	case key {
	'\n' =>
		line := inputbuf + "\n";
		if(inputbuf != "")
			addhistory(inputbuf);
		histpos = -1;
		appendoutput(inputbuf + "\n");
		inputbuf = "";
		inputcol = 0;
		sendinput(line);
		if(atbottom)
			scrolltobottom();
		;
	Kbs =>
		if(inputcol > 0) {
			inputbuf = inputbuf[0:inputcol-1] + inputbuf[inputcol:];
			inputcol--;
		}
	Kdel =>
		if(inputcol < len inputbuf)
			inputbuf = inputbuf[0:inputcol] + inputbuf[inputcol+1:];
	Kleft =>
		if(inputcol > 0)
			inputcol--;
	Kright =>
		if(inputcol < len inputbuf)
			inputcol++;
	Khome =>
		inputcol = 0;
	Kend =>
		inputcol = len inputbuf;
	Kup =>
		if(nhist > 0) {
			if(histpos < 0)
				histpos = nhist;
			if(histpos > 0) {
				histpos--;
				inputbuf = history[histpos];
				inputcol = len inputbuf;
			}
		}
	Kdown =>
		if(histpos >= 0) {
			histpos++;
			if(histpos >= nhist) {
				histpos = -1;
				inputbuf = "";
				inputcol = 0;
			} else {
				inputbuf = history[histpos];
				inputcol = len inputbuf;
			}
		}
	Kpgup =>
		if(vislines > 0) {
			topline -= vislines;
			if(topline < 0)
				topline = 0;
			atbottom = 0;
		}
	Kpgdown =>
		if(vislines > 0) {
			topline += vislines;
			maxtl := nlines - vislines;
			if(maxtl < 0) maxtl = 0;
			if(topline > maxtl) topline = maxtl;
			if(topline >= nlines - vislines)
				atbottom = 1;
		}
	'\t' =>
		insertinput("\t");
	Kesc =>
		selactive = 0;
	* =>
		if(key >= 16r20) {
			s := "";
			s[0] = key;
			insertinput(s);
		}
	}
}

insertinput(s: string)
{
	for(i := 0; i < len s; i++) {
		if(s[i] == '\n') {
			line := inputbuf + "\n";
			if(inputbuf != "")
				addhistory(inputbuf);
			histpos = -1;
			appendoutput(inputbuf + "\n");
			inputbuf = "";
			inputcol = 0;
			sendinput(line);
			;
		} else {
			if(inputcol >= len inputbuf)
				inputbuf += s[i:i+1];
			else
				inputbuf = inputbuf[0:inputcol] + s[i:i+1]
					+ inputbuf[inputcol:];
			inputcol++;
		}
	}
}

# ---------- History ----------

addhistory(line: string)
{
	if(nhist >= MAXHIST) {
		for(i := 0; i < MAXHIST - 1; i++)
			history[i] = history[i+1];
		nhist = MAXHIST - 1;
	}
	history[nhist] = line;
	nhist++;
}

# ---------- Output handling ----------

appendoutput(s: string)
{
	for(i := 0; i < len s; i++) {
		c := s[i];
		case c {
		'\n' =>
			nlines++;
			if(nlines >= MAXLINES)
				trimtranscript();
			growlines();
			lines[nlines-1] = "";
		'\r' =>
			;	# carriage return — ignore (shells use \n)
		'\b' =>
			line := lines[nlines-1];
			if(len line > 0)
				lines[nlines-1] = line[0:len line - 1];
		'\t' =>
			line := lines[nlines-1];
			spaces := TABSTOP - (len line % TABSTOP);
			for(j := 0; j < spaces; j++)
				lines[nlines-1] += " ";
		* =>
			if(c == 16r1B) {
				# ANSI escape — skip the sequence
				i++;
				if(i < len s && s[i] == '[') {
					i++;
					while(i < len s &&
					    !((s[i] >= 'A' && s[i] <= 'Z') ||
					      (s[i] >= 'a' && s[i] <= 'z')))
						i++;
				}
			} else if(c >= 16r20) {
				lines[nlines-1] += s[i:i+1];
			}
		}
	}

	# Save the last line as prompt hint
	if(nlines > 0)
		promptstr = lines[nlines-1];
}

trimtranscript()
{
	keep := TRIMLINES;
	if(keep >= nlines)
		return;
	drop := nlines - keep;
	for(i := 0; i < keep; i++)
		lines[i] = lines[i + drop];
	for(i = keep; i < nlines; i++)
		lines[i] = "";
	nlines = keep;
	topline -= drop;
	if(topline < 0)
		topline = 0;
	if(selactive) {
		selstartline -= drop;
		selendline -= drop;
		if(selstartline < 0 || selendline < 0)
			selactive = 0;
	}
}

# growlines is a safety net: trimtranscript keeps nlines < len lines,
# but this prevents a crash if the trim logic is ever changed.
growlines()
{
	if(nlines >= len lines) {
		newlines := array[len lines * 2] of string;
		newlines[0:] = lines;
		lines = newlines;
	}
}

clearscreen()
{
	lines[0] = promptstr;
	for(i := 1; i < nlines; i++)
		lines[i] = "";
	nlines = 1;
	topline = 0;
	atbottom = 1;
	;
}

scrolltobottom()
{
	if(vislines <= 0) {
		topline = 0;
		return;
	}
	total := nlines;	# nlines-1 transcript lines + 1 input line
	topline = total - vislines;
	if(topline < 0)
		topline = 0;
	atbottom = 1;
}

# ---------- Selection ----------

getlineat(row: int): string
{
	if(row < nlines - 1)
		return lines[row];
	return promptstr + inputbuf;
}

pos2cursor(p: Point): (int, int)
{
	if(w.image == nil)
		return (0, 0);

	textr := textrect();
	vy := p.y - textr.min.y;
	if(vy < 0)
		vy = 0;
	clickrow := 0;
	if(font.height > 0)
		clickrow = vy / font.height;

	row := clickrow + topline;
	total := nlines;
	if(row >= total)
		row = total - 1;
	if(row < 0)
		row = 0;

	line := getlineat(row);
	x := p.x - textr.min.x;
	if(x < 0)
		x = 0;
	col := 0;
	w2 := 0;
	for(i := 0; i < len line; i++) {
		cw := font.width(line[i:i+1]);
		if(w2 + cw/2 > x)
			break;
		w2 += cw;
		col++;
	}
	return (row, col);
}

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
	total := nlines;
	if(sl == el) {
		line := getlineat(sl);
		if(sc > len line) sc = len line;
		if(ec > len line) ec = len line;
		return line[sc:ec];
	}
	line := getlineat(sl);
	if(sc > len line) sc = len line;
	s := line[sc:];
	for(i := sl + 1; i < el && i < total; i++)
		s += "\n" + getlineat(i);
	line = getlineat(el);
	if(ec > len line) ec = len line;
	s += "\n" + line[0:ec];
	return s;
}

docopy()
{
	s := getseltext();
	if(s != "") {
		snarf = s;
		wmclient->snarfput(s);
	}
}

dopaste()
{
	buf := wmclient->snarfget();
	if(buf != "")
		snarf = buf;
	if(snarf != "")
		insertinput(snarf);
}

# ---------- Drawing ----------

textrect(): Rect
{
	if(w.image == nil)
		return Rect((0,0),(0,0));
	r := w.image.r;
	statusheight := font.height + MARGIN * 2;
	sw := widgetmod->scrollwidth();
	return Rect((r.min.x + sw + MARGIN, r.min.y + MARGIN),
		    (r.max.x - MARGIN, r.max.y - statusheight));
}

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

	sw := widgetmod->scrollwidth();
	scrollbar.resize(Rect((r.min.x, r.min.y),
		(r.min.x + sw, r.max.y - statusheight)));
	scrollbar.total = nlines;
	scrollbar.visible = vislines;
	scrollbar.origin = topline;
	scrollbar.draw(screen);

	y := textr.min.y;
	vrow := 0;

	# Draw transcript lines (all but the current partial line at lines[nlines-1])
	for(i := topline; i < nlines - 1 && vrow < maxvrows; i++) {
		if(i < 0) continue;
		if(selactive)
			drawselection(screen, i, textr.min.x, y);
		screen.text(Point(textr.min.x, y), fgcolor,
			Point(0, 0), font, lines[i]);
		y += font.height;
		vrow++;
	}

	# Draw input line (prompt + inputbuf)
	if(vrow < maxvrows) {
		if(selactive)
			drawselection(screen, nlines - 1, textr.min.x, y);
		if(promptstr != "")
			screen.text(Point(textr.min.x, y), promptcolor,
				Point(0, 0), font, promptstr);
		if(inputbuf != "") {
			px := textr.min.x + font.width(promptstr);
			screen.text(Point(px, y), fgcolor,
				Point(0, 0), font, inputbuf);
		}
		y += font.height;
		vrow++;
	}

	vislines = maxvrows;

	drawcursor(1);
	# Status bar
	statbar.resize(Rect((r.min.x, r.max.y - statusheight), r.max));
	<-rawlock;
	israw_s := rawon;
	rawlock <-= 1;
	mode := "cooked";
	if(israw_s)
		mode = "raw";
	statbar.prompt = nil;
	statbar.left = sys->sprint("Shell (%s)  %d lines", mode, nlines);
	statbar.right = sys->sprint("Ln %d", nlines);
	statbar.leftcolor = nil;
	statbar.draw(screen);
	screen.flush(Draw->Flushnow);
}

drawselection(screen: ref Image, linenum, textx, y: int)
{
	(sl, sc, el, ec) := getsel();
	if(linenum < sl || linenum > el)
		return;

	line := getlineat(linenum);
	startx := textx;
	endx := textx + font.width(line);

	if(linenum == sl) {
		prefix := "";
		if(sc <= len line)
			prefix = line[0:sc];
		startx = textx + font.width(prefix);
	}
	if(linenum == el) {
		prefix := "";
		if(ec <= len line)
			prefix = line[0:ec];
		endx = textx + font.width(prefix);
	}

	selr := Rect((startx, y), (endx, y + font.height));
	screen.draw(selr, selcolor, nil, Point(0, 0));
}

drawcursor(vis: int)
{
	if(w.image == nil)
		return;

	textr := textrect();
	maxvrows := 1;
	if(font.height > 0)
		maxvrows = textr.dy() / font.height;

	# The input line is at visual row (nlines - 1 - topline)
	inputrow := nlines - 1 - topline;
	if(inputrow < 0 || inputrow >= maxvrows)
		return;

	y := textr.min.y + inputrow * font.height;
	prefix := inputbuf[0:inputcol];
	x := textr.min.x + font.width(promptstr) + font.width(prefix);

	col := cursorcolor;
	if(!vis)
		col = bgcolor;
	w.image.line(Point(x, y), Point(x, y + font.height - 1),
		0, 0, 0, col, Point(0, 0));
	w.image.flush(Draw->Flushnow);
}

# ---------- Real-file IPC ----------

initshelldirs()
{
	mkdirq("/tmp/veltro");
	mkdirq(SHELL_DIR);
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

writeshellstate()
{
	if(!shellstatedirty)
		return;
	# Write transcript body (read-only for Veltro)
	body := getbodytext();
	writestatefile(SHELL_DIR + "/body", body);
	# Write current input line
	writestatefile(SHELL_DIR + "/input", inputbuf);
	shellstatedirty = 0;
}

getbodytext(): string
{
	s := "";
	for(i := 0; i < nlines; i++) {
		if(i > 0)
			s += "\n";
		s += lines[i];
	}
	return s;
}

writestatefile(path, data: string)
{
	fd := sys->create(path, Sys->OWRITE, 8r644);
	if(fd == nil)
		return;
	b := array of byte data;
	sys->write(fd, b, len b);
	fd = nil;
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
