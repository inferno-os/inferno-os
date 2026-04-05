implement SignalFeed;

#
# signal-feed - Matrix display module for TBL4 signal stream
#
# Reads /n/tbl4/signals (JSON array), displays a scrollable
# color-coded list of recent signals.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	drawm: Draw;
	Display, Font, Image, Point, Rect: import drawm;

include "lucitheme.m";

include "widget.m";
	widgetmod: Widget;
	Scrollbar: import widgetmod;

include "matrix.m";

SignalFeed: module
{
	init:	fn(display: ref Display, font: ref Font, mount: string): string;
	resize:	fn(r: Rect);
	update:	fn(): int;
	draw:	fn(dst: ref Image);
	pointer:	fn(p: ref Draw->Pointer): int;
	key:	fn(k: int): int;
	retheme:	fn(display: ref Display);
	shutdown:	fn();
};

Signal: adt
{
	asset: string;
	direction: string;
	confidence: string;
	signal_type: string;
	timestamp: string;
};

display_g: ref Display;
font_g: ref Font;
mountpath: string;
r_g: Rect;
signals: array of ref Signal;
scroll: ref Scrollbar;
scrolltop: int;

bgcolor: ref Image;
textcol: ref Image;
dimcol: ref Image;
headcol: ref Image;
greencol: ref Image;
redcol: ref Image;
yellowcol: ref Image;
bordercol: ref Image;

ROWH: con 18;
HDRH: con 24;
PAD: con 6;

init(display: ref Display, font: ref Font, mount: string): string
{
	sys = load Sys Sys->PATH;
	drawm = load Draw Draw->PATH;

	if(widgetmod == nil) {
		widgetmod = load Widget Widget->PATH;
		if(widgetmod != nil)
			widgetmod->init(display, font);
	}

	display_g = display;
	font_g = font;
	mountpath = mount;
	signals = nil;
	scrolltop = 0;
	loadcolors();
	return nil;
}

loadcolors()
{
	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme != nil) {
		th := lucitheme->gettheme();
		bgcolor  = display_g.color(th.bg);
		textcol  = display_g.color(th.text);
		dimcol   = display_g.color(th.dim);
		headcol  = display_g.color(th.accent);
		greencol = display_g.color(th.green);
		redcol   = display_g.color(th.red);
		yellowcol= display_g.color(th.yellow);
		bordercol= display_g.color(th.border);
	} else {
		bgcolor  = display_g.color(int 16r1A1A2EFF);
		textcol  = display_g.color(int 16rDDDDDDFF);
		dimcol   = display_g.color(int 16r888888FF);
		headcol  = display_g.color(int 16r60A5FAFF);
		greencol = display_g.color(int 16r44FF44FF);
		redcol   = display_g.color(int 16rFF4444FF);
		yellowcol= display_g.color(int 16rFFFF44FF);
		bordercol= display_g.color(int 16r333355FF);
	}
}

resize(r: Rect)
{
	r_g = r;
	sw := 0;
	if(widgetmod != nil)
		sw = widgetmod->scrollwidth();
	scrollr := Rect((r.max.x - sw, r.min.y + HDRH), r.max);
	if(scroll == nil)
		scroll = Scrollbar.new(scrollr, 1);
	else
		scroll.resize(scrollr);
}

update(): int
{
	readsignals();
	return 1;
}

draw(dst: ref Image)
{
	if(dst == nil)
		return;

	dst.draw(r_g, bgcolor, nil, (0, 0));

	# Title
	titlept := Point(r_g.min.x + PAD, r_g.min.y + PAD);
	dst.text(titlept, headcol, (0, 0), font_g, "Signals");

	# Header line
	hdry := r_g.min.y + HDRH;
	dst.draw(Rect((r_g.min.x, hdry - 1), (r_g.max.x, hdry)), bordercol, nil, (0, 0));

	if(signals == nil || len signals == 0) {
		emptypt := Point(r_g.min.x + PAD, hdry + PAD + font_g.height);
		dst.text(emptypt, dimcol, (0, 0), font_g, "No signals");
		return;
	}

	visrows := (r_g.max.y - hdry) / ROWH;
	if(visrows < 1) visrows = 1;
	if(scrolltop > len signals - visrows) scrolltop = len signals - visrows;
	if(scrolltop < 0) scrolltop = 0;

	y := hdry + 2;
	for(i := scrolltop; i < len signals && y + ROWH <= r_g.max.y; i++) {
		s := signals[i];

		# Direction color
		col := textcol;
		if(s.direction == "long")
			col = greencol;
		else if(s.direction == "short")
			col = redcol;

		# Direction indicator
		pt := Point(r_g.min.x + PAD, y + 2);
		indicator := "+";
		if(s.direction == "short")
			indicator = "-";
		else if(s.direction == "neutral")
			indicator = "~";
		dst.text(pt, col, (0, 0), font_g, indicator);

		# Asset
		pt.x = r_g.min.x + PAD + 16;
		dst.text(pt, textcol, (0, 0), font_g, s.asset);

		# Confidence
		pt.x = r_g.min.x + r_g.dx() * 30 / 100;
		dst.text(pt, dimcol, (0, 0), font_g, s.confidence);

		# Type
		pt.x = r_g.min.x + r_g.dx() * 50 / 100;
		dst.text(pt, dimcol, (0, 0), font_g, s.signal_type);

		# Timestamp (show time only)
		pt.x = r_g.min.x + r_g.dx() * 72 / 100;
		ts := s.timestamp;
		# Extract HH:MM from ISO timestamp
		tidx := strfind(ts, "T");
		if(tidx >= 0 && tidx + 6 <= len ts)
			ts = ts[tidx+1:tidx+6];
		dst.text(pt, dimcol, (0, 0), font_g, ts);

		y += ROWH;
	}

	if(scroll != nil) {
		scroll.total = len signals;
		scroll.visible = visrows;
		scroll.origin = scrolltop;
		scroll.draw(dst);
	}
}

pointer(p: ref Draw->Pointer): int
{
	if(!r_g.contains(p.xy))
		return 0;
	if(scroll != nil) {
		if(p.buttons & 8) { scrolltop = scroll.wheel(8, 1); return 1; }
		if(p.buttons & 16) { scrolltop = scroll.wheel(16, 1); return 1; }
		if(scroll.isactive()) {
			newo := scroll.track(p);
			if(newo >= 0) scrolltop = newo;
			return 1;
		}
		sw := 0;
		if(widgetmod != nil) sw = widgetmod->scrollwidth();
		scrollr := Rect((r_g.max.x - sw, r_g.min.y + HDRH), r_g.max);
		if(scrollr.contains(p.xy) && (p.buttons & 7)) {
			newo := scroll.event(p);
			if(newo >= 0) scrolltop = newo;
			return 1;
		}
	}
	return 0;
}

key(nil: int): int { return 0; }

retheme(display: ref Display)
{
	display_g = display;
	loadcolors();
}

shutdown() { signals = nil; }

# ── Data ─��─────────────────────────────���────────────────────

# Parse Plan 9 text: one signal per line
# Format: id asset direction confidence signal_type timestamp
readsignals()
{
	fd := sys->open(mountpath, Sys->OREAD);
	if(fd == nil) {
		signals = nil;
		return;
	}
	content := "";
	buf := array[32768] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		content += string buf[0:n];
	}
	fd = nil;
	if(content == "") {
		signals = nil;
		return;
	}

	lines := splitlines(content);
	slist: list of ref Signal;
	count := 0;
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		(ntoks, toks) := sys->tokenize(line, " \t");
		if(ntoks < 6)
			continue;
		s := ref Signal("", "", "", "", "");
		toks = tl toks;	# skip id
		s.asset = hd toks; toks = tl toks;
		s.direction = hd toks; toks = tl toks;
		s.confidence = hd toks; toks = tl toks;
		s.signal_type = hd toks; toks = tl toks;
		s.timestamp = hd toks;
		slist = s :: slist;
		count++;
	}

	# Reverse into array (signals arrive newest-first from server)
	signals = array[count] of ref Signal;
	i := 0;
	for(; slist != nil; slist = tl slist) {
		signals[count - 1 - i] = hd slist;
		i++;
	}
}

splitlines(s: string): list of string
{
	lines: list of string;
	start := 0;
	for(i := 0; i < len s; i++) {
		if(s[i] == '\n') {
			if(i > start)
				lines = s[start:i] :: lines;
			start = i + 1;
		}
	}
	if(start < len s)
		lines = s[start:] :: lines;
	# Reverse
	rev: list of string;
	for(; lines != nil; lines = tl lines)
		rev = hd lines :: rev;
	return rev;
}

strfind(s: string, sub: string): int
{
	slen := len sub;
	for(i := 0; i + slen <= len s; i++)
		if(s[i:i+slen] == sub)
			return i;
	return -1;
}
