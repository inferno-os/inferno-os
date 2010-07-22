#include <lib9.h>
#include <bio.h>
#include <ctype.h>
#include "mach.h"
#include "regexp.h"
#define Extern extern
#include "acid.h"
#include "y.tab.h"

void	cvtatof(Node*, Node*);
void	cvtatoi(Node*, Node*);
void	cvtitoa(Node*, Node*);
void	bprint(Node*, Node*);
void	funcbound(Node*, Node*);
void	printto(Node*, Node*);
void	getfile(Node*, Node*);
void	fmt(Node*, Node*);
void	pcfile(Node*, Node*);
void	pcline(Node*, Node*);
void	setproc(Node*, Node*);
void	strace(Node*, Node*);
void	follow(Node*, Node*);
void	reason(Node*, Node*);
void	newproc(Node*, Node*);
void	startstop(Node*, Node*);
void	match(Node*, Node*);
void	status(Node*, Node*);
void	dokill(Node*,Node*);
void	waitstop(Node*, Node*);
void	stop(Node*, Node*);
void	start(Node*, Node*);
void	filepc(Node*, Node*);
void	doerror(Node*, Node*);
void	rc(Node*, Node*);
void	doaccess(Node*, Node*);
void	map(Node*, Node*);
void	readfile(Node*, Node*);
void	interpret(Node*, Node*);
void	include(Node*, Node*);
void	regexp(Node*, Node*);
void	_bpcondset(Node*, Node*);
void	_bpconddel(Node*, Node*);
void	setdebug(Node*, Node*);

typedef struct Btab Btab;
struct Btab
{
	char	*name;
	void	(*fn)(Node*, Node*);
} tab[] =
{
	"atof",		cvtatof,
	"atoi",		cvtatoi,
	"error",	doerror,
	"file",		getfile,
	"readfile",	readfile,
	"access",	doaccess,
	"filepc",	filepc,
	"fnbound",	funcbound,
	"fmt",		fmt,
	"follow",	follow,
	"itoa",		cvtitoa,
	"kill",		dokill,
	"match",	match,
	"newproc",	newproc,
	"pcfile",	pcfile,
	"pcline",	pcline,
	"print",	bprint,
	"printto",	printto,
	"rc",		rc,
	"reason",	reason,
	"setproc",	setproc,
	"sh",		rc,
	"start",	start,
	"startstop",	startstop,
	"status",	status,
	"stop",		stop,
	"strace",	strace,
	"waitstop",	waitstop,
	"map",		map,
	"interpret",	interpret,
	"include",	include,
	"regexp",	regexp,
	"debug",	setdebug,
	"_bpcondset",	_bpcondset,
	"_bpconddel",	_bpconddel,
	0
};

void
mkprint(Lsym *s)
{
	prnt = gmalloc(sizeof(Node));
	prnt->op = OCALL;
	prnt->left = gmalloc(sizeof(Node));
	prnt->left->sym = s;
}

void
installbuiltin(void)
{
	Btab *b;
	Lsym *s;

	b = tab;
	while(b->name) {
		s = look(b->name);
		if(s == 0)
			s = enter(b->name, Tid);

		s->builtin = b->fn;
		if(b->fn == bprint)
			mkprint(s);
		b++;
	}
}

void
match(Node *r, Node *args)
{
	int i;
	List *f;
	Node *av[Maxarg];
	Node resi, resl;

	na = 0;
	flatten(av, args);
	if(na != 2)
		error("match(obj, list): arg count");

	expr(av[1], &resl);
	if(resl.type != TLIST)
		error("match(obj, list): need list");
	expr(av[0], &resi);

	r->op = OCONST;
	r->type = TINT;
	r->nstore.fmt = 'D';
	r->nstore.u0.sival = -1;

	i = 0;
	for(f = resl.nstore.u0.sl; f; f = f->next) {
		if(resi.type == f->type) {
			switch(resi.type) {
			case TINT:
				if(resi.nstore.u0.sival == f->lstore.u0.sival) {
					r->nstore.u0.sival = i;
					return;
				}
				break;
			case TFLOAT:
				if(resi.nstore.u0.sfval == f->lstore.u0.sfval) {
					r->nstore.u0.sival = i;
					return;
				}
				break;
			case TSTRING:
				if(scmp(resi.nstore.u0.sstring, f->lstore.u0.sstring)) {
					r->nstore.u0.sival = i;
					return;
				}
				break;
			case TLIST:
				error("match(obj, list): not defined for list");
			}
		}
		i++;
	}
}

void
newproc(Node *r, Node *args)
{
	int i;
	Node res;
	char *p, *e;
	char *argv[Maxarg], buf[Strsize];

	i = 1;
	argv[0] = aout;

	if(args) {
		expr(args, &res);
		if(res.type != TSTRING)
			error("newproc(): arg not string");
		if(res.nstore.u0.sstring->len >= sizeof(buf))
			error("newproc(): too many arguments");
		memmove(buf, res.nstore.u0.sstring->string, res.nstore.u0.sstring->len);
		buf[res.nstore.u0.sstring->len] = '\0';
		p = buf;
		e = buf+res.nstore.u0.sstring->len;
		for(;;) {
			while(p < e && (*p == '\t' || *p == ' '))
				*p++ = '\0';
			if(p >= e)
				break;
			argv[i++] = p;
			if(i >= Maxarg)
				error("newproc: too many arguments");
			while(p < e && *p != '\t' && *p != ' ')
				p++;
		}
	}
	argv[i] = 0;
	r->op = OCONST;
	r->type = TINT;
	r->nstore.fmt = 'D';
	r->nstore.u0.sival = nproc(argv);
}
void
startstop(Node *r, Node *args)
{
	Node res;

	if(args == 0)
		error("startstop(pid): no pid");
	expr(args, &res);
	if(res.type != TINT)
		error("startstop(pid): arg type");
	if(rdebug) {
		Lsym *s;
		r->op = OCONST;
		r->type = TINT;
		r->nstore.u0.sival = remcondstartstop(res.nstore.u0.sival);
		r->nstore.fmt = 'D';

		s = look("_breakid");
		if(s)
			s->v->vstore.u0.sival = (int)r->nstore.u0.sival;
	} else
		msg(res.nstore.u0.sival, "startstop");
	notes(res.nstore.u0.sival);
	dostop(res.nstore.u0.sival);
}

void
waitstop(Node *r, Node *args)
{
	Node res;

	USED(r);
	if(args == 0)
		error("waitstop(pid): no pid");
	expr(args, &res);
	if(res.type != TINT)
		error("waitstop(pid): arg type");

	Bflush(bout);
	msg(res.nstore.u0.sival, "waitstop");
	notes(res.nstore.u0.sival);
	dostop(res.nstore.u0.sival);
}

void
start(Node *r, Node *args)
{
	Node res;

	USED(r);
	if(args == 0)
		error("start(pid): no pid");
	expr(args, &res);
	if(res.type != TINT)
		error("start(pid): arg type");

	msg(res.nstore.u0.sival, "start");
}

void
stop(Node *r, Node *args)
{
	Node res;

	USED(r);
	if(args == 0)
		error("stop(pid): no pid");
	expr(args, &res);
	if(res.type != TINT)
		error("stop(pid): arg type");

	Bflush(bout);
	msg(res.nstore.u0.sival, "stop");
	notes(res.nstore.u0.sival);
	dostop(res.nstore.u0.sival);
}

void
dokill(Node *r, Node *args)
{
	Node res;

	USED(r);
	if(args == 0)
		error("kill(pid): no pid");
	expr(args, &res);
	if(res.type != TINT)
		error("kill(pid): arg type");

	msg(res.nstore.u0.sival, "kill");
	deinstall(res.nstore.u0.sival);
}

void
status(Node *r, Node *args)
{
	Node res;
	char *p;

	USED(r);
	if(args == 0)
		error("status(pid): no pid");
	expr(args, &res);
	if(res.type != TINT)
		error("status(pid): arg type");

	p = getstatus(res.nstore.u0.sival);
	r->nstore.u0.sstring = strnode(p);
	r->op = OCONST;
	r->nstore.fmt = 's';
	r->type = TSTRING;
}

void
reason(Node *r, Node *args)
{
	Node res;

	if(args == 0)
		error("reason(cause): no cause");
	expr(args, &res);
	if(res.type != TINT)
		error("reason(cause): arg type");

	r->op = OCONST;
	r->type = TSTRING;
	r->nstore.fmt = 's';
	r->nstore.u0.sstring = strnode((*machdata->excep)(cormap, rget));
}

void
follow(Node *r, Node *args)
{
	int n, i;
	Node res;
	uvlong f[10];
	List **tail, *l;

	if(args == 0)
		error("follow(addr): no addr");
	expr(args, &res);
	if(res.type != TINT)
		error("follow(addr): arg type");

	n = (*machdata->foll)(cormap, res.nstore.u0.sival, rget, f);
	if (n < 0)
		error("follow(addr): %r");
	tail = &r->nstore.u0.sl;
	for(i = 0; i < n; i++) {
		l = al(TINT);
		l->lstore.u0.sival = f[i];
		l->lstore.fmt = 'X';
		*tail = l;
		tail = &l->next;
	}
}

void
funcbound(Node *r, Node *args)
{
	int n;
	Node res;
	uvlong bounds[2];
	List *l;

	if(args == 0)
		error("fnbound(addr): no addr");
	expr(args, &res);
	if(res.type != TINT)
		error("fnbound(addr): arg type");

	n = fnbound(res.nstore.u0.sival, bounds);
	if (n != 0) {
		r->nstore.u0.sl = al(TINT);
		l = r->nstore.u0.sl;
		l->lstore.u0.sival = bounds[0];
		l->lstore.fmt = 'X';
		l->next = al(TINT);
		l = l->next;
		l->lstore.u0.sival = bounds[1];
		l->lstore.fmt = 'X';
	}
}

void
setproc(Node *r, Node *args)
{
	Node res;

	USED(r);
	if(args == 0)
		error("setproc(pid): no pid");
	expr(args, &res);
	if(res.type != TINT)
		error("setproc(pid): arg type");

	sproc(res.nstore.u0.sival);
}

void
filepc(Node *r, Node *args)
{
	Node res;
	char *p, c;

	if(args == 0)
		error("filepc(filename:line): arg count");
	expr(args, &res);
	if(res.type != TSTRING)
		error("filepc(filename:line): arg type");

	p = strchr(res.nstore.u0.sstring->string, ':');
	if(p == 0)
		error("filepc(filename:line): bad arg format");

	c = *p;
	*p++ = '\0';
	r->nstore.u0.sival = file2pc(res.nstore.u0.sstring->string, atoi(p));
	p[-1] = c;
	if(r->nstore.u0.sival == -1)
		error("filepc(filename:line): can't find address");

	r->op = OCONST;
	r->type = TINT;
	r->nstore.fmt = 'D';
}

void
interpret(Node *r, Node *args)
{
	Node res;
	int isave;

	if(args == 0)
		error("interpret(string): arg count");
	expr(args, &res);
	if(res.type != TSTRING)
		error("interpret(string): arg type");

	pushstr(&res);

	isave = interactive;
	interactive = 0;
	r->nstore.u0.sival = yyparse();
	interactive = isave;
	popio();
	r->op = OCONST;
	r->type = TINT;
	r->nstore.fmt = 'D';
}

void
include(Node *r, Node *args)
{
	Node res;
	int isave;

	if(args == 0)
		error("include(string): arg count");
	expr(args, &res);
	if(res.type != TSTRING)
		error("include(string): arg type");

	pushfile(res.nstore.u0.sstring->string);

	isave = interactive;
	interactive = 0;
	r->nstore.u0.sival = yyparse();
	interactive = isave;
	popio();
	r->op = OCONST;
	r->type = TINT;
	r->nstore.fmt = 'D';
}

void
rc(Node *r, Node *args)
{
	Node res;

	char *p, *q;

	USED(r);
	if(args == 0)
		error("error(string): arg count");
	expr(args, &res);
	if(res.type != TSTRING)
		error("error(string): arg type");

	p = runcmd(res.nstore.u0.sstring->string);
	q = strrchr(p, ':');
	if (q)
		p = q+1;

	r->op = OCONST;
	r->type = TSTRING;
	r->nstore.u0.sstring = strnode(p);
	r->nstore.fmt = 's';
}

void
doerror(Node *r, Node *args)
{
	Node res;

	USED(r);
	if(args == 0)
		error("error(string): arg count");
	expr(args, &res);
	if(res.type != TSTRING)
		error("error(string): arg type");

	error(res.nstore.u0.sstring->string);
}

void
doaccess(Node *r, Node *args)
{
	Node res;

	if(args == 0)
		error("access(filename): arg count");
	expr(args, &res);
	if(res.type != TSTRING)
		error("access(filename): arg type");

	r->op = OCONST;
	r->type = TINT;
	r->nstore.u0.sival = 0;		
	if(access(res.nstore.u0.sstring->string, OREAD) == 0)
		r->nstore.u0.sival = 1;
}

void
readfile(Node *r, Node *args)
{
	Node res;
	int n, fd;
	char *buf;
	Dir *db;

	if(args == 0)
		error("readfile(filename): arg count");
	expr(args, &res);
	if(res.type != TSTRING)
		error("readfile(filename): arg type");

	fd = open(res.nstore.u0.sstring->string, OREAD);
	if(fd < 0)
		return;

	db = dirfstat(fd);
	if(db == nil || db->length == 0)
		n = 8192;
	else
		n = db->length;
	free(db);

	buf = gmalloc(n);
	n = read(fd, buf, n);

	if(n > 0) {
		r->op = OCONST;
		r->type = TSTRING;
		r->nstore.u0.sstring = strnodlen(buf, n);
		r->nstore.fmt = 's';
	}
	free(buf);
	close(fd);
}

void
getfile(Node *r, Node *args)
{
	int n;
	char *p;
	Node res;
	String *s;
	Biobuf *bp;
	List **l, *new;

	if(args == 0)
		error("file(filename): arg count");
	expr(args, &res);
	if(res.type != TSTRING)
		error("file(filename): arg type");

	r->op = OCONST;
	r->type = TLIST;
	r->nstore.u0.sl = 0;

	p = res.nstore.u0.sstring->string;
	bp = Bopen(p, OREAD);
	if(bp == 0)
		return;

	l = &r->nstore.u0.sl;
	for(;;) {
		p = Brdline(bp, '\n');
		n = BLINELEN(bp);
		if(p == 0) {
			if(n == 0)
				break;
			s = strnodlen(0, n);
			Bread(bp, s->string, n);
		}
		else
			s = strnodlen(p, n-1);

		new = al(TSTRING);
		new->lstore.u0.sstring = s;
		new->lstore.fmt = 's';
		*l = new;
		l = &new->next;
	}
	Bterm(bp);
}

void
cvtatof(Node *r, Node *args)
{
	Node res;

	if(args == 0)
		error("atof(string): arg count");
	expr(args, &res);
	if(res.type != TSTRING)
		error("atof(string): arg type");

	r->op = OCONST;
	r->type = TFLOAT;
	r->nstore.u0.sfval = atof(res.nstore.u0.sstring->string);
	r->nstore.fmt = 'f';
}

void
cvtatoi(Node *r, Node *args)
{
	Node res;

	if(args == 0)
		error("atoi(string): arg count");
	expr(args, &res);
	if(res.type != TSTRING)
		error("atoi(string): arg type");

	r->op = OCONST;
	r->type = TINT;
	r->nstore.u0.sival = strtoul(res.nstore.u0.sstring->string, 0, 0);
	r->nstore.fmt = 'D';
}

void
cvtitoa(Node *r, Node *args)
{
	Node res;
	char buf[128];

	if(args == 0)
		error("itoa(integer): arg count");
	expr(args, &res);
	if(res.type != TINT)
		error("itoa(integer): arg type");

	sprint(buf, "%d", (int)res.nstore.u0.sival);
	r->op = OCONST;
	r->type = TSTRING;
	r->nstore.u0.sstring = strnode(buf);
	r->nstore.fmt = 's';
}

List*
mapent(Map *m)
{
	int i;
	List *l, *n, **t, *h;

	h = 0;
	t = &h;
	for(i = 0; i < m->nsegs; i++) {
		if(m->seg[i].inuse == 0)
			continue;
		l = al(TSTRING);
		n = al(TLIST);
		n->lstore.u0.sl = l;
		*t = n;
		t = &n->next;
		l->lstore.u0.sstring = strnode(m->seg[i].name);
		l->lstore.fmt = 's';
		l->next = al(TINT);
		l = l->next;
		l->lstore.u0.sival = m->seg[i].b;
		l->lstore.fmt = 'X';
		l->next = al(TINT);
		l = l->next;
		l->lstore.u0.sival = m->seg[i].e;
		l->lstore.fmt = 'X';
		l->next = al(TINT);
		l = l->next;
		l->lstore.u0.sival = m->seg[i].f;
		l->lstore.fmt = 'X';
	}
	return h;
}

void
map(Node *r, Node *args)
{
	int i;
	Map *m;
	List *l;
	char *ent;
	Node *av[Maxarg], res;

	na = 0;
	flatten(av, args);

	if(na != 0) {
		expr(av[0], &res);
		if(res.type != TLIST)
			error("map(list): map needs a list");
		if(listlen(res.nstore.u0.sl) != 4)
			error("map(list): list must have 4 entries");

		l = res.nstore.u0.sl;
		if(l->type != TSTRING)
			error("map name must be a string");
		ent = l->lstore.u0.sstring->string;
		m = symmap;
		i = findseg(m, ent);
		if(i < 0) {
			m = cormap;
			i = findseg(m, ent);
		}
		if(i < 0)
			error("%s is not a map entry", ent);	
		l = l->next;
		if(l->type != TINT)
			error("map entry not int");
		m->seg[i].b = l->lstore.u0.sival;
		if (strcmp(ent, "text") == 0)
			textseg(l->lstore.u0.sival, &fhdr);
		l = l->next;
		if(l->type != TINT)
			error("map entry not int");
		m->seg[i].e = l->lstore.u0.sival;
		l = l->next;
		if(l->type != TINT)
			error("map entry not int");
		m->seg[i].f = l->lstore.u0.sival;
	}

	r->type = TLIST;
	r->nstore.u0.sl = 0;
	if(symmap)
		r->nstore.u0.sl = mapent(symmap);
	if(cormap) {
		if(r->nstore.u0.sl == 0)
			r->nstore.u0.sl = mapent(cormap);
		else {
			for(l = r->nstore.u0.sl; l->next; l = l->next)
				;
			l->next = mapent(cormap);
		}
	}
}

void 
flatten(Node **av, Node *n)
{
	if(n == 0)
		return;

	switch(n->op) {
	case OLIST:
		flatten(av, n->left);
		flatten(av, n->right);
		break;
	default:
		av[na++] = n;
		if(na >= Maxarg)
			error("too many function arguments");
		break;
	}
}

void
strace(Node *r, Node *args)
{
	Node *av[Maxarg], *n, res;
	ulong pc, sp;

	na = 0;
	flatten(av, args);
	if(na != 3)
		error("strace(pc, sp, link): arg count");

	n = av[0];
	expr(n, &res);
	if(res.type != TINT)
		error("strace(pc, sp, link): pc bad type");
	pc = res.nstore.u0.sival;

	n = av[1];
	expr(n, &res);
	if(res.type != TINT)
		error("strace(pc, sp, link): sp bad type");
	sp = res.nstore.u0.sival;

	n = av[2];
	expr(n, &res);
	if(res.type != TINT)
		error("strace(pc, sp, link): link bad type");

	tracelist = 0;
	if ((*machdata->ctrace)(cormap, pc, sp, res.nstore.u0.sival, trlist) <= 0)
		error("no stack frame");
	r->type = TLIST;
	r->nstore.u0.sl = tracelist;
}

void
regerror(char *msg)
{
	error(msg);
}

void
regexp(Node *r, Node *args)
{
	Node res;
	Reprog *rp;
	Node *av[Maxarg];

	na = 0;
	flatten(av, args);
	if(na != 2)
		error("regexp(pattern, string): arg count");
	expr(av[0], &res);
	if(res.type != TSTRING)
		error("regexp(pattern, string): pattern must be string");
	rp = regcomp(res.nstore.u0.sstring->string);
	if(rp == 0)
		return;

	expr(av[1], &res);
	if(res.type != TSTRING)
		error("regexp(pattern, string): bad string");

	r->nstore.fmt = 'D';
	r->type = TINT;
	r->nstore.u0.sival = regexec(rp, res.nstore.u0.sstring->string, 0, 0);
	free(rp);
}

char vfmt[] = "aBbcCdDfFgGiIoOqQrRsuUVxXYZ";

void
fmt(Node *r, Node *args)
{
	Node res;
	Node *av[Maxarg];

	na = 0;
	flatten(av, args);
	if(na != 2)
		error("fmt(obj, fmt): arg count");
	expr(av[1], &res);
	if(res.type != TINT || strchr(vfmt, res.nstore.u0.sival) == 0)
		error("fmt(obj, fmt): bad format '%c'", (char)res.nstore.u0.sival);
	expr(av[0], r);
	r->nstore.fmt = res.nstore.u0.sival;
}

void
patom(char type, Store *res)
{
	int i;
	char buf[512];
	extern char *typenames[];

	switch(res->fmt) {
	case 'c':
		Bprint(bout, "%c", (int)res->u0.sival);
		break;
	case 'C':
		if(res->u0.sival < ' ' || res->u0.sival >= 0x7f)
			Bprint(bout, "%3d", (int)res->u0.sival&0xff);
		else
			Bprint(bout, "%3c", (int)res->u0.sival);
		break;
	case 'r':
		Bprint(bout, "%C", (int)res->u0.sival);
		break;
	case 'B':
		memset(buf, '0', 34);
		buf[1] = 'b';
		for(i = 0; i < 32; i++) {
			if(res->u0.sival & (1<<i))
				buf[33-i] = '1';
		}
		buf[35] = '\0';
		Bprint(bout, "%s", buf);
		break;
	case 'b':
		Bprint(bout, "%3d", (int)res->u0.sival&0xff);
		break;
	case 'X':
		Bprint(bout, "%.8ux", (int)res->u0.sival);
		break;
	case 'x':
		Bprint(bout, "%.4ux", (int)res->u0.sival&0xffff);
		break;
	case 'Y':
		Bprint(bout, "%.16llux", res->u0.sival);
		break;
	case 'D':
		Bprint(bout, "%d", (int)res->u0.sival);
		break;
	case 'd':
		Bprint(bout, "%d", (ushort)res->u0.sival);
		break;
	case 'u':
		Bprint(bout, "%ud", (int)res->u0.sival&0xffff);
		break;
	case 'U':
		Bprint(bout, "%lud", (ulong)res->u0.sival);
		break;
	case 'Z':
		Bprint(bout, "%llud", res->u0.sival);
		break;
	case 'V':
		Bprint(bout, "%lld", res->u0.sival);
		break;
	case 'o':
		Bprint(bout, "0%.11uo", (int)res->u0.sival&0xffff);
		break;
	case 'O':
		Bprint(bout, "0%.6uo", (int)res->u0.sival);
		break;
	case 'q':
		Bprint(bout, "0%.11o", (short)(res->u0.sival&0xffff));
		break;
	case 'Q':
		Bprint(bout, "0%.6o", (int)res->u0.sival);
		break;
	case 'f':
	case 'F':
		if(type != TFLOAT)
			Bprint(bout, "*%c<%s>*", res->fmt, typenames[type]);
		else
			Bprint(bout, "%g", res->u0.sfval);
		break;
	case 's':
	case 'g':
	case 'G':
		if(type != TSTRING)
			Bprint(bout, "*%c<%s>*", res->fmt, typenames[type]);
		else
			Bwrite(bout, res->u0.sstring->string, res->u0.sstring->len);
		break;
	case 'R':
		if(type != TSTRING)
			Bprint(bout, "*%c<%s>*", res->fmt, typenames[type]);
		else
			Bprint(bout, "%S", (Rune*)res->u0.sstring->string);
		break;
	case 'a':
	case 'A':
		symoff(buf, sizeof(buf), res->u0.sival, CANY);
		Bprint(bout, "%s", buf);
		break;
	case 'I':
	case 'i':
		if(type != TINT)
			Bprint(bout, "*%c<%s>*", res->fmt, typenames[type]);
		else {
			if ((*machdata->das)(symmap, res->u0.sival, res->fmt, buf, sizeof(buf)) < 0)
				Bprint(bout, "no instruction: %r");
			else
				Bprint(bout, "%s", buf);
		}
		break;
	}
}

void
blprint(List *l)
{
	Bprint(bout, "{");
	while(l) {
		switch(l->type) {
		default:
			patom(l->type, &l->lstore);
			break;
		case TSTRING:
			Bputc(bout, '"');
			patom(l->type, &l->lstore);
			Bputc(bout, '"');
			break;
		case TLIST:
			blprint(l->lstore.u0.sl);
			break;
		case TCODE:
			pcode(l->lstore.u0.scc, 0);
			break;
		}
		l = l->next;
		if(l)
			Bprint(bout, ", ");
	}
	Bprint(bout, "}");
}

int
comx(Node res)
{
	Lsym *sl;
	Node *n, xx;

	if(res.nstore.fmt != 'a' && res.nstore.fmt != 'A')
		return 0;

	if(res.nstore.comt == 0 || res.nstore.comt->base == 0)
		return 0;

	sl = res.nstore.comt->base;
	if(sl->proc) {
		res.left = ZN;
		res.right = ZN;
		n = an(ONAME, ZN, ZN);
		n->sym = sl;
		n = an(OCALL, n, &res);
			n->left->sym = sl;
		expr(n, &xx);
		return 1;
	}
	print("(%s)", sl->name);
	return 0;
}

void
bprint(Node *r, Node *args)
{
	int i, nas;
	Node res, *av[Maxarg];

	USED(r);
	na = 0;
	flatten(av, args);
	nas = na;
	for(i = 0; i < nas; i++) {
		expr(av[i], &res);
		switch(res.type) {
		default:
			if(comx(res))
				break;
			patom(res.type, &res.nstore);
			break;
		case TCODE:
			pcode(res.nstore.u0.scc, 0);
			break;
		case TLIST:
			blprint(res.nstore.u0.sl);
			break;
		}
	}
	if(ret == 0)
		Bputc(bout, '\n');
}

void
printto(Node *r, Node *args)
{
	int fd;
	Biobuf *b;
	int i, nas;
	Node res, *av[Maxarg];

	USED(r);
	na = 0;
	flatten(av, args);
	nas = na;

	expr(av[0], &res);
	if(res.type != TSTRING)
		error("printto(string, ...): need string");

	fd = create(res.nstore.u0.sstring->string, OWRITE, 0666);
	if(fd < 0)
		fd = open(res.nstore.u0.sstring->string, OWRITE);
	if(fd < 0)
		error("printto: open %s: %r", res.nstore.u0.sstring->string);

	b = gmalloc(sizeof(Biobuf));
	Binit(b, fd, OWRITE);

	Bflush(bout);
	io[iop++] = bout;
	bout = b;

	for(i = 1; i < nas; i++) {
		expr(av[i], &res);
		switch(res.type) {
		default:
			if(comx(res))
				break;
			patom(res.type, &res.nstore);
			break;
		case TLIST:
			blprint(res.nstore.u0.sl);
			break;
		}
	}
	if(ret == 0)
		Bputc(bout, '\n');

	Bterm(b);
	close(fd);
	free(b);
	bout = io[--iop];
}

void
pcfile(Node *r, Node *args)
{
	Node res;
	char *p, buf[128];

	if(args == 0)
		error("pcfile(addr): arg count");
	expr(args, &res);
	if(res.type != TINT)
		error("pcfile(addr): arg type");

	r->type = TSTRING;
	r->nstore.fmt = 's';
	if(fileline(buf, sizeof(buf), res.nstore.u0.sival) == 0) {
		r->nstore.u0.sstring = strnode("?file?");
		return;
	}
	p = strrchr(buf, ':');
	if(p == 0)
		error("pcfile(addr): funny file %s", buf);
	*p = '\0';
	r->nstore.u0.sstring = strnode(buf);	
}

void
pcline(Node *r, Node *args)
{
	Node res;
	char *p, buf[128];

	if(args == 0)
		error("pcline(addr): arg count");
	expr(args, &res);
	if(res.type != TINT)
		error("pcline(addr): arg type");

	r->type = TINT;
	r->nstore.fmt = 'D';
	if(fileline(buf, sizeof(buf), res.nstore.u0.sival) == 0) {
		r->nstore.u0.sival = 0;
		return;
	}

	p = strrchr(buf, ':');
	if(p == 0)
		error("pcline(addr): funny file %s", buf);
	r->nstore.u0.sival = atoi(p+1);	
}

void
_bpcondset(Node *r, Node *args)
{
	Node id, p, addr, conds;
	Node *av[Maxarg];
	List *l;
	char *op;
	List *val;
	ulong pid;

	USED(r);

	if(!rdebug)
		error("_bpcondset(id, pid, addr, conds): only available with remote debugger\n");

	if(args == 0)
		error("_bpcondset(id, pid, addr, conds): not enough args");
	na = 0;
	flatten(av, args);
	if(na != 4)
		error("_bpcondset(id, pid, addr, conds): %s args",
			na > 4 ? "too many" : "too few");
	expr(av[0], &id);
	expr(av[1], &p);
	expr(av[2], &addr);
	expr(av[3], &conds);
	if(id.type != TINT)
		error("_bpcondset(id, pid, addr, conds): id: integer expected");
	if(p.type != TINT)
		error("_bpcondset(pid, addr, conds): pid: integer expected");
	if(addr.type != TINT)
		error("_bpcondset(pid, addr, conds): addr: integer expected");
	if(conds.type != TLIST)
		error("_bpcondset(pid, addr, conds): conds: list expected");
	l = conds.nstore.u0.sl;
	remcondset('n', (ulong)id.nstore.u0.sival);
	pid = (ulong)p.nstore.u0.sival;
	if (pid != 0)
		remcondset('k', pid);
	while(l != nil) {
		if(l->type != TLIST || listlen(l->lstore.u0.sl) != 2)
			error("_bpcondset(addr, list): list elements are {\"op\", val} pairs");
		if(l->lstore.u0.sl->type != TSTRING)
			error("_bpcondset(addr, list): list elements are {string, val} pairs");
		op = l->lstore.u0.sl->lstore.u0.sstring->string;
		val = l->lstore.u0.sl->next;
		if(val->type != TINT)
			error("_bpcondset(addr, list): list elements are {string, int} pairs");
		remcondset(op[0], (ulong)val->lstore.u0.sival);
		l = l->next;
	}
	remcondset('b', (ulong)addr.nstore.u0.sival);
}

void
_bpconddel(Node *r, Node *args)
{
	Node res;

	USED(r);
	if(!rdebug)
		error("_bpconddel(id): only available with remote debugger\n");

	expr(args, &res);
	if(res.type != TINT)
		error("_bpconddel(id): arg type");

	remcondset('d', (ulong)res.nstore.u0.sival);
}

void
setdebug(Node *r, Node *args)
{
	Node res;

	USED(r);
	expr(args, &res);
	if (res.type != TINT)
		error("debug(type): bad type");
	setdbg_opt((char)res.nstore.u0.sival, 1);
}


void
setdbg_opt(char c, int prflag)
{
	switch(c) {
	case 'p':
		if (protodebug) {
			protodebug = 0;
			if (prflag)
				print("Serial protocol debug is OFF\n");
		} else {
			protodebug = 1;
			if (prflag)
				print("Serial protocol debug is ON\n");
		}
		break;
	default:
		print("Invalid debug flag(%c), supported values: p\n", c);
		break;
	}
}
