#include	"mem.h"
#define	MB	(1024*1024)

/*
 * TLB prototype entries, loaded once-for-all at startup,
 * remaining unchanged thereafter.
 * Limit the table to at most 8 entries to ensure
 * it works on the 823 (other 8xx processors allow up to 32 TLB entries).
 */
#define	TLBE(epn,rpn,twc)	WORD	$(epn);  WORD	$(twc); WORD	$(rpn)

TEXT	tlbtab(SB), $-4

	/* epn, rpn, twc */
	TLBE(KZERO|PHYSDRAM|TLBVALID, PHYSDRAM|PTEWRITE|PTELPS|PTESH|PTEVALID, PTE8MB|PTEVALID)	/* DRAM, 8M */
	TLBE(KZERO|(PHYSDRAM+8*MB)|TLBVALID, (PHYSDRAM+8*MB)|PTEWRITE|PTELPS|PTESH|PTEVALID, PTE8MB|PTEVALID)	/* DRAM, 8M */
	TLBE(KZERO|PHYSIMM|TLBVALID, PHYSIMM|PTEWRITE|PTELPS|PTESH|PTECI|PTEVALID, PTE512K|PTEVALID)	/* IMMR, 512K (includes FPGA control and clock synth) */
	TLBE(KZERO|PHYSFLASH|TLBVALID, PHYSFLASH|PTEWRITE|PTELPS|PTESH|PTECI|PTEVALID, PTE8MB|PTEWT|PTEVALID)	/* Flash, 8M */
	TLBE(KZERO|FPGAMEM|TLBVALID, FPGAMEM|PTEWRITE|PTELPS|PTESH|PTECI|PTEVALID, PTE8MB|PTEG|PTEVALID)	/* FPGA mem, 8M */
TEXT	tlbtabe(SB), $-4
	RETURN
