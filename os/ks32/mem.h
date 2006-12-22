/*
 * Memory and machine-specific definitions.  Used in C and assembler.
 */

/*
 * Sizes
 */
#define _K_		1024			/* 2^10 -> Kilo */
#define _M_		1048576			/* 2^20 -> Mega */
#define _G_		1073741824		/* 2^30 -> Giga */
#define _T_		1099511627776UL		/* 2^40 -> Tera */
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
#define TIMER_HZ	50000000
#define MS2TMR(t)	((ulong)(((uvlong)(t)*TIMER_HZ)/1000))
#define US2TMR(t)	((ulong)(((uvlong)(t)*TIMER_HZ)/1000000))

/*
 *  Address spaces
 *
*/

#define KZERO		0x0
#define MACHADDR	((ulong)&Mach0)
/* #define MACHADDR	(KZERO+0x00002000)  /* should come from BootParam, */
					/* or be automatically allocated */
/* #define KTTB		(KZERO+0x00004000)  - comes from BootParam now */
#define KTZERO		bootparam->entry
#define KSTACK		8192			/* Size of kernel stack */

#include "armv7.h"
