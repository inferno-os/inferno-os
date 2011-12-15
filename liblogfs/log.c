#include "logfsos.h"
#include "logfs.h"
#include "local.h"
#include "fcall.h"

void
logfsflashaddr2spo(LogfsServer *server, u32int flashaddr, long *seq, int *page, int *offset)
{
	LogfsLowLevel *ll = server->ll;
	flashaddr &= ~LogAddr;
	*offset = flashaddr & ((1 << ll->l2pagesize) - 1);
	flashaddr >>= ll->l2pagesize;
	*page = flashaddr & ((1 << ll->l2pagesperblock) - 1);
	flashaddr >>= ll->l2pagesperblock;
	*seq = flashaddr;
}

u32int
logfsspo2flashaddr(LogfsServer *server, long seq, int page, int offset)
{
//print("logfsspo2flashaddr(%ld, %d, %d)\n", seq, page, offset);
	return (((seq << server->ll->l2pagesperblock) + page) << server->ll->l2pagesize) + offset;
}

void
logfsflashaddr2o(LogfsServer *server, u32int flashaddr, int *offset)
{
	LogfsLowLevel *ll = server->ll;
	flashaddr &= ~LogAddr;
	*offset = flashaddr & ((1 << ll->l2pagesize) - 1);
}

char *
logfslogsegmentnew(LogfsServer *server, int gen, LogSegment **segp)
{
	LogSegment *seg;
	seg = logfsrealloc(nil, sizeof(LogSegment) + (server->ll->blocks - 1) * sizeof(long));
	if(seg == nil)
		return Enomem;
	seg->pagebuf = logfsrealloc(nil, 1 << server->ll->l2pagesize);
	if(seg->pagebuf == nil) {
		logfsfreemem(seg);
		return Enomem;
	}
	seg->curpage = -1;
	seg->curblockindex = -1;
	seg->gen = gen;
	*segp = seg;
	return nil;
}

void
logfslogsegmentfree(LogSegment **segp)
{
	LogSegment *seg = *segp;
	if(seg) {
		logfsfreemem(seg->pagebuf);
		logfsfreemem(seg);
		*segp = nil;
	}
}

char *
logfslogsegmentflush(LogfsServer *server, int active)
{
	LogSegment *seg;
	seg = active ? server->activelog : server->sweptlog;
	if(seg == nil)
		return nil;
	if(seg->curpage >= 0 && seg->nbytes) {
		char *errmsg;
		LogfsLowLevel *ll = server->ll;
		int pagesize = 1 << ll->l2pagesize;
//print("curblockindex %ld curpage %d nbytes %d\n", seg->curblockindex, seg->curpage, seg->nbytes);
		if(seg->nbytes < pagesize)
			seg->pagebuf[seg->nbytes++] = LogfsLogTend;
		memset(seg->pagebuf + seg->nbytes, 0xff, pagesize - seg->nbytes);
		for(;;) {
			errmsg = (*ll->writepage)(ll, seg->pagebuf,
				seg->blockmap[seg->curblockindex], seg->curpage);
			if(errmsg == nil)
				break;
			if(strcmp(errmsg, Eio) != 0)
				return errmsg;
			errmsg = logfsserverreplacelogblock(server, seg, seg->curblockindex);
			if(errmsg)
				return errmsg;
		}
		seg->curpage++;
		if(seg->curpage == (1 << ll->l2pagesperblock))
			seg->curpage = -1;
		seg->nbytes = 0;
	}
	return nil;
}

static char *
logspace(LogfsServer *server, int active, int takearisk, int nbytes, uchar **where, u32int *flashaddr)
{
	char *errmsg;
	LogfsLowLevel *ll = server->ll;
	int pagesize = 1 << ll->l2pagesize;
	LogSegment *seg;

	if(nbytes > pagesize)
		return logfselogmsgtoobig;
retry:
	seg = active ? server->activelog : server->sweptlog;
	for(;;) {
//print("curpage %d nbytes %d\n", seg->curpage, seg->nbytes);
		if(seg->curpage >= 0) {
			if(seg->nbytes + nbytes < pagesize)
				break;
			errmsg = logfslogsegmentflush(server, active);
			if(errmsg)
				return errmsg;
		}
		if(seg->curpage < 0) {
			long block;
			long path;
			block = logfsfindfreeblock(ll,
				active ? (takearisk ? AllocReasonLogExtend : AllocReasonDataExtend) : AllocReasonTransfer);
			if(block < 0) {
				if(active) {
					int didsomething;
					errmsg = logfsserverlogsweep(server, 0, &didsomething);
					if(errmsg)
						return errmsg;
					if(didsomething)
						goto retry;
				}
				return logfselogfull;
			}
			seg->blockmap[++seg->curblockindex] = block;
			path = mklogpath(seg->curblockindex, seg->gen, 0);
			(*ll->setblocktag)(ll, block, LogfsTlog);
			(*ll->setblockpath)(ll, block, path);
			seg->curpage = 0;
#ifdef FUTURE
			/* TODO - do we need one of these if the underlying system supports erase counting? */
			seg->pagebuf[0] = LogfsLogTstart;
			PBIT16(seg->pagebuf + 1, 8);
			PBIT32(seg->pagebuf + 3, path);	/* TODO duplicate information */
			PBIT32(seg->pagebuf + 7, 0);		/* TODO don't have this - discuss with forsyth */
			seg->nbytes = 11;
#else
			seg->nbytes = 0;
#endif
		}
	}
	*where = seg->pagebuf + seg->nbytes;
	if(flashaddr)
		*flashaddr = logfsspo2flashaddr(server, seg->curblockindex, seg->curpage, seg->nbytes);
	seg->nbytes += nbytes;
	return nil;
}

static void
logdirty(LogfsServer *server, int active)
{
	if(active)
		server->activelog->dirty = 1;
	else
		server->sweptlog->dirty = 1;
}

char *
logfslogbytes(LogfsServer *server, int active, uchar *msg, uint size)
{
	char *errmsg;
	uchar *p;

	errmsg = logspace(server, active, 0, size, &p, nil);
	if(errmsg)
		return errmsg;
	memmove(p, msg, size);
	logdirty(server, active);
	return nil;
}

char *
logfslog(LogfsServer *server, int active, LogMessage *s)
{
	uint size = logfssizeS2M(s);
	char *errmsg;
	uchar *p;
	int takearisk;

	if(server->trace > 1) {
		print("%c<< ", active ? 'A' : 'S');
		logfsdumpS(s);
		print("\n");
	}
	if(active) {
		switch(s->type) {
		case LogfsLogTremove:
		case LogfsLogTtrunc:
			takearisk = 1;
			break;
		default:
			takearisk = 0;
		}
	}
	else
		takearisk = 0;
	errmsg = logspace(server, active, takearisk, size, &p, nil);
	if(errmsg)
		return errmsg;
	if(logfsconvS2M(s, p, size) != size)
		return "bad conversion";
	logdirty(server, active);
	return nil;
}

int
lognicesizeforwrite(LogfsServer *server, int active, u32int count, int muidlen)
{
	int rawspace;
	LogSegment *seg;
	if(count > LogDataLimit)
		return 0;
	seg = active ? server->activelog : server->sweptlog;
	if(seg->curpage < 0)
		return LogDataLimit;
	rawspace = (1 << server->ll->l2pagesize) - seg->nbytes;
	if(rawspace < 5 * 4 + 2 + muidlen + 1)
		return LogDataLimit;
	return 5 * 4 + 2 + muidlen - rawspace;
}

char *
logfslogwrite(LogfsServer *server, int active, u32int path, u32int offset, int count, u32int mtime, u32int cvers,
	char *muid, uchar *data, u32int *flashaddr)
{
	/* 'w' size[2] path[4] offset[4] count[2] mtime[4] cvers[4] muid[s] flashaddr[4] [data[n]] */
	LogMessage s;
	uint size;
	char *errmsg;
	uchar *p;
	u32int faddr;
	uint asize;

	s.type = LogfsLogTwrite;
	s.path = path;
	s.u.write.offset = offset;
	s.u.write.count = count;
	s.u.write.mtime = mtime;
	s.u.write.cvers = cvers;
	s.u.write.muid = muid;
	s.u.write.data = data;
	size = logfssizeS2M(&s);
	errmsg = logspace(server, active, 0, size, &p, &faddr);
	if(errmsg)
		return errmsg;
	if(data)
		*flashaddr = (faddr + size - count) | LogAddr;
	s.u.write.flashaddr = *flashaddr;
	if(server->trace > 1) {
		print("%c<< ", active ? 'A' : 'S');
		logfsdumpS(&s);
		print("\n");
	}
	if((asize = logfsconvS2M(&s, p, size)) != size) {
		print("expected %d actual %d\n", size, asize);
		return "bad conversion";
	}
	logdirty(server, active);
	return nil;
}

