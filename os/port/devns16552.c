#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"

#include	"../port/netif.h"

/*
 *  Driver for the ns16552.
 */
enum
{
	/*
	 *  register numbers
	 */
	Data=	0,		/* xmit/rcv buffer */
	Iena=	1,		/* interrupt enable */
	 Ircv=	(1<<0),		/*  for char rcv'd */
	 Ixmt=	(1<<1),		/*  for xmit buffer empty */
	 Irstat=(1<<2),		/*  for change in rcv'er status */
	 Imstat=(1<<3),		/*  for change in modem status */
	Istat=	2,		/* interrupt flag (read) */
	 Ipend=	1,		/* interrupt pending (not) */
	 Fenabd=(3<<6),   		/*  on if fifo's enabled */
	Fifoctl=2,		/* fifo control (write) */
	 Fena=	(1<<0),		/*  enable xmit/rcv fifos */
	 Ftrig=	(1<<6),		/*  trigger after 4 input characters */
	 Fclear=(3<<1),		/*  clear xmit & rcv fifos */
	Format=	3,		/* byte format */
	 Bits8=	(3<<0),		/*  8 bits/byte */
	 Stop2=	(1<<2),		/*  2 stop bits */
	 Pena=	(1<<3),		/*  generate parity */
	 Peven=	(1<<4),		/*  even parity */
	 Pforce=(1<<5),		/*  force parity */
	 Break=	(1<<6),		/*  generate a break */
	 Dra=	(1<<7),		/*  address the divisor */
	Mctl=	4,		/* modem control */
	 Dtr=	(1<<0),		/*  data terminal ready */
	 Rts=	(1<<1),		/*  request to send */
	 Ri=	(1<<2),		/*  ring */
	 Inton=	(1<<3),		/*  turn on interrupts */
	 Loop=	(1<<4),		/*  loop back */
	Lstat=	5,		/* line status */
	 Inready=(1<<0),	/*  receive buffer full */
	 Oerror=(1<<1),		/*  receiver overrun */
	 Perror=(1<<2),		/*  receiver parity error */
	 Ferror=(1<<3),		/*  rcv framing error */
	 Berror=(1<<4),		/* break alarm */
	 Outready=(1<<5),	/*  output buffer full */
	Mstat=	6,		/* modem status */
	 Ctsc=	(1<<0),		/*  clear to send changed */
	 Dsrc=	(1<<1),		/*  data set ready changed */
	 Rire=	(1<<2),		/*  rising edge of ring indicator */
	 Dcdc=	(1<<3),		/*  data carrier detect changed */
	 Cts=	(1<<4),		/*  complement of clear to send line */
	 Dsr=	(1<<5),		/*  complement of data set ready line */
	 Ring=	(1<<6),		/*  complement of ring indicator line */
	 Dcd=	(1<<7),		/*  complement of data carrier detect line */
	Scratch=7,		/* scratchpad */
	Dlsb=	0,		/* divisor lsb */
	Dmsb=	1,		/* divisor msb */

	CTLS= 023,
	CTLQ= 021,

	Stagesize= 1024,
	Nuart=	32,		/* max per machine */
};

typedef struct Uart Uart;
struct Uart
{
	QLock;
	int	opens;

	int	enabled;
	Uart	*elist;			/* next enabled interface */
	char	name[KNAMELEN];

	uchar	sticky[8];		/* sticky write register values */
	ulong	port;
	ulong	freq;			/* clock frequency */
	uchar	mask;			/* bits/char */
	int	dev;
	int	baud;			/* baud rate */

	uchar	istat;			/* last istat read */
	int	frame;			/* framing errors */
	int	overrun;		/* rcvr overruns */

	/* buffers */
	int	(*putc)(Queue*, int);
	Queue	*iq;
	Queue	*oq;

	Lock	flock;			/* fifo */
	uchar	fifoon;			/* fifo's enabled */
	uchar	nofifo;			/* earlier chip version with nofifo */

	Lock	rlock;			/* receive */
	uchar	istage[Stagesize];
	uchar	*ip;
	uchar	*ie;

	int	haveinput;

	Lock	tlock;			/* transmit */
	uchar	ostage[Stagesize];
	uchar	*op;
	uchar	*oe;

	int	modem;			/* hardware flow control on */
	int	xonoff;			/* software flow control on */
	int	blocked;
	int	cts, dsr, dcd;		/* keep track of modem status */ 
	int	ctsbackoff;
	int	hup_dsr, hup_dcd;	/* send hangup upstream? */
	int	dohup;

	Rendez	r;
};

static Uart *uart[Nuart];
static int nuart;
static Uart *consuart;

struct Uartalloc {
	Lock;
	Uart *elist;	/* list of enabled interfaces */
} uartalloc;

void ns16552intr(int);

/*
 *  pick up architecture specific routines and definitions
 */
#include "ns16552.h"

/*
 *  set the baud rate by calculating and setting the baudrate
 *  generator constant.  This will work with fairly non-standard
 *  baud rates.
 */
static void
ns16552setbaud(Uart *p, int rate)
{
	ulong brconst;

	if(rate <= 0)
		return;

	brconst = (p->freq+8*rate-1)/(16*rate);

	uartwrreg(p, Format, Dra);
	outb(p->port + Dmsb, (brconst>>8) & 0xff);
	outb(p->port + Dlsb, brconst & 0xff);
	uartwrreg(p, Format, 0);

	p->baud = rate;
}

/*
 * decide if we should hangup when dsr or dcd drops.
 */
static void
ns16552dsrhup(Uart *p, int n)
{
	p->hup_dsr = n;
}

static void
ns16552dcdhup(Uart *p, int n)
{
	p->hup_dcd = n;
}

static void
ns16552parity(Uart *p, char type)
{
	switch(type){
	case 'e':
		p->sticky[Format] |= Pena|Peven;
		break;
	case 'o':
		p->sticky[Format] &= ~Peven;
		p->sticky[Format] |= Pena;
		break;
	default:
		p->sticky[Format] &= ~(Pena|Peven);
		break;
	}
	uartwrreg(p, Format, 0);
}

/*
 *  set bits/character, default 8
 */
void
ns16552bits(Uart *p, int bits)
{
	if(bits < 5 || bits > 8)
		error(Ebadarg);

	p->sticky[Format] &= ~3;
	p->sticky[Format] |= bits-5;

	uartwrreg(p, Format, 0);
}


/*
 *  toggle DTR
 */
void
ns16552dtr(Uart *p, int n)
{
	if(n)
		p->sticky[Mctl] |= Dtr;
	else
		p->sticky[Mctl] &= ~Dtr;

	uartwrreg(p, Mctl, 0);
}

/*
 *  toggle RTS
 */
void
ns16552rts(Uart *p, int n)
{
	if(n)
		p->sticky[Mctl] |= Rts;
	else
		p->sticky[Mctl] &= ~Rts;

	uartwrreg(p, Mctl, 0);
}

/*
 *  send break
 */
static void
ns16552break(Uart *p, int ms)
{
	if(ms == 0)
		ms = 200;

	uartwrreg(p, Format, Break);
	tsleep(&up->sleep, return0, 0, ms);
	uartwrreg(p, Format, 0);
}

static void
ns16552fifoon(Uart *p)
{
	ulong i, x;

	if(p->nofifo || uartrdreg(p, Istat) & Fenabd)
		return;

	x = splhi();

	/* reset fifos */
	p->sticky[Fifoctl] = 0;
	uartwrreg(p, Fifoctl, Fclear);

	/* empty buffer and interrupt conditions */
	for(i = 0; i < 16; i++){
		if(uartrdreg(p, Istat)){
			/* nothing to do */
		}
		if(uartrdreg(p, Data)){
			/* nothing to do */
		}
	}

	/* turn on fifo */
	p->fifoon = 1;
	p->sticky[Fifoctl] = Fena|Ftrig;
	uartwrreg(p, Fifoctl, 0);
	p->istat = uartrdreg(p, Istat);
	if((p->istat & Fenabd) == 0) {
		/* didn't work, must be an earlier chip type */
		p->nofifo = 1;
	}

	splx(x);
}

/*
 *  modem flow control on/off (rts/cts)
 */
static void
ns16552mflow(Uart *p, int n)
{
	ilock(&p->tlock);
	if(n){
		p->sticky[Iena] |= Imstat;
		uartwrreg(p, Iena, 0);
		p->modem = 1;
		p->cts = uartrdreg(p, Mstat) & Cts;
	} else {
		p->sticky[Iena] &= ~Imstat;
		uartwrreg(p, Iena, 0);
		p->modem = 0;
		p->cts = 1;
	}
	iunlock(&p->tlock);

//	ilock(&p->flock);
//	if(1)
//		/* turn on fifo's */
//		ns16552fifoon(p);
//	else {
//		/* turn off fifo's */
//		p->fifoon = 0;
//		p->sticky[Fifoctl] = 0;
//		uartwrreg(p, Fifoctl, Fclear);
//	}
//	iunlock(&p->flock);
}

/*
 *  turn on a port's interrupts.  set DTR and RTS
 */
static void
ns16552enable(Uart *p)
{
	Uart **l;

	if(p->enabled)
		return;

	uartpower(p->dev, 1);

	p->hup_dsr = p->hup_dcd = 0;
	p->cts = p->dsr = p->dcd = 0;

	/*
 	 *  turn on interrupts
	 */
	p->sticky[Iena] = Ircv | Ixmt | Irstat;
	uartwrreg(p, Iena, 0);

	/*
	 *  turn on DTR and RTS
	 */
	ns16552dtr(p, 1);
	ns16552rts(p, 1);

	ns16552fifoon(p);

	/*
	 *  assume we can send
	 */
	ilock(&p->tlock);
	p->cts = 1;
	p->blocked = 0;
	iunlock(&p->tlock);

	/*
	 *  set baud rate to the last used
	 */
	ns16552setbaud(p, p->baud);

	lock(&uartalloc);
	for(l = &uartalloc.elist; *l; l = &(*l)->elist){
		if(*l == p)
			break;
	}
	if(*l == 0){
		p->elist = uartalloc.elist;
		uartalloc.elist = p;
	}
	p->enabled = 1;
	unlock(&uartalloc);
}

/*
 *  turn off a port's interrupts.  reset DTR and RTS
 */
static void
ns16552disable(Uart *p)
{
	Uart **l;

	/*
 	 *  turn off interrupts
	 */
	p->sticky[Iena] = 0;
	uartwrreg(p, Iena, 0);

	/*
	 *  revert to default settings
	 */
	p->sticky[Format] = Bits8;
	uartwrreg(p, Format, 0);

	/*
	 *  turn off DTR, RTS, hardware flow control & fifo's
	 */
	ns16552dtr(p, 0);
	ns16552rts(p, 0);
	ns16552mflow(p, 0);
	ilock(&p->tlock);
	p->xonoff = p->blocked = 0;
	iunlock(&p->tlock);

	uartpower(p->dev, 0);

	lock(&uartalloc);
	for(l = &uartalloc.elist; *l; l = &(*l)->elist){
		if(*l == p){
			*l = p->elist;
			break;
		}
	}
	p->enabled = 0;
	unlock(&uartalloc);
}

/*
 *  put some bytes into the local queue to avoid calling
 *  qconsume for every character
 */
static int
stageoutput(Uart *p)
{
	int n;

	n = qconsume(p->oq, p->ostage, Stagesize);
	if(n <= 0)
		return 0;
	p->op = p->ostage;
	p->oe = p->ostage + n;
	return n;
}

/*
 *  (re)start output
 */
static void
ns16552kick0(Uart *p)
{
	int i;
	if((p->modem && (p->cts == 0)) || p->blocked)
		return;

	/*
	 *  128 here is an arbitrary limit to make sure
	 *  we don't stay in this loop too long.  If the
	 *  chips output queue is longer than 128, too
	 *  bad -- presotto
	 */
	for(i = 0; i < 128; i++){
		if(!(uartrdreg(p, Lstat) & Outready))
			break;
		if(p->op >= p->oe && stageoutput(p) == 0)
			break;
		outb(p->port + Data, *(p->op++));
	}
}

static void
ns16552kick(void *v)
{
	Uart *p;

	p = v;
	ilock(&p->tlock);
	ns16552kick0(p);
	iunlock(&p->tlock);
}

/*
 *  restart input if it's off
 */
static void
ns16552flow(void *v)
{
	Uart *p;

	p = v;
	if(p->modem)
		ns16552rts(p, 1);
	ilock(&p->rlock);
	p->haveinput = 1;
	iunlock(&p->rlock);
}

/*
 *  default is 9600 baud, 1 stop bit, 8 bit chars, no interrupts,
 *  transmit and receive enabled, interrupts disabled.
 */
static void
ns16552setup0(Uart *p)
{
	memset(p->sticky, 0, sizeof(p->sticky));
	/*
	 *  set rate to 9600 baud.
	 *  8 bits/character.
	 *  1 stop bit.
	 *  interrupts enabled.
	 */
	p->sticky[Format] = Bits8;
	uartwrreg(p, Format, 0);
	p->sticky[Mctl] |= Inton;
	uartwrreg(p, Mctl, 0x0);

	ns16552setbaud(p, 9600);

	p->iq = qopen(4*1024, 0, ns16552flow, p);
	p->oq = qopen(4*1024, 0, ns16552kick, p);
	if(p->iq == nil || p->oq == nil)
		panic("ns16552setup0");

	p->ip = p->istage;
	p->ie = &p->istage[Stagesize];
	p->op = p->ostage;
	p->oe = p->ostage;
}

/*
 *  called by main() to create a new duart
 */
void
ns16552setup(ulong port, ulong freq, char *name)
{
	Uart *p;

	if(nuart >= Nuart)
		return;

	p = xalloc(sizeof(Uart));
	uart[nuart] = p;
	strcpy(p->name, name);
	p->dev = nuart;
	nuart++;
	p->port = port;
	p->freq = freq;
	ns16552setup0(p);
}

/*
 *  called by main() to configure a duart port as a console or a mouse
 */
void
ns16552special(int port, int baud, Queue **in, Queue **out, int (*putc)(Queue*, int))
{
	Uart *p = uart[port];
	ns16552enable(p);
	if(baud)
		ns16552setbaud(p, baud);
	p->putc = putc;
	if(in)
		*in = p->iq;
	if(out)
		*out = p->oq;
	p->opens++;
}

/*
 *  handle an interrupt to a single uart
 */
void
ns16552intr(int dev)
{
	uchar ch;
	int s, l;
	Uart *p = uart[dev];

	for (s = uartrdreg(p, Istat); !(s&Ipend); s = uartrdreg(p, Istat)) {
		switch(s&0x3f){
		case 4:	/* received data available */
		case 6:	/* receiver line status (alarm or error) */
		case 12:	/* character timeout indication */
			while ((l = uartrdreg(p, Lstat)) & Inready) {
				if(l & Ferror)
					p->frame++;
				if(l & Oerror)
					p->overrun++;
				ch = uartrdreg(p, Data) & 0xff;
				if (l & (Berror|Perror|Ferror)) {
					/* ch came with break, parity or framing error - consume */
					continue;
				}
				if (ch == CTLS || ch == CTLQ) {
					ilock(&p->tlock);
					if(p->xonoff){
						if(ch == CTLS)
							p->blocked = 1;
						else
							p->blocked = 0;	/* clock gets output going again */
					}
					iunlock(&p->tlock);
				}
				if(p->putc)
					p->putc(p->iq, ch);
				else {
					ilock(&p->rlock);
					if(p->ip < p->ie)
						*p->ip++ = ch;
					else
						p->overrun++;
					p->haveinput = 1;
					iunlock(&p->rlock);
				}
			}
			break;

		case 2:	/* transmitter not full */
			ns16552kick(p);
			break;

		case 0:	/* modem status */
			ch = uartrdreg(p, Mstat);
			if(ch & Ctsc){
				ilock(&p->tlock);
				l = p->cts;
				p->cts = ch & Cts;
				if(l == 0 && p->cts)
					p->ctsbackoff = 2; /* clock gets output going again */
				iunlock(&p->tlock);
			}
	 		if (ch & Dsrc) {
				l = ch & Dsr;
				if(p->hup_dsr && p->dsr && !l){
					ilock(&p->rlock);
					p->dohup = 1;
					iunlock(&p->rlock);
				}
				p->dsr = l;
			}
	 		if (ch & Dcdc) {
				l = ch & Dcd;
				if(p->hup_dcd && p->dcd && !l){
					ilock(&p->rlock);
					p->dohup = 1;
					iunlock(&p->rlock);
				}
				p->dcd = l;
			}
			break;

		default:
			print("weird uart interrupt #%2.2ux\n", s);
			break;
		}
	}
	p->istat = s;
}

/*
 *  we save up input characters till clock time
 *
 *  There's also a bit of code to get a stalled print going.
 *  It shouldn't happen, but it does.  Obviously I don't
 *  understand something.  Since it was there, I bundled a
 *  restart after flow control with it to give some hysteresis
 *  to the hardware flow control.  This makes compressing
 *  modems happier but will probably bother something else.
 *	 -- presotto
 */
void
uartclock(void)
{
	int n;
	Uart *p;

	for(p = uartalloc.elist; p; p = p->elist){

		/* this amortizes cost of qproduce to many chars */
		if(p->haveinput){
			ilock(&p->rlock);
			if(p->haveinput){
				n = p->ip - p->istage;
				if(n > 0 && p->iq){
					if(n > Stagesize)
						panic("uartclock");
					if(qproduce(p->iq, p->istage, n) < 0)
						ns16552rts(p, 0);
					else
						p->ip = p->istage;
				}
				p->haveinput = 0;
			}
			iunlock(&p->rlock);
		}
		if(p->dohup){
			ilock(&p->rlock);
			if(p->dohup){
				qhangup(p->iq, 0);
				qhangup(p->oq, 0);
			}
			p->dohup = 0;
			iunlock(&p->rlock);
		}

		/* this adds hysteresis to hardware flow control */
		if(p->ctsbackoff){
			ilock(&p->tlock);
			if(p->ctsbackoff){
				if(--(p->ctsbackoff) == 0)
					ns16552kick0(p);
			}
			iunlock(&p->tlock);
		}
	}
}

Dirtab *ns16552dir;
int ndir;

static void
setlength(int i)
{
	Uart *p;

	if(i > 0){
		p = uart[i];
		if(p && p->opens && p->iq)
			ns16552dir[1+3*i].length = qlen(p->iq);
	} else for(i = 0; i < nuart; i++){
		p = uart[i];
		if(p && p->opens && p->iq)
			ns16552dir[1+3*i].length = qlen(p->iq);
	}
}

/*
 *  all uarts must be ns16552setup() by this point or inside of ns16552install()
 */
static void
ns16552reset(void)
{
	int i;
	Dirtab *dp;
	ns16552install();	/* architecture specific */

	ndir = 1+3*nuart;
	ns16552dir = xalloc(ndir * sizeof(Dirtab));
	dp = ns16552dir;
	strcpy(dp->name, ".");
	mkqid(&dp->qid, 0, 0, QTDIR);
	dp->length = 0;
	dp->perm = DMDIR|0555;
	dp++;
	for(i = 0; i < nuart; i++){
		/* 3 directory entries per port */
		strcpy(dp->name, uart[i]->name);
		dp->qid.path = NETQID(i, Ndataqid);
		dp->perm = 0666;
		dp++;
		sprint(dp->name, "%sctl", uart[i]->name);
		dp->qid.path = NETQID(i, Nctlqid);
		dp->perm = 0666;
		dp++;
		sprint(dp->name, "%sstatus", uart[i]->name);
		dp->qid.path = NETQID(i, Nstatqid);
		dp->perm = 0444;
		dp++;
	}
}

static Chan*
ns16552attach(char *spec)
{
	return devattach('t', spec);
}

static Walkqid*
ns16552walk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, ns16552dir, ndir, devgen);
}

static int
ns16552stat(Chan *c, uchar *dp, int n)
{
	if(NETTYPE(c->qid.path) == Ndataqid)
		setlength(NETID(c->qid.path));
	return devstat(c, dp, n, ns16552dir, ndir, devgen);
}

static Chan*
ns16552open(Chan *c, int omode)
{
	Uart *p;

	c = devopen(c, omode, ns16552dir, ndir, devgen);

	switch(NETTYPE(c->qid.path)){
	case Nctlqid:
	case Ndataqid:
		p = uart[NETID(c->qid.path)];
		qlock(p);
		if(p->opens++ == 0){
			ns16552enable(p);
			qreopen(p->iq);
			qreopen(p->oq);
		}
		qunlock(p);
		break;
	}

	return c;
}

static void
ns16552close(Chan *c)
{
	Uart *p;

	if(c->qid.type & QTDIR)
		return;
	if((c->flag & COPEN) == 0)
		return;
	switch(NETTYPE(c->qid.path)){
	case Ndataqid:
	case Nctlqid:
		p = uart[NETID(c->qid.path)];
		qlock(p);
		if(--(p->opens) == 0){
			ns16552disable(p);
			qclose(p->iq);
			qclose(p->oq);
			p->ip = p->istage;
			p->dcd = p->dsr = p->dohup = 0;
		}
		qunlock(p);
		break;
	}
}

static long
uartstatus(Chan*, Uart *p, void *buf, long n, long offset)
{
	uchar mstat, fstat, istat, tstat;
	char str[256];

	str[0] = 0;
	tstat = p->sticky[Mctl];
	mstat = uartrdreg(p, Mstat);
	istat = p->sticky[Iena];
	fstat = p->sticky[Format];
	snprint(str, sizeof str,
		"b%d c%d d%d e%d l%d m%d p%c r%d s%d\n"
		"%d %d %d%s%s%s%s%s\n",

		p->baud,
		p->hup_dcd, 
		(tstat & Dtr) != 0,
		p->hup_dsr,
		(fstat & Bits8) + 5,
		(istat & Imstat) != 0, 
		(fstat & Pena) ? ((fstat & Peven) ? 'e' : 'o') : 'n',
		(tstat & Rts) != 0,
		(fstat & Stop2) ? 2 : 1,

		p->dev,
		p->frame,
		p->overrun, 
		uartrdreg(p, Istat) & Fenabd       ? " fifo" : "",
		(mstat & Cts)    ? " cts"  : "",
		(mstat & Dsr)    ? " dsr"  : "",
		(mstat & Dcd)    ? " dcd"  : "",
		(mstat & Ring)   ? " ring" : ""
	);
	return readstr(offset, buf, n, str);
}

static long
ns16552read(Chan *c, void *buf, long n, vlong off)
{
	Uart *p;
	ulong offset = off;

	if(c->qid.type & QTDIR){
		setlength(-1);
		return devdirread(c, buf, n, ns16552dir, ndir, devgen);
	}

	p = uart[NETID(c->qid.path)];
	switch(NETTYPE(c->qid.path)){
	case Ndataqid:
		return qread(p->iq, buf, n);
	case Nctlqid:
		return readnum(offset, buf, n, NETID(c->qid.path), NUMSIZE);
	case Nstatqid:
		return uartstatus(c, p, buf, n, offset);
	}

	return 0;
}

static void
ns16552ctl(Uart *p, char *cmd)
{
	int i, n;

	/* let output drain for a while */
	for(i = 0; i < 16 && qlen(p->oq); i++)
		tsleep(&p->r, (int(*)(void*))qlen, p->oq, 125);

	if(strncmp(cmd, "break", 5) == 0){
		ns16552break(p, 0);
		return;
	}


	n = atoi(cmd+1);
	switch(*cmd){
	case 'B':
	case 'b':
		ns16552setbaud(p, n);
		break;
	case 'C':
	case 'c':
		ns16552dcdhup(p, n);
		break;
	case 'D':
	case 'd':
		ns16552dtr(p, n);
		break;
	case 'E':
	case 'e':
		ns16552dsrhup(p, n);
		break;
	case 'f':
	case 'F':
		qflush(p->oq);
		break;
	case 'H':
	case 'h':
		qhangup(p->iq, 0);
		qhangup(p->oq, 0);
		break;
	case 'L':
	case 'l':
		ns16552bits(p, n);
		break;
	case 'm':
	case 'M':
		ns16552mflow(p, n);
		break;
	case 'n':
	case 'N':
		qnoblock(p->oq, n);
		break;
	case 'P':
	case 'p':
		ns16552parity(p, *(cmd+1));
		break;
	case 'K':
	case 'k':
		ns16552break(p, n);
		break;
	case 'R':
	case 'r':
		ns16552rts(p, n);
		break;
	case 'Q':
	case 'q':
		qsetlimit(p->iq, n);
		qsetlimit(p->oq, n);
		break;
	case 'W':
	case 'w':
		/* obsolete */
		break;
	case 'X':
	case 'x':
		ilock(&p->tlock);
		p->xonoff = n;
		iunlock(&p->tlock);
		break;
	}
}

static long
ns16552write(Chan *c, void *buf, long n, vlong)
{
	Uart *p;
	char cmd[32];

	if(c->qid.type & QTDIR)
		error(Eperm);

	p = uart[NETID(c->qid.path)];

	/*
	 *  The fifo's turn themselves off sometimes.
	 *  It must be something I don't understand. -- presotto
	 */
	lock(&p->flock);
	if((p->istat & Fenabd) == 0 && p->fifoon && p->nofifo == 0)
		ns16552fifoon(p);
	unlock(&p->flock);

	switch(NETTYPE(c->qid.path)){
	case Ndataqid:
		return qwrite(p->oq, buf, n);
	case Nctlqid:
		if(n >= sizeof(cmd))
			n = sizeof(cmd)-1;
		memmove(cmd, buf, n);
		cmd[n] = 0;
		ns16552ctl(p, cmd);
		return n;
	}
}

static int
ns16552wstat(Chan *c, uchar *dp, int n)
{
	Dir d;
	Dirtab *dt;

	if(!iseve())
		error(Eperm);
	if(c->qid.type & QTDIR)
		error(Eperm);
	if(NETTYPE(c->qid.path) == Nstatqid)
		error(Eperm);

	dt = &ns16552dir[1+3 * NETID(c->qid.path)];
	n = convM2D(dp, n, &d, nil);
	if(n == 0)
		error(Eshortstat);
	if(d.mode != ~0UL){
		d.mode &= 0666;
		dt[0].perm = dt[1].perm = d.mode;
	}
	return n;
}

Dev ns16552devtab = {
	't',
	"ns16552",

	ns16552reset,
	devinit,
	devshutdown,
	ns16552attach,
	ns16552walk,
	ns16552stat,
	ns16552open,
	devcreate,
	ns16552close,
	ns16552read,
	devbread,
	ns16552write,
	devbwrite,
	devremove,
	ns16552wstat,
};

void
uartputc(int c)
{
	Uart *p;
	int i;

	p = consuart;
	if(p == nil)
		return;
	for(i = 0; !(uartrdreg(p, Lstat)&Outready) && i < 128; i++)
		delay(1);
	outb(p->port+Data, c);
	for(i = 0; !(uartrdreg(p, Lstat)&Outready) && i < 128; i++)
		delay(1);
}

void
uartputs(char *s, int n)
{
	char *e;

	if(consuart == nil)
		return;
	e = s+n;
	for(; s < e; s++){
		if(*s == '\n')
			uartputc('\r');
		uartputc(*s);
	}
}
