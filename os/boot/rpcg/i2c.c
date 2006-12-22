#include "boot.h"

/*
 * basic read/write interface to mpc8xx I2C bus (master mode)
 */

typedef struct I2C I2C;

struct I2C {
	uchar	i2mod;
	uchar	rsv12a[3];
	uchar	i2add;
	uchar	rsv12b[3];
	uchar	i2brg;
	uchar	rsv12c[3];
	uchar	i2com;
	uchar	rsv12d[3];
	uchar	i2cer;
	uchar	rsv12e[3];
	uchar	i2cmr;
};

enum {
	/* i2c-specific BD flags */
	RxeOV=		1<<1,	/* overrun */
	TxS=			1<<10,	/* transmit start condition */
	TxeNAK=		1<<2,	/* last transmitted byte not acknowledged */
	TxeUN=		1<<1,	/* underflow */
	TxeCL=		1<<0,	/* collision */
	TxERR=		(TxeNAK|TxeUN|TxeCL),

	/* i2cmod */
	REVD=	1<<5,	/* =1, LSB first */
	GCD=	1<<4,	/* =1, general call address disabled */
	FLT=		1<<3,	/* =0, not filtered; =1, filtered */
	PDIV=	3<<1,	/* predivisor field */
	EN=		1<<0,	/* enable */

	/* i2com */
	STR=		1<<7,	/* start transmit */
	I2CM=	1<<0,	/* master */
	I2CS=	0<<0,	/* slave */

	/* i2cer */
	TXE =	1<<4,
	BSY =	1<<2,
	TXB =	1<<1,
	RXB =	1<<0,

	/* port B bits */
	I2CSDA =	IBIT(27),
	I2CSCL = IBIT(26),

	Rbit =	1<<0,	/* bit in address byte denoting read */

	/* maximum I2C I/O (can change) */
	MaxIO=	128,
	Bufsize =	MaxIO+4,	/* extra space for address/clock bytes and alignment */
	Freq =	100000,
	I2CTimeout = 250,	/* msec */
};

/* data cache needn't be flushed if buffers allocated in uncached INTMEM */
#define	DCFLUSH(a,n)

/*
 * I2C software structures
 */

struct Ctlr {
	Lock;
	QLock	io;
	int	init;
	I2C*	i2c;
	IOCparam*	sp;

	BD*	rd;
	BD*	td;
	int	phase;
	int	timeout;
	char*	addr;
	char*	txbuf;
	char*	rxbuf;
};
typedef struct Ctlr Ctlr;

static	Ctlr	i2ctlr[1];
extern	int	predawn;

static	void	interrupt(Ureg*, void*);

static void
enable(void)
{
	I2C *i2c;

	i2c = i2ctlr->i2c;
	i2c->i2cer = ~0;	/* clear events */
	eieio();
	i2c->i2mod |= EN;
	eieio();
	i2c->i2cmr = TXE|BSY|TXB|RXB;	/* enable all interrupts */
	eieio();
}

static void
disable(void)
{
	I2C *i2c;

	i2c = i2ctlr->i2c;
	i2c->i2cmr = 0;	/* mask all interrupts */
	i2c->i2mod &= ~EN;
}

/*
 * called by the reset routine of any driver using the I2C
 */
void
i2csetup(void)
{
	IMM *io;
	I2C *i2c;
	IOCparam *sp;
	Ctlr *ctlr;
	long f, e, emin;
	int p, d, dmax;

	ctlr = i2ctlr;
	if(ctlr->init)
		return;
	print("i2c setup...\n");
	ctlr->init = 1;
	i2c = KADDR(INTMEM+0x860);
	ctlr->i2c = i2c;
	sp = KADDR(INTMEM+0x3c80);
	ctlr->sp = sp;
	disable();

	if(ctlr->txbuf == nil){
		ctlr->txbuf = ialloc(Bufsize, 2);
		ctlr->addr = ctlr->txbuf+Bufsize;
	}
	if(ctlr->rxbuf == nil)
		ctlr->rxbuf = ialloc(Bufsize, 2);
	if(ctlr->rd == nil){
		ctlr->rd = bdalloc(1);
		ctlr->rd->addr = PADDR(ctlr->rxbuf);
		ctlr->rd->length = 0;
		ctlr->rd->status = BDWrap;
	}
	if(ctlr->td == nil){
		ctlr->td = bdalloc(2);
		ctlr->td->addr = PADDR(ctlr->txbuf);
		ctlr->td->length = 0;
		ctlr->td->status = BDWrap|BDLast;
	}

	/* select port pins */
	io = ioplock();
	io->pbdir |= I2CSDA | I2CSCL;
	io->pbodr |= I2CSDA | I2CSCL;
	io->pbpar |= I2CSDA | I2CSCL;
	iopunlock();

	/* explicitly initialise parameters, because InitRxTx can't be used (see i2c/spi relocation errata) */
	sp = ctlr->sp;
	sp->rbase = PADDR(ctlr->rd);
	sp->tbase = PADDR(ctlr->td);
	sp->rfcr = 0x18;
	sp->tfcr = 0x18;
	sp->mrblr = Bufsize;
	sp->rstate = 0;
	sp->rptr = 0;
	sp->rbptr = sp->rbase;
	sp->rcnt = 0;
	sp->tstate = 0;
	sp->tbptr = sp->tbase;
	sp->tptr = 0;
	sp->tcnt = 0;
	eieio();

	i2c->i2com = I2CM;
	i2c->i2mod = 0;	/* normal mode */
	i2c->i2add = 0;

	emin = Freq;
	dmax = (m->cpuhz/Freq)/2-3;
	for(d=0; d < dmax; d++){
		for(p=3; p>=0; p--){
			f = (m->cpuhz>>(p+2))/(2*(d+3));
			e = Freq - f;
			if(e < 0)
				e = -e;
			if(e < emin){
				emin = e;
				i2c->i2brg = d;
				i2c->i2mod = (i2c->i2mod&~PDIV)|((3-p)<<1); /* set PDIV */
			}
		}
	}
	//print("i2brg=%d i2mod=#%2.2ux\n", i2c->i2brg, i2c->i2mod);
	setvec(VectorCPIC+0x10, interrupt, i2ctlr);
}

enum {
	Idling,
	Done,
	Busy,
		Sending,
		Recving,
};

static void
interrupt(Ureg*, void *arg)
{
	int events;
	Ctlr *ctlr;
	I2C *i2c;

	ctlr = arg;
	i2c = ctlr->i2c;
	events = i2c->i2cer;
	eieio();
	i2c->i2cer = events;
	if(events & (BSY|TXE)){
		print("I2C#%x\n", events);
		if(ctlr->phase != Idling){
			ctlr->phase = Idling;
		}
	}else{
		if(events & TXB){
			//print("i2c: xmt %d %4.4ux %4.4ux\n", ctlr->phase, ctlr->td->status, ctlr->td[1].status);
			if(ctlr->phase == Sending){
				ctlr->phase = Done;
			}
		}
		if(events & RXB){
			//print("i2c: rcv %d %4.4ux %d\n", ctlr->phase, ctlr->rd->status, ctlr->rd->length);
			if(ctlr->phase == Recving){
				ctlr->phase = Done;
			}
		}
	}
}

static int
done(void *a)
{
	return ((Ctlr*)a)->phase < Busy;
}

static void
i2cwait(Ctlr *ctlr)
{
	int i;

	ctlr->timeout = 0;
	i = 0;
	while(!done(ctlr)){
		if(predawn){
			if(++i > 100){
				ctlr->phase = Done;
				ctlr->timeout = 1;
				return;
			}
			delay(1);
			interrupt(nil, ctlr);
		}
	}
}

long
i2csend(int addr, void *buf, long n)
{
	Ctlr *ctlr;
	int i, p, s;

	ctlr = i2ctlr;
	if(n > MaxIO)
		return -1;
	i = 1;
	ctlr->txbuf[0] = addr & ~1;
	if(addr & 1){
		ctlr->txbuf[1] = addr>>8;
		i++;
	}
	memmove(ctlr->txbuf+i, buf, n);
	DCFLUSH(ctlr->txbuf, Bufsize);
	ctlr->phase = Sending;
	ctlr->rd->status = BDEmpty|BDWrap|BDInt;
	ctlr->td->addr = PADDR(ctlr->txbuf);
	ctlr->td->length = n+i;
	ctlr->td->status = BDReady|BDWrap|BDLast|BDInt;
	enable();
	ctlr->i2c->i2com = STR|I2CM;
	eieio();
	i2cwait(ctlr);
	disable();
	p = ctlr->phase;
	s = ctlr->td->status;
	if(s & BDReady || s & TxERR || p != Done || ctlr->timeout)
		return -1;
	return n;
}

long
i2crecv(int addr, void *buf, long n)
{
	Ctlr *ctlr;
	int p, s, flag;
	BD *td;
	long nr;

	ctlr = i2ctlr;
	if(n > MaxIO)
		return -1;
	ctlr->txbuf[0] = addr|Rbit;
	if(addr & 1){	/* special select sequence */
		ctlr->addr[0] = addr &~ 1;
		ctlr->addr[1] = addr>>8;
	}
	DCFLUSH(ctlr->txbuf, Bufsize);
	DCFLUSH(ctlr->rxbuf, Bufsize);
	ctlr->phase = Recving;
	ctlr->rd->addr = PADDR(ctlr->rxbuf);
	ctlr->rd->status = BDEmpty|BDWrap|BDInt;
	flag = 0;
	td = ctlr->td;
	td[1].status = 0;
	if(addr & 1){
		/* special select sequence */
		td->addr = PADDR(ctlr->addr);
		td->length = 2;
		/* td->status made BDReady below */
		td++;
		flag = TxS;
	}
	td->addr = PADDR(ctlr->txbuf);
	td->length = n+1;
	td->status = BDReady|BDWrap|BDLast | flag;	/* not BDInt: leave that to receive */
	if(flag)
		ctlr->td->status = BDReady;
	enable();
	ctlr->i2c->i2com = STR|I2CM;
	eieio();
	i2cwait(ctlr);
	disable();
	p = ctlr->phase;
	s = ctlr->td->status;
	if(flag)
		s |= ctlr->td[1].status;
	nr = ctlr->rd->length;
	if(nr > n)
		nr = n;	/* shouldn't happen */
	if(s & TxERR || s & BDReady || p != Done || ctlr->rd->status & BDEmpty || ctlr->timeout)
		return -1;
	memmove(buf, ctlr->rxbuf, nr);
	return nr;
}
