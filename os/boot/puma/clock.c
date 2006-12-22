#include "boot.h"

 /*
 * Control Word Read/Write Counter (mode 0)  LSB, MSB
 */
#define PIT_RW_COUNTER0  0x30
#define PIT_RW_COUNTER1  0x70
#define PIT_RW_COUNTER2  0xB0
#define PIT_COUNTERLATCH0	0x00
#define PIT_COUNTERLATCH1	0x40
#define PIT_COUNTERLATCH2	0x80

#define PIT_MODE_0	0	/* Interrupt on Terminal Count */
#define PIT_MODE_1	2	/* Hardware Retriggeable One-shot */
#define PIT_MODE_2	4	/* Rate Generator */
#define PIT_MODE_3	6	/* Square Wave Mode */
#define PIT_MODE_4	8	/* Software Triggered Mode */
#define PIT_MODE_5	10	/* Hardware Triggered Mode (Retriggeable) */

/*
 * Harris 82C54 Programmable Interval Timer
 * On the Puma board the PIT is memory mapped
 * starting at 0xf2000000 and with each of the 8-bit
 * registers addressed on a consecutive 4-byte boundary.
 */
#undef inb
#undef outb
#define 	inb(port)			((*(uchar *)(port))&0xff)
#define 	outb(port, data)	(*(uchar *)(port) = (data))
enum
{
	Cnt0=	0xf2000000,		/* counter locations */
	Cnt1=	0xf2000004,		/* ... */
	Cnt2=	0xf2000008,		/* ... */
	Ctlw=	0xf200000c,		/* control word register*/

	/* commands */
	Latch0=	0x00,		/* latch counter 0's value */
	Load0=	0x30,		/* load counter 0 with 2 bytes */
	Latch1=	0x40,		/* latch counter 1's value */
	Load1=	0x70,		/* load counter 1 with 2 bytes */

	/* modes */
	Square=	0x06,		/* periodic square wave */
	RateGen=	0x04,		/* rate generator */

	Freq=	3686400,	/* Real clock frequency */
};

static int cpufreq = 233000000;
static int aalcycles = 14;

static void
clockintr(Ureg*, void*)
{
	m->ticks++;
	checkalarms();
}

/*
 *  delay for l milliseconds more or less.  delayloop is set by
 *  clockinit() to match the actual CPU speed.
 */
void
delay(int l)
{
	l *= m->delayloop;
	if(l <= 0)
		l = 1;
	aamloop(l);
}

void
microdelay(int l)
{
	l *= m->delayloop;
	l /= 1000;
	if(l <= 0)
		l = 1;
	aamloop(l);
}

void
clockinit(void)
{
	int x, y;	/* change in counter */
	int loops, incr;

	/*
	 *  set vector for clock interrupts
	 */
	setvec(V_TIMER0, clockintr, 0);

	/*
	 *  set clock for 1/HZ seconds
	 */
	outb(Ctlw, Load0|Square);
	outb(Cnt0, (Freq/HZ));	/* low byte */
	outb(Cnt0, (Freq/HZ)>>8);	/* high byte */

	/* find biggest loop that doesn't wrap */
	incr = 16000000/(aalcycles*HZ*2);
	x = 2000;
	for(loops = incr; loops < 64*1024; loops += incr) {
		/*
		 *  measure time for the loop
		 *	TEXT aamloop(SB), $-4
		 *	_aamloop:
		 *		MOVW	R0, R0
		 *		MOVW	R0, R0
		 *		MOVW	R0, R0
		 *		SUB		$1, R0
		 *		CMP		$0, R0
		 *		BNE		_aamloop
		 *		RET
		 *
		 *  the time for the loop should be independent of external
		 *  cache and memory system since it fits in the execution
		 *  prefetch buffer.
		 *
		 */
		outb(Ctlw, Latch0);
		x = inb(Cnt0);
		x |= inb(Cnt0)<<8;
		aamloop(loops);
		outb(Ctlw, Latch0);
		y = inb(Cnt0);
		y |= inb(Cnt0)<<8;
		x -= y;
	
		if(x < 0)
			x += Freq/HZ;

		if(x > Freq/(3*HZ))
			break;
	}

	/*
	 *  counter  goes at twice the frequency, once per transition,
	 *  i.e., twice per square wave
	 */
	x >>= 1;

	/*
 	 *  figure out clock frequency and a loop multiplier for delay().
	 */
	cpufreq = loops*((aalcycles*Freq)/x);
	m->delayloop = (cpufreq/1000)/aalcycles;	/* AAMLOOPs for 1 ms */

	/*
	 *  add in possible .2% error and convert to MHz
	 */
	m->speed = (cpufreq + cpufreq/500)/1000000;
}
