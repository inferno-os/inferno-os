#include <asm-ppc/reg.h>

	.file	"asm-power.S"
	.section	".text"
	.align 2
	.globl	FPsave
	.type	FPsave, @function
FPsave:
	.set	_framesize,0
	mffs	f0
	stfd	f0,0(r3)
	blr
	.size	FPsave,.-FPsave

	.align 2
	.globl	FPrestore
FPrestore:
	lfd		f0,0(r3)
	mtfsf 	0xff,f0
	blr
	.size	FPrestore, .-FPrestore

	.align 2
	.globl	_tas
_tas:
	sync
	mr	r4,r3
	addi    r5,0,0x1
1:
	lwarx	r3,0,r4
	cmpwi   r3,0x0
	bne-    2f
	stwcx.	r5,0,r4
	bne-    1b		/* Lost reservation, try again */
2:
	sync
	blr
	.size	_tas,.-_tas

/*
 * void executeonnewstack(void *tos, void (*tramp)(void *arg), void *arg)
 */
	.align	2
	.globl	executeonnewstack:
executeonnewstack:
	mr	r1,r3	/* change stacks */
	stwu 1,-16(r1)	/* save lr to aid the traceback */
	li	r0,0
	stw r0,20(r1)
	mr	r3,r5
	mtctr r4
	bctrl		/* tramp(arg) */
	br	.	/* failed */
	.size executeonnewstack,.-executeonnewstack

/*
 * void unlockandexit(int *key)
 *
 * NB: the return status may be garbaged if the stack is reused
 *	between the unlock and the system call, but this should
 *	not matter since no task is waiting for the result
 */
	.align	2
	.globl	unlockandexit
unlockandexit:
	li	r0,0x0
	stw	r0,0(r3)	/* unlock */
	li	r0,1	/* sys exit; 234 is exit group */
	li	r3,0	/* exit status */
	sc
	br	.	/* not reached */
	.size	unlockandexit,.-unlockandexit
