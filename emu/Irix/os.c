/* Link with -lfpe. See man pages for fpc
 * and /usr/include/sigfpe.h, sys/fpu.h.
 */
#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	<time.h>
#include	<ulocks.h>
#include	<termios.h>
#include 	<sigfpe.h>
#include	<sys/prctl.h>
#include 	<sys/fpu.h>
#include	<sys/cachectl.h>
#undef _POSIX_SOURCE		/* SGI incompetence */
#include	<signal.h>
#define _BSD_TIME
/* for gettimeofday(), which isn't POSIX,
 * but is fairly common
 */
#include 	<sys/time.h> 
#define _POSIX_SOURCE
#include 	<pwd.h>

extern	int	rebootargc;
extern	char**	rebootargv;

int	gidnobody = -1;
int	uidnobody = -1;
Proc**	Xup;

#define MAXSPROC 30000	/* max procs == MAXPID */
static int	sproctbl[MAXSPROC];

enum
{
	KSTACK	= 64*1024,
	DELETE	= 0x7F
};
char *hosttype = "Irix";
char *cputype = "mips";

extern int dflag;

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

	sproctbl[getpid()] = -1;

	unlock(&procs.l);

/*	print("pexit: %s: %s\n", up->text, msg); /**/
	e = up->env;
	if(e != nil) {
		closefgrp(e->fgrp);
		closepgrp(e->pgrp);
		closeegrp(e->egrp);
		closesigs(e->sigs);
	}
	free(up->prog);
	free(up);
	exit(0);
}

static void
tramp(void *p, size_t stacksz)
{
	up = p;
	up->sigid = getpid();
	up->func(up->arg);
	pexit("", 0);
}

int
kproc(char *name, void (*func)(void*), void *arg, int flags)
{
	Proc *p;
	Pgrp *pg;
	Fgrp *fg;
	Egrp *eg;
	int pid;
	int id;
	int i;

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

	for(i = 1; i < MAXSPROC; i++) {
		if(sproctbl[i] == -1) {
			break;
		}
	}

	if(i==MAXSPROC)
		return -1;

	sproctbl[i] = -i - 1; /* temporary hold of table index outside of lock */

	unlock(&procs.l);

	pid = sprocsp(tramp, PR_SALL, p, 0, KSTACK);

	if(-1 < pid)
		sproctbl[i] = pid;
	else
		sproctbl[i] = -1;

	return pid;
}

void
osblock(void)
{
	blockproc(up->sigid);
}

void
osready(Proc *p)
{
	unblockproc(p->sigid);
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
trapBUS(void)
{
	disfault(nil, "Bus error");
}

void
trapSEGV(void)
{
	disfault(nil, "Segmentation violation");
}

/*
 * This is not a signal handler but rather a vector from real/FPcontrol-Irix.c
 */
void
trapFPE(unsigned exception[5], int value[2])
{
	disfault(nil, "Floating point exception");
}

void
oshostintr(Proc *p)
{
	kill(p->sigid, SIGUSR1);
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

/*	if(sproctbl[0] < 0)
		panic("corrupt sproc tbl");

	kill(sproctbl[0], SIGUSR2);
	sginap(10000); */
}

void
trapUSR2(void)
{
	int i;

	for(i = MAXSPROC - 1; i > 0; i--) {
		if(sproctbl[i] != -1) 
			kill(sproctbl[i], SIGKILL);
		sproctbl[i] = -1;
	}

	execvp(rebootargv[0], rebootargv);
	panic("reboot failure");
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
getnobody(void)
{
	struct passwd *pwd;

	pwd = getpwnam("nobody");
	if(pwd != nil) {
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
	struct sigaction act;
	struct passwd *pw;
	int i;
	char sys[64];

	setsid();

	for(i=0; i<MAXSPROC; i++)
		sproctbl[i] = -1;

	sproctbl[0] = getpid();

	gethostname(sys, sizeof(sys));
	kstrdup(&ossysname, sys);

	if(dflag == 0)
		termset();

	if(signal(SIGTERM, SIG_IGN) != SIG_IGN)
		signal(SIGTERM, cleanexit);
	if(signal(SIGINT, SIG_IGN) != SIG_IGN)
		signal(SIGINT, cleanexit);
	signal(SIGUSR2, trapUSR2);
	/* For the correct functioning of devcmd in the
	 * face of exiting slaves
	 */
	signal(SIGCLD, SIG_IGN);
	signal(SIGPIPE, SIG_IGN);
	memset(&act, 0 , sizeof(act));
	act.sa_handler=trapUSR1;
	sigaction(SIGUSR1, &act, nil);
	if(sflag == 0) {
		act.sa_handler=trapBUS;
		sigaction(SIGBUS, &act, nil);
		act.sa_handler=trapILL;
		sigaction(SIGILL, &act, nil);
		act.sa_handler=trapSEGV;
		sigaction(SIGSEGV, &act, nil);
	}

	if(usconfig(CONF_INITUSERS, 1000) < 0)
		panic("usconfig");

	Xup = (Proc**)PRDA->usr_prda.fill;
	up = newproc();

	pw = getpwuid(getuid());
	if(pw != nil) {
		if (strlen(pw->pw_name) + 1 <= KNAMELEN)
			strcpy(eve, pw->pw_name);
		else
			print("pw_name too long\n");
	}
	else
		print("cannot getpwuid\n");

	/* after setting up, since this takes locks */
	getnobody();
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
		fprint(2, "keyboard read error: %s\n", strerror(errno));
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

int
segflush(void *a, ulong n)
{
	cacheflush(a, n, BCACHE);
	return 0;
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
	static int tick;

	/*
	 * Posix-conforming CLK_TCK implementations tend to call sysconf,
	 * and we don't need the overhead.
	 */
	if(tick == 0)
		tick = CLK_TCK;
	sginap((tick*milsec)/1000);
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
	sginap(0);
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
	nice(2);
}
