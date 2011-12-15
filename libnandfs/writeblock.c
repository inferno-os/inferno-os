#include "logfsos.h"
#include "logfs.h"
#include "nandfs.h"
#include "local.h"

char *
nandfswriteblock(Nandfs *nandfs, void *buf, uchar tag, ulong path, int xcount, long *data, long block)
{
	int p;
	char *errmsg;

	ulong opath = nandfsgetpath(nandfs, block);
	ulong writepath = (~opath | path) & NandfsPathMask;
	uchar writetag = ~nandfsgettag(nandfs, block) | tag;
	int ppb = 1 << nandfs->ll.l2pagesperblock;

	for (p = 0; p < ppb; p++) {
		ulong wp;
		if (p > 0 && p <= 2 + xcount) {
			switch (p) {
			case 1:
				wp = (~opath | nandfsgetbaseblock(nandfs)) & NandfsPathMask;
				break;
			case 2:
				wp = (~opath | nandfs->ll.blocks) & NandfsPathMask;
				break;
			default:
				wp = (~opath | data[p - 3]) & NandfsPathMask;
				break;
			}
		}
		else
			wp = writepath;
		errmsg = nandfsupdatepage(nandfs, buf, wp, writetag, block, p);
		if (errmsg)
			return errmsg;
#ifdef LOGFSTEST
		if (logfstest.partialupdate && p > 0) {
			print("skipping pageupdate\n");
			break;
		}
#endif
		buf = (uchar *)buf + NandfsPageSize;
	}

	return nil;
}
