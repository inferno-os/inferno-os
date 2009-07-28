#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	"interp.h"
#include	"kernel.h"
#include	"draw.h"
#include	"version.h"

int		rebootargc = 0;
char**		rebootargv;
static	char	*imod = "/dis/emuinit.dis";
extern	char*	hosttype;
char*	tkfont;	/* for libtk/utils.c */
int	tkstylus;	/* libinterp/tk.c */
extern	int	mflag;
	int	dflag;
	int vflag;
	int	vflag;
	Procs	procs;
	char	*eve;
	int	Xsize	= 640;
	int	Ysize	= 480;
	int	bflag = 1;
	int	sflag;
	int	qflag;
	int	xtblbit;
	ulong	displaychan;
char *cputype;

static void
usage(void)
{
	fprint(2, "Usage: emu [options...] [file.dis [args...]]\n"
		"\t-gXxY\n"
		"\t-c[0-9]\n"
		"\t-d file.dis\n"
		"\t-s\n"
		"\t-v\n"
		"\t-p<poolname>=maxsize\n"
		"\t-f<fontpath>\n"
		"\t-r<rootpath>\n"
		"\t-7\n"
		"\t-B\n"
		"\t-C<channel string>\n"
		"\t-S\n");

	exits("usage");
}

static void
envusage(void)
{
	fprint(2, "emu: bad option in EMU environment variable (%s)\n", getenv("EMU"));
	usage();
}

static int
isnum(char *p)
{
	if (*p == 0) return 0;
	while (*p) {
		if (*p < '0' || *p > '9') return 0;
		p++;
	}
	return 1;
}

static int
geom(char *val)
{
	char *p;
	int x, y;
	if (val == '\0' || (*val < '0' || *val > '9')) 
		return 0;
	x = strtoul(val, &p, 0);
	if(x >= 64) 
		Xsize = x;
	if (*p++ != 'x' || !isnum(p))
		return 0;
	y = strtoul(p, &p, 0);
	if(y >= 48)
		Ysize = y;
	if (*p != '\0') return 0;
	return 1;
}

static void
poolopt(char *str)
{
	char *var;
	int n;
	ulong x;

	var = str;
	while(*str && *str != '=')
		str++;
	if(*str != '=' || str[1] == '\0')
		usage();
	*str++ = '\0';
	n = strlen(str);
	x = atoi(str);
	switch(str[n - 1]){
	case 'k':
	case 'K':
		x *= 1024;
		break;
	case 'm':
	case 'M':
		x *= 1024*1024;
		break;
	}
	if(poolsetsize(var, x) == 0)
		usage();
}

static void
option(int argc, char *argv[], void (*badusage)(void))
{
	char *cp;

	ARGBEGIN {
	default:
		badusage();
	case 'g':		/* Window geometry */
		if (geom(EARGF(badusage())) == 0)
			badusage();
		break;
	case 'b':		/* jit array bounds checking (obsolete, now on by default) */
		break;
	case 'B':		/* suppress jit array bounds checks */
		bflag = 0;
		break;
	case 'c':		/* Compile on the fly */
		cp = EARGF(badusage());
		if (!isnum(cp))
			badusage();
		cflag = atoi(cp);
		if(cflag < 0|| cflag > 9)
			usage();
		break;
	case 'I':	/* (temporary option) run without cons */
		dflag++;
		break;
	case 'd':		/* run as a daemon */
		dflag++;
		imod = EARGF(badusage());
		break;
	case 's':		/* No trap handling */
		sflag++;
		break;
	case 'm':		/* gc mark and sweep */
		cp = EARGF(badusage());
		if (!isnum(cp))
			badusage();
		mflag = atoi(cp);
		if(mflag < 0|| mflag > 9)
			usage();
		break;
	case 'p':		/* pool option */
		poolopt(EARGF(badusage()));
		break;
	case 'f':		/* Set font path */
		tkfont = EARGF(badusage());
		break;
	case 'r':		/* Set inferno root */
		strecpy(rootdir, rootdir+sizeof(rootdir), EARGF(badusage()));
		break;
	case '7':		/* use 7 bit colormap in X */
		xtblbit = 1;
		break;
	case 'G':		/* allow global access to file system (obsolete) */
		break;
	case	'C':		/* channel specification for display */
		cp = EARGF(badusage());
		displaychan = strtochan(cp);
		if(displaychan == 0){
			fprint(2, "emu: invalid channel specifier (-C): %q\n", cp);
			exits("usage");
		}
		break;
	case 'S':
		tkstylus = 1;
		break;
	case 'v':
		vflag = 1;	/* print startup messages */
		break;
	} ARGEND
}

static void
savestartup(int argc, char *argv[])
{
	int i;

	rebootargc = argc;
	rebootargv = malloc((argc+1)*sizeof(char*));
	if(rebootargv == nil)
		panic("can't save startup args");
	for(i = 0; i < argc; i++) {
		rebootargv[i] = strdup(argv[i]);
		if(rebootargv[i] == nil)
			panic("can't save startup args");
	}
	rebootargv[i] = nil;
}

void
putenvq(char *name, char *val, int conf)
{
	val = smprint("%q", val);
	ksetenv(name, val, conf);
	free(val);
}

void
putenvqv(char *name, char **v, int n, int conf)
{
	Fmt f;
	int i;
	char *val;

	fmtstrinit(&f);
	for(i=0; i<n; i++)
		fmtprint(&f, "%s%q", i?" ":"", v[i]);
	val = fmtstrflush(&f);
	ksetenv(name, val, conf);
	free(val);
}

void
main(int argc, char *argv[])
{
	char *opt, *p;
	char *enva[20];
	int envc;

	quotefmtinstall();
	savestartup(argc, argv);
	/* set default root now, so either $EMU or -r can override it later */
	if((p = getenv("INFERNO")) != nil || (p = getenv("ROOT")) != nil)
		strecpy(rootdir, rootdir+sizeof(rootdir), p);
	opt = getenv("EMU");
	if(opt != nil && *opt != '\0') {
		enva[0] = "emu";
		envc = tokenize(opt, &enva[1], sizeof(enva)-1) + 1;
		enva[envc] = 0;
		option(envc, enva, envusage);
	}
	option(argc, argv, usage);
	eve = strdup("inferno");

	opt = "interp";
	if(cflag)
		opt = "compile";

	if(vflag)
		print("Inferno %s main (pid=%d) %s\n", VERSION, getpid(), opt);

	libinit(imod);
}

void
emuinit(void *imod)
{
	Osenv *e;
	char *wdir;

	e = up->env;
	e->pgrp = newpgrp();
	e->fgrp = newfgrp(nil);
	e->egrp = newegrp();
	e->errstr = e->errbuf0;
	e->syserrstr = e->errbuf1;
	e->user = strdup("");

	links();
	chandevinit();

	if(waserror())
		panic("setting root and dot");

	e->pgrp->slash = namec("#/", Atodir, 0, 0);
	cnameclose(e->pgrp->slash->name);
	e->pgrp->slash->name = newcname("/");
	e->pgrp->dot = cclone(e->pgrp->slash);
	poperror();

	strcpy(up->text, "main");

	if(kopen("#c/cons", OREAD) != 0)
		fprint(2, "failed to make fd0 from #c/cons: %r\n");
	kopen("#c/cons", OWRITE);
	kopen("#c/cons", OWRITE);

	/* the setid cannot precede the bind of #U */
	kbind("#U", "/", MAFTER|MCREATE);
	setid(eve, 0);
	kbind("#^", "/dev", MBEFORE);	/* snarf */
	kbind("#^", "/chan", MBEFORE);
	kbind("#m", "/dev", MBEFORE);	/* pointer */
	kbind("#c", "/dev", MBEFORE);
	kbind("#p", "/prog", MREPL);
	kbind("#d", "/fd", MREPL);
	kbind("#I", "/net", MAFTER);	/* will fail on Plan 9 */

	/* BUG: we actually only need to do these on Plan 9 */
	kbind("#U/dev", "/dev", MAFTER);
	kbind("#U/net", "/net", MAFTER);
	kbind("#U/net.alt", "/net.alt", MAFTER);

	if(cputype != nil)
		ksetenv("cputype", cputype, 1);
	putenvqv("emuargs", rebootargv, rebootargc, 1);
	putenvq("emuroot", rootdir, 1);
	ksetenv("emuhost", hosttype, 1);
	wdir = malloc(1024);
	if(wdir != nil){
		if(getwd(wdir, 1024) != nil)
			putenvq("emuwdir", wdir, 1);
		free(wdir);
	}

	kproc("main", disinit, imod, KPDUPFDG|KPDUPPG|KPDUPENVG);

	for(;;)
		ospause(); 
}

void
errorf(char *fmt, ...)
{
	va_list arg;
	char buf[PRINTSIZE];

	va_start(arg, fmt);
	vseprint(buf, buf+sizeof(buf), fmt, arg);
	va_end(arg);
	error(buf);
}

void
error(char *err)
{
	if(err != up->env->errstr && up->env->errstr != nil)
		kstrcpy(up->env->errstr, err, ERRMAX);
//	ossetjmp(up->estack[NERR-1]);
	nexterror();
}

void
exhausted(char *resource)
{
	char buf[64];
	int n;

	n = snprint(buf, sizeof(buf), "no free %s\n", resource);
	iprint(buf);
	buf[n-1] = 0;
	error(buf);
}

void
nexterror(void)
{
	oslongjmp(nil, up->estack[--up->nerr], 1);
}

/* for dynamic modules - functions not macros */

void*
waserr(void)
{
	up->nerr++;
	return up->estack[up->nerr-1];
}

void
poperr(void)
{
	up->nerr--;
}

char*
enverror(void)
{
	return up->env->errstr;
}

void
panic(char *fmt, ...)
{
	va_list arg;
	char buf[512];

	va_start(arg, fmt);
	vseprint(buf, buf+sizeof(buf), fmt, arg);
	va_end(arg);
	fprint(2, "panic: %s\n", buf);
	if(sflag)
		abort();

	cleanexit(0);
}

int
iprint(char *fmt, ...)
{

	int n;	
	va_list va;
	char buf[1024];

	va_start(va, fmt);
	n = vseprint(buf, buf+sizeof buf, fmt, va) - buf;
	va_end(va);

	write(1, buf, n);
	return 1;
}

void
_assert(char *fmt)
{
	panic("assert failed: %s", fmt);
}

/*
 * mainly for libmp
 */
void
sysfatal(char *fmt, ...)
{
	va_list arg;
	char buf[64];

	va_start(arg, fmt);
	vsnprint(buf, sizeof(buf), fmt, arg);
	va_end(arg);
	error(buf);
}

void
oserror(void)
{
	oserrstr(up->env->errstr, ERRMAX);
	error(up->env->errstr);
}
