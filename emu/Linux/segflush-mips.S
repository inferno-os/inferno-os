#include "syscall.h"
#include <sys/asm.h>
#include <sys/regdef.h>
#include <asm/cachectl.h>

/*
 * int segflush(void *p, ulong len)
 */

LEAF(segflush)
	li	a2,BCACHE
	li	v0,SYS_cacheflush
	syscall
	li	v0,0
	j	$31
	END(segflush)
