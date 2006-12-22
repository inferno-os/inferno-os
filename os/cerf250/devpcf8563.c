/*
 *	Philips PCF8563 real-time clock on I⁲C (and compatibles)
 *
 *	currently this can't coexist with ../pxa/devrtc.c
 */

#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

#include	"io.h"

typedef struct Rtc	Rtc;
typedef struct Rtcreg	Rtcreg;

struct Rtc
{
	int	sec;
	int	min;
	int	hour;
	int	wday;
	int	mday;
	int	mon;
	int	year;
};

struct Rtcreg
{
	uchar	csr1;
	uchar	csr2;
	uchar	sec;	/* 00-59 and VL */
	uchar	min;		/* 00-59 */
	uchar	hour;	/* 00-23 */
	uchar	mday;	/* 01-31 */
	uchar	wday;	/* 0=Sun */
	uchar	mon;	/* 1-12 and 1900 bit */
	uchar	year;
	uchar	amin;	/* minute alarm */
	uchar	ahour;
	uchar	aday;
	uchar	awday;
};

enum{
	Qdir = 0,
	Qrtc,

	Rtclen=	0x0C+1,		/* bytes read and written to timekeeper */
	VL=	0x80,	/* reliable clock data no longer guaranteed */
};

static QLock	rtclock;		/* mutex on nvram operations */
static I2Cdev	rtdev;

static Dirtab rtcdir[]={
	".",		{Qdir, 0, QTDIR},	0,	DMDIR|0555,
	"rtc",		{Qrtc, 0},	0,	0664,
};

static ulong	rtc2sec(Rtc*);
static void	sec2rtc(ulong, Rtc*);
static void	setrtc(Rtc*);

static void
rtcreset(void)
{
	rtdev.addr = 0x51;
	rtdev.salen = 1;
	i2csetup(1);
}

static Chan*
rtcattach(char *spec)
{
	return devattach('r', spec);
}

static Walkqid*
rtcwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, rtcdir, nelem(rtcdir), devgen);
}

static int	 
rtcstat(Chan *c, uchar *dp, int n)
{
	return devstat(c, dp, n, rtcdir, nelem(rtcdir), devgen);
}

static Chan*
rtcopen(Chan *c, int omode)
{
	omode = openmode(omode);
	switch((ulong)c->qid.path){
	case Qrtc:
		if(strcmp(up->env->user, eve)!=0 && omode!=OREAD)
			error(Eperm);
		break;
	}
	return devopen(c, omode, rtcdir, nelem(rtcdir), devgen);
}

static void	 
rtcclose(Chan*)
{
}

static long	 
rtcread(Chan *c, void *buf, long n, vlong offset)
{
	ulong t, ot;

	if(c->qid.type & QTDIR)
		return devdirread(c, buf, n, rtcdir, nelem(rtcdir), devgen);

	switch((ulong)c->qid.path){
	case Qrtc:
		qlock(&rtclock);
		t = rtctime();
		do{
			ot = t;
			t = rtctime();	/* make sure there's no skew */
		}while(t != ot);
		qunlock(&rtclock);
		return readnum(offset, buf, n, t, 12);
	}
	error(Egreg);
	return -1;		/* never reached */
}

static long	 
rtcwrite(Chan *c, void *buf, long n, vlong off)
{
	Rtc rtc;
	ulong secs;
	char *cp, sbuf[32];
	ulong offset = off;

	switch((ulong)c->qid.path){
	case Qrtc:
		if(offset!=0 || n >= sizeof(sbuf)-1)
			error(Ebadarg);
		memmove(sbuf, buf, n);
		sbuf[n] = '\0';
		/*
		 *  read the time
		 */
		cp = sbuf;
		while(*cp){
			if(*cp>='0' && *cp<='9')
				break;
			cp++;
		}
		secs = strtoul(cp, 0, 0);
		/*
		 *  convert to bcd
		 */
		sec2rtc(secs, &rtc);
		/*
		 * write it
		 */
		setrtc(&rtc);
		return n;
	}
	error(Egreg);
	return -1;		/* never reached */
}

Dev pcf8563devtab = {
	'r',
	"pcf8563",

	rtcreset,
	devinit,
	devshutdown,
	rtcattach,
	rtcwalk,
	rtcstat,
	rtcopen,
	devcreate,
	rtcclose,
	rtcread,
	devbread,
	rtcwrite,
	devbwrite,
	devremove,
	devwstat,
};

static int
getbcd(int bcd)
{
	return (bcd&0x0f) + 10 * (bcd>>4);
}

static int
putbcd(int val)
{
	return (val % 10) | (((val/10) % 10) << 4);
}

long	 
rtctime(void)
{
	Rtc rtc;
	Rtcreg d;

	if(waserror()){
		iprint("rtc: err %s\n", up->env->errstr);
		return 0;
	}
	if(i2crecv(&rtdev, &d, Rtclen, 0) != Rtclen)
		return 0;
	poperror();
	rtc.sec = getbcd(d.sec & 0x7F);
	rtc.min = getbcd(d.min & 0x7F);
	rtc.hour = getbcd(d.hour & 0x3F);
	rtc.mday = getbcd(d.mday & 0x3F);
	rtc.mon = getbcd(d.mon & 0x1f);
	rtc.year = getbcd(d.year);
	if(rtc.mon < 1 || rtc.mon > 12)
		return 0;
	if(d.mon & (1<<7))
		rtc.year += 1900;
	else
		rtc.year += 2000;
	return rtc2sec(&rtc);
}

static void
setrtc(Rtc *rtc)
{
	Rtcreg d;

	memset(&d, 0, sizeof(d));
	d.year = putbcd(rtc->year % 100);
	d.mon = putbcd(rtc->mon);
	if(rtc->year <  2000)
		d.mon |= 1<<7;
	d.wday = rtc->wday+1;
	d.mday = putbcd(rtc->mday);
	d.hour = putbcd(rtc->hour);
	d.min = putbcd(rtc->min);
	d.sec = putbcd(rtc->sec);
	i2csend(&rtdev, &d, Rtclen, 0);
}

#define SEC2MIN 60L
#define SEC2HOUR (60L*SEC2MIN)
#define SEC2DAY (24L*SEC2HOUR)

/*
 *  days per month plus days/year
 */
static	int	dmsize[] =
{
	365, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
};
static	int	ldmsize[] =
{
	366, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
};

/*
 *  return the days/month for the given year
 */
static int *
yrsize(int y)
{

	if((y%4) == 0 && ((y%100) != 0 || (y%400) == 0))
		return ldmsize;
	else
		return dmsize;
}

/*
 *  compute seconds since Jan 1 1970
 */
static ulong
rtc2sec(Rtc *rtc)
{
	ulong secs;
	int i;
	int *d2m;

	secs = 0;

	/*
	 *  seconds per year
	 */
	for(i = 1970; i < rtc->year; i++){
		d2m = yrsize(i);
		secs += d2m[0] * SEC2DAY;
	}

	/*
	 *  seconds per month
	 */
	d2m = yrsize(rtc->year);
	for(i = 1; i < rtc->mon; i++)
		secs += d2m[i] * SEC2DAY;

	secs += (rtc->mday-1) * SEC2DAY;
	secs += rtc->hour * SEC2HOUR;
	secs += rtc->min * SEC2MIN;
	secs += rtc->sec;

	return secs;
}

/*
 *  compute rtc from seconds since Jan 1 1970
 */
static void
sec2rtc(ulong secs, Rtc *rtc)
{
	int d;
	long hms, day;
	int *d2m;

	/*
	 * break initial number into days
	 */
	hms = secs % SEC2DAY;
	day = secs / SEC2DAY;
	if(hms < 0) {
		hms += SEC2DAY;
		day -= 1;
	}

	/*
	 * day is the day number.
	 * generate day of the week.
	 * The addend is 4 mod 7 (1/1/1970 was Thursday)
	 */

	rtc->wday = (day + 7340036L) % 7;

	/*
	 * generate hours:minutes:seconds
	 */
	rtc->sec = hms % 60;
	d = hms / 60;
	rtc->min = d % 60;
	d /= 60;
	rtc->hour = d;

	/*
	 * year number
	 */
	if(day >= 0)
		for(d = 1970; day >= *yrsize(d); d++)
			day -= *yrsize(d);
	else
		for (d = 1970; day < 0; d--)
			day += *yrsize(d-1);
	rtc->year = d;

	/*
	 * generate month
	 */
	d2m = yrsize(rtc->year);
	for(d = 1; day >= d2m[d]; d++)
		day -= d2m[d];
	rtc->mday = day + 1;
	rtc->mon = d;
}
