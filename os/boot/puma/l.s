/*
 *	File: 		l.s
 *	Purpose:
 *  	Puma Board StrongARM 110 Architecture Specific Assembly
 *	
 */

#include "mem.h"
#include "armv4.h"
#include "puma.h"

#define	DRAMWAIT	100000		/* 3.125μsec per iteration */
#define	TL750R(r)	(TL750_BASE+(r)*4)

#define	BOOTBASE	0x00200000

TEXT		_main(SB),1,$-4
	MOVW	R15, R7	/* save PC on entry */

/*
 * initialise DRAM controller on the TL750 (SDRAM mode)
 */
	MOVW	$DRAMWAIT, R0	/* wait 312 ms after reset before touching DRAM */
dram1:
	SUB.S	$1, R0
	BNE	dram1

	MOVW	$TL750R(0x103), R0	/* DMC_DELAY */
	MOVW	$0x03333333, R1	/* DRAM timing parameters */
	MOVW	R1, (R0)

	MOVW	$TL750R(0x101), R0	/* DMC_SDRAM */
	MOVW	$0x03133011, R1	/* SDRAM parameters for Puma */
	MOVW	R1, (R0)

	MOVW	$DRAMWAIT, R0	/* wait 312 ms for initialisation */
dram2:
	SUB.S	$1, R0
	BNE	dram2

	MOVW		$setR12(SB),R12

/*
 * copy bootstrap to final location in DRAM
 */
	MOVW	R7, baddr(SB)
	MOVW	$(BOOTBASE+8), R0
	CMP	R0, R7
	BEQ	inplace
	MOVW	$((128*1024)/4), R6
copyboot:
	MOVW.P	4(R7), R5
	MOVW.P	R5, 4(R0)
	SUB.S	$1, R6
	BNE	copyboot
	MOVW	$bootrel(SB), R7
	MOVW	R7, R15

TEXT	bootrel(SB), $-4

/*
 * set C environment and invoke main
 */
inplace:
	MOVW		$mach0(SB),R13
	MOVW		R13,m(SB)
	ADD			$(MACHSIZE-12),R13

	/* disable MMU activity */
	BL			mmuctlregr(SB)
	BIC			$(CpCmmu|CpCDcache|CpCwb|CpCIcache), R0
	BL			mmuctlregw(SB)
		
	BL			main(SB)
loop:
	B			loop

TEXT		idle(SB),$0
	RET

/*
 *  basic timing loop to determine CPU frequency
 */
TEXT aamloop(SB), $-4				/* 3 */
_aamloop:
	MOVW		R0, R0			/* 1 */
	MOVW		R0, R0			/* 1 */
	MOVW		R0, R0			/* 1 */
	SUB			$1, R0			/* 1 */
	CMP			$0, R0			/* 1 */
	BNE			_aamloop			/* 3 */
	RET							/* 3 */

/*
 * Function: setr13( mode, pointer )
 * Purpose:
 *		Sets the stack pointer for a particular mode
 */

TEXT setr13(SB), $-4
	MOVW		4(FP), R1

	MOVW		CPSR, R2
	BIC			$PsrMask, R2, R3
	ORR			R0, R3
	MOVW		R3, CPSR

	MOVW		R13, R0
	MOVW		R1, R13

	MOVW		R2, CPSR

	RET

/*
 * Function: _vundcall
 * Purpose:
 *		Undefined Instruction Trap Handler
 *
 */

TEXT _vundcall(SB), $-4			
_vund:
	MOVM.DB		[R0-R3], (R13)
	MOVW		$PsrMund, R0
	B			_vswitch

/*
 * Function: _vsvccall
 * Purpose:
 *		Reset or SWI Handler
 *
 */

TEXT _vsvccall(SB), $-4				
_vsvc:
	SUB			$12, R13
	MOVW		R14, 8(R13)
	MOVW		CPSR, R14
	MOVW		R14, 4(R13)
	MOVW		$PsrMsvc, R14
	MOVW		R14, (R13)
	B			_vsaveu

/*
 * Function: _pabcall
 * Purpose:
 *		Prefetch Abort Trap Handler
 *
 */

TEXT _vpabcall(SB), $-4			
_vpab:
	MOVM.DB		[R0-R3], (R13)
	MOVW		$PsrMabt, R0
	B			_vswitch

/*
 * Function: _vdabcall
 * Purpose:
 *		Data Abort Trap Handler
 *
 */

TEXT _vdabcall(SB), $-4	
_vdab:
	MOVM.DB		[R0-R3], (R13)
	MOVW		$(PsrMabt+1), R0
	B			_vswitch

/*
 * Function: _virqcall
 * Purpose:
 *		IRQ Trap Handler 
 *
 */

TEXT _virqcall(SB), $-4				/* IRQ */
_virq:
	MOVM.DB		[R0-R3], (R13)
	MOVW		$PsrMirq, R0
	B			_vswitch

/*
 * Function: _vfiqcall
 * Purpose:
 *		FIQ Trap Handler 
 *
 */

TEXT _vfiqcall(SB), $-4				/* FIQ */
_vfiq:
	MOVM.DB		[R0-R3], (R13)
	MOVW		$PsrMfiq, R0
	/* FALLTHROUGH */

_vswitch:					/* switch to svc mode */
	MOVW		SPSR, R1
	MOVW		R14, R2
	MOVW		R13, R3

	MOVW		CPSR, R14
	BIC			$PsrMask, R14
	ORR			$(PsrDirq|PsrDfiq|PsrMsvc), R14
	MOVW		R14, CPSR

	MOVM.DB.W 	[R0-R2], (R13)
	MOVM.DB	  	(R3), [R0-R3]

_vsaveu:						/* Save Registers */
	SUB			$4, R13		/* save link */
	MOVW		R14, (R13)	/* MOVW.W R14,4(R13)*/

	SUB			$8, R13

	MOVW		R13, R14	/* ur->sp */
	ADD			$(6*4), R14
	MOVW		R14, 0(R13)

	MOVW		8(SP), R14			/* ur->link */
	MOVW		R14, 4(SP)

	MOVM.DB.W 	[R0-R12], (R13)	
	MOVW		R0, R0				/* gratuitous noop */

	MOVW		$setR12(SB), R12		/* static base (SB) */
	MOVW		R13, R0				/* argument is ureg */
	SUB			$8, R13				/* space for arg+lnk*/
	BL			trap(SB)


_vrfe:							/* Restore Regs */
	MOVW		CPSR, R0			/* splhi on return */
	ORR			$(PsrDirq|PsrDfiq), R0, R1
	MOVW		R1, CPSR
	ADD			$(8+4*15), R13		/* [r0-R14]+argument+link */
	MOVW		(R13), R14			/* restore link */
	MOVW		8(R13), R0
	MOVW		R0, SPSR
	MOVM.DB.S 	(R13), [R0-R14]		/* restore user registers */
	MOVW		R0, R0				/* gratuitous nop */
	ADD			$12, R13		/* skip saved link+type+SPSR*/
	RFE					/* MOVM.IA.S.W (R13), [R15] */


/*
 * Function: splhi
 * Purpose:
 *		Disable Interrupts
 * Returns:
 *		Previous interrupt state
 */
	
TEXT splhi(SB), $-4					
	MOVW		CPSR, R0
	ORR			$(PsrDirq|PsrDfiq), R0, R1
	MOVW		R1, CPSR
	RET

/*
 * Function: spllo
 * Purpose:
 *		Enable Interrupts
 * Returns:
 *		Previous interrupt state
 */

TEXT spllo(SB), $-4
	MOVW		CPSR, R0
	BIC			$(PsrDirq), R0, R1
	MOVW		R1, CPSR
	RET

/*
 * Function: splx(level)
 * Purpose:
 *		Restore interrupt level
 */

TEXT splx(SB), $-4
	MOVW		R0, R1
	MOVW		CPSR, R0
	MOVW		R1, CPSR
	RET

/*
 * Function: islo
 * Purpose:
 *		Check if interrupts are enabled
 *
 */

TEXT islo(SB), $-4
	MOVW		CPSR, R0
	AND			$(PsrDirq), R0
	EOR			$(PsrDirq), R0
	RET

/*
 * Function: cpsrr
 * Purpose:
 *		Returns current program status register
 *
 */

TEXT cpsrr(SB), $-4
	MOVW		CPSR, R0
	RET

/*
 * Function: spsrr
 * Purpose:
 *		Returns saved program status register
 *
 */

TEXT spsrr(SB), $-4
	MOVW		SPSR, R0
	RET

/*
 * MMU Operations
 */
TEXT mmuctlregr(SB), $-4
	MRC		CpMMU, 0, R0, C(CpControl), C(0)
	RET	

TEXT mmuctlregw(SB), $-4
	MCR		CpMMU, 0, R0, C(CpControl), C(0)
	MOVW		R0, R0
	MOVW		R0, R0
	RET	

/*
 * Cache Routines
 */

/*
 * Function: flushIcache
 * Purpose:
 *		Flushes the *WHOLE* instruction cache
 */

TEXT flushIcache(SB), $-4
	MCR	 	CpMMU, 0, R0, C(CpCacheCtl), C(5), 0	
	MOVW		R0,R0							
	MOVW		R0,R0
	MOVW		R0,R0
	MOVW		R0,R0
	RET



/*
 * Function: flushDentry
 * Purpose:
 *		Flushes an entry of the data cache
 */

TEXT flushDentry(SB), $-4
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(6), 1
	RET

/*
 * Function: drainWBuffer
 * Purpose:
 *		Drains the Write Buffer
 */

TEXT drainWBuffer(SB), $-4
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(10), 4	
	RET

/*
 * Function: writeBackDC
 * Purpose:
 *		Drains the dcache prior to flush
 */

TEXT writeBackDC(SB), $-4
	MOVW		$0xE0000000, R0
	MOVW		$8192, R1
	ADD		R0, R1

wbflush:
	MOVW		(R0), R2
	ADD		$32, R0
	CMP		R1,R0
	BNE		wbflush
	RET

/*
 * Function: flushDcache(SB)
 * Purpose:
 *		Flush the dcache 
 */

TEXT flushDcache(SB), $-4
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(6), 0	
	RET

/*
 * Function: writeBackBDC(SB)
 * Purpose:
 *		Write back the Baby D-Cache
 */

TEXT writeBackBDC(SB), $-4		
	MOVW		$0xE4000000, R0
	MOVW		$0x200, R1
	ADD		R0, R1

wbbflush:
	MOVW		(R0), R2
	ADD		$32, R0
	CMP		R1,R0
	BNE		wbbflush
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(10), 4	
	MOVW		R0,R0								
	MOVW		R0,R0
	MOVW		R0,R0
	MOVW		R0,R0
	RET

GLOBL	mach0+0(SB), $MACHSIZE
GLOBL	m(SB), $4
GLOBL	baddr(SB), $4
