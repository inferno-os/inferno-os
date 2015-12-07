	.file	"arm-tas-v7.S"
#ifndef ARMv7
#define	DMB	mcr     p15, 0, r0, c7, c10, 5
#else
#define	DMB	dmb
#endif
.align 2
.global	_tas
.type	_tas, %function
_tas:
	@ args = 0, pretend = 0, frame = 0
	@ frame_needed = 0, uses_anonymous_args = 0
	@ link register save eliminated.
	@ lr needed for prologue
	DMB
	mov	r1, r0
	mov	r2, #0xaa
tas1:
	ldrex	r0, [r1]
	cmp	r0, #0
	bne	lockbusy
	strex	r3, r2, [r1]
	cmp	r3, #0
	bne	tas1
	DMB
	bx	lr
lockbusy:
	clrex
	bx	lr
	.size	_tas, .-_tas
