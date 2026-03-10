implement Menu;

#
# menu.b — Plan 9 hold-to-show contextual popup menu
#
# Draws a menu, loops on pointer events until button-3 UP, returns
# selected item index or -1.  No global state visible to callers.
# All dependencies flow in via init() / show() parameters.
#
# UX: hybrid hold-to-show / click-to-activate
#   - Hold button-3 and release over item → selects (Plan 9 style)
#   - Quick right-click → menu stays visible; click button-1 to select
#   - Button-1 outside menu or second button-3 press → dismiss (-1)
#
# Scrolling: when items exceed MAXVISIBLE or the window height,
# a subset is shown with up/down scroll indicators.  Mouse hover
# at top/bottom indicators scrolls the visible window.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Font, Image, Point, Rect, Pointer: import draw;

include "lucitheme.m";

include "menu.m";

# --- Constants ---

MAXVISIBLE: con 20;		# max items shown without scrolling
SCROLLIND:  con 12;		# scroll indicator height (pixels)

# --- Module-level state (set once by init, used by all Popup.show calls) ---

mfont:		ref Font;
mbg:		ref Image;	# menu background
mborder:	ref Image;	# 1px frame
mhilit:		ref Image;	# highlighted item background
mtext:		ref Image;	# normal item text colour
mdim:		ref Image;	# un-highlighted item text colour

init(d: ref Display, f: ref Font)
{
	sys  = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	mfont = f;
	if(d == nil || f == nil)
		return;
	lucitheme := load Lucitheme Lucitheme->PATH;
	th := lucitheme->gettheme();
	mbg     = d.color(th.menubg);
	mborder = d.color(th.menuborder);
	mhilit  = d.color(th.menuhilit);
	mtext   = d.color(th.menutext);
	mdim    = d.color(th.menudim);
}

new(items: array of string): ref Popup
{
	p := ref Popup;
	p.items = array[len items] of string;
	p.items[0:] = items;
	p.lasthit = 0;
	return p;
}

# --- Internal helpers ---

# Measure menu width from the widest label.
menuwidth(items: array of string): int
{
	w := 80;
	for(i := 0; i < len items; i++) {
		tw := mfont.width(items[i]) + 24;
		if(tw > w)
			w = tw;
	}
	return w;
}

# Draw a single menu item.  hilite != 0 → highlighted row.
# idx is the visual row index (0-based within the visible window).
# mr is the menu rectangle.
drawitem(win: ref Image, mr: Rect, label: string, itemh, idx, hilite, yoff: int)
{
	y := mr.min.y + 1 + yoff + idx * itemh;
	# Row background (inset 1px from left/right border)
	ir := Rect((mr.min.x + 1, y), (mr.max.x - 1, y + itemh));
	if(hilite)
		win.draw(ir, mhilit, nil, (0, 0));
	else
		win.draw(ir, mbg, nil, (0, 0));
	# Item text
	tcol := mtext;
	if(!hilite)
		tcol = mdim;
	ty := y + (itemh - mfont.height) / 2;
	win.text((mr.min.x + 12, ty), tcol, (0, 0), mfont, label);
}

# Draw a scroll indicator (up or down arrow).
drawindic(win: ref Image, mr: Rect, y, h: int, up: int)
{
	ir := Rect((mr.min.x + 1, y), (mr.max.x - 1, y + h));
	win.draw(ir, mbg, nil, (0, 0));
	# Draw a simple arrow: "▲" or "▼" centered
	arrow := "▼";
	if(up)
		arrow = "▲";
	aw := mfont.width(arrow);
	ax := (mr.min.x + mr.max.x - aw) / 2;
	ay := y + (h - mfont.height) / 2;
	win.text((ax, ay), mdim, (0, 0), mfont, arrow);
}

# Draw all visible items in the scrolled window.
drawallitems(win: ref Image, mr: Rect, items: array of string,
	itemh, off, nvis, yoff: int)
{
	for(i := 0; i < nvis && off + i < len items; i++)
		drawitem(win, mr, items[off + i], itemh, i, 0, yoff);
}

# --- Popup.show ---

Popup.show(m: self ref Popup, win: ref Image, at: Point,
	ptr: chan of ref Pointer): int
{
	if(mfont == nil || len m.items == 0)
		return -1;

	nitems := len m.items;
	lpad := 4;	# top/bottom item padding
	itemh := mfont.height + lpad * 2;
	menuw := menuwidth(m.items);

	# Determine scroll mode
	winr := win.r;
	maxfit := (winr.dy() - 2) / itemh;	# max items that fit in window
	if(maxfit < 3)
		maxfit = 3;
	scrolling := 0;
	nvis := nitems;		# number of visible items
	off := 0;		# scroll offset into items array
	indh := 0;		# indicator height (0 if not scrolling)

	if(nitems > MAXVISIBLE || nitems > maxfit) {
		scrolling = 1;
		nvis = MAXVISIBLE;
		if(nvis > maxfit - 2)	# leave room for indicators
			nvis = maxfit - 2;
		if(nvis < 1)
			nvis = 1;
		indh = SCROLLIND;
		# Center the view on lasthit
		if(m.lasthit >= 0 && m.lasthit < nitems) {
			off = m.lasthit - nvis / 2;
			if(off < 0) off = 0;
			if(off > nitems - nvis) off = nitems - nvis;
		}
	}

	menuh := nvis * itemh + 2;	# +2 for top+bottom border
	if(scrolling)
		menuh += indh * 2;	# up + down indicators

	# Position: open below-right of cursor, clamped to window bounds.
	mr := Rect((at.x, at.y), (at.x + menuw, at.y + menuh));
	if(mr.max.x > winr.max.x)
		mr = mr.subpt((mr.max.x - winr.max.x, 0));
	if(mr.max.y > winr.max.y)
		mr = mr.subpt((0, mr.max.y - winr.max.y));
	if(mr.min.x < winr.min.x)
		mr = mr.subpt((mr.min.x - winr.min.x, 0));
	if(mr.min.y < winr.min.y)
		mr = mr.subpt((0, mr.min.y - winr.min.y));

	# Save the screen region behind the menu for clean restore.
	savebuf: ref Image = nil;
	d := win.display;
	if(d != nil)
		savebuf = d.newimage(mr, win.chans, 0, Draw->Nofill);
	if(savebuf != nil)
		savebuf.draw(savebuf.r, win, nil, mr.min);

	# Vertical offset for item content (below top border + optional up indicator)
	yoff := 0;
	if(scrolling)
		yoff = indh;

	# Draw menu frame.
	win.draw(mr, mbg, nil, (0, 0));
	win.draw(Rect(mr.min, (mr.max.x, mr.min.y + 1)), mborder, nil, (0, 0));
	win.draw(Rect((mr.min.x, mr.max.y - 1), mr.max), mborder, nil, (0, 0));
	win.draw(Rect(mr.min, (mr.min.x + 1, mr.max.y)), mborder, nil, (0, 0));
	win.draw(Rect((mr.max.x - 1, mr.min.y), mr.max), mborder, nil, (0, 0));

	# Draw items
	drawallitems(win, mr, m.items, itemh, off, nvis, yoff);

	# Draw scroll indicators
	if(scrolling) {
		drawindic(win, mr, mr.min.y + 1, indh, 1);
		drawindic(win, mr, mr.max.y - 1 - indh, indh, 0);
	}

	win.flush(Draw->Flushnow);

	# Event loop.
	hover   := -1;		# visual index within visible window
	persistent := 0;
	b3held  := 0;
	prevb   := 4;		# button-3 was down when show() was called
	scrolltick := 0;	# counter for scroll repeat

	for(;;) {
		ev := <-ptr;
		if(ev == nil)
			break;

		# Scroll indicators: if pointer is hovering on an indicator,
		# scroll the menu in that direction on each event.
		if(scrolling) {
			upindy := mr.min.y + 1;
			downindy := mr.max.y - 1 - indh;
			scrolled := 0;
			if(ev.xy.x >= mr.min.x && ev.xy.x < mr.max.x) {
				if(ev.xy.y >= upindy && ev.xy.y < upindy + indh && off > 0) {
					off--;
					scrolled = 1;
				} else if(ev.xy.y >= downindy && ev.xy.y < downindy + indh && off < nitems - nvis) {
					off++;
					scrolled = 1;
				}
			}
			# Wheel scroll
			if(ev.buttons & 8 && off > 0) {
				off -= 3;
				if(off < 0) off = 0;
				scrolled = 1;
			} else if(ev.buttons & 16 && off < nitems - nvis) {
				off += 3;
				if(off > nitems - nvis) off = nitems - nvis;
				scrolled = 1;
			}
			if(scrolled) {
				drawallitems(win, mr, m.items, itemh, off, nvis, yoff);
				drawindic(win, mr, mr.min.y + 1, indh, 1);
				drawindic(win, mr, mr.max.y - 1 - indh, indh, 0);
				hover = -1;	# reset hover after scroll
				win.flush(Draw->Flushnow);
				prevb = ev.buttons;
				continue;
			}
		}

		# Compute hovered item (visual index within visible window).
		# Content area: [mr.min.y+1+yoff, mr.min.y+1+yoff+nvis*itemh)
		contentstart := mr.min.y + 1 + yoff;
		newhover := -1;
		if(ev.xy.x >= mr.min.x && ev.xy.x < mr.max.x &&
		   ev.xy.y >= contentstart && ev.xy.y < contentstart + nvis * itemh) {
			newhover = (ev.xy.y - contentstart) / itemh;
			if(newhover < 0 || newhover >= nvis)
				newhover = -1;
			# Check that the absolute index is valid
			if(newhover >= 0 && off + newhover >= nitems)
				newhover = -1;
		}

		# Redraw only changed item row.
		if(newhover != hover) {
			if(hover >= 0)
				drawitem(win, mr, m.items[off + hover], itemh, hover, 0, yoff);
			if(newhover >= 0)
				drawitem(win, mr, m.items[off + newhover], itemh, newhover, 1, yoff);
			hover = newhover;
			win.flush(Draw->Flushnow);
		}

		# In persistent mode: second button-3 press dismisses.
		if(persistent && (ev.buttons & 4) && !(prevb & 4))
			break;

		# Track if button-3 was held long enough to count as a hold.
		if(ev.buttons & 4)
			b3held = 1;

		# Button-3 UP edge:
		#   - If held (or hovering): select now (Plan 9 style).
		#   - Quick click with no hover: enter persistent mode.
		if(!(ev.buttons & 4) && (prevb & 4)) {
			if(b3held || hover >= 0)
				break;
			persistent = 1;
		}

		# Button-1 DOWN edge: select (if hovering) or dismiss.
		if((ev.buttons & 1) && !(prevb & 1))
			break;

		prevb = ev.buttons;
	}

	# Compute absolute item index from visual hover.
	result := -1;
	if(hover >= 0) {
		result = off + hover;
		m.lasthit = result;
	}

	# Restore region behind menu.
	if(savebuf != nil)
		win.draw(mr, savebuf, nil, savebuf.r.min);
	else
		win.draw(mr, mbg, nil, (0, 0));
	win.flush(Draw->Flushnow);

	return result;
}
