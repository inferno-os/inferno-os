#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

static int
growfd(Fgrp *f, int fd)
{
	int n;
	Chan **nfd, **ofd;

	if(fd < f->nfd)
		return 0;
	n = f->nfd+DELTAFD;
	if(n > MAXNFD)
		n = MAXNFD;
	if(fd >= n)
		return -1;
	nfd = malloc(n*sizeof(Chan*));
	if(nfd == nil)
		return -1;
	ofd = f->fd;
	memmove(nfd, ofd, f->nfd*sizeof(Chan *));
	f->fd = nfd;
	f->nfd = n;
	free(ofd);
	return 0;
}

int
newfd(Chan *c)
{
	int i;
	Fgrp *f = up->env->fgrp;

	lock(f);
	for(i=f->minfd; i<f->nfd; i++)
		if(f->fd[i] == 0)
			break;
	if(i >= f->nfd && growfd(f, i) < 0){
		unlock(f);
		exhausted("file descriptors");
		return -1;
	}
	f->minfd = i + 1;
	if(i > f->maxfd)
		f->maxfd = i;
	f->fd[i] = c;
	unlock(f);
	return i;
}

Chan*
fdtochan(Fgrp *f, int fd, int mode, int chkmnt, int iref)
{
	Chan *c;

	c = 0;

	lock(f);
	if(fd<0 || f->maxfd<fd || (c = f->fd[fd])==0) {
		unlock(f);
		error(Ebadfd);
	}
	if(iref)
		incref(c);
	unlock(f);

	if(chkmnt && (c->flag&CMSG)) {
		if(iref)
			cclose(c);
		error(Ebadusefd);
	}

	if(mode<0 || c->mode==ORDWR)
		return c;

	if((mode&OTRUNC) && c->mode==OREAD) {
		if(iref)
			cclose(c);
		error(Ebadusefd);
	}

	if((mode&~OTRUNC) != c->mode) {
		if(iref)
			cclose(c);
		error(Ebadusefd);
	}

	return c;
}

long
kchanio(void *vc, void *buf, int n, int mode)
{
	int r;
	Chan *c;

	c = vc;
	if(waserror())
		return -1;

	if(mode == OREAD)
		r = devtab[c->type]->read(c, buf, n, c->offset);
	else
		r = devtab[c->type]->write(c, buf, n, c->offset);

	lock(c);
	c->offset += r;
	unlock(c);
	poperror();
	return r;
}

int
openmode(ulong o)
{
	if(o >= (OTRUNC|OCEXEC|ORCLOSE|OEXEC))
		error(Ebadarg);
	o &= ~(OTRUNC|OCEXEC|ORCLOSE);
	if(o > OEXEC)
		error(Ebadarg);
	if(o == OEXEC)
		return OREAD;
	return o;
}

void
fdclose(Fgrp *f, int fd)
{
	int i;
	Chan *c;

	lock(f);
	c = f->fd[fd];
	if(c == 0){
		/* can happen for users with shared fd tables */
		unlock(f);
		return;
	}
	f->fd[fd] = 0;
	if(fd == f->maxfd)
		for(i=fd; --i>=0 && f->fd[i]==0; )
			f->maxfd = i;
	if(fd < f->minfd)
		f->minfd = fd;
	unlock(f);
	cclose(c);
}

int
kchdir(char *path)
{
	Chan *c;
	Pgrp *pg;

	if(waserror())
		return -1;

	c = namec(path, Atodir, 0, 0);
	pg = up->env->pgrp;
	cclose(pg->dot);
	pg->dot = c;
	poperror();
	return 0;
}

int
kfgrpclose(Fgrp *f, int fd)
{
	if(waserror())
		return -1;

	/*
	 * Take no reference on the chan because we don't really need the
	 * data structure, and are calling fdtochan only for error checks.
	 * fdclose takes care of processes racing through here.
	 */
	fdtochan(f, fd, -1, 0, 0);
	fdclose(f, fd);
	poperror();
	return 0;
}

int
kclose(int fd)
{
	return kfgrpclose(up->env->fgrp, fd);
}

int
kcreate(char *path, int mode, ulong perm)
{
	int fd;
	Chan *c;

	if(waserror())
		return -1;

	openmode(mode&~OEXCL);	/* error check only; OEXCL okay here */
	c = namec(path, Acreate, mode, perm);
	if(waserror()) {
		cclose(c);
		nexterror();
	}
	fd = newfd(c);
	if(fd < 0)
		error(Enofd);
	poperror();

	poperror();
	return fd;
}

int
kdup(int old, int new)
{
	int fd;
	Chan *c, *oc;
	Fgrp *f = up->env->fgrp;

	if(waserror())
		return -1;

	c = fdtochan(up->env->fgrp, old, -1, 0, 1);
	if(c->qid.type & QTAUTH)
		error(Eperm);
	fd = new;
	if(fd != -1){
		lock(f);
		if(fd<0 || growfd(f, fd) < 0) {
			unlock(f);
			cclose(c);
			error(Ebadfd);
		}
		if(fd > f->maxfd)
			f->maxfd = fd;
		oc = f->fd[fd];
		f->fd[fd] = c;
		unlock(f);
		if(oc)
			cclose(oc);
	}else{
		if(waserror()) {
			cclose(c);
			nexterror();
		}
		fd = newfd(c);
		if(fd < 0)
			error(Enofd);
		poperror();
	}
	poperror();
	return fd;
}

int
kfstat(int fd, uchar *buf, int n)
{
	Chan *c;

	if(waserror())
		return -1;

	c = fdtochan(up->env->fgrp, fd, -1, 0, 1);
	if(waserror()) {
		cclose(c);
		nexterror();
	}
	devtab[c->type]->stat(c, buf, n);

	poperror();
	cclose(c);

	poperror();
	return n;
}

char*
kfd2path(int fd)
{
	Chan *c;
	char *s;

	if(waserror())
		return nil;
	c = fdtochan(up->env->fgrp, fd, -1, 0, 1);
	s = nil;
	if(c->name != nil){
		s = malloc(c->name->len+1);
		if(s == nil){
			cclose(c);
			error(Enomem);
		}
		memmove(s, c->name->s, c->name->len+1);
		cclose(c);
	}
	poperror();
	return s;
}

int
kfauth(int fd, char *aname)
{
	Chan *c, *ac;

	if(waserror())
		return -1;

	validname(aname, 0);
	c = fdtochan(up->env->fgrp, fd, ORDWR, 0, 1);
	if(waserror()){
		cclose(c);
		nexterror();
	}

	ac = mntauth(c, aname);

	/* at this point ac is responsible for keeping c alive */
	poperror();	/* c */
	cclose(c);

	if(waserror()){
		cclose(ac);
		nexterror();
	}

	fd = newfd(ac);
	if(fd < 0)
		error(Enofd);
	poperror();	/* ac */

	poperror();

	return fd;
}

int
kfversion(int fd, uint msize, char *vers, uint arglen)
{
	int m;
	Chan *c;

	if(waserror())
		return -1;

	/* check there's a NUL in the version string */
	if(arglen==0 || memchr(vers, 0, arglen)==0)
		error(Ebadarg);

	c = fdtochan(up->env->fgrp, fd, ORDWR, 0, 1);
	if(waserror()){
		cclose(c);
		nexterror();
	}

	m = mntversion(c, vers, msize, arglen);

	poperror();
	cclose(c);

	poperror();
	return m;
}

int
kpipe(int fd[2])
{
	Dev *d;
	Fgrp *f;
	Chan *c[2];
	static char *names[] = {"data", "data1"};

	f = up->env->fgrp;

	d = devtab[devno('|', 0)];
	c[0] = namec("#|", Atodir, 0, 0);
	c[1] = 0;
	fd[0] = -1;
	fd[1] = -1;
	if(waserror()) {
		if(c[0] != 0)
			cclose(c[0]);
		if(c[1] != 0)
			cclose(c[1]);
		if(fd[0] >= 0)
			f->fd[fd[0]]=0;
		if(fd[1] >= 0)
			f->fd[fd[1]]=0;
		return -1;
	}
	c[1] = cclone(c[0]);
	if(walk(&c[0], &names[0], 1, 1, nil) < 0)
		error(Egreg);
	if(walk(&c[1], &names[1], 1, 1, nil) < 0)
		error(Egreg);
	c[0] = d->open(c[0], ORDWR);
	c[1] = d->open(c[1], ORDWR);
	fd[0] = newfd(c[0]);
	if(fd[0] < 0)
		error(Enofd);
	fd[1] = newfd(c[1]);
	if(fd[1] < 0)
		error(Enofd);
	poperror();
	return 0;
}

int
kfwstat(int fd, uchar *buf, int n)
{
	Chan *c;

	if(waserror())
		return -1;

	validstat(buf, n);
	c = fdtochan(up->env->fgrp, fd, -1, 1, 1);
	if(waserror()) {
		cclose(c);
		nexterror();
	}
	n = devtab[c->type]->wstat(c, buf, n);
	poperror();
	cclose(c);

	poperror();
	return n;
}

long
bindmount(Chan *c, char *old, int flag, char *spec)
{
	int ret;
	Chan *c1;

	if(flag>MMASK || (flag&MORDER) == (MBEFORE|MAFTER))
		error(Ebadarg);

	c1 = namec(old, Amount, 0, 0);
	if(waserror()){
		cclose(c1);
		nexterror();
	}
	ret = cmount(c, c1, flag, spec);

	poperror();
	cclose(c1);
	return ret;
}

int
kbind(char *new, char *old, int flags)
{
	long r;
	Chan *c0;

	if(waserror())
		return -1;

	c0 = namec(new, Abind, 0, 0);
	if(waserror()) {
		cclose(c0);
		nexterror();
	}
	r = bindmount(c0, old, flags, "");
	poperror();
	cclose(c0);

	poperror();
	return r;
}

int
kmount(int fd, int afd, char *old, int flags, char *spec)
{
	long r;
	volatile struct { Chan *c; } c0;
	volatile struct { Chan *c; } bc;
	volatile struct { Chan *c; } ac;
	Mntparam mntparam;

	ac.c = nil;
	bc.c = nil;
	c0.c = nil;
	if(waserror()) {
		cclose(ac.c);
		cclose(bc.c);
		cclose(c0.c);
		return -1;
	}
	bc.c = fdtochan(up->env->fgrp, fd, ORDWR, 0, 1);
	if(afd >= 0)
		ac.c = fdtochan(up->env->fgrp, afd, ORDWR, 0, 1);
	mntparam.chan = bc.c;
	mntparam.authchan = ac.c;
	mntparam.spec = spec;
	mntparam.flags = flags;
	c0.c = devtab[devno('M', 0)]->attach((char*)&mntparam);

	r = bindmount(c0.c, old, flags, spec);
	poperror();
	cclose(ac.c);
	cclose(bc.c);
	cclose(c0.c);

	return r;
}

int
kunmount(char *old, char *new)
{
	volatile struct { Chan *c; } cmount;
	volatile struct { Chan *c; } cmounted;

	cmount.c = nil;
	cmounted.c = nil;
	if(waserror()) {
		cclose(cmount.c);
		cclose(cmounted.c);
		return -1;
	}

	cmount.c = namec(new, Amount, 0, 0);
	if(old != nil && old[0] != '\0') {
		/*
		 * This has to be namec(..., Aopen, ...) because
		 * if arg[0] is something like /srv/cs or /fd/0,
		 * opening it is the only way to get at the real
		 * Chan underneath.
		 */
		cmounted.c = namec(old, Aopen, OREAD, 0);
	}

	cunmount(cmount.c, cmounted.c);
	poperror();
	cclose(cmount.c);
	cclose(cmounted.c);
	return 0;
}

int
kopen(char *path, int mode)
{
	int fd;
	Chan *c;

	if(waserror())
		return -1;

	openmode(mode);                         /* error check only */
	c = namec(path, Aopen, mode, 0);
	if(waserror()){
		cclose(c);
		nexterror();
	}
	fd = newfd(c);
	if(fd < 0)
		error(Enofd);
	poperror();

	poperror();
	return fd;
}

long
unionread(Chan *c, void *va, long n)
{
	int i;
	long nr;
	Mhead *m;
	Mount *mount;

	qlock(&c->umqlock);
	m = c->umh;
	rlock(&m->lock);
	mount = m->mount;
	/* bring mount in sync with c->uri and c->umc */
	for(i = 0; mount != nil && i < c->uri; i++)
		mount = mount->next;

	nr = 0;
	while(mount != nil) {
		/* Error causes component of union to be skipped */
		if(mount->to && !waserror()) {
			if(c->umc == nil){
				c->umc = cclone(mount->to);
				c->umc = devtab[c->umc->type]->open(c->umc, OREAD);
			}
	
			nr = devtab[c->umc->type]->read(c->umc, va, n, c->umc->offset);
			if(nr < 0)
				nr = 0;	/* dev.c can return -1 */
			c->umc->offset += nr;
			poperror();
		}
		if(nr > 0)
			break;

		/* Advance to next element */
		c->uri++;
		if(c->umc) {
			cclose(c->umc);
			c->umc = nil;
		}
		mount = mount->next;
	}
	runlock(&m->lock);
	qunlock(&c->umqlock);
	return nr;
}

static void
unionrewind(Chan *c)
{
	qlock(&c->umqlock);
	c->uri = 0;
	if(c->umc){
		cclose(c->umc);
		c->umc = nil;
	}
	qunlock(&c->umqlock);
}

static long
rread(int fd, void *va, long n, vlong *offp)
{
	int dir;
	Chan *c;
	vlong off;

	if(waserror())
		return -1;

	c = fdtochan(up->env->fgrp, fd, OREAD, 1, 1);
	if(waserror()) {
		cclose(c);
		nexterror();
	}

	if(n < 0)
		error(Etoosmall);

	dir = c->qid.type & QTDIR;
	if(dir && c->umh)
		n = unionread(c, va, n);
	else{
		if(offp == nil){
			lock(c);	/* lock for vlong assignment */
			off = c->offset;
			unlock(c);
		}else
			off = *offp;
		if(off < 0)
			error(Enegoff);
		if(off == 0){
			if(offp == nil){
				lock(c);
				c->offset = 0;
				c->dri = 0;
				unlock(c);
			}
			unionrewind(c);
		}
		n = devtab[c->type]->read(c, va, n, off);
		lock(c);
		c->offset += n;
		unlock(c);
	}

	poperror();
	cclose(c);

	poperror();
	return n;
}

long
kread(int fd, void *va, long n)
{
	return rread(fd, va, n, nil);
}

long
kpread(int fd, void *va, long n, vlong off)
{
	return rread(fd, va, n, &off);
}

int
kremove(char *path)
{
	Chan *c;

	if(waserror())
		return -1;

	c = namec(path, Aremove, 0, 0);
	if(waserror()) {
		c->type = 0;	/* see below */
		cclose(c);
		nexterror();
	}
	devtab[c->type]->remove(c);
	/*
	 * Remove clunks the fid, but we need to recover the Chan
	 * so fake it up.  rootclose() is known to be a nop.
	 */
	c->type = 0;
	poperror();
	cclose(c);

	poperror();
	return 0;
}

vlong
kseek(int fd, vlong off, int whence)
{
	Dir *dir;
	Chan *c;

	if(waserror())
		return -1;

	c = fdtochan(up->env->fgrp, fd, -1, 1, 1);
	if(waserror()) {
		cclose(c);
		nexterror();
	}

	if(devtab[c->type]->dc == '|')
		error(Eisstream);

	switch(whence) {
	case 0:
		if(c->qid.type & QTDIR){
			if(off != 0)
				error(Eisdir);
			unionrewind(c);
		}else if(off < 0)
			error(Enegoff);
		lock(c);	/* lock for vlong assignment */
		c->offset = off;
		unlock(c);
		break;

	case 1:
		if(c->qid.type & QTDIR)
			error(Eisdir);
		lock(c);	/* lock for read/write update */
		off += c->offset;
		if(off < 0){
			unlock(c);
			error(Enegoff);
		}
		c->offset = off;
		unlock(c);
		break;

	case 2:
		if(c->qid.type & QTDIR)
			error(Eisdir);
		dir = chandirstat(c);
		if(dir == nil)
			error("internal error: stat error in seek");
		off += dir->length;
		free(dir);
		if(off < 0)
			error(Enegoff);
		lock(c);	/* lock for read/write update */
		c->offset = off;
		unlock(c);
		break;

	default:
		error(Ebadarg);
		break;
	}
	poperror();
	c->dri = 0;
	cclose(c);
	poperror();
	return off;
}

void
validstat(uchar *s, int n)
{
	int m;
	char buf[64];

	if(statcheck(s, n) < 0)
		error(Ebadstat);
	/* verify that name entry is acceptable */
	s += STATFIXLEN - 4*BIT16SZ;	/* location of first string */
	/*
	 * s now points at count for first string.
	 * if it's too long, let the server decide; this is
	 * only for his protection anyway. otherwise
	 * we'd have to allocate and waserror.
	 */
	m = GBIT16(s);
	s += BIT16SZ;
	if(m+1 > sizeof buf)
		return;
	memmove(buf, s, m);
	buf[m] = '\0';
	/* name could be '/' */
	if(strcmp(buf, "/") != 0)
		validname(buf, 0);
}

int
kstat(char *path, uchar *buf, int n)
{
	Chan *c;

	if(waserror())
		return -1;

	c = namec(path, Aaccess, 0, 0);
	if(waserror()){
		cclose(c);
		nexterror();
	}
	devtab[c->type]->stat(c, buf, n);
	poperror();
	cclose(c);

	poperror();
	return 0;
}

static long
rwrite(int fd, void *va, long n, vlong *offp)
{
	Chan *c;
	vlong off;
	long m;

	if(waserror())
		return -1;
	c = fdtochan(up->env->fgrp, fd, OWRITE, 1, 1);
	if(waserror()) {
		cclose(c);
		nexterror();
	}
	if(c->qid.type & QTDIR)
		error(Eisdir);

	if(n < 0)
		error(Etoosmall);

	if(offp == nil){
		lock(c);
		off = c->offset;
		c->offset += n;
		unlock(c);
	}else
		off = *offp;

	if(waserror()){
		if(offp == nil){
			lock(c);
			c->offset -= n;
			unlock(c);
		}
		nexterror();
	}
	if(off < 0)
		error(Enegoff);
	m = devtab[c->type]->write(c, va, n, off);
	poperror();

	if(offp == nil && m < n){
		lock(c);
		c->offset -= n - m;
		unlock(c);
	}

	poperror();
	cclose(c);

	poperror();
	return n;
}

long
kwrite(int fd, void *va, long n)
{
	return rwrite(fd, va, n, nil);
}

long
kpwrite(int fd, void *va, long n, vlong off)
{
	return rwrite(fd, va, n, &off);
}

int
kwstat(char *path, uchar *buf, int n)
{
	Chan *c;

	if(waserror())
		return -1;

	validstat(buf, n);
	c = namec(path, Aaccess, 0, 0);
	if(waserror()){
		cclose(c);
		nexterror();
	}
	n = devtab[c->type]->wstat(c, buf, n);
	poperror();
	cclose(c);

	poperror();
	return n;
}

enum
{
	DIRSIZE = STATFIXLEN + 32 * 4,
	DIRREADLIM = 2048,	/* should handle the largest reasonable directory entry */
};

Dir*
chandirstat(Chan *c)
{
	Dir *d;
	uchar *buf;
	int n, nd, i;

	nd = DIRSIZE;
	for(i=0; i<2; i++){	/* should work by the second try */
		d = smalloc(sizeof(Dir) + nd);
		buf = (uchar*)&d[1];
		if(waserror()){
			free(d);
			return nil;
		}
		n = devtab[c->type]->stat(c, buf, nd);
		poperror();
		if(n < BIT16SZ){
			free(d);
			return nil;
		}
		nd = GBIT16((uchar*)buf) + BIT16SZ;	/* size needed to store whole stat buffer including count */
		if(nd <= n){
			convM2D(buf, n, d, (char*)&d[1]);
			return d;
		}
		/* else sizeof(Dir)+nd is plenty */
		free(d);
	}
	return nil;

}

Dir*
kdirstat(char *name)
{
	Chan *c;
	Dir *d;

	if(waserror())
		return nil;

	c = namec(name, Aaccess, 0, 0);
	if(waserror()){
		cclose(c);
		nexterror();
	}
	d = chandirstat(c);
	poperror();
	cclose(c);

	poperror();
	return d;
}

Dir*
kdirfstat(int fd)
{
	Chan *c;
	Dir *d;

	if(waserror())
		return nil;

	c = fdtochan(up->env->fgrp, fd, -1, 0, 1);
	if(waserror()) {
		cclose(c);
		nexterror();
	}
	d = chandirstat(c);
	poperror();
	cclose(c);

	poperror();
	return d;
}

int
kdirwstat(char *name, Dir *dir)
{
	uchar *buf;
	int r;

	r = sizeD2M(dir);
	buf = smalloc(r);
	convD2M(dir, buf, r);
	r = kwstat(name, buf, r);
	free(buf);
	return r < 0? r: 0;
}

int
kdirfwstat(int fd, Dir *dir)
{
	uchar *buf;
	int r;

	r = sizeD2M(dir);
	buf = smalloc(r);
	convD2M(dir, buf, r);
	r = kfwstat(fd, buf, r);
	free(buf);
	return r < 0? r: 0;
}

static long
dirpackage(uchar *buf, long ts, Dir **d)
{
	char *s;
	long ss, i, n, nn, m;

	*d = nil;
	if(ts <= 0)
		return ts;

	/*
	 * first find number of all stats, check they look like stats, & size all associated strings
	 */
	ss = 0;
	n = 0;
	for(i = 0; i < ts; i += m){
		m = BIT16SZ + GBIT16(&buf[i]);
		if(statcheck(&buf[i], m) < 0)
			break;
		ss += m;
		n++;
	}

	if(i != ts)
		error("bad directory format");

	*d = malloc(n * sizeof(Dir) + ss);
	if(*d == nil)
		error(Enomem);

	/*
	 * then convert all buffers
	 */
	s = (char*)*d + n * sizeof(Dir);
	nn = 0;
	for(i = 0; i < ts; i += m){
		m = BIT16SZ + GBIT16((uchar*)&buf[i]);
		if(nn >= n || convM2D(&buf[i], m, *d + nn, s) != m){
			free(*d);
			*d = nil;
			error("bad directory entry");
		}
		nn++;
		s += m;
	}

	return nn;
}

long
kdirread(int fd, Dir **d)
{
	uchar *buf;
	long ts;

	*d = nil;
	if(waserror())
		return -1;
	buf = malloc(DIRREADLIM);
	if(buf == nil)
		error(Enomem);
	if(waserror()){
		free(buf);
		nexterror();
	}
	ts = kread(fd, buf, DIRREADLIM);
	if(ts >= 0)
		ts = dirpackage(buf, ts, d);
	poperror();
	free(buf);
	poperror();
	return ts;
}

int
kiounit(int fd)
{
	Chan *c;
	int n;

	c = fdtochan(up->env->fgrp, fd, ORDWR, 0, 1);
	if(waserror()){
		cclose(c);
		return 0;	/* n.b. */
	}
	n = c->iounit;
	poperror();
	cclose(c);
	return n;
}
