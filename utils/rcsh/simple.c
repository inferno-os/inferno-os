#include "rc.h"

typedef struct Builtin	Builtin;

struct Builtin
{
	char	*name;
	void	(*fnc)(void);
};

int	exitnext(void);
void	execexec(void);
void	execfunc(Var *func);
void	execcd(void);
void	execwhatis(void);
void	execeval(void);
void	execexit(void);
void	execshift(void);
void	execwait(void);
void	execdot(void);
void	execflag(void);

Builtin builtin[]={
	"cd",		execcd,
	"whatis",	execwhatis,
	"eval",		execeval,
	"exec",		execexec,	/* but with popword first */
	"exit",		execexit,
	"shift",	execshift,
	"wait",		execwait,
	".",		execdot,
	"flag",		execflag,
	0
};

int	mapfd(int fd);

void
Xsimple(void)
{
	Word *a;
	Thread *p=runq;
	Var *v;
	Builtin *bp;
	uint pid;
	char **argv;

	globlist();
	a=runq->argv->words;
	if(a==0){
		Xerror("empty argument list");
		return;
	}
	if(flag['x'])
		pfmt(err, "%v\n", p->argv->words); /* wrong, should do redirs */

	v=gvlook(a->word);
	if(v->fn)
		execfunc(v);
	else{
		if(strcmp(a->word, "builtin")==0){
			if(count(a)==1){
				pfmt(err, "builtin: empty argument list\n");
				setstatus("empty arg list");
				poplist();
				return;
			}
			a=a->next;
			popword();
		}
		for(bp=builtin;bp->name;bp++) {
			if(strcmp(a->word, bp->name)==0){
				(*bp->fnc)();
				return;
			}
		}

		updenv();
		argv = procargv(0, 0, 0, 0, runq->argv->words);
		pid = proc(argv, mapfd(0), mapfd(1), mapfd(2));
		free(argv);

		if(pid == 0)
			pfmt(err, "%s: %r\n", runq->argv->words->word);
		else
			waitfor(pid);
		poplist();
#ifdef XXX
		if(exitnext()){
			/* fork and wait is redundant */
			pushword("exec");
			execexec();
			Xexit();
		}
		else{
			flush(err);
			updenv();
			switch(pid=fork()){
			case -1:
				Xperror("try again");
				return;
			case 0:
				pushword("exec");
				execexec();
				Exit("can't exec");
			default:
				poplist();
				/* interrupts don't get us out */
				while(Waitfor(pid, 1) < 0)
					;
			}
		}
#endif
	}
}

Word nullpath={ "", 0};

Word *
searchpath(char *w)
{
	Word *path;

	return &nullpath;

	if(strncmp(w, "/", 1) == 0
	|| strncmp(w, "#", 1) == 0
	|| *w && w[1] == ':'
	|| strncmp(w, "./", 2) == 0
	|| strncmp(w, "../", 3) == 0
	|| (path=vlook("path")->val) == 0)
		path=&nullpath;
	return path;
}

/*
 * Search through the following code to see if we're just going to exit.
 */
int
exitnext(void)
{
	Code *c=&runq->code[runq->pc];

	while(c->f==Xpopredir)
		c++;
	return c->f==Xexit;
}

#ifdef XXX

void
doredir(Redir *rp)
{
	if(rp){
		doredir(rp->next);
		switch(rp->type){
		case ROPEN:
			if(rp->from!=rp->to){
				Dup(rp->from, rp->to);
				close(rp->from);
			}
			break;
		case RDUP: Dup(rp->from, rp->to); break;
		case RCLOSE: close(rp->from); break;
		}
	}
}


#endif

void
execexec(void)
{
	popword();	/* "exec" */
	if(runq->argv->words==0){
		Xerror("empty argument list");
		return;
	}
	fatal("execexec not done yet");
/*
	doredir(runq->redir);
	Execute(runq->argv->words, searchpath(runq->argv->words->word));
*/	

	poplist();
}

void
execfunc(Var *func)
{
	Word *starval;

	popword();
	starval=runq->argv->words;
	runq->argv->words=0;
	poplist();
	start(func->fn, func->pc, runq->local);
	runq->local=newvar(strdup("*"), runq->local);
	runq->local->val=starval;
	runq->local->changed=1;
}

void
execcd(void)
{
	Word *a=runq->argv->words;
	Word *cdpath;
	char dir[512];

	setstatus("can't cd");
	cdpath=vlook("cdpath")->val;
	switch(count(a)){
	default:
		pfmt(err, "Usage: cd [directory]\n");
		break;
	case 2:
		if(a->next->word[0]=='/' || cdpath==0) cdpath=&nullpath;
		for(;cdpath;cdpath=cdpath->next){
			strcpy(dir, cdpath->word);
			if(dir[0]) strcat(dir, "/");
			strcat(dir, a->next->word);
			if(chdir(dir)>=0){
				if(strlen(cdpath->word)
				&& strcmp(cdpath->word, ".")!=0)
					pfmt(err, "%s\n", dir);
				setstatus("");
				break;
			}
		}
		if(cdpath==0) pfmt(err, "Can't cd %s\n", a->next->word);
		break;
	case 1:
		a=vlook("home")->val;
		if(count(a)>=1){
			if(chdir(a->word)>=0)
				setstatus("");
			else
				pfmt(err, "Can't cd %s\n", a->word);
		}
		else
			pfmt(err, "Can't cd -- $home empty\n");
		break;
	}
	poplist();
}

void
execexit(void)
{
	switch(count(runq->argv->words)){
	default: pfmt(err, "Usage: exit [status]\nExiting anyway\n");
	case 2: setstatus(runq->argv->words->next->word);
	case 1:	Xexit();
	}
}

void
execflag(void)
{
	char *letter, *val;
	switch(count(runq->argv->words)){
	case 2:
		setstatus(flag[runq->argv->words->next->word[0]]?"":"flag not set");
		break;
	case 3:
		letter=runq->argv->words->next->word;
		val=runq->argv->words->next->next->word;
		if(strlen(letter)==1){
			if(strcmp(val, "+")==0){
				flag[letter[0]]=1;
				break;
			}
			if(strcmp(val, "-")==0){
				flag[letter[0]]=0;
				break;
			}
		}
	default:
		Xerror("Usage: flag [letter] [+-]");
		return;
	}
	poplist();
}

void
execshift(void)
{
	int n;
	Word *a;
	Var *star;
	switch(count(runq->argv->words)){
	default:
		pfmt(err, "Usage: shift [n]\n");
		setstatus("shift usage");
		poplist();
		return;
	case 2: n=atoi(runq->argv->words->next->word); break;
	case 1: n=1; break;
	}
	star=vlook("*");
	for(;n && star->val;--n){
		a=star->val->next;
		free(star->val->word);
		free(star->val);
		star->val=a;
		star->changed=1;
	}
	setstatus("");
	poplist();
}

int
octal(char *s)
{
	int n=0;
	while(*s==' ' || *s=='\t' || *s=='\n') s++;
	while('0'<=*s && *s<='7') n=n*8+*s++-'0';
	return n;
}

void
execeval(void)
{
	char *cmdline, *s, *t;
	int len=0;
	Word *ap;

	if(count(runq->argv->words)<=1){
		Xerror("Usage: eval cmd ...");
		return;
	}
	eflagok=1;
	for(ap=runq->argv->words->next;ap;ap=ap->next)
		len+=1+strlen(ap->word);
	cmdline=malloc(len);
	s=cmdline;
	for(ap=runq->argv->words->next;ap;ap=ap->next){
		for(t=ap->word;*t;) *s++=*t++;
		*s++=' ';
	}
	s[-1]='\n';
	poplist();
	execcmds(opencore(cmdline, len));
	free(cmdline);
}

void
execdot(void)
{
	int iflag=0;
	int fd;
	List *av;
	Thread *p=runq;
	char *zero;
	char file[512];
	Word *path;
	static int first=1;
	static Code dotcmds[14];

	if(first) {
		dotcmds[0].i=1;
		dotcmds[1].f=Xmark;
		dotcmds[2].f=Xword;
		dotcmds[3].s="0";
		dotcmds[4].f=Xlocal;
		dotcmds[5].f=Xmark;
		dotcmds[6].f=Xword;
		dotcmds[7].s="*";
		dotcmds[8].f=Xlocal;
		dotcmds[9].f=Xrdcmds;
		dotcmds[10].f=Xunlocal;
		dotcmds[11].f=Xunlocal;
		dotcmds[12].f=Xreturn;
		first=0;
	} else
		eflagok=1;
	popword();
	if(p->argv->words && strcmp(p->argv->words->word, "-i")==0){
		iflag=1;
		popword();
	}
	/* get input file */
	if(p->argv->words==0){
		Xerror("Usage: . [-i] file [arg ...]");
		return;
	}
	zero=strdup(p->argv->words->word);
	popword();
	strcpy(file, "**No file name**");
	fd = -1;
	if(strcmp(zero, "stdin$") == 0)
		fd = dup(0);
	else{
		for(path=searchpath(zero);path;path=path->next){
			strcpy(file, path->word);
			if(file[0])
				strcat(file, "/");
			strcat(file, zero);
			if((fd=open(file, 0))>=0)
				break;
		}
	}
	if(fd<0){
		Xperror(file);
		return;
	}
	/* set up for a new command loop */
	start(dotcmds, 1, 0);
	pushredir(RCLOSE, fd, 0);
	runq->cmdfile=zero;
	runq->cmdfd=openfd(fd);
	runq->iflag=iflag;
	runq->iflast=0;
	/* push $* value */
	pushlist();
	runq->argv->words=p->argv->words;
	/* free caller's copy of $* */
	av=p->argv;
	p->argv=av->next;
	free(av);
	/* push $0 value */
	pushlist();
	pushword(zero);
	ndot++;
}

void
execwhatis(void)
{	/* mildly wrong -- should fork before writing */
	Word *a, *b, *path;
	Var *v;
	Builtin *bp;
	char file[512];
	Io out[1];
	int found, sep;

	a=runq->argv->words->next;
	if(a==0){
		Xerror("Usage: whatis name ...");
		return;
	}
	setstatus("");
	out->fd=mapfd(1);
	out->bufp=out->buf;
	out->ebuf=&out->buf[NBUF];
	out->strp=0;
	for(;a;a=a->next){
		v=vlook(a->word);
		if(v->val){
			pfmt(out, "%s=", a->word);
			if(v->val->next==0)
				pfmt(out, "%q\n", v->val->word);
			else{
				sep='(';
				for(b=v->val;b && b->word;b=b->next){
					pfmt(out, "%c%q", sep, b->word);
					sep=' ';
				}
				pfmt(out, ")\n");
			}
			found=1;
		}
		else
			found=0;
		v=gvlook(a->word);
		if(v->fn) pfmt(out, "fn %s %s\n", v->name, v->fn[v->pc-1].s);
		else{
			for(bp=builtin;bp->name;bp++)
				if(strcmp(a->word, bp->name)==0){
					pfmt(out, "builtin %s\n", a->word);
					break;
				}
			if(!bp->name){
				for(path=searchpath(a->word);path;path=path->next){
					strcpy(file, path->word);
					if(file[0]) strcat(file, "/");
					strcat(file, a->word);
#ifdef XXX
					if(Executable(file)){
						pfmt(out, "%s\n", file);
						break;
					}
#endif
				}
				if(!path && !found){
					pfmt(err, "%s: not found\n", a->word);
					setstatus("not found");
				}
			}
		}
	}
	poplist();
	flush(err);
}

void
execwait(void)
{
	fprint(2, "wait: not done yet");

#ifdef XXX
	switch(count(runq->argv->words)){
	default: Xerror("Usage: wait [pid]"); return;
	case 2: Waitfor(atoi(runq->argv->words->next->word), 0); break;
	case 1: Waitfor(-1, 0); break;
	}
	poplist();
#endif
}

int
mapfd(int fd)
{
	Redir *rp;
	for(rp=runq->redir;rp;rp=rp->next){
		switch(rp->type){
		case RCLOSE:
			if(rp->from==fd) fd=-1;
			break;
		case RDUP:
		case ROPEN:
			if(rp->to==fd) fd=rp->from;
			break;
		}
	}
	return fd;
}
