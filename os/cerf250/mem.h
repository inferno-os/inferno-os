/*
 * Memory and machine-specific definitions.  Used in C and assembler.
 */

/*
 * Sizes
 */
#define	BI2BY		8			/* bits per byte */
#define BI2WD		32			/* bits per word */
#define	BY2WD		4			/* bytes per word */
#define	BY2V		8			/* bytes per double word */
#define	BY2PG		4096			/* bytes per page */
#define	WD2PG		(BY2PG/BY2WD)		/* words per page */
#define	PGSHIFT		12			/* log(BY2PG) */
#define ROUND(s, sz)	(((s)+(sz-1))&~(sz-1))
#define PGROUND(s)	ROUND(s, BY2PG)
#define BIT(n)		(1<<n)
#define BITS(a,b)	((1<<(b+1))-(1<<a))

#define	MAXMACH		1			/* max # cpus system can run */

/*
 * Time
 */
#define	HZ		(100)			/* clock frequency */
#define	MS2HZ		(1000/HZ)		/* millisec per clock tick */
#define	TK2SEC(t)	((t)/HZ)		/* ticks to seconds */
#define	MS2TK(t)	((t)/MS2HZ)		/* milliseconds to ticks */

/*
 * More accurate time
 */
#define CLOCKFREQ	3686400
#define MS2TMR(t)	((ulong)(((uvlong)(t)*CLOCKFREQ)/1000))
#define US2TMR(t)	((ulong)(((uvlong)(t)*CLOCKFREQ)/1000000))

/*
 *  Address spaces
 *	nearly everything maps 1-1 with physical addresses
 *	0 to 1Mb is not mapped
 *	cache strategy varies as needed (see mmu.c)
 */

#define KZERO		0xA0000000
#define MACHADDR	(KZERO+0x00001000)
#define KTTB		(KZERO+0x00004000)
/*#define KTZERO	(KZERO+0x00008010)*/
#define KTZERO	(KZERO+0x200020)	/* temporary */
#define KSTACK	8192			/* Size of kernel stack */
#define FLASHMEM	0x50000000	/* map flash at phys 0 to otherwise unused virtual space */
#define FLUSHMEM	0xE0000000	/* virtual address reserved for cache flushing */
#define DCFADDR	FLUSHMEM	/* cached and buffered for cache writeback */
#define MCFADDR	(FLUSHMEM+(1<<20))	/* cached and unbuffered for minicache writeback */
#define UCDRAMZERO	0xA8000000	/* base of memory doubly-mapped as uncached */
#define AIVECADDR	0xFFFF0000	/* alternative interrupt vector address (other is 0) */

/*
 * Physical addresses
 */
#define PHYSFLASH0	0x00000000	/* flash (chip select 0) */
#define PHYSCS1		0x04000000	/* static chip select 1 */
#define PHYSCS2		0x08000000	/* static chip select 2 */
#define PHYSCS3		0x0C000000	/* static chip select 3 */
#define PHYSCS4		0x10000000	/* static chip select 4 */
#define PHYSCS5		0x18000000	/* static chip select 5 */
#define PHYSPCMCIA0	0x20000000	/* PCMCIA socket 0 space */
#define PHYSPCMCIA1	0x30000000	/* PCMCIA socket 1 space */
#define PCMCIASIZE		0x10000000	/* they're both huge */
#define PHYSREGS		0x40000000	/* memory mapped registers */
#define PHYSDMA		0x40000000	/* DMA controller */
#define PHYSUART0		0x40100000	/* full function UART*/
#define PHYSUARTBT	0x40200000	/* bluetooth UART */
#define PHYSI2C		0x40301680
#define PHYSI2S		0x40400000	/* serial audio */
#define PHYSAC97		0x40500000	/* AC97/PCM/modem */
#define PHYSUDC		0x40600000	/* USB client */
#define PHYSUART1		0x40700000	/* standard UART */
#define PHYSICP		0x40800000
#define PHYSRTC		0x40900000	/* real-time clock */
#define PHYSOSTMR		0x40A00000	/* timers */
#define PHYSPWM0		0x40B00000	/* pulse width modulator */
#define PHYSPWM1		0x40C00000
#define PHYSINTR		0x40D00000	/* interrupt controller */
#define PHYSGPIO		0x40E00000	/* pins */
#define PHYSPOWER		0x40F00000	/* power management registers */
#define PHYSSSP		0x41000000
#define PHYSMMC		0x41100000
#define PHYSCORE		0x41300000	/* clocks manager */
#define PHYSNETSSP	0x41400000	/* network SSP */
#define PHYSUART2		0x41600000	/* hardware UART */
#define PHYSLCD		0x44000000	/* LCD controller */
#define PHYSMEMCFG	0x48000000	/* memory configuration */
#define PHYSMEM0		0xA0000000

/*
 * Memory Interface Control Registers
 */
#define 	MDCNFG	(PHYSMEMCFG)	/* memory controller configuration */
#define	MDREFR	(PHYSMEMCFG+4)
#define	MSC0	(MDREFR+4)
#define	MSC1	(MSC0+4)
#define	MSC2	(MSC1+4)

#define	MSCx(RRR, RDN, RDF, RBW, RT)	((((RRR)&0x7)<<13)|(((RDN)&0x1F)<<8)|(((RDF)&0x1F)<<3)|(((RBW)&1)<<2)|((RT)&3))

#define	CACHELINELOG	5
#define	CACHELINESZ	(1<<CACHELINELOG)
#define	CACHESIZE	(32*1024)		/* I & D caches are the same size */
#define	MINICACHESIZE	(2*1024)

/*
 * PSR
 */
#define PsrMusr		0x10 	/* mode */
#define PsrMfiq		0x11 
#define PsrMirq		0x12
#define PsrMsvc		0x13
#define PsrMabt		0x17
#define PsrMund		0x1B
#define PsrMsys		0x1F
#define PsrMask		0x1F

#define PsrDfiq		0x00000040	/* disable FIQ interrupts */
#define PsrDirq		0x00000080	/* disable IRQ interrupts */

#define PsrV		0x10000000	/* overflow */
#define PsrC		0x20000000	/* carry/borrow/extend */
#define PsrZ		0x40000000	/* zero */
#define PsrN		0x80000000	/* negative/less than */

/*
 * Internal MMU coprocessor registers
 */
#define CpCPUID	0		/* R: opcode_2 is 0*/
#define CpCacheID	0		/* R: opcode_2 is 1 */
#define CpControl	1		/* R/W: control (opcode_2 is 0) */
#define CpAuxctl	1		/* R/W: auxiliary control (opcode_2 is 1) */
#define CpTTB		2		/* R/W: translation table base */
#define CpDAC		3		/* R/W: domain access control */
#define CpFSR		5		/* R/W: fault status */
#define CpFAR		6		/* R/W: fault address */
#define CpCacheCtl	7		/* W: */
#define CpTLBops	8		/* W: TLB operations */
#define CpCacheLk	9		/* W: cache lock down */
#define CpPID		13		/* R/W: Process ID Virtual Mapping */
#define CpDebug	14		/* R/W: debug registers */
#define CpAccess	15		/* R/W: Coprocessor Access */

/*
 * Coprocessors
 */
#define CpMMU		15
#define CpPWR		14

/*
 * CpControl bits
 */
#define CpCmmu	(1<<0)	/* M: MMU enable */
#define CpCalign	(1<<1)	/* A: alignment fault enable */
#define CpCDcache	(1<<2)	/* C: data cache on */
#define CpCwpd	(15<<3)	/* W, P, D, must be one */
#define CpCbe		(1<<7)	/* B: big-endian operation */
#define CpCsystem	(1<<8)	/* S: system permission */
#define CpCrom	(1<<9)	/* R: ROM permission */
#define CpCbranch	(1<<11)	/* Z: branch target buffer enable */
#define CpCIcache	(1<<12)	/* I: Instruction Cache on */
#define CpCaltivec	(1<<13)	/* V: exception vector relocation */

/*
 * CpAux bits
 */
#define	CpWBdisable	(1<<1)	/* globally disable write buffer coalescing */
#define	CpMDrwa	(1<<4)	/* mini data cache r/w allocate */
#define	CpMDwt	(1<<5)	/* mini data cache write through */
