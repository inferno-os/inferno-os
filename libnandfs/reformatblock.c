#include "logfsos.h"
#include "logfs.h"
#include "nandfs.h"
#include "local.h"

char *
nandfsreformatblock(Nandfs *nandfs, long block, uchar tag, ulong path, int xcount, long *xdata, void *llsave, int *markedbad)
{
	int bad;
	char *errmsg;
	NandfsBlockData *d;
	long nerase;

	if (nandfs->blockdata == nil)
		return Eperm;

	nerase = *(ulong *)llsave;

	errmsg = nandfsformatblock(nandfs, block, tag, path,
		nandfs->baseblock, nandfs->limitblock - nandfs->baseblock, xcount, xdata, &nerase, &bad);

	if (markedbad)
		*markedbad = bad;
	if (errmsg)
		return errmsg;

	d = &nandfs->blockdata[block];
	d->tag = bad ? LogfsTbad : tag;
	d->path = path;
	d->nerase = nerase;
	d->partial = 0;

	return nil;
}
