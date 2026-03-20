implement ManViewer;

#
# wm/man - Draw-based manual page viewer
#
# Displays Inferno manual pages using the native widget toolkit.
# Parses troff -man markup via the Parseman library and renders
# with proper fonts (bold for headings and .B text, regular for body).
#
# Usage:
#   wm/man [section ...] title ...
#   wm/man -f file ...
#
# Keyboard:
#   Up/Down      scroll one line
#   Page Up/Down scroll one screenful
#   Home/End     go to top/bottom
#   Ctrl-F       find text
#   Ctrl-G       find next
#   Ctrl-Q       quit
#   Escape       cancel find
#
# Mouse:
#   Button 1     select text (future)
#   Button 2     paste / plumb
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

include "bufio.m";
	bufio: Bufio;

include "string.m";
	str: String;

include "lucitheme.m";

include "widget.m";
	widgetmod: Widget;
	Scrollbar, Statusbar, Kbdfilter: import widgetmod;

include "man.m";

include "arg.m";
	arg: Arg;

ManViewer: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

# Fallback colours (overridden by theme)
BG:	con int 16rFFFDF6FF;
FG:	con int 16r333333FF;
HDCOL:	con int 16r1A1A1AFF;		# heading colour
LKCOL:	con int 16r2266CCFF;		# link colour

# Dimensions
MARGIN:	con 6;

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

# Viewer type for Parseman textwidth callback (pixel-based)
V: adt {
	textwidth: fn(v: self ref V, text: Parseman->Text): int;
};

# ---------- Parsed page storage ----------
# Each rendered line is a list of (indent, Text) spans.
ManLine: type list of (int, Parseman->Text);

lines: array of ref ManLine;
nlines: int;
topline: int;
vislines: int;

# Display resources
display: ref Display;
rfont: ref Font;		# regular (roman) font
bfont: ref Font;		# bold font
bgcolor: ref Image;
fgcolor: ref Image;
hdcolor: ref Image;
lkcolor: ref Image;
dimcolor: ref Image;

scrollbar: ref Scrollbar;
statbar: ref Statusbar;
kbdfilter: ref Kbdfilter;

w: ref Window;
stderr: ref Sys->FD;

# Search state
searchstr := "";

# Page info for title bar
pagetitle := "man";

# History for back navigation
history: list of string;
histfwd: list of string;

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;
	menumod = load Menu Menu->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
	stderr = sys->fildes(2);

	if(wmclient == nil) {
		sys->fprint(stderr, "wm/man: cannot load Wmclient: %r\n");
		raise "fail:init";
	}
	if(bufio == nil) {
		sys->fprint(stderr, "wm/man: cannot load Bufio: %r\n");
		raise "fail:init";
	}

	widgetmod = load Widget Widget->PATH;
	if(widgetmod == nil) {
		sys->fprint(stderr, "wm/man: cannot load Widget: %r\n");
		raise "fail:init";
	}
	kbdfilter = Kbdfilter.new();

	if(ctxt == nil) {
		sys->fprint(stderr, "wm/man: no window context\n");
		raise "fail:no context";
	}

	sys->pctl(Sys->NEWPGRP, nil);
	wmclient->init();

	# Parse arguments
	filemode := 0;
	files: list of string;
	sections: list of string;

	arg = load Arg Arg->PATH;
	if(arg != nil) {
		arg->init(argv);
		while((c := arg->opt()))
			case c {
			'f' =>
				filemode = 1;
			}
		argv = arg->argv();
	} else
		argv = tl argv;

	if(filemode) {
		# -f: treat remaining args as filenames
		for(; argv != nil; argv = tl argv)
			files = hd argv :: files;
	} else {
		# Separate section numbers from titles
		for(; argv != nil; argv = tl argv) {
			a := hd argv;
			if(isdir("/man/" + a))
				sections = a :: sections;
			else {
				# Look up title in INDEX files
				found := lookupman(sections, a);
				for(; found != nil; found = tl found)
					files = hd found :: files;
			}
		}
	}

	# Reverse to get original order
	rfiles: list of string;
	for(; files != nil; files = tl files)
		rfiles = hd files :: rfiles;
	files = rfiles;

	# Create window
	w = wmclient->window(ctxt, "man", Wmclient->Appl);
	display = w.display;

	# Load fonts
	rfont = Font.open(display, "/fonts/combined/unicode.sans.14.font");
	if(rfont == nil)
		rfont = Font.open(display, "*default*");
	bfont = Font.open(display, "/fonts/combined/unicode.sans.bold.14.font");
	if(bfont == nil)
		bfont = rfont;

	# Load theme colours
	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme != nil) {
		th := lucitheme->gettheme();
		bgcolor = display.color(th.editbg);
		fgcolor = display.color(th.edittext);
		hdcolor = display.color(th.text);
		lkcolor = display.color(th.accent);
		dimcolor = display.color(th.dim);
	} else {
		bgcolor = display.color(BG);
		fgcolor = display.color(FG);
		hdcolor = display.color(HDCOL);
		lkcolor = display.color(LKCOL);
		dimcolor = display.color(FG);
	}
	widgetmod->init(display, rfont);
	scrollbar = Scrollbar.new(Rect((0,0),(0,0)), 1);
	statbar = Statusbar.new(Rect((0,0),(0,0)));

	# Initialize with empty content
	lines = array[4096] of ref ManLine;
	nlines = 0;
	topline = 0;
	history = nil;
	histfwd = nil;

	# Load first file
	if(files != nil)
		loadpage(hd files);
	else {
		# No args — show usage
		pagetitle = "man";
		statbar.left = "Usage: wm/man [section] title";
	}

	w.reshape(Rect((0, 0), (680, 520)));
	w.startinput("kbd" :: "ptr" :: nil);
	w.onscreen(nil);

	if(menumod != nil)
		menumod->init(display, rfont);
	menu := menumod->new(array[] of {"back", "forward", "find", "top", "bottom", "exit"});

	redraw();

	for(;;) alt {
	ctl := <-w.ctl or
	ctl = <-w.ctxt.ctl =>
		w.wmctl(ctl);
		if(ctl != nil && ctl[0] == '!')
			redraw();

	rawkey := <-w.ctxt.kbd =>
		key := kbdfilter.filter(rawkey);
		if(key >= 0) {
			if(statbar.prompt != nil) {
				# In find/input mode
				(done, val) := statbar.key(key);
				if(done == 1) {
					searchstr = val;
					statbar.prompt = nil;
					findnext(0);
				} else if(done < 0)
					statbar.prompt = nil;
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
			# Scroll wheel (button 8 = up, 16 = down)
			scrollbar.total = nlines;
			scrollbar.visible = vislines;
			scrollbar.origin = topline;
			topline = scrollbar.wheel(p.buttons, 3);
			redraw();
		} else if(p.buttons & 4) {
			# Button 3 — context menu
			if(menu != nil) {
				n := menu.show(w.image, p.xy, w.ctxt.ptr);
				case n {
				0 =>	goback();
				1 =>	goforward();
				2 =>	startfind();
				3 =>	topline = 0; redraw();
				4 =>	scrollbottom(); redraw();
				5 =>	exit;
				}
			}
		} else if(p.buttons & 3) {
			sr := scrollrect();
			if(sr.contains(p.xy)) {
				scrollbar.total = nlines;
				scrollbar.visible = vislines;
				scrollbar.origin = topline;
				newo := scrollbar.event(p);
				if(newo >= 0) {
					topline = newo;
					redraw();
				}
			}
			# B1 in text area: future selection support
		} else
			w.pointer(*p);
	}
}

handlekey(key: int)
{
	case key {
	Kup =>
		if(topline > 0) topline--;
	Kdown =>
		if(topline < nlines - vislines) topline++;
	Kpgup =>
		topline -= vislines;
		if(topline < 0) topline = 0;
	Kpgdown =>
		topline += vislines;
		clamptop();
	Khome =>
		topline = 0;
	Kend =>
		scrollbottom();
	'q' or 'Q' =>
		exit;
	'f' & 16r1f =>	# Ctrl-F
		startfind();
	'g' & 16r1f =>	# Ctrl-G
		findnext(0);
	'q' & 16r1f =>	# Ctrl-Q
		exit;
	'n' =>
		findnext(0);
	'N' =>
		findnext(1);	# reverse
	* =>
		return;
	}
	redraw();
}

startfind()
{
	statbar.prompt = "Find: ";
	statbar.buf = "";
	redraw();
}

findnext(reverse: int)
{
	if(searchstr == nil || len searchstr == 0)
		return;
	lsearch := tolower(searchstr);
	start := topline + 1;
	if(reverse)
		start = topline - 1;
	for(i := 0; i < nlines; i++) {
		idx: int;
		if(reverse)
			idx = (start - i + nlines) % nlines;
		else
			idx = (start + i) % nlines;
		if(idx < 0 || idx >= nlines)
			continue;
		line := lines[idx];
		if(line == nil)
			continue;
		text := linetext(*line);
		if(contains(tolower(text), lsearch)) {
			topline = idx;
			clamptop();
			statbar.left = pagetitle;
			statbar.right = sys->sprint("found at line %d", idx + 1);
			return;
		}
	}
	statbar.right = "not found";
}

# Extract plain text from a ManLine
linetext(ml: ManLine): string
{
	s := "";
	for(; ml != nil; ml = tl ml) {
		(nil, txt) := hd ml;
		s += txt.text;
	}
	return s;
}

loadpage(path: string)
{
	parser := load Parseman Parseman->PATH;
	if(parser == nil) {
		sys->fprint(stderr, "wm/man: cannot load Parseman: %r\n");
		return;
	}
	err := parser->init();
	if(err != nil) {
		sys->fprint(stderr, "wm/man: %s\n", err);
		return;
	}

	fd := sys->open(path, Sys->OREAD);
	if(fd == nil) {
		sys->fprint(stderr, "wm/man: cannot open %s: %r\n", path);
		return;
	}

	# Push current page to history
	if(nlines > 0 && history != nil) {
		# history already has current; skip
	}

	em := rfont.width("m");
	en := rfont.width("n");
	# Calculate page width from window if available, else use default
	pw := 600;
	if(w != nil && w.image != nil) {
		sw := widgetmod->scrollwidth();
		pw = w.image.r.dx() - sw - MARGIN * 2;
	}
	m := Parseman->Metrics(pw, 96, em, en, rfont.height, em * 3, em * 2);
	datachan := chan of list of (int, Parseman->Text);
	spawn parser->parseman(fd, m, 0, ref V, datachan);

	# Collect parsed lines
	nlines = 0;
	for(;;) {
		line := <-datachan;
		if(line == nil)
			break;
		if(nlines >= len lines) {
			newlines := array[len lines * 2] of ref ManLine;
			newlines[0:] = lines;
			lines = newlines;
		}
		ml := line;
		lines[nlines] = ref ml;
		nlines++;
	}

	topline = 0;
	pagetitle = path;
	# Extract short title from path like /man/1/man → man(1)
	(nil, parts) := sys->tokenize(path, "/");
	if(parts != nil) {
		sec := "";
		name := "";
		for(; parts != nil; parts = tl parts) {
			p := hd parts;
			if(p == "man")
				continue;
			if(sec == "")
				sec = p;
			else
				name = p;
		}
		if(name != "" && sec != "")
			pagetitle = name + "(" + sec + ")";
		else if(name != "")
			pagetitle = name;
	}
	w.settitle("man — " + pagetitle);
	statbar.left = pagetitle;
	statbar.right = sys->sprint("%d lines", nlines);
}

goback()
{
	if(history == nil)
		return;
	path := hd history;
	history = tl history;
	# save current page for forward
	loadpage(path);
	redraw();
}

goforward()
{
	if(histfwd == nil)
		return;
	path := hd histfwd;
	histfwd = tl histfwd;
	loadpage(path);
	redraw();
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
	fh := rfont.height;
	maxvrows := tr.dy() / fh;
	if(maxvrows < 1)
		maxvrows = 1;
	vislines = maxvrows;

	# Draw text lines
	y := tr.min.y;
	for(i := topline; i < nlines && (y + fh) <= tr.max.y; i++) {
		line := lines[i];
		if(line == nil) {
			y += fh;
			continue;
		}
		drawmanline(screen, tr, y, *line);
		y += fh;
	}

	# Update and draw scrollbar
	sr := scrollrect();
	scrollbar.resize(sr);
	scrollbar.total = nlines;
	scrollbar.visible = vislines;
	scrollbar.origin = topline;
	scrollbar.draw(screen);

	# Status bar
	sth := widgetmod->statusheight();
	statbar.resize(Rect((r.min.x, r.max.y - sth), (r.max.x, r.max.y)));
	statbar.draw(screen);

	screen.flush(Draw->Flushnow);
}

drawmanline(screen: ref Image, tr: Rect, y: int, ml: ManLine)
{
	ZP := Point(0, 0);
	for(; ml != nil; ml = tl ml) {
		(indent, txt) := hd ml;
		x := tr.min.x + indent;
		if(x >= tr.max.x)
			break;

		# Choose font and colour based on text attributes
		f := rfont;
		col := fgcolor;
		if(txt.heading > 0) {
			f = bfont;
			col = hdcolor;
		} else {
			case txt.font {
			Parseman->FONT_BOLD =>
				f = bfont;
			Parseman->FONT_ITALIC =>
				col = dimcolor;
			}
		}
		if(txt.link != nil && len txt.link > 0)
			col = lkcolor;

		# Clip text to visible width
		text := txt.text;
		maxw := tr.max.x - x;
		if(maxw <= 0)
			break;
		tw := f.width(text);
		if(tw > maxw) {
			# Truncate to fit
			for(k := len text; k > 0; k--) {
				if(f.width(text[:k]) <= maxw) {
					text = text[:k];
					break;
				}
			}
		}
		screen.text(Point(x, y), col, ZP, f, text);
	}
}

V.textwidth(nil: self ref V, text: Parseman->Text): int
{
	f := rfont;
	case text.font {
	Parseman->FONT_BOLD =>
		f = bfont;
	}
	if(text.heading > 0)
		f = bfont;
	if(f == nil)
		return len text.text;
	return f.width(text.text);
}

# ---------- Man page lookup ----------

lookupman(sections: list of string, title: string): list of string
{
	if(sections == nil) {
		# Search all sections
		fd := sys->open("/man", Sys->OREAD);
		if(fd == nil)
			return nil;
		(n, dirs) := sys->dirread(fd);
		for(i := 0; i < n; i++) {
			name := dirs[i].name;
			if(len name == 1 && name[0] >= '0' && name[0] <= '9')
				sections = name :: sections;
		}
	}

	ltitle := tolower(title);
	found: list of string;
	for(; sections != nil; sections = tl sections) {
		sec := hd sections;
		idxpath := "/man/" + sec + "/INDEX";
		fd := sys->open(idxpath, Sys->OREAD);
		if(fd == nil)
			continue;
		bio := bufio->fopen(fd, Sys->OREAD);
		if(bio == nil)
			continue;
		while((line := bio.gets('\n')) != nil) {
			if(len line > 0 && line[len line - 1] == '\n')
				line = line[:len line - 1];
			(nf, fields) := sys->tokenize(line, " \t");
			if(nf < 2)
				continue;
			key := tolower(hd fields);
			file := hd tl fields;
			if(key == ltitle)
				found = "/man/" + sec + "/" + file :: found;
		}
	}
	return found;
}

# ---------- Helpers ----------

clamptop()
{
	max := nlines - vislines;
	if(max < 0)
		max = 0;
	if(topline > max)
		topline = max;
	if(topline < 0)
		topline = 0;
}

scrollbottom()
{
	topline = nlines - vislines;
	if(topline < 0) topline = 0;
}

isdir(path: string): int
{
	(ok, d) := sys->stat(path);
	if(ok < 0)
		return 0;
	return d.mode & Sys->DMDIR;
}

tolower(s: string): string
{
	r := "";
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c >= 'A' && c <= 'Z')
			c += 'a' - 'A';
		r[len r] = c;
	}
	return r;
}

contains(s, sub: string): int
{
	if(len sub > len s)
		return 0;
	for(i := 0; i <= len s - len sub; i++) {
		if(s[i:i + len sub] == sub)
			return 1;
	}
	return 0;
}
