#include <sparc/asm.h>

ENTRY_NOPROFILE(getcallerpc)
	retl
	 mov	%i7, %o0
	END(getcallerpc)
