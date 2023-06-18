#include <sparc/asm.h>

!!! int segflush(void *p, ulong len)
ENTRY_NOPROFILE(segflush)
	save	%sp, -CCFSZ, %sp

	!! mprotect(p, len, PROT_READ | PROT_WRITE | PROT_EXEC)
	mov	%i0, %o0
	mov	%i1, %o1
	call	mprotect
	 mov	7, %o2

	! The flush instruction works on 8-byte chunks.  We truncate
	! the pointer and increase the count to make sure we flush the
	! right range.
	!
	! SPARC requires 5 instructions after flush to let the caches
	! settle.  The loop code supplies the delay instructions.
	bclr	7, %i0			! clear low 3 bits of p
	inc	7, %i1			! len += 7
1:
	flush	%i0			! synchronize cache
	dec	8, %i1			! len -= 8
	cmp	%i1, 0			! if len > 0, repeat
	bg	1b
	 inc	8, %i0			! p += 8 in delay slot

	clr	%i0			! return 0
	ret
	 restore
	END(segflush)
