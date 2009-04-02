#include <sys/types.h>
#include <sys/syscall.h>

#include "dat.h"


/*
 * from geoff collyer's port
 * invalidate instruction cache and write back data cache from a to a+n-1,
 * at least.
 */
int
segflush(void *a, ulong n)
{
    ulong *p;

    // cache blocks are often eight words (32 bytes) long, sometimes 16 bytes.
    // need to determine it dynamically?
    for (p = (ulong *)((ulong)a & ~3UL); (char *)p < (char *)a + n; p++)
        __asm__("dcbst	0,%0\n\t"	// not dcbf, which writes back, then invalidates
            "icbi	0,%0\n\t"
            : // no output
            : "ar" (p)
            );
     __asm__("sync\n\t"
            : // no output
            :
            );
   __asm__("isync\n\t"
            : // no output
            :
            );
	return 0;
}
