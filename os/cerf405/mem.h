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
#define	CACHELINELOG	5
#define CACHELINESZ	(1<<CACHELINELOG)
#define	CACHESIZE	16384
#define	CACHEWAYSIZE	(CACHESIZE/2)	/* 2-way set associative */

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
 * 4xx MSR bits
 */

#define	MSR_WE	0x40000	/* wait state enable */
#define	MSR_CE	0x20000	/* critical interrupt enable */
#define	MSR_EE	0x08000	/* enable external/decrementer interrupts */
#define	MSR_PR	0x04000	/* =1, user mode */
#define	MSR_ME	0x01000	/* enable machine check exceptions */
#define	MSR_DWE	0x00400	/* debug wait enable */
#define	MSR_DE	0x00200	/* debug interrupts enable */
#define	MSR_IR	0x00020	/* enable instruction address translation */
#define	MSR_DR	0x00010	/* enable data address translation */

#define	KMSR	(MSR_ME)
#define	UMSR	(MSR_PR|MSR_DE|MSR_CE|MSR_EE|MSR_IR|MSR_DR)

/*
 * Magic registers
 */

#define	MACH	30		/* R30 is m-> */
#define	USER		29		/* R29 is up-> */

/*
 * Fundamental addresses
 */

#define	UREGSIZE	((8+32)*4)

/*
 * MMU
 */

/* TLBHI */
#define	TLBEPN(x)	((x) & ~0x3FF)
#define	TLB1K		(0<<7)
#define	TLB4K		(1<<7)
#define	TLB16K		(2<<7)
#define	TLB64K		(3<<7)
#define	TLB256K		(4<<7)
#define	TLB1MB		(5<<7)
#define	TLB4MB		(6<<7)
#define	TLB16MB		(7<<7)
#define	TLBVALID		(1<<6)
#define	TLBLE		(1<<5)	/* little-endian */
#define	TLBU0		(1<<4)	/* user-defined attribute */

/* TLBLO */
#define	TLBRPN(x)	((x) & ~0x3FF)
#define	TLBEX		(1<<9)	/* execute enable */
#define	TLBWR		(1<<8)	/* write enable */
#define	TLBZONE(x)	((x)<<4)
#define	TLBW		(1<<3)	/* write-through */
#define	TLBI			(1<<2)	/* cache inhibit */
#define	TLBM		(1<<1)	/* memory coherent */
#define	TLBG		(1<<0)	/* guarded */

/*
 * Address spaces
 */

#define	KUSEG	0x00000000
#define	KSEG0	0x20000000
#define	KSEG1	0x60000000	/* uncached alias for KSEG0 */
#define	KSEGM	0xE0000000	/* mask to check which seg */

#define	KZERO	KSEG0			/* base of kernel address space */
#define	KTZERO	(KZERO+0x3000)	/* first address in kernel text */
#define	KSTACK	8192	/* Size of kernel stack */

#define	OCMZERO	0x40000000	/* on-chip memory (virtual and physical--see p 5-1) */

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
/* 0x08 (fpu) not used */
/* 0x09 (dec) not used */
#define	CSYSCALL 0x0C
/* 0x0D (trace) not used */
/* 0x0E (fpa) not used */
#define	CPIT		0x10
/* FIT is 0x1010 */
/* WDT is 0x1020 */
#define	CDMISS	0x11
#define	CIMISS	0x12
#define	CDEBUG	0x20

/*
 * exception syndrome register
 */
#define	ESR_MCI	0x80000000	/* instruction machine check */
#define	ESR_PIL	0x08000000	/* program interrupt: illegal instruction */
#define	ESR_PPR	0x04000000	/* program interrupt: privileged */
#define	ESR_PTR	0x02000000	/* program intterupt: trap with successful compare */
#define	ESR_DST	0x00800000	/* data storage interrupt: store fault */
#define	ESR_DIZ	0x00400000	/* data/instruction storage interrupt: zone fault */
#define	ESR_U0F	0x00008000	/* data storage interrupt: u0 fault */

#include	"physmem.h"

/* cerf-cube specific */
#define	PHYSDRAM	0
#define	PHYSFLASH	0xFFE00000
#define	FLASHSIZE	0x200000
#define	PHYSNAND	0x60000000
