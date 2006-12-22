#include <lib9.h>
#include <draw.h>
#include <interp.h>
#include <isa.h>
#include "../libinterp/runt.h"
#include <drawif.h>
#include <prefab.h>
#include <kernel.h>

List*
prefabwrap(void *elem)
{
	List *l;
	Heap *h, *e;

	e = D2H(elem);
	h = nheap(sizeof(List) + sizeof(WORD*));
	h->t = &Tlist;
	Tlist.ref++;
	l = H2D(List*, h);
	l->tail = H;
	l->t = &Tptr;
	Tptr.ref++;
	e->ref++;
	*(WORD**)l->data = elem;
	return l;
}

static
PElement*
elistelement1(Prefab_Environ *e, Prefab_Element *elem, Prefab_Element *new, enum Elementtype kind)
{
	int first;
	PElement *pelem;
	List *atom;

	if(badenviron(e, 0))
		return H;

	gchalt++;
	first = 0;
	if(new == H)
		atom = H;
	else
		atom = prefabwrap(new);
	if(elem == H){
		pelem = mkelement(e, kind);
		elem = &pelem->e;
		pelem->first = H;
		pelem->nkids = 0;
	}else
		pelem = (PElement*)elem;
	if(atom == H)
		goto Return;

	if(elem->kids != pelem->first)
		error("list Element has been modified externally");
	if(elem->kids == H){
		elem->kids = atom;
		pelem->first = atom;
		pelem->last = atom;
		pelem->vfirst = atom;
		pelem->vlast = atom;
		first = 1;
	}
	if(new->kind!=ESeparator && Dx(elem->r)==0){
		elem->r = new->r;
		pelem->drawpt.x = elem->r.min.x;
		pelem->drawpt.y = elem->r.min.y;
	}
	pelem->nkids++;
	if(first)
		goto Return;
	pelem->last->tail = atom;
	pelem->last = atom;
	pelem->vlast = atom;
	if(new->kind != ESeparator){
		if(kind == EVertical){
			elem->r.max.y += Dy(new->r);
			if(elem->r.min.x > new->r.min.x)
				elem->r.min.x = new->r.min.x;
			if(elem->r.max.x < new->r.max.x)
				elem->r.max.x = new->r.max.x;
		}else{
			elem->r.max.x += Dx(new->r);
			if(elem->r.min.y > new->r.min.y)
				elem->r.min.y = new->r.min.y;
			if(elem->r.max.y < new->r.max.y)
				elem->r.max.y = new->r.max.y;
		}
	}
	pelem->pkind = kind;

    Return:
	gchalt--;
	return pelem;
}

PElement*
elistelement(Prefab_Environ *e, Prefab_Element *new, enum Elementtype kind)
{
	return elistelement1(e, H, new, kind);
}

PElement*
appendelist(Prefab_Element *elem, Prefab_Element *new)
{
	if(elem->kind!=EVertical && elem->kind!=EHorizontal){
		kwerrstr("appendelist to non-list");
		return H;
	}
	return elistelement1(elem->environ, elem, new, elem->kind);
}
