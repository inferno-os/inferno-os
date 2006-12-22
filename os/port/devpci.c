/*
 *	access to PCI configuration space (devpnp.c without PNP)
 *
 *	TODO
 *		- extend PCI raw access to configuration space (writes, byte/short access?)
 *		- implement PCI access to memory/io space/BIOS ROM
 *		- use c->aux instead of performing lookup on each read/write?
 */
#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"

#define	DPRINT	if(0) print
#define	XPRINT	if(1) print

enum {
	Qtopdir = 0,

	Qpcidir,
	Qpcictl,
	Qpciraw,
};

#define TYPE(q)		((ulong)(q).path & 0x0F)
#define QID(c, t)	(((c)<<4)|(t))

static Dirtab topdir[] = {
	".",	{ Qtopdir, 0, QTDIR },	0,	0555,
	"pci",	{ Qpcidir, 0, QTDIR },	0,	0555,
};

extern Dev pcidevtab;

static int
pcigen2(Chan *c, int t, int tbdf, Dir *dp)
{
	Qid q;

	q = (Qid){BUSBDF(tbdf)|t, 0, 0};
	switch(t) {
	case Qpcictl:
		sprint(up->genbuf, "%d.%d.%dctl", BUSBNO(tbdf), BUSDNO(tbdf), BUSFNO(tbdf));
		devdir(c, q, up->genbuf, 0, eve, 0444, dp);
		return 1;
	case Qpciraw:
		sprint(up->genbuf, "%d.%d.%draw", BUSBNO(tbdf), BUSDNO(tbdf), BUSFNO(tbdf));
		devdir(c, q, up->genbuf, 128, eve, 0444, dp);
		return 1;
	}
	return -1;
}

static int
pcigen(Chan *c, char *, Dirtab*, int, int s, Dir *dp)
{
	Qid q;
	Pcidev *p;
	int tbdf;

	switch(TYPE(c->qid)){
	case Qtopdir:
		if(s == DEVDOTDOT){
			q = (Qid){QID(0, Qtopdir), 0, QTDIR};
			sprint(up->genbuf, "#%C", pcidevtab.dc);
			devdir(c, q, up->genbuf, 0, eve, 0555, dp);
			return 1;
		}
		return devgen(c, nil, topdir, nelem(topdir), s, dp);
	case Qpcidir:
		if(s == DEVDOTDOT){
			q = (Qid){QID(0, Qtopdir), 0, QTDIR};
			sprint(up->genbuf, "#%C", pcidevtab.dc);
			devdir(c, q, up->genbuf, 0, eve, 0555, dp);
			return 1;
		}
		p = pcimatch(nil, 0, 0);
		while(s >= 2 && p != nil) {
			p = pcimatch(p, 0, 0);
			s -= 2;
		}
		if(p == nil)
			return -1;
		return pcigen2(c, s+Qpcictl, p->tbdf, dp);
	case Qpcictl:
	case Qpciraw:
		tbdf = MKBUS(BusPCI, 0, 0, 0)|BUSBDF((ulong)c->qid.path);
		p = pcimatchtbdf(tbdf);
		if(p == nil)
			return -1;
		return pcigen2(c, TYPE(c->qid), tbdf, dp);
	default:
		break;
	}
	return -1;
}

static Chan*
pciattach(char *spec)
{
	return devattach(pcidevtab.dc, spec);
}

Walkqid*
pciwalk(Chan* c, Chan *nc, char** name, int nname)
{
	return devwalk(c, nc, name, nname, nil, 0, pcigen);
}

static int
pcistat(Chan* c, uchar* dp, int n)
{
	return devstat(c, dp, n, nil, 0, pcigen);
}

static Chan*
pciopen(Chan *c, int omode)
{
	return devopen(c, omode, nil, 0, pcigen);
}

static void
pciclose(Chan*)
{
}

static long
pciread(Chan *c, void *va, long n, vlong offset)
{
	ulong x;
	Pcidev *p;
	char buf[256], *ebuf, *w;
	char *a = va;
	int i, tbdf, r;

	switch(TYPE(c->qid)){
	case Qtopdir:
	case Qpcidir:
		return devdirread(c, a, n, nil, 0, pcigen);
	case Qpcictl:
		tbdf = MKBUS(BusPCI, 0, 0, 0)|BUSBDF((ulong)c->qid.path);
		p = pcimatchtbdf(tbdf);
		if(p == nil)
			error(Egreg);
		ebuf = buf+sizeof buf-1;	/* -1 for newline */
		w = seprint(buf, ebuf, "%.2x.%.2x.%.2x %.4x/%.4x %3d",
			p->ccrb, p->ccru, p->ccrp, p->vid, p->did, p->intl);
		for(i=0; i<nelem(p->mem); i++){
			if(p->mem[i].size == 0)
				continue;
			w = seprint(w, ebuf, " %d:%.8lux %d", i, p->mem[i].bar, p->mem[i].size);
		}
		*w++ = '\n';
		*w = '\0';
		return readstr(offset, a, n, buf);
	case Qpciraw:
		tbdf = MKBUS(BusPCI, 0, 0, 0)|BUSBDF((ulong)c->qid.path);
		p = pcimatchtbdf(tbdf);
		if(p == nil)
			error(Egreg);
		if(offset > 256)
			return 0;
		if(n+offset > 256)
			n = 256-offset;
		if(offset%4)
			error(Ebadarg);
		r = offset;
		for(i = 0; i+4 <= n; i+=4) {
			x = pcicfgr32(p, r);
			a[0] = x;
			a[1] = (x>>8);
			a[2] = (x>>16);
			a[3] = (x>>24);
			a += 4;
			r += 4;
		}
		return i;
	default:
		error(Egreg);
	}
	return n;
}

static long
pciwrite(Chan *c, void *a, long n, vlong)
{
	char buf[256];

	if(n >= sizeof(buf))
		n = sizeof(buf)-1;
	strncpy(buf, a, n);
	buf[n] = 0;

	switch(TYPE(c->qid)){
	case Qpcictl:
	case Qpciraw:
		error(Eperm);
	default:
		error(Egreg);
	}
	return n;
}


Dev pcidevtab = {
	'$',
	"pci",

	devreset,
	devinit,
	devshutdown,
	pciattach,
	pciwalk,
	pcistat,
	pciopen,
	devcreate,
	pciclose,
	pciread,
	devbread,
	pciwrite,
	devbwrite,
	devremove,
	devwstat,
};
