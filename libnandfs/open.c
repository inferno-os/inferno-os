#include "logfsos.h"
#include "logfs.h"
#include "nandfs.h"
#include "local.h"

char *
nandfsopen(Nandfs *nandfs, long base, long limit, int trace, int xcount, long *xdata)
{
	NandfsBlockData *blockdata = nil;
	long u;
	ulong badones, goodones;
	char *errmsg;
	long possiblebaseblock, possiblesize;
	long baseblock, limitblock;
	int ppb;

	if (trace > 1)
		print("nandfsopen: base %ld limit %ld ppb %d\n", base, limit, 1 << nandfs->ll.l2pagesperblock);

	if (nandfs->blockdata)
		return Eperm;

	if (base % nandfs->rawblocksize)
		return Ebadarg;
	baseblock = base / nandfs->rawblocksize;

	if (limit == 0)
		limitblock = nandfs->limitblock;
	else if (limit % nandfs->rawblocksize)
		return Ebadarg;
	else
		limitblock = limit / nandfs->rawblocksize;

	if (trace > 1)
		print("nandfsopen: baseblock %ld limitblock %ld\n", baseblock, limitblock);

	possiblebaseblock = 0;
	possiblesize = 0;

	/*
	 * search for Tboot block which will reveal the parameters
	 */
	nandfs->baseblock = 0;

	for (u = baseblock; u < limitblock; u++) {
		NandfsTags tags;
		LogfsLowLevelReadResult e;
		int p;
		int lim;

		lim = xcount + 3;

		for (p = 0; p < lim; p++) {
			errmsg = nandfsreadpageauxiliary(nandfs, &tags, u, p, 1, &e);
			if (errmsg)
				goto error;
			if (e != LogfsLowLevelReadResultOk || tags.magic != LogfsMagic || tags.tag != LogfsTboot)
				break;
			if (trace > 1)
				print("block %lud/%d: 0x%.lux\n", u, p, tags.path);
			switch (p) {
			case 1:
				possiblebaseblock = tags.path;
				break;
			case 2:
				possiblesize = tags.path;
				break;
			default:
				xdata[p - 3] = tags.path;
				break;
			}
		}
		if (p == lim)
			break;
	}

	if (u >= limitblock) {
		errmsg = "no valid boot blocks found";
		goto error;
	}

	if (possiblebaseblock < baseblock
		|| possiblebaseblock >= limitblock
		|| possiblebaseblock + possiblesize > limitblock
		|| possiblesize == 0) {
		errmsg = "embedded parameters out of range";
		goto error;
	}

	baseblock = possiblebaseblock;
	limitblock = possiblebaseblock + possiblesize;

	if (trace > 0) {
		int x;
		print("nandfs filesystem detected: base %lud limit %lud",
			baseblock, limitblock);
		for (x = 0; x < xcount; x++)
			print(" data%d %ld", x, xdata[x]);
		print("\n");
	}

	blockdata = nandfsrealloc(nil, (limitblock - baseblock) * sizeof(NandfsBlockData));
	if (blockdata == nil) {
		errmsg = Enomem;
		goto error;
	}
	/*
	 * sanity check
	 * check the partition until 10 good blocks have been found
	 * check that bad blocks represent 10% or less
	 */

	badones = goodones = 0;
	ppb = 1 << nandfs->ll.l2pagesperblock;
	for (u = baseblock; u < limitblock; u++) {
		LogfsLowLevelReadResult firste, laste;
		NandfsTags firsttags, lasttags;
		errmsg = nandfsreadpageauxiliary(nandfs, &firsttags, u, 0, 1, &firste);
		if (errmsg)
			goto error;
		errmsg = nandfsreadpageauxiliary(nandfs, &lasttags, u, ppb - 1, 1, &laste);
		if (errmsg)
			goto error;
		if (firste == LogfsLowLevelReadResultBad || laste == LogfsLowLevelReadResultBad)
			continue;
		if (firste == LogfsLowLevelReadResultOk && laste == LogfsLowLevelReadResultOk && firsttags.magic == LogfsMagic &&
			lasttags.magic == LogfsMagic)
			goodones++;
		else
			badones++;
		if (badones == 0 && goodones >= 10)
			break;
	}

	if (badones * 10 > goodones) {
		errmsg = "most likely not a Log Filesystem";
		goto error;
	}

	for (u = baseblock; u < limitblock; u++) {
		int erased, partial;
		LogfsLowLevelReadResult firste, laste;
		NandfsTags firsttags, lasttags, newtags;
		int markedbad;
		errmsg = nandfsreadpageauxiliary(nandfs, &firsttags, u, 0, 1, &firste);
		if (errmsg)
			goto error;
		errmsg = nandfsreadpageauxiliary(nandfs, &lasttags, u, ppb - 1, 1, &laste);
		if (errmsg)
			goto error;
		if (trace > 1)
			print("%lud: ", u);
		if (firste == LogfsLowLevelReadResultBad || laste == LogfsLowLevelReadResultBad) {
			if (trace > 1)
				print("bad\n");
			blockdata[u - baseblock].tag = LogfsTbad;
			continue;
		}
		newtags = firsttags;
		erased = 0;
		partial = 0;
		if (firsttags.tag != lasttags.tag) {
			partial = 1;
			if (trace > 1)
				print("partially written\n");
			/*
			 * partially written block
			 * if Tboot, then it is either
			 * 	a failure during logfsformat() - well, we never got started, so give up
			 *	a failure during blocktransfer() - erase it as the transfer was not completed
			 *	tell the difference by the presence of another block with the same path
			 * if Tnone, then it's a no brainer
			 * if anything else, leave alone
			 */
			if (newtags.tag == LogfsTnone) {
				newtags.tag = LogfsTnone;
				newtags.path = NandfsPathMask;
				errmsg = nandfseraseblock(nandfs, u, nil, &markedbad);
				if (errmsg)
					goto error;
				if (markedbad) {
					blockdata[u - baseblock].tag = LogfsTbad;
					continue;
				}
				/* now erased */
				erased = 1;
				partial = 0;
			}
		}
		if (!erased && !partial && firste == LogfsLowLevelReadResultAllOnes) {
			if (trace > 1)
				print("probably erased");
			/*
			 * finding erased blocks at this stage is a rare event, so
			 * erase again just in case
			 */
			newtags.tag = LogfsTnone;
			newtags.path = NandfsPathMask;
			newtags.nerase = 1;		// what do I do here?
			errmsg = nandfseraseblock(nandfs, u, nil, &markedbad);
			if (errmsg)
				goto error;
			if (markedbad) {
				blockdata[u - baseblock].tag = LogfsTbad;
				continue;
			}
			erased = 1;
		}
		if (erased) {
			newtags.magic = 'V';
			errmsg = nandfseraseblock(nandfs, u, nil, &markedbad);
			if (errmsg)
				goto error;
			if (markedbad) {
				blockdata[u - baseblock].tag = LogfsTbad;
				continue;
			}
		}
		switch (newtags.tag) {
		case LogfsTboot:
		case LogfsTnone:
		case LogfsTdata:
		case LogfsTlog:
			blockdata[u - baseblock].path = newtags.path;
			blockdata[u - baseblock].tag = newtags.tag;
			blockdata[u - baseblock].nerase = newtags.nerase;
			blockdata[u - baseblock].partial = partial;
			if (trace > 1)
				print("%s 0x%.8lux %lud\n",
					logfstagname(blockdata[u - baseblock].tag),
					blockdata[u - baseblock].path,
					blockdata[u - baseblock].nerase);
			continue;
		}
		break;
	}
	nandfs->ll.blocks = u - baseblock;
	nandfs->baseblock = baseblock;
	nandfs->blockdata = nandfsrealloc(nil, nandfs->ll.blocks * sizeof(NandfsBlockData));
	if (nandfs->blockdata == nil) {
		errmsg = Enomem;
		goto error;
	}
	nandfs->trace = trace;
	memmove(nandfs->blockdata, blockdata, sizeof(*nandfs->blockdata) * nandfs->ll.blocks);
	nandfsfreemem(blockdata);
	if (trace > 0)
		print("nandfsopen: success\n");
	return nil;
error:
	nandfsfreemem(blockdata);
	return errmsg;
}
