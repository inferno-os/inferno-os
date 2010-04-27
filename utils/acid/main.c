/*#include <u.h>*/
#include <lib9.h>
#include <bio.h>
#include "mach.h"
#define Extern
#include "acid.h"
#include "y.tab.h"

char	*argv0;
char *acidlib;
static Biobuf	bioout;
static char	prog[128];
static char*	lm[16];
static int	nlm;
static char*	mtype;

static	int attachfiles(char*, int);
int	xfmt(Fmt*);
extern int	gfltconv(Fmt*), _ifmt(Fmt*);
int	isnumeric(char*);
void	die(void);

void
usage(void)
{
	fprint(2, "usage: acid [-l module] [-m machine] [-qrw] [-k] [-d flag] [-R tty] [pid] [file]\n");
	exits("usage");
}

void
main(int argc, char *argv[])
{
	Dir *db;
	Lsym *l;
	Node *n;
	char buf[128], *s;
	int pid, i;
	char *p;
	char afile[512];

	argv0 = argv[0];
	pid = 0;
	aout = "v.out";
	quiet = 1;
	/* turn off all debugging */
	protodebug = 0;

	mtype = 0;
	ARGBEGIN{
	case 'm':
		mtype = ARGF();
		break;
	case 'w':
		wtflag = 1;
		break;
	case 'l':
		s = ARGF();
		if(s == 0)
			usage();
		lm[nlm++] = s;
		break;
	case 'd':
		p = ARGF();
		if (p == 0)
			usage();
		while (*p) {
			setdbg_opt(*p, 0); /* don't print set message */
			p++;
		}
		break;
	case 'k':
		kernel++;
		break;
	case 'q':
		quiet = 0;
		break;
	case 'r':
		pid = 1;
		remote++;
		kernel++;
		break;
	case 'R':
		pid = 1;
		rdebug++;
		s = ARGF();
		if(s == 0)
			usage();
		remfd = opentty(s, 0);
		if(remfd < 0){
			fprint(2, "acid: can't open %s: %r\n", s);
			exits("open");
		}
		break;
	default:
		usage();
	}ARGEND

	if(argc > 0) {
		if(remote || rdebug)
			aout = argv[0];
		else
		if(isnumeric(argv[0])) {
			pid = atoi(argv[0]);
			sprint(prog, "/proc/%d/text", pid);
			aout = prog;
			if(argc > 1)
				aout = argv[1];
			else if(kernel)
				aout = mysystem();
		}
		else {
			if(kernel) {
				print("-k requires a pid");
				kernel = 0;
			}
			aout = argv[0];
		}
	} else if(rdebug)
		aout = "/386/bpc";
	else if(remote)
		aout = "/mips/bcarrera";

	fmtinstall('x', xfmt);
	fmtinstall('L', Lfmt);
	fmtinstall('f', gfltconv);
	fmtinstall('F', gfltconv);
	fmtinstall('g', gfltconv);
	fmtinstall('G', gfltconv);
	fmtinstall('e', gfltconv);
	fmtinstall('E', gfltconv);
	Binit(&bioout, 1, OWRITE);
	bout = &bioout;

	kinit();
	initialising = 1;
	pushfile(0);
	loadvars();
	installbuiltin();

	if(mtype && machbyname(mtype) == 0)
		print("unknown machine %s", mtype);

	if (attachfiles(aout, pid) < 0)
		varreg();		/* use default register set on error */

	acidlib = getenv("ACIDLIB");
	if(acidlib == nil){
		p = getenv("ROOT");
		if(p == nil)
			p = "/usr/inferno";
		snprint(afile, sizeof(afile)-1, "%s/lib/acid", p);
		acidlib = strdup(afile);
	}

	snprint(afile, sizeof(afile)-1, "%s/port", acidlib);
	loadmodule(afile);
	for(i = 0; i < nlm; i++) {
		if((db = dirstat(lm[i])) != nil) {
			free(db);
			loadmodule(lm[i]);
		} else {
			sprint(buf, "%s/%s", acidlib, lm[i]);
			loadmodule(buf);
		}
	}

	userinit();
	varsym();

	l = look("acidmap");
	if(l && l->proc) {
		n = an(ONAME, ZN, ZN);
		n->sym = l;
		n = an(OCALL, n, ZN);
		execute(n);
	}

	interactive = 1;
	initialising = 0;
	line = 1;

	setup_os_notify();

	for(;;) {
		if(setjmp(err)) {
			Binit(&bioout, 1, OWRITE);
			unwind();
		}
		stacked = 0;

		Bprint(bout, "acid: ");

		if(yyparse() != 1)
			die();
		restartio();

		unwind();
	}
	/* not reached */
}

static int
attachfiles(char *aout, int pid)
{
	interactive = 0;
	if(setjmp(err))
		return -1;

	if(aout) {				/* executable given */
		if(wtflag)
			text = open(aout, ORDWR);
		else
			text = open(aout, OREAD);

		if(text < 0)
			error("%s: can't open %s: %r\n", argv0, aout);
		readtext(aout);
	}
	if(pid)					/* pid given */
		sproc(pid);
	return 0;
}

void
die(void)
{
	Lsym *s;
	List *f;

	Bprint(bout, "\n");

	s = look("proclist");
	if(!rdebug && s && s->v->type == TLIST) {
		for(f = s->v->vstore.u0.sl; f; f = f->next)
			Bprint(bout, "echo kill > /proc/%d/ctl\n", (int)f->lstore.u0.sival);
	}
	exits(0);
}

void
userinit(void)
{
	Lsym *l;
	Node *n;
	char buf[512], *p;


	p = getenv("home");
	if(p == 0)
		p = getenv("HOME");
	if(p != 0) {
		snprint(buf, sizeof(buf)-1, "%s/lib/acid", p);
		silent = 1;
		loadmodule(buf);
	}

	if(rdebug){
		snprint(buf, sizeof(buf)-1, "%s/rdebug", acidlib);
		loadmodule(buf);
	}

	snprint(buf, sizeof(buf)-1, "%s/%s", acidlib, mach->name);
	loadmodule(buf);

	interactive = 0;
	if(setjmp(err)) {
		unwind();
		return;
	}
	l = look("acidinit");
	if(l && l->proc) {
		n = an(ONAME, ZN, ZN);
		n->sym = l;
		n = an(OCALL, n, ZN);
		execute(n);
	}
}

void
loadmodule(char *s)
{
	interactive = 0;
	if(setjmp(err)) {
		unwind();
		return;
	}
	pushfile(s);
	silent = 0;
	yyparse();
	popio();
	return;
}

void
readtext(char *s)
{
	Dir *d;
	Lsym *l;
	Value *v;
	Symbol sym;
	ulong length;
	extern Machdata mipsmach;

	if(mtype != 0){
		symmap = newmap(0, 1);
		if(symmap == 0)
			print("%s: (error) loadmap: cannot make symbol map\n", argv0);
		length = 1<<24;
		d = dirfstat(text);
		if(d != nil) {
			length = d->length;
			free(d);
		}
		setmap(symmap, text, 0, length, 0, "binary");
		free(d);
		return;
	}

	machdata = &mipsmach;

	if(!crackhdr(text, &fhdr)) {
		print("can't decode file header\n");
		return;
	}

	symmap = loadmap(0, text, &fhdr);
	if(symmap == 0)
		print("%s: (error) loadmap: cannot make symbol map\n", argv0);

	if(syminit(text, &fhdr) < 0) {
		print("%s: (error) syminit: %r\n", argv0);
		return;
	}
	print("%s:%s\n\n", s, fhdr.name);

	if(mach->sbreg && lookup(0, mach->sbreg, &sym)) {
		mach->sb = sym.value;
		l = enter("SB", Tid);
		l->v->vstore.fmt = 'X';
		l->v->vstore.u0.sival = mach->sb;
		l->v->type = TINT;
		l->v->set = 1;
	}

	l = mkvar("objtype");
	v = l->v;
	v->vstore.fmt = 's';
	v->set = 1;
	v->vstore.u0.sstring = strnode(mach->name);
	v->type = TSTRING;

	l = mkvar("textfile");
	v = l->v;
	v->vstore.fmt = 's';
	v->set = 1;
	v->vstore.u0.sstring = strnode(s);
	v->type = TSTRING;

	machbytype(fhdr.type);
	varreg();
}

Node*
an(int op, Node *l, Node *r)
{
	Node *n;

	n = gmalloc(sizeof(Node));
	n->ngc.gclink = gcl;
	gcl = &n->ngc;
	n->op = op;
	n->left = l;
	n->right = r;
	return n;
}

List*
al(int t)
{
	List *l;

	l = gmalloc(sizeof(List));
	l->type = t;
	l->lgc.gclink = gcl;
	gcl = &l->lgc;
	return l;
}

Node*
con(int v)
{
	Node *n;

	n = an(OCONST, ZN, ZN);
	n->nstore.u0.sival = v;
	n->nstore.fmt = 'X';
	n->type = TINT;
	return n;
}

void
fatal(char *fmt, ...)
{
	char buf[128];
	va_list arg;

	va_start(arg, fmt);
	vseprint(buf, buf+sizeof(buf), fmt, arg);
	va_end(arg);
	fprint(2, "%s: %L (fatal problem) %s\n", argv0, buf);
	exits(buf);
}

void
yyerror(char *fmt, ...)
{
	char buf[128];
	va_list arg;

	if(strcmp(fmt, "syntax error") == 0) {
		yyerror("syntax error, near symbol '%s'", symbol);
		return;
	}
	va_start(arg, fmt);
	vseprint(buf, buf+sizeof(buf), fmt, arg);
	va_end(arg);
	print("%L: %s\n", buf);
}

void
marktree(Node *n)
{

	if(n == 0)
		return;

	marktree(n->left);
	marktree(n->right);

	n->ngc.gcmark = 1;
	if(n->op != OCONST)
		return;

	switch(n->type) {
	case TSTRING:
		n->nstore.u0.sstring->sgc.gcmark = 1;
		break;
	case TLIST:
		marklist(n->nstore.u0.sl);
		break;
	case TCODE:
		marktree(n->nstore.u0.scc);
		break;
	}
}

void
marklist(List *l)
{
	while(l) {
		l->lgc.gcmark = 1;
		switch(l->type) {
		case TSTRING:
			l->lstore.u0.sstring->sgc.gcmark = 1;
			break;
		case TLIST:
			marklist(l->lstore.u0.sl);
			break;
		case TCODE:
			marktree(l->lstore.u0.scc);
			break;
		}
		l = l->next;
	}
}

void
gc(void)
{
	int i;
	Lsym *f;
	Value *v;
	Gc *m, **p, *next;

	if(dogc < Mempergc)
		return;
	dogc = 0;

	/* Mark */
	for(m = gcl; m; m = m->gclink)
		m->gcmark = 0;

	/* Scan */
	for(i = 0; i < Hashsize; i++) {
		for(f = hash[i]; f; f = f->hash) {
			marktree(f->proc);
			if(f->lexval != Tid)
				continue;
			for(v = f->v; v; v = v->pop) {
				switch(v->type) {
				case TSTRING:
					v->vstore.u0.sstring->sgc.gcmark = 1;
					break;
				case TLIST:
					marklist(v->vstore.u0.sl);
					break;
				case TCODE:
					marktree(v->vstore.u0.scc);
					break;
				}
			}
		}
	}

	/* Free */
	p = &gcl;
	for(m = gcl; m; m = next) {
		next = m->gclink;
		if(m->gcmark == 0) {
			*p = next;
			free(m);	/* Sleazy reliance on my malloc */
		}
		else
			p = &m->gclink;
	}
}

void*
gmalloc(long l)
{
	void *p;

	dogc += l;
	p = malloc(l);
	if(p == 0)
		fatal("out of memory");
	memset(p, 0, l);
	return p;
}

void
checkqid(int f1, int pid)
{
	int fd;
	Dir *d1, *d2;
	char buf[128];

	if(kernel || rdebug)
		return;

	d1 = dirfstat(f1);
	if(d1 == nil)
		fatal("checkqid: (qid not checked) dirfstat: %r");

	sprint(buf, "/proc/%d/text", pid);
	fd = open(buf, OREAD);
	if(fd < 0 || (d2 = dirfstat(fd)) == nil){
		fatal("checkqid: (qid not checked) dirstat %s: %r", buf);
		return;	/* not reached */
	}

	close(fd);

	if(d1->qid.path != d2->qid.path || d1->qid.vers != d2->qid.vers || d1->qid.type != d2->qid.type){
		print("path %llux %llux vers %lud %lud type %d %d\n",
			d1->qid.path, d2->qid.path, d1->qid.vers, d2->qid.vers, d1->qid.type, d2->qid.type);
		print("warning: image does not match text for pid %d\n", pid);
	}
	free(d1);
	free(d2);
}

char*
mysystem(void)
{
	char *cpu, *p, *q;
	static char kernel[128];

	cpu = getenv("cputype");
	if(cpu == 0) {
		cpu = "mips";
		print("$cputype not set; assuming %s\n", cpu);
	}
	p = getenv("terminal");
	if(p == 0 || (p=strchr(p, ' ')) == 0 || p[1] == ' ' || p[1] == 0) {
		p = "9power";
		print("missing or bad $terminal; assuming %s\n", p);
	}
	else{
		p++;
		q = strchr(p, ' ');
		if(q)
			*q = 0;
		sprint(kernel, "/%s/b%s", cpu, p);
	}
	return kernel;
}

int
isnumeric(char *s)
{
	while(*s) {
		if(*s < '0' || *s > '9')
			return 0;
		s++;
	}
	return 1;
}

int
xfmt(Fmt *f)
{
	f->flags ^= FmtSharp;
	return _ifmt(f);
}
