#include <machine/asm.h>

ENTRY_NOPROFILE(getfcr)
	mffs	%f0
	stfd	%f0,-16(%r1)
	lwz	%r3,-12(%r1)
	blr
	END(getfcr)

ENTRY_NOPROFILE(getfsr)
	mffs	%f0
	stfd	%f0,-16(%r1)
	lwz	%r3,-12(%r1)
	blr
	END(getfsr)

ENTRY_NOPROFILE(setfsr)
	sync
	stw	%r3,-12(%r1)
	lfd	%f0,-16(%r1)
	mtfsf	0xff, %f0
	isync
	blr
	END(setfsr)

ENTRY_NOPROFILE(setfcr)
	sync
	stw	%r3,-12(%r1)
	lfd	%f0,-16(%r1)
	mtfsf	0xff, %f0
	isync
	blr
	END(setfcr)
