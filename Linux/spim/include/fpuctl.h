/* FCR */
#define	FCRBITS	0x00000F83
#define	FPINEX	(1<<7)
#define	FPUNFL	(1<<8)
#define	FPOVFL	(1<<9)
#define	FPZDIV	(1<<10)
#define	FPINVAL	(1<<11)
#define	FPRNR	(0<<0)
#define	FPRZ	(1<<0)
#define	FPRPINF	(2<<0)
#define	FPRNINF	(3<<0)
#define	FPRMASK	(3<<0)
#define	FPPEXT	0
#define	FPPSGL	0
#define	FPPDBL	0
#define	FPPMASK	0
/* FSR */
#define	FSRBITS	0x0003F07C
#define	FPAINEX	(1<<2)
#define	FPAOVFL	(1<<4)
#define	FPAUNFL	(1<<3)
#define	FPAZDIV	(1<<5)
#define	FPAINVAL	(1<<6)

/*
 * Linux mips fpu support
 * Mimic Plan9 floating point support
 */

static void
setfcr(ulong fcr)
{
	__asm__("ctc1	%0,$31\n"
			: :"r" (fcr)
	);
}

static ulong
getfcr(void)
{
	ulong fcr = 0;
	__asm__("cfc1	%0,$31\n"
			: "=r" (fcr)
	);
	fcr &= FCRBITS;
	return fcr; 
}

static ulong
getfsr(void)
{
	ulong fsr = 0;
	__asm__("cfc1	%0,$31\n"
			: "=r" (fsr)
	);
	fsr &= FSRBITS;
	return fsr;
}

static void
setfsr(ulong fsr)
{
	fsr |= getfcr();
	setfcr(getfcr()|fsr);
}
