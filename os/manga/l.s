#include "mem.h"

#define	CPWAIT

/*
 * Entered here from the boot loader with
 *	supervisor mode, interrupts disabled;
 *	MMU and caches disabled
 */

#define	LED	\
	MOVW	$(PHYSGPIO+8), R6;\
	MOVW	(R6), R7;\
	EOR	$(1<<12), R7;\
	MOVW	R7, (R6)

TEXT _startup(SB), $-4
	MOVW		$setR12(SB), R12 	/* static base (SB) */
	MOVW		$(PsrDirq|PsrDfiq|PsrMsvc), R1	/* ensure SVC mode with interrupts disabled */
	MOVW		R1, CPSR

	/* build a temporary translation table at 4MB */
	MOVW	$0x400000, R0
	MCR	CpMMU, 0, R0, C(CpTTB), C(0), 0	/* set TTB */
	MOVW	$4096, R1
	MOVW	$0, R3
	ORR	$(1<<4), R3	/* must be one */
	ORR	$(3<<10), R3	/* supervisor rw */
	ORR	$(2<<0), R3	/* section */
startup0:
	BIC	$0xFC000000, R3	/* wraps round, at least for 0xC00... */
	MOVW	R3, (R0)
	ADD	$4, R0
	ADD	$(1<<20), R3
	SUB	$1, R1
	CMP	$0, R1
	BNE	startup0
	MRC		CpMMU, 0, R0, C(CpControl), C(0), 0
	ORR	$CpCmmu, R0

	MOVW	$3, R1
	MCR	CpMMU, 0, R1, C(CpDAC), C(0)	/* set domain 0 to manager */
	BL	mmuenable(SB)

	MOVW		$(MACHADDR+BY2PG-4), R13	/* stack; 4 bytes for link */
	BL	_relocate(SB)
	BL		main(SB)
dead:
	B	dead
	BL	_div(SB)			/* hack to get _div etc loaded */

TEXT _relocate(SB), $-4
	ORR	$KZERO, R14
	RET

TEXT	getcpuid(SB), $-4
	MRC		CpMMU, 0, R0, C(CpCPUID), C(0)
	RET

TEXT	getcacheid(SB), $-4
	MRC		CpMMU, 0, R0, C(CpCacheID), C(1)
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
	CPWAIT
	RET

TEXT	mmuputfsr(SB), $-4
	MCR		CpMMU, 0, R0, C(CpFSR), C(0)
	CPWAIT
	RET

TEXT	mmuputttb(SB), $-4
	MCR		CpMMU, 0, R0, C(CpTTB), C(0)
	CPWAIT
	RET

TEXT mmuputctl(SB), $-4
	MCR		CpMMU, 0, R0, C(CpControl), C(0)

	/* drain prefetch */
	MOVW	R0,R0						
	MOVW	R0,R0
	RET	

TEXT tlbinvalidateall(SB), $-4
	MCR		CpMMU, 0, R0, C(CpTLBops), C(7)
	CPWAIT
	RET

TEXT itlbinvalidate(SB), $-4
	MCR		CpMMU, 0, R0, C(CpTLBops), C(5), 1
	CPWAIT
	RET

TEXT dtlbinvalidate(SB), $-4
	MCR		CpMMU, 0, R0, C(CpTLBops), C(6), 1
	CPWAIT
	RET

TEXT mmuenable(SB), $-4

	/* disable and invalidate all caches and TLB's before enabling MMU */
	MCR		CpMMU, 0, R1, C(CpControl), C(0)
	BIC	$(CpCDcache | CpCIcache), R1
	MRC		CpMMU, 0, R1, C(CpControl), C(0)
	CPWAIT

	MOVW	$0, R1				/* disable everything */
	MCR	CpMMU, 0, R1, C(CpCacheCtl), C(7), 0	/* invalidate I&D Caches and BTB */
	MCR	CpMMU, 0, R1, C(CpCacheCtl), C(10), 4	/* drain write buffer */
	MCR	CpMMU, 0, R1, C(CpTLBops), C(7), 0	/* invalidate I&D TLB */

	/* enable desired mmu mode (R0) */
	MCR	CpMMU, 0, R0, C(CpControl), C(0)

	/* drain prefetch */
	MOVW	R0,R0						
	MOVW	R0,R0
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
 * flush (invalidate) the whole icache
 */
TEXT icflushall(SB), $-4
_icflushall:
	MCR	 	CpMMU, 0, R0, C(CpCacheCtl), C(5), 0	/* invalidate i-cache */
	CPWAIT
	RET

/*
 * invalidate part of i-cache
 */
TEXT	icflush(SB), $-4
	MOVW	4(FP), R1
	CMP		$(CACHESIZE/2), R1
	BGE		_icflushall		/* might as well do the lot */
	ADD		R0, R1
	BIC		$(CACHELINESZ-1), R0
icflush1:
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(5), 1	/* invalidate entry by address */
	ADD		$CACHELINESZ, R0
	CMP		R1, R0
	BLO	icflush1
	RET

/*
 * write back whole data cache, invalidate, and drain write buffer
 */
TEXT dcflushall(SB), $-4
_dcflushall:
	MOVW	$(63<<26), R1	/* index, segment 0 */
dcflushall0:
	MCR	CpMMU, 0, R1, C(CpCacheCtl), C(14), 2	/* clean and invalidate, using index */
	ADD	$(1<<5), R1	/* segment 1 */
	MCR	CpMMU, 0, R1, C(CpCacheCtl), C(14), 2
	ADD	$(1<<5), R1	/* segment 2 */
	MCR	CpMMU, 0, R1, C(CpCacheCtl), C(14), 2
	ADD	$(1<<5), R1	/* segment 3 */
	MCR	CpMMU, 0, R1, C(CpCacheCtl), C(14), 2
	EOR	$(3<<5), R1	/* back to 0 */
	SUB.S	$(1<<26), R1
	BCS	dcflushall0
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(10), 4	/* drain write buffer */
	CPWAIT
	RET

/*
 * write back a given region, inavlidate it, and drain write buffer
 */
TEXT	dcflush(SB), $-4
	MOVW	4(FP), R1
	CMP		$(CACHESIZE/2), R1
	BGE		_dcflushall
	ADD		R0, R1
	BIC		$(CACHELINESZ-1), R0
dcflush1:
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(14), 1	/* clean and invalidate entry by address */
	ADD		$CACHELINESZ, R0
	CMP		R1, R0
	BLO	dcflush1
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(10), 4	/* drain write buffer */
	CPWAIT
	RET

/*
 * invalidate data cache
 */
TEXT dcinval(SB), $-4
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(6), 0
	CPWAIT
	RET

/* for devboot */
TEXT	gotopc(SB), $-4
	MOVW	R0, R1
	MOVW	$0, R0
	MOVW	R1, PC
	RET

TEXT	idle(SB), $-4
	MCR		CpMMU, 0, R0, C(7), C(0), 4
	RET
