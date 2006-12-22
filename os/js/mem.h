/*
 * Memory and machine-specific definitions.  Used in C and assembler.
 */

/*
 * Sizes
 */

#define	BI2BY		8			/* bits per byte */
#define BI2WD		32			/* bits per word */
#define	BY2WD		4			/* bytes per word */
#define BY2V		8			/* bytes per double word */
#define	BY2PG		4096			/* bytes per page */
#define	WD2PG		(BY2PG/BY2WD)		/* words per page */
#define	PGSHIFT		12			/* log(BY2PG) */
#define ROUND(s, sz)	(((s)+(sz-1))&~(sz-1))
#define PGROUND(s)	ROUND(s,BY2PG)

#define	MAXMACH		1			/* max # cpus system can run */

/*
 * Time
 */
#define	HZ		50			/* clock frequency */
#define	MS2HZ		(1000/HZ)		/* millisec per clock tick */
#define	TK2SEC(t)	((t)/HZ)		/* ticks to seconds */
#define	MS2TK(t)	((((ulong)(t))*HZ)/1000)	/* milliseconds to ticks */

/*
 * PSR bits
 */
#define	PSREC		0x00002000
#define	PSREF		0x00001000
#define PSRSUPER	0x00000080
#define PSRPSUPER	0x00000040
#define	PSRET		0x00000020
#define SPL(n)		(n<<8)

/*
 * Magic registers
 */

#define	MACH		6		/* R6 is m-> */
#define	USER		5		/* R5 is u-> */

/*
 * Fundamental addresses
 */

#define	USERADDR	0xE0000000
#define	UREGADDR	(USERADDR+BY2PG-((32+6)*BY2WD))
#define	BOOTSTACK	(KTZERO-0*BY2PG)
#define	TRAPS		(KTZERO-2*BY2PG)

/*
 * Reference MMU registers (ASI 4)
 */
#define	PCR		0x000
#define	CTPR		0x100
#define	CXR		0x200
#define	SFSR		0x300
#define	SFAR		0x400

/*
 * Processor Control Register
 */
#define	ITBRDISABLE	(1<<16)
#define	BOOTMODE	(1<<14)	/* `must be cleared for normal operation' */
#define	MEMPCHECK	(1<<12)	/* check parity */
#define	ENABCACHE	(3<<8)	/* I & D caches */
#define	NOFAULT		(1<<1)	/* no fault */

/*
 * special MMU regions
 *	DMA segment for SBus DMA mapping via I/O MMU (hardware fixes location)
 *	the frame buffer is mapped as one MMU region (16 Mbytes)
 *	IO segments for device register pages etc.
 */
#define	DMARANGE	0
#define	DMASEGSIZE	((16*MB)<<DMARANGE)
#define	DMASEGBASE	(0 - DMASEGSIZE)
#define	FBSEGSIZE	(1*(16*MB))	 /* multiples of 16*MB */
#define	FBSEGBASE	(DMASEGBASE - DMASEGSIZE)
#define	IOSEGSIZE	(16*MB)
#define	IOSEGBASE	(FBSEGBASE - IOSEGSIZE)

/*
 * MMU entries
 */
#define	PTPVALID	1	/* page table pointer */
#define	PTEVALID	2	/* page table entry */
#define	PTERONLY	(2<<2)	/* read/execute */
#define	PTEWRITE	(3<<2)	/* read/write/execute */
#define	PTEKERNEL	(4<<2)	/* execute only */
#define	PTENOCACHE	(0<<7)
#define	PTECACHE	(1<<7)
#define	PTEACCESS	(1<<5)
#define	PTEMODIFY	(1<<6)
#define	PTEMAINMEM	0
#define	PTEIO		0
#define PTEPROBEMEM	(PTEVALID|PTEKERNEL|PTENOCACHE|PTEWRITE|PTEMAINMEM)
#define PTEUNCACHED	PTEACCESS	/* use as software flag for putmmu */

#define	NTLBPID		64	/* limited by microsparc hardware contexts */

#define PTEMAPMEM	(1024*1024)	
#define	PTEPERTAB	(PTEMAPMEM/BY2PG)
#define SEGMAPSIZE	128

#define	INVALIDPTE	0
#define	PPN(pa)		(((ulong)(pa)>>4)&0x7FFFFF0)
#define	PPT(pn)		((ulong*)KADDR((((ulong)(pn)&~0xF)<<4)))

/*
 * Virtual addresses
 */
#define	VTAG(va)	((va>>22)&0x03F)
#define	VPN(va)		((va>>13)&0x1FF)

/*
 * Address spaces
 */
#define	KZERO	0xE0000000		/* base of kernel address space */
#define	KTZERO	(KZERO+4*BY2PG)		/* first address in kernel text */
#define KSTACK	8192			/* size of kernel stack */

#define	MACHSIZE	4096

/*
 * control registers in physical address space (ASI 20)
 */
#define	IOCR		0x10000000	/* IO MMU control register */
#define	IBAR		0x10000004	/* IO MMU page table base address */
#define	AFR		0x10000018	/* address flush register */
#define	AFSR		0x10001000	/* asynch fault status */
#define	AFAR		0x10001004	/* asynch fault address */
#define	SSCR(i)		(0x10001010+(i)*4)	/* Sbus slot i config register */
#define	MFSR		0x10001020	/* memory fault status register */
#define	MFAR		0x10001024	/* memory fault address register */
#define	MID		0x10002000	/* sbus arbitration enable */

#define	SYSCTL		0x71F00000	/* system control & reset register */
#define	PROCINTCLR	0x71E00004	/* clear pending processor interrupts */

/*
 * IO MMU page table entry
 */
#define	IOPTEVALID	(1<<1)
#define	IOPTEWRITE	(1<<2)
