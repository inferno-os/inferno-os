#define UNICODE
#define Unknown win_Unknown
#include	<windows.h>
#include	<winbase.h>
#undef Unknown
#undef	Sleep
#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	<lm.h>

/* TODO: try using / in place of \ in path names */

enum
{
	MAX_SID		= sizeof(SID) + SID_MAX_SUB_AUTHORITIES*sizeof(DWORD),
	ACL_ROCK	= sizeof(ACL) + 20*(sizeof(ACCESS_ALLOWED_ACE)+MAX_SID),
	SD_ROCK		= SECURITY_DESCRIPTOR_MIN_LENGTH + MAX_SID + ACL_ROCK,
	MAXCOMP		= 128,
};

typedef struct	User	User;
typedef struct  Gmem	Gmem;
typedef	struct	Stat	Stat;
typedef	struct Fsinfo	Fsinfo;
typedef	WIN32_FIND_DATA	Fsdir;

#ifndef INVALID_SET_FILE_POINTER
#define	INVALID_SET_FILE_POINTER	((DWORD)-1)
#endif

struct Fsinfo
{
	int	uid;
	int	gid;
	int	mode;
	int	fd;
	vlong	offset;
	QLock	oq;
	char*	spec;
	Rune*	srv;
	Cname*	name;	/* Windows' idea of the file name */
	ushort	usesec;
	ushort	checksec;
	Fsdir*	de;	/* non-nil for saved entry from last dirread at offset */
};
#define	FS(c)	((Fsinfo*)(c)->aux)

/*
 * info about a user or group
 * there are two ways to specify a user:
 *	by sid, a unique identifier
 *	by user and domain names
 * this structure is used to convert between the two,
 * as well as figure out which groups a users belongs to.
 * the user information never gets thrown away,
 * but the group information gets refreshed with each setid.
 */
struct User
{
	QLock	lk;		/* locks the gotgroup and group fields */
	SID	*sid;
	Rune	*name;
	Rune	*dom;
	int	type;		/* the type of sid, ie SidTypeUser, SidTypeAlias, ... */
	int	gotgroup;	/* tried to add group */
	Gmem	*group;		/* global and local groups to which this user or group belongs. */
	User	*next;
};

struct Gmem
{
	User	*user;
	Gmem	*next;
};

/*
 * intermediate stat information
 */
struct Stat
{
	User	*owner;
	User	*group;
	ulong	mode;
};

/*
 * some "well-known" sids
 */
static	SID	*creatorowner;
static	SID	*creatorgroup;
static	SID	*everyone;
static	SID	*ntignore;
static	SID	*ntroot;	/* user who is supposed to run emu as a server */

/*
 * all users we ever see end up in this table
 * users are never deleted, but we should update
 * group information for users sometime
 */
static struct
{
	QLock	lk;
	User	*u;
}users;

/*
 * conversion from inferno permission modes to nt access masks
 * is this good enough?  this is what nt sets, except for NOMODE
 */
#define	NOMODE	(READ_CONTROL|FILE_READ_EA|FILE_READ_ATTRIBUTES)
#define	RMODE	(READ_CONTROL|SYNCHRONIZE\
		|FILE_READ_DATA|FILE_READ_EA|FILE_READ_ATTRIBUTES)
#define	XMODE	(READ_CONTROL|SYNCHRONIZE\
		|FILE_EXECUTE|FILE_READ_ATTRIBUTES)
#define	WMODE	(DELETE|READ_CONTROL|SYNCHRONIZE|WRITE_DAC|WRITE_OWNER\
		|FILE_WRITE_DATA|FILE_APPEND_DATA|FILE_WRITE_EA\
		|FILE_DELETE_CHILD|FILE_WRITE_ATTRIBUTES)

static	int
modetomask[] =
{
	NOMODE,
	XMODE,
	WMODE,
	WMODE|XMODE,
	RMODE,
	RMODE|XMODE,
	RMODE|WMODE,
	RMODE|WMODE|XMODE,
};

extern	DWORD	PlatformId;
	char    rootdir[MAXROOT] = "\\inferno";
	Rune	rootname[] = L"inferno-server";
static	Qid	rootqid;
static	User	*fsnone;
static	User	*fsuser;
static	Rune	*ntsrv;
static	int	usesec;
static	int	checksec;
static	int	isserver;
static	int	file_share_delete;
static	uchar	isntfrog[256];

static	void		fsremove(Chan*);

	wchar_t	*widen(char *s);
	char		*narrowen(wchar_t *ws);
	int		widebytes(wchar_t *ws);

static char Etoolong[] = "file name too long";

/*
 * these lan manager functions are not supplied
 * on windows95, so we have to load the dll by hand
 */
static struct {
	NET_API_STATUS (NET_API_FUNCTION *UserGetLocalGroups)(
		LPWSTR servername,
		LPWSTR username,
		DWORD level,
		DWORD flags,
		LPBYTE *bufptr,
		DWORD prefmaxlen,
		LPDWORD entriesread,
		LPDWORD totalentries);
	NET_API_STATUS (NET_API_FUNCTION *UserGetGroups)(
		LPWSTR servername,
		LPWSTR username,
		DWORD level,
		LPBYTE *bufptr,
		DWORD prefmaxlen,
		LPDWORD entriesread,
		LPDWORD totalentries);
	NET_API_STATUS (NET_API_FUNCTION *GetAnyDCName)(
		LPCWSTR ServerName,
		LPCWSTR DomainName,
		LPBYTE *Buffer);
	NET_API_STATUS (NET_API_FUNCTION *ApiBufferFree)(LPVOID Buffer);
} net;

extern	int		nth2fd(HANDLE);
extern	HANDLE		ntfd2h(int);
static	int		cnisroot(Cname*);
static	int		fsisroot(Chan*);
static	int		okelem(char*, int);
static	int		fsexist(char*, Qid*);
static	char*	fspath(Cname*, char*, char*, char*);
static	Cname*	fswalkpath(Cname*, char*, int);
static	char*	fslastelem(Cname*);
static	long		fsdirread(Chan*, uchar*, int, vlong);
static	ulong		fsqidpath(char*);
static	int		fsomode(int);
static	int		fsdirset(char*, int, WIN32_FIND_DATA*, char*, Chan*, int isdir);
static 	int		fsdirsize(WIN32_FIND_DATA*, char*, Chan*);
static	void		fssettime(char*, long, long);
static	long		unixtime(FILETIME);
static	FILETIME	wintime(ulong);
static	void		secinit(void);
static	int		secstat(Dir*, char*, Rune*);
static	int		secsize(char*, Rune*);
static	void		seccheck(char*, ulong, Rune*);
static	int		sechasperm(char*, ulong, Rune*);
static	SECURITY_DESCRIPTOR* secsd(char*, char[SD_ROCK]);
static	int		secsdhasperm(SECURITY_DESCRIPTOR*, ulong, Rune*);
static	int		secsdstat(SECURITY_DESCRIPTOR*, Stat*, Rune*);
static	SECURITY_DESCRIPTOR* secmksd(char[SD_ROCK], Stat*, ACL*, int);
static	SID		*dupsid(SID*);
static	int		ismembersid(Rune*, User*, SID*);
static	int		ismember(User*, User*);
static	User		*sidtouser(Rune*, SID*);
static	User		*domnametouser(Rune*, Rune*, Rune*);
static	User		*nametouser(Rune*, Rune*);
static	User		*unametouser(Rune*, char*);
static	void		addgroups(User*, int);
static	User		*mkuser(SID*, int, Rune*, Rune*);
static	Rune		*domsrv(Rune *, Rune[MAX_PATH]);
static	Rune		*filesrv(char*);
static	int		fsacls(char*);
static	User		*secuser(void);

	int		runeslen(Rune*);
	Rune*		runesdup(Rune*);
	Rune*		utftorunes(Rune*, char*, int);
	char*		runestoutf(char*, Rune*, int);
	int		runescmp(Rune*, Rune*);


int
winfilematch(char *path, WIN32_FIND_DATA *data)
{
	char *p;
	wchar_t *wpath;
	int r;

	p = path+strlen(path);
	while(p > path && p[-1] != '\\')
		--p;
	wpath = widen(p);
	r = (data->cFileName[0] == '.' && runeslen(data->cFileName) == 1)
			|| runescmp(data->cFileName, wpath) == 0;
	free(wpath);
	return r;
}

int
winfileclash(char *path)
{
	HANDLE h;
	WIN32_FIND_DATA data;
	wchar_t *wpath;

	wpath = widen(path);
	h = FindFirstFile(wpath, &data);
	free(wpath);
	if (h != INVALID_HANDLE_VALUE) {
		FindClose(h);
		return !winfilematch(path, &data);
	}
	return 0;
}


/*
 * this gets called to set up the environment when we switch users
 */
void
setid(char *name, int owner)
{
	User *u;

	if(owner && !iseve())
		return;

	kstrdup(&up->env->user, name);

	if(!usesec)
		return;

	u = unametouser(ntsrv, up->env->user);
	if(u == nil)
		u = fsnone;
	else {
		qlock(&u->lk);
		addgroups(u, 1);
		qunlock(&u->lk);
	}
	if(u == nil)
		panic("setid: user nil\n");

	up->env->ui = u;
}

static void
fsfree(Chan *c)
{
	cnameclose(FS(c)->name);
	if(FS(c)->de != nil)
		free(FS(c)->de);
	free(FS(c));
}

void
fsinit(void)
{
	int n, isvol;
	ulong attr;
	char *p, tmp[MAXROOT];
	wchar_t *wp, *wpath, *last;
	wchar_t wrootdir[MAXROOT];

	isntfrog['/'] = 1;
	isntfrog['\\'] = 1;
	isntfrog[':'] = 1;
	isntfrog['*'] = 1;
	isntfrog['?'] = 1;
	isntfrog['"'] = 1;
	isntfrog['<'] = 1;
	isntfrog['>'] = 1;

	/*
	 * vet the root
	 */
	strcpy(tmp, rootdir);
	for(p = tmp; *p; p++)
		if(*p == '/')
			*p = '\\';
	if(tmp[0] != 0 && tmp[1] == ':') {
		if(tmp[2] == 0) {
			tmp[2] = '\\';
			tmp[3] = 0;
		}
		else if(tmp[2] != '\\') {
			/* don't allow c:foo - only c:\foo */
			panic("illegal root pathX");
		}
	}
	wrootdir[0] = '\0';
	wpath = widen(tmp);
	for(wp = wpath; *wp; wp++) {
		if(*wp < 32 || (*wp < 256 && isntfrog[*wp] && *wp != '\\' && *wp != ':'))
			panic("illegal root path");
	}
	n = GetFullPathName(wpath, MAXROOT, wrootdir, &last);
	free(wpath);	
	runestoutf(rootdir, wrootdir, MAXROOT);
	if(n >= MAXROOT || n == 0)
		panic("illegal root path");

	/* get rid of trailing \ */
	while(rootdir[n-1] == '\\') {
		if(n <= 2) {
			panic("illegal root path");
		}
		rootdir[--n] = '\0';
	}

	isvol = 0;
	if(rootdir[1] == ':' && rootdir[2] == '\0')
		isvol = 1;
	else if(rootdir[0] == '\\' && rootdir[1] == '\\') {
		p = strchr(&rootdir[2], '\\');
		if(p == nil)
			panic("inferno root can't be a server");
		isvol = strchr(p+1, '\\') == nil;
	}

	if(strchr(rootdir, '\\') == nil)
		strcat(rootdir, "\\.");
	attr = GetFileAttributes(wrootdir);
	if(attr == 0xFFFFFFFF)
		panic("root path '%s' does not exist", narrowen(wrootdir));
	rootqid.path = fsqidpath(rootdir);
	if(attr & FILE_ATTRIBUTE_DIRECTORY)
		rootqid.type |= QTDIR;
	rootdir[n] = '\0';

	rootqid.vers = time(0);

	/*
	 * set up for nt file security checking
	 */
	ntsrv = filesrv(rootdir);
	usesec = PlatformId == VER_PLATFORM_WIN32_NT; 	/* true for NT and 2000 */
	if(usesec){
		file_share_delete = FILE_SHARE_DELETE;	/* sensible handling of shared files by delete and rename */
		secinit();
		if(!fsacls(rootdir))
			usesec = 0;
	}
	checksec = usesec && isserver;
}

Chan*
fsattach(char *spec)
{
	Chan *c;
	static int devno;
	static Lock l;
	char *drive = (char *)spec;

	if (!emptystr(drive) && (drive[1] != ':' || drive[2] != '\0'))
		error(Ebadspec);

	c = devattach('U', spec);
	lock(&l);
	c->dev = devno++;
	unlock(&l);
	c->qid = rootqid;
	c->aux = smalloc(sizeof(Fsinfo));
	FS(c)->srv = ntsrv;
	if(!emptystr(spec)) {
		char *s = smalloc(strlen(spec)+1);
		strcpy(s, spec);
		FS(c)->spec = s;
		FS(c)->srv = filesrv(spec);
		FS(c)->usesec = fsacls(spec);
		FS(c)->checksec = FS(c)->usesec && isserver;
		c->qid.path = fsqidpath(spec);
		c->qid.type = QTDIR;
		c->qid.vers = 0;
	}else{
		FS(c)->usesec = usesec;
		FS(c)->checksec = checksec;
	}
	FS(c)->name = newcname("/");
	return c;
}

Walkqid*
fswalk(Chan *c, Chan *nc, char **name, int nname)
{
	int j, alloc;
	Walkqid *wq;
	char path[MAX_PATH], *p;
	Cname *ph;
	Cname *current, *next;

	if(nname > 0)
		isdir(c);

	alloc = 0;
	current = nil;
	wq = smalloc(sizeof(Walkqid)+(nname-1)*sizeof(Qid));
	if(waserror()){
		if(alloc && wq->clone != nil)
			cclose(wq->clone);
		cnameclose(current);
		free(wq);
		return nil;
	}
	if(nc == nil){
		nc = devclone(c);
		nc->type = 0;
		alloc = 1;
	}
	wq->clone = nc;
	current = FS(c)->name;
	if(current != nil)
		incref(&current->r);
	for(j = 0; j < nname; j++){
		if(!(nc->qid.type&QTDIR)){
			if(j==0)
				error(Enotdir);
			break;
		}
		if(!okelem(name[j], 0)){
			if(j == 0)
				error(Efilename);
			break;
		}
		p = fspath(current, name[j], path, FS(c)->spec);
		if(FS(c)->checksec) {
			*p = '\0';
			if(!sechasperm(path, XMODE, FS(c)->srv)){
				if(j == 0)
					error(Eperm);
				break;
			}
			*p = '\\';
		}

		if(strcmp(name[j], "..") == 0) {
			if(fsisroot(c))
				nc->qid = rootqid;
			else{
				ph = fswalkpath(current, "..", 1);
				if(cnisroot(ph)){
					nc->qid = rootqid;
					current = ph;
					if(current != nil)
						incref(&current->r);
				}
				else {
					fspath(ph, 0, path, FS(c)->spec);
					if(!fsexist(path, &nc->qid)){
						cnameclose(ph);
						if(j == 0)
							error(Enonexist);
						break;
					}
				}
				next = fswalkpath(current, name[j], 1);
				cnameclose(current);
				current = next;
				cnameclose(ph);
			}
		}
		else{
			if(!fsexist(path, &nc->qid)){
				if(j == 0)
					error(Enonexist);
				break;
			}
			next = fswalkpath(current, name[j], 1);
			cnameclose(current);
			current = next;
		}
		wq->qid[wq->nqid++] = nc->qid;
	}
	poperror();
	if(wq->nqid < nname){
		cnameclose(current);
		if(alloc)
			cclose(wq->clone);
		wq->clone = nil;
	}else if(wq->clone){
		nc->aux = smalloc(sizeof(Fsinfo));
		nc->type = c->type;
		FS(nc)->spec = FS(c)->spec;
		FS(nc)->srv = FS(c)->srv;
		FS(nc)->name = current;
		FS(nc)->usesec = FS(c)->usesec;
		FS(nc)->checksec = FS(c)->checksec;
	}
	return wq;
}

Chan*
fsopen(Chan *c, int mode)
{
	HANDLE h;
	int m, isdir, aflag, cflag;
	char path[MAX_PATH];
	wchar_t *wpath;

	isdir = c->qid.type & QTDIR;
	if(isdir && mode != OREAD)
		error(Eperm);
	fspath(FS(c)->name, 0, path, FS(c)->spec);

	if(FS(c)->checksec) {
		switch(mode & (OTRUNC|3)) {
		case OREAD:
			seccheck(path, RMODE, FS(c)->srv);
			break;
		case OWRITE:
		case OWRITE|OTRUNC:
			seccheck(path, WMODE, FS(c)->srv);
			break;
		case ORDWR:
		case ORDWR|OTRUNC:
		case OREAD|OTRUNC:
			seccheck(path, RMODE|WMODE, FS(c)->srv);
			break;
		case OEXEC:
			seccheck(path, XMODE, FS(c)->srv);
			break;
		default:
			error(Ebadarg);
		}
	}

	c->mode = openmode(mode);
	if(isdir)
		FS(c)->fd = nth2fd(INVALID_HANDLE_VALUE);
	else {
		m = fsomode(mode & 3);
		cflag = OPEN_EXISTING;
		if(mode & OTRUNC)
			cflag = TRUNCATE_EXISTING;
		aflag = FILE_FLAG_RANDOM_ACCESS;
		if(mode & ORCLOSE)
			aflag |= FILE_FLAG_DELETE_ON_CLOSE;
		if (winfileclash(path))
			error(Eexist);
		wpath = widen(path);
		h = CreateFile(wpath, m, FILE_SHARE_READ|FILE_SHARE_WRITE|file_share_delete, 0, cflag, aflag, 0);
		free(wpath);
		if(h == INVALID_HANDLE_VALUE)
			oserror();
		FS(c)->fd = nth2fd(h);
	}

	c->offset = 0;
	FS(c)->offset = 0;
	c->flag |= COPEN;
	return c;
}

void
fscreate(Chan *c, char *name, int mode, ulong perm)
{
	Stat st;
	HANDLE h;
	int m, aflag;
	SECURITY_ATTRIBUTES sa;
	SECURITY_DESCRIPTOR *sd;
	BY_HANDLE_FILE_INFORMATION hi;
	char *p, path[MAX_PATH], sdrock[SD_ROCK];
	wchar_t *wpath;
	ACL *acl;

	if(!okelem(name, 1))
		error(Efilename);

	m = fsomode(mode & 3);
	p = fspath(FS(c)->name, name, path, FS(c)->spec);
	acl = (ACL*)smalloc(ACL_ROCK);
	sd = nil;
	if(FS(c)->usesec) {
		*p = '\0';
		sd = secsd(path, sdrock);
		*p = '\\';
		if(sd == nil){
			free(acl);
			oserror();
		}
		if(FS(c)->checksec && !secsdhasperm(sd, WMODE, FS(c)->srv)
		|| !secsdstat(sd, &st, FS(c)->srv)){
			if(sd != (void*)sdrock)
				free(sd);
			free(acl);
			error(Eperm);
		}
		if(sd != (void*)sdrock)
			free(sd);
		if(perm & DMDIR)
			st.mode = (perm & ~0777) | (st.mode & perm & 0777);
		else
			st.mode = (perm & ~0666) | (st.mode & perm & 0666);
		st.owner = up->env->ui;
		if(!isserver)
			st.owner = fsuser;
		sd = secmksd(sdrock, &st, acl, perm & DMDIR);
		if(sd == nil){
			free(acl);
			oserror();
		}
	}
	sa.nLength = sizeof(sa);
	sa.lpSecurityDescriptor = sd;
	sa.bInheritHandle = 0;

	if(perm & DMDIR) {
		if(mode != OREAD) {
			free(acl);
			error(Eisdir);
		}
		wpath = widen(path);
		if(!CreateDirectory(wpath, &sa) || !fsexist(path, &c->qid)) {
			free(wpath);
			free(acl);
			oserror();
		}
		free(wpath);
		FS(c)->fd = nth2fd(INVALID_HANDLE_VALUE);
	}
	else {
		aflag = 0;
		if(mode & ORCLOSE)
			aflag = FILE_FLAG_DELETE_ON_CLOSE;
		if (winfileclash(path))
			error(Eexist);
		wpath = widen(path);
		h = CreateFile(wpath, m, FILE_SHARE_READ|FILE_SHARE_WRITE|file_share_delete, &sa, CREATE_ALWAYS, aflag, 0);
		free(wpath);
		if(h == INVALID_HANDLE_VALUE) {
			free(acl);
			oserror();
		}
		FS(c)->fd = nth2fd(h);
		c->qid.path = fsqidpath(path);
		c->qid.type = 0;
		c->qid.vers = 0;
		if(GetFileInformationByHandle(h, &hi))
			c->qid.vers = unixtime(hi.ftLastWriteTime);
	}

	c->mode = openmode(mode);
	c->offset = 0;
	FS(c)->offset = 0;
	c->flag |= COPEN;
	FS(c)->name = fswalkpath(FS(c)->name, name, 0);
	free(acl);
}

void
fsclose(Chan *c)
{
	HANDLE h;

	if(c->flag & COPEN){
		h = ntfd2h(FS(c)->fd);
		if(h != INVALID_HANDLE_VALUE){
			if(c->qid.type & QTDIR)
				FindClose(h);
			else
				CloseHandle(h);
		}
	}
	if(c->flag & CRCLOSE){
		if(!waserror()){
			fsremove(c);
			poperror();
		}
		return;
	}
	fsfree(c);
}

/*
 * 64-bit seeks, using SetFilePointer because SetFilePointerEx
 * is not supported by NT
 */
static void
fslseek(HANDLE h, vlong offset)
{
	LONG hi;

	if(offset <= 0x7fffffff){
		if(SetFilePointer(h, (LONG)offset, NULL, FILE_BEGIN) == INVALID_SET_FILE_POINTER)
			oserror();
	}else{
		hi = offset>>32;
		if(SetFilePointer(h, (LONG)offset, &hi, FILE_BEGIN) == INVALID_SET_FILE_POINTER &&
		   GetLastError() != NO_ERROR)
			oserror();
	}
}

long
fsread(Chan *c, void *va, long n, vlong offset)
{
	DWORD n2;
	HANDLE h;

	qlock(&FS(c)->oq);
	if(waserror()){
		qunlock(&FS(c)->oq);
		nexterror();
	}
	if(c->qid.type & QTDIR) {
		n2 = fsdirread(c, va, n, offset);
	}
	else {
		h = ntfd2h(FS(c)->fd);
		if(FS(c)->offset != offset){
			fslseek(h, offset);
			FS(c)->offset = offset;
		}
		if(!ReadFile(h, va, n, &n2, NULL))
			oserror();
		FS(c)->offset += n2;
	}
	qunlock(&FS(c)->oq);
	poperror();
	return n2;
}

long
fswrite(Chan *c, void *va, long n, vlong offset)
{
	DWORD n2;
	HANDLE h;

	qlock(&FS(c)->oq);
	if(waserror()){
		qunlock(&FS(c)->oq);
		nexterror();
	}
	h = ntfd2h(FS(c)->fd);
	if(FS(c)->offset != offset){
		fslseek(h, offset);
		FS(c)->offset = offset;
	}
	if(!WriteFile(h, va, n, &n2, NULL))
		oserror();
	FS(c)->offset += n2;
	qunlock(&FS(c)->oq);
	poperror();
	return n2;
}

int
fsstat(Chan *c, uchar *buf, int n)
{
	WIN32_FIND_DATA data;
	char path[MAX_PATH];
	wchar_t *wpath;

	/*
	 * have to fake up a data for volumes like
	 * c: and \\server\share since you can't FindFirstFile them
	 */
	if(fsisroot(c)){
		strcpy(path, rootdir);
		if(strchr(path, '\\') == nil)
			strcat(path, "\\.");
		wpath = widen(path);
		data.dwFileAttributes = GetFileAttributes(wpath);
		free(wpath);
		if(data.dwFileAttributes == 0xffffffff)
			oserror();
		data.ftCreationTime =
		data.ftLastAccessTime =
		data.ftLastWriteTime = wintime(time(0));
		data.nFileSizeHigh = 0;
		data.nFileSizeLow = 0;
		utftorunes(data.cFileName, ".", MAX_PATH);
	} else {
		HANDLE h = INVALID_HANDLE_VALUE;

		fspath(FS(c)->name, 0, path, FS(c)->spec);
		if (c->flag & COPEN)
			h = ntfd2h(FS(c)->fd);

		if (h != INVALID_HANDLE_VALUE) {
			BY_HANDLE_FILE_INFORMATION fi;
			if (c->mode & OWRITE)
				FlushFileBuffers(h);
			if (!GetFileInformationByHandle(h, &fi))
				oserror();
			data.dwFileAttributes = fi.dwFileAttributes;
			data.ftCreationTime = fi.ftCreationTime;
			data.ftLastAccessTime = fi.ftLastAccessTime;
			data.ftLastWriteTime = fi.ftLastWriteTime;;
			data.nFileSizeHigh = fi.nFileSizeHigh;
			data.nFileSizeLow = fi.nFileSizeLow;
		} else {
			wpath = widen(path);
			h = FindFirstFile(wpath, &data);
			free(wpath);
			if(h == INVALID_HANDLE_VALUE)
				oserror();
			if (!winfilematch(path, &data)) {
				FindClose(h);
				error(Enonexist);
			}
			FindClose(h);
		}
		utftorunes(data.cFileName, fslastelem(FS(c)->name), MAX_PATH);
	}

	return fsdirset(buf, n, &data, path, c, 0);
}

int
fswstat(Chan *c, uchar *buf, int n)
{
	int wsd;
	Dir dir;
	Stat st;
	Cname * volatile ph;
	HANDLE h;
	ulong attr;
	User *ou, *gu;
	WIN32_FIND_DATA data;
	SECURITY_DESCRIPTOR *sd;
	char *last, sdrock[SD_ROCK], path[MAX_PATH], newpath[MAX_PATH], strs[4*256];
	wchar_t wspath[MAX_PATH], wsnewpath[MAX_PATH];
	wchar_t *wpath;
	int nmatch;

	n = convM2D(buf, n, &dir, strs);
	if(n == 0)
		error(Eshortstat);

	last = fspath(FS(c)->name, 0, path, FS(c)->spec);
	utftorunes(wspath, path, MAX_PATH);

	if(fsisroot(c)){
		if(dir.atime != ~0)
			data.ftLastAccessTime = wintime(dir.atime);
		if(dir.mtime != ~0)
			data.ftLastWriteTime = wintime(dir.mtime);
		utftorunes(data.cFileName, ".", MAX_PATH);
	}else{
		h = FindFirstFile(wspath, &data);
		if(h == INVALID_HANDLE_VALUE)
			oserror();
		if (!winfilematch(path, &data)) {
			FindClose(h);
			error(Enonexist);
		}
		FindClose(h);
	}

	wsd = 0;
	ou = nil;
	gu = nil;
	if(FS(c)->usesec) {
		if(FS(c)->checksec && up->env->ui == fsnone)
			error(Eperm);

		/*
		 * find new owner and group
		 */
		if(!emptystr(dir.uid)){
			ou = unametouser(FS(c)->srv, dir.uid);
			if(ou == nil)
				oserror();
		}
		if(!emptystr(dir.gid)){
			gu = unametouser(FS(c)->srv, dir.gid);
			if(gu == nil){
				if(strcmp(dir.gid, "unknown") != 0
				&& strcmp(dir.gid, "deleted") != 0)
					oserror();
				gu = ou;
			}
		}

		/*
		 * find old stat info
		 */
		sd = secsd(path, sdrock);
		if(sd == nil || !secsdstat(sd, &st, FS(c)->srv)){
			if(sd != nil && sd != (void*)sdrock)
				free(sd);
			oserror();
		}
		if(sd != (void*)sdrock)
			free(sd);

		/*
		 * permission rules:
		 * if none, can't do anything
		 * chown => no way
		 * chgrp => current owner or group, and in new group
		 * mode/time => owner or in either group
		 * rename => write in parent
		 */
		if(ou == nil)
			ou = st.owner;
		if(FS(c)->checksec && st.owner != ou)
			error(Eperm);

		if(gu == nil)
			gu = st.group;
		if(st.group != gu){
			if(FS(c)->checksec
			&&(!ismember(up->env->ui, ou) && !ismember(up->env->ui, gu)
			|| !ismember(up->env->ui, st.group)))
				error(Eperm);
			wsd = 1;
		}

		if(dir.atime != ~0 && unixtime(data.ftLastAccessTime) != dir.atime
		|| dir.mtime != ~0 && unixtime(data.ftLastWriteTime) != dir.mtime
		|| dir.mode != ~0 && st.mode != dir.mode){
			if(FS(c)->checksec
			&& !ismember(up->env->ui, ou)
			&& !ismember(up->env->ui, gu)
			&& !ismember(up->env->ui, st.group))
				error(Eperm);
			if(dir.mode != ~0 && st.mode != dir.mode)
				wsd = 1;
		}
	}
	wpath = widen(dir.name);
	nmatch = runescmp(wpath, data.cFileName);
	free(wpath);
	if(!emptystr(dir.name) && nmatch != 0){
		if(!okelem(dir.name, 1))
			error(Efilename);
		ph = fswalkpath(FS(c)->name, "..", 1);
		if(waserror()){
			cnameclose(ph);
			nexterror();
		}
		ph = fswalkpath(ph, dir.name, 0);
		fspath(ph, 0, newpath, FS(c)->spec);
		utftorunes(wsnewpath, newpath, MAX_PATH);
		if(GetFileAttributes(wpath) != 0xffffffff && !winfileclash(newpath))
			error("file already exists");
		if(fsisroot(c))
			error(Eperm);
		if(FS(c)->checksec){
			*last = '\0';
			seccheck(path, WMODE, FS(c)->srv);
			*last = '\\';
		}
		poperror();
		cnameclose(ph);
	}

	if(dir.atime != ~0 && unixtime(data.ftLastAccessTime) != dir.atime
	|| dir.mtime != ~0 && unixtime(data.ftLastWriteTime) != dir.mtime)
		fssettime(path, dir.atime, dir.mtime);

	attr = data.dwFileAttributes;
	if(dir.mode & 0222)
		attr &= ~FILE_ATTRIBUTE_READONLY;
	else
		attr |= FILE_ATTRIBUTE_READONLY;
	if(!fsisroot(c)
	&& attr != data.dwFileAttributes
	&& (attr & FILE_ATTRIBUTE_READONLY))
		SetFileAttributes(wspath, attr);
	if(FS(c)->usesec && wsd){
		ACL *acl = (ACL *) smalloc(ACL_ROCK);
		st.owner = ou;
		st.group = gu;
		if(dir.mode != ~0)
			st.mode = dir.mode;
		sd = secmksd(sdrock, &st, acl, data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY);
		if(sd == nil || !SetFileSecurity(wspath, DACL_SECURITY_INFORMATION, sd)){
			free(acl);
			oserror();
		}
		free(acl);
	}

	if(!fsisroot(c)
	&& attr != data.dwFileAttributes
	&& !(attr & FILE_ATTRIBUTE_READONLY))
		SetFileAttributes(wspath, attr);

	/* do last so path is valid throughout */
	wpath = widen(dir.name);
	nmatch = runescmp(wpath, data.cFileName);
	free(wpath);
	if(!emptystr(dir.name) && nmatch != 0) {
		ph = fswalkpath(FS(c)->name, "..", 1);
		if(waserror()){
			cnameclose(ph);
			nexterror();
		}
		ph = fswalkpath(ph, dir.name, 0);
		fspath(ph, 0, newpath, FS(c)->spec);
		utftorunes(wsnewpath, newpath, MAX_PATH);
		/*
		 * can't rename if it is open: if this process has it open, close it temporarily.
		 */
		if(!file_share_delete && c->flag & COPEN){
			h = ntfd2h(FS(c)->fd);
			if(h != INVALID_HANDLE_VALUE)
				CloseHandle(h);	/* woe betide it if ORCLOSE */
			FS(c)->fd = nth2fd(INVALID_HANDLE_VALUE);
		}
		if(!MoveFile(wspath, wsnewpath)) {
			oserror();
		} else if(!file_share_delete && c->flag & COPEN) {
			int	aflag;
			SECURITY_ATTRIBUTES sa;
			
			/* The move succeeded, so open new file to maintain handle */
			sa.nLength = sizeof(sa);
			sa.lpSecurityDescriptor = sd;
			sa.bInheritHandle = 0;
			if(c->flag & CRCLOSE)
				aflag = FILE_FLAG_DELETE_ON_CLOSE;
			h = CreateFile(wsnewpath, fsomode(c->mode & 0x3), FILE_SHARE_READ|FILE_SHARE_WRITE|file_share_delete, &sa, OPEN_EXISTING, aflag, 0);
			if(h == INVALID_HANDLE_VALUE)
				oserror();
			FS(c)->fd = nth2fd(h);
		}
		cnameclose(FS(c)->name);
		poperror();
		FS(c)->name = ph;
	}
	return n;
}

static void
fsremove(Chan *c)
{
	int n;
	char *p, path[MAX_PATH];
	wchar_t wspath[MAX_PATH];

	if(waserror()){
		fsfree(c);
		nexterror();
	}
	if(fsisroot(c))
		error(Eperm);
	p = fspath(FS(c)->name, 0, path, FS(c)->spec);
	utftorunes(wspath, path, MAX_PATH);
	if(FS(c)->checksec){
		*p = '\0';
		seccheck(path, WMODE, FS(c)->srv);
		*p = '\\';
	}
	if(c->qid.type & QTDIR)
		n = RemoveDirectory(wspath);
	else
		n = DeleteFile(wspath);
	if (!n) {
		ulong attr, mode;
		SECURITY_DESCRIPTOR *sd = nil;
		char sdrock[SD_ROCK];
		Stat st;
		int secok;
		attr = GetFileAttributes(wspath);
		if(attr != 0xFFFFFFFF) {
			if (FS(c)->usesec) {
				sd = secsd(path, sdrock);
				secok = (sd != nil) && secsdstat(sd, &st, FS(c)->srv);
				if (secok) {
					ACL *acl = (ACL *) smalloc(ACL_ROCK);
					mode = st.mode;
					st.mode |= 0660;
					sd = secmksd(sdrock, &st, acl, attr & FILE_ATTRIBUTE_DIRECTORY);
					if(sd != nil) {
						SetFileSecurity(wspath, DACL_SECURITY_INFORMATION, sd);
					}
					free(acl);
					if(sd != nil && sd != (void*)sdrock)
						free(sd);
					sd = nil;
				}
			}
			SetFileAttributes(wspath, FILE_ATTRIBUTE_NORMAL);
			if(c->qid.type & QTDIR)
				n = RemoveDirectory(wspath);
			else
				n = DeleteFile(wspath);
			if (!n) {
				if (FS(c)->usesec && secok) {
					ACL *acl = (ACL *) smalloc(ACL_ROCK);
					st.mode =  mode;
					sd = secmksd(sdrock, &st, acl, attr & FILE_ATTRIBUTE_DIRECTORY);
					if(sd != nil) {
						SetFileSecurity(wspath, DACL_SECURITY_INFORMATION, sd);
					}
					free(acl);
				}
				SetFileAttributes(wspath, attr);
				if(sd != nil && sd != (void*)sdrock)
					free(sd);
			}
		}
	}
	if(!n)
		oserror();
	poperror();
	fsfree(c);
}

/*
 * check elem for illegal characters /\:*?"<>
 * ... and relatives are also disallowed,
 * since they specify grandparents, which we
 * are not prepared to handle
 */
static int
okelem(char *elem, int nodots)
{
	int c, dots;

	dots = 0;
	while((c = *(uchar*)elem) != 0){
		if(isntfrog[c])
			return 0;
		if(c == '.' && dots >= 0)
			dots++;
		else
			dots = -1;
		elem++;
	}
	if(nodots)
		return dots <= 0;
	return dots <= 2;
}

static int
cnisroot(Cname *c)
{
	return strcmp(c->s, "/") == 0;
}

static int
fsisroot(Chan *c)
{
	return strcmp(FS(c)->name->s, "/") == 0;
}

static char*
fspath(Cname *c, char *ext, char *path, char *spec)
{
	char *p, *last, *rootd;
	int extlen = 0;

	rootd = spec != nil ? spec : rootdir;
	if(ext)
		extlen = strlen(ext) + 1;
	if(strlen(rootd) + extlen >= MAX_PATH)
		error(Etoolong);
	strcpy(path, rootd);
	if(cnisroot(c)){
		if(ext) {
			strcat(path, "\\");
			strcat(path, ext);
		}
	}else{
		if(*c->s != '/') {
			if(strlen(path) + 1 >= MAX_PATH)
				error(Etoolong);
			strcat(path, "\\");
		}
		if(strlen(path) + strlen(c->s) + extlen >= MAX_PATH)
			error(Etoolong);
		strcat(path, c->s);
		if(ext){
			strcat(path, "\\");
			strcat(path, ext);
		}
	}
	last = path;
	for(p = path; *p != '\0'; p++){
		if(*p == '/' || *p == '\\'){
			*p = '\\';
			last = p;
		}
	}
	return last;
}

extern void cleancname(Cname*);

static Cname *
fswalkpath(Cname *c, char *name, int dup)
{
	if(dup)
		c = newcname(c->s);
	c = addelem(c, name);
	if(isdotdot(name))
		cleancname(c);
	return c;
}

static char *
fslastelem(Cname *c)
{
	char *p;

	p = c->s + c->len;
	while(p > c->s && p[-1] != '/')
		p--;
	return p;
}

static int
fsdirbadentry(WIN32_FIND_DATA *data)
{
	wchar_t *s;

	s = data->cFileName;
	if(s[0] == 0)
		return 1;
	if(s[0] == '.' && (s[1] == 0 || s[1] == '.' && s[2] == 0))
		return 1;

	return 0;
}

static Fsdir*
fsdirent(Chan *c, char *path, Fsdir *data)
{
	wchar_t *wpath;
	HANDLE h;

	h = ntfd2h(FS(c)->fd);
	if(data == nil)
		data = smalloc(sizeof(*data));
	if(FS(c)->offset == 0){
		if(h != INVALID_HANDLE_VALUE)
			FindClose(h);
		wpath = widen(path);
		h = FindFirstFile(wpath, data);
		free(wpath);
		FS(c)->fd = nth2fd(h);
		if(h == INVALID_HANDLE_VALUE){
			free(data);
			return nil;
		}
		if(!fsdirbadentry(data))
			return data;
	}
	do{
		if(!FindNextFile(h, data)){
			free(data);
			return nil;
		}
	}while(fsdirbadentry(data));
	return data;
}

static long
fsdirread(Chan *c, uchar *va, int count, vlong offset)
{
	int i, r;
	char path[MAX_PATH], *p;
	Fsdir *de;
	vlong o;

	if(count == 0 || offset < 0)
		return 0;
	p = fspath(FS(c)->name, "*.*", path, FS(c)->spec);
	p++;
	de = nil;
	if(FS(c)->offset != offset){
		de = FS(c)->de;
		if(FS(c)->de != nil){
			free(FS(c)->de);
			FS(c)->de = nil;
		}
		FS(c)->offset = 0;
		for(o = 0; o < offset;){
			de = fsdirent(c, path, de);
			if(de == nil){
				FS(c)->offset = o;
				return 0;
			}
			runestoutf(p, de->cFileName, &path[MAX_PATH]-p);
			path[MAX_PATH-1] = '\0';
			o += fsdirsize(de, path, c);
		}
		FS(c)->offset = offset;
	}
	for(i = 0; i < count;){
		if(FS(c)->de != nil){	/* left over from previous read at offset */
			de = FS(c)->de;
			FS(c)->de = nil;
		}else{
			de = fsdirent(c, path, de);
			if(de == nil)
				break;
		}
		runestoutf(p, de->cFileName, &path[MAX_PATH]-p);
		path[MAX_PATH-1] = '\0';
		r = fsdirset(va+i, count-i, de, path, c, 1);
		if(r <= 0){
			/* won't fit; save for next read at this offset */
			FS(c)->de = de;
			break;
		}
		i += r;
		FS(c)->offset += r;
	}
	return i;
}

static ulong
fsqidpath(char *p)
{
	ulong h;
	int c;

	h = 0;
	while(*p != '\0'){
		/* force case insensitive file names */
		c = *p++;
		if(c >= 'A' && c <= 'Z')
			c += 'a'-'A';
		h = h * 19 ^ c;
	}
	return h;
}

/* TO DO: substitute fixed, made-up (unlikely) names for these */
static char* devf[] = { "aux", "com1", "com2", "lpt1", "nul", "prn", nil };

static int
devfile(char *p)
{
	char *s, *t, *u, **ss;

	if((u = strrchr(p, '\\')) != nil)
		u++;
	else if((u = strrchr(p, '/')) != nil)
		u++;
	else
		u = p;
	for(ss = devf; *ss != nil; ss++){
		for(s = *ss, t = u; *s != '\0' && *t != '\0' && *t != '.'; s++, t++)
			if(*s != *t && *s != *t+'a'-'A')
				break;
		if(*s == '\0' && (*t == '\0' || *t == '.'))
			return 1;
	}
	return 0;
}

/*
 * there are other ways to figure out
 * the attributes and times for a file.
 * perhaps they are faster
 */
static int
fsexist(char *p, Qid *q)
{
	HANDLE h;
	WIN32_FIND_DATA data;
	wchar_t *wpath;

	if(devfile(p))
		return 0;
	wpath = widen(p);
	h = FindFirstFile(wpath, &data);
	free(wpath);
	if(h == INVALID_HANDLE_VALUE)
		return 0;
			if (!winfilematch(p, &data)) {
				FindClose(h);
				return 0;
			}
	FindClose(h);

	q->path = fsqidpath(p);
	q->type = 0;

	if(data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
		q->type |= QTDIR;

	q->vers = unixtime(data.ftLastWriteTime);

	return 1;
}

static int
fsdirset(char *edir, int n, WIN32_FIND_DATA *data, char *path, Chan *c, int isdir)
{
	Dir dir;
	static char neveryone[] = "Everyone";

	dir.name = narrowen(data->cFileName);
	dir.muid = nil;
	dir.qid.path = fsqidpath(path);
	dir.qid.vers = 0;
	dir.qid.type = 0;
	dir.mode = 0;
	dir.atime = unixtime(data->ftLastAccessTime);
	dir.mtime = unixtime(data->ftLastWriteTime);
	dir.qid.vers = dir.mtime;
	dir.length = ((uvlong)data->nFileSizeHigh<<32) | ((uvlong)data->nFileSizeLow & ~((uvlong)0xFFFFFFFF<<32));
	dir.type = 'U';
	dir.dev = c->dev;

	if(!FS(c)->usesec){
		/* no NT security so make something up */
		dir.uid = neveryone;
		dir.gid = neveryone;
		dir.mode = 0777;
	}else if(!secstat(&dir, path, FS(c)->srv))
		oserror();

	if(data->dwFileAttributes & FILE_ATTRIBUTE_READONLY)
		dir.mode &= ~0222;
	if(data->dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY){
		dir.qid.type |= QTDIR;
		dir.mode |= DMDIR;
		dir.length = 0;
	}

	if(isdir && sizeD2M(&dir) > n)
		n = -1;
	else 
		n = convD2M(&dir, edir, n);
	if(dir.uid != neveryone)
		free(dir.uid);
	if(dir.gid != neveryone)
		free(dir.gid);
	free(dir.name);
	return n;
}

static int
fsdirsize(WIN32_FIND_DATA *data, char *path, Chan *c)
{
	int i, n;

	n = widebytes(data->cFileName);
	if(!FS(c)->usesec)
		n += 8+8;
	else{
		i = secsize(path, FS(c)->srv);
		if(i < 0)
			oserror();
		n += i;
	}
	return STATFIXLEN+n;
}

static void
fssettime(char *path, long at, long mt)
{
	HANDLE h;
	FILETIME atime, mtime;
	wchar_t *wpath;

	wpath = widen(path);
	h = CreateFile(wpath, GENERIC_WRITE,
		0, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
	free(wpath);
	if(h == INVALID_HANDLE_VALUE)
		return;
	mtime = wintime(mt);
	atime = wintime(at);
	if(!SetFileTime(h, 0, &atime, &mtime)){
		CloseHandle(h);
		oserror();
	}
	CloseHandle(h);
}

static int
fsomode(int m)
{
	switch(m & 0x3) {
	case OREAD:
	case OEXEC:
		return GENERIC_READ;
	case OWRITE:
		return GENERIC_WRITE;
	case ORDWR:
		return GENERIC_READ|GENERIC_WRITE;
	}
	error(Ebadarg);
	return 0;
}

static long
unixtime(FILETIME ft)
{
	vlong t;

	t = (vlong)ft.dwLowDateTime + ((vlong)ft.dwHighDateTime<<32);
	t -= (vlong)10000000*134774*24*60*60;

	return (long)(t/10000000);
}

static FILETIME
wintime(ulong t)
{
	FILETIME ft;
	vlong vt;

	vt = (vlong)t*10000000+(vlong)10000000*134774*24*60*60;

	ft.dwLowDateTime = vt;
	ft.dwHighDateTime = vt>>32;

	return ft;
}

/*
 * the sec routines manage file permissions for nt.
 * nt files have an associated security descriptor,
 * which has in it an owner, a group,
 * and a discretionary acces control list, or acl,
 * which specifies the permissions for the file.
 *
 * the strategy for mapping between inferno owner,
 * group, other, and mode and nt file security is:
 *
 *	inferno owner == nt file owner
 *	inferno other == nt Everyone
 *	inferno group == first non-owner,
 *			non-Everyone user given in the acl,
 *			or the owner if there is no such user.
 * we examine the entire acl when check for permissions,
 * but only report a subset.
 *
 * when we write an acl, we also give all permissions to
 * the special user rootname, who is supposed to run emu in server mode.
 */
static void
secinit(void)
{
	HMODULE lib;
	HANDLE token;
	TOKEN_PRIVILEGES *priv;
	char privrock[sizeof(TOKEN_PRIVILEGES) + 1*sizeof(LUID_AND_ATTRIBUTES)];
	SID_IDENTIFIER_AUTHORITY id = SECURITY_CREATOR_SID_AUTHORITY;
	SID_IDENTIFIER_AUTHORITY wid = SECURITY_WORLD_SID_AUTHORITY;
	SID_IDENTIFIER_AUTHORITY ntid = SECURITY_NT_AUTHORITY;

	lib = LoadLibraryA("netapi32");
	if(lib == 0) {
		usesec = 0;
		return;
	}

	net.UserGetGroups = (void*)GetProcAddress(lib, "NetUserGetGroups");
	if(net.UserGetGroups == 0)
		panic("bad netapi32 library");
	net.UserGetLocalGroups = (void*)GetProcAddress(lib, "NetUserGetLocalGroups");
	if(net.UserGetLocalGroups == 0)
		panic("bad netapi32 library");
	net.GetAnyDCName = (void*)GetProcAddress(lib, "NetGetAnyDCName");
	if(net.GetAnyDCName == 0)
		panic("bad netapi32 library");
	net.ApiBufferFree = (void*)GetProcAddress(lib, "NetApiBufferFree");
	if(net.ApiBufferFree == 0)
		panic("bad netapi32 library");

	if(!AllocateAndInitializeSid(&id, 1,
		SECURITY_CREATOR_OWNER_RID,
		1, 2, 3, 4, 5, 6, 7, &creatorowner)
	|| !AllocateAndInitializeSid(&id, 1,
		SECURITY_CREATOR_GROUP_RID,
		1, 2, 3, 4, 5, 6, 7, &creatorgroup)
	|| !AllocateAndInitializeSid(&wid, 1,
		SECURITY_WORLD_RID,
		1, 2, 3, 4, 5, 6, 7, &everyone)
	|| !AllocateAndInitializeSid(&ntid, 1,
		0,
		1, 2, 3, 4, 5, 6, 7, &ntignore))
		panic("can't initialize well-known sids");

	fsnone = sidtouser(ntsrv, everyone);
	if(fsnone == nil)
		panic("can't make none user");

	/*
	 * see if we are running as the emu server user
	 * if so, set up SE_RESTORE_NAME privilege,
	 * which allows setting the owner field in a security descriptor.
	 * other interesting privileges are SE_TAKE_OWNERSHIP_NAME,
	 * which enables changing the ownership of a file to yourself
	 * regardless of the permissions on the file, SE_BACKUP_NAME,
	 * which enables reading any files regardless of permission,
	 * and SE_CHANGE_NOTIFY_NAME, which enables walking through
	 * directories without X permission.
	 * SE_RESTORE_NAME and SE_BACKUP_NAME together allow writing
	 * and reading any file data, regardless of permission,
	 * if the file is opened with FILE_BACKUP_SEMANTICS.
	 */
	isserver = 0;
	fsuser = secuser();
	if(fsuser == nil)
		fsuser = fsnone;
	else if(runescmp(fsuser->name, rootname) == 0
	     && OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES, &token)){
		priv = (TOKEN_PRIVILEGES*)privrock;
		priv->PrivilegeCount = 1;
		priv->Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
		if(LookupPrivilegeValue(NULL, SE_RESTORE_NAME, &priv->Privileges[0].Luid)
		&& AdjustTokenPrivileges(token, 0, priv, 0, NULL, NULL))
			isserver = 1;
		CloseHandle(token);
	}
}

/*
 * get the User for the executing process
 */
static User*
secuser(void)
{
	DWORD need;
	HANDLE token;
	TOKEN_USER *tu;
	char turock[sizeof(TOKEN_USER) + MAX_SID];

	if(!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token))
		return nil;

	tu = (TOKEN_USER*)turock;
	if(!GetTokenInformation(token, TokenUser, tu, sizeof(turock), &need)){
		CloseHandle(token);
		return nil;
	}
	CloseHandle(token);
	return sidtouser(nil, tu->User.Sid);
}

static int
secstat(Dir *dir, char *file, Rune *srv)
{
	int ok, n;
	Stat st;
	char sdrock[SD_ROCK];
	SECURITY_DESCRIPTOR *sd;

	sd = secsd(file, sdrock);
	if(sd == nil){
		int e = GetLastError();
		if(e == ERROR_ACCESS_DENIED || e == ERROR_SHARING_VIOLATION){
			dir->uid = strdup("unknown");
			dir->gid = strdup("unknown");
			if(dir->uid == nil || dir->gid == nil){
				free(dir->uid);
				error(Enomem);	/* will change to use kstrdup */
			}
			dir->mode = 0;
			return 1;
		}
		return 0;
	}
	ok = secsdstat(sd, &st, srv);
	if(sd != (void*)sdrock)
		free(sd);
	if(ok){
		dir->mode = st.mode;
		n = runenlen(st.owner->name, runeslen(st.owner->name));
		dir->uid = smalloc(n+1);
		runestoutf(dir->uid, st.owner->name, n+1);
		n = runenlen(st.group->name, runeslen(st.group->name));
		dir->gid = smalloc(n+1);
		runestoutf(dir->gid, st.group->name, n+1);
	}
	return ok;
}

static int
secsize(char *file, Rune *srv)
{
	int ok;
	Stat st;
	char sdrock[SD_ROCK];
	SECURITY_DESCRIPTOR *sd;

	sd = secsd(file, sdrock);
	if(sd == nil){
		int e = GetLastError();
		if(e == ERROR_ACCESS_DENIED || e == ERROR_SHARING_VIOLATION)
			return 7+7;
		return -1;
	}
	ok = secsdstat(sd, &st, srv);
	if(sd != (void*)sdrock)
		free(sd);
	if(ok)
		return runenlen(st.owner->name, runeslen(st.owner->name))+runenlen(st.group->name, runeslen(st.group->name));
	return -1;
}

/*
 * verify that u had access to file
 */
static void
seccheck(char *file, ulong access, Rune *srv)
{
	if(!sechasperm(file, access, srv))
		error(Eperm);
}

static int
sechasperm(char *file, ulong access, Rune *srv)
{
	int ok;
	char sdrock[SD_ROCK];
	SECURITY_DESCRIPTOR *sd;

	/*
	 * only really needs dacl info
	 */
	sd = secsd(file, sdrock);
	if(sd == nil)
		return 0;
	ok = secsdhasperm(sd, access, srv);
	if(sd != (void*)sdrock)
		free(sd);
	return ok;
}

static SECURITY_DESCRIPTOR*
secsd(char *file, char sdrock[SD_ROCK])
{
	DWORD need;
	SECURITY_DESCRIPTOR *sd;
	char *path, pathrock[6];
	wchar_t *wpath;

	path = file;
	if(path[0] != '\0' && path[1] == ':' && path[2] == '\0'){
		path = pathrock;
		strcpy(path, "?:\\.");
		path[0] = file[0];
	}
	sd = (SECURITY_DESCRIPTOR*)sdrock;
	need = 0;
	wpath = widen(path);
	if(GetFileSecurity(wpath, OWNER_SECURITY_INFORMATION|DACL_SECURITY_INFORMATION, sd, SD_ROCK, &need)) {
		free(wpath);
		return sd;
	}
	 if(GetLastError() != ERROR_INSUFFICIENT_BUFFER) {
		free(wpath);
		return nil;
	}
	sd = malloc(need);
	if(sd == nil) {
		free(wpath);
		error(Enomem);
	}
	if(GetFileSecurity(wpath, OWNER_SECURITY_INFORMATION|DACL_SECURITY_INFORMATION, sd, need, &need)) {
		free(wpath);
		return sd;
	}
	free(wpath);
	free(sd);
	return nil;
}

static int
secsdstat(SECURITY_DESCRIPTOR *sd, Stat *st, Rune *srv)
{
	ACL *acl;
	BOOL hasacl, b;
	ACE_HEADER *aceh;
	User *owner, *group;
	SID *sid, *osid, *gsid;
	ACCESS_ALLOWED_ACE *ace;
	int i, allow, deny, *p, m;
	ACL_SIZE_INFORMATION size;

	st->mode = 0;

	osid = nil;
	gsid = nil;
	if(!GetSecurityDescriptorOwner(sd, &osid, &b)
	|| !GetSecurityDescriptorDacl(sd, &hasacl, &acl, &b))
		return 0;

	if(acl == 0)
		size.AceCount = 0;
	else if(!GetAclInformation(acl, &size, sizeof(size), AclSizeInformation))
		return 0;

	/*
	 * first pass through acl finds group
	 */
	for(i = 0; i < size.AceCount; i++){
		if(!GetAce(acl, i, &aceh))
			continue;
		if(aceh->AceFlags & INHERIT_ONLY_ACE)
			continue;

		if(aceh->AceType != ACCESS_ALLOWED_ACE_TYPE
		&& aceh->AceType != ACCESS_DENIED_ACE_TYPE)
			continue;

		ace = (ACCESS_ALLOWED_ACE*)aceh;
		sid = (SID*)&ace->SidStart;
		if(EqualSid(sid, creatorowner) || EqualSid(sid, creatorgroup))
			continue;

		if(EqualSid(sid, everyone))
			;
		else if(EqualSid(sid, osid))
			;
		else if(EqualPrefixSid(sid, ntignore))
			continue;		/* boring nt accounts */
		else{
			gsid = sid;
			break;
		}
	}
	if(gsid == nil)
		gsid = osid;

	owner = sidtouser(srv, osid);
	group = sidtouser(srv, gsid);
	if(owner == 0 || group == 0)
		return 0;

	/* no acl means full access */
	allow = 0;
	if(acl == 0)
		allow = 0777;
	deny = 0;
	for(i = 0; i < size.AceCount; i++){
		if(!GetAce(acl, i, &aceh))
			continue;
		if(aceh->AceFlags & INHERIT_ONLY_ACE)
			continue;

		if(aceh->AceType == ACCESS_ALLOWED_ACE_TYPE)
			p = &allow;
		else if(aceh->AceType == ACCESS_DENIED_ACE_TYPE)
			p = &deny;
		else
			continue;

		ace = (ACCESS_ALLOWED_ACE*)aceh;
		sid = (SID*)&ace->SidStart;
		if(EqualSid(sid, creatorowner) || EqualSid(sid, creatorgroup))
			continue;

		m = 0;
		if(ace->Mask & FILE_EXECUTE)
			m |= 1;
		if(ace->Mask & FILE_WRITE_DATA)
			m |= 2;
		if(ace->Mask & FILE_READ_DATA)
			m |= 4;

		if(ismembersid(srv, owner, sid))
			*p |= (m << 6) & ~(allow|deny) & 0700;
		if(ismembersid(srv, group, sid))
			*p |= (m << 3) & ~(allow|deny) & 0070;
		if(EqualSid(everyone, sid))
			*p |= m & ~(allow|deny) & 0007;
	}

	st->mode = allow & ~deny;
	st->owner = owner;
	st->group = group;
	return 1;
}

static int
secsdhasperm(SECURITY_DESCRIPTOR *sd, ulong access, Rune *srv)
{
	User *u;
	ACL *acl;
	BOOL hasacl, b;
	ACE_HEADER *aceh;
	SID *sid, *osid, *gsid;
	int i, allow, deny, *p, m;
	ACCESS_ALLOWED_ACE *ace;
	ACL_SIZE_INFORMATION size;

	u = up->env->ui;
	allow = 0;
	deny = 0;
	osid = nil;
	gsid = nil;
	if(!GetSecurityDescriptorDacl(sd, &hasacl, &acl, &b))
		return 0;

	/* no acl means full access */
	if(acl == 0)
		return 1;
	if(!GetAclInformation(acl, &size, sizeof(size), AclSizeInformation))
		return 0;
	for(i = 0; i < size.AceCount; i++){
		if(!GetAce(acl, i, &aceh))
			continue;
		if(aceh->AceFlags & INHERIT_ONLY_ACE)
			continue;

		if(aceh->AceType == ACCESS_ALLOWED_ACE_TYPE)
			p = &allow;
		else if(aceh->AceType == ACCESS_DENIED_ACE_TYPE)
			p = &deny;
		else
			continue;

		ace = (ACCESS_ALLOWED_ACE*)aceh;
		sid = (SID*)&ace->SidStart;
		if(EqualSid(sid, creatorowner) || EqualSid(sid, creatorgroup))
			continue;

		m = ace->Mask;

		if(ismembersid(srv, u, sid))
			*p |= m & ~(allow|deny);
	}

	allow &= ~deny;

	return (allow & access) == access;
}

static SECURITY_DESCRIPTOR*
secmksd(char *sdrock, Stat *st, ACL *dacl, int isdir)
{
	int m;

	ulong mode;
	ACE_HEADER *aceh;
	SECURITY_DESCRIPTOR *sd;

	sd = (SECURITY_DESCRIPTOR*)sdrock;
	if(!InitializeAcl(dacl, ACL_ROCK, ACL_REVISION))
		return nil;

	mode = st->mode;
	if(st->owner == st->group){
		mode |= (mode >> 3) & 0070;
		mode |= (mode << 3) & 0700;
	}


	m = modetomask[(mode>>6) & 7];
	if(!AddAccessAllowedAce(dacl, ACL_REVISION, m, st->owner->sid))
		return nil;

	if(isdir && !AddAccessAllowedAce(dacl, ACL_REVISION, m, creatorowner))
		return nil;

	m = modetomask[(mode>>3) & 7];
	if(!AddAccessAllowedAce(dacl, ACL_REVISION, m, st->group->sid))
		return nil;

	m = modetomask[(mode>>0) & 7];
	if(!AddAccessAllowedAce(dacl, ACL_REVISION, m, everyone))
		return nil;

	if(isdir){
		/* hack to add inherit flags */
		if(!GetAce(dacl, 1, &aceh))
			return nil;
		aceh->AceFlags |= OBJECT_INHERIT_ACE|CONTAINER_INHERIT_ACE;
		if(!GetAce(dacl, 2, &aceh))
			return nil;
		aceh->AceFlags |= OBJECT_INHERIT_ACE|CONTAINER_INHERIT_ACE;
		if(!GetAce(dacl, 3, &aceh))
			return nil;
		aceh->AceFlags |= OBJECT_INHERIT_ACE|CONTAINER_INHERIT_ACE;
	}

	/*
	 * allow server user to access any file
	 */
	if(isserver){
		if(!AddAccessAllowedAce(dacl, ACL_REVISION, RMODE|WMODE|XMODE, fsuser->sid))
			return nil;
		if(isdir){
			if(!GetAce(dacl, 4, &aceh))
				return nil;
			aceh->AceFlags |= OBJECT_INHERIT_ACE|CONTAINER_INHERIT_ACE;
		}
	}

	if(!InitializeSecurityDescriptor(sd, SECURITY_DESCRIPTOR_REVISION))
		return nil;
	if(!SetSecurityDescriptorDacl(sd, 1, dacl, 0))
		return nil;
//	if(isserver && !SetSecurityDescriptorOwner(sd, st->owner->sid, 0))
//		return nil;
	return sd;
}

/*
 * the user manipulation routines
 * just make it easier to deal with user identities
 */
static User*
sidtouser(Rune *srv, SID *s)
{
	SID_NAME_USE type;
	Rune aname[100], dname[100];
	DWORD naname, ndname;
	User *u;

	qlock(&users.lk);
	for(u = users.u; u != 0; u = u->next)
		if(EqualSid(s, u->sid))
			break;
	qunlock(&users.lk);

	if(u != 0)
		return u;

	naname = sizeof(aname);
	ndname = sizeof(dname);

	if(!LookupAccountSidW(srv, s, aname, &naname, dname, &ndname, &type))
		return nil;
	return mkuser(s, type, aname, dname);
}

static User*
domnametouser(Rune *srv, Rune *name, Rune *dom)
{
	User *u;

	qlock(&users.lk);
	for(u = users.u; u != 0; u = u->next)
		if(runescmp(name, u->name) == 0 && runescmp(dom, u->dom) == 0)
			break;
	qunlock(&users.lk);
	if(u == 0)
		u = nametouser(srv, name);
	return u;
}

static User*
nametouser(Rune *srv, Rune *name)
{
	char sidrock[MAX_SID];
	SID *sid;
	SID_NAME_USE type;
	Rune dom[MAX_PATH];
	DWORD nsid, ndom;

	sid = (SID*)sidrock;
	nsid = sizeof(sidrock);
	ndom = sizeof(dom);
	if(!LookupAccountNameW(srv, name, sid, &nsid, dom, &ndom, &type))
		return nil;

	return mkuser(sid, type, name, dom);
}

/*
 * this mapping could be cached
 */
static User*
unametouser(Rune *srv, char *name)
{
	Rune rname[MAX_PATH];

	utftorunes(rname, name, MAX_PATH);
	return nametouser(srv, rname);
}

/*
 * make a user structure and add it to the global cache.
 */
static User*
mkuser(SID *sid, int type, Rune *name, Rune *dom)
{
	User *u;

	qlock(&users.lk);
	for(u = users.u; u != 0; u = u->next){
		if(EqualSid(sid, u->sid)){
			qunlock(&users.lk);
			return u;
		}
	}

	switch(type) {
	default:
		break;
	case SidTypeDeletedAccount:
		name = L"deleted";
		break;
	case SidTypeInvalid:
		name = L"invalid";
		break;
	case SidTypeUnknown:
		name = L"unknown";
		break;
	}

	u = malloc(sizeof(User));
	if(u == nil){
		qunlock(&users.lk);
		return 0;
	}
	u->next = nil;
	u->group = nil;
	u->sid = dupsid(sid);
	u->type = type;
	u->name = nil;
	if(name != nil)
		u->name = runesdup(name);
	u->dom = nil;
	if(dom != nil)
		u->dom = runesdup(dom);

	u->next = users.u;
	users.u = u;

	qunlock(&users.lk);
	return u;
}

/*
 * check if u is a member of gsid,
 * which might be a group.
 */
static int
ismembersid(Rune *srv, User *u, SID *gsid)
{
	User *g;

	if(EqualSid(u->sid, gsid))
		return 1;

	g = sidtouser(srv, gsid);
	if(g == 0)
		return 0;
	return ismember(u, g);
}

static int
ismember(User *u, User *g)
{
	Gmem *grps;

	if(EqualSid(u->sid, g->sid))
		return 1;

	if(EqualSid(g->sid, everyone))
		return 1;

	qlock(&u->lk);
	addgroups(u, 0);
	for(grps = u->group; grps != 0; grps = grps->next){
		if(EqualSid(grps->user->sid, g->sid)){
			qunlock(&u->lk);
			return 1;
		}
	}
	qunlock(&u->lk);
	return 0;
}

/*
 * find out what groups a user belongs to.
 * if force, throw out the old info and do it again.
 *
 * note that a global group is also know as a group,
 * and a local group is also know as an alias.
 * global groups can only contain users.
 * local groups can contain global groups or users.
 * this code finds all global groups to which a user belongs,
 * and all the local groups to which the user or a global group
 * containing the user belongs.
 */
static void
addgroups(User *u, int force)
{
	LOCALGROUP_USERS_INFO_0 *loc;
	GROUP_USERS_INFO_0 *grp;
	DWORD i, n, rem;
	User *gu;
	Gmem *g, *next;
	Rune *srv, srvrock[MAX_PATH];

	if(force){
		u->gotgroup = 0;
		for(g = u->group; g != nil; g = next){
			next = g->next;
			free(g);
		}
		u->group = nil;
	}
	if(u->gotgroup)
		return;
	u->gotgroup = 1;

	rem = 1;
	n = 0;
	srv = domsrv(u->dom, srvrock);
	while(rem != n){
		i = net.UserGetGroups(srv, u->name, 0,
			(BYTE**)&grp, 1024, &n, &rem);
		if(i != NERR_Success && i != ERROR_MORE_DATA)
			break;
		for(i = 0; i < n; i++){
			gu = domnametouser(srv, grp[i].grui0_name, u->dom);
			if(gu == 0)
				continue;
			g = malloc(sizeof(Gmem));
			if(g == nil)
				error(Enomem);
			g->user = gu;
			g->next = u->group;
			u->group = g;
		}
		net.ApiBufferFree(grp);
	}

	rem = 1;
	n = 0;
	while(rem != n){
		i = net.UserGetLocalGroups(srv, u->name, 0, LG_INCLUDE_INDIRECT,
			(BYTE**)&loc, 1024, &n, &rem);
		if(i != NERR_Success && i != ERROR_MORE_DATA)
			break;
		for(i = 0; i < n; i++){
			gu = domnametouser(srv, loc[i].lgrui0_name, u->dom);
			if(gu == NULL)
				continue;
			g = malloc(sizeof(Gmem));
			if(g == nil)
				error(Enomem);
			g->user = gu;
			g->next = u->group;
			u->group = g;
		}
		net.ApiBufferFree(loc);
	}
}

static SID*
dupsid(SID *sid)
{
	SID *nsid;
	int n;

	n = GetLengthSid(sid);
	nsid = malloc(n);
	if(nsid == nil || !CopySid(n, nsid, sid))
		panic("can't copy sid");
	return nsid;
}

/*
 * return the name of the server machine for file
 */
static Rune*
filesrv(char *file)
{
	int n;
	Rune *srv;
	char *p, uni[MAX_PATH], mfile[MAX_PATH];
	wchar_t vol[3];

	strcpy(mfile, file);
	/* assume file is a fully qualified name - X: or \\server */
	if(file[1] == ':') {
		vol[0] = file[0];
		vol[1] = file[1];
		vol[2] = 0;
		if(GetDriveType(vol) != DRIVE_REMOTE)
			return 0;
		n = sizeof(uni);
		if(WNetGetUniversalName(vol, UNIVERSAL_NAME_INFO_LEVEL, uni, &n) != NO_ERROR)
			return nil;
		runestoutf(mfile, ((UNIVERSAL_NAME_INFO*)uni)->lpUniversalName, MAX_PATH);
		file = mfile;
	}
	file += 2;
	p = strchr(file, '\\');
	if(p == 0)
		n = strlen(file);
	else
		n = p - file;
	if(n >= MAX_PATH)
		n = MAX_PATH-1;

	memmove(uni, file, n);
	uni[n] = '\0';

	srv = malloc((n + 1) * sizeof(Rune));
	if(srv == nil)
		panic("filesrv: no memory");
	utftorunes(srv, uni, n+1);
	return srv;
}

/*
 * does the file system support acls?
 */
static int
fsacls(char *file)
{
	char *p;
	DWORD flags;
	char path[MAX_PATH];
	wchar_t wpath[MAX_PATH];

	/* assume file is a fully qualified name - X: or \\server */
	if(file[1] == ':') {
		path[0] = file[0];
		path[1] = file[1];
		path[2] = '\\';
		path[3] = 0;
	} else {
		strcpy(path, file);
		p = strchr(path+2, '\\');
		if(p == 0)
			return 0;
		p = strchr(p+1, '\\');
		if(p == 0)
			strcat(path, "\\");
		else
			p[1] = 0;
	}
	utftorunes(wpath, path, MAX_PATH);
	if(!GetVolumeInformation(wpath, NULL, 0, NULL, NULL, &flags, NULL, 0))
		return 0;

	return flags & FS_PERSISTENT_ACLS;
}

/*
 * given a domain, find out the server to ask about its users.
 * we just ask the local machine to do the translation,
 * so it might fail sometimes.  in those cases, we don't
 * trust the domain anyway, and vice versa, so it's not
 * clear what benifit we would gain by getting the answer "right".
 */
static Rune*
domsrv(Rune *dom, Rune srv[MAX_PATH])
{
	Rune *psrv;
	int n, r;

	if(dom[0] == 0)
		return nil;

	r = net.GetAnyDCName(NULL, dom, (LPBYTE*)&psrv);
	if(r == NERR_Success) {
		n = runeslen(psrv);
		if(n >= MAX_PATH)
			n = MAX_PATH-1;
		memmove(srv, psrv, n*sizeof(Rune));
		srv[n] = 0;
		net.ApiBufferFree(psrv);
		return srv;
	}

	return nil;
}

Rune*
runesdup(Rune *r)
{
	int n;
	Rune *s;

	n = runeslen(r) + 1;
	s = malloc(n * sizeof(Rune));
	if(s == nil)
		error(Enomem);
	memmove(s, r, n * sizeof(Rune));
	return s;
}

int
runeslen(Rune *r)
{
	int n;

	n = 0;
	while(*r++ != 0)
		n++;
	return n;
}

char*
runestoutf(char *p, Rune *r, int nc)
{
	char *op, *ep;
	int n, c;

	op = p;
	ep = p + nc;
	while(c = *r++) {
		n = 1;
		if(c >= Runeself)
			n = runelen(c);
		if(p + n >= ep)
			break;
		if(c < Runeself)
			*p++ = c;
		else
			p += runetochar(p, r-1);
	}
	*p = '\0';
	return op;
}

Rune*
utftorunes(Rune *r, char *p, int nc)
{
	Rune *or, *er;

	or = r;
	er = r + nc;
	while(*p != '\0' && r + 1 < er)
		p += chartorune(r++, p);
	*r = '\0';
	return or;
}

int
runescmp(Rune *s1, Rune *s2)
{
	Rune r1, r2;

	for(;;) {
		r1 = *s1++;
		r2 = *s2++;
		if(r1 != r2) {
			if(r1 > r2)
				return 1;
			return -1;
		}
		if(r1 == 0)
			return 0;
	}
}

Dev fsdevtab = {
	'U',
	"fs",

	fsinit,
	fsattach,
	fswalk,
	fsstat,
	fsopen,
	fscreate,
	fsclose,
	fsread,
	devbread,
	fswrite,
	devbwrite,
	fsremove,
	fswstat
};
