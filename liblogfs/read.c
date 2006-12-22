#include "lib9.h"
#include "logfs.h"
#include "local.h"
#include "fcall.h"

struct DirReadState {
	u32int offset;
	u32int lastoffset;
	u32int limit;
	uchar *data;
};

typedef struct ReaderState {
	uchar *buf;
	u32int maxoffset;
	LogfsServer *server;
	char *errmsg;
} ReaderState;

static DirReadState *
drsinit(LogfsIdentityStore *is, Entry *list, uchar *buf, u32int buflen, u32int *rcount)
{
	Entry *p, *q;
	DirReadState *drs;
	u32int k;
	/*
	 * stash as many entries as will fit in the read buffer
	 */
	*rcount = 0;
	for(p = list; p; p = p->next) {
		uint len = logfsflattenentry(is, buf, buflen, p);
		if(len == 0)
			break;
		*rcount += len;
		buf += len;
		buflen -= len;
	}
	drs = logfsrealloc(nil, sizeof(*drs));
	if(drs == nil)
		return nil;
	drs->offset = *rcount;
	drs->lastoffset = drs->offset;
	k = 0;
	for(q = p; q; q = q->next)
		k += logfsflattenentry(is, nil, 0, q);
	if(k) {
		u32int k2;
//		print("drsinit: %ud bytes extra\n", k);
		drs->data = logfsrealloc(nil, k);
		if(drs->data == nil) {
			logfsfreemem(drs);
			return nil;
		}
		k2 = 0;
		for(q = p; q; q = q->next)
			k2 += logfsflattenentry(is, drs->data + k2, k - k2, q);
		drs->limit = drs->offset + k;
	}
//	print("drsinit: rcount %ud\n", *rcount);
	return drs;
}

static void
drsread(DirReadState *drs, uchar *buf, u32int buflen, u32int *rcount)
{
	uchar *p;
	*rcount = 0;
	p = drs->data + drs->lastoffset - drs->offset;
	while(drs->lastoffset < drs->limit) {
		/*
		 * copy an entry, if it fits
		 */
		uint len = GBIT16(p) + BIT16SZ;
		if(len > buflen)
			break;
		memcpy(buf, p, len);
		drs->lastoffset += len;
		*rcount += len;
		buf += len;
		buflen -= len;
		p += len;
	}
	if(drs->lastoffset >= drs->limit) {
		logfsfreemem(drs->data);
		drs->data = nil;
	}
}

void
logfsdrsfree(DirReadState **drsp)
{
	DirReadState *drs = *drsp;
	if(drs) {
		logfsfreemem(drs->data);
		logfsfreemem(drs);
		*drsp = nil;
	}
}

static int
reader(void *magic, u32int baseoffset, u32int limitoffset, Extent *e, u32int extentoffset)
{
	ReaderState *s = magic;
	LogfsServer *server;
	LogfsLowLevel *ll;
	LogfsLowLevelReadResult llrr;
	long seq;
	int page;
	int offset;
	long block;
	int pagesize;
	LogSegment *seg;
	int replace;

	if(e == nil) {
//print("fill(%d, %d)\n", baseoffset, limitoffset);
		memset(s->buf + baseoffset, 0, limitoffset - baseoffset);
		if(limitoffset > s->maxoffset)
			s->maxoffset = limitoffset;
		return 1;
	}
	server = s->server;
	ll = server->ll;
	/*
	 * extentoffset is how much to trim off the front of the extent
	 */
	logfsflashaddr2spo(server, e->flashaddr + extentoffset, &seq, &page, &offset);
	/*
	 * offset is the offset within the page to where e->min is stored
	 */
//print("read(%d, %d, %c%ld/%ud/%ud)\n",
//	baseoffset, limitoffset, (e->flashaddr & LogAddr) ? 'L' :  'D', seq, page, offset);
	if(e->flashaddr & LogAddr) {
		if(seq >= server->activelog->unsweptblockindex && seq <= server->activelog->curblockindex)
			seg = server->activelog;
		else if(server->sweptlog && seq <= server->sweptlog->curblockindex)
			seg = server->sweptlog;
		else {
			print("logfsserverread: illegal log sequence number %ld (active=[%ld, %ld], swept=[%ld, %ld])\n",
				seq, server->activelog->unsweptblockindex, server->activelog->curblockindex,
				server->sweptlog ? 0L : -1L, server->sweptlog ? server->sweptlog->curblockindex : -1L);
			s->errmsg = logfseinternal;
			return -1;
		}
		if(seg->curpage == page && seg->curblockindex == seq) {
			/*
			 * it hasn't made it to disk yet
			 */
			memcpy(s->buf + baseoffset, seg->pagebuf + offset, limitoffset - baseoffset);
			goto done;
		}
		if(seq < seg->unsweptblockindex) {
			/* data already swept */
			print("logfsserverread: log address has been swept\n");
			s->errmsg = logfseinternal;
			return -1;
		}
		block = seg->blockmap[seq];
	}
	else {
		seg = nil;
		if(seq >= server->ndatablocks)
			block = -1;
		else
			block = server->datablock[seq].block;
		if(block < 0) {
			print("logfsserveread: data address does not exist\n");
			s->errmsg = logfseinternal;
			return -1;
		}
	}
	/*
	 * read as many pages as necessary to get to the limitoffset
	 */
	pagesize = 1 << ll->l2pagesize;
	replace = 0;
	while(baseoffset < limitoffset) {
		u32int thistime;
		thistime = pagesize - offset;
		if(thistime > (limitoffset - baseoffset))
			thistime = limitoffset - baseoffset;
		s->errmsg = (*ll->readpagerange)(ll, s->buf + baseoffset, block, page,
			offset, thistime, &llrr);
		if(s->errmsg)
			return -1;
		if(llrr != LogfsLowLevelReadResultOk) {
			replace = 1;
		}
		baseoffset += thistime;
		page++;
		offset = 0;
	}
	if(replace) {
		s->errmsg = logfsserverreplaceblock(server, seg, seq);
		if(s->errmsg)
			return -1;
	}
done:
	if(limitoffset > s->maxoffset)
		s->maxoffset = limitoffset;
	return 1;
}

char *
logfsserverread(LogfsServer *server, u32int fid, u32int offset, u32int count, uchar *buf, u32int buflen, u32int *rcount)
{
	Fid *f;
	Entry *e;
	ReaderState s;
	int rv;

	if(server->trace > 1)
		print("logfsserverread(%ud, %ud, %ud)\n", fid, offset, count);
	f = logfsfidmapfindentry(server->fidmap, fid);
	if(f == nil)
		return logfsebadfid;
	if(f->openmode < 0)
		return logfsefidnotopen;
	if((f->openmode & 3) == OWRITE)
		return logfseaccess;
	if(count > buflen)
		return Etoobig;
	e = f->entry;
	if(e->deadandgone)
		return Eio;
	if(e->qid.type & QTDIR) {
		if(offset != 0) {
			if(f->drs == nil || f->drs->lastoffset != offset)
				return Eio;
			drsread(f->drs, buf, count, rcount);
		}
		else {
			logfsdrsfree(&f->drs);
			f->drs = drsinit(server->is, e->u.dir.list, buf, count, rcount);
			if(f->drs == nil)
				return Enomem;
		}
		return nil;
	}
	if(offset >= e->u.file.length) {
		*rcount = 0;
		return nil;
	}
	s.buf = buf;
	s.server = server;
	s.maxoffset = 0;
	rv = logfsextentlistwalkrange(e->u.file.extent, reader, &s, offset, offset + count);
	if(rv < 0)
		return s.errmsg;
	*rcount = s.maxoffset;
	return nil;
}

