#include	"l.h"
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/times.h>
#undef getwd
#include <unistd.h>	/* For sysconf() and _SC_CLK_TCK */

/*
 * fake malloc
 */
void*
malloc(size_t n)
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
calloc(size_t m, size_t n)
{
	void *p;

	n *= m;
	p = malloc(n);
	memset(p, 0, n);
	return p;
}

void*
realloc(void *p, size_t n)
{
	fprint(2, "realloc called\n", p, n);
	abort();
	return 0;
}

void*
mysbrk(ulong size)
{
	return (void*)sbrk(size);
}

double
cputime(void)
{

	struct tms tmbuf;
	double	ret_val;

	/*
	 * times() only fails if &tmbuf is invalid.
	 */
	(void)times(&tmbuf);
	/*
	 * Return the total time (in system clock ticks)
	 * spent in user code and system
	 * calls by both the calling process and its children.
	 */
	ret_val = (double)(tmbuf.tms_utime + tmbuf.tms_stime +
			tmbuf.tms_cutime + tmbuf.tms_cstime);
	/*
	 * Convert to seconds.
	 */
	ret_val *= sysconf(_SC_CLK_TCK);
	return ret_val;
	
}

int
fileexists(char *name)
{
	struct stat sb;

	return stat(name, &sb) >= 0;
}
