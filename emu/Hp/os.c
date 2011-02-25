#include	<pthread.h>
#include	<signal.h>
#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include 	<sys/socket.h>
#include	<time.h>
#include	<sys/time.h>
#include	<termios.h>
#include	<pwd.h>
#include	<errno.h>

enum
{
	BUNCHES = 5000,
	DELETE  = 0x7F
};
char *hosttype = "Hp";


static pthread_key_t	prdakey;

extern int dflag;

Lock mulock = {1, 0};
 
ulong
_tas(ulong *l)
{
	ulong v;

	while(!(mutexlock(&mulock)))
		pthread_yield();
 
	v = *l;
	if(v == 0)
		*l = 1;
	mulock.key = 1;
	return v;
}

static ulong erendezvous(void*, ulong);


void
osblock(void)
{
	erendezvous(up, 0);
}

void
osready(Proc *p)
{
	erendezvous(p, 0);
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

	e = up->env;
	if(e != nil) {
		closefgrp(e->fgrp);
		closepgrp(e->pgrp);
		closeegrp(e->egrp);
		closesigs(e->sigs);
	}
	free(up->prog);
	free(up);
	pthread_exit(0);
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

void
trapUSR1(void)
{
	int intwait;

	intwait = up->intwait;
	up->intwait = 0;	/* clear it to let proc continue in osleave */

	if(up->type != Interp)		/* Used to unblock pending I/O */
		return;

	if(intwait == 0)		/* Not posted so it's a sync error */
		disfault(nil, Eintr);	/* Should never happen */
}

void
trapILL(void)
{
	disfault(nil, "Illegal instruction");
}

void
trapSEGV(void)
{
	disfault(nil, "Segmentation violation");
}

sigset_t set;
setsigs()
{
	struct sigaction act;

	memset(&act, 0 , sizeof(act));
	sigemptyset(&set);
	
	act.sa_handler=SIG_IGN;
	if(sigaction(SIGPIPE, &act, nil))
	        panic("can't ignore sig pipe");

	if(sigaddset(&set,SIGUSR1)== -1)
		panic("sigaddset SIGUSR1");

	if(sigaddset(&set,SIGUSR2)== -1)
                panic("sigaddset SIGUSR2");

	/* For the correct functioning of devcmd in the
	 * face of exiting slaves
	 */
	if(sflag == 0) {
		act.sa_handler=trapBUS;
		act.sa_flags|=SA_SIGINFO;
		if(sigaction(SIGBUS, &act, nil))
			panic("sigaction SIGBUS");
		act.sa_handler=trapILL;
		if(sigaction(SIGILL, &act, nil))
                        panic("sigaction SIGILL");
		act.sa_handler=trapSEGV;
		if(sigaction(SIGSEGV, &act, nil))
                        panic("sigaction SIGSEGV");
		if(sigaddset(&set,SIGINT)== -1)
			panic("sigaddset");
	}
	if(sigprocmask(SIG_BLOCK,&set,nil)!= 0)
		panic("sigprocmask");
}

static void *
tramp(void *v)
{
	struct Proc *Up;
	pthread_t thread;
	struct sigaction oldact;

	setsigs();
	if(sigaction(SIGBUS, nil, &oldact))
                panic("sigaction failed");
        if(oldact.sa_handler!=trapBUS && sflag==0)
                panic("3rd old act sa_handler");

	if(pthread_setspecific(prdakey,v)) {
		print("set specific data failed in tramp\n");
		pthread_exit(0);
	}
	Up = v;
 	thread = pthread_self();
	Up->sigid = cma_thread_get_unique(&thread);
	/* attempt to catch signals again */
	setsigs();
	Up->func(Up->arg);
	pexit("", 0);
}

pthread_t active_threads[BUNCHES]; /* this should be more than enuf */

void
kproc(char *name, void (*func)(void*), void *arg, int flags)
{
	pthread_t thread;
	pthread_attr_t attr;
	int id;
	Proc *p;
	Pgrp *pg;
	Fgrp *fg;
	Egrp *eg;
	struct sigaction oldact;

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
	if((pthread_attr_create(&attr))== -1)
		panic("pthread_attr_create failed");

	pthread_attr_setsched(&attr,SCHED_OTHER);
	if(pthread_create(&thread, &attr, tramp, p))
		panic("thr_create failed\n");
        if(sigaction(SIGBUS, nil, &oldact))
                panic("sigaction failed");
        if(oldact.sa_handler!=trapBUS && sflag == 0)
                panic("2nd old act sa_handler");

	if((id=cma_thread_get_unique(&thread))>=BUNCHES)
		panic("id too big");
	active_threads[id]=thread;
}

void
oshostintr(Proc *p)
{
	pthread_cancel(active_threads[p->sigid]);
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

static	pthread_mutex_t rendezvouslock;

void
libinit(char *imod)
{
	struct passwd *pw;
	struct Proc *Up;
	struct sigaction oldact;
	int ii;
	int retval;
	int *pidptr;
	char sys[64];

	cma_init();
	setsid();
	/* mulock.key = 1; */ /* initialize to unlock */
	if(pthread_mutex_init(&rendezvouslock,pthread_mutexattr_default))
		panic("pthread_mutex_init");

	gethostname(sys, sizeof(sys));
	kstrdup(&ossysname, sys);
	getnobody();

	if(dflag == 0)
		termset();

	setsigs();
	if(sigaction(SIGBUS, nil, &oldact)) {
                panic("sigaction failed");
	}
        if(oldact.sa_handler!=trapBUS && sflag == 0)
                panic("1st old act sa_handler");

	if(pthread_keycreate(&prdakey,NULL))
		print("keycreate failed\n");

	Up = newproc();
	if(pthread_setspecific(prdakey,Up))
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
	if(n != 1) {
		print("keyboard close (n=%d, %s)\n", n, strerror(errno));
		pexit("keyboard thread", 0);
	}

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

enum
{
	NHLOG	= 7,
	NHASH	= (1<<NHLOG)
};

typedef struct Tag Tag;
struct Tag
{
	void*	tag;
	ulong	val;
	int	pid;
	Tag*	hash;
	Tag*	free;
	pthread_cond_t cv;
};

static	Tag*	ht[NHASH];
static	Tag*	ft;

static ulong
erendezvous(void *tag, ulong value)
{
	int h;
	ulong rval;
	Tag *t, *f, **l;
	int ii=0;

	h = (ulong)tag & (NHASH-1);

	if(pthread_mutex_lock(&rendezvouslock))
		panic("pthread_mutex_lock");

	l = &ht[h];
	for(t = *l; t; t = t->hash) {
		if(t->tag == tag) {
			rval = t->val;
			t->val = value;
			t->tag = 0;
			if(pthread_mutex_unlock(&rendezvouslock))
				panic("pthread_mutex_unlock");
			if(pthread_cond_signal(&(t->cv)))
				panic("pthread_cond_signal");
			return rval;		
		}
	}

	t = ft;
	if(t == 0) {
		t = malloc(sizeof(Tag));
		if(t == 0)
			panic("rendezvous: no memory");
		if(pthread_cond_init(&(t->cv),pthread_condattr_default)) {
			print("pthread_cond_init (errno: %s) \n", strerror(errno));
			panic("pthread_cond_init");
		}
	} else
		ft = t->free;

	t->tag = tag;
	t->val = value;
	t->hash = *l;
	*l = t;

	while(t->tag)
		pthread_cond_wait(&(t->cv),&rendezvouslock);

	rval = t->val;
	for(f = *l; f; f = f->hash){
		if(f == t) {
			*l = f->hash;
			break;
		}
		l = &f->hash;
	}
	t->free = ft;
	ft = t;
	if(pthread_mutex_unlock(&rendezvouslock))
		panic("pthread_mutex_unlock");

	return rval;
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
		return(0);
	if(sec0==0) {
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
	if(pthread_delay_np(&time)== -1)
		;	/* might be interrupted */
	return 0;
}
	
Proc *
getup(void)
{
	void *vp;

	vp=nil;
	pthread_getspecific(prdakey,&vp);
	return(vp);
}

ulong
getcallerpc(void *arg)
{
	return 0 ;
}

void
osyield(void)
{
	pthread_yield();
}

void
ospause(void)
{
	int s;

	for(;;) {
		switch(s=sigwait(&set)) {
		case SIGUSR1:
			trapUSR1();
		case SIGINT:
			cleanexit(0);
		default:
			print("signal: %d %s\n",s, strerror(errno));
			panic("sigwait");
		}
	}
}

void
oslopri(void)
{
	/* TO DO */
}
