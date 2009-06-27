#define	UMULL(Rs,Rm,Rhi,Rlo,S)	WORD	$((14<<28)|(4<<21)|(S<<20)|(Rhi<<16)|(Rlo<<12)|(Rs<<8)|(9<<4)|Rm)
#define UMLAL(Rs,Rm,Rhi,Rlo,S)	WORD	$((14<<28)|(5<<21)|(S<<20)|(Rhi<<16)|(Rlo<<12)|(Rs<<8)|(9<<4)|Rm)
#define	MUL(Rs,Rm,Rd,S)	WORD	$((14<<28)|(0<<21)|(S<<20)|(Rd<<16)|(Rs<<8)|(9<<4)|Rm)
arg=0

/* replaced use of R10 by R11 because the former can be the data segment base register */

TEXT	_mulv(SB), $0
	MOVW	4(FP), R9	/* l0 */
	MOVW	8(FP), R11	/* h0 */
	MOVW	12(FP), R4	/* l1 */
	MOVW	16(FP), R5	/* h1 */
	UMULL(4, 9, 7, 6, 0)
	MUL(11, 4, 8, 0)
	ADD	R8, R7
	MUL(9, 5, 8, 0)
	ADD	R8, R7
	MOVW	R6, 0(R(arg))
	MOVW	R7, 4(R(arg))
	RET

/* multiply, add, and right-shift, yielding a 32-bit result, while
   using 64-bit accuracy for the multiply -- for fast fixed-point math */
TEXT	_mularsv(SB), $0
	MOVW	4(FP), R11	/* m1 */
	MOVW	8(FP),	R8	/* a */
	MOVW	12(FP), R4	/* rs */
	MOVW	$0, R9
	UMLAL(0, 11, 9, 8, 0)
	MOVW	R8>>R4, R8
	RSB	$32, R4, R4
	ORR	R9<<R4, R8, R0
	RET

