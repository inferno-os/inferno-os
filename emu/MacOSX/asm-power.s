/*
 * File: asm-power.s
 *
 * Copyright (c) 2003, Corpus Callosum Corporation.  All rights reserved.
 */

#include <architecture/ppc/asm_help.h>

.text

LEAF(_FPsave)
	mffs	f0
	stfd	f0,0(r3)
	blr
END(_FPsave)

LEAF(_FPrestore)
	lfd		f0,0(r3)
	mtfsf 	0xff,f0
	blr
END(_FPrestore)

LEAF(__tas)
	sync
	mr	r4,r3
	addi    r5,0,0x1
1:
	lwarx	r3,0,r4
	cmpwi   r3,0x0
	bne-    2f
	stwcx.	r5,0,r4
	bne-    1b		/* Lost reservation, try again */
2:
	sync
	blr
END(__tas)
