implement Shell;

#
# shell - Draw-based shell terminal with 9P interface
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
#   Ctrl-W       delete word before cursor
#   Ctrl-L       clear screen (keep prompt)
#   Up/Down      scroll history
#   Page Up/Down scroll transcript
#   Ctrl-Q       quit
#   ESC          toggle hold mode (freeze output)
#
# Mouse:
#   Button 1     place cursor / select text
#   Button 2     paste (snarf buffer)
#   Button 3     context menu / plumb word
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

include "arg.m";
	arg: Arg;

include "workdir.m";
	workdir: Workdir;

include "plumbmsg.m";
	plumbmod: Plumbmsg;
	Msg: import plumbmod;

Shell: module
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
HOLDCOL: con int 16rCC8800FF;		# hold-mode text color
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

# Maximum dynamic buttons
MAXBUTTONS: con 20;

# --- Module-level state ---
display_g: ref Display;
font: ref Font;
bgcolor: ref Image;
fgcolor: ref Image;
fgcolor_normal: ref Image;		# text color when focused, no hold
fgcolor_dim: ref Image;		# text color when unfocused
fgcolor_hold: ref Image;		# text color when holding
cursorcolor: ref Image;
selcolor: ref Image;
promptcolor: ref Image;
scrollbar: ref Scrollbar;
statbar: ref Statusbar;

w: ref Window;
vislines: int;
stderr: ref Sys->FD;
themech: chan of int;

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
snarfbuf: string;

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

# Hold mode
holding: int;			# 1 = output frozen
holdqueue: list of string;	# output buffered while holding

# Scroll mode
scrolling: int;			# 1 = auto-scroll on output (default)

# Focus tracking
haskbdfocus: int;		# 1 = window has keyboard focus

# Working directory
cwd: string;

# Plumbing
plumbed: int;			# 1 = plumbing available

# Shell argv (built from command-line flags)
shellargv: list of string;

# Dynamic button bar
Button: adt {
	label: string;
	cmd: string;		# text to send as input
};
buttons: array of ref Button;
nbuttons: int;

# shctl channel
shctlch: chan of string;

# Window geometry (from command-line flags)
initwidth: int;
initheight: int;

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
		sys->fprint(stderr, "shell: cannot load Widget: %r\n");
		raise "fail:cannot load Widget";
	}

	if(ctxt == nil) {
		sys->fprint(stderr, "shell: no window context\n");
		raise "fail:no context";
	}

	# Parse command-line arguments
	initwidth = 640;
	initheight = 480;
	fontpath := "";
	shellargv = "sh" :: "-i" :: nil;
	arg = load Arg Arg->PATH;
	if(arg != nil) {
		arg->init(argv);
		arg->setusage("shell [-w width] [-h height] [-f font] [-c cmd] [-ilxvn]");
		shflags: list of string;
		shcmd := "";
		while((c := arg->opt()) != 0)
			case c {
			'w' => initwidth = int arg->earg();
			'h' => initheight = int arg->earg();
			'f' => fontpath = arg->earg();
			'c' =>
				shcmd = arg->earg();
			'i' or 'l' or 'x' or 'v' or 'n' =>
				s := "";
				s[0] = c;
				shflags = ("-" + s) :: shflags;
			* => arg->usage();
			}
		if(shcmd != "") {
			shellargv = "sh" :: "-c" :: shcmd :: nil;
		} else {
			shellargv = "sh" :: "-i" :: nil;
			# shflags is reversed from parsing; append each
			# to build correct order via listappend
			for(fl := shflags; fl != nil; fl = tl fl)
				shellargv = listappend(shellargv, hd fl);
			for(ra := arg->argv(); ra != nil; ra = tl ra)
				shellargv = listappend(shellargv, hd ra);
		}
	}

	sys->pctl(Sys->NEWPGRP, nil);
	wmclient->init();

	# Get working directory
	workdir = load Workdir Workdir->PATH;
	if(workdir != nil)
		cwd = workdir->init();
	if(cwd == nil || cwd == "")
		cwd = "/";

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
	snarfbuf = "";
	history = array[MAXHIST] of string;
	nhist = 0;
	histpos = -1;
	holding = 0;
	scrolling = 1;
	haskbdfocus = 1;
	plumbed = 0;
	buttons = array[MAXBUTTONS] of ref Button;
	nbuttons = 0;
	shctlch = chan[8] of string;

	outputch = chan[32] of string;
	sendbyteschan = chan of array of byte;

	# Start file-based IPC directory
	initshelldirs();

	# Start shell process (uses file2chan, must happen before window)
	spawn startshell();

	# Create window
	title := "Shell " + cwd;
	w = wmclient->window(ctxt, title, Wmclient->Appl);
	display_g = w.display;

	# Load font
	if(fontpath != "")
		font = Font.open(display_g, fontpath);
	if(font == nil)
		font = Font.open(display_g, "/fonts/combined/unicode.14.font");
	if(font == nil)
		font = Font.open(display_g, "*default*");
	if(font == nil) {
		sys->fprint(stderr, "shell: cannot load any font\n");
		raise "fail:no font";
	}

	# Create color images from theme
	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme != nil) {
		th := lucitheme->gettheme();
		bgcolor = display_g.color(th.editbg);
		fgcolor_normal = display_g.color(th.edittext);
		fgcolor_dim = display_g.color(th.dim);
		fgcolor_hold = display_g.color(th.yellow);
		cursorcolor = display_g.color(th.editcursor);
		selcolor = display_g.color(th.accent);
		promptcolor = display_g.color(th.dim);
	} else {
		bgcolor = display_g.color(BG);
		fgcolor_normal = display_g.color(FG);
		fgcolor_dim = display_g.color(PROMPTCOL);
		fgcolor_hold = display_g.color(HOLDCOL);
		cursorcolor = display_g.color(CURSORCOL);
		selcolor = display_g.color(SELCOL);
		promptcolor = display_g.color(PROMPTCOL);
	}
	fgcolor = fgcolor_normal;

	widgetmod->init(display_g, font);
	kbdfilter = Kbdfilter.new();
	scrollbar = Scrollbar.new(Rect((0,0),(0,0)), 1);
	statbar = Statusbar.new(Rect((0,0),(0,0)));

	# Set up window
	w.reshape(Rect((0, 0), (initwidth, initheight)));
	w.startinput("kbd" :: "ptr" :: nil);
	w.onscreen(nil);

	if(menumod != nil)
		menumod->init(display_g, font);
	menu := makemenu();

	# Initialize plumbing
	plumbmod = load Plumbmsg Plumbmsg->PATH;
	if(plumbmod != nil) {
		if(plumbmod->init(0, nil, 0) >= 0)
			plumbed = 1;
	}

	redraw();

	# Cursor blink timer
	ticks := chan of int;
	spawn timer(ticks, 500);
	cursorvis := 1;
	mousedown := 0;

	# Listen for live theme changes
	themech = chan[1] of int;
	spawn themelistener();

	for(;;) alt {
	ctl := <-w.ctl or
	ctl = <-w.ctxt.ctl =>
		w.wmctl(ctl);
		if(ctl != nil && ctl[0] == '!') {
			redraw();
		} else if(ctl != nil) {
			handlectl(ctl);
		}
	rawkey := <-w.ctxt.kbd =>
		# Intercept bare ESC before the ANSI filter eats it.
		# In windowed mode arrows arrive as 0xFF5x, so ESC (27)
		# is always a genuine ESC keypress.
		if(rawkey == Kesc) {
			cursorvis = 1;
			handlekey(Kesc);
			shellstatedirty = 1;
			redraw();
		} else {
			key := kbdfilter.filter(rawkey);
			if(key >= 0) {
				cursorvis = 1;
				handlekey(key);
				shellstatedirty = 1;
				redraw();
			}
		}
	p := <-w.ctxt.ptr =>
		if(!w.pointer(*p)) {
			if(p.buttons & 4 && menumod != nil && menu != nil) {
				n := menu.show(w.image, p.xy, w.ctxt.ptr);
				domenu(n);
				menu = makemenu();
				redraw();
			} else if(p.buttons & 2) {
				buf := wmclient->snarfget();
				if(buf != "")
					snarfbuf = buf;
				if(snarfbuf != "")
					insertinput(snarfbuf);
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
				# B1 or B2 in scrollbar area or button bar
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
				} else if(p.buttons & 1 && nbuttons > 0 && buttonhit(p.xy)) {
					redraw();
				} else if(p.buttons & 1 && mousedown) {
					# Selection drag — only redraw if endpoint changed
					(ml, mc) := pos2cursor(p.xy);
					if(ml != selendline || mc != selendcol) {
						selendline = ml;
						selendcol = mc;
						selactive = (ml != selstartline || mc != selstartcol);
						redraw();
					}
				} else {
					(ml, mc) := pos2cursor(p.xy);
					selstartline = ml;
					selstartcol = mc;
					selendline = ml;
					selendcol = mc;
					selactive = 0;
					mousedown = 1;
					redraw();
				}
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
		if(holding) {
			holdqueue = output :: holdqueue;
		} else {
			appendoutput(output);
			if(atbottom && scrolling)
				scrolltobottom();
			shellstatedirty = 1;
			redraw();
		}
	cmd := <-shctlch =>
		handleshctl(cmd);
		redraw();
	<-themech =>
		reloadcolors();
		redraw();
	}
}

# ---------- Window control messages ----------

handlectl(ctl: string)
{
	# Parse "haskbdfocus N"
	if(len ctl > 13 && ctl[0:13] == "haskbdfocus ") {
		haskbdfocus = int ctl[13:];
		updatefgcolor();
		redraw();
	}
}

updatefgcolor()
{
	if(holding)
		fgcolor = fgcolor_hold;
	else if(haskbdfocus)
		fgcolor = fgcolor_normal;
	else
		fgcolor = fgcolor_dim;
}

updatetitle()
{
	title := "Shell " + cwd;
	if(holding)
		title += " (holding)";
	w.settitle(title);
}

# ---------- Context menu ----------

makemenu(): ref Popup
{
	scrolllabel := "noscroll";
	if(!scrolling)
		scrolllabel = "scroll";
	if(plumbed)
		return menumod->new(array[] of {
			"cut", "snarf", "paste", "send",
			"plumb", scrolllabel, "clear", "exit"});
	return menumod->new(array[] of {
		"cut", "snarf", "paste", "send",
		scrolllabel, "clear", "exit"});
}

domenu(n: int)
{
	if(plumbed) {
		# Menu: cut snarf paste send plumb scroll clear exit
		case n {
		0 => docut();
		1 => dosnarf();
		2 => dopaste();
		3 => dosend();
		4 => doplumb();
		5 => scrolling = !scrolling;
		6 => clearscreen();
		7 =>
			postnote(1, sys->pctl(0, nil), "kill");
			exit;
		}
	} else {
		# Menu: cut snarf paste send scroll clear exit
		case n {
		0 => docut();
		1 => dosnarf();
		2 => dopaste();
		3 => dosend();
		4 => scrolling = !scrolling;
		5 => clearscreen();
		6 =>
			postnote(1, sys->pctl(0, nil), "kill");
			exit;
		}
	}
}

docut()
{
	dosnarf();
	# Delete selection from transcript (only in transcript, not input line)
	# This is a simplified cut — it snarfs the text and clears the selection
	selactive = 0;
}

dosnarf()
{
	s := getseltext();
	if(s != "") {
		snarfbuf = s;
		wmclient->snarfput(s);
	}
}

dopaste()
{
	buf := wmclient->snarfget();
	if(buf != "")
		snarfbuf = buf;
	if(snarfbuf != "")
		insertinput(snarfbuf);
}

doplumb()
{
	# Plumb selected text, or word at last click position
	s := getseltext();
	if(s == "" && selstartline >= 0) {
		line := getlineat(selstartline);
		s = wordatpos(line, selstartcol);
	}
	plumbtext(s);
}

dosend()
{
	# Plan 9 / Inferno convention: "send" sends the selected text
	# as input to the shell (select-and-execute idiom).
	# If there's no selection, fall back to snarf buffer.
	s := getseltext();
	if(s == "") {
		buf := wmclient->snarfget();
		if(buf != "")
			snarfbuf = buf;
		s = snarfbuf;
	}
	if(s == "")
		return;
	# Ensure it ends with newline so the shell executes it
	if(len s > 0 && s[len s - 1] != '\n')
		s += "\n";
	selactive = 0;
	insertinput(s);
}

# ---------- Plumbing ----------

plumbtext(text: string)
{
	if(!plumbed || text == "")
		return;
	msg := ref Msg(
		"Shell",		# src
		"",			# dst (let plumber decide)
		cwd,			# dir
		"text",			# kind
		"",			# attr
		array of byte text	# data
	);
	msg.send();
}

# Extract word at character position in a line
wordatpos(line: string, col: int): string
{
	if(col >= len line)
		return "";
	# Find word boundaries (non-whitespace run)
	start := col;
	while(start > 0 && !isspace(line[start-1]))
		start--;
	end := col;
	while(end < len line && !isspace(line[end]))
		end++;
	if(start == end)
		return "";
	return line[start:end];
}

isspace(c: int): int
{
	return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

# ---------- Shell process ----------

startshell()
{
	# Fork namespace so our synthetic /dev/cons doesn't affect parent
	sys->pctl(Sys->FORKNS, nil);

	# Bind #s (srv device) so file2chan works
	if(sys->bind("#s", "/chan", Sys->MBEFORE|Sys->MCREATE) < 0) {
		sys->fprint(stderr, "shell: bind #s: %r\n");
		outputch <-= "shell: cannot bind #s for file2chan\n";
		return;
	}

	# Create synthetic /dev/cons using file2chan
	consio := sys->file2chan("/chan", "cons");
	if(consio == nil) {
		sys->fprint(stderr, "shell: file2chan cons: %r\n");
		outputch <-= "shell: cannot create synthetic cons\n";
		return;
	}

	# Create synthetic /dev/consctl
	consctlio := sys->file2chan("/chan", "consctl");

	# Create synthetic /dev/shctl for dynamic button bar
	shctlio := sys->file2chan("/chan", "shctl");

	# Bind our synthetic cons over /dev/cons
	if(sys->bind("/chan/cons", "/dev/cons", Sys->MREPL) < 0)
		sys->fprint(stderr, "shell: bind cons: %r\n");
	if(consctlio != nil) {
		if(sys->bind("/chan/consctl", "/dev/consctl", Sys->MREPL) < 0)
			sys->fprint(stderr, "shell: bind consctl: %r\n");
	}
	if(shctlio != nil) {
		if(sys->bind("/chan/shctl", "/dev/shctl", Sys->MREPL) < 0)
			sys->fprint(stderr, "shell: bind shctl: %r\n");
	}

	# Fork the fd table so our redirections below do not affect the main
	# shell goroutine (which still needs its original stdin/stdout/stderr).
	sys->pctl(Sys->FORKFD, nil);

	# Redirect stdin, stdout, and stderr to our synthetic /dev/cons.
	newcons := sys->open("/dev/cons", Sys->ORDWR);
	if(newcons != nil) {
		sys->dup(newcons.fd, 0);	# stdin  → synthetic cons
		sys->dup(newcons.fd, 1);	# stdout → synthetic cons
		sys->dup(newcons.fd, 2);	# stderr → synthetic cons (prompts go here)
		newcons = nil;
	}

	# Start the file server for cons reads/writes
	spawn consserver(consio, consctlio);

	# Start the shctl server
	if(shctlio != nil)
		spawn shctlserver(shctlio);

	# Give consserver a moment to start
	sys->sleep(50);

	# Load and run the shell
	sh := load Command "/dis/sh.dis";
	if(sh == nil) {
		err := sys->sprint("%r");
		sys->fprint(stderr, "shell: cannot load /dis/sh.dis: %s\n", err);
		outputch <-= "shell: cannot load /dis/sh.dis: " + err + "\n";
		return;
	}

	spawn sh->init(nil, shellargv);
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

# shctlserver handles /dev/shctl reads and writes.
# Commands: button "label" "cmd", cwd /dir, clear
shctlserver(shctlio: ref Sys->FileIO)
{
	for(;;) alt {
	(nil, nil, nil, rc) := <-shctlio.read =>
		if(rc == nil)
			continue;
		rc <-= (nil, "permission denied");

	(nil, data, nil, wc) := <-shctlio.write =>
		if(wc == nil)
			continue;
		s := string data;
		wc <-= (len data, nil);
		shctlch <-= s;
	}
}

handleshctl(cmd: string)
{
	# Strip trailing newline
	if(len cmd > 0 && cmd[len cmd - 1] == '\n')
		cmd = cmd[0:len cmd - 1];
	if(len cmd == 0)
		return;

	# Parse command
	if(len cmd > 7 && cmd[0:7] == "button ") {
		# button "label" "cmd"
		(label, rest) := parseshctlarg(cmd[7:]);
		(bcmd, nil) := parseshctlarg(rest);
		if(label != "" && nbuttons < MAXBUTTONS) {
			buttons[nbuttons] = ref Button(label, bcmd);
			nbuttons++;
		}
	} else if(len cmd > 4 && cmd[0:4] == "cwd ") {
		cwd = cmd[4:];
		updatetitle();
	} else if(cmd == "clear") {
		nbuttons = 0;
	}
}

# Parse a quoted or unquoted argument from shctl command
parseshctlarg(s: string): (string, string)
{
	# Skip whitespace
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;
	if(i >= len s)
		return ("", "");
	if(s[i] == '"') {
		# Quoted string
		i++;
		start := i;
		while(i < len s && s[i] != '"')
			i++;
		val := s[start:i];
		if(i < len s)
			i++;	# skip closing quote
		return (val, s[i:]);
	}
	# Unquoted: take until whitespace
	start := i;
	while(i < len s && s[i] != ' ' && s[i] != '\t')
		i++;
	return (s[start:i], s[i:]);
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
		23 =>	# Ctrl-W: delete word before cursor
			if(inputcol > 0) {
				j := inputcol;
				# Skip whitespace backwards
				while(j > 0 && isspace(inputbuf[j-1]))
					j--;
				# Skip non-whitespace backwards
				while(j > 0 && !isspace(inputbuf[j-1]))
					j--;
				inputbuf = inputbuf[0:j] + inputbuf[inputcol:];
				inputcol = j;
			}
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
		# Toggle hold mode
		holding = !holding;
		if(!holding) {
			# Flush queued output
			flushholdqueue();
		}
		updatefgcolor();
		updatetitle();
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

# ---------- Hold mode ----------

flushholdqueue()
{
	# Reverse the queue (it was built in reverse order)
	rev: list of string;
	for(q := holdqueue; q != nil; q = tl q)
		rev = (hd q) :: rev;
	holdqueue = nil;
	for(; rev != nil; rev = tl rev) {
		appendoutput(hd rev);
	}
	if(atbottom && scrolling)
		scrolltobottom();
	shellstatedirty = 1;
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
			# Carriage return — move to start of current line
			lines[nlines-1] = "";
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
			} else if(c == 0) {
				# NUL → replacement character
				lines[nlines-1] += "□";
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
	textr := textrect();
	maxpx := textr.dx();

	# Work backwards from the last line, counting visual rows,
	# to find the topline that shows the bottom of the transcript.
	vrows := 0;
	topline = 0;
	for(i := nlines - 1; i >= 0; i--) {
		line: string;
		if(i == nlines - 1)
			line = promptstr + inputbuf;
		else
			line = lines[i];
		lrows := linevisrows(line, maxpx);
		if(vrows + lrows > vislines) {
			topline = i + 1;
			if(topline >= nlines)
				topline = nlines - 1;
			atbottom = 1;
			return;
		}
		vrows += lrows;
	}
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
	maxpx := textr.dx();
	vy := p.y - textr.min.y;
	if(vy < 0)
		vy = 0;
	targetvrow := 0;
	if(font.height > 0)
		targetvrow = vy / font.height;

	# Walk logical lines from topline, counting visual rows with wrapping
	vrow := 0;
	total := nlines;
	for(i := topline; i < total; i++) {
		if(i < 0) continue;
		line := getlineat(i);
		if(len line == 0) {
			if(vrow == targetvrow)
				return (i, 0);
			vrow++;
		} else {
			start := 0;
			while(start < len line) {
				end := wrapend(line, start, maxpx);
				if(vrow == targetvrow) {
					x := p.x - textr.min.x;
					if(x < 0) x = 0;
					col := start;
					w2 := 0;
					for(j := start; j < end; j++) {
						cw := font.width(line[j:j+1]);
						if(w2 + cw/2 > x)
							break;
						w2 += cw;
						col++;
					}
					return (i, col);
				}
				vrow++;
				start = end;
			}
		}
	}
	# Past end
	if(total > 0)
		return (total - 1, len getlineat(total - 1));
	return (0, 0);
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

# ---------- Drawing ----------

textrect(): Rect
{
	if(w.image == nil)
		return Rect((0,0),(0,0));
	r := w.image.r;
	statusheight := font.height + MARGIN * 2;
	sw := widgetmod->scrollwidth();
	bbarh := buttonbarheight();
	return Rect((r.min.x + sw + MARGIN, r.min.y + MARGIN),
		    (r.max.x - MARGIN, r.max.y - statusheight - bbarh));
}

buttonbarheight(): int
{
	if(nbuttons <= 0)
		return 0;
	return font.height + MARGIN * 2;
}

redraw()
{
	if(w.image == nil)
		return;

	screen := w.image;
	r := screen.r;
	statusheight := font.height + MARGIN * 2;
	bbarh := buttonbarheight();

	screen.draw(r, bgcolor, nil, Point(0, 0));

	textr := textrect();
	maxvrows := 1;
	if(font.height > 0)
		maxvrows = textr.dy() / font.height;

	sw := widgetmod->scrollwidth();
	scrollbar.resize(Rect((r.min.x, r.min.y),
		(r.min.x + sw, r.max.y - statusheight - bbarh)));
	scrollbar.total = nlines;
	scrollbar.visible = vislines;
	scrollbar.origin = topline;
	scrollbar.draw(screen);

	y := textr.min.y;
	vrow := 0;
	maxpx := textr.dx();

	# Draw transcript lines with wrapping
	for(i := topline; i < nlines - 1 && vrow < maxvrows; i++) {
		if(i < 0) continue;
		line := lines[i];
		if(len line == 0) {
			if(selactive)
				drawselwrap(screen, i, 0, 0, textr.min.x, y);
			y += font.height;
			vrow++;
		} else {
			start := 0;
			while(start < len line && vrow < maxvrows) {
				end := wrapend(line, start, maxpx);
				if(selactive)
					drawselwrap(screen, i, start, end, textr.min.x, y);
				screen.text(Point(textr.min.x, y), fgcolor,
					Point(0, 0), font, line[start:end]);
				y += font.height;
				vrow++;
				start = end;
			}
		}
	}

	# Draw input line (prompt + inputbuf) with wrapping
	if(vrow < maxvrows) {
		inputline := promptstr + inputbuf;
		if(len inputline == 0) {
			if(selactive)
				drawselwrap(screen, nlines - 1, 0, 0, textr.min.x, y);
			y += font.height;
			vrow++;
		} else {
			plen := len promptstr;
			start := 0;
			while(start < len inputline && vrow < maxvrows) {
				end := wrapend(inputline, start, maxpx);
				if(selactive)
					drawselwrap(screen, nlines - 1, start, end, textr.min.x, y);
				# Color prompt portion differently from user input
				if(start < plen) {
					pend := plen;
					if(pend > end) pend = end;
					screen.text(Point(textr.min.x, y), promptcolor,
						Point(0, 0), font, inputline[start:pend]);
					if(pend < end) {
						px := textr.min.x + font.width(inputline[start:pend]);
						screen.text(Point(px, y), fgcolor,
							Point(0, 0), font, inputline[pend:end]);
					}
				} else {
					screen.text(Point(textr.min.x, y), fgcolor,
						Point(0, 0), font, inputline[start:end]);
				}
				y += font.height;
				vrow++;
				start = end;
			}
		}
	}

	vislines = maxvrows;

	drawcursor(1);

	# Button bar
	if(nbuttons > 0)
		drawbuttonbar(screen, r, statusheight);

	# Status bar
	statbar.resize(Rect((r.min.x, r.max.y - statusheight), r.max));
	<-rawlock;
	israw_s := rawon;
	rawlock <-= 1;
	mode := "cooked";
	if(israw_s)
		mode = "raw";
	statbar.prompt = nil;
	status := sys->sprint("Shell (%s)  %d lines", mode, nlines);
	if(holding)
		status += "  HOLD";
	if(!scrolling)
		status += "  noscroll";
	statbar.left = status;
	statbar.right = sys->sprint("Ln %d", nlines);
	if(holding)
		statbar.leftcolor = fgcolor_hold;
	else
		statbar.leftcolor = nil;
	statbar.draw(screen);
	screen.flush(Draw->Flushnow);
}

drawbuttonbar(screen: ref Image, r: Rect, statusheight: int)
{
	bbarh := buttonbarheight();
	bbary := r.max.y - statusheight - bbarh;
	x := r.min.x + MARGIN;
	for(i := 0; i < nbuttons; i++) {
		b := buttons[i];
		tw := font.width(b.label);
		bw := tw + MARGIN * 4;
		br := Rect((x, bbary + 1), (x + bw, bbary + bbarh - 1));
		# Button border
		screen.line(br.min, Point(br.max.x, br.min.y), 0, 0, 0, fgcolor_dim, Point(0, 0));
		screen.line(Point(br.max.x, br.min.y), br.max, 0, 0, 0, fgcolor_dim, Point(0, 0));
		screen.line(br.max, Point(br.min.x, br.max.y), 0, 0, 0, fgcolor_dim, Point(0, 0));
		screen.line(Point(br.min.x, br.max.y), br.min, 0, 0, 0, fgcolor_dim, Point(0, 0));
		# Button label
		screen.text(Point(x + MARGIN * 2, bbary + MARGIN), fgcolor_normal,
			Point(0, 0), font, b.label);
		x += bw + MARGIN;
	}
}

buttonhit(p: Point): int
{
	if(nbuttons <= 0 || w.image == nil)
		return 0;
	r := w.image.r;
	statusheight := font.height + MARGIN * 2;
	bbarh := buttonbarheight();
	bbary := r.max.y - statusheight - bbarh;
	if(p.y < bbary || p.y >= bbary + bbarh)
		return 0;
	x := r.min.x + MARGIN;
	for(i := 0; i < nbuttons; i++) {
		b := buttons[i];
		tw := font.width(b.label);
		bw := tw + MARGIN * 4;
		if(p.x >= x && p.x < x + bw) {
			# Button hit — send its command as input
			s := b.cmd;
			if(len s > 0 && s[len s - 1] != '\n')
				s += "\n";
			insertinput(s);
			return 1;
		}
		x += bw + MARGIN;
	}
	return 0;
}

# Draw selection highlight for one wrapped chunk of a logical line.
# chunkstart..chunkend is the character range of this visual chunk.
drawselwrap(screen: ref Image, linenum, chunkstart, chunkend, textx, y: int)
{
	(sl, sc, el, ec) := getsel();
	if(linenum < sl || linenum > el)
		return;

	line := getlineat(linenum);

	# Selection range for this logical line
	selstart := 0;
	selend := len line;
	if(linenum == sl) selstart = sc;
	if(linenum == el) selend = ec;

	# Clip to this chunk
	if(selstart < chunkstart) selstart = chunkstart;
	if(selend > chunkend) selend = chunkend;
	if(selstart >= selend)
		return;

	# Pixel positions relative to chunk start
	startx := textx + font.width(line[chunkstart:selstart]);
	endx := textx + font.width(line[chunkstart:selend]);
	selr := Rect((startx, y), (endx, y + font.height));
	screen.draw(selr, selcolor, nil, Point(0, 0));
}

drawcursor(vis: int)
{
	if(w.image == nil)
		return;

	textr := textrect();
	maxpx := textr.dx();
	maxvrows := 1;
	if(font.height > 0)
		maxvrows = textr.dy() / font.height;

	# Walk from topline counting visual rows to find cursor position
	inputline := promptstr + inputbuf;
	cursorpos := len promptstr + inputcol;
	vrow := 0;

	# Count visual rows for transcript lines
	for(i := topline; i < nlines - 1 && vrow < maxvrows; i++) {
		if(i < 0) continue;
		line := lines[i];
		vrow += linevisrows(line, maxpx);
	}

	if(vrow >= maxvrows)
		return;

	# Find which visual chunk of the input line contains the cursor
	if(len inputline == 0) {
		y := textr.min.y + vrow * font.height;
		x := textr.min.x;
		c := cursorcolor;
		if(!vis)
			c = bgcolor;
		w.image.line(Point(x, y), Point(x, y + font.height - 1),
			0, 0, 0, c, Point(0, 0));
		w.image.flush(Draw->Flushnow);
		return;
	}

	start := 0;
	while(start < len inputline && vrow < maxvrows) {
		end := wrapend(inputline, start, maxpx);
		if(cursorpos >= start && (cursorpos < end || end >= len inputline)) {
			y := textr.min.y + vrow * font.height;
			x := textr.min.x;
			if(cursorpos > start)
				x += font.width(inputline[start:cursorpos]);
			c := cursorcolor;
			if(!vis)
				c = bgcolor;
			w.image.line(Point(x, y), Point(x, y + font.height - 1),
				0, 0, 0, c, Point(0, 0));
			w.image.flush(Draw->Flushnow);
			return;
		}
		vrow++;
		start = end;
	}
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

# ---------- Text wrapping ----------

# Compute end index (exclusive) of next visual chunk of s starting at
# position start, fitting within maxpx pixels.  Guarantees >= 1 char.
wrapend(s: string, start, maxpx: int): int
{
	if(start >= len s)
		return len s;
	w := 0;
	k := start;
	while(k < len s) {
		cw := font.width(s[k:k+1]);
		if(w + cw > maxpx)
			break;
		w += cw;
		k++;
	}
	if(k == start)
		k++;		# at least one char per chunk
	return k;
}

# Count visual rows a logical line occupies at a given pixel width.
linevisrows(line: string, maxpx: int): int
{
	if(maxpx <= 0 || len line == 0)
		return 1;
	rows := 0;
	start := 0;
	while(start < len line) {
		start = wrapend(line, start, maxpx);
		rows++;
	}
	return rows;
}

# ---------- Helpers ----------

themelistener()
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
			alt { themech <-= 1 => ; * => ; }
	}
}

reloadcolors()
{
	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme != nil) {
		th := lucitheme->gettheme();
		bgcolor = display_g.color(th.editbg);
		fgcolor_normal = display_g.color(th.edittext);
		fgcolor_dim = display_g.color(th.dim);
		fgcolor_hold = display_g.color(th.yellow);
		cursorcolor = display_g.color(th.editcursor);
		selcolor = display_g.color(th.accent);
		promptcolor = display_g.color(th.dim);
	}
	updatefgcolor();
	widgetmod->retheme(display_g);
	wmclient->retheme(w);
	if(menumod != nil)
		menumod->init(display_g, font);
}

timer(c: chan of int, ms: int)
{
	for(;;) {
		sys->sleep(ms);
		c <-= 1;
	}
}

listappend(l: list of string, s: string): list of string
{
	if(l == nil)
		return s :: nil;
	return (hd l) :: listappend(tl l, s);
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
