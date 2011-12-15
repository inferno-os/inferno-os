#include "logfsos.h"
#include "logfs.h"
#include "nandfs.h"
#include "local.h"

uchar _nandfsvalidtags[] = {
	LogfsTnone,
	LogfsTboot,
	LogfsTlog,
	LogfsTdata,
};

int _nandfsvalidtagscount = nelem(_nandfsvalidtags);

static int
l2(long n)
{
	int i;
	for (i = 0; i < 32; i++)
		if ((1 << i) >= n)
			return i;
	return 0;
}

char *
nandfsinit(void *magic, long rawsize, long rawblocksize,
	char *(*read)(void *magic, void *buf, long nbytes, ulong offset),
	char *(*write)(void *magic, void *buf, long nbytes, ulong offset),
	char *(*erase)(void *magic, long blockaddr),
	char *(*sync)(void *magic),
	LogfsLowLevel **llp)
{
	Nandfs *nandfs;
	nandfs = nandfsrealloc(nil, sizeof(*nandfs));
	if (nandfs == nil)
		return Enomem;
	if (rawblocksize % NandfsFullSize)
		return "unsupported block size";
	if (rawsize % rawblocksize)
		return "size not multiple of block size";
	nandfs->read = read;
	nandfs->write = write;
	nandfs->erase = erase;
	nandfs->sync = sync;
	nandfs->magic = magic;
	nandfs->limitblock = rawsize / rawblocksize;
//print("rawsize %ld\n", rawsize);
//print("rawblocksize %ld\n", rawblocksize);
//print("limitblock %ld\n", nandfs->limitblock);
	nandfs->rawblocksize = rawblocksize;
	/* fill in upper interface */
	nandfs->ll.pathbits = NandfsPathBits;
	nandfs->ll.blocks = 0;
	nandfs->ll.l2pagesize = NandfsL2PageSize;
	nandfs->ll.l2pagesperblock = l2(rawblocksize / NandfsFullSize);
	nandfs->ll.open = (LOGFSOPENFN *)nandfsopen;
	nandfs->ll.getblocktag = (LOGFSGETBLOCKTAGFN *)nandfsgettag;
	nandfs->ll.setblocktag = (LOGFSSETBLOCKTAGFN *)nandfssettag;
	nandfs->ll.getblockpath = (LOGFSGETBLOCKPATHFN *)nandfsgetpath;
	nandfs->ll.setblockpath = (LOGFSSETBLOCKPATHFN *)nandfssetpath;
	nandfs->ll.getblockpartialformatstatus = (LOGFSGETBLOCKPARTIALFORMATSTATUSFN *)nandfsgetblockpartialformatstatus;
	nandfs->ll.findfreeblock = (LOGFSFINDFREEBLOCKFN *)nandfsfindfreeblock;
	nandfs->ll.readpagerange = (LOGFSREADPAGERANGEFN *)nandfsreadpagerange;
	nandfs->ll.writepage = (LOGFSWRITEPAGEFN *)nandfswritepage;
	nandfs->ll.readblock = (LOGFSREADBLOCKFN *)nandfsreadblock;
	nandfs->ll.writeblock = (LOGFSWRITEBLOCKFN *)nandfswriteblock;
	nandfs->ll.eraseblock = (LOGFSERASEBLOCKFN *)nandfseraseblock;
	nandfs->ll.formatblock = (LOGFSFORMATBLOCKFN *)nandfsformatblock;
	nandfs->ll.reformatblock = (LOGFSREFORMATBLOCKFN *)nandfsreformatblock;
	nandfs->ll.markblockbad = (LOGFSMARKBLOCKBADFN *)nandfsmarkblockbad;
	nandfs->ll.getbaseblock = (LOGFSGETBASEBLOCKFN *)nandfsgetbaseblock;
	nandfs->ll.getblocksize = (LOGFSGETBLOCKSIZEFN *)nandfsgetblocksize;
	nandfs->ll.calcrawaddress = (LOGFSCALCRAWADDRESSFN *)nandfscalcrawaddress;
	nandfs->ll.getblockstatus = (LOGFSGETBLOCKSTATUSFN *)nandfsgetblockstatus;
	nandfs->ll.calcformat = (LOGFSCALCFORMATFN *)nandfscalcformat;
	nandfs->ll.getopenstatus = (LOGFSGETOPENSTATUSFN *)nandfsgetopenstatus;
	nandfs->ll.free = (LOGFSFREEFN *)nandfsfree;
	nandfs->ll.sync = (LOGFSSYNCFN *)nandfssync;
	*llp = (LogfsLowLevel *)nandfs;
	return nil;
}

void
nandfsfree(Nandfs *nandfs)
{
	if (nandfs) {
		nandfsfreemem(nandfs->blockdata);
		nandfsfreemem(nandfs);
	}
}

void
nandfssetmagic(Nandfs *nandfs, void *magic)
{
	nandfs->magic = magic;
}

char *
nandfssync(Nandfs *nandfs)
{
	return (*nandfs->sync)(nandfs->magic);
}
