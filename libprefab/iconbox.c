#include <lib9.h>
#include <draw.h>
#include <interp.h>
#include <isa.h>
#include "../libinterp/runt.h"
#include <drawif.h>
#include <prefab.h>

PCompound*
iconbox(Prefab_Environ *e, Draw_Point p, String *titletext, Draw_Image *icon, Draw_Image *mask)
{
	Draw_Rect er, r, ir;
	PCompound *pc;
	Prefab_Compound *c;
	PElement *elem, *title;
	Image *disp;
	Draw_Image *ddisp;
	Screen *screen;
	Heap *h;
	Rectangle t;
	Point pt;

	screen = lookupscreen(e->screen);
	if(screen == nil)
		return H;
	h = heapz(TCompound);
	if(h == H)
		return H;
	pc = H2D(PCompound*, h);
	c = &pc->c;

	gchalt++;
	title = H;
	if(titletext != H){
		er.min.x = 0;
		er.min.y = 0;
		er.max.x = Dx(icon->r)-5;
		er.max.y = 0;
		title = textelement(e, titletext, er, ETitle);
		if(title == H){
    Err:
			destroy(c);
			gchalt--;
			return H;
		}
		c->title = (Prefab_Element*)title;
	}

	r = icon->r;
	if(title != H)
		r.max.y += 2+1+title->nkids*e->style->titlefont->height+1;

	er = edgerect(e, p, &r);

	R2R(t, er);
	disp = allocwindow(screen, t, Refbackup /*refreshcompound*/, DWhite);
	if(disp == nil)
		goto Err;

	if((ddisp=mkdrawimage(disp, e->screen, e->screen->display, nil)) == H){
		freeimage(disp);
		goto Err;
	}

	ir = r;
	if(title != H){
		ir = r;
		pt.x = r.min.x+3;
		pt.y = r.min.y+3;
		translateelement(&title->e, pt);
		ir.min.y = title->e.r.max.y+1;
	}

	elem = iconelement(e, ir, icon, mask);
	c->r = r;
	c->image = ddisp;
	c->environ = e;
	D2H(e)->ref++;
	c->contents = (Prefab_Element*)elem;
	pc->display = screen->display;
	gchalt--;
	return pc;
}
