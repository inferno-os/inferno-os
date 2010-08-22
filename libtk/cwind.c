#include "lib9.h"
#include "draw.h"
#include "tk.h"
#include "canvs.h"

#define	O(t, e)		((long)(&((t*)0)->e))

/* Window Options (+ means implemented)
	 +tags
	 +width
	 +height
	 +window
	 +anchor
*/

static
TkOption windopts[] =
{
	"width",	OPTdist,	O(TkCwind, width),	nil,
	"height",	OPTdist,	O(TkCwind, height),	nil,
	"anchor",	OPTstab,	O(TkCwind, flags),	tkanchor,
	"window",	OPTwinp,	O(TkCwind, sub),	nil,
	nil
};

static
TkOption itemopts[] =
{
	"tags",		OPTctag,	O(TkCitem, tags),	nil,
	nil
};

static void
tkcvswindsize(TkCitem *i)
{
	Tk *s;
	int bw;
	Point p;
	TkGeom old;
	TkCwind *w;

	w = TKobj(TkCwind, i);
	s = w->sub;
	if(s == nil)
		return;

	if(w->width != s->act.width || w->height != s->act.height) {
		old = s->act;
		s->act.width = w->width;
		s->act.height = w->height;
		if(s->slave) {
			tkpackqit(s);
			tkrunpack(s->env->top);
		}
		tkdeliver(s, TkConfigure, &old);
	}
	p = tkcvsanchor(i->p.drawpt[0], s->act.width, s->act.height, w->flags);
	s->act.x = p.x;
	s->act.y = p.y;

	bw = 2*s->borderwidth;
	i->p.bb.min = p;
	i->p.bb.max.x = p.x + s->act.width + bw;
	i->p.bb.max.y = p.y + s->act.height + bw;
}

TkCitem*
tkcvsfindwin(Tk *tk)
{
	Tk *parent, *sub;
	TkCitem *i;
	TkCanvas *c;
	TkCwind *w;

	sub = tkfindsub(tk);
	if(sub == nil)
		return nil;
	parent = sub->parent;
	if(parent->type != TKcanvas)
		return nil;	/* inconsistent */
	c = TKobj(TkCanvas, parent);
	for(i = c->head; i != nil; i = i->next) {
		if(i->type == TkCVwindow) {
			w = TKobj(TkCwind, i);
			if(w->sub == sub)
				return i;
		}
	}
	return nil;
}

void
tkcvsforgetsub(Tk *sub, Tk *tk)
{
	TkCwind *w;
	TkCitem *i;

	i = tkcvsfindwin(sub);
	if(i == nil)
		return;
	w = TKobj(TkCwind, i);
	if(w->focus == tk) {
if(0)print("tkcsvsforget sub %p %q focus %p %q\n", sub, tkname(sub), tk, tkname(tk));
		w->focus = nil;
	}
}

static void
tkcvswindgeom(Tk *sub, int x, int y, int w, int h)
{
	TkCitem *i;
	Tk *parent;
	TkCanvas *c;
	TkCwind *win;

	USED(x);
	USED(y);
	parent = sub->parent;
	win = nil;
	c = TKobj(TkCanvas, parent);
	for(i = c->head; i; i = i->next) {
		if(i->type == TkCVwindow) {
			win = TKobj(TkCwind, i);
			if(win->sub == sub)
				break;
		}
	}

	tkbbmax(&c->update, &i->p.bb);

	if((win->flags & Tksetwidth) == 0)
		win->width = w;
	if ((win->flags & Tksetheight) == 0)
		win->height = h;

	sub->req.width = w;
	sub->req.height = h;
	tkcvswindsize(i);

	tkbbmax(&c->update, &i->p.bb);
	tkcvsdirty(parent);
}

static void
tkcvssubdestry(Tk *sub)
{
	Tk *tk;
	TkCitem *i;
	TkCanvas *c;
	TkCwind *win;

	tk = sub->parent;
	if(tk == nil)
		return;

if(0)print("tkcvssubdestry %p %q\n", sub, tkname(sub));
	i = tkcvsfindwin(sub);
	if(i == nil)
		return;
	win = TKobj(TkCwind, i);
	if(win->sub != sub){
		if(win->sub != nil)
			print("inconsistent tkcvssubdestry %p %q\n", sub, tkname(sub));
		return;
	}

	c = TKobj(TkCanvas, tk);
	tkbbmax(&c->update, &i->p.bb);
	tkcvssetdirty(tk);

	win->focus = nil;
	win->sub = nil;
	sub->parent = nil;
	sub->geom = nil;
}

Point
tkcvsrelpos(Tk *sub)
{
	Tk *tk;
	TkCitem *i;
	TkCanvas *c;
	TkCwind *win;

	tk = sub->parent;
	if(tk == nil)
		return ZP;

	c = TKobj(TkCanvas, tk);
	for(i = c->head; i; i = i->next) {
		if(i->type == TkCVwindow) {
			win = TKobj(TkCwind, i);
			if(win->sub == sub)
				return subpt(i->p.bb.min, c->view);
		}
	}
	return ZP;
}

static char*
tkcvswindchk(Tk *tk, TkCwind *w, Tk *oldsub)
{
	Tk *sub;

	sub = w->sub;
	if (sub != oldsub) {
		w->sub = oldsub;
		if(sub == nil)
			return nil;
	
		if(sub->flag & Tkwindow)
			return TkIstop;

		if(sub->master != nil || sub->parent != nil)
			return TkWpack;

		if (oldsub != nil) {
			oldsub->parent = nil;
			oldsub->geom = nil;
			oldsub->destroyed = nil;
		}
		w->sub = sub;
		w->focus = nil;
		sub->parent = tk;
		tksetbits(w->sub, Tksubsub);
		sub->geom = tkcvswindgeom;
		sub->destroyed = tkcvssubdestry;
	
		if(w->width == 0)
			w->width = sub->req.width;
		if(w->height == 0)
			w->height = sub->req.height;
	}

	return nil;
}

char*
tkcvswindcreat(Tk* tk, char *arg, char **val)
{
	char *e;
	TkCwind *w;
	TkCitem *i;
	TkCanvas *c;
	TkOptab tko[3];

	c = TKobj(TkCanvas, tk);

	i = tkcnewitem(tk, TkCVwindow, sizeof(TkCitem)+sizeof(TkCwind));
	if(i == nil)
		return TkNomem;

	w = TKobj(TkCwind, i);
	w->flags = Tkcenter;

	e = tkparsepts(tk->env->top, &i->p, &arg, 0);
	if(e != nil) {
		tkcvsfreeitem(i);
		return e;
	}
	if(i->p.npoint != 1) {
		tkcvsfreeitem(i);
		return TkFewpt;
	}

	tko[0].ptr = w;
	tko[0].optab = windopts;
	tko[1].ptr = i;
	tko[1].optab = itemopts;
	tko[2].ptr = nil;
	e = tkparse(tk->env->top, arg, tko, nil);
	if(e != nil) {
		tkcvsfreeitem(i);
		return e;
	}
	e = tkcvswindchk(tk, w, nil);
	if(e != nil) {
		tkcvsfreeitem(i);
		return e;
	}

	e = tkcaddtag(tk, i, 1);
	if(e != nil) {
		tkcvsfreeitem(i);
		return e;
	}

	e = tkvalue(val, "%d", i->id);
	if(e != nil) {
		tkcvsfreeitem(i);
		return e;
	}
	tkcvsappend(c, i);
	tkcvswindsize(i);

	tkbbmax(&c->update, &i->p.bb);
	tkcvssetdirty(tk);
	return nil;
}

char*
tkcvswindcget(TkCitem *i, char *arg, char **val)
{
	TkOptab tko[3];
	TkCwind *w = TKobj(TkCwind, i);

	tko[0].ptr = w;
	tko[0].optab = windopts;
	tko[1].ptr = i;
	tko[1].optab = itemopts;
	tko[2].ptr = nil;

	return tkgencget(tko, arg, val, i->env->top);
}

char*
tkcvswindconf(Tk *tk, TkCitem *i, char *arg)
{
	char *e;
	int dx, dy;
	TkOptab tko[3];
	TkCwind *w = TKobj(TkCwind, i);
	Tk *oldsub;

	tko[0].ptr = w;
	tko[0].optab = windopts;
	tko[1].ptr = i;
	tko[1].optab = itemopts;
	tko[2].ptr = nil;

	dx = w->width;
	dy = w->height;
	w->width = -1;
	w->height = -1;

	oldsub = w->sub;
	e = tkparse(tk->env->top, arg, tko, nil);
	if(e == nil) {
		e = tkcvswindchk(tk, w, oldsub);
		if(e != nil)
			return e;
		if(w->width == -1)
			w->width = dx;
		else
			w->flags |= Tksetwidth;
		if(w->height == -1)
			w->height = dy;
		else
			w->flags |= Tksetheight;
		tkcvswindsize(i);
	} else {
		w->width = dx;
		w->height = dy;
	}
	return e;
}

void
tkcvswindfree(TkCitem *i)
{
	Tk *sub;
	TkCwind *w;

	w = TKobj(TkCwind, i);
	sub = w->sub;
	if(sub != nil) {
		sub->parent = nil;
		sub->geom = nil;
		sub->destroyed = nil;
	}
	w->focus = nil;
	w->sub = nil;
}

void
tkcvswinddraw(Image *img, TkCitem *i, TkEnv *pe)
{
	TkCwind *w;
	Point rel;
	Rectangle r;
	Tk *sub;

	USED(img);			/* See tkimageof */
	USED(pe);
	w = TKobj(TkCwind, i);
	sub = w->sub;
	if(sub != nil) {
		int dirty;
		r = i->p.bb;
		rel.x = r.min.x + sub->borderwidth;
		rel.y = r.min.y + sub->borderwidth;
		if (rectclip(&r, img->clipr)) {
			sub->dirty = rectsubpt(r, rel);
			sub->flag |= Tkrefresh;
			tkdrawslaves(sub, ZP, &dirty);	/* XXX - Tad: propagate err? */
		}
	}
}

char*
tkcvswindcoord(TkCitem *i, char *arg, int x, int y)
{
	char *e;
	TkCpoints p;
/*
	TkCwind *w;
	int xi, yi;
*/

	if(arg == nil) {
		tkxlatepts(i->p.parampt, i->p.npoint, x, y);
		tkxlatepts(i->p.drawpt, i->p.npoint, TKF2I(x), TKF2I(y));
		tkcvswindsize(i);
/*
		w = TKobj(TkCwind, i);
		xi = TKF2I(x);
		yi = TKF2I(y);
		if (w->sub != nil) {
			w->sub->act.x += xi;
			w->sub->act.y += yi;
		}
		i->p.bb = rectaddpt(i->p.bb, Pt(xi, yi));
*/
	}
	else {
		e = tkparsepts(i->env->top, &p, &arg, 0);
		if(e != nil)
			return e;
		if(p.npoint != 1) {
			tkfreepoint(&p);
			return TkFewpt;
		}
		tkfreepoint(&i->p);
		i->p = p;
		tkcvswindsize(i);
	}
	return nil;
}
