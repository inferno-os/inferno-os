#include "logfsos.h"
#include "logfs.h"
#include "nandfs.h"
#include "local.h"

char *
nandfsformatblock(Nandfs *nandfs, long absblock, uchar tag, ulong path, long baseblock, long sizeinblocks, int xcount, long *xdata, void *llsave, int *markedbad)
{
	int page;
	char *rv;
	NandfsTags t;
	int ppb;

	if (markedbad)
		*markedbad = 0;

	t.tag = tag;
	t.magic = LogfsMagic;
	t.nerase = *(ulong *)llsave < NandfsNeraseMask ? *(ulong *)llsave + 1 : 1;

	ppb = 1 << nandfs->ll.l2pagesperblock;
	for (page = 0, rv = nil; rv == nil && page < ppb; page++) {
		if (tag == LogfsTboot && page > 0 && page < xcount + 3) {
			switch (page) {
			case 1:
				t.path = baseblock;
				break;
			case 2:
				t.path = sizeinblocks;
				break;
			default:
				t.path = xdata[page - 3];
				break;
			}
		}
		else
			t.path = path;
		rv = nandfswritepageauxiliary(nandfs, &t, absblock, page);
		if (rv)
			break;
	}

	if (rv) {
		if (strcmp(rv, Eio) != 0)
			return rv;
		if (markedbad) {
			*markedbad = 1;
			rv = nandfsmarkabsblockbad(nandfs, absblock);
			if (strcmp(rv, Eio) != 0)
				return rv;
			return nil;
		}
		return rv;
	}
		
	return nil;
}
