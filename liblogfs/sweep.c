#include "lib9.h"
#include "logfs.h"
#include "local.h"

enum {
	ThrowAway,
	Keep,
	Repack,
	Error,
};

#define setaction(a) if(*actionp < (a)) *actionp = a
#define REPACK setaction(Repack)
#define KEEP setaction(Keep)
#define OPTCOPYEX(name, etag, stag) \
	if(e->etag != s->stag) { \
		s->stag = e->etag; \
		REPACK; \
	}
#define OPTSTRCOPYEX(name, etag, stag) \
	if(strcmp(e->etag, s->stag) != 0) { \
		s->stag = e->etag; \
		REPACK; \
	}

#define OPTCOPY(name, tag, sunion) OPTCOPYEX(name, tag, u.sunion.tag)
#define OPTSTRCOPY(name, tag, sunion) OPTSTRCOPYEX(name, tag, u.sunion.tag)

static char *
sweepcreate(LogfsServer *server, LogMessage *s, int *actionp)
{
	Entry *pe, *e;
	e = logfspathmapfinde(server->pathmap, s->u.create.newpath);
	if(e == nil)
		/* file no longer exists */
		return nil;
	pe = logfspathmapfinde(server->pathmap, s->path);
	if(pe == nil)
		/* file exists but parent doesn't - not good, but can continue */
		return "parent missing";
	if((pe->perm & DMDIR) == 0 || (e->perm & DMDIR) != (s->u.create.perm & DMDIR))
		/* parent must be a directory, and
		 * the directory mode cannot change
		 */
		return logfseinternal;
	if((e->perm & DMDIR) == 0) {
		OPTCOPYEX("cvers", u.file.cvers, u.create.cvers);
	}
	OPTSTRCOPY("name", name, create);
	OPTCOPY("mtime", mtime, create);
	OPTCOPY("perm", perm, create);
	OPTSTRCOPY("uid", uid, create);
	OPTSTRCOPY("gid", gid, create);
	KEEP;
	return nil;
}

static char *
sweepwrite(LogfsServer *server, LogMessage *s, int readoffset, Entry **ep, int *trimp, int *actionp)
{
	Entry *e;
	Extent extent;
	Extent *ext;
	*ep = nil;
	e = logfspathmapfinde(server->pathmap, s->path);
	if(e == nil)
		/* gone, gone */
		return nil;
	if(e->perm & DMDIR)
		return logfseinternal;
	if(e->u.file.cvers != s->u.write.cvers)
		/* trunced more recently */
		return nil;
	extent.min = s->u.write.offset;
	extent.max = extent.min + s->u.write.count;
	extent.flashaddr = s->u.write.flashaddr;
	ext = logfsextentlistmatch(e->u.file.extent, &extent);
	if(ext == nil)
		return nil;
	if(s->u.write.data) {
		/*
		 * trim the front of the data so that when fixing up extents,
		 * flashaddr refers to the first byte
		 */
		int offset;	
		logfsflashaddr2o(server, ext->flashaddr, &offset);
		*trimp = offset - readoffset;
		*ep = e;
	}
	KEEP;
	return nil;
}

typedef struct FixupState {
	LogfsServer *server;
	int oldoffset;
	u32int newflashaddr;
} FixupState;

static int
fixup(void *magic, Extent *e)
{
	FixupState *state = magic;
	int offset;
	logfsflashaddr2o(state->server, e->flashaddr, &offset);
	e->flashaddr = state->newflashaddr + (offset - state->oldoffset);
	return 1;
}

static char *
sweepblock(LogfsServer *server, uchar *buf)
{
	char *errmsg;
	LogSegment *active = server->activelog;
	LogSegment *swept = server->sweptlog;
	int pagesize, ppb, page;
	LogfsLowLevel *ll = server->ll;
	LogfsLowLevelReadResult llrr;
	int markedbad;
	long oblock;

	if(active == nil)
		return nil;
	if(swept == nil) {
		errmsg = logfslogsegmentnew(server, loggensucc(active->gen), &server->sweptlog);
		if(errmsg)
			return errmsg;
		swept = server->sweptlog;
	}
	/*
	 * if this is last block in the active log, flush it, so that the read of the last page works
	 */
	if(active->unsweptblockindex	== active->curblockindex)
		logfslogsegmentflush(server, 1);
	ppb = (1 << ll->l2pagesperblock);
	pagesize = (1 << ll->l2pagesize);
	for(page = 0; page < ppb; page++) {
		uchar *p, *bufend;
		errmsg = (*ll->readpagerange)(ll, buf, active->blockmap[active->unsweptblockindex], page, 0,  pagesize, &llrr);
		if(errmsg)
			goto fail;
		if(llrr != LogfsLowLevelReadResultOk)
			logfsserverreplacelogblock(server, active, active->unsweptblockindex);
		p = buf;
		if(*p == 0xff)
			break;
		bufend = p + pagesize;
		while(p < bufend) {
			int action;
			uint size;
			LogMessage s;
			Entry *e;
			int trim;

			size = logfsconvM2S(p, bufend - p, &s);
			if(size == 0)
				return "parse failure";
			if(server->trace > 1) {
				print("A>> ");
				logfsdumpS(&s);
				print("\n");
			}
			if(s.type == LogfsLogTend)
				break;
			action = ThrowAway;
			switch(s.type) {
			case LogfsLogTstart:
				break;
			case LogfsLogTcreate:
				errmsg = sweepcreate(server, &s, &action);
				break;
			case LogfsLogTremove:
				/* always obsolete; might check that path really doesn't exist */
				break;
			case LogfsLogTtrunc:
				/* always obsolete, unless collecting out of order */
				break;
			case LogfsLogTwrite:
				errmsg = sweepwrite(server, &s, s.u.write.data ? s.u.write.data - buf : 0, &e, &trim, &action);
				break;
			case LogfsLogTwstat:
				/* always obsolete, unless collecting out of order */
				break;
			default:
				return "bad tag in log page";
			}
			if(action == Error)
				return errmsg;
			if(errmsg)
				print("bad sweep: %s\n", errmsg);
			if(action == Keep)
				action = Repack;		/* input buffer has been wrecked, so can't just copy it */
			if(action == Keep) {
				/* write 'size' bytes to log */
				errmsg = logfslogbytes(server, 0, p, size);
				if(errmsg)
					goto fail;
			}
			else if(action == Repack) {
				/* TODO - handle writes */
				if(s.type == LogfsLogTwrite && s.u.write.data) {
					FixupState state;
					errmsg = logfslogwrite(server, 0, s.path, s.u.write.offset + trim, s.u.write.count - trim,
						s.u.write.mtime, s.u.write.cvers,
						s.u.write.muid, s.u.write.data + trim, &state.newflashaddr);
					if(errmsg == nil && s.u.write.data != nil) {
						Extent extent;
						/* TODO - deal with a failure to write the changes */
						state.oldoffset = s.u.write.data - buf + trim;
						state.server = server;
						extent.min = s.u.write.offset;
						extent.max = extent.min + s.u.write.count;
						extent.flashaddr = s.u.write.flashaddr;
						logfsextentlistmatchall(e->u.file.extent, fixup, &state, &extent);
					}
				}
				else
					errmsg = logfslog(server, 0, &s);
				if(errmsg)
					goto fail;
			}
			p += size;
		}
	}
	/*
	 * this log block is no longer needed
	 */
	oblock = active->blockmap[active->unsweptblockindex++];
	errmsg = logfsbootfettleblock(server->lb, oblock, LogfsTnone, ~0, &markedbad);
	if(errmsg)
		goto fail;
	if(active->unsweptblockindex  > active->curblockindex) {
		/*
		 * the activelog is now empty, so make the sweptlog the active one
		 */
		logfslogsegmentfree(&active);
		server->activelog = swept;
		server->sweptlog = nil;
		swept->dirty = 0;
	}
	return nil;
fail:
	return errmsg;
}

char *
logfsserverlogsweep(LogfsServer *server, int justone, int *didsomething)
{
	uchar *buf;
	char *errmsg;

	/*
	 * TODO - is it even worth doing?
	 */
	*didsomething = 0;
	if(!server->activelog->dirty)
		return nil;
	buf = logfsrealloc(nil, (1 << server->ll->l2pagesize));
	if(buf == nil)
		return Enomem;
	errmsg = nil;
	while(server->activelog->unsweptblockindex <= server->activelog->curblockindex) {
		errmsg = sweepblock(server, buf);
		if(errmsg)
			break;
		if(server->sweptlog == nil || justone)
			break;
	}
	logfsfreemem(buf);
	*didsomething = 1;
	return errmsg;
}
