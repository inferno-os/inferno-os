#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"

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
 *
 * on the Xscale, X, C & B are interpreted as follows:
 * X = 0:
 *	C=0 B=0	uncached, unbuffered, stall until data access complete
 *	C=0 B=1	uncached, buffered (different from Strongarm)
 *	C=1 B=0	cached, buffered, write through, read allocate (different from Strongarm)
 *	C=1 B=1	cached, buffered, write back, read allocate
 * X = 1:
 *	C=0 B=0	undefined
 *	C=0 B=1	uncached, buffered, writes will not coalesce
 *	C=1 B=0	mini data cache (policy set by auxiliary control reg)
 *	C=1 B=1	cached, buffered, write back, read/write allocate
 * and the i-cache uses only the C bit (cached if non-zero).
 */
#define TTB(pa)	((pa) & ~0x3FFF)	/* translation table base */
#define L1x(pa)	(((pa)>>20) & 0xFFF)	/* L1 table index */
#define PTBA(pa)	((pa) & ~0x3FF)		/* page table base address */
#define L2x(pa)	(((pa)>>12) & 0xFF)	/* L2 table index */
#define PBA(pa)	((pa) & ~0xFFF)		/* page base address */
#define SBA(pa)	((pa) & ~0xFFFFF)	/* section base address */

enum {
	/* sizes */
	Section=	1<<20,
	LargePage=	1<<16,
	SmallPage=	1<<12,
	EsmallPage=	1<<10,
	SectionPages = Section/SmallPage,
	PtAlign = 1<<10,

	/* L1 descriptor format */
	L1type= 	3<<0,	/* mask for type */
	L1page= 	1<<0,		/* descriptor is for L2 pages */
	L1section= 2<<0,			/* descriptor is for section */
	L1fpage=	3<<0,	/* descriptor is for fine (1k) L2 pages */
	L1buffered=	1<<2,
	L1cached=	1<<3,
	L1P=	1<<9,	/* application-processor specific */
	L1sectionX=	1<<12,	/* X bit in section descriptor */
	L1minicache=	(L1sectionX | L1cached),

	/* L2 descriptor format for coarse page table */
	L2type=	3<<0,	/* mask for type */
	L2invalid=	0<<0,
	L2large=	1<<0,			/* large page */
	L2small=	2<<0,			/* small page */
	L2esmall=	3<<0,	/* extended small page */
	L2buffered=	1<<2,
	L2cached=	1<<3,
	/* then access permissions */
	L2smallX=	1<<6,
	L2largeX=	1<<12,

	/* domains */
	Dnone=	0,
	Dclient=	1,
	Dmanager=	3,

	/* access permissions */
	APsro=	0,	/* supervisor ro if S|R */
	APsrw=	1,	/* supervisor rw */
	APuro=	2,	/* supervisor rw + user ro */
	APurw=	3,	/* supervisor rw + user rw */

	MINICACHED = 0x10000000,
};

#define L1dom(d)	(((d) & 0xF)<<5)	/* L1 domain */
#define AP(i, v)	((v)<<(((i)*2)+4))	/* access permissions */
#define L1AP(v)	AP(3, (v))
#define L2AP(v)	AP(3, (v))|AP(2, (v))|AP(1, (v))|AP(0, (v))

#define L1krw	(L1AP(APsrw) | L1dom(0))

/*
 * return physical address corresponding to a given virtual address,
 * or 0 if there is no such address
 */
ulong
va2pa(void *v)
{
	int idx;
	ulong pte, ste, *ttb;

	idx = L1x((ulong)v);
	ttb = (ulong*)KTTB;
	ste = ttb[idx];
	switch(ste & L1type) {
	case L1section:
		return SBA(ste)|((ulong)v & 0x000fffff);
	case L1page:
		pte = ((ulong *)PTBA(ste))[L2x((ulong)v)]; 
		switch(pte & 3) {
		case L2large:
			return (pte & 0xffff0000)|((ulong)v & 0x0000ffff);
		case L2small:
			return (pte & 0xfffff000)|((ulong)v & 0x00000fff);
		}
	}
	return 0;
}

/* for debugging */
void
prs(char *s)
{
	for(; *s; s++)
		uartputc(*s);
}

void
pr16(ulong n)
{
	int i, c;

	for(i=28; i>=0; i-=4){
		c = (n>>i) & 0xF;
		if(c >= 0 && c <= 9)
			c += '0';
		else
			c += 'A'-10;
		uartputc(c);
	}
}

void
xdelay(int n)
{
	int j;

	for(j=0; j<1000000/4; j++)
		n++;
	USED(n);
}

void*
mmuphysmap(ulong phys, ulong)
{
	ulong *ttb;
	void *va;

	ttb = (ulong*)KTTB;
	va = KADDR(phys);
	ttb[L1x((ulong)va)] = phys | L1krw | L1section;
	return va;
}

/*
 * Set a 1-1 map of virtual to physical memory, except:
 *	doubly-map page0 at the alternative interrupt vector address,
 * 	doubly-map physical memory at KZERO+256*MB as uncached but buffered,
 *	map flash to virtual space away from 0,
 *	disable access to 0 (nil pointers).
 *
 * Other section maps are added later as required by mmuphysmap.
 */
void
mmuinit(void)
{
	int i;
	ulong *ttb, *ptable, va;

	ttb = (ulong*)KTTB;
	for(i=0; i<L1x(0x10000000); i++)
		ttb[i] = 0;
	for(; i < 0x1000; i++)
		ttb[i] = (i<<20) | L1krw | L1section;

	/* cached dram at normal kernel addresses */
	for(va = KZERO; va < KZERO+64*MB; va += MB)
		ttb[L1x(va)] = va | L1krw | L1section | L1cached | L1buffered;

	/* aliases for uncached dram */
	for(i = 0; i < 64*MB; i += MB)
		ttb[L1x(UCDRAMZERO+i)] = (PHYSMEM0+i) | L1krw | L1section;

	/* TO DO: make the text read only */

	/* minicached region; used for frame buffer (if present) */
	if(0)
	for(va = KZERO; va < KZERO+64*MB; va += MB)
		ttb[L1x(va|MINICACHED)] = va | L1krw  | L1minicache | L1section;

	ttb[L1x(DCFADDR)] |= L1cached | L1buffered;	/* cached and buffered for cache writeback */

#ifdef NOTYET
	/* TO DO: mini cache writeback */
	ttb[L1x(MCFADDR)] |= L1minicache;	/* cached and unbuffered for minicache writeback */
#endif

	/* remap flash */
	for(i=0; i<32*MB; i+=MB)
		ttb[L1x(FLASHMEM+i)] = (PHYSFLASH0+i) | L1krw | L1section;	/* we'll make flash uncached for now */

	/*
	 * build page table for alternative vector page, mapping trap vectors in *page0
	 */
	ptable = xspanalloc(SectionPages*sizeof(*ptable), PtAlign, 0);
	ptable[L2x(AIVECADDR)] = PADDR(page0) | L2AP(APsrw) | L2cached | L2buffered | L2small;
	ttb[L1x(AIVECADDR)] = PADDR(ptable) | L1page;
	mmuputttb(KTTB);
	mmuputdac(Dclient);
	mmuenable(CpCaltivec | CpCIcache | CpCsystem | CpCwpd | CpCDcache | CpCmmu);
}

/*
 * flush data in a given address range to memory
 * and invalidate the region in the instruction cache.
 */
int
segflush(void *a, ulong n)
{
	dcflush(a, n);
	icflush(a, n);
	return 0;
}

#ifdef NOTYET
/*
 * map an address to cached but unbuffered memory
 * forcing load allocations to the mini data cache.
 * the address a must be in a region that is cache line aligned
 * with a length that is a multiple of the cache line size
 */
void *
minicached(void *a)
{
	if(conf.useminicache == 0)
		return a;
	/* must flush and invalidate any data lingering in main cache */
	dcflushall();
	minidcflush();
	dcinval();
	return (void*)((ulong)a | MINICACHED);
}
#endif
