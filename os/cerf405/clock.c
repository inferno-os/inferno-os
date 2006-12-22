#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"ureg.h"

#include	<isa.h>
#include	<interp.h>

typedef struct Clock0link Clock0link;
typedef struct Clock0link {
	void		(*clock)(void);
	Clock0link*	link;
} Clock0link;

static Clock0link *clock0link;
static Lock clock0lock;
ulong	clkrelinq;
void	(*kproftick)(ulong);	/* set by devkprof.c when active */
void	(*archclocktick)(void);	/* set by arch*.c when desired */

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

void
delay(int l)
{
	ulong i, j;

	j = m->delayloop;
	while(l-- > 0)
		for(i=0; i < j; i++)
			;
}

void
microdelay(int l)
{
	ulong i;

	l *= m->delayloop;
	l /= 1000;
	if(l <= 0)
		l = 1;
	for(i = 0; i < l; i++)
		;
}

enum {
	Timebase = 1,	/* system clock cycles per time base cycle */

	Wp17=	0<<30,	/* watchdog period (2^x clocks) */
	Wp21=	1<<30,
	Wp25=	2<<30,
	Wp29=	3<<30,
	Wrnone=	0<<28,	/* no watchdog reset */
	Wrcore=	1<<28,	/* core reset */
	Wrchip=	2<<28,	/* chip reset */
	Wrsys=	3<<28,	/* system reset */
	Wie=		1<<27,	/* watchdog interrupt enable */
	Pie=		1<<26,	/* enable PIT interrupt */
	Fit9=		0<<24,	/* fit period (2^x clocks) */
	Fit13=	1<<24,
	Fit17=	2<<24,
	Fit21=	3<<24,
	Fie=		1<<23,	/* fit interrupt enable */
	Are=		1<<22,	/* auto reload enable */

	/* dcr */
	Boot=	0x0F1,
	Epctl=	0x0F3,
	Pllmr0=	0x0F0,
	Pllmr1=	0x0F4,
	Ucr=		0x0F5,
};

void
clockinit(void)
{
	long x;

	m->delayloop = m->cpuhz/1000;	/* initial estimate */
	do {
		x = gettbl();
		delay(10);
		x = gettbl() - x;
	} while(x < 0);

	/*
	 *  fix count
	 */
	m->delayloop = ((vlong)m->delayloop*(10*(vlong)m->clockgen/1000))/(x*Timebase);
	if((int)m->delayloop <= 0)
		m->delayloop = 20000;

	x = (m->clockgen/Timebase)/HZ;
	putpit(x);
iprint("pit value=%.8lux [%lud]\n", x, x);
	puttsr(~0);
	puttcr(Pie|Are);
iprint("boot=%.8lux epctl=%.8lux pllmr0=%.8lux pllmr1=%.8lux ucr=%.8lux\n",
	getdcr(Boot), getdcr(Epctl), getdcr(Pllmr0), getdcr(Pllmr1), getdcr(Ucr));
}

void
clockintr(Ureg *ur)
{
	Clock0link *lp;

	/* PIT was set to reload automatically */
	puttsr(~0);
	m->ticks++;

	if(up)
		up->pc = ur->pc;

	if(archclocktick != nil)
		archclocktick();
	checkalarms();
	if(m->machno == 0) {
		if(kproftick != nil)
			(*kproftick)(ur->pc);
		lock(&clock0lock);
		for(lp = clock0link; lp; lp = lp->link)
			lp->clock();
		unlock(&clock0lock);
	}

	if(up && up->state == Running){
		if(cflag && up->type == Interp && tready(nil))
			ur->cr |= 1;	/* set flag in condition register for ../../interp/comp-power.c:/^schedcheck */
		if(anyready())
			sched();
	}
}

uvlong
fastticks(uvlong *hz)
{
	if(hz)
		*hz = HZ;
	return m->ticks;
}
