	.file	"asm-FreeBSD-386.S"
#include <sys/syscall.h>

/*
 * executeonnewstack(void *tos, void (*tramp)(void *arg), void *arg)
 */

	.type	 ournewstack,@function
	.global	executeonnewstack
executeonnewstack:
	pushl	%ebp
	movl	%esp, %ebp
	pushl	%esi

	movl	8(%ebp), %esi	/* get tos */
	subl	$4, %esi
	movl	16(%ebp), %eax
	movl	%eax, (%esi)	/* stash arg on new stack */
	subl	$4, %esi
	movl	12(%ebp), %eax
	movl	%eax, (%esi)	/* stash tramp on new stack */
	mov	%esi, %esp	/* swap stacks pronto */
	popl	%eax		/* recover the tramp address */
	call	*%eax		/* and jump to it (ho ho) */

	/* if we return here, tramp didn't do it's job */

	addl	$8, %esp	/* clean up for pose value */

	leal	SYS_exit, %eax
	int	$0x80

/*
 * unlockandexit(int *key)
 *
 * NB: the return status may be rubbish if the stack is reused
 *	between the unlock and the system call, but this should
 *	not matter since no task is waiting for the result
 */

	.type	unlockandexit,@function
	.global	unlockandexit
unlockandexit:
	pushl	%ebp
	movl	%esp, %ebp

	movl	8(%ebp), %esi		/* get the key address */
	pushl	$0			/* exit status 0 */
	movl	$0, %eax		/* unlock the stack allocator */
	movl	%eax, (%esi)
	leal	SYS_exit, %eax		/* call exit */
	int	$0x80

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

	.type	getcallerpc,@function
	.global	getcallerpc
getcallerpc:
	pushl	%ebp
	movl	%esp, %ebp
	movl	4(%ebp), %eax
	popl	%ebp
	ret

	.type	_tas,@function
	.globl	_tas
_tas:
	movl	$1, %eax
	movl	4(%esp), %ecx
	xchgl	%eax, 0(%ecx)
	ret
