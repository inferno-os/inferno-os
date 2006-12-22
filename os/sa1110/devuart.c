#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"
#include	"../port/netif.h"

/*
 * currently no DMA or flow control (hardware or software)
 */

enum
{
	Stagesize= 1024,
	Dmabufsize=Stagesize/2,
	Nuart=7,		/* max per machine */

	CTLS= 023,
	CTLQ= 021,
};

typedef struct Uart Uart;
struct Uart
{
	QLock;

	int	opens;

	int	enabled;

	int	frame;		/* framing errors */
	int	overrun;	/* rcvr overruns */
	int	soverrun;	/* software overruns */
	int	perror;		/* parity error */
	int	bps;		/* baud rate */
	uchar	bits;
	char	parity;

	int	inters;		/* total interrupt count */
	int	rinters;	/* interrupts due to read */
	int	winters;	/* interrupts due to write */

	int	rcount;		/* total read count */
	int	wcount;		/* total output count */

	int	xonoff;		/* software flow control on */
	int	blocked;		/* output blocked */

	/* buffers */
	int	(*putc)(Queue*, int);
	Queue	*iq;
	Queue	*oq;

	int	port;
	UartReg	*reg;

	/* staging areas to avoid some of the per character costs */
	uchar	*ip;
	uchar	*ie;
	uchar	*op;
	uchar	*oe;

	/* put large buffers last to aid register-offset optimizations: */
	char	name[KNAMELEN];
	uchar	istage[Stagesize];
	uchar	ostage[Stagesize];
};

enum {
	UTCR0_PE=	0x01,
	UTCR0_OES=	0x02,
	UTCR0_SBS=	0x04,
	UTCR0_DSS=	0x08,
	UTCR0_SCE=	0x10,
	UTCR0_RCE=	0x20,
	UTCR0_TCE=	0x40,

	UTCR3_RXE=	0x01,
	UTCR3_TXE=	0x02,
	UTCR3_BRK=	0x04,
	UTCR3_RIM=	0x08,
	UTCR3_TIM=	0x10,
	UTCR3_LBM=	0x20,

	UTSR0_TFS=	0x01,
	UTSR0_RFS=	0x02,
	UTSR0_RID=	0x04,
	UTSR0_RBB=	0x08,
	UTSR0_REB=	0x10,
	UTSR0_EIF=	0x20,

	UTSR1_TBY=	0x01,
	UTSR1_RNE=	0x02,
	UTSR1_TNF=	0x04,
	UTSR1_PRE=	0x08,
	UTSR1_FRE=	0x10,
	UTSR1_ROR=	0x20,
};

static Uart *uart[Nuart];
static int nuart;
static int uartspcl;
int redirectconsole;

static void
uartset(Uart *p)
{
	UartReg *reg = p->reg;
	ulong ocr3;
	ulong brdiv;
	int n;

	brdiv = CLOCKFREQ/16/p->bps - 1;
	ocr3 = reg->utcr3;
	reg->utcr3 = ocr3&~(UTCR3_RXE|UTCR3_TXE);
	reg->utcr1 = brdiv >> 8;
	reg->utcr2 = brdiv & 0xff;
	/* set PE and OES appropriately for o/e/n: */
	reg->utcr0 = ((p->parity&3)^UTCR0_OES)|(p->bits&UTCR0_DSS);
	reg->utcr3 = ocr3;

	/* set buffer length according to speed, to allow
	 * at most a 200ms delay before dumping the staging buffer
	 * into the input queue
	 */
	n = p->bps/(10*1000/200);
	p->ie = &p->istage[n < Stagesize ? n : Stagesize];
}

/*
 *  send break
 */
static void
uartbreak(Uart *p, int ms)
{
	UartReg *reg = p->reg;
	if(ms == 0)
		ms = 200;
	reg->utcr3 |= UTCR3_BRK;
	tsleep(&up->sleep, return0, 0, ms);
	reg->utcr3 &= ~UTCR3_BRK;
}

/*
 *  turn on a port
 */
static void
uartenable(Uart *p)
{
	UartReg *reg = p->reg;

	if(p->enabled)
		return;

	archuartpower(p->port, 1);
	uartset(p);
	reg->utsr0 = 0xff;		// clear all sticky status bits
	// enable receive, transmit, and receive interrupt:
	reg->utcr3 = UTCR3_RXE|UTCR3_TXE|UTCR3_RIM;
	p->blocked = 0;
	p->xonoff = 0;
	p->enabled = 1;
}

/*
 *  turn off a port
 */
static void
uartdisable(Uart *p)
{
	p->reg->utcr3 = 0;		// disable TX, RX, and ints
	p->blocked = 0;
	p->xonoff = 0;
	p->enabled = 0;
	archuartpower(p->port, 0);
}

/*
 *  put some bytes into the local queue to avoid calling
 *  qconsume for every character
 */
static int
stageoutput(Uart *p)
{
	int n;
	Queue *q = p->oq;

	if(q == nil)
		return 0;
	n = qconsume(q, p->ostage, Stagesize);
	if(n <= 0)
		return 0;
	p->op = p->ostage;
	p->oe = p->ostage + n;
	return n;
}

static void
uartxmit(Uart *p)
{
	UartReg *reg = p->reg;
	ulong e = 0;

	if(!p->blocked) {
		while(p->op < p->oe || stageoutput(p)) {	
			if(reg->utsr1 & UTSR1_TNF) {
				reg->utdr = *(p->op++);
				p->wcount++;
			} else {
				e = UTCR3_TIM;
				break;
			}
		}
	}
	reg->utcr3 = (reg->utcr3&~UTCR3_TIM)|e;
}

static void
uartrecvq(Uart *p)
{
	uchar *cp = p->istage;
	int n = p->ip - cp;

	if(n == 0)
		return;
	if(p->putc)
		while(n-- > 0) 
			p->putc(p->iq, *cp++);
	else if(p->iq) 
		if(qproduce(p->iq, p->istage, n) < n){
			/* if xonoff, should send XOFF when qwindow(p->iq) < threshold */
			p->soverrun++;
			//print("qproduce flow control");
		}
	p->ip = p->istage;
}

static void
uartrecv(Uart *p)
{
	UartReg *reg = p->reg;
	ulong n;
	while(reg->utsr1 & UTSR1_RNE) {
		int c;
		n = reg->utsr1;
		c = reg->utdr;
		if(n & (UTSR1_PRE|UTSR1_FRE|UTSR1_ROR)) {
			if(n & UTSR1_PRE) 
				p->perror++;
			if(n & UTSR1_FRE) 
				p->frame++;
			if(n & UTSR1_ROR) 
				p->overrun++;
			continue;
		}
		if(p->xonoff){
			if(c == CTLS){
				p->blocked = 1;
			}else if (c == CTLQ){
				p->blocked = 0;
			}
		}
		*p->ip++ = c;
		if(p->ip >= p->ie)
			uartrecvq(p);
		p->rcount++;
	}
	if(reg->utsr0 & UTSR0_RID) {
		reg->utsr0 = UTSR0_RID;
		uartrecvq(p);
	}
}

static void
uartclock(void)
{
	Uart *p;
	int i;

	for(i=0; i<nuart; i++){
		p = uart[i];
		if(p != nil)
			uartrecvq(p);
	}
}

static void
uartkick(void *a)
{
	Uart *p = a;
	int x;

	x = splhi();
	uartxmit(p);
	splx(x);
}

/*
 *  UART Interrupt Handler
 */
static void
uartintr(Ureg*, void* arg)
{
	Uart *p = arg;			
	UartReg *reg = p->reg;
	ulong m = reg->utsr0;
	int dokick;

	dokick = p->blocked;
	p->inters++;
	if(m & (UTSR0_RFS|UTSR0_RID|UTSR0_EIF)) {
		p->rinters++;
		uartrecv(p);
	}
	if(p->blocked)
		dokick = 0;
	if((m & UTSR0_TFS) && (reg->utcr3&UTCR3_TIM || dokick)) {
		p->winters++;
		uartxmit(p);
	}

	if(m & (UTSR0_RBB|UTSR0_REB)) {
		//print("<BREAK>");
		/* reg->utsr0 = UTSR0_RBB|UTSR0_REB; */
		reg->utsr0 = m & (UTSR0_RBB|UTSR0_REB);
		/* what to do? if anything */
	}
}

static void
uartsetup(ulong port, char *name)
{
	Uart *p;

	if(nuart >= Nuart)
		return;

	p = xalloc(sizeof(Uart));
	uart[nuart++] = p;
	strcpy(p->name, name);

	p->port = port;
	p->reg = UARTREG(port);
	p->bps = 9600;
	p->bits = 8;
	p->parity = 'n';

	p->iq = qopen(4*1024, 0, 0 , p);
	p->oq = qopen(4*1024, 0, uartkick, p);

	p->ip = p->istage;
	p->ie = &p->istage[Stagesize];
	p->op = p->ostage;
	p->oe = p->ostage;
	if(port == 1)
		GPCLKREG->gpclkr0 |= 1;	/* SUS=1 for uart on serial 1 */

	intrenable(UARTbit(port), uartintr, p, BusCPU, name);
}

static void
uartinstall(void)
{
	static int already;

	if(already)
		return;
	already = 1;

	uartsetup(3, "eia0");
	uartsetup(1, "eia1");
	addclock0link(uartclock, 22);
}

/*
 *  called by main() to configure a duart port as a console or a mouse
 */
void
uartspecial(int port, int bps, char parity, Queue **in, Queue **out, int (*putc)(Queue*, int))
{
	Uart *p;

	uartinstall();
	if(port >= nuart) 
		return;
	p = uart[port];
	if(bps) 
		p->bps = bps;
	if(parity)
		p->parity = parity;
	uartenable(p);
	p->putc = putc;
	if(in)
		*in = p->iq;
	if(out)
		*out = p->oq;
	p->opens++;
	uartspcl = 1;
}

Dirtab *uartdir;
int ndir;

static void
setlength(int i)
{
	Uart *p;

	if(i > 0){
		p = uart[i];
		if(p && p->opens && p->iq)
			uartdir[1+3*i].length = qlen(p->iq);
	} else for(i = 0; i < nuart; i++){
		p = uart[i];
		if(p && p->opens && p->iq)
			uartdir[1+3*i].length = qlen(p->iq);
	}
}

/*
 *  all uarts must be uartsetup() by this point or inside of uartinstall()
 */
static void
uartreset(void)
{
	int i;
	Dirtab *dp;

	uartinstall();

	ndir = 1+3*nuart;
	uartdir = xalloc(ndir * sizeof(Dirtab));
	dp = uartdir;
	strcpy(dp->name, ".");
	mkqid(&dp->qid, 0, 0, QTDIR);
	dp->length = 0;
	dp->perm = DMDIR|0555;
	dp++;
	for(i = 0; i < nuart; i++){
		/* 3 directory entries per port */
		strcpy(dp->name, uart[i]->name);
		dp->qid.path = NETQID(i, Ndataqid);
		dp->perm = 0660;
		dp++;
		sprint(dp->name, "%sctl", uart[i]->name);
		dp->qid.path = NETQID(i, Nctlqid);
		dp->perm = 0660;
		dp++;
		sprint(dp->name, "%sstatus", uart[i]->name);
		dp->qid.path = NETQID(i, Nstatqid);
		dp->perm = 0444;
		dp++;
	}
}

static Chan*
uartattach(char *spec)
{
	return devattach('t', spec);
}

static Walkqid*
uartwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, uartdir, ndir, devgen);
}

static int
uartstat(Chan *c, uchar *dp, int n)
{
	if(NETTYPE(c->qid.path) == Ndataqid)
		setlength(NETID(c->qid.path));
	return devstat(c, dp, n, uartdir, ndir, devgen);
}

static Chan*
uartopen(Chan *c, int omode)
{
	Uart *p;

	c = devopen(c, omode, uartdir, ndir, devgen);

	switch(NETTYPE(c->qid.path)){
	case Nctlqid:
	case Ndataqid:
		p = uart[NETID(c->qid.path)];
		qlock(p);
		if(p->opens++ == 0){
			uartenable(p);
			qreopen(p->iq);
			qreopen(p->oq);
		}
		qunlock(p);
		break;
	}

	return c;
}

static void
uartclose(Chan *c)
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
			uartdisable(p);
			qclose(p->iq);
			qclose(p->oq);
			p->ip = p->istage;
		}
		qunlock(p);
		break;
	}
}

static long
uartstatus(Chan *c, Uart *p, void *buf, long n, long offset)
{
	char str[256];
	USED(c);

	str[0] = 0;
	snprint(str, sizeof(str),
			"b%d l%d p%c s%d x%d\n"
			"opens %d ferr %d oerr %d perr %d baud %d parity %c"
			" intr %d rintr %d wintr %d"
			" rcount %d wcount %d",
		p->bps, p->bits, p->parity, (p->reg->utcr0&UTCR0_SBS)?2:1, p->xonoff,
		p->opens, p->frame, p->overrun+p->soverrun, p->perror, p->bps, p->parity,
		p->inters, p->rinters, p->winters,
		p->rcount, p->wcount);

	strcat(str, "\n");
	return readstr(offset, buf, n, str);
}

static long
uartread(Chan *c, void *buf, long n, vlong offset)
{
	Uart *p;

	if(c->qid.type & QTDIR){
		setlength(-1);
		return devdirread(c, buf, n, uartdir, ndir, devgen);
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
uartctl(Uart *p, char *cmd)
{
	int i, n;

	/* let output drain for a while (up to 4 secs) */
	for(i = 0; i < 200 && (qlen(p->oq) || p->reg->utsr1 & UTSR1_TBY); i++)
		tsleep(&up->sleep, return0, 0, 20);

	if(strncmp(cmd, "break", 5) == 0){
		uartbreak(p, 0);
		return;
	}

	n = atoi(cmd+1);
	switch(*cmd){
	case 'B':
	case 'b':
		if(n <= 0) 
			error(Ebadarg);
		p->bps = n;
		uartset(p);
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
		if(n < 7 || n > 8)
			error(Ebadarg);
		p->bits = n;
		uartset(p);
		break;
	case 'n':
	case 'N':
		qnoblock(p->oq, n);
		break;
	case 'P':
	case 'p':
		p->parity = *(cmd+1);
		uartset(p);
		break;
	case 'K':
	case 'k':
		uartbreak(p, n);
		break;
	case 'Q':
	case 'q':
		qsetlimit(p->iq, n);
		qsetlimit(p->oq, n);
		break;
	case 'X':
	case 'x':
		p->xonoff = n;
		break;
	}
}

static long
uartwrite(Chan *c, void *buf, long n, vlong offset)
{
	Uart *p;
	char cmd[32];

	USED(offset);

	if(c->qid.type & QTDIR)
		error(Eperm);

	p = uart[NETID(c->qid.path)];

	switch(NETTYPE(c->qid.path)){
	case Ndataqid:
		return qwrite(p->oq, buf, n);
	case Nctlqid:

		if(n >= sizeof(cmd))
			n = sizeof(cmd)-1;
		memmove(cmd, buf, n);
		cmd[n] = 0;
		uartctl(p, cmd);
		return n;
	}
}

static int
uartwstat(Chan *c, uchar *dp, int n)
{
	Dir d;
	Dirtab *dt;

	if(!iseve())
		error(Eperm);
	if(c->qid.type & QTDIR)
		error(Eperm);
	if(NETTYPE(c->qid.path) == Nstatqid)
		error(Eperm);

	dt = &uartdir[1+3 * NETID(c->qid.path)];
	n = convM2D(dp, n, &d, nil);
	if(d.mode != ~0UL){
		d.mode &= 0666;
		dt[0].perm = dt[1].perm = d.mode;
	}
	return n;
}

void
uartpower(int on)
{
	Uart *p;
	int i;

	for(i=0; i<nuart; i++){
		p = uart[i];
		if(p != nil && p->opens){
			if(on && !p->enabled){
				p->enabled = 0;
				uartenable(p);
				uartkick(p);
			}else{
				if(p->port != 3)	/* leave the console */
					uartdisable(p);
				p->enabled = 0;
			}
		}
	}
}

Dev uartdevtab = {
	't',
	"uart",

	uartreset,
	devinit,
	devshutdown,
	uartattach,
	uartwalk,
	uartstat,
	uartopen,
	devcreate,
	uartclose,
	uartread,
	devbread,
	uartwrite,
	devbwrite,
	devremove,
	uartwstat,
	uartpower,
};

/*
 * for use by iprint
 */
void
uartputc(int c)
{
	UartReg *r;

	if(!uartspcl && !redirectconsole)
		return;
	if(c == 0)
		return;
	r = UARTREG(3);
	while((r->utsr1 & UTSR1_TNF) == 0)
		{}
	r->utdr = c;
	if(c == '\n')
		while(r->utsr1 & UTSR1_TBY)	/* flush xmit fifo */
			{}
}

void
uartputs(char *data, int len)
{
	int s;

	if(!uartspcl && !redirectconsole)
		return;
	clockpoll();
	s = splfhi();
	while(--len >= 0){
		if(*data == '\n')
			uartputc('\r');
		uartputc(*data++);
	}
	splx(s);
}

/*
 * for use by debugger
 */
int
uartgetc(void)
{
	UartReg *r;

	if(!uartspcl)
		return -1;
	clockcheck();
	r = UARTREG(3);
	while(!(r->utsr1 & UTSR1_RNE))
		clockcheck();
	return r->utdr;
}
