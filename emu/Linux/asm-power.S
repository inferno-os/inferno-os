	.align	2
	.global	FPsave
FPsave:
	stfd	%f14,0*8(%r3)
	stfd	%f15,1*8(%r3)
	stfd	%f16,2*8(%r3)
	stfd	%f17,3*8(%r3)
	stfd	%f18,4*8(%r3)
	stfd	%f19,5*8(%r3)
	stfd	%f20,6*8(%r3)
	stfd	%f21,7*8(%r3)
	stfd	%f22,8*8(%r3)
	stfd	%f23,9*8(%r3)
	stfd	%f24,10*8(%r3)
	stfd	%f25,11*8(%r3)
	stfd	%f26,12*8(%r3)
	stfd	%f27,13*8(%r3)
	stfd	%f28,14*8(%r3)
	stfd	%f29,15*8(%r3)
	stfd	%f30,16*8(%r3)
	stfd	%f31,17*8(%r3)
	blr

	.align	2
	.global	FPrestore
FPrestore:
	lfd		%f14,0*8(%r3)
	lfd		%f15,1*8(%r3)
	lfd		%f16,2*8(%r3)
	lfd		%f17,3*8(%r3)
	lfd		%f18,4*8(%r3)
	lfd		%f19,5*8(%r3)
	lfd		%f20,6*8(%r3)
	lfd		%f21,7*8(%r3)
	lfd		%f22,8*8(%r3)
	lfd		%f23,9*8(%r3)
	lfd		%f24,10*8(%r3)
	lfd		%f25,11*8(%r3)
	lfd		%f26,12*8(%r3)
	lfd		%f27,13*8(%r3)
	lfd		%f28,14*8(%r3)
	lfd		%f29,15*8(%r3)
	lfd		%f30,16*8(%r3)
	lfd		%f31,17*8(%r3)
	blr

	.align	2
	.global	_tas
_tas:
	sync
	mr		%r4, %r3
	addi		%r5,0,0x1	
1:
	lwarx	%r3, 0, %r4
	cmpwi	%r3, 0
	bne-	2f
	stwcx.	%r5, 0, %r4
	bne-	1b
2:
	sync
	blr

/*
 * void
 * executeonnewstack(void *tos, void (*tramp)(void *arg), void *arg)
 */
	.align	2
	.global	executeonnewstack
executeonnewstack:
	mr		%r1,%r3	/* change stacks */
	stwu 	%lr,-16(%r1)	/* save lr to aid the traceback */
	li		%r0,0
	stw 	%r0,20(%r1)
	mr		%r3,%r5
	mtctr 	%r4
	bctrl	/* tramp(arg) */
	br

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
	li	%r0,0x0
	stw	%r0,0(%r3)	/* unlock */
	li	%r0,1		/* sys exit; 234 is exit group */
	li	%r3,0		/* exit status */
	sc
	br
