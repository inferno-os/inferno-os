/* This code is a little awkward.  If somebody who understands Solaris
   better would tell me an idiomatic way to invoke equivalent
   behavior, I'd be grateful.    ehg@bell-labs.com  */

/*
 * accrued exception bits in the fsr
 */
#define FPAINEX		(1<<5)
#define FPAOVFL		(1<<8)
#define	FPAUNFL		(1<<7)
#define	FPAZDIV		(1<<6)
#define	FPAINVAL	(1<<9)

/*
 * exception enable bits in the fsr
 */
#define	FPINEX		(1<<23)
#define	FPOVFL		(1<<26)
#define	FPUNFL		(1<<25)
#define	FPZDIV		(1<<24)
#define	FPINVAL		(1<<27)

/*
 * rounding
 */
#define	FPRMASK		(3<<30)
#define	FPRNR		(0<<30)
#define	FPRNINF		(3<<30)
#define	FPRPINF		(2<<30)
#define	FPRZ		(1<<30)

/*
 * precision
 */
#define	FPPDBL		0

#define	FPFCR		(FPRMASK|FPINEX|FPOVFL|FPUNFL|FPZDIV|FPINVAL)
#define	FPFSR		(FPAINEX|FPAOVFL|FPAUNFL|FPAZDIV|FPAINVAL)

static ulong
getfcr(void)
{
	ulong v;

	asm("	st	%fsr, [%fp-8]");
	return v;
}

static void
setfcr(ulong v)
{
	ulong vv;

	vv = (getfcr() & ~FPFCR) | (v & FPFCR);
	asm("	ld	[%fp-4], %fsr");
}

static ulong
getfsr(void)
{
	ulong v;

	asm("	st	%fsr, [%fp-8]");
	return v;
}

static void
setfsr(ulong v)
{
	ulong vv;

	vv = (getfsr() & ~FPFSR) | (v & FPFSR);
	asm("	ld	[%fp-4], %fsr");
}

