#include	<lib9.h>

/* for testing only */
void*
memcpy(void *a1, void *a2, ulong n)
{
	return memmove(a1, a2, n);
}

void*
memmove(void *a1, void *a2, ulong n)
{
	int m = (int)n;
	uchar *s, *d;
	
	d = a1;
	s = a2;
	if(d > s){
		s += m;
		d += m;
		while(--m >= 0)
			*--d = *--s;
	}
	else{
		while(--m >= 0)
			*d++ = *s++;
	}
	return a1;
}

/*
void
memset(void *a1, int c, ulong n)
{
	int m = (int)n;
	uchar *d;

	d = a1;
	while(--m >= 0)
		*d++ = c;
}
*/
	
