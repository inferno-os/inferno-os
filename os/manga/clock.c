#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"

#include "ureg.h"

enum {
	Mclk=	25000000
};

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
profintr(Ureg *, void*)
{
	/* TO DO: watchdog, profile on Timer 0 */
}

static void
clockintr(Ureg*, void*)
{
	Clock0link *lp;
	static int blip, led;

	if(++blip >= HZ){
		blip = 0;
		ledset(led ^= 1);
	}
	m->ticks++;

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
installprof(void (*pf)(Ureg *, int))
{
	USED(pf);
}

void
clockinit(void)
{
	TimerReg *tr;
	IntrReg *ir;
	ulong l, u;

	m->ticks = 0;
	tr = TIMERREG;
	tr->enable = 0;
	tr->pulse1 = 1;

	/* first tune the delay loop parameter (using a search because the counter doesn't decrement) */
	ir = INTRREG;
	tr->count1 = Mclk/1000 - tr->pulse1;	/* millisecond */
	u = m->cpuhz/(2*1000);	/* over-large estimate for a millisecond */
	l = 10000;
	while(l+1 < u){
		m->delayloop = l + (u-l)/2;
		ir->st = 1<<IRQtm1;	/* reset edge */
		tr->enable = 1<<1;
		delay(1);
		tr->enable = 0;
		if(ir->st & (1<<IRQtm1))
			u = m->delayloop;
		else
			l = m->delayloop;
	}

	intrenable(IRQ, IRQtm1, clockintr, nil, "timer.1");
	tr->count1 = Mclk/HZ - tr->pulse1;
	tr->enable = 1<<1;	/* enable only Timer 1 */
}

void
clockpoll(void)
{
}

void
clockcheck(void)
{
}

uvlong
fastticks(uvlong *hz)
{
	if(hz)
		*hz = HZ;
	return m->ticks;
}

void
microdelay(int l)
{
	int i;

	l *= m->delayloop;
	l /= 1000;
	if(l <= 0)
		l = 1;
	for(i = 0; i < l; i++)
		;
}

void
delay(int l)
{
	ulong i, j;

	j = m->delayloop;
	while(l-- > 0)
		for(i=0; i < j; i++)
			;
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
