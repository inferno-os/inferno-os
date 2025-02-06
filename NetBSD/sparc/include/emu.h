/*
 * system- and machine-specific declarations for emu:
 * floating-point save and restore, signal handling primitive, and
 * implementation of the current-process variable `up'.
 */

/*
 * This structure must agree with FPsave and FPrestore asm routines
 */
typedef struct FPU FPU;
struct FPU
{
	ulong	fsr;
};

#define KSTACK (32 * 1024)

extern	Proc*	getup(void);
#define	up	(getup())

typedef sigjmp_buf osjmpbuf;
#define	ossetjmp(buf)	sigsetjmp(buf, 1)
