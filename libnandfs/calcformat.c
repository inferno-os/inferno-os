#include "logfsos.h"
#include "logfs.h"
#include "nandfs.h"
#include "local.h"

int
nandfscalcformat(Nandfs *nandfs, long base, long limit, long bootsize, long *baseblock, long *limitblock, long *bootblocks)
{
	*baseblock = (base + nandfs->rawblocksize - 1) / nandfs->rawblocksize;
	if (limit == 0)
		*limitblock = nandfs->limitblock;	
	else
		*limitblock = limit / nandfs->rawblocksize;
	*bootblocks = (bootsize + nandfs->rawblocksize - 1) / nandfs->rawblocksize;
	if (*bootblocks < 3)
		*bootblocks = 3;
	/* sanity checks */	
	if (*limitblock > nandfs->limitblock
		|| *baseblock < nandfs->baseblock
		|| *bootblocks > nandfs->limitblock - nandfs->baseblock)
		return 0;
	return 1;
}

