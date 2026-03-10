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
MINTHUMB: con 10;	# minimum thumb height in pixels

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

# ── Key constants ─────────────────────────────────────────────

Kbs:  con 8;
Kesc: con 27;
Kdel: con 16rFF9F;

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

# ── Scrollbar ─────────────────────────────────────────────────

# Compute thumb rectangle within scrollbar rect.
thumbrect(sb: ref Scrollbar): Rect
{
	r := sb.r;
	totalh := r.dy();
	if(sb.total <= 0 || sb.visible <= 0 || totalh <= 0)
		return Rect((r.min.x + 2, r.min.y), (r.max.x - 2, r.min.y));

	thumbh := (sb.visible * totalh) / sb.total;
	if(thumbh < MINTHUMB)
		thumbh = MINTHUMB;
	if(thumbh > totalh)
		thumbh = totalh;

	thumby := r.min.y;
	if(sb.total > sb.visible)
		thumby = r.min.y + (sb.origin * (totalh - thumbh)) / (sb.total - sb.visible);

	return Rect((r.min.x + 2, thumby), (r.max.x - 2, thumby + thumbh));
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

# Convert a y coordinate in the track to an absolute origin.
ytoorigin(sb: ref Scrollbar, y: int): int
{
	r := sb.r;
	totalh := r.dy();
	if(totalh <= 0 || sb.total <= 0)
		return 0;
	frac := y - r.min.y;
	if(frac < 0)
		frac = 0;
	if(frac > totalh)
		frac = totalh;
	o := (frac * sb.total) / totalh;
	maxtl := sb.total - sb.visible;
	if(maxtl < 0)
		maxtl = 0;
	if(o > maxtl)
		o = maxtl;
	return o;
}

Scrollbar.new(r: Rect): ref Scrollbar
{
	return ref Scrollbar(r, 0, 0, 0);
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

	# B2: absolute position jump — start tracking
	if(p.buttons & 2) {
		activesb = sb;
		dragoffset = 0;
		dragbutton = 2;
		o := ytoorigin(sb, p.xy.y);
		sb.origin = o;
		return o;
	}

	# B1: page up/down or thumb drag
	if(p.buttons & 1) {
		tr := thumbrect(sb);
		if(p.xy.y >= tr.min.y && p.xy.y < tr.max.y) {
			# Pointer is on thumb — start drag
			activesb = sb;
			dragoffset = p.xy.y - tr.min.y;
			dragbutton = 1;
			return sb.origin;
		}
		# Above thumb — page up
		if(p.xy.y < tr.min.y) {
			sb.origin -= sb.visible;
			sb.origin = clamporigin(sb);
			return sb.origin;
		}
		# Below thumb — page down
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

	r := sb.r;
	totalh := r.dy();
	if(totalh <= 0 || sb.total <= sb.visible)
		return sb.origin;

	if(dragbutton == 2) {
		# B2: absolute position tracking
		o := ytoorigin(sb, p.xy.y);
		sb.origin = o;
		return o;
	}

	# B1: thumb drag — compute origin from pointer position
	thumbh := (sb.visible * totalh) / sb.total;
	if(thumbh < MINTHUMB)
		thumbh = MINTHUMB;
	if(thumbh > totalh)
		thumbh = totalh;

	available := totalh - thumbh;
	if(available <= 0)
		return sb.origin;

	# Where the top of the thumb should be
	thumbtop := p.xy.y - dragoffset - r.min.y;
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
	if(button & 8)
		sb.origin -= step;
	else if(button & 16)
		sb.origin += step;
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
