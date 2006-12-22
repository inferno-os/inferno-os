/*
 * BUG: it's slow
 */
	TEXT	strchr(SB), $0
	MOVBZ	c+7(FP), R4
	SUB	$1, R3
l1:
	MOVBZU	1(R3), R6
	CMP	R6, R4
	BEQ	eq
	CMP	R6, $0
	BNE	l1
nf:
	MOVW	$0, R3
eq:
	RETURN
