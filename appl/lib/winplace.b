implement Winplace;

#
# Copyright © 2003 Vita Nuova Holdings Limited
#

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Rect, Point: import draw;
include "winplace.m";

Delta: adt {
	d:		int;	# +1 or -1
	wid:		int;	# index into wr
	coord:	int;	# x/y coord
};

EW, NS: con iota;
Lay: adt {
	d: int;
	x: fn(l: self Lay, p: Point): int;
	y: fn(l: self Lay, p: Point): int;
	mkr: fn(l: self Lay, r: Rect): Rect;
};

init()
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
}

place(wins: list of Rect, scr, lastrect: Rect, minsize: Point): Rect
{
	found := find(wins, scr);
	if(found != nil){
		# first look for any spaces big enough to hold minsize;
		# choose top-left of those available.
		(ok, best) := findfit(found, minsize);
		if (ok){
			if(minsize.x == 0)
				return best;
			return (best.min, best.min.add(minsize));
		}
		if(minsize.x == 0)
			minsize = scr.size().div(2);
	}
	# no big enough space; try to avoid covering titlebars
	tfound := find(titlebarrects(wins), scr);
	(ok, best) := findfit(tfound, minsize);
	if (ok)
		return (best.min, best.min.add(minsize));
	tfound = nil;

	# no areas available - just find somewhere.
	if(found == nil)
		return somespace(scr, lastrect, minsize);

	# no big enough space found; find the largest area available
	# that will fit within minsize
	best = clipsize(hd found, minsize);
	area := best.dx() * best.dy();
	for (fl := tl found; fl != nil; fl = tl fl) {
		r := clipsize(hd fl, minsize);
		rarea := r.dx() * r.dy();
		if (rarea > area || (rarea == area && better(r, best)))
			(area, best) = (rarea, r);
	}
	best.max = best.min.add(minsize);
	return checkrect(best, scr);
}

findfit(found: list of Rect, minsize: Point): (int, Rect)
{
	best: Rect;
	ok := 0;
	for (fl := found; fl != nil; fl = tl fl) {
		r := hd fl;
		if (r.dx() < minsize.x || r.dy() < minsize.y)
			continue;
		if (!ok || better(r, best)) {
			best = r;
			ok++;
		}
	}
	return (ok, best);
}

TBARWIDTH: con 100;
TBARHEIGHT: con 20;
titlebarrects(rl: list of Rect): list of Rect
{
	nl: list of Rect;
	for (; rl != nil; rl = tl rl) {
		r := hd rl;
		tr := Rect((r.max.x - TBARWIDTH, r.min.y),
					(r.max.x, r.min.y + TBARHEIGHT));
		if (tr.min.x < r.min.x)
			tr.min.x = r.min.x;
		if (tr.max.y > r.max.y)
			tr.max.y = r.max.y;
		nl = tr :: nl;
	}
	return nl;
}

somespace(scr, lastrect: Rect, minsize: Point): Rect
{
	r := Rect(lastrect.min, lastrect.min.add(minsize)).addpt((20, 20));
	if (r.max.x > scr.max.x || r.max.y > scr.max.y)
		r = Rect(scr.min, scr.min.add(minsize));
	return r;
}

checkrect(r, scr: Rect): Rect
{
	# make sure it's all on screen
	if (r.max.x > scr.max.x) {
		dx := r.max.x - scr.max.x;
		r.max.x -= dx;
		r.min.x -= dx;
	}
	if (r.max.y > scr.max.y) {
		dy := r.max.y - scr.max.y;
		r.max.y -= dy;
		r.min.y -= dy;
	}

	# make sure origin is on screen.
	off := r.min.sub(scr.min);
	if (off.x > 0)
		off.x = 0;
	if (off.y > 0)
		off.y = 0;
	r = r.subpt(off);
	return r;
}

# return true if r1 is ``better'' placed than r2, all other things
# being equal.
# currently we choose top-most, left-most, in that order.
better(r1, r2: Rect): int
{
	return r1.min.y < r2.min.y ||
			(r1.min.y == r2.min.y && r1.min.x < r2.min.x);
}

clipsize(r: Rect, size: Point): Rect
{
	if (r.dx() > size.x)
		r.max.x = r.min.x + size.x;
	if (r.dy() > size.y)
		r.max.y = r.min.y + size.y;
	return r;
}

find(wins: list of Rect, scr: Rect): list of Rect
{

	n := len wins + 4;
	wr := array[n] of Rect;
	for (; wins != nil; wins = tl wins)
		wr[--n] = hd wins;
	scr2 := scr.inset(-1);
	# border sentinels
	wr[3] = Rect((scr.min.x,scr2.min.y), (scr.max.x, scr.min.y));		# top
	wr[2] = Rect((scr2.min.x, scr2.min.y), (scr.min.x, scr2.max.y));		# left
	wr[1] = Rect((scr.min.x, scr.max.y), (scr.max.x, scr2.max.y));		# bottom
	wr[0] = Rect((scr.max.x, scr2.min.y), (scr2.max.x, scr2.max.y));	# right
	found := sweep(wr, Lay(EW), nil);
	return sweep(wr, Lay(NS), found);
}

sweep(wr: array of Rect, lay: Lay, found: list of Rect): list of Rect
{
	# sweep through in the direction of lay,
	# adding and removing end points of rectangles
	# as we pass them, and maintaining list of current viable rectangles.
	maj := sortcoords(wr, lay);
	(cr, ncr) := (array[len wr * 2] of Delta, 0);
	rl: list of Rect;		# ordered by lay.y(min)
	for (i := 0; i < len maj; i++) {
		wid := maj[i].wid;
		if (maj[i].d > 0)
			ncr = addwin(cr, ncr, wid, lay.y(wr[wid].min), lay.y(wr[wid].max));
		else
			ncr = removewin(cr, ncr, wid, lay.y(wr[wid].min), lay.y(wr[wid].max));
		nrl: list of Rect = nil;
		count := 0;
		for (j := 0; j < ncr - 1; j++) {
			count += cr[j].d;
			(start, end) := (cr[j].coord, cr[j+1].coord);
			if (count == 0 && end > start) {
				nf: list of Rect;
				(rl, nrl, nf) = select(rl, nrl, maj[i].coord, start, end);
				for (; nf != nil; nf = tl nf)
					found = addfound(found, lay.mkr(hd nf));
			}
		}
		for (; rl != nil; rl = tl rl) {
			r := hd rl;
			r.max.x = maj[i].coord;
			found = addfound(found, lay.mkr(r));
		}
		for (; nrl != nil; nrl = tl nrl)
			rl = hd nrl :: rl;
		nrl = nil;
	}
	return found;
}

addfound(found: list of Rect, r: Rect): list of Rect
{
	if (r.max.x - r.min.x < 1 ||
			r.max.y - r.min.y < 1)
		return found;
	return r :: found;
}

select(rl, nrl: list of Rect, xcoord, start, end: int): (list of Rect, list of Rect, list of Rect)
{
	found: list of Rect;
	made := 0;
	while (rl != nil) {
		r := hd rl;
		r.max.x = xcoord;
		(rstart, rend) := (r.min.y, r.max.y);
		if (rstart >= end)
			break;
		addit := 1;
		if (rstart == start && rend == end) {
			made = 1;
		} else {
			if (!made && rstart > start) {
				nrl = ((xcoord, start), (xcoord, end)) :: nrl;
				made = 1;
			}
			if (rend > end || rstart < start) {
				found = r :: found;
				if (rend > end)
					rend = end;
				if (rstart < start)
					rstart = start;
				if (rstart >= rend)
					addit = 0;
				(r.min.y, r.max.y) = (rstart, rend);
			}
		}
		if (addit)
			nrl = r :: nrl;
		rl = tl rl;
	}
	if (!made)
		nrl = ((xcoord, start), (xcoord, end)) :: nrl;
	return (rl, nrl, found);
}

removewin(d: array of Delta, nd: int, wid: int, min, max: int): int
{
	minidx := finddelta(d, nd, Delta(+1, wid, min));
	maxidx := finddelta(d, nd, Delta(-1, wid, max));
	if (minidx == -1 || maxidx == -1 || minidx == maxidx) {
		sys->fprint(sys->fildes(2),
				"bad delta find; minidx: %d; maxidx: %d; wid: %d; min: %d; max: %d\n",
				minidx, maxidx, wid, min, max);
		raise "panic";
	}
	d[minidx:] = d[minidx + 1:maxidx];
	d[maxidx - 1:] = d[maxidx + 1:nd];
	return nd - 2;
}

addwin(d: array of Delta, nd: int, wid: int, min, max: int): int
{
	(minidx, maxidx) := (findcoord(d, nd, min), findcoord(d, nd, max));
	d[maxidx + 2:] = d[maxidx:nd];
	d[maxidx + 1] = Delta(-1, wid, max);
	d[minidx + 1:] = d[minidx:maxidx];
	d[minidx] = Delta(+1, wid, min);
	return nd + 2;
}

finddelta(d: array of Delta, nd: int, df: Delta): int
{
	idx := findcoord(d, nd, df.coord);
	for (i := idx; i < nd && d[i].coord == df.coord; i++)
		if (d[i].wid == df.wid && d[i].d == df.d)
			return i;
	for (i = idx - 1; i >= 0 && d[i].coord == df.coord; i--)
		if (d[i].wid == df.wid && d[i].d == df.d)
			return i;
	return -1;
}

findcoord(d: array of Delta, nd: int, coord: int): int
{
	(lo, hi) := (0, nd - 1);
	while (lo <= hi) {
		mid := (lo + hi) / 2;
		if (coord < d[mid].coord)
			hi = mid - 1;
		else if (coord > d[mid].coord)
			lo = mid + 1;
		else
			return mid;
	}
	return lo;
}

sortcoords(wr: array of Rect, lay: Lay): array of Delta
{
	a := array[len wr * 2] of Delta;
	j := 0;
	for (i := 0; i < len wr; i++) {
		a[j++] = (+1, i, lay.x(wr[i].min));
		a[j++] = (-1, i, lay.x(wr[i].max));
	}
	sortdelta(a);
	return a;
}

sortdelta(a: array of Delta)
{
	n := len a;
	for(m := n; m > 1; ) {
		if(m < 5)
			m = 1;
		else
			m = (5*m-1)/11;
		for(i := n-m-1; i >= 0; i--) {
			tmp := a[i];
			for(j := i+m; j <= n-1 && tmp.coord > a[j].coord; j += m)
				a[j-m] = a[j];
			a[j-m] = tmp;
		}
	}
}

Lay.x(l: self Lay, p: Point): int
{
	if (l.d == EW)
		return p.x;
	return p.y;
}

Lay.y(l: self Lay, p: Point): int
{
	if (l.d == EW)
		return p.y;
	return p.x;
}

Lay.mkr(l: self Lay, r: Rect): Rect
{
	if (l.d == EW)
		return r;
	return ((r.min.y, r.min.x), (r.max.y, r.max.x));
}
