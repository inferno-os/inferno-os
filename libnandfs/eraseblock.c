#include "logfsos.h"
#include "logfs.h"
#include "nandfs.h"
#include "local.h"

char *
nandfseraseblock(Nandfs *nandfs, long block, void **llsavep, int *markedbad)
{
	NandfsBlockData *d;
	char *errmsg;

	if (markedbad)
		*markedbad = 0;

	errmsg = (*nandfs->erase)(nandfs->magic, nandfs->rawblocksize * (nandfs->baseblock + block));
	if (errmsg) {
		if (nandfs->blockdata) {
			d = &nandfs->blockdata[block];
			d->tag = LogfsTworse;
			nandfs->worseblocks = 1;
		}
		if (strcmp(errmsg, Eio) != 0)
			return errmsg;
		if (markedbad) {
			*markedbad = 1;
			errmsg = nandfsmarkblockbad(nandfs, block);
			if (strcmp(errmsg, Eio) != 0)
				return errmsg;
			return nil;
		}
		return errmsg;
	}

	if (nandfs->blockdata) {
		ulong *llsave;
		d = &nandfs->blockdata[block];
		if (llsavep) {
			llsave = nandfsrealloc(nil, sizeof(ulong));
			if (llsave == nil)
				return Enomem;
			*llsave = d->nerase;
			*llsavep = llsave;
		}
		d->tag = 0xff;
		d->path = NandfsPathMask;
		d->nerase = NandfsNeraseMask;
	}
	return  nil;
}

