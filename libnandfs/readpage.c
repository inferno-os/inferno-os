#include "logfsos.h"
#include "logfs.h"
#include "nandfs.h"
#include "nandecc.h"
#include "local.h"

char *
nandfsreadpage(Nandfs *nandfs, void *buf, NandfsTags *tags, long block, int page, int reportbad, LogfsLowLevelReadResult *result)
{
	ulong ecc1, ecc2, storedecc1, storedecc2;
	NandEccError e1, e2;
	ulong rawoffset;
	NandfsAuxiliary hdr;
	char *errmsg;

	rawoffset = nandfs->rawblocksize * (nandfs->baseblock + block) + NandfsFullSize * page;
	errmsg = (*nandfs->read)(nandfs->magic, buf, NandfsPageSize, rawoffset);
	if (errmsg)
		return errmsg;
	errmsg = (*nandfs->read)(nandfs->magic, &hdr, sizeof(hdr), rawoffset + NandfsPageSize);
	if (errmsg)
		return errmsg;
	ecc1 = nandecc(buf);
	ecc2 = nandecc((uchar *)buf + 256);
	storedecc1 = getlittle3(hdr.ecc1);
	storedecc2 = getlittle3(hdr.ecc2);
	e1 = nandecccorrect(buf, ecc1, &storedecc1, reportbad);
	e2 = nandecccorrect((uchar *)buf + 256, ecc2, &storedecc2, reportbad);
	if (e1 == NandEccErrorBad || e2 == NandEccErrorBad)
		*result = LogfsLowLevelReadResultHardError;
	else if (e1 != NandEccErrorGood || e2 != NandEccErrorGood)
		*result = LogfsLowLevelReadResultSoftError;
	else
		*result = LogfsLowLevelReadResultOk;
	if (tags) {
		*result = _nandfscorrectauxiliary(&hdr);
		_nandfsextracttags(&hdr, tags);
	}
	return nil;
}

char *
nandfsreadpagerange(Nandfs *nandfs, void *buf, long block, int page, int offset, int count, LogfsLowLevelReadResult *result)
{
	char *errmsg;
	uchar tmpbuf[NandfsPageSize];
	errmsg = nandfsreadpage(nandfs, tmpbuf, nil, block, page, 1, result);
	if (errmsg == nil)
		memmove(buf, tmpbuf + offset, count);
	return errmsg;
}

