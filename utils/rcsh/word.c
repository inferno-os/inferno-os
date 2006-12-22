#include "rc.h"

Word *
newword(char *wd, Word *next)
{
	Word *p=new(Word);
	p->word=strdup(wd);
	p->next=next;
	return p;
}

void
pushword(char *wd)
{
	if(runq->argv==0)
		panic("pushword but no argv!", 0);
	runq->argv->words=newword(wd, runq->argv->words);
}

void
popword(void)
{
	Word *p;

	if(runq->argv==0)
		panic("popword but no argv!", 0);
	p=runq->argv->words;
	if(p==0)
		panic("popword but no word!", 0);
	runq->argv->words=p->next;
	free(p->word);
	free(p);
}

void
freewords(Word *w)
{
	Word *nw;
	while(w){
		free(w->word);
		nw=w->next;
		free(w);
		w=nw;
	}
}

void
freelist(Word *w)
{
	Word *nw;
	while(w){
		nw=w->next;
		free(w->word);
		free(w);
		w=nw;
	}
}

void
pushlist(void)
{
	List *p=new(List);
	p->next=runq->argv;
	p->words=0;
	runq->argv=p;
}

void
poplist(void)
{
	List *p=runq->argv;
	if(p==0)
		panic("poplist but no argv", 0);
	freelist(p->words);
	runq->argv=p->next;
	free(p);
}

int
count(Word *w)
{
	int n;
	for(n=0;w;n++)
		w=w->next;
	return n;
}

/*
 * copy arglist a, adding the copy to the front of tail
 */
Word *
copywords(Word *a, Word *tail)
{
	Word *v=0, **end;
	for(end=&v;a;a=a->next,end=&(*end)->next)
		*end=newword(a->word, 0);
	*end=tail;
	return v;
}

char *
list2str(Word *words)
{
	char *value, *s, *t;
	int len=0;
	Word *ap;

	for(ap=words;ap;ap=ap->next)
		len+=1+strlen(ap->word);
	value=malloc(len+1);
	s=value;
	for(ap=words;ap;ap=ap->next){
		for(t=ap->word;*t;) *s++=*t++;
		*s++=' ';
	}
	if(s==value)
		*s='\0';
	else
		s[-1]='\0';
	return value;
}

Word *
subwords(Word *val, int len, Word *sub, Word *a)
{
	int n;
	char *s;

	if(!sub) return a;
	a=subwords(val, len, sub->next, a);
	s=sub->word;
	deglob(s);
	n=0;
	while('0'<=*s && *s<='9') n=n*10+ *s++ -'0';
	if(n<1 || len<n) return a;
	for(;n!=1;--n) val=val->next;
	return newword(val->word, a);
}


void
pushredir(int type, int from, int to)
{
	Redir *rp=new(Redir);
	rp->type=type;
	rp->from=from;
	rp->to=to;
	rp->next=runq->redir;
	runq->redir=rp;
}

void
turfredir(void)
{
	while(runq->redir!=runq->startredir)
		Xpopredir();
}

Word*
conclist(Word *lp, Word *rp, Word *tail)
{
	char *buf;
	Word *v;
	if(lp->next || rp->next)
		tail=conclist(lp->next==0?lp:lp->next, rp->next==0?rp:rp->next,
			tail);
	buf=malloc(strlen(lp->word)+strlen(rp->word)+1);
	strcpy(buf, lp->word);
	strcat(buf, rp->word);
	v=newword(buf, tail);
	free(buf);
	return v;
}
