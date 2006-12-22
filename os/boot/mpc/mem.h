/*
 * Memory and machine-specific definitions.  Used in C and assembler.
 */

/*
 * Sizes
 */
#define	BI2BY		8			/* bits per byte */
#define BI2WD		32			/* bits per word */
#define	BY2WD		4			/* bytes per word */
#define	BY2PG		4096			/* bytes per page */
#define	WD2PG		(BY2PG/BY2WD)		/* words per page */
#define	PGSHIFT		12			/* log(BY2PG) */
#define PGROUND(s)	(((s)+(BY2PG-1))&~(BY2PG-1))

#define	MAXMACH		1			/* max # cpus system can run */
#define	CACHELINELOG	4
#define CACHELINESZ	(1<<CACHELINELOG)

/*
 * Time
 */
#define	HZ		(50)				/* clock frequency */
#define	MS2HZ		(1000/HZ)			/* millisec per clock tick */
#define	TK2SEC(t)	((t)/HZ)			/* ticks to seconds */
#define	TK2MS(t)	((((ulong)(t))*1000)/HZ)	/* ticks to milliseconds */
#define	MS2TK(t)	((((ulong)(t))*HZ)/1000)	/* milliseconds to ticks */
#define	MHz	1000000

/*
 * Fundamental values
 */

#define	KZERO	0	/* bootstrap runs in real mode */
#define	MACHSIZE	4096

/*
 *  physical MMU
 */
#define KSEG0	0x20000000
#define	KSEGM	0xE0000000	/* mask to check which seg */

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
#define	IP	0x00040	/* =0, vector to nnnnn; =1, vector to FFFnnnnn */
#define	IR	0x00020	/* enable instruction address translation */
#define	DR	0x00010	/* enable data address translation */
#define	RI	0x00002	/* exception is recoverable */
#define	LE	0x00001	/* little endian mode */

#define	KMSR	(ME|FE0|FE1|FPE)
#define	UMSR	(KMSR|PR|EE|IR|DR)

/*
 * MPC82x addresses; mpc8bug is happy with these
 */
#define	BCSRMEM	0x02100000
#define	INTMEM	0x02200000
#define	FLASHMEM	0x02800000
#define	SDRAMMEM	0x03000000

#define	DPRAM	(INTMEM+0x2000)
#define	DPLEN1	0x400
#define	DPLEN2	0x200
#define	DPLEN3	0x100
#define	DPBASE	(DPRAM+DPLEN1)

#define	SCC1P	(INTMEM+0x3C00)
#define	I2CP	(INTMEM+0x3C80)
#define	MISCP	(INTMEM+0x3CB0)
#define	IDMA1P	(INTMEM+0x3CC0)
#define	SCC2P	(INTMEM+0x3D00)
#define	SCC3P	(INTMEM+0x3E00)
#define	SCC4P	(INTMEM+0x3F00)
#define	SPIP	(INTMEM+0x3D80)
#define	TIMERP	(INTMEM+0x3DB0)
#define	SMC1P	(INTMEM+0x3E80)
#define	DSP1P	(INTMEM+0x3EC0)
#define	SMC2P	(INTMEM+0x3F80)
#define	DSP2P	(INTMEM+0x3FC0)

#define KEEP_ALIVE_KEY 0x55ccaa33	/* clock and rtc register key */
