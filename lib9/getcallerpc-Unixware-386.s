	.align	4
	.globl	getcallerpc
getcallerpc:
	movl	4(%ebp),%eax
	ret	
	.align	4
	.type	getcallerpc,@function
	.size	getcallerpc,.-getcallerpc
