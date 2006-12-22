#include "lib9.h"
#include "logfs.h"
#include "local.h"

struct LogfsBoot {
	LogfsLowLevel *ll;
	long bootblocks;
	long blocksize;
	long size;
	long *map;
	int trace;
	int printbad;
//	ulong bootpathmask;
//	int bootgenshift;
};

typedef struct LogfsBootPath LogfsBootPath;

//#define LogfsBootGenBits 2
//#define LogfsBootGenMask ((1 << LogfsBootGenBits) - 1)
#define LogfsBootGenMask ((1 << L2BlockCopies) - 1)

struct LogfsBootPath {
	ulong path;
	uchar gen;
};

#define LOGFSMKBOOTPATH(lb, p) mkdatapath((p)->path, (p)->gen)
#define LOGFSSPLITBOOTPATHEX(bgs, bpm, p, v) ((p)->path = dataseqof(v), (p)->gen = copygenof(v))
#define LOGFSSPLITBOOTPATH(lb, p, v) LOGFSSPLITBOOTPATHEX(0, 0, p, v)

//#define LOGFSMKBOOTPATH(lb, p) (((p)->path & (lb)->bootpathmask) | (((p)->gen & LogfsBootGenMask) << (lb)->bootgenshift))
//#define LOGFSSPLITBOOTPATHEX(bgs, bpm, p, v) ((p)->path = (v) & (bpm), (p)->gen = ((v) >> (bgs)) & LogfsBootGenMask) 
//#define LOGFSSPLITBOOTPATH(lb, p, v) LOGFSSPLITBOOTPATHEX((lb)->bootgenshift, (lb)->bootpathmask, p, v)

extern LogfsBootPath logfsbooterasedpath;

static char Ecorrupt[] = "filesystem corrupt";
static char Enospc[] = "no free blocks";
static char Eaddress[] = "address out of range";

static char *
logfsbootblockupdate(LogfsBoot *lb, void *buf, LogfsBootPath *path, uchar tag, ulong block)
{
	LogfsLowLevel *ll =  lb->ll;
	char *errmsg;
	ulong packedpath;

	if(lb->trace > 1)
		print("logfsbootblockupdate: path 0x%.8lux(%d) tag %s block %lud\n",
		    path->path, path->gen, logfstagname(tag), block);

	packedpath = LOGFSMKBOOTPATH(lb, path);
	errmsg = (*ll->writeblock)(ll, buf, tag, packedpath, 1, &lb->bootblocks, block);

	if(errmsg) {
		/*
		 * ensure block never used again until file system reinitialised
		 * We have absolutely no idea what state it's in. This is most
		 * likely if someone turns off the power (or at least threatens
		 * the power supply), during a block update. This way the block
		 * is protected until the file system in reinitialised. An alternative
		 * would be check the file system after a power fail false alarm,
		 * and erase any Tworse blocks
		 */
		(*ll->setblocktag)(ll, block, LogfsTworse);
		return errmsg;
	}
		
	(*ll->setblocktag)(ll, block, tag);
	(*ll->setblockpath)(ll, block, packedpath);

	return nil;
}

char *
logfsbootfettleblock(LogfsBoot *lb, long block, uchar tag, long path, int *markedbad)
{
	LogfsLowLevel *ll = lb->ll;
	char *errmsg;
	void *llsave;

	errmsg = (*ll->eraseblock)(ll, block, &llsave, markedbad);
	if(errmsg || (markedbad && *markedbad)) {
		logfsfreemem(llsave);
		return errmsg;
	}
	errmsg = (*ll->reformatblock)(ll, block, tag, path, 1, &lb->bootblocks, llsave, markedbad);
	logfsfreemem(llsave);
	return errmsg;
}

/*
 * block transfer is the critical unit of update
 * we are going to assume that page writes and block erases are atomic
 * this can pretty much be assured by not starting a page write or block erase
 * if the device feels it is in power fail
 */

static char *
logfsbootblocktransfer(LogfsBoot *lb, void *buf, ulong oldblock, int markbad)
{
	LogfsLowLevel *ll = lb->ll;
	long bestnewblock;
	ulong oldpackedpath;
	LogfsBootPath oldpath;
	short oldtag;
	char *errmsg;
	int markedbad;

	oldpackedpath = (*ll->getblockpath)(ll, oldblock);
	oldtag = (*ll->getblocktag)(ll, oldblock);

	LOGFSSPLITBOOTPATH(lb, &oldpath, oldpackedpath);

	for(;;) {
		LogfsBootPath newpath;

		bestnewblock = logfsfindfreeblock(ll, markbad ? AllocReasonReplace : AllocReasonTransfer);
		if(lb->trace > 0 && markbad)
			print("logfsbootblocktransfer: block %lud is bad, copying to %ld\n",
				oldblock, bestnewblock);
		if(lb->trace > 1 && !markbad)
			print("logfsbootblocktransfer: copying block %lud to %ld\n",
				oldblock, bestnewblock);
		if(bestnewblock == -1)
			return Enospc;
		newpath = oldpath;
//		newpath.gen = (newpath.gen + 1) & LogfsBootGenMask;
		newpath.gen = copygensucc(newpath.gen);
		errmsg = logfsbootblockupdate(lb, buf, &newpath, oldtag, bestnewblock);
		if(errmsg == nil)
			break;
		if(strcmp(errmsg, Eio) != 0)
			return errmsg;
		(*ll->markblockbad)(ll, bestnewblock);
	}

#ifdef LOGFSTEST
	if(logfstest.partialupdate) {
		print("skipping erase\n");
		logfstest.partialupdate = 0;
		return nil;
	}
	if(logfstest.updatenoerase) {
		print("skipping erase\n");
		logfstest.updatenoerase = 0;
		return nil;
	}
#endif

	if(oldtag == LogfsTboot)
		lb->map[oldpath.path] = bestnewblock;

	return logfsbootfettleblock(lb, oldblock, LogfsTnone, ~0, &markedbad);
}

static char *
logfsbootblockread(LogfsBoot *lb, void *buf, long block, LogfsLowLevelReadResult *blocke)
{
	LogfsLowLevel *ll = lb->ll;
	char *errmsg;

	*blocke = LogfsLowLevelReadResultOk;
	errmsg = (*ll->readblock)(ll, buf, block, blocke);
	if(errmsg)
		return errmsg;

	if(*blocke != LogfsLowLevelReadResultOk) {
		char *errmsg = logfsbootblocktransfer(lb, buf, block, 1);
		if(errmsg)
			return errmsg;
	}

	if(*blocke == LogfsLowLevelReadResultHardError)
		return Eio;

	return nil;
}

char *
logfsbootread(LogfsBoot *lb, void *buf, long n, ulong offset)
{
	int i;

	if(lb->trace > 0)
		print("logfsbootread(0x%.8lux, 0x%lx, 0x%lux)\n", (ulong)buf, n, offset);
	if(offset % lb->blocksize || n % lb->blocksize)
		return Eio;
	n /= lb->blocksize;
	offset /= lb->blocksize;
	if(offset + n > lb->bootblocks)
		return Eio;
	for(i = 0; i < n; i++) {
		LogfsLowLevelReadResult result;
		char *errmsg = logfsbootblockread(lb, buf, lb->map[offset + i], &result);
		if(errmsg)
			return errmsg;
		buf = (uchar *)buf + lb->blocksize;
	}
	return nil;
}

static char *
logfsbootblockreplace(LogfsBoot *lb, void *buf, ulong logicalblock)
{
	uchar *oldblockbuf;
	ulong oldblock;
	char *errmsg;
	LogfsLowLevelReadResult result;

	oldblock = lb->map[logicalblock];
	oldblockbuf = logfsrealloc(nil, lb->blocksize);
	if(oldblockbuf == nil)
		return Enomem;

	errmsg = logfsbootblockread(lb, oldblockbuf, oldblock, &result);
	if(errmsg == nil && memcmp(oldblockbuf, buf, lb->blocksize) != 0)
		errmsg = logfsbootblocktransfer(lb, buf, oldblock, 0);

	logfsfreemem(oldblockbuf);
	return errmsg;
}

char *
logfsbootwrite(LogfsBoot *lb, void *buf, long n, ulong offset)
{
	int i;

	if(lb->trace > 0)
		print("logfsbootwrite(0x%.8lux, 0x%lux, 0x%lux)\n", (ulong)buf, n, offset);
	/*
	 * don't even get started on a write if the power has failed
	 */
	if(offset % lb->blocksize || n % lb->blocksize)
		return Eio;
	n /= lb->blocksize;
	offset /= lb->blocksize;
	if(offset + n > lb->bootblocks)
		return Eio;
	for(i = 0; i < n; i++) {
		logfsbootblockreplace(lb, buf, offset + i);
		buf = (uchar *)buf + lb->blocksize;
	}
	return nil;
}

char *
logfsbootio(LogfsBoot *lb, void *buf, long n, ulong offset, int write)
{
	return (write ? logfsbootwrite : logfsbootread)(lb, buf, n, offset);
}

static char *
eraseandformatblock(LogfsBoot *lb, long block, int trace)
{
	char *errmsg;
	int markedbad;

	errmsg = logfsbootfettleblock(lb, block, LogfsTnone, ~0, &markedbad);
	if(errmsg)
		return errmsg;
	if(markedbad && trace > 1)
		print("erase/format failed - marked bad\n");
	return nil;
}

char *
logfsbootopen(LogfsLowLevel *ll, long base, long limit, int trace, int printbad, LogfsBoot **lbp)
{
	long *reversemap;
	ulong blocksize;
	ulong blocks;
	long i;
	long bootblockmax;
	LogfsBoot *lb = nil;
	ulong baseblock;
	char *errmsg;
//	int bootgenshift = ll->pathbits- LogfsBootGenBits;
//	ulong bootpathmask = (1 << (ll->pathbits - LogfsBootGenBits)) - 1;
	long expectedbootblocks;

	errmsg = (*ll->open)(ll, base, limit, trace, 1, &expectedbootblocks);
	if(errmsg)
		return errmsg;

	bootblockmax = -1;
	blocks = ll->blocks;
	baseblock = (*ll->getbaseblock)(ll);
	blocksize = (*ll->getblocksize)(ll);

	for(i = 0; i < blocks; i++) {
		if((*ll->getblocktag)(ll, i) == LogfsTboot) {
			long path = (*ll->getblockpath)(ll, i);
			LogfsBootPath lp;
			LOGFSSPLITBOOTPATHEX(bootgenshift, bootpathmask, &lp, path);
			if((long)lp.path > bootblockmax)
				bootblockmax = lp.path;
		}
	}
	if(bootblockmax + 1 >= blocks) {
		if(printbad)
			print("logfsbootinit: bootblockmax %ld exceeds number of blocks\n", bootblockmax);
		return Ecorrupt;
	}
	if(bootblockmax < 0) {
		if(printbad)
			print("logfsbootopen: no boot area\n");
		return Ecorrupt;
	}
	if(bootblockmax + 1 != expectedbootblocks) {
		if(printbad)
			print("logfsbootopen: wrong number of bootblocks (found %lud, expected %lud)\n",
				bootblockmax + 1, expectedbootblocks);
	}
		
	reversemap = logfsrealloc(nil, sizeof(*reversemap) * (bootblockmax + 1));
	if(reversemap == nil)
		return Enomem;

	for(i = 0; i <= bootblockmax; i++)
		reversemap[i] = -1;
	for(i = 0; i < blocks; i++) {
		LogfsBootPath ipath;
		long rm;
		ulong ip;

		if((*ll->getblocktag)(ll, i) != LogfsTboot)
			continue;
		ip = (*ll->getblockpath)(ll, i);
		LOGFSSPLITBOOTPATHEX(bootgenshift, bootpathmask, &ipath, ip);
		rm = reversemap[ipath.path];
		if(rm != -1) {
			if(printbad)
				print("logfsbootopen: blockaddr 0x%.8lux: path %ld(%d): duplicate\n",
					blocksize * (baseblock + i), ipath.path, ipath.gen);
			/*
			 * resolve collision
			 * if this one is partial, then erase it
			 * if the existing one is partial, erase that
			 * if both valid, give up
			 */
			if((*ll->getblockpartialformatstatus)(ll, i)) {
				errmsg = eraseandformatblock(lb, i, trace);
				if(errmsg)
					goto error;
			}
			else if((*ll->getblockpartialformatstatus)(ll, rm)) {
				errmsg = eraseandformatblock(lb, rm, trace);
				if(errmsg)
					goto error;
				reversemap[ipath.path] = i;
			}
			else {
				int d;
				ulong rmp;
				LogfsBootPath rmpath;
				rmp = (*ll->getblockpath)(ll, rm);
				LOGFSSPLITBOOTPATHEX(bootgenshift, bootpathmask, &rmpath, rmp);
				d = (ipath.gen - rmpath.gen) & LogfsBootGenMask;
				if(printbad)
					print("i.gen = %d rm.gen = %d d = %d\n", ipath.gen, rmpath.gen, d);
				if(d == 1) {
					/* i is newer;
					 * keep the OLDER one because
					 * we might have had a write failure on the last page, but lost the
					 * power before being able to mark the first page bad
					 * if, worse, the auxiliary area's tag is the same for first and last page,
					 * this looks like a successfully written page. so, we cannot believe the
					 * data in the newer block unless we erased the old one, and then of
					 * course, we wouldn't have a duplicate.
					 */
					errmsg = eraseandformatblock(lb, i, trace);
					if(errmsg)
						goto error;
				}
				else if(d == LogfsBootGenMask) {
					/* rm is newer */
					errmsg = eraseandformatblock(lb, rm, trace);
					if(errmsg)
						goto error;
					reversemap[ipath.path] = i;
				}
				else {
					errmsg = Ecorrupt;
					goto error;
				}
			}
		}
		else
			reversemap[ipath.path] = i;
	}
	/*
	 * final checks; not partial blocks, and no holes
	 */
	for(i = 0; i <= bootblockmax; i++) {
		long rm;
		rm = reversemap[i];
		if(rm == -1) {
			if(printbad)
				print("logfsbootopen: missing boot block %ld\n", i);
			errmsg = Ecorrupt;
			goto error;
		}
		if((*ll->getblockpartialformatstatus)(ll, rm)) {
			if(printbad)
				print("logfsbootopen: boot block %ld partially written\n", rm);
			errmsg = Ecorrupt;
			goto error;
		}
	}
	/* the reverse map is consistent */
	lb = logfsrealloc(nil, sizeof(*lb));
	if(lb == nil) {
		errmsg = Enomem;
		goto error;
	}

	lb->blocksize = blocksize;
	lb->bootblocks = bootblockmax + 1;
	lb->map = reversemap;
	lb->trace = trace;
	lb->printbad = printbad;
	lb->ll = ll;
	lb->size = blocksize * lb->bootblocks;
//	lb->bootgenshift = bootgenshift;
//	lb->bootpathmask = bootpathmask;
	*lbp = lb;
	if(trace)
		print("logfsbootopen: success\n");
	return nil;

error:
	logfsfreemem(reversemap);
	logfsfreemem(lb);
	return errmsg;
}

void
logfsbootfree(LogfsBoot *lb)
{
	if(lb) {
		logfsfreemem(lb->map);
		logfsfreemem(lb);
	}
}

char *
logfsbootmap(LogfsBoot *lb, ulong laddress, ulong *lblockp, int *lboffsetp, int *lpagep, int *lpageoffsetp, ulong *pblockp, ulong *paddressp)
{
	LogfsLowLevel *ll = lb->ll;
	ulong lblock;
	ulong lboffset, lpageoffset, lpage;
	ulong pblock;
	ulong paddress;

	lblock = laddress / lb->blocksize;
	if(lblock >= lb->bootblocks)
		return Eaddress;
	lboffset = laddress % lb->blocksize;
	pblock = lb->map[lblock];
	paddress = (*ll->calcrawaddress)(ll, pblock, lboffset);
	lpage = lboffset >>  ll->l2pagesize;
	lpageoffset = lboffset & ((1 << ll->l2pagesize) - 1);
	if(lblockp)
		*lblockp = lblock;
	if(lboffsetp)
		*lboffsetp = lboffset;
	if(lpagep)
		*lpagep = lpage;
	if(lpageoffsetp)
		*lpageoffsetp = lpageoffset;
	if(pblockp)
		*pblockp = pblock;
	if(paddressp)
		*paddressp = paddress;
	return nil;
}

long
logfsbootgetiosize(LogfsBoot *lb)
{
	return lb->blocksize;
}

long
logfsbootgetsize(LogfsBoot *lb)
{
	return lb->size;
}

void
logfsboottrace(LogfsBoot *lb, int level)
{
	lb->trace = level;
}
