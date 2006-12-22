implement Riff;

include "sys.m";

sys: Sys;

include "riff.m";

init()
{
	sys = load Sys Sys->PATH;
}

open(file: string): (ref RD, string)
{
	fd := sys->open(file, sys->OREAD);
	if(fd == nil)
		return (nil, "open failed");

	r := ref RD;
	r.fd = fd;
	r.buf = array[DEFBUF] of byte;
	r.ptr = 0;
	r.nbyte = 0;

	(hdr, l) := r.gethdr();
	if(hdr != "RIFF")
		return (nil, "not a RIFF file");

	return (r, nil);
}

RD.gethdr(r: self ref RD): (string, int)
{
	b := array[8] of byte;

	if(r.readn(b, 8) != 8)
		return (nil, -1);

	return (string b[0:4], ledword(b, 4));
}

RD.check4(r: self ref RD, code: string): string
{
	b := array[4] of byte;

	if(r.readn(b, 4) != 4)
		return "file i/o error";
	if(string b != code)
		return "bad four code header information";
	return nil;
}

RD.avihdr(r: self ref RD): (ref AVIhdr, string)
{
	(s, l) := r.gethdr();
	if(s == nil || s != "avih")
		return (nil, "missing/malformed avih");

	b := array[AVImainhdr] of byte;
	if(r.readn(b, AVImainhdr) != AVImainhdr)
		return (nil, "short read in avih");

	h := ref AVIhdr;

	h.usecperframe = ledword(b, 0);
	h.bytesec = ledword(b, 4);
	h.flag = ledword(b, 12);
	h.frames = ledword(b, 16);
	h.initframes = ledword(b, 20);
	h.streams = ledword(b, 24);
	h.bufsize = ledword(b, 28);
	h.width = ledword(b, 32);
	h.height = ledword(b, 36);

	return (h, nil);
}

RD.streaminfo(r: self ref RD): (ref AVIstream, string)
{
	(h, l) := r.gethdr();
	if(h != "LIST")
		return (nil, "streaminfo expected LIST");

	err := r.check4("strl");
	if(err != nil)
		return (nil, err);

	(strh, sl) := r.gethdr();
	if(strh != "strh")
		return (nil, "streaminfo expected strh");

	b := array[sl] of byte;
	if(r.readn(b, sl) != sl)
		return (nil, "streaminfo strl short read");

	s := ref AVIstream;

	s.stype = string b[0:4];
	s.handler = string b[4:8];
	s.flags = ledword(b, 8);
	s.priority = ledword(b, 12);
	s.initframes = ledword(b, 16);
	s.scale = ledword(b, 20);
	s.rate = ledword(b, 24);
	s.start = ledword(b, 28);
	s.length = ledword(b, 32);
	s.bufsize = ledword(b, 36);
	s.quality = ledword(b, 40);
	s.samplesz = ledword(b, 44);

	(strf, sf) := r.gethdr();
	if(strf != "strf")
		return (nil, "streaminfo expected strf");

	s.fmt = array[sf] of byte;
	if(r.readn(s.fmt, sf) != sf)
		return (nil, "streaminfo strf short read");

	return (s, nil);
}

RD.readn(r: self ref RD, b: array of byte, l: int): int
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

RD.skip(r: self ref RD, size: int): int
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

AVIstream.fmt2binfo(a: self ref AVIstream): string
{
	if(len a.fmt < Binfosize)
		return "format is wrong size for BITMAPINFO";

	b := ref Bitmapinfo;

	# Pull out the bitmap info
	b.width = ledword(a.fmt, 4);
	b.height = ledword(a.fmt, 8);
	b.planes = leword(a.fmt, 12);
	b.bitcount = leword(a.fmt, 14);
	b.compression = ledword(a.fmt, 16);
	b.sizeimage = ledword(a.fmt, 20);
	b.xpelpermeter = ledword(a.fmt, 24);
	b.ypelpermeter = ledword(a.fmt, 28);
	b.clrused = ledword(a.fmt, 32);
	b.clrimportant = ledword(a.fmt, 36);

	# Parse out the color map
	ncolor := len a.fmt - Binfosize;
	if(ncolor & 3)
		return "wrong size color map";
	ncolor /= 4;

	b.cmap = array[ncolor] of RGB;
	idx := 40;
	for(i := 0; i < ncolor; i++) {
		b.cmap[i].r = int a.fmt[idx+2];
		b.cmap[i].g = int a.fmt[idx+1];
		b.cmap[i].b = int a.fmt[idx+0];
		idx += 4;
	}

	a.fmt = nil;
	a.binfo = b;
	return nil;
}

leword(b: array of byte, o: int): int
{
	return 	(int b[o+1] << 8) | int b[o];
}

ledword(b: array of byte, o: int): int
{
	return	(int b[o+3] << 24) |
		(int b[o+2] << 16) |
		(int b[o+1] << 8) |
		int b[o];
}
