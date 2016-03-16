/* for VFP */
#define VMRS(fp, cpu) WORD $(0xeef00a10 | (fp)<<16 | (cpu)<<12) /* FP → arm */
#define VMSR(cpu, fp) WORD $(0xeee00a10 | (fp)<<16 | (cpu)<<12) /* arm → FP */

#define Fpscr 1

	TEXT	tramp(SB), 1, $0
	MOVW	fn+4(FP), R1		/* func to exec */
	MOVW	arg+8(FP), R2		/* argument */
	SUB	$8, R0			/* new stack */
	MOVW	R0, SP
	MOVW	R2, R0
	BL	(R1)

	MOVW	$0, R0
	BL	_exits(SB)
	RET

	TEXT	vstack(SB), 1, $0
	MOVW	ustack(SB), SP
	BL		exectramp(SB)
	RET

	TEXT	FPsave(SB), 1, $0
	VMRS(Fpscr, 1)
	MOVW	R1, 0(R0)
	RET

	TEXT	FPrestore(SB), 1, $0
	MOVW	(R0), R0
	VMSR(0, Fpscr)
	RET
