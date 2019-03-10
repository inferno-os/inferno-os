#include <machine/asm.h>

#define	ENT	subl $16, %esp
#define	RET	addl $16, %esp; ret

NENTRY(setfcr)
	ENT
	xorb	$0x3f, %al
	movl	%eax, (%esp)
	fwait
	fldcw	(%esp)
	RET
	END(setfcr)

NENTRY(getfcr)
	ENT
	fwait
	fstcw	(%esp)
	movw	(%esp), %ax
	andl	$0xffff, %eax
	xorb	$0x3f, %al
	RET
	END(getfcr)

NENTRY(getfsr)
	ENT
	fwait
	fstsw	(%esp)
	movw	(%esp), %ax
	andl	$0xffff, %eax
	RET
	END(getfsr)

NENTRY(setfsr)
	fclex
	ret
	END(setfsr)
