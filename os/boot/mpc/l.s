#include "mem.h"

/* special instruction definitions */
#define	BDNE	BC	0,2,
#define	BDNZ	BC	16,0,
#define	NOOP	OR	R0,R0,R0

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
 * mpc82x-specific special purpose registers of interest here
 */
#define EIE	80
#define EID	81
#define NRI	82
#define IMMR	638
#define IC_CST	560
#define IC_ADR	561
#define IC_DAT	562
#define DC_CST	568
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

/* as on 603e, apparently mtmsr needs help in some chip revisions */
#define	WAITMSR	SYNC; ISYNC

/* use of SPRG registers in save/restore */
#define	SAVER0	SPRG0
#define	SAVER1	SPRG1
#define	SAVELR	SPRG2
#define	SAVECR	SPRG3

#define	UREGSIZE	((8+32)*4)
#define	UREGSPACE	(UREGSIZE+8)	/* allow for arg to trap, and align */

/*
 * This code is loaded by the ROM loader at location 0x3000,
 * or lives in flash memory at 0x2800100.
 * Move it to high memory so that it can load the kernel at 0x0000.
 */

#define LOADCODEBASE	0x3000	/* when downloaded in S records */
#define FLASHCODEBASE	(FLASHMEM+0x100)	/* when in flash */

	TEXT	start(SB), $-4
	MOVW	MSR, R3
	MOVW	$(EE|IP|RI), R4
	ANDN	R4, R3
	OR	$ME, R3
	SYNC
	MOVW	R3, MSR	/* turn off interrupts but enable traps */
	WAITMSR

/*
 * reset the caches and disable them for now
 */
	MOVW	SPR(IC_CST), R4	/* read and clear */
	MOVW	$(5<<25), R4
	MOVW	R4, SPR(IC_CST)	/* unlock all */
	ISYNC
	MOVW	$(6<<25), R4
	MOVW	R4, SPR(IC_CST)	/* invalidate all */
	ISYNC
	MOVW	$(2<<25), R4
	MOVW	R4, SPR(IC_CST)	/* disable i-cache */
	ISYNC

	SYNC
	MOVW	SPR(DC_CST), R4	/* read and clear */
	MOVW	$(10<<24), R4
	MOVW	R4, SPR(DC_CST)	/* unlock all */
	ISYNC
	MOVW	$(12<<24), R4
	MOVW	R4, SPR(DC_CST)	/* invalidate all */
	ISYNC
	MOVW	$(4<<24), R4
	MOVW	R4, SPR(DC_CST)	/* disable i-cache */
	ISYNC

	MOVW	$7, R4
ANDN R4, R4, R4
	MOVW	R4, SPR(158)		/* cancel `show cycle' for normal instruction execution */

/*
 * set other system configuration values
 */
	MOVW	SPR(IMMR), R5		/* save initial space pointer */
	MOVW	$INTMEM, R4
	MOVW	R4, SPR(IMMR)		/* set internal memory base */
	MOVW	$0xFFFFFF88, R3
	MOVW	R3, 4(R4)	/* disable watchdog in sypcr */
	MOVW	$0x01012440, R3
	MOVW	R3, 0(R4)	/* siumcr */

/*
 * system initialisation (init and map DRAM)
 */
	MOVW	$0, R0
	MOVW	$setSB(SB), R2
	MOVW	$(0xF000<<16), R3
/*MOVW R0, R3*/
	ANDCC	R5, R3	/* initial space is high? */
	BEQ	notrom
	MOVW	$FLASHCODEBASE, R5	/* where $start(SB) actually is now */
	MOVW	$start(SB), R4	/* logical start address */
	SUB	R4, R5, R6	/* text relocation value */
	MOVW	$etext(SB), R7
	SUB	R4, R7
	ADD	R5, R7	/* data address in ROM */
	MOVW	$bdata(SB), R8
	SUB	R8, R2
	ADD	R7, R2	/* relocate SB: SB' = romdata+(SB-bdata) */
	MOVW	$sysinit0(SB), R4
	ADD	R6, R4	/* relocate sysinit0's address */
	MOVW	R4, CTR
	MOVW	$inmem(SB), R4
	ADD	R6, R4
	MOVW	R4, LR	/* and the return address */
	BR	(CTR)	/* call sysinit0 */
	TEXT	inmem(SB), $-4
	MOVW	$FLASHCODEBASE, R3
	BR	cpu0
notrom:
	MOVW	$start(SB), R6
	SUB	R6, R2
	ADD	$LOADCODEBASE, R2
	BL	sysinit0(SB)
	MOVW	$LOADCODEBASE, R3

/*
 * cpu 0
 *	relocate bootstrap to our link addresses for text and data
 *	set new PC
 */
cpu0:
	MOVW	$setSB(SB), R2	/* set correct static base register */
	MOVW	$start(SB), R4
	MOVW	$etext(SB), R5
	SUB	R4, R5
	CMP	R4, R3	/* already there? */
	BNE	copytext
	ADD	R5, R3	/* start of data image */
	BR	copydata

copytext:
	ADD	$3, R5
	SRAW	$2, R5
	MOVW	R5, CTR
	SUB	$4, R4
	SUB	$4, R3
copyt:			/* copy text */
	MOVWU	4(R3), R5
	MOVWU	R5, 4(R4)
	BDNZ	copyt
	ADD	$4, R3

copydata:
	/* copy data */
	MOVW	$bdata(SB), R4
	CMP	R4, R3	/* already there? */
	BEQ	loadkpc
	MOVW	$edata(SB), R5
	SUB	R4, R5
	ADD	$3, R5
	SRAW	$2, R5
	MOVW	R5, CTR
	SUB	$4, R4
	SUB	$4, R3
copyd:
	MOVWU	4(R3), R5
	MOVWU	R5, 4(R4)
	BDNZ	copyd

	/* load correct PC */
loadkpc:
	MOVW	$start1(SB), R3
	MOVW	R3, LR
	BR	(LR)
TEXT start1(SB), $-4
	MOVW	$edata(SB), R3
	MOVW	$end(SB), R4
	SUBCC	R3, R4
	BLE	skipz
	SRAW	$2, R4
	MOVW	R4, CTR
	SUB	$4, R3
	MOVW	$0, R0
zero:
	MOVWU	R0, 4(R3)
	BDNZ	zero
skipz:
	MOVW	$mach0(SB), R1
	MOVW	R1, m(SB)
	ADD	$(MACHSIZE-8), R1
	MOVW	$0, R0
	BL	main(SB)
	BR	0(PC)

TEXT	getmsr(SB), $0
	MOVW	MSR, R3
	RETURN

TEXT	putmsr(SB), $0
	SYNC
	MOVW	R3, MSR
	WAITMSR
	RETURN

TEXT	eieio(SB), $0
	EIEIO
	RETURN

TEXT	idle(SB), $0
	RETURN

TEXT	spllo(SB), $0
	MOVW	MSR, R3
	OR	$EE, R3, R4
	SYNC
	MOVW	R4, MSR
	WAITMSR
	RETURN

TEXT	splhi(SB), $0
	MOVW	MSR, R3
	RLWNM	$0, R3, $~EE, R4
	SYNC
	MOVW	R4, MSR
	WAITMSR
	RETURN

TEXT	splx(SB), $0
	MOVW	MSR, R4
	RLWMI	$0, R3, $EE, R4
	SYNC
	MOVW	R4, MSR
	WAITMSR
	RETURN

TEXT	gettbl(SB), $0
/*	MOVW	SPR(TBRL), R3	*/
	WORD	$0x7c6c42e6	/* mftbl on 8xx series */
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

/*
 * save state in Ureg on kernel stack.
 * enter with R0 giving the PC from the call to `exception' from the vector.
 * on return, SB (R2) has been set, and R3 has the Ureg*
 */
TEXT saveureg(SB), $-4
	SUB	$UREGSPACE, R1
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
	MOVW	SPR(SAVECR), R5	/* CR */
	MOVW	R5, 28(R1)
	MOVW	SPR(SAVELR), R6	/* LR */
	MOVW	R6, 24(R1)
	/* pad at 20(R1) */
	MOVW	SPR(SRR0), R4
	MOVW	R4, 16(R1)	/* old PC */
	MOVW	SPR(SRR1), R5
	MOVW	R5, 12(R1)
	MOVW	R0, 8(R1)	/* cause/vector, encoded in LR from vector */
	ADD	$8, R1, R3	/* Ureg* */
	STWCCC	R3, (R1)	/* break any pending reservations */
	MOVW	$0, R0	/* R0ISZERO */
	BR	(LR)

/*
 * restore state from Ureg
 * SB (R2) is unusable on return
 */
TEXT restoreureg(SB), $-4
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
	BR	(LR)

TEXT	exception(SB), $-4
	MOVW	R1, SPR(SAVER1)
	MOVW	CR, R0
	MOVW	R0, SPR(SAVECR)
	MOVW	LR, R0
	BL	saveureg(SB)
	MOVW	$0, R0
	BL	trap(SB)
	BL	restoreureg(SB)
	MOVW	SPR(SAVELR), R0
	MOVW	R0, LR
	MOVW	SPR(SAVER0), R0
	ISYNC
	RFI

GLOBL	mach0+0(SB), $MACHSIZE
GLOBL	m(SB), $4
