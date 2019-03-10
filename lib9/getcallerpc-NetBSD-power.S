#include <machine/asm.h>

ENTRY_NOPROFILE(getcallerpc)
	mflr	%r3
	blr
	END(getcallerpc)
