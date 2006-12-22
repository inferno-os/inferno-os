#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "raise.h"
#include <kernel.h>

static void
newlink(Link *l, char *fn, int sig, Type *t)
{
	l->name = malloc(strlen(fn)+1);
	if(l->name == nil)
		error(exNomem);
	strcpy(l->name, fn);
	l->sig = sig;
	l->frame = t;
}

void
runtime(Module *m, Link *l, char *fn, int sig, void (*runt)(void*), Type *t)
{
	USED(m);
	newlink(l, fn, sig, t);
	l->u.runt = runt;
}

void
mlink(Module *m, Link* l, uchar *fn, int sig, int pc, Type *t)
{
	newlink(l, (char*)fn, sig, t);
	l->u.pc = m->prog+pc;
}

static int
linkm(Module *m, Modlink *ml, int i, Import *ldt)
{
	Link *l;
	int sig;
	char e[ERRMAX];

	sig = ldt->sig;
	for(l = m->ext; l->name; l++)
		if(strcmp(ldt->name, l->name) == 0)
			break;

	if(l == nil) {
		snprint(e, sizeof(e), "link failed fn %s->%s() not implemented", m->name, ldt->name);
		goto bad;
	}
	if(l->sig != sig) {
		snprint(e, sizeof(e), "link typecheck %s->%s() %ux/%ux",
							m->name, ldt->name, l->sig, sig);
		goto bad;
	}

	ml->links[i].u = l->u;
	ml->links[i].frame = l->frame;
	return 0;
bad:
	kwerrstr(e);
	print("%s\n", e);
	return -1;
}

Modlink*
mklinkmod(Module *m, int n)
{
	Heap *h;
	Modlink *ml;

	h = nheap(sizeof(Modlink)+(n-1)*sizeof(ml->links[0]));
	h->t = &Tmodlink;
	Tmodlink.ref++;
	ml = H2D(Modlink*, h);
	ml->nlinks = n;
	ml->m = m;
	ml->prog = m->prog;
	ml->type = m->type;
	ml->compiled = m->compiled;
	ml->MP = H;
	ml->data = nil;

	return ml;
}

Modlink*
linkmod(Module *m, Import *ldt, int mkmp)
{
	Type *t;
	Heap *h;
	int i;
	Modlink *ml;
	Import *l;

	if(m == nil)
		return H;

	for(i = 0, l = ldt; l->name != nil; i++, l++)
		;
	ml = mklinkmod(m, i);

	if(mkmp){
		if(m->rt == DYNMOD)
			newdyndata(ml);
		else if(mkmp && m->origmp != H && m->ntype > 0) {
			t = m->type[0];
			h = nheap(t->size);
			h->t = t;
			t->ref++;
			ml->MP = H2D(uchar*, h);
			newmp(ml->MP, m->origmp, t);
		}
	}

	for(i = 0, l = ldt; l->name != nil; i++, l++) {
		if(linkm(m, ml, i, l) < 0){
			destroy(ml);
			return H;
		}
	}

	return ml;
}

void
destroylinks(Module *m)
{
	Link *l;

	for(l = m->ext; l->name; l++)
		free(l->name);
	free(m->ext);
}
