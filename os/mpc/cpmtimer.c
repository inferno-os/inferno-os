#include "u.h"
#include "lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"

enum {
	Ntimer = 4	/* maximum allowed by hardware */
};

static struct {
	Lock;
	int	init;
	int	ntimer;	/* actual timers on this chip revision */
	GTimer	t[Ntimer];
} cpmtimers;

static	uchar	timerirq[] = {0x19, 0x12, 0x0C, 0x07};

static	void	gtimerinit(int, ushort*, ushort*);

static void
gtimerreset(void)
{
	IMM *io;
	int i;

	ilock(&cpmtimers);
	if(!cpmtimers.init){
		if(m->cputype == 0x50 && (getimmr() & 0xFFFF) <= 0x2001)
			cpmtimers.ntimer = 2;
		else
			cpmtimers.ntimer = Ntimer;
		io = m->iomem;
		io->tgcr = 0x2222;	/* reset timers, low-power stop */
		for(i=0; i<cpmtimers.ntimer; i++)
			gtimerinit(i, &io->tmr1+i, &io->ter1+i);
		cpmtimers.init = 1;
	}
	iunlock(&cpmtimers);
}

static void
gtimerintr(Ureg *ur, void *arg)
{
	GTimer *t;

	t = arg;
	t->event = *t->ter;
	*t->ter = t->event;
	if(t->inuse && t->interrupt != nil)
		t->interrupt(ur, t->arg, t);
}

static void
gtimerinit(int i, ushort *tmr, ushort *ter)
{
	GTimer *t;
	char name[KNAMELEN];

	snprint(name, sizeof(name), "timer.%d", i);
	t = &cpmtimers.t[i];
	t->x = i*4;	/* field in tgcr */
	t->inuse = 0;
	t->interrupt = nil;
	t->tmr = tmr;
	t->trr = tmr+2;
	t->tcr = tmr+4;
	t->tcn = tmr+6;
	t->ter = ter;
	intrenable(VectorCPIC+timerirq[i], gtimerintr, t, BUSUNKNOWN, name);
}

GTimer*
gtimer(ushort mode, ushort ref, void (*intr)(Ureg*,void*,GTimer*), void *arg)
{
	GTimer *t;
	int i;

	t = cpmtimers.t;
	if(!cpmtimers.init)
		gtimerreset();
	ilock(&cpmtimers);
	for(i=0; ; i++){
		if(i >= cpmtimers.ntimer){
			iunlock(&cpmtimers);
			return nil;
		}
		if(t->inuse == 0)
			break;
		t++;
	}
	t->inuse = 1;
	t->interrupt = intr;
	t->arg = arg;
	m->iomem->tgcr &= ~(0xF<<t->x);	/* reset */
	*t->tmr = mode;
	*t->tcn = 0;
	*t->trr = ref;
	*t->ter = 0xFFFF;
	iunlock(&cpmtimers);
	return t;
}

void
gtimerset(GTimer *t, ushort mode, int usec)
{
	ulong ref, ps;
	int clk;

	if(usec <= 0)
		return;
	ref = usec*m->speed;
	clk = mode & (3<<1);
	if(ref >= 0x1000000 && clk == TimerSclk){
		mode = (mode & ~clk) | TimerSclk16;
		ref >>= 4;
	} else if(clk == TimerSclk16)
		ref >>= 4;
	ps = (ref+(1<<16))/(1<<16);	/* round up */
	ref /= ps;
	*t->tmr = ((ps-1)<<8) | (mode&0xFF);
	*t->trr = ref;
}

void
gtimerstart(GTimer *t)
{
	if(t){
		ilock(&cpmtimers);
		m->iomem->tgcr = (m->iomem->tgcr & ~(0xF<<t->x)) | (1<<t->x);	/* enable */
		iunlock(&cpmtimers);
	}
}

void
gtimerstop(GTimer *t)
{
	if(t){
		ilock(&cpmtimers);
		m->iomem->tgcr |= 2<<t->x;	/* stop */
		iunlock(&cpmtimers);
	}
}

void
gtimerfree(GTimer *t)
{
	if(t){
		ilock(&cpmtimers);
		t->inuse = 0;
		*t->tmr = 0;	/* disable interrupts */
		*t->ter = 0xFFFF;
		m->iomem->tgcr = (m->iomem->tgcr & ~(0xF<<t->x)) | (2<<t->x);	/* reset and stop */
		iunlock(&cpmtimers);
	}
}

#ifdef GTIMETEST
static void
gtintr(Ureg*, void*, GTimer*)
{
	m->bcsr[4] ^= DisableVideoLamp;	/* toggle an LED */
}

void
gtimetest(void)
{
	GTimer *g;

	g = gtimer(0, 0, gtintr, nil);
	gtimerset(g, TimerORI|TimerRestart|TimerSclk, 64000);
	gtimerstart(g);
	delay(1);
print("started timer: #%4.4ux #%4.4ux %8.8lux #%4.4ux #%4.4ux\n", *g->tmr, *g->trr, m->iomem->tgcr, *g->tcn, *g->ter);
print("ter=#%8.8lux tmr=#%8.8lux trr=#%8.8lux\n", g->ter, g->tmr, g->trr);
}
#endif
