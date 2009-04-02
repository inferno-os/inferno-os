#include <sys/types.h>
#include <sys/syscall.h>

#include "dat.h"

#define	SYS_cacheflush	__ARM_NR_cacheflush

int
segflush(void *a, ulong n)
{
	if(n)
		syscall(SYS_cacheflush, a, (char*)a+n-1, 1);
	return 0;
}
