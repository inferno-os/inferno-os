implement Items;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect: import draw;
include "tk.m";
	tk: Tk;
include "items.m";

Taglen: con 5;
Titletaglen: con 10;
Spotdiam: con 10;
Lineopts: con " -width 1 -fill gray";
Ovalopts: con " -outline gray";
Crossopts: con " -fill red";

init()
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
}

blankexpander: Expander;
Expander.new(win: ref Tk->Toplevel, cvs: string): ref Expander
{
	e := ref blankexpander;
	e.win = win;
	e.cvs = cvs;
	return e;
}

moveto(win: ref Tk->Toplevel, cvs: string, tag: string, bbox: Rect, p: Point)
{
	if (!bbox.min.eq(p))
		cmd(win, cvs + " move " + tag + " " + p2s(p.sub(bbox.min)));
}

bbox(win: ref Tk->Toplevel, cvs, w: string): Rect
{
	return s2r(cmd(win, cvs + " bbox " + w));
}

rename(win: ref Tk->Toplevel, it: Item, newname: string): Item
{
	(nil, itl) := sys->tokenize(cmd(win, ".c find withtag " + it.name), " ");
	cmd(win, ".c dtag " + it.name + " " + it.name);
	for (; itl != nil; itl = tl itl)
		cmd(win, ".c addtag " + newname + " withtag " + hd itl);
	it.name = newname;
	return it;
}

Expander.make(e: self ref Expander, titleitem: Item): Item
{
	name := titleitem.name;
	tag := " -tags " + name;

	e.titleitem = rename(e.win, titleitem, "!!." + name);
	cmd(e.win, e.cvs + " addtag " + name + " withtag !!." + name);
	sc := spotcentre((0, 0), dxy(e.titleitem.r));
	spotr := Rect(sc, sc).inset(-Spotdiam/2);

	p := (spotr.max.x + Titletaglen, 0);
	moveto(e.win, e.cvs, e.titleitem.name, e.titleitem.r, p);
	e.titleitem.r = rmoveto(e.titleitem.r, p);
	it := Item(name,  ((0, 0), (spotr.max.x + Titletaglen + titleitem.r.dx(), titleitem.r.dy())), (0, 0));

	# make line to the right of spot
	cmd(e.win, e.cvs + " create line " +
		p2s((spotr.max.x, sc.y)) + " " + p2s((spotr.max.x+Titletaglen, sc.y)) + tag + Lineopts);

	# make spot
	spotid := cmd(e.win, e.cvs + " create oval " +
		r2s(spotr) + Ovalopts + tag);
	if (e.expanded)
		cmd(e.win, e.cvs + " bind " + spotid + " <ButtonRelease-1>"
			+ " {send event " + name + " contract}");
	else
		cmd(e.win, e.cvs + " bind " + spotid + " <ButtonRelease-1>"
			+ " {send event " + name + " expand}");

	cmd(e.win, e.cvs + " raise " + spotid);
	e.spotid = int spotid;

	it.attach = (0, sc.y);
	it.r.max = (e.titleitem.r.dx() + spotr.max.x + Titletaglen, e.titleitem.r.dy());

	if (!e.expanded) {
		addcross(e, it, name);
		return it;
	}

	it.r = placechildren(e, it, name);
	return it;
}

rmoveto(r: Rect, p: Point): Rect
{
	return r.addpt(p.sub(r.min));
}

# place all children of e appropriately.
# assumes that the canvas items of all children are already made.
# return bbox rectangle of whole thing.
placechildren(e: ref Expander, it: Item, tags: string): Rect
{
	ltag := " -tags {"+ tags + " !." + it.name + "}";
	titlesize := dxy(e.titleitem.r);
	sc := spotcentre(it.r.min, titlesize);
	maxwidth := 0;
	y := it.r.min.y + titlesize.y;
	lasty := 0;
	for (i := 0; i < len e.children; i++) {
		c := e.children[i];
		if (c.r.dx() > maxwidth)
			maxwidth = c.r.dx();
		c.r = c.r.addpt(it.r.min);
		r: Rect;
		r.min = (sc.x + Taglen, y);
		r.max = r.min.add(dxy(c.r));
		moveto(e.win, e.cvs, c.name, c.r, r.min);

		# make item coords relative to parent
		e.children[i].r = r.subpt(it.r.min);
		cmd(e.win, e.cvs + " addtag " + it.name + " withtag " + c.name);

		# horizontal attachment
		cmd(e.win, e.cvs + " create line " +
			p2s((sc.x, y + c.attach.y)) + " " +
			p2s((sc.x + Taglen + c.attach.x, y + c.attach.y)) +
			ltag + Lineopts);
		lasty = y + c.attach.y;
		y += r.dy();
	}

	# vertical attachment (if there were any children)
	if (i > 0) {
		id := cmd(e.win, e.cvs + " create line " +
			p2s((sc.x, sc.y + Spotdiam/2)) + " " + p2s((sc.x, lasty)) + ltag + Lineopts);
		cmd(e.win, e.cvs + " bind " + id + " <Button-1>"+
				" {send event " + it.name + " see}");
	}
	r := Rect(it.r.min,
			(max(sc.x+Spotdiam/2+Titletaglen+titlesize.x, sc.x+Taglen+maxwidth),
			y));
	return r;
}

Expander.event(e: self ref Expander, it: Item, ev: string): Item
{
	case ev {
	"expand" =>
		if (e.expanded) {
			sys->print("item %s is already expanded\n", it.name);
			return it;
		}
		e.expanded = 1;
		tags := gettags(e.win, e.cvs, string e.spotid);
		cmd(e.win, e.cvs + " delete !." + it.name);
		cmd(e.win, e.cvs + " bind " + string e.spotid + " <ButtonRelease-1>" +
			+ " {send event " + it.name + " contract}");
		it.r = placechildren(e, it, tags);
	"contract" =>
		if (!e.expanded) {
			sys->print("item %s is already contracted\n", it.name);
			return it;
		}
		e.expanded = 0;
		cmd(e.win, e.cvs + " delete !." + it.name);
		for (i := 0; i < len e.children; i++)
			cmd(e.win, e.cvs + " delete " + e.children[i].name);
		cmd(e.win, e.cvs + " bind " + string e.spotid + " <ButtonRelease-1>" +
			+ " {send event " + it.name + " expand}");
		tags := gettags(e.win, e.cvs, string e.spotid);
		addcross(e, it, tags);
		titlesize := dxy(e.titleitem.r);
		it.r.max = it.r.min.add((Taglen * 2 + Spotdiam + titlesize.x, titlesize.y));
		e.children = nil;
	"see" =>
		cmd(e.win, e.cvs + " see " + p2s(it.r.min));
	* =>
		sys->print("unknown event '%s' on item %s\n", ev, it.name);
	}
	return it;
}

Expander.childrenchanged(e: self ref Expander, it: Item): Item
{
	cmd(e.win, e.cvs + " delete !." + it.name);
	tags := gettags(e.win, e.cvs, string e.spotid);
	it.r = placechildren(e, it, tags);
	return it;
}

gettags(win: ref Tk->Toplevel, cvs: string, name: string): string
{
	tags := cmd(win, cvs + " gettags " + name);
	(n, tagl) := sys->tokenize(tags, " ");
	ntags := "";
	for (; tagl != nil; tagl = tl tagl) {
		t := hd tagl;
		if (t[0] != '!' && (t[0] < '0' || t[0] > '9'))
			ntags += " " + t;
	}
	return ntags;
}

spotcentre(origin, titlesize: Point): Point
{
	return (origin.x + Spotdiam / 2, origin.y + titlesize.y / 2);
}

addcross(e: ref Expander, it: Item, tags: string)
{
	p := spotcentre(it.r.min, dxy(e.titleitem.r));
	crosstags := " -tags {" + tags + " !." + it.name + "}";

	id1 := cmd(e.win, e.cvs + " create line " +
		p2s((p.x-Spotdiam/2, p.y)) + " " +
		p2s((p.x+Spotdiam/2, p.y)) + crosstags + Crossopts);
	id2 := cmd(e.win, e.cvs + " create line " +
		p2s((p.x, p.y-Spotdiam/2)) + " " +
		p2s((p.x, p.y+Spotdiam/2)) + crosstags + Crossopts);
	cmd(e.win, e.cvs + " lower " + id1 + ";" + e.cvs + " lower " + id2);
}

knownfont: string;
knownfontheight: int;
fontheight(win: ref Tk->Toplevel, font: string): int
{
	Font: import draw;
	if (font == knownfont)
		return knownfontheight;
	if (win.image == nil)			# can happen if we run out of image memory
		return -1;
	f := Font.open(win.image.display, font);
	if (f == nil)
		return -1;
	knownfont = font;
	knownfontheight = f.height;
	return f.height;
}

maketext(win: ref Tk->Toplevel, cvs: string, name: string, text: string): Item
{
	tag := " -tags " + name;
	it := Item(name, ((0, 0), (0, 0)), (0, 0));
	ttid := cmd(win, cvs + " create text 0 0 " +
		" -anchor nw" + tag +
		" -text '" + text);
	it.r = bbox(win, cvs, ttid);
	h := fontheight(win, cmd(win, cvs + " itemcget " + ttid + " -font"));
	if (h != -1) {
		dh := it.r.dy() - h;
		it.r.min.y += dh / 2;
		it.r.max.y -= dh / 2;
	}
	it.attach = (0, it.r.dy() / 2);
	return it;
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(sys->fildes(2), "items: tk error %s on '%s'\n", e, s);
	return e;
}

r2s(r: Rect): string
{
	return string r.min.x + " " + string r.min.y + " " +
			string r.max.x + " " + string r.max.y;
}

s2r(s: string): Rect
{
	(n, toks) := sys->tokenize(s, " ");
	if (n != 4) {
		sys->print("'%s' is not a rectangle!\n", s);
		raise "bad conversion";
	}
	r: Rect;
	(r.min.x, toks) = (int hd toks, tl toks);
	(r.min.y, toks) = (int hd toks, tl toks);
	(r.max.x, toks) = (int hd toks, tl toks);
	(r.max.y, toks) = (int hd toks, tl toks);
	return r;
}

Item.eq(i: self Item, j: Item): int
{
	return i.r.eq(j.r) && i.attach.eq(j.attach) && i.name == j.name;
}

Item.addpt(i: self Item, p: Point): Item
{
	i.r = i.r.addpt(p);
	return i;
}

Item.subpt(i: self Item, p: Point): Item
{
	i.r = i.r.subpt(p);
	return i;
}

p2s(p: Point): string
{
	return string p.x + " " + string p.y;
}

dxy(r: Rect): Point
{
	return r.max.sub(r.min);
}

max(a, b: int): int
{
	if (a > b)
		return a;
	return b;
}
