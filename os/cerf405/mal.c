#include "u.h"
#include "lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"

/*
 * on the 405EP the MAL is used only by the Ethernet
 * but we keep it separate even so
 */

enum {
	Nrxchan=	2,
	Ntxchan=	4,
	Maxchan		= 4
};

enum {
	/* device control registers */
	Cfg=		0x180,	/* configuration register */
	Esr=		0x181,	/* error status register */
	Ier=		0x182,	/* interrupt enable register */
	Txcasr=	 0x184,	/* transmit channel active set register */
	Txcarr=	 0x185,	/* transmit channel active reset register */
	Txeobisr= 0x186,	/* transmit end of buffer interrupt status register */
	Txdeir=	 0x187,	/* transmit descriptor error interrupt register */
	Rxcasr=	 0x190,	/* receive channel active set register */
	Rxcarr= 	0x191,	/* receive channel active reset register */
	Rxeobisr=	 0x192,	/* receive channel descriptor error interrupt register */
	Rxdeir=	 0x193,	/* receive descriptor error interrupt register */
};

#define	TXCTPR(n)	(0x1A0+(n))	/* transmit channel table pointer register */
#define	RXCTPR(n)	(0x1C0+(n))	/* receive channel table pointer register */
#define	RCBS(n)	(0x1E0+(n))	/* receive channel buffer size register */

enum {
	/* configuration */
	CfgSr=		1<<31,	/* software reset */
	CfgPlbp0=	0<<22,	/* PLB priority (0=lowest) */
	CfgPlbp1=	1<<22,
	CfgPlbp2=	2<<22,
	CfgPlbp3=	3<<22,
	CfgGa=		1<<21,	/* guarded */
	CfgOa=		1<<20,	/* ordered */
	CfgPlble=		1<<19,	/* lock error */
	CfgPlbt_f=	0xF<<15,	/* latency timer field */
	CfgPlbt_s=	15,		/* latency timer (shift) */
	CfgPlbb=		1<<14,	/* burst enable */
	CfgOpbbl=	1<<7,	/* OPB locked */
	CfgOepie=	1<<2,	/* interrupt on every end of packet */
	CfgLea=		1<<1,	/* locked error active */
	CfgSd=		1<<0,	/* scroll to next packet on early termination */

	/* error status */
	EsrEvb=		1<<31,	/* error valid bit */
	EsrCid_f=		0x7F<<25,	/* field: channel ID causing lock error */
	EsrDe=		1<<20,	/* descriptor error */
	EsrOne=		1<<19,	/* OPB non-fullword error */
	EsrOte=		1<<18,	/* OPB timeout error */
	EsrOse=		1<<17,	/* OPB slave error */
	EsrPein=		1<<16,	/* PLB bus error indication */
	EsrDei=		1<<4,	/* descriptor error interrupt */
	EsrOnei=		1<<3,	/* OPB non-fulword error interrupt */
	EsrOtei=		1<<2,	/* OPB timeout error interrupt */
	EsrOsei=		1<<1,	/* OPB slave error interrupt */
	EsrPbei=		1<<0,	/* OPB bus error interrupt */

};

typedef struct Malmem Malmem;
struct Malmem {
	Lock;
	BD*	base;
	BD*	limit;
	BD*	avail;
};

static Malmem	malmem;

static Mal*	malchans[2][Maxchan];

static void
errorintr(Ureg*, void*)
{
	ulong esr, rxdeir, txdeir;

	/* mal de tête */
	esr = getdcr(Esr);
	txdeir = getdcr(Txdeir);
	rxdeir = getdcr(Rxdeir);
	iprint("mal: esr=%8.8lux txdeir=%8.8lux rxdeir=%8.8lux\n", esr, txdeir, rxdeir);
	putdcr(Rxdeir, rxdeir);
	putdcr(Txdeir, txdeir);
	putdcr(Esr, esr);
}

static void
scanintr(Ureg *ur, ulong ir, Mal *chans[])
{
	Mal *ml;
	int i;

	for(i=0; ir != 0 && i < Maxchan; i++)
		if(ir & IBIT(i)){
			ir &= ~IBIT(i);
			ml = chans[i];
			if(ml != nil && ml->interrupt != nil)
				ml->interrupt(ur, ml->arg);
			/* unexpected interrupt otherwise */
		}
}

static void
txinterrupt(Ureg *ur, void*)
{
	ulong ir;

	ir = getdcr(Txeobisr);
	putdcr(Txeobisr, ir);
	scanintr(ur, ir, malchans[1]);
}

static void
rxinterrupt(Ureg *ur, void*)
{
	ulong ir;

	ir = getdcr(Rxeobisr);
	putdcr(Rxeobisr, ir);
	scanintr(ur, ir, malchans[0]);
}

void
ioinit(void)
{
	int i;

	putdcr(Txcarr, ~0);
	putdcr(Rxcarr, ~0);

	/* reset */
	putdcr(Cfg, CfgSr);
	while(getdcr(Cfg) & CfgSr)
		;	/* at most one system clock */

	/* clear these out whilst we're at it */
	for(i=0; i<Nrxchan; i++){
		putdcr(RCBS(i), 0);
		putdcr(RXCTPR(i), 0);
	}
	for(i=0; i<Ntxchan; i++)
		putdcr(TXCTPR(i), 0);

	putdcr(Cfg, (0xF<<CfgPlbt_s)|CfgPlbb);	/* TO DO: check */

	/* Ier */
	intrenable(VectorMALSERR, errorintr, nil, BUSUNKNOWN, "malserr");
	intrenable(VectorMALTXDE, errorintr, nil, BUSUNKNOWN, "maltxde");
	intrenable(VectorMALRXDE, errorintr, nil, BUSUNKNOWN, "malrxde");
	intrenable(VectorMALTXEOB, txinterrupt, nil, BUSUNKNOWN, "maltxeob");
	intrenable(VectorMALRXEOB, rxinterrupt, nil, BUSUNKNOWN, "malrxeob");
	putdcr(Ier, EsrDei | EsrOnei | EsrOtei | EsrOsei | EsrPbei);
}

Mal*
malchannel(int n, int tx, void (*intr)(Ureg*, void*), void *arg)
{
	Mal *ml;

	if((ml = malchans[tx][n]) == nil){
		ml = malloc(sizeof(*m));
		malchans[tx][n] = ml;
	}
	ml->n = n;
	ml->tx = tx;
	ml->len = 1;
	ml->arg = arg;
	ml->interrupt = intr;
	return ml;
}

void
maltxreset(Mal *ml)
{
	putdcr(Txcarr, IBIT(ml->n));
}

void
maltxinit(Mal *ml, Ring *r)
{
	putdcr(TXCTPR(ml->n), PADDR(r->tdr));
}

void
maltxenable(Mal *ml)
{
	putdcr(Txcasr, getdcr(Txcasr) | IBIT(ml->n));
}

void
malrxreset(Mal *ml)
{
	putdcr(Rxcarr, IBIT(ml->n));
}

void
malrxinit(Mal *ml, Ring *r, ulong limit)
{
	putdcr(RXCTPR(ml->n), PADDR(r->rdr));
	putdcr(RCBS(ml->n), limit);
}

void
malrxenable(Mal *ml)
{
	putdcr(Rxcasr, getdcr(Rxcasr) | IBIT(ml->n));
}

/*
 * initialise receive and transmit buffer rings
 * to use both Emacs, or two channels per emac, we'll need
 * to allocate all rx descriptors at once, and all tx descriptors at once,
 * in a region where all addresses have the same bits 0-12(!);
 * see p 20-34. of the MAL chapter.
 *
 * the ring entries must be aligned on sizeof(BD) boundaries
 * rings must be uncached, and buffers must align with cache lines since the cache doesn't snoop
 *
 * thus, we initialise it once for all, then hand it out as requested.
 */
void
ioringreserve(int nrx, ulong nrb, int ntx, ulong ntb)
{
	ulong nb, nbd;

	lock(&malmem);
	if(malmem.base == nil){
		nbd = nrx*nrb + ntx*ntb;
		nb = mmumapsize(nbd*sizeof(BD));
		/*
		 * the data sheet says in the description of buffer tables that they must be on a 4k boundary,
		 * but the pointer register descriptions say 8 bytes; it seems to be the latter.
		 */
		malmem.base = mmucacheinhib(xspanalloc(nb, nb, 1<<19), nb);
		malmem.limit = malmem.base + nbd;
		malmem.avail = malmem.base;
		if((PADDR(malmem.base)&~0x7FFFF) != (PADDR(malmem.base)&~0x7FFFF))
			print("mal: trouble ahead?\n");
	}
	unlock(&malmem);
	if(malmem.base == nil)
		panic("ioringreserve");
}

BD*
bdalloc(ulong nd)
{
	BD *b;

	lock(&malmem);
	b = malmem.avail;
	if(b+nd > malmem.limit)
		b = nil;
	else
		malmem.avail = b+nd;
	unlock(&malmem);
	return b;
}

int
ioringinit(Ring* r, int nrdre, int ntdre)
{
	int i;

	/* buffers must align with cache lines since the cache doesn't snoop */
	r->nrdre = nrdre;
	if(r->rdr == nil)
		r->rdr = bdalloc(nrdre);
	if(r->rxb == nil)
		r->rxb = malloc(nrdre*sizeof(Block*));
	if(r->rdr == nil || r->rxb == nil)
		return -1;
	for(i = 0; i < nrdre; i++){
		r->rxb[i] = nil;
		r->rdr[i].length = 0;
		r->rdr[i].addr = 0;
		r->rdr[i].status = BDEmpty|BDInt;
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

void
dumpmal(void)
{
	int i;

	iprint("Cfg=%8.8lux\n", getdcr(Cfg));
	iprint("Esr=%8.8lux\n", getdcr(Esr));
	iprint("Ier=%8.8lux\n", getdcr(Ier));
	iprint("Txcasr=%8.8lux\n", getdcr(Txcasr));
	iprint("Txcarr=%8.8lux\n", getdcr(Txcarr));
	iprint("Txeobisr=%8.8lux\n", getdcr(Txeobisr));
	iprint("Txdeir=%8.8lux\n", getdcr(Txdeir));
	iprint("Rxcasr=%8.8lux\n", getdcr(Rxcasr));
	iprint("Rxcarr=%8.8lux\n", getdcr(Rxcarr));
	iprint("Rxeobisr=%8.8lux\n", getdcr(Rxeobisr));
	iprint("Rxdeir=%8.8lux\n", getdcr(Rxdeir));
	for(i=0; i<Nrxchan; i++)
		iprint("Rxctpr[%d]=%8.8lux Rcbs[%d]=%8.8lux\n", i, getdcr(RXCTPR(i)), i, getdcr(RCBS(i)));
	for(i=0;i<Ntxchan; i++)
		iprint("Txctpr[%d]=%8.8lux\n", i, getdcr(TXCTPR(i)));
}
