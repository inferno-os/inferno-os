#include "lib9.h"
#include "logfs.h"
#include "nandfs.h"
#include "local.h"

void
_nandfsextracttags(NandfsAuxiliary *hdr, NandfsTags *tags)
{
	ulong tmp;
	tmp = (getbig2(hdr->nerasemagicmsw) << 16) | getbig2(hdr->nerasemagiclsw);
	if (tmp == 0xffffffff) {
		tags->nerase = 0xffffffff;
		tags->magic = 0xff;
	}
	else {
		tags->nerase = (tmp >> 6) & 0x3ffff;
		tags->magic = tmp >> 24;
	}
	tmp = getbig4(hdr->parth);
	if (tmp != 0xffffffff)
		tags->path = tmp >> 6;
	else
		tags->path = 0xffffffff;
	tags->tag = hdr->tag;
}

