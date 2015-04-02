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
	int n, c;
	Rune rc;

	op = p;
	ep = p + nc;
	while(c = *r++) {
		n = 1;
		if(c >= Runeself)
			n = runelen(c);
		if(p + n >= ep)
			break;
		rc = c;
		if(c < Runeself)
			*p++ = c;
		else
			p += runetochar(p, &rc);
	}
	*p = '\0';
	return op;
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
		*r++ = rc;	/* we'll ignore surrogate pairs */
	}
	*r = '\0';
	return or;
}

int
runescmp(Rune16 *s1, Rune16 *s2)
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

	while (*ws)
		n += runelen(*ws++);
	return n+1;
}
