#include	"mk.h"
#include	<signal.h>
#include	<sys/utime.h>

#define Arc	My_Arc		/* avoid name conflicts */
#undef DELETE

#include	<windows.h>

enum {
	Nchild	= 100,
};

char *rootdir =		"c:\\inferno";
char *shell =		"Nt\\386\\bin\\rcsh.exe";	/* Path relative to root */

typedef struct Child	Child;

struct Child {
	int	pid;
	HANDLE	handle;
};

static Child child[Nchild];

extern char **environ;

DWORD WINAPI writecmd(LPVOID a);

void
readenv(void)
{
	char **p, *s;
	Word *w;

	for(p = environ; *p; p++){
		s = shname(*p);
		if(*s == '=') {
			*s = 0;
			w = newword(s+1);
		} else
			w = newword("");
		if (symlook(*p, S_INTERNAL, 0))
			continue;
		s = strdup(*p);
		setvar(s, (void *)w);
		symlook(s, S_EXPORTED, (void *)"")->value = "";
	}
}

char *
exportenv(Envy *e)
{
	int i, n;
	char *buf, *v;

	buf = 0;
	n = 0;
	for(i = 0; e->name; e++, i++) {
			/* word separator is shell-dependent */
		if(e->values)
			v = wtos(e->values, IWS);
		else
			v = "";
		buf = Realloc(buf, n+strlen(e->name)+1+strlen(v)+1);
		
		n += sprint(buf+n, "%s=%s", e->name, v);
		n++;	/* skip over null */
		if(e->values)
			free(v);
	}
	/* final null */
	buf = Realloc(buf, n+1);
	buf[n] = 0;

	return buf;
}

int
waitfor(char *msg)
{
	int pid, n, i, r, code;
	HANDLE tab[Nchild];

	for(i=0,n=0; i<Nchild; i++)
		if(child[i].handle != 0)
			tab[n++] = child[i].handle;

	if(n == 0)
		return -1;

	r = WaitForMultipleObjects(n, tab, 0, INFINITE);

	r -= WAIT_OBJECT_0;
	if(r<0 || r>=n) {
		perror("wait failed");
		exits("wait failed");
	}

	for(i=0; i<Nchild; i++)
		if(child[i].handle == tab[r])
			break;
	if(i == Nchild){
		snprint(msg, ERRMAX, "unknown child (%lux)", tab[r]);
		return -1;
	}

	if(msg) {
		*msg = 0;
		if(GetExitCodeProcess(child[i].handle, &code) == FALSE)
			snprint(msg, ERRMAX, "unknown exit code");
		else if(code != 0)
			snprint(msg, ERRMAX, "exit(%d)", code);
	}

	CloseHandle(child[i].handle);
	child[i].handle = 0;
	pid = child[i].pid;
	child[i].pid = 0;

	return pid;
}

void
expunge(int pid, char *msg)
{
/*
	if(strcmp(msg, "interrupt"))
		kill(pid, SIGINT);
	else
		kill(pid, SIGHUP);
*/
}

HANDLE
duphandle(HANDLE h)
{
	HANDLE r;

	if(DuplicateHandle(GetCurrentProcess(), h,
			GetCurrentProcess(), &r, DUPLICATE_SAME_ACCESS,
			1, DUPLICATE_SAME_ACCESS) == FALSE) {
		perror("dup handle");
		Exit();
	}

	return r;
}

void
childadd(HANDLE h, int pid)
{
	int i;
	
	for(i=0; i<Nchild; i++) {
		if(child[i].handle == 0) {
			child[i].handle = h;
			child[i].pid = pid;
			return;
		}
	}
	perror("child table full");
	Exit();
}

static DWORD WINAPI
spinoff(HANDLE in, HANDLE out, char *args, char *cmd, Envy *e)
{
	char args2[4096], path[MAX_PATH], *s, *eb;
	STARTUPINFO si;
	PROCESS_INFORMATION pi;
	Symtab *sym;


		/* set up the full path of the shell */
	sym = symlook("MKSH", S_VAR, 0);
	if(sym){
		strncpy(path, ((Word*)(sym->value))->s, sizeof(path));
		path[MAX_PATH-1] = 0;
	}else{
		sym = symlook("ROOT", S_VAR, 0);
		if(sym)
			rootdir = ((Word*)(sym->value))->s;
		snprint(path, sizeof(path), "%s\\%s", rootdir, shell);
	}
		/* convert to backslash notation */
	for(s = strchr(path,'/'); s; s = strchr(s+1, '/'))
			*s = '\\';

	s = args2;
	s += snprint(args2, sizeof(args2)-1, "%s", path);
	if(shflags)
		s += snprint(s, args2+sizeof(args2)-s-1, " %s", shflags);
	if(args)
		s += snprint(s, args2+sizeof(args2)-s-1, " %s", args);
	if(cmd)
		s += snprint(s, args2+sizeof(args2)-s-1, " \"%s\"", cmd);

	memset(&si, 0, sizeof(si));
	si.cb = sizeof(si);
	si.dwFlags = STARTF_USESHOWWINDOW|STARTF_USESTDHANDLES;
	si.wShowWindow = SW_SHOW;

	if (e)
		eb = exportenv(e);
	else
		eb = 0;
	si.hStdInput = duphandle(in);
	si.hStdOutput = duphandle(out);
	si.hStdError = duphandle(GetStdHandle(STD_ERROR_HANDLE));
	if(CreateProcess(path, args2, 0, 0, 1, 0, eb, 0, &si, &pi) == FALSE) {
		perror("can't find shell");
		Exit();
	}

	free(eb);

	CloseHandle(si.hStdInput);
	CloseHandle(si.hStdOutput);
	CloseHandle(si.hStdError);

	childadd(pi.hProcess, pi.dwProcessId);
	return pi.dwProcessId;
}

int
execsh(char *args, char *cmd, Bufblock *buf, Envy *e)
{
	int tot, n, tid, pid;
	HANDLE outin, outout, inout, inin;
	struct { char *cmd; HANDLE handle; } *arg;

	if(buf == 0)
		outout = GetStdHandle(STD_OUTPUT_HANDLE);
	else
	if(CreatePipe(&outin, &outout, 0, 0) == FALSE){
		perror("pipe");
		Exit();
	}

	if(CreatePipe(&inin, &inout, 0, 0) == FALSE){
		perror("pipe");
		Exit();
	}

	arg = malloc(sizeof(*arg));
	arg->cmd = strdup(cmd);
	arg->handle = inout;
	if(CreateThread(0, 0, writecmd, arg, 0, &tid) == FALSE) {
		perror("spawn writecmd");
		Exit();
	}

	pid = spinoff(inin, outout, args, 0, e);
	CloseHandle(inin);

	if(DEBUG(D_EXEC))
		fprint(1, "starting: %s\n", cmd);

	if(buf){
		CloseHandle(outout);
		tot = 0;
		for(;;){
			if (buf->current >= buf->end)
				growbuf(buf);
			if(ReadFile(outin, buf->current, buf->end-buf->current, &n, 0) == FALSE)
				break;
			buf->current += n;
			tot += n;
		}
		if (tot && buf->current[-1] == '\n')
			buf->current--;
		CloseHandle(outin);
	}

	return pid;
}

static DWORD WINAPI
writecmd(LPVOID a)
{
	struct {char *cmd; HANDLE handle;} *arg;
	char *cmd, *p;
	int n;

	arg = a;
	cmd = arg->cmd;
	p = cmd+strlen(cmd);
	while(cmd < p){
		if(WriteFile(arg->handle, cmd, p-cmd, &n, 0) == FALSE)
			break;
		cmd += n;
	}	

	free(arg->cmd);
	CloseHandle(arg->handle);
	free(arg);
	ExitThread(0);
	return 0;
}

int
pipecmd(char *cmd, Envy *e, int *fd)
{
	int pid;
	HANDLE pipein, pipeout;

	if(fd){
		if(CreatePipe(&pipein, &pipeout, 0, 0) == FALSE){
			perror("pipe");
			Exit();
		}
	} else 
		pipeout = GetStdHandle(STD_OUTPUT_HANDLE);


	pid = spinoff(GetStdHandle(STD_INPUT_HANDLE), pipeout, "-c", cmd, e);

	if(fd){
		CloseHandle(pipeout);
		*fd = _open_osfhandle((long)pipein, 0);
	}
	return pid;
}

void
Exit(void)
{
	while(waitfor(0) != -1)
		;
	exits("error");
}

void
catchnotes()
{
}

char*
maketmp(void)
{
	static char temp[] = "mkargXXX.XXX";

	mktemp(temp);
	return temp;
}

Dir*
mkdirstat(char *name)
{
	int c, n, ret;
	Dir *buf;

	n = strlen(name)-1;
	c = name[n];
	if(c == '/' || c == '\\')
		name[n] = 0;
	buf = dirstat(name);
	name[n] = c;
	return buf;
}

int
chgtime(char *name)
{
	Dir *sbuf;
	struct utimbuf u;

	if((sbuf = mkdirstat(name)) != nil){
		u.actime = sbuf->atime;
		u.modtime = time(0);
		free(sbuf);
		return utime(name, &u);
	}
	return close(create(name, OWRITE, 0666));
}

void
rcopy(char **to, Resub *match, int n)
{
	int c;
	char *p;

	*to = match->s.sp;		/* stem0 matches complete target */
	for(to++, match++; --n > 0; to++, match++){
		if(match->s.sp && match->e.ep){
			p = match->e.ep;
			c = *p;
			*p = 0;
			*to = strdup(match->s.sp);
			*p = c;
		} else
			*to = 0;
	}
}

ulong
mkmtime(char *name)
{
	Dir *buf;
	ulong t;
	int n;
	char *s;

	n = strlen(name)-1;
	if(n >= 0 && (name[n] == '/' || name[n] == '\\')){
		s = strdup(name);
		s[n] = 0;
	}else
		s = name;
	buf = dirstat(s);
	if(buf == nil){
		if(s != name)
			free(s);
		return 0;
	}
	t = buf->mtime;
	free(buf);
	if(s != name)
		free(s);
	return t;
}

char *stab;

char *
membername(char *s, int fd, char *sz)
{
	long t;

	if(s[0] == '/' && s[1] == '\0'){	/* long file name string table */
		t = atol(sz);
		if(t&01) t++;
		stab = malloc(t);
		read(fd, stab, t);
		return nil;
	}
	else if(s[0] == '/' && stab != nil)		/* index into string table */
		return stab+atol(s+1);
	else
		return s;
}
