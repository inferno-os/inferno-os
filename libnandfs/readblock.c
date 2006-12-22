#include "lib9.h"
#include "logfs.h"
#include "nandfs.h"
#include "local.h"

char *
nandfsreadblock(Nandfs *nandfs, void *buf, long block, LogfsLowLevelReadResult *blocke)
{
	int p;
	uchar *bp;
	int ppb;

	*blocke = LogfsLowLevelReadResultOk;
	ppb = 1 << nandfs->ll.l2pagesperblock;
	for (p = 0, bp = buf; p < ppb; p++, bp += NandfsPageSize) {
		LogfsLowLevelReadResult e;
		char *errmsg;
		errmsg = nandfsreadpage(nandfs, bp, nil, block, p, nandfs->printbad, &e);
		if (errmsg)
			return errmsg;
		switch (e) {
		case LogfsLowLevelReadResultOk:
			break;
		case LogfsLowLevelReadResultSoftError:
			if (*blocke == LogfsLowLevelReadResultOk)
				*blocke = LogfsLowLevelReadResultSoftError;
			break;
		case LogfsLowLevelReadResultHardError:
			if (*blocke == LogfsLowLevelReadResultOk || *blocke == LogfsLowLevelReadResultSoftError)
				*blocke = LogfsLowLevelReadResultHardError;
			break;
		}
	}

	return nil;
}
