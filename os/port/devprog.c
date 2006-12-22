#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	<interp.h>
#include	<isa.h>
#include	"runt.h"

/*
 * Enable the heap device for environments that allow debugging =>
 * Must be 1 for a production environment.
 */
int	SECURE = 0;

enum
{
	Qdir,
	Qctl,
	Qdbgctl,
	Qheap,
	Qns,
	Qnsgrp,
	Qpgrp,
	Qstack,
	Qstatus,
	Qtext,
	Qwait,
	Qfd,
	Qexception,
};

/*
 * must be in same order as enum
 */
Dirtab progdir[] =
{
	"ctl",		{Qctl},		0,			0200,
	"dbgctl",	{Qdbgctl},	0,			0600,
	"heap",		{Qheap},	0,			0600,
	"ns",		{Qns},		0,			0400,
	"nsgrp",	{Qnsgrp},	0,			0444,
	"pgrp",		{Qpgrp},	0,			0444,
	"stack",	{Qstack},	0,			0400,
	"status",	{Qstatus},	0,			0444,
	"text",		{Qtext},	0,			0000,
	"wait",		{Qwait},	0,			0400,
	"fd",		{Qfd},		0,			0400,
	"exception",	{Qexception},	0,	0400,
};

enum
{
	CMkill,
	CMkillgrp,
	CMrestricted,
	CMexceptions,
	CMprivate
};

static
Cmdtab progcmd[] = {
	CMkill,	"kill",	1,
	CMkillgrp,	"killgrp",	1,
	CMrestricted, "restricted", 1,
	CMexceptions, "exceptions", 2,
	CMprivate, "private",	1,
};

enum
{
	CDstep,
	CDtoret,
	CDcont,
	CDstart,
	CDstop,
	CDunstop,
	CDmaim,
	CDbpt
};

static
Cmdtab progdbgcmd[] = {
	CDstep,	"step",	0,	/* known below to be first, to cope with stepN */
	CDtoret,	"toret",	1,
	CDcont,	"cont",	1,
	CDstart,	"start",	1,
	CDstop,	"stop",	1,
	CDunstop,	"unstop",	1,
	CDmaim,	"maim",	1,
	CDbpt,	"bpt",	4,
};

typedef struct Heapqry Heapqry;
struct Heapqry
{
	char	fmt;
	ulong	addr;
	ulong	module;
	int	count;
};

typedef struct Bpt	Bpt;

struct Bpt
{
	Bpt	*next;
	int	pc;
	char	*file;
	char	path[1];
};

typedef struct Progctl Progctl;
struct Progctl
{
	Rendez	r;
	int	ref;
	Proc	*debugger;	/* waiting for dbgxec */
	char	*msg;		/* reply from dbgxec */
	int	step;		/* instructions to try */
	int	stop;		/* stop running the program */
	Bpt*	bpts;		/* active breakpoints */
	Queue*	q;		/* status queue */
};

#define	QSHIFT		4		/* location in qid of pid */
#define	QID(q)		(((ulong)(q).path&0x0000000F)>>0)
#define QPID(pid)	(((pid)<<QSHIFT))
#define	PID(q)		((q).vers)
#define PATH(q)		((ulong)(q).path&~((1<<QSHIFT)-1))

static char *progstate[] =			/* must correspond to include/interp.h */
{
	"alt",				/* blocked in alt instruction */
	"send",				/* waiting to send */
	"recv",				/* waiting to recv */
	"debug",			/* debugged */
	"ready",			/* ready to be scheduled */
	"release",			/* interpreter released */
	"exiting",			/* exit because of kill or error */
	"broken",			/* thread crashed */
};

static	void	dbgstep(Progctl*, Prog*, int);
static	void	dbgstart(Prog*);
static	void	freebpts(Bpt*);
static	Bpt*	delbpt(Bpt*, char*, int);
static	Bpt*	setbpt(Bpt*, char*, int);
static	void	mntscan(Mntwalk*, Pgrp*);
extern	Type	*Trdchan;
extern	Type	*Twrchan;
extern	Module*	modules;
static  char 	Emisalign[] = "misaligned address";

static int
proggen(Chan *c, char *name, Dirtab *tab, int, int s, Dir *dp)
{
	Qid qid;
	Prog *p;
	char *e;
	Osenv *o;
	ulong pid, path, perm, len;

	if(s == DEVDOTDOT){
		mkqid(&qid, Qdir, 0, QTDIR);
		devdir(c, qid, "#p", 0, eve, DMDIR|0555, dp);
		return 1;
	}

	if((ulong)c->qid.path == Qdir) {
		if(name != nil){
			/* ignore s and use name to find pid */
			pid = strtoul(name, &e, 0);
			if(pid == 0 || *e != '\0')
				return -1;
			acquire();
			p = progpid(pid);
			if(p == nil){
				release();
				return -1;
			}
		}else{
			acquire();
			p = progn(s);
			if(p == nil) {
				release();
				return -1;
			}
			pid = p->pid;
		}
		o = p->osenv;
		sprint(up->genbuf, "%lud", pid);
		if(name != nil && strcmp(name, up->genbuf) != 0){
			release();
			return -1;
		}
		mkqid(&qid, pid<<QSHIFT, pid, QTDIR);
		devdir(c, qid, up->genbuf, 0, o->user, DMDIR|0555, dp);
		release();
		return 1;
	}

	if(s >= nelem(progdir))
		return -1;
	tab = &progdir[s];
	path = PATH(c->qid);

	acquire();
	p = progpid(PID(c->qid));
	if(p == nil) {
		release();
		return -1;
	}

	o = p->osenv;

	perm = tab->perm;
	if((perm & 7) == 0)
		perm = (perm|(perm>>3)|(perm>>6)) & o->pgrp->progmode;

	len = tab->length;
	mkqid(&qid, path|tab->qid.path, c->qid.vers, QTFILE);
	devdir(c, qid, tab->name, len, o->user, perm, dp);
	release();
	return 1;
}

static Chan*
progattach(char *spec)
{
	return devattach('p', spec);
}

static Walkqid*
progwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, 0, 0, proggen);
}

static int
progstat(Chan *c, uchar *db, int n)
{
	return devstat(c, db, n, 0, 0, proggen);
}

static Chan*
progopen(Chan *c, int omode)
{
	Prog *p;
	Osenv *o;
	Progctl *ctl;
	int perm;

	if(c->qid.type & QTDIR)
		return devopen(c, omode, 0, 0, proggen);

	acquire();
	if (waserror()) {
		release();
		nexterror();
	}
	p = progpid(PID(c->qid));
	if(p == nil)
		error(Ethread);

	o = p->osenv;
	perm = progdir[QID(c->qid)-1].perm;
	if((perm & 7) == 0)
		perm = (perm|(perm>>3)|(perm>>6)) & o->pgrp->progmode;
	devpermcheck(o->user, perm, omode);
	omode = openmode(omode);

	switch(QID(c->qid)){
	default:
		error(Egreg);
	case Qnsgrp:
	case Qpgrp:
	case Qtext:
	case Qstatus:
	case Qstack:
	case Qctl:
	case Qfd:
	case Qexception:
		break;
	case Qwait:
		c->aux = qopen(1024, Qmsg, nil, nil);
		if(c->aux == nil)
			error(Enomem);
		o->childq = c->aux;
		break;
	case Qns:
		c->aux = malloc(sizeof(Mntwalk));
		if(c->aux == nil)
			error(Enomem);
		break;
	case Qheap:
		if(SECURE || o->pgrp->privatemem || omode != ORDWR)
			error(Eperm);
		c->aux = malloc(sizeof(Heapqry));
		if(c->aux == nil)
			error(Enomem);
		break;
	case Qdbgctl:
		if(SECURE || o->pgrp->privatemem || omode != ORDWR)
			error(Eperm);
		ctl = malloc(sizeof(Progctl));
		if(ctl == nil)
			error(Enomem);
		ctl->q = qopen(1024, Qmsg, nil, nil);
		if(ctl->q == nil) {
			free(ctl);
			error(Enomem);
		}
		ctl->bpts = nil;
		ctl->ref = 1;
		c->aux = ctl;
		break;
	}
	if(p->state != Pexiting)
		c->qid.vers = p->pid;

	poperror();
	release();
	c->offset = 0;
	c->mode = omode;
	c->flag |= COPEN;
	return c;
}

static int
progwstat(Chan *c, uchar *db, int n)
{
	Dir d;
	Prog *p;
	char *u;
	Osenv *o;

	if(c->qid.type&QTDIR)
		error(Eperm);
	acquire();
	p = progpid(PID(c->qid));
	if(p == nil) {
		release();
		error(Ethread);
	}

	u = up->env->user;
	o = p->osenv;
	if(strcmp(u, o->user) != 0 && strcmp(u, eve) != 0) {
		release();
		error(Eperm);
	}

	n = convM2D(db, n, &d, nil);
	if(n == 0){
		release();
		error(Eshortstat);
	}
	if(d.mode != ~0UL)
		o->pgrp->progmode = d.mode&0777;
	release();
	return n;
}

static void
closedbgctl(Progctl *ctl, Prog *p)
{
	Osenv *o;

	if(ctl->ref-- > 1)
		return;
	freebpts(ctl->bpts);
	if(p != nil){
		o = p->osenv;
		if(o->debug == ctl){
			o->debug = nil;
			p->xec = xec;
		}
	}
	qfree(ctl->q);
	free(ctl);
}

static void
progclose(Chan *c)
{
	int i;
	Prog *f;
	Osenv *o;
	Progctl *ctl;

	switch(QID(c->qid)) {
	case Qns:
	case Qheap:
		free(c->aux);
		break;
	case Qdbgctl:
		if((c->flag & COPEN) == 0)
			return;
		ctl = c->aux;
		acquire();
		closedbgctl(ctl, progpid(PID(c->qid)));
		release();
		break;
	case Qwait:
		acquire();
		i = 0;
		for(;;) {
			f = progn(i++);
			if(f == nil)
				break;
			o = f->osenv;
			if(o->waitq == c->aux)
				o->waitq = nil;
			if(o->childq == c->aux)
				o->childq = nil;
		}
		release();
		qfree(c->aux);
	}
}

static int
progsize(Prog *p)
{
	int size;
	Frame *f;
	uchar *fp;
	Modlink *m;

	m = p->R.M;
	size = 0;
	if(m->MP != H)
		size += hmsize(D2H(m->MP));
	if(m->prog != nil)
		size += msize(m->prog);

	fp = p->R.FP;
	while(fp != nil) {
		f = (Frame*)fp;
		fp = f->fp;
		if(f->mr != nil) {
			if(f->mr->MP != H)
				size += hmsize(D2H(f->mr->MP));
			if(f->mr->prog != nil)
				size += msize(f->mr->prog);
		}
		if(f->t == nil)
			size += msize(SEXTYPE(f));
	}
	return size/1024;
}

static long
progoffset(long offset, char *va, int *np)
{
	if(offset > 0) {
		offset -= *np;
		if(offset < 0) {
			memmove(va, va+*np+offset, -offset);
			*np = -offset;
		}
		else
			*np = 0;
	}
	return offset;
}

static int
progqidwidth(Chan *c)
{
	char buf[32];

	return sprint(buf, "%lud", c->qid.vers);
}

int
progfdprint(Chan *c, int fd, int w, char *s, int ns)
{
	int n;

	if(w == 0)
		w = progqidwidth(c);
	n = snprint(s, ns, "%3d %.2s %C %4ld (%.16llux %*lud %.2ux) %5ld %8lld %s\n",
		fd,
		&"r w rw"[(c->mode&3)<<1],
		devtab[c->type]->dc, c->dev,
		c->qid.path, w, c->qid.vers, c->qid.type,
		c->iounit, c->offset, c->name->s);
	return n;
}

static int
progfds(Osenv *o, char *va, int count, long offset)
{
	Fgrp *f;
	Chan *c;
	int n, i, w, ww;

	f = o->fgrp;	/* f is not locked because we've acquired */
	n = readstr(0, va, count, o->pgrp->dot->name->s);
	n += snprint(va+n, count-n, "\n");
	offset = progoffset(offset, va, &n);
	/* compute width of qid.path */
	w = 0;
	for(i = 0; i <= f->maxfd; i++) {
		c = f->fd[i];
		if(c == nil)
			continue;
		ww = progqidwidth(c);
		if(ww > w)
			w = ww;
	}
	for(i = 0; i <= f->maxfd; i++) {
		c = f->fd[i];
		if(c == nil)
			continue;
		n += progfdprint(c, i, w, va+n, count-n);
		offset = progoffset(offset, va, &n);
	}
	return n;
}

Inst *
pc2dispc(Inst *pc, Module *mod)
{
	ulong l, u, m, v;
	ulong *tab = mod->pctab;

	v = (ulong)pc - (ulong)mod->prog;
	l = 0;
	u = mod->nprog-1;
	while(l < u){
		m = (l+u+1)/2;
		if(tab[m] < v)
			l = m;
		else if(tab[m] > v)
			u = m-1;
		else
			l = u = m;
	}
	if(l == u && tab[u] <= v && u != mod->nprog-1 && tab[u+1] > v)
		return &mod->prog[u];
	return 0;
}

static int
progstack(REG *reg, int state, char *va, int count, long offset)
{
	int n;
	Frame *f;
	Inst *pc;
	uchar *fp;
	Modlink *m;

	n = 0;
	m = reg->M;
	fp = reg->FP;
	pc = reg->PC;

	/*
	 * all states other than debug and ready block,
	 * but interp has already advanced the PC
	 */
	if(!m->compiled && state != Pready && state != Pdebug && pc > m->prog)
		pc--;
	if(m->compiled && m->m->pctab != nil)
		pc = pc2dispc(pc, m->m);

	while(fp != nil) {
		f = (Frame*)fp;
		n += snprint(va+n, count-n, "%.8lux %.8lux %.8lux %.8lux %d %s\n",
				(ulong)f,		/* FP */
				(ulong)(pc - m->prog),	/* PC in dis instructions */
				(ulong)m->MP,		/* MP */
				(ulong)m->prog,	/* Code for module */
				m->compiled && m->m->pctab == nil,	/* True if native assembler: fool stack utility for now */
				m->m->path);	/* File system path */

		if(offset > 0) {
			offset -= n;
			if(offset < 0) {
				memmove(va, va+n+offset, -offset);
				n = -offset;
			}
			else
				n = 0;
		}

		pc = f->lr;
		fp = f->fp;
		if(f->mr != nil)
			m = f->mr;
		if(!m->compiled)
			pc--;
		else if(m->m->pctab != nil)
			pc = pc2dispc(pc, m->m)-1;
	}
	return n;
}

static int
calldepth(REG *reg)
{
	int n;
	uchar *fp;

	n = 0;
	for(fp = reg->FP; fp != nil; fp = ((Frame*)fp)->fp)
		n++;
	return n;
}

static int
progheap(Heapqry *hq, char *va, int count, ulong offset)
{
	WORD *w;
	void *p;
	List *hd;
	Array *a;
	char *fmt, *str;
	Module *m;
	Modlink *ml;
	Channel *c;
	ulong addr;
	String *ss;
	union { REAL r; LONG l; WORD w[2]; } rock;
	int i, s, n, len, signed_off;
	Type *t;

	n = 0;
	s = 0;
	signed_off = offset;
	addr = hq->addr;
	for(i = 0; i < hq->count; i++) {
		switch(hq->fmt) {
		case 'W':
			if(addr & 3)
				return -1;
			n += snprint(va+n, count-n, "%d\n", *(WORD*)addr);
			s = sizeof(WORD);
			break;
		case 'B':
			n += snprint(va+n, count-n, "%d\n", *(BYTE*)addr);
			s = sizeof(BYTE);
			break;
		case 'V':
			if(addr & 3)
				return -1;
			w = (WORD*)addr;
			rock.w[0] = w[0];
			rock.w[1] = w[1];
			n += snprint(va+n, count-n, "%lld\n", rock.l);
			s = sizeof(LONG);
			break;
		case 'R':
			if(addr & 3)
				return -1;
			w = (WORD*)addr;
			rock.w[0] = w[0];
			rock.w[1] = w[1];
			n += snprint(va+n, count-n, "%g\n", rock.r);
			s = sizeof(REAL);
			break;
		case 'I':
			if(addr & 3)
				return -1;
			for(m = modules; m != nil; m = m->link)
				if(m == (Module*)hq->module)
					break;
			if(m == nil)
				error(Ebadctl);
			addr = (ulong)(m->prog+addr);
			n += snprint(va+n, count-n, "%D\n", (Inst*)addr);
			s = sizeof(Inst);
			break;
		case 'P':
			if(addr & 3)
				return -1;
			p = *(void**)addr;
			fmt = "nil\n";
			if(p != H)
				fmt = "%lux\n";
			n += snprint(va+n, count-n, fmt, p);
			s = sizeof(WORD);
			break;
		case 'L':
			if(addr & 3)
				return -1;
			hd = *(List**)addr;
			if(hd == H || D2H(hd)->t != &Tlist)
				return -1;
			n += snprint(va+n, count-n, "%lux.%lux\n", (ulong)&hd->tail, (ulong)hd->data);
			s = sizeof(WORD);
			break;
		case 'A':
			if(addr & 3)
				return -1;
			a = *(Array**)addr;
			if(a == H)
				n += snprint(va+n, count-n, "nil\n");
			else {
				if(D2H(a)->t != &Tarray)
					return -1;
				n += snprint(va+n, count-n, "%d.%lux\n", a->len, (ulong)a->data);
			}
			s = sizeof(WORD);
			break;
		case 'C':
			if(addr & 3)
				return -1;
			ss = *(String**)addr;
			if(ss == H)
				ss = &snil;
			else
			if(D2H(ss)->t != &Tstring)
				return -1;
			n += snprint(va+n, count-n, "%d.", abs(ss->len));
			str = string2c(ss);
			len = strlen(str);
			if(count-n < len)
				len = count-n;
			if(len > 0) {
				memmove(va+n, str, len);
				n += len;
			}
			break;
		case 'M':
			if(addr & 3)
				return -1;
			ml = *(Modlink**)addr;
			fmt = ml == H ? "nil\n" : "%lux\n";
			n += snprint(va+n, count-n, fmt, ml->MP);
			s = sizeof(WORD);
			break;
		case 'c':
			if(addr & 3)
				return -1;
			c = *(Channel**)addr;
			if(c == H)
				n += snprint(va+n, count-n, "nil\n");
			else{
				t = D2H(c)->t;
				if(t != &Tchannel && t != Trdchan && t != Twrchan)
					return -1;
				if(c->buf == H)
					n += snprint(va+n, count-n, "0.%lux\n", (ulong)c);
				else
					n += snprint(va+n, count-n, "%d.%lux.%d.%d\n", c->buf->len, (ulong)c->buf->data, c->front, c->size);
			}
			break;
			
		}
		addr += s;
		if(signed_off > 0) {
			signed_off -= n;
			if(signed_off < 0) {
				memmove(va, va+n+signed_off, -signed_off);
				n = -signed_off;
			}
			else
				n = 0;
		}
	}
	return n;
}

WORD
modstatus(REG *r, char *ptr, int len)
{
	Inst *PC;
	Frame *f;

	if(r->M->m->name[0] == '$') {
		f = (Frame*)r->FP;
		snprint(ptr, len, "%s[%s]", f->mr->m->name, r->M->m->name);
		if(f->mr->compiled)
			return (WORD)f->lr;
		return f->lr - f->mr->prog;
	}
	memmove(ptr, r->M->m->name, len);
	if(r->M->compiled)
		return (WORD)r->PC;
	PC = r->PC;
	/* should really check for blocked states */
	if(PC > r->M->prog)
		PC--;
	return PC - r->M->prog;
}

static void
int2flag(int flag, char *s)
{
	if(flag == 0){
		*s = '\0';
		return;
	}
	*s++ = '-';
	if(flag & MAFTER)
		*s++ = 'a';
	if(flag & MBEFORE)
		*s++ = 'b';
	if(flag & MCREATE)
		*s++ = 'c';
	if(flag & MCACHE)
		*s++ = 'C';
	*s = '\0';
}

static char*
progtime(ulong msec, char *buf, char *ebuf)
{
	int tenths, sec;

	tenths = msec/100;
	sec = tenths/10;
	seprint(buf, ebuf, "%4d:%2.2d.%d", sec/60, sec%60, tenths%10);
	return buf;
}

static long
progread(Chan *c, void *va, long n, vlong offset)
{
	int i;
	Prog *p;
	Osenv *o;
	Mntwalk *mw;
	ulong grpid;
	char *a = va;
	Progctl *ctl;
	char mbuf[64], timebuf[12];
	char flag[10];

	if(c->qid.type & QTDIR)
		return devdirread(c, a, n, 0, 0, proggen);

	switch(QID(c->qid)){
	case Qdbgctl:
		ctl = c->aux;
		return qread(ctl->q, va, n);
	case Qstatus:
		acquire();
		p = progpid(PID(c->qid));
		if(p == nil || p->state == Pexiting || p->R.M == H) {
			release();
			snprint(up->genbuf, sizeof(up->genbuf), "%8lud %8d %10s %s %10s %5dK %s",
				PID(c->qid),
				0,
				eve,
				progtime(0, timebuf, timebuf+sizeof(timebuf)),
				progstate[Pexiting],
				0,
				"[$Sys]");
			return readstr(offset, va, n, up->genbuf);
		}
		modstatus(&p->R, mbuf, sizeof(mbuf));
		o = p->osenv;
		snprint(up->genbuf, sizeof(up->genbuf), "%8d %8d %10s %s %10s %5dK %s",
			p->pid,
			p->group!=nil? p->group->id: 0,
			o->user,
			progtime(TK2MS(p->ticks), timebuf, timebuf+sizeof(timebuf)),
			progstate[p->state],
			progsize(p),
			mbuf);
		release();
		return readstr(offset, va, n, up->genbuf);
	case Qwait:
		return qread(c->aux, va, n);
	case Qns:
		acquire();
		if(waserror()){
			release();
			nexterror();
		}
		p = progpid(PID(c->qid));
		if(p == nil)
			error(Ethread);
		mw = c->aux;
		if(mw->cddone){
			poperror();
			release();
			return 0;
		}
		o = p->osenv;
		mntscan(mw, o->pgrp);
		if(mw->mh == 0) {
			mw->cddone = 1;
			i = snprint(a, n, "cd %s\n", o->pgrp->dot->name->s);
			poperror();
			release();
			return i;
		}
		int2flag(mw->cm->mflag, flag);
		if(strcmp(mw->cm->to->name->s, "#M") == 0){
			i = snprint(a, n, "mount %s %s %s %s\n", flag,
				mw->cm->to->mchan->name->s,
				mw->mh->from->name->s, mw->cm->spec? mw->cm->spec : "");
		}else
			i = snprint(a, n, "bind %s %s %s\n", flag,
				mw->cm->to->name->s, mw->mh->from->name->s);
		poperror();
		release();
		return i;
	case Qnsgrp:
		acquire();
		p = progpid(PID(c->qid));
		if(p == nil) {
			release();
			error(Ethread);
		}
		grpid = ((Osenv *)p->osenv)->pgrp->pgrpid;
		release();
		return readnum(offset, va, n, grpid, NUMSIZE);
	case Qpgrp:
		acquire();
		p = progpid(PID(c->qid));
		if(p == nil) {
			release();
			error(Ethread);
		}
		grpid = p->group!=nil? p->group->id: 0;
		release();
		return readnum(offset, va, n, grpid, NUMSIZE);
	case Qstack:
		acquire();
		p = progpid(PID(c->qid));
		if(p == nil || p->state == Pexiting) {
			release();
			error(Ethread);
		}
		if(p->state == Pready) {
			release();
			error(Estopped);
		}
		n = progstack(&p->R, p->state, va, n, offset);
		release();
		return n;
	case Qheap:
		acquire();
		if(waserror()){
			release();
			nexterror();
		}
		n = progheap(c->aux, va, n, offset);
		if(n == -1)
			error(Emisalign);
		poperror();
		release();
		return n;
	case Qfd:
		acquire();
		if(waserror()) {
			release();
			nexterror();
		}
		p = progpid(PID(c->qid));
		if(p == nil)
			error(Ethread);
		o = p->osenv;
		n = progfds(o, va, n, offset);
		poperror();
		release();
		return n;
	case Qexception:
		acquire();
		p = progpid(PID(c->qid));
		if(p == nil) {
			release();
			error(Ethread);
		}
		if(p->exstr == nil)
			up->genbuf[0] = 0;
		else
			snprint(up->genbuf, sizeof(up->genbuf), p->exstr);
		release();
		return readstr(offset, va, n, up->genbuf);
	}
	error(Egreg);
	return 0;
}

static void
mntscan(Mntwalk *mw, Pgrp *pg)
{
	Mount *t;
	Mhead *f;
	int nxt, i;
	ulong last, bestmid;

	rlock(&pg->ns);

	nxt = 0;
	bestmid = ~0;

	last = 0;
	if(mw->mh)
		last = mw->cm->mountid;

	for(i = 0; i < MNTHASH; i++) {
		for(f = pg->mnthash[i]; f; f = f->hash) {
			for(t = f->mount; t; t = t->next) {
				if(mw->mh == 0 ||
				  (t->mountid > last && t->mountid < bestmid)) {
					mw->cm = t;
					mw->mh = f;
					bestmid = mw->cm->mountid;
					nxt = 1;
				}
			}
		}
	}
	if(nxt == 0)
		mw->mh = 0;

	runlock(&pg->ns);
}

static long
progwrite(Chan *c, void *va, long n, vlong offset)
{
	Prog *p, *f;
	Heapqry *hq;
	char buf[128];
	Progctl *ctl;
	char *b;
	int i, pc;
	Cmdbuf *cb;
	Cmdtab *ct;
	Osenv *o;

	USED(offset);
	USED(va);

	if(c->qid.type & QTDIR)
		error(Eisdir);

	acquire();
	if(waserror()) {
		release();
		nexterror();
	}
	p = progpid(PID(c->qid));
	if(p == nil)
		error(Ethread);

	switch(QID(c->qid)){
	case Qctl:
		cb = parsecmd(va, n);
		if(waserror()){
			free(cb);
			nexterror();
		}
		ct = lookupcmd(cb, progcmd, nelem(progcmd));
		switch(ct->index){
		case CMkillgrp:
			killgrp(p, "killed");
			break;
		case CMkill:
			killprog(p, "killed");
			break;
		case CMrestricted:
			p->flags |= Prestrict;
			break;
		case CMexceptions:
			if(p->group->id != p->pid)
				error(Eperm);
			if(strcmp(cb->f[1], "propagate") == 0)
				p->flags |= Ppropagate;
			else if(strcmp(cb->f[1], "notifyleader") == 0)
				p->flags |= Pnotifyleader;
			else
				error(Ebadctl);
			break;
		case CMprivate:
			o = p->osenv;
			o->pgrp->privatemem = 1;
			break;
		}
		poperror();
		free(cb);
		break;
	case Qdbgctl:
		cb = parsecmd(va, n);
		if(waserror()){
			free(cb);
			nexterror();
		}
		if(cb->nf == 1 && strncmp(cb->f[0], "step", 4) == 0)
			ct = progdbgcmd;
		else
			ct = lookupcmd(cb, progdbgcmd, nelem(progdbgcmd));
		switch(ct->index){
		case CDstep:
			if(cb->nf == 1)
				i = strtoul(cb->f[0]+4, nil, 0);
			else
				i = strtoul(cb->f[1], nil, 0);
			dbgstep(c->aux, p, i);
			break;
		case CDtoret:
			f = currun();
			i = calldepth(&p->R);
			while(f->kill == nil) {
				dbgstep(c->aux, p, 1024);
				if(i > calldepth(&p->R))
					break;
			}
			break;
		case CDcont:
			f = currun();
			while(f->kill == nil)
				dbgstep(c->aux, p, 1024);
			break;
		case CDstart:
			dbgstart(p);
			break;
		case CDstop:
			ctl = c->aux;
			ctl->stop = 1;
			break;
		case CDunstop:
			ctl = c->aux;
			ctl->stop = 0;
			break;
		case CDbpt:
			pc = strtoul(cb->f[3], nil, 10);
			ctl = c->aux;
			if(strcmp(cb->f[1], "set") == 0)
				ctl->bpts = setbpt(ctl->bpts, cb->f[2], pc);
			else if(strcmp(cb->f[1], "del") == 0)
				ctl->bpts = delbpt(ctl->bpts, cb->f[2], pc);
			else
				error(Ebadctl);
			break;
		case CDmaim:
			p->kill = "maim";
			break;
		}
		poperror();
		free(cb);
		break;
	case Qheap:
		/*
		 * Heap query:
		 *	addr.Fn
		 *	pc+module.In
		 */
		i = n;
		if(i > sizeof(buf)-1)
			i = sizeof(buf)-1;
		memmove(buf, va, i);
		buf[i] = '\0';
		hq = c->aux;
		hq->addr = strtoul(buf, &b, 0);
		if(*b == '+')
			hq->module = strtoul(b, &b, 0);
		if(*b++ != '.')
			error(Ebadctl);
		hq->fmt = *b++;
		hq->count = strtoul(b, nil, 0);
		break;
	default:
		print("unknown qid in procwrite\n");
		error(Egreg);
	}
	poperror();
	release();
	return n;
}

static Bpt*
setbpt(Bpt *bpts, char *path, int pc)
{
	int n;
	Bpt *b;

	n = strlen(path);
	b = mallocz(sizeof *b + n, 0);
	if(b == nil)
		return bpts;
	b->pc = pc;
	memmove(b->path, path, n+1);
	b->file = b->path;
	path = strrchr(b->path, '/');
	if(path != nil)
		b->file = path + 1;
	b->next = bpts;
	return b;
}

static Bpt*
delbpt(Bpt *bpts, char *path, int pc)
{
	Bpt *b, **last;

	last = &bpts;
	for(b = bpts; b != nil; b = b->next){
		if(b->pc == pc && strcmp(b->path, path) == 0) {
			*last = b->next;
			free(b);
			break;
		}
		last = &b->next;
	}
	return bpts;
}

static void
freebpts(Bpt *b)
{
	Bpt *next;

	for(; b != nil; b = next){
		next = b->next;
		free(b);
	}
}

static void
telldbg(Progctl *ctl, char *msg)
{
	kstrcpy(ctl->msg, msg, ERRMAX);
	ctl->debugger = nil;
	wakeup(&ctl->r);
}

static void
dbgstart(Prog *p)
{
	Osenv *o;
	Progctl *ctl;

	o = p->osenv;
	ctl = o->debug;
	if(ctl != nil && ctl->debugger != nil)
		error("prog debugged");
	if(p->state == Pdebug)
		addrun(p);
	o->debug = nil;
	p->xec = xec;
}

static int
xecdone(void *vc)
{
	Progctl *ctl = vc;

	return ctl->debugger == nil;
}

static void
dbgstep(Progctl *vctl, Prog *p, int n)
{
	Osenv *o;
	Progctl *ctl;
	char buf[ERRMAX+20], *msg;

	if(p == currun())
		error("cannot step yourself");

	if(p->state == Pbroken)
		error("prog broken");

	ctl = vctl;
	if(ctl->debugger != nil)
		error("prog already debugged");

	o = p->osenv;
	if(o->debug == nil) {
		o->debug = ctl;
		p->xec = dbgxec;
	}else if(o->debug != ctl)
		error("prog already debugged");

	ctl->step = n;
	if(p->state == Pdebug)
		addrun(p);
	ctl->debugger = up;
	strcpy(buf, "child: ");
	msg = buf+7;
	ctl->msg = msg;

	/*
	 * wait for reply from dbgxec; release is okay because prog is now
	 * debugged, cannot exit.
	 */
	if(waserror()){
		acquire();
		ctl->debugger = nil;
		ctl->msg = nil;
		o->debug = nil;
		p->xec = xec;
		nexterror();
	}
	release();
	sleep(&ctl->r, xecdone, ctl);
	poperror();
	acquire();
	if(msg[0] != '\0')
		error(buf);
}

void
dbgexit(Prog *kid, int broken, char *estr)
{
	int n;
	Osenv *e;
	Progctl *ctl;
	char buf[ERRMAX+20];

	e = kid->osenv;
	ctl = e->debug;
	e->debug = nil;
	kid->xec = xec;

	if(broken)
		n = snprint(buf, sizeof(buf), "broken: %s", estr);
	else
		n = snprint(buf, sizeof(buf), "exited");
	if(ctl->debugger)
		telldbg(ctl, buf);
	qproduce(ctl->q, buf, n);
}

static void
dbgaddrun(Prog *p)
{
	Osenv *o;

	p->state = Pdebug;
	p->addrun = nil;
	o = p->osenv;
	if(o->rend != nil)
		wakeup(o->rend);
	o->rend = nil;
}

static int
bdone(void *vp)
{
	Prog *p = vp;

	return p->addrun == nil;
}

static void
dbgblock(Prog *p)
{
	Osenv *o;
	Progctl *ctl;

	o = p->osenv;
	ctl = o->debug;
	qproduce(ctl->q, progstate[p->state], strlen(progstate[p->state]));
	pushrun(p);
	p->addrun = dbgaddrun;
	o->rend = &up->sleep;

	/*
	 * bdone(p) is safe after release because p is being debugged,
	 * so cannot exit.
	 */
	if(waserror()){
		acquire();
		nexterror();
	}
	release();
	if(o->rend != nil)
		sleep(o->rend, bdone, p);
	poperror();
	acquire();
	if(p->kill != nil)
		error(p->kill);
	ctl = o->debug;
	if(ctl != nil)
		qproduce(ctl->q, "run", 3);
}

void
dbgxec(Prog *p)
{
	Bpt *b;
	Prog *kid;
	Osenv *env;
	Progctl *ctl;
	int op, pc, n;
	char buf[ERRMAX+10];
	extern void (*dec[])(void);

	env = p->osenv;
	ctl = env->debug;
	ctl->ref++;
	if(waserror()){
		closedbgctl(ctl, p);
		nexterror();
	}

	R = p->R;
	R.MP = R.M->MP;

	R.IC = p->quanta;
	if((ulong)R.IC > ctl->step)
		R.IC = ctl->step;
	if(ctl->stop)
		R.IC = 0;


	buf[0] = '\0';

	if(R.IC != 0 && R.M->compiled) {
		comvec();
		if(p != currun())
			dbgblock(p);
		goto save;
	}

	while(R.IC != 0) {
		if(0)
			print("step: %lux: %s %4ld %D\n",
				(ulong)p, R.M->m->name, R.PC-R.M->prog, R.PC);

		dec[R.PC->add]();
		op = R.PC->op;
		R.PC++;
		optab[op]();

		/*
		 * check notification about new progs
		 */
		if(op == ISPAWN || op == IMSPAWN) {
			/* pick up the kid from the end of the run queue */
			kid = delruntail(Pdebug);
			n = snprint(buf, sizeof buf, "new %d", kid->pid);
			qproduce(ctl->q, buf, n);
			buf[0] = '\0';
		}
		if(op == ILOAD) {
			n = snprint(buf, sizeof buf, "load %s", string2c(*(String**)R.s));
			qproduce(ctl->q, buf, n);
			buf[0] = '\0';
		}

		/*
		 * check for returns at big steps
		 */
		if(op == IRET)
			R.IC = 1;

		/*
		 * check for blocked progs
		 */
		if(R.IC == 1 && p != currun())
			dbgblock(p);
		if(ctl->stop)
			R.IC = 1;
		R.IC--;
		if(ctl->bpts == nil)
			continue;
		pc = R.PC - R.M->prog;
		for(b = ctl->bpts; b != nil; b = b->next) {
			if(pc == b->pc &&
			  (strcmp(R.M->m->path, b->path) == 0 ||
			   strcmp(R.M->m->path, b->file) == 0)) {
				strcpy(buf, "breakpoint");
				goto save;
			}
		}
	}

save:
	if(ctl->stop)
		strcpy(buf, "stopped");

	p->R = R;

	if(env->debug == nil) {
		poperror();
		return;
	}

	if(p == currun())
		delrun(Pdebug);

	telldbg(env->debug, buf);
	poperror();
	closedbgctl(env->debug, p);
}

Dev progdevtab = {
	'p',
	"prog",

	devreset,
	devinit,
	devshutdown,
	progattach,
	progwalk,
	progstat,
	progopen,
	devcreate,
	progclose,
	progread,
	devbread,
	progwrite,
	devbwrite,
	devremove,
	progwstat,
};
