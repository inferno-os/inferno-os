#include	"mem.h"
#define	MB	(1024*1024)

/*
 * TLB prototype entries, loaded once-for-all at startup,
 * remaining unchanged thereafter.
 * Limit the table size to ensure it fits in small TLBs.
 */
#define	TLBE(hi, lo)	WORD	$(hi);  WORD	$(lo)

TEXT	tlbtab(SB), $-4

	/* tlbhi tlblo */

	/* DRAM, 32MB */
	TLBE(KZERO|PHYSDRAM|TLB16MB|TLBVALID, PHYSDRAM|TLBZONE(0)|TLBWR|TLBEX)
	TLBE(KZERO|(PHYSDRAM+16*MB)|TLB16MB|TLBVALID, (PHYSDRAM+16*MB)|TLBZONE(0)|TLBWR|TLBEX)

	/* memory-mapped IO, 4K */
	TLBE(PHYSMMIO|TLB4K|TLBVALID, PHYSMMIO|TLBZONE(0)|TLBWR|TLBI|TLBG)

	/* NAND flash access (4K?) */
	TLBE(PHYSNAND|TLB4K|TLBVALID, PHYSNAND|TLBZONE(0)|TLBWR|TLBI|TLBG)

	/* NOR flash, 2MB */
	TLBE(PHYSFLASH|TLB1MB|TLBVALID, PHYSFLASH|TLBZONE(0)|TLBWR|TLBEX)
	TLBE((PHYSFLASH+MB)|TLB1MB|TLBVALID, (PHYSFLASH+MB)|TLBZONE(0)|TLBWR|TLBEX)

TEXT	tlbtabe(SB), $-4
	RETURN
