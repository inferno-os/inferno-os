/*
 * stubs when no floating-point hardware
 */

TEXT	kfpinit(SB), $0
	RETURN

TEXT	getfpscr(SB), $8
	MOVW	$0, R3
	RETURN

TEXT	fpsave(SB), $0
	RETURN

TEXT	fprestore(SB), $0
	RETURN

TEXT	clrfptrap(SB), $0
	RETURN

TEXT	fpinit(SB), $0
	RETURN

TEXT	fpoff(SB), $0
	RETURN

TEXT	FPsave(SB), 1, $0
	RETURN

TEXT	FPrestore(SB), 1, $0
	RETURN
