#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"

typedef struct Ctx Ctx;
/*
 * software description of an MMU context
 */
struct Ctx
{
	Ctx	*prev;	/* less recently used */
	Ctx	*next;	/* more recently used */
	Proc	*proc;	/* process that owns this context */
	ushort	index;	/* which context this is */
};

ulong	*ioptes;	/* IO MMU's table (shared by all processors) */

/* offset of x into the three page table levels in a context */
#define AOFF(x) (((ulong)x)>>24)
#define BOFF(x)	((((ulong)x)>>18)&(64-1))
#define COFF(x)	((((ulong)x)>>12)&(64-1))
#define	ISPTAB(x) ((((ulong)x)&3) == PTPVALID)
#define	KPN(va) PPN(PADDR(va))

#define	NIOPTE	(DMASEGSIZE/BY2PG)

/*
 *  allocate kernel page map and enter one mapping.  Return
 *  address of the mapping.
 */
static ulong*
putkmmu(ulong virt, ulong phys, int level)
{
	ulong *a, *b, *c;


	a = &PPT(m->contexts[0])[AOFF(virt)];
	if(level > 1) {
		if(*a == 0){
			b = (ulong*)xspanalloc(64*sizeof(ulong),
					       64*sizeof(ulong), 0);
			*a = KPN(b) | PTPVALID;
		} else {
			if(!ISPTAB(*a))
				panic("putkmmu virt=%lux *a=%lux", virt, *a);
			b = PPT(*a);
		}
		b = &b[BOFF(virt)];
		if(level > 2) {
			if(*b == 0){
				c = (ulong*)xspanalloc(64*sizeof(ulong),
						       64*sizeof(ulong), 0);
				*b = KPN(c) | PTPVALID;
			} else {
				if(!ISPTAB(*b))
					panic("putkmmu virt=%lux *b=%lux",
					      virt, *b);
				c = PPT(*b);
			}
			c = &c[COFF(virt)];
			*c = phys;
			return c;
		} else {
			*b = phys;
			return b;
		}
	} else {
		*a = phys;
		return a;
	}
}

void
mmuinit(void)
{
	int i, n;
	ulong *a;

	m->contexts = (ulong*)xspanalloc(conf.ncontext*sizeof(ulong),
					 conf.ncontext*sizeof(ulong),
					 0);

	/*
	 * context 0 will have the prototype level 1 entries
	 */
	a = (ulong*)xspanalloc(256*sizeof(ulong), 256*sizeof(ulong), 0);

	m->contexts[0] = KPN(a) | PTPVALID;

	/*
	 * map all memory to KZERO
	 */
	n = 128*MB/BY2PG;

	 /* pages to first segment boundary */
	for(i=0; i<(256*1024/BY2PG); i++)
		putkmmu(KZERO|(i*BY2PG),
			PPN(i*BY2PG)|PTEKERNEL|PTEWRITE|PTEVALID|PTECACHE, 3);

	 /* segments to first 16Mb boundary */
	for(; i<(16*MB)/BY2PG; i += 64)
		putkmmu(KZERO|(i*BY2PG),
			PPN(i*BY2PG)|PTEKERNEL|PTEWRITE|PTEVALID|PTECACHE, 2);

	 /* 16 Mbyte regions to end */
	for(; i<n; i += 64*64)
		putkmmu(KZERO|(i*BY2PG),
			PPN(i*BY2PG)|PTEKERNEL|PTEWRITE|PTEVALID|PTECACHE, 1);

	/*
	 * allocate page table pages for IO mapping
	 */
	n = IOSEGSIZE/BY2PG;
	for(i=0; i<n; i++)
		putkmmu(IOSEGBASE+(i*BY2PG), 0, 3);

	/*
	 * load kernel context
	 */

	putrmmu(CTPR, PADDR(m->contexts)>>4);
	putrmmu(CXR, 0);
	flushtlb();

	ioptes = (ulong*)xspanalloc(NIOPTE*sizeof(ulong), DMASEGSIZE/1024, 0);
	putphys(IBAR, PADDR(ioptes)>>4);
	putphys(IOCR, (DMARANGE<<2)|1);	/* IO MMU enable */
}


void
flushicache(void)
{
	int i;
	ulong addr = 0;

	for(i=0;i<512;i++) {
		flushiline(addr);
		addr += 1<<5;
	}
}

void
flushdcache(void)
{
	int i;
	ulong addr = 0;

	for(i=0;i<512;i++) {
		flushdline(addr);
		addr += 1<<5;
	}
}

int
segflush(void *p, ulong l)
{
	USED(p,l);
	flushicache();
	return 0;
}

void
cacheinit(void)
{
	flushdcache();
	flushicache();
	setpcr(getpcr()|ENABCACHE);
}

typedef struct Mregion Mregion;
struct Mregion
{
	ulong	addr;
	long	size;
};

struct
{
	Mregion	io;
	Mregion	dma;
	Lock;
}kmapalloc = {
	{IOSEGBASE, IOSEGSIZE},
	{DMASEGBASE, DMASEGSIZE},
};

void
kmapinit(void)
{
}

KMap*
kmappa(ulong pa, ulong flag)
{
	ulong k;

	lock(&kmapalloc);
	k = kmapalloc.io.addr;
	kmapalloc.io.addr += BY2PG;
	if((kmapalloc.io.size -= BY2PG) < 0)
		panic("kmappa");
	putkmmu(k, PPN(pa)|PTEKERNEL|PTEWRITE|PTEVALID|flag, 3);
	flushtlbpage(k);
	unlock(&kmapalloc);
	return (KMap*)k;
}

ulong
kmapdma(ulong pa, ulong n)
{
	ulong va0, va;
	int i, j;
	

	lock(&kmapalloc);
	i = (n+(BY2PG-1))/BY2PG;
	va0 = kmapalloc.dma.addr;
	kmapalloc.dma.addr += i*BY2PG;
	if((kmapalloc.dma.size -= i*BY2PG) <= 0)
		panic("kmapdma");
	va = va0;
	for(j=0; j<i; j++) {
		putkmmu(va, PPN(pa)|PTEKERNEL|PTEVALID|PTEWRITE, 3);
		flushtlbpage(va);
		ioptes[(va>>PGSHIFT)&(NIOPTE-1)] = PPN(pa)|IOPTEVALID|IOPTEWRITE;
		va += BY2PG;
		pa += BY2PG;
	}
	unlock(&kmapalloc);
	return va0;
}

/*
 * map the frame buffer
 */
ulong
kmapsbus(int slot)
{
	int i, n;

	lock(&kmapalloc);
	n = FBSEGSIZE/BY2PG;
	for(i=0; i<n; i += 64*64)
		putkmmu(FBSEGBASE+(i*BY2PG), PPN(SBUS(slot)+(i*BY2PG))|PTEKERNEL|PTEWRITE|PTEVALID, 1);
	unlock(&kmapalloc);
	return FBSEGBASE;
}
