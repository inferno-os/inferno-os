#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include <interp.h>
#include "io.h"
#include "../port/error.h"
#include <isa.h>
#include "kernel.h"

/* Builtin module support */
#include "bench.h"
#include "benchmod.h"

typedef enum { None, Calibrate, Base, Op, Intr, Dis, Gc, MS2T, xTest};
static struct {
	int		inuse;	/* reference count */
	int		test;
	void*	scratch;
	char*	buf;
	int		bufsz;
	char*	wpos;
	void		(*op)(void);
	vlong	tickstart;
} bench;

static void
log(char *msg, ...)
{
	va_list ap;

	va_start(ap, msg);
	bench.wpos = vseprint(bench.wpos, bench.buf+bench.bufsz, msg, ap);
	va_end(ap);
}

void
elog(char *msg, ...)
{
	va_list ap;

	if(bench.buf == 0)
		return;
	va_start(ap, msg);
	bench.wpos = vseprint(bench.wpos, bench.buf+bench.bufsz, msg, ap);
	va_end(ap);
}

static void
clear(void)
{
	bench.wpos = bench.buf;
}

static long
rep(void *to, long n, ulong offset)
{
	long left = bench.wpos - bench.buf - offset;
	if(left < 0)
		left = 0;
	if(n > left)
		n = left;
	memmove(to, bench.buf+offset, n);
	return n;
}

static long
notest(int report, void *va, long n, ulong offset)
{
	USED(report, va, n, offset);
	if(report)
		return rep(va, n, offset);
	return 0;
}

// Calibration
static long MS2TS = 0;	// time stamps per millisec
static long US2TS = 0;	// time stamps per microsecond

static long
cal(int report, void *va, long n, ulong offset)
{
	int tot, i, lim, low, max, pl, mdelay;
	ulong t;
	if(report)
		return rep(va, n, offset);
	clear();
	setpri(PriRealtime);
	lim = 1000;
	low = 64000000;
	max = 0;
	tot = 0;
	mdelay = 1000;
	for(i=0; i<lim; i++){
		do{
			pl = splhi();
			t = archrdtsc32();
			microdelay(mdelay);
			t = archrdtsc32() - t;
			splx(pl);
		} while(t < 0);
		if(t < low)
			low = t;
		if(t > max)
			max = t;
		tot += t;
	}
	MS2TS = tot/lim;
	US2TS = MS2TS/1000;
	if(va)
		log("mdelay=%lud lim=%lud tot=%lud low=%lud max=%lud\n", mdelay, lim, tot, low, max);
	setpri(PriNormal);
	return n;
}

/*
 * ticks to format string
 */
/*static*/ char *
ts2str(vlong ticks)
{
#define Nbuf 5
	static char b[Nbuf][40];
	static int n=Nbuf-1;
	char *fmt, *unit;
	double d;

	if(0){
		print("ticks=%lld MS2TS=%ld\n", ticks, MS2TS);
		d = (double)ticks;
		print("1:%f\n", d);
		d = (double)ticks*1000;
		//print("2:%f\n", d);
		d = ((double)ticks)/MS2TS;
		//print("3:%f\n", d);
	}
	n = (n+1)%Nbuf;
	if(ticks > MS2TS*1000) {
		fmt = "%.2f %s";
		unit = "s";
		d = ((double)ticks/MS2TS) * 1000.0;
	} else if(ticks > MS2TS) {
		fmt = "%.2f %s";
		unit = "ms";
		d = (double)ticks/MS2TS;
	} else if(ticks > MS2TS/1000) {
		fmt = "%.2f %s";
		unit = "us";
		d = ((double)ticks*1000)/MS2TS;
	} else {
		fmt = "%.2f %s";
		unit = "ns";
		d = ((double)ticks*1000*1000)/MS2TS;
	}
	sprint(b[n], fmt, d, unit);
	return b[n];
}

/*
 * ticks to microseconds
 */
static double
ts2us(vlong ticks)
{
	return ((double)ticks*1000)/MS2TS;
}

/*
 * microseconds timestamp
 */
static vlong
bus(int reset)
{
	vlong now;
	if(US2TS == 0)
		return 0;
	if(reset) {
		bench.tickstart = archrdtsc();
		return 0;
	}
	now = archrdtsc();
	return ((now-bench.tickstart))/US2TS;
}

// Base
static long
base(int report, void *va, long n, ulong offset)
{
	int tot, i, lim, low, max, pl;
	ulong t;
	char *bm;

	if(report)
		return rep(va, n, offset);
	clear();
	setpri(PriRealtime);
	lim = 1000;
	low = 64000000;
	max = 0;
	tot = 0;
	for(i=0; i<lim; i++){
		do {
			pl = splhi();
			t = archrdtsc32();
			// do nothing
			t = archrdtsc32() - t;
			splx(pl);
		} while(t < 0);
		if(t < low)
			low = t;
		if(t > max)
			max = t;
		tot += t;
	}
	bm = ts2str(tot/lim);
	log("%d %lud %lud %lud %lud (%s)\n", up->pid, lim, tot, low, max, bm);
	setpri(PriNormal);
	return n;
}

// Timeop

typedef struct Psync Psync;

enum {
	Maxprocs=3,
};

struct Psync {
	Rendez	r;
	int	flag;
	int	id;
	int	awaken;
};
static Psync timesync[Maxprocs];
static Ref nactive;
static Ref nbusy;
static RWlock sync;

static void
nilop(void)
{
}

static int
timev(void *a)
{
	return *(int*)a;
}

static void
timeop0(void *ap)
{
	int tot, i, lim, low, max;
	ulong t;
	Psync *ps;
	char *bm;

	ps = ap;
	setpri(PriRealtime);
	incref(&nactive);
	sleep(&ps->r, timev, &ps->flag);
	rlock(&sync);
	lim = 1000;
	low = 64000000;
	max = 0;
	tot = 0;
	for(i=0; i<lim; i++){
		do{
			t = archrdtsc32();
			(*bench.op)();
			t = archrdtsc32() - t;
		}while(t < 0);
		if(t < low)
			low = t;
		if(t > max)
			max = t;
		tot += t;
	}
	bm = ts2str(tot/lim);
	log("%d %lud %lud %lud %lud (%s)\n", up->pid, lim, tot, low, max, bm);
	runlock(&sync);
	pexit("", 0);
}

static long
timeop(int report, void *va, long n, ulong offset)
{
	int i, np, pl;

	if(report)
		return rep(va, n, offset);
	clear();
	bench.op = 0;
	if(strncmp(va, "nil", 3) == 0)
		bench.op = nilop;
	else if(strncmp(va, "sched", 5) == 0)
		bench.op = sched;
	else
		return 0;
	for(np=1; np<=Maxprocs; np++) {
		nactive.ref = 0;
		wlock(&sync);
		log("%d procs\n", np);
		setpri(PriRealtime);
		for(i=0; i<np; i++) {
			timesync[i].id = i;
			kproc("timeop", timeop0, &timesync[i], 0);
		}
		while(nactive.ref < np)
			tsleep(&up->sleep, return0, 0, 20);
		for(i=0; i<np; i++){
			timesync[i].flag = 1;
			wakeup(&timesync[i].r);
		}
		sched();
		pl = splhi();
		setpri(PriNormal);
		wunlock(&sync);
		// now they run
		wlock(&sync);		// wait for last reader
		wunlock(&sync);
		splx(pl);
	}
	return n;
}

typedef struct Ictr Ictr;
struct Ictr {
	ulong	base;
	ulong	sleep;
	ulong	spllo;
	ulong	intr;
	ulong	isave;
	ulong	arrive;
	ulong	wakeup;
	ulong	awake;
};
static Ictr counters[5/*100*/], *curct;
static int intrwant;
static Rendez vous;
int	spltbl;	/* set by spllo */
int	intrtbl;	/* set by intrvec() */
int	isavetbl;	/* set by intrvec() */

static int ienable;


static void
intrwake(void)
{
	if(ienable == 0)
		return;
	ienable = 0;
	if(spltbl == 0)		// not used here
		curct->spllo = curct->intr = curct->isave = archrdtsc32();
	else {
		curct->spllo = spltbl;
		curct->intr = intrtbl;
		curct->isave = isavetbl;
	}
	curct->arrive = archrdtsc32();
	intrwant = 0;
	wakeup(&vous);
	curct->wakeup = archrdtsc32();
}

/*
 * sleep calls intrtest with splhi (under lock):
 * provoke the interrupt now, so that it is guaranteed
 * not to happen until sleep has queued the process,
 * forcing wakeup to do something.
 */
static int
intrtest(void*)
{
	ienable = 1;		/* enable recording on interrupt */
	curct->sleep = archrdtsc32();
	return intrwant==0;
}

static long
intrtime(int report, void *va, long n, ulong offset)
{
	Ictr *ic;
	long t;
	int i;
	char *bm;
	if(report)
		return rep(va, n, offset);
	clear();

	setpri(PriRealtime);
	sched();
	curct = counters;
	ienable = 0;
	addclock0link(intrwake, MS2HZ);
	for(i=0; i<nelem(counters); i++){
		curct = &counters[i];
		intrwant = 1;
		curct->base = archrdtsc32();
		sleep(&vous, intrtest, nil);
		curct->awake = archrdtsc32();
		sched();	/* just to slow it down between trials */
	}
	log("interrupt\n");
	for(i=0; i<nelem(counters); i++){
		ic = &counters[i];
		t = ic->awake - ic->base;
		bm = ts2str(ic->awake - ic->arrive);
		ic->awake -= ic->wakeup;
		ic->wakeup -= ic->arrive;
		ic->arrive -= ic->isave;
		ic->isave -= ic->intr;
		ic->intr -= ic->spllo;
		ic->spllo -= ic->sleep;
		ic->sleep -= ic->base;
		log("%ld\t%ld\t%ld\t%ld\t%ld\t%ld\t%ld\t%ld (%s)\n", ic->sleep, ic->spllo, ic->intr, ic->isave, ic->arrive, ic->wakeup, ic->awake, t, bm);
	}
	setpri(PriNormal);
	return n;
}


/* DIS operation timing */

typedef struct  {
	vlong	n;		/* count */
	vlong	min;
	vlong 	max;
	vlong	sum;
	vlong	sumsq;	/* sum of squares */
} Stat;

static void
stat(enum { Reset, Inc } op, Stat *c, vlong val)
{
	switch(op) {
	case	Reset:
		c->n = 0;
		c->sum = 0;
		c->sumsq = 0;
		c->min = 0;
		c->max = 0;
		break;
	case Inc:
		c->n++;
		c->sum += val;
		c->sumsq += val*val;
		break;
	}
	if(val < c->min || c->n == 1)
		c->min = val;
	if(val > c->max || c->n == 1)
		c->max = val;
}

static void
statinc(Stat *d, Stat *s)
{
	d->n += s->n;
	d->sum += s->sum;
	d->sumsq += s->sumsq;
	if(s->min < d->min || d->n == s->n)
		d->min = s->min;
	if(s->max > d->max || d->n == s->n)
		d->max = s->max;
}

enum
{
	HSIZE	= 31,
	MAXCOUNT	= 100000000L,
};

typedef struct {
	int		op;
	int		pc;
	long		count;
	Stat	t;		/* combined dec and execution time */
} Istat;

typedef struct Mstat Mstat;
struct Mstat {
	char*	name;
	char*	path;
	int		ninst;
	Istat*	inst;
	Inst*		base;
	Mstat*	hash;
	Mstat*	link;
};

struct
{
	Mstat*	hash[HSIZE];
	Mstat*	list;
} vmstat;

extern struct			/* see ../../interp/tab.h:/keywds/ */
{
	char*	name;
	int	op;
	int	terminal;
}keywds[];

static char *
opname(int op)
{
	char *name;

	if(op < 0 || op >= MAXDIS)
		return "Unknown";
	return keywds[op].name;
	if(name == 0)
		name = "<Noname>";
	return name;
}

static void
mreset(void)
{
	Mstat *mp, *link;

	for(mp=vmstat.list; mp; mp=link) {
		link = mp->link;
		free(mp->inst);
		free(mp);
	}
	vmstat.list = 0;
	memset(vmstat.hash, 0, HSIZE*sizeof(Mstat*));
}

static ulong
hash(void *s)
{
	ulong sum = 0;
	uchar *a = s;

	while(*a)
		sum = (sum << 1) + *a++;
	return sum%HSIZE;
}

static Mstat *
mlookup(Module *mod)
{
	Mstat *m;
	ulong h;

	for(m=vmstat.hash[hash(mod->name)]; m; m=m->hash)
		if(strcmp(m->name, mod->name) == 0
		&& strcmp(m->path, mod->path) == 0) {
			return m;
		}


	m = malloc(sizeof(Mstat));
	if(m == 0)
		return 0;
	kstrdup(&m->name, mod->name);
	kstrdup(&m->path, mod->path);
	m->ninst = mod->nprog;
	m->inst = malloc(m->ninst*sizeof(Istat));
	if(m->path == 0 || m->inst == 0)
		return 0;
	m->base = mod->prog;
	m->link = vmstat.list;
	vmstat.list = m;
	h = hash(m->name);
	m->hash = vmstat.hash[h];
	vmstat.hash[h] = m;
	return m;
}

/* interpreted code Dis timing */
void
bxec(Prog *p)
{
	int op, pc;
	vlong t0, t;
	Mstat*	ms;
	Istat*	is;
	Module *om;

	R = p->R;
	R.MP = R.M->MP;
	R.IC = p->quanta;

	if(p->kill != nil) {
		char *m;
		m = p->kill;
		p->kill = nil;
		error(m);
	}

	if(R.M->compiled)
		comvec();
	else {
		om = 0;
		ms = mlookup(R.M->m);
		do {
			op = R.PC->op;
			pc = R.PC-R.M->prog;
			if(om != R.M->m) {
				om = R.M->m;
				ms = mlookup(R.M->m);
			}

			t0 = archrdtsc();
			dec[R.PC->add]();
			R.PC++;
			optab[op]();
			t = archrdtsc();
			if(ms) {
				is = &ms->inst[pc];
				if(is->count < MAXCOUNT) {
					if(is->count++ == 0) {
						is->op = op;
						is->pc = pc;
					}
					stat(Inc, &is->t, t-t0);
				}
			}
			if(op==ISPAWN || op==IMSPAWN) {
				Prog *new = delruntail(Pdebug);
				new->xec = bxec;
				addrun(new);
			}
		} while(--R.IC != 0);
	}

	p->R = R;
}

/* compiled code Dis timing */

static struct {			/* compiled code timing */
	int		set;
	int 		op, pc;		/* Dis opcode and program counter */
	vlong	t0, t;			/* time-in and time-out */
	vlong	base;		/* cost of doing the timing */
	Mstat	*ms;
	Module	*om;
	int		timing;		/* between "dis timer start" and stop */
} C;

enum { Nop = 0 };	/* opcode value for Dis NOP instruction */
void
dopostcomp(vlong t)
{
	Istat*	is;

	C.t = t;
	C.set = 0;
	if(C.ms != 0) {
		is = &C.ms->inst[C.pc];
		if(C.op == Nop) {			/* NOP  calibration */
			vlong newbase = C.t - C.t0;
			if(C.base == 0 || newbase < C.base)
				C.base = newbase;
		}
		if(is->count < MAXCOUNT) {
			if(is->count++ == 0) {
				is->op = C.op;
				is->pc = C.pc;
			}
			stat(Inc, &is->t, C.t-C.t0/*-C.base*/);
		}
	}
}

void
postcomp(void)
{
	vlong t;

	t = archrdtsc();
	if(C.timing == 0 || C.set == 0)
		return;
	dopostcomp(t);
}

void
precomp(void)
{
	vlong t;

	t = archrdtsc();
	if(C.timing == 0)
		return;
	if(C.set)
		dopostcomp(t);
	C.pc = *(ulong *)R.m;
	C.op = *(ulong *)R.s;
	if(C.om != R.M->m) {
		C.om = R.M->m;
		C.ms = mlookup(R.M->m);
	}
	C.set = 1;
	C.t0 = archrdtsc();
}

/* standard deviation */
static vlong
sdev(Stat *s)
{
	extern double sqrt(double);
	vlong var;
	var = s->sum;
	var *= var/s->n;
	var = (s->sumsq - var)/s->n;
	return (vlong)sqrt(var);
}

/*
 * Use the sequence:
 * 1. "timer startclr" or "timer start", then,
 * 2. Any DIS operations, and,
 * 3. "timer stop", to stop timing.
 * 4. Read the results from the data file after:
 *	a) "timer report" to get module/pc level results, or
 *	b) "timer summary" to get opcode level results
 */
static long
distime(int report, void *va, long n, ulong offset)
{
	Prog *p;
	Mstat *mp;
	Istat *ip, *ep;

	if(report)
		return rep(va, n, offset);
	clear();
	acquire();
	p = currun();
	if(strncmp(va, "timer startclr", 14) == 0) {
		mreset();
		memset(&C, 0, sizeof(C));
		C.timing = 1;
		p->xec = bxec;
	} else if(strncmp(va, "timer start", 11) == 0) {
		p->xec = bxec;
		C.timing = 1;
	} else if(strncmp(va, "timer stop", 10) == 0) {
		p->xec = xec;				/* bug: stop all xec threads */
		C.timing = 0;
	} else if(strncmp(va, "timer nilop", 11) == 0) {
	} else if(strncmp(va, "timer report", 12) == 0)	/* by address */
		for(mp=vmstat.list; mp; mp=mp->link) {
			ep = mp->inst + mp->ninst;
			for(ip=mp->inst; ip<ep; ip++)
				if(ip->count > 0) {
					char *mean = ts2str(ip->t.sum/ip->count);
					char *min = ts2str(ip->t.min);
					char *max = ts2str(ip->t.max);
					char *std = ts2str(sdev(&ip->t));
					log("%s %d %s %ld %s %s %s %s\n", mp->path, ip->pc, opname(ip->op), ip->count, mean, min, max, std);
				}
		}
	else if(strncmp(va, "timer summary", 13) == 0) {	/* by opcode */
		static Stat T[MAXDIS];
		int i;

		for(i=0; i<MAXDIS; i++)
			stat(Reset, &T[i], 0);
		for(mp=vmstat.list; mp; mp=mp->link) {
			ep = mp->inst + mp->ninst;
			for(ip=mp->inst; ip<ep; ip++)
				if(ip->count > 0)
					statinc(&T[ip->op], &ip->t);
		}
		for(i=0; i<MAXDIS; i++) {
			Stat *t = &T[i];
			char *mean = "0.00 ms";
			char *min = "0.00 ms";
			char *max = "0.00 ms";
			char *std = "0.00 ms";
			if(t->n > 0) {
				mean = ts2str(t->sum/t->n);
				min = ts2str(t->min);
				max = ts2str(t->max);
				std = ts2str(sdev(t));
			}
			log("%d %s %lld %s %s %s %s\n", i, opname(i), t->n, mean, min, max, std);
		}
	} else
		n = 0;
	R.IC = 1;
	release();

	return n;
}
 
/*
 * Garbage collection
 */
static int nidle;

int
idlegc(void *p)
{
	int done;
	Prog *head;
	vlong t0, t1, tot;
	USED(p);

	head = progn(0);	/* isched.head */
	done = gccolor + 3;
	tot = 0;
	while(gccolor < done && gcruns()) {
		if(tready(nil))
			break;
		t0 = archrdtsc();
		rungc(head);
		t1 = archrdtsc();
		t1 -= t0;
		tot += t1;
//		log(" %.2f",  ts2us(t1));
	}
	log(" %.2f",  ts2us(tot));
	nidle--;
	if(nidle == 0) {
		log("\n");
		return 1;
	}
	return 0;
}

static long
gctime(int report, void *va, long n, ulong offset)
{
	int i;
	vlong t0, t1;
	Prog *head;

	if(report)
		return rep(va, n, offset);
	clear();
	acquire();
	head = progn(0);	/* isched.head */
/*
	if(strncmp(va, "idle", 4) == 0) {
		nidle = 100;
		log("GCIDLE:1l:Observation:n:Time:us");
		atidle(idlegc, 0);
	} else if(strncmp(va, "stop", 4) == 0) {
		atidledont(idlegc, 0);
	} else 
*/
	if(strncmp(va, "sched", 5) == 0) {
		log("GCSCHED:1l:Observation:n:Time:us");
		for(i=0; i<1000; i++) {
			t0 = archrdtsc();
			rungc(head);
			t1 = archrdtsc();
			log(" %.2f",  ts2us(t1-t0));
			release();
			acquire();
		}
		log("\n");
	} else if(strncmp(va, "acquire", 7) == 0) {
		log("GCACQUIRE:1l:Observation:n:Time:us");
		for(i=0; i<1000; i++) {
			t0 = archrdtsc();
			release();
			acquire();
			head = progn(0);	/* isched.head */
			rungc(head);
			release();
			acquire();
			t1 = archrdtsc();
			log(" %.2f",  ts2us(t1-t0));
		}
		log("\n");
	}

	release();

	return n;
}


/* 
 * Request the number of time stamp ticks per millisecond
 */
static long
ms2ts(int report, void *va, long n, ulong offset)
{
	if(report)
		return rep(va, n, offset);
	log("%.ld\n", MS2TS);
	return n;
}

/*
 * test
 */

static long
test(int report, void *va, long n, ulong offset)
{
//	vlong v;
	double d;
	if(report)
		return rep(va, n, offset);
//	v = 5;
//	print("vlong %lld\n", v);
//	print("before cast\n");
//	d = (double)v;
//	print("after cast\n");
//	print("before assign\n");
	d=100.0;
	print("after assign\n");
	print("double %f\n", d);
//	log("%lld %f\n", v, d);
	return n;
}

/*
 * $Bench builtin support
 */
void
Bench_reset(void *)
{
	bus(1);
}

void
Bench_microsec(void *fp)
{
	F_Bench_microsec *f;

	f = fp;
	*f->ret = bus(0);
}

void
Bench_disablegc(void *)
{
	gclock();
}

void
Bench_enablegc(void *)
{
	gcunlock();
}


#define fdchk(x)	((x) == (Bench_FD*)H ? -1 : (x)->fd)
void
Bench_read(void *fp)
{
	int n;
	F_Bench_read *f;
	vlong usrelease, uskread, usacquire, ussched;

	f = fp;
	n = f->n;
	if(f->buf == (Array*)H) {
		*f->ret = 0;
		return;		
	}
	if(n > f->buf->len)
		n = f->buf->len;

	bus(1);
	release();
	usrelease = bus(0);
	*f->ret = kread(fdchk(f->fd), f->buf->data, n);
	uskread = bus(0);
	acquire();
	usacquire = bus(0);
	sched();
	ussched = bus(0);
	log("%lld %lld %lld %lud %lld\n", usrelease, uskread, usacquire, m->ticks, ussched);
}


/*
 * driver support
 */
long (*Test[])(int report, void *va, long n, ulong offset) = {
	[None]		notest,
	[Calibrate]	cal,
	[Base]		base,
	[Op]			timeop,
	[Intr]			intrtime,
	[Dis]			distime,
	[Gc]			gctime,
	[MS2T]		ms2ts,
	[xTest]		test,
};

enum {
	Benchdirqid,
	Benchdataqid,
	Benchctlqid,
	Benchusqid,
};
#define Data 0
static Dirtab benchtab[]={
	".",		{Benchdirqid,0,QTDIR},	0,	0555,
	"bdata",	{Benchdataqid},		0,	0444,
	"bctl",	{Benchctlqid},		0,	0660,
	"busec",	{Benchusqid},		0,	0660,
};

static void
benchreset(void)
{
	builtinmod("$Bench", Benchmodtab);
}

static Chan*
benchattach(char *spec)
{
	bench.inuse++;
	if(bench.inuse == 1) {
		bench.bufsz = 100*READSTR;
		bench.buf = xalloc(bench.bufsz);
		bench.wpos = bench.buf;
		if(bench.buf == 0)
			error(Enomem);
		bench.test = None;
		cal(0, 0, 0, 0);
	}	
	return devattach('x', spec);
}

void
benchshutdown(void)
{
	bench.inuse--;
	if(bench.inuse == 0)
		xfree(bench.buf);
}

static Walkqid*
benchwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, benchtab, nelem(benchtab), devgen);
}

static Chan*
benchopen(Chan *c, int omode)
{
	if(c->qid.path == Benchdirqid){
		if(omode != OREAD)
			error(Eperm);
	}
	c->mode = openmode(omode);
	c->flag |= COPEN;
	c->offset = 0;
	return c;
}

static int
benchstat(Chan *c, uchar *dp, int n)
{
	switch((ulong)c->qid.path){
	case Benchdataqid:
		benchtab[Data].length = bench.wpos - bench.buf;
	}
	return devstat(c, dp, n, benchtab, nelem(benchtab), devgen);
}

static void
benchclose(Chan*)
{
}

static long	 
benchread(Chan *c, void *buf, long n, vlong offset)
{
	vlong us;
	char tmp[64];

	switch((ulong)c->qid.path){
	case Benchdirqid:
		return devdirread(c, buf, n, benchtab, nelem(benchtab), devgen);

	case Benchdataqid:
		return Test[bench.test](1, buf, n, offset);

	case Benchusqid:
		us = archrdtsc();
		us /= US2TS;
		snprint(tmp, sizeof(tmp), "%.lld", us);
		return readstr(0, buf, n, tmp);
	default:
		n = 0;
		break;
	}
	return n;
}

static long	 
benchwrite(Chan *c, void *buf, long n, vlong offset)
{
	int argn = n;

	switch((ulong)c->qid.path){
	case Benchctlqid:
		bench.test = None;
		memset((char *)bench.buf, 0, bench.bufsz);
		bench.wpos = bench.buf;
		if(strncmp(buf, "test", 4) == 0)
			bench.test = xTest;
		else if(strncmp(buf, "calibrate", 9) == 0)
			bench.test = Calibrate;
		else if(strncmp(buf, "base", 4) == 0)
			bench.test = Base;
		else if(strncmp(buf, "intr", 4) == 0)
			bench.test = Intr;
		else if(strncmp(buf, "op ", 3) == 0) {
			bench.test = Op;
			buf = (char *)buf + 3;
			argn -= 3;
		} else if(strncmp(buf, "dis ", 4) == 0) {
			bench.test = Dis;
			buf = (char *)buf + 4;
			argn -= 4;
		} else if(strncmp(buf, "gc ", 3) == 0) {
			bench.test = Gc;
			buf = (char *)buf + 3;
			argn -= 3;
		} else if(strncmp(buf, "ms2ts", 5) == 0)
			bench.test = MS2T;
		else
			error(Ebadctl);
		Test[bench.test](0, buf, argn, offset);
		break;
	case Benchusqid:
		bench.tickstart = archrdtsc();
		break;
	default:
		error(Ebadusefd);
	}
	return n;
}

Dev	benchdevtab = {
	'x',
	"bench",

	benchreset,
	devinit,
	benchshutdown,
	benchattach,
	benchwalk,
	benchstat,
	benchopen,
	devcreate,
	benchclose,
	benchread,
	devbread,
	benchwrite,
	devbwrite,
	devremove,
	devwstat,

};
