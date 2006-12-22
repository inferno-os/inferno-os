#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"

#include	"ureg.h"

typedef struct Clock0link Clock0link;
typedef struct Clock0link {
	void		(*clock)(void);
	Clock0link*	link;
} Clock0link;

static Clock0link *clock0link;
static Lock clock0lock;

void
microdelay(int ms)
{
	int i;

	ms *= 13334;		/* experimentally indetermined */
	for(i=0; i<ms; i++)
		;
}

typedef struct Ctr Ctr;
struct Ctr
{
	ulong	lim;
	ulong	ctr;
	ulong	limnr;	/* non-resetting */
	ulong	ctl;
};
Ctr	*ctr;

void
clockinit(void)
{
	KMap *k;

	putphys(TIMECONFIG, 0);	/* it's a processor counter */
	k = kmappa(CLOCK, PTENOCACHE|PTEIO);
	ctr = (Ctr*)VA(k);
	ctr->lim = (CLOCKFREQ/HZ)<<10;
}

void
clock(Ureg *ur)
{
	Clock0link *lp;
	ulong i;

	USED(ur);

	i = ctr->lim;	/* clear interrupt */
	USED(i);
	 /* is this needed? page 6-43 801-3137-10 suggests so */
	ctr->lim = (CLOCKFREQ/HZ)<<10;

	m->ticks++;

	if(up)
		up->pc = ur->pc;

	checkalarms();

	lock(&clock0lock);
	for(lp = clock0link; lp; lp = lp->link)
		lp->clock();
	unlock(&clock0lock);

	if(up && up->state == Running) {
		if(anyready())
			sched();
	}
}

Timer*
addclock0link(void (*clockfunc)(void), int)
{
	Clock0link *lp;

	if((lp = malloc(sizeof(Clock0link))) == 0){
		print("addclock0link: too many links\n");
		return nil;
	}
	ilock(&clock0lock);
	lp->clock = clockfunc;
	lp->link = clock0link;
	clock0link = lp;
	iunlock(&clock0lock);
	return nil;
}

uvlong
fastticks(uvlong *hz)
{
	if(hz)
		*hz = HZ;
	return m->ticks;
}
