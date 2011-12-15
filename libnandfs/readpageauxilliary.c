#include "logfsos.h"
#include "logfs.h"
#include "nandfs.h"
#include "local.h"

static int
countzeros(uchar byte)
{
	int b, count;
	for (b = 0x80, count = 0; b; b>>= 1)
		if ((byte & b) == 0)
			count++;
	return count;
}

char *
nandfsreadpageauxiliary(Nandfs *nandfs, NandfsTags *tags, long block, int page, int correct, LogfsLowLevelReadResult *result)
{
	NandfsAuxiliary hdr;
	char *rv;

	rv = (*nandfs->read)(nandfs->magic, &hdr, sizeof(hdr), nandfs->rawblocksize * (nandfs->baseblock + block) + page * NandfsFullSize + NandfsPageSize);
	if (rv)
		return rv;
	if (countzeros(hdr.blockstatus) > 2) {
		*result = LogfsLowLevelReadResultBad;
		return nil;
	}
	if (correct)
		*result = _nandfscorrectauxiliary(&hdr);
	else
		*result = LogfsLowLevelReadResultOk;
	_nandfsextracttags(&hdr, tags);
	return nil;
}
