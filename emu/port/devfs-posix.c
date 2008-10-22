/*
 * Unix file system interface
 */
#define _LARGEFILE64_SOURCE	1
#define _FILE_OFFSET_BITS 64
#include	"dat.h"
#include	"fns.h"
#include	"error.h"

#include	<sys/types.h>
#include	<sys/stat.h>
#include	<sys/fcntl.h>
#include	<utime.h>
#include	<dirent.h>
#include	<stdio.h>
#define	__EXTENSIONS__
#undef	getwd
#include	<unistd.h>
#include	<pwd.h>
#include	<grp.h>

typedef struct Fsinfo Fsinfo;
struct Fsinfo
{
	int	uid;
	int	gid;
	int	mode;	/* Unix mode */
	DIR*	dir;		/* open directory */
	struct dirent*	de;	/* directory reading */
	int	fd;		/* open files */
	ulong	offset;	/* offset when reading directory */
	int	eod;	/* end of directory */
	QLock	oq;	/* mutex for offset */
	char*	spec;
	Cname*	name;	/* Unix's name for file */
	Qid	rootqid;		/* Plan 9's qid for Inferno's root */
};

#define	FS(c)	((Fsinfo*)(c)->aux)

enum
{
	IDSHIFT	= 8,
	NID	= 1 << IDSHIFT,
	IDMASK	= NID - 1,
	MAXPATH	= 1024	/* TO DO: eliminate this */
};

typedef struct User User;
struct User
{
	int	id;		/* might be user or group ID */
	int	gid;		/* if it's a user not a group, the group ID (only for setid) */
	char*	name;
	int	nmem;
	int*	mem;	/* member array, if nmem != 0 */
	User*	next;
};

char	rootdir[MAXROOT] = ROOT;

static	User*	uidmap[NID];
static	User*	gidmap[NID];
static	QLock	idl;
static	User*	name2user(User**, char*, User* (*get)(char*));
static	User*	id2user(User**, int, User* (*get)(int));
static	User*	newuid(int);
static	User*	newgid(int);
static	User*	newuname(char*);
static	User*	newgname(char*);

static	Qid	fsqid(struct stat *);
static	void	fspath(Cname*, char*, char*);
static	int	fsdirconv(Chan*, char*, struct stat*, uchar*, int, int);
static	Cname*	fswalkpath(Cname*, char*, int);
static	char*	fslastelem(Cname*);
static	int ingroup(int id, int gid);
static	void	fsperm(Chan*, int);
static	long	fsdirread(Chan*, uchar*, int, vlong);
static	int	fsomode(int);
static	void	fsremove(Chan*);

/*
 * this crud is to compensate for invalid symbolic links;
 * all you can do is delete them, and good riddance
 */
static int
xstat(char *f, struct stat *sb)
{
	if(stat(f, sb) >= 0)
		return 0;
	/* could possibly generate ->name as rob once suggested */
	return lstat(f, sb);
}

static void
fsfree(Chan *c)
{
	cnameclose(FS(c)->name);
	free(FS(c));
}

Chan*
fsattach(char *spec)
{
	Chan *c;
	struct stat stbuf;
	static int devno;
	static Lock l;

	if(!emptystr(spec) && strcmp(spec, "*") != 0)
		error(Ebadspec);
	if(stat(rootdir, &stbuf) < 0)
		oserror();

	c = devattach('U', spec);
	c->qid = fsqid(&stbuf);
	c->aux = smalloc(sizeof(Fsinfo));
	FS(c)->dir = nil;
	FS(c)->de = nil;
	FS(c)->fd = -1;
	FS(c)->gid = stbuf.st_gid;
	FS(c)->uid = stbuf.st_uid;
	FS(c)->mode = stbuf.st_mode;
	lock(&l);
	c->dev = devno++;
	unlock(&l);
	if (!emptystr(spec)){
		FS(c)->spec = "/";
		FS(c)->name = newcname(FS(c)->spec);
	}else
		FS(c)->name = newcname(rootdir);
	FS(c)->rootqid = c->qid;

	return c;
}

Walkqid*
fswalk(Chan *c, Chan *nc, char **name, int nname)
{
	int j;
	volatile int alloc;
	Walkqid *wq;
	struct stat stbuf;
	char *n;
	Cname *next;
	Cname *volatile current;
	Qid rootqid;

	if(nname > 0)
		isdir(c);

	alloc = 0;
	current = nil;
	wq = smalloc(sizeof(Walkqid)+(nname-1)*sizeof(Qid));
	if(waserror()){
		if(alloc && wq->clone != nil)
			cclose(wq->clone);
		cnameclose(current);
		free(wq);
		return nil;
	}
	if(nc == nil){
		nc = devclone(c);
		nc->type = 0;
		alloc = 1;
	}
	wq->clone = nc;
	rootqid = FS(c)->rootqid;
	current = FS(c)->name;
	if(current != nil)
		incref(&current->r);
	for(j = 0; j < nname; j++){
		if(!(nc->qid.type&QTDIR)){
			if(j==0)
				error(Enotdir);
			break;
		}
		n = name[j];
		if(strcmp(n, ".") != 0 && !(isdotdot(n) && nc->qid.path == rootqid.path)){
			next = current;
			incref(&next->r);
			next = addelem(current, n);
			//print("** ufs walk '%s' -> %s [%s]\n", current->s, n, next->s);
			if(xstat(next->s, &stbuf) < 0){
				cnameclose(next);
				if(j == 0)
					error(Enonexist);
				strcpy(up->env->errstr, Enonexist);
				break;
			}
			nc->qid = fsqid(&stbuf);
			cnameclose(current);
			current = next;
		}
		wq->qid[wq->nqid++] = nc->qid;
	}
	poperror();
	if(wq->nqid < nname){
		cnameclose(current);
		if(alloc)
			cclose(wq->clone);
		wq->clone = nil;
	}else if(wq->clone){
		nc->aux = smalloc(sizeof(Fsinfo));
		nc->type = c->type;
		if (nname) {
			FS(nc)->gid = stbuf.st_gid;
			FS(nc)->uid = stbuf.st_uid;
			FS(nc)->mode = stbuf.st_mode;
		} else {
			FS(nc)->gid = FS(c)->gid;
			FS(nc)->uid = FS(c)->uid;
			FS(nc)->mode = FS(c)->mode;
		}
		FS(nc)->name = current;
		FS(nc)->spec = FS(c)->spec;
		FS(nc)->rootqid = rootqid;
		FS(nc)->fd = -1;
		FS(nc)->dir = nil;
		FS(nc)->de = nil;
	}
	return wq;
}

static int
fsstat(Chan *c, uchar *dp, int n)
{
	struct stat stbuf;
	char *p;

	if(xstat(FS(c)->name->s, &stbuf) < 0)
		oserror();
	p = fslastelem(FS(c)->name);
	if(*p == 0)
		p = "/";
	qlock(&idl);
	n = fsdirconv(c, p, &stbuf, dp, n, 0);
	qunlock(&idl);
	return n;
}

static Chan*
fsopen(Chan *c, int mode)
{
	int m, isdir;

	m = mode & (OTRUNC|3);
	switch(m) {
	case 0:
		fsperm(c, 4);
		break;
	case 1:
	case 1|16:
		fsperm(c, 2);
		break;
	case 2:
	case 0|16:
	case 2|16:
		fsperm(c, 4);
		fsperm(c, 2);
		break;
	case 3:
		fsperm(c, 1);
		break;
	default:
		error(Ebadarg);
	}

	isdir = c->qid.type & QTDIR;

	if(isdir && mode != OREAD)
		error(Eperm);

	m = fsomode(m & 3);
	c->mode = openmode(mode);

	if(isdir) {
		FS(c)->dir = opendir(FS(c)->name->s);
		if(FS(c)->dir == 0)
			oserror();
		FS(c)->eod = 0;
	}
	else {
		if(mode & OTRUNC)
			m |= O_TRUNC;
		FS(c)->fd = open(FS(c)->name->s, m, 0666);
		if(FS(c)->fd < 0)
			oserror();
	}

	c->offset = 0;
	FS(c)->offset = 0;
	c->flag |= COPEN;
	return c;
}

static void
fscreate(Chan *c, char *name, int mode, ulong perm)
{
	int fd, m, o;
	struct stat stbuf;
	Cname *n;

	fsperm(c, 2);

	m = fsomode(mode&3);
	openmode(mode);	/* get the errors out of the way */

	if(strcmp(name, ".") == 0 || strcmp(name, "..") == 0)
		error(Efilename);
	n = fswalkpath(FS(c)->name, name, 1);
	if(waserror()){
		cnameclose(n);
		nexterror();
	}
	if(perm & DMDIR) {
		if(m)
			error(Eperm);

		perm &= ~0777 | (FS(c)->mode & 0777);
		if(mkdir(n->s, perm) < 0)
			oserror();

		fd = open(n->s, 0);
		if(fd < 0)
			oserror();
		fchmod(fd, perm);
		fchown(fd, up->env->uid, FS(c)->gid);
		if(fstat(fd, &stbuf) <0){
			close(fd);
			oserror();
		}
		close(fd);
		FS(c)->dir = opendir(n->s);
		if(FS(c)->dir == nil)
			oserror();
		FS(c)->eod = 0;
	} else {
		o = (O_CREAT | O_EXCL) | (mode&3);
		if(mode & OTRUNC)
			o |= O_TRUNC;
		perm &= ~0666 | (FS(c)->mode & 0666);
		fd = open(n->s, o, perm);
		if(fd < 0)
			oserror();
		fchmod(fd, perm);
		fchown(fd, up->env->uid, FS(c)->gid);
		if(fstat(fd, &stbuf) < 0){
			close(fd);
			oserror();
		}
		FS(c)->fd = fd;
	}
	cnameclose(FS(c)->name);
	FS(c)->name = n;
	poperror();

	c->qid = fsqid(&stbuf);
	FS(c)->gid = stbuf.st_gid;
	FS(c)->uid = stbuf.st_uid;
	FS(c)->mode = stbuf.st_mode;
	c->mode = openmode(mode);
	c->offset = 0;
	FS(c)->offset = 0;
	c->flag |= COPEN;
}

static void
fsclose(Chan *c)
{
	if((c->flag & COPEN) != 0){
		if(c->qid.type & QTDIR)
			closedir(FS(c)->dir);
		else
			close(FS(c)->fd);
	}
	if(c->flag & CRCLOSE) {
		if(!waserror()) {
			fsremove(c);
			poperror();
		}
		return;
	}
	fsfree(c);
}

static long
fsread(Chan *c, void *va, long n, vlong offset)
{
	long r;

	if(c->qid.type & QTDIR){
		qlock(&FS(c)->oq);
		if(waserror()) {
			qunlock(&FS(c)->oq);
			nexterror();
		}
		r = fsdirread(c, va, n, offset);
		poperror();
		qunlock(&FS(c)->oq);
	}else{
		r = pread(FS(c)->fd, va, n, offset);
		if(r < 0 && (errno == ESPIPE || errno == EPIPE)){
			r = read(FS(c)->fd, va, n);
			if(r < 0)
				oserror();
		}
	}
	return r;
}

static long
fswrite(Chan *c, void *va, long n, vlong offset)
{
	long r;

	r = pwrite(FS(c)->fd, va, n, offset);
	if(r < 0 && (errno == ESPIPE || errno == EPIPE)){
		r = write(FS(c)->fd, va, n);
		if(r < 0)
			oserror();
	}
	return r;
}

static void
fswchk(Cname *c)
{
	struct stat stbuf;

	if(stat(c->s, &stbuf) < 0)
		oserror();

	if(stbuf.st_uid == up->env->uid)
		stbuf.st_mode >>= 6;
	else
	if(stbuf.st_gid == up->env->gid || ingroup(up->env->uid, stbuf.st_gid))
		stbuf.st_mode >>= 3;

	if(stbuf.st_mode & S_IWOTH)
		return;

	error(Eperm);
}

static void
fsremove(Chan *c)
{
	int n;
	volatile struct { Cname *dir; } dir;

	dir.dir = fswalkpath(FS(c)->name, "..", 1);
	if(waserror()){
		if(dir.dir != nil)
			cnameclose(dir.dir);
		fsfree(c);
		nexterror();
	}
	fswchk(dir.dir);
	cnameclose(dir.dir);
	dir.dir = nil;
	if(c->qid.type & QTDIR)
		n = rmdir(FS(c)->name->s);
	else
		n = remove(FS(c)->name->s);
	if(n < 0)
		oserror();
	poperror();
	fsfree(c);
}

static int
fswstat(Chan *c, uchar *buf, int nb)
{
	Dir *d;
	User *p;
	volatile struct { Cname *ph; } ph;
	struct stat stbuf;
	struct utimbuf utbuf;
	int tsync;

	if(FS(c)->fd >= 0){
		if(fstat(FS(c)->fd, &stbuf) < 0)
			oserror();
	}else{
		if(stat(FS(c)->name->s, &stbuf) < 0)
			oserror();
	}
	d = malloc(sizeof(*d)+nb);
	if(d == nil)
		error(Enomem);
	if(waserror()){
		free(d);
		nexterror();
	}
	tsync = 1;
	nb = convM2D(buf, nb, d, (char*)&d[1]);
	if(nb == 0)
		error(Eshortstat);
	if(!emptystr(d->name) && strcmp(d->name, fslastelem(FS(c)->name)) != 0) {
		tsync = 0;
		validname(d->name, 0);
		ph.ph = fswalkpath(FS(c)->name, "..", 1);
		if(waserror()){
			cnameclose(ph.ph);
			nexterror();
		}
		fswchk(ph.ph);
		ph.ph = fswalkpath(ph.ph, d->name, 0);
		if(rename(FS(c)->name->s, ph.ph->s) < 0)
			oserror();
		cnameclose(FS(c)->name);
		poperror();
		FS(c)->name = ph.ph;
	}

	if(d->mode != ~0 && (d->mode&0777) != (stbuf.st_mode&0777)) {
		tsync = 0;
		if(up->env->uid != stbuf.st_uid)
			error(Eowner);
		if(FS(c)->fd >= 0){
			if(fchmod(FS(c)->fd, d->mode&0777) < 0)
				oserror();
		}else{
			if(chmod(FS(c)->name->s, d->mode&0777) < 0)
				oserror();
		}
		FS(c)->mode &= ~0777;
		FS(c)->mode |= d->mode&0777;
	}

	if(d->atime != ~0 && d->atime != stbuf.st_atime
		|| d->mtime != ~0 && d->mtime != stbuf.st_mtime) {
		tsync = 0;
		if(up->env->uid != stbuf.st_uid)
			error(Eowner);
		if(d->mtime != ~0)
			utbuf.modtime = d->mtime;
		else
			utbuf.modtime = stbuf.st_mtime;
		if(d->atime != ~0)
			utbuf.actime  = d->atime;
		else
			utbuf.actime = stbuf.st_atime;
		if(utime(FS(c)->name->s, &utbuf) < 0)	/* TO DO: futimes isn't portable */
			oserror();
	}

	if(*d->gid){
		tsync = 0;
		qlock(&idl);
		if(waserror()){
			qunlock(&idl);
			nexterror();
		}
		p = name2user(gidmap, d->gid, newgname);
		if(p == 0)
			error(Eunknown);
		if(p->id != stbuf.st_gid) {
			if(up->env->uid != stbuf.st_uid)
				error(Eowner);
			if(FS(c)->fd >= 0){
				if(fchown(FS(c)->fd, stbuf.st_uid, p->id) < 0)
					oserror();
			}else{
				if(chown(FS(c)->name->s, stbuf.st_uid, p->id) < 0)
					oserror();
			}
			FS(c)->gid = p->id;
		}
		poperror();
		qunlock(&idl);
	}

	if(d->length != ~(uvlong)0){
		tsync = 0;
		if(FS(c)->fd >= 0){
			fsperm(c, 2);
			if(ftruncate(FS(c)->fd, d->length) < 0)
				oserror();
		}else{
			fswchk(FS(c)->name);
			if(truncate(FS(c)->name->s, d->length) < 0)
				oserror();
		}
	}

	poperror();
	free(d);
	if(tsync && FS(c)->fd >= 0 && fsync(FS(c)->fd) < 0)
		oserror();
	return nb;
}

#define	QDEVBITS 4	/* 16 devices should be plenty */
#define MAXDEV (1<<QDEVBITS)
#define	QDEVSHIFT	(64-QDEVBITS)
#define	QINOMASK	(((uvlong)1<<QDEVSHIFT)-1)
#define QPATH(d,i)      (((uvlong)(d)<<QDEVSHIFT)|((uvlong)(i)&QINOMASK))

static Qid
fsqid(struct stat *st)
{
	Qid q;
	ulong dev;
	int idev;
	static int nqdev = 0;
	static ulong qdev[MAXDEV];
	static Lock l;

	q.type = QTFILE;
	if(S_ISDIR(st->st_mode))
		q.type = QTDIR;

	dev = st->st_dev;
	lock(&l);
	for(idev = 0; idev < nqdev; idev++)
		if(qdev[idev] == dev)
			break;
	if(idev == nqdev) {
		if(nqdev == MAXDEV) {
			unlock(&l);
			error("too many devices");
		}
		qdev[nqdev++] = dev;
	}
	unlock(&l);

	if(0)	/* we'll just let it be masked off */
	if((uvlong)st->st_ino & ~QINOMASK)
		error("inode number too large");

	q.path = QPATH(idev, st->st_ino);
	q.vers = st->st_mtime;

	return q;
}

static void
fspath(Cname *c, char *name, char *path)
{
	int n;

	if(c->len+strlen(name) >= MAXPATH)
		panic("fspath: name too long");
	memmove(path, c->s, c->len);
	n = c->len;
	if(path[n-1] != '/')
		path[n++] = '/';
	strcpy(path+n, name);
	if(isdotdot(name))
		cleanname(path);
/*print("->%s\n", path);*/
}

static Cname *
fswalkpath(Cname *c, char *name, int dup)
{
	if(dup)
		c = newcname(c->s);
	c = addelem(c, name);
	if(isdotdot(name))
		cleancname(c);
	return c;
}

static char *
fslastelem(Cname *c)
{
	char *p;

	p = c->s + c->len;
	while(p > c->s && p[-1] != '/')
		p--;
	return p;
}

static void
fsperm(Chan *c, int mask)
{
	int m;

	m = FS(c)->mode;
/*
	print("fsperm: %o %o uuid %d ugid %d cuid %d cgid %d\n",
		m, mask, up->env->uid, up->env->gid, FS(c)->uid, FS(c)->gid);
*/
	if(FS(c)->uid == up->env->uid)
		m >>= 6;
	else
	if(FS(c)->gid == up->env->gid || ingroup(up->env->uid, FS(c)->gid))
		m >>= 3;

	m &= mask;
	if(m == 0)
		error(Eperm);
}

static int
isdots(char *name)
{
	return name[0] == '.' && (name[1] == '\0' || name[1] == '.' && name[2] == '\0');
}

static int
fsdirconv(Chan *c, char *name, struct stat *s, uchar *va, int nb, int indir)
{
	Dir d;
	char uidbuf[NUMSIZE], gidbuf[NUMSIZE];
	User *u;

	memset(&d, 0, sizeof(d));
	d.name = name;
	u = id2user(uidmap, s->st_uid, newuid);
	if(u == nil){
		snprint(uidbuf, sizeof(uidbuf), "#%lud", (long)s->st_uid);
		d.uid = uidbuf;
	}else
		d.uid = u->name;
	u = id2user(gidmap, s->st_gid, newgid);
	if(u == nil){
		snprint(gidbuf, sizeof(gidbuf), "#%lud", (long)s->st_gid);
		d.gid = gidbuf;
	}else
		d.gid = u->name;
	d.muid = "";
	d.qid = fsqid(s);
	d.mode = (d.qid.type<<24)|(s->st_mode&0777);
	d.atime = s->st_atime;
	d.mtime = s->st_mtime;
	d.length = s->st_size;
	if(d.mode&DMDIR)
		d.length = 0;
	d.type = 'U';
	d.dev = c->dev;
	if(indir && sizeD2M(&d) > nb)
		return -1;	/* directory reader needs to know it didn't fit */
	return convD2M(&d, va, nb);
}

static long
fsdirread(Chan *c, uchar *va, int count, vlong offset)
{
	int i;
	long n, r;
	struct stat stbuf;
	char path[MAXPATH], *ep;
	struct dirent *de;
	static char slop[8192];

	i = 0;
	fspath(FS(c)->name, "", path);
	ep = path+strlen(path);
	if(FS(c)->offset != offset) {
		seekdir(FS(c)->dir, 0);
		FS(c)->de = nil;
		FS(c)->eod = 0;
		for(n=0; n<offset; ) {
			de = readdir(FS(c)->dir);
			if(de == 0) {
				/* EOF, so stash offset and return 0 */
				FS(c)->offset = n;
				FS(c)->eod = 1;
				return 0;
			}
			if(de->d_ino==0 || de->d_name[0]==0 || isdots(de->d_name))
				continue;
			strecpy(ep, path+sizeof(path), de->d_name);
			if(xstat(path, &stbuf) < 0) {
				fprint(2, "dir: bad path %s\n", path);
				continue;
			}
			qlock(&idl);
			r = fsdirconv(c, de->d_name, &stbuf, slop, sizeof(slop), 1);
			qunlock(&idl);
			if(r <= 0) {
				FS(c)->offset = n;
				return 0;
			}
			n += r;
		}
		FS(c)->offset = offset;
	}

	if(FS(c)->eod)
		return 0;

	/*
	 * Take idl on behalf of id2name.  Stalling attach, which is a
	 * rare operation, until the readdir completes is probably
	 * preferable to adding lock round-trips.
	 */
	qlock(&idl);
	while(i < count){
		de = FS(c)->de;
		FS(c)->de = nil;
		if(de == nil)
			de = readdir(FS(c)->dir);
		if(de == nil){
			FS(c)->eod = 1;
			break;
		}

		if(de->d_ino==0 || de->d_name[0]==0 || isdots(de->d_name))
			continue;

		strecpy(ep, path+sizeof(path), de->d_name);
		if(xstat(path, &stbuf) < 0) {
			fprint(2, "dir: bad path %s\n", path);
			continue;
		}
		r = fsdirconv(c, de->d_name, &stbuf, va+i, count-i, 1);
		if(r <= 0){
			FS(c)->de = de;
			break;
		}
		i += r;
		FS(c)->offset += r;
	}
	qunlock(&idl);
	return i;
}

static int
fsomode(int m)
{
	if(m < 0 || m > 3)
		error(Ebadarg);
	return m == 3? 0: m;
}

void
setid(char *name, int owner)
{
	User *u;

	if(owner && !iseve())
		return;
	kstrdup(&up->env->user, name);

	qlock(&idl);
	u = name2user(uidmap, name, newuname);
	if(u == nil){
		qunlock(&idl);
		up->env->uid = -1;
		up->env->gid = -1;
		return;
	}

	up->env->uid = u->id;
	up->env->gid = u->gid;
	qunlock(&idl);
}

static User**
hashuser(User** tab, int id)
{
	int i;

	i = (id>>IDSHIFT) ^ id;
	return &tab[i & IDMASK];
}

/*
 * the caller of the following functions must hold QLock idl.
 */

/*
 * we could keep separate maps of user and group names to Users to
 * speed this up, but the reverse lookup currently isn't common (ie, change group by wstat and setid)
 */
static User*
name2user(User **tab, char *name, User* (*get)(char*))
{
	int i;
	User *u, **h;
	static User *prevu;
	static User **prevtab;

	if(prevu != nil && prevtab == tab && strcmp(name, prevu->name) == 0)
		return prevu;	/* it's often the one we've just seen */

	for(i=0; i<NID; i++)
		for(u = tab[i]; u != nil; u = u->next)
			if(strcmp(name, u->name) == 0) {
				prevtab = tab;
				prevu = u;
				return u;
			}

	u = get(name);
	if(u == nil)
		return nil;
	h = hashuser(tab, u->id);
	u->next = *h;
	*h = u;
	prevtab = tab;
	prevu = u;
	return u;
}

static void
freeuser(User *u)
{
	if(u != nil){
		free(u->name);
		free(u->mem);
		free(u);
	}
}

static User*
newuser(int id, int gid, char *name, int nmem)
{
	User *u;

	u = malloc(sizeof(*u));
	if(u == nil)
		return nil;
	u->name = strdup(name);
	if(u->name == nil){
		free(u);
		return nil;
	}
	u->nmem = nmem;
	if(nmem){
		u->mem = malloc(nmem*sizeof(*u->mem));
		if(u->mem == nil){
			free(u->name);
			free(u);
			return nil;
		}
	}else
		u->mem = nil;
	u->id = id;
	u->gid = gid;
	u->next = nil;
	return u;
}

static User*
newuname(char *name)
{
	struct passwd *p;
	User *u;

	p = getpwnam(name);
	if(p == nil)
		return nil;
	return newuser(p->pw_uid, p->pw_gid, name, 0);
}

static User*
newuid(int id)
{
	struct passwd *p;
	User *u;

	p = getpwuid(id);
	if(p == nil)
		return nil;
	return newuser(p->pw_uid, p->pw_gid, p->pw_name, 0);
}

static User*
newgroup(struct group *g)
{
	User *u, *gm;
	int n, o;

	if(g == nil)
		return nil;
	for(n=0; g->gr_mem[n] != nil; n++)
		;
	u = newuser(g->gr_gid, g->gr_gid, g->gr_name, n);
	if(u == nil)
		return nil;
	o = 0;
	for(n=0; g->gr_mem[n] != nil; n++){
		gm = name2user(uidmap, g->gr_mem[n], newuname);
		if(gm != nil)
			u->mem[o++] = gm->id;
		/* ignore names that don't map to IDs */
	}
	u->nmem = o;
	return u;
}

static User*
newgid(int id)
{
	return newgroup(getgrgid(id));
}

static User*
newgname(char *name)
{
	return newgroup(getgrnam(name));
}

static User*
id2user(User **tab, int id, User* (*get)(int))
{
	int i;
	User *u, **h;

	h = hashuser(tab, id);
	for(u = *h; u != nil; u = u->next)
		if(u->id == id)
			return u;
	u = get(id);
	if(u == nil)
		return nil;
	u->next = *h;
	*h = u;
	return u;
}

static int
ingroup(int id, int gid)
{
	int i;
	User *g;

	g = id2user(gidmap, gid, newgid);
	if(g == nil || g->mem == nil)
		return 0;
	for(i = 0; i < g->nmem; i++)
		if(g->mem[i] == id)
			return 1;
	return 0;
}

Dev fsdevtab = {
	'U',
	"fs",

	devinit,
	fsattach,
	fswalk,
	fsstat,
	fsopen,
	fscreate,
	fsclose,
	fsread,
	devbread,
	fswrite,
	devbwrite,
	fsremove,
	fswstat
};
