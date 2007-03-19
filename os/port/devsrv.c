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
struct SrvFile
{
	char*	spec;
	char*	name;
	char*	user;
	ulong		perm;
	vlong	length;
	Qid		qid;
	int		ref;
	int		opens;
	int		flags;
	Channel*	read;
	Channel*	write;
	SrvFile*	entry;
	SrvFile*	dir;
	SrvFile*	devlist;
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

Type	*Trdchan;
Type	*Twrchan;

static int
srvgen(Chan *c, char*, Dirtab*, int, int s, Dir *dp)
{
	SrvFile *f;

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
srvchkattach(SrvFile *d)
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

	if(spec[0] != '\0'){
		qlock(&dev.l);
		for(d = dev.devices; d != nil; d = d->devlist){
			if(strcmp(spec, d->spec) == 0){
				if(srvchkattach(d) == 0){
					qunlock(&dev.l);
					error(Eperm);
				}
				d->ref++;
				break;
			}
		}
		qunlock(&dev.l);

		if(d != nil){
			c = devattach('s', spec);
			c->aux = d;
			c->qid = d->qid;
			return c;
		}
	}

	d = malloc(sizeof(SrvFile));
	if(d == nil)
		error(Enomem);

	c = devattach('s', spec);

	d->ref = 1;
	kstrdup(&d->spec, spec);
	kstrdup(&d->user, up->env->user);
	snprint(up->genbuf, sizeof(up->genbuf), "srv%ld", up->env->pgrp->pgrpid);
	kstrdup(&d->name, up->genbuf);
	d->perm = DMDIR|0770;

	qlock(&dev.l);
	mkqid(&d->qid, dev.pathgen++, 0, QTDIR);
	d->devlist = dev.devices;
	dev.devices = d;
	qunlock(&dev.l);

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
srvputdir(SrvFile *sf)
{
	SrvFile **l, *d;

	sf->ref--;
	if(sf->ref != 0)
		return;

	for(l = &dev.devices; (d = *l) != nil; l = &d->devlist)
		if(d == sf){
			*l = d->devlist;
			break;
		}
	free(sf->spec);
	free(sf->user);
	free(sf->name);
	free(sf);
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
srvdecr(SrvFile *sf, int remove)
{
	SrvFile *f, **l;

	if(remove){
		l = &sf->dir->entry;
		for(f = *l; f != nil; f = f->entry){
			if(sf == f){
				*l = f->entry;
				break;
			}
			l = &f->entry;
		}
		sf->ref--;
		sf->flags |= SREMOVED;
	}

	if(sf->ref != 0)
		return;

	if(sf->dir != nil)
		srvputdir(sf->dir);

	free(sf->spec);
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
		srvdecr(sf, (sf->flags & SREMOVED) == 0);
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
		if (sf->read != H || sf->write != H)
			srvunblock(sf, c->fid);
	}

	sf->ref--;
	if(opens == 1){
		if((sf->flags & (SORCLOSE | SREMOVED)) == SORCLOSE)
			remove = 1;
	}

	noperm = 0;
	if(remove && strcmp(sf->dir->user, up->env->user) != 0){
		noperm = 1;
		remove = 0;
	}

	srvdecr(sf, remove);
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

static long
srvread(Chan *c, void *va, long count, vlong offset)
{
	int l;
	Heap * volatile h;
	Array *a;
	SrvFile *sp;
	Channel *rc;
	Channel *rd;
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
		error(Eshutdown);

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

	crecv(rc, r);
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
		error(Eshutdown);

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
	crecv(wc, w);
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
	h->t->ref--;
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
	for(f = s->entry; f != nil; f = f->entry){
		if(strcmp(f->name, file) == 0){
			qunlock(&dev.l);
			error(Eexist);
		}
	}

	f = malloc(sizeof(SrvFile));
	if(f == nil){
		qunlock(&dev.l);
		error(Enomem);
	}

	srvretype(io->read, f, Trdchan);
	srvretype(io->write, f, Twrchan);
	f->read = io->read;
	f->write = io->write;

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
