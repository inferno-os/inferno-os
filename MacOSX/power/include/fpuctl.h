/*
 * MacOSX/Darwin ppc fpu support
 * Mimic Plan9 floating point support
 */

#include <architecture/ppc/fp_regs.h>

static __inline__ ulong
getfcr(void)
{
	ppc_fp_scr_t fpscr = get_fp_scr();
	return ((ulong *)&fpscr)[1];
}

ulong
getfsr(void)
{
	ppc_fp_scr_t fpscr = get_fp_scr();
	return ((ulong *)&fpscr)[1];
}

void
setfsr(ulong fsr)
{
	ppc_fp_scr_t fpscr;
	// fpscr = get_fp_scr();
	(((ulong *)&fpscr)[1]) = fsr;
	set_fp_scr(fpscr);
}

void
setfcr(ulong fcr)
{
	ppc_fp_scr_t fpscr;
	// fpscr = get_fp_scr();
	(((ulong *)&fpscr)[1]) = fcr;
	set_fp_scr(fpscr);
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
