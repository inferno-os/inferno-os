#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

#include "io.h"


enum{
	Qdir,
	Qled,
};

static
Dirtab cerftab[]={
	".",			{Qdir, 0, QTDIR},	0,	0555,
	"cerfled",		{Qled, 0},	0,	0660,
};

static void
cerfinit(void)						/* default in dev.c */
{
	int s;

	s = splhi();
	GPIOREG->gpdr |= 0xF;
	GPIOREG->gpsr = 1<<0;	/* we're here */
	splx(s);
}

static Chan*
cerfattach(char* spec)
{
	return devattach('T', spec);
}

static Walkqid*
cerfwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, cerftab, nelem(cerftab), devgen);
}

static int
cerfstat(Chan* c, uchar *db, int n)
{
	return devstat(c, db, n, cerftab, nelem(cerftab), devgen);
}

static Chan*
cerfopen(Chan* c, int omode)
{
	return devopen(c, omode, cerftab, nelem(cerftab), devgen);
}

static void
cerfclose(Chan* c)
{
	USED(c);
}

static long
cerfread(Chan* c, void* a, long n, vlong offset)
{
	char buf[16];

	switch((ulong)c->qid.path){
	case Qdir:
		return devdirread(c, a, n, cerftab, nelem(cerftab), devgen);
	case Qled:
		snprint(buf, sizeof(buf), "%2.2lux", GPIOREG->gplr&0xF);
		return readstr(offset, a, n, buf);
	default:
		n=0;
		break;
	}
	return n;
}

static long
cerfwrite(Chan* c, void* a, long n, vlong)
{
	char buf[16];
	ulong v;

	switch((ulong)c->qid.path){
	case Qled:
		if(n >= sizeof(buf))
			n = sizeof(buf)-1;
		memmove(buf, a, n);
		buf[n] = 0;
		v = GPIOREG->gplr & 0xF;
		if(buf[0] == '+')
			v |= strtoul(buf+1, nil, 0);
		else if(buf[0] == '-')
			v &= ~strtoul(buf+1, nil, 0);
		else
			v = strtoul(buf, nil, 0);
		GPIOREG->gpsr = v & 0xF;
		GPIOREG->gpcr = ~v & 0xF;
		break;
	default:
		error(Ebadusefd);
	}
	return n;
}

Dev cerfdevtab = {
	'T',
	"cerf",

	devreset,
	cerfinit,
	devshutdown,
	cerfattach,
	cerfwalk,
	cerfstat,
	cerfopen,
	devcreate,
	cerfclose,
	cerfread,
	devbread,
	cerfwrite,
	devbwrite,
	devremove,
	devwstat,
};
