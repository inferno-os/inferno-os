#include "lib9.h"
#include "logfs.h"
#include "nandfs.h"
#include "nandecc.h"
#include "local.h"

char *
nandfsupdatepage(Nandfs *nandfs, void *buf, ulong path, uchar tag, long block, int page)
{
	uchar tbuf[NandfsFullSize];
	ulong ecc1, ecc2;
	ulong rawoffset;
	NandfsAuxiliary *hdr;

	rawoffset =  (nandfs->baseblock + block) * nandfs->rawblocksize + page * NandfsFullSize;
	memmove(tbuf, buf, NandfsPageSize);
	ecc1 = nandecc(tbuf);
	ecc2 = nandecc(tbuf + 256);
	hdr = (NandfsAuxiliary *)(tbuf + NandfsPageSize);
	memset(hdr, 0xff, sizeof(*hdr));
	hdr->tag = tag;
	if (path < NandfsPathMask) {
		ulong tmp = _nandfshamming31_26calc(path << 6) | (1 << 5);
		putbig4(hdr->parth, tmp);
	}
	putlittle3(hdr->ecc1, ecc1);
	putlittle3(hdr->ecc2, ecc2);
	return (*nandfs->write)(nandfs->magic, tbuf, sizeof(tbuf), rawoffset);
}

char *
nandfswritepage(Nandfs *nandfs, void *buf, long block, int page)
{
	ulong writepath = nandfsgetpath(nandfs, block);
	uchar writetag = nandfsgettag(nandfs, block);
//print("block %ld writepath 0x%.8lux writetag 0x%.2ux\n", block, writepath, writetag);
	return nandfsupdatepage(nandfs, buf, writepath, writetag, block, page);
}
