	.file	"getcallerpc-Linux-386.S"
	.text
	.type	getcallerpc,@function
	.global	getcallerpc
getcallerpc:
	movl	4(%ebp), %eax
	ret
