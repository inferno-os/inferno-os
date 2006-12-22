#pragma src "/usr/inferno/libnandfs"

enum {
	NandfsL2PageSize = 9,
	NandfsPageSize = 1 << NandfsL2PageSize,
	NandfsAuxiliarySize = 16,
	NandfsFullSize = NandfsPageSize + NandfsAuxiliarySize,
	NandfsPathBits = 26,
	NandfsPathMask = ((1 << NandfsPathBits) - 1),
	NandfsNeraseBits = 18,
	NandfsNeraseMask = ((1 << NandfsNeraseBits) - 1),
};

typedef struct Nandfs Nandfs;

typedef struct NandfsTags {
	ulong path;	// 26 bits
	ulong nerase;	// 18 bits
	uchar tag;		// 8 bits
	uchar magic;	// 8 bits
} NandfsTags;

char *nandfsinit(void *magic, long rawsize, long rawblocksize,
	char *(*read)(void *magic, void *buf, long nbytes, ulong offset),
	char *(*write)(void *magic, void *buf, long nbytes, ulong offset),
	char *(*erase)(void *magic, long blockaddr),
	char *(*sync)(void *magic),
	LogfsLowLevel **llp);
void nandfsfree(Nandfs *nandfs);
char *nandfsreadpageauxiliary(Nandfs *nandfs, NandfsTags *tags, long block, int page, int correct, LogfsLowLevelReadResult *result);
void nandfssetmagic(Nandfs *nandfs, void *magic);
char *nandfswritepageauxiliary(Nandfs *nandfs, NandfsTags *tags, long absblock, int page);
char *nandfsreadpage(Nandfs *nandfs, void *buf, NandfsTags *tags, long block, int page, int reportbad, LogfsLowLevelReadResult *result);
char *nandfsreadpagerange(Nandfs *nandfs, void *buf, long block, int page, int offset, int count, LogfsLowLevelReadResult *result);
char *nandfsupdatepage(Nandfs *nandfs, void *buf, ulong path, uchar tag, long block, int page);

long nandfsgetnerase(Nandfs *nandfs, long block);
void nandfssetnerase(Nandfs *nandfs, long block, ulong nerase);
void nandfssetpartial(Nandfs *nandfs, long block, int partial);

char *nandfsmarkabsblockbad(Nandfs *nandfs, long absblock);

/* low level interface functions */

char *nandfsopen(Nandfs *nandfs, long base, long limit, int trace, int xcount, long *data);
short nandfsgettag(Nandfs *nandfs, long block);
void nandfssettag(Nandfs *nandfs, long block, short tag);
long nandfsgetpath(Nandfs *nandfs, long block);
void nandfssetpath(Nandfs *nandfs, long block, ulong path);
int nandfsgetblockpartialformatstatus(Nandfs *nandfs, long block);
long nandfsfindfreeblock(Nandfs *nandfs, long *freeblocksp);
char *nandfsreadblock(Nandfs *nandfs, void *buf, long block, LogfsLowLevelReadResult *blocke);
char *nandfswriteblock(Nandfs *nandfs, void *buf, uchar tag, ulong path, int xcount, long *data, long block);
char *nandfswritepage(Nandfs *nandfs, void *buf, long block, int page);
char *nandfseraseblock(Nandfs *nandfs, long block, void **llsavep, int *markedbad);
char *nandfsformatblock(Nandfs *nandfs, long block, uchar tag, ulong path, long baseblock, long sizeinblocks, int xcount, long *xdata, void *llsave, int *markedbad);
char *nandfsreformatblock(Nandfs *nandfs, long block, uchar tag, ulong path, int xcount, long *xdata, void *llsave, int *markedbad);
char *nandfsmarkblockbad(Nandfs *nandfs, long block);
int nandfsgetpagesize(Nandfs *nandfs);
int nandfsgetpagesperblock(Nandfs *nandfs);
long nandfsgetblocks(Nandfs *nandfs);
long nandfsgetbaseblock(Nandfs *nandfs);
int nandfsgetblocksize(Nandfs *nandfs);
ulong nandfscalcrawaddress(Nandfs *nandfs, long pblock, int dataoffset);
char *nandfsgetblockstatus(Nandfs *nandfs, long block, int *magicfound, void **llsave, LogfsLowLevelReadResult *result);
int nandfscalcformat(Nandfs *nandfs, long base, long limit, long bootsize, long *baseblock, long *limitblock, long *bootblocks);
int nandfsgetopenstatus(Nandfs *nandfs);
char *nandfssync(Nandfs *nandfs);

/* defined in environment */
void *nandfsrealloc(void *p, ulong size);
void nandfsfreemem(void *p);
