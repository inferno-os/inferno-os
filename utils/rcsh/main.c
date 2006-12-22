#include "rc.h"

int	flag[256];
Io	*err;
char	*argv0;

Thread	*runq;
int	ndot;


void
main(int argc, char *argv[])
{
	int i;
	Code bootstrap[17];
	char *cflag, *cp;
	char rcmain[200];
	Var *infroot;
	char **p;

	cflag = 0;

	/* default to interactive mode */
	flag['i']++;

	/* hack for DOS-style options, when rcsh started from MS-land */
	for (p = argv+1; *p && **p == '/'; p++)
		**p = '-';

	argv0 = *argv;
	ARGBEGIN{
	default:
		fprint(2, "usage: %s: [-seiIlvxr] [-c string] [file [args]]\n", argv0);
		exits("usage");
	case 'e': flag['e']++; break;
	case 'c': cflag = ARGF(); break;
	case 'i': flag['i']++; break;
	case 'I': flag['i'] = 0; break;
	case 'l': flag['l']++; break;
	case 'r': flag['r']++; break;
	case 's': flag['s']++; break;
	case 'S': flag['S']++; break;		/* sub shell */
	case 'v': flag['v']++; break;
	case 'V': flag['V']++; break;
	case 'x': flag['x']++; break;
	}ARGEND

	err = openfd(2);

	kinit();
	vinit();

	cp = ROOT;
	if(0 && strlen(argv0))
		sprint(rcmain, "%s/../lib/rcmain", argv0);
	else{
		infroot = vlook("ROOT");
		if(infroot->val)
			cp = infroot->val->word;
	}
	sprint(rcmain, "%s/utils/lib/rcmain", cp);

	setvar("rcname", newword(argv0, 0));
	if(cflag)
		setvar("cflag", newword(cflag, 0));
	else
		setvar("cflag", 0);

	/* bootstrap == . rcmain $* */
	i=0;
	bootstrap[i++].i=1;
	bootstrap[i++].f=Xmark;
	bootstrap[i++].f=Xword;
	bootstrap[i++].s="*";
	bootstrap[i++].f=Xassign;
	bootstrap[i++].f=Xmark;
	bootstrap[i++].f=Xmark;
	bootstrap[i++].f=Xword;
	bootstrap[i++].s="*";
	bootstrap[i++].f=Xdol;
	bootstrap[i++].f=Xword;
	bootstrap[i++].s=rcmain;
	bootstrap[i++].f=Xword;
	bootstrap[i++].s=".";
	bootstrap[i++].f=Xsimple;
	bootstrap[i++].f=Xexit;
	bootstrap[i].i=0;
	start(bootstrap, 1, 0);
	pushlist();
	for(i=argc-1;i>=0;i--)
		pushword(argv[i]);

	for(;;){
		if(flag['r']) pfnc(err, runq);
		runq->pc++;
		(*runq->code[runq->pc-1].f)();
		if(ntrap.ref)
			dotrap();
	}
}

void
panic(char *s, int n)
{
	pfmt(err, "rc: ");
	pfmt(err, s, n);
	pchr(err, '\n');
	flush(err);
	pfmt(err, "aborting\n");
	flush(err);
	exits("aborting");
}

void
setstatus(char *s)
{
	setvar("status", newword(s, 0));
}

char *
getstatus(void)
{
	Var *status=vlook("status");

	return status->val?status->val->word:"";
}

int
truestatus(void)
{
	char *s;
	for(s=getstatus();*s;s++)
		if(*s!='|' && *s!='0') return 0;
	return 1;
}

char *
concstatus(char *s, char *t)
{
	static char v[NSTATUS+1];
	int n=strlen(s);
	strncpy(v, s, NSTATUS);
	if(n<NSTATUS){
		v[n]='|';
		strncpy(v+n+1, t, NSTATUS-n-1);
	}
	v[NSTATUS]='\0';
	return v;
}

/*
 * Start executing the given code at the given pc with the given redirection
 */
void
start(Code *c, int pc, Var *local)
{
	Thread *p = new(Thread);

	memset(p, 0, sizeof(Thread));
	p->code = codecopy(c);
	p->pc = pc;
	if(runq) {
		p->redir = runq->redir;
		p->startredir = runq->redir;
	}
	p->local = local;
	p->lineno = 1;
	p->ret = runq;
	runq=p;
}

void
execcmds(Io *f)
{
	static Code rdcmds[4];
	static int first=1;

	if(first){
		rdcmds[0].i=1;
		rdcmds[1].f=Xrdcmds;
		rdcmds[2].f=Xreturn;
		first=0;
	}
	start(rdcmds, 1, runq->local);
	runq->cmdfd=f;
	runq->iflast=0;
}

void
waitfor(uint pid)
{
	int e;
	char estr[64];

	e = procwait(pid);
	if(e != 0) {
		sprint(estr, "error code %d", e);
		setstatus(estr);
	} else
		setstatus("");
}

char **
procargv(char *s0, char *s1, char *s2, char *s3, Word *w)
{
	int n, i;
	Word *p;
	char **argv;

	for(p=w,n=5; p; p=p->next,n++);
		;
	
	argv = malloc(n*sizeof(char*));
	i = 0;
	if(s0)
		argv[i++] = s0;
	if(s1)
		argv[i++] = s1;
	if(s2)
		argv[i++] = s2;
	if(s3)
		argv[i++] = s3;
	for(p=w; p; p=p->next)
		argv[i++] = p->word;
	argv[i] = 0;
	return argv;
}

