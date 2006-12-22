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
 * C & B are interpreted as follows:
 *	C=0 B=0	uncached, unbuffered, stall until data access complete
 *	C=0 B=1	uncached, buffered
 *	C=1 B=0	write-through cachable
 *	C=1 B=1	write-back cachable
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
	L1mbo=		1<<4,	/* must be one */

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
	serialputs(s, strlen(s));
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
		serialputc(c);
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
mmuphysmap(void *va, ulong pa, ulong nbytes)
{
	ulong *ttb;
	ulong p, o;

	if(va == nil)
		va = KADDR(pa);
	p = (ulong)va;
	if((pa|p) & (Section-1))
		panic("kmapphys");
	ttb = (ulong*)KTTB;
	nbytes = (nbytes+Section-1)&~(Section-1);
	for(o = 0; o < nbytes; o += Section)
		ttb[L1x(p+o)] = (pa+o) | (1<<4) | L1krw | L1section;
	return va;
}

void*
mmukaddr(ulong pa)
{
	if(pa >= PHYSDRAM0 && pa < conf.topofmem)
		return (void*)(KZERO+(pa-PHYSDRAM0));
	return (void*)pa;
}

/*
 * Set a 1-1 map of virtual to physical memory, except:
 *	kernel is mapped to KZERO
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
	ulong *ttb, *ptable;

	ttb = (ulong*)KTTB;
	memset(ttb, 0, 16384);

	/* assume flash is first in special physical space */
	for(i = L1x(PHYSFLASH0); i < 0x1000; i++)
		ttb[i] = (i<<20) | L1krw | (1<<4) | L1section;

	/* cached dram at normal kernel addresses */
	for(i = 0; i < 32*MB; i += MB)
		ttb[L1x(KZERO+i)] = (PHYSDRAM0+i) | (1<<4) | L1krw | L1section | L1cached | L1buffered;

	/* aliases for uncached dram */
	for(i = 0; i < 64*MB; i += MB)
		ttb[L1x(UCDRAMZERO+i)] = (PHYSDRAM0+i) | L1krw | (1<<4) | L1section;

	/* TO DO: make the text read only */

	/* remap flash */
	for(i=0; i<8*MB; i+=MB)
		ttb[L1x(FLASHMEM+i)] = (PHYSFLASH0+i) | L1krw | (1<<4) | L1section;	/* we'll make flash uncached for now */

	/*
	 * build page table for alternative vector page, mapping trap vectors in *page0
	 */
	ptable = xspanalloc(SectionPages*sizeof(*ptable), PtAlign, 0);
	ptable[L2x(AIVECADDR)] = PADDR(page0) | L2AP(APsrw) | L2cached | L2buffered | L2small;
	ttb[L1x(AIVECADDR)] = PADDR(ptable) | (1<<4) | L1page;

	mmuputttb(KTTB & ~KZERO);
	mmuputdac(Dclient);
	mmuputctl(mmugetctl() | CpCaltivec | CpCIcache | CpCsystem | CpCwpd | CpCDcache | CpCmmu);
	tlbinvalidateall();
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

/*
 * return an uncached alias for the memory at a
 */
void*
mmucacheinhib(void *a, ulong nb)
{
	ulong p;

	if(a == nil)
		return nil;
	p = PADDR(a);
	if(p & (CACHELINESZ-1))
		panic("mmucacheinhib");
	dcflush(a, nb);
	return (void*)(UCDRAMZERO|PADDR(a));
}
