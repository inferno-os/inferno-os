#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

#include	"io.h"

/*
 * Mostek MK48T12-15 Zeropower/Timekeeper
 * This driver is actually portable.
 */
typedef struct Rtc	Rtc;
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

static uchar	rtcgencksum(void);
static void	setrtc(Rtc *rtc);
static long	rtctime(void);
static int	*yrsize(int yr);
static int	*yrsize(int yr);
static ulong	rtc2sec(Rtc *rtc);
static void	sec2rtc(ulong secs, Rtc *rtc);

static struct
{
	uchar	*cksum;
	uchar	*ram;
	RTCdev	*rtc;
}nvr;

enum{
	Qdir,
	Qrtc,
	Qnvram,
};

QLock	rtclock;		/* mutex on clock operations */

static Dirtab rtcdir[]={
	".",		{Qdir, 0, QTDIR},	0,	0555,
	"rtc",		{Qrtc, 0},	0,		0666,
	"nvram",	{Qnvram, 0},	NVWRITE,	0666,
};
#define	NRTC	(sizeof(rtcdir)/sizeof(rtcdir[0]))

static void
rtcinit(void)
{
	KMap *k;

	k = kmappa(NVR_CKSUM_PHYS, PTENOCACHE|PTEIO);
	nvr.cksum = (uchar*)VA(k);

	k = kmappa(NVR_PHYS, PTENOCACHE|PTEIO);
	nvr.ram = (uchar*)VA(k);
	nvr.rtc = (RTCdev*)(VA(k)+RTCOFF);

	rtcgencksum();
}

static Chan*
rtcattach(char *spec)
{
	return devattach('r',spec);
}

static Walkqid*
rtcwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, rtcdir, NRTC, devgen);
}

static int
rtcstat(Chan *c, uchar *dp, int n)
{
	return devstat(c, dp, n, rtcdir, NRTC, devgen);
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
	case Qnvram:
		if(strcmp(up->env->user, eve)!=0)
			error(Eperm);
	}
	return devopen(c, omode, rtcdir, NRTC, devgen);
}

static void	 
rtccreate(Chan *c, char *name, int omode, ulong perm)
{
	USED(c, name, omode, perm);
	error(Eperm);
}

static void	 
rtcclose(Chan *c)
{
	USED(c);
}

static long	 
rtcread(Chan *c, void *buf, long n, vlong offset)
{
	ulong t, ot;

	if(c->qid.type & QTDIR)
		return devdirread(c, buf, n, rtcdir, NRTC, devgen);

	switch((ulong)c->qid.path){
	case Qrtc:
		qlock(&rtclock);
		t = rtctime();
		do{
			ot = t;
			t = rtctime();	/* make sure there's no skew */
		}while(t != ot);
		qunlock(&rtclock);
		n = readnum(offset, buf, n, t, 12);
		return n;
	case Qnvram:
		if(offset > NVREAD)
			return 0;
		if(n > NVREAD - offset)
			n = NVREAD - offset;
		qlock(&rtclock);
		memmove(buf, nvr.ram+offset, n);
		qunlock(&rtclock);
		return n;
	}
	error(Egreg);
	return 0;		/* not reached */
}

/*
 * XXX - Tad: fixme to generate the correct checksum
 */
static uchar
rtcgencksum(void)
{
	uchar cksum;
	int i;
	static uchar p1cksum = 0;
	static uchar p1cksumvalid=0;

	if(!p1cksumvalid) {
		for(i=1; i < 0x1000 ; i++)
			p1cksum ^= nvr.cksum[i];
		p1cksumvalid = 1;
	}

	cksum = p1cksum;

	for(i=0; i < 0xfdf ; i++) {
		cksum ^= nvr.ram[i];
	}

	return cksum;
}

static long	 
rtcwrite(Chan *c, void *buf, long n, vlong offset)
{
	Rtc rtc;
	ulong secs;
	char *cp, sbuf[32];

	switch((ulong)c->qid.path){
	case Qrtc:
		/*
		 *  read the time
		 */
		if(offset != 0 || n >= sizeof(sbuf)-1)
			error(Ebadarg);
		memmove(sbuf, buf, n);
		sbuf[n] = '\0';
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
		qlock(&rtclock);
		setrtc(&rtc);
		qunlock(&rtclock);
		return n;
	case Qnvram:
		if(offset > NVWRITE)
			return 0;
		if(n > NVWRITE - offset)
			n = NVWRITE - offset;
		qlock(&rtclock);
		memmove(nvr.ram+offset, buf, n);
		*nvr.cksum = rtcgencksum();
		qunlock(&rtclock);
		return n;
	}
	error(Egreg);
	return 0;		/* not reached */
}

#define bcd2dec(bcd)	(((((bcd)>>4) & 0x0F) * 10) + ((bcd) & 0x0F))
#define dec2bcd(dec)	((((dec)/10)<<4)|((dec)%10))

static void
setrtc(Rtc *rtc)
{
	struct RTCdev *dev;

	dev = nvr.rtc;
	dev->control |= RTCWRITE;
	wbflush();
	dev->year = dec2bcd(rtc->year % 100);
	dev->mon = dec2bcd(rtc->mon);
	dev->mday = dec2bcd(rtc->mday);
	dev->hour = dec2bcd(rtc->hour);
	dev->min = dec2bcd(rtc->min);
	dev->sec = dec2bcd(rtc->sec);
	wbflush();
	dev->control &= ~RTCWRITE;
	wbflush();
}

static long
rtctime(void)
{
	struct RTCdev *dev;
	Rtc rtc;

	dev = nvr.rtc;
	dev->control |= RTCREAD;
	wbflush();
	rtc.sec = bcd2dec(dev->sec) & 0x7F;
	rtc.min = bcd2dec(dev->min & 0x7F);
	rtc.hour = bcd2dec(dev->hour & 0x3F);
	rtc.mday = bcd2dec(dev->mday & 0x3F);
	rtc.mon = bcd2dec(dev->mon & 0x3F);
	rtc.year = bcd2dec(dev->year);
	dev->control &= ~RTCREAD;
	wbflush();

	if (rtc.mon < 1 || rtc.mon > 12)
		return 0;
	/*
	 *  the world starts Jan 1 1970
	 */
	if(rtc.year < 70)
		rtc.year += 2000;
	else
		rtc.year += 1900;

	return rtc2sec(&rtc);
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
yrsize(int yr)
{
	if((yr % 4) == 0)
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

	return;
}

Dev rtcdevtab = {
	'r',
	"rtc",

	devreset,
	rtcinit,
	devshutdown,
	rtcattach,
	rtcwalk,
	rtcstat,
	rtcopen,
	rtccreate,
	rtcclose,
	rtcread,
	devbread,
	rtcwrite,
	devbwrite,
	devremove,
	devwstat,
};
