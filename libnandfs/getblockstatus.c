#include "logfsos.h"
#include "logfs.h"
#include "nandfs.h"
#include "local.h"

char *
nandfsgetblockstatus(Nandfs *nandfs, long absblock, int *magicfound, void **llsavep, LogfsLowLevelReadResult *result)
{
	NandfsTags tags;
	char *errmsg;
	ulong *llsave;

	errmsg = nandfsreadpageauxiliary(nandfs, &tags, absblock, 0, 1, result);

	*magicfound = tags.magic == LogfsMagic;

	if (llsavep) {
		llsave = nandfsrealloc(nil, sizeof(ulong));
		if (llsave == nil)
			return Enomem;
		*llsave = tags.nerase;
		*llsavep = llsave;
	}

	return errmsg;
}

