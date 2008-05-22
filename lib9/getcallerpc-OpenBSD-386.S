	.file	"getcallerpc-OpenBSD-386.S"

	.type	getcallerpc,@function
	.global	getcallerpc
getcallerpc:
	movl	4(%ebp), %eax
	ret
