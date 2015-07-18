
#define	FN(x)	.type x,@function; .global x; x

FN(getfcr):
	mffs	%f0
	stfdu	%f0,-16(%r1)
	lw	%r3,-12(%r1)
	blr

FN(getfsr):
	mffs	%f0
	stfdu	%f0,-16(%r1)
	lw	%r3,-12(%r1)
	blr

FN(setfsr):
	sync
	stw	%r3,-12(%r1)
	lfd	%f0,-16(%r1)
	mtfsf	0xff, %f0
	isync
	blr

FN(setfcr):
	sync
	stw	%r3,-12(%r1)
	lfd	%f0,-16(%r1)
	mtfsf	0xff, %f0
	isync
	blr
