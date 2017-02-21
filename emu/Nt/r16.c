#define UNICODE
#define Unknown win_Unknown
#include	<windows.h>
#include	<winbase.h>
#undef Unknown
#undef	Sleep
#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	"r16.h"

enum
{
	Bits10 = 0x03ff,		/* 0011 1111 1111 */

	R16self = 0x10000,

	HSurrogateMin = 0xd800,
	HSurrogateMax = 0xdbff,
	LSurrogateMin = 0xdc00,
	LSurrogateMax = 0xdfff,
};

Rune16*
runes16dup(Rune16 *r)
{
	int n;
	Rune16 *s;

	n = runes16len(r) + 1;
	s = malloc(n * sizeof(Rune16));
	if(s == nil)
		error(Enomem);
	memmove(s, r, n * sizeof(Rune16));
	return s;
}

int
runes16len(Rune16 *r)
{
	int n;

	n = 0;
	while(*r++ != 0)
		n++;
	return n;
}

char*
runes16toutf(char *p, Rune16 *r, int nc)
{
	char *op, *ep;
	int n;
	Rune c, lc;

	op = p;
	ep = p + nc;
	while(c = *r++) {
		if(c > Runemax)
			c = Runeerror;
		if(c >= LSurrogateMin && c <= LSurrogateMax)
			c = Runeerror;
		if(c >= HSurrogateMin && c<= HSurrogateMax){
			lc = *r++;
			if(lc >= LSurrogateMin || lc <= LSurrogateMax)
				c = (c&Bits10)<<10 | (lc&Bits10) + R16self;
			else
				c = Runeerror;
		}
		n = runelen(c);
		if(p + n >= ep)
			break;
		p += runetochar(p, &c);
	}
	*p = '\0';
	return op;
}

int
rune16nlen(Rune16 *r, int nrune)
{
	int nb;
	Rune c;

	nb = 0;
	while(nrune--) {
		c = *r++;
		if(c < R16self)
			nb += runelen(c);
		else {
			c -= R16self;
			nb += runelen(HSurrogateMin | (c>>10));
			nb += runelen(LSurrogateMin | (c&Bits10));
		}
	}
	return nb;
}

Rune16*
utftorunes16(Rune16 *r, char *p, int nc)
{
	Rune16 *or, *er;
	Rune rc;

	or = r;
	er = r + nc;
	while(*p != '\0' && r + 1 < er){
		p += chartorune(&rc, p);
		if(rc < R16self){
			*r++ = rc;
			continue;
		}
		if(rc > Runemax || er-r < 2){
			*r++ = Runeerror;
			continue;
		}
		rc -= R16self;
		*r++ = HSurrogateMin | (rc>>10);
		*r++ = LSurrogateMin | (rc&Bits10);
	}
	*r = '\0';
	return or;
}

int
runes16cmp(Rune16 *s1, Rune16 *s2)
{
	Rune16 r1, r2;

	for(;;) {
		r1 = *s1++;
		r2 = *s2++;
		if(r1 != r2) {
			if(r1 > r2)
				return 1;
			return -1;
		}
		if(r1 == 0)
			return 0;
	}
}

wchar_t *
widen(char *s)
{
	int n;
	wchar_t *ws;

	n = utflen(s) + 1;
	ws = smalloc(n*sizeof(wchar_t));
	utftorunes16(ws, s, n);
	return ws;
}


char *
narrowen(wchar_t *ws)
{
	char *s;
	int n;

	n = widebytes(ws);
	s = smalloc(n);
	runes16toutf(s, ws, n);
	return s;
}


int
widebytes(wchar_t *ws)
{
	int n = 0;
	wchar_t c;

	while (*ws){
		c = *ws++;
		if(c < R16self)
			n += runelen(c);
		else {
			c -= R16self;
			n += runelen(HSurrogateMin | (c>>10));
			n += runelen(LSurrogateMin | (c&Bits10));
		}
	}
	return n+1;
}
