#include "os.h"
#include <mp.h>

#define iseven(a)	(((a)->p[0] & 1) == 0)

// use extended gcd to find the multiplicative inverse
// res = b**-1 mod m
void
mpinvert(mpint *b, mpint *m, mpint *res)
{
	mpint *dc1, *dc2;	// don't care
	int r;

	dc1 = mpnew(0);
	dc2 = mpnew(0);
	mpextendedgcd(b, m, dc1, res, dc2);
	r = mpcmp(dc1, mpone);
	mpfree(dc1);
	mpfree(dc2);
	if(r != 0)
		sysfatal("mpinvert: no inverse");
	mpmod(res, m, res);
}
