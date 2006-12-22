#include	"mem.h"

#define	MB	(1024*1024)

/*
 * options
 */
#undef	MMUTWC		/* we don't map enough memory to need table walk */
#undef	SHOWCYCLE	/* might be needed for BDM debugger to keep control */

/*
 * common ppc special purpose registers
 */
#define DSISR	18
#define DAR	19	/* Data Address Register */
#define DEC	22	/* Decrementer */
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
 * mpc8xx-specific special purpose registers of interest here
 */
#define EIE	80
#define EID	81
#define NRI	82
#define IMMR	638
#define IC_CSR	560
#define IC_ADR	561
#define IC_DAT	562
#define DC_CSR	568
#define DC_ADR	569
#define DC_DAT	570
#define MI_CTR	784
#define MI_AP	786
#define MI_EPN	787
#define MI_TWC	789
#define MI_RPN	790
#define MI_DBCAM	816
#define MI_DBRAM0	817
#define MI_DBRAM1	818
#define MD_CTR	792
#define M_CASID	793
#define MD_AP	794
#define MD_EPN	795
#define M_TWB	796
#define MD_TWC	797
#define MD_RPN	798
#define	M_TW	799
#define	MD_DBCAM	824
#define	MD_DBRAM0	825
#define	MD_DBRAM1	826

/* use of SPRG registers in save/restore */
#define	SAVER0	SPRG0
#define	SAVER1	SPRG1
#define	SAVELR	SPRG2
#define	SAVEXX	SPRG3

/* special instruction definitions */
#define	BDNZ	BC	16,0,
#define	BDNE	BC	0,2,
#define	TLBIA	WORD	$((31<<26)|(370<<1))
#define	MFTB(tbr,d)	WORD	$((31<<26)|((d)<<21)|((tbr&0x1f)<<16)|(((tbr>>5)&0x1f)<<11)|(371<<1))

/* on some models mtmsr doesn't synchronise enough (eg, 603e) */
#define	MSRSYNC	SYNC; ISYNC

#define	UREGSPACE	(UREGSIZE+8)

/* could define STEP to set an LED to mark progress */
#define	STEP(x)

/*
 * Boot first processor
 */
	TEXT start(SB), $-4

	MOVW	MSR, R3
	RLWNM	$0, R3, $~EE, R3
	RLWNM	$0, R3, $~FPE, R3
	OR	$ME, R3
	ISYNC
	MOVW	R3, MSR	/* turn off interrupts but enable traps */
	MSRSYNC
	MOVW	$0, R0	/* except during trap handling, R0 is zero from now on */
	MOVW	R0, CR
	MOVW	$setSB(SB), R2

/*
 * reset the caches and disable them for now
 */
	MOVW	SPR(IC_CSR), R4	/* read and clear */
	MOVW	$(5<<25), R4
	MOVW	R4, SPR(IC_CSR)	/* unlock all */
	ISYNC
	MOVW	$(6<<25), R4
	MOVW	R4, SPR(IC_CSR)	/* invalidate all */
	ISYNC
	MOVW	$(2<<25), R4
	MOVW	R4, SPR(IC_CSR)	/* disable i-cache */
	ISYNC

	SYNC
	MOVW	SPR(DC_CSR), R4	/* read and clear */
	MOVW	$(10<<24), R4
	SYNC
	MOVW	R4, SPR(DC_CSR)	/* unlock all */
	ISYNC
	MOVW	$(12<<24), R4
	SYNC
	MOVW	R4, SPR(DC_CSR)	/* invalidate all */
	ISYNC
	MOVW	$(4<<24), R4
	SYNC
	MOVW	R4, SPR(DC_CSR)	/* disable d-cache */
	ISYNC

#ifdef SHOWCYCLE
	MOVW	$0, R4
#else
	MOVW	$7, R4
#endif
	MOVW	R4, SPR(158)		/* cancel `show cycle' for normal instruction execution */
	ISYNC

/*
 * set other system configuration values
 */
	MOVW	$PHYSIMM, R4
	MOVW	R4, SPR(IMMR)		/* set internal memory base */

STEP(1)

	BL	kernelmmu(SB)

STEP(2)
	/* no kfpinit on 82x */

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

TEXT	kernelmmu(SB), $0
	TLBIA
	ISYNC

	MOVW	$0, R4
	MOVW	R4, SPR(M_CASID)	/* set supervisor space */
	MOVW	$(0<<29), R4		/* allow i-cache when IR=0 */
	MOVW	R4, SPR(MI_CTR)	/* i-mmu control */
	ISYNC
	MOVW	$((1<<29)|(1<<28)), R4	/* cache inhibit when DR=0, write-through */
	SYNC
	MOVW	R4, SPR(MD_CTR)	/* d-mmu control */
	ISYNC
	TLBIA

	/* map various things 1:1 */
	MOVW	$tlbtab-KZERO(SB), R4
	MOVW	$tlbtabe-KZERO(SB), R5
	SUB	R4, R5
	MOVW	$(3*4), R6
	DIVW	R6, R5
	SUB	$4, R4
	MOVW	R5, CTR
ltlb:
	MOVWU	4(R4), R5
	MOVW	R5, SPR(MD_EPN)
	MOVW	R5, SPR(MI_EPN)
	MOVWU	4(R4), R5
	MOVW	R5, SPR(MI_TWC)
	MOVW	R5, SPR(MD_TWC)
	MOVWU	4(R4), R5
	MOVW	R5, SPR(MD_RPN)
	MOVW	R5, SPR(MI_RPN)
	BDNZ	ltlb

	MOVW	$(1<<25), R4
	MOVW	R4, SPR(IC_CSR)	/* enable i-cache */
	ISYNC

	MOVW	$(3<<24), R4
	SYNC
	MOVW	R4, SPR(DC_CSR)	/* clear force write through mode */
	MOVW	$(2<<24), R4
	SYNC
	MOVW	R4, SPR(DC_CSR)	/* enable d-cache */
	ISYNC

	/* enable MMU and set kernel PC to virtual space */
	MOVW	$((0<<29)|(0<<28)), R4	/* cache when DR=0, write back */
	SYNC
	MOVW	R4, SPR(MD_CTR)	/* d-mmu control */
	MOVW	LR, R3
	OR	$KZERO, R3
	MOVW	R3, SPR(SRR0)
	MOVW	MSR, R4
	OR	$(ME|IR|DR), R4	/* had ME|FPE|FE0|FE1 */
	MOVW	R4, SPR(SRR1)
	RFI	/* resume in kernel mode in caller */

TEXT	splhi(SB), $0
	MOVW	MSR, R3
	RLWNM	$0, R3, $~EE, R4
	SYNC
	MOVW	R4, MSR
	MSRSYNC
	MOVW	LR, R31
	MOVW	R31, 4(R(MACH))	/* save PC in m->splpc */
	RETURN

TEXT	splx(SB), $0
	MOVW	MSR, R4
	RLWMI	$0, R3, $EE, R4
	RLWNMCC	$0, R3, $EE, R5
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
	RLWMI	$0, R3, $EE, R4
	RLWNMCC	$0, R3, $EE, R5
	SYNC
	MOVW	R4, MSR
	MSRSYNC
	RETURN

TEXT	spllo(SB), $0
	MFTB(TBRL, 3)
	MOVW	R3, spltbl(SB)
	MOVW	MSR, R3
	OR	$EE, R3, R4
	SYNC
	MOVW	R4, MSR
	MSRSYNC
	RETURN

TEXT	spldone(SB), $0
	RETURN

TEXT	islo(SB), $0
	MOVW	MSR, R3
	RLWNM	$0, R3, $EE, R3
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
	OR	$(IR|DR), R5	/* enable MMU */
	MOVW	R5, SPR(SRR1)
	MOVW	LR, R31
	OR	$KZERO, R31	/* return PC in KSEG0 */
	MOVW	R31, SPR(SRR0)
	SYNC
	ISYNC
	RFI	/* returns to trap handler */

TEXT	icflush(SB), $-4	/* icflush(virtaddr, count) */
	MOVW	n+4(FP), R4
	RLWNM	$0, R3, $~(CACHELINESZ-1), R5
	SUB	R5, R3
	ADD	R3, R4
	ADD		$(CACHELINESZ-1), R4
	SRAW	$CACHELINELOG, R4
	MOVW	R4, CTR
icf0:	ICBI	(R5)
	ADD	$CACHELINESZ, R5
	BDNZ	icf0
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
	ISYNC
dcf1:
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

TEXT	getimmr(SB), $0
	MOVW	SPR(IMMR), R3
	RETURN

TEXT	getdec(SB), $0
	MOVW	SPR(DEC), R3
	RETURN

TEXT	putdec(SB), $0
	MOVW	R3, SPR(DEC)
	RETURN

TEXT	getcallerpc(SB), $-4
	MOVW	0(R1), R3
	RETURN

TEXT getdar(SB), $0
	MOVW	SPR(DAR), R3
	RETURN

TEXT getdsisr(SB), $0
	MOVW	SPR(DSISR), R3
	RETURN

TEXT	getdepn(SB), $0
	MOVW	SPR(MD_EPN), R3
	RETURN

TEXT	getmsr(SB), $0
	MOVW	MSR, R3
	RETURN

TEXT	putmsr(SB), $0
	SYNC
	MOVW	R3, MSR
	MSRSYNC
	RETURN

TEXT	eieio(SB), $0
	EIEIO
	RETURN

TEXT	gotopc(SB), $0
	MOVW	R3, CTR
	MOVW	LR, R31	/* for trace back */
	BR	(CTR)

TEXT	firmware(SB), $0
	MOVW	MSR, R3
	MOVW	$(EE|ME), R4
	ANDN	R4, R3
	OR	$(MSR_IP), R3
	ISYNC
	MOVW	R3, MSR	/* turn off interrupts and machine checks */
	MSRSYNC
	MOVW	$(RI|IR|DR|ME), R4
	ANDN	R4, R3
	MOVW	R3, SPR(SRR1)
	MOVW	$(0xFF00<<16), R4
	MOVW	R4, SPR(IMMR)
	MOVW	$(0x0800<<16), R4
	MOVW	R4, SPR(SRR0)	/* force bad address */
	MOVW	R0, SPR(149)	/* ensure checkstop on machine check */
	MOVW	R4, R1
	MOVW	R4, R2
	EIEIO
	ISYNC
	RFI

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

#ifdef MMUTWC
/*
 * ITLB miss
 *	avoid references that might need the right SB value;
 *	IR and DR are off.
 */
TEXT	itlbmiss(SB), $-4
	MOVW	R1, SPR(M_TW)
	MOVW	SPR(SRR0), R1	/* instruction miss address */
	MOVW	R1, SPR(MD_EPN)
	MOVW	SPR(M_TWB), R1	/* level one pointer */
	MOVW	(R1), R1
	MOVW	R1, SPR(MI_TWC)	/* save level one attributes */
	MOVW	R1, SPR(MD_TWC)	/* save base and attributes */
	MOVW	SPR(MD_TWC), R1	/* level two pointer */
	MOVW	(R1), R1	/* level two entry */
	MOVW	R1, SPR(MI_RPN)	/* write TLB */
	MOVW	SPR(M_TW), R1
	RFI

/*
 * DTLB miss
 *	avoid references that might need the right SB value;
 *	IR and DR are off.
 */
TEXT	dtlbmiss(SB), $-4
	MOVW	R1, SPR(M_TW)
	MOVW	SPR(M_TWB), R1	/* level one pointer */
	MOVW	(R1), R1	/* level one entry */
	MOVW	R1, SPR(MD_TWC)	/* save base and attributes */
	MOVW	SPR(MD_TWC), R1	/* level two pointer */
	MOVW	(R1), R1	/* level two entry */
	MOVW	R1, SPR(MD_RPN)	/* write TLB */
	MOVW	SPR(M_TW), R1
	RFI
#else
TEXT	itlbmiss(SB), $-4
	BR	traps
TEXT	dtlbmiss(SB), $-4
	BR	traps
#endif

/*
 * traps force memory mapping off.
 * this code goes to too much effort (for the Inferno environment) to restore it.
 */
TEXT	trapvec(SB), $-4
traps:
	MOVW	LR, R0

pagefault:

/*
 * map data virtually and make space to save
 */
	MOVW	R0, SPR(SAVEXX)	/* vector */
	MOVW	R1, SPR(SAVER1)
	SYNC
	ISYNC
	MOVW	MSR, R0
	OR	$(DR|ME), R0		/* make data space usable */
	SYNC
	MOVW	R0, MSR
	MSRSYNC
	SUB	$UREGSPACE, R1

	MOVW	SPR(SRR0), R0	/* save SRR0/SRR1 now, since DLTB might be missing stack page */
	MOVW	R0, LR
	MOVW	SPR(SRR1), R0
	MOVW	R0, 12(R1)	/* save status: could take DLTB miss here */
	MOVW	LR, R0
	MOVW	R0, 16(R1)	/* old PC */
	BL	saveureg(SB)
	BL	trap(SB)
	BR	restoreureg

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
	OR	$DR, R0		/* make data space usable */
	SYNC
	MOVW	R0, MSR
	MSRSYNC
	SUB	$UREGSPACE, R1

	MFTB(TBRL, 0)
	MOVW	R0, intrtbl(SB)

	MOVW	SPR(SRR0), R0
	MOVW	R0, LR
	MOVW	SPR(SRR1), R0
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

GLOBL	mach0+0(SB), $MACHSIZE
GLOBL	spltbl+0(SB), $4
GLOBL	intrtbl+0(SB), $4
GLOBL	isavetbl+0(SB), $4
