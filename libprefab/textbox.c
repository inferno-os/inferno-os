#include <lib9.h>
#include <draw.h>
#include <interp.h>
#include <isa.h>
#include "../libinterp/runt.h"
#include <drawif.h>
#include <prefab.h>

PCompound*
layoutbox(Prefab_Environ *e, Draw_Rect rr, String *titletext, List *texttext)
{
	Draw_Rect er, r, lr;
	PCompound *pc;
	Prefab_Compound *c;
	PElement *title, *text;
	Image *disp;
	Draw_Image *ddisp;
	Screen *screen;
	Heap *h;
	Rectangle t;
	int wid, w;
	Point p, pt;

	screen = lookupscreen(e->screen);
	if(screen == nil)
		return H;

	gchalt++;
	wid = Dx(rr);
	P2P(p, rr.min);
	title = H;
	text = H;
	if(texttext != H){
		er.min.x = 0;
		er.min.y = 0;
		er.max.x = wid-5;
		er.max.y = Dy(rr);
		text = layoutelement(e, texttext, er, EText);
		if(text == H){
			gchalt--;
			return H;
		}
		if(wid <= 0)
			wid = Dx(text->e.r)+5;
	}
	if(titletext != H){
		/* see how wide title wants to be */
		memset(&er, 0, sizeof er);
		title = textelement(e, titletext, er, ETitle);
		if(title == H){
    Errtitle:
			destroy(text);
			gchalt--;
			return H;
		}
		w = 2+1+3+Dx(title->e.r)+1;
		/* if title is wider than text, adjust wid accordingly */
		if(text!=0 && Dx(text->e.r)<w){
			if(Dx(text->e.r) < 100){	/* narrow text; don't let title get too wide */
				if(w > 250+5)
					w = 250+5;
				wid = w;
			}
			destroy(title);
			er.min.x = 0;
			er.min.y = 0;
			er.max.x = wid-5;
			er.max.y = 0;
			title = textelement(e, titletext, er, ETitle);
			if(title == H)
				goto Errtitle;
		}
		if(wid <= 0)
			wid = Dx(title->e.r)+5;
	}

	h = heapz(TCompound);
	pc = H2D(PCompound*, h);
	c = &pc->c;
	c->title = (Prefab_Element*)title;
	c->contents = (Prefab_Element*)text;
	/* now can just destroy c to clean up */

	r.min = DPOINT(p);
	r.max.x = r.min.x+wid;
	r.max.y = p.y+2+1 + 1+1;
	if(title != H)
		r.max.y += title->nkids*e->style->titlefont->height+1;
	if(text != H)
		r.max.y += Dy(text->e.r);

	er = edgerect(e, DPOINT(p), &r);

	R2R(t, er);
	disp = allocwindow(screen, t, Refbackup /*refreshcompound*/, DWhite);
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
		translateelement(&title->e, pt);
		lr.min.y = title->e.r.max.y+1;
	}

	if(text != H)
		translateelement((Prefab_Element*)text, subpt(IPOINT(lr.min), IPOINT(text->e.r.min)));

	c->r = r;
	c->environ = e;
	c->image = ddisp;
	D2H(e)->ref++;
	pc->display = screen->display;
	gchalt--;
	return pc;

}

PCompound*
textbox(Prefab_Environ *e, Draw_Rect rr, String *titletext, String *texttext)
{
	PCompound *pc;
	List *l;

	l = listoflayout(e->style, texttext, EText);
	pc = layoutbox(e, rr, titletext, l);
	free(l);
	return pc;
}
