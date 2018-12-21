#include <machine/asm.h>

NENTRY(getcallerpc)
	movl	4(%esp), %eax
	movl	-4(%eax), %eax
	ret
	END(getcallerpc)
