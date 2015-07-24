#include "rc.h"
#include "y.tab.h"

extern char **_environ;
extern char **environ;

typedef struct Kw	Kw;

#define	NKW	30
#define NVAR	521

struct Kw{
	char	*name;
	int	type;
	Kw	*next;
};

void	updenvlocal(Var *v);
void	addenv(Var *v);

Kw	*kw[NKW];
Var	*gvar[NVAR];

int
hash(char *s, int n)
{
	int h=0, i=1;

	while(*s)
		h+=*s++*i++;
	h%=n;
	return h<0?h+n:h;
}

void
kenter(int type, char *name)
{
	int h=hash(name, NKW);
	Kw *p=new(Kw);
	p->type=type;
	p->name=name;
	p->next=kw[h];
	kw[h]=p;
}

void
vinit(void)
{
	char **env, *name, *val, *p;
	int i;
	Word *w;
	Io *f;
	int n;
	Var *v;

	env = _environ;
	for(i=0; env[i]; free(name), i++) {
		name = strdup(env[i]);
		p = strchr(name, '=');
		if(p == 0 || p == name)
			continue;
		*p = 0;
		val = p+1;
		n = strlen(val);
		if(n == 0)
			continue;

		if(strncmp(name, "fn#", 3)!=0) {
			/* variable */
			w = 0;
			p = val+n-1;
			while(*p) {
				if(*p == IWS)
					*p-- = 0;
				for(; *p && *p != IWS; p--)
					;
				w=newword(p+1, w);
			}
			setvar(name, w);
			vlook(name)->changed=0;
		} else {
			/* function */
			f = opencore(val, n);
			execcmds(f);
		}
	}
	v = vlook("path");
	p = getenv("path");
	if(v->val == 0 && p)
		v->val = newword(p, 0);
}


Tree *
klook(char *name)
{
	Kw *p;
	Tree *t=token(name, WORD);
	for(p=kw[hash(name, NKW)];p;p=p->next) {
		if(strcmp(p->name, name)==0){
			t->type=p->type;
			t->iskw=1;
			break;
		}
	}
	return t;
}

Var *
gvlook(char *name)
{
	int h=hash(name, NVAR);
	Var *v;
	for(v=gvar[h]; v; v=v->next)
		if(strcmp(v->name, name)==0)
			return v;

	return gvar[h]=newvar(strdup(name), gvar[h]);
}

Var *
vlook(char *name)
{
	Var *v;
	if(runq)
		for(v=runq->local; v; v=v->next)
			if(strcmp(v->name, name)==0)
				return v;
	return gvlook(name);
}

void
setvar(char *name, Word *val)
{
	Var *v=vlook(name);
	freewords(v->val);
	v->val=val;
	v->changed=1;
}

Var *
newvar(char *name, Var *next)
{
	Var *v=new(Var);
	v->name=name;
	v->val=0;
	v->fn=0;
	v->changed=0;
	v->fnchanged=0;
	v->next=next;
	return v;
}


void
execfinit(void)
{
}

void 
updenv(void)
{
	Var *v, **h;

	for(h=gvar;h!=&gvar[NVAR];h++)
		for(v=*h;v;v=v->next)
			addenv(v);

	if(runq)
		updenvlocal(runq->local);
}

static void
envput(char *var, char  *val)
{
	int i, n;
	char *e;
	char buf[256];

	snprint(buf, sizeof(buf), "%s=%s", var, val);
	n = strlen(var);
	for(i = 0;;i++){
		e = environ[i];
		if(e == 0)
			break;
		if(strncmp(e, var, n) == 0){
			free(e);
			environ[i] = strdup(buf);
			return;
		}
	}
	environ = realloc(environ, (i+2)*sizeof(char*));
	environ[i++] = strdup(buf);
	environ[i] = 0;
}

void
addenv(Var *v)
{
	char buf[100], *p;
	Io *f;
	Word *w;
	int i, n;

	if(v->changed){
		v->changed=0;
		p = 0;
		n = 0;
		if(v->val) {
			for(w=v->val; w; w=w->next) {
				i = strlen(w->word);
				p = realloc(p, n+i+1);
				memmove(p+n, w->word, i);
				n+=i;
				p[n++] = IWS;
			}
			p[n-1] = 0;
			envput(v->name, p);
		} else
			envput(v->name, "");
		free(p);
	}

	if(v->fnchanged){
		v->fnchanged=0;
		snprint(buf, sizeof(buf), "fn#%s", v->name);
		f = openstr();
		pfmt(f, "fn %s %s\n", v->name, v->fn[v->pc-1].s);
		envput(buf, f->strp);
		closeio(f);
	}
}

void
updenvlocal(Var *v)
{
	if(v){
		updenvlocal(v->next);
		addenv(v);
	}
}
