#include <machine/asm.h>

ENTRY_NOPROFILE(FPsave)
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
	END(FPsave)

ENTRY_NOPROFILE(FPrestore)
	lfd	%f14,0*8(%r3)
	lfd	%f15,1*8(%r3)
	lfd	%f16,2*8(%r3)
	lfd	%f17,3*8(%r3)
	lfd	%f18,4*8(%r3)
	lfd	%f19,5*8(%r3)
	lfd	%f20,6*8(%r3)
	lfd	%f21,7*8(%r3)
	lfd	%f22,8*8(%r3)
	lfd	%f23,9*8(%r3)
	lfd	%f24,10*8(%r3)
	lfd	%f25,11*8(%r3)
	lfd	%f26,12*8(%r3)
	lfd	%f27,13*8(%r3)
	lfd	%f28,14*8(%r3)
	lfd	%f29,15*8(%r3)
	lfd	%f30,16*8(%r3)
	lfd	%f31,17*8(%r3)
	blr
	END(FPrestore)

ENTRY_NOPROFILE(_tas)
	sync
	mr	%r4, %r3
	addi	%r5,0,0x1	
1:
	lwarx	%r3, 0, %r4
	cmpwi	%r3, 0
	bne-	2f
	stwcx.	%r5, 0, %r4
	bne-	1b
2:
	sync
	blr
	END(_tas)
