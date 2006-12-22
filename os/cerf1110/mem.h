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

#define KZERO		0xC0000000
#define MACHADDR	(KZERO+0x00001000)
#define KTTB		(KZERO+0x00004000)
#define KTZERO	(KZERO+0x00008010)
#define KSTACK	8192			/* Size of kernel stack */
#define FLASHMEM	0x50000000	/* map flash at phys 0 to otherwise unused virtual space */
#define FLUSHMEM	0xE0000000	/* internally decoded zero memory (for cache flushing) */
#define DCFADDR	FLUSHMEM	/* cached and buffered for cache writeback */
#define MCFADDR	(FLUSHMEM+(1<<20))	/* cached and unbuffered for minicache writeback */
#define UCDRAMZERO	0xC8000000	/* base of memory doubly-mapped as uncached */
#define AIVECADDR	0xFFFF0000	/* alternative interrupt vector address (other is 0) */

/*
 * Physical addresses
 */
#define PHYSFLASH0	0x00000000	/* flash (chip select 0) */
#define PHYSCS1		0x08000000	/* static chip select 1 */
#define PHYSCS2		0x10000000	/* static chip select 2 */
#define PHYSCS3		0x18000000	/* static chip select 3 */
#define PHYSPCMCIA0	0x20000000	/* PCMCIA socket 0 space */
#define PHYSPCMCIA1	0x30000000	/* PCMCIA socket 1 space */
#define PCMCIASIZE		0x10000000	/* they're both huge */
#define PHYSCS4		0x40000000	/* static chip select 4 */
#define PHYSCS5		0x48000000	/* static chip select 5 */
#define PHYSSERIAL(n)	(0x80000000+0x10000*(n))	/* serial devices */
#define PHYSUSB		0x80000000
#define PHYSGPCLK		0x80020060
#define PHYSMCP		0x80060000
#define PHYSSSP		0x80070060
#define PHYSOSTMR		0x90000000	/* timers */
#define PHYSRTC		0x90010000	/* real time clock */
#define PHYSPOWER		0x90020000	/* power management registers */
#define PHYSRESET		0x90030000	/* reset controller */
#define PHYSGPIO		0x90040000
#define PHYSINTR		0x90050000	/* interrupt controller */
#define PHYSPPC		0x90060000	/* peripheral pin controller */
#define PHYSMEMCFG	0xA0000000	/* memory configuration */
#define PHYSDMA		0xB0000000	/* DMA controller */
#define PHYSLCD		0xB0100000	/* LCD controller */
#define PHYSMEM0		0xC0000000
#define PHYSFLUSH0	0xE0000000	/* internally decoded, for cache flushing */

/*
 * Memory Interface Control Registers
 */
#define 	MDCNFG	(PHYSMEMCFG)	/* memory controller configuration */
#define	MDCAS0	(PHYSMEMCFG+4)
#define	MDCAS1	(PHYSMEMCFG+8)
#define	MDCAS2	(PHYSMEMCFG+0xC)
#define	MSC0	(PHYSMEMCFG+0x10)
#define	MSC1	(PHYSMEMCFG+0x14)
#define	MSC2	(PHYSMEMCFG+0x2C)	/* SA1110, but not SA1100 */

#define	MSCx(RRR, RDN, RDF, RBW, RT)	((((RRR)&0x7)<<13)|(((RDN)&0x1F)<<8)|(((RDF)&0x1F)<<3)|(((RBW)&1)<<2)|((RT)&3))

#define	CACHELINELOG	5
#define	CACHELINESZ	(1<<CACHELINELOG)

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
#define CpCPUID	0		/* R: */
#define CpControl	1		/* R/W: */
#define CpTTB		2		/* R/W: translation table base */
#define CpDAC		3		/* R/W: domain access control */
#define CpFSR		5		/* R/W: fault status */
#define CpFAR		6		/* R/W: fault address */
#define CpCacheCtl	7		/* W: */
#define CpTLBops	8		/* W: TLB operations */
#define CpRBops	9		/* W: Read Buffer operations */
#define CpPID		13		/* R/W: Process ID Virtual Mapping */
#define CpDebug	14		/* R/W: debug registers */
#define CpTest		15		/* W: Test, Clock and Idle Control */

/*
 * Coprocessors
 */
#define CpMMU		15
#define CpPWR		15

/*
 * CpControl bits
 */
#define CpCmmu	0x00000001	/* M: MMU enable */
#define CpCalign	0x00000002	/* A: alignment fault enable */
#define CpCDcache	0x00000004	/* C: instruction/data cache on */
#define CpCwb		0x00000008	/* W: write buffer turned on */
#define CpCi32		0x00000010	/* P: 32-bit programme space */
#define CpCd32	0x00000020	/* D: 32-bit data space */
#define CpCbe		0x00000080	/* B: big-endian operation */
#define CpCsystem	0x00000100	/* S: system permission */
#define CpCrom	0x00000200	/* R: ROM permission */
#define CpCIcache	0x00001000	/* I: Instruction Cache on */
#define CpCaltivec	0x00002000	/* X: alternative interrupt vectors */

/*
 * MMU
 */
/*
 * Small pages:
 *	L1: 12-bit index -> 4096 descriptors -> 16Kb
 *	L2:  8-bit index ->  256 descriptors ->  1Kb
 * Each L2 descriptor has access permissions for 4 1Kb sub-pages.
 *
 *	TTB + L1Tx gives address of L1 descriptor
 *	L1 descriptor gives PTBA
 *	PTBA + L2Tx gives address of L2 descriptor
 *	L2 descriptor gives PBA
 */
#define MmuSection	(1<<20)
#define MmuLargePage	(1<<16)
#define MmuSmallPage	(1<<12)
#define MmuTTB(pa)	((pa) & ~0x3FFF)	/* translation table base */
#define MmuL1x(pa)	(((pa)>>20) & 0xFFF)	/* L1 table index */
#define MmuPTBA(pa)	((pa) & ~0x3FF)		/* page table base address */
#define MmuL2x(pa)	(((pa)>>12) & 0xFF)	/* L2 table index */
#define MmuPBA(pa)	((pa) & ~0xFFF)		/* page base address */
#define MmuSBA(pa)	((pa) & ~0xFFFFF)	/* section base address */

#define MmuL1type	0x03
#define MmuL1page	0x01			/* descriptor is for L2 pages */
#define MmuL1section	0x02			/* descriptor is for section */

#define MmuL2invalid	0x000
#define MmuL2large	0x001			/* large */
#define MmuL2small	0x002			/* small */
#define MmuWB		0x004			/* data goes through write buffer */
#define MmuIDC		0x008			/* data placed in cache */

#define MmuDAC(d)	(((d) & 0xF)<<5)	/* L1 domain */
#define MmuAP(i, v)	((v)<<(((i)*2)+4))	/* access permissions */
#define MmuL1AP(v)	MmuAP(3, (v))
#define MmuL2AP(v)	MmuAP(3, (v))|MmuAP(2, (v))|MmuAP(1, (v))|MmuAP(0, (v))
#define MmuAPsro	0			/* supervisor ro if S|R */
#define MmuAPsrw	1			/* supervisor rw */
#define MmuAPuro	2			/* supervisor rw + user ro */
#define MmuAPurw	3			/* supervisor rw + user rw */
