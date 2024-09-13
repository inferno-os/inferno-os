#include	<sys/types.h>
#include	<time.h>
#include	<termios.h>
#include	<signal.h>
#include	<ucontext.h>
#include 	<pwd.h>
#include	<sched.h>
#include	<sys/resource.h>
#include	<sys/wait.h>
#include	<sys/time.h>
#include	<errno.h>

#include	"dat.h"
#include	"fns.h"
#include	"error.h"

#include	"raise.h"

/* For dynamic linking init/fini code that needs malloc */
void (*coherence)(void) = nofence;


enum
{
	DELETE	= 0x7f,
	CTRLC	= 'C'-'@',
};
char *hosttype = "NetBSD";


extern int dflag;

int	gidnobody = -1;
int	uidnobody = -1;
static struct 	termios tinit;

static void
sysfault(char *what, void *addr, const ucontext_t *uc)
{
	char buf[64];

	if (uc)
		snprint(buf, sizeof(buf), "sys: %s%#p pc=%#p", what, addr,
			_UC_MACHINE_PC(uc));
	else
		snprint(buf, sizeof(buf), "sys: %s%#p", what, addr);
	disfault(nil, buf);
}

static void
trapILL(int signo, siginfo_t *si, void *ctx)
{
	USED(signo);
	USED(ctx);
	sysfault("illegal instruction pc=", si->si_addr, NULL);
}

static int
isnilref(siginfo_t *si)
{
	return si != 0 && (si->si_addr == (void*)~(uintptr_t)0 || (uintptr_t)si->si_addr < 512);
}

static void
trapmemref(int signo, siginfo_t *si, void *ctx)
{
	if(isnilref(si))
		disfault(nil, exNilref);
	else if(signo == SIGBUS)
		sysfault("bad address addr=", si->si_addr, ctx); /* eg, misaligned */
	else
		sysfault("segmentation violation addr=", si->si_addr, ctx);
}

static void
trapFPE(int signo, siginfo_t *si, void *ctx)
{
	char buf[64];

	USED(signo);
	USED(ctx);
	snprint(buf, sizeof(buf), "sys: fp: exception status=%.4lux pc=%#p", getfsr(), si->si_addr);
	USED(buf);
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
	struct passwd *pw;
	Proc *p;
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

	memset(&act, 0, sizeof(act));
	act.sa_handler = trapUSR1;
	sigaction(SIGUSR1, &act, nil);

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

		act.sa_flags = 0;
	}

	p = newproc();
	kprocinit(p);

	pw = getpwuid(getuid());
	if(pw != nil)
		kstrdup(&eve, pw->pw_name);
	else
		print("cannot getpwuid\n");

	p->env->uid = getuid();
	p->env->gid = getgid();

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
