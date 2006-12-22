#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "../port/error.h"

typedef struct Psync Psync;

enum {
	Maxprocs=2,
};

struct Psync {
	Rendez	r;
	int	flag;
};
static Psync timesync[Maxprocs];
static Ref nactive;
static Ref nbusy;

static int
timev(void *a)
{
	return *(int*)a;
}

static void
timesched0(void *ap)
{
	long tot, t, i, lim, low, max;
	Psync *ps;

	ps = ap;
	sleep(&ps->r, timev, &ps->flag);
	setpri(PriRealtime);
	incref(&nbusy);
	while(nbusy.ref < nactive.ref)
		sched();
	lim = 1000;
	low = 64000000;
	max = 0;
	tot = 0;
	for(i=0; i<lim; i++){
if(i<8)print("%lud\n", up->pid);
		do{
			t = gettbl();
			sched();
			t = gettbl()-t;
		}while(t < 0);
		if(t < low)
			low = t;
		if(t > max)
			max = t;
		tot += t;
	}
	print("%lud %lud %lud %lud %lud\n", up->pid, lim, tot, low, max);
	decref(&nactive);
	pexit("", 0);
}

static void
timesched(void)
{
	int i, np;

	for(np=1; np<=Maxprocs; np++){
		nactive.ref = np;
		print("%d procs\n", np);
		setpri(PriRealtime);
		for(i=0; i<np; i++)
			kproc("timesched", timesched0, &timesync[i], 0);
		for(i=0; i<np; i++){
			timesync[i].flag = 1;
			wakeup(&timesync[i].r);
		}
		setpri(PriNormal);
		while(nactive.ref>0)
			sched();
	}
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
static Ictr counters[100], *curct;
static int intrwant;
static Rendez vous;
int	spltbl;	/* set by spllo */
int	intrtbl;	/* set by intrvec() */
int	isavetbl;	/* set by intrvec() */

static void
intrwake(Ureg*, void*)
{
	m->iomem->tgcr &= ~1;	/* reset the timer */
	curct->spllo = spltbl;
	curct->intr = intrtbl;
	curct->isave = isavetbl;
	curct->arrive = gettbl();
	intrwant = 0;
	wakeup(&vous);
	curct->wakeup = gettbl();
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
	m->iomem->tgcr |= 1;		/* enable timer: allow interrupt */
	curct->sleep = gettbl();
	return intrwant==0;
}

static void
intrtime(void)
{
	IMM *io;
	Ictr *ic;
	long t;
	int i;

	sched();
	curct = counters;
	io = ioplock();
	io->tgcr &= ~3;
	iopunlock();
	intrenable(VectorCPIC+0x19, intrwake, nil, BUSUNKNOWN, "bench");
	for(i=0; i<nelem(counters); i++){
		curct = &counters[i];
		//puttbl(0);
		intrwant = 1;
		io = m->iomem;	/* don't lock, to save time */
		io->tmr1 = (0<<8)|TimerORI|TimerSclk;
		io->trr1 = 1;
		curct->base = gettbl();
		sleep(&vous, intrtest, nil);
		curct->awake = gettbl();
		sched();	/* just to slow it down between trials */
	}
	m->iomem->tmr1 = 0;
	print("interrupt\n");
	for(i=0; i<20; i++){
		ic = &counters[i];
		t = ic->awake - ic->base;
		ic->awake -= ic->wakeup;
		ic->wakeup -= ic->arrive;
		ic->arrive -= ic->isave;
		ic->isave -= ic->intr;
		ic->intr -= ic->spllo;
		ic->spllo -= ic->sleep;
		ic->sleep -= ic->base;
		print("%ld\t%ld\t%ld\t%ld\t%ld\t%ld\t%ld\t%ld\n", ic->sleep, ic->spllo, ic->intr, ic->isave, ic->arrive, ic->wakeup, ic->awake, t);
	}
}

static Chan*
benchattach(char *spec)
{
	timesched();
	intrtime();
	USED(spec);
	error(Eperm);
	return nil;
}

static Walkqid*
benchwalk(Chan*, Chan*, char**, int)
{
	error(Enonexist);
	return 0;
}

static Chan*
benchopen(Chan*, int)
{
	error(Eperm);
	return nil;
}

static int
benchstat(Chan*, uchar*, int)
{
	error(Eperm);
	return 0;
}

static void
benchclose(Chan*)
{
}

static long	 
benchread(Chan *c, void *buf, long n, vlong offset)
{
	USED(c, buf, n, offset);
	error(Eperm);
	return 0;
}

static long	 
benchwrite(Chan *c, void *buf, long n, vlong offset)
{
	USED(c, buf, n, offset);
	error(Eperm);
	return 0;
}


Dev	benchdevtab = {
	'x',
	"bench",

	devreset,
	devinit,
	devshutdown,
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
