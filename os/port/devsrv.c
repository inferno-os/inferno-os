#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "../port/error.h"
#include "interp.h"
#include "isa.h"
#include "runt.h"

typedef struct SrvFile SrvFile;
typedef struct Pending Pending;

/* request pending to a server, in case a server vanishes */
struct Pending
{
	Pending*	next;
	Pending*	prev;
	int fid;
	Channel*	rc;
	Channel*	wc;
};

struct SrvFile
{
	char*	name;
	char*	user;
	ulong		perm;
	Qid		qid;
	int		ref;

	/* root directory */
	char*	spec;
	SrvFile*	devlist;
	SrvFile*	entry;

	/* file */
	int		opens;
	int		flags;
	vlong	length;
	Channel*	read;
	Channel*	write;
	SrvFile*	dir;		/* parent directory */
	Pending	waitlist;	/* pending requests from client opens */
};

enum
{
	SORCLOSE	= (1<<0),
	SRDCLOSE	= (1<<1),
	SWRCLOSE	= (1<<2),
	SREMOVED	= (1<<3),
};

typedef struct SrvDev SrvDev;
struct SrvDev
{
	Type*	Rread;
	Type*	Rwrite;
	QLock	l;
	ulong	pathgen;
	SrvFile*	devices;
};

static SrvDev dev;

void	freechan(Heap*, int);
static void	freerdchan(Heap*, int);
static void	freewrchan(Heap*, int);
static void delwaiting(Pending*);

Type	*Trdchan;
Type	*Twrchan;

static int
srvgen(Chan *c, char *name, Dirtab *tab, int ntab, int s, Dir *dp)
{
	SrvFile *f;

	USED(name);
	USED(tab);
	USED(ntab);

	if(s == DEVDOTDOT){
		devdir(c, c->qid, "#s", 0, eve, 0555, dp);
		return 1;
	}
	f = c->aux;
	if((c->qid.type & QTDIR) == 0){
		if(s > 0)
			return -1;
		devdir(c, f->qid, f->name, f->length, f->user, f->perm, dp);
		return 1;
	}

	for(f = f->entry; f != nil; f = f->entry){
		if(s-- == 0)
			break;
	}
	if(f == nil)
		return -1;

	devdir(c, f->qid, f->name, f->length, f->user, f->perm, dp);
	return 1;
}

static void
srvinit(void)
{
	static uchar rmap[] = Sys_Rread_map;
	static uchar wmap[] = Sys_Rwrite_map;

	Trdchan = dtype(freerdchan, sizeof(Channel), Tchannel.map, Tchannel.np);
	Twrchan = dtype(freewrchan, sizeof(Channel), Tchannel.map, Tchannel.np);

	dev.pathgen = 1;
	dev.Rread = dtype(freeheap, Sys_Rread_size, rmap, sizeof(rmap));
	dev.Rwrite = dtype(freeheap, Sys_Rwrite_size, wmap, sizeof(wmap));
}

static int
srvcanattach(SrvFile *d)
{
	if(strcmp(d->user, up->env->user) == 0)
		return 1;

	/*
	 * Need write permission in other to allow attaches if
	 * we are not the owner
	 */
	if(d->perm & 2)
		return 1;

	return 0;
}

static Chan*
srvattach(char *spec)
{
	Chan *c;
	SrvFile *d;
	char srvname[16];

	qlock(&dev.l);
	if(waserror()){
		qunlock(&dev.l);
		nexterror();
	}

	if(spec[0] != '\0'){
		for(d = dev.devices; d != nil; d = d->devlist){
			if(strcmp(spec, d->spec) == 0){
				if(!srvcanattach(d))
					error(Eperm);
				c = devattach('s', spec);
				c->aux = d;
				c->qid = d->qid;
				d->ref++;
				poperror();
				qunlock(&dev.l);
				return c;
			}
		}
	}

	d = malloc(sizeof(SrvFile));
	if(d == nil)
		error(Enomem);

	d->ref = 1;
	kstrdup(&d->spec, spec);
	kstrdup(&d->user, up->env->user);
	snprint(srvname, sizeof(srvname), "srv%ld", up->env->pgrp->pgrpid);
	kstrdup(&d->name, srvname);
	d->perm = DMDIR|0770;
	mkqid(&d->qid, dev.pathgen++, 0, QTDIR);

	d->devlist = dev.devices;
	dev.devices = d;

	poperror();
	qunlock(&dev.l);

	c = devattach('s', spec);
	c->aux = d;
	c->qid = d->qid;

	return c;
}

static Walkqid*
srvwalk(Chan *c, Chan *nc, char **name, int nname)
{
	SrvFile *d, *pd;
	Walkqid *w;

	pd = c->aux;
	qlock(&dev.l);
	if(waserror()){
		qunlock(&dev.l);
		nexterror();
	}

	w = devwalk(c, nc, name, nname, nil, 0, srvgen);
	if(w != nil && w->clone != nil){
		if(nname != 0){
			for(d = pd->entry; d != nil; d = d->entry)
				if(d->qid.path == w->clone->qid.path)
					break;
			if(d == nil)
				panic("srvwalk");
			if(w->clone == c)
				pd->ref--;
		}else
			d = pd;
		w->clone->aux = d;
		d->ref++;
	}

	poperror();
	qunlock(&dev.l);
	return w;
}

static int
srvstat(Chan *c, uchar *db, int n)
{
	qlock(&dev.l);
	if(waserror()){
		qunlock(&dev.l);
		nexterror();
	}
	n = devstat(c, db, n, 0, 0, srvgen);
	poperror();
	qunlock(&dev.l);
	return n;
}

static Chan*
srvopen(Chan *c, int omode)
{
	SrvFile *sf;

	openmode(omode);	/* check it */
	if(c->qid.type & QTDIR){
		if(omode != OREAD)
			error(Eisdir);
		c->mode = omode;
		c->flag |= COPEN;
		c->offset = 0;
		return c;
	}

	sf = c->aux;

	qlock(&dev.l);
	if(waserror()){
		qunlock(&dev.l);
		nexterror();
	}
	devpermcheck(sf->user, sf->perm, omode);
	if(omode&ORCLOSE && strcmp(sf->user, up->env->user) != 0)
		error(Eperm);
	if(sf->perm & DMEXCL && sf->opens != 0)
		error(Einuse);
	sf->opens++;
	if(omode&ORCLOSE)
		sf->flags |= SORCLOSE;
	poperror();
	qunlock(&dev.l);

	c->offset = 0;
	c->flag |= COPEN;
	c->mode = openmode(omode);

	return c;
}

static int
srvwstat(Chan *c, uchar *dp, int n)
{
	Dir *d;
	SrvFile *sf, *f;

	sf = c->aux;
	if(strcmp(up->env->user, sf->user) != 0)
		error(Eperm);

	d = smalloc(sizeof(*d)+n);
	if(waserror()){
		free(d);
		nexterror();
	}
	n = convM2D(dp, n, d, (char*)&d[1]);
	if(n == 0)
		error(Eshortstat);
	if(!emptystr(d->name)){
		if(sf->dir == nil)
			error(Eperm);
		validwstatname(d->name);
		qlock(&dev.l);
		for(f = sf->dir; f != nil; f = f->entry)
			if(strcmp(f->name, d->name) == 0){
				qunlock(&dev.l);
				error(Eexist);
			}
		kstrdup(&sf->name, d->name);
		qunlock(&dev.l);
	}
	if(d->mode != ~0UL)
		sf->perm = d->mode & (DMEXCL|DMAPPEND|0777);
	if(d->length != (vlong)-1)
		sf->length = d->length;
	poperror();
	free(d);
	return n;
}

static void
srvputdir(SrvFile *dir)
{
	SrvFile **l, *d;

	dir->ref--;
	if(dir->ref != 0)
		return;

	for(l = &dev.devices; (d = *l) != nil; l = &d->devlist)
		if(d == dir){
			*l = d->devlist;
			break;
		}
	free(dir->spec);
	free(dir->user);
	free(dir->name);
	free(dir);
}

static void
srvunblock(SrvFile *sf, int fid)
{
	Channel *d;
	Sys_FileIO_read rreq;
	Sys_FileIO_write wreq;

	acquire();
	if(waserror()){
		release();
		nexterror();
	}
	d = sf->read;
	if(d != H){
		rreq.t0 = 0;
		rreq.t1 = 0;
		rreq.t2 = fid;
		rreq.t3 = H;
		csendalt(d, &rreq, d->mid.t, -1);
	}

	d = sf->write;
	if(d != H){
		wreq.t0 = 0;
		wreq.t1 = H;
		wreq.t2 = fid;
		wreq.t3 = H;
		csendalt(d, &wreq, d->mid.t, -1);
	}
	poperror();
	release();
}

static void
srvcancelreqs(SrvFile *sf)
{
	Pending *w, *ws;
	Sys_Rread rreply;
	Sys_Rwrite wreply;

	acquire();
	ws = &sf->waitlist;
	while((w = ws->next) != ws){
		delwaiting(w);
		if(waserror() == 0){
			if(w->rc != nil){
				rreply.t0 = H;
				rreply.t1 = c2string(Ehungup, strlen(Ehungup));
				csend(w->rc, &rreply);
			}
			if(w->wc != nil){
				wreply.t0 = 0;
				wreply.t1 = c2string(Ehungup, strlen(Ehungup));
				csend(w->wc, &wreply);
			}
			poperror();
		}
	}
	release();
}

static void
srvdelete(SrvFile *sf)
{
	SrvFile *f, **l;

	if((sf->flags & SREMOVED) == 0){
		for(l = &sf->dir->entry; (f = *l) != nil; l = &f->entry){
			if(sf == f){
				*l = f->entry;
				break;
			}
		}
		sf->ref--;
		sf->flags |= SREMOVED;
	}
}

static void
srvchkref(SrvFile *sf)
{
	if(sf->ref != 0)
		return;

	if(sf->dir != nil)
		srvputdir(sf->dir);

	free(sf->user);
	free(sf->name);
	free(sf);
}

static void
srvfree(SrvFile *sf, int flag)
{
	sf->flags |= flag;
	if((sf->flags & (SRDCLOSE | SWRCLOSE)) == (SRDCLOSE | SWRCLOSE)){
		sf->ref--;
		srvdelete(sf);
		/* no further requests can arrive; return error to pending requests */
		srvcancelreqs(sf);
		srvchkref(sf);
	}
}

static void
freerdchan(Heap *h, int swept)
{
	SrvFile *sf;

	release();
	qlock(&dev.l);
	sf = H2D(Channel*, h)->aux;
	sf->read = H;
	srvfree(sf, SRDCLOSE);
	qunlock(&dev.l);
	acquire();

	freechan(h, swept);
}

static void
freewrchan(Heap *h, int swept)
{
	SrvFile *sf;

	release();
	qlock(&dev.l);
	sf = H2D(Channel*, h)->aux;
	sf->write = H;
	srvfree(sf, SWRCLOSE);
	qunlock(&dev.l);
	acquire();

	freechan(h, swept);
}

static void
srvclunk(Chan *c, int remove)
{
	int opens, noperm;
	SrvFile *sf;

	sf = c->aux;
	qlock(&dev.l);
	if(c->qid.type & QTDIR){
		srvputdir(sf);
		qunlock(&dev.l);
		if(remove)
			error(Eperm);
		return;
	}
	opens = 0;
	if(c->flag & COPEN){
		opens = sf->opens--;
		if(sf->read != H || sf->write != H)
			srvunblock(sf, c->fid);
	}

	sf->ref--;
	if(opens == 1){
		if(sf->flags & SORCLOSE)
			remove = 1;
	}

	noperm = 0;
	if(remove && strcmp(sf->dir->user, up->env->user) != 0){
		noperm = 1;
		remove = 0;
	}
	if(remove)
		srvdelete(sf);
	srvchkref(sf);
	qunlock(&dev.l);

	if(noperm)
		error(Eperm);
}

static void
srvclose(Chan *c)
{
	srvclunk(c, 0);
}

static void
srvremove(Chan *c)
{
	srvclunk(c, 1);
}

static void
addwaiting(SrvFile *sp, Pending *w)
{
	Pending *sw;

	sw = &sp->waitlist;
	w->next = sw;
	w->prev = sw->prev;
	sw->prev->next = w;
	sw->prev = w;
}

static void
delwaiting(Pending *w)
{
	w->next->prev = w->prev;
	w->prev->next = w->next;
}

static long
srvread(Chan *c, void *va, long count, vlong offset)
{
	int l;
	Heap * volatile h;
	Array *a;
	SrvFile *sp;
	Channel *rc;
	Channel *rd;
	Pending wait;
	Sys_Rread * volatile r;
	Sys_FileIO_read req;

	if(c->qid.type & QTDIR){
		qlock(&dev.l);
		if(waserror()){
			qunlock(&dev.l);
			nexterror();
		}
		l = devdirread(c, va, count, 0, 0, srvgen);
		poperror();
		qunlock(&dev.l);
		return l;
	}

	sp = c->aux;

	acquire();
	if(waserror()){
		release();
		nexterror();
	}

	rd = sp->read;
	if(rd == H)
		error(Ehungup);

	rc = cnewc(dev.Rread, movtmp, 1);
	ptradd(D2H(rc));
	if(waserror()){
		ptrdel(D2H(rc));
		destroy(rc);
		nexterror();
	}

	req.t0 = offset;
	req.t1 = count;
	req.t2 = c->fid;
	req.t3 = rc;
	csend(rd, &req);

	h = heap(dev.Rread);
	r = H2D(Sys_Rread *, h);
	ptradd(h);
	if(waserror()){
		ptrdel(h);
		destroy(r);
		nexterror();
	}

	wait.fid = c->fid;
	wait.rc = rc;
	wait.wc = nil;
	addwaiting(sp, &wait);
	if(waserror()){
		delwaiting(&wait);
		nexterror();
	}
	crecv(rc, r);
	poperror();
	delwaiting(&wait);

	if(r->t1 != H)
		error(string2c(r->t1));

	a = r->t0;
	l = 0;
	if(a != H){
		l = a->len;
		if(l > count)
			l = count;
		memmove(va, a->data, l);
	}

	poperror();
	ptrdel(h);
	destroy(r);

	poperror();
	ptrdel(D2H(rc));
	destroy(rc);

	poperror();
	release();

	return l;
}

static long
srvwrite(Chan *c, void *va, long count, vlong offset)
{
	long l;
	Heap * volatile h;
	SrvFile *sp;
	Channel *wc;
	Channel *wr;
	Pending wait;
	Sys_Rwrite * volatile w;
	Sys_FileIO_write req;

	if(c->qid.type & QTDIR)
		error(Eperm);

	acquire();
	if(waserror()){
		release();
		nexterror();
	}

	sp = c->aux;
	wr = sp->write;
	if(wr == H)
		error(Ehungup);

	wc = cnewc(dev.Rwrite, movtmp, 1);
	ptradd(D2H(wc));
	if(waserror()){
		ptrdel(D2H(wc));
		destroy(wc);
		nexterror();
	}

	req.t0 = offset;
	req.t1 = mem2array(va, count);
	req.t2 = c->fid;
	req.t3 = wc;

	ptradd(D2H(req.t1));

	if(waserror()){
		ptrdel(D2H(req.t1));
		destroy(req.t1);
		nexterror();
	}

	csend(wr, &req);

	poperror();
	ptrdel(D2H(req.t1));
	destroy(req.t1);

	h = heap(dev.Rwrite);
	w = H2D(Sys_Rwrite *, h);
	ptradd(h);

	if(waserror()){
		ptrdel(h);
		destroy(w);
		nexterror();
	}

	wait.fid = c->fid;
	wait.rc = nil;
	wait.wc = wc;
	addwaiting(sp, &wait);
	if(waserror()){
		delwaiting(&wait);
		nexterror();
	}
	crecv(wc, w);
	poperror();
	delwaiting(&wait);

	if(w->t1 != H)
		error(string2c(w->t1));
	poperror();
	ptrdel(h);
	l = w->t0;
	destroy(w);

	poperror();
	ptrdel(D2H(wc));
	destroy(wc);

	poperror();
	release();
	if(l < 0)
		l = 0;
	return l;
}

static void
srvretype(Channel *c, SrvFile *f, Type *t)
{
	Heap *h;

	h = D2H(c);
	freetype(h->t);
	h->t = t;
	t->ref++;
	c->aux = f;
}

int
srvf2c(char *dir, char *file, Sys_FileIO *io)
{
	SrvFile *s, *f;
	volatile struct { Chan *c; } c;

	c.c = nil;
	if(waserror()){
		cclose(c.c);
		return -1;
	}

	if(strchr(file, '/') != nil || strlen(file) >= 64 || strcmp(file, ".") == 0 || strcmp(file, "..") == 0)
		error(Efilename);

	c.c = namec(dir, Aaccess, 0, 0);
	if((c.c->qid.type&QTDIR) == 0 || devtab[c.c->type]->dc != 's')
		error("directory not a srv device");

	s = c.c->aux;

	qlock(&dev.l);
	if(waserror()){
		qunlock(&dev.l);
		nexterror();
	}
	for(f = s->entry; f != nil; f = f->entry){
		if(strcmp(f->name, file) == 0)
			error(Eexist);
	}

	f = malloc(sizeof(SrvFile));
	if(f == nil)
		error(Enomem);

	srvretype(io->read, f, Trdchan);
	srvretype(io->write, f, Twrchan);
	f->read = io->read;
	f->write = io->write;
	
	f->waitlist.next = &f->waitlist;
	f->waitlist.prev = &f->waitlist;

	kstrdup(&f->name, file);
	kstrdup(&f->user, up->env->user);
	f->perm = 0666 & (~0666 | (s->perm & 0666));
	f->length = 0;
	f->ref = 2;
	mkqid(&f->qid, dev.pathgen++, 0, QTFILE);

	f->entry = s->entry;
	s->entry = f;
	s->ref++;
	f->dir = s;
	poperror();
	qunlock(&dev.l);

	cclose(c.c);
	poperror();

	return 0;
}

Dev srvdevtab = {
	's',
	"srv",

	devreset,
	srvinit,
	devshutdown,
	srvattach,
	srvwalk,
	srvstat,
	srvopen,
	devcreate,
	srvclose,
	srvread,
	devbread,
	srvwrite,
	devbwrite,
	srvremove,
	srvwstat
};
