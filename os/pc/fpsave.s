TEXT	FPsave(SB), 1, $0	/* save FPU environment without waiting */
	MOVL	fpu+0(FP), AX
	FSTENV	0(AX)
	RET
 
TEXT	FPrestore(SB), 1, $0	/* restore FPU environment without waiting */
	MOVL	fpu+0(FP), AX
	FLDENV	0(AX)
	RET
