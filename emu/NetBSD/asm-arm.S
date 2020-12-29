#include <machine/asm.h>

/*
 * ulong _tas(ulong*);
 */
#if __ARM_ARCH >= 6

#if __ARM_ARCH >= 7
#define	DMB	dmb
#else
#define	DMB	mcr	p15, 0, r0, c7, c10, 5
#endif

ENTRY(_tas)
	@ args = 0, pretend = 0, frame = 0
	@ frame_needed = 0, uses_anonymous_args = 0
	@ link register save eliminated.
	@ lr needed for prologue
	DMB
	mov	r1, r0
	mov	r2, #0xaa
.Loop:
	ldrex	r0, [r1]
	cmp	r0, #0
	bne	.Lockbusy
	strex	r3, r2, [r1]
	cmp	r3, #0
	bne	.Loop
	DMB
	bx	lr
.Lockbusy:
	clrex
	bx	lr
	END(_tas)

#else	/* __ARM_ARCH <= 5*/

ENTRY(_tas)
	@ args = 0, pretend = 0, frame = 0
	@ frame_needed = 0, uses_anonymous_args = 0
	@ link register save eliminated.
	@ lr needed for prologue
	mov	r3, #1
	mov	r1, r0
	swp	r0, r3, [r1]
	bx	lr
	END(_tas)

#endif	/* __ARM_ARCH <= 5*/


/*
 * void FPsave(void *);
 */
ENTRY(FPsave)
	@ args = 0, pretend = 0, frame = 4
	@ frame_needed = 1, uses_anonymous_args = 0
	mov	ip, sp
	stmfd	sp!, {fp, ip, lr, pc}
	sub	fp, ip, #4
	sub	sp, sp, #4
	str	r0, [fp, #-16]
	ldmea	fp, {fp, sp, pc}
	END(FPsave)

/*
 * void FPrestore(void *);
 */
ENTRY(FPrestore)
	@ args = 0, pretend = 0, frame = 4
	@ frame_needed = 1, uses_anonymous_args = 0
	mov	ip, sp
	stmfd	sp!, {fp, ip, lr, pc}
	sub	fp, ip, #4
	sub	sp, sp, #4
	str	r0, [fp, #-16]
	ldmea	fp, {fp, sp, pc}
	END(FPrestore)
