#include <sys/types.h>
#include <sys/syscall.h>
#include <sys/mman.h>
#include <unistd.h>

#include "dat.h"

/*
 * The JIT (emu -c1) writes code into ordinary heap memory and calls
 * segflush when it is done.  The 386 needs no cache flush, but current
 * kernels give heap memory no execute permission, so make the pages
 * holding the new code executable.
 */
int
segflush(void *a, ulong n)
{
	ulong pg, s, e;

	pg = getpagesize();
	s = (ulong)a & ~(pg-1);
	e = ((ulong)a + n + pg-1) & ~(pg-1);
	return mprotect((void*)s, e-s, PROT_READ|PROT_WRITE|PROT_EXEC);
}
