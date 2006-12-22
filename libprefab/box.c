#include <lib9.h>
#include <draw.h>
#include <interp.h>
#include <isa.h>
#include "../libinterp/runt.h"
#include <drawif.h>
#include <prefab.h>

PCompound*
box(Prefab_Environ *e, Draw_Point p, Prefab_Element *title, Prefab_Element *list)
{
	Draw_Rect er, r, lr;
	PCompound *pc;
	Prefab_Compound *c;
	Image *disp;
	Draw_Image *ddisp;
	Screen *screen;
	Heap *h;
	Point pt;
	int w;

	if(list == H)
		return H;
	screen = lookupscreen(e->screen);
	if(screen == nil)
		return H;
	h = heapz(TCompound);
	if(h == H)
		return H;
	pc = H2D(PCompound*, h);
	c = &pc->c;

	gchalt++;
	r = list->r;
	if(title != H){
		w = 2+1+3+Dx(title->r)+1;
		if(w > Dx(r))
			r.max.x = r.min.x + w;
		r.max.y += 2+1+Dy(title->r)+1;
	}

	er = edgerect(e, p, &r);

	disp = allocwindow(screen, IRECT(er), Refbackup /*refreshcompound*/, DWhite);
	if(disp == nil){
   Err:
		destroy(c);
		gchalt--;
		return H;
	}
	if((ddisp=mkdrawimage(disp, e->screen, e->screen->display, nil)) == H){
		freeimage(disp);
		goto Err;
	}

	lr = r;
	if(title != H){
		pt.x = r.min.x+3;
		pt.y = r.min.y+3;
		translateelement(title, pt);
		lr.min.y = title->r.max.y+1;
	}
	translateelement(list, subpt(IPOINT(lr.min), IPOINT(list->r.min)));

	c->r = r;
	c->image = ddisp;
	c->environ = e;
	D2H(e)->ref++;
	if(title != H){
		c->title = title;
		D2H(title)->ref++;
	}
	if(list != H){
		c->contents = (Prefab_Element*)list;
		D2H(list)->ref++;
	}
	pc->display = screen->display;
	gchalt--;
	return pc;
}
