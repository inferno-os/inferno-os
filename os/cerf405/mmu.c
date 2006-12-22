#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"

extern	ulong	tlbtab[], tlbtabe[];
static	int	tlbx;	/* index of next free entry in TLB */

enum
{
	/* on-chip memory dcr */
	Isarc=	0x018,	/* instruction-side address range compare */
	Iscntl=	0x019,	/* instruction-side control register */
	  Isen=		1<<31,	/* enable */
	Dsarc=	0x01A,	/* data-side address range compare register */
	Dscntl=	0x01B,	/* data-side control register */
	  Dsen=		1<<31,	/* enable */
	  Dof=		1<<30,	/* must be one (p. 5-7) */
};

void
mmuinit(void)
{
	int i;

	/*
	 * the l.s initial TLB settings do nearly all that is needed initially.
	 * clear invalid entries (just for clarity) and record the address
	 * of the first available
 	 */
	tlbx = -1;
	for(i = 0; i < 64; i++)
		if((tlbrehi(i) & TLBVALID) == 0){
			if(tlbx < 0)
				tlbx = i;
			tlbwelo(i, 0);
			tlbwehi(i, 0);
		}

	iprint("ccr0=%8.8lux\n", getccr0());

	/*
	 * set OCM mapping, assuming:
	 *	caches were invalidated earlier;
	 *	and we aren't currently using it
	 * must also set a tlb entry that validates the virtual address but
	 * the translation is not used (see p. 5-2)
	 */
	putdcr(Isarc, OCMZERO);
	putdcr(Dsarc, OCMZERO);
	putdcr(Iscntl, Isen);
	putdcr(Iscntl, Dsen|Dof);
	tlbwelo(tlbx, OCMZERO|TLBZONE(0)|TLBWR|TLBEX|TLBI);
	tlbwehi(tlbx, OCMZERO|TLB4K|TLBVALID);
	tlbx++;
}

int
segflush(void *a, ulong n)
{
	/* flush dcache then invalidate icache */
	dcflush(a, n);
	icflush(a, n);
	return 0;
}

/*
 * return required size and alignment to map n bytes in a tlb entry
 */
ulong
mmumapsize(ulong n)
{
	ulong size;
	int i;

	size = 1024;
	for(i = 0; i < 8 && size < n; i++)
		size <<= 2;
	return size;
}

/*
 * map a physical addresses at pa to va, with the given attributes.
 * the virtual address must not be mapped already.
 * if va is nil, map it at pa in virtual space.
 */
void*
kmapphys(void *va, ulong pa, ulong nb, ulong attr, ulong le)
{
	int s, i;
	ulong size;

	if(va == nil)
		va = (void*)pa;	/* simplest is to use a 1-1 map */
	size = 1024;
	for(i = 0; i < 8 && size < nb; i++)
		size <<= 2;
	if(i >= 8)
		return nil;
	s = splhi();
	tlbwelo(tlbx, pa | TLBZONE(0) | attr);
	tlbwehi(tlbx, (ulong)va | (i<<7) | TLBVALID | le);
	tlbx++;
	splx(s);
	return va;
}

/*
 * return an uncached alias for the memory at a
 */
void*
mmucacheinhib(void *a, ulong nb)
{
	ulong p;

	if(a == nil)
		return nil;
	dcflush(a, nb);
	p = PADDR(a);
	return kmapphys((void*)(KSEG1|p), p, nb, TLBWR | TLBI | TLBG, 0);
}
