#include "lib9.h"
#include "draw.h"
#include "tk.h"
#include "canvs.h"

#define	O(t, e)		((long)(&((t*)0)->e))
typedef void	(*Drawfn)(Image*, Point, int, int, Image*, int);

/* Oval Options (+ means implemented)
	+fill
	+outline
	+stipple
	+tags
	+width
*/

typedef struct TkCoval TkCoval;
struct TkCoval
{
	int	width;
	Image*	stipple;
	Image*	pen;
	TkCanvas*	canv;
};

static
TkOption ovalopts[] =
{
	"width",	OPTnnfrac,	O(TkCoval, width),	nil,			/* XXX should be nnfrac */
	"stipple",	OPTbmap,	O(TkCoval, stipple),	nil,
	nil
};

static
TkOption itemopts[] =
{
	"tags",		OPTctag,	O(TkCitem, tags),	nil,
	"fill",		OPTcolr,	O(TkCitem, env),	IAUX(TkCfill),
	"outline",	OPTcolr,	O(TkCitem, env),	IAUX(TkCforegnd),
	nil
};

void
tkcvsovalsize(TkCitem *i)
{
	int w;
	TkCoval *o;

	o = TKobj(TkCoval, i);
	w = TKF2I(o->width)*2;

	i->p.bb = bbnil;
	tkpolybound(i->p.drawpt, i->p.npoint, &i->p.bb);
	i->p.bb = insetrect(i->p.bb, -w);
}

char*
tkcvsovalcreat(Tk* tk, char *arg, char **val)
{
	char *e;
	TkCoval *o;
	TkCitem *i;
	TkCanvas *c;
	TkOptab tko[3];

	c = TKobj(TkCanvas, tk);

	i = tkcnewitem(tk, TkCVoval, sizeof(TkCitem)+sizeof(TkCoval));
	if(i == nil)
		return TkNomem;

	o = TKobj(TkCoval, i);
	o->width = TKI2F(1);
	o->canv = c;
	e = tkparsepts(tk->env->top, &i->p, &arg, 0);
	if(e != nil) {
		tkcvsfreeitem(i);
		return e;
	}
	if(i->p.npoint != 2) {
		tkcvsfreeitem(i);
		return TkFewpt;
	}

	tko[0].ptr = o;
	tko[0].optab = ovalopts;
	tko[1].ptr = i;
	tko[1].optab = itemopts;
	tko[2].ptr = nil;
	e = tkparse(tk->env->top, arg, tko, nil);
	if(e != nil) {
		tkcvsfreeitem(i);
		return e;
	}
	e = tkcaddtag(tk, i, 1);
	if(e != nil) {
		tkcvsfreeitem(i);
		return e;
	}

	tkcvsovalsize(i);

	e = tkvalue(val, "%d", i->id);
	if(e != nil) {
		tkcvsfreeitem(i);
		return e;
	}

	tkcvsappend(c, i);
	tkbbmax(&c->update, &i->p.bb);
	tkmkpen(&o->pen, i->env, o->stipple);
	tkcvssetdirty(tk);
	return nil;
}

char*
tkcvsovalcget(TkCitem *i, char *arg, char **val)
{
	TkOptab tko[3];
	TkCoval *o = TKobj(TkCoval, i);

	tko[0].ptr = o;
	tko[0].optab = ovalopts;
	tko[1].ptr = i;
	tko[1].optab = itemopts;
	tko[2].ptr = nil;

	return tkgencget(tko, arg, val, i->env->top);
}

char*
tkcvsovalconf(Tk *tk, TkCitem *i, char *arg)
{
	char *e;
	TkOptab tko[3];
	TkCoval *o = TKobj(TkCoval, i);

	tko[0].ptr = o;
	tko[0].optab = ovalopts;
	tko[1].ptr = i;
	tko[1].optab = itemopts;
	tko[2].ptr = nil;

	e = tkparse(tk->env->top, arg, tko, nil);
	tkcvsovalsize(i);
	tkmkpen(&o->pen, i->env, o->stipple);

	return e;
}

void
tkcvsovalfree(TkCitem *i)
{
	TkCoval *o;

	o = TKobj(TkCoval, i);
	if(o->stipple)
		freeimage(o->stipple);
	if(o->pen)
		freeimage(o->pen);
}

void
tkcvsovaldraw(Image *img, TkCitem *i, TkEnv *pe)
{
	Point c;
	TkEnv *e;
	Image *pen;
	TkCoval *o;
	Rectangle d;
	int w, dx, dy;

	USED(pe);

	d.min = i->p.drawpt[0];
	d.max = i->p.drawpt[1];

	e = i->env;
	o = TKobj(TkCoval, i);

	pen = o->pen;
	if(pen == nil && (e->set & (1<<TkCfill)))
		pen = tkgc(e, TkCfill);

	w = TKF2I(o->width)/2;
	if(w < 0)
		return;

	d = canonrect(d);
	dx = Dx(d)/2;
	dy = Dy(d)/2;
	c.x = d.min.x + dx;
	c.y = d.min.y + dy;
	if(pen != nil)
		fillellipse(img, c, dx, dy, pen, c);
	ellipse(img, c, dx, dy, w, tkgc(e, TkCforegnd), c);
}

char*
tkcvsovalcoord(TkCitem *i, char *arg, int x, int y)
{
	char *e;
	TkCpoints p;

	if(arg == nil) {
		tkxlatepts(i->p.parampt, i->p.npoint, x, y);
		tkxlatepts(i->p.drawpt, i->p.npoint, TKF2I(x), TKF2I(y));
		i->p.bb = rectaddpt(i->p.bb, Pt(TKF2I(x), TKF2I(y)));
	}
	else {
		e = tkparsepts(i->env->top, &p, &arg, 0);
		if(e != nil)
			return e;
		if(p.npoint != 2) {
			tkfreepoint(&p);
			return TkFewpt;
		}
		tkfreepoint(&i->p);
		i->p = p;
		tkcvsovalsize(i);
	}
	return nil;
}

int
tkcvsovalhit(TkCitem *i, Point p)
{
	TkCoval *o;
	int w, dx, dy;
	Rectangle d;
	vlong v;
	
	o = TKobj(TkCoval, i);
	w = TKF2I(o->width)/2;
	d = canonrect(Rpt(i->p.drawpt[0], i->p.drawpt[1]));
	d = insetrect(d, -(w/2 + 1));

	dx = Dx(d)/2;
	dy = Dy(d)/2;

	p.x -= d.min.x + dx;
	p.y -= d.min.y + dy;

	dx *= dx;
	dy *= dy;

	/* XXX can we do this nicely without overflow and without vlongs? */
	v = (vlong)(p.x*p.x)*dy;
	v += (vlong)(p.y*p.y)*dx;
	return v < (vlong)dx*dy;
}
