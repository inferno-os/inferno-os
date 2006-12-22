#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	"../ip/ip.h"

IProuter iprouter;

/*
 *  User level routing.  Ip packets we don't know what to do with
 *  come here.
 */
void
useriprouter(Fs *f, Ipifc *ifc, Block *bp)
{
	qlock(&f->iprouter);
	if(f->iprouter.q != nil){
		bp = padblock(bp, IPaddrlen);
		if(bp == nil)
			return;
		ipmove(bp->rp, ifc->lifc->local);
		qpass(f->iprouter.q, bp);
	}else
		freeb(bp);
	qunlock(&f->iprouter);
}

void
iprouteropen(Fs *f)
{
	qlock(&f->iprouter);
	f->iprouter.opens++;
	if(f->iprouter.q == nil)
		f->iprouter.q = qopen(64*1024, 0, 0, 0);
	else if(f->iprouter.opens == 1)
		qreopen(f->iprouter.q);
	qunlock(&f->iprouter);
}

void
iprouterclose(Fs *f)
{
	qlock(&f->iprouter);
	f->iprouter.opens--;
	if(f->iprouter.opens == 0)
		qclose(f->iprouter.q);
	qunlock(&f->iprouter);
}

long
iprouterread(Fs *f, void *a, int n)
{
	return qread(f->iprouter.q, a, n);
}
