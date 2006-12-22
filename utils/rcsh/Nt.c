#include "rc.h"
#include <windows.h>

enum {
	Nchild	= 100,
};

typedef struct Child	Child;

struct Child {
	int	pid;
	HANDLE	handle;
};

static Child child[Nchild];

static void
winerror(void)
{
	int e, r;
	char buf[100], *p, *q;

	e = GetLastError();
	
	r = FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM,
		0, e, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
		buf, sizeof(buf), 0);

	if(r == 0)
		snprint(buf, sizeof(buf), "windows error %d", e);

	for(p=q=buf; *p; p++) {
		if(*p == '\r')
			continue;
		if(*p == '\n')
			*q++ = ' ';
		else
			*q++ = *p;
	}
	*q = 0;
	errstr(buf, sizeof buf);
}

static int
badentry(char *filename)
{
	if(*filename == 0)
		return 1;
	if(filename[0] == '.'){
		if(filename[1] == 0)
			return 1;
		if(filename[1] == '.' && filename[2] == 0)
			return 1;
	}
	return 0;
}

Direntry*
readdirect(char *path)
{
	long n;
	HANDLE h;
	Direntry *d;
	char fullpath[MAX_PATH];
	WIN32_FIND_DATA data;

	snprint(fullpath, MAX_PATH, "%s\\*.*", path);

	h = FindFirstFile(fullpath, &data);
	if(h == INVALID_HANDLE_VALUE)
		return 0;

	n = 0;
	d = 0;
	for(;;){
		if(!badentry(data.cFileName)){
			d = realloc(d, (n+2)*sizeof(Direntry));
			if(d == 0){
				werrstr("memory allocation");
				return 0;
			}
			d[n].name = malloc(strlen(data.cFileName)+1);
			if(d[n].name == 0){
				werrstr("memory allocation");
				return 0;
			}
			strcpy(d[n].name, data.cFileName);
			if(data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
				d[n].isdir = 1;
			else
				d[n].isdir = 0;
			n++;
		}
		if(FindNextFile(h, &data) == 0)
			break;
	}
	FindClose(h);
	if(d){
		d[n].name = 0;
		d[n].isdir = 0;
	}
	return d;
}

void
fatal(char *fmt, ...)
{
	char buf[512];
	va_list arg;

	va_start(arg, fmt);
	vseprint(buf, buf+sizeof(buf), fmt, arg);
	va_end(arg);

	fprint(2, "rc: %s\n", buf);
	_exits(buf);
}

static int
tas(int *p)
{	
	int v;
	
	_asm {
		mov	eax, p
		mov	ebx, 1
		xchg	ebx, [eax]
		mov	v, ebx
	}

	return v;
}

static void
lock(Lock *lk)
{
	int i;

	/* easy case */
	if(!tas(&lk->val))
		return;

	/* for muli processor machines */
	for(i=0; i<100; i++)
		if(!tas(&lk->val))
			return;

	SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_BELOW_NORMAL);
	for(;;) {
		for(i=0; i<10000; i++) {
			Sleep(0);
			if(!tas(&lk->val)) {
				SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_NORMAL);
				return;
			}
		}
	}
}

static void
unlock(Lock *lk)
{
	lk->val = 0;
}

int
refinc(Ref *r)
{
	int i;

	lock(&r->lk);
	i = r->ref;
	r->ref++;
	unlock(&r->lk);
	return i;
}

int	
refdec(Ref *r)
{
	int i;

	lock(&r->lk);
	r->ref--;
	i = r->ref;
	unlock(&r->lk);

	return i;
}

/*
 * windows quoting rules - I think
 * Words are seperated by space or tab
 * Words containing a space or tab can be quoted using "
 * 2N backslashes + " ==> N backslashes and end quote
 * 2N+1 backslashes + " ==> N backslashes + literal "
 * N backslashes not followed by " ==> N backslashes
 */
static char *
dblquote(char *cmd, char *s)
{
	int nb;
	char *p;

	for(p=s; *p; p++)
		if(*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' || *p == '"')
			break;

	if(*p == 0){				/* easy case */
		strcpy(cmd, s);
		return cmd+(p-s);
	}

	*cmd++ = '"';
	for(;;) {
		for(nb=0; *s=='\\'; nb++)
			*cmd++ = *s++;

		if(*s == 0) {			/* trailing backslashes -> 2N */
			while(nb-- > 0)
				*cmd++ = '\\';
			break;
		}

		if(*s == '"') {			/* literal quote -> 2N+1 backslashes */
			while(nb-- > 0)
				*cmd++ = '\\';
			*cmd++ = '\\';		/* escape the quote */
		}
		*cmd++ = *s++;
	}

	*cmd++ = '"';
	*cmd = 0;

	return cmd;
}

static char *
proccmd(char **argv)
{
	int i, n;
	char *cmd, *p;

		/* conservatively calculate length of command;
		 * backslash expansion can cause growth in dblquote().
		 */
	for(i=0,n=0; argv[i]; i++) {
		n += 2*strlen(argv[i]);
	}
	n++;
	
	cmd = malloc(n);
	for(i=0,p=cmd; argv[i]; i++) {
		p = dblquote(p, argv[i]);
		*p++ = ' ';
	}
	if(p != cmd)
		p--;
	*p = 0;

	return cmd;
}

static char *
exportenv(char **e)
{
	int i, j, n;
	char *buf;

	if(e == 0 || *e == 0)
		return 0;

	buf = 0;
	n = 0;
	for(i = 0; *e; e++, i++) {
		j = strlen(*e)+1;
		buf = realloc(buf, n+j);
		strcpy(buf+n, *e);
		n += j;
	}
	/* final null */
	buf = realloc(buf, n+1);
	buf[n] = 0;

	return buf;
}

static int
setpath(char *path, char *file)
{
	char *p, *last, tmp[MAX_PATH+1];
	int n;

	if(strlen(file) >= MAX_PATH){
		werrstr("file name too long");
		return -1;
	}
	strcpy(tmp, file);

	for(p=tmp; *p; p++) {
		if(*p == '/')
			*p = '\\';
	}

	if(tmp[0] != 0 && tmp[1] == ':') {
		if(tmp[2] == 0) {
			tmp[2] = '\\';
			tmp[3] = 0;
		} else if(tmp[2] != '\\') {
			/* don't allow c:foo - only c:\foo */
			werrstr("illegal file name");
			return -1;
		}
	}

	path[0] = 0;
	n = GetFullPathName(tmp, MAX_PATH, path, &last);
	if(n >= MAX_PATH) {
		werrstr("file name too long");
		return -1;
	}
	if(n == 0 && tmp[0] == '\\' && tmp[1] == '\\' && tmp[2] != 0) {
		strcpy(path, tmp);
		return -1;
	}

	if(n == 0) {
		werrstr("bad file name");
		return -1;
	}

	for(p=path; *p; p++) {
		if(*p < 32 || *p == '*' || *p == '?') {
			werrstr("file not found");
			return -1;
		}
	}

	/* get rid of trailling \ */
	if(path[n-1] == '\\') {
		if(n <= 2) {
			werrstr("illegal file name");
			return -1;
		}
		path[n-1] = 0;
		n--;
	}

	if(path[1] == ':' && path[2] == 0) {
		path[2] = '\\';
		path[3] = '.';
		path[4] = 0;
		return -1;
	}

	if(path[0] != '\\' || path[1] != '\\')
		return 0;

	for(p=path+2,n=0; *p; p++)
		if(*p == '\\')
			n++;
	if(n == 0)
		return -1;
	if(n == 1)
		return -1;
	return 0;
}


static int
execpath(char *path, char *file)
{
	int n;

	if(setpath(path, file) < 0)
		return 0;

	n = strlen(path)-4;
	if(path[n] == '.') {
		if(GetFileAttributes(path) != -1)
			return 1;
	}
	strncat(path, ".exe", MAX_PATH);
	path[MAX_PATH-1] = 0;
	if(GetFileAttributes(path) != -1)
		return 1;
	return 0;
}

static HANDLE
fdexport(int fd)
{
	HANDLE h, r;

	if(fd < 0)
		return INVALID_HANDLE_VALUE;

	h = (HANDLE)_get_osfhandle(fd);
	if(h < 0)
		return INVALID_HANDLE_VALUE;

	if(!DuplicateHandle(GetCurrentProcess(), h,
				GetCurrentProcess(), &r, DUPLICATE_SAME_ACCESS,
				1, DUPLICATE_SAME_ACCESS))
		return INVALID_HANDLE_VALUE;
	return r;
}

static int
addchild(int pid, HANDLE handle)
{
	int i;
	
	for(i=0; i<Nchild; i++) {
		if(child[i].handle == 0) {
			child[i].handle = handle;
			child[i].pid = pid;
			return 1;
		}
	}
	werrstr("child table full");
	return 0;
}

int
procwait(uint pid)
{
	HANDLE h;
	int i, exit;
	
	if(pid == 0)
		return 0;

	h = 0;
	for(i = 0; i < Nchild; i++){
		if(child[i].pid == pid){
			h = child[i].handle;
			child[i].pid = 0;
			child[i].handle = 0;
			break;
		}
	}

	if(h == 0){	/* we don't know about this one - let the system try to find it */
		h = OpenProcess(PROCESS_ALL_ACCESS, 0, pid);
		if(h == 0)
			return 0;		/* can't find it */
	}

	if(WaitForSingleObject(h, INFINITE) == WAIT_FAILED) {
		winerror();
		fatal("procwait: ");
	}

	if(!GetExitCodeProcess(h, &exit)) {
		winerror();
		exit = 1;
	}

	CloseHandle(h);
	return exit;
}

uint
proc(char **argv, int stdin, int stdout, int stderr)
{
	char *p, *arg0, *q, buf[MAX_PATH], path[MAX_PATH], *cmd, *eb;
	STARTUPINFO si;
	PROCESS_INFORMATION pi;
	int r, found, full;
	extern char **_environ;
	Word *w;

	arg0 = argv[0];
	if(arg0 == 0) {
		werrstr("null argv[0]");
		return 0;
	}

	full = arg0[0] == '\\' || arg0[0] == '/' || arg0[0] == '.';
	found = execpath(path, arg0);

	if(!found && !full) {
		w = vlook("path")->val;
		if(w)
			p = w->word;
		else
			p = getenv("path");
		for(; p && *p; p = q){
			q = strchr(p, ';');
			if(q)
				*q = 0;
			snprint(buf, sizeof(buf), "%s/%s", p, arg0);
			if(q)
				*q++ = ';';
			found = execpath(path, buf);
			if(found)
				break;
		}
	}

	if(!found) {
		werrstr("file not found");
		return 0;
	}

	memset(&si, 0, sizeof(si));
	si.cb = sizeof(si);
	si.dwFlags = STARTF_USESHOWWINDOW|STARTF_USESTDHANDLES;
	si.wShowWindow = SW_SHOW;
	si.hStdInput = fdexport(stdin);
	si.hStdOutput = fdexport(stdout);
	si.hStdError = fdexport(stderr);

	eb = exportenv(_environ);

	cmd = proccmd(argv);

	r = CreateProcess(path, cmd, 0, 0, 1, 0, eb, 0, &si, &pi);

	/* allow child to run */
	Sleep(0);

	free(cmd);
	free(eb);

	CloseHandle(si.hStdInput);
	CloseHandle(si.hStdOutput);
	CloseHandle(si.hStdError);

	if(!r) {
		winerror();
		return 0;
	}

	CloseHandle(pi.hThread);

	if(addchild(pi.dwProcessId, pi.hProcess) == 0)
		return 0;

	return pi.dwProcessId;
}

int
pipe(int *fd)
{
	return _pipe(fd, 0, _O_BINARY);
}
