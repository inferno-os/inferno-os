/*
 * system- and machine-specific declarations for emu:
 * floating-point save and restore, signal handling primitive, and
 * implementation of the current-process variable `up'.
 *
 * Windows AMD64 version.
 * On x86_64, FP context is handled per-thread by the OS.
 * FPsave/FPrestore are no-ops (implemented in asm-amd64-win.asm).
 */

typedef	struct	FPU	FPU;
struct FPU
{
	uchar	env[512];	/* FXSAVE area (512 bytes for x86_64) */
};

extern	void		sleep(int);

/* Set up private thread space */
extern	__declspec(thread) Proc*	up;
#define Sleep	NTsleep

typedef jmp_buf osjmpbuf;
#define	ossetjmp(buf)	setjmp(buf)
