#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#undef _POSIX_C_SOURCE 
#undef getwd
#include	<unistd.h>
#include	<thread.h>
#include	<time.h>
#include	<termios.h>
#include	<signal.h>
#include 	<pwd.h>
#include	<sys/resource.h>
#include	<sys/time.h>

enum
{
	DELETE  = 0x7F
};
char *hosttype = "Solaris";

static thread_key_t	prdakey;

static siginfo_t siginfo;

extern int dflag;

Proc*
getup(void)
{
	void *vp;

	if (thr_getspecific(prdakey, &vp))
		return nil;
	return vp;
}

void
pexit(char *msg, int t)
{
	Osenv *e;

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

	/*print("pexit: %s: %s\n", up->text, msg);*/
	e = up->env;
	if(e != nil) {
		closefgrp(e->fgrp);
		closepgrp(e->pgrp);
		closeegrp(e->egrp);
		closesigs(e->sigs);
	}
	free(up->prog);
	sema_destroy(up->os);
	free(up->os);
	free(up);
	thr_exit(0);
}

static void *
tramp(void *v)
{
	struct Proc *Up;

	if(thr_setspecific(prdakey, v)) {
		print("set specific data failed in tramp\n");
		thr_exit(0);
	}
	Up = v;
	Up->sigid = thr_self();
	Up->func(Up->arg);
	pexit("", 0);
}

int
kproc(char *name, void (*func)(void*), void *arg, int flags)
{
	thread_t thread;
	Proc *p;
	Pgrp *pg;
	Fgrp *fg;
	Egrp *eg;
	sema_t *sem;

	p = newproc();

	sem = malloc(sizeof(*sem));
	if(sem == nil)
		panic("can't allocate semaphore");
	sema_init(sem, 0, USYNC_THREAD, 0);
	p->os = sem;

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

	if(thr_create(0, 0, &tramp, p, THR_BOUND|THR_DETACHED, &thread))
		panic("thr_create failed\n");
	thr_yield();
	return(thread);
}

/* to get pc on trap use siginfo.si_pc field and define all trap handlers
	as printILL - have to set sa_sigaction, sa_flags not sa_handler
*/

static void
trapUSR1(void)
{
	int intwait;

	intwait = up->intwait;
	up->intwait = 0;	/* clear it to let proc continue in osleave */

	if(up->type != Interp)		/* Used to unblock pending I/O */
		return;
	if(intwait == 0)		/* Not posted so its a sync error */
		disfault(nil, Eintr);	/* Should never happen */
}

static void
trapILL(void)
{
	disfault(nil, "Illegal instruction");
}

static void
printILL(int sig, siginfo_t *siginfo, void *v)
{
	panic("Illegal instruction with code=%d at address=%x, opcode=%x.\n",
		siginfo->si_code, siginfo->si_addr,*(char*)siginfo->si_addr);
}

static void
trapBUS(void)
{
	disfault(nil, "Bus error");
}

static void
trapSEGV(void)
{
	disfault(nil, "Segmentation violation");
}

static void
trapFPE(void)
{
	disfault(nil, "Floating point exception");
}

void
oshostintr(Proc *p)
{
	thr_kill(p->sigid, SIGUSR1);
}

void
osblock(void)
{
	while(sema_wait(up->os))
		;	/* retry on signals */
}

void
osready(Proc *p)
{
	sema_post(p->os);
}

void
oslongjmp(void *regs, osjmpbuf env, int val)
{
	USED(regs);
	siglongjmp(env, val);
}

static struct termios tinit;

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
	exit(0);
}

int gidnobody= -1, uidnobody= -1;

void
getnobody(void)
{
	struct passwd *pwd;
	
	if (pwd=getpwnam("nobody")) {
		uidnobody = pwd->pw_uid;
		gidnobody = pwd->pw_gid;
	}
}

void
osreboot(char *file, char **argv)
{
	if(dflag == 0)
		termrestore();
	execvp(file, argv);
	panic("reboot failure");
}

void
libinit(char *imod)
{
	struct Proc *Up;
	struct sigaction act;
	struct passwd *pw;
	char sys[64];

	setsid();

	if(dflag == 0)
		termset();

	gethostname(sys, sizeof(sys));
	kstrdup(&ossysname, sys);
	getnobody();

	memset(&act, 0 , sizeof(act));
	act.sa_handler=trapUSR1;
	sigaction(SIGUSR1, &act, nil);
	/*
	 * For the correct functioning of devcmd in the
	 * face of exiting slaves
	 */
	signal(SIGPIPE, SIG_IGN);
	if(signal(SIGTERM, SIG_IGN) != SIG_IGN)
		signal(SIGTERM, cleanexit);
	if(sflag == 0) {
		act.sa_handler = trapBUS;
		sigaction(SIGBUS, &act, nil);
		act.sa_handler = trapILL;
		sigaction(SIGILL, &act, nil);
		act.sa_handler = trapSEGV;
		sigaction(SIGSEGV, &act, nil);
		act.sa_handler = trapFPE;
		sigaction(SIGFPE, &act, nil);
		if(signal(SIGINT, SIG_IGN) != SIG_IGN)
			signal(SIGINT, cleanexit);
	} else{
		act.sa_sigaction = printILL;
		act.sa_flags=SA_SIGINFO;
		sigaction(SIGILL, &act, nil);
	}	

	if(thr_keycreate(&prdakey,NULL))
		print("keycreate failed\n");

	Up = newproc();
	if(thr_setspecific(prdakey,Up))
		panic("set specific thread data failed\n");

	pw = getpwuid(getuid());
	if(pw != nil)
		kstrdup(&eve, pw->pw_name);
	else
		print("cannot getpwuid\n");

	up->env->uid = getuid();
	up->env->gid = getgid();
	emuinit(imod);
}

int
readkbd(void)
{
	int n;
	char buf[1];

	n = read(0, buf, sizeof(buf));
	if(n < 0)
		fprint(2, "keyboard read: %s\n", strerror(errno));
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

	if(gettimeofday(&t, NULL)<0)
		return(0);
	if(sec0==0){
		sec0 = t.tv_sec;
		usec0 = t.tv_usec;
	}
	return((t.tv_sec-sec0)*1000+(t.tv_usec-usec0+500)/1000);
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
	nanosleep(&time,nil);
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
	thr_yield();
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
