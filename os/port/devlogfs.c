#ifndef EMU
#include "u.h"
#include "../port/lib.h"
#include "../port/error.h"
#include "mem.h"
#else
#include	"error.h"
#endif
#include	"dat.h"
#include	"fns.h"
#include	"kernel.h"
#include	"logfs.h"
#include	"nandfs.h"

#ifndef EMU
#define Sleep sleep
#define Wakeup wakeup
#endif

typedef struct Devlogfs Devlogfs;
typedef struct DevlogfsSession DevlogfsSession;

//#define CALLTRACE

enum {
	DEVLOGFSDEBUG = 0,
	DEVLOGFSIODEBUG = 0,
	DEVLOGFSBAD = 1,
};

enum {
	Qdir,
	Qctl,
	Qusers,
	Qdump,
	Qfs,
	Qfsboot,
	Qend,
};

typedef enum DevlogfsServerState { Closed, BootOpen, NeedVersion, NeedAttach, Attached, Hungup } DevlogfsServerState;

struct Devlogfs {
	QLock qlock;
	QLock	rlock;
	QLock	wlock;
	Ref ref;
	int instance;
	int trace;	/* (debugging) trace of read/write actions */
	int nand;
	char *name;
	char *device;
	char *filename[Qend - Qfs];
	LogfsLowLevel *ll;
	Chan *flash, *flashctl;
	QLock bootqlock;
	int logfstrace;
	LogfsBoot *lb;
	/* stuff for server */
	ulong openflags;
	Fcall in;
	Fcall out;
	int reading;
	DevlogfsServerState state;
	Rendez readrendez;
	Rendez writerendez;
	uint readcount;
	ulong readbufsize;
	uchar *readbuf;
	uchar *readp;
	LogfsServer *server;
	Devlogfs *next;
};

#define MAXMSIZE 8192

static struct {
	RWlock rwlock;		/* rlock when walking, wlock when changing */
	QLock configqlock;		/* serialises addition of new configurations */
	Devlogfs *head;
	char *defname;
} devlogfslist;

static LogfsIdentityStore *is;

#ifndef EMU
char Eunknown[] = "unknown user or group id";
#endif

static	void	devlogfsfree(Devlogfs*);

#define SPLITPATH(path, qtype, instance, qid, qt) { instance = path >> 4; qid = path & 0xf; qt = qtype & QTDIR; }
#define DATAQID(q, qt) (!(qt) && (q) >= Qfs && (q) < Qend)
#define MKPATH(instance, qid) ((instance << 4) | qid)

#define PREFIX "logfs"

static char *devlogfsprefix = PREFIX;
static char *devlogfsctlname = PREFIX "ctl";
static char *devlogfsusersname = PREFIX "users";
static char *devlogfsdumpname = PREFIX "dump";
static char *devlogfsbootsuffix = "boot";
static char *devlogfs9pversion = "9P2000";

static void
errorany(char *errmsg)
{
	if (errmsg)
		error(errmsg);
}

static void *
emalloc(ulong size)
{
	void *p;
	p = logfsrealloc(nil, size);
	if (p == nil)
		error(Enomem);
	return p;
}

static char *
estrdup(char *q)
{
	void *p;
	if (q == nil)
		return nil;
	p = logfsrealloc(nil, strlen(q) + 1);
	if (p == nil)
		error(Enomem);
	return strcpy(p, q);
}

static char *
estrconcat(char *a, ...)
{
	va_list l;
	char *p, *r;
	int t;

	t = strlen(a);
	va_start(l, a);
	while ((p = va_arg(l, char *)) != nil)
		t += strlen(p);

	r = logfsrealloc(nil, t + 1);
	if (r == nil)
		error(Enomem);

	strcpy(r, a);
	va_start(l, a);
	while ((p = va_arg(l, char *)) != nil)
		strcat(r, p);

	va_end(l);

	return r;
}

static int
gen(Chan *c, int i, Dir *dp, int lockit)
{
	Devlogfs *l;
	long size;
	Qid qid;
	qid.vers = 0;
	qid.type = 0;

	if (i + Qctl < Qfs) {
		switch (i + Qctl) {
		case Qctl:
			qid.path = Qctl;
			devdir(c, qid, devlogfsctlname, 0, eve, 0666, dp);
			return 1;
		case Qusers:
			qid.path = Qusers;
			devdir(c, qid, devlogfsusersname, 0, eve, 0444, dp);
			return 1;
		case Qdump:
			qid.path = Qdump;
			devdir(c, qid, devlogfsdumpname, 0, eve, 0444, dp);
			return 1;
		}
	}

	i -= Qfs - Qctl;

	if (lockit)
		rlock(&devlogfslist.rwlock);

	if (waserror()) {
		if (lockit)
			runlock(&devlogfslist.rwlock);
		nexterror();
	}

	for (l = devlogfslist.head; l; l = l->next) {
		if (i < Qend - Qfs)
			break;
		i -= Qend - Qfs;
	}

	if (l == nil) {
		poperror();
		if (lockit)
			runlock(&devlogfslist.rwlock);
		return -1;
	}

	switch (Qfs + i) {
	case Qfsboot:
		size = l->lb ? logfsbootgetsize(l->lb) : 0;
		break;
	default:
		size = 0;
		break;
	}
	/* perhaps the user id should come from the underlying file */
	qid.path = MKPATH(l->instance, Qfs + i);
	devdir(c, qid, l->filename[i], size, eve, 0666, dp);

	poperror();
	if (lockit)
		runlock(&devlogfslist.rwlock);

	return 1;
}

static int
devlogfsgen(Chan *c, char *n, Dirtab *tab, int ntab, int i, Dir *dp)
{
	USED(n);
	USED(tab);
	USED(ntab);
	return gen(c, i, dp, 1);
}

static int
devlogfsgennolock(Chan *c, char *n, Dirtab *tab, int ntab, int i, Dir *dp)
{
	USED(n);
	USED(tab);
	USED(ntab);
	return gen(c, i, dp, 0);
}

/* called under lock */
static Devlogfs *
devlogfsfind(int instance)
{
	Devlogfs *l;

	for (l = devlogfslist.head; l; l = l->next)
		if (l->instance == instance)
			break;
	return l;
}

static Devlogfs *
devlogfsget(int instance)
{
	Devlogfs *l;
	rlock(&devlogfslist.rwlock);
	for (l = devlogfslist.head; l; l = l->next)
		if (l->instance == instance)
			break;
	if (l)
		incref(&l->ref);
	runlock(&devlogfslist.rwlock);
	return l;
}

static Devlogfs *
devlogfsfindbyname(char *name)
{
	Devlogfs *l;

	rlock(&devlogfslist.rwlock);
	for (l = devlogfslist.head; l; l = l->next)
		if (strcmp(l->name, name) == 0)
			break;
	runlock(&devlogfslist.rwlock);
	return l;
}

static Devlogfs *
devlogfssetdefname(char *name)
{
	Devlogfs *l;
	char *searchname;
	wlock(&devlogfslist.rwlock);
	if (waserror()) {
		wunlock(&devlogfslist.rwlock);
		nexterror();
	}
	if (name == nil)
		searchname = devlogfslist.defname;
	else
		searchname = name;
	for (l = devlogfslist.head; l; l = l->next)
		if (strcmp(l->name, searchname) == 0)
			break;
	if (l == nil) {
		logfsfreemem(devlogfslist.defname);
		devlogfslist.defname = nil;
	}
	else if (name) {
		if (devlogfslist.defname) {
			logfsfreemem(devlogfslist.defname);
			devlogfslist.defname = nil;
		}
		devlogfslist.defname = estrdup(name);
	}
	poperror();
	wunlock(&devlogfslist.rwlock);
	return l;
}

static Chan *
devlogfskopen(char *name, char *suffix, int mode)
{
	Chan *c;
	char *fn;
	int fd;

	fn = estrconcat(name, suffix, 0);
	fd = kopen(fn, mode);
	logfsfreemem(fn);
	if (fd < 0)
		error(up->env->errstr);
	c = fdtochan(up->env->fgrp, fd, mode, 0, 1);
	kclose(fd);
	return c;
}

static char *
xread(void *a, void *buf, long nbytes, ulong offset)
{
	Devlogfs *l = a;
	long rv;

	if (DEVLOGFSIODEBUG || l->trace)
		print("devlogfs: %s: read(0x%lux, %ld)\n", l->device, offset, nbytes);
	l->flash->offset = offset;
	rv = kchanio(l->flash, buf, nbytes, OREAD);
	if (rv < 0) {
		print("devlogfs: %s: flash read error: %s\n", l->device, up->env->errstr);
		return up->env->errstr;
	}
	if (rv != nbytes) {
		print("devlogfs: %s: short flash read: offset %lud, %ld not %ld\n", l->device, offset, rv, nbytes);
		return "short read";
	}
	return nil;
}

static char *
xwrite(void *a, void *buf, long nbytes, ulong offset)
{
	Devlogfs *l = a;
	long rv;

	if (DEVLOGFSIODEBUG || l->trace)
		print("devlogfs: %s: write(0x%lux, %ld)\n", l->device, offset, nbytes);
	l->flash->offset = offset;
	rv = kchanio(l->flash, buf, nbytes, OWRITE);
	if (rv < 0) {
		print("devlogfs: %s: flash write error: %s\n", l->device, up->env->errstr);
		return up->env->errstr;
	}
	if (rv != nbytes) {
		print("devlogfs: %s: short flash write: offset %lud, %ld not %ld\n", l->device, offset, rv, nbytes);
		return "short write";
	}
	return nil;
}

static char *
xerase(void *a, long address)
{
	Devlogfs *l = a;
	char cmd[40];

	if (DEVLOGFSIODEBUG || l->trace)
		print("devlogfs: %s: erase(0x%lux)\n", l->device, address);
	snprint(cmd, sizeof(cmd), "erase 0x%8.8lux", address);
	if (kchanio(l->flashctl, cmd, strlen(cmd), OWRITE) <= 0) {
		print("devlogfs: %s: flash erase error: %s\n", l->device, up->env->errstr);
		return up->env->errstr;
	}
	return nil;
}

static char *
xsync(void *a)
{
	Devlogfs *l = a;

	if (DEVLOGFSIODEBUG || l->trace)
		print("devlogfs: %s: sync()\n", l->device);
	if (kchanio(l->flashctl, "sync", 4, OWRITE) <= 0){
		print("devlogfs: %s: flash sync error: %s\n", l->device, up->env->errstr);
		return up->env->errstr;
	}
	return nil;
}

//#define LEAKHUNT
#ifdef LEAKHUNT
#define MAXLIVE 2000
typedef struct Live {
	void *p;
	int freed;
	ulong callerpc;
} Live;

static Live livemem[MAXLIVE];

static void
leakalloc(void *p, ulong callerpc)
{
	int x;
	int use = -1;
	for (x = 0; x < MAXLIVE; x++) {
		if (livemem[x].p == p) {
			if (!livemem[x].freed)
				print("leakalloc: unexpected realloc of 0x%.8lux from 0x%.8lux\n", p, callerpc);
//			else
//				print("leakalloc: reusing address 0x%.8lux from 0x%.8lux\n", p, callerpc);
			livemem[x].freed = 0;
			livemem[x].callerpc = callerpc;
			return;
		}
		else if (use < 0 && livemem[x].p == 0)
			use = x;
	}
	if (use < 0)
		panic("leakalloc: too many live entries");
	livemem[use].p = p;
	livemem[use].freed = 0;
	livemem[use].callerpc = callerpc;
}

static void
leakaudit(void)
{
	int x;
	for (x = 0; x < MAXLIVE; x++) {
		if (livemem[x].p && !livemem[x].freed)
			print("leakaudit: 0x%.8lux from 0x%.8lux\n", livemem[x].p, livemem[x].callerpc);
	}
}

static void
leakfree(void *p, ulong callerpc)
{
	int x;
	if (p == nil)
		return;
	for (x = 0; x < MAXLIVE; x++) {
		if (livemem[x].p == p) {
			if (livemem[x].freed)
				print("leakfree: double free of 0x%.8lux from 0x%.8lux, originally by 0x%.8lux\n",
					p, callerpc, livemem[x].callerpc);
			livemem[x].freed = 1;
			livemem[x].callerpc = callerpc;
			return;
		}
	}
	print("leakfree: free of unalloced address 0x%.8lux from 0x%.8lux\n", p, callerpc);
	leakaudit();
}

static void
leakrealloc(void *newp, void *oldp, ulong callerpc)
{
	leakfree(oldp, callerpc);
	leakalloc(newp, callerpc);
}
#endif


#ifdef LEAKHUNT
static void *_realloc(void *p, ulong size, ulong callerpc)
#else
void *
logfsrealloc(void *p, ulong size)
#endif
{
	void *q;
	ulong osize;
	if (waserror()) {
		print("wobbly thrown in memory allocator: %s\n", up->env->errstr);
		nexterror();
	}
	if (p == nil) {
		q = smalloc(size);
		poperror();
#ifdef LEAKHUNT
		leakrealloc(q, nil, callerpc);
#endif
		return q;
	}
	q = realloc(p, size);
	if (q) {
		poperror();
#ifdef LEAKHUNT
		leakrealloc(q, p, callerpc);
#endif
		return q;
	}
	q = smalloc(size);
	osize = msize(p);
	if (osize > size)
		osize = size;
	memmove(q, p, osize);
	free(p);
	poperror();
#ifdef LEAKHUNT
	leakrealloc(q, p, callerpc);
#endif
	return q;
}

#ifdef LEAKHUNT
void *
logfsrealloc(void *p, ulong size)
{
	return _realloc(p, size, getcallerpc(&p));
}

void *
nandfsrealloc(void *p, ulong size)
{
	return _realloc(p, size, getcallerpc(&p));
}
#else
void *
nandfsrealloc(void *p, ulong size)
{
	return logfsrealloc(p, size);
}
#endif

void
logfsfreemem(void *p)
{
#ifdef LEAKHUNT
	leakfree(p, getcallerpc(&p));
#endif
	free(p);
}

void
nandfsfreemem(void *p)
{
#ifdef LEAKHUNT
	leakfree(p, getcallerpc(&p));
#endif
	free(p);
}

static Devlogfs *
devlogfsconfig(char *name, char *device)
{
	Devlogfs *newl, *l;
	int i;
	int n;
	char buf[100], *fields[12];
	long rawblocksize, rawsize;

	newl = nil;

	qlock(&devlogfslist.configqlock);

	if (waserror()) {
		qunlock(&devlogfslist.configqlock);
		devlogfsfree(newl);
		nexterror();
	}

	rlock(&devlogfslist.rwlock);
	for (l = devlogfslist.head; l; l = l->next)
		if (strcmp(l->name, name) == 0) {
			runlock(&devlogfslist.rwlock);
			error(Einuse);
		}

	/* horrid n^2 solution to finding a unique instance number */

	for (i = 0;; i++) {
		for (l = devlogfslist.head; l; l = l->next)
			if (l->instance == i)
				break;
		if (l == nil)
			break;
	}
	runlock(&devlogfslist.rwlock);

	newl = emalloc(sizeof(Devlogfs));
	newl->instance = i;
	newl->name = estrdup(name);
	newl->device = estrdup(device);
	newl->filename[Qfs - Qfs] = estrconcat(devlogfsprefix, name, nil);
	newl->filename[Qfsboot - Qfs] = estrconcat(devlogfsprefix, name, devlogfsbootsuffix, nil);
	newl->flash = devlogfskopen(device, nil, ORDWR);
	newl->flashctl = devlogfskopen(device, "ctl", ORDWR);
	newl->flashctl->offset = 0;
	if ((n = kchanio(newl->flashctl, buf, sizeof(buf), OREAD)) <= 0) {
		print("devlogfsconfig: read ctl failed: %s\n", up->env->errstr);
		error(up->env->errstr);
	}

	if (n >= sizeof(buf))
		n = sizeof(buf) - 1;
	buf[n] = 0;
	n = tokenize(buf, fields, nelem(fields));
	if(n < 7)
		error("unexpected flashctl format");
	newl->nand = strcmp(fields[3], "nand") == 0;
	rawblocksize = strtol(fields[6], nil, 0);
	rawsize = strtol(fields[5], nil, 0)-strtol(fields[4], nil, 0);
	if(newl->nand == 0)
		error("only NAND supported at the moment");
	errorany(nandfsinit(newl, rawsize, rawblocksize, xread, xwrite, xerase, xsync, &newl->ll));
	wlock(&devlogfslist.rwlock);
	newl->next = devlogfslist.head;
	devlogfslist.head = newl;
	logfsfreemem(devlogfslist.defname);
	devlogfslist.defname = nil;
	if (!waserror()){
		devlogfslist.defname = estrdup(name);
		poperror();
	}
	wunlock(&devlogfslist.rwlock);
	poperror();
	qunlock(&devlogfslist.configqlock);
	return newl;
}

static void
devlogfsunconfig(Devlogfs *devlogfs)
{
	Devlogfs **lp;

	qlock(&devlogfslist.configqlock);

	if (waserror()) {
		qunlock(&devlogfslist.configqlock);
		nexterror();
	}

	wlock(&devlogfslist.rwlock);

	if (waserror()) {
		wunlock(&devlogfslist.rwlock);
		nexterror();
	}

	for (lp = &devlogfslist.head; *lp && (*lp) != devlogfs; lp = &(*lp)->next)
		;
	if (*lp == nil) {
		if (DEVLOGFSBAD)
			print("devlogfsunconfig: not in list\n");
	}
	else
		*lp = devlogfs->next;

	poperror();
	wunlock(&devlogfslist.rwlock);

	/* now invisible to the naked eye */
	devlogfsfree(devlogfs);
	poperror();
	qunlock(&devlogfslist.configqlock);
}

static void
devlogfsllopen(Devlogfs *l)
{
	qlock(&l->qlock);
	if (waserror()) {
		qunlock(&l->qlock);
		nexterror();
	}
	if (l->lb == nil)
		errorany(logfsbootopen(l->ll, 0, 0, l->logfstrace, 1, &l->lb));
	l->state = BootOpen;
	poperror();
	qunlock(&l->qlock);
}

static void
devlogfsllformat(Devlogfs *l, long bootsize)
{
	qlock(&l->qlock);
	if (waserror()) {
		qunlock(&l->qlock);
		nexterror();
	}
	if (l->lb == nil)
		errorany(logfsformat(l->ll, 0, 0, bootsize, l->logfstrace));
	poperror();
	qunlock(&l->qlock);
}

static Chan *
devlogfsattach(char *spec)
{
	Chan *c;
#ifdef CALLTRACE
	print("devlogfsattach(spec = %s) - start\n", spec);
#endif
	/* create the identity store on first attach */
	if (is == nil)
		errorany(logfsisnew(&is));
	c =  devattach(0x29f, spec);
//	c =  devattach(L'ʟ', spec);
#ifdef CALLTRACE
	print("devlogfsattach(spec = %s) - return %.8lux\n", spec, (ulong)c);
#endif
	return c;
}

static Walkqid*
devlogfswalk(Chan *c, Chan *nc, char **name, int nname)
{
	int instance, qid, qt, clone;
	Walkqid *wq;

#ifdef CALLTRACE
	print("devlogfswalk(c = 0x%.8lux, nc = 0x%.8lux, name = 0x%.8lux, nname = %d) - start\n",
		(ulong)c, (ulong)nc, (ulong)name, nname);
#endif
	clone = 0;
	if(nc == nil){
		nc = devclone(c);
		nc->type = 0;
		SPLITPATH(c->qid.path, c->qid.type, instance, qid, qt);
		if(DATAQID(qid, qt))
			nc->aux = devlogfsget(instance);
		clone = 1;
	}
	wq = devwalk(c, nc, name, nname, 0, 0, devlogfsgen);
	if (wq == nil || wq->nqid < nname) {
		if(clone)
			cclose(nc);
	}
	else if (clone) {
		wq->clone = nc;
		nc->type = c->type;
	}
#ifdef CALLTRACE
	print("devlogfswalk(c = 0x%.8lux, nc = 0x%.8lux, name = 0x%.8lux, nname = %d) - return\n",
		(ulong)c, (ulong)nc, (ulong)name, nname);
#endif
	return wq;
}

static int
devlogfsstat(Chan *c, uchar *dp, int n)
{
#ifdef CALLTRACE
	print("devlogfsstat(c = 0x%.8lux, dp = 0x%.8lux n= %d)\n",
		(ulong)c, (ulong)dp, n);
#endif
	return devstat(c, dp, n, 0, 0, devlogfsgen);
}

static Chan*
devlogfsopen(Chan *c, int omode)
{
	int instance, qid, qt;

	omode = openmode(omode);
	SPLITPATH(c->qid.path, c->qid.type, instance, qid, qt);
#ifdef CALLTRACE
	print("devlogfsopen(c = 0x%.8lux, omode = %o, instance = %d, qid = %d, qt = %d)\n",
		(ulong)c, omode, instance, qid, qt);
#endif


	rlock(&devlogfslist.rwlock);
	if (waserror()) {
		runlock(&devlogfslist.rwlock);
#ifdef CALLTRACE
		print("devlogfsopen(c = 0x%.8lux, omode = %o) - error %s\n", (ulong)c, omode, up->env->errstr);
#endif
		nexterror();
	}

	if (DATAQID(qid, qt)) {
		Devlogfs *d;
		d = devlogfsfind(instance);
		if (d == nil)
			error(Enodev);
		if (strcmp(up->env->user, eve) != 0)
			error(Eperm);
		if (qid == Qfs && d->state != BootOpen)
			error(Eperm);
		if (d->server == nil) {
			errorany(logfsservernew(d->lb, d->ll, is, d->openflags, d->logfstrace, &d->server));
			d->state = NeedVersion;
		}
		c = devopen(c, omode, 0, 0, devlogfsgennolock);
		incref(&d->ref);
		c->aux = d;
	}
	else if (qid == Qctl || qid == Qusers) {
		if (strcmp(up->env->user, eve) != 0)
			error(Eperm);
		c = devopen(c, omode, 0, 0, devlogfsgennolock);
	}
	else
		c = devopen(c, omode, 0, 0, devlogfsgennolock);
	poperror();
	runlock(&devlogfslist.rwlock);
#ifdef CALLTRACE
	print("devlogfsopen(c = 0x%.8lux, omode = %o) - return\n", (ulong)c, omode);
#endif
	return c;
}

static void
devlogfsclose(Chan *c)
{
	int instance, qid, qt;
#ifdef CALLTRACE
	print("devlogfsclose(c = 0x%.8lux)\n", (ulong)c);
#endif
	SPLITPATH(c->qid.path, c->qid.type, instance, qid, qt);
	USED(instance);
	if(DATAQID(qid, qt) && (c->flag & COPEN) != 0) {
		Devlogfs *d;
		d = c->aux;
		qlock(&d->qlock);
		if (qid == Qfs && d->state == Attached) {
			logfsserverflush(d->server);
			logfsserverfree(&d->server);
			d->state = BootOpen;
		}
		qunlock(&d->qlock);
		decref(&d->ref);
	}
#ifdef CALLTRACE
	print("devlogfsclose(c = 0x%.8lux) - return\n", (ulong)c);
#endif
}

typedef char *(SMARTIOFN)(void *magic, void *buf, long n, ulong offset, int write);

static void
smartio(SMARTIOFN *io, void *magic, void *buf, long n, ulong offset, long blocksize, int write)
{
	void *tmp = nil;
	ulong blocks, toread;

	if (waserror()) {
		logfsfreemem(tmp);
		nexterror();
	}
	if (offset % blocksize) {
		ulong aoffset;
		int tmpoffset;
		int tocopy;

		if (tmp == nil)
			tmp = emalloc(blocksize);
		aoffset = offset / blocksize;
		aoffset *= blocksize;
		errorany((*io)(magic, tmp, blocksize, aoffset, 0));
		tmpoffset = offset - aoffset;
		tocopy = blocksize - tmpoffset;
		if (tocopy > n)
			tocopy = n;
		if (write) {
			memmove((uchar *)tmp + tmpoffset, buf, tocopy);
			errorany((*io)(magic, tmp, blocksize, aoffset, 1));
		}
		else
			memmove(buf, (uchar *)tmp + tmpoffset, tocopy);
		buf = (uchar *)buf + tocopy;
		n -= tocopy;
		offset = aoffset + blocksize;
	}
	blocks = n / blocksize;
	toread = blocks * blocksize;
	errorany((*io)(magic, buf, toread, offset, write));
	buf = (uchar *)buf + toread;
	n -= toread;
	offset += toread;
	if (n) {
		if (tmp == nil)
			tmp = emalloc(blocksize);
		errorany((*io)(magic, tmp, blocksize, offset, 0));
		if (write) {
			memmove(tmp, buf, n);
			errorany((*io)(magic, tmp, blocksize, offset, 1));
		}
		memmove(buf, tmp, n);
	}
	poperror();
	logfsfreemem(tmp);
}

static int
readok(void *a)
{
	Devlogfs *d = a;
	return d->reading;
}

static int
writeok(void *a)
{
	Devlogfs *d = a;
	return !d->reading;
}

static long
lfsrvread(Devlogfs *d, void *buf, long n)
{
	qlock(&d->rlock);
	if(waserror()){
		qunlock(&d->rlock);
		nexterror();
	}
	if (d->state == Hungup)
		error(Ehungup);
	Sleep(&d->readrendez, readok, d);
	if (n > d->readcount)
		n = d->readcount;
	memmove(buf, d->readp, n);
	d->readp += n;
	d->readcount -= n;
	if (d->readcount == 0) {
		d->reading = 0;
		Wakeup(&d->writerendez);
	}
	poperror();
	qunlock(&d->rlock);
	return n;
}

static void
reply(Devlogfs *d)
{
	d->readp = d->readbuf;
	d->readcount = convS2M(&d->out, d->readp, d->readbufsize);
//print("reply is %d bytes\n", d->readcount);
	if (d->readcount == 0)
		panic("logfs: reply: did not fit\n");
	d->reading = 1;
	Wakeup(&d->readrendez);
}

static void
rerror(Devlogfs *d, char *ename)
{
	d->out.type = Rerror;
	d->out.ename = ename;
	reply(d);
}

static struct {
	QLock qlock;
	int (*read)(void *magic, Devlogfs *d, int line, char *buf, int buflen);
	void *magic;
	Devlogfs *d;
	int line;
} dump;

static void *
extentdumpinit(Devlogfs *d, int argc, char **argv)
{
	int *p;
	ulong path;
	u32int flashaddr, length;
	long block;
	int page, offset;

	if (argc != 1)
		error(Ebadarg);
	path = strtoul(argv[0], 0, 0);
	errorany(logfsserverreadpathextent(d->server, path, 0, &flashaddr, &length, &block, &page, &offset));
	p = emalloc(sizeof(ulong));
	*p = path;
	return p;
}

static int
extentdumpread(void *magic, Devlogfs *d, int line, char *buf, int buflen)
{
	ulong *p = magic;
	u32int flashaddr, length;
	long block;
	int page, offset;
	USED(d);
	errorany(logfsserverreadpathextent(d->server, *p, line, &flashaddr, &length, &block, &page, &offset));
	if (length == 0)
		return 0;
	return snprint(buf, buflen, "%.8ux %ud %ld %d %d\n", flashaddr, length, block, page, offset);
}

static void
devlogfsdumpinit(Devlogfs *d,
	void *(*init)(Devlogfs *d, int argc, char **argv),
	int (*read)(void *magic, Devlogfs *d, int line, char *buf, int buflen), int argc, char **argv)
{
	qlock(&dump.qlock);
	if (waserror()) {
		qunlock(&dump.qlock);
		nexterror();
	}
	if (d) {
		if (d->state < NeedVersion)
			error("not mounted");
		qlock(&d->qlock);
		if (waserror()) {
			qunlock(&d->qlock);
			nexterror();
		}
	}
	if (dump.magic) {
		logfsfreemem(dump.magic);
		dump.magic = nil;
	}
	dump.d = d;
	dump.magic = (*init)(d, argc, argv);
	dump.read = read;
	dump.line = 0;
	if (d) {
		poperror();
		qunlock(&d->qlock);
	}
	poperror();
	qunlock(&dump.qlock);
}

static long
devlogfsdumpread(char *buf, int buflen)
{
	char *tmp = nil;
	long n;
	qlock(&dump.qlock);
	if (waserror()) {
		logfsfreemem(tmp);
		qunlock(&dump.qlock);
		nexterror();
	}
	if (dump.magic == nil)
		error(Eio);
	tmp = emalloc(READSTR);
	if (dump.d) {
		if (dump.d->state < NeedVersion)
			error("not mounted");
		qlock(&dump.d->qlock);
		if (waserror()) {
			qunlock(&dump.d->qlock);
			nexterror();
		}
	}
	n = (*dump.read)(dump.magic, dump.d, dump.line, tmp, READSTR);
	if (n) {
		dump.line++;
		n = readstr(0, buf, buflen, tmp);
	}
	if (dump.d) {
		poperror();
		qunlock(&dump.d->qlock);
	}
	logfsfreemem(tmp);
	poperror();
	qunlock(&dump.qlock);
	return n;
}

static void
devlogfsserverlogsweep(Devlogfs *d, int justone)
{
	int didsomething;
	if (d->state < NeedVersion)
		error("not mounted");
	qlock(&d->qlock);
	if (waserror()) {
		qunlock(&d->qlock);
		nexterror();
	}
	errorany(logfsserverlogsweep(d->server, justone, &didsomething));
	poperror();
	qunlock(&d->qlock);
}

static void
devlogfsserversync(Devlogfs *d)
{
	if (d->state < NeedVersion)
		return;
	qlock(&d->qlock);
	if (waserror()) {
		qunlock(&d->qlock);
		nexterror();
	}
	errorany(logfsserverflush(d->server));
	poperror();
	qunlock(&d->qlock);
}

static void
lfssrvwrite(Devlogfs *d, void *buf, long n)
{
	volatile int locked = 0;

	qlock(&d->wlock);
	if(waserror()){
		qunlock(&d->wlock);
		nexterror();
	}
	if (d->state == Hungup)
		error(Ehungup);
	Sleep(&d->writerendez, writeok, d);
	if (convM2S(buf, n, &d->in) != n) {
		/*
		 * someone is writing drivel; have nothing to do with them anymore
		 * most common cause; trying to mount authenticated
		 */
		d->state = Hungup;
		error(Ehungup);
	}
	d->out.tag = d->in.tag;
	d->out.fid = d->in.fid;
	d->out.type = d->in.type + 1;
	if (waserror()) {
		if (locked)
			qunlock(&d->qlock);
		rerror(d, up->env->errstr);
		goto Replied;
	}
	if (d->in.type != Tversion && d->in.type != Tattach) {
		if (d->state != Attached)
			error("must be attached");
		qlock(&d->qlock);
		locked = 1;
	}
	switch (d->in.type) {
	case Tauth:
		error("no authentication needed");
	case Tversion: {
		char *rversion;
		if (d->state != NeedVersion)
			error("unexpected Tversion");
		 if (d->in.tag != NOTAG)
			error("protocol botch");
		/*
		 * check the version string
		 */
		if (strcmp(d->in.version, devlogfs9pversion) != 0)
			rversion = "unknown";
		else
			rversion = devlogfs9pversion;
		/*
		 * allocate the reply buffer
		 */
		d->readbufsize = d->in.msize;
		if (d->readbufsize > MAXMSIZE)
			d->readbufsize = MAXMSIZE;
		d->readbuf = emalloc(d->readbufsize);
		/*
		 * compose the Rversion
		 */
		d->out.msize = d->readbufsize;
		d->out.version = rversion;
		d->state = NeedAttach;
		break;
	}
	case Tattach:
		if (d->state != NeedAttach)
			error("unexpected attach");
		if (d->in.afid != NOFID)
			error("unexpected afid");
		errorany(logfsserverattach(d->server, d->in.fid, d->in.uname, &d->out.qid));
		d->state = Attached;
		break;
	case Tclunk:
		errorany(logfsserverclunk(d->server, d->in.fid));
		break;
	case Tcreate:
		errorany(logfsservercreate(d->server, d->in.fid, d->in.name, d->in.perm, d->in.mode, &d->out.qid));
		d->out.iounit = d->readbufsize - 11;
		break;
	case Tflush:
		break;
	case Topen:
		errorany(logfsserveropen(d->server, d->in.fid, d->in.mode, &d->out.qid));
		d->out.iounit = d->readbufsize - 11;
		break;
	case Tread:
		d->out.data = (char *)d->readbuf + 11;
		/* TODO - avoid memmove */
		errorany(logfsserverread(d->server, d->in.fid, d->in.offset, d->in.count, (uchar *)d->out.data,
			d->readbufsize - 11, &d->out.count));
		break;
	case Tremove:
		errorany(logfsserverremove(d->server, d->in.fid));
		break;
	case Tstat:
		d->out.stat = d->readbuf + 9;
		/* TODO - avoid memmove */
		errorany(logfsserverstat(d->server, d->in.fid, d->out.stat, d->readbufsize - 9, &d->out.nstat));
//		print("nstat %d\n", d->out.nstat);
		break;
	case Twalk:
		errorany(logfsserverwalk(d->server, d->in.fid, d->in.newfid,
			d->in.nwname, d->in.wname, &d->out.nwqid, d->out.wqid));
		break;
	case Twrite:
		errorany(logfsserverwrite(d->server, d->in.fid, d->in.offset, d->in.count, (uchar *)d->in.data,
			&d->out.count));
		break;
	case Twstat:
		errorany(logfsserverwstat(d->server, d->in.fid, d->in.stat, d->in.nstat));
		break;
	default:
		print("lfssrvwrite: msg %d unimplemented\n", d->in.type);
		error("unimplemented");
	}
	poperror();
	if (locked)
		qunlock(&d->qlock);
	reply(d);
Replied:
	poperror();
	qunlock(&d->wlock);
}

static long
devlogfsread(Chan *c, void *buf, long n, vlong off)
{
	int instance, qid, qt;

	SPLITPATH(c->qid.path, c->qid.type, instance, qid, qt);
	USED(instance);
#ifdef CALLTRACE
	print("devlogfsread(c = 0x%.8lux, buf = 0x%.8lux, n = %ld, instance = %d, qid = %d, qt = %d) - start\n",
		(ulong)c, (ulong)buf, n, instance, qid, qt);
#endif
	if(qt & QTDIR) {
#ifdef CALLTRACE
		print("devlogfsread(c = 0x%.8lux, buf = 0x%.8lux, n = %ld, instance = %d, qid = %d, qt = %d) - calling devdirread\n",
			(ulong)c, (ulong)buf, n, instance, qid, qt);
#endif
		return devdirread(c, buf, n, 0, 0, devlogfsgen);
	}

	if(DATAQID(qid, qt)) {
		if (qid == Qfsboot) {
			Devlogfs *l = c->aux;
			qlock(&l->bootqlock);
			if (waserror()) {
				qunlock(&l->bootqlock);
				nexterror();
			}
			smartio((SMARTIOFN *)logfsbootio, l->lb, buf, n, off, logfsbootgetiosize(l->lb), 0);
			poperror();
			qunlock(&l->bootqlock);
			return n;
		}
		else if (qid == Qfs) {
			Devlogfs *d = c->aux;
			return lfsrvread(d, buf, n);
		}
		error(Eio);
	}

	if (qid == Qusers) {
		long nr;
		errorany(logfsisusersread(is, buf, n, (ulong)off, &nr));
		return nr;
	}
	else if (qid == Qdump)
		return devlogfsdumpread(buf, n);

	if (qid != Qctl)
		error(Egreg);

	return 0;
}

enum {
	CMconfig,
	CMformat,
	CMopen,
	CMsweep,
	CMtrace,
	CMunconfig,
	CMextent,
	CMsweepone,
	CMtest,
	CMleakaudit,
	CMsync
};

static Cmdtab fscmds[] = {
	{CMconfig, "config", 2},
	{CMformat, "format", 2},
	{CMopen, "open", 0},
	{CMsweep, "sweep", 1},
	{CMsweepone, "sweepone", 1},
	{CMtrace, "trace", 0},
	{CMunconfig, "unconfig", 1},
	{CMextent, "extent", 0},
	{CMtest, "test", 0},
	{CMleakaudit, "leakaudit", 1},
	{CMsync, "sync", 1},
};

static long
devlogfswrite(Chan *c, void *buf, long n, vlong off)
{
	int instance, qid, qt, i;
	Cmdbuf *cmd;
	Cmdtab *ct;

	if(n <= 0)
		return 0;
	SPLITPATH(c->qid.path, c->qid.type, instance, qid, qt);
#ifdef CALLTRACE
	print("devlogfswrite(c = 0x%.8lux, buf = 0x%.8lux, n = %ld, instance = %d, qid = %d, qt = %d) - start\n",
		(ulong)c, (ulong)buf, n, instance, qid, qt);
#endif
	USED(instance);
	if(DATAQID(qid, qt)){
		if (qid == Qfsboot) {
			Devlogfs *l = c->aux;
			qlock(&l->bootqlock);
			if (waserror()) {
				qunlock(&l->bootqlock);
				nexterror();
			}
			smartio((SMARTIOFN *)logfsbootio, l->lb, buf, n, off, logfsbootgetiosize(l->lb), 1);
			poperror();
			qunlock(&l->bootqlock);
			return n;
		}
		else if (qid == Qfs) {
			Devlogfs *d = c->aux;
			lfssrvwrite(d, buf, n);
			return n;
		}
		error(Eio);
	}
	else if (qid == Qctl) {
		Devlogfs *l = nil;
		int a;

		cmd = parsecmd(buf, n);
		if(waserror()){
			free(cmd);
			nexterror();
		}
		i = cmd->nf;
		if(0){print("i=%d", i); for(i=0; i<cmd->nf; i++)print(" %q", cmd->f[i]); print("\n");}
		if (i <= 0)
			error(Ebadarg);
		if (i == 3 && strcmp(cmd->f[0], "uname") == 0) {
			switch (cmd->f[2][0]) {
			default:
				errorany(logfsisgroupcreate(is, cmd->f[1], cmd->f[2]));
				break;
			case ':':
				errorany(logfsisgroupcreate(is, cmd->f[1], cmd->f[2] + 1));
				break;
			case '%':
				errorany(logfsisgrouprename(is, cmd->f[1], cmd->f[2] + 1));
				break;
			case '=':
				errorany(logfsisgroupsetleader(is, cmd->f[1], cmd->f[2] + 1));
				break;
			case '+':
				errorany(logfsisgroupaddmember(is, cmd->f[1], cmd->f[2] + 1));
				break;
			case '-':
				errorany(logfsisgroupremovemember(is, cmd->f[1], cmd->f[2] + 1));
				break;
			}
			i = 0;
		}
		if (i == 4 && strcmp(cmd->f[0], "fsys") == 0 && strcmp(cmd->f[2], "config") == 0) {
			l = devlogfsconfig(cmd->f[1], cmd->f[3]);
			i = 0;
		}
		else if (i >= 2 && strcmp(cmd->f[0], "fsys") == 0) {
			l = devlogfssetdefname(cmd->f[1]);
			if (l == nil)
				errorf("file system %q not configured", cmd->f[1]);
			i -= 2;
			cmd->f += 2;
			cmd->nf = i;
		}
		if (i != 0) {
			ct = lookupcmd(cmd, fscmds, nelem(fscmds));
			if (l == nil)
				l = devlogfssetdefname(nil);
			if(l == nil && ct->index != CMleakaudit)
				error("file system not configured");
			switch(ct->index){
			case CMopen:
				for (a = 1; a < i; a++)
					if (cmd->f[a][0] == '-')
						switch (cmd->f[a][1]) {
						case 'P':
							l->openflags |= LogfsOpenFlagNoPerm;
							break;
						case 'W':
							l->openflags |= LogfsOpenFlagWstatAllow;
							break;
						default:
							error(Ebadarg);
						}
				devlogfsllopen(l);
				break;
			case CMformat:
				devlogfsllformat(l, strtol(cmd->f[1], nil, 0));
				break;
			case CMsweep:
				devlogfsserverlogsweep(l, 0);
				break;
			case CMsweepone:
				devlogfsserverlogsweep(l, 1);
				break;
			case CMtrace:
				l->logfstrace = i > 1 ? strtol(cmd->f[1], nil, 0) : 0;
				if (l->server)
					logfsservertrace(l->server, l->logfstrace);
				if (l->lb)
					logfsboottrace(l->lb, l->logfstrace);
				break;
			case CMunconfig:
				if (l->ref.ref > 0)
					error(Einuse);
				devlogfsunconfig(l);
				break;
			case CMextent:
				if(i < 2)
					error(Ebadarg);
				devlogfsdumpinit(l, extentdumpinit, extentdumpread, i - 1, cmd->f + 1);
				break;
			case CMtest:
				if(i < 2)
					error(Ebadarg);
				errorany(logfsservertestcmd(l->server, i - 1, cmd->f + 1));
				break;
			case CMleakaudit:
#ifdef LEAKHUNT
				leakaudit();
#endif
				break;
			case CMsync:
				devlogfsserversync(l);
				break;
			default:
				error(Ebadarg);
			}
		}
		poperror();
		free(cmd);
		return n;
	}
	error(Egreg);
	return 0;		/* not reached */
}

static void
devlogfsfree(Devlogfs *devlogfs)
{
	if (devlogfs != nil) {
		int i;
		logfsfreemem(devlogfs->device);
		logfsfreemem(devlogfs->name);
		for (i = 0; i < Qend - Qfs; i++)
			logfsfreemem(devlogfs->filename[i]);
		cclose(devlogfs->flash);
		cclose(devlogfs->flashctl);
		qlock(&devlogfs->qlock);
		logfsserverfree(&devlogfs->server);
		logfsbootfree(devlogfs->lb);
		if (devlogfs->ll)
			(*devlogfs->ll->free)(devlogfs->ll);
		logfsfreemem(devlogfs->readbuf);
		qunlock(&devlogfs->qlock);
		logfsfreemem(devlogfs);
	}
}

#ifdef EMU
ulong
logfsnow(void)
{
	extern vlong timeoffset;
	return (timeoffset + osusectime()) / 1000000;
}
#endif

Dev logfsdevtab = {
	0x29f,
//	L'ʟ',
	"logfs",

#ifndef EMU
	devreset,
#endif
	devinit,
#ifndef EMU
	devshutdown,
#endif
	devlogfsattach,
	devlogfswalk,
	devlogfsstat,
	devlogfsopen,
	devcreate,
	devlogfsclose,
	devlogfsread,
	devbread,
	devlogfswrite,
	devbwrite,
	devremove,
	devwstat,
};
