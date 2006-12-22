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
#define	CACHELINELOG	4
#define CACHELINESZ	(1<<CACHELINELOG)

#define	MAXMACH		1			/* max # cpus system can run */
#define	MACHSIZE	BY2PG

/*
 * Time
 */
#define HZ		100			/* clock frequency */
#define	MS2HZ		(1000/HZ)		/* millisec per clock tick */
#define	TK2SEC(t)	((t)/HZ)		/* ticks to seconds */
#define	MS2TK(t)	((t)/MS2HZ)		/* milliseconds to ticks */
#define	MHz	1000000

/*
 * MSR bits
 */

#define	POW	0x40000	/* enable power mgmt */
#define	TGPR	0x20000	/* GPR0-3 remapped; 603/603e specific */
#define	ILE	0x10000	/* interrupts little endian */
#define	EE	0x08000	/* enable external/decrementer interrupts */
#define	PR	0x04000	/* =1, user mode */
#define	FPE	0x02000	/* enable floating point */
#define	ME	0x01000	/* enable machine check exceptions */
#define	FE0	0x00800
#define	SE	0x00400	/* single-step trace */
#define	BE	0x00200	/* branch trace */
#define	FE1	0x00100
#define	MSR_IP	0x00040	/* =0, vector to nnnnn; =1, vector to FFFnnnnn */
#define	IR	0x00020	/* enable instruction address translation */
#define	DR	0x00010	/* enable data address translation */
#define	RI	0x00002	/* exception is recoverable */
#define	LE	0x00001	/* little endian mode */

#define	KMSR	(ME|FE0|FE1|FPE)
#define	UMSR	(KMSR|PR|EE|IR|DR)

/*
 * Magic registers
 */

#define	MACH		30		/* R30 is m-> */
#define	USER		29		/* R29 is up-> */
#define	IOMEMR		28		/* R28 will be iomem-> */

/*
 * Fundamental addresses
 */

#define	UREGSIZE	((8+32)*4)

/*
 * MMU
 */

/* L1 table entry and Mx_TWC flags */
#define PTEVALID	(1<<0)
#define PTEWT		(1<<1)	/* write through */
#define PTE4K		(0<<2)
#define PTE512K	(1<<2)
#define PTE8MB	(3<<2)
#define PTEG		(1<<4)	/* guarded */

/* L2 table entry and Mx_RPN flags (also PTEVALID) */
#define PTECI		(1<<1)	/*  cache inhibit */
#define PTESH		(1<<2)	/* page is shared; ASID ignored */
#define PTELPS		(1<<3)	/* large page size */
#define PTEWRITE	0x9F0

/* TLB and MxEPN flag */
#define	TLBVALID	(1<<9)

/*
 * Address spaces
 */

#define	KUSEG	0x00000000
#define KSEG0	0x20000000
#define	KSEGM	0xE0000000	/* mask to check which seg */

#define	KZERO	KSEG0			/* base of kernel address space */
#define	KTZERO	(KZERO+0x3000)	/* first address in kernel text */
#define	KSTACK	8192	/* Size of kernel stack */

#define	CONFADDR	(KZERO|0x200000)	/* where qboot leaves configuration info */

/*
 * Exception codes (trap vectors)
 */
#define	CRESET	0x01
#define	CMCHECK 0x02
#define	CDSI	0x03
#define	CISI	0x04
#define	CEI	0x05
#define	CALIGN	0x06
#define	CPROG	0x07
#define	CFPU	0x08
#define	CDEC	0x09
#define	CSYSCALL 0x0C
#define	CTRACE	0x0D
#define	CFPA	0x0E
/* rest are power-implementation dependent (8xx) */
#define	CEMU	0x10
#define	CIMISS	0x11
#define	CDMISS	0x12
#define	CITLBE	0x13
#define	CDTLBE	0x14
#define	CDBREAK	0x1C
#define	CIBREAK	0x1D
#define	CPBREAK	0x1E
#define	CDPORT	0x1F

/*
 * MPC8xx physical addresses
 */

/* those encouraged by rpx lite */
#define	PHYSDRAM	0x00000000
#define	PHYSNVRAM	0xFA000000
#define	PHYSIMM	0xFA200000
#define	PHYSBCSR	0xFA400000
#define	PHYSFLASH	0xFE000000

/* remaining ones are our choice */
#define	PHYSPCMCIA	0x04000000
#define	PCMCIALEN	(8*MB)	/* chosen to allow mapping by single TLB entry */
#define	ISAIO	(KZERO|PHYSPCMCIA)	/* for inb.s */

/*
 * MPC8xx dual-ported CPM memory physical addresses
 */
#define	PHYSDPRAM	(PHYSIMM+0x2000)
#define	DPLEN1	0x200
#define	DPLEN2	0x400
#define	DPLEN3	0x800
#define	DPBASE	(PHYSDPRAM+DPLEN1)

#define KEEP_ALIVE_KEY 0x55ccaa33	/* clock and rtc register key */
