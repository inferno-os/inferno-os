#include "mem.h"

/*
 * Entered here from the boot loader with
 *	supervisor mode, interrupts disabled;
 *	MMU, IDC and WB disabled.
 */

TEXT _startup(SB), $-4
	MOVW		$setR12(SB), R12 	/* static base (SB) */
	MOVW		$(PsrDirq|PsrDfiq|PsrMsvc), R1	/* ensure SVC mode with interrupts disabled */
	MOVW		R1, CPSR
	MOVW		$(MACHADDR+BY2PG-4), R13	/* stack; 4 bytes for link */

	BL		main(SB)
dead:
	B	dead
	BL	_div(SB)			/* hack to get _div etc loaded */

TEXT	getcpuid(SB), $-4
	MRC		CpMMU, 0, R0, C(CpCPUID), C(0)
	RET

TEXT mmugetctl(SB), $-4
	MRC		CpMMU, 0, R0, C(CpControl), C(0)
	RET	

TEXT	mmugetdac(SB), $-4
	MRC		CpMMU, 0, R0, C(CpDAC), C(0)
	RET

TEXT	mmugetfar(SB), $-4
	MRC		CpMMU, 0, R0, C(CpFAR), C(0)
	RET

TEXT	mmugetfsr(SB), $-4
	MRC		CpMMU, 0, R0, C(CpFSR), C(0)
	RET

TEXT	mmuputdac(SB), $-4
	MCR		CpMMU, 0, R0, C(CpDAC), C(0)
	RET

TEXT	mmuputfsr(SB), $-4
	MCR		CpMMU, 0, R0, C(CpFSR), C(0)
	RET

TEXT	mmuputttb(SB), $-4
	MCR		CpMMU, 0, R0, C(CpTTB), C(0)
	RET

TEXT mmuputctl(SB), $-4
	MCR		CpMMU, 0, R0, C(CpControl), C(0)
	MOVW		R0, R0
	MOVW		R0, R0
	RET	

TEXT tlbinvalidateall(SB), $-4
	MCR		CpMMU, 0, R0, C(CpTLBops), C(7)
	RET

TEXT tlbinvalidate(SB), $-4
	MCR		CpMMU, 0, R0, C(CpTLBops), C(7), 1
	RET

TEXT mmuenable(SB), $-4

	MOVW	$1, R1
	MCR	CpMMU, 0, R1, C(CpDAC), C(3)	/* set domain 0 to client */

	/* disable and flush all caches and TLB's before (re-)enabling MMU */
	MOVW	$(CpCi32 | CpCd32 | (1<<6) | CpCsystem), R1
	MRC		CpMMU, 0, R1, C(CpControl), C(0)
	MOVW	$0, R1				/* disable everything */
	MCR	CpMMU, 0, R1, C(CpCacheCtl), C(7), 0	/* Flush I&D Caches */
	MCR	CpMMU, 0, R1, C(CpCacheCtl), C(10), 4	/* drain write buffer */
	MCR	CpMMU, 0, R1, C(CpTLBops), C(7), 0	/* Flush I&D TLB */
	MCR	CpMMU, 0, R1, C(CpRBops), C(0), 0	/* Flush Read Buffer */

	/* enable desired mmu mode (R0) */
	MCR	CpMMU, 0, R0, C(1), C(0)
	MOVW	R0, R0
	MOVW	R0, R0
	MOVW	R0, R0
	MOVW	R0, R0
	RET				/* start running in remapped area */

TEXT setr13(SB), $-4
	MOVW		4(FP), R1

	MOVW		CPSR, R2
	BIC		$PsrMask, R2, R3
	ORR		R0, R3
	MOVW		R3, CPSR

	MOVW		R13, R0
	MOVW		R1, R13

	MOVW		R2, CPSR
	RET

TEXT vectors(SB), $-4
	MOVW	0x18(R15), R15			/* reset */
	MOVW	0x18(R15), R15			/* undefined */
	MOVW	0x18(R15), R15			/* SWI */
	MOVW	0x18(R15), R15			/* prefetch abort */
	MOVW	0x18(R15), R15			/* data abort */
	MOVW	0x18(R15), R15			/* reserved */
	MOVW	0x18(R15), R15			/* IRQ */
	MOVW	0x18(R15), R15			/* FIQ */

TEXT vtable(SB), $-4
	WORD	$_vsvc(SB)			/* reset, in svc mode already */
	WORD	$_vund(SB)			/* undefined, switch to svc mode */
	WORD	$_vsvc(SB)			/* swi, in svc mode already */
	WORD	$_vpab(SB)			/* prefetch abort, switch to svc mode */
	WORD	$_vdab(SB)			/* data abort, switch to svc mode */
	WORD	$_vsvc(SB)			/* reserved */
	WORD	$_virq(SB)			/* IRQ, switch to svc mode */
	WORD	$_vfiq(SB)			/* FIQ, switch to svc mode */

TEXT _vund(SB), $-4			
	MOVM.DB		[R0-R3], (R13)
	MOVW		$PsrMund, R0
	B		_vswitch

TEXT _vsvc(SB), $-4				
	MOVW.W		R14, -4(R13)
	MOVW		CPSR, R14
	MOVW.W		R14, -4(R13)
	BIC		$PsrMask, R14
	ORR		$(PsrDirq|PsrDfiq|PsrMsvc), R14
	MOVW		R14, CPSR
	MOVW		$PsrMsvc, R14
	MOVW.W		R14, -4(R13)
	B		_vsaveu

TEXT _vpab(SB), $-4			
	MOVM.DB		[R0-R3], (R13)
	MOVW		$PsrMabt, R0
	B		_vswitch

TEXT _vdab(SB), $-4	
	MOVM.DB		[R0-R3], (R13)
	MOVW		$(PsrMabt+1), R0
	B		_vswitch

TEXT _vfiq(SB), $-4				/* FIQ */
	MOVM.DB		[R0-R3], (R13)
	MOVW		$PsrMfiq, R0
	B		_vswitch

TEXT _virq(SB), $-4				/* IRQ */
	MOVM.DB		[R0-R3], (R13)
	MOVW		$PsrMirq, R0

_vswitch:					/* switch to svc mode */
	MOVW		SPSR, R1
	MOVW		R14, R2
	MOVW		R13, R3

	MOVW		CPSR, R14
	BIC		$PsrMask, R14
	ORR		$(PsrDirq|PsrDfiq|PsrMsvc), R14
	MOVW		R14, CPSR

	MOVM.DB.W 	[R0-R2], (R13)
	MOVM.DB	  	(R3), [R0-R3]

_vsaveu:						/* Save Registers */
	MOVW.W		R14, -4(R13)			/* save link */
	MCR		CpMMU, 0, R0, C(0), C(0), 0	

	SUB		$8, R13
	MOVM.DB.W 	[R0-R12], (R13)

	MOVW		R0, R0				/* gratuitous noop */

	MOVW		$setR12(SB), R12		/* static base (SB) */
	MOVW		R13, R0				/* argument is ureg */
	SUB		$8, R13				/* space for arg+lnk*/
	BL		trap(SB)

_vrfe:							/* Restore Regs */
	MOVW		CPSR, R0			/* splhi on return */
	ORR		$(PsrDirq|PsrDfiq), R0, R1
	MOVW		R1, CPSR
	ADD		$(8+4*15), R13		/* [r0-R14]+argument+link */
	MOVW		(R13), R14			/* restore link */
	MOVW		8(R13), R0
	MOVW		R0, SPSR
	MOVM.DB.S 	(R13), [R0-R14]		/* restore user registers */
	MOVW		R0, R0				/* gratuitous nop */
	ADD		$12, R13		/* skip saved link+type+SPSR*/
	RFE					/* MOVM.IA.S.W (R13), [R15] */
	
TEXT splhi(SB), $-4					
	MOVW		CPSR, R0
	ORR		$(PsrDirq), R0, R1
	MOVW		R1, CPSR
	MOVW	$(MACHADDR), R6
	MOVW	R14, (R6)	/* m->splpc */
	RET

TEXT spllo(SB), $-4
	MOVW		CPSR, R0
	BIC		$(PsrDirq|PsrDfiq), R0, R1
	MOVW		R1, CPSR
	RET

TEXT splx(SB), $-4
	MOVW	$(MACHADDR), R6
	MOVW	R14, (R6)	/* m->splpc */

TEXT splxpc(SB), $-4
	MOVW		R0, R1
	MOVW		CPSR, R0
	MOVW		R1, CPSR
	RET

TEXT spldone(SB), $-4
	RET

TEXT islo(SB), $-4
	MOVW		CPSR, R0
	AND		$(PsrDirq), R0
	EOR		$(PsrDirq), R0
	RET

TEXT splfhi(SB), $-4					
	MOVW		CPSR, R0
	ORR		$(PsrDfiq|PsrDirq), R0, R1
	MOVW		R1, CPSR
	RET

TEXT splflo(SB), $-4
	MOVW		CPSR, R0
	BIC		$(PsrDfiq), R0, R1
	MOVW		R1, CPSR
	RET

TEXT getcpsr(SB), $-4
	MOVW		CPSR, R0
	RET

TEXT getspsr(SB), $-4
	MOVW		SPSR, R0
	RET

TEXT getcallerpc(SB), $-4
	MOVW		0(R13), R0
	RET

TEXT _tas(SB), $-4
	MOVW		R0, R1
	MOVW		$0xDEADDEAD, R2
	SWPW		R2, (R1), R0
	RET

TEXT setlabel(SB), $-4
	MOVW		R13, 0(R0)		/* sp */
	MOVW		R14, 4(R0)		/* pc */
	MOVW		$0, R0
	RET

TEXT gotolabel(SB), $-4
	MOVW		0(R0), R13		/* sp */
	MOVW		4(R0), R14		/* pc */
	MOVW		$1, R0
	RET

/*
 * flush the whole icache
 */
TEXT icflushall(SB), $-4
	MCR	 	CpMMU, 0, R0, C(CpCacheCtl), C(5), 0	
	MOVW		R0,R0
	MOVW		R0,R0
	MOVW		R0,R0
	MOVW		R0,R0
	RET

/*
 * write back whole data cache and drain write buffer
 */
TEXT dcflushall(SB), $-4
_dcflushall:
	MOVW		$(DCFADDR), R0
	ADD		$8192, R0, R1
dcflushall1:
	MOVW.P	CACHELINESZ(R0), R2
	CMP		R1,R0
	BNE		dcflushall1
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(10), 4	/* drain write buffer */
	MOVW		R0,R0								
	MOVW		R0,R0
	MOVW		R0,R0
	MOVW		R0,R0
	RET

/*
 * write back a given region and drain write buffer
 */
TEXT	dcflush(SB), $-4
	MOVW	4(FP), R1
	CMP		$(4*1024), R1
	BGE		_dcflushall
	ADD		R0, R1
	BIC		$(CACHELINESZ-1), R0
dcflush1:
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(10), 1	/* clean entry */
	ADD		$CACHELINESZ, R0
	CMP		R1, R0
	BLO	dcflush1
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(10), 4	/* drain write buffer */
	MOVW		R0,R0								
	MOVW		R0,R0
	MOVW		R0,R0
	MOVW		R0,R0
	RET

/*
 * write back mini data cache
 */
TEXT minidcflush(SB), $-4		
	MOVW		$(MCFADDR), R0
	ADD		$(16*CACHELINESZ), R0, R1

wbbflush:
	MOVW.P	CACHELINESZ(R0), R2
	CMP		R1,R0
	BNE		wbbflush
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(10), 4	/* drain write buffer */
	MOVW		R0,R0								
	MOVW		R0,R0
	MOVW		R0,R0
	MOVW		R0,R0
	RET

/*
 * invalidate data caches (main and mini)
 */
TEXT dcinval(SB), $-4
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(6), 0	
	RET

/* for devboot */
TEXT	gotopc(SB), $-4
	MOVW	R0, R1
	MOVW	$0, R0
	MOVW	R1, PC
	RET

/*
 * See page 9-26 of the SA1110 developer's manual.
 * trap copies this to a cache-aligned area.
 */
TEXT	_idlemode(SB), $-4
	MOVW	$UCDRAMZERO, R1
	MOVW	R0,R0
	MOVW	R0,R0
	MOVW	R0,R0
	MOVW	R0,R0
	MOVW	R0,R0
	MOVW	R0,R0
	MOVW	R0,R0
	/* the following must be on a cache line boundary */
	MCR		CpPWR, 0, R0, C(CpTest), C(0x2), 2	/* disable clock switching */
	MOVW	(R1), R0	/* non-cacheable memory read */
	MCR		CpPWR, 0, R0, C(CpTest), C(0x8), 2
	MCR		CpPWR, 0, R0, C(CpTest), C(0x2), 1	/* enable clock switching */
	RET

/*
 * the following code is considerably modified from the
 * sleep code by nemo@gsyc.escet.urjc.es for Plan 9, but that's
 * where it started.  in particular, there's no need to save regs in all modes,
 * since here we're called from kernel main level (a kproc) so nothing is live;
 * the only regs needed are the various R13s, but we have trap restore them on resume.
 * similarly there's no need to save SPSR, CPSR, etc. (even CpPID isn't really needed here).
 */

#define MDREFR_k1db2	(1<<22)
#define MDREFR_slfrsh	(1<<31)	/* self refresh */
#define MDREFR_e1pin	(1<<20)
#define MSC_rt		((3<<16)|(3<<0))
#define MDCFNG_de	((3<<16)|(3<<0))	/* dram enable, banks (3 2), (1 0) */

TEXT suspenditall(SB), $-4
	MOVW.W	R14, -4(R13)
	/* push mmu state on stack */
	MRC		CpMMU, 0, R1, C(CpDAC), C(0)
	MRC		CpMMU, 0, R2, C(CpTTB), C(0)
	MRC		CpMMU, 0, R3, C(CpPID), C(0)
	MRC		CpMMU, 0, R4, C(CpControl), C(0)
	MOVM.DB.W	[R1-R4], (R13)
	/* if pspr by convention held a stack pointer pointing to a pc we wouldn't need power_state */
	MOVW	R13, power_state+0(SB)

	BL	dcflushall(SB)
	/* don't write DRAM after this */

	MOVW	$PHYSPOWER, R3

	/* put resume address in scratchpad for boot loader */
	MOVW	$power_resume+0(SB), R2
	MOVW	R2, 0x8(R3)	/* pspr */

	/* disable clock switching */
	MCR   	CpPWR, 0, R1, C(CpTest), C(0x2), 2

	/* adjust mem timing first to avoid processor bug causing hang */
	MOVW	$MDCNFG, R5
	MOVW	0x1c(R5), R2
	ORR	$(MDREFR_k1db2), R2
	MOVW	R2, 0x1c(R5)

	/* set PLL to lower speed w/ delay */
	MOVW	$(120*206),R0
l11:	SUB	$1,R0
	BGT	l11
	MOVW	$0, R2
	MOVW	R2, 0x14(R3)	/* ppcr */
	MOVW	$(120*206),R0
l12:	SUB	$1,R0
	BGT	l12

	/*
	 *  SA1110 fix for various suspend bugs in pre-B4 chips (err. 14-16, 18):
	 * 	set up register values here for use in code below that is at most
	 *	one cache line (32 bytes) long, to run without DRAM.
	 */
	/* 1. clear RT in MSCx (R1, R7, R8) without changing other bits */
	MOVW	0x10(R5), R1	/* MSC0 */
	BIC	$(MSC_rt), R1
	MOVW	0x14(R5), R7	/* MSC1 */
	BIC	$(MSC_rt), R7
	MOVW	0x2c(R5), R8	/* MSC2 */
	BIC	$(MSC_rt), R8
	/* 2. clear DRI0-11 in MDREFR (R4) without changing other bits */
	MOVW	0x1c(R5), R4
	BIC	$(0xfff0), R4
	/* 3. set SLFRSH in MDREFR (R6) without changing other bits */
	ORR	$(MDREFR_slfrsh), R4, R6
	/* 4. clear DE in MDCNFG (R9), and any other bits desired */
	MOVW	0x0(R5), R9
	BIC	$(MDCFNG_de), R9
	/* 5. clear SLFRSH and E1PIN (R10), without changing other bits */
	BIC	$(MDREFR_slfrsh), R4, R10
	BIC	$(MDREFR_e1pin), R10
	/* 6. force sleep mode in PMCR (R2) */
	MOVW	$1,R2
	MOVW	suspendcode+0(SB), R0
	B	(R0)	/* off to do it */

/*
 * the following is copied by trap.c to a cache-aligned area (suspendcode),
 * so that it can all run during disabling of DRAM
 */
TEXT _suspendcode(SB), $-4
	/* 1: clear RT field of all MSCx registers */
	MOVW	R1, 0x10(R5)
	MOVW	R7, 0x14(R5)
	MOVW	R8, 0x2c(R5)
	/* 2: clear DRI field in MDREFR */
	MOVW	R4, 0x1c(R5)
	/* 3: set SLFRSH bit in MDREFR */
	MOVW	R6, 0x1c(R5)
	/* 4: clear DE bits in MDCFNG */
	MOVW	R9, 0x0(R5)
	/* 5: clear SLFRSH and E1PIN in MDREFR */
	MOVW	R10, 0x1c(R5)
	/* 6: suspend request */
	MOVW	R2, 0x0(R3)	 /* pmcr */
	B		0(PC)		/* wait for it */

/*
 * The boot loader comes here after the resume.
 */
TEXT power_resume(SB), $-4
	MOVW	$(PsrDirq|PsrDfiq|PsrMsvc), R0
	MOVW	R0, CPSR		/* svc mode, interrupts off */
	MOVW	$setR12(SB), R12

	/* flush caches */
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(7), 0
	/* drain prefetch */
	MOVW	R0,R0						
	MOVW	R0,R0
	MOVW	R0,R0
	MOVW	R0,R0
	/* drain write buffer */
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(10), 4
	/* flush tlb */
	MCR		CpMMU, 0, R0, C(CpTLBops), C(7)

	/* restore state */
	MOVW	power_state+0(SB), R13
	MOVM.IA.W	(R13), [R1-R4]
	MOVW.P	4(R13), R14

	MCR		CpMMU, 0, R1, C(CpDAC), C(0x0)
	MCR		CpMMU, 0, R2, C(CpTTB), C(0x0)
	MCR		CpMMU, 0, R3, C(CpPID), C(0x0)
	MCR		CpMMU, 0, R4, C(CpControl), C(0x0)	/* enable cache and mmu */
	MOVW	R0,R0						
	MOVW	R0,R0
	MOVW	R0,R0
	MOVW	R0,R0
	/* flush i&d caches */
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(7)
	/* flush tlb */
	MCR		CpMMU, 0, R0, C(CpTLBops), C(7)
	/* drain prefetch */
	MOVW	R0,R0						
	MOVW	R0,R0
	MOVW	R0,R0
	MOVW	R0,R0
	/* enable clock switching */
	MCR   	CpPWR, 0, R1, C(CpTest), C(1), 2
	RET

	GLOBL	power_state+0(SB), $4

/* for debugging sleep code: */
TEXT fastreset(SB), $-4
	MOVW	$PHYSRESET, R7
	MOVW	$1, R1
	MOVW	R1, (R7)
	RET
