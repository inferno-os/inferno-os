#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	"io.h"

#define	DMAREGS	((Dmaregs*)PHYSDMA)
typedef struct Dmadesc Dmadesc;
typedef struct Dmaregs Dmaregs;

struct Dmadesc {
	ulong	ddadr;	/* next descriptor address (0 mod 16) */
	ulong	dsadr;	/* source address (0 mod 8 if external, 0 mod 4 internal) */
	ulong	dtadr;	/* target address (same) */
	ulong	dcmd;	/* command */
};

struct Dmaregs {
	ulong	dcsr[16];	/* control and status */
	uchar	pad0[0xF0-0x40];
	ulong	dint;	/* mask of interrupting channels: 0 is bit 0 */
	uchar	pad1[0x100-0xF4];
	ulong	drcmr[40];
	Dmadesc	chan[16];	/* offset 0x200 */
};

enum {
	/* dcsr */
	DcsRun=	1<<31,	/* start the channel */
	DcsNodesc=	1<<30,	/* set if channel is in no-descriptor fetch mode */
	DcsStopirq=	1<<29,	/* enable interrupt if channel is uninitialised or stopped */
	DcsReqpend=	1<<8,	/* channel has pending request */
	DcsStopstate=	1<<3,	/* channel is uninitialised or stopped */
	DcsEndintr=	1<<2,	/* transaction complete, length now 0 */
	DcsStartintr=	1<<1,	/* successful descriptor fetch */
	DcsBuserr=	1<<0,	/* bus error */

	/* drcmr */
	DmrValid=	1<<7,	/* mapped to channel given by bits 0-3 */
	DmrChan=	0xF,		/* channel number mask */

	/* ddadr */
	DdaStop=	1<<1,	/* =0, run channel; =1, stop channel after this descriptor */

	/* dcmd */
	DcmIncsrc=	1<<31,	/* increment source address after use */
	DcmIncdest=	1<<30,	/* increment destination address after use */
	DcmFlowsrc=	1<<29,	/* enable flow control on source */
	DcmFlowdest=	1<<28,	/* enable flow control on target */
	DcmStartirq=	1<<22,	/* interrupt when descriptor loaded (fetch mode) */
	DcmEndirq=	1<<21,	/* interrupt when transfer complete */
	DcmEndian=	1<<18,	/* must be zero (little endian) */
	DcmBurst8=	1<<16,	/* burst size in bytes */
	DcmBurst16=	2<<16,
	DcmBurst32=	3<<16,
	DcmWidth0=	0<<14,	/* width for external memory */
	DcmWidth1=	1<<14,	/* width of on-chip peripheral */
	DcmWidth2=	2<<14,
	DcmWidth4=	3<<14,
	DcmLength=	(1<<13)-1,

	Ndma=	16,		/* number of dma channels */
	MaxDMAbytes=	8192-1,	/* annoyingly small limit */
};

struct Dma {
	int	chan;
	Dmadesc*	desc;
	Dmadesc	stop;
	ulong	*csr;
	void	(*interrupt)(void*, ulong);
	void*	arg;
	Rendez	r;
	ulong	attrs;	/* transfer attributes: flow control, burst size, width */
};

static struct {
	Lock;
	ulong	avail;
	Dma	dma[Ndma];
} dmachans;

static	void	dmaintr(Ureg*, void*);

void
dmareset(void)
{
	int i;
	Dma *d;

	for(i=0; i<Ndma; i++){
		dmachans.avail |= 1<<i;
		d = &dmachans.dma[i];
		d->chan = i;
		d->csr = &DMAREGS->dcsr[i];
		d->desc = &DMAREGS->chan[i];
		d->stop.ddadr = (ulong)&d->stop | DdaStop;
		d->stop.dcmd = 0;
	}
	intrenable(IRQ, IRQdma, dmaintr, nil, "dma");
}

/*
 * allocate a DMA channel, reset it, and configure it for the given device
 */
Dma*
dmasetup(int owner, void (*interrupt)(void*, ulong), void *arg, ulong attrs)
{
	Dma *d;
	Dmadesc *dc;
	int i;

	ilock(&dmachans);
	for(i=0; (dmachans.avail & (1<<i)) == 0; i++)
		if(i >= Ndma){
			iunlock(&dmachans);
			return nil;
		}
	dmachans.avail &= ~(1<<i);
	iunlock(&dmachans);

	d = &dmachans.dma[i];
	d->owner = owner;
	d->interrupt = interrupt;
	d->arg = arg;
	d->attrs = attrs;
	dc = d->desc;
	dc->ddadr = (ulong)&d->stop | DdaStop;	/* empty list */
	dc->dcmd = 0;
	*d->csr = DcsEndintr | DcsStartintr | DcsBuserr;	/* clear status, stopped */
	DMAREGS->drcmr[owner] = DmrValid | i;
	return d;
}

void
dmafree(Dma *dma)
{
	dmastop(dma);
	DMAREGS->drcmr[d->owner] = 0;
	ilock(&dmachans);
	dmachans.avail |= 1<<dma->chan;
	dma->interrupt = nil;
	iunlock(&dmachans);
}

/*
 * simple dma transfer on a channel, using `no fetch descriptor' mode.
 * virtual buffer addresses are assumed to refer to contiguous physical addresses.
 */
int
dmastart(Dma *dma, void *from, void *to, int nbytes)
{
	Dmadesc *dc;

	if((ulong)nbytes > MaxDMAbytes)
		panic("dmastart");
	if((*dma->csr & DcsStopstate) == 0)
		return 0;	/* busy */
	dc = dma->desc;
	dc->ddadr = DdaStop;
	dc->dsadr = PADDR(from);
	dc->dtadr = PADDR(to);
	dc->dcmd = dma->attrs | DcmEndirq | nbytes;
	*dma->csr = DcsRun | DcsNodesc | DcsEndintr | DcsStartintr | DcsBuserr;
	return 1;
}

/*
 * stop dma on a channel
 */
void
dmastop(Dma *dma)
{
	*dma->csr = 0;
	while((*dma->csr & DcsStopstate) == 0)
		;
	*dma->csr = DcsStopstate;
}

/*
 * return nonzero if there was a memory error during DMA,
 * and clear the error state
 */
int
dmaerror(Dma *dma)
{
	ulong e;

	e = *dma->csr & DcsBuserr;
	*dma->csr |= e;
	return e;
}

/*
 * return nonzero if the DMA channel is not busy
 */
int
dmaidle(Dma *d)
{
	return (*d->csr & DcsStopstate) == 0;
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
dmaintr(Ureg*, void*)
{
	Dma *d;
	Dmaregs *dr;
	int i;
	ulong s, csr;

	dr = DMAREGS;
	s = dr->dint;
	dr->dint = s;
	for(i=0; i<Ndma && s != 0; i++)
		if(s & (1<<i)){
			d = &dmachans.dma[i];
			csr = *d->csr;
			if(csr & DcsBuserr)
				iprint("DMA error, chan %d status #%8.8lux\n", d->chan, csr);
			*d->csr = csr & (DcsRun | DcsNodesc | DcsEndintr | DcsStartintr | DcsBuserr);
			if(d->interrupt != nil)
				d->interrupt(d->arg, csr);
			else
				wakeup(&d->r);
		}
}
