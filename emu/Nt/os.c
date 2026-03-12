#define Unknown win_Unknown
#define UNICODE
#ifdef _AMD64_
/* Prevent windows.h from including winsock.h (conflicts with winsock2.h) */
#define WIN32_LEAN_AND_MEAN
#include	<windows.h>
#include	<winsock2.h>
#include	<ws2tcpip.h>
#else
#include	<windows.h>
#include <winbase.h>
#include	<winsock.h>
#endif
#undef Unknown
#include	<excpt.h>
#ifdef _AMD64_
#include	<float.h>	/* for _clearfp() */
#endif
#include	"dat.h"
#include	"fns.h"
#include	"error.h"

int	SYS_SLEEP = 2;
int SOCK_SELECT = 3;
#define	MAXSLEEPERS	1500

extern	int	cflag;

DWORD	PlatformId;
DWORD	consolestate;
static	char*	path;
static	HANDLE	kbdh = INVALID_HANDLE_VALUE;
static	HANDLE	conh = INVALID_HANDLE_VALUE;
static	HANDLE	errh = INVALID_HANDLE_VALUE;
static	int	donetermset = 0;
static	int sleepers = 0;

	wchar_t	*widen(char *s);
	char		*narrowen(wchar_t *ws);
	int		widebytes(wchar_t *ws);
	int		runeslen(Rune*);
	Rune*	runesdup(Rune*);
	Rune*	utftorunes(Rune*, char*, int);
	char*	runestoutf(char*, Rune*, int);
	int		runescmp(Rune*, Rune*);

__declspec(thread)       Proc    *up;

HANDLE	ntfd2h(int);
int	nth2fd(HANDLE);
void	termrestore(void);
char *hosttype = "Nt";
#ifdef _AMD64_
char *cputype = "amd64";
#else
char *cputype = "386";
#endif

static void
pfree(Proc *p)
{
	Osenv *e;

	lock(&procs.l);
	if(p->prev)
		p->prev->next = p->next;
	else
		procs.head = p->next;

	if(p->next)
		p->next->prev = p->prev;
	else
		procs.tail = p->prev;
	unlock(&procs.l);

	e = p->env;
	if(e != nil) {
		closefgrp(e->fgrp);
		closepgrp(e->pgrp);
		closeegrp(e->egrp);
		closesigs(e->sigs);
		free(e->user);
	}
	free(p->prog);
	CloseHandle((HANDLE)p->os);
	free(p);
}

void
osblock(void)
{
	if(WaitForSingleObject((HANDLE)up->os, INFINITE) != WAIT_OBJECT_0)
		panic("osblock failed");
}

void
osready(Proc *p)
{
	if(SetEvent((HANDLE)p->os) == FALSE)
		panic("osready failed");
}

void
pexit(char *msg, int t)
{
	pfree(up);
	ExitThread(0);
}

LONG TrapHandler(LPEXCEPTION_POINTERS ureg);

__cdecl
Exhandler(EXCEPTION_RECORD *rec, void *frame, CONTEXT *context, void *dcon)
{
	EXCEPTION_POINTERS ep;
	ep.ExceptionRecord = rec;
	ep.ContextRecord = context;
	TrapHandler(&ep);
	return ExceptionContinueExecution;
}

DWORD WINAPI
tramp(LPVOID p)
{
	up = p;
	up->func(up->arg);
	pexit("", 0);
	/* not reached */
	for(;;)
		panic("tramp");
	return 0;
}

void
kproc(char *name, void (*func)(void*), void *arg, int flags)
{
	DWORD h;
	Proc *p;
	Pgrp *pg;
	Fgrp *fg;
	Egrp *eg;

	p = newproc();
	if(p == nil)
		panic("out of kernel processes");
	p->os = CreateEvent(NULL, FALSE, FALSE, NULL);
	if(p->os == NULL)
		panic("can't allocate os event");
		
	if(flags & KPDUPPG) {
		pg = up->env->pgrp;
		incref(&pg->r);
		p->env->pgrp = pg;
	}
	if(flags & KPDUPFDG) {
		fg = up->env->fgrp;
		incref(&fg->r);
		p->env->fgrp = fg;
	}
	if(flags & KPDUPENVG) {
		eg = up->env->egrp;
		incref(&eg->r);
		p->env->egrp = eg;
	}

	p->env->ui = up->env->ui;
	kstrdup(&p->env->user, up->env->user);
	strcpy(p->text, name);

	p->func = func;
	p->arg = arg;

	lock(&procs.l);
	if(procs.tail != nil) {
		p->prev = procs.tail;
		procs.tail->next = p;
	}
	else {
		procs.head = p;
		p->prev = nil;
	}
	procs.tail = p;
	unlock(&procs.l);

	{
		HANDLE th;
		th = CreateThread(0, 16384, tramp, p, 0, &h);
		p->pid = (int)(intptr_t)th;
		if(th == NULL)
			panic("ran out of  kernel processes");
	}
}

#if(_WIN32_WINNT >= 0x0400)
void APIENTRY sleepintr(DWORD param)
{
}
#endif

void
oshostintr(Proc *p)
{
	if (p->syscall == SOCK_SELECT)
		return;
	p->intwait = 0;
#if(_WIN32_WINNT >= 0x0400)
	if(p->syscall == SYS_SLEEP) {
		QueueUserAPC(sleepintr, (HANDLE)(intptr_t) p->pid, (ULONG_PTR) p->pid);
	}
#endif
}

void
oslongjmp(void *regs, osjmpbuf env, int val)
{
	USED(regs);
	longjmp(env, val);
}

int
readkbd(void)
{
	DWORD r;
	char buf[1];

	if(ReadFile(kbdh, buf, sizeof(buf), &r, 0) == FALSE || r == 0)
		pexit("keyboard thread", 0);

	if (buf[0] == 0x03) {
		// INTR (CTRL+C)
		termrestore();
		ExitProcess(0);
	}
	if(buf[0] == '\r')
		buf[0] = '\n';
	return buf[0];
}

void
cleanexit(int x)
{
	sleep(2);
	termrestore();
	ExitProcess(x);
}

struct ecodes {
	DWORD	code;
	char*	name;
} ecodes[] = {
	EXCEPTION_ACCESS_VIOLATION,		"segmentation violation",
	EXCEPTION_DATATYPE_MISALIGNMENT,	"data alignment",
	EXCEPTION_BREAKPOINT,                	"breakpoint",
	EXCEPTION_SINGLE_STEP,               	"single step",
	EXCEPTION_ARRAY_BOUNDS_EXCEEDED,	"array bounds check",
	EXCEPTION_FLT_DENORMAL_OPERAND,		"denormalized float",
	EXCEPTION_FLT_DIVIDE_BY_ZERO,		"floating point divide by zero",
	EXCEPTION_FLT_INEXACT_RESULT,		"inexact floating point",
	EXCEPTION_FLT_INVALID_OPERATION,	"invalid floating operation",
	EXCEPTION_FLT_OVERFLOW,			"floating point result overflow",
	EXCEPTION_FLT_STACK_CHECK,		"floating point stack check",
	EXCEPTION_FLT_UNDERFLOW,		"floating point result underflow",
	EXCEPTION_INT_DIVIDE_BY_ZERO,		"divide by zero",
	EXCEPTION_INT_OVERFLOW,			"integer overflow",
	EXCEPTION_PRIV_INSTRUCTION,		"privileged instruction",
	EXCEPTION_IN_PAGE_ERROR,		"page-in error",
	EXCEPTION_ILLEGAL_INSTRUCTION,		"illegal instruction",
	EXCEPTION_NONCONTINUABLE_EXCEPTION,	"non-continuable exception",
	EXCEPTION_STACK_OVERFLOW,		"stack overflow",
	EXCEPTION_INVALID_DISPOSITION,		"invalid disposition",
	EXCEPTION_GUARD_PAGE,			"guard page violation",
	0,					nil
};

LONG
TrapHandler(LPEXCEPTION_POINTERS ureg)
{
	int i;
	char *name;
	DWORD code;
	// WORD pc;
	char buf[ERRMAX];

	code = ureg->ExceptionRecord->ExceptionCode;
	// pc = ureg->ContextRecord->Eip;

#ifdef _AMD64_
	if(code == EXCEPTION_ACCESS_VIOLATION) {
		const ULONG_PTR *info = ureg->ExceptionRecord->ExceptionInformation;
		const CONTEXT *ctx = ureg->ContextRecord;
		const char *vtype;
		if(info[0] == 0)
			vtype = "read";
		else if(info[0] == 1)
			vtype = "write";
		else
			vtype = "exec";
		print("ACCESS VIOLATION: %s addr=%p RIP=%p\n",
			vtype,
			(void*)info[1], (void*)ctx->Rip);
		print("  RAX=%p RBX=%p RCX=%p RDX=%p\n",
			(void*)ctx->Rax, (void*)ctx->Rbx, (void*)ctx->Rcx, (void*)ctx->Rdx);
		print("  R10=%p R12=%p R14=%p R15=%p\n",
			(void*)ctx->R10, (void*)ctx->R12, (void*)ctx->R14, (void*)ctx->R15);
		print("  RSP=%p RBP=%p RSI=%p RDI=%p\n",
			(void*)ctx->Rsp, (void*)ctx->Rbp, (void*)ctx->Rsi, (void*)ctx->Rdi);
		/* Dump top of x86 stack to trace call chain */
		{
			const ULONG_PTR *sp = (const ULONG_PTR*)ctx->Rsp;
			int j;
			print("  Stack:");
			for(j = 0; j < 12; j++)
				print(" [%d]=%p", j, (void*)sp[j]);
			print("\n");
		}
	}
#endif

	name = nil;
	for(i = 0; i < nelem(ecodes); i++) {
		if(ecodes[i].code == code) {
			name = ecodes[i].name;
			break;
		}
	}

	if(name == nil) {
		snprint(buf, sizeof(buf), "unknown trap type (%#.8lux)\n", code);
		name = buf;
	}
/*
	if(pc != 0) {
		snprint(buf, sizeof(buf), "%s: pc=0x%lux", name, pc);
		name = buf;
	}
*/
	switch (code) {
	case EXCEPTION_FLT_DENORMAL_OPERAND:
	case EXCEPTION_FLT_DIVIDE_BY_ZERO:
	case EXCEPTION_FLT_INEXACT_RESULT:
	case EXCEPTION_FLT_INVALID_OPERATION:
	case EXCEPTION_FLT_OVERFLOW:
	case EXCEPTION_FLT_STACK_CHECK:
	case EXCEPTION_FLT_UNDERFLOW:
		/* clear exception flags and ensure safe empty state */
#ifdef _AMD64_
		_clearfp();
#else
		_asm { fnclex };
		_asm { fninit };
#endif
	}
	disfault(nil, name);
	/* not reached */
	return EXCEPTION_CONTINUE_EXECUTION;
}

static void
termset(void)
{
	DWORD flag;

	if(donetermset)
		return;
	donetermset = 1;
	conh = GetStdHandle(STD_OUTPUT_HANDLE);
	kbdh = GetStdHandle(STD_INPUT_HANDLE);
	errh = GetStdHandle(STD_ERROR_HANDLE);
	if(errh == INVALID_HANDLE_VALUE)
		errh = conh;

	// The following will fail if kbdh not from console (e.g. a pipe)
	// in which case we don't care
	GetConsoleMode(kbdh, &consolestate);
	flag = consolestate;
	flag = flag & ~(ENABLE_PROCESSED_INPUT|ENABLE_LINE_INPUT|ENABLE_ECHO_INPUT);
	SetConsoleMode(kbdh, flag);
}

void
termrestore(void)
{
	if(kbdh != INVALID_HANDLE_VALUE)
		SetConsoleMode(kbdh, consolestate);
}

static	int	rebootok = 0;	/* is shutdown -r supported? */

void
osreboot(char *file, char **argv)
{
	if(rebootok){
		termrestore();
		execvp(file, argv);
		panic("reboot failure");
	}
}

#ifdef GUI_SDL3
/*
 * Worker thread wrapper for emuinit when using SDL3 GUI.
 * The main thread must remain free for sdl3_mainloop().
 */
static DWORD WINAPI
emuinit_worker(LPVOID arg)
{
	char *imod = (char*)arg;

	up = newproc();
	if(up == nil)
		panic("cannot create kernel process for emuinit worker");
	emuinit(imod);
	return 0;	/* never reached */
}
#endif

void
libinit(char *imod)
{
	WSADATA wasdat;
	DWORD lasterror, namelen;
	OSVERSIONINFO os;
	char sys[64], uname[64];
	wchar_t wuname[64];
	char *uns;

	os.dwOSVersionInfoSize = sizeof(os);
	if(!GetVersionEx(&os))
		panic("can't get os version");
	PlatformId = os.dwPlatformId;
	if (PlatformId == VER_PLATFORM_WIN32_NT) {	/* true for NT and 2000 */
		rebootok = 1;
	} else {
		rebootok = 0;
	}
	termset();

#ifndef _AMD64_
	if((int)INVALID_HANDLE_VALUE != -1 || sizeof(HANDLE) != sizeof(int))
		panic("invalid handle value or size");
#endif

	/* Winsock 2.2 on AMD64, 1.1 on 386 */
#ifdef _AMD64_
	if(WSAStartup(MAKEWORD(2, 2), &wasdat) != 0)
		panic("no ws2_32.dll");
#else
	if(WSAStartup(MAKEWORD(1, 1), &wasdat) != 0)
		panic("no winsock.dll");
#endif

	gethostname(sys, sizeof(sys));
	kstrdup(&ossysname, sys);
	if(sflag == 0)
		SetUnhandledExceptionFilter((LPTOP_LEVEL_EXCEPTION_FILTER)TrapHandler);

	path = getenv("PATH");
	if(path == nil)
		path = ".";

	up = newproc();
	if(up == nil)
		panic("cannot create kernel process");

	strcpy(uname, "inferno");
	namelen = sizeof(wuname);
	if(GetUserName(wuname, &namelen) != TRUE) {
		lasterror = GetLastError();	
		if(PlatformId == VER_PLATFORM_WIN32_NT || lasterror != ERROR_NOT_LOGGED_ON)
			print("cannot GetUserName: %d\n", lasterror);
	}else{
		uns = narrowen(wuname);
		snprint(uname, sizeof(uname), "%s", uns);
		free(uns);
	}
	kstrdup(&eve, uname);

#ifdef GUI_SDL3
	/* SDL3: Spawn emuinit on worker thread so main thread can run sdl3_mainloop() */
	{
		HANDLE th;
		DWORD tid;
		th = CreateThread(NULL, 16384, emuinit_worker, imod, 0, &tid);
		if(th == NULL)
			panic("cannot create emuinit worker thread");
		CloseHandle(th);
	}
	/* Return to main() which will call sdl3_mainloop() */
#else
	emuinit(imod);
#endif
}

/*
 * On AMD64, FPsave/FPrestore/umult are implemented in asm-amd64-win.asm
 * (assembled by ml64.exe). They use no-op stubs for FP (OS handles context)
 * and the MUL instruction for 128-bit multiply.
 *
 * On 386, they use MSVC inline assembly.
 */
#ifndef _AMD64_
void
FPsave(void *fptr)
{
	_asm {
		mov	eax, fptr
		fstenv	[eax]
	}
}

void
FPrestore(void *fptr)
{
	_asm {
		mov	eax, fptr
		fldenv	[eax]
	}
}

ulong
umult(ulong a, ulong b, ulong *high)
{
	ulong lo, hi;

	_asm {
		mov	eax, a
		mov	ecx, b
		MUL	ecx
		mov	lo, eax
		mov	hi, edx
	}
	*high = hi;
	return lo;
}
#endif /* !_AMD64_ */

int
close(int fd)
{
	if(fd == -1)
		return 0;
	CloseHandle(ntfd2h(fd));
	return 0;
}

int
read(int fd, void *buf, uint n)
{
	HANDLE h;

	if(fd == 0)
		h = kbdh;
	else
		h = ntfd2h(fd);
	if(h == INVALID_HANDLE_VALUE)
		return -1;
	if(!ReadFile(h, buf, n, &n, NULL))
		return -1;
	return n;
}

int
write(int fd, void *buf, uint n)
{
	HANDLE h;

	if(fd == 1 || fd == 2){
		if(!donetermset)
			termset();
		if(fd == 1)
			h = conh;
		else
			h = errh;
		if(h == INVALID_HANDLE_VALUE)
			return -1;
		if(!WriteFile(h, buf, n, &n, NULL))
			return -1;
		return n;
	}
	if(!WriteFile(ntfd2h(fd), buf, n, &n, NULL))
		return -1;
	return n;
}

/*
 * map handles and fds.
 *
 * On 32-bit Windows, sizeof(HANDLE) == sizeof(int) == 4.
 * On 64-bit Windows, sizeof(HANDLE) == 8 but sizeof(int) == 4.
 *
 * We use intptr_t for the intermediate cast to avoid truncation
 * warnings and data loss on AMD64.
 */
int
nth2fd(HANDLE h)
{
	return (int)(intptr_t)h;
}

HANDLE
ntfd2h(int fd)
{
	return (HANDLE)(intptr_t)fd;
}

void
oslopri(void)
{
	SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_BELOW_NORMAL);
}

/* Resolve system header name conflict */
#undef Sleep
void
sleep(int secs)
{
	Sleep(secs*1000);
}

void*
sbrk(int size)
{
	void *brk;

	brk = VirtualAlloc(NULL, size, MEM_COMMIT|MEM_RESERVE, PAGE_READWRITE);
	if(brk == 0)
		return (void*)-1;

	return brk;
}

/*
 * On AMD64, getcallerpc is in asm-amd64-win.asm.
 * On 386, it uses inline assembly.
 */
#ifndef _AMD64_
ulong
getcallerpc(void *arg)
{
	ulong cpc;
	_asm {
		mov eax, dword ptr [ebp]
		mov eax, dword ptr [eax+4]
		mov dword ptr cpc, eax
	}
	return cpc;
}
#endif /* !_AMD64_ */

/*
 * Return an abitrary millisecond clock time
 */
long
osmillisec(void)
{
	return GetTickCount();
}

#define SEC2MIN 60L
#define SEC2HOUR (60L*SEC2MIN)
#define SEC2DAY (24L*SEC2HOUR)

/*
 *  days per month plus days/year
 */
static	int	dmsize[] =
{
	365, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
};
static	int	ldmsize[] =
{
	366, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
};

/*
 *  return the days/month for the given year
 */
static int*
yrsize(int yr)
{
	/* a leap year is a multiple of 4, excluding centuries
	 * that are not multiples of 400 */
	if( (yr % 4 == 0) && (yr % 100 != 0 || yr % 400 == 0) )
		return ldmsize;
	else
		return dmsize;
}

static long
tm2sec(SYSTEMTIME *tm)
{
	long secs;
	int i, *d2m;

	secs = 0;

	/*
	 *  seconds per year
	 */
	for(i = 1970; i < tm->wYear; i++){
		d2m = yrsize(i);
		secs += d2m[0] * SEC2DAY;
	}

	/*
	 *  seconds per month
	 */
	d2m = yrsize(tm->wYear);
	for(i = 1; i < tm->wMonth; i++)
		secs += d2m[i] * SEC2DAY;

	/*
	 * secs in last month
	 */
	secs += (tm->wDay-1) * SEC2DAY;

	/*
	 * hours, minutes, seconds
	 */
	secs += tm->wHour * SEC2HOUR;
	secs += tm->wMinute * SEC2MIN;
	secs += tm->wSecond;

	return secs;
}

/*
 * Return the time since the epoch in microseconds
 * The epoch is defined at 1 Jan 1970
 */
vlong
osusectime(void)
{
	SYSTEMTIME tm;
	vlong secs;

	GetSystemTime(&tm);
	secs = tm2sec(&tm);
	return secs * 1000000 + tm.wMilliseconds * 1000;
}

vlong
osnsec(void)
{
	return osusectime()*1000;	/* TO DO better */
}

int
osmillisleep(ulong milsec)
{
	SleepEx(milsec, FALSE);
	return 0;
}

int
limbosleep(ulong milsec)
{
	if (sleepers > MAXSLEEPERS)
		return -1;
	sleepers++;
	up->syscall = SYS_SLEEP;
	SleepEx(milsec, TRUE);
	up->syscall = 0;
	sleepers--;
	return 0;
}

void
osyield(void)
{	
	SwitchToThread();
}

void
ospause(void)
{
      for(;;)
              sleep(1000000);
}

/*
 * these should never be called, and are included
 * as stubs since we are linking against a library which defines them
 */
int
open(const char *path, int how, ...)
{
	panic("open");
	return -1;
}

int
creat(const char *path, int how)
{
	panic("creat");
	return -1;
}

int
stat(const char *path, struct stat *sp)
{
	panic("stat");
	return -1;
}

int
chown(const char *path, int uid, int gid)
{
	panic("chown");
	return -1;
}

int
chmod(const char *path, int mode)
{
	panic("chmod");
	return -1;
}

void
link(char *path, char *next)
{
	panic("link");
}

int
segflush(void *a, ulong n)
{
	DWORD old;

	/* Make JIT code executable (W^X: was PAGE_READWRITE during generation) */
	VirtualProtect(a, n, PAGE_EXECUTE_READ, &old);
	FlushInstructionCache(GetCurrentProcess(), a, n);
	return 0;
}

wchar_t *
widen(char *s)
{
	int n;
	wchar_t *ws;

	n = utflen(s) + 1;
	ws = smalloc(n*sizeof(wchar_t));
	utftorunes(ws, s, n);
	return ws;
}


char *
narrowen(wchar_t *ws)
{
	char *s;
	int n;

	n = widebytes(ws);
	s = smalloc(n);
	runestoutf(s, ws, n);
	return s;
}


int
widebytes(wchar_t *ws)
{
	int n = 0;

	while (*ws)
		n += runelen(*ws++);
	return n+1;
}
