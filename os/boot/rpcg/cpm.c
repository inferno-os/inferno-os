#include "u.h"
#include "lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"

enum {
	BDSIZE=	1024,	/* TO DO: check this */
};

static	Map	bdmapv[BDSIZE/sizeof(BD)];
static	RMap	bdmap = {"buffer descriptors"};

void
cpminit(void)
{
	IMM *io;

	io = m->iomem;
	io->sdcr = 1;
	io->lccr &= ~1;	/* disable LCD */
	io->pcint = 0;	/* disable all port C interrupts */
	io->pcso = 0;
	io->pcdir =0;
	io->pcpar = 0;
	io->pcdat = 0;
	io->papar = 0;
	io->padir = 0;
	io->paodr = 0;
	io->padat = 0;
	io->pbpar = 0;
	io->pbdir = 0;
	io->pbodr = 0;
	io->pbdat = 0;
	eieio();

	for(io->cpcr = 0x8001; io->cpcr & 1;)	/* reset all CPM channels */
		eieio();

	mapinit(&bdmap, bdmapv, sizeof(bdmapv));
	mapfree(&bdmap, DPBASE, BDSIZE);
}

void
cpmop(int op, int cno, int param)
{
	IMM *io;
	int s;

	s = splhi();
	io = m->iomem;
	eieio();
	while(io->cpcr & 1)
		eieio();
	io->cpcr = (op<<8)|(cno<<4)|(param<<1)|1;
	eieio();
	while(io->cpcr & 1)
		eieio();
	splx(s);
}

/*
 * connect SCCx clocks in NSMI mode (x=1 for USB)
 */
void
sccnmsi(int x, int rcs, int tcs)
{
	IMM *io;
	ulong v;
	int sh;

	sh = (x-1)*8;	/* each SCCx field in sicr is 8 bits */
	v = (((rcs&7)<<3) | (tcs&7)) << sh;
	io = ioplock();
	io->sicr = (io->sicr & ~(0xFF<<sh)) | v;
	iopunlock();
}

void
scc2stop(void)
{
	SCC *scc;

	scc = IOREGS(0xA20, SCC);
	if(scc->gsmrl & (3<<4)){
		cpmop(GracefulStopTx, SCC2ID, 0);
		cpmop(CloseRxBD, SCC2ID, 0);
		delay(1);
		scc->gsmrl &= ~(3<<4);	/* disable current use */
		archetherdisable(SCC2ID);
	}
}

BD *
bdalloc(int n)
{
	ulong a;

	a = mapalloc(&bdmap, 0, n*sizeof(BD), 0);
	if(a == 0)
		panic("bdalloc");
	return KADDR(a);
}

void
bdfree(BD *b, int n)
{
	if(b){
		eieio();
		mapfree(&bdmap, PADDR(b), n*sizeof(BD));
	}
}

/*
 * initialise receive and transmit buffer rings.
 */
int
ioringinit(Ring* r, int nrdre, int ntdre, int bufsize)
{
	int i, x;

	/* the ring entries must be aligned on sizeof(BD) boundaries */
	r->nrdre = nrdre;
	if(r->rdr == nil)
		r->rdr = bdalloc(nrdre);
	/* the buffer size must align with cache lines since the cache doesn't snoop */
	bufsize = (bufsize+CACHELINESZ-1)&~(CACHELINESZ-1);
	if(r->rrb == nil)
		r->rrb = malloc(nrdre*bufsize);
	if(r->rdr == nil || r->rrb == nil)
		return -1;
	dcflush(r->rrb, nrdre*bufsize);
	x = PADDR(r->rrb);
	for(i = 0; i < nrdre; i++){
		r->rdr[i].length = 0;
		r->rdr[i].addr = x;
		r->rdr[i].status = BDEmpty|BDInt;
		x += bufsize;
	}
	r->rdr[i-1].status |= BDWrap;
	r->rdrx = 0;

	r->ntdre = ntdre;
	if(r->tdr == nil)
		r->tdr = bdalloc(ntdre);
	if(r->txb == nil)
		r->txb = malloc(ntdre*sizeof(Block*));
	if(r->tdr == nil || r->txb == nil)
		return -1;
	for(i = 0; i < ntdre; i++){
		r->txb[i] = nil;
		r->tdr[i].addr = 0;
		r->tdr[i].length = 0;
		r->tdr[i].status = 0;
	}
	r->tdr[i-1].status |= BDWrap;
	r->tdrh = 0;
	r->tdri = 0;
	r->ntq = 0;
	return 0;
}
