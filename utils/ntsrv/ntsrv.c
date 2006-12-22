#ifndef ForNT4
/* only for XP, 2000 and above - JobObject only available on these*/
#undef _WIN32_WINNT
#define _WIN32_WINNT 0x0500
#endif

#include "lib9.h"
#include <windows.h>
#include <winsvc.h>
#include <stdarg.h>

#ifdef JOB_OBJECT_TERMINATE
#define	Jobs
#endif

#ifdef ForNT4
#undef Jobs
#endif

/*
 * ntsrv add Name Inferno-root Cmds
 * ntsrv del Name
 * ntsrv run Name Inferno-root Cmds
 *
 * 'add' registers service: Name with args "run Name Inferno-root Cmds"
 * 'del' unregisters service Name
 * 'run' - only given by NT service manager when starting the service (see 'add')
 *
 * Cmds are cat'd (with space separator) and requoted for CreateProcess()
 *
 * There must be an ntsrv.exe in Inferno-root/Nt/386/bin
 */


SERVICE_STATUS	status = {
	SERVICE_WIN32_OWN_PROCESS,	/* dwServiceType */
	0,							/* dwCurrentState */
	SERVICE_ACCEPT_STOP			/* dwControlsAccepted */
};

typedef struct Emu Emu;
struct Emu {
	HANDLE	proc;		/* NULL if error */
	HANDLE	job;			/* job for all children */
	HANDLE	stdin;		/* stdio pipes */
	HANDLE	stdout;
	DWORD	notepg;		/* process group ID (in case we lack Jobs) */
};

typedef struct Copyargs Copyargs;
struct Copyargs {
	HANDLE in;
	HANDLE out;
};

#ifdef Jobs
static char *myname = "ntsrv.exe";
#else
static char *myname = "ntsrv4.exe";
#endif
#define LOGFILE "grid\\slave\\svclog"
static char *name;
static char *root;
static char *cmds;
static SERVICE_STATUS_HANDLE	statush;
static HANDLE	emujob;		/* win32 job object for emu session */
static DWORD	emugroup;		/* process group ID for emu session */
static HANDLE emuin;		/* stdin pipe of emu */
static HANDLE logf;

HANDLE openlog(char*);
void logmsg(char*, ...);
void WINAPI infmain(ulong, LPTSTR[]);
void WINAPI infctl(ulong);
Emu runemu(char*);
HANDLE exporthandle(HANDLE, int);
DWORD WINAPI copy(LPVOID);
int shuttingdown = 0;
int nice = 0;

static void
usage()
{
	fprint(2, "usage: ntsrv [-n] add name root cmds | del name\n");
}

/* (from rcsh)
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

int
installnewemu()
{
	LPCTSTR currpath, newpath;
	currpath = smprint("%s\\Nt\\386\\bin\\emu.exe", root);
	newpath = smprint("%s\\Nt\\386\\bin\\newemu.exe", root);
	if(GetFileAttributes(newpath) == 0xffffffff)	// INVALID_FILE_ATTRIBUTES is not defined
		return 0;
	DeleteFile(currpath);			// ignore error message - it might not be there.
	if(MoveFile(newpath, currpath) == 0){
		logmsg("cannot rename %s to %s: %r", newpath, currpath);
		return -1;
	}
	return 0;
}	

void WINAPI
infmain(ulong argc, char *argv[])
{
	HANDLE cpt;
	Emu emu;
	Copyargs cp;
	DWORD tid;
	char *cmd;

	argc--;
	argv++;
	cmd = smprint("%s\\%s", root, LOGFILE);
	logf = openlog(cmd);
	free(cmd);
	statush = RegisterServiceCtrlHandler(name, infctl);
	if (statush == 0)
		return;

	status.dwCurrentState = SERVICE_START_PENDING;
	SetServiceStatus(statush, &status);

	while(installnewemu() != -1){
		/* start the service */
		cmd = smprint("%s\\Nt\\386\\bin\\emu.exe -r%s %s", root, root, cmds);
		logmsg("starting %s", cmd);
		emu = runemu(cmd);
		free(cmd);
		if (emu.proc == NULL) {
			logmsg("runemu failed: %r");
			status.dwCurrentState = SERVICE_STOPPED;
			SetServiceStatus(statush, &status);
			return;
		}
	
		cp.in = emu.stdout;
		cp.out = logf;
		cpt = CreateThread(NULL, 0, copy, (void*)&cp, 0, &tid);
		if (cpt == NULL) {
			logmsg("failed to create copy thread: %r");
			CloseHandle(emu.stdout);
		}
	
		logmsg("infmain blocking on emu proc");
		emujob = emu.job;
		emugroup = emu.notepg;
		status.dwCurrentState = SERVICE_RUNNING;
		SetServiceStatus(statush, &status);
		WaitForSingleObject(emu.proc, INFINITE);
		logmsg("infmain emu proc terminated");
		emujob = NULL;
		emugroup = 0;
#ifdef Jobs
		logmsg("terminating job");
		TerminateJobObject(emu.job, 0);
#else
		logmsg("notepg (%d)", emu.notepg);
		if(emu.notepg)
			GenerateConsoleCtrlEvent(CTRL_C_EVENT, emu.notepg);
#endif
		if (cpt) {
			/* copy() sees eof on emu.stdout and exits */
			WaitForSingleObject(cpt, INFINITE);
			CloseHandle(cpt);
			CloseHandle(emu.stdout);
		}
		CloseHandle(emu.proc);
		if(emu.job != NULL)
			CloseHandle(emu.job);
		CloseHandle(emu.stdin);
		// XXX should check to see that we're not starting up again too quickly, as
		// it's quite possible to get into an infinite loop here.
		// but what are good criteria? 5 times? 100 times?
		// 10 times within a minute?
		// for the moment, just sleep for a while before restarting...
		if(shuttingdown)
			break;
		SleepEx(10000, FALSE);
	}
	logmsg("infmain done");
	if (logf)
		CloseHandle(logf);
	status.dwCurrentState = SERVICE_STOPPED;
	SetServiceStatus(statush, &status);
	return;
}

void WINAPI
infctl(ulong op)
{
	if (op != SERVICE_CONTROL_STOP)
		return;

	/* stop the service (status set by infmain()
	 *
	 * NOTE: there is a race for emujob - may have been closed
	 * after test, but before TerminateJobObject()
	 * MSDN is unclear as to whether TerminatJobObject() handles
	 * NULL job ptr - should probably use a mutex
	 */
	shuttingdown = 1;
#ifdef Jobs
	logmsg("svc stop: stopping job");
	if (emujob)
		TerminateJobObject(emujob, 0);
#else
	logmsg("svc stop: interrupting emu");
	if (emugroup)
		GenerateConsoleCtrlEvent(CTRL_C_EVENT, emugroup);
#endif
}

void
printerror(char *s)
{
	char *msg;
	FormatMessage(FORMAT_MESSAGE_ALLOCATE_BUFFER|
		FORMAT_MESSAGE_FROM_SYSTEM|
		FORMAT_MESSAGE_IGNORE_INSERTS,
		NULL,
		GetLastError(),
		MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
		(LPTSTR)&msg,
		0,
		NULL);
	fprint(2, "%s: %s\n", s, msg);
	LocalFree(msg);
}

int
add(char *name, char *root, char *cmds)
{
	char *path;
	int r;
	SC_HANDLE scm, scs;
	char *nopt;

	nopt = nice ? " -n" : "";
	path = smprint("%s\\Nt\\386\\bin\\%s%s run %s %s %s", root, myname, nopt, name, root, cmds);
	r = 0;
	scm = OpenSCManager(NULL, NULL, SC_MANAGER_ALL_ACCESS);
	if (scm == NULL) {
		printerror("cannot open service control manager");
		return -1;
	}
	scs = CreateService(scm,
		name,
		name,
		SERVICE_START|SERVICE_STOP,
		SERVICE_WIN32_OWN_PROCESS,
		SERVICE_AUTO_START,
		SERVICE_ERROR_IGNORE,
		path,
		NULL,
		NULL,
		NULL,
		NULL,
		NULL
	);
	if (scs == NULL) {
		printerror("cannot create service");
		r = -1;
	} else {
		CloseServiceHandle(scs);
	}
	CloseServiceHandle(scm);
	return r;
}

int
del(char *name)
{
	SC_HANDLE scm, scs;

	scm = OpenSCManager(NULL, NULL, SC_MANAGER_ALL_ACCESS);
	if (scm == NULL) {
		printerror("cannot open service control manager");
		return -1;
	}

	scs = OpenService(scm, name, DELETE);
	if (scs == NULL) {
		printerror("cannot open service");
		CloseServiceHandle(scm);
		return -1;
	}
	if (!DeleteService(scs)) {
		printerror("cannot delete Iservice");
		CloseServiceHandle(scs);
		CloseServiceHandle(scm);
		return -1;
	}
	CloseServiceHandle(scs);
	CloseServiceHandle(scm);
	return 0;
}

HANDLE
openlog(char *p)
{
	HANDLE h;
	h = CreateFile(p, GENERIC_WRITE, FILE_SHARE_READ, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
	if (h == INVALID_HANDLE_VALUE)
		return NULL;
	SetFilePointer(h, 0, NULL, FILE_END);
	return h;
}

void
logmsg(char *fmt, ...)
{
	int n;
	char *p;
	va_list args;
	if(logf == 0)
		return;
	va_start(args, fmt);
	p = vsmprint(fmt, args);
	va_end(args);
	n = strlen(p);
	if (n)
		WriteFile(logf, p, n, &n, NULL);
	WriteFile(logf, "\n", 1, &n, NULL);
}

Emu
runemu(char *cmd)
{
	Emu r = {NULL, NULL, NULL};
	STARTUPINFO si;
	PROCESS_INFORMATION pinfo;
	HANDLE job, emu, emut, stdin, stdout, stderr, emui, emuo;
	SECURITY_ATTRIBUTES sec;
	DWORD flags;

	job = emu = emut = stdin = stdout = stderr = emui = emuo = NULL;
#ifdef Jobs
	job = CreateJobObject(NULL, NULL);
	if (job == NULL) {
		logmsg("cannot create job object: %r");
		goto error;
	}
#endif

	/* set up pipes */
	sec.nLength = sizeof(sec);
	sec.lpSecurityDescriptor = 0;
	sec.bInheritHandle = 0;
	if (!CreatePipe(&stdin, &emui, &sec, 0)) {
		logmsg("cannot create stdin pipe: %r");
		goto error;
	}
	if (!CreatePipe(&emuo, &stdout, &sec, 0)) {
		logmsg("cannot create stdout pipe: %r");
		goto error;
	}
	stdin = exporthandle(stdin, 1);
	stdout = exporthandle(stdout, 1);
	stderr = exporthandle(stdout, 0);

	/* create emu process (suspended) */
	memset(&si, 0, sizeof(si));
	si.cb = sizeof(si);
	si.dwFlags = STARTF_USESTDHANDLES;
	si.hStdInput = stdin;
	si.hStdOutput = stdout;
	si.hStdError = stderr;

	flags = CREATE_NEW_PROCESS_GROUP|CREATE_DEFAULT_ERROR_MODE|CREATE_SUSPENDED;
	if(nice)
		flags |= IDLE_PRIORITY_CLASS;
	if(!CreateProcess(0, cmd, 0, 0, 1, flags, 0, 0, &si, &pinfo)) {
		logmsg("cannot create process: %r");
		goto error;
	}
	emu = pinfo.hProcess;
	emut = pinfo.hThread;
	CloseHandle(stdin);
	stdin = NULL;
	CloseHandle(stdout);
	stdout = NULL;
	CloseHandle(stderr);
	stderr = NULL;

#ifdef Jobs
	if(!AssignProcessToJobObject(job, emu)) {
		logmsg("failed to assign emu to job: %r");
		goto error;
	}
#endif
	ResumeThread(emut);
	CloseHandle(emut);

	r.proc = emu;
	r.notepg = pinfo.dwProcessId;
	r.job = job;	/* will be NULL if not implemented (NT4) */
	r.stdin = emui;
	r.stdout = emuo;
	return r;

error:
	if (stdin)
		CloseHandle(stdin);
	if (stdout)
		CloseHandle(stdout);
	if (stderr)
		CloseHandle(stderr);
	if (emui)
		CloseHandle(emuin);
	if (emuo)
		CloseHandle(emuo);
	if (emut)
		CloseHandle(emut);
	if (emu) {
		TerminateProcess(emu, 0);
		CloseHandle(emu);
	}
	if (job)
		CloseHandle(job);
	return r;
}

HANDLE
exporthandle(HANDLE h, int close)
{
	HANDLE cp, dh;
	DWORD flags = DUPLICATE_SAME_ACCESS;
	if (close)
		flags |= DUPLICATE_CLOSE_SOURCE;
	cp = GetCurrentProcess();
	if (!DuplicateHandle(cp, h, cp, &dh, DUPLICATE_SAME_ACCESS, 1, flags))
		return nil;
	return dh;
}

DWORD WINAPI
copy(void *arg)
{
	Copyargs *cp = (Copyargs*)arg;
	char buf[1024];
	DWORD n;

	while (ReadFile(cp->in, buf, sizeof(buf), &n, NULL)) {
		if (n && cp->out)
			WriteFile(cp->out, buf, n, &n, NULL);
	}
	return 0;
}

void
main(int argc, char *argv[])
{
	char *verb;
	SERVICE_TABLE_ENTRY services[2];

	memset(services, 0, sizeof(services));

	ARGBEGIN{
	case 'n':
		nice = 1;
		break;
	default:
		usage();
	}ARGEND

	if (argc < 2) {
		usage();
		return;
	}

	verb = argv[0];
	name = argv[1];
	if (argc > 2)
		root = argv[2];
	if (argc > 3)
		cmds = proccmd(argv+3);

	if (strcmp(verb, "del") == 0)
		exit(del(name));
	if (strcmp(verb, "add") == 0) {
		if (root == NULL || cmds == NULL) {
			usage();
			return;
		}
		exit(add(name, root, cmds));
	}
	if (strcmp(verb, "run") == 0) {
		if (root == NULL || cmds == NULL || *cmds == '\0') {
			usage();
			return;
		}
		services[0].lpServiceName = name;
		services[0].lpServiceProc = infmain;
		StartServiceCtrlDispatcher(services);
		exit(0);
	}
	usage();
}
