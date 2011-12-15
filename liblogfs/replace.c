#include "logfsos.h"
#include "logfs.h"
#include "local.h"
#include "fcall.h"

static char *
copypages(LogfsServer *server, long newb, long oldb, Pageset copymask, LogfsLowLevelReadResult *llrrp, int *markedbadp)
{
	char *errmsg;
	int page;
	LogfsLowLevel *ll;
	int ppb;
	int pagesize;
	uchar *buf;

	if(copymask == 0)
		return nil;

	ll = server->ll;
	ppb = 1 << ll->l2pagesperblock;
	pagesize = 1 << ll->l2pagesize;
	*markedbadp = 0;
	*llrrp = LogfsLowLevelReadResultOk;
	errmsg = nil;

	buf = logfsrealloc(nil, 1 << ll->l2pagesize);
	if(buf == nil)
		return Enomem;

	for(page = ppb - 1; page >= 0; page--) {
		Pageset m;

		m = logfsdatapagemask(1, page);

		if(copymask & m) {
			LogfsLowLevelReadResult llrr;
			if(server->trace > 1)
				print("copypages read page %d\n", page);
			errmsg = (*ll->readpagerange)(ll, buf, oldb, page, 0, pagesize, &llrr);
			if(errmsg != nil)
				break;
			if(llrr > *llrrp)
				*llrrp = llrr;
			if(server->trace > 1)
				print("copypages write page %d\n", page);
			errmsg = (*ll->writepage)(ll, buf, newb, page);
			if(errmsg) {
				if(strcmp(errmsg, Eio) == 0) {
					(*ll->markblockbad)(ll, newb);
					*markedbadp = 1;
				}
				break;
			}
			if(server->trace > 1)
				print("copypages end page %d\n", page);
		}
	}
	logfsfreemem(buf);
	return errmsg;
}

char *
logfsservercopyactivedata(LogfsServer *server, long newb, long oldblockindex, int forcepage0, LogfsLowLevelReadResult *llrrp, int *markedbadp)
{
	LogfsLowLevel *ll = server->ll;
	ulong newpath;
	DataBlock *ob;
	char *errmsg;
	Pageset copymask;

	ob = server->datablock + oldblockindex;
	copymask = ~ob->free;
	if(forcepage0)
		copymask |= logfsdatapagemask(1, 0);
	if(server->trace > 1)
		print("copyactivedata %ld: (%ld -> %ld)\n", oldblockindex, ob->block, newb);
	newpath = mkdatapath(dataseqof(ob->path), copygensucc(copygenof(ob->path)));
	(*ll->setblocktag)(ll, newb, LogfsTdata);
	(*ll->setblockpath)(ll, newb, newpath);
	errmsg = copypages(server, newb, ob->block, copymask, llrrp, markedbadp);
	if(errmsg)
		return errmsg;
	/*
	 * anything not copied is now not dirty
	 */
	ob->dirty &= copymask;
	ob->block = newb;
	ob->path = newpath;
	return nil;
}

/*
 * unconditionally replace a datablock, and mark the old one bad
 * NB: if page 0 is apparently unused, force it to be copied, and mark
 * it free and dirty afterwards
 */
char *
logfsserverreplacedatablock(LogfsServer *server, long index)
{
	long newb;
	LogfsLowLevel *ll = server->ll;

	newb = logfsfindfreeblock(ll, AllocReasonReplace);
	/* TODO - recover space by scavenging other blocks, or recycling the log */
	while(newb >= 0) {
		char *errmsg;
		LogfsLowLevelReadResult llrr;
		long oldblock;
		int markedbad;
		DataBlock *db;

		db = server->datablock + index;
		oldblock = db->block;
		errmsg = logfsservercopyactivedata(server, newb, index, 1, &llrr, &markedbad);
		if(errmsg) {
			if(!markedbad)
				return errmsg;
			newb = logfsfindfreeblock(ll, AllocReasonReplace);
			continue;
		}
		(*ll->markblockbad)(ll, oldblock);
		return nil;
	}
	return logfsefullreplacing;
}

char *
logfsserverreplacelogblock(LogfsServer *server, LogSegment *seg, long index)
{
	ulong opath;
	LogfsLowLevel *ll = server->ll;
	long oldb = seg->blockmap[index];

	opath = (*ll->getblockpath)(ll, oldb);

	for(;;) {
		long newb;
		int pages;
		char *errmsg;
		LogfsLowLevelReadResult llrr;
		int markedbad;

		newb  = logfsfindfreeblock(ll, AllocReasonReplace);
		if(newb < 0)
			return "full replacing log block";
		/* TODO - scavenge data space for a spare block */
		(*ll->setblocktag)(ll, newb, LogfsTlog);
		(*ll->setblockpath)(ll, newb, mklogpath(seg->gen, index, copygensucc(copygenof(opath))));
		if(index == seg->curblockindex)
			pages = seg->curpage;
		else
			pages = 1 << server->ll->l2pagesperblock;
		errmsg = copypages(server, newb, oldb, logfsdatapagemask(pages, 0), &llrr, &markedbad);
		if(errmsg == nil) {
			(*ll->markblockbad)(ll, seg->blockmap[index]);
			seg->blockmap[index] = newb;
			return nil;
		}
		if(!markedbad)
			return errmsg;
	}
}

char *
logfsserverreplaceblock(LogfsServer *server, LogSegment *seg, long index)
{
	if(seg)
		return logfsserverreplacelogblock(server, seg, index);
	else
		return logfsserverreplacedatablock(server, index);
}
