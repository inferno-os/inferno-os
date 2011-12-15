#include "logfsos.h"
#include "logfs.h"
#include "nandfs.h"
#include "local.h"

char *
nandfsmarkabsblockbad(Nandfs *nandfs, long absblock)
{
	NandfsAuxiliary hdr;
	int page;
	int ppb;

	memset(&hdr, 0xff, sizeof(hdr));
	hdr.blockstatus = 0xf0;		// late failure

	ppb = 1 << nandfs->ll.l2pagesperblock;
	for (page = 0; page < ppb; page++) {
		char *errmsg = (*nandfs->write)(nandfs->magic, &hdr, sizeof(hdr), nandfs->rawblocksize * absblock + page * NandfsFullSize + NandfsPageSize);
		if (errmsg && strcmp(errmsg, Eio) != 0)
			return errmsg;
	}

	return nil;
}

char *
nandfsmarkblockbad(Nandfs *nandfs, long block)
{
	char *errmsg;
	errmsg = nandfsmarkabsblockbad(nandfs, block + nandfs->baseblock);
	if (errmsg)
		return errmsg;

	if (nandfs->blockdata) {
		NandfsBlockData *d;
		d = &nandfs->blockdata[block];
		d->tag = LogfsTbad;
	}

	return nil;
}

