/*
 * Loosely based on FreeBSD/os.c and Solaris/os.c
 * Copyright © 1998, 1999 Lucent Technologies Inc.  All rights reserved.
 * Revisions Copyright © 1999, 2000 Vita Nuova Limited.  All rights reserved.
 * Revisions Copyright © 2002, 2003 Corpus Callosum Corporation.  All rights reserved.
 */

#include	"dat.h"
#include	"fns.h"
#include	"error.h"

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
char *cputype = "power";

static pthread_key_t  prdakey;

extern int dflag;

Proc *
getup(void) {
    return (Proc *)pthread_getspecific(prdakey);
}

/*  Pthread version */
void
pexit(char *msg, int t)
{
    Osenv *e;
    Proc *p;

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
    }
    free(e->user);
    free(p->prog);
    free(p);
    pthread_exit(0);
}

void
trapBUS(int signo)
{
    USED(signo);    
    disfault(nil, "Bus error");
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

void
trapILL(int signo)
{
    USED(signo);
    disfault(nil, "Illegal instruction");
}

/* from geoff collyer's port */
void
printILL(int sig, siginfo_t *siginfo, void *v)
{
    USED(sig);
    USED(v);
    panic("Illegal instruction with code=%d at address=%x, opcode=%x.\n"
        ,siginfo->si_code, siginfo->si_addr,*(char*)siginfo->si_addr);
}

void
trapSEGV(int signo)
{
    USED(signo);
    disfault(nil, "Segmentation violation");
}

void
trapFPE(int signo)
{
    USED(signo);
    disfault(nil, "Floating point exception");
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
    
    act.sa_handler=trapUSR1;
    sigaction(SIGUSR1, &act, nil);
    
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
    } else {
        act.sa_sigaction = printILL;
        act.sa_flags=SA_SIGINFO;
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

int
kproc(char *name, void (*func)(void*), void *arg, int flags)
{
    pthread_t thread;
    Proc *p;
    Pgrp *pg;
    Fgrp *fg;
    Egrp *eg;
    
    pthread_attr_t attr;

    p = newproc();
    if(p == nil)
        panic("kproc: no memory");
    
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
    
    up->kid = p;
    
    if((pthread_attr_init(&attr))== -1)
        panic("pthread_attr_init failed");

    errno=0;
    pthread_attr_setschedpolicy(&attr,SCHED_OTHER);
    if(errno)
        panic("pthread_attr_setschedpolicy failed");

    pthread_attr_setinheritsched(&attr, PTHREAD_INHERIT_SCHED);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);

    if(pthread_create(&thread, &attr, tramp, p))
        panic("thr_create failed\n");
    pthread_attr_destroy(&attr);
        
    return (int)thread;
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
    if (err != KERN_SUCCESS) {
        print("segflush: failure (%d) address %lud\n", err, va);        
    }
    return (int)err;
}

/* from geoff collyer's port
invalidate instruction cache and write back data cache from a to a+n-1,
at least.

void
segflush(void *a, ulong n)
{
    ulong *p;
    
    // paranoia, flush the world
    __asm__("isync\n\t"
            "eieio\n\t"
            : // no output
            :
            );
    // cache blocks are often eight words (32 bytes) long, sometimes 16 bytes.
    // need to determine it dynamically?
    for (p = (ulong *)((ulong)a & ~3UL); (char *)p < (char *)a + n; p++)
        __asm__("dcbst	0,%0\n\t"	// not dcbf, which writes back, then invalidates
            "icbi	0,%0\n\t"
            : // no output
            : "ar" (p)
            );
    __asm__("isync\n\t"
            "eieio\n\t"
            : // no output
            :
            );
}
*/

void
oshostintr(Proc *p)
{
    pthread_kill((pthread_t)p->sigid, SIGUSR1);
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

/* Pthread version */
static	pthread_mutex_t rendezvouslock;
static	pthread_mutexattr_t	*pthread_mutexattr_default = NULL;

void
libinit(char *imod)
{
    struct passwd *pw;
    Proc *p;
    char sys[64];

    setsid();
        
    // setup personality
    gethostname(sys, sizeof(sys));
    kstrdup(&ossysname, sys);
    getnobody();
    
    if(dflag == 0)
        termset();

    setsigs();

    if(pthread_mutex_init(&rendezvouslock, pthread_mutexattr_default))
         panic("pthread_mutex_init");

    if(pthread_key_create(&prdakey,NULL))
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
    pthread_cond_t cv;
    Tag*	next;
};

static	Tag*	ht[NHASH];
static	Tag*	ft;
//static	Lock	hlock;

static ulong
erendezvous(void *tag, ulong value)
{
    int h;
    ulong rval;
    Tag *t, **l, *f;
    
    h = (ulong)tag & (NHASH-1);

//    lock(&hlock);
    pthread_mutex_lock(&rendezvouslock);
    l = &ht[h];
    for(t = ht[h]; t; t = t->next) {
        if(t->tag == tag) {
            rval = t->val;
            t->val = value;
            t->tag = 0;
            pthread_mutex_unlock(&rendezvouslock);
//            unlock(&hlock);
            if(pthread_cond_signal(&(t->cv)))
                panic("pthread_cond_signal");
            return rval;		
        }
    }
    
    t = ft;
    if(t == 0) {
        t = malloc(sizeof(Tag));
        if(t == nil)
            panic("rendezvous: no memory");
        if(pthread_cond_init(&(t->cv), NULL)) {
            print("pthread_cond_init (errno: %s) \n", strerror(errno));
            panic("pthread_cond_init");
        }
    } else
        ft = t->next;
    
    t->tag = tag;
    t->val = value;
    t->next = *l;
    *l = t;
//    pthread_mutex_unlock(&rendezvouslock);
//    unlock(&hlock);
    
    while(t->tag != nil)
        pthread_cond_wait(&(t->cv),&rendezvouslock);
    
//    pthread_mutex_lock(&rendezvouslock);
//    lock(&hlock);
    rval = t->val;
    for(f = *l; f; f = f->next){
        if(f == t) {
            *l = f->next;
            break;
        }
        l = &f->next;
    }
    t->next = ft;
    ft = t;
    pthread_mutex_unlock(&rendezvouslock);
//    unlock(&hlock);

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

    if(gettimeofday(&t, NULL)<0)
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
    // sched_yield();
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
//  pthread_setschedparam(pthread_t thread,  int policy, const struct sched_param *param);
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
    if (err != KERN_SUCCESS)
        brk = (void*)-1;
    
    return brk;
}
