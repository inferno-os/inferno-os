/*
 * Loosely based on FreeBSD/os.c and Solaris/os.c
 * Copyright © 1998, 1999 Lucent Technologies Inc.  All rights reserved.
 * Revisions Copyright © 1999, 2000 Vita Nuova Limited.  All rights reserved.
 * Revisions Copyright © 2002, 2003 Corpus Callosum Corporation.  All rights reserved.
 */

#include	"dat.h"
#include	"fns.h"
#include	"error.h"

#include <raise.h>

#undef _POSIX_C_SOURCE 
#undef getwd

#include	<unistd.h>
#include        <pthread.h>
#include	<time.h>
#include	<termios.h>
#include	<signal.h>
#include	<pwd.h>
#include	<sys/resource.h>
#include	<sys/time.h>

#include 	<sys/socket.h>
#include	<sched.h>
#include	<errno.h>
#include        <sys/ucontext.h>

#include <sys/types.h>
#include <sys/stat.h>

#include <mach/mach_init.h>
#include <mach/task.h>
#include <mach/vm_map.h>

#if defined(__ppc__)
#include <architecture/ppc/cframe.h>
#endif

enum
{
    DELETE = 0x7F
};
char *hosttype = "MacOSX";
char *cputype = OBJTYPE;

typedef struct Sem Sem;
struct Sem {
	pthread_cond_t	c;
	pthread_mutex_t	m;
	int	v;
};

static pthread_key_t  prdakey;

extern int dflag;

Proc*
getup(void)
{
	return pthread_getspecific(prdakey);
}

void
pexit(char *msg, int t)
{
	Osenv *e;
	Proc *p;
	Sem *sem;

	USED(t);
	USED(msg);

	lock(&procs.l);
	p = up;
	if(p->prev)
		p->prev->next = p->next;
	else
		procs.head = p->next;

	if(p->next)
		p->next->prev = p->prev;
	else
		procs.tail = p->prev;
	unlock(&procs.l);

	if(0)
		print("pexit: %s: %s\n", p->text, msg);

	e = p->env;
	if(e != nil) {
		closefgrp(e->fgrp);
		closepgrp(e->pgrp);
		closeegrp(e->egrp);
		closesigs(e->sigs);
		free(e->user);
	}
	free(p->prog);
	sem = p->os;
	if(sem != nil){
		pthread_cond_destroy(&sem->c);
		pthread_mutex_destroy(&sem->m);
	}
	free(p->os);
	free(p);
	pthread_exit(0);
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

void
trapUSR1(int signo)
{
    USED(signo);
    
    if(up->type != Interp)      /* Used to unblock pending I/O */
        return;
    if(up->intwait == 0)        /* Not posted so its a sync error */
        disfault(nil, Eintr);	/* Should never happen */
    
    up->intwait = 0;		/* Clear it so the proc can continue */
}

/* from geoff collyer's port */
void
printILL(int sig, siginfo_t *si, void *v)
{
	USED(sig);
	USED(v);
	panic("illegal instruction with code=%d at address=%p, opcode=%#x\n",
		si->si_code, si->si_addr, *(uchar*)si->si_addr);
}

static void
setsigs(void)
{
	struct sigaction act;

	memset(&act, 0 , sizeof(act));

	/*
	  * For the correct functioning of devcmd in the
	 * face of exiting slaves
	 */
	signal(SIGPIPE, SIG_IGN);
	if(signal(SIGTERM, SIG_IGN) != SIG_IGN)
		signal(SIGTERM, cleanexit);

	act.sa_handler = trapUSR1;
	sigaction(SIGUSR1, &act, nil);

	if(sflag == 0) {
		act.sa_flags = SA_SIGINFO;
		act.sa_sigaction = trapILL;
		sigaction(SIGILL, &act, nil);
		act.sa_sigaction = trapFPE;
		sigaction(SIGFPE, &act, nil);
		act.sa_sigaction = trapmemref;
		sigaction(SIGBUS, &act, nil);
		sigaction(SIGSEGV, &act, nil);
		if(signal(SIGINT, SIG_IGN) != SIG_IGN)
			signal(SIGINT, cleanexit);
	} else {
		act.sa_sigaction = printILL;
		act.sa_flags = SA_SIGINFO;
		sigaction(SIGILL, &act, nil);
	}
}




void *
tramp(void *arg)
{
	Proc *p = arg;
	p->sigid = (int)pthread_self();
	if(pthread_setspecific(prdakey, arg)) {
		print("set specific data failed in tramp\n");
		pthread_exit(0);
	}
	p->func(p->arg);
	pexit("{Tramp}", 0);
	return NULL;
}

void
kproc(char *name, void (*func)(void*), void *arg, int flags)
{
	pthread_t thread;
	Proc *p;
	Pgrp *pg;
	Fgrp *fg;
	Egrp *eg;
	pthread_attr_t attr;
	Sem *sem;

	p = newproc();
	if(p == nil)
		panic("kproc: no memory");
	sem = malloc(sizeof(*sem));
	if(sem == nil)
		panic("can't allocate semaphore");
	pthread_cond_init(&sem->c, NULL);
	pthread_mutex_init(&sem->m, NULL);
	sem->v = 0;
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
	} else {
		procs.head = p;
		p->prev = nil;
	}
	procs.tail = p;
	unlock(&procs.l);

	if(pthread_attr_init(&attr) == -1)
		panic("pthread_attr_init failed");

	pthread_attr_setschedpolicy(&attr, SCHED_OTHER);
	pthread_attr_setinheritsched(&attr, PTHREAD_INHERIT_SCHED);
	pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);

	if(pthread_create(&thread, &attr, tramp, p))
		panic("thr_create failed\n");
	pthread_attr_destroy(&attr);
}

int
segflush(void *va, ulong len)
{
	kern_return_t   err;
	vm_machine_attribute_val_t value = MATTR_VAL_ICACHE_FLUSH;

	err = vm_machine_attribute( (vm_map_t)mach_task_self(),
		(vm_address_t)va,
		(vm_size_t)len,
		MATTR_CACHE,
		&value);
	if(err != KERN_SUCCESS)
		print("segflush: failure (%d) address %lud\n", err, va);
	return (int)err;
}

void
oshostintr(Proc *p)
{
	pthread_kill((pthread_t)p->sigid, SIGUSR1);
}

void
osblock(void)
{
	Sem *sem;

	sem = up->os;
	pthread_mutex_lock(&sem->m);
	while(sem->v == 0)
		pthread_cond_wait(&sem->c, &sem->m);
	sem->v--;
	pthread_mutex_unlock(&sem->m);
}

void
osready(Proc *p)
{
	Sem *sem;

	sem = p->os;
	pthread_mutex_lock(&sem->m);
	sem->v++;
	pthread_cond_signal(&sem->c);
	pthread_mutex_unlock(&sem->m);
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
	t.c_lflag &= ~(ICANON | ECHO | ISIG);
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

	if((pwd = getpwnam("nobody"))) {
		uidnobody = pwd->pw_uid;
		gidnobody = pwd->pw_gid;
	}
}

void
libinit(char *imod)
{
	struct passwd *pw;
	Proc *p;
	char	sys[64];

	setsid();

	// setup personality
	gethostname(sys, sizeof(sys));
	kstrdup(&ossysname, sys);
	getnobody();

	if(dflag == 0)
		termset();

	setsigs();

	if(pthread_key_create(&prdakey, NULL))
		print("key_create failed\n");

	p = newproc();
	if(pthread_setspecific(prdakey, p))
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
	int	n;
	char	buf[1];

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
	static long	sec0 = 0, usec0;
	struct timeval t;

	if(gettimeofday(&t, NULL) < 0)
		return(0);
	if(sec0 == 0) {
		sec0 = t.tv_sec;
		usec0 = t.tv_usec;
	}
	return((t.tv_sec - sec0) * 1000 + (t.tv_usec - usec0 + 500) / 1000);
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
	nanosleep(&time, nil);
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
	pthread_yield_np();
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
//	pthread_setschedparam(pthread_t thread,  int policy, const struct sched_param *param);
	setpriority(PRIO_PROCESS, 0, getpriority(PRIO_PROCESS,0)+4);
}

__typeof__(sbrk(0))
sbrk(int size)
{
	void *brk;
	kern_return_t   err;
    
	err = vm_allocate( (vm_map_t) mach_task_self(),
                       (vm_address_t *)&brk,
                       size,
                       VM_FLAGS_ANYWHERE);
	if(err != KERN_SUCCESS)
		brk = (void*)-1;
	return brk;
}
