	.section	.bss
	.align	4
.L4_.bss:
	.align	4
Solaris_Asm_IntP: / Offset 0
	.type	Solaris_Asm_IntP,@object
	.size	Solaris_Asm_IntP,4
	.set	.,.+4
Solaris_Asm_VoidP: / Offset 4
	.type	Solaris_Asm_VoidP,@object
	.size	Solaris_Asm_VoidP,4
	.set	.,.+4
	.section	.text
	.align	4
.L1_.text:

/====================
/ FPsave
/--------------------
	.align	4
	.align	4
	.globl	FPsave
FPsave:
	pushl	%ebp
	movl	%esp,%ebp
	movl	8(%ebp),%eax
	movl	%eax,Solaris_Asm_VoidP
	fstenv	(%eax)
	leave	
	ret	
	.align	4
	.type	FPsave,@function
	.size	FPsave,.-FPsave

/====================
/ FPrestore
/--------------------
	.align	4
	.globl	FPrestore
FPrestore:
	pushl	%ebp
	movl	%esp,%ebp
	movl	8(%ebp),%eax
	movl	%eax,Solaris_Asm_VoidP
	fldenv	(%eax)
	leave	
	ret	
	.align	4
	.type	FPrestore,@function
	.size	FPrestore,.-FPrestore


/====================
/ getcallerpc
/--------------------
	.align	4
	.globl	getcallerpc
getcallerpc:
	movl	4(%ebp),%eax
	ret	
	.align	4
	.type	getcallerpc,@function
	.size	getcallerpc,.-getcallerpc

/ test-and-set
	.align	4
	.globl	_tas
_tas:
	movl	$1, %eax
	movl	4(%esp), %ecx
	xchgl	%eax, 0(%ecx)
	ret
