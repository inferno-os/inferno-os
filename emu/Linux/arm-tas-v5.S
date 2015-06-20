
	.file	"arm-tas-v5.S"
/*
 * ulong _tas(ulong*);
 */
	.align	2
	.global	_tas
	.type	_tas, %function
_tas:
	@ args = 0, pretend = 0, frame = 0
	@ frame_needed = 0, uses_anonymous_args = 0
	@ link register save eliminated.
	@ lr needed for prologue
	mov	r3, #1
	mov	r1, r0
	swp	r0, r3, [r1]
	bx	lr
	.size	_tas, .-_tas
