#include	"u.h"
#include	"lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"ureg.h"

enum {
	Timebase = 4,	/* system clock cycles per time base cycle */
};

void	(*archclocktick)(void);	/* set by arch*.c when desired */

static	ulong	clkreload;

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

void
clockintr(Ureg*, void*)
{
	putdec(clkreload);
	m->ticks++;
	checkalarms();
	if(archclocktick != nil)
		archclocktick();
}

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
	m->delayloop = ((vlong)m->delayloop*(10*m->clockgen/1000))/(x*Timebase);
	if(m->delayloop == 0)
		m->delayloop = 1;
	clkreload = (m->clockgen/Timebase)/HZ-1;
	putdec(clkreload);
}
