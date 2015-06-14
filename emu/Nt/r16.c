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

#define Bit(i) (7-(i))
/* N 0's preceded by i 1's, T(Bit(2)) is 1100 0000 */
#define T(i) (((1 << (Bit(i)+1))-1) ^ 0xFF)
/* 0000 0000 0000 0111 1111 1111 */
#define	RuneX(i) ((1 << (Bit(i) + ((i)-1)*Bitx))-1)

enum
{
	Bitx	= Bit(1),

	Tx	= T(1),			/* 1000 0000 */
	Rune1 = (1<<(Bit(0)+0*Bitx))-1,	/* 0000 0000 0000 0000 0111 1111 */

	Maskx	= (1<<Bitx)-1,		/* 0011 1111 */
	Testx	= Maskx ^ 0xFF,		/* 1100 0000 */

	SurrogateMin	= 0xD800,
	SurrogateMax	= 0xDFFF,

	Bad	= Runeerror,
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

int
rune16nlen(Rune16 *r, int nrune)
{
	int nb, i;
	Rune c;

	nb = 0;
	while(nrune--) {
		c = *r++;
		if(c <= Rune1){
			nb++;
		} else {
			for(i = 2; i < UTFmax + 1; i++)
				if(c <= RuneX(i) || i == UTFmax){
					nb += i;
					break;
				}
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
		*r++ = rc;	/* we'll ignore surrogate pairs */
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

	while (*ws)
		n += runelen(*ws++);
	return n+1;
}
