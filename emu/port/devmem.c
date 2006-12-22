#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	"interp.h"

enum
{
	Qdir,
	Qctl,
	Qstate,
	Qsum,
	Qevent,
	Qprof,
	Qheap,
	Qgc
};

static
Dirtab memdir[] =
{
	".",			{Qdir, 0, QTDIR},	0,	DMDIR|0555,
	"memctl",		{Qctl},	0,			0666,
	"memstate",	{Qstate},	0,			0444,
	"memsum",	{Qsum},	0,			0444,
	"memevent",	{Qevent},	0,			0444,
	"memprof",	{Qprof},	0,			0444,
	"memheap",	{Qheap},	0,			0444,
	"memgc",		{Qgc},	0,			0444,
};

enum
{
	/* these are the top two bits of size */
	Pflags=	3<<30,
	  Pfree=	0<<30,
	  Palloc=	1<<30,
	  Paend=	2<<30,
	  Pimmutable=	3<<30,

	Npool = 3,
	Nevent = 10000,
	Nstate = 12000
};

/*
 * pool snapshots
 */
typedef struct Pstate Pstate;
struct Pstate
{
	ulong	base;
	ulong	size;
};

static struct
{
	Pstate	state[3+Nstate];
	Pstate*	lim;
	Pstate*	ptr;
	int	summary;
} poolstate[Npool];
static Ref	stateopen;

/*
 * pool/heap allocation events
 */
typedef struct Pevent Pevent;
struct Pevent
{
	int	pool;
	ulong	pc;
	ulong	base;
	ulong	size;
};

static struct
{
	Lock	l;
	Ref	inuse;
	Rendez	r;
	int	open;
	Pevent	events[Nevent];
	int	rd;
	int	wr;
	int	full;
	int	want;
	ulong	lost;
} poolevents;

/*
 * allocation profiles
 */
typedef struct Pprof Pprof;
typedef struct Pbucket Pbucket;

struct Pbucket
{
	ulong	val;
	ulong	pool;
	ulong	count;
	ulong	size;
	Pbucket*	next;
};

static struct {
	Ref	inuse;	/* only one of these things */
	Lock	l;
	Pbucket	buckets[1000];
	Pbucket	snap[1000];
	int	used;
	int	snapped;
	Pbucket*	hash[128];
	ulong	lost;
} memprof;

extern	void	(*memmonitor)(int, ulong, ulong, ulong);
extern	ulong	gcnruns;
extern	ulong	gcsweeps;
extern	ulong	gcbroken;
extern	ulong	gchalted;
extern	ulong	gcepochs;
extern	uvlong	gcdestroys;
extern	uvlong	gcinspects;
extern	uvlong	gcbusy;
extern	uvlong	gcidle;
extern	uvlong	gcidlepass;
extern	uvlong	gcpartial;


static void
mprofreset(void)
{
	lock(&memprof.l);	/* need ilock in kernel */
	memset(memprof.hash, 0, sizeof(memprof.hash));
	memprof.used = 0;
	memprof.lost = 0;
	unlock(&memprof.l);
}

static void
mprofmonitor(int pool, ulong pc, ulong base, ulong size)
{
	Pbucket **h0, **h, *p;

	if((pool&7) == 1)
		return;	/* ignore heap */
	USED(base);
	h0 = &memprof.hash[((pc>>16)^(pc>>4))&(nelem(memprof.hash)-1)];
	lock(&memprof.l);
	for(h = h0; (p = *h) != nil; h = &p->next)
		if(p->val == pc && p->pool == pool){
			p->count++;
			p->size += size;
			*h = p->next;
			p->next = *h0;
			*h0 = p;
			unlock(&memprof.l);
			return;
		}
	if(memprof.used >= nelem(memprof.buckets)){
		memprof.lost++;
		unlock(&memprof.l);
		return;
	}
	p = &memprof.buckets[memprof.used++];
	p->val = pc;
	p->pool = pool;
	p->count = 1;
	p->size = size;
	p->next = *h0;
	*h0 = p;
	unlock(&memprof.l);
}

static void
_memmonitor(int pool, ulong pc, ulong base, ulong size)
{
	Pevent e;

	e.pool = pool;
	e.pc = pc;
	e.base = base;
	e.size = size;
	lock(&poolevents.l);
	if(!poolevents.full){
		poolevents.events[poolevents.wr] = e;
		if(++poolevents.wr == nelem(poolevents.events))
			poolevents.wr = 0;
		if(poolevents.wr == poolevents.rd)
			poolevents.full = 1;
	}else
		poolevents.lost++;
	if(poolevents.want){
		poolevents.want = 0;
		Wakeup(&poolevents.r);
	}
	unlock(&poolevents.l);
}

static int
ismemdata(void *v)
{
	USED(v);
	return poolevents.full || poolevents.rd != poolevents.wr;
}

static char*
memaudit(int pno, Bhdr *b)
{
	Pstate *p;

	if(pno >= Npool)
		return "too many pools for memaudit";
	if((p = poolstate[pno].ptr) == poolstate[pno].lim){
		if(b->magic == MAGIC_E)
			return nil;
		p = &poolstate[pno].state[1];
		if(b->magic == MAGIC_F)
			p++;
		p->base++;
		p->size += b->size;
		return nil;
	}
	poolstate[pno].ptr++;
	p->base = (ulong)b;
	p->size = b->size;
	switch(b->magic){
	case MAGIC_A:
		p->size |= Palloc;
		break;
	case MAGIC_F:
		p->size |= Pfree;
		break;
	case MAGIC_E:
		p->size = b->csize | Paend;
		break;
	case MAGIC_I:
		p->size |= Pimmutable;
		break;
	default:
		return "bad magic number in block";
	}
	return nil;
}

static void
mput4(uchar *m, ulong v)
{
	m[0] = v>>24;
	m[1] = v>>16;
	m[2] = v>>8;
	m[3] = v;
}

static Chan*
memattach(char *spec)
{
	return devattach('%', spec);
}

static Walkqid*
memwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, memdir, nelem(memdir), devgen);
}

static int
memstat(Chan *c, uchar *db, int n)
{
	return devstat(c, db, n, memdir, nelem(memdir), devgen);
}

static Chan*
memopen(Chan *c, int omode)
{
	if(memmonitor != nil && c->qid.path != Qgc)
		error(Einuse);
	c = devopen(c, omode, memdir, nelem(memdir), devgen);
	switch((ulong)c->qid.path){
	case Qevent:
		if(incref(&poolevents.inuse) != 1){
			decref(&poolevents.inuse);
			c->flag &= ~COPEN;
			error(Einuse);
		}
		poolevents.rd = poolevents.wr = 0;
		poolevents.full = 0;
		poolevents.want = 0;
		poolevents.lost = 0;
		memmonitor = _memmonitor;
		poolevents.open = 1;
		break;
	case Qstate:
		if(incref(&stateopen) != 1){
			decref(&stateopen);
			c->flag &= ~COPEN;
			error(Einuse);
		}
		break;
	case Qprof:
		if(incref(&memprof.inuse) != 1){
			decref(&memprof.inuse);
			c->flag &= ~COPEN;
			error(Einuse);
		}
		memmonitor = mprofmonitor;
		break;
	}
	return c;
}

static void
memclose(Chan *c)
{
	if((c->flag & COPEN) == 0)
		return;
	switch((ulong)c->qid.path) {
	case Qevent:
		memmonitor = nil;
		poolevents.open = 0;
		decref(&poolevents.inuse);
		break;
	case Qstate:
		decref(&stateopen);
		break;
	case Qprof:
		decref(&memprof.inuse);
		memmonitor = nil;
		break;
	}

}

static long
memread(Chan *c, void *va, long count, vlong offset)
{
	uchar *m;
	char *e, *s;
	int i, summary;
	long n, nr;
	Pstate *p;
	Pevent pe;
	Pbucket *b;

	if(c->qid.type & QTDIR)
		return devdirread(c, va, count, memdir, nelem(memdir), devgen);

	summary = 0;
	switch((ulong)c->qid.path) {
	default:
		error(Egreg);
	case Qctl:
		return 0;
	case Qsum:
		summary = 1;
		/* fall through */
	case Qstate:
		if(offset == 0){
			for(i=0; i<Npool; i++){
				poolstate[i].ptr = &poolstate[i].state[3];
				poolstate[i].lim = poolstate[i].ptr + Nstate;
				memset(poolstate[i].state, 0, sizeof(poolstate[i].state));
				poolstate[i].summary = summary;
			}
			e = poolaudit(memaudit);
			if(e != nil){
				print("mem: %s\n", e);
				error(e);
			}
		}
		m = va;
		nr = offset/8;
		for(i=0; i<Npool && count >= 8; i++){
			n = poolstate[i].ptr - poolstate[i].state;
			poolstate[i].state[0].base = i;
			poolstate[i].state[0].size = n;
			if(nr >= n){
				nr -= n;
				continue;
			}
			n -= nr;
			p = &poolstate[i].state[nr];
			for(; --n >= 0 && (count -= 8) >= 0; m += 8, p++){
				mput4(m, p->base);
				mput4(m+4, p->size);
			}
		}
		return m-(uchar*)va;
	case Qevent:
		while(!ismemdata(nil)){
			poolevents.want = 1;
			Sleep(&poolevents.r, ismemdata, nil);
		}
		m = va;
		do{
			if((count -= 4*4) < 0)
				return m-(uchar*)va;
			pe = poolevents.events[poolevents.rd];
			mput4(m, pe.pool);
			mput4(m+4, pe.pc);
			mput4(m+8, pe.base);
			mput4(m+12, pe.size);
			m += 4*4;
			if(++poolevents.rd >= nelem(poolevents.events))
				poolevents.rd = 0;
		}while(poolevents.rd != poolevents.wr);
		poolevents.full = 0;
		return m-(uchar*)va;
	case Qprof:
		if(offset == 0){
			lock(&memprof.l);
			memmove(memprof.snap, memprof.buckets, memprof.used*sizeof(memprof.buckets[0]));
			memprof.snapped = memprof.used;
			unlock(&memprof.l);
		}
		m = va;
		for(i = offset/(4*4); i < memprof.snapped && (count -= 4*4) >= 0; i++){
			b = &memprof.snap[i];
			mput4(m, b->pool);
			mput4(m+4, b->val);
			mput4(m+8, b->count);
			mput4(m+12, b->size);
			m += 4*4;
		}
		return m-(uchar*)va;
	case Qgc:
		s = malloc(READSTR);
		if(s == nil)
			error(Enomem);
		if(waserror()){
			free(s);
			nexterror();
		}
		snprint(s, READSTR, "runs: %lud\nsweeps: %lud\nbchain: %lud\nhalted: %lud\nepochs: %lud\ndestroy: %llud\ninspects: %llud\nbusy: %llud\nidle: %llud\nidlepass: %llud\npartial: %llud\n",
			gcnruns, gcsweeps, gcbroken, gchalted, gcepochs, gcdestroys, gcinspects, gcbusy, gcidle, gcidlepass, gcpartial);
		count = readstr(offset, va, count, s);
		poperror();
		free(s);
		return count;
	}
	return 0;
}

static long
memwrite(Chan *c, void *va, long count, vlong offset)
{
	USED(offset);
	USED(count);
	USED(va);

	if(c->qid.type & QTDIR)
		error(Eperm);

	switch((ulong)c->qid.path) {
	default:
		error(Egreg);
	case Qctl:
		error(Ebadarg);
	case Qstate:
		error(Eperm);
	case Qprof:
		mprofreset();
		break;
	}
	return 0;
}

Dev memdevtab = {
	'%',
	"mem",

	devinit,
	memattach,
	memwalk,
	memstat,
	memopen,
	devcreate,
	memclose,
	memread,
	devbread,
	memwrite,
	devbwrite,
	devremove,
	devwstat
};
