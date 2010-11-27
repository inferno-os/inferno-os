#include	<sys/types.h>
#include	<time.h>
#include	<termios.h>
#include	<signal.h>
#include 	<pwd.h>
#include	<sched.h>
#include	<sys/resource.h>
#include	<sys/wait.h>
#include	<sys/time.h>

#include	<stdint.h>

#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include <fpuctl.h>

#include	<raise.h>

/* glibc 2.3.3-NTPL messes up getpid() by trying to cache the result, so we'll do it ourselves */
#include	<sys/syscall.h>
#define	getpid()	syscall(SYS_getpid)

/* temporarily suppress CLONE_PTRACE so it works on broken Linux kernels */
#undef CLONE_PTRACE
#define	CLONE_PTRACE	0

enum
{
	DELETE	= 0x7f,
	CTRLC	= 'C'-'@',
	NSTACKSPERALLOC = 16,
	X11STACK=	256*1024
};
char *hosttype = "Linux";

extern void unlockandexit(int*);
extern void executeonnewstack(void*, void (*f)(void*), void*);

static void *stackalloc(Proc *p, void **tos);
static void stackfreeandexit(void *stack);

extern int dflag;

int	gidnobody = -1;
int	uidnobody = -1;
static struct 	termios tinit;

void
pexit(char *msg, int t)
{
	Osenv *e;
	void *kstack;

	lock(&procs.l);
	if(up->prev)
		up->prev->next = up->next;
	else
		procs.head = up->next;

	if(up->next)
		up->next->prev = up->prev;
	else
		procs.tail = up->prev;
	unlock(&procs.l);

	if(0)
		print("pexit: %s: %s\n", up->text, msg);

	e = up->env;
	if(e != nil) {
		closefgrp(e->fgrp);
		closepgrp(e->pgrp);
		closeegrp(e->egrp);
		closesigs(e->sigs);
	}
	kstack = up->kstack;
	free(up->prog);
	free(up);
	if(kstack != nil)
		stackfreeandexit(kstack);
}

void
tramp(void *arg)
{
	Proc *p;
	p = arg;
	p->pid = p->sigid = getpid();
	(*p->func)(p->arg);
	pexit("{Tramp}", 0);
}

int
kproc(char *name, void (*func)(void*), void *arg, int flags)
{
	Proc *p;
	Pgrp *pg;
	Fgrp *fg;
	Egrp *eg;
	void *tos;

	p = newproc();
	if(0)
		print("start %s:%#p\n", name, p);
	if(p == nil)
		panic("kproc(%s): no memory", name);

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

	p->env->uid = up->env->uid;
	p->env->gid = up->env->gid;
	kstrdup(&p->env->user, up->env->user);

	strcpy(p->text, name);

	p->func = func;
	p->arg = arg;

	if(flags & KPX11){
		p->kstack = nil;	/* never freed; also up not defined */
		tos = (char*)mallocz(X11STACK, 0) + X11STACK - sizeof(vlong);
	}else
		p->kstack = stackalloc(p, &tos);

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

	if (__clone(tramp, tos, CLONE_PTRACE|CLONE_VM|CLONE_FS|CLONE_FILES|SIGCHLD, p) <= 0)
		panic("kproc: clone failed");

	return 0;
}

static void
sysfault(char *what, void *addr)
{
	char buf[64];

	snprint(buf, sizeof(buf), "sys: %s%#p", what, addr);
	disfault(nil, buf);
}

static void
trapILL(int signo, siginfo_t *si, void *a)
{
	USED(signo);
	USED(a);
	sysfault("illegal instruction pc=", si->si_addr);
}

static int
isnilref(siginfo_t *si)
{
	return si != 0 && (si->si_addr == (void*)~(uintptr_t)0 || (uintptr_t)si->si_addr < 512);
}

static void
trapmemref(int signo, siginfo_t *si, void *a)
{
	USED(a);	/* ucontext_t*, could fetch pc in machine-dependent way */
	if(isnilref(si))
		disfault(nil, exNilref);
	else if(signo == SIGBUS)
		sysfault("bad address addr=", si->si_addr);	/* eg, misaligned */
	else
		sysfault("segmentation violation addr=", si->si_addr);
}

static void
trapFPE(int signo, siginfo_t *si, void *a)
{
	char buf[64];

	USED(signo);
	USED(a);
	snprint(buf, sizeof(buf), "sys: fp: exception status=%.4lux pc=%#p", getfsr(), si->si_addr);
	disfault(nil, buf);
}

static void
trapUSR1(int signo)
{
	int intwait;

	USED(signo);

	intwait = up->intwait;
	up->intwait = 0;	/* clear it to let proc continue in osleave */

	if(up->type != Interp)		/* Used to unblock pending I/O */
		return;

	if(intwait == 0)		/* Not posted so it's a sync error */
		disfault(nil, Eintr);	/* Should never happen */
}

/* called to wake up kproc blocked on a syscall */
void
oshostintr(Proc *p)
{
	kill(p->sigid, SIGUSR1);
}

static void
trapUSR2(int signo)
{
	USED(signo);
	/* we've done our work of interrupting sigsuspend */
}

void
osblock(void)
{
	sigset_t mask;

	sigprocmask(SIG_SETMASK, NULL, &mask);
	sigdelset(&mask, SIGUSR2);
	sigsuspend(&mask);
}

void
osready(Proc *p)
{
	if(kill(p->sigid, SIGUSR2) < 0)
		fprint(2, "emu: osready failed: pid %d: %s\n", p->sigid, strerror(errno));
}

void
oslongjmp(void *regs, osjmpbuf env, int val)
{
	USED(regs);
	siglongjmp(env, val);
}

static void
termset(void)
{
	struct termios t;

	tcgetattr(0, &t);
	tinit = t;
	t.c_lflag &= ~(ICANON|ECHO|ISIG);
	t.c_cc[VMIN] = 1;
	t.c_cc[VTIME] = 0;
	tcsetattr(0, TCSANOW, &t);
}

static void
termrestore(void)
{
	tcsetattr(0, TCSANOW, &tinit);
}

void
cleanexit(int x)
{
	USED(x);

	if(up->intwait) {
		up->intwait = 0;
		return;
	}

	if(dflag == 0)
		termrestore();

	kill(0, SIGKILL);
	exit(0);
}

void
osreboot(char *file, char **argv)
{
	if(dflag == 0)
		termrestore();
	execvp(file, argv);
	error("reboot failure");
}

void
libinit(char *imod)
{
	struct sigaction act;
	sigset_t mask;
	struct passwd *pw;
	Proc *p;
	void *tos;
	char sys[64];

	setsid();

	gethostname(sys, sizeof(sys));
	kstrdup(&ossysname, sys);
	pw = getpwnam("nobody");
	if(pw != nil) {
		uidnobody = pw->pw_uid;
		gidnobody = pw->pw_gid;
	}

	if(dflag == 0)
		termset();

	memset(&act, 0 , sizeof(act));
	act.sa_handler = trapUSR1;
	sigaction(SIGUSR1, &act, nil);

	sigemptyset(&mask);
	sigaddset(&mask, SIGUSR2);
	sigprocmask(SIG_BLOCK, &mask, NULL);

	memset(&act, 0 , sizeof(act));
	act.sa_handler = trapUSR2;
	sigaction(SIGUSR2, &act, nil);

	act.sa_handler = SIG_IGN;
	sigaction(SIGCHLD, &act, nil);

	/*
	 * For the correct functioning of devcmd in the
	 * face of exiting slaves
	 */
	signal(SIGPIPE, SIG_IGN);
	if(signal(SIGTERM, SIG_IGN) != SIG_IGN)
		signal(SIGTERM, cleanexit);
	if(signal(SIGINT, SIG_IGN) != SIG_IGN)
		signal(SIGINT, cleanexit);

	if(sflag == 0) {
		act.sa_flags = SA_SIGINFO;
		act.sa_sigaction = trapILL;
		sigaction(SIGILL, &act, nil);
		act.sa_sigaction = trapFPE;
		sigaction(SIGFPE, &act, nil);
		act.sa_sigaction = trapmemref;
		sigaction(SIGBUS, &act, nil);
		sigaction(SIGSEGV, &act, nil);
		act.sa_flags &= ~SA_SIGINFO;
	}

	p = newproc();
	p->kstack = stackalloc(p, &tos);

	pw = getpwuid(getuid());
	if(pw != nil)
		kstrdup(&eve, pw->pw_name);
	else
		print("cannot getpwuid\n");

	p->env->uid = getuid();
	p->env->gid = getgid();

	executeonnewstack(tos, emuinit, imod);
}

int
readkbd(void)
{
	int n;
	char buf[1];

	n = read(0, buf, sizeof(buf));
	if(n < 0)
		print("keyboard close (n=%d, %s)\n", n, strerror(errno));
	if(n <= 0)
		pexit("keyboard thread", 0);

	switch(buf[0]) {
	case '\r':
		buf[0] = '\n';
		break;
	case DELETE:
		buf[0] = 'H' - '@';
		break;
	case CTRLC:
		cleanexit(0);
		break;
	}
	return buf[0];
}

/*
 * Return an abitrary millisecond clock time
 */
long
osmillisec(void)
{
	static long sec0 = 0, usec0;
	struct timeval t;

	if(gettimeofday(&t,(struct timezone*)0)<0)
		return 0;

	if(sec0 == 0) {
		sec0 = t.tv_sec;
		usec0 = t.tv_usec;
	}
	return (t.tv_sec-sec0)*1000+(t.tv_usec-usec0+500)/1000;
}

/*
 * Return the time since the epoch in nanoseconds and microseconds
 * The epoch is defined at 1 Jan 1970
 */
vlong
osnsec(void)
{
	struct timeval t;

	gettimeofday(&t, nil);
	return (vlong)t.tv_sec*1000000000L + t.tv_usec*1000;
}

vlong
osusectime(void)
{
	struct timeval t;
 
	gettimeofday(&t, nil);
	return (vlong)t.tv_sec * 1000000 + t.tv_usec;
}

int
osmillisleep(ulong milsec)
{
	struct  timespec time;

	time.tv_sec = milsec/1000;
	time.tv_nsec= (milsec%1000)*1000000;
	nanosleep(&time, NULL);
	return 0;
}

int
limbosleep(ulong milsec)
{
	return osmillisleep(milsec);
}

void
osyield(void)
{
	sched_yield();
}

void
ospause(void)
{
	for(;;)
		pause();
}

void
oslopri(void)
{
	setpriority(PRIO_PROCESS, 0, getpriority(PRIO_PROCESS,0)+4);
}

static struct {
	Lock l;
	void *free;
} stacklist;

static void
_stackfree(void *stack)
{
	*((void **)stack) = stacklist.free;
	stacklist.free = stack;
}

static void
stackfreeandexit(void *stack)
{
	lock(&stacklist.l);
	_stackfree(stack);
	unlockandexit(&stacklist.l.val);
}

static void *
stackalloc(Proc *p, void **tos)
{
	void *rv;
	lock(&stacklist.l);
	if (stacklist.free == 0) {
		int x;
		/*
		 * obtain some more by using sbrk()
		 */
		void *more = sbrk(KSTACK * (NSTACKSPERALLOC + 1));
		if (more == 0)
			panic("stackalloc: no more stacks");
		/*
		 * align to KSTACK
		 */
		more = (void *)((((unsigned long)more) + (KSTACK - 1)) & ~(KSTACK - 1));
		/*
		 * free all the new stacks onto the freelist
		 */
		for (x = 0; x < NSTACKSPERALLOC; x++)
			_stackfree((char *)more + KSTACK * x);
	}
	rv = stacklist.free;
	stacklist.free = *(void **)rv;
	unlock(&stacklist.l);
	*tos = rv + KSTACK - sizeof(vlong);
	*(Proc **)rv = p;
	return rv;
}
