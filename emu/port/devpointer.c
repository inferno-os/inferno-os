/*
 * mouse or stylus
 */

#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

#include <draw.h>
#include <memdraw.h>
#include <cursor.h>

#define	cursorenable()
#define	cursordisable()

enum{
	Qdir,
	Qpointer,
	Qcursor
};

typedef struct Pointer Pointer;

struct Pointer {
	int	x;
	int	y;
	int	b;
	ulong	msec;
};

static struct
{
	Pointer	v;
	int	modify;
	int	lastb;
	Rendez	r;
	Ref	ref;
	QLock	q;
} mouse;

static
Dirtab pointertab[]={
	".",			{Qdir, 0, QTDIR},	0,	0555,
	"pointer",		{Qpointer},	0,	0666,
	"cursor",		{Qcursor},		0,	0222,
};

enum {
	Nevent = 16	/* enough for some */
};

static struct {
	int	rd;
	int	wr;
	Pointer	clicks[Nevent];
	Rendez r;
	int	full;
	int	put;
	int	get;
} ptrq;

/*
 * called by any source of pointer data
 */
void
mousetrack(int b, int x, int y, int isdelta)
{
	int lastb;
	ulong msec;
	Pointer e;

	if(isdelta){
		x += mouse.v.x;
		y += mouse.v.y;
	}
	msec = osmillisec();
	if(0 && b && (mouse.v.b ^ b)&0x1f){
		if(msec - mouse.v.msec < 300 && mouse.lastb == b
		   && abs(mouse.v.x - x) < 12 && abs(mouse.v.y - y) < 12)
			b |= 1<<8;
		mouse.lastb = b & 0x1f;
		mouse.v.msec = msec;
	}
	if((b&(1<<8))==0 && x == mouse.v.x && y == mouse.v.y && mouse.v.b == b)
		return;
	lastb = mouse.v.b;
	mouse.v.x = x;
	mouse.v.y = y;
	mouse.v.b = b;
	mouse.v.msec = msec;
	if(!ptrq.full && lastb != b){
		e = mouse.v;
		ptrq.clicks[ptrq.wr] = e;
		if(++ptrq.wr >= Nevent)
			ptrq.wr = 0;
		if(ptrq.wr == ptrq.rd)
			ptrq.full = 1;
	}
	mouse.modify = 1;
	ptrq.put++;
	Wakeup(&ptrq.r);
/*	drawactive(1);	*/
/*	setpointer(x, y); */
}

static int
ptrqnotempty(void *x)
{
	USED(x);
	return ptrq.full || ptrq.put != ptrq.get;
}

static Pointer
mouseconsume(void)
{
	Pointer e;

	Sleep(&ptrq.r, ptrqnotempty, 0);
	ptrq.full = 0;
	ptrq.get = ptrq.put;
	if(ptrq.rd != ptrq.wr){
		e = ptrq.clicks[ptrq.rd];
		if(++ptrq.rd >= Nevent)
			ptrq.rd = 0;
	}else
		e = mouse.v;
	return e;
}

Point
mousexy(void)
{
	return Pt(mouse.v.x, mouse.v.y);
}


static Chan*
pointerattach(char* spec)
{
	return devattach('m', spec);
}

static Walkqid*
pointerwalk(Chan *c, Chan *nc, char **name, int nname)
{
	Walkqid *wq;

	wq = devwalk(c, nc, name, nname, pointertab, nelem(pointertab), devgen);
	if(wq != nil && wq->clone != c && wq->clone != nil && (ulong)c->qid.path == Qpointer)
		incref(&mouse.ref);	/* can this happen? */
	return wq;
}

static int
pointerstat(Chan* c, uchar *db, int n)
{
	return devstat(c, db, n, pointertab, nelem(pointertab), devgen);
}

static Chan*
pointeropen(Chan* c, int omode)
{
	c = devopen(c, omode, pointertab, nelem(pointertab), devgen);
	if((ulong)c->qid.path == Qpointer){
		if(waserror()){
			c->flag &= ~COPEN;
			nexterror();
		}
		if(!canqlock(&mouse.q))
			error(Einuse);
		if(incref(&mouse.ref) != 1){
			qunlock(&mouse.q);
			error(Einuse);
		}
		cursorenable();
		qunlock(&mouse.q);
		poperror();
	}
	return c;
}

static void
pointerclose(Chan* c)
{
	if((c->flag & COPEN) == 0)
		return;
	switch((ulong)c->qid.path){
	case Qpointer:
		qlock(&mouse.q);
		if(decref(&mouse.ref) == 0){
			cursordisable();
		}
		qunlock(&mouse.q);
		break;
	}
}

static long
pointerread(Chan* c, void* a, long n, vlong off)
{
	Pointer mt;
	char buf[1+4*12+1];
	int l;

	USED(&off);
	switch((ulong)c->qid.path){
	case Qdir:
		return devdirread(c, a, n, pointertab, nelem(pointertab), devgen);
	case Qpointer:
		qlock(&mouse.q);
		if(waserror()) {
			qunlock(&mouse.q);
			nexterror();
		}
		mt = mouseconsume();
		poperror();
		qunlock(&mouse.q);
		l = snprint(buf, sizeof(buf), "m%11d %11d %11d %11lud ", mt.x, mt.y, mt.b, mt.msec);
		if(l < n)
			n = l;
		memmove(a, buf, n);
		break;
	default:
		n=0;
		break;
	}
	return n;
}

static long
pointerwrite(Chan* c, void* va, long n, vlong off)
{
	char *a = va;
	char buf[128];
	int b, x, y;
	Drawcursor cur;

	USED(&off);
	switch((ulong)c->qid.path){
	case Qpointer:
		if(n > sizeof buf-1)
			n = sizeof buf -1;
		memmove(buf, va, n);
		buf[n] = 0;
		x = strtoul(buf+1, &a, 0);
		if(*a == 0)
			error(Eshort);
		y = strtoul(a, &a, 0);
		if(*a != 0)
			b = strtoul(a, 0, 0);
		else
			b = mouse.v.b;
		/*mousetrack(b, x, y, msec);*/
		setpointer(x, y);
		USED(b);
		break;
	case Qcursor:
		/* TO DO: perhaps interpret data as an Image */
		/*
		 *  hotx[4] hoty[4] dx[4] dy[4] clr[dx/8 * dy/2] set[dx/8 * dy/2]
		 *  dx must be a multiple of 8; dy must be a multiple of 2.
		 */
		if(n == 0){
			cur.data = nil;
			drawcursor(&cur);
			break;
		}
		if(n < 8)
			error(Eshort);
		cur.hotx = BGLONG((uchar*)va+0*4);
		cur.hoty = BGLONG((uchar*)va+1*4);
		cur.minx = 0;
		cur.miny = 0;
		cur.maxx = BGLONG((uchar*)va+2*4);
		cur.maxy = BGLONG((uchar*)va+3*4);
		if(cur.maxx%8 != 0 || cur.maxy%2 != 0 || n-4*4 != (cur.maxx/8 * cur.maxy))
			error(Ebadarg);
		cur.data = (uchar*)va + 4*4;
		drawcursor(&cur);
		break;
	default:
		error(Ebadusefd);
	}
	return n;
}

Dev pointerdevtab = {
	'm',
	"pointer",

	devinit,
	pointerattach,
	pointerwalk,
	pointerstat,
	pointeropen,
	devcreate,
	pointerclose,
	pointerread,
	devbread,
	pointerwrite,
	devbwrite,
	devremove,
	devwstat,
};
