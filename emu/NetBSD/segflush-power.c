#include <sys/types.h>
#include <machine/cpu.h>

#include "dat.h"


int
segflush(void *a, ulong n)
{
	__syncicache(a, n);
	return 0;
}
