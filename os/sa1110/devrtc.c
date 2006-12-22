#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

#include	"io.h"

/*
 * SA11x0 real time clock
 *	TO DO: alarms, wakeup, allow trim setting(?)
 */

enum{
	Qdir,
	Qrtc,
	Qrtctrim,
};

static Dirtab rtcdir[]={
	".",		{Qdir,0,QTDIR},	0,	0555,
	"rtc",		{Qrtc},	NUMSIZE,	0664,
	"rtctrim",	{Qrtctrim},	0,	0664,
};
#define	NRTC	(sizeof(rtcdir)/sizeof(rtcdir[0]))

extern ulong boottime;

enum {
	RTSR_al=	1<<0,	/* RTC alarm detected */
	RTSR_hz=	1<<1,	/* 1-Hz rising-edge detected */
	RTSR_ale=	1<<2,	/* RTC alarm interrupt enabled */
	RTSR_hze=	1<<3,	/* 1-Hz interrupt enable */
};

static void
rtcreset(void)
{
	RtcReg *r;

	r = RTCREG;
	if((r->rttr & 0xFFFF) == 0){	/* reset state */
		r->rttr = 32768-1;
		r->rcnr = boottime;	/* typically zero */
	}
	r->rtar = ~0;
	r->rtsr = RTSR_al | RTSR_hz;
}

static Chan*
rtcattach(char *spec)
{
	return devattach('r', spec);
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
	return devopen(c, omode, rtcdir, NRTC, devgen);
}

static void	 
rtcclose(Chan*)
{
}

static long	 
rtcread(Chan *c, void *buf, long n, vlong off)
{
	if(c->qid.type & QTDIR)
		return devdirread(c, buf, n, rtcdir, NRTC, devgen);

	switch((ulong)c->qid.path){
	case Qrtc:
		return readnum(off, buf, n, RTCREG->rcnr, NUMSIZE);
	case Qrtctrim:
		return readnum(off, buf, n, RTCREG->rttr, NUMSIZE);
	}
	error(Egreg);
	return 0;		/* not reached */
}

static long	 
rtcwrite(Chan *c, void *buf, long n, vlong off)
{
	ulong offset = off;
	ulong secs;
	char *cp, sbuf[32];

	switch((ulong)c->qid.path){
	case Qrtc:
		/*
		 *  write the time
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
		RTCREG->rcnr = secs;
		return n;

	case Qrtctrim:
		if(offset != 0 || n >= sizeof(sbuf)-1)
			error(Ebadarg);
		memmove(sbuf, buf, n);
		sbuf[n] = '\0';
		RTCREG->rttr = strtoul(sbuf, 0, 0);
		return n;
	}
	error(Egreg);
	return 0;		/* not reached */
}

static void
rtcpower(int on)
{
	if(on)
		boottime = RTCREG->rcnr - TK2SEC(MACHP(0)->ticks);
	else
		RTCREG->rcnr = seconds();
}

long
rtctime(void)
{
	return RTCREG->rcnr;
}

Dev rtcdevtab = {
	'r',
	"rtc",

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
	rtcpower,
};
