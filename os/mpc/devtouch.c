#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "../port/error.h"

#define	DPRINT	if(0)print
#define	THREEBUT	0	/* !=0, enable 3-button emulation (see below) */

/*
 * DynaPro touch panel and Maxim MAX192 A/D converter on
 * York Electronics Centre's BRD/98/024 (Version A) interface,
 * accessed via mpc8xx SPI interface (see spi.c).
 *
 * The highest level of the driver is derived from the ARM/UCB touch panel driver,
 * simplified because of the differences between the panels.
 */

/*
 * Values determined by interface board
 */
enum {
	/* MAX192 control words */
	MeasureX =	(1<<7)|(0<<6)|(1<<3)|(1<<2)|3,	/* start, channel 0, unipolar, single-ended, external clock */
	MeasureY =	(1<<7)|(1<<6)|(1<<3)|(1<<2)|3,	/* start, channel 1, unipolar, single-ended, external clock */

	/* port B bits */
	ADselect = IBIT(16),	/* chip select to MAX192, active low */

	/* port C bits */
	Xenable =	1<<2,	/* PC13: TOUCH_XEN, active low */
	Yenable =	1<<3,	/* PC12: TOUCH_YEN, active low */
	Touched = 1<<10,	/* PC5: contact detect, active low */

	/* interrupt control via port C */
	TouchIRQ=	2,	/* parallel i/o - PC5 */
	TouchEnable=	1<<TouchIRQ,	/* mask for cimr */

	/* other parameters */
	Nconverge =	10,	/* maximum iterations for convergence */
	MaxDelta =	2,	/* acceptable change in X/Y between iterations */
};

/*
 * ADC interface via SPI (see MAX192 data sheet)
 *	select the ADC
 *	send 8-bit control word and two zero bytes to clock the conversion
 *	receive three data bytes
 *	deselect the ADC and return the result
 */
static int
getcoord(int cw)
{
	uchar tbuf[3], rbuf[3];
	IMM *io;
	int nr;

	tbuf[0] = cw;
	tbuf[1] = 0;
	tbuf[2] = 0;
	io = ioplock();
	io->pbdat &= ~ADselect;
	iopunlock();
	nr = spioutin(tbuf, sizeof(tbuf), rbuf);
	io = ioplock();
	io->pbdat |= ADselect;
	iopunlock();
	if(nr != 3)
		return -1;
	return ((rbuf[1]<<8)|rbuf[2])>>5;
}

/*
 * keep reading the a/d until the value stabilises
 */
static int
dejitter(int enable, int cw)
{
	int i, diff, prev, v;
	IMM *io;

	io = ioplock();
	io->pcdat &= ~enable;	/* active low */
	iopunlock();

	i = 0;
	v = getcoord(cw);
	do{
		prev = v;
		v = getcoord(cw);
		diff = v - prev;
		if(diff < 0)
			diff = -diff;
	}while(diff >= MaxDelta && ++i <= Nconverge);

	io = ioplock();
	io->pcdat |= enable;
	iopunlock();
	return v;
}

static void
adcreset(void)
{
	IMM *io;

	/* select port pins */
	io = ioplock();
	io->pcdir &= ~(Xenable|Yenable);	/* ensure set to input before changing state */
	io->pcpar &= ~(Xenable|Yenable);
	io->pcdat |= Xenable|Yenable;
	io->pcdir |= Xenable;	/* change enable bits to output one at a time to avoid both being low at once (could damage panel) */
	io->pcdat |= Xenable;	/* ensure it's high after making it an output */
	io->pcdir |= Yenable;
	io->pcdat |= Yenable;	/* ensure it's high after making it an output */
	io->pcso &= ~(Xenable|Yenable);
	io->pbdat |= ADselect;
	io->pbpar &= ~ADselect;
	io->pbdir |= ADselect;
	iopunlock();
}

/*
 * high-level touch panel interface
 */

/* to and from fixed point */
#define	FX(n)	((n)<<16)
#define	XF(v)		((v)>>16)

typedef struct Touch Touch;

struct Touch {
	Lock;
	Rendez	r;
	int	m[2][3];	/* transformation matrix */
	int	rate;
	int	down;
	int	raw_count;
	int	valid_count;
	int	wake_time;
	int	sleep_time;
};

static Touch touch = {
	{0},
	.r {0},
	.m {{FX(1), 0, 0},{0, FX(1), 0}},	/* default is 1:1 */
	.rate 20,	/* milliseconds */
};

/*
 * panel-touched state and interrupt
 */

static int
touching(void)
{
	eieio();
	return (m->iomem->pcdat & Touched) == 0;
}

static int
ispendown(void*)
{
	return touch.down || touching();
}

static void
touchintr(Ureg*, void*)
{
	if((m->iomem->pcdat & Touched) == 0){
		m->iomem->cimr &= ~TouchEnable;	/* mask interrupts when reading pen */
		touch.down = 1;
		wakeup(&touch.r);
	}
}

static void
touchenable(void)
{
	IMM *io;
 
	io = ioplock();
	io->cimr |= TouchEnable;
	iopunlock();
}

/*
 * touchctl commands:
 *	X a b c	- set X transformation
 *	Y d e f	- set Y transformation
 *	s<delay>		- set sample delay in millisec per sample
 *	r<delay>		- set read delay in microsec
 *	R<l2nr>			- set log2 of number of readings to average
 */

enum{
	Qdir,
	Qtouchctl,
	Qtouchstat,
	Qtouch,
};

Dirtab touchdir[]={
	".",	{Qdir, 0, QTDIR}, 0, 0555,
	"touchctl",	{Qtouchctl, 0}, 	0,	0666,
	"touchstat",	{Qtouchstat, 0}, 	0,	0444,
	"touch",	{Qtouch, 0},	0,	0444,
};

static int
ptmap(int *m, int x, int y)
{
	return XF(m[0]*x + m[1]*y + m[2]);
}

/*
 * read a point from the touch panel;
 * returns true iff the point is valid, otherwise x, y aren't changed
 */
static int
touchreadxy(int *fx, int *fy)
{
	int rx, ry;

	if(touching()){
		rx = dejitter(Xenable, MeasureX);
		ry = dejitter(Yenable, MeasureY);
		microdelay(40);
		if(rx >=0 && ry >= 0){
			if(0)
				print("touch %d %d\n", rx, ry);
			*fx = ptmap(touch.m[0], rx, ry);
			*fy = ptmap(touch.m[1], rx, ry);
			touch.raw_count++;
			return 1;
		}
	}
	return 0;
}

#define	timer_start()	0	/* could use TBL if necessary */
#define	tmr2us(n)	0

static void
touchproc(void*)
{
	int b, i, x, y;
	ulong t1, t2;

	t1 = timer_start();
	b = 1;
	for(;;) {
		//setpri(PriHi);
		do{
			touch.down = 0;
			touch.wake_time += (t2 = timer_start())-t1;
			touchenable();
			sleep(&touch.r, ispendown, nil);
			touch.sleep_time += (t1 = timer_start())-t2;
		}while(!touchreadxy(&x, &y));

		/* 640x480-specific 3-button emulation hack: */
		if(THREEBUT){
			if(y > 481) { 
				b = ((639-x) >> 7);
				continue;
			} else if(y < -2) {
				b = (x >> 7)+3;
				continue;
			}
		}

		DPRINT("#%d %d", x, y);
		mousetrack(b, x, y, 0);
		setpri(PriNormal);
		while(touching()) {
			for(i=0; i<3; i++)
				if(touchreadxy(&x, &y)) {
					DPRINT("*%d %d", x, y);
					mousetrack(b, x, y, 0);
					break;
				}
			touch.wake_time += (t2 = timer_start())-t1;
			tsleep(&touch.r, return0, nil, touch.rate);
			touch.sleep_time += (t1 = timer_start())-t2;
		}
		mousetrack(0, x, y, 0);
		b = 1;	/* go back to just button one for next press */
	}
}

static void
touchreset(void)
{
	IMM *io;

	spireset();
	adcreset();
	intrenable(VectorCPIC+TouchIRQ, touchintr, &touch, BUSUNKNOWN, "touch");

	/* set i/o pin to interrupt when panel touched */
	io = ioplock();
	io->pcdat &= ~Touched;
	io->pcpar &= ~Touched;
	io->pcdir &= ~Touched;
	io->pcso &= ~Touched;
	io->pcint |= Touched;	/* high-to-low trigger */
	io->cimr &= ~TouchEnable;	/* touchproc will enable when ready */
	iopunlock();
}

static void
touchinit(void)
{
	static int done;

	if(!done){
		done = 1;
		kproc( "touchscreen", touchproc, nil, 0);
	}
}

static Chan*
touchattach(char* spec)
{
	return devattach('T', spec);
}

static Walkqid*
touchwalk(Chan* c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, touchdir, nelem(touchdir), devgen);
}

static int
touchstat(Chan* c, uchar* dp, int n)
{
	return devstat(c, dp, n, touchdir, nelem(touchdir), devgen);
}

static Chan*
touchopen(Chan* c, int omode)
{
	omode = openmode(omode);
	switch((ulong)c->qid.path){
	case Qtouchctl:
	case Qtouchstat:
		if(!iseve())
			error(Eperm);
		break;
	}
	return devopen(c, omode, touchdir, nelem(touchdir), devgen);
}

static void	 
touchclose(Chan*)
{
}

static long	 
touchread(Chan* c, void* buf, long n, vlong offset)
{
	char *tmp;
	int x, y;

	if(c->qid.type & QTDIR)
		return devdirread(c, buf, n, touchdir, nelem(touchdir), devgen);

	tmp = malloc(READSTR);
	if(waserror()){
		free(tmp);
		nexterror();
	}
	switch((ulong)c->qid.path){
	case Qtouch:
		if(!touchreadxy(&x, &y))
			x = y = -1;
		snprint(tmp, READSTR, "%d %d", x, y);
		break;
	case Qtouchctl:
		snprint(tmp, READSTR, "s%d\nr%d\nR%d\nX %d %d %d\nY %d %d %d\n",
			touch.rate, 0, 1,
			touch.m[0][0], touch.m[0][1], touch.m[0][2],
			touch.m[1][0], touch.m[1][1], touch.m[1][2]);
		break;
	case Qtouchstat:
		snprint(tmp, READSTR, "%d %d\n%d %d\n",
			touch.raw_count, touch.valid_count, tmr2us(touch.sleep_time), tmr2us(touch.wake_time));
		touch.raw_count = 0;
		touch.valid_count = 0;
		touch.sleep_time = 0;
		touch.wake_time = 0;
		break;
	default:
		error(Ebadarg);
		return 0;
	}
	n = readstr(offset, buf, n, tmp);
	poperror();
	free(tmp);
	return n;
}

static void
dotouchwrite(Chan *c, char *buf)
{
	char *field[8];
	int nf, cmd, pn, m[3], n;

	nf = getfields(buf, field, nelem(field), 1, " \t\n");
	if(nf <= 0)
		return;
	switch((ulong)c->qid.path){
	case Qtouchctl:
		cmd = *(field[0])++;
		pn = *field[0] == 0;
		switch(cmd) {
		case 's':
			n = strtol(field[pn], 0, 0);
			if(n <= 0)
				error(Ebadarg);
			touch.rate = n;
			break;
		case 'r':
			/* touch read delay */
			break;
		case 'X':
		case 'Y':
			if(nf < pn+2)
				error(Ebadarg);
			m[0] = strtol(field[pn], 0, 0);
			m[1] = strtol(field[pn+1], 0, 0);
			m[2] = strtol(field[pn+2], 0, 0);
			memmove(touch.m[cmd=='Y'], m, sizeof(touch.m[0]));
			break;
		case 'c':
		case 'C':
		case 'v':
		case 't':
		case 'e':
			/* not used */
			/* break; */
		default:
			error(Ebadarg);
		}
		break;
	default:
		error(Ebadarg);
		return;
	}
}

static long	 
touchwrite(Chan* c, void* vp, long n, vlong)
{
	char buf[64];
	char *cp, *a;
	int n0 = n;
	int bn;

	a = vp;
	while(n) {
		bn = (cp = memchr(a, '\n', n))!=nil ? cp-a+1 : n;
		n -= bn;
		bn = bn > sizeof(buf)-1 ? sizeof(buf)-1 : bn;
		memmove(buf, a, bn);
		buf[bn] = '\0';
		a = cp;
		dotouchwrite(c, buf);
	}
	return n0-n;
}

Dev touchdevtab = {
	'T',
	"touch",

	touchreset,
	touchinit,
	devshutdown,
	touchattach,
	touchwalk,
	touchstat,
	touchopen,
	devcreate,
	touchclose,
	touchread,
	devbread,
	touchwrite,
	devbwrite,
	devremove,
	devwstat,
};
