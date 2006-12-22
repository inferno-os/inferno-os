#include <lib9.h>
#include <draw.h>
#include <interp.h>
#include <isa.h>
#include "../libinterp/runt.h"
#include <drawif.h>
#include <prefab.h>

extern void queuerefresh(Image *i, Rectangle r, Reffn reffn, void *refptr);

Draw_Rect
edgerect(Prefab_Environ *e, Draw_Point p, Draw_Rect *rin)
{
	Draw_Rect r;
	Screen *s;

	r.min.x = p.x;
	r.min.y = p.y;
	r.max.x = p.x + 1 + Dx(*rin) + 1;
	r.max.y = p.y + 1 + Dy(*rin) + 1;
	/* outer box computed; now make sure it's all visible */
	s = lookupscreen(e->screen);
	if(s != nil)
		fitrect((Rectangle*)&r, s->display->image->r);

	rin->min.x = r.min.x+1;
	rin->min.y = r.min.y+1;
	rin->max.x = r.max.x-1;
	rin->max.y = r.max.y-1;

	return r;
}

/*
 * Draw edge around r.
 * Assume geometry has already been clipped and adjusted.
 */
void
edge(Prefab_Environ *e, Image *box, Draw_Rect dr, Draw_Rect dclipr)
{
	Rectangle r, r1, clipr;
	Image *ec;
	Screen *s;

	R2R(r, dr);
	R2R(clipr, dclipr);
	r.min.x -= 1;
	r.min.y -= 1;
	r.max.x += 1;
	r.max.y += 1;
	s = lookupscreen(e->screen);
	if(s == nil)
		return;
	ec = lookupimage(e->style->edgecolor);
	if(ec == nil)
		return;

	r1 = r;
	r1.min.y++;
	r1.max.y = r1.min.y+2;
	r1.max.x = r1.min.x+2*(r1.max.x-r1.min.x)/3;
	if(rectclip(&r1, clipr))
		draw(box, r1, ec, nil, r1.min);
	r1 = r;
	r1.min.x++;
	r1.max.x = r1.min.x+2;
	r1.max.y = r1.min.y+2*(r1.max.y-r1.min.y)/3;
	if(rectclip(&r1, clipr))
		draw(box, r1, ec, nil, r1.min);
	r1=r;
	r1.min.x = r1.max.x-1;
	if(rectclip(&r1, clipr))
		draw(box, r1, ec, nil, r1.min);
	r1=r;
	r1.min.y = r1.max.y-1;
	if(rectclip(&r1, clipr))
		draw(box, r1, ec, nil, r1.min);
	r1 = r;
	r1.max.y = r1.min.y+1;
	if(rectclip(&r1, clipr))
		draw(box, r1, ec, nil, r1.min);
	r1=r;
	r1.max.x = r1.min.x+1;
	if(rectclip(&r1, clipr))
		draw(box, r1, ec, nil, r1.min);
}

void
redrawcompound(Image *i, Rectangle clipr, Prefab_Compound *c)
{
	Rectangle r1, rt, r;
	int l, len;
	Prefab_Style *s;
	Image *elemcolor, *edgecolor;
	List *list;
	Font *font;
	Prefab_Element *e;

	if(c==H || badenviron(c->environ, 0))
		return;
	
	r = clipr;
	s = c->environ->style;
	elemcolor = lookupimage(s->elemcolor);
	edgecolor = lookupimage(s->edgecolor);
	if(elemcolor==nil || edgecolor==nil)
		return;
	draw(i, r, elemcolor, nil, r.min);
	if(lookupelement(c->title) != H){
		R2R(rt, c->title->r);
		if(c->title->environ!=H && c->title->environ->style!=H && rectXrect(r, rt)){
			drawelement(c->title, i, r, c->environ==c->title->environ, 0);
			r1.min.x = c->r.min.x;
			r1.min.y = c->title->r.max.y;
			s = c->title->environ->style;
			len = 0;
			switch(c->title->kind){
			case ETitle:
				font = lookupfont(s->titlefont);
				if(font != nil)
					len = 2+1+stringwidth(font, string2c(c->title->str));
				break;
			case EVertical:
				font = lookupfont(s->titlefont);
				if(font != nil)
					for(list=c->title->kids; list!=H; list=list->tail){
						e = *(Prefab_Element**)list->data;
						l = stringwidth(font, string2c(e->str));
						if(l > len)
							len = l;
					}
				len += 2+1;
				break;
			default: 
				len = r1.min.x+2*Dx(c->r)/3;
			}
			r1.max.x = r1.min.x + len;
			r1.max.y = r1.min.y+1;
			draw(i, r1, edgecolor, nil, r.min);
			r.min.y = r1.max.y;
		}
	}
	if(c->contents!=H)
		drawelement(c->contents, i, r, c->environ==c->contents->environ, 0);
	edge(c->environ, i, c->r, DRECT(clipr));
}

void
refreshcompound(Image *i, Rectangle r, void *ptr)
{
	Prefab_Compound *c;

	c = ptr;
	if(c == nil)
		return;
	if(i == nil){	/* called from flushimage */
		i = lookupimage(c->image);
		if(i  == nil)
			return;
	}
	redrawcompound(i, r, c);
}

void
localrefreshcompound(Memimage *mi, Rectangle r, void *ptr)
{
	Prefab_Compound *c;
	Image *i;

	USED(mi);	/* can't do anything with this, but it's part of the memlayer interface */
	c = ptr;
	if(c == nil)
		return;
	i = lookupimage(c->image);
	if(i == nil)
		return;
	queuerefresh(i, r, refreshcompound, ptr);
}

void
drawcompound(Prefab_Compound *c)
{
	Image *i;

	if(c==H || c->image==H)
		return;
	i = lookupimage(c->image);
	redrawcompound(i, insetrect(IRECT(c->r), -1), c);
	if(i->display->local && i->refptr==nil)
		if(drawlsetrefresh(i->display->dataqid, i->id, localrefreshcompound, c) <= 0)
			fprint(2, "drawcompound: can't set refresh\n");
	i->refptr = c;	/* can now be refreshed */
}
