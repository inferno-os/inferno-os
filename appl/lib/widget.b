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
FIELDPAD: con 3;	# internal padding in text fields
LABELGAP: con 6;	# gap between label and input area
LEFTPAD: con 4;		# left indent for labels, checkboxes, radios

wfont:    ref Font;
wdisplay: ref Display;	# cached for colour allocation

# Cached colour images (created from theme in init/retheme)
trackcolor:  ref Image;
thumbcolor:  ref Image;
statusbg:    ref Image;
statusfg:    ref Image;
sepcolor:    ref Image;
promptfg:    ref Image;	# text colour in prompt mode (edittext)
fieldbg:     ref Image;	# text field background
fieldborder: ref Image;	# text field border
fieldfocus:  ref Image;	# focused field border
fieldtext:   ref Image;	# text field text colour
fieldlabel:  ref Image;	# label text colour
fieldcursor: ref Image;	# text cursor colour
listsel:     ref Image;	# list selection highlight
listtext:    ref Image;	# list item text
listbg:      ref Image;	# list background
btnbg:       ref Image;	# button background
btnborder:   ref Image;	# button border
btntext:     ref Image;	# button text
btnpress:    ref Image;	# button pressed background

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
	wdisplay = display;
	activesb = nil;
	loadcolors(display);
}

retheme(display: ref Display)
{
	loadcolors(display);
}

loadcolors(display: ref Display)
{
	if(display == nil)
		return;
	wdisplay = display;
	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme == nil) {
		# Fallback to hardcoded defaults
		trackcolor  = display.color(int 16rE8E8E8FF);
		thumbcolor  = display.color(int 16rBBBBBBFF);
		statusbg    = display.color(int 16rE8E8E8FF);
		statusfg    = display.color(int 16r555555FF);
		sepcolor    = display.color(int 16rBBBBBBFF);
		promptfg    = display.color(int 16r333333FF);
		fieldbg     = display.color(int 16rFFFFFFFF);
		fieldborder = display.color(int 16rBBBBBBFF);
		fieldfocus  = display.color(int 16r2266CCFF);
		fieldtext   = display.color(int 16r333333FF);
		fieldlabel  = display.color(int 16r666666FF);
		fieldcursor = display.color(int 16r2266CCFF);
		listsel     = display.color(int 16rB4D5FEFF);
		listtext    = display.color(int 16r333333FF);
		listbg      = display.color(int 16rFFFFFFFF);
		btnbg       = display.color(int 16rE8E8E8FF);
		btnborder   = display.color(int 16rBBBBBBFF);
		btntext     = display.color(int 16r333333FF);
		btnpress    = display.color(int 16rCCCCCCFF);
		return;
	}
	th := lucitheme->gettheme();
	trackcolor  = display.color(th.editscroll);
	thumbcolor  = display.color(th.editthumb);
	statusbg    = display.color(th.editstatus);
	statusfg    = display.color(th.editstattext);
	sepcolor    = display.color(th.editlineno);
	promptfg    = display.color(th.edittext);
	fieldbg     = display.color(th.editbg);
	fieldborder = display.color(th.editlineno);
	fieldfocus  = display.color(th.editcursor);
	fieldtext   = display.color(th.edittext);
	fieldlabel  = display.color(th.dim);
	fieldcursor = display.color(th.editcursor);
	listsel     = display.color(th.accent);
	listtext    = display.color(th.edittext);
	listbg      = display.color(th.editbg);
	btnbg       = display.color(th.editstatus);
	btnborder   = display.color(th.editlineno);
	btntext     = display.color(th.editstattext);
	btnpress    = display.color(th.editscroll);
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

labelwidth(labels: array of string): int
{
	if(wfont == nil)
		return 0;
	maxw := 0;
	for(i := 0; i < len labels; i++){
		w := wfont.width(labels[i]);
		if(w > maxw)
			maxw = w;
	}
	return maxw + LABELGAP;
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

# ── Label ─────────────────────────────────────────────────────

Label.mk(r: Rect, text: string, dim: int, align: int): ref Label
{
	return ref Label(r, text, dim, align);
}

Label.draw(l: self ref Label, dst: ref Image)
{
	if(wfont == nil)
		return;
	col := fieldtext;
	if(l.dim)
		col = fieldlabel;
	ty := l.r.min.y + (l.r.dy() - wfont.height) / 2;
	tx: int;
	if(l.align == CENTER) {
		tw := wfont.width(l.text);
		tx = l.r.min.x + (l.r.dx() - tw) / 2;
	} else
		tx = l.r.min.x + LEFTPAD;
	dst.text(Point(tx, ty), col, Point(0, 0), wfont, l.text);
}

Label.resize(l: self ref Label, r: Rect)
{
	l.r = r;
}

Label.settext(l: self ref Label, s: string)
{
	l.text = s;
}

# ── Checkbox ──────────────────────────────────────────────────

CHECKBOXSZ: con 14;	# box size in pixels
CHECKBOXGAP: con 6;	# gap between box and label

Checkbox.mk(r: Rect, label: string, checked: int): ref Checkbox
{
	return ref Checkbox(r, label, checked);
}

Checkbox.draw(cb: self ref Checkbox, dst: ref Image)
{
	if(wfont == nil)
		return;

	# Centre box vertically within row
	boxy := cb.r.min.y + (cb.r.dy() - CHECKBOXSZ) / 2;
	boxx := cb.r.min.x + LEFTPAD;
	boxr := Rect((boxx, boxy), (boxx + CHECKBOXSZ, boxy + CHECKBOXSZ));

	# Box background and border
	dst.draw(boxr, fieldbg, nil, Point(0, 0));
	dst.draw(Rect(boxr.min, (boxr.max.x, boxr.min.y + 1)), fieldborder, nil, Point(0, 0));
	dst.draw(Rect((boxr.min.x, boxr.max.y - 1), boxr.max), fieldborder, nil, Point(0, 0));
	dst.draw(Rect(boxr.min, (boxr.min.x + 1, boxr.max.y)), fieldborder, nil, Point(0, 0));
	dst.draw(Rect((boxr.max.x - 1, boxr.min.y), boxr.max), fieldborder, nil, Point(0, 0));

	# Check mark (two diagonal lines forming a tick)
	if(cb.checked) {
		# Inner area for the check mark
		ix := boxr.min.x + 3;
		iy := boxr.min.y + 3;
		iw := CHECKBOXSZ - 6;
		ih := CHECKBOXSZ - 6;
		# Descending stroke: top-left to mid-bottom
		dst.line(Point(ix, iy + ih/2),
			 Point(ix + iw/3, iy + ih),
			 0, 0, 0, fieldfocus, Point(0, 0));
		# Ascending stroke: mid-bottom to top-right
		dst.line(Point(ix + iw/3, iy + ih),
			 Point(ix + iw, iy),
			 0, 0, 0, fieldfocus, Point(0, 0));
	}

	# Label text
	tx := boxx + CHECKBOXSZ + CHECKBOXGAP;
	ty := cb.r.min.y + (cb.r.dy() - wfont.height) / 2;
	dst.text(Point(tx, ty), fieldtext, Point(0, 0), wfont, cb.label);
}

Checkbox.resize(cb: self ref Checkbox, r: Rect)
{
	cb.r = r;
}

Checkbox.toggle(cb: self ref Checkbox)
{
	cb.checked = !cb.checked;
}

Checkbox.contains(cb: self ref Checkbox, p: Point): int
{
	return cb.r.contains(p);
}

Checkbox.value(cb: self ref Checkbox): int
{
	return cb.checked;
}

# ── Radio ─────────────────────────────────────────────────────

RADIOR: con 6;		# circle radius in pixels
RADIOGAP: con 6;	# gap between circle and label

Radio.mk(r: Rect, label: string, selected: int): ref Radio
{
	return ref Radio(r, label, selected);
}

Radio.draw(rb: self ref Radio, dst: ref Image)
{
	if(wfont == nil)
		return;

	# Centre circle vertically within row
	cy := rb.r.min.y + rb.r.dy() / 2;
	cx := rb.r.min.x + LEFTPAD + RADIOR + 1;
	c := Point(cx, cy);

	# Outer circle (border)
	dst.ellipse(c, RADIOR, RADIOR, 0, fieldborder, Point(0, 0));

	# Fill with background
	dst.fillellipse(c, RADIOR - 1, RADIOR - 1, fieldbg, Point(0, 0));

	# Inner filled dot when selected
	if(rb.selected) {
		inner := RADIOR - 3;
		if(inner < 2)
			inner = 2;
		dst.fillellipse(c, inner, inner, fieldfocus, Point(0, 0));
	}

	# Label text
	tx := rb.r.min.x + LEFTPAD + RADIOR * 2 + RADIOGAP;
	ty := rb.r.min.y + (rb.r.dy() - wfont.height) / 2;
	dst.text(Point(tx, ty), fieldtext, Point(0, 0), wfont, rb.label);
}

Radio.resize(rb: self ref Radio, r: Rect)
{
	rb.r = r;
}

Radio.contains(rb: self ref Radio, p: Point): int
{
	return rb.r.contains(p);
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
	1 or Khome =>
		# Ctrl-A / Home — (statusbar is append-only display, no-op)
		return (0, nil);
	5 or Kend =>
		# Ctrl-E / End — (statusbar is append-only display, no-op)
		return (0, nil);
	Kbs =>
		# Backspace/Ctrl-H — remove last character
		if(len sb.buf > 0)
			sb.buf = sb.buf[0:len sb.buf - 1];
		return (0, nil);
	11 =>
		# Ctrl-K — kill to end (at end of buf, no-op)
		return (0, nil);
	21 =>
		# Ctrl-U — kill whole line
		sb.buf = "";
		return (0, nil);
	23 =>
		# Ctrl-W — delete word back
		if(len sb.buf > 0) {
			p := len sb.buf;
			while(p > 0 && (sb.buf[p-1] == ' ' || sb.buf[p-1] == '\t'))
				p--;
			while(p > 0 && sb.buf[p-1] != ' ' && sb.buf[p-1] != '\t')
				p--;
			sb.buf = sb.buf[0:p];
		}
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

# ── Textfield ────────────────────────────────────────────────

# Compute the input area rectangle (excludes label).
tfinputr(tf: ref Textfield): Rect
{
	if(wfont == nil || tf.label == nil || len tf.label == 0)
		return tf.r;
	lw: int;
	if(tf.labelw > 0)
		lw = tf.labelw;
	else
		lw = wfont.width(tf.label) + LABELGAP;
	return Rect((tf.r.min.x + lw, tf.r.min.y), tf.r.max);
}

# Return the display string (dots for secret fields).
tfdisplay(tf: ref Textfield): string
{
	if(!tf.secret)
		return tf.text;
	s := "";
	for(i := 0; i < len tf.text; i++)
		s += "*";
	return s;
}

Textfield.mk(r: Rect, label: string, secret: int): ref Textfield
{
	return ref Textfield(r, "", 0, secret, 0, label, 0);
}

Textfield.draw(tf: self ref Textfield, dst: ref Image)
{
	if(wfont == nil)
		return;

	# Draw label
	if(tf.label != nil && len tf.label > 0) {
		ly := tf.r.min.y + FIELDPAD;
		dst.text(Point(tf.r.min.x, ly), fieldlabel, Point(0, 0), wfont, tf.label);
	}

	# Input area
	ir := tfinputr(tf);

	# Background
	dst.draw(ir, fieldbg, nil, Point(0, 0));

	# Border (1px)
	bcol := fieldborder;
	if(tf.focused)
		bcol = fieldfocus;
	# Top
	dst.draw(Rect(ir.min, (ir.max.x, ir.min.y + 1)), bcol, nil, Point(0, 0));
	# Bottom
	dst.draw(Rect((ir.min.x, ir.max.y - 1), ir.max), bcol, nil, Point(0, 0));
	# Left
	dst.draw(Rect(ir.min, (ir.min.x + 1, ir.max.y)), bcol, nil, Point(0, 0));
	# Right
	dst.draw(Rect((ir.max.x - 1, ir.min.y), ir.max), bcol, nil, Point(0, 0));

	# Text
	tx := ir.min.x + FIELDPAD + 1;
	ty := ir.min.y + FIELDPAD;
	ds := tfdisplay(tf);
	dst.text(Point(tx, ty), fieldtext, Point(0, 0), wfont, ds);

	# Cursor
	if(tf.focused) {
		cpos := tf.cursor;
		if(cpos > len ds)
			cpos = len ds;
		pre := ds[0:cpos];
		cx := tx + wfont.width(pre);
		cy1 := ir.min.y + 2;
		cy2 := ir.max.y - 2;
		dst.line(Point(cx, cy1), Point(cx, cy2),
			 0, 0, 0, fieldcursor, Point(0, 0));
	}
}

Textfield.resize(tf: self ref Textfield, r: Rect)
{
	tf.r = r;
}

Textfield.key(tf: self ref Textfield, c: int): int
{
	if(!tf.focused)
		return 0;

	case c {
	'\n' =>
		return 1;
	1 =>
		# Ctrl-A — beginning of line
		tf.cursor = 0;
	2 =>
		# Ctrl-B — back one character
		if(tf.cursor > 0)
			tf.cursor--;
	4 =>
		# Ctrl-D — delete at cursor
		if(tf.cursor < len tf.text)
			tf.text = tf.text[0:tf.cursor] + tf.text[tf.cursor+1:];
	5 =>
		# Ctrl-E — end of line
		tf.cursor = len tf.text;
	6 =>
		# Ctrl-F — forward one character
		if(tf.cursor < len tf.text)
			tf.cursor++;
	Kbs =>
		# Ctrl-H / Backspace
		if(tf.cursor > 0) {
			tf.text = tf.text[0:tf.cursor-1] + tf.text[tf.cursor:];
			tf.cursor--;
		}
	11 =>
		# Ctrl-K — kill from cursor to end
		tf.text = tf.text[0:tf.cursor];
	21 =>
		# Ctrl-U — kill whole line
		tf.text = "";
		tf.cursor = 0;
	22 =>
		# Ctrl-V — paste from /dev/snarf
		s := readsnarffile();
		if(s != nil && len s > 0) {
			# Strip trailing newlines
			while(len s > 0 && (s[len s-1] == '\n' || s[len s-1] == '\r'))
				s = s[:len s-1];
			tf.text = tf.text[0:tf.cursor] + s + tf.text[tf.cursor:];
			tf.cursor += len s;
		}
	3 =>
		# Ctrl-C — copy to /dev/snarf
		if(len tf.text > 0 && !tf.secret)
			writesnarffile(tf.text);
	24 =>
		# Ctrl-X — cut to /dev/snarf
		if(len tf.text > 0 && !tf.secret) {
			writesnarffile(tf.text);
			tf.text = "";
			tf.cursor = 0;
		}
	23 =>
		# Ctrl-W — delete word back
		if(tf.cursor > 0) {
			p := tf.cursor;
			while(p > 0 && (tf.text[p-1] == ' ' || tf.text[p-1] == '\t'))
				p--;
			while(p > 0 && tf.text[p-1] != ' ' && tf.text[p-1] != '\t')
				p--;
			tf.text = tf.text[0:p] + tf.text[tf.cursor:];
			tf.cursor = p;
		}
	Kdel =>
		if(tf.cursor < len tf.text)
			tf.text = tf.text[0:tf.cursor] + tf.text[tf.cursor+1:];
	Kleft =>
		if(tf.cursor > 0)
			tf.cursor--;
	Kright =>
		if(tf.cursor < len tf.text)
			tf.cursor++;
	Khome =>
		tf.cursor = 0;
	Kend =>
		tf.cursor = len tf.text;
	* =>
		if(c >= 32 && c < 16rFF00) {
			ch := "x";
			ch[0] = c;
			tf.text = tf.text[0:tf.cursor] + ch + tf.text[tf.cursor:];
			tf.cursor++;
		}
	}
	return 0;
}

Textfield.click(tf: self ref Textfield, p: Point)
{
	if(wfont == nil)
		return;
	ir := tfinputr(tf);
	tx := ir.min.x + FIELDPAD + 1;
	ds := tfdisplay(tf);
	# Find character position closest to click
	best := 0;
	bestdist := p.x - tx;
	if(bestdist < 0)
		bestdist = -bestdist;
	for(i := 1; i <= len ds; i++) {
		cx := tx + wfont.width(ds[0:i]);
		d := p.x - cx;
		if(d < 0)
			d = -d;
		if(d < bestdist) {
			bestdist = d;
			best = i;
		}
	}
	tf.cursor = best;
}

Textfield.contains(tf: self ref Textfield, p: Point): int
{
	return tf.r.contains(p);
}

Textfield.value(tf: self ref Textfield): string
{
	return tf.text;
}

Textfield.setval(tf: self ref Textfield, s: string)
{
	tf.text = s;
	tf.cursor = len s;
}

# ── Listbox ──────────────────────────────────────────────────

Listbox.mk(r: Rect): ref Listbox
{
	# Scrollbar on the left (Plan 9 convention)
	sbr := Rect(r.min, (r.min.x + SCROLLW, r.max.y));
	sb := Scrollbar.new(sbr, 1);
	return ref Listbox(Rect((r.min.x + SCROLLW, r.min.y), r.max),
			   nil, -1, 0, sb);
}

Listbox.draw(lb: self ref Listbox, dst: ref Image)
{
	if(wfont == nil)
		return;

	# Background
	dst.draw(lb.r, listbg, nil, Point(0, 0));

	# Draw items
	rowh := wfont.height + MARGIN;
	vis := lb.visible();
	y := lb.r.min.y;
	for(i := 0; i < vis && lb.top + i < len lb.items; i++) {
		idx := lb.top + i;
		rowr := Rect((lb.r.min.x, y), (lb.r.max.x, y + rowh));
		if(idx == lb.selected)
			dst.draw(rowr, listsel, nil, Point(0, 0));
		tx := lb.r.min.x + MARGIN;
		ty := y + MARGIN / 2;
		dst.text(Point(tx, ty), listtext, Point(0, 0), wfont, lb.items[idx]);
		y += rowh;
	}

	# Scrollbar
	if(lb.scroll != nil) {
		lb.scroll.total = len lb.items;
		lb.scroll.visible = vis;
		lb.scroll.origin = lb.top;
		lb.scroll.draw(dst);
	}
}

Listbox.resize(lb: self ref Listbox, r: Rect)
{
	if(lb.scroll != nil) {
		sbr := Rect(r.min, (r.min.x + SCROLLW, r.max.y));
		lb.scroll.resize(sbr);
	}
	lb.r = Rect((r.min.x + SCROLLW, r.min.y), r.max);
}

Listbox.click(lb: self ref Listbox, p: Point): int
{
	if(wfont == nil || lb.items == nil)
		return -1;

	# Check scrollbar first
	if(lb.scroll != nil && lb.scroll.r.contains(p)) {
		pp := ref Pointer(1, p, 0);
		newo := lb.scroll.event(pp);
		if(newo >= 0)
			lb.top = newo;
		return lb.selected;
	}

	if(!lb.r.contains(p))
		return -1;

	rowh := wfont.height + MARGIN;
	row := (p.y - lb.r.min.y) / rowh;
	idx := lb.top + row;
	if(idx >= 0 && idx < len lb.items)
		lb.selected = idx;
	return lb.selected;
}

Listbox.wheel(lb: self ref Listbox, button: int): int
{
	if(lb.scroll == nil)
		return lb.top;
	lb.scroll.total = len lb.items;
	lb.scroll.visible = lb.visible();
	lb.scroll.origin = lb.top;
	lb.top = lb.scroll.wheel(button, 3);
	return lb.top;
}

Listbox.contains(lb: self ref Listbox, p: Point): int
{
	if(lb.scroll != nil && lb.scroll.r.contains(p))
		return 1;
	return lb.r.contains(p);
}

Listbox.setitems(lb: self ref Listbox, items: array of string)
{
	lb.items = items;
	lb.selected = -1;
	lb.top = 0;
}

Listbox.visible(lb: self ref Listbox): int
{
	if(wfont == nil)
		return 0;
	rowh := wfont.height + MARGIN;
	if(rowh <= 0)
		return 0;
	return lb.r.dy() / rowh;
}

# ── Button ───────────────────────────────────────────────────

Button.mk(r: Rect, label: string): ref Button
{
	return ref Button(r, label, 0);
}

Button.draw(b: self ref Button, dst: ref Image)
{
	if(wfont == nil)
		return;

	bg := btnbg;
	if(b.pressed)
		bg = btnpress;

	dst.draw(b.r, bg, nil, Point(0, 0));

	# Border
	dst.draw(Rect(b.r.min, (b.r.max.x, b.r.min.y + 1)), btnborder, nil, Point(0, 0));
	dst.draw(Rect((b.r.min.x, b.r.max.y - 1), b.r.max), btnborder, nil, Point(0, 0));
	dst.draw(Rect(b.r.min, (b.r.min.x + 1, b.r.max.y)), btnborder, nil, Point(0, 0));
	dst.draw(Rect((b.r.max.x - 1, b.r.min.y), b.r.max), btnborder, nil, Point(0, 0));

	# Centered label
	tw := wfont.width(b.label);
	tx := b.r.min.x + (b.r.dx() - tw) / 2;
	ty := b.r.min.y + (b.r.dy() - wfont.height) / 2;
	dst.text(Point(tx, ty), btntext, Point(0, 0), wfont, b.label);
}

Button.resize(b: self ref Button, r: Rect)
{
	b.r = r;
}

Button.contains(b: self ref Button, p: Point): int
{
	return b.r.contains(p);
}

# ── RadioGroup ───────────────────────────────────────────────

RadioGroup.mk(origin: Point, width: int, labels: array of string, sel: int, rowh: int): ref RadioGroup
{
	n := len labels;
	buttons := array[n] of ref Radio;
	for(i := 0; i < n; i++) {
		y := origin.y + i * rowh;
		r := Rect((origin.x, y), (origin.x + width, y + rowh));
		buttons[i] = Radio.mk(r, labels[i], sel == i);
	}
	return ref RadioGroup(buttons);
}

RadioGroup.draw(rg: self ref RadioGroup, dst: ref Image)
{
	if(rg.buttons == nil)
		return;
	for(i := 0; i < len rg.buttons; i++)
		if(rg.buttons[i] != nil)
			rg.buttons[i].draw(dst);
}

RadioGroup.click(rg: self ref RadioGroup, p: Point): int
{
	if(rg.buttons == nil)
		return -1;
	for(i := 0; i < len rg.buttons; i++) {
		if(rg.buttons[i] != nil && rg.buttons[i].contains(p)) {
			for(j := 0; j < len rg.buttons; j++)
				rg.buttons[j].selected = 0;
			rg.buttons[i].selected = 1;
			return i;
		}
	}
	return -1;
}

RadioGroup.selected(rg: self ref RadioGroup): int
{
	if(rg.buttons == nil)
		return -1;
	for(i := 0; i < len rg.buttons; i++)
		if(rg.buttons[i] != nil && rg.buttons[i].selected)
			return i;
	return -1;
}

RadioGroup.select(rg: self ref RadioGroup, idx: int)
{
	if(rg.buttons == nil)
		return;
	for(i := 0; i < len rg.buttons; i++)
		rg.buttons[i].selected = 0;
	if(idx >= 0 && idx < len rg.buttons)
		rg.buttons[idx].selected = 1;
}

RadioGroup.resize(rg: self ref RadioGroup, origin: Point, width: int, rowh: int)
{
	if(rg.buttons == nil)
		return;
	for(i := 0; i < len rg.buttons; i++) {
		y := origin.y + i * rowh;
		rg.buttons[i].r = Rect((origin.x, y), (origin.x + width, y + rowh));
	}
}

RadioGroup.bounds(rg: self ref RadioGroup): Rect
{
	if(rg.buttons == nil || len rg.buttons == 0)
		return Rect((0, 0), (0, 0));
	r0 := rg.buttons[0].r;
	rn := rg.buttons[len rg.buttons - 1].r;
	return Rect(r0.min, rn.max);
}

RadioGroup.contains(rg: self ref RadioGroup, p: Point): int
{
	if(rg.buttons == nil)
		return 0;
	for(i := 0; i < len rg.buttons; i++)
		if(rg.buttons[i] != nil && rg.buttons[i].contains(p))
			return 1;
	return 0;
}

# ── Snarf (clipboard) ────────────────────────────────────────

readsnarffile(): string
{
	fd := sys->open("/dev/snarf", Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	return string buf[0:n];
}

writesnarffile(s: string)
{
	fd := sys->open("/dev/snarf", Sys->OWRITE);
	if(fd == nil)
		return;
	b := array of byte s;
	sys->write(fd, b, len b);
}
