implement QuickTime;

include "sys.m";

sys: Sys;

include "quicktime.m";

init()
{
	sys = load Sys Sys->PATH;
}

open(file: string): (ref QD, string)
{
	fd := sys->open(file, sys->OREAD);
	if(fd == nil)
		return (nil, "open failed");

	r := ref QD;
	r.fd = fd;
	r.buf = array[DEFBUF] of byte;

	(hdr, l) := r.atomhdr();
	if(hdr != "mdat")
		return (nil, "not a QuickTime movie file");

	#
	# We are expecting a unified file with .data then .rsrc
	#
	r.skipatom(l);

	return (r, nil);
}

QD.atomhdr(r: self ref QD): (string, int)
{
	b := array[8] of byte;

	if(r.readn(b, 8) != 8)
		return (nil, -1);

for(i := 0; i < 8; i++)
sys->print("%.2ux ", int b[i]);
sys->print(" %s %d\n", string b[4:8], bedword(b, 0));

	return (string b[4:8], bedword(b, 0));
}

QD.skipatom(r: self ref QD, l: int): int
{
	return r.skip(l - AtomHDR);
}

QD.mvhd(q: self ref QD, l: int): string
{
	l -= AtomHDR;
	if(l != MvhdrSIZE)
		return "mvhd atom funny size";

	b := array[l] of byte;
	if(q.readn(b, l) != l)
		return "short read in mvhd";

	mvhdr := ref Mvhdr;

	mvhdr.version = bedword(b, 0);
	mvhdr.create = bedword(b, 4);
	mvhdr.modtime = bedword(b, 8);
	mvhdr.timescale = bedword(b, 12);
	mvhdr.duration = bedword(b, 16);
	mvhdr.rate = bedword(b, 20);
	mvhdr.vol = beword(b, 24);
	mvhdr.r1 = bedword(b, 26);
	mvhdr.r2 = bedword(b, 30);

	mvhdr.matrix = array[9] of int;
	for(i :=0; i<9; i++)
		mvhdr.matrix[i] = bedword(b, 34+i*4);

	mvhdr.r3 = beword(b, 70);
	mvhdr.r4 = bedword(b, 72);
	mvhdr.pvtime = bedword(b, 76);
	mvhdr.posttime = bedword(b, 80);
	mvhdr.seltime = bedword(b, 84);
	mvhdr.seldurat = bedword(b, 88);
	mvhdr.curtime = bedword(b, 92);
	mvhdr.nxttkid = bedword(b, 96);

	q.mvhdr = mvhdr;
	return nil;
}

QD.trak(q: self ref QD, l: int): string
{
	(tk, tkl) := q.atomhdr();
	if(tk != "tkhd")
		return "missing track header atom";

	l -= tkl;
	tkl -= AtomHDR;
	b := array[tkl] of byte;
	if(q.readn(b, tkl) != tkl)
		return "short read in tkhd";

	tkhdr := ref Tkhdr;

	tkhdr.version =	bedword(b, 0);
	tkhdr.creation = bedword(b, 4);
	tkhdr.modtime =	bedword(b, 8);
	tkhdr.trackid =	bedword(b, 12);
	tkhdr.timescale = bedword(b, 16);
	tkhdr.duration = bedword(b, 20);
	tkhdr.timeoff = bedword(b, 24);
	tkhdr.priority = bedword(b, 28);
	tkhdr.layer = beword(b, 32);
	tkhdr.altgrp = beword(b, 34);
	tkhdr.volume = beword(b, 36);

	tkhdr.matrix = array[9] of int;
	for(i := 0; i < 9; i++)
		tkhdr.matrix[i] = bedword(b, 38+i*4);

	tkhdr.width = bedword(b, 74);
	tkhdr.height = bedword(b, 78);

	(md, mdl) := q.atomhdr();
	if(md != "mdia")
		return "missing media atom";

	while(mdl != AtomHDR) {
		(atom, atoml) := q.atomhdr();
sys->print("\t%s %d\n", atom, atoml);
		q.skipatom(atoml);

		mdl -= atoml;
	}

	return nil;
}

QD.readn(r: self ref QD, b: array of byte, l: int): int
{
	if(r.nbyte < l) {
		c := 0;
		if(r.nbyte != 0) {
			b[0:] = r.buf[r.ptr:];
			l -= r.nbyte;
			c += r.nbyte;
			b = b[r.nbyte:];
		}
		bsize := len r.buf;
		while(l != 0) {
			r.nbyte = sys->read(r.fd, r.buf, bsize);
			if(r.nbyte <= 0) {
				r.nbyte = 0;
				return -1;
			}
			n := l;
			if(n > bsize)
				n = bsize;

			r.ptr = 0;
			b[0:] = r.buf[0:n];
			b = b[n:];
			r.nbyte -= n;
			r.ptr += n;
			l -= n;
			c += n;
		}
		return c;
	}
	b[0:] = r.buf[r.ptr:r.ptr+l];
	r.nbyte -= l;
	r.ptr += l;
	return l;
}

QD.skip(r: self ref QD, size: int): int
{
	if(r.nbyte != 0) {
		n := size;
		if(n > r.nbyte)
			n = r.nbyte;
		r.ptr += n;
		r.nbyte -= n;
		size -= n;
		if(size == 0)
			return 0;
	}
	return int sys->seek(r.fd, big size, sys->SEEKRELA);
}

beword(b: array of byte, o: int): int
{
	return 	(int b[o] << 8) | int b[o+1];
}

bedword(b: array of byte, o: int): int
{
	return	(int b[o] << 24) |
		(int b[o+1] << 16) |
		(int b[o+2] << 8) |
		int b[o+3];
}
