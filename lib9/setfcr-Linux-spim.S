#include <sys/regdef.h>
#include <sys/asm.h>

#define	FN(x)	.type x,%function; .global x; x
#define	ENT
#define	RET	jr ra

	.file	"setfcr-Linux-spim.S"
FN(setfcr):
	ENT
	mtc1 a0, $31
	RET

FN(getfcr):
	ENT
	mfc1 v0, $31
	RET

FN(getfsr):
	ENT
	mfc1 v0, $31
	RET

FN(setfsr):
	ENT
	mtc1 a0, $31
	RET
