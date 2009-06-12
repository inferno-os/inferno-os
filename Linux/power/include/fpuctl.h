/*
 * Linux PPC
 * Mimic Plan9 floating point support
 */

static __inline__ ulong
getfcr(void)
{
	float fpscr;

	__asm__ __volatile__ ("mffs %0" : "=&f" (fpscr):);

	return (ulong)fpscr;
}

static __inline__ ulong
getfsr(void)
{
	float fpscr;

	__asm__ __volatile__ ("mffs %0" : "=&f" (fpscr):);

	return (ulong) fpscr;
}

static __inline__ void
setfsr(ulong fsr)
{
	float t = (float) fsr;

	__asm__ __volatile__("mtfsf 0xff, %0" : : "f" (t) );
}

static __inline__ void
setfcr(ulong fcr)
{
	float t = (float) fcr;

	__asm__ __volatile__("mtfsf 0xff, %0" : : "f" (t) );
}

/* FPSCR */
#define	FPSFX	(1<<31)	/* exception summary (sticky) */
#define	FPSEX	(1<<30)	/* enabled exception summary */
#define	FPSVX	(1<<29)	/* invalid operation exception summary */
#define	FPSOX	(1<<28)	/* overflow exception OX (sticky) */
#define	FPSUX	(1<<27)	/* underflow exception UX (sticky) */
#define	FPSZX	(1<<26)	/* zero divide exception ZX (sticky) */
#define	FPSXX	(1<<25)	/* inexact exception XX (sticky) */
#define	FPSVXSNAN (1<<24)	/* invalid operation exception for SNaN (sticky) */
#define	FPSVXISI	(1<<23)	/* invalid operation exception for ∞-∞ (sticky) */
#define	FPSVXIDI	(1<<22)	/* invalid operation exception for ∞/∞ (sticky) */
#define	FPSVXZDZ (1<<21)	/* invalid operation exception for 0/0 (sticky) */
#define	FPSVXIMZ	(1<<20)	/* invalid operation exception for ∞*0 (sticky) */
#define	FPSVXVC	(1<<19)	/* invalid operation exception for invalid compare (sticky) */
#define	FPSFR	(1<<18)	/* fraction rounded */
#define	FPSFI	(1<<17)	/* fraction inexact */
#define	FPSFPRF	(1<<16)	/* floating point result class */
#define	FPSFPCC	(0xF<<12)	/* <, >, =, unordered */
#define	FPVXCVI	(1<<8)	/* enable exception for invalid integer convert (sticky) */

/* FCR */
#define	FPVE	(1<<7)	/* invalid operation exception enable */
#define	FPOVFL	(1<<6)	/* enable overflow exceptions */
#define	FPUNFL	(1<<5)	/* enable underflow */
#define	FPZDIV	(1<<4)	/* enable zero divide */
#define	FPINEX	(1<<3)	/* enable inexact exceptions */
#define	FPRMASK	(3<<0)	/* rounding mode */
#define	FPRNR	(0<<0)
#define	FPRZ	(1<<0)
#define	FPRPINF	(2<<0)
#define	FPRNINF	(3<<0)
#define	FPPEXT	0
#define	FPPSGL	0
#define	FPPDBL	0
#define	FPPMASK	0
#define	FPINVAL	FPVE
/* FSR */
#define	FPAOVFL	FPSOX
#define	FPAINEX	FPSXX
#define	FPAUNFL	FPSUX
#define	FPAZDIV	FPSZX
#define	FPAINVAL	FPSVX
