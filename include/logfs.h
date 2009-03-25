#pragma src "/usr/inferno/liblogfs"

enum {
	LogfsTnone = 0xff,
	LogfsTboot = 0x01,
	LogfsTlog = 0x06,
	LogfsTdata = 0x18,
	LogfsTbad = -1,
	LogfsTworse = -2,
	LogfsMagic = 'V',
};

enum {
	LogfsLogTstart = 's',
	LogfsLogTcreate = 'c',
	LogfsLogTtrunc = 't',
	LogfsLogTremove = 'r',
	LogfsLogTwrite = 'w',
	LogfsLogTwstat = 'W',
	LogfsLogTend = 'e',
};

enum {
	LogfsOpenFlagNoPerm = 1,
	LogfsOpenFlagWstatAllow = 2,
};

typedef struct LogfsLowLevel LogfsLowLevel;

typedef enum LogfsLowLevelFettleAction {
	LogfsLowLevelFettleActionMarkBad,
	LogfsLowLevelFettleActionErase,
	LogfsLowLevelFettleActionFormat,
	LogfsLowLevelFettleActionEraseAndFormat,
} LogfsLowLevelFettleAction;

typedef enum LogfsLowLevelReadResult {
	LogfsLowLevelReadResultOk,
	LogfsLowLevelReadResultSoftError,
	LogfsLowLevelReadResultHardError,
	LogfsLowLevelReadResultBad,
	LogfsLowLevelReadResultAllOnes,
} LogfsLowLevelReadResult;

typedef short LOGFSGETBLOCKTAGFN(LogfsLowLevel *ll, long block);
typedef void LOGFSSETBLOCKTAGFN(LogfsLowLevel *ll, long block, short tag);
typedef ulong LOGFSGETBLOCKPATHFN(LogfsLowLevel *ll, long block);
typedef void LOGFSSETBLOCKPATHFN(LogfsLowLevel *ll, long block, ulong path);
typedef long LOGFSFINDFREEBLOCKFN(LogfsLowLevel *ll, long *freeblocks);
typedef char *LOGFSREADBLOCKFN(LogfsLowLevel *ll, void *buf, long block, LogfsLowLevelReadResult *blocke);
typedef char *LOGFSWRITEBLOCKFN(LogfsLowLevel *ll, void *buf, uchar tag, ulong path, int xcount, long *xdata, long block);
typedef char *LOGFSERASEBLOCKFN(LogfsLowLevel *ll, long block, void **llsave, int *markedbad);
typedef char *LOGFSFORMATBLOCKFN(LogfsLowLevel *ll, long block, uchar tag, long path, long baseblock, long sizeinblocks, int xcount, long *xdata, void *llsave, int *markedbad);
typedef char *LOGFSREFORMATBLOCKFN(LogfsLowLevel *ll, long block, uchar tag, long path, int xcount, long *xdata, void *llsave, int *markedbad);
typedef void LOGFSMARKBLOCKBADFN(LogfsLowLevel *ll, long block);
typedef int LOGFSGETBLOCKSFN(LogfsLowLevel *ll);
typedef long LOGFSGETBASEBLOCKFN(LogfsLowLevel *ll);
typedef int LOGFSGETBLOCKSIZEFN(LogfsLowLevel *ll);
typedef int LOGFSGETBLOCKPARTIALFORMATSTATUSFN(LogfsLowLevel *ll, long block);
typedef ulong LOGFSCALCRAWADDRESSFN(LogfsLowLevel *ll, long pblock, int dataoffset);
typedef char *LOGFSOPENFN(LogfsLowLevel *ll, long base, long limit, int trace, int xcount, long *xdata);
typedef char *LOGFSGETBLOCKSTATUSFN(LogfsLowLevel *ll, long block, int *magicfound, void **llsave, LogfsLowLevelReadResult *result);
typedef int LOGFSCALCFORMATFN(LogfsLowLevel *ll, long base, long limit, long bootsize, long *baseblock, long *limitblock, long *bootblocks);
typedef int LOGFSGETOPENSTATUSFN(LogfsLowLevel *ll);
typedef void LOGFSFREEFN(LogfsLowLevel *ll);
typedef char *LOGFSREADPAGERANGEFN(LogfsLowLevel *ll, uchar *data, long block, int page, int offset, int count, LogfsLowLevelReadResult *result);
typedef char *LOGFSWRITEPAGEFN(LogfsLowLevel *ll, uchar *data, long block, int page);
typedef char *LOGFSSYNCFN(LogfsLowLevel *ll);

struct LogfsLowLevel {
	int l2pagesize;
	int l2pagesperblock;
	long blocks;
	int pathbits;
	LOGFSOPENFN *open;
	LOGFSGETBLOCKTAGFN *getblocktag;
	LOGFSSETBLOCKTAGFN *setblocktag;
	LOGFSGETBLOCKPATHFN *getblockpath;
	LOGFSSETBLOCKPATHFN *setblockpath;
	LOGFSREADPAGERANGEFN *readpagerange;
	LOGFSWRITEPAGEFN *writepage;
	LOGFSFINDFREEBLOCKFN *findfreeblock;
	LOGFSREADBLOCKFN *readblock;
	LOGFSWRITEBLOCKFN *writeblock;
	LOGFSERASEBLOCKFN *eraseblock;
	LOGFSFORMATBLOCKFN *formatblock;
	LOGFSREFORMATBLOCKFN *reformatblock;
	LOGFSMARKBLOCKBADFN *markblockbad;
	LOGFSGETBASEBLOCKFN *getbaseblock;
	LOGFSGETBLOCKSIZEFN *getblocksize;
	LOGFSGETBLOCKPARTIALFORMATSTATUSFN *getblockpartialformatstatus;
	LOGFSCALCRAWADDRESSFN *calcrawaddress;
	LOGFSGETBLOCKSTATUSFN *getblockstatus;
	LOGFSCALCFORMATFN *calcformat;
	LOGFSGETOPENSTATUSFN *getopenstatus;
	LOGFSFREEFN *free;
	LOGFSSYNCFN *sync;
};

extern char Eio[];
extern char Ebadarg[];
extern char Eperm[];

char *logfstagname(uchar tag);

typedef struct LogfsIdentityStore LogfsIdentityStore;
char *logfsisnew(LogfsIdentityStore **isp);
void logfsisfree(LogfsIdentityStore **isp);
char *logfsisgroupcreate(LogfsIdentityStore *is, char *groupname, char *groupid);
char *logfsisgrouprename(LogfsIdentityStore *is, char *oldgroupname, char *newgroupname);
char *logfsisgroupsetleader(LogfsIdentityStore *is, char *groupname, char *leadername);
char *logfsisgroupaddmember(LogfsIdentityStore *is, char *groupname, char *membername);
char *logfsisgroupremovemember(LogfsIdentityStore *is, char *groupname, char *nonmembername);
char *logfsisusersread(LogfsIdentityStore *is, void *buf, long n, ulong offset, long *nr);

typedef struct LogfsBoot LogfsBoot;
typedef struct Logfs Logfs;
typedef struct LogfsServer LogfsServer;

char *logfsformat(LogfsLowLevel *ll, long base, long limit, long bootsize, int trace);
char *logfsbootopen(LogfsLowLevel *ll, long base, long limit, int trace, int printbad, LogfsBoot **lbp);
void logfsbootfree(LogfsBoot *lb);
char *logfsbootread(LogfsBoot *lb, void *buf, long n, ulong offset);
char *logfsbootwrite(LogfsBoot *lb, void *buf, long n, ulong offset);
char *logfsbootio(LogfsBoot *lb, void *buf, long n, ulong offset, int write);
char *logfsbootmap(LogfsBoot *lb, ulong laddress, ulong *lblockp, int *lboffsetp, int *lpagep, int *lpageoffsetp, ulong *pblockp, ulong *paddressp);
long logfsbootgetiosize(LogfsBoot *lb);
long logfsbootgetsize(LogfsBoot *lb);
void logfsboottrace(LogfsBoot *lb, int level);

char *logfsserverattach(LogfsServer *s, u32int fid, char *uname, Qid *qid);
char *logfsserverclunk(LogfsServer *s, u32int fid);
char *logfsservercreate(LogfsServer *server, u32int fid, char *name, u32int perm, uchar mode, Qid *qid);
char *logfsserverflush(LogfsServer *server);
char *logfsservernew(LogfsBoot *lb, LogfsLowLevel *ll, LogfsIdentityStore *is, ulong openflags, int trace, LogfsServer **sp);
char *logfsserveropen(LogfsServer *s, u32int fid, uchar mode, Qid *qid);
char *logfsserverread(LogfsServer *s, u32int fid, u32int offset, u32int count, uchar *buf, u32int buflen, u32int *rcount);
char *logfsserverremove(LogfsServer *server, u32int fid);
char *logfsserverstat(LogfsServer *s, u32int fid, uchar *buf, u32int bufsize, ushort *count);
char *logfsserverwalk(LogfsServer *s, u32int fid, u32int newfid, ushort nwname, char **wname, ushort *nwqid, Qid *wqid);
char *logfsserverwrite(LogfsServer *server, u32int fid, u32int offset, u32int count, uchar *buf, u32int *rcount);
char *logfsserverwstat(LogfsServer *server, u32int fid, uchar *stat, ushort nstat);
void logfsserverfree(LogfsServer **sp);
char *logfsserverlogsweep(LogfsServer *server, int justone, int *didsomething);
char *logfsserverreadpathextent(LogfsServer *server, u32int path, int nth, u32int *flashaddrp, u32int *lengthp,
	long *blockp, int *pagep, int *offsetp);

char *logfsservertestcmd(LogfsServer *s, int argc, char **argv);
void logfsservertrace(LogfsServer *s, int level);

/*
 * implemented by the environment
 */
ulong logfsnow(void);
void *logfsrealloc(void *p, ulong size);
void logfsfreemem(void *p);
