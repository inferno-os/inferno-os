
#define	FN(x)	.type x,@function; .global x; x
#define	ENT	subl $16, %esp
#define	RET	addl $16, %esp; ret

	.file	"setfcr-Linux-386.S"
FN(setfcr):
	ENT
	xorb	$0x3f, %al
	movl	%eax, (%esp)
	fwait
	fldcw	(%esp)
	RET

FN(getfcr):
	ENT
	fwait
	fstcw	(%esp)
	movw	(%esp), %ax
	andl	$0xffff, %eax
	xorb	$0x3f, %al
	RET

FN(getfsr):
	ENT
	fwait
	fstsw	(%esp)
	movw	(%esp), %ax
	andl	$0xffff, %eax
	RET

FN(setfsr):
	fclex
	ret
