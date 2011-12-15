#include "logfsos.h"
#include "logfs.h"
#include "nandfs.h"
#include "local.h"

/*
 * update the tags in a page's auxiliary area
 * only touch the fields if they contain some zeros, and compute the hamming codes
 * as well
 */

char *
nandfswritepageauxiliary(Nandfs *nandfs, NandfsTags *tags, long absblock, int page)
{
	NandfsAuxiliary hdr;
	ulong tmp;
	ushort htmp;

	memset(&hdr, 0xff, sizeof(hdr));
	if (tags->path < NandfsPathMask) {
		tmp = _nandfshamming31_26calc((tags->path << 6)) | (1 << 5);
		putbig4(hdr.parth, tmp);
	}
	if (tags->nerase < NandfsNeraseMask || tags->magic != 0xff) {
		tmp = _nandfshamming31_26calc((tags->magic << 24) | (tags->nerase << 6)) | (1 << 5);
		htmp = tmp >> 16;
		putbig2(hdr.nerasemagicmsw, htmp);
		putbig2(hdr.nerasemagiclsw, tmp);
	}
	if  (tags->tag != 0xff)
		hdr.tag = tags->tag;
	return (*nandfs->write)(nandfs->magic, &hdr, sizeof(hdr), nandfs->rawblocksize * absblock + page * NandfsFullSize + NandfsPageSize);
}
