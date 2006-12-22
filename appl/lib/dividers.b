implement Dividers;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect: import draw;
include "tk.m";
	tk: Tk;
include "dividers.m";

Lay: adt {
	d: int;
	x: fn(l: self Lay, p: Point): int;
	y: fn(l: self Lay, p: Point): int;
	mkr: fn(l: self Lay, r: Rect): Rect;
	mkpt: fn(l: self Lay, p: Point): Point;
};

DIVHEIGHT: con 6;

init()
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
}

# dir is direction in which to stack widgets (NS or EW)
Divider.new(win: ref Tk->Toplevel, w: string, wl: list of string, dir: int): (ref Divider, chan of string)
{
	lay := Lay(dir);
	n := len wl;
	d := ref Divider(win, w, nil, dir, array[n] of {* => ref DWidget}, (0, 0));
	p := Point(0, 0);
	for (i := 0; wl != nil; (wl, i) = (tl wl, i+1)) {
		sz := lay.mkpt(wsize(win, hd wl));
		*d.widgets[i] = (hd wl, (p, p.add(sz)), sz);
		if (sz.x > d.canvsize.x)
			d.canvsize.x = sz.x;
		p.y += sz.y + DIVHEIGHT;
	}
	d.canvsize.y = p.y - DIVHEIGHT;
	cmd(win, "canvas " + d.w + " -width " + string lay.x(d.canvsize) +
			" -height " + string lay.y(d.canvsize));
	ech := chan of string;
	echname := "dw" + d.w;
	tk->namechan(win, ech, echname);
	for (i = 0; i < n; i++) {
		dw := d.widgets[i];
		dw.r.max.x = d.canvsize.x + dw.r.min.x;
		sz := dxy(dw.r);
		cmd(win, d.w + " create window " + p2s(lay.mkpt(dw.r.min)) +
			" -window " + dw.w +
			" -tags w" + string i + " -anchor nw" +
			" -width " + string lay.x(sz) +
			" -height " + string lay.y(sz));
		cmd(win, "pack propagate " + dw.w + " 0");
		if (i < n - 1) {
			r := lay.mkr(((dw.r.min.x, dw.r.max.y),
					(dw.r.max.x, dw.r.max.y + DIVHEIGHT)));
			cmd(win, d.w + " create rectangle " + r2s(r) +
				" -fill red" +
				" -tags d" + string i);
			cmd(win, d.w + " bind d" + string i + " <Button-1>" +
				" {send " + echname + " but " + string i + " %x %y}");
			cmd(win, d.w + " bind d" + string i + " <Motion-Button-1> {}");
			cmd(win, d.w + " bind d" + string i + " <ButtonRelease-1>" +
				" {send " + echname + " up x %x %y}");
		}
	}
	cmd(win, d.w + " create rectangle -2 -2 -1 -1 -tags grab");
	cmd(win, d.w + " bind grab <Button-1> {send " + echname + " drag x %x %y}");
	cmd(win, d.w + " bind grab <ButtonRelease-1> {send " + echname + " up x %x %y}");
	cmd(win, "bind " + d.w + " <Configure> {send " + echname + " config x x x}");
	return (d, ech);
}

Divider.event(d: self ref Divider, e: string)
{
	(n, toks) := sys->tokenize(e, " ");
	if (n != 4) {
		sys->print("dividers: invalid event %s\n", e);
		return;
	}
	lay := Lay(d.dir);
	p := lay.mkpt((int hd tl tl toks, int hd tl tl tl toks));
	t := hd toks;
	if (t == "but" && d.state != nil)
		t = "drag";
	case t {
	"but" =>
		if (d.state != nil) {
			sys->print("dividers: event '%s' received in drag mode\n", e);
			return;
		}
		div := int hd tl toks;
		d.state = ref DState;
		d.state.dragdiv = div;
		d.state.dy = p.y - d.widgets[div].r.max.y;
		d.state.maxy = d.widgets[div+1].r.max.y - DIVHEIGHT;
		d.state.miny = d.widgets[div].r.min.y;
		cmd(d.win, d.w + " itemconfigure d" + string div + " -fill orange");
		cmd(d.win, d.w + " raise d" + string div);
		cmd(d.win, d.w + " coords grab -10000 -10000 10000 10000");
		cmd(d.win, "grab set " + d.w);
		cmd(d.win, "update");
	"drag" =>
		if (d.state == nil) {
			sys->print("dividers: event '%s' received in non-drag mode\n", e);
			return;
		}
		div := d.state.dragdiv;
		ypos := p.y - d.state.dy;
		if (ypos > d.state.maxy)
			ypos = d.state.maxy;
		else if (ypos < d.state.miny)
			ypos = d.state.miny;
		r := Rect((0, ypos), (d.canvsize.x, ypos + DIVHEIGHT));
		cmd(d.win, d.w + " coords d" + string div + " " + r2s(lay.mkr(r)));
		d.widgets[div].r.max.y = ypos;
		d.widgets[div+1].r.min.y = ypos + DIVHEIGHT;
		relayout(d);
		cmd(d.win, "update");
	"up" =>
		if (d.state == nil) {
			sys->print("dividers: event '%s' received in non-drag mode\n", e);
			return;
		}
		div := d.state.dragdiv;
		cmd(d.win, d.w + " itemconfigure d" + string div + " -fill red");
		cmd(d.win, d.w + " coords grab -2 -2 -1 -1");
		cmd(d.win, "grab release " + d.w);
		cmd(d.win, "update");
		d.state = nil;
	"config" =>
		resize(d);
		cmd(d.win, "update");
	}
}

# lay out widgets according to rectangles that have been already specified.
relayout(d: ref Divider)
{
	lay := Lay(d.dir);
	for (i := 0; i < len d.widgets; i++) {
		dw := d.widgets[i];
		sz := dxy(dw.r);
		szs := " -width " + string lay.x(sz) + " -height " + string lay.y(sz);
		cmd(d.win, d.w + " coords w" + string i + " " + p2s(lay.mkpt(dw.r.min)));
		cmd(d.win, d.w + " itemconfigure w" + string i + szs);
		cmd(d.win, dw.w + " configure" + szs);
		if (i < len d.widgets - 1) {
			r := lay.mkr(((dw.r.min.x, dw.r.max.y),
					(dw.r.max.x, dw.r.max.y + DIVHEIGHT)));
			cmd(d.win, d.w + " coords d" + string i + " " + r2s(r));
		}
	}
}

# resize based on current actual size of canvas;
# sections resize proportionate to their previously occupied space.
# strange things will happen if we're resizing in the middle of a drag...
resize(d: ref Divider)
{
	lay := Lay(d.dir);
	sz := lay.mkpt((int cmd(d.win, d.w + " cget -actwidth"), 
			int cmd(d.win, d.w + " cget -actheight")));

	wspace := (len d.widgets - 1) * DIVHEIGHT;
	y := 0;
	for (i := 0; i < len d.widgets; i++) {
		dw := d.widgets[i];
		prop := real dw.r.dy() / real (d.canvsize.y - wspace);
		dw.r = ((0, y), (sz.x, y + int (prop * real (sz.y - wspace))));
		y = dw.r.max.y + DIVHEIGHT;
	}
	y -= DIVHEIGHT;
	# compensate for rounding errors
	d.widgets[i - 1].r.max.y -= y - sz.y;
	d.canvsize = sz;
	relayout(d);
}

wsize(win: ref Tk->Toplevel, w: string): Point
{
	bw := int cmd(win, w + " cget -borderwidth");
	return Point(int cmd(win, w + " cget -width") + bw*2,
			int cmd(win, w + " cget -height") + bw*2);
}

dxy(r: Rect): Point
{
	return r.max.sub(r.min);
}

p2s(p: Point): string
{
	return string p.x + " " + string p.y;
}

r2s(r: Rect): string
{
	return string r.min.x + " " + string r.min.y + " " +
			string r.max.x + " " + string r.max.y;
}

Lay.x(l: self Lay, p: Point): int
{
	if (l.d == NS)
		return p.x;
	return p.y;
}

Lay.y(l: self Lay, p: Point): int
{
	if (l.d == NS)
		return p.y;
	return p.x;
}

Lay.mkr(l: self Lay, r: Rect): Rect
{
	if (l.d == NS)
		return r;
	return ((r.min.y, r.min.x), (r.max.y, r.max.x));
}

Lay.mkpt(l: self Lay, p: Point): Point
{
	if (l.d == NS)
		return p;
	return (p.y, p.x);
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->print("dividers: tk error %s on '%s'\n", e, s);
	return e;
}
