#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	"io.h"

enum {
	 /* DMA CSR bits */
	CSRrun=		1 << 0,
	CSRie=		1 << 1,
	CSRerror=	1 << 2,
	CSRdonea=	1 << 3,
	CSRstrta=	1 << 4,
	CSRdoneb=	1 << 5,
	CSRstrtb=	1 << 6,
	CSRbiu=		1 << 7,

	Ndma=	6,		/* number of dma channels */
};

/* DDAR configuration: DA 31:8, DS 3:0, data width, burst size */
#define	DMACFG(da, ds, dw, bs) (((da)<<8)|((ds)<<4)|((dw)<<3)|((bs)<<2))

static ulong dmaconfig[16] = {
[DmaUDC] 	DMACFG(0x80000A, 0, 0, 1),
[DmaUART0]	DMACFG(0x804005, 4, 0, 0),
[DmaHSSP]	DMACFG(0x81001B, 6, 0, 1),
[DmaUART1]	DMACFG(0x80C005, 6, 0, 0),
[DmaUART2]	DMACFG(0x814005, 8, 0, 0),
[DmaMCPaudio] DMACFG(0x818002, 10, 1, 1),
[DmaMCPtelecom] DMACFG(0x818003, 12, 1, 1),
[DmaSSP]		DMACFG(0x81C01B, 14, 1, 0),	/* see SSP description not DMA section for correct burst size */
};

struct Dma {
	int	chan;
	DmaReg*	reg;
	void	(*interrupt)(void*, ulong);
	void*	arg;
	Rendez	r;
	int	intrset;
};

static struct {
	Lock;
	int	avail;
	Dma	dma[Ndma];
} dmachans;

static	void	dmaintr(Ureg*, void*);

void
dmareset(void)
{
	int i;
	Dma *d;

	for(i=0; i<nelem(dmachans.dma); i++){
		dmachans.avail |= 1<<i;
		d = &dmachans.dma[i];
		d->chan = i;
		d->reg = DMAREG(i);
		d->reg->dcsr_c = 0xFF;
	}
	/* this is the place to mask off bits in avail corresponding to broken channels in old revisions */
}

/*
 * allocate a DMA channel, reset it, and configure it for the given device
 */
Dma*
dmasetup(int device, int direction, int bigend, void (*interrupt)(void*, ulong), void *arg)
{
	Dma *d;
	DmaReg *dr;
	ulong cfg;
	int i;
	char name[KNAMELEN];

	cfg = dmaconfig[device];
	if(cfg == 0){
		print("dmasetup: no device %d\n", device);
		return nil;
	}

	ilock(&dmachans);
	for(i=0; (dmachans.avail & (1<<i)) == 0; i++)
		if(i >= nelem(dmachans.dma)){
			iunlock(&dmachans);
			return nil;
		}
	dmachans.avail &= ~(1<<i);
	iunlock(&dmachans);

	d = &dmachans.dma[i];
	d->interrupt = interrupt;
	d->arg = arg;
	dr = d->reg;
	dr->dcsr_c = CSRrun | CSRie | CSRerror | CSRdonea | CSRstrta | CSRdoneb | CSRstrtb;
	dr->ddar = cfg | (direction<<4) | (bigend<<1);
	if(d->intrset == 0){
		d->intrset = 1;
		snprint(name, sizeof(name), "dma%d", i);
		intrenable(DMAbit(i), dmaintr, d, BusCPU, name);
	}
	return d;
}

void
dmafree(Dma *dma)
{
	dma->reg->dcsr_c = CSRrun | CSRie;
	ilock(&dmachans);
	dmachans.avail |= 1<<dma->chan;
	dma->interrupt = nil;
	iunlock(&dmachans);
}

/*
 * start dma on the given channel on one or two buffers,
 * each of which must adhere to DMA controller restrictions.
 * (eg, on some versions of the StrongArm it musn't span 256-byte boundaries).
 * virtual buffer addresses are assumed to refer to contiguous physical addresses.
 */
int
dmastart(Dma *dma, void *buf, int nbytes)
{
	ulong v, csr;
	DmaReg *dr;
	int b;

	dr = dma->reg;
	v = dr->dcsr;
	if((v & (CSRstrta|CSRstrtb|CSRrun)) == (CSRstrta|CSRstrtb|CSRrun))
		return 0;	/* fully occupied */

	dcflush(buf, nbytes);

	csr = CSRrun | CSRie;

	/* start first xfer with buffer B or A? */
	b = (v & CSRbiu) != 0 && (v & CSRstrtb) == 0 || (v & CSRstrta) != 0;
	if(b)
		csr |= CSRstrtb;
	else
		csr |= CSRstrta;

	if(v & csr & (CSRstrtb|CSRstrta))
		panic("dmasetup csr=%2.2lux %2.2lux", v, csr);

	 /* set first src/dst and size */
	dr->buf[b].start = (ulong)buf;
	dr->buf[b].count = nbytes;
	dr->dcsr_s = csr;
	return 1;
}

/*
 * stop dma on a channel
 */
void
dmastop(Dma *dma)
{
	// print("dmastop (was %ux)\n", dma->reg->dcsr);

	dma->reg->dcsr_c =	CSRrun |
					CSRie |
					CSRerror |
					CSRdonea |
					CSRstrta |
					CSRdoneb |
					CSRstrtb;
}

/*
 * return nonzero if there was a memory error during DMA,
 * and clear the error state
 */
int
dmaerror(Dma *dma)
{
	DmaReg *dr;
	ulong e;

	dr = dma->reg;
	e = dr->dcsr & CSRerror;
	dr->dcsr_c = e;
	return e;
}

/*
 * return nonzero if the DMA channel is not busy
 */
int
dmaidle(Dma *d)
{
	return (d->reg->dcsr & (CSRstrta|CSRstrtb)) == 0;
}

static int
dmaidlep(void *a)
{
	return dmaidle((Dma*)a);
}

void
dmawait(Dma *d)
{
	while(!dmaidle(d))
		sleep(&d->r, dmaidlep, d);
}

/*
 * this interface really only copes with one buffer at once
 */
static void
dmaintr(Ureg*, void *a)
{
	Dma *d;
	ulong s;

	d = (Dma*)a;
	s = d->reg->dcsr;
	if(s & CSRerror)
		iprint("DMA error, chan %d status #%2.2lux\n", d->chan, s);
	s &= (CSRdonea|CSRdoneb|CSRerror);
	d->reg->dcsr_c = s;
	if(d->interrupt != nil)
		d->interrupt(d->arg, s & (CSRdonea|CSRdoneb));
	wakeup(&d->r);
}
