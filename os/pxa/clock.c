#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"

#include "ureg.h"

static ulong timer_incr[4] = { 0, 0, 0, -1 };

typedef struct Clock0link Clock0link;
typedef struct Clock0link {
	void		(*clock)(void);
	Clock0link*	link;
} Clock0link;

static Clock0link *clock0link;
static Lock clock0lock;
static void (*prof_fcn)(Ureg *, int);

Timer*
addclock0link(void (*clock)(void), int)
{
	Clock0link *lp;

	if((lp = malloc(sizeof(Clock0link))) == 0){
		print("addclock0link: too many links\n");
		return nil;
	}
	ilock(&clock0lock);
	lp->clock = clock;
	lp->link = clock0link;
	clock0link = lp;
	iunlock(&clock0lock);
	return nil;
}

static void
profintr(Ureg *ur, void*)
{
	OstmrReg *ost = OSTMRREG;
	int t;

	if((ost->osmr[3] - ost->oscr) < 2*CLOCKFREQ) {
		/* less than 2 seconds before reset, say something */
		setpanic();
		clockpoll();
		dumpregs(ur);
		panic("Watchdog timer will expire");
	}

	/* advance the profile clock tick */
	ost->osmr[2] += timer_incr[2];
	ost->ossr = (1 << 2); 			/* Clear the SR */
	t = 1;
	while((ost->osmr[2] - ost->oscr) > 0x80000000) {
		ost->osmr[2] += timer_incr[2];
		t++;
	}
	if(prof_fcn)
		prof_fcn(ur, t);
}

static void
clockintr(Ureg*, void*)
{
	Clock0link *lp;
	int losttick = 0;
	OstmrReg *ost = OSTMRREG;

{static int tag, led; if(++tag >= HZ){ledset(led ^= 1);tag=0;}}
	m->ticks++;
//	ost->osmr[3] = ost->oscr + timer_incr[3]; /* restart the watchdog */
	ost->osmr[0] += timer_incr[0];		/* advance the clock tick */
	ost->ossr = (1<<0); 			/* Clear the SR */

	while((ost->osmr[0] - ost->oscr) >= 0x80000000) {
		ost->osmr[0] += timer_incr[0]; 
		losttick++;
		m->ticks++;
	}

	checkalarms();

	if(canlock(&clock0lock)){
		for(lp = clock0link; lp; lp = lp->link)
			if(lp->clock)
				lp->clock();
		unlock(&clock0lock);
	}

	/* round robin time slice is done by trap.c and proc.c */
}

void
timerenable( int timer, int Hz, void (*f)(Ureg *, void*), void* a)
{
	OstmrReg *ost = OSTMRREG;
	char name[KNAMELEN];

	if(timer < 0 || timer > 3)
		return;
	timer_incr[timer] = CLOCKFREQ/Hz;		/* set up freq */
	ost->osmr[timer] = ost->oscr+timer_incr[timer];
	snprint(name, sizeof(name), "timer%d", timer);
	intrenable(IRQ, IRQtimer0+timer, f, a, name);
	ost->ossr = (1 << timer);	/* clear any pending interrupt */
	ost->oier |= (1 << timer);		/* enable interrupt */
}

void
timerdisable( int timer )
{
	OstmrReg *ost = OSTMRREG;

	if(timer < 0 || timer > 3)
		return;
	ost->osmr[timer] = 0;				/* clear freq */
	ost->oier &= ~(1 << timer);			/* disable interrupt */
}

void
installprof(void (*pf)(Ureg *, int))
{
	int s;

	s = splfhi();
	prof_fcn = pf;
	timerenable( 2, HZ+1, profintr, 0);
	timer_incr[2] = timer_incr[0]+63;	/* fine tuning */
	splx(s);
}

void
clockinit(void)
{
	OstmrReg *ost = OSTMRREG;
	m->ticks = 0;
	/* Set up timer registers */
	ost->ossr = 0xf;	/* clear all four OSSR trigger bits */
	ost->oier = 0;
	ost->osmr[0] = 0;
	ost->osmr[1] = 0;
	ost->osmr[2] = 0;
	//	ost->osmr[3] = 0;
	timerenable( 0, HZ, clockintr, 0);
//	timer_incr[3] = CLOCKFREQ*10;	/* 10 second watchdog */
//	timer_setwatchdog(timer_incr[3]);
//	timerenable( 2, 1, profintr, 0);	/* watch the watchdog */
}

void
clockpoll(void)
{
	OstmrReg *ost = OSTMRREG;
//	ost->osmr[3] = ost->oscr + timer_incr[3];	/* restart the watchdog */
}

void
clockcheck(void)
{
	OstmrReg *ost = OSTMRREG;

	if((ost->osmr[3] - ost->oscr) < CLOCKFREQ) {
		setpanic();
		clockpoll();
		dumpstack();
		panic("Watchdog timer will expire");
	}
}

// macros for fixed-point math

ulong _mularsv(ulong m0, ulong m1, ulong a, ulong s);

/* truncated: */
#define FXDPTDIV(a,b,n) ((ulong)(((uvlong)(a) << (n)) / (b)))
#define MAXMUL(a,n)     ((ulong)((((uvlong)1<<(n))-1)/(a)))
#define MULDIV(x,a,b,n) (((x)*FXDPTDIV(a,b,n)) >> (n)) 
#define MULDIV64(x,a,b,n) ((ulong)_mularsv(x, FXDPTDIV(a,b,n), 0, (n)))

/* rounded: */
#define FXDPTDIVR(a,b,n) ((ulong)((((uvlong)(a) << (n))+((b)/2)) / (b)))
#define MAXMULR(a,n)     ((ulong)((((uvlong)1<<(n))-1)/(a)))
#define MULDIVR(x,a,b,n) (((x)*FXDPTDIVR(a,b,n)+(1<<((n)-1))) >> (n)) 
#define MULDIVR64(x,a,b,n) ((ulong)_mularsv(x, FXDPTDIVR(a,b,n), 1<<((n)-1), (n)))


// these routines are all limited to a maximum of 1165 seconds,
// due to the wrap-around of the OSTIMER

ulong
timer_start(void)
{
	return OSTMRREG->oscr;
}

ulong
timer_ticks(ulong t0)
{
	return OSTMRREG->oscr - t0;
}

int
timer_devwait(ulong *adr, ulong mask, ulong val, int ost)
{
	int i;
	ulong t0 = timer_start();
	while((*adr & mask) != val) 
		if(timer_ticks(t0) > ost)
			return ((*adr & mask) == val) ? 0 : -1;
		else
			for(i = 0; i < 10; i++);	/* don't pound OSCR too hard! (why not?) */
	return 0;
}

void
timer_setwatchdog(int t)
{
	OstmrReg *ost = OSTMRREG;
	ost->osmr[3] = ost->oscr + t;
	if(t) {
		ost->ossr = (1<<3);
		ost->oier |= (1<<3);
		ost->ower = 1;
	} else 
		ost->oier &= ~(1<<3);
}

void
timer_delay(int t)
{	
	ulong t0 = timer_start();
	while(timer_ticks(t0) < t)
		;
}


ulong
us2tmr(int us)
{
	return MULDIV64(us, CLOCKFREQ, 1000000, 24);
}

int
tmr2us(ulong t)
{
	return MULDIV64(t, 1000000, CLOCKFREQ, 24);
}

void
microdelay(int us)
{
	ulong t0 = timer_start();
	ulong t = us2tmr(us);
	while(timer_ticks(t0) <= t)
		;
}

ulong
ms2tmr(int ms)
{
	return MULDIV64(ms, CLOCKFREQ, 1000, 20);
}

int
tmr2ms(ulong t)
{
	return MULDIV64(t, 1000, CLOCKFREQ, 32);
}

void
delay(int ms)
{
	ulong t0 = timer_start();
	ulong t = ms2tmr(ms);
	while(timer_ticks(t0) <= t)
		clockpoll();
}

/*
 * for devbench.c
 */
vlong
archrdtsc(void)
{
	return OSTMRREG->oscr;
}

ulong
archrdtsc32(void)
{
	return OSTMRREG->oscr;
}

/*
 * for devkprof.c
 */
long
archkprofmicrosecondspertick(void)
{
	return MS2HZ*1000;
}

void
archkprofenable(int)
{
	/* TO DO */
}

uvlong
fastticks(uvlong *hz)
{
	if(hz)
		*hz = HZ;
	return m->ticks;
}
