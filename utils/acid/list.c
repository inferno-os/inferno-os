#include <lib9.h>
#include <bio.h>
#include <ctype.h>
#include "mach.h"
#define Extern extern
#include "acid.h"

static List **tail;

List*
construct(Node *l)
{
	List *lh, **save;

	save = tail;
	lh = 0;
	tail = &lh;
	build(l);
	tail = save;

	return lh;
}

int
listlen(List *l)
{
	int len;

	len = 0;
	while(l) {
		len++;
		l = l->next;
	}
	return len;
}

void
build(Node *n)
{
	List *l;
	Node res;

	if(n == 0)
		return;

	switch(n->op) {
	case OLIST:
		build(n->left);
		build(n->right);
		return;
	default:
		expr(n, &res);
		l = al(res.type);
		l->lstore = res.nstore;
		*tail = l;
		tail = &l->next;	
	}
}

List*
addlist(List *l, List *r)
{
	List *f;

	if(l == 0)
		return r;

	for(f = l; f->next; f = f->next)
		;
	f->next = r;

	return l;
}

void
append(Node *r, Node *list, Node *val)
{
	List *l, *f;

	l = al(val->type);
	l->lstore = val->nstore;
	l->next = 0;

	r->op = OCONST;
	r->type = TLIST;

	if(list->nstore.u0.sl == 0) {
		list->nstore.u0.sl = l;
		r->nstore.u0.sl = l;
		return;
	}
	for(f = list->nstore.u0.sl; f->next; f = f->next)
		;
	f->next = l;
	r->nstore.u0.sl = list->nstore.u0.sl;
}

int
listcmp(List *l, List *r)
{
	if(l == r)
		return 1;

	while(l) {
		if(r == 0)
			return 0;
		if(l->type != r->type)
			return 0;
		switch(l->type) {
		case TINT:
			if(l->lstore.u0.sival != r->lstore.u0.sival)
				return 0;
			break;
		case TFLOAT:
			if(l->lstore.u0.sfval != r->lstore.u0.sfval)
				return 0;
			break;
		case TSTRING:
			if(scmp(l->lstore.u0.sstring, r->lstore.u0.sstring) == 0)
				return 0;
			break;
		case TLIST:
			if(listcmp(l->lstore.u0.sl, r->lstore.u0.sl) == 0)
				return 0;
			break;
		}
		l = l->next;
		r = r->next;
	}
	if(l != r)
		return 0;
	return 1;
}

void
nthelem(List *l, int n, Node *res)
{
	if(n < 0)
		error("negative index in []");

	while(l && n--)
		l = l->next;

	res->op = OCONST;
	if(l == 0) {
		res->type = TLIST;
		res->nstore.u0.sl = 0;
		return;
	}
	res->type = l->type;
	res->nstore = l->lstore;
}

void
delete(List *l, int n, Node *res)
{
	List **tl;

	if(n < 0)
		error("negative index in delete");

	res->op = OCONST;
	res->type = TLIST;
	res->nstore.u0.sl = l;

	for(tl = &res->nstore.u0.sl; l && n--; l = l->next)
		tl = &l->next;

	if(l == 0)
		error("element beyond end of list");
	*tl = l->next;
}

List*
listvar(char *s, long v)
{
	List *l, *tl;

	tl = al(TLIST);

	l = al(TSTRING);
	tl->lstore.u0.sl = l;
	l->lstore.fmt = 's';
	l->lstore.u0.sstring = strnode(s);
	l->next = al(TINT);
	l = l->next;
	l->lstore.fmt = 'X';
	l->lstore.u0.sival = v;

	return tl;
}

static List*
listlocals(Map *map, Symbol *fn, ulong fp)
{
	int i;
	uvlong val;
	Symbol s;
	List **tail, *l2;

	l2 = 0;
	tail = &l2;
	s = *fn;

	for(i = 0; localsym(&s, i); i++) {
		if(s.class != CAUTO)
			continue;
		if(s.name[0] == '.')
			continue;

		if(geta(map, fp-s.value, &val) > 0) {
			*tail = listvar(s.name, val);
			tail = &(*tail)->next;
		}
	}
	return l2;
}

static List*
listparams(Map *map, Symbol *fn, ulong fp)
{
	int i;
	Symbol s;
	uvlong v;
	List **tail, *l2;

	l2 = 0;
	tail = &l2;
	fp += mach->szaddr;			/* skip saved pc */
	s = *fn;
	for(i = 0; localsym(&s, i); i++) {
		if (s.class != CPARAM)
			continue;

		if(geta(map, fp+s.value, &v) > 0) {
			*tail = listvar(s.name, v);
			tail = &(*tail)->next;
		}
	}
	return l2;
}

void
trlist(Map *map, uvlong pc, uvlong sp, Symbol *sym)
{
	List *q, *l;

	static List **tail;

	if (tracelist == 0) {		/* first time */
		tracelist = al(TLIST);
		tail = &tracelist;
	}

	q = al(TLIST);
	*tail = q;
	tail = &q->next;

	l = al(TINT);			/* Function address */
	q->lstore.u0.sl = l;
	l->lstore.u0.sival = sym->value;
	l->lstore.fmt = 'X';

	l->next = al(TINT);		/* called from address */
	l = l->next;
	l->lstore.u0.sival = pc;
	l->lstore.fmt = 'X';

	l->next = al(TLIST);		/* make list of params */
	l = l->next;
	l->lstore.u0.sl = listparams(map, sym, sp);

	l->next = al(TLIST);		/* make list of locals */
	l = l->next;
	l->lstore.u0.sl = listlocals(map, sym, sp);
}
