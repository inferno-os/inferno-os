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

/*
 * problems fixed from previous vsn:
 *
 *	- no kick on queue's, so redirections weren't getting
 *	  started until the clock tick
 *
 *	- lots of unnecessary overhead
 *
 *	- initialization sequencing
 *
 *	- uart[n] no longer indexed before calling uartinstall()
 */
#define DEBUG	if(0)iprint

static void uartintr(Ureg*, void*);

enum
{
	Stagesize= 1024,
	Dmabufsize=Stagesize/2,
	Nuart=7,		/* max per machine */
};

typedef struct Uart Uart;
struct Uart
{
	QLock;

	int	opens;

	int	enabled;

	int	port;			/* 0 or 1 */
	int	kickme;		/* for kick */
	int	frame;		/* framing errors */
	int	overrun;	/* rcvr overruns */
	int	perror;		/* parity error */
	int	bps;		/* baud rate */
	uchar	bits;
	char	parity;
	uchar	stop;

	int	inters;		/* total interrupt count */
	int	rinters;	/* interrupts due to read */
	int	winters;	/* interrupts due to write */

	int	rcount;		/* total read count */
	int	wcount;		/* total output count */

	/* buffers */
	int	(*putc)(Queue*, int);
	Queue	*iq;
	Queue	*oq;

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

#define UCON_ENABLEMASK (UCON_RXMDMASK | UCON_TXMDMASK | UCON_SINTMASK)
#define UCON_ENABLESET (UCON_RXMDINT | UCON_TXMDINT | UCON_SINTON)
#define UCON_DISABLESET (UCON_RXMDOFF | UCON_TXMDOFF | UCON_SINTOFF)

static Uart *uart[Nuart];
static int nuart;

static uchar
readstatus(Uart *p)
{
	UartReg *reg = p->reg;
	uchar stat = reg->stat;
	if (stat & USTAT_OV)
		p->overrun++;
	if (stat & USTAT_PE)
		p->perror++;
	if (stat & USTAT_FE)
		p->frame++;
	return stat;
}
	
static void
uartset(Uart *p)
{
	UartReg *reg = p->reg;
	ulong denom;
	ulong brdiv;
	int n;
	uchar lcon;

	lcon= ULCON_CLOCKMCLK | ULCON_IROFF;
	lcon |= ULCON_WL5 + (p->bits - 5);
	lcon |= p->stop == 1 ? ULCON_STOP1 : ULCON_STOP2;
	switch (p->parity) {
	default:
	case 'n':
		lcon |= ULCON_PMDNONE;
		break;
	case 'o':
		lcon |= ULCON_PMDODD;
		break;
	case 'e':
		lcon |= ULCON_PMDEVEN;
		break;
	}
	reg->lcon = lcon;

	/* clear the break and loopback bits; leave everything else alone */
	reg->con = (reg->con & ~(UCON_BRKMASK | UCON_LOOPMASK)) | UCON_BRKOFF | UCON_LOOPOFF;

	denom = 2 * 16 * p->bps;
	brdiv = (TIMER_HZ + denom / 2) / denom - 1;
	reg->brdiv = brdiv << 4;

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
	reg->con |= UCON_BRKON;
	tsleep(&up->sleep, return0, 0, ms);
	reg->con &= ~UCON_BRKON;
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

	uartset(p);
	// enable receive, transmit, and receive interrupt:
	reg->con = (reg->con & UCON_ENABLEMASK) | UCON_ENABLESET;
	p->enabled = 1;
}

/*
 *  turn off a port
 */
static void
uartdisable(Uart *p)
{
	p->reg->con = (p->reg->con & UCON_ENABLEMASK) | UCON_DISABLESET;
	p->enabled = 0;
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

	if(!q)
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
	ulong gag = 1;
	while(p->op < p->oe || stageoutput(p)) {	
		if(readstatus(p) & USTAT_TBE) {
			DEBUG("T");
			reg->txbuf = *(p->op++);
			p->wcount++;
		} else {
			DEBUG("F");
			gag = 0;
			break;
		}
	}
	if (gag) {
		DEBUG("G");
		p->kickme = 1;
		intrmask(UARTTXbit(p->port), 0);
	}
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
		if(qproduce(p->iq, p->istage, n) < n)
			print("qproduce flow control");
	p->ip = p->istage;
}

static void
uartrecv(Uart *p)
{
	UartReg *reg = p->reg;
	uchar stat = readstatus(p);

DEBUG("R");
	if (stat & USTAT_RDR) {
		int c;
		c = reg->rxbuf;
		if (c == '?') {		
			DEBUG("mod 0x%.8lx\n", INTREG->mod);
			DEBUG("msk 0x%.8lx\n", INTREG->msk);
			DEBUG("pnd 0x%.8lx\n", INTREG->pnd);
		}
		*p->ip++ = c;
/*		if(p->ip >= p->ie) */
			uartrecvq(p);
		p->rcount++;
	}
}

static void
uartkick(void *a)
{
	Uart *p = a;
	int x = splhi();
	DEBUG("k");
	if (p->kickme) {
		p->kickme = 0;
		DEBUG("K");
		intrunmask(UARTTXbit(p->port), 0);
	}
	splx(x);
}

/*
 *  UART Interrupt Handler
 */
static void
uarttxintr(Ureg*, void* arg)
{
	Uart *p = arg;			
	intrclear(UARTTXbit(p->port), 0);
	p->inters++;
	p->winters++;
	uartxmit(p);
}

static void
uartrxintr(Ureg*, void* arg)
{
	Uart *p = arg;			
	intrclear(UARTRXbit(p->port), 0);
	p->inters++;
	p->rinters++;
	uartrecv(p);
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

	p->reg = &UARTREG[port];
	p->bps = 9600;
	p->bits = 8;
	p->parity = 'n';
	p->stop = 1;
	p->kickme = 0;
	p->port = port;

	p->iq = qopen(4*1024, 0, 0 , p);
	p->oq = qopen(4*1024, 0, uartkick, p);

	p->ip = p->istage;
	p->ie = &p->istage[Stagesize];
	p->op = p->ostage;
	p->oe = p->ostage;

	intrenable(UARTTXbit(port), uarttxintr, p, 0); 
	intrenable(UARTRXbit(port), uartrxintr, p, 0); 
}

static void
uartinstall(void)
{
	static int already;

	if(already)
		return;
	already = 1;

	uartsetup(0, "eia0");
//	uartsetup(1, "eia1");
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
	sprint(str, "opens %d ferr %d oerr %d perr %d baud %d parity %c"
			" intr %d rintr %d wintr %d"
			" rcount %d wcount %d",
		p->opens, p->frame, p->overrun, p->perror, p->bps, p->parity,
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
	for(i = 0; i < 200 && (qlen(p->oq) || (readstatus(p) & USTAT_TC) == 0); i++)
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
	case 's':
	case 'S':
		if(n < 1 || n > 2)
			error(Ebadarg);
		p->stop = n;
		uartset(p);
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
	error(Eperm);
	return 0;
#ifdef xxx
	Dir d;
	Dirtab *dt;

	if(!iseve())
		error(Eperm);
	if(c->qid.type & QTDIR)
		error(Eperm);
	if(NETTYPE(c->qid.path) == Nstatqid)
		error(Eperm);

	dt = &uartdir[3 * NETID(c->qid.path)];
	convM2D(dp, &d);
	d.mode &= 0666;
	dt[0].perm = dt[1].perm = d.mode;
#endif
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
};

void
uartputc(int c)
{
	UartReg *u;

	if (!c)
		return;
	u = &UARTREG[1];
	while ((u->stat & USTAT_TBE) == 0)
		;
	u->txbuf = c;
	if (c == '\n')
		while((u->stat & USTAT_TC) == 0)	/* flush xmit fifo */
			;
}

void
uartputs(char *data, int len)
{
	int x;

	clockpoll();
	x = splfhi();
	while (len--){
		if(*data == '\n')
			uartputc('\r');
		uartputc(*data++);
	}
	splx(x);
}

int
uartgetc(void)
{
	UartReg *u;

	clockcheck();
	u = &UARTREG[1];
	while((u->stat & USTAT_RDR) == 0)
		clockcheck();
	return u->rxbuf;
}
