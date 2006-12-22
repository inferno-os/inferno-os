#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include "interp.h"

#define NETTYPE(x)	((ulong)(x)&0x1f)
#define NETID(x)	(((ulong)(x))>>5)
#define NETQID(i,t)	(((i)<<5)|(t))

typedef struct Pipe	Pipe;
struct Pipe
{
	QLock;
	Pipe*	next;
	int	ref;
	ulong	path;
	Queue*	q[2];
	int	qref[2];
	Dirtab	*pipedir;
	char*	user;
};

static struct
{
	Lock;
	ulong	path;
	int	pipeqsize;	
} pipealloc;

enum
{
	Qdir,
	Qdata0,
	Qdata1,
};

static 
Dirtab pipedir[] =
{
	".",		{Qdir,0,QTDIR},	0,		DMDIR|0500,
	"data",		{Qdata0},	0,			0660,
	"data1",	{Qdata1},	0,			0660,
};

static void
freepipe(Pipe *p)
{
	if(p != nil){
		free(p->user);
		free(p->q[0]);
		free(p->q[1]);
		free(p->pipedir);
		free(p);
	}
}

static void
pipeinit(void)
{
	pipealloc.pipeqsize = 32*1024;
}

/*
 *  create a pipe, no streams are created until an open
 */
static Chan*
pipeattach(char *spec)
{
	Pipe *p;
	Chan *c;

	c = devattach('|', spec);
	p = malloc(sizeof(Pipe));
	if(p == 0)
		error(Enomem);
	if(waserror()){
		freepipe(p);
		nexterror();
	}
	p->pipedir = malloc(sizeof(pipedir));
	if (p->pipedir == 0)
		error(Enomem);
	memmove(p->pipedir, pipedir, sizeof(pipedir));
	kstrdup(&p->user, up->env->user);
	p->ref = 1;

	p->q[0] = qopen(pipealloc.pipeqsize, 0, 0, 0);
	if(p->q[0] == 0)
		error(Enomem);
	p->q[1] = qopen(pipealloc.pipeqsize, 0, 0, 0);
	if(p->q[1] == 0)
		error(Enomem);
	poperror();

	lock(&pipealloc);
	p->path = ++pipealloc.path;
	unlock(&pipealloc);

	c->qid.path = NETQID(2*p->path, Qdir);
	c->qid.vers = 0;
	c->qid.type = QTDIR;
	c->aux = p;
	c->dev = 0;
	return c;
}

static int
pipegen(Chan *c, char *, Dirtab *tab, int ntab, int i, Dir *dp)
{
	int id, len;
	Qid qid;
	Pipe *p;

	if(i == DEVDOTDOT){
		devdir(c, c->qid, "#|", 0, eve, 0555, dp);
		return 1;
	}
	i++;	/* skip . */
	if(tab==0 || i>=ntab)
		return -1;
	tab += i;
	p = c->aux;
	switch(NETTYPE(tab->qid.path)){
	case Qdata0:
		len = qlen(p->q[0]);
		break;
	case Qdata1:
		len = qlen(p->q[1]);
		break;
	default:
		len = tab->length;
		break;
	}
	id = NETID(c->qid.path);
	qid.path = NETQID(id, tab->qid.path);
	qid.vers = 0;
	qid.type = QTFILE;
	devdir(c, qid, tab->name, len, eve, tab->perm, dp);
	return 1;
}


static Walkqid*
pipewalk(Chan *c, Chan *nc, char **name, int nname)
{
	Walkqid *wq;
	Pipe *p;

	p = c->aux;
	wq = devwalk(c, nc, name, nname, p->pipedir, nelem(pipedir), pipegen);
	if(wq != nil && wq->clone != nil && wq->clone != c){
		qlock(p);
		p->ref++;
		if(c->flag & COPEN){
			switch(NETTYPE(c->qid.path)){
			case Qdata0:
				p->qref[0]++;
				break;
			case Qdata1:
				p->qref[1]++;
				break;
			}
		}
		qunlock(p);
	}
	return wq;
}

static int
pipestat(Chan *c, uchar *db, int n)
{
	Pipe *p;
	Dir dir;
	Dirtab *tab;

	p = c->aux;
	tab = p->pipedir;

	switch(NETTYPE(c->qid.path)){
	case Qdir:
		devdir(c, c->qid, ".", 0, eve, DMDIR|0555, &dir);
		break;
	case Qdata0:
		devdir(c, c->qid, tab[1].name, qlen(p->q[0]), eve, tab[1].perm, &dir);
		break;
	case Qdata1:
		devdir(c, c->qid, tab[2].name, qlen(p->q[1]), eve, tab[2].perm, &dir);
		break;
	default:
		panic("pipestat");
	}
	n = convD2M(&dir, db, n);
	if(n < BIT16SZ)
		error(Eshortstat);
	return n;
}

/*
 *  if the stream doesn't exist, create it
 */
static Chan*
pipeopen(Chan *c, int omode)
{
	Pipe *p;

	if(c->qid.type & QTDIR){
		if(omode != OREAD)
			error(Ebadarg);
		c->mode = omode;
		c->flag |= COPEN;
		c->offset = 0;
		return c;
	}

	openmode(omode);	/* check it */

	p = c->aux;
	qlock(p);
	if(waserror()){
		qunlock(p);
		nexterror();
	}
	switch(NETTYPE(c->qid.path)){
	case Qdata0:
		devpermcheck(p->user, p->pipedir[1].perm, omode);
		p->qref[0]++;
		break;
	case Qdata1:
		devpermcheck(p->user, p->pipedir[2].perm, omode);
		p->qref[1]++;
		break;
	}
	poperror();
	qunlock(p);

	c->mode = openmode(omode);
	c->flag |= COPEN;
	c->offset = 0;
	c->iounit = qiomaxatomic;
	return c;
}

static void
pipeclose(Chan *c)
{
	Pipe *p;

	p = c->aux;
	qlock(p);

	if(c->flag & COPEN){
		/*
		 *  closing either side hangs up the stream
		 */
		switch(NETTYPE(c->qid.path)){
		case Qdata0:
			p->qref[0]--;
			if(p->qref[0] == 0){
				qhangup(p->q[1], 0);
				qclose(p->q[0]);
			}
			break;
		case Qdata1:
			p->qref[1]--;
			if(p->qref[1] == 0){
				qhangup(p->q[0], 0);
				qclose(p->q[1]);
			}
			break;
		}
	}

	
	/*
	 *  if both sides are closed, they are reusable
	 */
	if(p->qref[0] == 0 && p->qref[1] == 0){
		qreopen(p->q[0]);
		qreopen(p->q[1]);
	}

	/*
	 *  free the structure on last close
	 */
	p->ref--;
	if(p->ref == 0){
		qunlock(p);
		freepipe(p);
	} else
		qunlock(p);
}

static long
piperead(Chan *c, void *va, long n, vlong)
{
	Pipe *p;

	p = c->aux;

	switch(NETTYPE(c->qid.path)){
	case Qdir:
		return devdirread(c, va, n, p->pipedir, nelem(pipedir), pipegen);
	case Qdata0:
		return qread(p->q[0], va, n);
	case Qdata1:
		return qread(p->q[1], va, n);
	default:
		panic("piperead");
	}
	return -1;	/* not reached */
}

static Block*
pipebread(Chan *c, long n, ulong offset)
{
	Pipe *p;

	p = c->aux;

	switch(NETTYPE(c->qid.path)){
	case Qdata0:
		return qbread(p->q[0], n);
	case Qdata1:
		return qbread(p->q[1], n);
	}

	return devbread(c, n, offset);
}

/*
 *  a write to a closed pipe causes an exception to be sent to
 *  the prog.
 */
static long
pipewrite(Chan *c, void *va, long n, vlong)
{
	Pipe *p;
	Prog *r;

	if(waserror()) {
		/* avoid exceptions when pipe is a mounted queue */
		if((c->flag & CMSG) == 0) {
			r = up->iprog;
			if(r != nil && r->kill == nil)
				r->kill = "write on closed pipe";
		}
		nexterror();
	}

	p = c->aux;

	switch(NETTYPE(c->qid.path)){
	case Qdata0:
		n = qwrite(p->q[1], va, n);
		break;

	case Qdata1:
		n = qwrite(p->q[0], va, n);
		break;

	default:
		panic("pipewrite");
	}

	poperror();
	return n;
}

static long
pipebwrite(Chan *c, Block *bp, ulong junk)
{
	long n;
	Pipe *p;
	Prog *r;

	USED(junk);
	if(waserror()) {
		/* avoid exceptions when pipe is a mounted queue */
		if((c->flag & CMSG) == 0) {
			r = up->iprog;
			if(r != nil && r->kill == nil)
				r->kill = "write on closed pipe";
		}
		nexterror();
	}

	p = c->aux;
	switch(NETTYPE(c->qid.path)){
	case Qdata0:
		n = qbwrite(p->q[1], bp);
		break;

	case Qdata1:
		n = qbwrite(p->q[0], bp);
		break;

	default:
		n = 0;
		panic("pipebwrite");
	}

	poperror();
	return n;
}

static int
pipewstat(Chan *c, uchar *dp, int n)
{
	Dir *d;
	Pipe *p;
	int d1;

	if (c->qid.type&QTDIR)
		error(Eperm);
	p = c->aux;
	if(strcmp(up->env->user, p->user) != 0)
		error(Eperm);
	d = smalloc(sizeof(*d)+n);
	if(waserror()){
		free(d);
		nexterror();
	}
	n = convM2D(dp, n, d, (char*)&d[1]);
	if(n == 0)
		error(Eshortstat);
	d1 = NETTYPE(c->qid.path) == Qdata1;
	if(!emptystr(d->name)){
		validwstatname(d->name);
		if(strlen(d->name) >= KNAMELEN)
			error(Efilename);
		if(strcmp(p->pipedir[1+!d1].name, d->name) == 0)
			error(Eexist);
		kstrcpy(p->pipedir[1+d1].name, d->name, KNAMELEN);
	}
	if(d->mode != ~0UL)
		p->pipedir[d1 + 1].perm = d->mode & 0777;
	poperror();
	free(d);
	return n;
}

Dev pipedevtab = {
	'|',
	"pipe",

	devreset,
	pipeinit,
	devshutdown,
	pipeattach,
	pipewalk,
	pipestat,
	pipeopen,
	devcreate,
	pipeclose,
	piperead,
	pipebread,
	pipewrite,
	pipebwrite,
	devremove,
	pipewstat,
};
