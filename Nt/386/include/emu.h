/*
 * system- and machine-specific declarations for emu:
 * floating-point save and restore, signal handling primitive, and
 * implementation of the current-process variable `up'.
 */

/*
 * This structure must agree with FPsave and FPrestore asm routines
 */
typedef	struct	FPU	FPU;
struct FPU
{
	uchar	env[28];
};

extern	void		sleep(int);

/* Set up private thread space */
extern	__declspec(thread) Proc*	up;
#define Sleep	NTsleep

typedef jmp_buf osjmpbuf;
#define	ossetjmp(buf)	setjmp(buf)

