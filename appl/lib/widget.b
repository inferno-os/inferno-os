implement Widget;

#
# widget.b — Native Limbo widget toolkit
#
# Composable, theme-driven, flat-drawn UI widgets.
# See module/widget.m for interface documentation.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Font, Image, Point, Rect, Pointer: import draw;

include "lucitheme.m";

include "widget.m";

# ── Module state ──────────────────────────────────────────────

SCROLLW: con 12;	# scrollbar width in pixels
MARGIN:  con 4;		# text padding in status bar
MINTHUMB: con 10;	# minimum thumb size in pixels

wfont:    ref Font;

# Cached colour images (created from theme in init/retheme)
trackcolor:  ref Image;
thumbcolor:  ref Image;
statusbg:    ref Image;
statusfg:    ref Image;
sepcolor:    ref Image;
promptfg:    ref Image;	# text colour in prompt mode (edittext)

# ── Internal scrollbar drag state ─────────────────────────────
#
# Stored per-scrollbar.  We use a small helper ADT that is NOT
# exported — the Scrollbar ADT in widget.m has no hidden fields,
# so we keep a parallel ref keyed by the Scrollbar pointer.
# For simplicity (and because apps typically have 0-1 active
# scrollbars), we track a single active drag globally.
#

activesb:   ref Scrollbar;	# scrollbar currently being dragged
dragoffset: int;		# pointer y offset within thumb at grab start
dragbutton: int;		# which button started the drag (1 or 2)

# ── Module functions ──────────────────────────────────────────

init(display: ref Display, font: ref Font)
{
	sys  = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wfont = font;
	activesb = nil;
	loadcolors(display);
}

retheme(display: ref Display)
{
	loadcolors(display);
}

loadcolors(display: ref Display)
{
	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme == nil) {
		# Fallback to hardcoded defaults
		trackcolor = display.color(int 16rE8E8E8FF);
		thumbcolor = display.color(int 16rBBBBBBFF);
		statusbg   = display.color(int 16rE8E8E8FF);
		statusfg   = display.color(int 16r555555FF);
		sepcolor   = display.color(int 16rBBBBBBFF);
		promptfg   = display.color(int 16r333333FF);
		return;
	}
	th := lucitheme->gettheme();
	trackcolor = display.color(th.editscroll);
	thumbcolor = display.color(th.editthumb);
	statusbg   = display.color(th.editstatus);
	statusfg   = display.color(th.editstattext);
	sepcolor   = display.color(th.editlineno);
	promptfg   = display.color(th.edittext);
}

scrollwidth(): int
{
	return SCROLLW;
}

statusheight(): int
{
	if(wfont == nil)
		return MARGIN * 2 + 14;	# reasonable fallback
	return wfont.height + MARGIN * 2;
}

# ── Kbdfilter ─────────────────────────────────────────────────

Kbdfilter.new(): ref Kbdfilter
{
	return ref Kbdfilter(0, 0);
}

Kbdfilter.filter(kf: self ref Kbdfilter, c: int): int
{
	if(c >= 16rFF00)
		return c;
	case kf.state {
	0 =>
		if(c == 27) {
			kf.state = 1;
			return -1;
		}
	1 =>
		kf.state = 0;
		if(c == '[') {
			kf.state = 2;
			kf.arg = 0;
			return -1;
		}
		# bare ESC + char: deliver the char
	2 =>
		kf.state = 0;
		if(c == 'A') return Kup;
		if(c == 'B') return Kdown;
		if(c == 'C') return Kright;
		if(c == 'D') return Kleft;
		if(c == 'H') return Khome;
		if(c == 'F') return Kend;
		if(c == '1' || c == '4' || c == '5' || c == '6'
		    || c == '7' || c == '8') {
			kf.arg = c - '0';
			kf.state = 3;
			return -1;
		}
		return -1;	# unknown sequence, discard
	3 =>
		if(c == '~') {
			kf.state = 0;
			if(kf.arg == 1 || kf.arg == 7) return Khome;
			if(kf.arg == 4 || kf.arg == 8) return Kend;
			if(kf.arg == 5) return Kpgup;
			if(kf.arg == 6) return Kpgdown;
			return -1;
		}
		if(c >= '0' && c <= '9') {
			kf.arg = kf.arg * 10 + (c - '0');
			return -1;
		}
		kf.state = 0;
		return -1;
	}
	return c;
}

# ── Scrollbar ─────────────────────────────────────────────────

# Return the primary-axis length and the pointer coordinate on that axis.
sblength(sb: ref Scrollbar): int
{
	if(sb.vert)
		return sb.r.dy();
	return sb.r.dx();
}

sbpos(sb: ref Scrollbar, p: Point): int
{
	if(sb.vert)
		return p.y;
	return p.x;
}

sbmin(sb: ref Scrollbar): int
{
	if(sb.vert)
		return sb.r.min.y;
	return sb.r.min.x;
}

# Compute thumb rectangle within scrollbar rect.
thumbrect(sb: ref Scrollbar): Rect
{
	r := sb.r;
	tlen := sblength(sb);
	if(sb.total <= 0 || sb.visible <= 0 || tlen <= 0) {
		if(sb.vert)
			return Rect((r.min.x + 2, r.min.y), (r.max.x - 2, r.min.y));
		return Rect((r.min.x, r.min.y + 2), (r.min.x, r.max.y - 2));
	}

	thumbsz := (sb.visible * tlen) / sb.total;
	if(thumbsz < MINTHUMB)
		thumbsz = MINTHUMB;
	if(thumbsz > tlen)
		thumbsz = tlen;

	tpos := sbmin(sb);
	if(sb.total > sb.visible)
		tpos = sbmin(sb) + (sb.origin * (tlen - thumbsz)) / (sb.total - sb.visible);

	if(sb.vert)
		return Rect((r.min.x + 2, tpos), (r.max.x - 2, tpos + thumbsz));
	return Rect((tpos, r.min.y + 2), (tpos + thumbsz, r.max.y - 2));
}

# Clamp origin to valid range.
clamporigin(sb: ref Scrollbar): int
{
	o := sb.origin;
	if(o < 0)
		o = 0;
	maxtl := sb.total - sb.visible;
	if(maxtl < 0)
		maxtl = 0;
	if(o > maxtl)
		o = maxtl;
	return o;
}

# Convert a coordinate on the primary axis to an absolute origin.
postoorigin(sb: ref Scrollbar, v: int): int
{
	tlen := sblength(sb);
	if(tlen <= 0 || sb.total <= 0)
		return 0;
	frac := v - sbmin(sb);
	if(frac < 0)
		frac = 0;
	if(frac > tlen)
		frac = tlen;
	o := (frac * sb.total) / tlen;
	maxtl := sb.total - sb.visible;
	if(maxtl < 0)
		maxtl = 0;
	if(o > maxtl)
		o = maxtl;
	return o;
}

Scrollbar.new(r: Rect, vert: int): ref Scrollbar
{
	return ref Scrollbar(r, 0, 0, 0, vert);
}

Scrollbar.draw(sb: self ref Scrollbar, dst: ref Image)
{
	# Track background
	dst.draw(sb.r, trackcolor, nil, Point(0, 0));

	if(sb.total <= 0 || sb.visible <= 0)
		return;

	# Thumb
	tr := thumbrect(sb);
	dst.draw(tr, thumbcolor, nil, Point(0, 0));
}

Scrollbar.resize(sb: self ref Scrollbar, r: Rect)
{
	sb.r = r;
}

Scrollbar.event(sb: self ref Scrollbar, p: ref Pointer): int
{
	if(!sb.r.contains(p.xy))
		return -1;

	if(sb.total <= 0 || sb.visible <= 0)
		return -1;

	v := sbpos(sb, p.xy);

	# B2: absolute position jump — start tracking
	if(p.buttons & 2) {
		activesb = sb;
		dragoffset = 0;
		dragbutton = 2;
		o := postoorigin(sb, v);
		sb.origin = o;
		return o;
	}

	# B1: page up/down or thumb drag
	if(p.buttons & 1) {
		tr := thumbrect(sb);
		trmin := sbpos(sb, tr.min);
		trmax := sbpos(sb, tr.max);
		if(v >= trmin && v < trmax) {
			# Pointer is on thumb — start drag
			activesb = sb;
			dragoffset = v - trmin;
			dragbutton = 1;
			return sb.origin;
		}
		# Before thumb — page up/left
		if(v < trmin) {
			sb.origin -= sb.visible;
			sb.origin = clamporigin(sb);
			return sb.origin;
		}
		# After thumb — page down/right
		sb.origin += sb.visible;
		sb.origin = clamporigin(sb);
		return sb.origin;
	}

	return -1;
}

Scrollbar.track(sb: self ref Scrollbar, p: ref Pointer): int
{
	if(activesb != sb)
		return -1;

	# Check if the button that started the drag is still held
	if(dragbutton == 1 && !(p.buttons & 1)) {
		activesb = nil;
		return -1;
	}
	if(dragbutton == 2 && !(p.buttons & 2)) {
		activesb = nil;
		return -1;
	}

	tlen := sblength(sb);
	if(tlen <= 0 || sb.total <= sb.visible)
		return sb.origin;

	v := sbpos(sb, p.xy);

	if(dragbutton == 2) {
		# B2: absolute position tracking
		o := postoorigin(sb, v);
		sb.origin = o;
		return o;
	}

	# B1: thumb drag — compute origin from pointer position
	thumbsz := (sb.visible * tlen) / sb.total;
	if(thumbsz < MINTHUMB)
		thumbsz = MINTHUMB;
	if(thumbsz > tlen)
		thumbsz = tlen;

	available := tlen - thumbsz;
	if(available <= 0)
		return sb.origin;

	# Where the leading edge of the thumb should be
	thumbtop := v - dragoffset - sbmin(sb);
	if(thumbtop < 0)
		thumbtop = 0;
	if(thumbtop > available)
		thumbtop = available;

	maxtl := sb.total - sb.visible;
	if(maxtl < 0)
		maxtl = 0;
	o := (thumbtop * maxtl) / available;
	sb.origin = o;
	return o;
}

Scrollbar.isactive(sb: self ref Scrollbar): int
{
	return activesb == sb;
}

Scrollbar.wheel(sb: self ref Scrollbar, button: int, step: int): int
{
	if(sb.vert) {
		if(button & 8)
			sb.origin -= step;
		else if(button & 16)
			sb.origin += step;
	} else {
		if(button & 32)
			sb.origin -= step;
		else if(button & 64)
			sb.origin += step;
	}
	sb.origin = clamporigin(sb);
	return sb.origin;
}

# ── Statusbar ─────────────────────────────────────────────────

Statusbar.new(r: Rect): ref Statusbar
{
	return ref Statusbar(r, "", "", nil, "", nil);
}

Statusbar.draw(sb: self ref Statusbar, dst: ref Image)
{
	# Background
	dst.draw(sb.r, statusbg, nil, Point(0, 0));

	# Top separator line
	dst.line(Point(sb.r.min.x, sb.r.min.y),
		 Point(sb.r.max.x, sb.r.min.y),
		 0, 0, 0, sepcolor, Point(0, 0));

	if(wfont == nil)
		return;

	x := sb.r.min.x + MARGIN;
	y := sb.r.min.y + MARGIN;

	if(sb.prompt != nil) {
		# Input mode: show "prompt: buf_"
		s := sb.prompt + sb.buf + "_";
		dst.text(Point(x, y), promptfg, Point(0, 0), wfont, s);
	} else {
		# Display mode: left text + right text
		if(sb.left != nil) {
			lcol := statusfg;
			if(sb.leftcolor != nil)
				lcol = sb.leftcolor;
			dst.text(Point(x, y), lcol, Point(0, 0), wfont, sb.left);
		}

		if(sb.right != nil) {
			rw := wfont.width(sb.right);
			rx := sb.r.max.x - rw - MARGIN;
			dst.text(Point(rx, y), statusfg, Point(0, 0), wfont, sb.right);
		}
	}
}

Statusbar.resize(sb: self ref Statusbar, r: Rect)
{
	sb.r = r;
}

Statusbar.key(sb: self ref Statusbar, c: int): (int, string)
{
	if(sb.prompt == nil)
		return (-1, nil);

	case c {
	'\n' =>
		# Enter — accept input
		val := sb.buf;
		sb.prompt = nil;
		sb.buf = "";
		return (1, val);
	Kesc =>
		# Escape — cancel input
		sb.prompt = nil;
		sb.buf = "";
		return (-1, nil);
	Kbs or Kdel =>
		# Backspace/Delete — remove last character
		if(len sb.buf > 0)
			sb.buf = sb.buf[0:len sb.buf - 1];
		return (0, nil);
	* =>
		# Printable character — append as Unicode char (not decimal)
		if(c >= 32 && c < 16rFF00) {
			ch := "x";
			ch[0] = c;
			sb.buf += ch;
		}
		return (0, nil);
	}
}
