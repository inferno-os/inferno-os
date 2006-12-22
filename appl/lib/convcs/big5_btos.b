implement Btos;

include "sys.m";
include "convcs.m";

# Big5 consists of 89 fonts of 157 chars each
BIG5MAX : con 13973;
BIG5FONT : con 157;

BIG5DATA : con "/lib/convcs/big5";

MAXINT : con 16r7fffffff;
BADCHAR : con 16rFFFD;

big5map := "";

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
	if (len big5map != BIG5MAX) {
		big5map = nil;
		return sys->sprint("%s: corrupt data", BIG5DATA);
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
		if (font == -1) {
			# idle state
			if(c >= 16rA1){
				font = c;
				continue;
			}
			if(c == 26)
				c = '\n';
			str[len str] = c;
			nbytes = i + 1;
			continue;
		} else {
			# seen a font spec
			f := font;
			font = -1;
			ch := Sys->UTFerror;
			if(c >= 64 && c <= 126)
				c -= 64;
			else if(c >= 161 && c <= 254)
				c = c-161 + 63;
			else
				# bad big5 char
				f = 255;
			if(f <= 254) {
				f -= 161;
				ix := f*BIG5FONT + c;
				if(ix < len big5map)
					ch = big5map[ix];
				if (ch == -1)
					ch = BADCHAR;
			}
			str[len str] = ch;
			nbytes = i + 1;
		}
	}
	return (nil, str, nbytes);
}
