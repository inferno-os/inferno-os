
enum {
	L2LogSweeps = 2,
	L2BlockCopies = 2,
	LogDataLimit = 128,
	LogAddr = (1 << 31),
	Replacements = 2,		/* how much free space must be available for replacements */
	Transfers = 2,			/* how much additional space must be available for transfers */
	LogSlack = 1,			/* how much additional space must be available for data allocation */
};

typedef struct Extent {
	u32int min, max;
	u32int flashaddr;		/* encode block index, page number, and offset within page to min */
} Extent;

typedef struct ExtentList ExtentList;

char *logfsextentlistnew(ExtentList **l);
void logfsextentlistfree(ExtentList **l);
char *logfsextentlistinsert(ExtentList *l, Extent *add, Extent **new);
int logfsextentlistwalk(ExtentList *l, int (*func)(void *magic, Extent *e, int hole),void *magic);
Extent *logfsextentlistmatch(ExtentList *l, Extent *e);
int logfsextentlistwalkrange(ExtentList *l,
	int (*func)(void *magic, u32int baseoffset, u32int limitoffset, Extent *, u32int extentoffset),
	void *magic, u32int base, u32int limit);
int logfsextentlistmatchall(ExtentList *l, int (*func)(void *magic, Extent *), void *magic, Extent *e);
void logfsextentlistreset(ExtentList *l);

typedef struct Entry {
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
} Entry;

char *logfsentrynew(LogfsServer *server, int inuse, u32int path, Entry *parent,
	char *name, char *uid, char *gid,
	u32int mtime, char *muid, u32int perm, ulong cvers, ulong length, Entry **ep);
void logfsentryclunk(Entry *e);

typedef struct DirReadState DirReadState;
void logfsdrsfree(DirReadState **drsp);

typedef struct Fid {
	ulong fid;
	int openmode;
	Entry *entry;
	char *uname;
	DirReadState *drs;
} Fid;

typedef struct Map Map;
typedef int LOGFSMAPWALKFN(void *magic, void *entry);
char *logfsmapnew(int size, int (*hash)(void *key, int size), int (*compare)(void *entry, void *key), int (*allocsize)(void *key), void (*free)(void *), Map **mapp);
void logfsmapfree(Map **mp);
char *logfsmapnewentry(Map *m, void *key, void **entryp);
void *logfsmapfindentry(Map *m, void *key);
int logfsmapdeleteentry(Map *m, void *key);
int logfsmapwalk(Map *m, LOGFSMAPWALKFN *func, void *magic);

typedef struct Map FidMap;

char *logfsfidmapnew(FidMap **fidmapmapp);
#define logfsfidmapfree(mp) logfsmapfree(mp)
char *logfsfidmapnewentry(FidMap *m, ulong fid, Fid **fidmapp);
#define logfsfidmapfindentry(m, fid) logfsmapfindentry(m, (void *)fid)
int logfsfidmapclunk(FidMap *m, ulong fid);

struct Logfs {
	int trace;
};

typedef struct Map Ust;
char *logfsustnew(Ust **ustp);
#define logfsustfree(m) logfsmapfree(m)
char *logfsustadd(Ust *m, char *s);

typedef struct GroupSet GroupSet;

typedef struct Group Group;
typedef struct Map GroupMap;
typedef struct Uname Uname;
typedef struct Map UnameMap;

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

char *logfsgroupmapnew(GroupMap **groupmapp, UnameMap **unamemapp);
#define logfsgroupmapfree(mp) logfsmapfree(mp)
#define logfsunamemapfree(mp) logfsmapfree(mp)
char *logfsgroupmapnewentry(GroupMap *gm, UnameMap *um, char *uid, char *uname, Group **groupp, Uname **unamep);
#define logfsgroupmapdeleteentry(m, uid) logfsmapdeleteentry(m, (void *)uid)
#define logfsgroupmapfindentry(m, uid) logfsmapfindentry(m, uid)
#define logfsunamemapfindentry(m, uname) logfsmapfindentry(m, uname)
char *logfsgroupmapfinduname(GroupMap *m, char *uid);
char *logfsunamemapfinduid(UnameMap *m, char *uid);
#define logfsunamemapdeleteentry(m, uname) logfsmapdeleteentry(m, (void *)uname)

typedef int LOGFSGROUPSETWALKFN(void *magic, Group *g);
char *logfsgroupsetnew(GroupSet **sp);
void logfsgroupsetfree(GroupSet **sp);
int logfsgroupsetadd(GroupSet *s, Group *g);
int logfsgroupsetremove(GroupSet *s, Group *g);
int logfsgroupsetwalk(GroupSet *s, LOGFSGROUPSETWALKFN *func, void *magic);
int logfsgroupsetismember(GroupSet *gs, Group *g);
char *logfsisfindidfromname(LogfsIdentityStore *is, char *name);
char *logfsisfindnamefromid(LogfsIdentityStore *is, char *id);
#define logfsisfindgroupfromid(is, id) logfsgroupmapfindentry((is)->groupmap, id)
Group *logfsisfindgroupfromname(LogfsIdentityStore *is, char *uname);
#define logfsisustadd(is, s) logfsustadd((is)->ids, s)
int logfsisgroupunameismember(LogfsIdentityStore *is, Group *g, char *uname);
int logfsisgroupuidismember(LogfsIdentityStore *is, Group *g, char *uid);
int logfsisgroupuidisleader(LogfsIdentityStore *is, Group *g, char *uid);
extern char *logfsisgroupnonename;

typedef struct LogMessage {
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
} LogMessage;

uint logfsconvM2S(uchar *ap, uint nap, LogMessage *f);
uint logfssizeS2M(LogMessage *f);
uint logfsconvS2M(LogMessage *f, uchar *ap, uint nap);
void logfsdumpS(LogMessage *s);

typedef struct LogSegment LogSegment;

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

char *logfslogsegmentnew(LogfsServer *server, int gen, LogSegment **segp);
void logfslogsegmentfree(LogSegment **segp);
char *logfslogbytes(LogfsServer *server, int active, uchar *msg, uint size);
char *logfslog(LogfsServer *server, int active, LogMessage *s);
char *logfslogwrite(LogfsServer *server, int active, u32int path, u32int offset, int count, u32int mtime,
	u32int cvers, char *muid, uchar *data, u32int *flashaddr);
char *logfslogsegmentflush(LogfsServer *server, int active);
int lognicesizeforwrite(LogfsServer *server, int active, u32int count, int muidlen);
char *logfsscan(LogfsServer *server);

typedef struct DataBlock DataBlock;

struct DataBlock {
	u32int free;
	u32int dirty;
	long path;			/* includes generation */
	long block;
};

u32int logfsdatapagemask(int pages, int base);

typedef struct Path Path;

struct Path {
	ulong path;
	Entry *entry;
};

typedef struct Map PathMap;

char *logfspathmapnew(PathMap **pathmapmapp);
#define logfspathmapfree(mp) logfsmapfree(mp)
char *logfspathmapnewentry(PathMap *m, ulong path, Entry *e, Path **pathmapp);
#define logfspathmapfindentry(m, path) (Path *)logfsmapfindentry(m, (void *)path)
#define logfspathmapdeleteentry(m, path) logfsmapdeleteentry(m, (void *)path)
Entry *logfspathmapfinde(PathMap *m, ulong path);

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

int logfshashulong(void *v, int size);

int logfsuserpermcheck(LogfsServer *s, Entry *e, Fid *f, ulong modemask);
u32int logfsflattenentry(LogfsIdentityStore *is, uchar *buf, u32int buflen, Entry *e);
char *logfsreplay(LogfsServer *server, LogSegment *seg, int disableerrorsforfirstblock);
void logfsreplayfinddata(LogfsServer *server);

#define dataseqof(path) ((path) >> L2BlockCopies)
#define copygenof(path) ((path) & ((1 << L2BlockCopies) -1))
#define mkdatapath(seq, gen) (((seq) << L2BlockCopies) | (gen))
#define gensucc(g, l2) (((g) + 1) & ((1 << (l2)) - 1))
#define copygensucc(g) gensucc(g, L2BlockCopies)
#define loggenof(path) ((path >> L2BlockCopies) & ((1 << L2LogSweeps) - 1))
#define logseqof(path) ((path) >> (L2BlockCopies + L2LogSweeps))
#define mklogpath(seq, gen, copygen) (((((seq) << L2LogSweeps) | (gen)) << L2BlockCopies) | (copygen))
#define loggensucc(g) gensucc(g, L2LogSweeps)

int logfsunconditionallymarkfreeanddirty(void *magic, Extent *e, int hole);
void logfsflashaddr2spo(LogfsServer *server, u32int flashaddr, long *seq, int *page, int *offset);
int logfsgn(uchar **pp, uchar *mep, char **v);
u32int logfsspo2flashaddr(LogfsServer *server, long seq, int page, int offset);
int logfsgn(uchar **pp, uchar *mep, char **v);
void logfsflashaddr2o(LogfsServer *server, u32int flashaddr, int *offset);
void logfsfreedatapages(LogfsServer *server, long seq, u32int mask);
void logfsfreeanddirtydatablockcheck(LogfsServer *server, long seq);

typedef enum AllocReason {
	AllocReasonReplace,
	AllocReasonTransfer,
	AllocReasonLogExtend,
	AllocReasonDataExtend,
} AllocReason;

long logfsfindfreeblock(LogfsLowLevel *ll, AllocReason reason);
char *logfsbootfettleblock(LogfsBoot *lb, long block, uchar tag, long path, int *markedbad);
char *logfsserverreplacedatablock(LogfsServer *server, long index);
char *logfsserverreplacelogblock(LogfsServer *server, LogSegment *seg, long index);
char *logfsserverreplaceblock(LogfsServer *server, LogSegment *seg, long seq);
char *logfsservercopyactivedata(LogfsServer *server, long newb, long oldblockindex, int forcepage0,
	LogfsLowLevelReadResult *llrrp, int *markedbadp);

char *logfsstrdup(char *);

extern char Enomem[];
extern char Emsgsize[];
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
