typedef struct DataBlock DataBlock;
typedef struct Extent Extent;
typedef struct Entry Entry;
typedef struct ExtentList ExtentList;
typedef struct Fid Fid;
typedef struct Map Map;
typedef struct GroupSet GroupSet;
typedef struct Group Group;
typedef struct Uname Uname;
typedef struct LogMessage LogMessage;
typedef struct LogSegment LogSegment;
typedef struct Path Path;
typedef struct DirReadState DirReadState;

typedef struct Map PathMap;
typedef struct Map FidMap;
typedef struct Map GroupMap;
typedef struct Map UnameMap;
typedef struct Map Ust;

#pragma incomplete Extent
#pragma incomplete ExtentList
#pragma incomplete Map
#pragma incomplete DirReadState

enum {
	L2LogSweeps = 2,
	L2BlockCopies = 2,
	LogDataLimit = 128,
	LogAddr = (1 << 31),
	Replacements = 2,		/* extra space for replacements */
	Transfers = 2,			/* extra space available for transfers */
	LogSlack = 1,			/* extra space for data allocation */
};

struct Extent {
	u32int min, max;
	u32int flashaddr;		/* encode block index, page number, and offset within page to min */
};

char *logfsextentlistnew(ExtentList **);
void logfsextentlistfree(ExtentList **);
char *logfsextentlistinsert(ExtentList *, Extent *, Extent **);
int logfsextentlistwalk(ExtentList *, int (*)(void *, Extent *, int),void *);
Extent *logfsextentlistmatch(ExtentList *, Extent *);
int logfsextentlistwalkrange(ExtentList *,
	int (*)(void *, u32int, u32int, Extent *, u32int),
	void *, u32int, u32int);
int logfsextentlistmatchall(ExtentList *, int (*)(void *, Extent *), void *, Extent *);
void logfsextentlistreset(ExtentList *);

struct Entry {
	int inuse;
	int deadandgone;	/* removed */
	Qid qid;
	struct Entry *parent;
	char *name;
	char *uid;
	char *gid;
	ulong mtime;
	char *muid;
	u32int perm;
	struct Entry *next;
	struct {
		struct {
			ulong cvers;
			ulong length;
			ExtentList *extent;
		} file;
		struct {
			struct Entry *list;
		} dir;
	} u;
};

char *logfsentrynew(LogfsServer *, int, u32int, Entry *,
	char *, char *, char *,
	u32int, char *, u32int, ulong, ulong, Entry **);
void logfsentryclunk(Entry *);

void logfsdrsfree(DirReadState **);

struct Fid {
	ulong fid;
	int openmode;
	Entry *entry;
	char *uname;
	DirReadState *drs;
};

typedef int LOGFSMAPWALKFN(void*, void*);
char *logfsmapnew(int, int (*)(void*, int), int (*)(void*, void*), int (*)(void*), void (*)(void*), Map **);
void logfsmapfree(Map **);
char *logfsmapnewentry(Map*, void*, void **);
void *logfsmapfindentry(Map*, void*);
int logfsmapdeleteentry(Map*, void*);
int logfsmapwalk(Map*, LOGFSMAPWALKFN*, void*);

char *logfsfidmapnew(FidMap **);
#define logfsfidmapfree(mp) logfsmapfree(mp)
char *logfsfidmapnewentry(FidMap *, ulong, Fid **);
#define logfsfidmapfindentry(m, fid) logfsmapfindentry(m, (void *)fid)
int logfsfidmapclunk(FidMap *, ulong);

struct Logfs {
	int trace;
};

char *logfsustnew(Ust**);
#define logfsustfree(m) logfsmapfree((m))
char *logfsustadd(Ust*, char*);

struct Group {
	char *uid;
	char *uname;
	Group *leader;
	GroupSet *members;
};

struct Uname {
	char *uname;
	Group *g;
};

struct LogfsIdentityStore {
	Ust *ids;
	GroupMap *groupmap;
	UnameMap *unamemap;
};

char *logfsgroupmapnew(GroupMap **, UnameMap **);
#define logfsgroupmapfree(mp) logfsmapfree(mp)
#define logfsunamemapfree(mp) logfsmapfree(mp)
char *logfsgroupmapnewentry(GroupMap *, UnameMap *, char *, char *, Group **, Uname **);
#define logfsgroupmapdeleteentry(m, uid) logfsmapdeleteentry(m, (void *)uid)
#define logfsgroupmapfindentry(m, uid) logfsmapfindentry(m, uid)
#define logfsunamemapfindentry(m, uname) logfsmapfindentry(m, uname)
char *logfsgroupmapfinduname(GroupMap *, char *);
char *logfsunamemapfinduid(UnameMap *, char *);
#define logfsunamemapdeleteentry(m, uname) logfsmapdeleteentry(m, (void *)uname)

typedef int LOGFSGROUPSETWALKFN(void *, Group *);
char *logfsgroupsetnew(GroupSet **);
void logfsgroupsetfree(GroupSet **);
int logfsgroupsetadd(GroupSet *, Group *);
int logfsgroupsetremove(GroupSet *, Group *);
int logfsgroupsetwalk(GroupSet *, LOGFSGROUPSETWALKFN *, void *);
int logfsgroupsetismember(GroupSet *, Group *);
char *logfsisfindidfromname(LogfsIdentityStore *, char *);
char *logfsisfindnamefromid(LogfsIdentityStore *, char *);
#define logfsisfindgroupfromid(is, id) logfsgroupmapfindentry((is)->groupmap, id)
Group *logfsisfindgroupfromname(LogfsIdentityStore *, char *);
#define logfsisustadd(is, s) logfsustadd((is)->ids, s)
int logfsisgroupunameismember(LogfsIdentityStore *, Group *, char *);
int logfsisgroupuidismember(LogfsIdentityStore *, Group *, char *);
int logfsisgroupuidisleader(LogfsIdentityStore *, Group *, char *);
extern char *logfsisgroupnonename;

struct LogMessage {
	uchar type;
	u32int path;
	union {
		struct {
			u32int nerase;
		} start;
		struct {
			u32int perm;
			u32int newpath;
			u32int mtime;
			u32int cvers;
			char *name;
			char *uid;
			char *gid;
		} create;
		struct {
			u32int mtime;
			char *muid;
		} remove;
		struct {
			u32int mtime;
			u32int cvers;
			char *muid;
		} trunc;
		struct {
			u32int offset;
			u32int count;
			u32int mtime;
			u32int cvers;
			char *muid;
			u32int flashaddr;
			uchar *data;
		} write;
		struct {
			char *name;
			u32int perm;
			char *uid;
			char *gid;
			u32int mtime;
			char *muid;
		} wstat;
	} u;
};

uint logfsconvM2S(uchar *, uint, LogMessage *);
uint logfssizeS2M(LogMessage *);
uint logfsconvS2M(LogMessage *, uchar *, uint);
void logfsdumpS(LogMessage *);

struct LogSegment {
	int gen;				/* generation number of this log */
	int dirty;				/* written to since last sweep */
	long curblockindex;		/* index of block being filled, or -1 */
	long unsweptblockindex;	/* next block to sweep */
	int curpage;			/* page within block */
	uchar *pagebuf;		/* page buffer */
	int nbytes;			/* bytes used in page buffer */
	long blockmap[1];		/* there are ll->blocks of these */
};

char *logfslogsegmentnew(LogfsServer *, int, LogSegment **);
void logfslogsegmentfree(LogSegment **);
char *logfslogbytes(LogfsServer *, int, uchar *, uint);
char *logfslog(LogfsServer *, int, LogMessage *);
char *logfslogwrite(LogfsServer *, int, u32int, u32int, int, u32int,
	u32int, char *, uchar *, u32int *);
char *logfslogsegmentflush(LogfsServer *, int);
int lognicesizeforwrite(LogfsServer *, int, u32int, int);
char *logfsscan(LogfsServer *);

struct DataBlock {
	Pageset free;
	Pageset dirty;
	long path;			/* includes generation */
	long block;
};

Pageset logfsdatapagemask(int, int);

struct Path {
	ulong path;
	Entry *entry;
};

char *logfspathmapnew(PathMap **);
#define logfspathmapfree(mp) logfsmapfree(mp)
char *logfspathmapnewentry(PathMap *, ulong, Entry *, Path **);
#define logfspathmapfindentry(m, path) (Path *)logfsmapfindentry(m, (void *)path)
#define logfspathmapdeleteentry(m, path) logfsmapdeleteentry(m, (void *)path)
Entry *logfspathmapfinde(PathMap *, ulong);

enum {
	LogfsTestDontFettleDataBlock = 1,
};

struct LogfsServer {
	LogfsLowLevel *ll;
	LogfsBoot *lb;
	FidMap *fidmap;
	LogfsIdentityStore *is;
	PathMap *pathmap;
	LogSegment *activelog;
	LogSegment *sweptlog;
	long ndatablocks;
	DataBlock *datablock;
	ulong path;
	Entry root;
	int trace;
	ulong openflags;
	ulong testflags;
};

int logfshashulong(void *, int);

int logfsuserpermcheck(LogfsServer *, Entry *, Fid *, ulong);
u32int logfsflattenentry(LogfsIdentityStore *, uchar *, u32int, Entry *);
char *logfsreplay(LogfsServer *, LogSegment *, int);
void logfsreplayfinddata(LogfsServer *);

#define dataseqof(path) ((path) >> L2BlockCopies)
#define copygenof(path) ((path) & ((1 << L2BlockCopies) -1))
#define mkdatapath(seq, gen) (((seq) << L2BlockCopies) | (gen))
#define gensucc(g, l2) (((g) + 1) & ((1 << (l2)) - 1))
#define copygensucc(g) gensucc((g), L2BlockCopies)
#define loggenof(path) ((path >> L2BlockCopies) & ((1 << L2LogSweeps) - 1))
#define logseqof(path) ((path) >> (L2BlockCopies + L2LogSweeps))
#define mklogpath(seq, gen, copygen) (((((seq) << L2LogSweeps) | (gen)) << L2BlockCopies) | (copygen))
#define loggensucc(g) gensucc((g), L2LogSweeps)

int logfsunconditionallymarkfreeanddirty(void *, Extent *, int);
void logfsflashaddr2spo(LogfsServer *, u32int, long *, int *, int *);
int logfsgn(uchar **, uchar *, char **);
u32int logfsspo2flashaddr(LogfsServer *, long, int, int);
int logfsgn(uchar **, uchar *, char **);
void logfsflashaddr2o(LogfsServer *, u32int, int *);
void logfsfreedatapages(LogfsServer *, long, Pageset);
void logfsfreeanddirtydatablockcheck(LogfsServer *, long);

typedef enum AllocReason {
	AllocReasonReplace,
	AllocReasonTransfer,
	AllocReasonLogExtend,
	AllocReasonDataExtend,
} AllocReason;

long logfsfindfreeblock(LogfsLowLevel *, AllocReason);
char *logfsbootfettleblock(LogfsBoot *, long, uchar tag, long, int *);
char *logfsserverreplacedatablock(LogfsServer *, long);
char *logfsserverreplacelogblock(LogfsServer *, LogSegment *, long);
char *logfsserverreplaceblock(LogfsServer *, LogSegment *, long);
char *logfsservercopyactivedata(LogfsServer *, long, long, int,
	LogfsLowLevelReadResult *, int *);

char *logfsstrdup(char*);

extern char Enomem[];
extern char Eshortstat[];
extern char Enonexist[];
extern char Etoobig[];
extern char Eexist[];
extern char Eunknown[];
extern char Enotdir[];
extern char Eisdir[];
extern char logfsebadfid[];
extern char logfsefidopen[];
extern char logfsefidnotopen[];
extern char logfsefidinuse[];
extern char logfseopen[];
extern char logfseaccess[];
extern char logfselogmsgtoobig[];
extern char logfselogfull[];
extern char logfseinternal[];
extern char logfsenotempty[];
extern char logfseexcl[];
extern char logfsefullreplacing[];
extern char logfseunknownpath[];
