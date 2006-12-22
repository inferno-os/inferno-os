#include "rc.h"
#include "y.tab.h"

#define	c0	t->child[0]
#define	c1	t->child[1]
#define	c2	t->child[2]
#define	emitf(x) ((codep!=ncode || morecode()), codebuf[codep].f=(x), codep++)
#define	emiti(x) ((codep!=ncode || morecode()), codebuf[codep].i=(x), codep++)
#define	emits(x) ((codep!=ncode || morecode()), codebuf[codep].s=(x), codep++)

void	stuffdot(int);
char	*fnstr(Tree*);
void	outcode(Tree*, int);
void	codeswitch(Tree*, int);
int	iscase(Tree*);
Code	*codecopy(Code*);
void	codefree(Code*);

int	codep, ncode;
Code	*codebuf;

int
morecode(void)
{
	ncode+=100;
	codebuf=realloc(codebuf, ncode*sizeof codebuf[0]);
	if(codebuf==0)
		panic("Can't realloc %d bytes in morecode!",
				ncode*sizeof codebuf[0]);
	return 0;	/* not used */
}

void
stuffdot(int a)
{
	if(a<0 || codep<=a) panic("Bad address %d in stuffdot", a);
	codebuf[a].i=codep;
}

int
compile(Tree *t)
{
	ncode=100;
	codebuf=malloc(ncode*sizeof codebuf[0]);
	codep=0;
	emiti(0);			/* reference count */
	outcode(t, flag['e']?1:0);
	if(nerror){
		free(codebuf);
		return 0;
	}
/*	readhere(); */
	emitf(Xreturn);
	emitf(0);
	return 1;
}

void
cleanhere(char *f)
{
	emitf(Xdelhere);
	emits(strdup(f));
}

char *
fnstr(Tree *t)
{
	Io *f=openstr();
	char *v;
	extern char nl;
	char svnl=nl;

	nl=';';
	pfmt(f, "%t", t);
	nl=svnl;
	v=f->strp;
	f->strp=0;
	closeio(f);
	return v;
}

void
outcode(Tree *t, int eflag)
{
	int p, q;
	Tree *tt;

	if(t==0)
		return;
	if(t->type != NOT && t->type != ';')
		runq->iflast=0;
	switch(t->type){
	default:
		pfmt(err, "bad type %d in outcode\n", t->type);
		break;
	case '$':
		emitf(Xmark);
		outcode(c0, eflag);
		emitf(Xdol);
		break;
	case '"':
		emitf(Xmark);
		outcode(c0, eflag);
		emitf(Xqdol);
		break;
	case SUB:
		emitf(Xmark);
		outcode(c0, eflag);
		emitf(Xmark);
		outcode(c1, eflag);
		emitf(Xsub);
		break;
	case '&':
		emitf(Xasync);
		emits(fnstr(c0));
/*
		p=emiti(0);
		outcode(c0, eflag);
		emitf(Xexit);
		stuffdot(p);
*/
		break;
	case ';':
		outcode(c0, eflag);
		outcode(c1, eflag);
		break;
	case '^':
		emitf(Xmark);
		outcode(c1, eflag);
		emitf(Xmark);
		outcode(c0, eflag);
		emitf(Xconc);
		break;
	case '`':
		emitf(Xbackq);
		emits(fnstr(c0));
/*
		p=emiti(0);
		outcode(c0, 0);
		emitf(Xexit);
		stuffdot(p);
*/
		break;
	case ANDAND:
		outcode(c0, 0);
		emitf(Xtrue);
		p=emiti(0);
		outcode(c1, eflag);
		stuffdot(p);
		break;
	case ARGLIST:
		outcode(c1, eflag);
		outcode(c0, eflag);
		break;
	case BANG:
		outcode(c0, eflag);
		emitf(Xbang);
		break;
	case PCMD:
	case BRACE:
		outcode(c0, eflag);
		break;
	case COUNT:
		emitf(Xmark);
		outcode(c0, eflag);
		emitf(Xcount);
		break;
	case FN:
		emitf(Xmark);
		outcode(c0, eflag);
		if(c1){
			emitf(Xfn);
			p=emiti(0);
			emits(fnstr(c1));
			outcode(c1, eflag);
			emitf(Xunlocal);	/* get rid of $* */
			emitf(Xreturn);
			stuffdot(p);
		}
		else
			emitf(Xdelfn);
		break;
	case IF:
		outcode(c0, 0);
		emitf(Xif);
		p=emiti(0);
		outcode(c1, eflag);
		emitf(Xwastrue);
		stuffdot(p);
		break;
	case NOT:
		if(!runq->iflast) yyerror("`if not' does not follow `if(...)'");
		emitf(Xifnot);
		p=emiti(0);
		outcode(c0, eflag);
		stuffdot(p);
		break;
	case OROR:
		outcode(c0, 0);
		emitf(Xfalse);
		p=emiti(0);
		outcode(c1, eflag);
		stuffdot(p);
		break;
	case PAREN:
		outcode(c0, eflag);
		break;
	case SIMPLE:
		emitf(Xmark);
		outcode(c0, eflag);
		emitf(Xsimple);
		if(eflag) emitf(Xeflag);
		break;
	case SUBSHELL:
		emitf(Xsubshell);
		emits(fnstr(c0));
/*
		p=emiti(0);
		outcode(c0, eflag);
		emitf(Xexit);
		stuffdot(p);
*/
		if(eflag) emitf(Xeflag);
		break;
	case SWITCH:
		codeswitch(t, eflag);
		break;
	case TWIDDLE:
		emitf(Xmark);
		outcode(c1, eflag);
		emitf(Xmark);
		outcode(c0, eflag);
		emitf(Xmatch);
		if(eflag) emitf(Xeflag);
		break;
	case WHILE:
		q=codep;
		emitf(Xsettrue);
		outcode(c0, 0);
		emitf(Xtrue);
		p=emiti(0);
		outcode(c1, eflag);
		emitf(Xjump);
		emiti(q);
		stuffdot(p);
		break;
	case WORDS:
		outcode(c1, eflag);
		outcode(c0, eflag);
		break;
	case FOR:
		emitf(Xmark);
		if(c1){
			outcode(c1, eflag);
			emitf(Xglob);
		}
		else{
			emitf(Xmark);
			emitf(Xword);
			emits(strdup("*"));
			emitf(Xdol);
		}
		emitf(Xmark);		/* dummy value for Xlocal */
		emitf(Xmark);
		outcode(c0, eflag);
		emitf(Xlocal);
		p=emitf(Xfor);
		q=emiti(0);
		outcode(c2, eflag);
		emitf(Xjump);
		emiti(p);
		stuffdot(q);
		emitf(Xunlocal);
		break;
	case WORD:
		emitf(Xword);
		emits(strdup(t->str));
		break;
	case DUP:
		if(t->rtype==DUPFD) {
			emitf(Xdup);
			emiti(t->fd0);
			emiti(t->fd1);
		} else { /* t->rtype == CLOSE */
			emitf(Xclose);
			emiti(t->fd0);
		}
		outcode(c1, eflag);
		emitf(Xpopredir);
		break;
/*
	case PIPEFD:
		emitf(Xpipefd);
		emiti(t->rtype);
		p=emiti(0);
		outcode(c0, eflag);
		emitf(Xexit);
		stuffdot(p);
		break;
*/
	case REDIR:
		emitf(Xmark);
		outcode(c0, eflag);
		emitf(Xglob);
		switch(t->rtype){
		case APPEND:
			emitf(Xappend);
			break;
		case WRITE:
			emitf(Xwrite);
			break;
		case READ:
		case HERE:
			emitf(Xread);
			break;
		}
		emiti(t->fd0);
		outcode(c1, eflag);
		emitf(Xpopredir);
		break;
	case '=':
		tt=t;
		for(;t && t->type=='=';t=c2)
			;
		if(t){
			for(t=tt;t->type=='=';t=c2){
				emitf(Xmark);
				outcode(c1, eflag);
				emitf(Xmark);
				outcode(c0, eflag);
				emitf(Xlocal);
			}
			t=tt;
			outcode(c2, eflag);
			for(;t->type=='=';t=c2)
				emitf(Xunlocal);
		}
		else{
			for(t=tt;t;t=c2){
				emitf(Xmark);
				outcode(c1, eflag);
				emitf(Xmark);
				outcode(c0, eflag);
				emitf(Xassign);
			}
		}
		t=tt;	/* so tests below will work */
		break;
	case PIPE:
		emitf(Xpipe);
		emiti(t->fd0);
		emiti(t->fd1);
		emits(fnstr(c0));
		q=emiti(0);
/*
		outcode(c0, eflag);
		emitf(Xexit);
		stuffdot(p);
*/
		outcode(c1, eflag);
		emitf(Xreturn);
		stuffdot(q);
		emitf(Xpipewait);
		break;
	}
	if(t->type!=NOT && t->type!=';')
		runq->iflast=t->type==IF;
	else if(c0) runq->iflast=c0->type==IF;
}

/*
 * switch code looks like this:
 *	Xmark
 *	(get switch value)
 *	Xjump	1f
 * out:	Xjump	leave
 * 1:	Xmark
 *	(get case values)
 *	Xcase	1f
 *	(commands)
 *	Xjump	out
 * 1:	Xmark
 *	(get case values)
 *	Xcase	1f
 *	(commands)
 *	Xjump	out
 * 1:
 * leave:
 *	Xpopm
 */
void
codeswitch(Tree *t, int eflag)
{
	int leave;		/* patch jump address to leave switch */
	int out;		/* jump here to leave switch */
	int nextcase;		/* patch jump address to next case */
	Tree *tt;
	if(c1->child[0]->type!=';'
	|| !iscase(c1->child[0]->child[0])){
		yyerror("case missing in switch");
		return;
	}
	emitf(Xmark);
	outcode(c0, eflag);
	emitf(Xjump);
	nextcase=emiti(0);
	out=emitf(Xjump);
	leave=emiti(0);
	stuffdot(nextcase);
	t=c1->child[0];
	while(t->type==';'){
		tt=c1;
		emitf(Xmark);
		for(t=c0->child[0];t->type==ARGLIST;t=c0) outcode(c1, eflag);
		emitf(Xcase);
		nextcase=emiti(0);
		t=tt;
		for(;;){
			if(t->type==';'){
				if(iscase(c0)) break;
				outcode(c0, eflag);
				t=c1;
			}
			else{
				outcode(t, eflag);
				break;
			}
		}
		emitf(Xjump);
		emiti(out);
		stuffdot(nextcase);
	}
	stuffdot(leave);
	emitf(Xpopm);
}

int
iscase(Tree *t)
{
	if(t->type!=SIMPLE)
		return 0;
	do
		t=c0;
	while(t->type==ARGLIST);

	return t->type==WORD && !t->quoted && strcmp(t->str, "case")==0;
}

Code *
codecopy(Code *cp)
{
	cp[0].i++;
	return cp;
}

void
codefree(Code *cp)
{
	Code *p;

	if(--cp[0].i!=0)
		return;

	for(p=cp+1;p->f;){
		if(p->f==Xappend || p->f==Xclose || p->f==Xread || p->f==Xwrite
		|| p->f==Xasync || p->f==Xcase || p->f==Xfalse
		|| p->f==Xfor || p->f==Xjump
		|| p->f==Xsubshell || p->f==Xtrue)
			p+=2;
		else if(p->f==Xdup || p->f==Xpipefd)
			p+=3;
		else if(p->f==Xpipe) {
			free(p[3].s);
			p+=5;
		} else if(p->f==Xword || p->f==Xdelhere || p->f==Xbackq) {
			free(p[1].s);
			p+=2;
		} else if(p->f==Xfn){
			free(p[2].s);
			p+=3;
		} else
			p++;
	}

	free(cp);
}
