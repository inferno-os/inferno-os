/*
 *	basic read/write interface to PXA25x I⁲C bus (master mode)
 *	7 bit addressing only.
 * TO DO:
 *	- enable unit clock
 */
#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	"io.h"

typedef struct Ctlr Ctlr;
typedef struct I2Cregs I2Cregs;
struct I2Cregs {
	ulong	ibmr;	/* bus monitor */
	ulong	pad0;
	ulong	idbr;	/* data buffer */
	ulong	pad1;
	ulong	icr;	/* control */
	ulong	pad2;
	ulong	isr;	/* status */
	ulong	pad3;
	ulong	isar;	/* slave address */
};

enum {
	/* ibmr */
	Scls=	1<<1,	/* SCL pin status */
	Sdas=	1<<0,	/* SDA pin status */

	/* icr */
	Fm=		1<<15,	/* =0, 100 kb/sec; =1, 400 kb/sec */
	Ur=		1<<14,	/* reset the i2c unit only */
	Sadie=	1<<13,	/* slave address detected interrupt enable */
	Aldie=	1<<12,	/* arbitration loss detected interrupt enable (master mode) */
	Ssdie=	1<<11,	/* stop detected interrupt enable (slave mode) */
	Beie=	1<<10,	/* bus error interrupt enable */
	Irfie=	1<<9,	/* idbr receive full, interrupt enable */
	Iteie=	1<<8,	/* idbr transmit empty interrupt enable */
	Gcd=	1<<7,	/* disable response to general call message (slave); must be set if master uses g.c. */
	Scle=	1<<6,	/* SCL enable: enable clock output for master mode */
	Iue=		1<<5,	/* enable i2c (default: slave) */
	Ma=		1<<4,	/* master abort (send STOP without data) */
	Tb=		1<<3,	/* transfer byte on i2c bus */
	Ack=		0<<2,
	Nak=	1<<2,
	Stop=	1<<1,	/* send a stop */
	Start=	1<<0,	/* send a stop */

	/* isr */
	Bed=		1<<10,	/* bus error detected */
	Sad=		1<<9,	/* slave address detected */
	Gcad=	1<<8,	/* general call address detected */
	Irf=		1<<7,	/* idbr receive full */
	Ite=		1<<6,	/* idbr transmit empty */
	Ald=		1<<5,	/* arbitration loss detected (multi-master) */
	Ssd=		1<<4,	/* slave stop detected */
	Ibb=		1<<3,	/* i2c bus is busy */
	Ub=		1<<2,	/* unit is busy (between start and stop) */
	Nakrcv=	1<<1,	/* nak received or sent a NAK */
	Rwm=	1<<0,	/* =0, master transmit (or slave receive); =1, master receive (or slave transmit) */
	Err=		Bed | Ssd,

	/* isar address (0x7F bits) */

	/* others */
	Rbit =	1<<0,	/* bit in address byte denoting read */
	Wbit=	0<<0,

	MaxIO =	8192,	/* largest transfer done at once (can change) */
	MaxSA=	2,		/* largest subaddress; could be FIFOsize */
	Bufsize =	MaxIO,	/* subaddress bytes don't go in buffer */
	Freq =	0,	/* set to Fm for high-speed */
//	I2Ctimeout = 125,	/* msec (can change) */
	I2Ctimeout = 10000,	/* msec when Chatty */

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
	I2Cregs*	regs;	/* hardware registers */

	/* controller state (see below) */
	int	status;
	int	phase;
	Rendez	r;

	/* transfer parameters */
	int	addr;
	int	salen;	/* bytes remaining of subaddress */
	int	offset;	/* sub-addressed offset */
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
	Address,
	Subaddress,
	Read,
	Write,
	Halting,
};

static	Ctlr	i2cctlr[1];

static void	interrupt(Ureg*, void*);
static int readyxfer(Ctlr*, int);
static void	rxstart(Ctlr*);
static void	txstart(Ctlr*);
static void	stopxfer(Ctlr*);
static void	txoffset(Ctlr*, ulong, int);
static int idlectlr(Ctlr*);

static void
i2cdump(char *t, I2Cregs *i2c)
{
	iprint("i2c %s: ibmr=%.4lux icr=%.4lux isr=%.4lux\n", t, i2c->ibmr, i2c->icr, i2c->isr);
}

static void
initialise(I2Cregs *i2c, int eintr)
{
	int ctl;

	/* initialisation (see p. 9-11 on) */
	i2c->isar = 0;
	ctl = Freq | Gcd | Scle | Iue;
	if(eintr)
		ctl |= Beie | Irfie;	/* Iteie set by txstart */
	i2c->icr = ctl;
	if(Chatty)
		iprint("ctl=%4.4ux icr=%4.4lux\n", ctl, i2c->icr);
}

/*
 * called by the reset routine of any driver using the IIC
 */
void
i2csetup(int polling)
{
	I2Cregs *i2c;
	Ctlr *ctlr;

	ctlr = i2cctlr;
	ctlr->polling = polling;
	i2c = KADDR(PHYSI2C);
	ctlr->regs = i2c;
	if(!polling){
		if(ctlr->init == 0){
			initialise(i2c, 1);
			ctlr->init = 1;
			intrenable(IRQ, IRQi2c, interrupt, i2cctlr, "i2c");
			if(Chatty)
				i2cdump("init", i2c);
		}
	}else
		initialise(i2c, 0);
}

static void
done(Ctlr *ctlr)
{
	ctlr->phase = Done;
	wakeup(&ctlr->r);
}

static void
failed(Ctlr *ctlr)
{
	ctlr->phase = Failed;
	wakeup(&ctlr->r);
}

static void
interrupt(Ureg*, void *arg)
{
	int sts, idl;
	Ctlr *ctlr;
	Block *b;
	I2Cregs *i2c;
	char xx[12];

	ctlr = arg;
	i2c = ctlr->regs;
	idl = (i2c->ibmr & 3) == 3;
	if(Chatty && ctlr->phase != Read && ctlr->phase != Write){
		snprint(xx, sizeof(xx), "intr %d", ctlr->phase);
		i2cdump(xx, i2c);
	}
	sts = i2c->isr;
	if(sts & (Bed | Sad | Gcad | Ald))
		iprint("i2c: unexpected status: %.4ux", sts);
	i2c->isr = sts;
	ctlr->status = sts;
	i2c->icr &= ~(Start | Stop | Nak | Ma | Iteie);
	if(sts & Err){
		failed(ctlr);
		return;
	}
	switch(ctlr->phase){
	default:
		iprint("i2c: unexpected interrupt: p-%d s=%.4ux\n", ctlr->phase, sts);
		break;

	case Halting:
		ctlr->phase = Idle;
		break;

	case Subaddress:
		if(ctlr->salen){
			/* push out next byte of subaddress */
			ctlr->salen -= 8;
			i2c->idbr = ctlr->offset >> ctlr->salen;
			i2c->icr |= Aldie | Tb | Iteie;
			break;
		}
		/* subaddress finished */
		if(ctlr->cntl & Rbit){
			/* must readdress if reading to change mode */
			i2c->idbr = (ctlr->addr << 1) | Rbit;
			i2c->icr |= Start | Tb | Iteie;
			ctlr->phase = Address;	/* readdress */
			break;
		}
		/* FALL THROUGH if writing */
	case Address:
		/* if not sub-addressed, rxstart/txstart */
		if(ctlr->cntl & Rbit)
			rxstart(ctlr);
		else
			txstart(ctlr);
		break;

	case Read:
		b = ctlr->b;
		if(b == nil)
			panic("i2c: no buffer");
		/* master receive: next byte */
		if(sts & Irf){
			ctlr->rdcount--;
			if(b->wp < b->lim)
				*b->wp++ = i2c->idbr;
		}
		if(ctlr->rdcount <= 0 || sts & Nakrcv || idl){
			if(Chatty)
				iprint("done: %.4ux\n", sts);
			done(ctlr);
			break;
		}
		rxstart(ctlr);
		break;

	case Write:
		b = ctlr->b;
		if(b == nil)
			panic("i2c: no buffer");
		/* account for data transmitted */
		if(BLEN(b) <= 0 || sts & Nakrcv){
			done(ctlr);
			break;
		}
		txstart(ctlr);
		break;
	}
}

static int
isdone(void *a)
{
	return ((Ctlr*)a)->phase < Busy;
}

static int
i2cerror(char *s)
{
	DPRINT("i2c error: %s\n", s);
	if(up)
		error(s);
	/* no current process, don't call error */
	return -1;
}

static char*
startxfer(I2Cdev *d, int op, Block *b, int n, ulong offset)
{
	I2Cregs *i2c;
	Ctlr *ctlr;
	int i, p, s;

	ctlr = i2cctlr;
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
		panic("i2c: ctlr busy");
	ctlr->cntl = op;
	ctlr->b = b;
	ctlr->rdcount = n;
	ctlr->addr = d->addr;
	i2c = ctlr->regs;
	ctlr->salen = d->salen*8;
	ctlr->offset = offset;
	if(ctlr->salen){
		ctlr->phase = Subaddress;
		op = Wbit;
	}else
		ctlr->phase = Address;
	i2c->idbr = (d->addr<<1) | op;	/* 7-bit address + R/nW */
	i2c->icr |= Start | Tb | Iteie;
	if(Chatty)
		i2cdump("start", i2c);
	iunlock(ctlr);

	/* wait for it */
	if(ctlr->polling){
		for(i=0; !isdone(ctlr); i++){
			delay(2);
			interrupt(nil, ctlr);
		}
	}else
		tsleep(&ctlr->r, isdone, ctlr, I2Ctimeout);

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
	if(p != Done || s & (Bed|Ald)){	/* CHECK; time out */
		if(s & Ald)
			return "i2c lost arbitration";
		if(s & Bed)
			return "i2c bus error";
		if(s & Ssd)
			return "i2c transfer aborted";	/* ?? */
		if(0 && p != Done)
			return "i2c timed out";
		sprint(up->genbuf, "i2c error: phase=%d status=%.4ux", p, s);
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
	e = startxfer(d, 0, b, 0, offset);
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
	e = startxfer(d, Rbit, b, n, offset);
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
readyxfer(Ctlr *ctlr, int phase)
{
	I2Cregs *i2c;

	i2c = ctlr->regs;
	if((i2c->isr & Bed) != 0){
		failed(ctlr);
		return 0;
	}
	ctlr->phase = phase;
	return 1;
}

/*
 * start a master  transfer to receive the next byte of data
 */
static void
rxstart(Ctlr *ctlr)
{
	Block *b;
	int cntl;

	b = ctlr->b;
	if(b == nil || ctlr->rdcount<= 0){
		done(ctlr);
		return;
	}
	if(!readyxfer(ctlr, Read))
		return;
	cntl = Aldie | Tb;
	if(ctlr->rdcount == 1)
		cntl |= Stop | Nak | Iteie;	/* last byte of transfer */
	ctlr->regs->icr |= cntl;
}

/*
 * start a master transfer to send the next chunk of data
 */
static void
txstart(Ctlr *ctlr)
{
	Block *b;
	int cntl;
	long nb;
	I2Cregs *i2c;

	b = ctlr->b;
	if(b == nil || (nb = BLEN(b)) <= 0){
		done(ctlr);
		return;
	}
	if(!readyxfer(ctlr, Write))
		return;
	i2c = ctlr->regs;
	i2c->idbr = *b->rp++;
	cntl = Aldie | Tb | Iteie;
	if(nb == 1)
		cntl |= Stop;
	i2c->icr |= cntl;
}

/*
 * stop a transfer if one is in progress
 */
static void
stopxfer(Ctlr *ctlr)
{
	I2Cregs *i2c;

	i2c = ctlr->regs;
	if((i2c->isr & Ub) == 0){
		ctlr->phase = Idle;
		return;
	}
	if((i2c->isr & Ibb) == 0 && ctlr->phase != Halting){
		ctlr->phase = Halting;	/* interrupt will clear the state */
		i2c->icr |= Ma;
	}
	/* if that doesn't clear it by the next operation, idlectlr will do so below */
}

static int
idlectlr(Ctlr *ctlr)
{
	I2Cregs *i2c;

	i2c = ctlr->regs;
	if((i2c->isr & Ibb) == 0){
		if((i2c->isr & Ub) == 0){
			ctlr->phase = Idle;
			return 1;
		}
		iprint("i2c: bus free, ctlr busy: isr=%.4lux icr=%.4lux\n", i2c->isr, i2c->icr);
	}
	/* hit it with the hammer, soft reset */
	iprint("i2c: soft reset\n");
	i2c->icr = Ur;
	iunlock(ctlr);
	delay(1);
	ilock(ctlr);
	initialise(i2c, !ctlr->polling);
	ctlr->phase = Idle;
	return (i2c->isr & (Ibb | Ub)) == 0;
}
