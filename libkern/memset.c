#include	<lib9.h>

void*
memset(void *ap, int c, ulong n)
{
	char *p;
	int m = (int)n;

	p = ap;
	while(m > 0) {
		*p++ = c;
		m--;
	}
	return ap;
}
