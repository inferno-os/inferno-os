/*
 * system- and machine-specific declarations for emu:
 * floating-point save and restore, signal handling primitive, and
 * implementation of the current-process variable `up'.
 */

extern Proc *getup(void);
#define	up	(getup())

/*
 * This structure must agree with FPsave and FPrestore asm routines
 */

// something is at odds between i386/fpu.h and some of the thread headers
#define fp_control inffp_control
#define fp_control_t inffp_control_t
#define fp_status inffp_status
#define fp_status_t inffp_status_t

#include <architecture/i386/fpu.h>

typedef struct FPU FPU;
struct FPU
{
	fp_state_t	env;
};

#undef fp_control
#undef fp_control_t
#undef fp_status
#undef fp_status_t

typedef sigjmp_buf osjmpbuf;
#define	ossetjmp(buf)	sigsetjmp(buf, 1)
