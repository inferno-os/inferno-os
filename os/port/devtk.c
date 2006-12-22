#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

#include <interp.h>

#include "draw.h"

enum{
	Qdir,
	Qtkevents
};

static
Dirtab tkdirtab[]={
	{".",	{Qdir,0,QTDIR},	0,	0500},
	{"tkevents",		{Qtkevents, 0},		0,	0600},
};

static struct {
	QLock	l;
	Queue*	eq;
	Ref	inuse;
} tkevents;

static void
tkwiretapper(void *top, char *cmd, char *result, void *image, Rectangle *rp)
{
	Block *b;
	int n;
	char *s, *e;

	n = 12;
	if(cmd != nil)
		n += strlen(cmd)+2+1;
	if(result != nil)
		n += strlen(result)+2+1;
	if(image != nil)
		n += 12;
	if(rp != nil)
		n += 4*20;
	n++;
	b = allocb(n);
	if(b != nil){
		s = (char*)b->wp;
		e = s+n;
		s += snprint(s, e-s, "%p", top);
		if(cmd != nil){
			*s++ = ' ';
			*s++ = '[';
			n = strlen(cmd);
			memmove(s, cmd, n);
			s += n;
			*s++ = ']';
		}
		/* ignore result for now */
		if(image != nil)
			s += snprint(s, e-s, " %p", image);
		if(rp != nil)
			s += snprint(s, e-s, " %d %d %d %d", rp->min.x, rp->min.y, rp->max.x, rp->max.y);
		*s++ = '\n';
		b->wp = (uchar*)s;
		release();
		qlock(&tkevents.l);
		if(waserror()){
			qunlock(&tkevents.l);
			acquire();
			return;
		}
		if(tkevents.eq != nil)
			qbwrite(tkevents.eq, b);
		poperror();
		qunlock(&tkevents.l);
		acquire();
	}
}

void	(*tkwiretap)(void*, char*, char*, void*, Rectangle*);

static Chan*
tkattach(char* spec)
{
	return devattach(L'τ', spec);
}

static Walkqid*
tkwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, tkdirtab, nelem(tkdirtab), devgen);
}

static int
tkstat(Chan *c, uchar *db, int n)
{
	return devstat(c, db, n, tkdirtab, nelem(tkdirtab), devgen);
}

static Chan*
tkopen(Chan* c, int omode)
{
	if(c->qid.type & QTDIR)
		return devopen(c, omode, tkdirtab, nelem(tkdirtab), devgen);
	switch((ulong)c->qid.path){
	case Qtkevents:
		c = devopen(c, omode, tkdirtab, nelem(tkdirtab), devgen);
		qlock(&tkevents.l);
		if(incref(&tkevents.inuse) != 1){
			qunlock(&tkevents.l);
			error(Einuse);
		}
		if(tkevents.eq == nil)
			tkevents.eq = qopen(256*1024, 0, nil, nil);
		else
			qreopen(tkevents.eq);
		tkwiretap = tkwiretapper;
		qunlock(&tkevents.l);
		break;
	}
	return c;
}

static void
tkclose(Chan* c)
{
	if(c->qid.type & QTDIR || (c->flag & COPEN) == 0)
		return;
	qlock(&tkevents.l);
	if(decref(&tkevents.inuse) == 0){
		tkwiretap = nil;
		qclose(tkevents.eq);
	}
	qunlock(&tkevents.l);
}

static long
tkread(Chan* c, void* a, long n, vlong offset)
{
	USED(offset);
	switch((ulong)c->qid.path){
	case Qdir:
		return devdirread(c, a, n, tkdirtab, nelem(tkdirtab), devgen);
	case Qtkevents:
		return qread(tkevents.eq, a, n);
	default:
		n=0;
		break;
	}
	return n;
}

static long
tkwrite(Chan*, void*, long, vlong)
{
	error(Ebadusefd);
	return 0;
}

Dev tkdevtab = {
	L'τ',
	"tk",

	devreset,
	devinit,
	devshutdown,
	tkattach,
	tkwalk,
	tkstat,
	tkopen,
	devcreate,
	tkclose,
	tkread,
	devbread,
	tkwrite,
	devbwrite,
	devremove,
	devwstat,
};
