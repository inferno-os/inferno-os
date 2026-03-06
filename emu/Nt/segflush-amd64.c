/*
 * Cache flush for x86_64 Windows
 *
 * x86_64 has hardware cache coherency, so no explicit flush needed.
 * This is a no-op, same as Linux.
 */

#include "dat.h"

int
segflush(void *a, ulong n)
{
	USED(a);
	USED(n);
	return 0;
}
