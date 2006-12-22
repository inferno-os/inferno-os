#include "lib9.h"
#include "logfs.h"
#include "fcall.h"
#include "local.h"

static char *unimp = "unimplemented";
char *logfsbadfid = "invalid fid";

char *
logfsstrdup(char *p)
{
	int l;
	char *q;
	if(p == nil)
		return nil;
	l = strlen(p);
	q = logfsrealloc(nil, l + 1);
	if(q == nil)
		return nil;
	return strcpy(q, p);
}

static
mkdirentry(LogfsServer *server, Entry *e, int inuse, ulong path, Entry *parent, char *name, char *uid, char *gid,
	ulong mtime, char *muid, ulong perm)
{
//print("mkdirentry 0x%.8lux\n", e);
	e->inuse = inuse;
	e->qid.path = path;
	e->qid.vers = 0;
	e->qid.type = QTDIR;
	e->parent = parent;
	e->name = name;
	e->uid = logfsisustadd(server->is, uid);
	e->gid = logfsisustadd(server->is, gid);
	e->mtime = mtime;
	e->muid = logfsisustadd(server->is, muid);
	e->perm = perm | DMDIR;
	e->next = nil;
	return e->uid != nil && e->muid != nil && e->name != nil;
}

void
logfsentryfree(Entry *e)
{
	logfsfreemem(e->name);
	if((e->qid.type & QTDIR) == 0)
		logfsextentlistfree(&e->u.file.extent);
	logfsfreemem(e);
}

char *
logfsentrynew(LogfsServer *server, int inuse, u32int path, Entry *parent, char *name, char *uid, char *gid,
u32int mtime, char *muid, u32int perm, ulong cvers, ulong length, Entry **ep)
{
	Entry *e;
	char *errmsg;
	e = logfsrealloc(nil, sizeof(*e));
	if(e == nil)
		return Enomem;
	e->inuse = inuse;
	e->qid.path = path;
	e->qid.vers = 0;
	e->qid.type = perm >> 24;
	e->parent = parent;
	e->name = logfsstrdup(name);
	e->uid = logfsisustadd(server->is, uid);
	e->gid = logfsisustadd(server->is, gid);
	e->muid = logfsisustadd(server->is, muid);
	if(e->uid == nil || e->gid == nil || e->muid == nil || e->name == nil) {
		logfsentryfree(e);
		return Enomem;
	}
	e->mtime = mtime;
	if(perm & DMDIR)
		e->perm = perm & (~0777 | (parent->perm & 0777));
	else {
		e->perm = perm & (~0666 | (parent->perm & 0666));
		e->u.file.cvers = cvers;
		e->u.file.length = length;
		errmsg = logfsextentlistnew(&e->u.file.extent);
		if(errmsg) {
			logfsentryfree(e);
			return errmsg;
		}
	}
//print("e 0x%.8lux perm 0%.uo\n", e, e->perm);
	*ep = e;
	return nil;
	
}

void
logfsentryclunk(Entry *e)
{
	e->inuse--;
	if(e->inuse <= 0)
		logfsentryfree(e);
}

char *
logfsservernew(LogfsBoot *lb, LogfsLowLevel *ll, LogfsIdentityStore *is, ulong openflags, int trace, LogfsServer **srvp)
{
	LogfsServer *srv;
	char *errmsg;
	Path *p;

	if(trace > 1)
		print("logfsservernew()\n");
	if(ll->l2pagesperblock > 5)
		return "more than 32 pages per block";
	if((1 << (ll->pathbits - L2LogSweeps - L2BlockCopies)) < ll->blocks)
		return "too many blocks";
	srv = logfsrealloc(nil, sizeof(*srv));
	if(srv == nil) {
	memerror:
		errmsg = Enomem;
	err:
		logfsserverfree(&srv);
		return errmsg;
	}
	errmsg = logfsfidmapnew(&srv->fidmap);
	if(errmsg)
		goto memerror;
	errmsg = logfspathmapnew(&srv->pathmap);
	if(errmsg)
		goto memerror;
	srv->is = is;
	srv->ll = ll;
	srv->trace = trace;
	srv->lb = lb;
	srv->openflags = openflags;
	if(!mkdirentry(srv, &srv->root, 1, 0, &srv->root, "", "inferno", "sys", logfsnow(), "inferno", 0777))
		goto memerror;
	errmsg = logfspathmapnewentry(srv->pathmap, 0, &srv->root, &p);
	/* p is guaranteed to be non null */
	if(errmsg)
		goto memerror;
	errmsg = logfslogsegmentnew(srv, 0, &srv->activelog);
	if(errmsg)
		goto memerror;
	srv->ndatablocks = 0;
	srv->datablock = logfsrealloc(nil, sizeof(DataBlock) * ll->blocks);
	if(srv->datablock == nil)
		goto memerror;
	errmsg = logfsscan(srv);
	if(errmsg)
		goto err;
	errmsg = logfsreplay(srv, srv->sweptlog, 0);
	if(errmsg)
		goto err;
	errmsg = logfsreplay(srv, srv->activelog, srv->sweptlog != nil);
	if(errmsg)
		goto err;
	logfsreplayfinddata(srv);
	*srvp = srv;
	return nil;
}

static void
freeentrylist(Entry *e)
{
	Entry *next;
	while(e) {
		next = e->next;
		if(e->qid.type & QTDIR)
			freeentrylist(e->u.dir.list);
		logfsentryfree(e);
		e = next;
	}
}

void
logfsserverfree(LogfsServer **serverp)
{
	LogfsServer *server = *serverp;
	if(server) {
		logfsfidmapfree(&server->fidmap);
		logfslogsegmentfree(&server->activelog);
		logfslogsegmentfree(&server->sweptlog);
		logfspathmapfree(&server->pathmap);
		logfsfreemem(server->datablock);
		logfsfreemem(server);
		freeentrylist(server->root.u.dir.list);
		*serverp = nil;
	}
}

char *
logfsserverattach(LogfsServer *server, u32int fid, char *uname, Qid *qid)
{
	char *errmsg;
	Fid *f;
	if(server->trace > 1)
		print("logfsserverattach(%ud, %s)\n", fid, uname);
	errmsg = logfsfidmapnewentry(server->fidmap, fid, &f);
	if(errmsg)
		return errmsg;
	f->uname = logfsisustadd(server->is, uname);
	if(f->uname == nil) {
		logfsfidmapclunk(server->fidmap, fid);
		return Enomem;
	}
	f->entry = &server->root;
	f->entry->inuse++;
	*qid = f->entry->qid;
	return nil;
}

static void
id2name(LogfsIdentityStore *is, char *id, char **namep, int *badp, int *lenp)
{
	char *name;
	if(id == logfsisgroupnonename)
		name = id;
	else {
		name = logfsisfindnamefromid(is, id);
		if(name == nil) {
			*badp = 2;
			name = id;
		}
	}
	*lenp = strlen(name);
	*namep = name;
}

u32int
logfsflattenentry(LogfsIdentityStore *is, uchar *buf, u32int limit, Entry *e)
{
	int unamelen, gnamelen, munamelen, namelen;
	uint len;
	uchar *p;
	int unamebad = 0, gnamebad = 0, munamebad = 0;
	char *uname, *gname, *muname;

	id2name(is, e->uid, &uname, &unamebad, &unamelen);
	id2name(is, e->gid, &gname, &gnamebad, &gnamelen);
	id2name(is, e->muid, &muname, &munamebad, &munamelen);
	namelen = strlen(e->name);
	len = 49 + unamelen + unamebad + gnamelen + gnamebad + munamelen + munamebad + namelen;
	if(buf == nil)
		return len;
	if(len > limit)
		return 0;
	p = buf;
	/* size */		PBIT16(p, len - BIT16SZ); p += BIT16SZ;
	/* type */		p += BIT16SZ;
	/* dev */		p += BIT32SZ;
	/* qid.type */	*p++ = e->qid.type;
	/* qid.vers */	PBIT32(p, e->qid.vers); p += BIT32SZ;
	/* qid.path */	PBIT64(p, e->qid.path); p+= 8;
	/* mode */	PBIT32(p, e->perm); p+= BIT32SZ;
	/* atime */	PBIT32(p, e->mtime); p+= BIT32SZ;
	/* mtime */	PBIT32(p, e->mtime); p+= BIT32SZ;
	/* length */	if(e->qid.type & QTDIR) {
					PBIT64(p, 0);
					p += 8;
				}
				else {
					PBIT32(p, e->u.file.length); p += BIT32SZ;
					PBIT32(p, 0); p += BIT32SZ;
				}
	/* name */	PBIT16(p, namelen); p += BIT16SZ; memcpy(p, e->name, namelen); p+= namelen;
	/* uid */		PBIT16(p, unamelen + unamebad); p += BIT16SZ;
				if(unamebad)
					*p++ = '(';
				memcpy(p, uname, unamelen + unamebad); p+= unamelen;
				if(unamebad)
					*p++ = ')';
	/* gid */		PBIT16(p, gnamelen + gnamebad); p += BIT16SZ;
				if(gnamebad)
					*p++ = '(';
				memcpy(p, gname, gnamelen); p+= gnamelen;
				if(gnamebad)
					*p++ = ')';
	/* muid */	PBIT16(p, munamelen + munamebad); p += BIT16SZ;
				if(munamebad)
					*p++ = '(';
				memcpy(p, muname, munamelen); p+= munamelen;
				if(munamebad)
					*p = ')';
//print("len %ud p - buf %ld\n", len, p - buf);
	return len;
}

char *
logfsserverstat(LogfsServer *server, u32int fid, uchar *buf, u32int bufsize, ushort *nstat)
{
	Fid *f;
	if(server->trace > 1)
		print("logfsserverstat(%ud)\n", fid);
	f = logfsfidmapfindentry(server->fidmap, fid);
	if(f == nil)
		return logfsbadfid;
	if(f->entry->deadandgone)
		return Eio;
	*nstat = logfsflattenentry(server->is, buf, bufsize, f->entry);
	if(*nstat == 0)
		return Emsgsize;
	return nil;
}


void
logfsservertrace(LogfsServer *server, int level)
{
	server->trace = level;
}
