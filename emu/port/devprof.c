#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	"interp.h"
#include	<isa.h>
#include	"runt.h"

extern	Pool*	imagmem;
extern void	(*memmonitor)(int, ulong, ulong, ulong);

static void	cpxec(Prog *);
static void memprof(int, void*, ulong);
static void memprofmi(int, ulong, ulong, ulong);

extern	Inst*	pc2dispc(Inst*, Module*);

static	int	interval = 100;	/* Sampling interval in milliseconds */

enum
{
	HSIZE	= 32,
};

#define HASH(m)	((m)%HSIZE)

/* cope with  multiple profilers some day */

typedef struct Record Record;
struct Record
{
	int	id;
	char*	name;
	char*	path;
	Inst*	base;
	int	size;
	/*Module*	m;	*/
	ulong	mtime;
	Qid	qid;
	Record*	hash;
	Record*	link;
	ulong	bucket[1];
};

struct
{
	Lock	l;
	vlong	time;
	Record*	hash[HSIZE];
	Record*	list;
} profile;

typedef struct Pmod Pmod;
struct Pmod
{
	char*	name;
	Pmod*	link;
} *pmods;
	
#define QSHIFT	4
#define QID(q)		((ulong)(q).path&0xf)
#define QPID(pid)	((pid)<<QSHIFT)
#define PID(q)		((q).vers)
#define PATH(q)	((ulong)(q).path&~((1<<QSHIFT)-1))

enum
{
	Qdir,
	Qname,
	Qpath,
	Qhist,
	Qpctl,
	Qctl,
};

Dirtab profdir[] =
{
	".",			{Qdir, 0, QTDIR},	0,	DMDIR|0555,
	"name",		{Qname},	0,			0444,
	"path",		{Qpath},	0,			0444,
	"histogram",	{Qhist},	0,			0444,
	"pctl",		{Qpctl},	0,			0222,
	"ctl",			{Qctl},	0,			0222,
};

enum{
	Pnil,	/* null profiler */
	Psam,	/* sampling profiler */
	Pcov,	/* coverage profiler */
	Pmem,	/* heap memory profiler */
};

enum{
	Mnone = 0,
	Mmain = 1,
	Mheap = 2,
	Mimage = 4,
};

static int profiler = Pnil;
static int mprofiler = Mnone;

static int ids;
static int samplefn;

static void sampler(void*);

static Record*
getrec(int id)
{
	Record *r;

	for(r = profile.list; r != nil; r = r->link)
		if(r->id == id)
			break;
	return r;
}

static void
addpmod(char *m)
{
	Pmod *p = malloc(sizeof(Pmod));

	if(p == nil)
		return;
	p->name = malloc(strlen(m)+1);
	if(p->name == nil){
		free(p);
		return;
	}
	strcpy(p->name, m);
	p->link = pmods;
	pmods = p;
}

static void
freepmods(void)
{
	Pmod *p, *np;

	for(p = pmods; p != nil; p = np){
		free(p->name);
		np = p->link;
		free(p);
	}
	pmods = nil;
}

static int
inpmods(char *m)
{
	Pmod *p;

	for(p = pmods; p != nil; p = p->link)
		if(strcmp(p->name, m) == 0)
			return 1;
	return 0;
}

static void
freeprof(void)
{
	int i;
	Record *r, *nr;

	ids = 0;
	profiler = Pnil;
	mprofiler = Mnone;
	freepmods();
	for(r = profile.list; r != nil; r = nr){
		free(r->name);
		free(r->path);
		nr = r->link;
		free(r);
	}
	profile.list = nil;
	profile.time = 0;
	for(i = 0; i < HSIZE; i++)
		profile.hash[i] = nil;
}

static int
profgen(Chan *c, char *name, Dirtab *d, int nd, int s, Dir *dp)
{
	Qid qid;
	Record *r;
	ulong path, perm, len;
	Dirtab *tab;

	USED(name);
	USED(d);
	USED(nd);

	if(s == DEVDOTDOT) {
		mkqid(&qid, Qdir, 0, QTDIR);
		devdir(c, qid, "#P", 0, eve, 0555, dp);
		return 1;
	}

	if(c->qid.path == Qdir && c->qid.type & QTDIR) {
		acquire();
		if(s-- == 0){
			tab = &profdir[Qctl];
			mkqid(&qid, PATH(c->qid)|tab->qid.path, c->qid.vers, QTFILE);
			devdir(c, qid, tab->name, tab->length, eve, tab->perm, dp);
			release();
			return 1;
		}
		r = profile.list;
		while(s-- && r != nil)
			r = r->link;
		if(r == nil) {
			release();
			return -1;
		}
		sprint(up->genbuf, "%.8lux", (ulong)r->id);
		mkqid(&qid, (r->id<<QSHIFT), r->id, QTDIR);
		devdir(c, qid, up->genbuf, 0, eve, DMDIR|0555, dp);
		release();
		return 1;
	}
	if(s >= nelem(profdir)-1)
		error(Enonexist);	/* was return -1; */
	tab = &profdir[s];
	path = PATH(c->qid);

	acquire();
	r = getrec(PID(c->qid));
	if(r == nil) {
		release();
		error(Enonexist);	/* was return -1; */
	}

	perm = tab->perm;
	len = tab->length;
	mkqid(&qid, path|tab->qid.path, c->qid.vers, QTFILE);
	devdir(c, qid, tab->name, len, eve, perm, dp);
	release();
	return 1;
}

static Chan*
profattach(char *spec)
{
	return devattach('P', spec);
}

static Walkqid*
profwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, 0, 0, profgen);
}

static int
profstat(Chan *c, uchar *db, int n)
{
	return devstat(c, db, n, 0, 0, profgen);
}

static Chan*
profopen(Chan *c, int omode)
{
	int qid;
	Record *r;

	if(c->qid.type & QTDIR) {
		if(omode != OREAD)
			error(Eisdir);
		c->mode = openmode(omode);
		c->flag |= COPEN;
		c->offset = 0;
		return c;
	}

	if(omode&OTRUNC)
		error(Eperm);

	qid = QID(c->qid);
	if(qid == Qctl || qid == Qpctl){
		if (omode != OWRITE)
			error(Eperm);
	}
	else{
		if(omode != OREAD)
			error(Eperm);
	}

	if(qid != Qctl){
		acquire();
		r = getrec(PID(c->qid));
		release();
		if(r == nil)
			error(Ethread);
	}

	c->offset = 0;
	c->flag |= COPEN;
	c->mode = openmode(omode);
	if(QID(c->qid) == Qhist)
		c->aux = nil;
	return c;
}

static int
profwstat(Chan *c, uchar *dp, int n)
{
	Dir d;
	Record *r;

	if(strcmp(up->env->user, eve))
		error(Eperm);
	if(c->qid.type & QTDIR)
		error(Eperm);
	acquire();
	r = getrec(PID(c->qid));
	release();
	if(r == nil)
		error(Ethread);
	n = convM2D(dp, n, &d, nil);
	if(n == 0)
		error(Eshortstat);
	d.mode &= 0777;
	/* TO DO: copy to c->aux->perm, once that exists */
	return n;
}

static void
profclose(Chan *c)
{
	USED(c);
}

static long
profread(Chan *c, void *va, long n, vlong offset)
{
	int i;
	Record *r;
	char *a = va;

	if(c->qid.type & QTDIR)
		return devdirread(c, a, n, 0, 0, profgen);
	acquire();
	r = getrec(PID(c->qid));
	release();
	if(r == nil)
		error(Ethread);
	switch(QID(c->qid)){
	case Qname:
		return readstr(offset, va, n, r->name);
	case Qpath:
		return readstr(offset, va, n, r->path);
	case Qhist:
		i = (int)c->aux;
		while(i < r->size && r->bucket[i] == 0)
			i++;
		if(i >= r->size)
			return 0;
		c->aux = (void*)(i+1);
		if(n < 20)
			error(Etoosmall);
		return sprint(a, "%d %lud", i, r->bucket[i]);
	case Qctl:
		error(Eperm);
	}
	return 0;
}

static long
profwrite(Chan *c, void *va, long n, vlong offset)
{
	int i;
	char *a = va;
	char buf[128], *fields[128];
	void	(*f)(int, ulong, ulong, ulong);

	USED(va);
	USED(n);
	USED(offset);

	if(c->qid.type & QTDIR)
		error(Eisdir);
	switch(QID(c->qid)){
	case Qctl:
		if(n > sizeof(buf)-1)
			n = sizeof(buf)-1;
		memmove(buf, a, n);
		buf[n] = 0;
		i = getfields(buf, fields, nelem(fields), 1, " \t\n");
		if(i > 0 && strcmp(fields[0], "module") == 0){
			f = memmonitor;
			memmonitor = nil;
			freepmods();
			while(--i > 0)
				addpmod(fields[i]);
			memmonitor = f;
			return n;
		}
		if(i == 1){
			if(strcmp(fields[0], "start") == 0){
				if(profiler == Pnil) {
					profiler = Psam;
					if(!samplefn){
						samplefn = 1;
						kproc("prof", sampler, 0, 0);
					}
				}
			}
			else if(strncmp(fields[0], "startmp", 7) == 0){
				if(profiler == Pnil){
					profiler = Pmem;
					for(a = &fields[0][7]; *a != '\0'; a++){
						if(*a == '1'){
							memmonitor = memprofmi;
							mprofiler |= Mmain;
						}
						else if(*a == '2'){
							heapmonitor = memprof;
							mprofiler |= Mheap;
						}
						else if(*a == '3'){
							memmonitor = memprofmi;
							mprofiler |= Mimage;
						}
					};
				}
			}
			else if(strcmp(fields[0], "stop") == 0){
				profiler = Pnil;
				mprofiler = Mnone;
			}
			else if(strcmp(fields[0], "end") == 0){
				profiler = Pnil;
				mprofiler = Mnone;
				memmonitor = nil;
				freeprof();
				interval = 100;
			}
			else
				error(Ebadarg);
		}
		else if (i == 2){
			if(strcmp(fields[0], "interval") == 0)
				interval = strtoul(fields[1], nil, 0);
			else if(strcmp(fields[0], "startcp") == 0){
				Prog *p;

				acquire();
				p = progpid(strtoul(fields[1], nil, 0));
				if(p == nil){
					release();
					return -1;
				}
				if(profiler == Pnil){
					profiler = Pcov;
					p->xec = cpxec;
				}
				release();
			}
			else
				error(Ebadarg);
		}
		else
			error(Ebadarg);
		return n;
	default:
		error(Eperm);
	}
	return 0;
}

static Record*
newmodule(Module *m, int vm, int scale, int origin)
{
	int dsize;
	Record *r, **l;

	if(!vm)
		acquire();
	if((m->compiled && m->pctab == nil) || m->prog == nil) {
		if(!vm)
			release();
		return nil;
	}
	if(m->compiled)
		dsize = m->nprog * sizeof(r->bucket[0]);
	else
		dsize = (msize(m->prog)/sizeof(Inst)) * sizeof(r->bucket[0]);
	dsize *= scale;
	dsize += origin;
	r = malloc(sizeof(Record)+dsize);
	if(r == nil) {
		if(!vm)
			release();
		return nil;
	}

	r->id = ++ids;
	if(ids == (1<<8)-1)
		ids = 0;
	kstrdup(&r->name, m->name);
	kstrdup(&r->path, m->path);
	r->base = m->prog;
	r->size = dsize/sizeof(r->bucket[0]);
	/* r->m = m; */
	r->mtime = m->mtime;
	r->qid.path = m->qid.path;
	r->qid.vers = m->qid.vers;
	memset(r->bucket, 0, dsize);
	r->link = profile.list;
	profile.list = r;

	l = &profile.hash[HASH(m->mtime)];
	r->hash = *l;
	*l = r;

	if(!vm)
		release();
	return r;
}

#define LIMBO(m)	((m)->path[0] != '$')

Module*
limbomodule(void)
{
	Frame *f;
	uchar *fp;
	Module *m;

	m = R.M->m;
	if(LIMBO(m))
		return m;
	for(fp = R.FP ; fp != nil; fp = f->fp){
		f = (Frame*)fp;
		if(f->mr != nil){
			m = f->mr->m;
			if(LIMBO(m))
				return m;
		}
	}
	return nil;
}
	
static Record*
mlook(Module *m, int limbo, int vm, int scale, int origin)
{
	Record *r;
	void	(*f)(int, ulong, ulong, ulong);

	if(limbo)
		m = limbomodule();
	if(m == nil)
		return nil;
	for(r = profile.hash[HASH(m->mtime)]; r; r = r->hash){
		if(r->mtime == m->mtime && r->qid.path == m->qid.path && r->qid.vers == m->qid.vers && strcmp(r->name, m->name) == 0 && strcmp(r->path, m->path) == 0){
			r->base = m->prog;
			return r;
		}
	}
	if(pmods == nil || inpmods(m->name) || inpmods(m->path)){
		f = memmonitor;
		memmonitor = nil;	/* prevent monitoring of our memory usage */
		r = newmodule(m, vm, scale, origin);
		memmonitor = f;
		return r;
	}
	return nil;
}

static void
sampler(void* a)
{
	int i;
	Module *m;
	Record *r;
	Inst *p;

	USED(a);
	for(;;) {
		osmillisleep(interval);
		if(profiler != Psam)
			break;
		lock(&profile.l);
		profile.time += interval;
		if(R.M == H || (m = R.M->m) == nil){
			unlock(&profile.l);
			continue;
		}
		p = R.PC;
		r = mlook(m, 0, 0, 1, 0);
		if(r == nil){
			unlock(&profile.l);
			continue;
		}
		if(m->compiled && m->pctab != nil)
			p = pc2dispc(p, m);
		if((i = p-r->base) >= 0 && i < r->size)
			r->bucket[i]++;
		unlock(&profile.l);
	}
	samplefn = 0;
	pexit("", 0);
}

/*
 *	coverage profiling
 */

static void
cpxec(Prog *p)
{
	int op, i;
	Module *m;
	Record *r;
	Prog *n;

	R = p->R;
	R.MP = R.M->MP;
	R.IC = p->quanta;

	if(p->kill != nil){
		char *m;
		m = p->kill;
		p->kill = nil;
		error(m);
	}

	if(R.M->compiled)
		comvec();
	else{
		m = R.M->m;
		r = profiler == Pcov ? mlook(m, 0, 1, 1, 0) : nil;
		do{
			dec[R.PC->add]();
			op = R.PC->op;
			if(r != nil){
				i = R.PC-r->base;
				if(i >= 0 && i < r->size)
					r->bucket[i]++;
			}
			R.PC++;
			optab[op]();
			if(op == ISPAWN || op == IMSPAWN){
				n = delruntail(Pdebug);	/* any state will do */
				n->xec = cpxec;
				addrun(n);
			}
			if(m != R.M->m){
				m = R.M->m;
				r = profiler == Pcov ? mlook(m, 0, 1, 1, 0) : nil;
			}
		}while(--R.IC != 0);
	}

	p->R = R;
}

/* memory profiling */

enum{
	Mhalloc,
	Mhfree,
	Mgcfree,
	Mmfree,
	Mmalloc,
	Mifree,
	Mialloc,
};

static void
memprof(int c, void *v, ulong n)
{
	int i, j, k;
	ulong kk, *b;
	Module *m;
	Record *r;
	Inst *p;
	Heap *h;

	USED(v);
	USED(n);
	if(profiler != Pmem){
		memmonitor = nil;
		heapmonitor = nil;
		return;
	}
	lock(&profile.l);
	m = nil;
	if(c != Mgcfree && (R.M == H || (m = R.M->m) == nil)){
		unlock(&profile.l);
		return;
	}
	h = v;
	if(c == Mhalloc || c == Mmalloc || c == Mialloc){
		p = R.PC;
		if(m->compiled && m->pctab != nil)
			p = pc2dispc(p, m);
		if((r = mlook(m, 1, 1, 2, 2)) == nil){
			unlock(&profile.l);
			return;
		}
		i = p-r->base;
		k = (r->id<<24) | i;
		if(c == Mhalloc){
			h->hprof = k;
			j = hmsize(h)-sizeof(Heap);
		}
		else if(c == Mmalloc){
			setmalloctag(v, k);
			j = msize(v);
		}
		else{
			((ulong*)v)[1] = k;
			j = poolmsize(imagmem, v)-sizeof(ulong);
		}
	}
	else{
		if(c == Mmfree)
			k = getmalloctag(v);
		else if(c == Mifree)
			k = ((ulong*)v)[1];
		else
			k = h->hprof;
		if((r = getrec(k>>24)) == nil){
			unlock(&profile.l);
			return;
		}
		i = k&0xffffff;
		if(c == Mmfree)
			j = msize(v);
		else if(c == Mifree)
			j = poolmsize(imagmem, v)-sizeof(ulong);
		else
			j = hmsize(h)-sizeof(Heap);
		j = -j;
	}
	i = 2*(i+1);
	b = r->bucket;
	if(i >= 0 && i < r->size){
		if(0){
			if(c == 1){
				b[0] -= j;
				b[i] -= j;
			}
			else if(c == 2){
				b[1] -= j;
				b[i+1] -= j;
			}
		}
		else{
			b[0] += j;
			if((int)b[0] < 0)
				b[0] = 0;
			b[i] += j;
			if((int)b[i] < 0)
				b[i] = 0;
			if(j > 0){
				if((kk = b[0]) > b[1])
					b[1] = kk;
				if((kk = b[i]) > b[i+1])
					b[i+1] = kk;
			}
		}
	}
	unlock(&profile.l);
}

/* main and image memory */
static void
memprofmi(int c, ulong pc, ulong v, ulong n)
{
	USED(pc);

	if(c&2){
		if(!(mprofiler&Mimage))
			return;
	}
	else{
		if(!(mprofiler&Mmain))
			return;
	}
	switch(c){
	case 0:
		c = Mmalloc;
		break;
	case 2:
		c = Mialloc;
		break;
	case 0 | 1<<8:
		c = Mmfree;
		break;
	case 2 | 1<<8:
		c = Mifree;
		break;
	default:
		print("bad profile code %d\n", c);
	}
	memprof(c, (void*)v, n);
}

Dev profdevtab = {
	'P',
	"prof",

	devinit,
	profattach,
	profwalk,
	profstat,
	profopen,
	devcreate,
	profclose,
	profread,
	devbread,
	profwrite,
	devbwrite,
	devremove,
	profwstat
};
