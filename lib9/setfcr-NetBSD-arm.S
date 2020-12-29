#include <machine/asm.h>

#define	ENT
#define	RET	bx lr

#ifdef USEVFP
	.fpu	vfp
#define	VMSR(f,r)	vmsr	f,r
#define	VMRS(r,f)	vmrs	r,f
#else
	.fpu	softvfp
#define	VMSR(f,r)
#define	VMRS(r,f)
#endif

ENTRY_NP(setfcr)
	ENT
	VMSR(fpscr, r0)
	RET
	END(setfcr)

ENTRY_NP(getfcr)
	ENT
	VMRS(r0, fpscr)
	RET
	END(getfcr)

ENTRY_NP(getfsr)
	ENT
	VMRS(r0, fpscr)
	RET
	END(getfsr)

ENTRY_NP(setfsr)
	ENT
	VMSR(fpscr, r0)
	RET
	END(setfsr)
