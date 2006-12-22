implement Stob;

include "sys.m";
include "convcs.m";


# Big5 consists of 89 fonts of 157 chars each
BIG5MAX : con 13973;
BIG5FONT : con 157;
NFONTS : con 89;

BIG5DATA : con "/lib/convcs/big5";

big5map := "";
r2fontchar : array of byte;

# NOTE: could be more memory friendly during init()
# by building the r2fontchar mapping table on the fly
# instead of building it from the complete big5map string

init(nil : string) : string
{
	sys := load Sys Sys->PATH;
	fd := sys->open(BIG5DATA, Sys->OREAD);
	if (fd == nil)
		return sys->sprint("%s: %r", BIG5DATA);

	buf := array[BIG5MAX * Sys->UTFmax] of byte;
	nread := 0;
	for (;nread < len buf;) {
		n := sys->read(fd, buf[nread:], Sys->ATOMICIO);
		if (n <= 0)
			break;
		nread += n;
	}
	big5map = string buf[:nread];
	buf = nil;
	if (len big5map != BIG5MAX) {
		big5map = nil;
		return sys->sprint("%s: corrupt data", BIG5DATA);
	}
	r2fontchar = array [2 * 16r10000] of { * => byte 16rff};
	for (i := 0; i < len big5map; i++) {
		f := i / BIG5FONT;
		c := i % BIG5FONT;
		ix := 2*big5map[i];
		r2fontchar[ix] = byte f;
		r2fontchar[ix+1] = byte c;
	}
	return nil;
}

stob(nil : Convcs->State, str : string) : (Convcs->State, array of byte)
{
	buf := array [1024] of byte;
	nb := 0;
	cbuf := array [2] of byte;
	nc := 0;
	for (i := 0; i < len str; i++) {
		c := str[i];
		nc = 0;
		if (c < 128) {
#			if (c == '\n')		# not sure abou this
#				c = 26;
			cbuf[nc++] = byte c;
		} else {
			ix := 2*c;
			f := int r2fontchar[ix];
			c = int r2fontchar[ix+1];
			if (f >= NFONTS) {
				# no mapping of unicode character to big5
				cbuf[nc++] = byte '?';
			} else {
				f += 16rA1;
				cbuf[nc++] = byte f;
				if (c <= 62)
					c += 64;
				else
					c += 16rA1 - 63;
				cbuf[nc++] = byte c;
			}
		}
		if (nc + nb > len buf)
			buf = ((array [len buf * 2] of byte)[:] = buf);
		buf[nb:] = cbuf[:nc];
		nb += nc;
	}
	if (nb == 0)
		return (nil, nil);
	r := array [nb] of byte;
	r[:] = buf[:nb];
	return (nil, r);
}
