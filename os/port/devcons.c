#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	<version.h>
#include	"mp.h"
#include	"libsec.h"
#include	"keyboard.h"

extern int cflag;
extern int keepbroken;

void	(*serwrite)(char *, int);

Queue*	kscanq;			/* keyboard raw scancodes (when needed) */
char*	kscanid;		/* name of raw scan format (if defined) */
Queue*	kbdq;			/* unprocessed console input */
Queue*	lineq;			/* processed console input */
Queue*	printq;			/* console output */
Queue*	klogq;			/* kernel print (log) output */
int	iprintscreenputs;

static struct
{
	RWlock;
	Queue*	q;
} kprintq;

static struct
{
	QLock;

	int	raw;		/* true if we shouldn't process input */
	int	ctl;		/* number of opens to the control file */
	int	kbdr;		/* number of open reads to the keyboard */
	int	scan;		/* true if reading raw scancodes */
	int	x;		/* index into line */
	char	line[1024];	/* current input line */

	char	c;
	int	count;
	int	repeat;
} kbd;

char*	sysname;
char*	eve;

enum
{
	CMreboot,
	CMhalt,
	CMpanic,
	CMbroken,
	CMnobroken,
	CMconsole,
};

static Cmdtab sysctlcmd[] =
{
	CMreboot,	"reboot",	0,
	CMhalt,	"halt", 0,
	CMpanic,	"panic", 0,
	CMconsole,	"console", 1,
	CMbroken,	"broken", 0,
	CMnobroken,	"nobroken", 0,
};

void
printinit(void)
{
	lineq = qopen(2*1024, 0, nil, nil);
	if(lineq == nil)
		panic("printinit");
	qnoblock(lineq, 1);
}

/*
 *  return true if current user is eve
 */
int
iseve(void)
{
	Osenv *o;

	o = up->env;
	return strcmp(eve, o->user) == 0;
}

static int
consactive(void)
{
	if(printq)
		return qlen(printq) > 0;
	return 0;
}

static void
prflush(void)
{
	ulong now;

	now = m->ticks;
	while(serwrite==nil && consactive())
		if(m->ticks - now >= HZ)
			break;
}

/*
 *   Print a string on the console.  Convert \n to \r\n for serial
 *   line consoles.  Locking of the queues is left up to the screen
 *   or uart code.  Multi-line messages to serial consoles may get
 *   interspersed with other messages.
 */
static void
putstrn0(char *str, int n, int usewrite)
{
	int m;
	char *t;
	char buf[PRINTSIZE+2];

	/*
	 *  if kprint is open, put the message there, otherwise
	 *  if there's an attached bit mapped display,
	 *  put the message there.
	 */
	m = consoleprint;
	if(canrlock(&kprintq)){
		if(kprintq.q != nil){
			if(waserror()){
				runlock(&kprintq);
				nexterror();
			}
			if(usewrite)
				qwrite(kprintq.q, str, n);
			else
				qiwrite(kprintq.q, str, n);
			poperror();
			m = 0;
		}
		runlock(&kprintq);
	}
	if(m && screenputs != nil)
		screenputs(str, n);

	/*
	 *  if there's a serial line being used as a console,
	 *  put the message there.
	 */
	if(serwrite != nil) {
		serwrite(str, n);
		return;
	}

	if(printq == 0)
		return;

	while(n > 0) {
		t = memchr(str, '\n', n);
		if(t && !kbd.raw) {
			m = t - str;
			if(m > sizeof(buf)-2)
				m = sizeof(buf)-2;
			memmove(buf, str, m);
			buf[m] = '\r';
			buf[m+1] = '\n';
			if(usewrite)
				qwrite(printq, buf, m+2);
			else
				qiwrite(printq, buf, m+2);
			str = t + 1;
			n -= m + 1;
		} else {
			if(usewrite)
				qwrite(printq, str, n);
			else 
				qiwrite(printq, str, n);
			break;
		}
	}
}

void
putstrn(char *str, int n)
{
	putstrn0(str, n, 0);
}

int
snprint(char *s, int n, char *fmt, ...)
{
	va_list arg;

	va_start(arg, fmt);
	n = vseprint(s, s+n, fmt, arg) - s;
	va_end(arg);

	return n;
}

int
sprint(char *s, char *fmt, ...)
{
	int n;
	va_list arg;

	va_start(arg, fmt);
	n = vseprint(s, s+PRINTSIZE, fmt, arg) - s;
	va_end(arg);

	return n;
}

int
print(char *fmt, ...)
{
	int n;
	va_list arg;
	char buf[PRINTSIZE];

	va_start(arg, fmt);
	n = vseprint(buf, buf+sizeof(buf), fmt, arg) - buf;
	va_end(arg);
	putstrn(buf, n);

	return n;
}

int
fprint(int fd, char *fmt, ...)
{
	int n;
	va_list arg;
	char buf[PRINTSIZE];

	USED(fd);
	va_start(arg, fmt);
	n = vseprint(buf, buf+sizeof(buf), fmt, arg) - buf;
	va_end(arg);
	putstrn(buf, n);

	return n;
}

int
kprint(char *fmt, ...)
{
	va_list arg;
	char buf[PRINTSIZE];
	int n;

	va_start(arg, fmt);
	n = vseprint(buf, buf+sizeof(buf), fmt, arg) - buf;
	va_end(arg);
	if(qfull(klogq))
		qflush(klogq);
	return qproduce(klogq, buf, n);
}

int
iprint(char *fmt, ...)
{
	int n, s;
	va_list arg;
	char buf[PRINTSIZE];

	s = splhi();
	va_start(arg, fmt);
	n = vseprint(buf, buf+sizeof(buf), fmt, arg) - buf;
	va_end(arg);
	if(screenputs != nil && iprintscreenputs)
		screenputs(buf, n);
	uartputs(buf, n);
	splx(s);

	return n;
}

void
panic(char *fmt, ...)
{
	int n;
	va_list arg;
	char buf[PRINTSIZE];

	setpanic();
	kprintq.q = nil;
	strcpy(buf, "panic: ");
	va_start(arg, fmt);
	n = vseprint(buf+strlen(buf), buf+sizeof(buf)-1, fmt, arg) - buf;
	va_end(arg);
	buf[n] = '\n';
	putstrn(buf, n+1);
	spllo();
	dumpstack();

	exit(1);
}

void
_assert(char *fmt)
{
	panic("assert failed: %s", fmt);
}

void
sysfatal(char *fmt, ...)
{
	va_list arg;
	char buf[64];

	va_start(arg, fmt);
	vsnprint(buf, sizeof(buf), fmt, arg);
	va_end(arg);
	panic("sysfatal: %s", buf);
}

int
pprint(char *fmt, ...)
{
	int n;
	Chan *c;
	Osenv *o;
	va_list arg;
	char buf[2*PRINTSIZE];

	n = sprint(buf, "%s %ld: ", up->text, up->pid);
	va_start(arg, fmt);
	n = vseprint(buf+n, buf+sizeof(buf), fmt, arg) - buf;
	va_end(arg);

	o = up->env;
	if(o->fgrp == 0) {
		print("%s", buf);
		return 0;
	}
	c = o->fgrp->fd[2];
	if(c==0 || (c->mode!=OWRITE && c->mode!=ORDWR)) {
		print("%s", buf);
		return 0;
	}

	if(waserror()) {
		print("%s", buf);
		return 0;
	}
	devtab[c->type]->write(c, buf, n, c->offset);
	poperror();

	lock(c);
	c->offset += n;
	unlock(c);

	return n;
}

void
echo(Rune r, char *buf, int n)
{
	if(kbd.raw)
		return;

	if(r == '\n'){
		if(printq)
			qiwrite(printq, "\r", 1);
	} else if(r == 0x15){
		buf = "^U\n";
		n = 3;
	}
	if(consoleprint && screenputs != nil)
		screenputs(buf, n);
	if(printq)
		qiwrite(printq, buf, n);
}

/*
 *	Debug key support.  Allows other parts of the kernel to register debug
 *	key handlers, instead of devcons.c having to know whatever's out there.
 *	A kproc is used to invoke most handlers, rather than tying up the CPU at
 *	splhi, which can choke some device drivers (eg softmodem).
 */
typedef struct {
	Rune	r;
	char	*m;
	void	(*f)(Rune);
	int	i;	/* function called at interrupt time */
} Dbgkey;

static struct {
	Rendez;
	Dbgkey	*work;
	Dbgkey	keys[50];
	int	nkeys;
	int	on;
} dbg;

static Dbgkey *
finddbgkey(Rune r)
{
	int i;
	Dbgkey *dp;

	for(dp = dbg.keys, i = 0; i < dbg.nkeys; i++, dp++)
		if(dp->r == r)
			return dp;
	return nil;
}

static int
dbgwork(void *)
{
	return dbg.work != 0;
}

static void
dbgproc(void *)
{
	Dbgkey *dp;

	setpri(PriRealtime);
	for(;;) {
		do {
			sleep(&dbg, dbgwork, 0);
			dp = dbg.work;
		} while(dp == nil);
		dp->f(dp->r);
		dbg.work = nil;
	}
}

void
debugkey(Rune r, char *msg, void (*fcn)(), int iflag)
{
	Dbgkey *dp;

	if(dbg.nkeys >= nelem(dbg.keys))
		return;
	if(finddbgkey(r) != nil)
		return;
	for(dp = &dbg.keys[dbg.nkeys++] - 1; dp >= dbg.keys; dp--) {
		if(strcmp(dp->m, msg) < 0)
			break;
		dp[1] = dp[0];
	}
	dp++;
	dp->r = r;
	dp->m = msg;
	dp->f = fcn;
	dp->i = iflag;
}

static int
isdbgkey(Rune r)
{
	static int ctrlt;
	Dbgkey *dp;
	int echoctrlt = ctrlt;

	/*
	 * ^t hack BUG
	 */
	if(dbg.on || (ctrlt >= 2)) {
		if(r == 0x14 || r == 0x05) {
			ctrlt++;
			return 0;
		}
		if(dp = finddbgkey(r)) {
			if(dp->i || ctrlt > 2)
				dp->f(r);
			else {
				dbg.work = dp;
				wakeup(&dbg);
			}
			ctrlt = 0;
			return 1;
		}
		ctrlt = 0;
	}
	else if(r == 0x14){
		ctrlt++;
		return 1;
	}
	else
		ctrlt = 0;
	if(echoctrlt){
		char buf[3];

		buf[0] = 0x14;
		while(--echoctrlt >= 0){
			echo(buf[0], buf, 1);
			qproduce(kbdq, buf, 1);
		}
	}
	return 0;
}

static void
dbgtoggle(Rune)
{
	dbg.on = !dbg.on;
	print("Debug keys %s\n", dbg.on ? "HOT" : "COLD");
}

static void
dbghelp(void)
{
	int i;
	Dbgkey *dp;
	Dbgkey *dp2;
	static char fmt[] = "%c: %-22s";

	dp = dbg.keys;
	dp2 = dp + (dbg.nkeys + 1)/2;
	for(i = dbg.nkeys; i > 1; i -= 2, dp++, dp2++) {
		print(fmt, dp->r, dp->m);
		print(fmt, dp2->r, dp2->m);
		print("\n");
	}
	if(i)
		print(fmt, dp->r, dp->m);
	print("\n");
}

static void
debuginit(void)
{
	kproc("consdbg", dbgproc, nil, 0);
	debugkey('|', "HOT|COLD keys", dbgtoggle, 0);
	debugkey('?', "help", dbghelp, 0);
}

/*
 *  Called by a uart interrupt for console input.
 *
 *  turn '\r' into '\n' before putting it into the queue.
 */
int
kbdcr2nl(Queue *q, int ch)
{
	if(ch == '\r')
		ch = '\n';
	return kbdputc(q, ch);
}

/*
 *  Put character, possibly a rune, into read queue at interrupt time.
 *  Performs translation for compose sequences
 *  Called at interrupt time to process a character.
 */
int
kbdputc(Queue *q, int ch)
{
	int n;
	char buf[3];
	Rune r;
	static Rune kc[15];
	static int nk, collecting = 0;

	r = ch;
	if(r == Latin) {
		collecting = 1;
		nk = 0;
		return 0;
	}
	if(collecting) {
		int c;
		nk += runetochar((char*)&kc[nk], &r);
		c = latin1(kc, nk);
		if(c < -1)	/* need more keystrokes */
			return 0;
		collecting = 0;
		if(c == -1) {	/* invalid sequence */
			echo(kc[0], (char*)kc, nk);
			qproduce(q, kc, nk);
			return 0;
		}
		r = (Rune)c;
	}
	kbd.c = r;
	n = runetochar(buf, &r);
	if(n == 0)
		return 0;
	if(!isdbgkey(r)) {
		echo(r, buf, n);
		qproduce(q, buf, n);
	}
	return 0;
}

void
kbdrepeat(int rep)
{
	kbd.repeat = rep;
	kbd.count = 0;
}

void
kbdclock(void)
{
	if(kbd.repeat == 0)
		return;
	if(kbd.repeat==1 && ++kbd.count>HZ){
		kbd.repeat = 2;
		kbd.count = 0;
		return;
	}
	if(++kbd.count&1)
		kbdputc(kbdq, kbd.c);
}

enum{
	Qdir,
	Qcons,
	Qsysctl,
	Qconsctl,
	Qdrivers,
	Qhostowner,
	Qkeyboard,
	Qklog,
	Qkprint,
	Qscancode,
	Qmemory,
	Qmsec,
	Qnull,
	Qpin,
	Qrandom,
	Qnotquiterandom,
	Qsysname,
	Qtime,
	Quser,
	Qjit,
};

static Dirtab consdir[]=
{
	".",	{Qdir, 0, QTDIR},	0,		DMDIR|0555,
	"cons",		{Qcons},	0,		0660,
	"consctl",	{Qconsctl},	0,		0220,
	"sysctl",	{Qsysctl},	0,		0644,
	"drivers",	{Qdrivers},	0,		0444,
	"hostowner",	{Qhostowner},	0,	0644,
	"keyboard",	{Qkeyboard},	0,		0666,
	"klog",		{Qklog},	0,		0444,
	"kprint",		{Qkprint},	0,		0444,
	"scancode",	{Qscancode},	0,		0444,
	"memory",	{Qmemory},	0,		0444,
	"msec",		{Qmsec},	NUMSIZE,	0444,
	"null",		{Qnull},	0,		0666,
	"pin",		{Qpin},		0,		0666,
	"random",	{Qrandom},	0,		0444,
	"notquiterandom", {Qnotquiterandom}, 0,	0444,
	"sysname",	{Qsysname},	0,		0664,
	"time",		{Qtime},	0,		0664,
	"user",		{Quser},	0,	0644,
	"jit",		{Qjit},	0,	0666,
};

ulong	boottime;		/* seconds since epoch at boot */

long
seconds(void)
{
	return boottime + TK2SEC(MACHP(0)->ticks);
}

vlong
mseconds(void)
{
	return ((vlong)boottime*1000)+((vlong)(TK2MS(MACHP(0)->ticks)));
}

vlong
osusectime(void)
{
	return (((vlong)boottime*1000)+((vlong)(TK2MS(MACHP(0)->ticks)))*1000);
}

vlong
nsec(void)
{
	return osusectime()*1000;	/* TO DO */
}

int
readnum(ulong off, char *buf, ulong n, ulong val, int size)
{
	char tmp[64];

	if(size > 64) size = 64;

	snprint(tmp, sizeof(tmp), "%*.0lud ", size, val);
	if(off >= size)
		return 0;
	if(off+n > size)
		n = size-off;
	memmove(buf, tmp+off, n);
	return n;
}

int
readstr(ulong off, char *buf, ulong n, char *str)
{
	int size;

	size = strlen(str);
	if(off >= size)
		return 0;
	if(off+n > size)
		n = size-off;
	memmove(buf, str+off, n);
	return n;
}

void
fddump()
{
	Proc *p;
	Osenv *o;
	int i;
	Chan *c;

	p = proctab(6);
	o = p->env;
	for(i = 0; i <= o->fgrp->maxfd; i++) {
		if((c = o->fgrp->fd[i]) == nil)
			continue;
		print("%d: %s\n", i, c->name == nil? "???": c->name->s);
	}
}

static void
qpanic(Rune)
{
	panic("User requested panic.");
}

static void
rexit(Rune)
{
	exit(0);
}

static void
consinit(void)
{
	randominit();
	debuginit();
	debugkey('f', "files/6", fddump, 0);
	debugkey('q', "panic", qpanic, 1);
	debugkey('r', "exit", rexit, 1);
	klogq = qopen(128*1024, 0, 0, 0);
}

static Chan*
consattach(char *spec)
{
	return devattach('c', spec);
}

static Walkqid*
conswalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, consdir, nelem(consdir), devgen);
}

static int
consstat(Chan *c, uchar *dp, int n)
{
	return devstat(c, dp, n, consdir, nelem(consdir), devgen);
}

static void
flushkbdline(Queue *q)
{
	if(kbd.x){
		qwrite(q, kbd.line, kbd.x);
		kbd.x = 0;
	}
}

static Chan*
consopen(Chan *c, int omode)
{
	c->aux = 0;
	switch((ulong)c->qid.path){
	case Qconsctl:
		if(!iseve())
			error(Eperm);
		qlock(&kbd);
		kbd.ctl++;
		qunlock(&kbd);
		break;

	case Qkeyboard:
		if((omode & 3) != OWRITE) {
			qlock(&kbd);
			kbd.kbdr++;
			flushkbdline(kbdq);
			kbd.raw = 1;
			qunlock(&kbd);
		}
		break;

	case Qscancode:
		qlock(&kbd);
		if(kscanq || !kscanid) {
			qunlock(&kbd);
			c->flag &= ~COPEN;
			if(kscanq)
				error(Einuse);
			else
				error(Ebadarg);
		}
		kscanq = qopen(256, 0, nil, nil);
		qunlock(&kbd);
		break;

	case Qkprint:
		if((omode & 3) != OWRITE) {
			wlock(&kprintq);
			if(kprintq.q != nil){
				wunlock(&kprintq);
				error(Einuse);
			}
			kprintq.q = qopen(32*1024, Qcoalesce, nil, nil);
			if(kprintq.q == nil){
				wunlock(&kprintq);
				error(Enomem);
			}
			qnoblock(kprintq.q, 1);
			wunlock(&kprintq);
			c->iounit = qiomaxatomic;
		}
		break;
	}
	return devopen(c, omode, consdir, nelem(consdir), devgen);
}

static void
consclose(Chan *c)
{
	if((c->flag&COPEN) == 0)
		return;

	switch((ulong)c->qid.path){
	case Qconsctl:
		/* last close of control file turns off raw */
		qlock(&kbd);
		if(--kbd.ctl == 0)
			kbd.raw = 0;
		qunlock(&kbd);
		break;

	case Qkeyboard:
		if(c->mode != OWRITE) {
			qlock(&kbd);
			--kbd.kbdr;
			qunlock(&kbd);
		}
		break;

	case Qscancode:
		qlock(&kbd);
		if(kscanq) {
			qfree(kscanq);
			kscanq = 0;
		}
		qunlock(&kbd);
		break;

	case Qkprint:
		wlock(&kprintq);
		qfree(kprintq.q);
		kprintq.q = nil;
		wunlock(&kprintq);
		break;
	}
}

static long
consread(Chan *c, void *buf, long n, vlong offset)
{
	int l;
	Osenv *o;
	int ch, eol, i;
	char *p, tmp[128];
	char *cbuf = buf;

	if(n <= 0)
		return n;
	o = up->env;
	switch((ulong)c->qid.path){
	case Qdir:
		return devdirread(c, buf, n, consdir, nelem(consdir), devgen);
	case Qsysctl:
		return readstr(offset, buf, n, VERSION);
	case Qcons:
	case Qkeyboard:
		qlock(&kbd);
		if(waserror()) {
			qunlock(&kbd);
			nexterror();
		}
		if(kbd.raw || kbd.kbdr) {
			if(qcanread(lineq))
				n = qread(lineq, buf, n);
			else {
				/* read as much as possible */
				do {
					i = qread(kbdq, cbuf, n);
					cbuf += i;
					n -= i;
				} while(n>0 && qcanread(kbdq));
				n = cbuf - (char*)buf;
			}
		} else {
			while(!qcanread(lineq)) {
				qread(kbdq, &kbd.line[kbd.x], 1);
				ch = kbd.line[kbd.x];
				eol = 0;
				switch(ch){
				case '\b':
					if(kbd.x)
						kbd.x--;
					break;
				case 0x15:
					kbd.x = 0;
					break;
				case '\n':
				case 0x04:
					eol = 1;
				default:
					kbd.line[kbd.x++] = ch;
					break;
				}
				if(kbd.x == sizeof(kbd.line) || eol) {
					if(ch == 0x04)
						kbd.x--;
					qwrite(lineq, kbd.line, kbd.x);
					kbd.x = 0;
				}
			}
			n = qread(lineq, buf, n);
		}
		qunlock(&kbd);
		poperror();
		return n;

	case Qscancode:
		if(offset == 0)
			return readstr(0, buf, n, kscanid);
		else
			return qread(kscanq, buf, n);

	case Qpin:
		p = "pin set";
		if(up->env->pgrp->pin == Nopin)
			p = "no pin";
		return readstr(offset, buf, n, p);

	case Qtime:
		snprint(tmp, sizeof(tmp), "%.lld", (vlong)mseconds()*1000);
		return readstr(offset, buf, n, tmp);

	case Qhostowner:
		return readstr(offset, buf, n, eve);

	case Quser:
		return readstr(offset, buf, n, o->user);

	case Qjit:
		snprint(tmp, sizeof(tmp), "%d", cflag);
		return readstr(offset, buf, n, tmp);

	case Qnull:
		return 0;

	case Qmsec:
		return readnum(offset, buf, n, TK2MS(MACHP(0)->ticks), NUMSIZE);

	case Qsysname:
		if(sysname == nil)
			return 0;
		return readstr(offset, buf, n, sysname);

	case Qnotquiterandom:
		genrandom(buf, n);
		return n;

	case Qrandom:
		return randomread(buf, n);

	case Qmemory:
		return poolread(buf, n, offset);

	case Qdrivers:
		p = malloc(READSTR);
		if(p == nil)
			error(Enomem);
		l = 0;
		for(i = 0; devtab[i] != nil; i++)
			l += snprint(p+l, READSTR-l, "#%C %s\n", devtab[i]->dc,  devtab[i]->name);
		if(waserror()){
			free(p);
			nexterror();
		}
		n = readstr(offset, buf, n, p);
		free(p);
		poperror();
		return n;

	case Qklog:
		return qread(klogq, buf, n);

	case Qkprint:
		rlock(&kprintq);
		if(waserror()){
			runlock(&kprintq);
			nexterror();
		}
		n = qread(kprintq.q, buf, n);
		poperror();
		runlock(&kprintq);
		return n;

	default:
		print("consread %llud\n", c->qid.path);
		error(Egreg);
	}
	return -1;		/* never reached */
}

static long
conswrite(Chan *c, void *va, long n, vlong offset)
{
	vlong t;
	long l, bp;
	char *a = va;
	Cmdbuf *cb;
	Cmdtab *ct;
	char buf[256];
	int x;

	switch((ulong)c->qid.path){
	case Qcons:
		/*
		 * Can't page fault in putstrn, so copy the data locally.
		 */
		l = n;
		while(l > 0){
			bp = l;
			if(bp > sizeof buf)
				bp = sizeof buf;
			memmove(buf, a, bp);
			putstrn0(a, bp, 1);
			a += bp;
			l -= bp;
		}
		break;

	case Qconsctl:
		if(n >= sizeof(buf))
			n = sizeof(buf)-1;
		strncpy(buf, a, n);
		buf[n] = 0;
		for(a = buf; a;){
			if(strncmp(a, "rawon", 5) == 0){
				qlock(&kbd);
				flushkbdline(kbdq);
				kbd.raw = 1;
				qunlock(&kbd);
			} else if(strncmp(a, "rawoff", 6) == 0){
				qlock(&kbd);
				kbd.raw = 0;
				kbd.x = 0;
				qunlock(&kbd);
			}
			if(a = strchr(a, ' '))
				a++;
		}
		break;

	case Qkeyboard:
		for(x=0; x<n; ) {
			Rune r;
			x += chartorune(&r, &a[x]);
			kbdputc(kbdq, r);
		}
		break;
	
	case Qtime:
		if(n >= sizeof(buf))
			n = sizeof(buf)-1;
		strncpy(buf, a, n);
		buf[n] = 0;
		t = strtoll(buf, 0, 0)/1000000;
		boottime = t - TK2SEC(MACHP(0)->ticks);
		break;

	case Qhostowner:
		if(!iseve())
			error(Eperm);
		if(offset != 0 || n >= sizeof(buf))
			error(Ebadarg);
		memmove(buf, a, n);
		buf[n] = '\0';
		if(n > 0 && buf[n-1] == '\n')
			buf[--n] = 0;
		if(n <= 0)
			error(Ebadarg);
		renameuser(eve, buf);
		renameproguser(eve, buf);
		kstrdup(&eve, buf);
		kstrdup(&up->env->user, buf);
		break;

	case Quser:
		if(!iseve())
			error(Eperm);
		if(offset != 0)
			error(Ebadarg);
		if(n <= 0 || n >= sizeof(buf))
			error(Ebadarg);
		strncpy(buf, a, n);
		buf[n] = 0;
		if(buf[n-1] == '\n')
			buf[n-1] = 0;
		kstrdup(&up->env->user, buf);
		break;

	case Qjit:
		if(n >= sizeof(buf))
			n = sizeof(buf)-1;
		strncpy(buf, va, n);
		buf[n] = '\0';
		x = atoi(buf);
		if(x < 0 || x > 9)
			error(Ebadarg);
		cflag = x;
		return n;

	case Qnull:
		break;

	case Qpin:
		if(up->env->pgrp->pin != Nopin)
			error("pin already set");
		if(n >= sizeof(buf))
			n = sizeof(buf)-1;
		strncpy(buf, va, n);
		buf[n] = '\0';
		up->env->pgrp->pin = atoi(buf);
		return n;

	case Qsysname:
		if(offset != 0)
			error(Ebadarg);
		if(n <= 0 || n >= sizeof(buf))
			error(Ebadarg);
		strncpy(buf, a, n);
		buf[n] = 0;
		if(buf[n-1] == '\n')
			buf[n-1] = 0;
		kstrdup(&sysname, buf);
		break;

	case Qsysctl:
		if(!iseve())
			error(Eperm);
		cb = parsecmd(a, n);
		if(waserror()){
			free(cb);
			nexterror();
		}
		ct = lookupcmd(cb, sysctlcmd, nelem(sysctlcmd));
		switch(ct->index){
		case CMreboot:
			reboot();
			break;
		case CMhalt:
			halt();
			break;
		case CMpanic:
			panic("sysctl");
		case CMconsole:
			consoleprint = strcmp(cb->f[1], "off") != 0;
			break;
		case CMbroken:
			keepbroken = 1;
			break;
		case CMnobroken:
			keepbroken = 0;
			break;
		}
		poperror();
		free(cb);
		break;

	default:
		print("conswrite: %llud\n", c->qid.path);
		error(Egreg);
	}
	return n;
}

Dev consdevtab = {
	'c',
	"cons",

	devreset,
	consinit,
	devshutdown,
	consattach,
	conswalk,
	consstat,
	consopen,
	devcreate,
	consclose,
	consread,
	devbread,
	conswrite,
	devbwrite,
	devremove,
	devwstat,
};

static	ulong	randn;

static void
seedrand(void)
{
	randomread((void*)&randn, sizeof(randn));
}

int
nrand(int n)
{
	if(randn == 0)
		seedrand();
	randn = randn*1103515245 + 12345 + MACHP(0)->ticks;
	return (randn>>16) % n;
}

int
rand(void)
{
	nrand(1);
	return randn;
}

ulong
truerand(void)
{
	ulong x;

	randomread(&x, sizeof(x));
	return x;
}

QLock grandomlk;

void
_genrandomqlock(void)
{
	qlock(&grandomlk);
}


void
_genrandomqunlock(void)
{
	qunlock(&grandomlk);
}
