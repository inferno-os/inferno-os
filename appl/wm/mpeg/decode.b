implement Mpegd;

include "sys.m";
include "mpegio.m";

sys: Sys;
idct: IDCT;

Mpegi, Picture, Slice, MacroBlock, YCbCr, Pair: import Mpegio;

intra_tab := array[64] of {
	8, 16, 19, 22, 26, 27, 29, 34,
	16, 16, 22, 24, 27, 29, 34, 37,
	19, 22, 26, 27, 29, 34, 34, 38,
	22, 22, 26, 27, 29, 34, 37, 40,
	22, 26, 27, 29, 32, 35, 40, 48,
	26, 27, 29, 32, 35, 40, 48, 58,
	26, 27, 29, 34, 38, 46, 56, 69,
	27, 29, 35, 38, 46, 56, 69, 83,
};

nintra_tab := array[64] of { * => 16 };

CLOFF: con 256;

intraQ, nintraQ: array of int;
rtmp: array of array of int;
rflag := array[6] of int;
rforw, dforw, rback, dback: int;
rforw2, dforw2, rback2, dback2: int;
ydb, ydf, cdb, cdf: int;
vflags: int;
past := array[3] of int;
pinit := array[3] of { * => 128 * 8 };
zeros := array[64] of { * => 0 };
zeros1: array of int;
clamp := array[CLOFF + 256 + CLOFF] of byte;
width, height, w2, h2: int;
mpi, mps, yadj, cadj, yskip: int;
I, B0: ref YCbCr;
Ps := array[2] of ref YCbCr;
Rs := array[2] of ref YCbCr;
P, B, R, M, N: ref YCbCr;
pn: int = 0;
rn: int = 0;

zig := array[64] of {
	0, 1, 8, 16, 9, 2, 3, 10, 17,
	24, 32, 25, 18, 11, 4, 5,
	12, 19, 26, 33, 40, 48, 41, 34,
	27, 20, 13, 6, 7, 14, 21, 28, 
	35, 42, 49, 56, 57, 50, 43, 36,
	29, 22, 15, 23, 30, 37, 44, 51,
	58, 59, 52, 45, 38, 31, 39, 46,
	53, 60, 61, 54, 47, 55, 62, 63,
};

init(m: ref Mpegi)
{
	sys = load Sys Sys->PATH;
	idct = load IDCT IDCT->PATH;
	if (idct == nil) {
		sys->print("could not open %s: %r\n", IDCT->PATH);
		exit;
	}
	idct->init();
	width = m.width;
	height = m.height;
	w2 = width >> 1;
	h2 = height >> 1;
	mps = width >> 4;
	mpi = mps * height >> 4;
	yskip = 8 * width;
	yadj = 16 * width - (width - 16);
	cadj = 8 * w2 - (w2 - 8);
	I = frame();
	Ps[0] = frame();
	Ps[1] = frame();
	Rs[0] = Ps[0];
	Rs[1] = Ps[1];
	B0 = frame();
	for (i := 0; i < CLOFF; i++)
		clamp[i] = byte 0;
	for (i = 0; i < 256; i++)
		clamp[i + CLOFF] = byte i;
	for (i = CLOFF + 256; i < CLOFF + 256 + CLOFF; i++)
		clamp[i] = byte 255;
	if (m.intra == nil)
		intraQ = intra_tab;
	else
		intraQ = zigof(m.intra);
	if (m.nintra == nil)
		nintraQ = nintra_tab;
	else
		nintraQ = zigof(m.nintra);
	rtmp = array[6] of array of int;
	for (i = 0; i < 6; i++)
		rtmp[i] = array[64] of int;
	zeros1 = zeros[1:];
}

zarray(n: int, v: byte): array of byte
{
	return array[n] of { * => v };
}

frame(): ref YCbCr
{
	y := zarray(width * height, byte 0);
	b := zarray(w2 * h2, byte 128);
	r := zarray(w2 * h2, byte 128);
	return ref YCbCr(y, b, r);
}

zigof(a: array of int): array of int
{
	z := array[64] of int;
	for (i := 0; i < 64; i++)
		z[zig[i]] = a[i];
	return z;
}

invQ_intra(a: array of Pair, q: int, b: array of int)
{
	(nil, t) := a[0];
	b[0] = t * 8;
	b[1:] = zeros1;
	n := 1;
	i := 1;
	while (n < len a) {
		(r, l) := a[n++];
		i += r;
		x := zig[i++];
		if (l > 0) {
			v := l * q * intraQ[x] >> 3;
			if (v > 2047)
				b[x] = 2047;
			else
				b[x] = (v - 1) | 1;
		} else {
			v := (l * q * intraQ[x] + 7) >> 3;
			if (v < -2048)
				b[x] = -2048;
			else
				b[x] = v | 1;
		}
		#sys->print("%d %d %d %d\n", x, r, l, b[x]);
	}
}

invQ_nintra(a: array of Pair, q: int, b: array of int)
{
	b[0:] = zeros;
	i := 0;
	for (n := 0; n < len a; n++) {
		(r, l) := a[n];
		i += r;
		if (l == 0) {
			raisex("zero level");
			i++;
			continue;
		}
		x := zig[i++];
		if (l > 0) {
			v := ((l << 1) + 1) * q * nintraQ[x] >> 4;
			if (v > 2047)
				b[x] = 2047;
			else
				b[x] = (v - 1) | 1;
		} else {
			v := (((l << 1) - 1) * q * nintraQ[x] + 15) >> 4;
			if (v < -2048)
				b[x] = -2048;
			else
				b[x] = v | 1;
		}
		#sys->print("%d %d %d %d\n", x, r, l, b[x]);
	}
}

yzero(v: array of byte, base: int)
{
	x := 0;
	i := 8;
	do {
		n := base;
		j := 8;
		do
			v[n++] = byte 0;
		while (--j > 0);
		base += width;
	} while (--i > 0);
}

czero(v: array of byte, base: int)
{
	x := 0;
	i := 8;
	do {
		n := base;
		j := 8;
		do
			v[n++] = byte 128;
		while (--j > 0);
		base += w2;
	} while (--i > 0);

}

blockzero(d: ref YCbCr)
{
	yzero(d.Y, ybase);
	yzero(d.Y, ybase + 8);
	yzero(d.Y, ybase + yskip);
	yzero(d.Y, ybase + 8 + yskip);
	czero(d.Cb, cbase);
	czero(d.Cr, cbase);
}

ydistr(a: array of int, v: array of byte, base: int)
{
	x := 0;
	i := 8;
	do {
		n := base;
		j := 8;
		do
			v[n++] = clamp[a[x++] + CLOFF];
		while (--j > 0);
		base += width;
	} while (--i > 0);
}

cdistr(a: array of int, v: array of byte, base: int)
{
	x := 0;
	i := 8;
	do {
		n := base;
		j := 8;
		do
			v[n++] = clamp[a[x++] + CLOFF];
		while (--j > 0);
		base += w2;
	} while (--i > 0);

}

invQ_intra_block(b: array of array of Pair, q: int, pred: int, d: ref YCbCr)
{
	a, dc: array of int;
	if (pred)
		dc = past;
	else
		dc = pinit;
	p := dc[0];
	for (i := 0; i < 4; i++) {
		a = rtmp[i];
		#sys->print("%d\n", i);
		invQ_intra(b[i], q, a);
		p += a[0];
		a[0] = p;
		#sys->print("%d\n", a[0]);
		idct->idct(a);
	}
	past[0] = p;
	for (i = 4; i < 6; i++) {
		p = dc[i - 3];
		a = rtmp[i];
		#sys->print("%d\n", i);
		invQ_intra(b[i], q, a);
		p += a[0];
		a[0] = p;
		#sys->print("%d\n", a[0]);
		past[i - 3] = p;
		idct->idct(a);
	}
	ydistr(rtmp[0], d.Y, ybase);
	ydistr(rtmp[1], d.Y, ybase + 8);
	ydistr(rtmp[2], d.Y, ybase + yskip);
	ydistr(rtmp[3], d.Y, ybase + 8 + yskip);
	cdistr(rtmp[4], d.Cb, cbase);
	cdistr(rtmp[5], d.Cr, cbase);
}

invQ_nintra_block(b: array of array of Pair, q: int)
{
	for (i := 0; i < 6; i++) {
		p := b[i];
		if (p != nil) {
			a := rtmp[i];
			#sys->print("%d\n", i);
			invQ_nintra(p, q, a);
			idct->idct(a);
			rflag[i] = 1;
		} else
			rflag[i] = 0;
	}
}

mbr, ybase, cbase: int;

nextmb()
{
	if (--mbr == 0) {
		ybase += yadj;
		cbase += cadj;
		mbr = mps;
	} else {
		ybase += 16;
		cbase += 8;
	}
}

copyblock(s, d: array of byte, b, n, w: int)
{
	i := 8;
	do {
		d[b:] = s[b:b+n];
		b += w;
	} while (--i > 0);
}

copyblockdisp(s, d: array of byte, b, n, w, p: int)
{
	i := 8;
	p += b;
	do {
		d[b:] = s[p:p+n];
		b += w;
		p += w;
	} while (--i > 0);
}

interpblock(s0, s1, d: array of byte, b, n, w, p0, p1: int)
{
	i := 8;
	do {
		dx := b;
		s0x := b + p0;
		s1x := b + p1;
		j := n;
		do
			d[dx++] = byte ((int s0[s0x++] + int s1[s1x++] + 1) >> 1);
		while (--j > 0);
		b += w;
	} while (--i > 0);
}

deltablock(s: array of byte, r: array of int, d: array of byte, b, w, o: int)
{
	rx := 0;
	i := 8;
	do {
		dx := b;
		sx := b + o;
		j := 8;
		do
			d[dx++] = clamp[CLOFF + int s[sx++] + r[rx++]];
		while (--j > 0);
		b += w;
	} while (--i > 0);
}

deltainterpblock(s0, s1: array of byte, r: array of int, d: array of byte, b, w, o0, o1: int)
{
	rx := 0;
	i := 8;
	do {
		dx := b;
		s0x := b + o0;
		s1x := b + o1;
		j := 8;
		do
			d[dx++] = clamp[CLOFF + ((int s0[s0x++] + int s1[s1x++] + 1) >> 1) + r[rx++]];
		while (--j > 0);
		b += w;
	} while (--i > 0);
}

dispblock(s, d: array of byte, n, b, w, o: int)
{
	if (rflag[n])
		deltablock(s, rtmp[n], d, b, w, o);
	else
		copyblockdisp(s, d, b, 8, w, o);
}

genblock(s0, s1, d: array of byte, n, b, w, o0, o1: int)
{
	if (rflag[n])
		deltainterpblock(s0, s1, rtmp[n], d, b, w, o0, o1);
	else
		interpblock(s0, s1, d, b, 8, w, o0, o1);
}

copymb()
{
	copyblock(R.Y, P.Y, ybase, 16, width);
	copyblock(R.Y, P.Y, ybase + yskip, 16, width);
	copyblock(R.Cb, P.Cb, cbase, 8, w2);
	copyblock(R.Cr, P.Cr, cbase, 8, w2);
}

deltamb()
{
	dispblock(R.Y, P.Y, 0, ybase, width, 0);
	dispblock(R.Y, P.Y, 1, ybase + 8, width, 0);
	dispblock(R.Y, P.Y, 2, ybase + yskip, width, 0);
	dispblock(R.Y, P.Y, 3, ybase + 8 + yskip, width, 0);
	dispblock(R.Cb, P.Cb, 4, cbase, w2, 0);
	dispblock(R.Cr, P.Cr, 5, cbase, w2, 0);
}

copymbforw()
{
	copyblockdisp(N.Y, B.Y, ybase, 16, width, ydf);
	copyblockdisp(N.Y, B.Y, ybase + yskip, 16, width, ydf);
	copyblockdisp(N.Cb, B.Cb, cbase, 8, w2, cdf);
	copyblockdisp(N.Cr, B.Cr, cbase, 8, w2, cdf);
}

copymbback()
{
	copyblockdisp(M.Y, B.Y, ybase, 16, width, ydb);
	copyblockdisp(M.Y, B.Y, ybase + yskip, 16, width, ydb);
	copyblockdisp(M.Cb, B.Cb, cbase, 8, w2, cdb);
	copyblockdisp(M.Cr, B.Cr, cbase, 8, w2, cdb);
}

copymbbackforw()
{
	interpblock(M.Y, N.Y, B.Y, ybase, 16, width, ydb, ydf);
	interpblock(M.Y, N.Y, B.Y, ybase + yskip, 16, width, ydb, ydf);
	interpblock(M.Cb, N.Cb, B.Cb, cbase, 8, w2, cdb, cdf);
	interpblock(M.Cr, N.Cr, B.Cr, cbase, 8, w2, cdb, cdf);
}

deltambforw()
{
	dispblock(N.Y, B.Y, 0, ybase, width, ydf);
	dispblock(N.Y, B.Y, 1, ybase + 8, width, ydf);
	dispblock(N.Y, B.Y, 2, ybase + yskip, width, ydf);
	dispblock(N.Y, B.Y, 3, ybase + 8 + yskip, width, ydf);
	dispblock(N.Cb, B.Cb, 4, cbase, w2, cdf);
	dispblock(N.Cr, B.Cr, 5, cbase, w2, cdf);
}

deltambback()
{
	dispblock(M.Y, B.Y, 0, ybase, width, ydb);
	dispblock(M.Y, B.Y, 1, ybase + 8, width, ydb);
	dispblock(M.Y, B.Y, 2, ybase + yskip, width, ydb);
	dispblock(M.Y, B.Y, 3, ybase + 8 + yskip, width, ydb);
	dispblock(M.Cb, B.Cb, 4, cbase, w2, cdb);
	dispblock(M.Cr, B.Cr, 5, cbase, w2, cdb);
}

deltambbackforw()
{
	genblock(M.Y, N.Y, B.Y, 0, ybase, width, ydb, ydf);
	genblock(M.Y, N.Y, B.Y, 1, ybase + 8, width, ydb, ydf);
	genblock(M.Y, N.Y, B.Y, 2, ybase + yskip, width, ydb, ydf);
	genblock(M.Y, N.Y, B.Y, 3, ybase + 8 + yskip, width, ydb, ydf);
	genblock(M.Cb, N.Cb, B.Cb, 4, cbase, w2, cdb, cdf);
	genblock(M.Cr, N.Cr, B.Cr, 5, cbase, w2, cdb, cdf);
}

deltambinterp()
{
	case vflags & (Mpegio->MB_MF | Mpegio->MB_MB) {
	Mpegio->MB_MF =>
		deltambforw();
	Mpegio->MB_MB =>
		deltambback();
	Mpegio->MB_MF | Mpegio->MB_MB =>
		deltambbackforw();
	* =>
		raisex("bad vflags");
	}
}

interpmb()
{
	case vflags & (Mpegio->MB_MF | Mpegio->MB_MB) {
	Mpegio->MB_MF =>
		copymbforw();
	Mpegio->MB_MB =>
		copymbback();
	Mpegio->MB_MF | Mpegio->MB_MB =>
		copymbbackforw();
	* =>
		raisex("bad vflags");
	}
}

Idecode(p: ref Picture): ref YCbCr
{
	sa := p.slices;
	n := 0;
	mbr = mps;
	ybase = 0;
	cbase = 0;
	for (i := 0; i < len sa; i++) {
		pred := 0;
		ba := sa[i].blocks;
		for (j := 0; j < len ba; j++) {
			invQ_intra_block(ba[j].rls, ba[j].qscale, pred, I);
			nextmb();
			n++;
			pred = 1;
		}
	}
	if (n != mpi)
		raisex("I mb count");
	R = I;
	Rs[rn] = I;
	rn ^= 1;
	return I;
}

Pdecode(p: ref Picture): ref YCbCr
{
	rforwp, dforwp: int;
	md, c: int;
	P = Ps[pn];
	N = R;
	B = P;
	pn ^= 1;
	fs := 1 << p.forwfc;
	fsr := fs << 5;
	fsmin := -(fs << 4);
	fsmax := (fs << 4) - 1;
	sa := p.slices;
	n := 0;
	mbr = mps;
	ybase = 0;
	cbase = 0;
	for (i := 0; i < len sa; i++) {
		pred := 0;
		ipred := 0;
		ba := sa[i].blocks;
		for (j := 0; j < len ba; j++) {
			mb := ba[j];
			while (n < mb.addr) {
				copymb();
				ipred = 0;
				pred = 0;
				nextmb();
				n++;
			}
			if (mb.flags & Mpegio->MB_I) {
				invQ_intra_block(mb.rls, mb.qscale, ipred, P);
				#blockzero(P);
				ipred = 1;
				pred = 0;
			} else {
				if (mb.flags & Mpegio->MB_MF) {
					if (fs == 1 || mb.mhfc == 0)
						md = mb.mhfc;
					else if ((c = mb.mhfc) < 0)
						md = (c + 1) * fs - mb.mhfr - 1;
					else
						md = (c - 1) * fs + mb.mhfr + 1;
					if (pred)
						md += rforwp;
					if (md > fsmax)
						rforw = md - fsr;
					else if (md < fsmin)
						rforw = md + fsr;
					else
						rforw = md;
					rforwp = rforw;
					if (fs == 1 || mb.mvfc == 0)
						md = mb.mvfc;
					else if ((c = mb.mvfc) < 0)
						md = (c + 1) * fs - mb.mvfr - 1;
					else
						md = (c - 1) * fs + mb.mvfr + 1;
					if (pred)
						md += dforwp;
					if (md > fsmax)
						dforw = md - fsr;
					else if (md < fsmin)
						dforw = md + fsr;
					else
						dforw = md;
					dforwp = dforw;
					if (p.flags & Mpegio->FPFV) {
						rforw2 = rforw;
						dforw2 = dforw;
						rforw <<= 1;
						dforw <<= 1;
						ydf = rforw2 + dforw2 * width;
						cdf = (rforw2 >> 1) + (dforw2 >> 1) * w2;
					} else {
						if (rforw < 0)
							rforw2 = (rforw + 1) >> 1;
						else
							rforw2 = rforw >> 1;
						if (dforw < 0)
							dforw2 = (dforw + 1) >> 1;
						else
							dforw2 = dforw >> 1;
						ydf = (rforw >> 1) + (dforw >> 1) * width;
						cdf = (rforw2 >> 1) + (dforw2 >> 1) * w2;
					}
					pred = 1;
					if (mb.rls != nil) {
						invQ_nintra_block(mb.rls, mb.qscale);
						deltambforw();
					} else
						copymbforw();
				} else {
					if (mb.rls == nil)
						raisex("empty delta");
					invQ_nintra_block(mb.rls, mb.qscale);
					deltamb();
					pred = 0;
				}
				ipred = 0;
			}
			nextmb();
			n++;
		}
	}
	while (n < mpi) {
		copymb();
		nextmb();
		n++;
	}
	R = P;
	Rs[rn] = P;
	rn ^= 1;
	return P;
}

Bdecode(p: ref Mpegio->Picture): ref Mpegio->YCbCr
{
	return Bdecode2(p, Rs[rn ^ 1], Rs[rn]);
}

Bdecode2(p: ref Mpegio->Picture, f0, f1: ref Mpegio->YCbCr): ref Mpegio->YCbCr
{
	rforwp, dforwp, rbackp, dbackp: int;
	md, c: int;
	M = f0;
	N = f1;
	B = B0;
	fs := 1 << p.forwfc;
	fsr := fs << 5;
	fsmin := -(fs << 4);
	fsmax := (fs << 4) - 1;
	bs := 1 << p.backfc;
	bsr := bs << 5;
	bsmin := -(bs << 4);
	bsmax := (bs << 4) - 1;
	sa := p.slices;
	n := 0;
	mbr = mps;
	ybase = 0;
	cbase = 0;
	for (i := 0; i < len sa; i++) {
		ipred := 0;
		rback = 0;
		rforw = 0;
		dback = 0;
		dforw = 0;
		rbackp = 0;
		rforwp = 0;
		dbackp = 0;
		dforwp = 0;
		rback2 = 0;
		rforw2 = 0;
		dback2 = 0;
		dforw2 = 0;
		ydb = 0;
		ydf = 0;
		cdb = 0;
		cdf = 0;
		ba := sa[i].blocks;
		for (j := 0; j < len ba; j++) {
			mb := ba[j];
			while (n < mb.addr) {
				interpmb();
				nextmb();
				ipred = 0;
				n++;
			}
			if (mb.flags & Mpegio->MB_I) {
				invQ_intra_block(mb.rls, mb.qscale, ipred, B);
				ipred = 1;
				rback = 0;
				rforw = 0;
				dback = 0;
				dforw = 0;
				rbackp = 0;
				rforwp = 0;
				dbackp = 0;
				dforwp = 0;
				rback2 = 0;
				rforw2 = 0;
				dback2 = 0;
				dforw2 = 0;
				ydb = 0;
				ydf = 0;
				cdb = 0;
				cdf = 0;
			} else {
				if (mb.flags & Mpegio->MB_MF) {
					if (fs == 1 || mb.mhfc == 0)
						md = mb.mhfc;
					else if ((c = mb.mhfc) < 0)
						md = (c + 1) * fs - mb.mhfr - 1;
					else
						md = (c - 1) * fs + mb.mhfr + 1;
					md += rforwp;
					if (md > fsmax)
						rforw = md - fsr;
					else if (md < fsmin)
						rforw = md + fsr;
					else
						rforw = md;
					rforwp = rforw;
					if (fs == 1 || mb.mvfc == 0)
						md = mb.mvfc;
					else if ((c = mb.mvfc) < 0)
						md = (c + 1) * fs - mb.mvfr - 1;
					else
						md = (c - 1) * fs + mb.mvfr + 1;
					md += dforwp;
					if (md > fsmax)
						dforw = md - fsr;
					else if (md < fsmin)
						dforw = md + fsr;
					else
						dforw = md;
					dforwp = dforw;
					if (p.flags & Mpegio->FPFV) {
						rforw2 = rforw;
						dforw2 = dforw;
						rforw <<= 1;
						dforw <<= 1;
						ydf = rforw2 + dforw2 * width;
						cdf = (rforw2 >> 1) + (dforw2 >> 1) * w2;
					} else {
						if (rforw < 0)
							rforw2 = (rforw + 1) >> 1;
						else
							rforw2 = rforw >> 1;
						if (dforw < 0)
							dforw2 = (dforw + 1) >> 1;
						else
							dforw2 = dforw >> 1;
						ydf = (rforw >> 1) + (dforw >> 1) * width;
						cdf = (rforw2 >> 1) + (dforw2 >> 1) * w2;
					}
				}
				if (mb.flags & Mpegio->MB_MB) {
					if (bs == 1 || mb.mhbc == 0)
						md = mb.mhbc;
					else if ((c = mb.mhbc) < 0)
						md = (c + 1) * bs - mb.mhbr - 1;
					else
						md = (c - 1) * bs + mb.mhbr + 1;
					md += rbackp;
					if (md > bsmax)
						rback = md - bsr;
					else if (md < bsmin)
						rback = md + bsr;
					else
						rback = md;
					rbackp = rback;
					if (bs == 1 || mb.mvbc == 0)
						md = mb.mvbc;
					else if ((c = mb.mvbc) < 0)
						md = (c + 1) * bs - mb.mvbr - 1;
					else
						md = (c - 1) * bs + mb.mvbr + 1;
					md += dbackp;
					if (md > bsmax)
						dback = md - bsr;
					else if (md < bsmin)
						dback = md + bsr;
					else
						dback = md;
					dbackp = dback;
					if (p.flags & Mpegio->FPBV) {
						rback2 = rback;
						dback2 = dback;
						rback <<= 1;
						dback <<= 1;
						ydb = rback2 + dback2 * width;
						cdb = (rback2 >> 1) + (dback2 >> 1) * w2;
					} else {
						if (rback < 0)
							rback2 = (rback + 1) >> 1;
						else
							rback2 = rback >> 1;
						if (dback < 0)
							dback2 = (dback + 1) >> 1;
						else
							dback2 = dback >> 1;
						ydb = (rback >> 1) + (dback >> 1) * width;
						cdb = (rback2 >> 1) + (dback2 >> 1) * w2;
					}
				}
				vflags = mb.flags;
				if (mb.rls != nil) {
					invQ_nintra_block(mb.rls, mb.qscale);
					deltambinterp();
				} else
					interpmb();
				ipred = 0;
			}
			nextmb();
			n++;
		}
	}
	while (n < mpi) {
		interpmb();
		nextmb();
		n++;
	}
	return B;
}

raisex(nil: string)
{
	raise "decode error";
}
