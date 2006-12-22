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
#define CpCPUID		0		/* R: */
#define CpControl	1		/* R: */
#define CpTTB		2		/* W: translation table base */
#define CpDAC		3		/* W: domain access control */
#define CpFSR		5		/* R: fault status */
#define CpTLBflush	5		/* W: */
#define CpFAR		6		/* R: fault address */
#define CpTLBpurge	6		/* W: */
#define CpCacheCtl	7		/* W: */

#define CpDebug		14		/* R/W: debug registers */
/*
 * Coprocessors
 */
#define CpMMU		15

/*
 * Internal MMU coprocessor registers
 */
#define CpCmmu		0x00000001	/* M: MMU enable */
#define CpCalign	0x00000002	/* A: alignment fault enable */
#define CpCDcache	0x00000004	/* C: instruction/data cache on */
#define CpCwb		0x00000008	/* W: write buffer turned on */
#define CpCi32		0x00000010	/* P: 32-bit programme space */
#define CpCd32		0x00000020	/* D: 32-bit data space */
#define CpCbe		0x00000080	/* B: big-endian operation */
#define CpCsystem	0x00000100	/* S: system permission */
#define CpCrom		0x00000200	/* R: ROM permission */
#define CpCIcache	0x00001000	/* C: Instruction Cache on */

/*
 * Debug support internal registers
 */
#define CpDBAR	0
#define CpDBVR	1
#define CpDBMR	2
#define CpDBCR	3
#define CpIBCR	8
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
#define MmuTTB(pa)	((pa) & ~0x3FFF)	/* translation table base */
#define MmuL1x(pa)	(((pa)>>20) & 0xFFF)	/* L1 table index */
#define MmuPTBA(pa)	((pa) & ~0x3FF)		/* page table base address */
#define MmuL2x(pa)	(((pa)>>12) & 0xFF)	/* L2 table index */
#define MmuPBA(pa)	((pa) & ~0xFFF)		/* page base address */
#define MmuSBA(pa)	((pa) & ~0xFFFFF)	/* section base address */

#define MmuL1page	0x011			/* descriptor is for L2 pages */
#define MmuL1section	0x012			/* descriptor is for section */

#define MmuL2invalid	0x000
#define MmuL2large	0x001			/* large */
#define MmuL2small	0x002			/* small */
#define MmuWB		0x004			/* data goes through write buffer */
#define MmuIDC		0x008			/* data placed in cache */

#define MmuDAC(d)	(((d) & 0xF)<<5)	/* L1 domain */
#define MmuAP(i, v)	((v)<<(((i)*2)+4))	/* access permissions */
#define MmuL1AP(v)	MmuAP(3, (v))
#define MmuL2AP(v)	MmuAP(3, (v))|MmuAP(2, (v))|MmuAP(1, (v))|MmuAP(0, (v))
#define MmuAPsro	0			/* supervisor rw */
#define MmuAPsrw	1			/* supervisor rw */
#define MmuAPuro	2			/* supervisor rw + user ro */
#define MmuAPurw	3			/* supervisor rw + user rw */
