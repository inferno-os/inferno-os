#include "syscall.h"
#include <sys/asm.h>
#include <sys/regdef.h>
#include <asm/cachectl.h>

/*
 * executeonnewstack(void *tos, void (*tramp)(void *arg), void *arg)
 */

LEAF(executeonnewstack)
	and		a0,a0,~7
	addu		sp,a0,-16
	move	a0,a2
	move	t9,a1
	jalr	t9

	li	v0,SYS_exit
	li	a0,0
	syscall

	END(executeonnewstack)

/*
 * unlockandexit(int *key)
 */

LEAF(unlockandexit)
	lw	a1,0(a0)
	li	v0,SYS_exit
	li	a0,0
	sw	a0,0(a1)
	syscall
	END(unlockandexit)

LEAF(FPsave)
	cfc1	t0, $31
	sw	t0, 0(a0)		/* a0 is argument */
	j	$31
	END(FPsave)

LEAF(FPrestore)
	lw	t0, 0(a0)		/* a0 is argument */
	ctc1	t0, $31
	j	$31
	END(FPrestore)

LEAF(_tas)
	.set 	noreorder
1:
	ll	v0,0(a0)		/* a0 is argument */
	or	t1, v0, 1
	sc	t1,0(a0)
	beq	t1,zero,1b	
	nop
	j	$31			/* lock held */
	nop
	.set 	reorder
	END(_tas)

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
