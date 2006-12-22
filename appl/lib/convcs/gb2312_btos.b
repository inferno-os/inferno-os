implement Btos;

include "sys.m";
include "convcs.m";

GBMAX : con 8795;

GBDATA : con "/lib/convcs/gb2312";

MAXINT : con 16r7fffffff;
BADCHAR : con 16rFFFD;

gbmap := "";

init(nil : string): string
{
	sys := load Sys Sys->PATH;
	fd := sys->open(GBDATA, Sys->OREAD);
	if (fd == nil)
		return sys->sprint("%s: %r", GBDATA);

	buf := array[GBMAX * Sys->UTFmax] of byte;
	nread := 0;
	for (;nread < len buf;) {
		n := sys->read(fd, buf[nread:], Sys->ATOMICIO);
		if (n <= 0)
			break;
		nread += n;
	}
	gbmap = string buf[:nread];
	if (len gbmap != GBMAX) {
		gbmap = nil;
		return sys->sprint("%s: corrupt data", GBDATA);
	}
	return nil;
}

btos(nil : Convcs->State, b : array of byte, n : int) : (Convcs->State, string, int)
{
	nbytes := 0;
	str := "";

	if (n == -1)
		n = MAXINT;

	font := -1;
	for (i := 0; i < len b && len str < n; i++) {
		c := int b[i];
		ch := Sys->UTFerror;
		if (font == -1) {
			# idle state
			if (c >= 16rA1) {
				font = c;
				continue;
			}
			ch = c;
		} else {
			# seen a font spec
			if (c >= 16rA1) {
				ix := (font - 16rA0)*100 + (c-16rA0);
				ch = gbmap[ix];
			}
			font = -1;
		}
		str[len str] = ch;
		nbytes = i + 1;
	}
	return (nil, str, nbytes);
}

