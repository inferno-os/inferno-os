#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "../port/error.h"

/*
 * basic read/write interface to 4xx IIC bus (master mode)
 * ``referred to as IIC to distinguish it from the Phillips I⁲C bus [itself]''
 *
 * TO DO:
 *	power management ref count
 *	power up/power down on timer?
 */

typedef struct Ctlr Ctlr;
typedef struct IICregs IICregs;

struct IICregs {
	uchar	mdbuf;	/* master data buffer */
	uchar	rsvd0;
	uchar	sdbuf;	/* slave data buffer */
	uchar	rsvd1;
	uchar	lmadr;	/* low master address */
	uchar	hmadr;	/* high master address */
	uchar	cntl;		/* control */
	uchar	mdcntl;	/* mode control */
	uchar	sts;		/* status */
	uchar	extsts;	/* extended status */
	uchar	lsadr;	/* low slave address */
	uchar	hsadr;	/* high slave address */
	uchar	clkdiv;	/* clock divide */
	uchar	intrmsk;	/* interrupt mask */
	uchar	xfrcnt;	/* transfer count */
	uchar	xtcntlss;	/* extended control and slave status */
	uchar	directcntl;	/* direct control */
};

enum {
	/* cntl */
	Hmt=	1<<7,	/* halt master transfer */
	Amd10=	1<<6,	/* =0, 7-bit; =1, 10-bit addressing */
					/* 5,4: two bit transfer count (n-1)&3 bytes */
	Rpst=	1<<3,	/* =0, normal start; =1, repeated Start, transfer should be followed by another start */
	Cht=		1<<2,	/* chain transfer; not the last */
	Write=	0<<1,	/* transfer is a write */
	Read=	1<<1,	/* transfer is a read */
	Pt=		1<<0,	/* =0, most recent transfer complete; =1, start transfer if bus free */

	/* mdcntl */
	Fsdb=	1<<7,	/* flush slave data buffer */
	Fmdb=	1<<6,	/* flush master data buffer */
	Fsm=	1<<4,	/* =0, 100 kHz standard mode; =1, 400 Khz fast mode */
	Esm=	1<<3,	/* enable slave mode */
	Eint=		1<<2,	/* enable interrupt */
	Eubs=	1<<1,	/* exit unknown bus state */
	Hscl=	1<<0,	/* hold IIC serial clock low */

	/* sts */
	Sss=		1<<7,	/* slave status set (slave operation in progress) */
	Slpr=	1<<6,	/* sleep mode */
	Mdbs=	1<<5,	/* master data buffer has data */
	Mdbf=	1<<4,	/* master data buffer is full */
	Scmp=	1<<3,	/* stop complete */
	Err=		1<<2,	/* error set in extsts */
	Irqa=	1<<1,	/* IRQ active */
	/* Pt as above */

	/* extsts */
	Irqp=	1<<7,	/* IRQ pending */
	Bcs=		7<<4,
	 Bcs_ssel=	1<<4,	/* slave-selected state */
	 Bcs_sio=	2<<4,	/* slave transfer state */
	 Bcs_mio=	3<<4,	/* master transfer state */
	 Bcs_free=	4<<4,	/* bus is free */
	 Bcs_busy= 5<<4,	/* bus is busy */
	 Bcs_gok=	6<<4,	/* unknown state */
	Irqd=	1<<3,	/* IRQ on deck */
	La=		1<<2,	/* lost arbitration */
	Ict=		1<<1,	/* incomplete transfer */
	Xfra=	1<<0,	/* transfer aborted */

	/* intrmsk */
	Eirc=		1<<7,	/* slave read complete */
	Eirs=		1<<6,	/* slave read needs service */
	Eiwc=	1<<5,	/* slave write complete */
	Eiws=	1<<4,	/* slave write needs service */
	Eihe=	1<<3,	/* halt executed */
	Eiic=		1<<2,	/* incomplete transfer */
	Eita=		1<<1,	/* transfer aborted */
	Eimtc=	1<<0,	/* master transfer complete */

	/* xtcntlss */
	Src=		1<<7,	/* slave read complete; =1, NAK or Stop, or repeated Start ended op */
	Srs=		1<<6,	/* slave read needs service */
	Swc=	1<<5,	/* slave write complete */
	Sws=	1<<4,	/* slave write needs service */
	Sdbd=	1<<3,	/* slave buffer has data */
	Sdbf=	1<<2,	/* slave buffer is full */
	Epi=		1<<1,	/* enable pulsed IRQ on transfer aborted */
	Srst=		1<<0,	/* soft reset */

	/* directcntl */
	Sdac=	1<<3,	/* SDA output */
	Scc=		1<<2,	/* SCL output */
	Msda=	1<<1,	/* SDA input */
	Msc=	1<<0,	/* SCL input */

	/* others */
	Rbit =	1<<0,	/* bit in address byte denoting read */
	FIFOsize=	4,		/* most to be written at once */

	MaxIO =	8192,	/* largest transfer done at once (can change) */
	MaxSA=	2,		/* largest subaddress; could be FIFOsize */
	Bufsize =	MaxIO,	/* subaddress bytes don't go in buffer */
	Freq =	100000,
	I2Ctimeout = 125,	/* msec (can change) */

	Chatty = 0,
};

#define	DPRINT	if(Chatty)print

/*
 * I2C software structures
 */

struct Ctlr {
	Lock;
	QLock	io;
	int	init;
	int	polling;	/* eg, when running before system set up */
	IICregs*	regs;	/* hardware registers */

	/* controller state (see below) */
	int	status;
	int	phase;
	Rendez	r;

	/* transfer parameters */
	int	cntl;		/* everything but transfer length */
	int	rdcount;	/* requested read transfer size */
	Block*	b;
};

enum {
	/* Ctlr.state */
	Idle,
	Done,
	Failed,
	Busy,
	Halting,
};

static	Ctlr	iicctlr[1];

static void	interrupt(Ureg*, void*);
static int readyxfer(Ctlr*);
static void	rxstart(Ctlr*);
static void	txstart(Ctlr*);
static void	stopxfer(Ctlr*);
static void	txoffset(Ctlr*, ulong, int);
static int idlectlr(Ctlr*);

static void
iicdump(char *t, IICregs *iic)
{
	iprint("iic %s: lma=%.2ux hma=%.2ux im=%.2ux mdcntl=%.2ux sts=%.2ux ests=%.2ux cntl=%.2ux\n",
		t, iic->lmadr, iic->hmadr, iic->intrmsk, iic->mdcntl, iic->sts, iic->extsts, iic->cntl);
}

static void
initialise(IICregs *iic, int intrmsk)
{
	int d;

	d = (m->opbhz-1000000)/10000000;
	if(d <= 0)
		d = 1;	/* just in case OPB freq < 20 Mhz */
	/* initialisation (see 22.4, p. 22-23) */
	iic->lmadr = 0;
	iic->hmadr = 0;
	iic->sts = Scmp|Irqa;
	iic->extsts = Irqp | Irqd | La | Ict | Xfra;
	iic->clkdiv = d;
	iic->intrmsk = 0;	/* see below */
	iic->xfrcnt = 0;
	iic->xtcntlss = Src | Srs | Swc | Sws;
	iic->mdcntl = Fsdb | Fmdb | Eubs;	/* reset; standard mode */
	iic->cntl = 0;
	eieio();
	iic->mdcntl = 0;
	eieio();
	if(intrmsk){
		iic->intrmsk = intrmsk;
		iic->mdcntl = Eint;
	}
}

/*
 * called by the reset routine of any driver using the IIC
 */
void
i2csetup(int polling)
{
	IICregs *iic;
	Ctlr *ctlr;

	ctlr = iicctlr;
	ctlr->polling = polling;
	iic = (IICregs*)KADDR(PHYSIIC);
	ctlr->regs = iic;
	if(!polling){
		if(ctlr->init == 0){
			initialise(iic, Eihe | Eiic | Eita | Eimtc);
			ctlr->init = 1;
			intrenable(VectorIIC, interrupt, iicctlr, BUSUNKNOWN, "iic");
		}
	}else
		initialise(iic, 0);
}

static void
interrupt(Ureg*, void *arg)
{
	int sts, nb, ext, avail;
	Ctlr *ctlr;
	Block *b;
	IICregs *iic;

	ctlr = arg;
	iic = ctlr->regs;
	if(0)
		iicdump("intr", iic);
	sts = iic->sts;
	if(sts & Pt)
		iprint("iic: unexpected status: %.2ux", iic->sts);
	ext = iic->extsts;
	if(sts & Mdbs)
		nb = iic->xfrcnt & 7;
	else
		nb = 0;
	eieio();
	iic->sts = sts;
	if(sts & Err && (ext & (La|Xfra)) != 0)
		iprint("iic: s=%.2ux es=%.2ux (IO)\n", sts, ext);
	ctlr->status = ext;
	switch(ctlr->phase){
	default:
		iprint("iic: unexpected interrupt: p-%d s=%.2ux es=%.2ux\n", ctlr->phase, sts, ext);
		break;

	case Halting:
		ctlr->phase = Idle;
		break;

	case Busy:
		b = ctlr->b;
		if(b == nil)
			panic("iic: no buffer");
		if(ctlr->cntl & Read){
			/* copy data in from FIFO */
			avail = b->lim - b->wp;
			if(nb > avail)
				nb = avail;
			while(--nb >= 0)
				*b->wp++ = iic->mdbuf;	/* ``the IIC interface handles the [FIFO] latency'' (22-4) */
			if(sts & Err || ctlr->rdcount <= 0){
				ctlr->phase = Done;
				wakeup(&ctlr->r);
				break;
			}
			rxstart(ctlr);
		}else{
			/* account for data transmitted */
			if((b->rp += nb) > b->wp)
				b->rp = b->wp;
			if(sts & Err || BLEN(b) <= 0){
				ctlr->phase = Done;
				wakeup(&ctlr->r);
				break;
			}
			txstart(ctlr);
		}
	}
}

static int
done(void *a)
{
	return ((Ctlr*)a)->phase < Busy;
}

static int
i2cerror(char *s)
{
	DPRINT("iic error: %s\n", s);
	if(up)
		error(s);
	/* no current process, don't call error */
	return -1;
}

static char*
startxfer(I2Cdev *d, int op, void (*xfer)(Ctlr*), Block *b, int n, ulong offset)
{
	IICregs *iic;
	Ctlr *ctlr;
	int i, cntl, p, s;

	ctlr = iicctlr;
	if(up){
		qlock(&ctlr->io);
		if(waserror()){
			qunlock(&ctlr->io);
			nexterror();
		}
	}
	ilock(ctlr);
	if(!idlectlr(ctlr)){
		iunlock(ctlr);
		if(up)
			error("bus confused");
		return "bus confused";
	}
	if(ctlr->phase >= Busy)
		panic("iic: ctlr busy");
	cntl = op | Pt;
	if(d->tenbit)
		cntl |= Amd10;
	ctlr->cntl = cntl;
	ctlr->b = b;
	ctlr->rdcount = n;
	ctlr->phase = Busy;
	iic = ctlr->regs;
	if(d->tenbit){
		iic->hmadr = 0xF0 | (d->addr>>7);	/* 2 higher bits of address, LSB don't care */
		iic->lmadr = d->addr;
	}else{
		iic->hmadr = 0;
		iic->lmadr = d->addr<<1;	/* 7-bit address */
	}
	if(d->salen)
		txoffset(ctlr, offset, d->salen);
	else
		(*xfer)(ctlr);
	iunlock(ctlr);

	/* wait for it */
	if(ctlr->polling){
		for(i=0; !done(ctlr); i++){
			delay(2);
			interrupt(nil, ctlr);
		}
	}else
		tsleep(&ctlr->r, done, ctlr, I2Ctimeout);

	ilock(ctlr);
	p = ctlr->phase;
	s = ctlr->status;
	ctlr->b = nil;
	if(ctlr->phase != Done && ctlr->phase != Idle)
		stopxfer(ctlr);
	iunlock(ctlr);

	if(up){
		poperror();
		qunlock(&ctlr->io);
	}
	if(p != Done || s & (La|Xfra)){	/* CHECK; time out */
		if(s & La)
			return "iic lost arbitration";
		if(s & Xfra)
			return "iic transfer aborted";
		if(p != Done)
			return "iic timed out";
		sprint(up->genbuf, "iic error: phase=%d estatus=%.2ux", p, s);
		return up->genbuf;
	}
	return nil;
}

long
i2csend(I2Cdev *d, void *buf, long n, ulong offset)
{
	Block *b;
	char *e;

	if(n <= 0)
		return 0;
	if(n > MaxIO)
		n = MaxIO;

	if(up){
		b = allocb(n);
		if(b == nil)
			error(Enomem);
		if(waserror()){
			freeb(b);
			nexterror();
		}
	}else{
		b = iallocb(n);
		if(b == nil)
			return -1;
	}
	memmove(b->wp, buf, n);
	b->wp += n;
	e = startxfer(d, Write, txstart, b, 0, offset);
	if(up)
		poperror();
	n -= BLEN(b);	/* residue */
	freeb(b);
	if(e)
		return i2cerror(e);
	return n;
}

long
i2crecv(I2Cdev *d, void *buf, long n, ulong offset)
{
	Block *b;
	long nr;
	char *e;

	if(n <= 0)
		return 0;
	if(n > MaxIO)
		n = MaxIO;

	if(up){
		b = allocb(n);
		if(b == nil)
			error(Enomem);
		if(waserror()){
			freeb(b);
			nexterror();
		}
	}else{
		b = iallocb(n);
		if(b == nil)
			return -1;
	}
	e = startxfer(d, Read, rxstart, b, n, offset);
	nr = BLEN(b);
	if(nr > 0)
		memmove(buf, b->rp, nr);
	if(up)
		poperror();
	freeb(b);
	if(e)
		return i2cerror(e);
	return nr;
}

/*
 * the controller must be locked for the following functions
 */

static int
readyxfer(Ctlr *ctlr)
{
	IICregs *iic;

	iic = ctlr->regs;
	iic->sts = Scmp | Err;
	if((iic->sts & Pt) != 0){
		ctlr->phase = Failed;
		wakeup(&ctlr->r);
		return 0;
	}
	iic->mdcntl |= Fmdb;
	return 1;
}

/*
 * start a master  transfer to receive the next chunk of data
 */
static void
rxstart(Ctlr *ctlr)
{
	Block *b;
	int cntl;
	long nb;

	b = ctlr->b;
	if(b == nil || (nb = ctlr->rdcount) <= 0){
		ctlr->phase = Done;
		wakeup(&ctlr->r);
		return;
	}
	if(!readyxfer(ctlr))
		return;
	cntl = ctlr->cntl;
	if(nb > FIFOsize){
		nb = FIFOsize;
		cntl |= Cht;	/* more to come */
	}
	ctlr->rdcount -= nb;
	ctlr->regs->cntl = cntl | ((nb-1)<<4);
}

/*
 * start a master transfer to send the next chunk of data
 */
static void
txstart(Ctlr *ctlr)
{
	Block *b;
	int cntl, i;
	long nb;
	IICregs *iic;

	b = ctlr->b;
	if(b == nil || (nb = BLEN(b)) <= 0){
		ctlr->phase = Done;
		wakeup(&ctlr->r);
		return;
	}
	if(!readyxfer(ctlr))
		return;
	cntl = ctlr->cntl;
	if(nb > FIFOsize){
		nb = FIFOsize;
		cntl |= Cht;	/* more to come */
	}
	iic = ctlr->regs;
	for(i=0; i<nb; i++)
		iic->mdbuf = *b->rp++;	/* load the FIFO */
	iic->cntl = cntl | ((nb-1)<<4);
}

/*
 * start a master transfer to send a sub-addressing offset;
 * if subsequently receiving, use Rpst to cause the next transfer to include a Start;
 * if subsequently sending, use Cht to chain the transfer without a Start.
 */
static void
txoffset(Ctlr *ctlr, ulong offset, int len)
{
	int i, cntl;
	IICregs *iic;

	if(!readyxfer(ctlr))
		return;
	iic = ctlr->regs;
	for(i=len*8; (i -= 8) >= 0;)
		iic->mdbuf = offset>>i;	/* load offset bytes into FIFO */
	cntl = ctlr->cntl & Amd10;
	if(ctlr->cntl & Read)
		cntl |= Rpst;
	else
		cntl |= Cht;
	iic->cntl = cntl | ((len-1)<<4) | Write | Pt;
}

/*
 * stop a transfer if one is in progress
 */
static void
stopxfer(Ctlr *ctlr)
{
	IICregs *iic;
	int ext;

	iic = ctlr->regs;
	ext = iic->extsts;
	eieio();
	iic->sts = Scmp | Irqa;
	eieio();
	if((iic->sts & Pt) == 0){
		ctlr->phase = Idle;
		return;
	}
	if((ext & Bcs) == Bcs_mio && ctlr->phase != Halting){
		ctlr->phase = Halting;	/* interrupt will clear the state */
		iic->cntl = Hmt;
	}
}

static int
idlectlr(Ctlr *ctlr)
{
	IICregs *iic;

	iic = ctlr->regs;
	if((iic->extsts & Bcs) == Bcs_free){
		if((iic->sts & Pt) == 0){
			ctlr->phase = Idle;
			return 1;
		}
		iprint("iic: bus free, ctlr busy: s=%.2ux es=%.2ux\n", iic->sts, iic->extsts);
	}
	/* hit it with the hammer, soft reset */
	iprint("iic: soft reset\n");
	iic->xtcntlss = Srst;
	iunlock(ctlr);
	delay(1);
	ilock(ctlr);
	initialise(iic, Eihe | Eiic | Eita | Eimtc);
	ctlr->phase = Idle;
	return (iic->extsts & Bcs) == Bcs_free && (iic->sts & Pt) == 0;
}
