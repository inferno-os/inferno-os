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
	uchar	env[28];
};

/*
 * Later versions of Linux seemed to need large stack for gethostbyname()
 * so we had this at 128k, which is excessive.  More recently, we've
 * reduced it again after testing stack usage by gethostbyname.
 */
#define KSTACK (16 * 1024)

static __inline Proc *getup(void) {
	Proc *p;
	__asm__(	"move	%0, $29\n\t"
			: "=r" (p)
	);
	return *(Proc **)((unsigned long)p & ~(KSTACK - 1));
};

#define	up	(getup())

typedef sigjmp_buf osjmpbuf;
#define	ossetjmp(buf)	sigsetjmp(buf, 1)

