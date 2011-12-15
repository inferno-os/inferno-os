#include "logfsos.h"
#include "logfs.h"
#include "local.h"
#include "fcall.h"

static void
maxpath(LogfsServer *server, ulong p)
{
	if(p > server->path)
		server->path = p;
}

static char *
recreate(LogfsServer *server, LogMessage *s, int *ok)
{
	Entry *parent;
	char *errmsg;
	Entry *e;
	Path *p;

	parent = logfspathmapfinde(server->pathmap, s->path);
	if(parent == nil)
		return "can't find parent";
	if(logfspathmapfindentry(server->pathmap, s->u.create.newpath) != nil){
		Entry *d = logfspathmapfinde(server->pathmap, s->u.create.newpath);
		if(d == nil)
			print("existing was nil\n");
		else{
			print("existing: name=%q d=%d path=%8.8llux uid=%q gid=%q perm=%#uo\n",
				d->name, d->deadandgone, d->qid.path, d->uid, d->gid, d->perm);
		}
		return "duplicate path";
	}
	if((parent->qid.type & QTDIR) == 0)
		return Enotdir;
	errmsg = logfsentrynew(server, 1, s->u.create.newpath, parent,
		s->u.create.name, s->u.create.uid, s->u.create.gid, s->u.create.mtime, s->u.create.uid,
		s->u.create.perm, s->u.create.cvers, 0, &e);
	if(errmsg) {
		*ok = 0;
		return errmsg;
	}
	/* p guaranteed to be non null */
	errmsg = logfspathmapnewentry(server->pathmap, s->u.create.newpath, e, &p);
	if(errmsg) {
		logfsfreemem(e);
		*ok = 0;
		return errmsg;
	}
	e->next = parent->u.dir.list;
	parent->u.dir.list = e;
	return nil;
}

static char *
reremove(LogfsServer *server, LogMessage *s, int *ok)
{
	Entry *oe;
	Entry *parent;
	Entry **ep;
	Entry *e;
	char *ustmuid;

	USED(ok);
	oe = logfspathmapfinde(server->pathmap, s->path);
	if(oe == nil)
		return logfseunknownpath;
	parent = oe->parent;
	if(parent == oe)
		return "tried to remove root";
	if((parent->qid.type & QTDIR) == 0)
		return Enotdir;
	if((oe->qid.type & QTDIR) != 0 && oe->u.dir.list)
		return logfsenotempty;
	for(ep = &parent->u.dir.list; e = *ep; ep = &e->next)
		if(e == oe)
			break;
	if(e == nil)
		return logfseinternal;
	ustmuid = logfsisustadd(server->is, s->u.remove.muid);
	if(ustmuid == nil)
		return Enomem;
	parent->mtime = s->u.remove.mtime;
	parent->muid = ustmuid;
	logfspathmapdeleteentry(server->pathmap, s->path);
	*ep = e->next;
	if(e->inuse > 1) {
		print("replay: entry inuse > 1\n");
		e->inuse = 1;
	}
	logfsentryclunk(e);
	return nil;
}

static char *
retrunc(LogfsServer *server, LogMessage *s, int *ok)
{
	Entry *e;
	char *ustmuid;

	USED(ok);
	e = logfspathmapfinde(server->pathmap, s->path);
	if(e == nil)
		return logfseunknownpath;
	if((e->qid.type & QTDIR) != 0)
		return Eperm;
	if(e->u.file.cvers >= s->u.trunc.cvers)
		return "old news";
	ustmuid = logfsisustadd(server->is, s->u.trunc.muid);
	if(ustmuid == nil)
		return Enomem;
	e->muid = ustmuid;
	e->mtime = s->u.trunc.mtime;
	e->qid.vers++;
	e->u.file.cvers = s->u.trunc.cvers;
	/*
	 * zap all extents
	 */
	logfsextentlistreset(e->u.file.extent);
	e->u.file.length = 0;
	return nil;
}

static char *
rewrite(LogfsServer *server, LogMessage *s, int *ok)
{
	Entry *e;
	char *ustmuid;
	Extent extent;
	char *errmsg;

	USED(ok);
	e = logfspathmapfinde(server->pathmap, s->path);
	if(e == nil)
		return logfseunknownpath;
	if((e->qid.type & QTDIR) != 0)
		return Eperm;
	if(e->u.file.cvers != s->u.write.cvers)
		return nil;
	ustmuid = logfsisustadd(server->is, s->u.write.muid);
	if(ustmuid == nil)
		return Enomem;
	extent.min = s->u.write.offset;
	extent.max = s->u.write.offset + s->u.write.count;
	extent.flashaddr = s->u.write.flashaddr;
	errmsg = logfsextentlistinsert(e->u.file.extent, &extent, nil);
	if(errmsg)
		return errmsg;
	e->mtime = s->u.write.mtime;
	e->muid = ustmuid;
	if(extent.max > e->u.file.length)
		e->u.file.length = extent.max;
	/* TODO forsyth increments vers here; not sure whether necessary */
	return nil;
}

static char *
rewstat(LogfsServer *server, LogMessage *s, int *ok)
{
	Entry *e;
	char *errmsg;
	char *cname, *ustgid, *ustmuid;
	char *ustuid;

	USED(ok);
	e = logfspathmapfinde(server->pathmap, s->path);
	if(e == nil)
		return logfseunknownpath;
	cname = nil;
	ustuid = nil;
	ustgid = nil;
	ustmuid = nil;
	if(s->u.wstat.name) {
		cname = logfsstrdup(s->u.wstat.name);
		if(cname == nil) {
		memerror:
			errmsg = Enomem;
			goto fail;
		}
	}
	if(s->u.wstat.uid) {
		ustuid = logfsisustadd(server->is, s->u.wstat.uid);
		if(ustuid == nil)
			goto memerror;
	}
	if(s->u.wstat.gid) {
		ustgid = logfsisustadd(server->is, s->u.wstat.gid);
		if(ustgid == nil)
			goto memerror;
	}
	if(s->u.wstat.muid) {
		ustmuid = logfsisustadd(server->is, s->u.wstat.muid);
		if(ustmuid == nil)
			goto memerror;
	}
	if(cname) {
		logfsfreemem(e->name);
		e->name = cname;
		cname = nil;
	}
	if(ustuid)
		e->uid = ustuid;
	if(ustgid)
		e->gid = ustgid;
	if(ustmuid)
		e->muid = ustmuid;
	if(s->u.wstat.perm != ~0)
		e->perm = (e->perm & DMDIR) | (s->u.wstat.perm & ~DMDIR);
	if(s->u.wstat.mtime != ~0)
		e->mtime = s->u.wstat.mtime;
	errmsg = nil;
fail:
	logfsfreemem(cname);
	return errmsg;
}

static char *
replayblock(LogfsServer *server, LogSegment *seg, uchar *buf, long i, int *pagep, int disableerrors)
{
	int page;
	LogfsLowLevel *ll = server->ll;
	LogfsLowLevelReadResult llrr;
	ushort size;
	LogMessage s;
	int ppb = 1 << ll->l2pagesperblock;
	int pagesize = 1 << ll->l2pagesize;

	for(page = 0; page < ppb; page++) {
		uchar *p, *bufend;
		char *errmsg = (*ll->readpagerange)(ll, buf, seg->blockmap[i], page, 0,  pagesize, &llrr);
		if(errmsg)
			return errmsg;
		if(llrr != LogfsLowLevelReadResultOk)
			logfsserverreplacelogblock(server, seg, i);
			/* ignore failure to replace block */
		if(server->trace > 1)
			print("replaying seq %ld block %ld page %d\n", i, seg->blockmap[i], page);
		p = buf;
		if(*p == 0xff)
			break;
		bufend = p + pagesize;
		while(p < bufend) {
			int ok = 1;
			size = logfsconvM2S(p, bufend - p, &s);
			if(size == 0)
				return "parse failure";
			if(server->trace > 1) {
				print(">> ");
				logfsdumpS(&s);
				print("\n");
			}
			if(s.type == LogfsLogTend)
				break;
			switch(s.type) {
			case LogfsLogTstart:
				break;
			case LogfsLogTcreate:
				maxpath(server, s.path);
				maxpath(server, s.u.create.newpath);
				errmsg = recreate(server, &s, &ok);
				break;
			case LogfsLogTtrunc:
				maxpath(server, s.path);
				errmsg = retrunc(server, &s, &ok);
				break;
			case LogfsLogTremove:
				maxpath(server, s.path);
				errmsg = reremove(server, &s, &ok);
				break;
			case LogfsLogTwrite:
				maxpath(server, s.path);
				errmsg = rewrite(server, &s, &ok);
				break;
			case LogfsLogTwstat:
				maxpath(server, s.path);
				errmsg = rewstat(server, &s, &ok);
				break;
			default:
				return "bad tag in log page";
			}
			if(!ok)
				return errmsg;
			if(errmsg && !disableerrors){
				print("bad replay: %s\n", errmsg);
				print("on: "); logfsdumpS(&s); print("\n");
			}
			p += size;
		}
	}
	*pagep = page;
	return nil;
}

static int
map(void *magic, Extent *x, int hole)
{
	LogfsServer *server;
	LogfsLowLevel *ll;
	long seq;
	int page;
	int offset;
	Pageset mask;
	DataBlock *db;

	if(hole || (x->flashaddr & LogAddr) != 0)
		return 1;
	server = magic;
	ll = server->ll;
	logfsflashaddr2spo(server, x->flashaddr, &seq, &page, &offset);
	if(seq >= server->ndatablocks || (db = server->datablock + seq)->block < 0) {
		print("huntfordata: seq %ld invalid\n", seq);
		return 1;
	}
	mask = logfsdatapagemask((x->max - x->min + offset + (1 << ll->l2pagesize) - 1) >> ll->l2pagesize, page);
//print("mask 0x%.8ux free 0x%.8ux dirty 0x%.8ux\n", mask, db->free, db->dirty);
	if((db->free & mask) != mask)
		print("huntfordata: data referenced more than once: block %ld(%ld) free 0x%.8llux mask 0x%.8llux\n",
			seq, db->block, (u64int)db->free, (u64int)mask);
	db->free &= ~mask;
	db->dirty |= mask;
	return 1;
}

static void
huntfordatainfile(LogfsServer *server, Entry *e)
{
	logfsextentlistwalk(e->u.file.extent, map, server);
}

static void
huntfordataindir(LogfsServer *server, Entry *pe)
{
	Entry *e;
	for(e = pe->u.dir.list; e; e = e->next)
		if(e->qid.type & QTDIR)
			huntfordataindir(server, e);
		else
			huntfordatainfile(server, e);
}

char *
logfsreplay(LogfsServer *server, LogSegment *seg, int disableerrorsforfirstblock)
{
	uchar *buf;
	long i;
	int page;
	char *errmsg;

	if(seg == nil || seg->curblockindex < 0)
		return nil;
	buf = logfsrealloc(nil, 1 << server->ll->l2pagesize);
	if(buf == nil)
		return Enomem;
	for(i = 0; i <= seg->curblockindex; i++) {
		errmsg = replayblock(server, seg, buf,  i, &page, disableerrorsforfirstblock);
		disableerrorsforfirstblock = 0;
		if(errmsg) {
			print("logfsreplay: error: %s\n", errmsg);
			goto fail;
		}
	}
	/*
	 * if the last block ended early, restart at the first free page
	 */
	if(page < (1 << server->ll->l2pagesperblock))
		seg->curpage = page;
	errmsg = nil;
fail:
	logfsfreemem(buf);
	return errmsg;
}

void
logfsreplayfinddata(LogfsServer *server)
{
	huntfordataindir(server, &server->root);
	if(server->trace > 0) {
		long i;
		DataBlock *db;
		for(i = 0, db = server->datablock; i < server->ndatablocks; i++, db++) {
			logfsfreeanddirtydatablockcheck(server, i);
			if(db->block >= 0)
				print("%4ld: free 0x%.8llux dirty 0x%.8llux\n", i, (u64int)server->datablock[i].free, (u64int)server->datablock[i].dirty);
		}
	}
}
