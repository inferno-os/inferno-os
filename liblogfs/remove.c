#include "lib9.h"
#include "logfs.h"
#include "local.h"

void
logfsfreeanddirtydatablockcheck(LogfsServer *server, long seq)
{
	DataBlock *db;
	u32int mask;

	if(seq >= server->ndatablocks)
		return;
	db = server->datablock + seq;
	if(db->block < 0)
		return;

	mask = db->dirty & db->free;
	if(mask) {
		u32int allpages = logfsdatapagemask(1 << server->ll->l2pagesperblock, 0);
		if((mask & allpages) == allpages) {
//print("logfsfreedatapages: returning block to the wild\n");
			logfsbootfettleblock(server->lb, db->block, LogfsTnone, ~0, nil);
			db->block = -1;
			if(seq == server->ndatablocks - 1)
				server->ndatablocks--;
		}
	}
}

void
logfsfreedatapages(LogfsServer *server, long seq, u32int mask)
{
	DataBlock *db;
	if(seq >= server->ndatablocks)
		return;
	db = server->datablock + seq;
	if(db->block < 0)
		return;
//print("logfsfreedatapages: index %ld mask 0x%.8ux\n", seq, mask);
	db->dirty |= mask;
	db->free |= mask;
	logfsfreeanddirtydatablockcheck(server, seq);
}

int
logfsunconditionallymarkfreeanddirty(void *magic, Extent *e, int hole)
{
	if(!hole && (e->flashaddr & LogAddr) == 0) {
		LogfsServer *server = magic;
		LogfsLowLevel *ll = server->ll;
		DataBlock *db;
		long blockindex;
		int page, offset;
		logfsflashaddr2spo(server, e->flashaddr, &blockindex, &page, &offset);
		if(blockindex < server->ndatablocks && (db = server->datablock + blockindex)->block >= 0) {
			int npages = ((offset + e->max - e->min) + (1 << ll->l2pagesize) - 1) >> ll->l2pagesize;
			u32int mask = logfsdatapagemask(npages, page);
			if((db->dirty & mask) != mask)
				print("markfreeandirty: not all pages dirty\n");
//print("markfreeanddirty: datablock %ld mask 0x%.8ux\n", blockindex, mask);
			logfsfreedatapages(server, blockindex, mask);
		}
		else
			print("markfreeanddirty: data block index %ld invalid\n", blockindex);
	}
	return 1;
}

char *
logfsserverremove(LogfsServer *server, u32int fid)
{
	Fid *f;
	char *errmsg;
	Entry *parent;
	Entry *e, **ep;
	ulong now;
	char *uid;
	LogMessage s;

	if(server->trace > 1)
		print("logfsserverremove(%ud)\n", fid);
	f = logfsfidmapfindentry(server->fidmap, fid);
	if(f == nil) {
		errmsg = logfsebadfid;
		goto clunk;
	}
	if((f->openmode & 3) == OWRITE) {
		errmsg = logfseaccess;
		goto clunk;
	}
	parent = f->entry->parent;
	if(parent == f->entry) {
		errmsg = Eperm;
		goto clunk;
	}
	if((parent->qid.type & QTDIR) == 0) {
		errmsg = logfseinternal;
		goto clunk;
	}
	if(!logfsuserpermcheck(server, parent, f, DMWRITE)) {
		errmsg = Eperm;
		goto clunk;
	}
	if((f->entry->qid.type & QTDIR) != 0 && f->entry->u.dir.list) {
		errmsg = logfsenotempty;
		goto clunk;
	}
	if(f->entry->deadandgone) {
		errmsg = Eio;
		goto clunk;
	}
	for(ep = &parent->u.dir.list; e = *ep; ep = &e->next)
		if(e == f->entry)
			break;
	if(e == nil) {
		errmsg = logfseinternal;
		goto clunk;
	}
	now = logfsnow();
	uid = logfsisfindidfromname(server->is, f->uname);
	/* log it */
	s.type = LogfsLogTremove;
	s.path = e->qid.path;
	s.u.remove.mtime = e->mtime;
	s.u.remove.muid = e->muid;
	errmsg = logfslog(server, 1, &s);
	if(errmsg)
		goto clunk;
	parent->mtime = now;
	parent->muid = uid;
	logfspathmapdeleteentry(server->pathmap, e->qid.path);
	*ep = e->next;				/* so open can't find it */
	e->deadandgone = 1;		/* so that other fids don't work any more */
	/*
	 * lose the storage now, as deadandgone will prevent access
	 */
	if((e->qid.type & QTDIR) == 0) {
		logfsextentlistwalk(e->u.file.extent, logfsunconditionallymarkfreeanddirty, server);
		logfsextentlistfree(&e->u.file.extent);
	}
	e->inuse--;				/* so that the entryclunk removes the storage */
	errmsg = nil;
clunk:
	logfsfidmapclunk(server->fidmap, fid);
	return errmsg;
}

