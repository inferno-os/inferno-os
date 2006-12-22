#include <lib9.h>
#include <bio.h>
#include <ctype.h>
#include "mach.h"
#define Extern extern
#include "acid.h"
#include "y.tab.h"

static int syren;

Lsym*
unique(char *buf, Sym *s)
{
	Lsym *l;
	int i, renamed;

	renamed = 0;
	strcpy(buf, s->name);
	for(;;) {
		l = look(buf);
		if(l == 0 || (l->lexval == Tid && l->v->set == 0))
			break;

		if(syren == 0 && !quiet) {
			print("Symbol renames:\n");
			syren = 1;
		}
		i = strlen(buf)+1;
		memmove(buf+1, buf, i);
		buf[0] = '$';
		renamed++;
		if(renamed > 5 && !quiet) {
			print("Too many renames; must be X source!\n");
			break;
		}
	}
	if(renamed && !quiet)
		print("\t%s=%s %c/%lux\n", s->name, buf, s->type, s->value);
	if(l == 0)
		l = enter(buf, Tid);
	return l;	
}

void
varsym(void)
{
	int i;
	Sym *s;
	long n;
	Lsym *l;
	ulong v;
	char buf[1024];
	List *list, **tail, *l2, *tl;

	tail = &l2;
	l2 = 0;

	symbase(&n);
	for(i = 0; i < n; i++) {
		s = getsym(i);
		switch(s->type) {
		case 'T':
		case 'L':
		case 'D':
		case 'B':
		case 'b':
		case 'd':
		case 'l':
		case 't':
			if(s->name[0] == '.')
				continue;

			v = s->value;
			tl = al(TLIST);
			*tail = tl;
			tail = &tl->next;

			l = unique(buf, s);

			l->v->set = 1;
			l->v->type = TINT;
			l->v->vstore.u0.sival = v;
			if(l->v->vstore.comt == 0)
				l->v->vstore.fmt = 'X';

			/* Enter as list of { name, type, value } */
			list = al(TSTRING);
			tl->lstore.u0.sl = list;
			list->lstore.u0.sstring = strnode(buf);
			list->lstore.fmt = 's';
			list->next = al(TINT);
			list = list->next;
			list->lstore.fmt = 'c';
			list->lstore.u0.sival = s->type;
			list->next = al(TINT);
			list = list->next;
			list->lstore.fmt = 'X';
			list->lstore.u0.sival = v;

		}
	}
	l = mkvar("symbols");
	l->v->set = 1;
	l->v->type = TLIST;
	l->v->vstore.u0.sl = l2;
	if(l2 == 0)
		print("no symbol information\n");
}

void
varreg(void)
{
	Lsym *l;
	Value *v;
	Reglist *r;
	List **tail, *li;

	l = mkvar("registers");
	v = l->v;
	v->set = 1;
	v->type = TLIST;
	v->vstore.u0.sl = 0;
	tail = &v->vstore.u0.sl;

	for(r = mach->reglist; r->rname; r++) {
		l = mkvar(r->rname);
		v = l->v;
		v->set = 1;
		v->vstore.u0.sival = r->roffs;
		v->vstore.fmt = r->rformat;
		v->type = TINT;

		li = al(TSTRING);
		li->lstore.u0.sstring = strnode(r->rname);
		li->lstore.fmt = 's';
		*tail = li;
		tail = &li->next;
	}

	if(machdata == 0)
		return;

	l = mkvar("bpinst");	/* Breakpoint text */
	v = l->v;
	v->type = TSTRING;
	v->vstore.fmt = 's';
	v->set = 1;
	v->vstore.u0.sstring = gmalloc(sizeof(String));
	v->vstore.u0.sstring->len = machdata->bpsize;
	v->vstore.u0.sstring->string = gmalloc(machdata->bpsize);
	memmove(v->vstore.u0.sstring->string, machdata->bpinst, machdata->bpsize);
}

void
loadvars(void)
{
	Lsym *l;
	Value *v;

	l =  mkvar("proc");
	v = l->v;
	v->type = TINT;
	v->vstore.fmt = 'X';
	v->set = 1;
	v->vstore.u0.sival = 0;

	l = mkvar("pid");		/* Current process */
	v = l->v;
	v->type = TINT;
	v->vstore.fmt = 'D';
	v->set = 1;
	v->vstore.u0.sival = 0;

	mkvar("notes");			/* Pending notes */

	l = mkvar("proclist");		/* Attached processes */
	l->v->type = TLIST;

	l = mkvar("rdebug");		/* remote debugging enabled? */
	v = l->v;
	v->type = TINT;
	v->vstore.fmt = 'D';
	v->set = 1;
	v->vstore.u0.sival = rdebug;

	if(rdebug) {
		l = mkvar("_breakid");
		v = l->v;
		v->type = TINT;
		v->vstore.fmt = 'D';
		v->set = 1;
		v->vstore.u0.sival = -1;
	}
}

vlong
rget(Map *map, char *reg)
{
	Lsym *s;
	long x;
	vlong v;
	int ret;

	s = look(reg);
	if(s == 0)
		fatal("rget: %s\n", reg);

	if(s->v->vstore.fmt == 'Y')
		ret = get8(map, (long)s->v->vstore.u0.sival, &v);
	else {
		ret = get4(map, (long)s->v->vstore.u0.sival, &x);
		v = x;
	}
	if(ret < 0)
		error("can't get register %s: %r\n", reg);
	return v;
}

String*
strnodlen(char *name, int len)
{
	String *s;

	s = gmalloc(sizeof(String)+len+1);
	s->string = (char*)s+sizeof(String);
	s->len = len;
	if(name != 0)
		memmove(s->string, name, len);
	s->string[len] = '\0';

	s->sgc.gclink = gcl;
	gcl = &s->sgc;

	return s;
}

String*
strnode(char *name)
{
	return strnodlen(name, strlen(name));
}

String*
runenode(Rune *name)
{
	int len;
	Rune *p;
	String *s;

	p = name;
	for(len = 0; *p; p++)
		len++;

	len++;
	len *= sizeof(Rune);
	s = gmalloc(sizeof(String)+len);
	s->string = (char*)s+sizeof(String);
	s->len = len;
	memmove(s->string, name, len);

	s->sgc.gclink = gcl;
	gcl = &s->sgc;

	return s;
}

String*
stradd(String *l, String *r)
{
	int len;
	String *s;

	len = l->len+r->len;
	s = gmalloc(sizeof(String)+len+1);
	s->sgc.gclink = gcl;
	gcl = &s->sgc;
	s->len = len;
	s->string = (char*)s+sizeof(String);
	memmove(s->string, l->string, l->len);
	memmove(s->string+l->len, r->string, r->len);
	s->string[s->len] = 0;
	return s;
}

int
scmp(String *sr, String *sl)
{
	if(sr->len != sl->len)
		return 0;

	if(memcmp(sr->string, sl->string, sl->len))
		return 0;

	return 1;
}
