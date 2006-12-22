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
#define CLOCKFREQ	25000000
#define MS2TMR(t)	((ulong)(((uvlong)(t)*CLOCKFREQ)/1000))
#define US2TMR(t)	((ulong)(((uvlong)(t)*CLOCKFREQ)/1000000))

/*
 *  Address spaces
 *	nearly everything maps 1-1 with physical addresses
 *	0 to 1Mb is not mapped
 *	cache strategy varies as needed (see mmu.c)
 */

#define KZERO		0xC0000000
#define MACHADDR	(KZERO+0x00001000)
#define KTTB		(KZERO+0x00004000)
#define KTZERO	(KZERO+0x00008010)
#define KSTACK	8192			/* Size of kernel stack */
#define FLASHMEM	0x50000000	/* map flash to otherwise unused virtual space */
#define UCDRAMZERO	(KZERO+0x08000000)	/* base of memory doubly-mapped as uncached */
#define AIVECADDR	0xFFFF0000	/* alternative interrupt vector address (other is 0) */

/*
 * Physical addresses
 */
#define PHYSDRAM0	0x00000000	/* where firmware puts it */
#define PHYSFLASH0	0x02800000	/* where firmware puts it */
#define PHYSSCRINIT	0x03FF0000	/* address at reset */
#define PHYSSCR		PHYSSCRINIT	/* where it ends up after manga firmware */
#define PHYSBRIDGE	(PHYSSCR+0x2000)	/* PCI-AHB bridge configuration */
#define PHYSMEMCR	(PHYSSCR+0x4000)	/* memory controller interface */
#define PHYSWANDMA	(PHYSSCR+0x6000)	/* WAN DMA registers */
#define PHYSLANDMA	(PHYSSCR+0x8000)	/* LAN DMA registers */
#define PHYSUART		(PHYSSCR+0xE000)
#define PHYSINTR		(PHYSSCR+0xE200)	/* interrupt controller */
#define PHYSTIMER		(PHYSSCR+0xE400)	/* timer registers */
#define PHYSGPIO		(PHYSSCR+0xE600)
#define PHYSSWITCH	(PHYSSCR+0xE800)	/* switch engine configuration */
#define PHYSMISC		(PHYSSCR+0xEA00)	/* ``miscellaneous'' registers */

#define PHYSPCIBRIDGE	0x80000000	/* physical address that maps to PCI 0 */
#define PHYSPCIIO		0x10000000	/* physical address that maps to PCI I/O space */

#define	CACHELINELOG	5
#define	CACHELINESZ	(1<<CACHELINELOG)
#define	CACHESIZE	(8*1024)		/* I & D caches are the same size, 4 segment, 64-way associative */

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
 * Internal MMU coprocessor registers (ARM 922)
 */
#define CpCPUID	0		/* R: opcode_2 is 0*/
#define CpCacheID	0		/* R: opcode_2 is 1 */
#define CpControl	1		/* R/W: control (opcode_2 is 0) */
#define CpTTB		2		/* R/W: translation table base */
#define CpDAC		3		/* R/W: domain access control */
#define CpFSR		5		/* R/W: fault status */
#define CpFAR		6		/* R/W: fault address */
#define CpCacheCtl	7		/* W: */
#define CpTLBops	8		/* W: TLB operations */
#define CpCacheLk	9		/* W: cache lock down */
#define CpPID		13		/* R/W: Process ID Virtual Mapping */
#define CpTest		15		/* R/W: test configuration */

/*
 * Coprocessors
 */
#define CpMMU		15

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
#define CpCIcache	(1<<12)	/* I: Instruction Cache on */
#define CpCaltivec	(1<<13)	/* X: exception vector relocation */
#define CpCrrobin	(1<<14)	/* RR: round robin replacement */
#define CpCnotFast	(1<<30)	/* nF: notFastBus select */
#define CpCasync	(1<<31)	/* iA: asynchronous clock select */
