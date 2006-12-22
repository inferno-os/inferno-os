#include	"l.h"

/*
 * fake malloc
 */
void*
malloc(long n)
{
	void *p;

	while(n & 7)
		n++;
	while(nhunk < n)
		gethunk();
	p = hunk;
	nhunk -= n;
	hunk += n;
	return p;
}

void
free(void *p)
{
	USED(p);
}

void*
calloc(long m, long n)
{
	void *p;

	n *= m;
	p = malloc(n);
	memset(p, 0, n);
	return p;
}

void*
realloc(void *p, long n)
{
	fprint(2, "realloc called\n", p, n);
	abort();
	return 0;
}

void*
mysbrk(ulong size)
{
	return sbrk(size);
}
