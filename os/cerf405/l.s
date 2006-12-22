#include	"mem.h"

#define	MB	(1024*1024)

/*
 * common ppc special purpose registers
 */
#define DSISR	18
#define SRR0	26	/* Saved Registers (exception) */
#define SRR1	27
#define SPRG0	272	/* Supervisor Private Registers */
#define SPRG1	273
#define SPRG2	274
#define SPRG3	275
#define TBRU	269	/* Time base Upper/Lower (Reading) */
#define TBRL	268
#define TBWU	285	/* Time base Upper/Lower (Writing) */
#define TBWL	284
#define PVR	287	/* Processor Version */

/*
 * 4xx-specific special purpose registers of interest here
 */
#define ICCR	1019	/* instruction cache control */
#define DCCR	1018	/* data cache control */
#define DBCR0	1010	/* debug control register 0 */
#define DCWR	964	/* data cache write-through */
#define PID	945	/* TLB process ID */
#define CCR0	947	/* core configuration register 0 */
#define SLER	955	/* storage little-endian */
#define SU0R	956	/* storage user-defined 0 */
#define SRR2	990
#define SRR3	991
/* SPRGn up to 7, if needed, on the 400 series */
#define DEAR	961	/* data error address */
#define ESR	980	/* exception syndrome */
#define EVPR	982	/* exception vector prefix */
#define PIT	987	/* interval timer */
#define SGR	953	/* storage guarded */
#define TCR	986	/* timer control */
#define TSR	984	/* timer status */
#define ZPR	944	/* zone protection */

/*
 * 4xx-specific(?) device control registers
 */
#define OCM0_DSCNTL	0x1B	/* OCM data-side control register */

/* use of SPRG registers in save/restore */
#define	SAVER0	SPRG0
#define	SAVER1	SPRG1
#define	SAVELR	SPRG2
#define	SAVEXX	SPRG3

/* special instruction definitions */
#define	BDNZ	BC	16,0,
#define	BDNE	BC	0,2,
#define	TLBIA	WORD	$((31<<26)|(370<<1))
#define	TLBSYNC	WORD	$((31<<26)|(566<<1))
#define	MFTB(tbr,d)	WORD	$((31<<26)|((d)<<21)|((tbr&0x1f)<<16)|(((tbr>>5)&0x1f)<<11)|(371<<1))

/* 603/603e specific: load tlb entries */
#define	TLBLD(x)	WORD	$((31<<26)|(978<<1)|((x&0x1F)<<11))
#define	TLBLI(x)	WORD	$((31<<26)|(1010<<1)|((x&0x1F)<<11))

/* 400 models; perhaps others */
#define	ICCCI(a,b)	WORD	$((31<<26)|((a)<<16)|((b)<<11)|(966<<1))
#define	DCCCI(a,b)	WORD	$((31<<26)|((a)<<16)|((b)<<11)|(454<<1))
/* these follow the source -> dest ordering */
#define	DCREAD(s,t)	WORD	$((31<<26)|((t)<<21)|((s)<<11)|(486<<1))
#define	DCRF(n)	((((n)>>5)&0x1F)|(((n)&0x1F)<<5))
#define	MTDCR(s,n)	WORD	$((31<<26)|((s)<<21)|(DCRF(n)<<11)|(451<<1))
#define	MFDCR(n,t)	WORD	$((31<<26)|((t)<<21)|(DCRF(n)<<11)|(323<<1))
#define	TLBRELO(a,t)	WORD	$((31<<26)|((t)<<21)|((a)<<16)|(1<<11)|(946<<1))
#define	TLBREHI(a,t)	WORD	$((31<<26)|((t)<<21)|((a)<<16)|(0<<11)|(946<<1))
#define	TLBWELO(s,a)	WORD	$((31<<26)|((s)<<21)|((a)<<16)|(1<<11)|(978<<1))
#define	TLBWEHI(s,a)	WORD	$((31<<26)|((s)<<21)|((a)<<16)|(0<<11)|(978<<1))
#define	TLBSX(a,b,t)	WORD	$((31<<26)|((t)<<21)|((a)<<16)|((b)<<11)|(914<<1))
#define	TLBSXCC(a,b,t)	WORD	$((31<<26)|((t)<<21)|((a)<<16)|((b)<<11)|(914<<1)|1)
#define	WRTMSR_EE(s)	WORD	$((31<<26)|((s)<<21)|(131<<1))
#define	WRTMSR_EEI(e)	WORD	$((31<<26)|((e)<<16)|(163<<1))

/* on some models mtmsr doesn't synchronise enough (eg, 603e) */
#define	MSRSYNC	SYNC; ISYNC

/* on the 400 series, the prefetcher madly fetches across RFI, sys call, and others; use BR 0(PC) to stop */
#define	RFI	WORD $((19<<26)|(50<<1)); BR 0(PC)
#define	RFCI	WORD	$((19<<26)|(51<<1)); BR 0(PC)

#define	UREGSPACE	(UREGSIZE+8)

/* could define STEP to set an LED to mark progress */
#define	STEP(x)

/*
 * Boot first processor
 */
	TEXT start(SB), $-4

	MOVW	MSR, R3
	RLWNM	$0, R3, $~MSR_EE, R3
	OR	$MSR_ME, R3
	ISYNC
	MOVW	R3, MSR	/* turn off interrupts but enable traps */
	MSRSYNC
	MOVW	$0, R0	/* except during trap handling, R0 is zero from now on */
	MOVW	R0, CR

	MOVW	$setSB-KZERO(SB), R2	/* SB until mmu on */

/*
 * reset the caches and disable them until mmu on
 */
	MOVW	R0, SPR(ICCR)
	ICCCI(0, 2)	/* the errata reveals that EA is used; we'll use SB */
	ISYNC

	MOVW	$((CACHEWAYSIZE/CACHELINESZ)-1), R3
	MOVW	R3, CTR
	MOVW	R0, R3
dcinv:
	DCCCI(0,3)
	ADD	$32, R3
	BDNZ	dcinv

	/* cache is copy-back, disabled; no user-defined 0; big endian throughout */
	MOVW	R0, SPR(DCWR)
	MOVW	R0, SPR(DCCR)
	MOVW	R0, SPR(SU0R)
	MOVW	R0, SPR(SLER)
	ISYNC

	/* guard everything above 0x20000000 */
	MOVW	$~(0xF000<<16), R3
	MOVW	R3, SPR(SGR)
	ISYNC

	/* set access to LED */
	MOVW	$PHYSGPIO, R4
	MOVW	$(1<<31), R6
	MOVW	$(0xC000<<16), R5
	MOVW	4(R4), R3
	OR	R6, R3
	MOVW	R3, 4(R4)	/* tcr set */
	MOVW	0x18(R4), R3
	ANDN	R6, R3
	MOVW	R3, 0x18(R4)	/* odr reset */
	MOVW	8(R4), R3
	ANDN	R5, R3
	MOVW	R3, 8(R4)	/* osrh uses or */
	MOVW	0x10(R4), R3
	ANDN	R5, R3
	MOVW	R3, 0x10(R4)	/* tsr uses tcr */

	MOVW	$(1<<31), R4	/* reset MAL */
	MTDCR(0x180, 4)

/*
	MOVW	$'H', R3
	BL	uartputc(SB)
	MOVW	$'\n', R3
	BL	uartputc(SB)
*/
	
/*
 * set other system configuration values
 */
	MOVW	R0, SPR(PIT)
	MOVW	$~0, R3
	MOVW	R3, SPR(TSR)

STEP(1)

	BL	kernelmmu(SB)
	/* now running with correct addresses, mmu on */

	MOVW	$setSB(SB), R2

	/* enable caches for kernel 128mb in real mode; data is copy-back */
	MOVW	R0, SPR(DCWR)
	MOVW	$(1<<31), R3
	MOVW	R3, SPR(DCCR)
	MOVW	R3, SPR(ICCR)

/*
	BL	ledoff(SB)

	MOVW	$0x800, R8
	MOVW	R8, LR
	BL	(LR)
	BR	0(PC)
*/

STEP(2)
	/* no kfpinit on 4xx */

	MOVW	$mach0(SB), R(MACH)
	ADD	$(MACHSIZE-8), R(MACH), R1
	SUB	$4, R(MACH), R3
	ADD	$4, R1, R4
clrmach:
	MOVWU	R0, 4(R3)
	CMP	R3, R4
	BNE	clrmach

	MOVW	R0, R(USER)
	MOVW	R0, 0(R(MACH))

	MOVW	$edata(SB), R3
	MOVW	$end(SB), R4
	ADD	$4, R4
	SUB	$4, R3
clrbss:
	MOVWU	R0, 4(R3)
	CMP	R3, R4
	BNE	clrbss

STEP(3)
	BL	main(SB)
	BR	0(PC)

TEXT	kernelmmu(SB), $-4
	TLBIA
	ISYNC
	SYNC

	/* make following TLB entries shared, TID=PID=0 */
	MOVW	R0, SPR(PID)

	/* all zones are supervisor, access controlled by TLB */
	MOVW	R0, SPR(ZPR)

	/* map various things 1:1 */
	MOVW	$tlbtab-KZERO(SB), R4
	MOVW	$tlbtabe-KZERO(SB), R5
	SUB	R4, R5
	MOVW	$(2*4), R6
	DIVW	R6, R5
	SUB	$4, R4
	MOVW	R5, CTR
	MOVW	R0, R3
ltlb:
	MOVWU	4(R4), R5	/* TLBHI */
	TLBWEHI(5,3)
	MOVWU	4(R4), R5	/* TLBLO */
	TLBWELO(5,3)
	ADD	$1, R3
	BDNZ	ltlb

	MOVW	LR, R3
	OR	$KZERO, R3
	MOVW	R3, SPR(SRR0)
	MOVW	MSR, R4
	OR	$(MSR_IR|MSR_DR), R4
	MOVW	R4, SPR(SRR1)

	RFI	/* resume in kernel mode in caller */

TEXT	ledoff(SB), $0
	MOVW	$PHYSGPIO, R4
	MOVW	0(R4), R3
	RLWNM	$0, R3, $~(1<<31), R3	/* LED off */
	MOVW	R3, 0(R4)
	RETURN

TEXT	splhi(SB), $0
	MOVW	MSR, R3
	RLWNM	$0, R3, $~MSR_EE, R4
	SYNC
	MOVW	R4, MSR
	MSRSYNC
	MOVW	LR, R31
	MOVW	R31, 4(R(MACH))	/* save PC in m->splpc */
	RETURN

TEXT	splx(SB), $0
	MOVW	MSR, R4
	RLWMI	$0, R3, $MSR_EE, R4
	RLWNMCC	$0, R3, $MSR_EE, R5
	BNE	splx0
	MOVW	LR, R31
	MOVW	R31, 4(R(MACH))	/* save PC in m->splpc */
splx0:
	SYNC
	MOVW	R4, MSR
	MSRSYNC
	RETURN

TEXT	splxpc(SB), $0
	MOVW	MSR, R4
	RLWMI	$0, R3, $MSR_EE, R4
	RLWNMCC	$0, R3, $MSR_EE, R5
	SYNC
	MOVW	R4, MSR
	MSRSYNC
	RETURN

TEXT	spllo(SB), $0
	MFTB(TBRL, 3)
	MOVW	R3, spltbl(SB)
	MOVW	MSR, R3
	OR	$MSR_EE, R3, R4
	SYNC
	MOVW	R4, MSR
	MSRSYNC
	RETURN

TEXT	spldone(SB), $0
	RETURN

TEXT	islo(SB), $0
	MOVW	MSR, R3
	RLWNM	$0, R3, $MSR_EE, R3
	RETURN

TEXT	setlabel(SB), $-4
	MOVW	LR, R31
	MOVW	R1, 0(R3)
	MOVW	R31, 4(R3)
	MOVW	$0, R3
	RETURN

TEXT	gotolabel(SB), $-4
	MOVW	4(R3), R31
	MOVW	R31, LR
	MOVW	0(R3), R1
	MOVW	$1, R3
	RETURN

TEXT	tlbwelo(SB), $-4
	MOVW	v+4(FP), R5
	SYNC
	TLBWELO(5, 3)
	ISYNC
	SYNC
	RETURN

TEXT	tlbwehi(SB), $-4
	MOVW	v+4(FP), R5
	SYNC
	TLBWEHI(5, 3)
	ISYNC
	SYNC
	RETURN

TEXT	tlbrehi(SB), $-4
	TLBREHI(3, 3)
	RETURN

TEXT	tlbrelo(SB), $-4
	TLBRELO(3, 3)
	RETURN

TEXT	tlbsxcc(SB), $-4
	TLBSXCC(0, 3, 3)
	BEQ	tlbsxcc0
	MOVW	$-1, R3	/* not found */
tlbsxcc0:
	RETURN

/*
 * enter with stack set and mapped.
 * on return, SB (R2) has been set, and R3 has the Ureg*,
 * the MMU has been re-enabled, kernel text and PC are in KSEG,
 * R(MACH) has been set, and R0 contains 0.
 *
 * this can be simplified in the Inferno regime
 */
TEXT	saveureg(SB), $-4
/*
 * save state
 */
	MOVMW	R2, 48(R1)	/* r2:r31 */
	MOVW	$setSB(SB), R2
	MOVW	SPR(SAVER1), R4
	MOVW	R4, 44(R1)
	MOVW	SPR(SAVER0), R5
	MOVW	R5, 40(R1)
	MOVW	CTR, R6
	MOVW	R6, 36(R1)
	MOVW	XER, R4
	MOVW	R4, 32(R1)
	MOVW	CR, R5
	MOVW	R5, 28(R1)
	MOVW	SPR(SAVELR), R6	/* LR */
	MOVW	R6, 24(R1)
	/* pad at 20(R1) */
	/* old PC(16) and status(12) saved earlier */
	MOVW	SPR(SAVEXX), R0
	MOVW	R0, 8(R1)	/* cause/vector */
	ADD	$8, R1, R3	/* Ureg* */
	STWCCC	R3, (R1)	/* break any pending reservations */
	MOVW	$0, R0	/* compiler/linker expect R0 to be zero */

	MOVW	MSR, R5
	OR	$(MSR_IR|MSR_DR), R5	/* enable MMU */
	MOVW	R5, SPR(SRR1)
	MOVW	LR, R31
	OR	$KZERO, R31	/* return PC in KSEG0 */
	MOVW	R31, SPR(SRR0)
	SYNC
	ISYNC
	RFI	/* returns to trap handler */

TEXT	icflush(SB), $-4	/* icflush(virtaddr, count) */
	MOVW	n+4(FP), R4
	CMP	R4, R0
	BLE	icf1
	RLWNM	$0, R3, $~(CACHELINESZ-1), R5
	SUB	R5, R3
	ADD	R3, R4
	ADD		$(CACHELINESZ-1), R4
	SRAW	$CACHELINELOG, R4
	MOVW	R4, CTR
icf0:	ICBI	(R5)
	ADD	$CACHELINESZ, R5
	BDNZ	icf0
icf1:
	ISYNC
	RETURN

/*
 * flush to store and invalidate globally
 */
TEXT	dcflush(SB), $-4	/* dcflush(virtaddr, count) */
	SYNC
	MOVW	n+4(FP), R4
	RLWNM	$0, R3, $~(CACHELINESZ-1), R5
	CMP	R4, $0
	BLE	dcf1
	SUB	R5, R3
	ADD	R3, R4
	ADD		$(CACHELINESZ-1), R4
	SRAW	$CACHELINELOG, R4
	MOVW	R4, CTR
dcf0:	DCBF	(R5)
	ADD	$CACHELINESZ, R5
	BDNZ	dcf0
	SYNC
dcf1:
	ISYNC
	MOVW	R5, R3	/* check its operation */
	RETURN

/*
 * invalidate without flush, globally
 */
TEXT	dcinval(SB), $-4	/* dcinval(virtaddr, count) */
	SYNC
	MOVW	n+4(FP), R4
	RLWNM	$0, R3, $~(CACHELINESZ-1), R5
	CMP	R4, $0
	BLE	dci1
	SUB	R5, R3
	ADD	R3, R4
	ADD		$(CACHELINESZ-1), R4
	SRAW	$CACHELINELOG, R4
	MOVW	R4, CTR
dci0:	DCBI	(R5)
	ADD	$CACHELINESZ, R5
	BDNZ	dci0
	SYNC
	ISYNC
dci1:
	RETURN

TEXT	dccci(SB), $-4
	SYNC
	DCCCI(0, 3)
	ISYNC
	RETURN

TEXT	_tas(SB), $0
	SYNC
	MOVW	R3, R4
	MOVW	$0xdeaddead,R5
tas1:
	DCBF	(R4)	/* fix for 603x bug */
	LWAR	(R4), R3
	CMP	R3, $0
	BNE	tas0
	STWCCC	R5, (R4)
	BNE	tas1
tas0:
	SYNC
	ISYNC
	RETURN

TEXT	gettbl(SB), $0
	MFTB(TBRL, 3)
	RETURN

TEXT	gettbu(SB), $0
	MFTB(TBRU, 3)
	RETURN

TEXT	getpvr(SB), $0
	MOVW	SPR(PVR), R3
	RETURN

TEXT	getcallerpc(SB), $-4
	MOVW	0(R1), R3
	RETURN

TEXT getdear(SB), $0
	MOVW	SPR(DEAR), R3
	RETURN

TEXT getdsisr(SB), $0
	MOVW	SPR(DSISR), R3
	RETURN

TEXT	getmsr(SB), $0
	MOVW	MSR, R3
	RETURN

TEXT	putmsr(SB), $0
	SYNC
	MOVW	R3, MSR
	MSRSYNC
	RETURN

TEXT	putevpr(SB), $0
	MOVW	R3, SPR(EVPR)
	RETURN

TEXT	getesr(SB), $0
	MOVW	SPR(ESR), R3
	RETURN

TEXT	putesr(SB), $0
	MOVW	R3, SPR(ESR)
	RETURN

TEXT	getpit(SB), $0
	MOVW	SPR(PIT), R3
	RETURN

TEXT	putpit(SB), $0
	MOVW	R3, SPR(PIT)
	RETURN

TEXT	gettsr(SB), $0
	MOVW	SPR(TSR), R3
	RETURN

TEXT	puttsr(SB), $0
	MOVW	R3, SPR(TSR)
	RETURN

TEXT	puttcr(SB), $0
	MOVW	R3, SPR(TCR)
	RETURN

TEXT	eieio(SB), $0
	EIEIO
	RETURN

TEXT	gotopc(SB), $0
	MOVW	R3, CTR
	MOVW	LR, R31	/* for trace back */
	BR	(CTR)

TEXT getccr0(SB), $-4
	MOVW	SPR(CCR0), R3
	RETURN

TEXT dcread(SB), $-4
	MOVW	4(FP), R4
	MOVW	SPR(CCR0), R5
	RLWNM	$0, R5, $~0xFF, R5
	OR	R4, R5
	MOVW	R5, SPR(CCR0)
	SYNC
	ISYNC
	DCREAD(3, 3)
	RETURN

TEXT	getdcr(SB), $-4
	MOVW	$_getdcr(SB), R5
	SLW	$3, R3
	ADD	R3, R5
	MOVW	R5, CTR
	BR	(CTR)

TEXT	putdcr(SB), $-4
	MOVW	$_putdcr(SB), R5
	SLW	$3, R3
	ADD	R3, R5
	MOVW	R5, CTR
	MOVW	8(R1), R3
	BR	(CTR)

TEXT	firmware(SB), $0
	MOVW	$(3<<28), R3
	MOVW	R3, SPR(DBCR0)	/* system reset */
	BR	0(PC)

/*
 * byte swapping of arrays of long and short;
 * could possibly be avoided with more changes to drivers
 */
TEXT	swabl(SB), $0
	MOVW	v+4(FP), R4
	MOVW	n+8(FP), R5
	SRAW	$2, R5, R5
	MOVW	R5, CTR
	SUB	$4, R4
	SUB	$4, R3
swabl1:
	ADD	$4, R3
	MOVWU	4(R4), R7
	MOVWBR	R7, (R3)
	BDNZ	swabl1
	RETURN

TEXT	swabs(SB), $0
	MOVW	v+4(FP), R4
	MOVW	n+8(FP), R5
	SRAW	$1, R5, R5
	MOVW	R5, CTR
	SUB	$2, R4
	SUB	$2, R3
swabs1:
	ADD	$2, R3
	MOVHZU	2(R4), R7
	MOVHBR	R7, (R3)
	BDNZ	swabs1
	RETURN

TEXT	legetl(SB), $0
	MOVWBR	(R3), R3
	RETURN

TEXT	lesetl(SB), $0
	MOVW	v+4(FP), R4
	MOVWBR	R4, (R3)
	RETURN

TEXT	legets(SB), $0
	MOVHBR	(R3), R3
	RETURN

TEXT	lesets(SB), $0
	MOVW	v+4(FP), R4
	MOVHBR	R4, (R3)
	RETURN

TEXT	itlbmiss(SB), $-4
	BR	traps

TEXT	dtlbmiss(SB), $-4
	BR	traps

/*
 * traps force memory mapping off.
 * this code goes to much effort to restore it;
 * (a little more effort than needed for the Inferno environment)
 */
TEXT	trapvec(SB), $-4
traps:
	MOVW	LR, R0

pagefault:

/*
 * map data virtually and make space to save
 */
	MOVW	R0, SPR(SAVEXX)	/* vector */
trapcomm:
	MOVW	R1, SPR(SAVER1)
	SYNC
	ISYNC
	MOVW	MSR, R0
	OR	$(MSR_DR|MSR_ME), R0		/* make data space usable */
	SYNC
	MOVW	R0, MSR
	MSRSYNC
	SUB	$UREGSPACE, R1

	MOVW	SPR(SRR0), R0	/* save SRR0/SRR1 now, since DLTB might be missing stack page */
	MOVW	R0, LR
	MOVW	SPR(SRR1), R0
	RLWNM	$0, R0, $~MSR_WE, R0	/* remove wait state */
	MOVW	R0, 12(R1)	/* save status: could take DLTB miss here */
	MOVW	LR, R0
	MOVW	R0, 16(R1)	/* old PC */
	BL	saveureg(SB)
	BL	trap(SB)
	BR	restoreureg

/*
 * critical trap/interrupt
 */
TEXT	trapcvec(SB), $-4
	MOVW	LR, R0
	/* for now we'll just restore the state to the conventions that trap expects, since we don't use critical intrs yet */
	MOVW	R0, SPR(SAVEXX)
	MOVW	SPR(SRR2), R0
	MOVW	R0, SPR(SRR0)
	MOVW	SPR(SRR3), R0
	MOVW	R0, SPR(SRR1)
	BR	trapcomm

TEXT	intrvec(SB), $-4
	MOVW	LR, R0

/*
 * map data virtually and make space to save
 */
	MOVW	R0, SPR(SAVEXX)	/* vector */
	MOVW	R1, SPR(SAVER1)
	SYNC
	ISYNC
	MOVW	MSR, R0
	OR	$MSR_DR, R0		/* make data space usable */
	SYNC
	MOVW	R0, MSR
	MSRSYNC
	SUB	$UREGSPACE, R1

	MFTB(TBRL, 0)
	MOVW	R0, intrtbl(SB)

	MOVW	SPR(SRR0), R0
	MOVW	R0, LR
	MOVW	SPR(SRR1), R0
	RLWNM	$0, R0, $~MSR_WE, R0	/* remove wait state */
	MOVW	R0, 12(R1)
	MOVW	LR, R0
	MOVW	R0, 16(R1)
	BL	saveureg(SB)

	MFTB(TBRL, 5)
	MOVW	R5, isavetbl(SB)

	BL	intr(SB)

/*
 * restore state from Ureg and return from trap/interrupt
 */
restoreureg:
	MOVMW	48(R1), R2	/* r2:r31 */
	/* defer R1 */
	MOVW	40(R1), R0
	MOVW	R0, SPR(SAVER0)
	MOVW	36(R1), R0
	MOVW	R0, CTR
	MOVW	32(R1), R0
	MOVW	R0, XER
	MOVW	28(R1), R0
	MOVW	R0, CR	/* CR */
	MOVW	24(R1), R0
	MOVW	R0, SPR(SAVELR)	/* LR */
	/* pad, skip */
	MOVW	16(R1), R0
	MOVW	R0, SPR(SRR0)	/* old PC */
	MOVW	12(R1), R0
	MOVW	R0, SPR(SRR1)	/* old MSR */
	/* cause, skip */
	MOVW	44(R1), R1	/* old SP */
	MOVW	SPR(SAVELR), R0
	MOVW	R0, LR
	MOVW	SPR(SAVER0), R0
	RFI

TEXT mul64fract(SB), $0
	MOVW	a0+8(FP), R9
	MOVW	a1+4(FP), R10
	MOVW	b0+16(FP), R4
	MOVW	b1+12(FP), R5

	MULLW	R10, R5, R13		/* c2 = lo(a1*b1) */

	MULLW	R10, R4, R12		/* c1 = lo(a1*b0) */
	MULHWU	R10, R4, R7		/* hi(a1*b0) */
	ADD	R7, R13			/* c2 += hi(a1*b0) */

	MULLW	R9, R5, R6		/* lo(a0*b1) */
	MULHWU	R9, R5, R7		/* hi(a0*b1) */
	ADDC	R6, R12			/* c1 += lo(a0*b1) */
	ADDE	R7, R13			/* c2 += hi(a0*b1) + carry */

	MULHWU	R9, R4, R7		/* hi(a0*b0) */
	ADDC	R7, R12			/* c1 += hi(a0*b0) */
	ADDE	R0, R13			/* c2 += carry */

	MOVW	R12, 4(R3)
	MOVW	R13, 0(R3)
	RETURN

GLOBL	mach0+0(SB), $MACHSIZE
GLOBL	spltbl+0(SB), $4
GLOBL	intrtbl+0(SB), $4
GLOBL	isavetbl+0(SB), $4
