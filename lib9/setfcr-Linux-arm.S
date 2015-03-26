#define	FN(x)	.type x,%function; .global x; x
#define	ENT
#define	RET	bx lr
#ifdef USEVFP
	.fpu	vfp
#define	VMSR(f,r)	f,r
#define	VMRS(r,f)	r,f
#else
	.fpu	softvfp
#define	VMSR(f,r)
#define	VMRS(r,f)
#endif

	.file	"setfcr-Linux-arm.S"
FN(setfcr):
	ENT
	VMSR(fpscr,r0)
	RET

FN(getfcr):
	ENT
	VMRS(fpscr, r0)
	RET

FN(getfsr):
	ENT
	VMRS(r0, fpscr)
	RET

FN(setfsr):
	ENT
	VMRS(r0, fpscr)
	RET
