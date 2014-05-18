
#define	FN(x)	.type x,@function; .global x; x

FN(getfcr):
	mffs	%f0
	cvtfl	%r3,%f0
	blr

FN(getfsr):
	mffs	%f0
	cvtfl	%r3,%f0
	blr

FN(setfsr):
	mtfsf	0xff, %f0
	blr

FN(setfcr):
	mtfsf	0xff, %f0
	blr
