	.file	"asm-Linux-386.S"
	.text

/*
 * umult(ulong m1, ulong m2, ulong *hi)
 */

	.type	umult,@function
	.global	umult
umult:
	pushl	%ebp
	movl	%esp, %ebp
	pushl	%ebx

	movl	8(%ebp), %eax
	movl	12(%ebp), %ebx
	mull	%ebx
	movl	16(%ebp), %ebx
	movl	%edx, (%ebx)

	popl	%ebx
	popl	%ebp
	ret

	.type	FPsave,@function
	.global	FPsave
FPsave:
	pushl	%ebp
	movl	%esp, %ebp
	movl	8(%ebp), %eax
	fstenv	(%eax)
	popl	%ebp
	ret

	.type	FPrestore,@function
	.global	FPrestore
FPrestore:
	pushl	%ebp
	movl	%esp, %ebp
	movl	8(%ebp), %eax
	fldenv	(%eax)
	popl	%ebp
	ret

	.type	_tas,@function
	.globl	_tas
_tas:
	movl	$1, %eax
	movl	4(%esp), %ecx
	xchgl	%eax, 0(%ecx)
	ret
