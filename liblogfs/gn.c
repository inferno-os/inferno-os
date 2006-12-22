#include "lib9.h"
#include "logfs.h"
#include "fcall.h"
#include "local.h"

int
logfsgn(uchar **pp, uchar *mep, char **v)
{
	uchar *p = *pp;
	int l;
	if(p + BIT16SZ > mep)
		return 0;
	l = GBIT16(p); p += BIT16SZ;
	if(p + l > mep)
		return 0;
	*pp = p + l;
	if(l == 0) {
		*v = 0;
		return 1;
	}
	*v = (char *)(p - 1);
	memmove(p - 1, p, l);
	p[l - 1] = 0;
	return 1;
}

