#include "rc.h"

extern	char	*argv0;

int	ifnot;
int	eflagok;

/*
 * Opcode routines
 * Arguments on stack (...)
 * Arguments in line [...]
 * Code in line with jump around {...}
 *
 * Xappend(file)[fd]			open file to append
 * Xassign(name, val)			assign val to name
 * Xasync{... Xexit}			make thread for {}, no wait
 * Xbackq{... Xreturn}			make thread for {}, push stdout
 * Xbang				complement condition
 * Xcase(pat, value){...}		exec code on match, leave (value) on
 * 					stack
 * Xclose[i]				close file descriptor
 * Xconc(left, right)			concatenate, push results
 * Xcount(name)				push var count
 * Xdelfn(name)				delete function definition
 * Xdeltraps(names)			delete named traps
 * Xdol(name)				get variable value
 * Xqdol(name)				concatenate variable components
 * Xdup[i j]				dup file descriptor
 * Xexit				rc exits with status
 * Xfalse{...}				execute {} if false
 * Xfn(name){... Xreturn}			define function
 * Xfor(var, list){... Xreturn}		for loop
 * Xjump[addr]				goto
 * Xlocal(name, val)			create local variable, assign value
 * Xmark				mark stack
 * Xmatch(pat, str)			match pattern, set status
 * Xpipe[i j]{... Xreturn}{... Xreturn}	construct a pipe between 2 new threads,
 * 					wait for both
 * Xpipefd[type]{... Xreturn}		connect {} to pipe (input or output,
 * 					depending on type), push /dev/fd/??
 * Xpopm(value)				pop value from stack
 * Xread(file)[fd]			open file to read
 * Xsettraps(names){... Xreturn}		define trap functions
 * Xshowtraps				print trap list
 * Xsimple(args)			run command and wait
 * Xreturn				kill thread
 * Xsubshell{... Xexit}			execute {} in a subshell and wait
 * Xtrue{...}				execute {} if true
 * Xunlocal				delete local variable
 * Xword[string]			push string
 * Xwrite(file)[fd]			open file to write
 */

static char **
rcargv(char *s)
{
	char *flags;

	if(flag['e'])
		flags = "-Se";
	else
		flags = "-S";
	return procargv(argv0, flags, "-c", s, vlook("*")->val);
}

void
Xappend(void)
{
	char *file;
	int f;

	switch(count(runq->argv->words)){
	default: Xerror(">> requires singleton"); return;
	case 0: Xerror(">> requires file"); return;
	case 1: break;
	}
	file=runq->argv->words->word;
	if((f=open(file, 1))<0 && (f=create(file, 1, 0666))<0){
		Xperror(file);
		return;
	}
	seek(f, 0L, 2);
	pushredir(ROPEN, f, runq->code[runq->pc].i);
	runq->pc++;
	poplist();
}

void
Xassign(void)
{
	Var *v;

	if(count(runq->argv->words)!=1){
		Xerror("variable name not singleton!");
		return;
	}
	deglob(runq->argv->words->word);
	v=vlook(runq->argv->words->word);
	poplist();
	globlist();
	freewords(v->val);
	v->val=runq->argv->words;
	v->changed=1;
	runq->argv->words=0;
	poplist();
}

void
Xasync(void)
{
	uint pid;
	char buf[20], **argv;

	updenv();

	argv = rcargv(runq->code[runq->pc].s);
	pid = proc(argv, -1, 1, 2);
	free(argv);

	if(pid == 0) {
		Xerror("proc failed");
		return;
	}

	runq->pc++;
	sprint(buf, "%d", pid);
	setvar("apid", newword(buf, (Word *)0));
}

void
Xbackq(void)
{
	char wd[8193], **argv;
	int c;
	char *s, *ewd=&wd[8192], *stop;
	Io *f;
	Var *ifs=vlook("ifs");
	Word *v, *nextv;
	int pfd[2];
	int pid;

	stop = ifs->val?ifs->val->word:"";
	if(pipe(pfd)<0){
		Xerror("can't make pipe");
		return;
	}

	updenv();

	argv = rcargv(runq->code[runq->pc].s);
	pid = proc(argv, -1, pfd[1], 2);
	free(argv);

	close(pfd[1]);

	if(pid == 0) {
		Xerror("proc failed");
		close(pfd[0]);
		return;
	}

	f = openfd(pfd[0]);
	s = wd;
	v = 0;
	while((c=rchr(f))!=EOF){
		if(strchr(stop, c) || s==ewd){
			if(s!=wd){
				*s='\0';
				v=newword(wd, v);
				s=wd;
			}
		}
		else *s++=c;
	}
	if(s!=wd){
		*s='\0';
		v=newword(wd, v);
	}
	closeio(f);
	waitfor(pid);
	/* v points to reversed arglist -- reverse it onto argv */
	while(v){
		nextv=v->next;
		v->next=runq->argv->words;
		runq->argv->words=v;
		v=nextv;
	}
	runq->pc++;
}

void
Xbang(void)
{
	setstatus(truestatus()?"false":"");
}

void
Xcase(void)
{
	Word *p;
	char *s;
	int ok=0;

	s=list2str(runq->argv->next->words);
	for(p=runq->argv->words;p;p=p->next){
		if(match(s, p->word, '\0')){
			ok=1;
			break;
		}
	}
	free(s);
	if(ok)
		runq->pc++;
	else
		runq->pc=runq->code[runq->pc].i;
	poplist();
}

void
Xclose(void)
{
	pushredir(RCLOSE, runq->code[runq->pc].i, 0);
	runq->pc++;
}

void
Xconc(void)
{
	Word *lp=runq->argv->words;
	Word *rp=runq->argv->next->words;
	Word *vp=runq->argv->next->next->words;
	int lc=count(lp), rc=count(rp);

	if(lc!=0 || rc!=0){
		if(lc==0 || rc==0){
			Xerror("null list in concatenation");
			return;
		}
		if(lc!=1 && rc!=1 && lc!=rc){
			Xerror("mismatched list lengths in concatenation");
			return;
		}
		vp=conclist(lp, rp, vp);
	}
	poplist();
	poplist();
	runq->argv->words=vp;
}

void
Xcount(void)
{
	Word *a;
	char *s, *t;
	int n;
	char num[12];

	if(count(runq->argv->words)!=1){
		Xerror("variable name not singleton!");
		return;
	}
	s=runq->argv->words->word;
	deglob(s);
	n=0;
	for(t=s;'0'<=*t && *t<='9';t++) n=n*10+*t-'0';
	if(n==0 || *t){
		a=vlook(s)->val;
		sprint(num, "%d", count(a));
	}
	else{
		a=vlook("*")->val;
		sprint(num, "%d", a && 1<=n && n<=count(a)?1:0);
	}
	poplist();
	pushword(num);
}

void
Xdelfn(void)
{
	Var *v;
	Word *a;

	for(a=runq->argv->words;a;a=a->next){
		v=gvlook(a->word);
		if(v->fn)
			codefree(v->fn);
		v->fn=0;
		v->fnchanged=1;
	}
	poplist();
}

void
Xdelhere(void)
{
	Var *v;
	Word *a;

	for(a=runq->argv->words;a;a=a->next){
		v=gvlook(a->word);
		if(v->fn) codefree(v->fn);
		v->fn=0;
		v->fnchanged=1;
	}
	poplist();
}

void
Xdol(void)
{
	Word *a, *star;
	char *s, *t;
	int n;

	if(count(runq->argv->words)!=1){
		Xerror("variable name not singleton!");
		return;
	}
	s=runq->argv->words->word;
	deglob(s);
	n=0;
	for(t=s;'0'<=*t && *t<='9';t++) n=n*10+*t-'0';
	a=runq->argv->next->words;
	if(n==0 || *t)
		a=copywords(vlook(s)->val, a);
	else{
		star=vlook("*")->val;
		if(star && 1<=n && n<=count(star)){
			while(--n) star=star->next;
			a=newword(star->word, a);
		}
	}
	poplist();
	runq->argv->words=a;
}

void
Xdup(void)
{
	pushredir(RDUP, runq->code[runq->pc].i, runq->code[runq->pc+1].i);
	runq->pc+=2;
}

void
Xeflag(void)
{
	if(eflagok && !truestatus())
		Xexit();
}

void
Xexit(void)
{
	Var *trapreq;
	Word *starval;
	char *c;
	static int beenhere=0;

	if(truestatus())
		c = "";
	else
		c = getstatus();

	if(flag['S'] || beenhere)
		exits(c);

	trapreq=vlook("sigexit");
	if(trapreq->fn){
		beenhere=1;
		--runq->pc;
		starval=vlook("*")->val;
		start(trapreq->fn, trapreq->pc, (Var*)0);
		runq->local=newvar(strdup("*"), runq->local);
		runq->local->val=copywords(starval, (Word*)0);
		runq->local->changed=1;
		runq->redir=runq->startredir=0;
	}

	exits(c);
}

void
Xfalse(void)
{
	if(truestatus())
		runq->pc=runq->code[runq->pc].i;
	else
		runq->pc++;
}

void
Xfor(void)
{
	if(runq->argv->words==0) {
		poplist();
		runq->pc=runq->code[runq->pc].i;
	} else {
		freelist(runq->local->val);
		runq->local->val=runq->argv->words;
		runq->local->changed=1;
		runq->argv->words=runq->argv->words->next;
		runq->local->val->next=0;
		runq->pc++;
	}
}

void
Xfn(void)
{
	Var *v;
	Word *a;
	int end;

	end=runq->code[runq->pc].i;
	for(a=runq->argv->words;a;a=a->next){
		v=gvlook(a->word);
		if(v->fn)
			codefree(v->fn);
		v->fn=codecopy(runq->code);
		v->pc=runq->pc+2;
		v->fnchanged=1;
	}
	runq->pc=end;
	poplist();
}

void
Xglob(void)
{
	globlist();
}

void
Xif(void)
{
	ifnot=1;
	if(truestatus()) runq->pc++;
	else runq->pc=runq->code[runq->pc].i;
}

void
Xifnot(void)
{
	if(ifnot)
		runq->pc++;
	else
		runq->pc=runq->code[runq->pc].i;
}

void
Xjump(void)
{
	runq->pc=runq->code[runq->pc].i;
}


void
Xlocal(void)
{
	if(count(runq->argv->words)!=1){
		Xerror("variable name must be singleton\n");
		return;
	}
	deglob(runq->argv->words->word);
	runq->local=newvar(strdup(runq->argv->words->word), runq->local);
	runq->local->val=copywords(runq->argv->next->words, 0);
	runq->local->changed=1;
	poplist();
	poplist();
}


void 
Xmark(void)
{
	pushlist();
}

void
Xmatch(void)
{
	Word *p;
	char *subject;

	subject=list2str(runq->argv->words);
	setstatus("no match");
	for(p=runq->argv->next->words;p;p=p->next) {
		if(match(subject, p->word, '\0')){
			setstatus("");
			break;
		}
	}
	free(subject);
	poplist();
	poplist();
}

void
Xpipe(void)
{
	Thread *p=runq;
	int pc=p->pc, pid;
	int lfd=p->code[pc].i;
	int rfd=p->code[pc+1].i;
	int pfd[2];
	char **argv;

	if(pipe(pfd)<0){
		Xperror("can't get pipe");
		return;
	}

	updenv();

	argv = rcargv(runq->code[pc+2].s);
	pid = proc(argv, 0, pfd[1], 2);
	free(argv);
	close(pfd[1]);

	if(pid == 0) {
		Xerror("proc failed");
		close(pfd[0]);
		return;
	}

	start(p->code, pc+4, runq->local);
	pushredir(ROPEN, pfd[0], rfd);
	p->pc=p->code[pc+3].i;
	p->pid=pid;
}

void
Xpipefd(void)
{
	fatal("Xpipefd");
}

void
Xpipewait(void)
{
	char status[NSTATUS+1];
	if(runq->pid==-1)
		setstatus(concstatus(runq->status, getstatus()));
	else{
		strncpy(status, getstatus(), NSTATUS);
		status[NSTATUS]='\0';
		waitfor(runq->pid);
		runq->pid=-1;
		setstatus(concstatus(getstatus(), status));
	}
}

void
Xpopm(void)
{
	poplist();
}

void
Xpopredir(void)
{
	Redir *rp=runq->redir;

	if(rp==0)
		panic("turfredir null!", 0);
	runq->redir=rp->next;
	if(rp->type==ROPEN)
		close(rp->from);
	free((char *)rp);
}

void
Xqdol(void)
{
	Word *a, *p;
	char *s;
	int n;

	if(count(runq->argv->words)!=1){
		Xerror("variable name not singleton!");
		return;
	}
	s=runq->argv->words->word;
	deglob(s);
	a=vlook(s)->val;
	poplist();
	n=count(a);
	if(n==0){
		pushword("");
		return;
	}
	for(p=a;p;p=p->next) n+=strlen(p->word);
	s=malloc(n);
	if(a){
		strcpy(s, a->word);
		for(p=a->next;p;p=p->next){
			strcat(s, " ");
			strcat(s, p->word);
		}
	}
	else
		s[0]='\0';
	pushword(s);
	free(s);
}

void
Xrdcmds(void)
{
	Thread *p=runq;
	Word *prompt;

	flush(err);
	nerror=0;
	if(flag['s'] && !truestatus())
		pfmt(err, "status=%v\n", vlook("status")->val);
	if(runq->iflag){
		prompt=vlook("prompt")->val;
		if(prompt)
			promptstr=prompt->word;
		else
			promptstr="% ";
	}
	interrupted=0;
	if(yyparse()) {
		if(!p->iflag || p->eof /* && !Eintr() */) {
			if(p->cmdfile)
				free(p->cmdfile);
			closeio(p->cmdfd);
			Xreturn();	/* should this be omitted? */
		} else {
			if(interrupted){
				pchr(err, '\n');
				p->eof=0;
			}
			--p->pc;	/* go back for next command */
		}
	} else {
		--p->pc;	/* re-execute Xrdcmds after codebuf runs */
		start(codebuf, 1, runq->local);
	}
	freenodes();
}

void
Xread(void)
{
	char *file;
	int f;

	switch(count(runq->argv->words)){
	default: Xerror("< requires singleton\n"); return;
	case 0: Xerror("< requires file\n"); return;
	case 1: break;
	}
	file=runq->argv->words->word;
	if((f=open(file, 0))<0){
		Xperror(file);
		return;
	}
	pushredir(ROPEN, f, runq->code[runq->pc].i);
	runq->pc++;
	poplist();
}

void
Xreturn(void)
{
	Thread *p=runq;

	turfredir();
	while(p->argv)
		poplist();
	codefree(p->code);
	runq=p->ret;
	free(p);
	if(runq==0)
		exits(truestatus()?"":getstatus());
}

void
Xsettrue(void)
{
	setstatus("");
}


void
Xsub(void)
{
	Word *a, *v;
	char *s;
	if(count(runq->argv->next->words)!=1){
		Xerror("variable name not singleton!");
		return;
	}
	s=runq->argv->next->words->word;
	deglob(s);
	a=runq->argv->next->next->words;
	v=vlook(s)->val;
	a=subwords(v, count(v), runq->argv->words, a);
	poplist();
	poplist();
	runq->argv->words=a;
}

void
Xsubshell(void)
{
	char **argv;
	uint pid;

	updenv();

	argv = rcargv(runq->code[runq->pc].s);
	pid = proc(argv, -1, 1, 2);
	free(argv);

	if(pid == 0) {
		Xerror("proc failed");
		return;
	}

	waitfor(pid);
	runq->pc++;
}

void
Xtrue(void)
{
	if(truestatus())
		runq->pc++;
	else	
		runq->pc=runq->code[runq->pc].i;
}

void
Xunlocal(void)
{
	Var *v=runq->local, *hid;

	if(v==0)
		panic("Xunlocal: no locals!", 0);
	runq->local=v->next;
	hid=vlook(v->name);
	hid->changed=1;
	free(v->name);
	freewords(v->val);
	free(v);
}

void
Xwastrue(void)
{
	ifnot=0;
}

void
Xwrite(void)
{
	char *file;
	int f;

	switch(count(runq->argv->words)){
	default: Xerror("> requires singleton\n"); return;
	case 0: Xerror("> requires file\n"); return;
	case 1: break;
	}
	file=runq->argv->words->word;
	if((f = create(file, 1, 0666))<0){
		Xperror(file);
		return;
	}
	pushredir(ROPEN, f, runq->code[runq->pc].i);
	runq->pc++;
	poplist();
}

void
Xword(void)
{
	pushword(runq->code[runq->pc++].s);
}

void
Xerror(char *s)
{
	pfmt(err, "rcsh: %s\n", s);
	flush(err);
	while(!runq->iflag)
		Xreturn();
}

void
Xperror(char *s)
{
	pfmt(err, "rcsh: %s: %r\n", s);
	flush(err);
	while(!runq->iflag)
		Xreturn();
}
