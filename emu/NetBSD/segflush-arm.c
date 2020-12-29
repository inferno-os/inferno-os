#include <sys/types.h>
#include <machine/sysarch.h>

#include "dat.h"


int
segflush(void *a, ulong n)
{
	struct arm_sync_icache_args args;

	args.addr = (uintptr_t)a;
	args.len = (size_t)n;
	sysarch(ARM_SYNC_ICACHE, (void *)&args);
	return 0;
}
