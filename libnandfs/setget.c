#include "logfsos.h"
#include "logfs.h"
#include "nandfs.h"
#include "local.h"

short
nandfsgettag(Nandfs *nandfs, long block)
{
	if (nandfs->blockdata)
		return nandfs->blockdata[block].tag;
	return 0;
}

void
nandfssettag(Nandfs *nandfs, long block, short tag)
{
	if (nandfs->blockdata) {
		nandfs->blockdata[block].tag = tag;
		if (tag == LogfsTworse)
			nandfs->worseblocks = 1;
		return;
	}
}

long
nandfsgetpath(Nandfs *nandfs, long block)
{
	if (nandfs->blockdata)
		return nandfs->blockdata[block].path;
	return 0;
}

void
nandfssetpath(Nandfs *nandfs, long block, ulong path)
{
	if (nandfs->blockdata) {
		nandfs->blockdata[block].path = path;
		return;
	}
}

long
nandfsgetnerase(Nandfs *nandfs, long block)
{
	if (nandfs->blockdata)
		return nandfs->blockdata[block].nerase;
	return 0;
}

void
nandfssetnerase(Nandfs *nandfs, long block, ulong nerase)
{
	if (nandfs->blockdata) {
		nandfs->blockdata[block].nerase = nerase;
		return;
	}
}

int
nandfsgetblockpartialformatstatus(Nandfs *nandfs, long block)
{
	if (nandfs->blockdata)
		return nandfs->blockdata[block].partial;
	return 0;
}

void
nandfssetblockpartialformatstatus(Nandfs *nandfs, long block, int partial)
{
	if (nandfs->blockdata) {
		nandfs->blockdata[block].partial = partial;
		return;
	}
}

long
nandfsgetbaseblock(Nandfs *nandfs)
{
	return nandfs->baseblock;
}

int
nandfsgetblocksize(Nandfs *nandfs)
{
	return 1 << (nandfs->ll.l2pagesperblock + NandfsL2PageSize);
}

ulong
nandfscalcrawaddress(Nandfs *nandfs, long pblock, int dataoffset)
{
	int lpage, pageoffset;
	lpage = dataoffset / NandfsPageSize;
	pageoffset = dataoffset % NandfsPageSize;
	return nandfs->rawblocksize * pblock + lpage * NandfsFullSize + pageoffset;
}

int
nandfsgetopenstatus(Nandfs *nandfs)
{
	return nandfs->blockdata != nil;
}
