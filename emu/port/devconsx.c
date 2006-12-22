#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	"version.h"
#include	"libcrypt.h"
#include	"keyboard.h"

extern int cflag;
extern int keepbroken;

enum
{
	Qdir,
	Qcons,
	Qsysctl,
	Qconsctl,
	Qdrivers,
	Qkeyboard,
	Qkprint,
	Qscancode,
	Qmemory,
	Qmsec,
	Qnull,
	Qpin,
	Qpointer,
	Qrandom,
	Qnotquiterandom,
	Qsysname,
	Qtime,
	Quser,
	Qjit,
	Qcaphash,
	Qcapuse
};

Dirtab contab[] =
{
	".",	{Qdir, 0, QTDIR},	0,		DMDIR|0555,
	"cons",		{Qcons},	0,	0666,
	"consctl",	{Qconsctl},	0,	0222,
	"sysctl",	{Qsysctl},	0,	0644,
	"keyboard",	{Qkeyboard},	0,	0666,
	"kprint",	{Qkprint},	0,	0444,
	"scancode",	{Qscancode},	0,	0444,
	"memory",	{Qmemory},	0,	0444,
	"msec",		{Qmsec},	NUMSIZE,	0444,
	"notquiterandom",	{Qnotquiterandom},	0,	0444,
	"null",		{Qnull},	0,	0666,
	"pin",		{Qpin},		0,	0666,
	"pointer",	{Qpointer},	0,	0666,
	"random",	{Qrandom},	0,	0444,
	"sysname",	{Qsysname},	0,	0644,
	"user",		{Quser},	0,	0644,
	"time",		{Qtime},	0,	0644,
	"drivers",	{Qdrivers},	0,	0444,
	"jit",	{Qjit},	0,	0666,
	"caphash",	{Qcaphash},	0,	0200,
	"capuse",	{Qcapuse},	0,	0222,
};

enum
{
	MBS	=	1024
};

Queue*	gkscanq;		/* Graphics keyboard raw scancodes */
char*	gkscanid;		/* name of raw scan format (if defined) */
Queue*	gkbdq;			/* Graphics keyboard unprocessed input */
Queue*	kbdq;			/* Console window unprocessed keyboard input */
Queue*	lineq;			/* processed console input */

static Ref	capopen;

char	*ossysname;

static struct
{
	RWlock l;
	Queue*	q;
} kprintq;

vlong	timeoffset;

static ulong	randomread(void *xp, ulong n);
static void	randominit(void);

extern int	dflag;

static int	sysconwrite(void*, ulong);
static int	argsread(ulong, void*, ulong);
extern int	rebootargc;
extern char**	rebootargv;

static struct
{
	QLock	q;
	QLock	gq;		/* separate lock for the graphical input */

	int	raw;		/* true if we shouldn't process input */
	Ref	ctl;		/* number of opens to the control file */
	int	kbdr;		/* number of open reads to the keyboard */
	Ref	ptr;		/* number of opens to the ptr file */
	int	scan;		/* true if reading raw scancodes */
	int	x;		/* index into line */
	char	line[1024];	/* current input line */

	Rune	c;
	int	count;
} kbd;

void
kbdslave(void *a)
{
	char b;

	USED(a);
	for(;;) {
		b = readkbd();
		if(kbd.raw == 0)
			write(1, &b, 1);
		qproduce(kbdq, &b, 1);
	}
	pexit("kbdslave", 0);
}

void
gkbdputc(Queue *q, int ch)
{
	int n;
	Rune r;
	static uchar kc[5*UTFmax];
	static int nk, collecting = 0;
	char buf[UTFmax];

	r = ch;
	if(r == Latin) {
		collecting = 1;
		nk = 0;
		return;
	}
	if(collecting) {
		int c;
		nk += runetochar((char*)&kc[nk], &r);
		c = latin1(kc, nk);
		if(c < -1)	/* need more keystrokes */
			return;
		collecting = 0;
		if(c == -1) {	/* invalid sequence */
			qproduce(q, kc, nk);
			return;
		}
		r = (Rune)c;
	}
	n = runetochar(buf, &r);
	if(n == 0)
		return;
	/* if(!isdbgkey(r)) */ 
		qproduce(q, buf, n);
}

void
consinit(void)
{
	kbdq = qopen(512, 0, 0, 0);
	if(kbdq == 0)
		panic("no memory");
	lineq = qopen(512, 0, 0, 0);
	if(lineq == 0)
		panic("no memory");
	gkbdq = qopen(512, 0, 0, 0);
	if(gkbdq == 0)
		panic("no memory");
	randominit();
}

/*
 *  return true if current user is eve
 */
int
iseve(void)
{
	return strcmp(eve, up->env->user) == 0;
}

Chan*
consattach(char *spec)
{
	static int kp;

	if (kp == 0 && !dflag) {
		kproc("kbd", kbdslave, 0, 0);
		kp = 1;
	}
	return devattach('c', spec);
}

static Walkqid*
conswalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, contab, nelem(contab), devgen);
}

int
consstat(Chan *c, uchar *db, int n)
{
	return devstat(c, db, n, contab, nelem(contab), devgen);
}

Chan*
consopen(Chan *c, int omode)
{
	c = devopen(c, omode, contab, nelem(contab), devgen);
	switch((ulong)c->qid.path) {
	case Qconsctl:
		incref(&kbd.ctl);
		break;
#ifdef NOTYET
	case Qkeyboard:
		if((omode & 3) != OWRITE) {
			qlock(&kbd.q);
			kbd.kbdr++;
			/* flushkbdline(kbdq); */
			kbd.raw = 1;
			qunlock(&kbd.q);
		}
		break;
#endif
	case Qpointer:
		if(incref(&kbd.ptr) != 1){
			decref(&kbd.ptr);
			c->flag &= ~COPEN;
			error(Einuse);
		}
		break;
	case Qscancode:
		qlock(&kbd.gq);
		if(gkscanq || !gkscanid) {
			qunlock(&kbd.q);
			c->flag &= ~COPEN;
			if(gkscanq)
				error(Einuse);
			else
				error(Ebadarg);
		}
		gkscanq = qopen(256, 0, nil, nil);
		qunlock(&kbd.gq);
		break;
	case Qkprint:
		wlock(&kprintq.l);
		if(kprintq.q != nil){
			wunlock(&kprintq.l);
			c->flag &= ~COPEN;
			error(Einuse);
		}
		kprintq.q = qopen(32*1024, Qcoalesce, nil, nil);
		if(kprintq.q == nil){
			wunlock(&kprintq.l);
			c->flag &= ~COPEN;
			error(Enomem);
		}
		qnoblock(kprintq.q, 1);
		wunlock(&kprintq.l);
		break;
	case Qcaphash:
		if(incref(&capopen) != 1){
			decref(&capopen);
			c->flag &= ~COPEN;
			error(Einuse);
		}
		break;
	}
	return c;
}

void
consclose(Chan *c)
{
	if((c->flag & COPEN) == 0)
		return;

	switch((ulong)c->qid.path) {
	case Qconsctl:
		if(decref(&kbd.ctl) == 0)
			kbd.raw = 0;
		break;
	case Qkeyboard:
		if(c->mode != OWRITE) {
			qlock(&kbd.q);
			--kbd.kbdr;
			if(kbd.kbdr == 0)
				kbd.raw = 0;
			qunlock(&kbd.q);
		}
		break;
	case Qpointer:
		decref(&kbd.ptr);
		break;
	case Qscancode:
		qlock(&kbd.gq);
		if(gkscanq) {
			qfree(gkscanq);
			gkscanq = 0;
		}
		qunlock(&kbd.gq);
		break;
	case Qkprint:
		wlock(&kprintq.l);
		qfree(kprintq.q);
		kprintq.q = nil;
		wunlock(&kprintq.l);
		break;
	case Qcaphash:
		decref(&capopen);
		break;
	}
}

long
consread(Chan *c, void *xbuf, long n, vlong offset)
{
	int i, l, ch, eol;
	Pointer m;
	char *p, tmp[64];
	char *cbuf = xbuf;

	if(c->qid.type & QTDIR)
		return devdirread(c, xbuf, n, contab, nelem(contab), devgen);

	switch((ulong)c->qid.path) {
	default:
		error(Egreg);
	case Qsysctl:
		return readstr(offset, xbuf, n, VERSION);
	case Qsysname:
		if(ossysname == nil)
			return 0;
		return readstr(offset, xbuf, n, ossysname);
	case Qrandom:
		return randomread(xbuf, n);
	case Qnotquiterandom:
		pseudoRandomBytes(xbuf, n);
		return n;
	case Qpin:
		p = "pin set";
		if(up->env->pgrp->pin == Nopin)
			p = "no pin";
		return readstr(offset, xbuf, n, p);
	case Quser:
		return readstr(offset, xbuf, n, up->env->user);
	case Qjit:
		snprint(tmp, sizeof(tmp), "%d", cflag);
		return readstr(offset, xbuf, n, tmp);
	case Qtime:
		snprint(tmp, sizeof(tmp), "%.lld", timeoffset + osusectime());
		return readstr(offset, xbuf, n, tmp);
	case Qdrivers:
		p = malloc(READSTR);
		if(p == nil)
			error(Enomem);
		if(waserror()){
			free(p);
			nexterror();
		}
		l = 0;
		for(i = 0; devtab[i] != nil; i++)
			l += snprint(p+l, READSTR-l, "#%C %s\n", devtab[i]->dc,  devtab[i]->name);
		n = readstr(offset, xbuf, n, p);
		free(p);
		poperror();
		return n;
	case Qmemory:
		return poolread(xbuf, n, offset);

	case Qnull:
		return 0;
	case Qmsec:
		return readnum(offset, xbuf, n, osmillisec(), NUMSIZE);
	case Qcons:
		qlock(&kbd.q);
		if(waserror()){
			qunlock(&kbd.q);
			nexterror();
		}

		if(dflag)
			error(Enonexist);

		if(kbd.raw) {
			if(qcanread(lineq))
				n = qread(lineq, xbuf, n);
			else {
				/* read as much as possible */
				do {
					i = qread(kbdq, cbuf, n);
					cbuf += i;
					n -= i;
				} while (n>0 && qcanread(kbdq));
				n = cbuf - (char*)xbuf;
			}
		} else {
			while(!qcanread(lineq)) {
				qread(kbdq, &kbd.line[kbd.x], 1);
				ch = kbd.line[kbd.x];
				eol = 0;
				switch(ch) {
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
				if(kbd.x == sizeof(kbd.line) || eol){
					if(ch == 0x04)
						kbd.x--;
					qwrite(lineq, kbd.line, kbd.x);
					kbd.x = 0;
				}
			}
			n = qread(lineq, xbuf, n);
		}
		qunlock(&kbd.q);
		poperror();
		return n;
	case Qscancode:
		if(offset == 0)
			return readstr(0, xbuf, n, gkscanid);
		else
			return qread(gkscanq, xbuf, n);
	case Qkeyboard:
		return qread(gkbdq, xbuf, n);
	case Qpointer:
		m = mouseconsume();
		l = sprint(tmp, "m%11d %11d %11d %11lud ", m.x, m.y, m.b, m.msec);
		if (n < l)
			n = l;
		memmove(xbuf, tmp, n);
		return n;
	case Qkprint:
		rlock(&kprintq.l);
		if(waserror()){
			runlock(&kprintq.l);
			nexterror();
		}
		n = qread(kprintq.q, xbuf, n);
		poperror();
		runlock(&kprintq.l);
		return n;
	}
}

long
conswrite(Chan *c, void *va, long count, vlong offset)
{
	char buf[128], *p;
	int x, y;

	USED(offset);

	if(c->qid.type & QTDIR)
		error(Eperm);

	switch((ulong)c->qid.path) {
	default:
		error(Egreg);
	case Qcons:
		if(canrlock(&kprintq.l)){
			if(kprintq.q != nil){
				if(waserror()){
					runlock(&kprintq.l);
					nexterror();
				}
				qwrite(kprintq.q, va, count);
				poperror();
				runlock(&kprintq.l);
				return count;
			}
			runlock(&kprintq.l);
		}
		return write(1, va, count);
	case Qsysctl:
		return sysconwrite(va, count);
	case Qconsctl:
		if(count >= sizeof(buf))
			count = sizeof(buf)-1;
		strncpy(buf, va, count);
		buf[count] = 0;
		if(strncmp(buf, "rawon", 5) == 0) {
			kbd.raw = 1;
			return count;
		}
		else
		if(strncmp(buf, "rawoff", 6) == 0) {
			kbd.raw = 0;
			return count;
		}
		error(Ebadctl);
	case Qkeyboard:
		for(x=0; x<count; ) {
			Rune r;
			x += chartorune(&r, &((char*)va)[x]);
			gkbdputc(gkbdq, r);
		}
		return count;
	case Qpointer:
		if(count > sizeof buf-1)
			count = sizeof buf -1;
		memmove(buf, va, count);
		buf[count] = 0;
		p = nil;
		x = strtoul(buf+1, &p, 0);
		if(p == nil || p == buf+1)
			error(Eshort);
		y = strtoul(p, 0, 0);
		setpointer(x, y);
		return count;
	case Qnull:
		return count;
	case Qpin:
		if(up->env->pgrp->pin != Nopin)
			error("pin already set");
		if(count >= sizeof(buf))
			count = sizeof(buf)-1;
		strncpy(buf, va, count);
		buf[count] = '\0';
		up->env->pgrp->pin = atoi(buf);
		return count;
	case Qtime:
		if(count >= sizeof(buf))
			count = sizeof(buf)-1;
		strncpy(buf, va, count);
		buf[count] = '\0';
		timeoffset = strtoll(buf, 0, 0)-osusectime();
		return count;
	case Quser:
		if(count >= sizeof(buf))
			count = sizeof(buf)-1;
		strncpy(buf, va, count);
		buf[count] = '\0';
		if(strcmp(up->env->user, eve) != 0)
			error(Eperm);
		setid(buf, 0);
		return count;
	case Qcaphash:
		if(capwritehash(va, count) < 0)
			error(Ebadarg);
		return count;
	case Qcapuse:
		if(capwriteuse(va, count) < 0)
			error(Eperm);
		return count;
	case Qjit:
		if(count >= sizeof(buf))
			count = sizeof(buf)-1;
		strncpy(buf, va, count);
		buf[count] = '\0';
		x = atoi(buf);
		if (x < 0 || x > 9)
			error(Ebadarg);
		cflag = x;
		return count;
	case Qsysname:
		if(count >= sizeof(buf))
			count = sizeof(buf)-1;
		strncpy(buf, va, count);
		buf[count] = '\0';
		kstrdup(&ossysname, buf);
		return count;
	}
	return 0;
}

static Rb *rp;

int
rbnotfull(void *v)
{
	int i;

	USED(v);
	i = rp->wp - rp->rp;
	if(i < 0)
		i += sizeof(rp->buf);
	return i < rp->target;
}

static int
rbnotempty(void *v)
{
	USED(v);
	return rp->wp != rp->rp;
}

/*
 *  spin counting up
 */
void
genrandom(void *v)
{
	USED(v);

	osspin(&rp->producer);
}

/*
 *  produce random bits in a circular buffer
 */
static void
randomclock(void *v)
{
	uchar *p;

	USED(v);

	for(;; osmillisleep(20)){
		while(!rbnotfull(0)){
			rp->filled = 1;
			Sleep(&rp->clock, rbnotfull, 0);
		}

		if(rp->randomcount == 0)
			continue;
		rp->bits = (rp->bits<<2) ^ (rp->randomcount&3);
		rp->randomcount = 0;
		rp->next += 2;
		if(rp->next != 8)
			continue;

		rp->next = 0;
		*rp->wp ^= rp->bits ^ *rp->rp;
		p = rp->wp+1;
		if(p == rp->ep)
			p = rp->buf;
		rp->wp = p;

		if(rp->wakeme)
			Wakeup(&rp->consumer);
	}
}

static void
randominit(void)
{
	rp=osraninit();
	rp->target = 16;
	rp->ep = rp->buf + sizeof(rp->buf);
	rp->rp = rp->wp = rp->buf;
}

/*
 *  consume random bytes from a circular buffer
 */
static ulong
randomread(void *xp, ulong n)
{
	int i, sofar;
	uchar *e, *p;
	// ulong x;

	p = xp;

	if(waserror()){
		qunlock(&rp->l);
		nexterror();
	}

	qlock(&rp->l);
	if(!rp->kprocstarted){
		rp->kprocstarted = 1;
		kproc("genrand", genrandom, 0, 0);
		kproc("randomclock", randomclock, 0, 0);
	}

	for(sofar = 0; sofar < n;){
		if(!rbnotempty(0)){
			rp->wakeme = 1;
			Wakeup(&rp->clock);
			oswakeupproducer(&rp->producer);
			Sleep(&rp->consumer, rbnotempty, 0);
			rp->wakeme = 0;
			continue;
		}
		// x = rp->randn*1103515245 ^ *rp->rp;
		// *(p+(sofar++)) = rp->randn = x;
		*(p+(sofar++)) = *rp->rp;
		e = rp->rp + 1;
		if(e == rp->ep)
			e = rp->buf;
		rp->rp = e;
	}
	if(rp->filled && rp->wp == rp->rp){
		i = 2*rp->target;
		if(i > sizeof(rp->buf) - 1)
			i = sizeof(rp->buf) - 1;
		rp->target = i;
		rp->filled = 0;
	}
	qunlock(&rp->l);
	poperror();

	Wakeup(&rp->clock);
	oswakeupproducer(&rp->producer);

	return n;
}

static int	
sysconwrite(void *va, ulong count)
{
	char *arg = (char*) va;
	if(count>=6 && strncmp(arg, "reboot", 6) == 0) {
		osreboot(rebootargv[0], rebootargv);
		error("reboot not supported");
		return 0;
	} else if(count>=4 && strncmp(arg, "halt", 4) == 0)
		cleanexit(0);
	else if(count>=6 && strncmp(arg, "broken", 6) == 0)
		keepbroken = 1;
	else if(count>=8 && strncmp(arg, "nobroken", 8) == 0)
		keepbroken = 0;
	else
		error(Ebadarg);
	return count;
} 

typedef struct Ptrevent Ptrevent;

struct Ptrevent {
	int	x;
	int	y;
	int	b;
	ulong	msec;
};

enum {
	Nevent = 16	/* enough for some */
};

static struct {
	int	rd;
	int	wr;
	Ptrevent	clicks[Nevent];
	Rendez r;
	int	full;
	int	put;
	int	get;
} ptrq;

static Pointer mouse = {-32768,-32768,0};

void
mouseproduce(Pointer m)
{
	int lastb;
	Ptrevent e;

	e.x = m.x;
	e.y = m.y;
	e.b = m.b;
	e.msec = osmillisec();
	lastb = mouse.b;
	mouse.x = m.x;
	mouse.y = m.y;
	mouse.b = m.b;
	mouse.msec = e.msec;
	if(!ptrq.full && lastb != m.b){
		ptrq.clicks[ptrq.wr] = e;
		if(++ptrq.wr == Nevent)
			ptrq.wr = 0;
		if(ptrq.wr == ptrq.rd)
			ptrq.full = 1;
	}
	mouse.modify = 1;
	ptrq.put++;
	Wakeup(&ptrq.r);
/*	drawactive(1); */
}

static int
ptrqnotempty(void *a)
{
	USED(a);
	return ptrq.full || ptrq.put != ptrq.get;
}

Pointer
mouseconsume(void)
{
	Pointer m;
	Ptrevent e;

	Sleep(&ptrq.r, ptrqnotempty, 0);
	ptrq.full = 0;
	ptrq.get = ptrq.put;
	if(ptrq.rd != ptrq.wr){
		e = ptrq.clicks[ptrq.rd];
		if(++ptrq.rd >= Nevent)
			ptrq.rd = 0;
		memset(&m, 0, sizeof(m));
		m.x = e.x;
		m.y = e.y;
		m.b = e.b;
		m.msec = e.msec;
	}else
		m = mouse;
	return m;
}

Dev consdevtab = {
	'c',
	"cons",

	consinit,
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
	devwstat
};
