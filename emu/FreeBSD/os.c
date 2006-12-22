#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#undef getwd
#include	<signal.h>
#include 	<sys/socket.h>
#include	<time.h>
#include	<sys/time.h>
#include	<termios.h>
#include	<sched.h>
#include	<pwd.h>
#include	<errno.h>
#include	<unistd.h>
#include	<sys/resource.h>

enum
{
	DELETE  = 0x7F,
	NSTACKSPERALLOC = 16,
	X11STACK=	256*1024
};
char *hosttype = "FreeBSD";

extern void unlockandexit(int*);
extern void executeonnewstack(void*, void (*f)(void*), void*);
static void *stackalloc(Proc *p, void **tos);
static void stackfreeandexit(void *stack);

extern int dflag;

void
pexit(char *msg, int t)
{
	Osenv *e;
	Proc *p;
	void *kstack;

	lock(&procs.l);
	p = up;
	if(p->prev)
		p->prev->next = p->next;
	else
		procs.head = p->next;

	if(up->next)
		p->next->prev = p->prev;
	else
		procs.tail = p->prev;
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
	kstack = p->kstack;
	free(p->prog);
	free(p);
	if(kstack != nil)
		stackfreeandexit(kstack);
}

void
trapBUS(int signo, siginfo_t *info, void *context)
{
	if(info)
		print("trapBUS: signo: %d code: %d addr: %lx\n",
		info->si_signo, info->si_code, info->si_addr);
	else
		print("trapBUS: no info\n"); 
	disfault(nil, "Bus error");
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
	if(intwait == 0)		/* Not posted so its a sync error */
		disfault(nil, Eintr);	/* Should never happen */
}

static void
trapUSR2(int signo)
{
	USED(signo);
	/* we've done our work of interrupting sigsuspend */
}

static void
trapILL(int signo)
{
	disfault(nil, "Illegal instruction");
}

static void
trapSEGV(int signo)
{
	disfault(nil, "Segmentation violation");
}

static sigset_t initmask;

static void
setsigs(void)
{
	struct sigaction act;
	sigset_t mask;

	memset(&act, 0 , sizeof(act));
	sigemptyset(&initmask);
	
	signal(SIGPIPE, SIG_IGN);	/* prevent signal when devcmd child exits */
	if(signal(SIGTERM, SIG_IGN) != SIG_IGN)
		signal(SIGTERM, cleanexit);

	act.sa_handler = trapUSR1;
	act.sa_mask = initmask;
	sigaction(SIGUSR1, &act, nil);

	act.sa_handler = trapUSR2;
	sigaction(SIGUSR2, &act, nil);
	sigemptyset(&mask);
	sigaddset(&mask, SIGUSR2);
	sigaddset(&initmask, SIGUSR2);
	sigprocmask(SIG_BLOCK, &mask, NULL);

	/*
 	 * prevent Zombies forming when any process terminates
	 */
	act.sa_sigaction = 0;
	act.sa_flags |= SA_NOCLDWAIT;
	if(sigaction(SIGCHLD, &act, nil))
		panic("sigaction SIGCHLD");

	if(sflag == 0) {
		act.sa_sigaction = trapBUS;
		act.sa_flags |= SA_SIGINFO;
		if(sigaction(SIGBUS, &act, nil))
			panic("sigaction SIGBUS");
		act.sa_handler = trapILL;
		if(sigaction(SIGILL, &act, nil))
			panic("sigaction SIGBUS");
		act.sa_handler = trapSEGV;
		if(sigaction(SIGSEGV, &act, nil))
			panic("sigaction SIGSEGV");
		if(sigaddset(&initmask, SIGINT) == -1)
			panic("sigaddset");
	}
	if(sigprocmask(SIG_BLOCK, &initmask, nil)!= 0)
		panic("sigprocmask");
}

static int
tramp(void *arg)
{
	Proc *p;

	p = arg;
	p->pid = p->sigid = getpid();
	sigprocmask(SIG_BLOCK, &initmask, nil);	/* in 5.3, rfork_thread doesn't copy from parent, contrary to docs? */
	(*p->func)(p->arg);
	pexit("{Tramp}", 0);
	_exit(0);
}

int
kproc(char *name, void (*func)(void*), void *arg, int flags)
{
	Proc *p;
	Pgrp *pg;
	Fgrp *fg;
	Egrp *eg;
	int pid;
	void *tos;

	p = newproc();

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

	if(flags & KPX11){
		p->kstack = nil;	/* never freed; also up not defined */
		tos = (char*)mallocz(X11STACK, 0) + X11STACK - sizeof(void*);
	}else
		p->kstack = stackalloc(p, &tos);
	pid = rfork_thread(RFPROC|RFMEM|RFNOWAIT, tos, tramp, p);
	if(pid < 0)
		panic("ourfork");
		
	return pid;

}

void
oshostintr(Proc *p)
{
	kill(p->sigid, SIGUSR1);
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

struct termios tinit;

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
	panic("reboot failure");
}

int gidnobody= -1, uidnobody= -1;

void
getnobody()
{
	struct passwd *pwd;
	
	if(pwd = getpwnam("nobody")) {
		uidnobody = pwd->pw_uid;
		gidnobody = pwd->pw_gid;
	}
}

void
libinit(char *imod)
{
	struct passwd *pw;
	Proc *p;
	void *tos;
	char sys[64];

	setsid();

	gethostname(sys, sizeof(sys));
	kstrdup(&ossysname, sys);
	getnobody();

	if(dflag == 0)
		termset();

	setsigs();

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
	if(sec0==0) {
		sec0 = t.tv_sec;
		usec0 = t.tv_usec;
	}
	return (t.tv_sec-sec0)*1000+(t.tv_usec-usec0+500)/1000;
}

int
limbosleep(ulong milsec)
{
	return osmillisleep(milsec);
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
	struct timespec time;

	time.tv_sec = milsec / 1000;
	time.tv_nsec = (milsec % 1000) * 1000000;
	nanosleep(&time, 0);
	return 0;
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
	*tos = rv + KSTACK - sizeof(void*);
	*(Proc **)rv = p;
	return rv;
}
