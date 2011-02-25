/*
 * system- and machine-specific declarations for emu:
 * floating-point save and restore, signal handling primitive, and
 * implementation of the current-process variable `up'.
 */

extern	Proc*	getup(void);
#define	up	(getup())

/*
 * This structure must agree with FPsave and FPrestore asm routines
 */
typedef	struct	FPU	FPU;
struct FPU
{
	uchar	env[28];
};

typedef sigjmp_buf osjmpbuf;
#define	ossetjmp(buf)	sigsetjmp(buf, 1)

