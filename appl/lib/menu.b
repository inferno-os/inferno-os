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

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Font, Image, Point, Rect, Pointer: import draw;

include "lucitheme.m";

include "menu.m";

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
	th := lucitheme->load();
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
# Items start 1px below the top border (mr.min.y + 1) to avoid overwriting it.
drawitem(win: ref Image, mr: Rect, label: string, itemh, idx, hilite: int)
{
	y := mr.min.y + 1 + idx * itemh;
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

# --- Popup.show ---

Popup.show(m: self ref Popup, win: ref Image, at: Point,
	ptr: chan of ref Pointer): int
{
	stderr := sys->fildes(2);
	sys->fprint(stderr, "menu: show() items=%d at=(%d,%d)\n",
		len m.items, at.x, at.y);
	if(mfont == nil || len m.items == 0) {
		sys->fprint(stderr, "menu: show() early return (mfont nil=%d items=%d)\n",
			mfont == nil, len m.items);
		return -1;
	}

	lpad := 4;	# top/bottom item padding
	itemh := mfont.height + lpad * 2;
	menuw := menuwidth(m.items);
	menuh := len m.items * itemh + 2;	# +2 for top+bottom border

	# Position: open below-right of cursor, clamped to window bounds.
	mr := Rect((at.x, at.y), (at.x + menuw, at.y + menuh));
	winr := win.r;
	if(mr.max.x > winr.max.x) {
		dx := mr.max.x - winr.max.x;
		mr = mr.subpt((dx, 0));
	}
	if(mr.max.y > winr.max.y) {
		dy := mr.max.y - winr.max.y;
		mr = mr.subpt((0, dy));
	}
	if(mr.min.x < winr.min.x)
		mr = mr.subpt((mr.min.x - winr.min.x, 0));
	if(mr.min.y < winr.min.y)
		mr = mr.subpt((0, mr.min.y - winr.min.y));

	sys->fprint(stderr, "menu: drawing at mr=(%d,%d)-(%d,%d) win.r=(%d,%d)-(%d,%d)\n",
		mr.min.x, mr.min.y, mr.max.x, mr.max.y,
		winr.min.x, winr.min.y, winr.max.x, winr.max.y);

	# Save the screen region behind the menu for clean restore.
	savebuf: ref Image = nil;
	d := win.display;
	if(d != nil)
		savebuf = d.newimage(mr, win.chans, 0, Draw->Nofill);
	if(savebuf != nil)
		savebuf.draw(savebuf.r, win, nil, mr.min);

	# Draw menu frame.
	win.draw(mr, mbg, nil, (0, 0));
	win.draw(Rect(mr.min, (mr.max.x, mr.min.y + 1)), mborder, nil, (0, 0));
	win.draw(Rect((mr.min.x, mr.max.y - 1), mr.max), mborder, nil, (0, 0));
	win.draw(Rect(mr.min, (mr.min.x + 1, mr.max.y)), mborder, nil, (0, 0));
	win.draw(Rect((mr.max.x - 1, mr.min.y), mr.max), mborder, nil, (0, 0));

	# Draw all items dim.
	for(i := 0; i < len m.items; i++)
		drawitem(win, mr, m.items[i], itemh, i, 0);

	win.flush(Draw->Flushnow);
	sys->fprint(stderr, "menu: draw+flush done; entering event loop\n");

	# Event loop.
	#
	# Hybrid UX: Plan 9 hold-to-show AND macOS click-to-activate:
	#
	#   Hold button-3 → release over item = select (Plan 9 style)
	#   Quick right-click → menu stays visible; button-1 = select
	#   Button-1 outside menu OR second button-3 press = dismiss (-1)
	#
	# persistent: becomes 1 after a quick click; menu waits for button-1.
	# b3held: becomes 1 once button-3 is observed still pressed.
	#
	hover   := -1;
	persistent := 0;
	b3held  := 0;
	prevb   := 4;		# button-3 was down when show() was called
	for(;;) {
		ev := <-ptr;
		if(ev == nil)
			break;

		sys->fprint(stderr, "menu: event buttons=%d xy=(%d,%d)\n",
			ev.buttons, ev.xy.x, ev.xy.y);

		# Compute hovered item (bounds-checked).
		# Content area: [mr.min.y+1, mr.max.y-1) — items start 1px past top border.
		newhover := -1;
		if(ev.xy.x >= mr.min.x && ev.xy.x < mr.max.x &&
		   ev.xy.y >= mr.min.y + 1 && ev.xy.y < mr.max.y - 1) {
			newhover = (ev.xy.y - (mr.min.y + 1)) / itemh;
			if(newhover < 0 || newhover >= len m.items)
				newhover = -1;
		}

		# Redraw only changed item row.
		if(newhover != hover) {
			if(hover >= 0)
				drawitem(win, mr, m.items[hover], itemh, hover, 0);
			if(newhover >= 0)
				drawitem(win, mr, m.items[newhover], itemh, newhover, 1);
			hover = newhover;
			win.flush(Draw->Flushnow);
		}

		# In persistent mode: second button-3 press dismisses.
		# Check BEFORE updating b3held so we can detect "pressed again".
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

	sys->fprint(stderr, "menu: show() returning hover=%d\n", hover);

	# Restore region behind menu.
	if(savebuf != nil)
		win.draw(mr, savebuf, nil, savebuf.r.min);
	else
		win.draw(mr, mbg, nil, (0, 0));
	win.flush(Draw->Flushnow);

	return hover;
}
