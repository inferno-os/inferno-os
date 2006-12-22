implement Polyfill;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect, Image, Endsquare: import draw;
include "math/polyfill.m";

∞: con 16r7fffffff;

init()
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
}

initzbuf(r: Rect): ref Zstate
{
	if(sys == nil)
		init();
	s := ref Zstate;
	s.r = r;
	s.xlen = r.dx();
	s.ylen = r.dy();
	s.xylen = s.xlen*s.ylen;
	s.zbuf0 = array[s.xylen] of int;
	s.zbuf1 = array[s.xylen] of int;
	return s;
}

clearzbuf(s: ref Zstate)
{
	b0 := s.zbuf0;
	b1 := s.zbuf1;
	n := s.xylen;
	for(i := 0; i < n; i++)
		b0[i] = b1[i] = ∞;
}

setzbuf(s: ref Zstate, zd: int)
{
	b0 := s.zbuf0;
	b1 := s.zbuf1;
	n := s.xylen;
	for(i := 0; i < n; i++)
		b0[i] = b1[i] = zd;
}

Seg: adt
{
	p0: Point;
	p1: Point;
	num: int;
	den: int;
	dz: int;
	dzrem: int;
	z: int;
	zerr: int;
	d: int;
};

fillline(dst: ref Image, left: int, right: int, y: int, src: ref Image, p: Point)
{
	p.x += left;
	p.y += y;
	dst.line((left, y), (right, y), Endsquare, Endsquare, 0, src, p);
}

filllinez(dst: ref Image, left: int, right: int, y: int, z: int, e: int, dx: int, k: int, zbuf0: array of int, zbuf1: array of int, src: ref Image, p: Point)
{
	prevx := ∞;
	for(x := left; x <= right; x++){
		if(z+e < zbuf0[k] || (z-e <= zbuf1[k] && x != right && prevx != ∞)){
			zbuf0[k] = z-e;
			zbuf1[k] = z+e;
			if(prevx == ∞)
				prevx = x;
		}
		else if(prevx != ∞){
			fillline(dst, prevx, x-1, y, src, p);
			prevx = ∞;
		}
		z += dx;
		k++;
	}
	if(prevx != ∞)
		fillline(dst, prevx, right, y, src, p);
}

fillpoly(dst: ref Image, vert: array of Point, w: int, src: ref Image, sp: Point, zstate: ref Zstate, dc: int, dx: int, dy: int)
{
	p0: Point;
	i: int;

	nvert := len vert;
	if(nvert == 0)
		return;
	fixshift := 0;
	seg := array[nvert+2] of ref Seg;
	if(seg == nil)
		return;
	segtab := array[nvert+1] of ref Seg;
	if(segtab == nil)
		return;

	sp.x = (sp.x - vert[0].x) >> fixshift;
	sp.y = (sp.y - vert[0].y) >> fixshift;
	p0 = vert[nvert-1];
	if(!fixshift) {
		p0.x <<= 1;
		p0.y <<= 1;
	}
	for(i = 0; i < nvert; i++) {
		segtab[i] = ref Seg;
		segtab[i].p0 = p0;
		p0 = vert[i];
		if(!fixshift) {
			p0.x <<= 1;
			p0.y <<= 1;
		}
		segtab[i].p1 = p0;
		segtab[i].d = 1;
	}
	if(!fixshift)
		fixshift = 1;

	xscan(dst, seg, segtab, nvert, w, src, sp, zstate, dc, dx, dy, fixshift);
}

mod(x: int, y: int): int
{
	z: int;

	z = x%y;
	if((z^y) > 0 || z == 0)
		return z;
	return z + y;
}

sdiv(x: int, y: int): int
{
	if((x^y) >= 0 || x == 0)
		return x/y;
	return (x+((y>>30)|1))/y-1;
}

smuldivmod(x: int, y: int, z: int): (int, int)
{
	mod: int;
	vx: int;

	if(x == 0 || y == 0)
		return (0, 0);
	vx = x;
	vx *= y;
	mod = vx % z;
	if(mod < 0)
		mod += z;
	if((vx < 0) == (z < 0))
		return (vx/z, mod);
	return (-((-vx)/z), mod);
}

xscan(dst: ref Image, seg: array of ref Seg, segtab: array of ref Seg, nseg: int, wind: int, src: ref Image, spt: Point, zstate: ref Zstate, dc: int, dx: int, dy: int, fixshift: int)
{
	y, maxy, x, x2, onehalf: int;
	ep, next, p, q, s: int;
	n, i, iy, cnt, ix, ix2, minx, maxx, zinc, k, zv: int;
	pt: Point;
	sp: ref Seg;

	er := (abs(dx)+abs(dy)+1)/2;
	zr := zstate.r;
	xlen := zstate.xlen;
	zbuf0 := zstate.zbuf0;
	zbuf1 := zstate.zbuf1;
	s = 0;
	p = 0;
	for(i=0; i<nseg; i++) {
		sp = seg[p] = segtab[s];
		if(sp.p0.y == sp.p1.y){
			s++;
			continue;
		}
		if(sp.p0.y > sp.p1.y) {
			pt = sp.p0;
			sp.p0 = sp.p1;
			sp.p1 = pt;
			sp.d = -sp.d;
		}
		sp.num = sp.p1.x - sp.p0.x;
		sp.den = sp.p1.y - sp.p0.y;
		sp.dz = sdiv(sp.num, sp.den) << fixshift;
		sp.dzrem = mod(sp.num, sp.den) << fixshift;
		sp.dz += sdiv(sp.dzrem, sp.den);
		sp.dzrem = mod(sp.dzrem, sp.den);
		p++;
		s++;
	}
	n = p;
	if(n == 0)
		return;
	seg[p] = nil;
	qsortycompare(seg, p);

	onehalf = 0;
	if(fixshift)
		onehalf = 1 << (fixshift-1);

	minx = dst.clipr.min.x;
	maxx = dst.clipr.max.x;

	y = seg[0].p0.y;
	if(y < (dst.clipr.min.y << fixshift))
		y = dst.clipr.min.y << fixshift;
	iy = (y + onehalf) >> fixshift;
	y = (iy << fixshift) + onehalf;
	maxy = dst.clipr.max.y << fixshift;
	k = (iy-zr.min.y)*xlen;
	zv = dc+iy*dy;

	ep = next = 0;

	while(y<maxy) {
		for(q = p = 0; p < ep; p++) {
			sp = seg[p];
			if(sp.p1.y < y)
				continue;
			sp.z += sp.dz;
			sp.zerr += sp.dzrem;
			if(sp.zerr >= sp.den) {
				sp.z++;
				sp.zerr -= sp.den;
				if(sp.zerr < 0 || sp.zerr >= sp.den)
					sys->print("bad ratzerr1: %d den %d dzrem %d\n", sp.zerr, sp.den, sp.dzrem);
			}
			seg[q] = sp;
			q++;
		}

		for(p = next; seg[p] != nil; p++) {
			sp = seg[p];
			if(sp.p0.y >= y)
				break;
			if(sp.p1.y < y)
				continue;
			sp.z = sp.p0.x;
			(zinc, sp.zerr) = smuldivmod(y - sp.p0.y, sp.num, sp.den);
			sp.z += zinc;
			if(sp.zerr < 0 || sp.zerr >= sp.den)
				sys->print("bad ratzerr2: %d den %d ratdzrem %d\n", sp.zerr, sp.den, sp.dzrem);
			seg[q] = sp;
			q++;
		}
		ep = q;
		next = p;

		if(ep == 0) {
			if(seg[next] == nil)
				break;
			iy = (seg[next].p0.y + onehalf) >> fixshift;
			y = (iy << fixshift) + onehalf;
			k = (iy-zr.min.y)*xlen;
			zv = dc+iy*dy;
			continue;
		}

		zsort(seg, ep);

		for(p = 0; p < ep; p++) {
			sp = seg[p];
			cnt = 0;
			x = sp.z;
			ix = (x + onehalf) >> fixshift;
			if(ix >= maxx)
				break;
			if(ix < minx)
				ix = minx;
			cnt += sp.d;
			p++;
			sp = seg[p];
			for(;;) {
				if(p == ep) {
					sys->print("xscan: fill to infinity");
					return;
				}
				cnt += sp.d;
				if((cnt&wind) == 0)
					break;
				p++;
				sp = seg[p];
			}
			x2 = sp.z;
			ix2 = (x2 + onehalf) >> fixshift;
			if(ix2 <= minx)
				continue;
			if(ix2 > maxx)
				ix2 = maxx;
			filllinez(dst, ix, ix2, iy, zv+ix*dx, er, dx, k+ix-zr.min.x, zbuf0, zbuf1, src, spt);
		}
		y += (1<<fixshift);
		iy++;
		k += xlen;
		zv += dy;
	}
}

zsort(seg: array of ref Seg, ep: int)
{
	done: int;
	s: ref Seg;
	q, p: int;

	if(ep < 20) {
		# bubble sort by z - they should be almost sorted already
		q = ep;
		do {
			done = 1;
			q--;
			for(p = 0; p < q; p++) {
				if(seg[p].z > seg[p+1].z) {
					s = seg[p];
					seg[p] = seg[p+1];
					seg[p+1] = s;
					done = 0;
				}
			}
		} while(!done);
	} else {
		q = ep-1;
		for(p = 0; p < q; p++) {
			if(seg[p].z > seg[p+1].z) {
				qsortzcompare(seg, ep);
				break;
			}
		}
	}
}

ycompare(s0: ref Seg, s1: ref Seg): int
{
	y0, y1: int;

	y0 = s0.p0.y;
	y1 = s1.p0.y;

	if(y0 < y1)
		return -1;
	if(y0 == y1)
		return 0;
	return 1;
}

zcompare(s0: ref Seg, s1: ref Seg): int
{
	z0, z1: int;

	z0 = s0.z;
	z1 = s1.z;

	if(z0 < z1)
		return -1;
	if(z0 == z1)
		return 0;
	return 1;
}

qsortycompare(a : array of ref Seg, n : int)
{
	i, j : int;
	t : ref Seg;

	while(n > 1) {
		i = n>>1;
		t = a[0]; a[0] = a[i]; a[i] = t;
		i = 0;
		j = n;
		for(;;) {
			do
				i++;
			while(i < n && ycompare(a[i], a[0]) < 0);
			do
				j--;
			while(j > 0 && ycompare(a[j], a[0]) > 0);
			if(j < i)
				break;
			t = a[i]; a[i] = a[j]; a[j] = t;
		}
		t = a[0]; a[0] = a[j]; a[j] = t;
		n = n-j-1;
		if(j >= n) {
			qsortycompare(a, j);
			a = a[j+1:];
		} else {
			qsortycompare(a[j+1:], n);
			n = j;
		}
	}
}

qsortzcompare(a : array of ref Seg, n : int)
{
	i, j : int;
	t : ref Seg;

	while(n > 1) {
		i = n>>1;
		t = a[0]; a[0] = a[i]; a[i] = t;
		i = 0;
		j = n;
		for(;;) {
			do
				i++;
			while(i < n && zcompare(a[i], a[0]) < 0);
			do
				j--;
			while(j > 0 && zcompare(a[j], a[0]) > 0);
			if(j < i)
				break;
			t = a[i]; a[i] = a[j]; a[j] = t;
		}
		t = a[0]; a[0] = a[j]; a[j] = t;
		n = n-j-1;
		if(j >= n) {
			qsortzcompare(a, j);
			a = a[j+1:];
		} else {
			qsortzcompare(a[j+1:], n);
			n = j;
		}
	}
}

abs(n: int): int
{
	if(n < 0)
		return -n;
	return n;
}
