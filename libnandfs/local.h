typedef struct NandfsBlockData NandfsBlockData;
typedef struct NandfsAuxiliary NandfsAuxiliary;

struct NandfsBlockData {
	ulong path;
	short tag;
	ulong nerase;
	int partial;
};

struct Nandfs {
	LogfsLowLevel ll;
	char *(*read)(void*, void*, long, ulong);
	char *(*write)(void*, void*, long, ulong);
	char *(*erase)(void*, long blockaddr);
	char *(*sync)(void*);
	void *magic;
	long rawblocksize;
	long baseblock;
	long limitblock;
	NandfsBlockData *blockdata;
	int trace;
	int worseblocks;
	int printbad;
};

struct NandfsAuxiliary {
	uchar parth[4];		// ggpppppp pppppppp pppppppp pp1hhhhh (bigendian) self-protected
	uchar tag;			// self-protecting
	uchar blockstatus;	// self-protecting
	uchar nerasemagicmsw[2];	// see nerasemagiclsw
	uchar ecc2[3];		// self-protecting
	uchar nerasemagiclsw[2];	// mmmmmm mmeeeeee eeeeeeeeee ee1hhhhh (bigendian) self-protected
	uchar ecc1[3];		// self-protecting
};

#define getbig2(p) (((p)[0] << 8) | (p)[1])
#define getbig4(p) (((p)[0] << 24) | ((p)[1] << 16) | ((p)[2] << 8) | (p)[3])
#define getlittle3(p) (((p)[2] << 16) | ((p)[1] << 8) | (p)[0])
#define putlittle3(p, q) ((p)[0] = (q), (p)[1] = (q) >> 8, (p)[2] = (q) >> 16)
#define putbig2(p, q) ((p)[0] = (q) >> 8, (p)[1] = (q))
#define putbig4(p, q) ((p)[0] = (q) >> 24, (p)[1] = (q) >> 16, (p)[2] = (q) >> 8, (p)[3] = (q))

LogfsLowLevelReadResult _nandfscorrectauxiliary(NandfsAuxiliary*);

extern uchar _nandfsvalidtags[];
extern int _nandfsvalidtagscount;

ulong _nandfshamming31_26calc(ulong in);
int _nandfshamming31_26correct(ulong *in);

void _nandfsextracttags(NandfsAuxiliary*, NandfsTags*);

extern char Enomem[], Eperm[], Eio[];
