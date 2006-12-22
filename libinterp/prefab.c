#include <lib9.h>
#include <kernel.h>
#include "interp.h"
#include "isa.h"
#include "runt.h"
#include "prefabmod.h"
#include "draw.h"
#include "drawif.h"
#include "prefab.h"
#include "raise.h"

uchar elementmap[] = Prefab_Element_map;
uchar compoundmap[] = Prefab_Compound_map;
uchar layoutmap[] = Prefab_Layout_map;

void	freeprefabcompound(Heap*, int);

Type*	TCompound;
Type*	TElement;
Type*	TLayout;

/* Infrared remote buttons known to Compound_select */
enum
{
	IRFF		= 14,
	IRRew		= 15,
	IRUp		= 16,
	IRDn		= 17,
	IRSelect	= 18,
	IREnter	= 20,
};

void
prefabmodinit(void)
{
	TElement = dtype(freeheap, sizeof(PElement), elementmap, sizeof(elementmap));
	TLayout = dtype(freeheap, Prefab_Layout_size, layoutmap, sizeof(layoutmap));
	TCompound = dtype(freeprefabcompound, sizeof(PCompound), compoundmap, sizeof(compoundmap));
	builtinmod("$Prefab", Prefabmodtab, Prefabmodlen);
}

PElement*
checkelement(Prefab_Element *de)
{
	PElement *pe;

	pe = lookupelement(de);
	if(pe == H)
		error(exType);
	return pe;
}

PCompound*
checkcompound(Prefab_Compound *de)
{
	PCompound *pe;

	pe = lookupcompound(de);
	if(pe == H)
		error(exType);
	return pe;
}

PElement*
lookupelement(Prefab_Element *de)
{
	PElement *pe;
	if(de == H)
		return H;
	if(D2H(de)->t != TElement)
		return H;
	pe = (PElement*)de;
	if(de->kind!=pe->pkind || de->kids!=pe->first)
		return H;
	return pe;
}

PCompound*
lookupcompound(Prefab_Compound *dc)
{
	if(dc == H)
		return H;
	if(D2H(dc)->t != TCompound)
		return H;
	return (PCompound*)dc;
}

void
freeprefabcompound(Heap *h, int swept)
{
	Image *i;
	Prefab_Compound *d;
	PCompound *pc;

	d = H2D(Prefab_Compound*, h);
	pc = lookupcompound(d);
	/* disconnect compound from image refresh daemon */
	i = lookupimage(pc->c.image);
	if(i != nil)
		delrefresh(i);
	if(!swept && TCompound->np)
		freeptrs(d, TCompound);
	/* header will be freed by caller */
}

static
PElement*
findtag(PElement *pelem, char *tag)
{
	PElement *pe, *t;
	List *l;

	if(pelem==H || tag[0]==0)
		return pelem;
	for(l=pelem->first; l!=H; l=l->tail){
		pe = *(PElement**)l->data;
		if(strcmp(tag, string2c(pe->e.tag)) == 0)
			return pe;
		else if(pe->pkind==EHorizontal || pe->pkind==EVertical){
			t = findtag(pe, tag);
			if(t != H)
				return t;
		}
	}
	return H;
}

int
badenviron(Prefab_Environ *env, int err)
{
	Prefab_Style *s;

	if(env == H)
		goto bad;
	s = env->style;
	if(s == H)
		goto bad;
	if(s->titlefont==H || s->textfont==H)
		goto bad;
	if(s->elemcolor==H || s->edgecolor==H)
		goto bad;
	if(s->titlecolor==H || s->textcolor==H || s->highlightcolor==H)
		goto bad;
	return 0;
bad:
	if(err)
		error(exType);
	return 1;
}

void
Element_iconseparator(void *fp, int kind)
{
	F_Element_icon *f;
	PElement *e;
	Image *icon;
	int locked;

	f = fp;
	badenviron(f->env, 1);
	checkimage(f->mask);
	icon = checkimage(f->icon);
	locked = lockdisplay(icon->display);
	destroy(*f->ret);
	*f->ret = H;
	if(kind == ESeparator)
		e = separatorelement(f->env, f->r, f->icon, f->mask);
	else
		e = iconelement(f->env, f->r, f->icon, f->mask);
	*f->ret = (Prefab_Element*)e;
	if(locked)
		unlockdisplay(icon->display);
}

void
Element_icon(void *fp)
{
	Element_iconseparator(fp, EIcon);
}

void
Element_separator(void *fp)
{
	Element_iconseparator(fp, ESeparator);
}

void
Element_text(void *fp)
{
	F_Element_text *f;
	PElement *pelem;
	Display *disp;
	int locked;

	f = fp;
	badenviron(f->env, 1);
	if(f->kind!=EText && f->kind!=ETitle)
		return;

	disp = checkscreen(f->env->screen)->display;
	locked = lockdisplay(disp);
	destroy(*f->ret);
	*f->ret = H;
	pelem = textelement(f->env, f->text, f->r, f->kind);
	*f->ret = (Prefab_Element*)pelem;
	if(locked)
		unlockdisplay(disp);
}

void
Element_layout(void *fp)
{
	F_Element_layout *f;
	PElement *pelem;
	Display *disp;
	int locked;

	f = fp;
	badenviron(f->env, 1);
	if(f->kind!=EText && f->kind!=ETitle)
		return;

	disp = checkscreen(f->env->screen)->display;
	locked = lockdisplay(disp);
	destroy(*f->ret);
	*f->ret = H;
	pelem = layoutelement(f->env, f->lay, f->r, f->kind);
	*f->ret = (Prefab_Element*)pelem;
	if(locked)
		unlockdisplay(disp);
}

void
Element_elist(void *fp)
{
	F_Element_elist *f;
	PElement *pelist;
	Display *disp;
	int locked;

	f = fp;
	if(f->elem != H)
		checkelement(f->elem);
	badenviron(f->env, 1);
	if(f->kind!=EHorizontal && f->kind!=EVertical)
		return;

	disp = checkscreen(f->env->screen)->display;
	locked = lockdisplay(disp);
	destroy(*f->ret);
	*f->ret = H;
	pelist = elistelement(f->env, f->elem, f->kind);
	*f->ret = (Prefab_Element*)pelist;
	if(locked)
		unlockdisplay(disp);
}

void
Element_append(void *fp)
{
	F_Element_append *f;

	f = fp;
	*f->ret = 0;
	if(f->elist==H || f->elem==H)
		return;

	badenviron(f->elist->environ, 1);
	checkelement(f->elist);
	checkelement(f->elem);

	if(f->elist->kind!=EHorizontal && f->elist->kind!=EVertical)
		return;

	if(appendelist(f->elist, f->elem) != H)
		*f->ret = 1;
}

void
Element_adjust(void *fp)
{
	F_Element_adjust *f;
	Display *disp;
	int locked;

	f = fp;
	checkelement(f->elem);
	badenviron(f->elem->environ, 1);
	disp = checkscreen(f->elem->environ->screen)->display;
	locked = lockdisplay(disp);
	adjustelement(f->elem, f->equal, f->dir);
	if(locked)
		unlockdisplay(disp);
}

void
Element_show(void *fp)
{
	F_Element_show *f;
	Display *disp;
	int locked;

	f = fp;
	checkelement(f->elem);
	checkelement(f->elist);
	badenviron(f->elem->environ, 1);
	disp = checkscreen(f->elem->environ->screen)->display;
	locked = lockdisplay(disp);
	*f->ret = showelement(f->elist, f->elem);
	if(locked)
		unlockdisplay(disp);
}

void
Element_clip(void *fp)
{
	F_Element_clip *f;
	Rectangle r;
	Display *disp;
	int locked;

	f = fp;
	checkelement(f->elem);
	badenviron(f->elem->environ, 1);
	R2R(r, f->r);
	disp = checkscreen(f->elem->environ->screen)->display;
	locked = lockdisplay(disp);
	clipelement(f->elem, r);
	if(locked)
		unlockdisplay(disp);
}

void
Element_translatescroll(void *fp, int trans)
{
	F_Element_scroll *f;
	Point d;
	Display *disp;
	int locked, moved;

	f = fp;
	checkelement(f->elem);
	badenviron(f->elem->environ, 1);
	P2P(d, f->d);
	disp = checkscreen(f->elem->environ->screen)->display;
	locked = lockdisplay(disp);
	if(trans)
		translateelement(f->elem, d);
	else{
		moved = 0;
		scrollelement(f->elem, d, &moved);
	}
	if(locked)
		unlockdisplay(disp);
}

void
Element_scroll(void *fp)
{
	Element_translatescroll(fp, 0);
}

void
Element_translate(void *fp)
{
	Element_translatescroll(fp, 1);
}

void
Compound_iconbox(void *fp)
{
	F_Compound_iconbox *f;
	Image *icon;
	int locked;
	PCompound *pc;

	f = fp;
	badenviron(f->env, 1);
	checkimage(f->mask);
	icon = checkimage(f->icon);
	locked = lockdisplay(icon->display);
	destroy(*f->ret);
	*f->ret = H;
	pc = iconbox(f->env, f->p, f->title, f->icon, f->mask);
	*f->ret = &pc->c;
	if(locked)
		unlockdisplay(icon->display);
}

void
Compound_textbox(void *fp)
{
	F_Compound_textbox *f;
	Display *disp;
	int locked;
	PCompound *pc;

	f = fp;
	badenviron(f->env, 1);
	disp = checkscreen(f->env->screen)->display;
	locked = lockdisplay(disp);
	destroy(*f->ret);
	*f->ret = H;
	pc = textbox(f->env, f->r, f->title, f->text);
	*f->ret = &pc->c;
	if(locked)
		unlockdisplay(disp);
}

void
Compound_layoutbox(void *fp)
{
	F_Compound_layoutbox *f;
	Display *disp;
	int locked;
	PCompound *pc;

	f = fp;
	badenviron(f->env, 1);
	disp = checkscreen(f->env->screen)->display;
	locked = lockdisplay(disp);
	destroy(*f->ret);
	*f->ret = H;
	pc = layoutbox(f->env, f->r, f->title, f->lay);
	*f->ret = &pc->c;
	if(locked)
		unlockdisplay(disp);
}

void
Compound_box(void *fp)
{
	F_Compound_box *f;
	Display *disp;
	int locked;
	PCompound *pc;

	f = fp;
	badenviron(f->env, 1);
	if(f->title != H)
		checkelement(f->title);
	checkelement(f->elist);
	disp = checkscreen(f->env->screen)->display;
	locked = lockdisplay(disp);
	destroy(*f->ret);
	*f->ret = H;
	pc = box(f->env, f->p, f->title, f->elist);
	*f->ret = &pc->c;
	if(locked)
		unlockdisplay(disp);
}

void
Compound_draw(void *fp)
{
	F_Compound_draw *f;
	PCompound *pc;
	int locked;

	f = fp;
	if(f->comp == H)
		return;
	pc = checkcompound(f->comp);
	badenviron(pc->c.environ, 1);
	locked = lockdisplay(pc->display);
	drawcompound(&pc->c);
	flushimage(pc->display, 1);
	if(locked)
		unlockdisplay(pc->display);
}

void
Compound_redraw(void *fp)
{
	F_Compound_redraw *f;
	PCompound *pc;
	Image *i;
	int locked;

	f = fp;
	if(f->comp == H)
		return;
	pc = checkcompound(f->comp);
	badenviron(pc->c.environ, 1);
	i = checkimage(pc->c.image);
	locked = lockdisplay(pc->display);
	redrawcompound(i, IRECT(f->r), &pc->c);
	flushimage(pc->display, 1);
	if(locked)
		unlockdisplay(pc->display);
}

static
PElement*
pelement(Prefab_Compound *comp, Prefab_Element *elem)
{
	PElement *pe;

	if(comp == H)
		return H;
	checkcompound(comp);
	badenviron(comp->environ, 1);
	pe = lookupelement(elem);
	return pe;
}

void
Compound_highlight(void *fp)
{
	F_Compound_highlight *f;
	PCompound *pc;
	PElement *pe;
	Image *i;
	int locked;

	f = fp;
	pe = pelement(f->comp, f->elem);
	if(pe == H)
		return;
	pc = (PCompound*)f->comp;
	i = checkimage(pc->c.image);
	locked = lockdisplay(pc->display);
	highlightelement(&pe->e, i, &pc->c, f->on);
	flushimage(pc->display, 1);
	if(locked)
		unlockdisplay(pc->display);
}

void
Compound_scroll(void *fp)
{
	F_Compound_scroll *f;
	PCompound *pc;
	PElement *pe;
	int locked;
	Image *i;
	int moved;

	f = fp;
	pe = pelement(f->comp, f->elem);
	if(pe == H)
		return;
	pc = (PCompound*)f->comp;
	i = checkimage(pc->c.image);
	locked = lockdisplay(pc->display);
	moved = 0;
	scrollelement(&pe->e, IPOINT(f->d), &moved);
	if(moved){
		drawelement(&pe->e, i, IRECT(pe->e.r), 0, 0);
		flushimage(pc->display, 1);
	}
	if(locked)
		unlockdisplay(pc->display);
}

void
Compound_show(void *fp)
{
	F_Compound_show *f;
	PCompound *pc;
	PElement *pe;
	int locked;

	f = fp;
	pe = pelement(f->comp, f->elem);
	if(pe == H)
		return;
	pc = (PCompound*)f->comp;
	locked = lockdisplay(pc->display);
	*f->ret = showelement(pc->c.contents, &pe->e);
	flushimage(pc->display, 1);
	if(locked)
		unlockdisplay(pc->display);
}

static
PElement*
element(PElement *plist, int index, int *ip)
{
	int i;
	PElement *pe;
	List *l;

	i = 0;
	pe = H;
	for(l=plist->first; l!=H; l=l->tail){
		pe = *(PElement**)l->data;
		if(pe->pkind == ESeparator)
			continue;
		if(i == index)
			break;
		i++;
	}
	if(ip)
		*ip = i;
	if(l == H)
		return H;
	return pe;
}

static
int
wrapelement(PElement *plist, int index, int ntag)
{
	int i, wrap;

	if(ntag > 0){
		if(index < 0)
			return ntag-1;
		if(index >= ntag)
			return 0;
		return index;
	}
	wrap = 1;
	if(index < 0){
		index = 1000000;	/* will seek to end */
		wrap = 0;
	}
	if(element(plist, index, &i)==H && index!=0){
		if(wrap)	/* went off end; wrap to beginning */
			return wrapelement(plist, 0, 0);
		if(i > 0)
			--i;
	}
	return i;
}

void
dohighlight(PCompound *pc, PElement *list, PElement *pe, int on)
{
	Image *i;

	/* see if we need to scroll */
	i = lookupimage(pc->c.image);
	if(i == nil)
		return;
	if(on && showelement(&list->e, &pe->e))
		redrawcompound(i, IRECT(pc->c.contents->r), &pc->c);
	highlightelement(&pe->e, i, &pc->c, on);
}

void
highlight(PCompound *pc, PElement *list, int index, int on)
{
	dohighlight(pc, list, element(list, index, nil), on);
}

static
PElement**
tags(PElement *pelem, int *ntag)
{
	int n, nalloc, nn;
	List *l;
	PElement *pe, **tagged, **ntagged;

	n = 0;
	nalloc = 0;
	tagged = nil;
	*ntag = 0;
	for(l=pelem->first; l!=H; l=l->tail){
		pe = *(PElement**)l->data;
		if(pe->e.tag != H){
			if(nalloc == n){
				nalloc += 10;
				tagged = realloc(tagged, nalloc*sizeof(PElement*));
				if(tagged == nil)
					return nil;
			}
			tagged[n++] = pe;
		}else if(pe->pkind==EHorizontal || pe->pkind==EVertical){
			ntagged = tags(pe, &nn);
			if(nn > 0){
				if(nalloc < n+nn){
					nalloc = n+nn+10;
					tagged = realloc(tagged, nalloc*sizeof(PElement*));
					if(tagged == nil){
						free(ntagged);
						return nil;
					}
				}
				memmove(tagged+n, ntagged, nn*sizeof(PElement*));
				free(ntagged);
				n += nn;
			}
		}
	}
	*ntag = n;
	return tagged;
}

void
doselect(void *fp, int dotags)
{
	F_Compound_select *f;
	PCompound *pc;
	PElement *pe;
	WORD *val;
	List *l;
	Prefab_Element *t;
	int i, lasti, ntag;
	PElement **tagged;
	int locked;

	f = fp;
	pc = checkcompound(f->comp);
	pe = lookupelement(f->elem);
	if(pe->pkind!=EHorizontal && pe->pkind!=EVertical || pe->nkids == 0){
    Bad:
		destroy(f->ret->t2);
		f->ret->t0 = 9999;
		f->ret->t1 = 0;
		f->ret->t2 = H;
		return;
	}
	ntag = 0;
	tagged = 0;
	/* check at least one selectable item */
	if(dotags){
		tagged = tags(pe, &ntag);
		if(ntag > 0)
			goto OK;
	}else
		for(l=pe->first; l!=H; l=l->tail){
			t = *(Prefab_Element**)l->data;
			if(t->kind != ESeparator)
				goto OK;
		}
	goto Bad;

    OK:
	i = f->i;
	i = wrapelement(pe, i, ntag);
	lasti = i;
	locked = lockdisplay(pc->display);
	if(dotags)
		dohighlight(pc, pe, tagged[i], 1);
	else
		highlight(pc, pe, i, 1);
	/* val must be in shared memory, but stacks not shared */
	val = malloc(sizeof(WORD));
	if(val == nil)
		goto Bad;
	for(;;){
		if(lasti != i){
			if(dotags){
				dohighlight(pc, pe, tagged[lasti], 0);
				dohighlight(pc, pe, tagged[i], 1);
			}else{
				highlight(pc, pe, lasti, 0);
				highlight(pc, pe, i, 1);
			}
			lasti = i;
		}
		flushimage(pc->display, 1);
		if(locked)
			unlockdisplay(pc->display);
		crecv(f->c, val);
		locked = lockdisplay(pc->display);
		switch(*val){
		case IRUp:
			if(pe->pkind != EVertical)
				goto Default;
			goto Up;
		case IRRew:
			if(pe->pkind != EHorizontal)
				goto Default;
		Up:
			i = wrapelement(pe, i-1, ntag);
			break;
		case IRSelect:
			if(dotags)
				dohighlight(pc, pe, tagged[i], 0);
			else
				highlight(pc, pe, i, 0);
			f->ret->t0 = *val;
			f->ret->t1 = i;
    Return:
			flushimage(pc->display, 1);
			if(dotags)
				pe = tagged[i];
			else
				pe = element(pe, i, nil);
			destroy(f->ret->t2);
			D2H(pe)->ref++;
			f->ret->t2 = &pe->e;
			if(locked)
				unlockdisplay(pc->display);
			free(val);
			free(tagged);
			return;
		case IRDn:
			if(pe->pkind != EVertical)
				goto Default;
			goto Down;
		case IRFF:
			if(pe->pkind != EHorizontal)
				goto Default;
		Down:
			i = wrapelement(pe, i+1, ntag);
			break;
		default:
    Default:
			if(dotags)
				dohighlight(pc, pe, tagged[lasti], 0);
			else
				highlight(pc, pe, lasti, 0);
			f->ret->t0 = *val;
			f->ret->t1 = i;
			goto Return;
		}
	}
}

void
Compound_tagselect(void *fp)
{
	doselect(fp, 1);
}

void
Compound_select(void *fp)
{
	doselect(fp, 0);
}
