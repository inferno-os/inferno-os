#include <lib9.h>
#include <draw.h>
#include <interp.h>
#include <isa.h>
#include "../libinterp/runt.h"
#include <drawif.h>
#include <prefab.h>


void	icondraw(Prefab_Element*, Image*, Rectangle, int, int);
void	textdraw(Prefab_Element*, Image*, Rectangle, int, int);
void	listdraw(Prefab_Element*, Image*, Rectangle, int, int);
void	outlinehighlight(Prefab_Element*, Image*, Prefab_Compound*, int);
void	texthighlight(Prefab_Element*, Image*, Prefab_Compound*, int);
void	simpleclip(Prefab_Element*, Rectangle);
void	horizontalclip(Prefab_Element*, Rectangle);
void	verticalclip(Prefab_Element*, Rectangle);
void	textscroll(Prefab_Element*, Point, int*);
void	horizontalscroll(Prefab_Element*, Point, int*);
void	verticalscroll(Prefab_Element*, Point, int*);
void	iconscroll(Prefab_Element*, Point, int*);

struct
{
	void	(*draw)(Prefab_Element*, Image*, Rectangle, int, int);
	void	(*highlight)(Prefab_Element*, Image*, Prefab_Compound*, int);
	void	(*clip)(Prefab_Element*, Rectangle);
	void	(*scroll)(Prefab_Element*, Point, int*);
}elemfn[] = {
 /* EIcon */		{ icondraw, outlinehighlight, simpleclip, iconscroll, },
 /* EText */		{ textdraw, texthighlight, simpleclip, textscroll, },
 /* ETitle */		{ textdraw, outlinehighlight, simpleclip, textscroll, },
 /* EHorizontal */	{ listdraw, outlinehighlight, horizontalclip, horizontalscroll, },
 /* EVertical */	{ listdraw, outlinehighlight, verticalclip, verticalscroll, },
 /* ESeparator */	{ icondraw, outlinehighlight, simpleclip, iconscroll, },
};

Point
iconsize(Image *image)
{
	Point dd;

	if(image->repl){
		dd.x = Dx(image->clipr);
		dd.y = Dy(image->clipr);
	}else{
		dd.x = Dx(image->r);
		dd.y = Dy(image->r);
	}
	return dd;
}

void
icondraw(Prefab_Element *elem, Image *i, Rectangle clipr, int clean, int highlight)
{
	Prefab_Style *style;
	Rectangle r;
	Point p;
	PElement *pelem;
	Image *image, *c;
	Point size;

	USED(highlight);
	pelem = lookupelement(elem);
	if(pelem == H)
		return;
	if(!rectclip(&clipr, i->clipr))
		return;
	R2R(r, elem->r);
	if(!rectclip(&clipr, r))
		return;
	if(elem->image==H || elem->mask==H || badenviron(elem->environ, 0))
		return;
	style = elem->environ->style;
	if(!clean){
		c = lookupimage(style->elemcolor);
		if(c != nil)
			draw(i, clipr, c, nil, clipr.min);
	}
	r.min = pelem->drawpt;
	image = lookupimage(elem->image);
	if(image == nil)
		return;
	size = iconsize(image);
	r.max.x = r.min.x+size.x;
	r.max.y = r.min.y+size.y;
	if(rectclip(&r, clipr)){
		p = image->r.min;
		p.x += r.min.x-pelem->drawpt.x;
		p.y += r.min.y-pelem->drawpt.y;
		c = lookupimage(elem->mask);
		if(c != nil)
			draw(i, r, image, c, p);
	}
}

void
textdraw(Prefab_Element *elem, Image *i, Rectangle clipr, int clean, int highlight)
{
	Prefab_Style *style;
	Rectangle r;
	PElement *pelem;
	Image *color, *c;
	Font *font;

	USED(highlight);
	pelem = lookupelement(elem);
	if(pelem == H)
		return;
	if(!rectclip(&clipr, i->clipr))
		return;
	R2R(r, elem->r);
	if(!rectclip(&clipr, r))
		return;
	if(elem->str==H || badenviron(elem->environ, 0))
		return;
	style = elem->environ->style;
	font = lookupfont(elem->font);
	if(font == nil)
		return;
	if(highlight)
		color = lookupimage(style->highlightcolor);
	else
		color = lookupimage(elem->image);
	if(!clean){
		c = lookupimage(style->elemcolor);
		if(c != nil)
			draw(i, clipr, c, nil, clipr.min);
	}
	if(color != nil)
		_string(i, pelem->drawpt, color, pelem->drawpt, font, string2c(elem->str), nil, 1<<24, clipr, nil, pelem->drawpt, SoverD);
}

void
listdraw(Prefab_Element *elem, Image *i, Rectangle clipr, int clean, int highlight)
{
	Prefab_Style *style;
	Prefab_Element *e;
	List *l;
	Rectangle r;
	PElement *pelem;
	Image *c;

	pelem = lookupelement(elem);
	if(pelem == H)
		return;
	if(!rectclip(&clipr, i->clipr))
		return;
	R2R(r, elem->r);
	if(!rectclip(&clipr, r))
		return;
	if(elem->kids==H || badenviron(elem->environ, 0))
		return;
	if(pelem->first != elem->kids)	/* error? */
		return;
	style = elem->environ->style;
	if(!clean){
		c = lookupimage(style->elemcolor);
		if(c != nil)
			draw(i, clipr, c, nil, clipr.min);
	}
	for(l=pelem->vfirst; l!=H; l=l->tail){
		e = *(Prefab_Element**)l->data;
		R2R(r, e->r);
		if(rectXrect(r, clipr))
			drawelement(e, i, clipr, elem->environ==e->environ, highlight);
		if(l == pelem->vlast)
			break;
	}
}

void
drawelement(Prefab_Element *elem, Image *i, Rectangle clipr, int clean, int highlight)
{
	PElement *pelem;

	if(elem != H){
		pelem = lookupelement(elem);
		if(pelem == H)
			return;
		(*elemfn[elem->kind].draw)(elem, i, clipr, clean, highlight);
		if(!highlight && pelem->highlight!=H)
			(*elemfn[elem->kind].highlight)(elem, i, pelem->highlight, 1);
	}
}

void
translateelement(Prefab_Element *elem, Point delta)
{
	PElement *pelem;
	List *l;

	if(elem == H)
		return;
	pelem = lookupelement(elem);
	if(pelem == H)
		return;
	elem->r.min.x += delta.x;
	elem->r.min.y += delta.y;
	elem->r.max.x += delta.x;
	elem->r.max.y += delta.y;
	pelem->drawpt.x += delta.x;
	pelem->drawpt.y += delta.y;
	switch(elem->kind){
	case EHorizontal:
	case EVertical:
		if(pelem->first != elem->kids)
			return;
		for(l=elem->kids; l!=H; l=l->tail)
			translateelement(*(Prefab_Element**)l->data, delta);
		break;
	}
}

int
fitrect(Rectangle *r, Rectangle sr)
{
	if(r->max.x > sr.max.x){
		r->min.x -= r->max.x-sr.max.x;
		r->max.x = sr.max.x;
	}
	if(r->max.y > sr.max.y){
		r->min.y -= r->max.y-sr.max.y;
		r->max.y = sr.max.y;
	}
	if(r->min.x < sr.min.x){
		r->max.x += sr.min.x-r->min.x;
		r->min.x = sr.min.x;
	}
	if(r->min.y < sr.min.y){
		r->max.y += sr.min.y-r->min.y;
		r->min.y = sr.min.y;
	}
	return rectinrect(*r, sr);
}

void
adjusthorizontal(Prefab_Element *elem, int spacing, int position)
{
	int edx, dx, i, x;
	int nlist;	/* BUG: should precompute */
	List *l;
	PElement *pelem;
	Prefab_Element *e;
	Point p;

	pelem = lookupelement(elem);
	if(pelem == H)
		return;
	if(pelem->first != elem->kids)
		return;
	p.y = 0;
	switch(spacing){
	default:	/* shouldn't happen; protected by adjustelement */
	case Adjpack:
		x = elem->r.min.x;
		for(l=elem->kids; l!=H; l=l->tail){
			e = *(Prefab_Element**)l->data;
			p.x = x - e->r.min.x;
			translateelement(e, p);
			x += Dx(e->r);
		}
		elem->r.max.x = x;
		return;

	case Adjequal:
		dx = 0;
		nlist = 0;
		for(l=elem->kids; l!=H; l=l->tail){
			e = *(Prefab_Element**)l->data;
			if(dx < Dx(e->r))
				dx = Dx(e->r);
			nlist++;
		}
		elem->r.max.x = elem->r.min.x+nlist*dx;
		break;

	case Adjfill:
		nlist = 0;
		for(l=elem->kids; l!=H; l=l->tail)
			nlist++;
		dx = Dx(elem->r)/nlist;
		break;
	}
	i = 0;
	for(l=elem->kids; l!=H; l=l->tail){
		e = *(Prefab_Element**)l->data;
		edx = Dx(e->r);
		if(position == Adjleft)
			edx = 0;
		else if(position == Adjcenter)
			edx = (dx-edx)/2;
		else	/* right */
			edx = dx-edx;
		p.x = (elem->r.min.x+i*dx + edx) - e->r.min.x;
		translateelement(e, p);
		i++;
	}
}

void
adjustvertical(Prefab_Element *elem, int spacing, int position)
{
	int edy, dy, i, y;
	int nlist;	/* BUG: should precompute */
	List *l;
	PElement *pelem;
	Prefab_Element *e;
	Point p;

	pelem = lookupelement(elem);
	if(pelem == H)
		return;
	if(pelem->first != elem->kids)
		return;
	p.x = 0;
	switch(spacing){
	default:	/* shouldn't happen; protected by adjustelement */
	case Adjpack:
		y = elem->r.min.y;
		for(l=elem->kids; l!=H; l=l->tail){
			e = *(Prefab_Element**)l->data;
			p.y = y - e->r.min.y;
			translateelement(e, p);
			y += Dy(e->r);
		}
		elem->r.max.y = y;
		return;

	case Adjequal:
		dy = 0;
		nlist = 0;
		for(l=elem->kids; l!=H; l=l->tail){
			e = *(Prefab_Element**)l->data;
			if(dy < Dy(e->r))
				dy = Dy(e->r);
			nlist++;
		}
		elem->r.max.y = elem->r.min.y+nlist*dy;
		break;

	case Adjfill:
		nlist = 0;
		for(l=elem->kids; l!=H; l=l->tail)
			nlist++;
		dy = Dy(elem->r)/nlist;
		break;
	}
	i = 0;
	for(l=elem->kids; l!=H; l=l->tail){
		e = *(Prefab_Element**)l->data;
		edy = Dy(e->r);
		if(position == Adjup)
			edy = 0;
		else if(position == Adjcenter)
			edy = (dy-edy)/2;
		else	/* down */
			edy = dy-edy;
		p.y = (elem->r.min.y+i*dy + edy) - e->r.min.y;
		translateelement(e, p);
		i++;
	}
}

void
adjustelement(Prefab_Element *elem, int spacing, int position)
{
	if(lookupelement(elem) == H)
		return;
	if(spacing<Adjpack || spacing>Adjfill || position<Adjleft || position>Adjdown)
		return;
	switch(elem->kind){
	case EVertical:
		adjustvertical(elem, spacing, position);
		break;
	case EHorizontal:
		adjusthorizontal(elem, spacing, position);
		break;
	}
}

void
highlightelement(Prefab_Element *elem, Image *i, Prefab_Compound *comp, int on)
{
	PElement *pelem;

	pelem = lookupelement(elem);
	if(pelem!=H && lookupcompound(comp)!=H){
		if(on)
			pelem->highlight = comp;
		else
			pelem->highlight = H;
		(*elemfn[elem->kind].highlight)(elem, i, comp, on);
	}
}

static
int
anytextelements(Prefab_Element *e)
{
	Prefab_Element *t;
	List *l;

	for(l=e->kids; l!=H; l=l->tail){
		t = *(Prefab_Element**)l->data;
		if(t->kind == EText)
			return 1;
	}
	return 0;
}

void
textlisthighlight(Prefab_Element *e, Image *i, Prefab_Compound *c, int on)
{
	Prefab_Element *t;
	List *l;

	for(l=e->kids; l!=H; l=l->tail){
		t = *(Prefab_Element**)l->data;
		if(t->kind == EText)
			texthighlight(t, i, c, on);
	}
}

void
outlinehighlight(Prefab_Element *e, Image *i, Prefab_Compound *c, int on)
{
	List *l;
	Prefab_Element *t;
	Image *color;
	Rectangle r, r1, r2;
	Point dp;
	int done;

	/* see if we can do it by highlighting just a text element */
	if((e->kind==EVertical || e->kind==EHorizontal) && e->kids!=H){
		/* is any child a text element? */
		if(anytextelements(e)){
			textlisthighlight(e, i, c, on);
			return;
		}
		/* grandchild? */
		done = 0;
		for(l=e->kids; l!=H; l=l->tail){
			t = *(Prefab_Element**)l->data;
			if(t->kind==EVertical || t->kind==EHorizontal)
				if(anytextelements(t)){
					textlisthighlight(t, i, c, on);
					done = 1;
				}
		}
		if(done)
			return;
	}
	if(on){
		color = lookupimage(e->environ->style->highlightcolor);
		if(color == nil)
			return;
		R2R(r, e->r);
		/* avoid outlining empty space around images */
		dp = ((PElement*)e)->drawpt;
		if(e->kind==EIcon && e->image->repl==0 && ptinrect(dp, r)){
			R2R(r1, e->image->r);
			R2R(r2, e->image->clipr);
			if(rectclip(&r1, r2)){
				dp.x += Dx(r1);
				dp.y += Dy(r1);
				if(ptinrect(dp, r))
					r = Rpt(((PElement*)e)->drawpt, dp);
			}
		}
		draw(i, r, color, nil, r.min);
		drawelement(e, i, insetrect(r, 2), Dirty, 1);
	}else{
		drawelement(e, i, IRECT(e->r), Dirty, 0);
		edge(c->environ, i, c->r, e->r);
	}
}

void
texthighlight(Prefab_Element *e, Image *i, Prefab_Compound *c, int on)
{
	drawelement(e, i, IRECT(e->r), Clean, on);
	edge(c->environ, i, c->r, e->r);
}

void
clipelement(Prefab_Element *elem, Rectangle r)
{
	if(lookupelement(elem) != H)
		(*elemfn[elem->kind].clip)(elem, r);
}

void
simpleclip(Prefab_Element *elem, Rectangle r)
{
	R2R(elem->r, r);
}

void
horizontalclip(Prefab_Element *elem, Rectangle r)
{
	int x;
	List *l;
	Prefab_Element *e;
	PElement *pelem;

	x = r.min.x;
	pelem = lookupelement(elem);
	if(pelem == H)
		return;
	for(l=pelem->vfirst; l!=H && x<r.max.x; l=l->tail){
		e = *(Prefab_Element**)l->data;
		x += Dx(e->r);
	}
	pelem->vlast = l;
	R2R(elem->r, r);
}

void
verticalclip(Prefab_Element *elem, Rectangle r)
{
	int y;
	List *l;
	Prefab_Element *e;
	PElement *pelem;

	y = r.min.y;
	pelem = lookupelement(elem);
	if(pelem == H)
		return;
	for(l=pelem->vfirst; l!=H && y<r.max.y; l=l->tail){
		e = *(Prefab_Element**)l->data;
		y += Dy(e->r);
	}
	pelem->vlast = l;
	R2R(elem->r, r);
}

void
scrollelement(Prefab_Element *elem, Point d, int *moved)
{
	if(lookupelement(elem) != H)
		(*elemfn[elem->kind].scroll)(elem, d, moved);
}

void
textscroll(Prefab_Element *elem, Point d, int *moved)
{
	PElement *pelem;

	pelem = lookupelement(elem);
	if(pelem==H || (d.x==0 && d.y==0))
		return;
	pelem->drawpt = subpt(pelem->drawpt, d);
	*moved = 1;
}

void
iconscroll(Prefab_Element *elem, Point d, int *moved)
{
	Point p;
	Image *i;
	PElement *pelem;

	pelem = lookupelement(elem);
	if(pelem==H || elem->image==H || (d.x==0 && d.y==0))
		return;
	i = lookupimage(elem->image);
	if(i == nil)
		return;
	p = subpt(pelem->drawpt, d);
	if(i->repl == 0){
		if(p.x+Dx(i->clipr) < elem->r.max.x)
			p.x = elem->r.max.x - Dx(i->clipr);
		if(p.y+Dy(i->clipr) < elem->r.max.y)
			p.y = elem->r.max.y - Dy(i->clipr);
		if(p.x > elem->r.min.x)
			p.x = elem->r.min.x;
		if(p.y > elem->r.min.y)
			p.y = elem->r.min.y;
	}
	*moved = !eqpt(pelem->drawpt, p);
	pelem->drawpt = p;
}

void
horizontalscroll(Prefab_Element *elem, Point d, int *moved)
{
	List *l;
	Prefab_Element *e;
	PElement *pelem;

	pelem = lookupelement(elem);
	if(pelem==H || elem->kids==H || (d.x==0 && d.y==0))
		return;
	for(l=pelem->first; l!=H; l=l->tail){
		e = *(Prefab_Element**)l->data;
		translateelement(e, d);
	}
	for(l=pelem->first; l!=H; l=l->tail){
		e = *(Prefab_Element**)l->data;
		if(e->r.max.x > elem->r.min.x)
			break;
	}
	pelem->vfirst = l;
	pelem->vlast = l;
	for(; l!=H; l=l->tail){
		e = *(Prefab_Element**)l->data;
		pelem->vlast = l;
		if(e->r.min.x >= elem->r.max.x)
			break;
	}
	*moved = 1;
}

void
verticalscroll(Prefab_Element *elem, Point d, int *moved)
{
	List *l;
	Prefab_Element *e;
	PElement *pelem;

	pelem = lookupelement(elem);
	if(pelem==H || elem->kids==H || (d.x==0 && d.y==0))
		return;
	for(l=pelem->first; l!=H; l=l->tail){
		e = *(Prefab_Element**)l->data;
		translateelement(e, d);
	}
	for(l=pelem->first; l!=H; l=l->tail){
		e = *(Prefab_Element**)l->data;
		if(e->r.max.y > elem->r.min.y)
			break;
	}
	pelem->vfirst = l;
	pelem->vlast = l;
	for(; l!=H; l=l->tail){
		e = *(Prefab_Element**)l->data;
		pelem->vlast = l;
		if(e->r.min.y >= elem->r.max.y)
			break;
	}
	*moved = 1;
}

/*
 * Make e visible within list.  Return value is whether any change was made;
 * if so, must redraw (BUG: should probably do this here)
 */
int
showelement(Prefab_Element *list, Prefab_Element *e)
{
	Point p;
	Prefab_Element *h, *t;
	PElement *plist;
	int moved;

	p.x = p.y = 0;
	if(list->kids == H)
		return 0;
	plist = lookupelement(list);
	if(plist == H)
		return 0;
	h = *(Prefab_Element**)plist->first->data;
	t = *(Prefab_Element**)plist->last->data;
	if(list->kind == EHorizontal){
		p.x = (list->r.min.x+Dx(list->r)/2) - e->r.min.x;
		if(e->r.min.x < list->r.min.x){	/* scroll to right */
			if(e->r.max.x+p.x > list->r.max.x)
				p.x = list->r.min.x-e->r.min.x;
			if(h->r.min.x + p.x > list->r.min.x)
				p.x = list->r.min.x-h->r.min.x;
		}else if(e->r.max.x > list->r.max.x){	/* scroll to left */
			if(e->r.min.x+p.x < list->r.min.x)
				p.x = list->r.min.x-e->r.min.x;
			if(t->r.max.x + p.x < list->r.max.x)
				p.x = list->r.max.x-t->r.max.x;
		}else
			return 0;
	}else if(list->kind == EVertical){
		p.y = (list->r.min.y+Dy(list->r)/2) - e->r.min.y;
		if(e->r.min.y < list->r.min.y){	/* scroll towards bottom */
			if(e->r.max.y+p.y > list->r.max.y)
				p.y = list->r.min.y-e->r.min.y;
			if(h->r.min.y + p.y > list->r.min.y)
				p.y = list->r.min.y-h->r.min.y;
		}else if(e->r.max.y > list->r.max.y){	/* scroll towards top */
			if(e->r.min.y+p.y < list->r.min.y)
				p.y = list->r.min.y-e->r.min.y;
			if(t->r.max.y + p.y < list->r.max.y)
				p.y = list->r.max.y-t->r.max.y;
		}else
			return 0;
	}else
		return 0;
	if(p.x!=0 || p.y!=0){
		scrollelement(list, p, &moved);
		return 1;
	}
	return 0;
}

PElement*
mkelement(Prefab_Environ *env, enum Elementtype t)
{
	Heap *h;
	PElement *p;

	h = heapz(TElement);
	p = H2D(PElement*, h);
	p->highlight = H;
	p->first = H;
	p->last = H;
	p->vfirst = H;
	p->vlast = H;
	p->nkids = 1;
	p->pkind = t;
	p->e.kind = t;
	p->e.environ = env;
	D2H(env)->ref++;
	return p;
}
