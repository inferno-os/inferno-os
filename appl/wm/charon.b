implement Charon;

#
# charon - Minimal web browser with filesystem interface
#
# A text-mode web browser built for both human and AI use.
# Uses Webclient (modern TLS 1.3) for fetching, htmlfmt for
# rendering HTML to readable text, and exposes a filesystem
# interface at /tmp/veltro/browser/ for Veltro agent control.
#
# Keyboard:
#   Arrow keys     scroll up/down
#   Page Up/Down   scroll by screenful
#   Home/End       top/bottom of page
#   Ctrl-L         enter URL (prompts in status bar)
#   Ctrl-R         reload
#   Ctrl-G         follow link by number (prompts)
#   Alt-Left       back
#   Alt-Right      forward
#   Esc            cancel URL/link entry
#
# Mouse:
#   Button 1       click numbered link to follow
#   Button 2       paste URL and navigate
#   Button 3       context menu (back, forward, reload, stop, home)
#   Scroll wheel   scroll up/down
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

include "webclient.m";
	webclient: Webclient;
	Response, Header: import webclient;

include "html.m";
	html: HTML;
	Lex, Attr: import html;

include "formatter.m";

include "lucitheme.m";

Charon: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

# Colors (fallback defaults; overridden by theme)
BG:	con int 16rFFFDF6FF;		# warm off-white
FG:	con int 16r333333FF;		# dark text
LINKFG:	con int 16r2266CCFF;		# blue links
URLBG:	con int 16rE8E8E8FF;		# status bar
URLFG:	con int 16r555555FF;		# status bar text
LNCOL:	con int 16rBBBBBBFF;		# scrollbar track

# Dimensions
MARGIN: con 4;
SCROLLW: con 12;

# Limits
MAXREDIR: con 20;
MAXBODY: con 8*1024*1024;	# 8MB max response body

# Key codes
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

# Link info
Link: adt {
	num:	int;		# 1-based link number
	href:	string;		# resolved URL
	text:	string;		# link display text
};

# History entry
HistEntry: adt {
	url:		string;
	title:		string;
	scrollpos:	int;
};

# Page state
Page: adt {
	url:		string;
	title:		string;
	body:		string;		# formatted text
	lines:		array of string;
	nlines:		int;
	links:		array of ref Link;
	nlinks:		int;
	forms:		string;		# form summary text
	status:		string;		# "ready", "loading", "error: ..."
};

# Globals
w: ref Window;
display: ref Draw->Display;
font: ref Font;
bgcolor, fgcolor, linkcolor: ref Image;
urlbgcolor, urlfgcolor, lncolor: ref Image;
htmlfmt: Formatter;
stderr: ref Sys->FD;

page: ref Page;
topline := 0;
vislines := 0;

# History
history: array of ref HistEntry;
nhist := 0;
histpos := -1;		# current position in history (-1 = none)
MAXHIST: con 100;

# Input mode
MNONE, MURL, MLINK: con iota;
inputmode := MNONE;
inputbuf := "";

# Filesystem state dir
BROWSER_DIR: con "/tmp/veltro/browser";
statedirty := 1;	# true when browser state files need updating

# Keyboard escape state
kbdescstate := 0;
kbdescarg := 0;

# Menu
menu: ref Popup;

# Navigation channels — serializes all navigation through a single thread
navchan: chan of string;
navdone: chan of ref Page;
navfromhist := 0;		# true if current navigation is back/forward
navhistscroll := 0;		# scroll position to restore after history navigation

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;
	menumod = load Menu Menu->PATH;
	str = load String String->PATH;
	stderr = sys->fildes(2);

	if(ctxt == nil) {
		sys->fprint(stderr, "charon: no window context\n");
		raise "fail:no context";
	}

	webclient = load Webclient Webclient->PATH;
	if(webclient == nil) {
		sys->fprint(stderr, "charon: cannot load Webclient: %r\n");
		raise "fail:no webclient";
	}
	err := webclient->init();
	if(err != nil) {
		sys->fprint(stderr, "charon: webclient init: %s\n", err);
		raise "fail:webclient";
	}

	html = load HTML HTML->PATH;
	if(html == nil) {
		sys->fprint(stderr, "charon: cannot load HTML: %r\n");
		raise "fail:no html";
	}

	htmlfmt = load Formatter "/dis/xenith/render/htmlfmt.dis";
	if(htmlfmt == nil) {
		sys->fprint(stderr, "charon: cannot load htmlfmt: %r\n");
		raise "fail:no htmlfmt";
	}
	htmlfmt->init();

	sys->pctl(Sys->NEWPGRP, nil);
	wmclient->init();

	# Init page state
	page = ref Page("", "Charon", "", array[0] of string, 0,
		array[0] of ref Link, 0, "", "ready");

	# Init history
	history = array[MAXHIST] of ref HistEntry;

	# Init filesystem
	initbrowserdir();

	# Create window
	w = wmclient->window(ctxt, "Charon", Wmclient->Appl);
	display = w.display;

	# Load font
	font = Font.open(display, "/fonts/combined/unicode.14.font");
	if(font == nil)
		font = Font.open(display, "/fonts/10646/9x15/9x15.font");
	if(font == nil)
		font = Font.open(display, "*default*");
	if(font == nil) {
		sys->fprint(stderr, "charon: cannot load font\n");
		raise "fail:no font";
	}

	# Load theme
	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme != nil) {
		th := lucitheme->gettheme();
		bgcolor = display.color(th.editbg);
		fgcolor = display.color(th.edittext);
		linkcolor = display.color(16r2266CCFF);
		urlbgcolor = display.color(th.editstatus);
		urlfgcolor = display.color(th.editstattext);
		lncolor = display.color(th.editlineno);
	} else {
		bgcolor = display.color(BG);
		fgcolor = display.color(FG);
		linkcolor = display.color(LINKFG);
		urlbgcolor = display.color(URLBG);
		urlfgcolor = display.color(URLFG);
		lncolor = display.color(LNCOL);
	}

	# Set up window
	w.reshape(Rect((0, 0), (800, 600)));
	w.startinput("kbd" :: "ptr" :: nil);
	w.onscreen(nil);

	if(menumod != nil) {
		menumod->init(display, font);
		menu = menumod->new(array[] of {
			"back", "forward", "reload", "stop", "go to URL", "home"
		});
	}

	# Parse arguments for start URL
	starturl := "";
	argv = tl argv;
	if(argv != nil)
		starturl = hd argv;

	# Init navigation channels and start navigator thread
	navchan = chan of string;
	navdone = chan of ref Page;
	spawn navigator(navchan, navdone);

	redraw();

	# Navigate to start URL if given
	if(starturl != "")
		requestnav(starturl);

	# Timer for polling filesystem commands
	ticks := chan of int;
	spawn timer(ticks, 500);

	# Main event loop
	for(;;) alt {

	ctl := <-w.ctl or
	ctl = <-w.ctxt.ctl =>
		w.wmctl(ctl);
		if(ctl != nil && ctl[0] == '!')
			redraw();

	rawkey := <-w.ctxt.kbd =>
		key := filterkbd(rawkey);
		if(key >= 0) {
			handlekey(key);
			redraw();
		}

	p := <-w.ctxt.ptr =>
		if(!w.pointer(*p)) {
			if(p.buttons & 4 && menumod != nil && menu != nil) {
				# Button 3: context menu
				n := menu.show(w.image, p.xy, w.ctxt.ptr);
				case n {
				0 => goback();
				1 => goforward();
				2 => requestnav(page.url);
				3 => page.status = "ready";
				4 => startinput(MURL);
				5 => requestnav("about:blank");
				}
				redraw();
			} else if(p.buttons & 2) {
				# Button 2: paste URL and navigate
				buf := wmclient->snarfget();
				if(buf != nil && buf != "") {
					buf = strip(buf);
					if(isallowedurl(buf))
						requestnav(buf);
				}
			} else if(p.buttons & 8) {
				# Scroll up
				topline -= 3;
				if(topline < 0)
					topline = 0;
				redraw();
			} else if(p.buttons & 16) {
				# Scroll down
				topline += 3;
				clampscroll();
				redraw();
			} else if(p.buttons & 1) {
				# Button 1: check scrollbar or click link
				r := w.image.r;
				stath := font.height + MARGIN * 2;
				scrollr := Rect((r.min.x, r.min.y),
					(r.min.x + SCROLLW, r.max.y - stath));
				if(scrollr.contains(p.xy)) {
					handlescrollclick(scrollr, p.xy);
					redraw();
				} else {
					# Check if clicking a link number
					linkn := findlinkat(p.xy);
					if(linkn > 0)
						requestfollow(linkn);
				}
			}
		}

	newpage := <-navdone =>
		# Navigation completed — atomically update all page state
		page = newpage;
		statedirty = 1;
		if(navfromhist) {
			topline = navhistscroll;
			clampscroll();
			navfromhist = 0;
		} else {
			topline = 0;
			if(page.status == "ready" && page.url != "")
				pushhist(page.url, page.title);
		}
		if(w != nil && w.image != nil && page.title != "")
			; # window title update not supported in this wmclient build
		redraw();

	<-ticks =>
		changed := checkctlfile();
		if(statedirty) {
			writebrowserstate();
			statedirty = 0;
		}
		if(changed)
			redraw();
	}
}

# ---------- Navigation ----------

# Send a navigation request to the navigator thread.
requestnav(url: string)
{
	if(url == "" || url == "about:blank") {
		page = ref Page("", "Charon", "", array[0] of string, 0,
			array[0] of ref Link, 0, "", "ready");
		topline = 0;
		redraw();
		return;
	}

	if(!isallowedurl(url)) {
		sys->fprint(stderr, "charon: blocked non-http URL: %s\n", url);
		return;
	}

	page.status = "loading";
	page.url = url;
	statedirty = 1;
	redraw();
	navchan <-= url;
}

# Resolve a link number and request navigation.
requestfollow(n: int)
{
	if(n < 1 || n > page.nlinks)
		return;
	link := page.links[n - 1];
	requestnav(link.href);
}

# Navigator thread — serializes all HTTP fetches.
# Receives URLs from navchan, fetches them, sends completed Pages to navdone.
# Uses a timeout to prevent indefinite blocking on unresponsive servers.
NAVTIMEOUT: con 60000;	# 60 second fetch timeout

navigator(req: chan of string, done: chan of ref Page)
{
	for(;;) {
		url := <-req;
		result := chan of ref Page;
		spawn fetchworker(url, result);
		timeout := chan of int;
		spawn timer(timeout, NAVTIMEOUT);
		alt {
		p := <-result =>
			done <-= p;
		<-timeout =>
			body := "Request timed out: " + url;
			lines := splitlines(body);
			done <-= ref Page(url, "Timeout", body, lines, len lines,
				array[0] of ref Link, 0, "", "error: timeout");
		}
	}
}

fetchworker(url: string, result: chan of ref Page)
{
	p := fetchpage(url, 0);
	result <-= p;
}

# Fetch a URL and return a fully-constructed Page.
# Does not touch any global state — safe to call from any thread.
# redirs tracks redirect depth to prevent infinite loops.
fetchpage(url: string, redirs: int): ref Page
{
	hdrs: list of Header;
	hdrs = Header("User-Agent", "Charon/2.0 (Infernode)") :: hdrs;
	hdrs = Header("Accept", "text/html, text/plain, */*") :: hdrs;
	(resp, err) := webclient->request("GET", url, hdrs, nil);
	if(err != nil) {
		body := "Failed to load: " + url + "\n\n" + err;
		lines := splitlines(body);
		return ref Page(url, "Error", body, lines, len lines,
			array[0] of ref Link, 0, "", "error: " + err);
	}

	# Handle redirects with depth limit
	if(resp.statuscode >= 300 && resp.statuscode < 400) {
		if(redirs >= MAXREDIR) {
			body := "Too many redirects (limit " + string MAXREDIR + ")\n\n" + url;
			lines := splitlines(body);
			return ref Page(url, "Error", body, lines, len lines,
				array[0] of ref Link, 0, "", "error: too many redirects");
		}
		loc := resp.hdrval("Location");
		if(loc != nil && loc != "") {
			loc = resolveurl(url, loc);
			return fetchpage(loc, redirs + 1);
		}
	}

	if(resp.statuscode >= 400) {
		status := sys->sprint("error: HTTP %d %s", resp.statuscode, resp.status);
		title := sys->sprint("Error %d", resp.statuscode);
		body := sys->sprint("HTTP %d %s\n\n%s", resp.statuscode, resp.status, url);
		lines := splitlines(body);
		return ref Page(url, title, body, lines, len lines,
			array[0] of ref Link, 0, "", status);
	}

	if(resp.body == nil || len resp.body == 0) {
		body := "(empty response)";
		lines := splitlines(body);
		return ref Page(url, url, body, lines, len lines,
			array[0] of ref Link, 0, "", "error: empty response");
	}

	if(len resp.body > MAXBODY)
		resp.body = resp.body[0:MAXBODY];
	bodytext := string resp.body;
	ct := resp.hdrval("Content-Type");
	if(ct == nil)
		ct = "";

	p := ref Page(url, url, "", array[0] of string, 0,
		array[0] of ref Link, 0, "", "ready");

	if(ishtml(ct, bodytext)) {
		p.title = extracttitle(resp.body);
		if(p.title == "")
			p.title = url;

		p.links = extractlinks(resp.body, url);
		p.nlinks = len p.links;
		p.forms = extractforms(resp.body);

		# Format HTML to text
		width := 80;
		if(w != nil && w.image != nil) {
			textr := textrect();
			cw := font.width("M");
			if(cw > 0)
				width = textr.dx() / cw;
			if(width < 40)
				width = 40;
			if(width > 120)
				width = 120;
		}
		formatted := htmlfmt->format(bodytext, width);
		if(formatted == nil || len formatted == 0)
			formatted = bodytext;

		p.body = injectlinknumbers(formatted, p.links);
	} else {
		p.body = bodytext;
	}

	p.lines = splitlines(p.body);
	p.nlines = len p.lines;
	return p;
}

goback()
{
	if(histpos <= 0)
		return;
	if(histpos >= 0 && histpos < nhist)
		history[histpos].scrollpos = topline;
	histpos--;
	h := history[histpos];
	navfromhist = 1;
	navhistscroll = h.scrollpos;
	requestnav(h.url);
}

goforward()
{
	if(histpos >= nhist - 1)
		return;
	if(histpos >= 0 && histpos < nhist)
		history[histpos].scrollpos = topline;
	histpos++;
	h := history[histpos];
	navfromhist = 1;
	navhistscroll = h.scrollpos;
	requestnav(h.url);
}

pushhist(url, title: string)
{
	# If not at end of history, truncate forward entries
	if(histpos >= 0 && histpos < nhist - 1)
		nhist = histpos + 1;

	if(nhist >= MAXHIST) {
		# Shift history down
		for(i := 0; i < nhist - 1; i++)
			history[i] = history[i + 1];
		nhist--;
	}

	history[nhist] = ref HistEntry(url, title, 0);
	histpos = nhist;
	nhist++;
}

# ---------- URL Validation ----------

# Check if a URL has an allowed scheme (http or https only).
isallowedurl(url: string): int
{
	lurl := tolower(url);
	if(hasprefix(lurl, "http://") || hasprefix(lurl, "https://"))
		return 1;
	return 0;
}

# ---------- HTML Processing ----------

ishtml(ct, body: string): int
{
	lct := tolower(ct);
	if(hasprefix(lct, "text/html"))
		return 1;
	# Check body for HTML markers
	sample := body;
	if(len sample > 256)
		sample = sample[0:256];
	for(i := 0; i < len sample; i++) {
		c := sample[i];
		if(c == ' ' || c == '\t' || c == '\n' || c == '\r')
			continue;
		if(c == '<') {
			rest := tolower(sample[i:]);
			if(hasprefix(rest, "<!doctype"))
				return 1;
			if(hasprefix(rest, "<html"))
				return 1;
		}
		break;
	}
	return 0;
}

extracttitle(data: array of byte): string
{
	tokens := html->lex(data, HTML->UTF8, 0);
	if(tokens == nil)
		return "";
	intitle := 0;
	title := "";
	for(i := 0; i < len tokens; i++) {
		tok := tokens[i];
		if(tok.tag == HTML->Ttitle) {
			intitle = 1;
			continue;
		}
		if(tok.tag == HTML->Ttitle + HTML->RBRA)
			break;
		if(intitle && tok.tag == HTML->Data)
			title += tok.text;
	}
	return cleanws(title);
}

extractlinks(data: array of byte, baseurl: string): array of ref Link
{
	tokens := html->lex(data, HTML->UTF8, 0);
	if(tokens == nil)
		return array[0] of ref Link;

	links: list of ref Link;
	nlinks := 0;
	inanchor := 0;
	curhref := "";
	curtext := "";

	for(i := 0; i < len tokens; i++) {
		tok := tokens[i];
		if(tok.tag == HTML->Ta) {
			(found, href) := html->attrvalue(tok.attr, "href");
			if(found) {
				inanchor = 1;
				curhref = resolveurl(baseurl, href);
				curtext = "";
			}
		} else if(tok.tag == HTML->Ta + HTML->RBRA) {
			if(inanchor && curhref != "") {
				nlinks++;
				text := cleanws(curtext);
				if(text == "")
					text = curhref;
				links = ref Link(nlinks, curhref, text) :: links;
			}
			inanchor = 0;
			curhref = "";
			curtext = "";
		} else if(inanchor && tok.tag == HTML->Data) {
			curtext += tok.text;
		}
	}

	# Reverse list into array
	result := array[nlinks] of ref Link;
	for(j := nlinks - 1; j >= 0; j--) {
		result[j] = hd links;
		links = tl links;
	}
	return result;
}

extractforms(data: array of byte): string
{
	tokens := html->lex(data, HTML->UTF8, 0);
	if(tokens == nil)
		return "";

	result := "";
	formid := -1;
	fieldid := 0;

	for(i := 0; i < len tokens; i++) {
		tok := tokens[i];
		if(tok.tag == HTML->Tform) {
			formid++;
			fieldid = 0;
			(ok1, action) := html->attrvalue(tok.attr, "action");
			(ok2, method) := html->attrvalue(tok.attr, "method");
			ok1 = ok2;
			if(method == "")
				method = "GET";
			result += sys->sprint("form%d action=%s method=%s\n",
				formid, action, method);
		} else if(tok.tag == HTML->Tinput && formid >= 0) {
			(ok3, itype) := html->attrvalue(tok.attr, "type");
			(ok4, iname) := html->attrvalue(tok.attr, "name");
			(ok5, ivalue) := html->attrvalue(tok.attr, "value");
			ok3 = ok4; ok4 = ok5;
			if(itype == "")
				itype = "text";
			result += sys->sprint("  form%d field%d %s name=%s value=%s\n",
				formid, fieldid, itype, iname, ivalue);
			fieldid++;
		} else if(tok.tag == HTML->Tselect && formid >= 0) {
			(_, iname) := html->attrvalue(tok.attr, "name");
			result += sys->sprint("  form%d field%d select name=%s\n",
				formid, fieldid, iname);
			fieldid++;
		} else if(tok.tag == HTML->Ttextarea && formid >= 0) {
			(_, iname) := html->attrvalue(tok.attr, "name");
			result += sys->sprint("  form%d field%d textarea name=%s\n",
				formid, fieldid, iname);
			fieldid++;
		}
	}
	return result;
}

# Inject [N] markers near link text in the formatted output.
# Simple approach: append link index at end of document.
injectlinknumbers(text: string, links: array of ref Link): string
{
	if(len links == 0)
		return text;

	result := text;
	if(len result > 0 && result[len result - 1] != '\n')
		result += "\n";
	result += "\n--- Links ---\n";
	for(i := 0; i < len links; i++) {
		l := links[i];
		result += sys->sprint("[%d] %s\n     %s\n", l.num, l.text, l.href);
	}
	return result;
}

# ---------- URL Helpers ----------

resolveurl(base, href: string): string
{
	if(href == nil || href == "")
		return base;

	lhref := tolower(href);
	if(hasprefix(lhref, "http://") || hasprefix(lhref, "https://"))
		return href;

	if(hasprefix(href, "//")) {
		# Protocol-relative
		if(hasprefix(tolower(base), "https://"))
			return "https:" + href;
		return "http:" + href;
	}

	# Parse base URL
	(scheme, rest) := splitscheme(base);
	if(scheme == "")
		return href;

	# Find host part
	host := rest;
	path := "/";
	for(i := 0; i < len rest; i++) {
		if(rest[i] == '/') {
			host = rest[0:i];
			path = rest[i:];
			break;
		}
	}

	if(hasprefix(href, "/")) {
		# Absolute path
		return scheme + host + href;
	}

	# Relative path - remove last component from base path
	lastslash := 0;
	for(i = 0; i < len path; i++) {
		if(path[i] == '/')
			lastslash = i;
	}
	dir := path[0:lastslash + 1];
	return scheme + host + canonpath(dir + href);
}

# Remove . and .. segments from a URL path.
canonpath(p: string): string
{
	if(p == "" || p == "/")
		return p;

	# Split into segments
	segs: list of string;
	start := 0;
	for(i := 0; i <= len p; i++) {
		if(i == len p || p[i] == '/') {
			seg := p[start:i];
			if(seg == "..") {
				if(segs != nil)
					segs = tl segs;
			} else if(seg != "" && seg != ".")
				segs = seg :: segs;
			start = i + 1;
		}
	}

	# Rebuild path
	result := "";
	for(; segs != nil; segs = tl segs)
		result = "/" + hd segs + result;
	if(result == "")
		result = "/";
	# Preserve trailing slash
	if(len p > 0 && p[len p - 1] == '/' && len result > 1 && result[len result - 1] != '/')
		result += "/";
	return result;
}

splitscheme(url: string): (string, string)
{
	for(i := 0; i < len url; i++) {
		if(url[i] == ':' && i + 2 < len url && url[i+1] == '/' && url[i+2] == '/')
			return (url[0:i+3], url[i+3:]);
	}
	return ("", url);
}

# ---------- Rendering ----------

textrect(): Rect
{
	if(w.image == nil)
		return Rect((0, 0), (0, 0));
	r := w.image.r;
	stath := font.height + MARGIN * 2;
	return Rect((r.min.x + SCROLLW + MARGIN, r.min.y + MARGIN),
		(r.max.x - MARGIN, r.max.y - stath));
}

redraw()
{
	if(w.image == nil)
		return;

	screen := w.image;
	r := screen.r;
	stath := font.height + MARGIN * 2;

	# Clear background
	screen.draw(r, bgcolor, nil, Point(0, 0));

	textr := textrect();
	maxvrows := 1;
	if(font.height > 0)
		maxvrows = textr.dy() / font.height;

	# Draw scrollbar
	drawscrollbar(screen, Rect((r.min.x, r.min.y),
		(r.min.x + SCROLLW, r.max.y - stath)));

	# Take local snapshot of page state for safe rendering
	curpage := page;
	curlines := curpage.lines;
	curnlines := curpage.nlines;

	# Draw text lines
	y := textr.min.y;
	vrow := 0;
	for(i := topline; i < curnlines && vrow < maxvrows; i++) {
		if(i >= len curlines)
			break;
		line := curlines[i];

		# Detect link lines and color them
		col := fgcolor;
		if(islinksection(line))
			col = linkcolor;

		screen.text(Point(textr.min.x, y), col, Point(0, 0), font, line);
		y += font.height;
		vrow++;
	}
	vislines = maxvrows;

	# Draw status bar
	drawstatus(screen, Rect((r.min.x, r.max.y - stath), r.max));

	screen.flush(Draw->Flushnow);
}

islinksection(line: string): int
{
	if(len line < 3)
		return 0;
	if(line[0] == '[' && line[1] >= '0' && line[1] <= '9')
		return 1;
	return 0;
}

drawscrollbar(screen: ref Image, r: Rect)
{
	screen.draw(r, urlbgcolor, nil, Point(0, 0));

	if(page.nlines <= 0 || vislines <= 0)
		return;

	totalh := r.dy();
	thumbh := (vislines * totalh) / page.nlines;
	if(thumbh < 10)
		thumbh = 10;
	if(thumbh > totalh)
		thumbh = totalh;
	thumby := r.min.y;
	if(page.nlines > vislines)
		thumby = r.min.y + (topline * (totalh - thumbh)) / (page.nlines - vislines);

	thumbr := Rect((r.min.x + 2, thumby), (r.max.x - 2, thumby + thumbh));
	screen.draw(thumbr, lncolor, nil, Point(0, 0));
}

drawstatus(screen: ref Image, r: Rect)
{
	screen.draw(r, urlbgcolor, nil, Point(0, 0));
	screen.line(Point(r.min.x, r.min.y), Point(r.max.x, r.min.y),
		0, 0, 0, lncolor, Point(0, 0));

	x := r.min.x + MARGIN;
	y := r.min.y + MARGIN;

	case inputmode {
	MURL =>
		prompt := "URL: " + inputbuf + "_";
		screen.text(Point(x, y), fgcolor, Point(0, 0), font, prompt);
	MLINK =>
		prompt := "Link #: " + inputbuf + "_";
		screen.text(Point(x, y), fgcolor, Point(0, 0), font, prompt);
	* =>
		# Show status and URL
		info := page.url;
		if(info == "")
			info = "(no page loaded)";
		if(page.status == "loading")
			info = "Loading: " + info;
		else if(hasprefix(page.status, "error:"))
			info = page.status;

		screen.text(Point(x, y), urlfgcolor, Point(0, 0), font, info);

		# Show link count on right
		if(page.nlinks > 0) {
			linfo := sys->sprint("%d links", page.nlinks);
			lw := font.width(linfo);
			screen.text(Point(r.max.x - lw - MARGIN, y),
				urlfgcolor, Point(0, 0), font, linfo);
		}
	}
}

handlescrollclick(scrollr: Rect, xy: Point)
{
	if(page.nlines <= 0 || vislines <= 0)
		return;

	totalh := scrollr.dy();
	thumbh := (vislines * totalh) / page.nlines;
	if(thumbh < 10) thumbh = 10;
	if(thumbh > totalh) thumbh = totalh;
	thumby := scrollr.min.y;
	if(page.nlines > vislines)
		thumby = scrollr.min.y + (topline * (totalh - thumbh)) /
			(page.nlines - vislines);

	if(xy.y < thumby) {
		topline -= vislines;
		if(topline < 0) topline = 0;
	} else if(xy.y > thumby + thumbh) {
		topline += vislines;
		clampscroll();
	}
}

# Find link number at a screen position.
# Looks at formatted text for [N] pattern on the clicked line.
findlinkat(xy: Point): int
{
	textr := textrect();
	if(!textr.contains(xy))
		return 0;
	vy := xy.y - textr.min.y;
	if(font.height <= 0)
		return 0;
	clickrow := vy / font.height;
	lineno := topline + clickrow;
	if(lineno < 0 || lineno >= page.nlines)
		return 0;
	if(lineno >= len page.lines)
		return 0;

	line := page.lines[lineno];
	# Check if this line starts with [N]
	if(len line < 3 || line[0] != '[')
		return 0;
	n := 0;
	for(i := 1; i < len line; i++) {
		if(line[i] == ']')
			break;
		if(line[i] < '0' || line[i] > '9')
			return 0;
		n = n * 10 + (line[i] - '0');
	}
	if(n > 0 && n <= page.nlinks)
		return n;
	return 0;
}

clampscroll()
{
	maxtl := page.nlines - vislines;
	if(maxtl < 0) maxtl = 0;
	if(topline > maxtl) topline = maxtl;
	if(topline < 0) topline = 0;
}

# ---------- Keyboard ----------

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
		# Alt+arrow keys
		if(c == Kleft)
			return -2;	# alt-left = back
		if(c == Kright)
			return -3;	# alt-right = forward
	2 =>
		kbdescstate = 0;
		if(c == 'A') return Kup;
		if(c == 'B') return Kdown;
		if(c == 'C') return Kright;
		if(c == 'D') return Kleft;
		if(c == 'H') return Khome;
		if(c == 'F') return Kend;
		if(c >= '1' && c <= '9') {
			kbdescarg = c - '0';
			kbdescstate = 3;
			return -1;
		}
		return -1;
	3 =>
		if(c == '~') {
			kbdescstate = 0;
			if(kbdescarg == 1 || kbdescarg == 7) return Khome;
			if(kbdescarg == 4 || kbdescarg == 8) return Kend;
			if(kbdescarg == 5) return Kpgup;
			if(kbdescarg == 6) return Kpgdown;
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
	if(inputmode != MNONE) {
		handleinputkey(key);
		return;
	}

	# Check for alt-arrow (back/forward)
	if(key == -2) {
		goback();
		return;
	}
	if(key == -3) {
		goforward();
		return;
	}

	# Ctrl keys
	ctrl := 0;
	if(key >= 1 && key <= 26 && key != Kbs && key != '\n' && key != '\t')
		ctrl = 1;

	if(ctrl) {
		case key {
		7 =>	# Ctrl-G: follow link
			startinput(MLINK);
		12 =>	# Ctrl-L: enter URL
			startinput(MURL);
		18 =>	# Ctrl-R: reload
			if(page.url != "")
				requestnav(page.url);
		}
		return;
	}

	case key {
	Kup =>
		topline--;
		if(topline < 0) topline = 0;
	Kdown =>
		topline++;
		clampscroll();
	Kpgup =>
		topline -= vislines;
		if(topline < 0) topline = 0;
	Kpgdown =>
		topline += vislines;
		clampscroll();
	Khome =>
		topline = 0;
	Kend =>
		topline = page.nlines - vislines;
		if(topline < 0) topline = 0;
	' ' =>
		# Space = page down
		topline += vislines;
		clampscroll();
	}
}

startinput(mode: int)
{
	inputmode = mode;
	inputbuf = "";
	if(mode == MURL && page.url != "")
		inputbuf = page.url;
}

handleinputkey(key: int)
{
	if(key == Kesc) {
		inputmode = MNONE;
		inputbuf = "";
		return;
	}

	if(key == '\n') {
		buf := inputbuf;
		mode := inputmode;
		inputmode = MNONE;
		inputbuf = "";

		case mode {
		MURL =>
			buf = strip(buf);
			if(buf != "") {
				if(!hasprefix(tolower(buf), "http://") &&
				   !hasprefix(tolower(buf), "https://"))
					buf = "https://" + buf;
				requestnav(buf);
			}
		MLINK =>
			n := atoi(buf);
			if(n > 0)
				requestfollow(n);
		}
		return;
	}

	if(key == Kbs) {
		if(len inputbuf > 0)
			inputbuf = inputbuf[0:len inputbuf - 1];
		return;
	}

	if(key >= 16r20 && key < 16rFF00 && len inputbuf < 4096)
		inputbuf[len inputbuf] = key;
}

# ---------- Filesystem Interface ----------

initbrowserdir()
{
	mkdirq("/tmp/veltro");
	mkdirq(BROWSER_DIR);
}

mkdirq(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd != nil) {
		fd = nil;
		return;
	}
	fd = sys->create(path, Sys->OREAD, Sys->DMDIR | 8r700);
	fd = nil;
}

writebrowserstate()
{
	# Take local snapshot to avoid races with navigator thread
	p := page;
	writestatefile(BROWSER_DIR + "/url", p.url);
	writestatefile(BROWSER_DIR + "/title", p.title);
	writestatefile(BROWSER_DIR + "/body", p.body);
	writestatefile(BROWSER_DIR + "/status", p.status);

	# Write link index
	linktext := "";
	plinks := p.links;
	pnlinks := p.nlinks;
	if(pnlinks > len plinks)
		pnlinks = len plinks;
	for(i := 0; i < pnlinks; i++) {
		l := plinks[i];
		linktext += sys->sprint("%d %s %s\n", l.num, l.href, l.text);
	}
	writestatefile(BROWSER_DIR + "/links", linktext);

	# Write forms
	writestatefile(BROWSER_DIR + "/forms", p.forms);
}

writestatefile(path, data: string)
{
	fd := sys->create(path, Sys->OWRITE, 8r600);
	if(fd == nil)
		return;
	b := array of byte data;
	sys->write(fd, b, len b);
	fd = nil;
}

checkctlfile(): int
{
	cmd := readctlfile(BROWSER_DIR + "/ctl");
	if(cmd == nil || cmd == "")
		return 0;

	(verb, rest) := splitfirst(cmd);
	verb = tolower(verb);

	case verb {
	"navigate" or "go" =>
		rest = strip(rest);
		if(rest != "" && isallowedurl(rest))
			requestnav(rest);
		else if(rest != "")
			sys->fprint(stderr, "charon: ctl: blocked non-http URL: %s\n", rest);
	"back" =>
		goback();
	"forward" =>
		goforward();
	"reload" =>
		if(page.url != "")
			requestnav(page.url);
	"follow" =>
		n := atoi(strip(rest));
		if(n > 0 && n <= page.nlinks)
			requestfollow(n);
	"stop" =>
		page.status = "ready";
		statedirty = 1;
	"search" =>
		q := strip(rest);
		if(len q > 0 && len q <= 1024)
			searchpage(q);
	}
	statedirty = 1;
	return 1;
}

# Read and atomically consume the ctl file.
# Reads, then truncates via the same fd to avoid TOCTOU races.
readctlfile(path: string): string
{
	fd := sys->open(path, Sys->ORDWR);
	if(fd == nil)
		return nil;
	buf := array[4096] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0) {
		fd = nil;
		return nil;
	}
	s := string buf[0:n];
	# Truncate by recreating through the same path while we still hold fd
	# Use create to atomically replace the file contents
	tfd := sys->create(path, Sys->OWRITE, 8r600);
	tfd = nil;
	fd = nil;
	return strip(s);
}

searchpage(query: string)
{
	if(query == "")
		return;
	lquery := tolower(query);
	# Search from current position
	start := topline + 1;
	if(start >= page.nlines)
		start = 0;
	for(i := 0; i < page.nlines; i++) {
		idx := (start + i) % page.nlines;
		if(idx >= len page.lines)
			continue;
		if(contains(tolower(page.lines[idx]), lquery)) {
			topline = idx;
			clampscroll();
			return;
		}
	}
}

# ---------- Utility Functions ----------

timer(ch: chan of int, ms: int)
{
	for(;;) {
		sys->sleep(ms);
		ch <-= 1;
	}
}

splitlines(s: string): array of string
{
	if(s == "" || len s == 0)
		return array[] of { "" };

	# Count lines
	n := 1;
	for(i := 0; i < len s; i++) {
		if(s[i] == '\n')
			n++;
	}

	lines := array[n] of string;
	idx := 0;
	start := 0;
	for(i = 0; i < len s; i++) {
		if(s[i] == '\n') {
			lines[idx++] = s[start:i];
			start = i + 1;
		}
	}
	if(start <= len s)
		lines[idx] = s[start:];
	return lines;
}

strip(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r'))
		i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\n' || s[j-1] == '\r'))
		j--;
	if(i >= j)
		return "";
	return s[i:j];
}

cleanws(s: string): string
{
	result := "";
	lastspace := 1;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c == '\n' || c == '\r' || c == '\t')
			c = ' ';
		if(c == ' ') {
			if(!lastspace) {
				result[len result] = ' ';
				lastspace = 1;
			}
		} else {
			result[len result] = c;
			lastspace = 0;
		}
	}
	if(len result > 0 && result[len result - 1] == ' ')
		result = result[0:len result - 1];
	return result;
}

splitfirst(s: string): (string, string)
{
	s = strip(s);
	for(i := 0; i < len s; i++) {
		if(s[i] == ' ' || s[i] == '\t')
			return (s[0:i], strip(s[i:]));
	}
	return (s, "");
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

contains(s, sub: string): int
{
	if(len sub == 0)
		return 1;
	if(len sub > len s)
		return 0;
	for(i := 0; i <= len s - len sub; i++) {
		if(s[i:i + len sub] == sub)
			return 1;
	}
	return 0;
}

tolower(s: string): string
{
	result := "";
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c >= 'A' && c <= 'Z')
			c += 'a' - 'A';
		result[len result] = c;
	}
	return result;
}

atoi(s: string): int
{
	s = strip(s);
	n := 0;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c < '0' || c > '9')
			break;
		n = n * 10 + (c - '0');
	}
	return n;
}
