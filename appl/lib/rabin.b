implement Rabin;

include "sys.m";
	sys: Sys;
include "bufio.m";
	bufio: Bufio;
	Iobuf, EOF, ERROR: import bufio;
include "rabin.m";

sprint: import sys;

init(b: Bufio)
{
	sys = load Sys Sys->PATH;
	bufio = b;
}

modpower(base, n, mod: int): int
{
	power := 1;
	for(i := 0; i < n; i++)
		power = (power * base) % mod;
	return power;
}

Rcfg.mk(prime, width, mod: int): (ref Rcfg, string)
{
	rcfg := ref Rcfg(prime, width, mod, array[256] of int);
	power := modpower(prime, width, mod);
	for(i := 0; i < 256; i++)
		rcfg.tab[i] = (i * power) % mod;
	return (rcfg, nil);
}


open(rcfg: ref Rcfg, b: ref Iobuf, min, max: int): (ref Rfile, string)
{
	if(min > max)
		return (nil, sprint("bad min/max"));
	if(min < rcfg.width)
		return (nil, "min < width");
	r := ref Rfile(b, rcfg, min, max, array[max+rcfg.width] of byte, 0, 0, big 0);

	(prime, width, mod) := (r.rcfg.prime, r.rcfg.width, r.rcfg.mod);
	while(r.n < width) {
		ch := r.b.getb();
		if(ch == ERROR)
			return (nil, sprint("reading: %r"));
		if(ch == EOF)
			break;
		r.buf[r.n] = byte ch;
		r.state = (prime*r.state + ch) % mod;
		r.n++;
	}
	return (r, nil);
}

Rfile.read(r: self ref Rfile): (array of byte, big, string)
{
	(prime, width, mod) := (r.rcfg.prime, r.rcfg.width, r.rcfg.mod);
	for(;;) {
		ch := r.b.getb();
		if(ch == ERROR)
			return (nil, big 0, sprint("reading: %r"));
		if(ch == EOF) {
			d := r.buf[:r.n];
			off := r.off;
			r.n = 0;
			r.off += big len d;
			return (d, off, nil);
		}
		r.buf[r.n] = byte ch;
		r.state = (mod+prime*r.state + ch - r.rcfg.tab[int r.buf[r.n-width]]) % mod;
		r.n++;
		if(r.n-width >= r.max || (r.n-width >= r.min && r.state == mod-1)) {
			d := array[r.n-width] of byte;
			d[:] = r.buf[:len d];
			off := r.off;
			r.buf[:] = r.buf[r.n-width:r.n];
			r.n = width;
			r.off += big len d;
			return (d, off, nil);
		}
	}
}
