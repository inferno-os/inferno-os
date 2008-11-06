#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "../port/error.h"
#include <isa.h>
#include <interp.h>
#include <kernel.h>
#include "raise.h"

	void	vmachine(void*);

struct
{
	Lock	l;
	Prog*	runhd;
	Prog*	runtl;
	Prog*	head;
	Prog*	tail;
	Rendez	irend;
	int	idle;
	int	nyield;
	int	creating;
	Proc*	vmq;		/* queue of procs wanting vm */
	Proc*	vmqt;
	Proc*	idlevmq;	/* queue of procs wanting work */
	Atidle*	idletasks;
} isched;

int	bflag;
int	cflag;
uvlong	gcbusy;
uvlong	gcidle;
uvlong	gcidlepass;
uvlong	gcpartial;
int keepbroken = 1;
static Prog*	proghash[64];

static Progs*	delgrp(Prog*);
static void	addgrp(Prog*, Prog*);
void	printgrp(Prog*, char*);

static Prog**
pidlook(int pid)
{
	ulong h;
	Prog **l;

	h = (ulong)pid % nelem(proghash);
	for(l = &proghash[h]; *l != nil && (*l)->pid != pid; l = &(*l)->pidlink)
		;
	return l;
}

int
tready(void *a)
{
	USED(a);
	return isched.runhd != nil || isched.vmq != nil;
}

Prog*
progpid(int pid)
{
	return *pidlook(pid);
}

Prog*
progn(int n)
{
	Prog *p;

	for(p = isched.head; p && n--; p = p->next)
		;
	return p;
}

int
nprog(void)
{
	int n;
	Prog *p;

	n = 0;
	for(p = isched.head; p; p = p->next)
		n++;
	return n;
}

static void
accountant(void)
{
	Prog *p;

	p = isched.runhd;
	if(p != nil)
		p->ticks++;
}

static void
execatidle(void)
{
	int done;

	if(tready(nil))
		return;

	gcidle++;
	up->type = IdleGC;
	up->iprog = nil;
	addrun(up->prog);

	done = gccolor+3;
	while(gccolor < done && gcruns()) {
		if(isched.vmq != nil || isched.runhd != isched.runtl) {
			gcpartial++;
			break;
		}
		rungc(isched.head);
		gcidlepass++;
		sched();
	}

	up->type = Interp;
	delrunq(up->prog);
}

Prog*
newprog(Prog *p, Modlink *m)
{
	Heap *h;
	Prog *n, **ph;
	Osenv *on, *op;
	static int pidnum;

	if(p != nil){
		if(p->group != nil)
			p->flags |= p->group->flags & Pkilled;
		if(p->kill != nil)
			error(p->kill);
		if(p->flags & Pkilled)
			error("");
	}
	n = malloc(sizeof(Prog)+sizeof(Osenv));
	if(n == 0){
		if(p == nil)
			panic("no memory");
		else
			error(exNomem);
	}

	n->pid = ++pidnum;
	if(n->pid <= 0)
		panic("no pids");
	n->group = nil;

	if(isched.tail != nil) {
		n->prev = isched.tail;
		isched.tail->next = n;
	}
	else {
		isched.head = n;
		n->prev = nil;
	}
	isched.tail = n;

	ph = pidlook(n->pid);
	if(*ph != nil)
		panic("dup pid");
	n->pidlink = nil;
	*ph = n;

	n->osenv = (Osenv*)((uchar*)n + sizeof(Prog));
	n->xec = xec;
	n->quanta = PQUANTA;
	n->flags = 0;
	n->exval = H;

	h = D2H(m);
	h->ref++;
	Setmark(h);
	n->R.M = m;
	n->R.MP = m->MP;
	if(m->MP != H)
		Setmark(D2H(m->MP));
	addrun(n);

	if(p == nil){
		newgrp(n);
		return n;
	}

	addgrp(n, p);
	n->flags = p->flags;
	if(p->flags & Prestrict)
		n->flags |= Prestricted;
	memmove(n->osenv, p->osenv, sizeof(Osenv));
	op = p->osenv;
	on = n->osenv;
	on->waitq = op->childq;
	on->childq = nil;
	on->debug = nil;
	incref(on->pgrp);
	incref(on->fgrp);
	if(on->egrp != nil)
		incref(on->egrp);
	if(on->sigs != nil)
		incref(on->sigs);
	on->user = nil;
	kstrdup(&on->user, op->user);
	on->errstr = on->errbuf0;
	on->syserrstr = on->errbuf1;

	return n;
}

void
delprog(Prog *p, char *msg)
{
	Osenv *o;
	Prog **ph;

	tellsomeone(p, msg);	/* call before being removed from prog list */

	o = p->osenv;
	release();
	closepgrp(o->pgrp);
	closefgrp(o->fgrp);
	closeegrp(o->egrp);
	closesigs(o->sigs);
	acquire();

	delgrp(p);

	if(p->prev)
		p->prev->next = p->next;
	else
		isched.head = p->next;

	if(p->next)
		p->next->prev = p->prev;
	else
		isched.tail = p->prev;

	ph = pidlook(p->pid);
	if(*ph == nil)
		panic("lost pid");
	*ph = p->pidlink;

	if(p == isched.runhd) {
		isched.runhd = p->link;
		if(p->link == nil)
			isched.runtl = nil;
	}
	p->state = 0xdeadbeef;
	free(o->user);
	free(p->killstr);
	free(p->exstr);
	free(p);
}

void
renameproguser(char *old, char *new)
{
	Prog *p;
	Osenv *o;

	acquire();
	for(p = isched.head; p; p = p->next){
		o = p->osenv;
		if(o->user != nil && strcmp(o->user, old) == 0)
			kstrdup(&o->user, new);
	}
	release();
}

void
tellsomeone(Prog *p, char *buf)
{
	Osenv *o;

	if(waserror())
		return;
	o = p->osenv;
	if(o->childq != nil)
		qproduce(o->childq, buf, strlen(buf));
	if(o->waitq != nil)
		qproduce(o->waitq, buf, strlen(buf));
	poperror();
}

static void
swiprog(Prog *p)
{
	Proc *q, *eq;

	q = proctab(0);
	for(eq = q+conf.nproc; q < eq; q++) {
		if(q->iprog == p) {
			swiproc(q, 1);
			return;
		}
	}
	/*print("didn't find\n");*/
}

static Prog*
grpleader(Prog *p)
{
	Progs *g;
	Prog *l;

	g = p->group;
	if(g != nil && (l = g->head) != nil && l->pid == g->id)
		return l;
	return nil;
}

int
exprog(Prog *p, char *exc)
{
	switch(p->state) {
	case Palt:
		altdone(p->R.s, p, nil, -1);
		break;
	case Psend:
		cqdelp(&p->chan->send, p);
		break;
	case Precv:
		cqdelp(&p->chan->recv, p);
		break;
	case Pready:
		break;
	case Prelease:
		swiprog(p);
		break;
	case Pexiting:
	case Pbroken:
	case Pdebug:
		return 0;
	default:
		panic("exprog - bad state 0x%x\n", p->state);
	}
	if(p->state != Pready && p->state != Prelease)
		addrun(p);
	if(p->kill == nil){
		if(p->killstr == nil){
			p->killstr = malloc(ERRMAX);
			if(p->killstr == nil){
				p->kill = Enomem;
				return 1;
			}
		}
		kstrcpy(p->killstr, exc, ERRMAX);
		p->kill = p->killstr;
	}
	return 1;
}

static void
propex(Prog *p, char *estr)
{
	Prog *f, *nf, *pgl;

	if(!(p->flags & (Ppropagate|Pnotifyleader)) || p->group == nil)
		return;
	if(*estr == 0){
		if((p->flags & Pkilled) == 0)
			return;
		estr = "killed";
	}
	pgl = grpleader(p);
	if(pgl == nil)
		pgl = p;
	if(!(pgl->flags & (Ppropagate|Pnotifyleader)))
		return;	/* exceptions are local; don't propagate */
	for(f = p->group->head; f != nil; f = nf){
		nf = f->grpnext;
		if(f != p && f != pgl){
			if(pgl->flags & Ppropagate)
				exprog(f, estr);
			else{
				f->flags &= ~(Ppropagate|Pnotifyleader);	/* prevent recursion */
				killprog(f, "killed");
			}
		}
	}
	if(p != pgl)
		exprog(pgl, estr);
}

int
killprog(Prog *p, char *cause)
{
	Osenv *env;
	char msg[ERRMAX+2*KNAMELEN];

	if(p == isched.runhd) {
		p->kill = "";
		p->flags |= Pkilled;
		p->state = Pexiting;
		return 0;
	}

	switch(p->state) {
	case Palt:
		altdone(p->R.s, p, nil, -1);
		break;
	case Psend:
		cqdelp(&p->chan->send, p);
		break;
	case Precv:
		cqdelp(&p->chan->recv, p);
		break;
	case Pready:
		delrunq(p);
		break;
	case Prelease:
		p->kill = "";
		p->flags |= Pkilled;
		p->state = Pexiting;
		swiprog(p);
		/* No break */
	case Pexiting:
		return 0;
	case Pbroken:
	case Pdebug:
		break;
	default:
		panic("killprog - bad state 0x%x\n", p->state);
	}

	if(p->addrun != nil) {
		p->kill = "";
		p->flags |= Pkilled;
		p->addrun(p);
		p->addrun = nil;
		return 0;
	}

	env = p->osenv;
	if(env->debug != nil) {
		p->state = Pbroken;
		dbgexit(p, 0, cause);
		return 0;
	}

	propex(p, "killed");

	snprint(msg, sizeof(msg), "%d \"%s\":%s", p->pid, p->R.M->m->name, cause);

	p->state = Pexiting;
	gclock();
	destroystack(&p->R);
	delprog(p, msg);
	gcunlock();

	return 1;
}

void
newgrp(Prog *p)
{
	Progs *pg, *g;

	if(p->group != nil && p->group->id == p->pid)
		return;
	g = malloc(sizeof(*g));
	if(g == nil)
		error(Enomem);
	p->flags &= ~(Ppropagate|Pnotifyleader);
	g->id = p->pid;
	g->flags = 0;
	g->child = nil;
	pg = delgrp(p);
	g->head = g->tail = p;
	p->group = g;
	if(pg != nil){
		g->sib = pg->child;
		pg->child = g;
	}
	g->parent = pg;
}

static void
addgrp(Prog *n, Prog *p)
{
	Progs *g;

	n->group = p->group;
	if((g = n->group) != nil){
		n->grpnext = nil;
		if(g->head != nil){
			n->grpprev = g->tail;
			g->tail->grpnext = n;
		}else{
			n->grpprev = nil;
			g->head = n;
		}
		g->tail = n;
	}
}

static Progs*
delgrp(Prog *p)
{
	Progs *g, *pg, *cg, **l;

	g = p->group;
	if(g == nil)
		return nil;
	if(p->grpprev)
		p->grpprev->grpnext = p->grpnext;
	else
		g->head = p->grpnext;
	if(p->grpnext)
		p->grpnext->grpprev = p->grpprev;
	else
		g->tail = p->grpprev;
	p->grpprev = p->grpnext = nil;
	p->group = nil;

	if(g->head == nil){
		/* move up, giving subgroups of groups with no Progs to their parents */
		do{
			if((pg = g->parent) != nil){
				pg = g->parent;
				for(l = &pg->child; *l != nil && *l != g; l = &(*l)->sib)
					;
				*l = g->sib;
			}
			/* put subgroups in new parent group */
			while((cg = g->child) != nil){
				g->child = cg->sib;
				cg->parent = pg;
				if(pg != nil){
					cg->sib = pg->child;
					pg->child = cg;
				}
			}
			free(g);
		}while((g = pg) != nil && g->head == nil);
	}
	return g;
}

void
printgrp(Prog *p, char *v)
{
	Progs *g;
	Prog *q;

	g = p->group;
	print("%s pid %d grp %d pgrp %d: [pid", v, p->pid, g->id, g->parent!=nil?g->parent->id:0);
	for(q = g->head; q != nil; q = q->grpnext)
		print(" %d", q->pid);
	print(" subgrp");
	for(g = g->child; g != nil; g = g->sib)
		print(" %d", g->id);
	print("]\n");
}

int
killgrp(Prog *p, char *msg)
{
	int i, npid, *pids;
	Prog *f;
	Progs *g;

	/* interpreter has been acquired */
	g = p->group;
	if(g == nil || g->head == nil)
		return 0;
	while(g->flags & Pkilled){
		release();
		acquire();
	}
	npid = 0;
	for(f = g->head; f != nil; f = f->grpnext)
		if(f->group != g)
			panic("killgrp");
		else
			npid++;
	/* use pids not Prog* because state can change during killprog (eg, in delprog) */
	pids = malloc(npid*sizeof(int));
	if(pids == nil)
		error(Enomem);
	npid = 0;
	for(f = g->head; f != nil; f = f->grpnext)
		pids[npid++] = f->pid;
	g->flags |= Pkilled;
	if(waserror()) {
		g->flags &= ~Pkilled;
		free(pids);
		nexterror();
	}
	for(i = 0; i < npid; i++) {
		f = progpid(pids[i]);
		if(f != nil && f != currun())
			killprog(f, msg);
	}
	poperror();
	g->flags &= ~Pkilled;
	free(pids);
	return 1;
}

char	changup[] = "channel hangup";

void
killcomm(Progq **q)
{
	Prog *p;
	Progq *f;

	for (f = *q; f != nil; f = *q) {
		*q = f->next;
		p = f->prog;
		free(f);
		if(p == nil)
			return;
		p->ptr = nil;
		switch(p->state) {
		case Prelease:
			swiprog(p);
			break;
		case Psend:
		case Precv:
			p->kill = changup;
			addrun(p);
			break;
		case Palt:
			altgone(p);
			break;
		}
	}
}

void
addprog(Proc *p)
{
	Prog *n;

	if((n = p->prog) == nil) {
		n = malloc(sizeof(Prog));
		if(n == nil)
			panic("no memory");
		p->prog = n;
	} else
		memset(n, 0, sizeof(Prog));
	n->osenv = p->env;
}

static void
cwakeme(Prog *p)
{
	Osenv *o;

	p->addrun = nil;
	o = p->osenv;
	wakeup(o->rend);
}

static int
cdone(void *vp)
{
	Prog *p = vp;

	return p->addrun == nil || p->kill != nil;
}

void
cblock(Prog *p)
{
	Osenv *o;

	p->addrun = cwakeme;
	o = p->osenv;
	o->rend = &up->sleep;
	release();

	/*
	 * To allow cdone(p) safely after release,
	 * p must be currun before the release.
	 * Exits in the error case with the vm acquired.
	 */
	if(waserror()) {
		acquire();
		p->addrun = nil;
		nexterror();
	}
	sleep(o->rend, cdone, p);
	if (p->kill != nil)
		error(Eintr);
	poperror();
	acquire();
}

void
addrun(Prog *p)
{
	if(p->addrun != 0) {
		p->addrun(p);
		return;
	}
	if(p->state == Pready && p != (Prog *)up->prog)
		panic("addrun of ready prog %8.8p by %8.8lux\n", p, getcallerpc(&p));
	p->state = Pready;
	p->link = nil;
	if(isched.runhd == nil)
		isched.runhd = p;
	else
		isched.runtl->link = p;

	isched.runtl = p;
}

Prog*
delrun(int state)
{
	Prog *p;

	p = isched.runhd;
	p->state = state;
	isched.runhd = p->link;
	if(p->link == nil)
		isched.runtl = nil;

	return p;
}

void
delrunq(Prog *p)
{
	Prog *prev, *f;

	prev = nil;
	for(f = isched.runhd; f; f = f->link) {
		if(f == p)
			break;
		prev = f;
	}
	if(f == nil)
		return;
	if(prev == nil)
		isched.runhd = p->link;
	else
		prev->link = p->link;
	if(p == isched.runtl)
		isched.runtl = prev;
}

Prog*
delruntail(int state)
{
	Prog *p;

	p = isched.runtl;
	delrunq(isched.runtl);
	p->state = state;
	return p;
}

Prog*
currun(void)
{
	return isched.runhd;
}

Prog*
schedmod(Module *m)
{
	Heap *h;
	Type *t;
	Prog *p;
	Modlink *ml;
	Frame f, *fp;

	ml = mklinkmod(m, 0);

	if(m->origmp != H && m->ntype > 0) {
		t = m->type[0];
		h = nheap(t->size);
		h->t = t;
		t->ref++;
		ml->MP = H2D(uchar*, h);
		newmp(ml->MP, m->origmp, t);
	}

	p = newprog(nil, ml);
	h = D2H(ml);
	h->ref--;
	p->R.PC = m->entry;
	fp = &f;
	R.s = &fp;
	f.t = m->entryt;
	newstack(p);
	initmem(m->entryt, p->R.FP);

	return p;
}

void
acquire(void)
{
	int empty;
	Prog *p;

	lock(&isched.l);
	if(isched.idle) {
		isched.idle = 0;
		unlock(&isched.l);
	}
	else {
		up->qnext = nil;
		if(isched.vmq != nil){
			empty = 0;
			isched.vmqt->qnext = up;
		}else{
			isched.vmq = up;
			empty = 1;
		}
		isched.vmqt = up;

		up->state = Queueing;
		up->pc = getcallerpc(&empty);
		unlock(&isched.l);
		if(empty)
			wakeup(&isched.irend);
		sched();
	}

	if(up->type == Interp) {
		p = up->iprog;
		up->iprog = nil;
		irestore(p);
	}
	else
		p = up->prog;

	p->state = Pready;
	p->link = isched.runhd;
	isched.runhd = p;
	if(p->link == nil)
		isched.runtl = p;
}

void
release(void)
{
	Proc *p, **pq;
	int f;

	if(up->type == Interp){
		if(up->iprog != nil)
			panic("Double release (Interp)?");
		up->iprog = isave();
	}else{
		if(((Prog *)up->prog)->state != Pready) panic("double release (GC)?");
		delrun(Prelease);
	}

	lock(&isched.l);
	if(*(pq = &isched.vmq) == nil && *(pq = &isched.idlevmq) == nil) {
		isched.idle = 1;
		f = isched.creating;
		isched.creating = 1;
		unlock(&isched.l);
		if(f == 0)
			kproc("dis", vmachine, nil, 0);
		return;
	}
	p = *pq;
	*pq = p->qnext;
	unlock(&isched.l);

	ready(p);
}

void
iyield(void)
{
	Proc *p;

	lock(&isched.l);
	p = isched.vmq;
	if(p == nil) {
		unlock(&isched.l);
		return;
	}
	isched.nyield++;
	isched.vmq = p->qnext;

	if(up->iprog != nil)
		panic("iyield but iprog, type %d", up->type);
	if(up->type != Interp){
		static int once;
		if(!once++)
			print("tell charles: #%p->type==%d\n", up, up->type);
	}
	up->qnext = isched.idlevmq;
	isched.idlevmq = up;

	up->state = Queueing;
	up->pc = getcallerpc(&p);
	unlock(&isched.l);
	ready(p);
	sched();
}

void
startup(void)
{
	int x;

	up->type = Interp;
	up->iprog = nil;

	lock(&isched.l);
	isched.creating = 0;
	if(isched.idle) {
		isched.idle = 0;
		unlock(&isched.l);
		return;
	}
	up->qnext = isched.idlevmq;
	isched.idlevmq = up;
	up->state = Queueing;
	up->pc = getcallerpc(&x);
	unlock(&isched.l);
	sched();
}

void
progexit(void)
{
	Prog *r;
	Module *m;
	int broken;
	char *estr, msg[ERRMAX+2*KNAMELEN];

	estr = up->env->errstr;
	broken = 0;
	if(estr[0] != '\0' && strcmp(estr, Eintr) != 0 && strncmp(estr, "fail:", 5) != 0)
		broken = 1;

	r = up->iprog;
	if(r != nil)
		acquire();
	else
		r = currun();

	if(*estr == '\0' && r->flags & Pkilled)
		estr = "killed";

	m = R.M->m;
	if(broken)
		print("[%s] Broken: \"%s\"\n", m->name, estr);

	snprint(msg, sizeof(msg), "%d \"%s\":%s", r->pid, m->name, estr);

	if(up->env->debug != nil) {
		dbgexit(r, broken, estr);
		broken = 1;
		/* must force it to break if in debug */
	}else if(broken && (!keepbroken || strncmp(estr, "out of memory", 13)==0 || memusehigh()))
		broken = 0;	/* don't want them or short of memory */

	if(broken){
		tellsomeone(r, msg);
		r = isave();
		r->state = Pbroken;
		return;
	}

	gclock();
	destroystack(&R);
	delprog(r, msg);
	gcunlock();
}

void
disfault(void *reg, char *msg)
{
	Prog *p;

	USED(reg);

	if(strncmp(msg, Eintr, 6) == 0 || up == nil) {
		print("EMU: faults: %s\n", msg);
		panic("disfault");
	}
	if(up->type != Interp) {
		print("SYS: process %s faults: %s\n", up->text, msg);
		panic("disfault");
	}

	if(up->iprog != nil)
		acquire();

	p = currun();
	if(p == nil)
		panic("Interp faults with no dis prog");

	/* cause an exception in the dis prog. */
	error(msg);
}

void
vmachine(void*)
{
	Prog *r;
	Osenv *o;
	int cycles;

	startup();

	while(waserror()) {
		if(up->type != Interp)
			panic("vmachine: non-interp kproc");
		if(up->iprog != nil)
			acquire();
		if(handler(up->env->errstr) == 0) {
			propex(currun(), up->env->errstr);
			progexit();
		}
		up->env = &up->defenv;
	}

	cycles = 0;
	for(;;) {
		if(tready(nil) == 0) {
			execatidle();
			sleep(&isched.irend, tready, 0);
		}

		if(isched.vmq != nil && (isched.runhd == nil || ++cycles > 2)){
			iyield();
			cycles = 0;
		}

		r = isched.runhd;
		if(r != nil) {
			o = r->osenv;
			up->env = o;

			FPrestore(&o->fpu);
			r->xec(r);
			FPsave(&o->fpu);

			if(isched.runhd != nil)
			if(r == isched.runhd)
			if(isched.runhd != isched.runtl) {
				isched.runhd = r->link;
				r->link = nil;
				isched.runtl->link = r;
				isched.runtl = r;
			}
			up->env = &up->defenv;
			if(isched.runhd != nil)
			if (up->iprog == nil) {
				up->type = BusyGC;
				pushrun(up->prog);
				rungc(isched.head);
				up->type = Interp;
				delrunq(up->prog);
			} else
				print("up->iprog not nil (%lux)\n", up->iprog);
		}
	}
}

void
disinit(void *a)
{
	Prog *p;
	Osenv *o;
	Module *root;
	char *initmod = a;

	if(waserror())
		panic("disinit error: %r");

	print("Initial Dis: \"%s\"\n", initmod);

	fmtinstall('D', Dconv);

	addclock0link(accountant, MS2HZ);

	FPinit();
	FPsave(&up->env->fpu);

	opinit();
	modinit();
	excinit();

	root = load(initmod);
	if(root == 0) {
		kgerrstr(up->genbuf, sizeof up->genbuf);
		panic("loading \"%s\": %s", initmod, up->genbuf);
	}

	p = schedmod(root);

	memmove(p->osenv, up->env, sizeof(Osenv));
	o = p->osenv;
	incref(o->pgrp);
	incref(o->fgrp);
	if(o->egrp != nil)
		incref(o->egrp);
	if(o->sigs != nil)
		incref(o->sigs);
	o->user = nil;
	kstrdup(&o->user, up->env->user);
	o->errstr = o->errbuf0;
	o->syserrstr = o->errbuf1;

	isched.idle = 1;

	if(kopen("#c/cons", OREAD) != 0)
		panic("failed to make fd0 from #c/cons");
	kopen("#c/cons", OWRITE);
	kopen("#c/cons", OWRITE);

	poperror();
	vmachine(nil);
}

void
pushrun(Prog *p)
{
	if(p->addrun != nil)
		panic("pushrun addrun");
	p->state = Pready;
	p->link = isched.runhd;
	isched.runhd = p;
	if(p->link == nil)
		isched.runtl = p;
}
