#include "lib9.h"
#include "draw.h"
#include "tk.h"
#include "canvs.h"

#define	O(t, e)		((long)(&((t*)0)->e))

typedef struct TkCpoly TkCpoly;
struct TkCpoly
{
	int		width;
	Image*		stipple;
	Image*		pen;
	TkCanvas*	canv;
	int		smooth;
	int		steps;
	int		winding;
};

static
TkStab tkwinding[] =
{
	"nonzero",	~0,
	"odd",		1,
	nil
};

/* Polygon Options (+ means implemented)
	+fill
	+smooth
	+splinesteps
	+stipple
	+tags
	+width
	+outline
*/
static
TkOption polyopts[] =
{
	"width",	OPTnnfrac,	O(TkCpoly, width),	nil,
	"stipple",	OPTbmap,	O(TkCpoly, stipple),	nil,
	"smooth",	OPTstab,	O(TkCpoly, smooth),	tkbool,
	"splinesteps",	OPTdist,	O(TkCpoly, steps),	nil,
	"winding",	OPTstab, O(TkCpoly, winding), tkwinding,
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
tkcvspolysize(TkCitem *i)
{
	int w;
	TkCpoly *p;

	p = TKobj(TkCpoly, i);
	w = TKF2I(p->width);

	i->p.bb = bbnil;
	tkpolybound(i->p.drawpt, i->p.npoint, &i->p.bb);
	i->p.bb = insetrect(i->p.bb, -w);
}

char*
tkcvspolycreat(Tk* tk, char *arg, char **val)
{
	char *e;
	TkCpoly *p;
	TkCitem *i;
	TkCanvas *c;
	TkOptab tko[3];

	c = TKobj(TkCanvas, tk);

	i = tkcnewitem(tk, TkCVpoly, sizeof(TkCitem)+sizeof(TkCpoly));
	if(i == nil)
		return TkNomem;

	p = TKobj(TkCpoly, i);
	p->width = TKI2F(1);
	p->winding = ~0;

	e = tkparsepts(tk->env->top, &i->p, &arg, 1);
	if(e == nil && i->p.npoint < 3)
		e = TkBadvl;
	if(e != nil) {
		tkcvsfreeitem(i);
		return e;
	}

	tko[0].ptr = p;
	tko[0].optab = polyopts;
	tko[1].ptr = i;
	tko[1].optab = itemopts;
	tko[2].ptr = nil;
	e = tkparse(tk->env->top, arg, tko, nil);
	if(e != nil) {
		tkcvsfreeitem(i);
		return e;
	}
	p->canv = c;

	e = tkcaddtag(tk, i, 1);
	if(e != nil) {
		tkcvsfreeitem(i);
		return e;
	}

	tkcvspolysize(i);
	tkmkpen(&p->pen, i->env, p->stipple);

	e = tkvalue(val, "%d", i->id);
	if(e != nil) {
		tkcvsfreeitem(i);
		return e;
	}

	tkcvsappend(c, i);
	tkbbmax(&c->update, &i->p.bb);
	tkcvssetdirty(tk);
	return nil;
}

char*
tkcvspolycget(TkCitem *i, char *arg, char **val)
{
	TkOptab tko[3];
	TkCpoly *p = TKobj(TkCpoly, i);

	tko[0].ptr = p;
	tko[0].optab = polyopts;
	tko[1].ptr = i;
	tko[1].optab = itemopts;
	tko[2].ptr = nil;

	return tkgencget(tko, arg, val, i->env->top);
}

char*
tkcvspolyconf(Tk *tk, TkCitem *i, char *arg)
{
	char *e;
	TkOptab tko[3];
	TkCpoly *p = TKobj(TkCpoly, i);

	tko[0].ptr = p;
	tko[0].optab = polyopts;
	tko[1].ptr = i;
	tko[1].optab = itemopts;
	tko[2].ptr = nil;

	e = tkparse(tk->env->top, arg, tko, nil);

	tkcvspolysize(i);
	tkmkpen(&p->pen, i->env, p->stipple);

	return e;
}

void
tkcvspolyfree(TkCitem *i)
{
	TkCpoly *p;

	p = TKobj(TkCpoly, i);
	if(p->stipple)
		freeimage(p->stipple);
	if(p->pen)
		freeimage(p->pen);
}

void
tkcvspolydraw(Image *img, TkCitem *i, TkEnv *pe)
{
	int w;
	TkEnv *e;
	TkCpoly *p;
	Image *pen;
	Point *pts;

	USED(pe);

	p = TKobj(TkCpoly, i);

	e = i->env;

	pen = p->pen;
	if(pen == nil && (e->set & (1<<TkCfill)))
		pen = tkgc(e, TkCfill);

	pts = i->p.drawpt;
	if(i->p.npoint > 0 && pen != nil) {
		if (p->smooth == BoolT)
			fillbezspline(img, pts, i->p.npoint+1, p->winding, pen, pts[0]);
		else
			fillpoly(img, pts, i->p.npoint+1, p->winding, pen, pts[0]);
	}

	w = TKF2I(p->width) - 1;
	if(w >= 0 && (e->set & (1<<TkCforegnd))) {
		pen = tkgc(i->env, TkCforegnd);
		if (p->smooth == BoolT)
			bezspline(img, pts, i->p.npoint+1, Enddisc, Enddisc, w, pen, pts[0]);
		else
			poly(img, pts, i->p.npoint+1, Enddisc, Enddisc, w, pen, pts[0]);
	}
}

char*
tkcvspolycoord(TkCitem *i, char *arg, int x, int y)
{
	char *e;
	TkCpoints p;

	if(arg == nil) {
		tkxlatepts(i->p.parampt, i->p.npoint, x, y);
		tkxlatepts(i->p.drawpt, i->p.npoint, TKF2I(x), TKF2I(y));
		i->p.drawpt[i->p.npoint] = i->p.drawpt[0];
		i->p.bb = rectaddpt(i->p.bb, Pt(TKF2I(x), TKF2I(y)));
	}
	else {
		e = tkparsepts(i->env->top, &p, &arg, 1);
		if(e != nil)
			return e;
		if(p.npoint < 2) {
			tkfreepoint(&p);
			return TkFewpt;
		}
		tkfreepoint(&i->p);
		i->p = p;
		tkcvspolysize(i);
	}
	return nil;
}

int
tkcvspolyhit(TkCitem *item, Point p)
{
	Point *poly;
	int r, np, fill, w;
	TkCpoly *l;
	TkEnv *e;

	l = TKobj(TkCpoly, item);
	w = TKF2I(l->width) + 2;		/* include some slop */
	e = item->env;
	fill = e->set & (1<<TkCfill);
	if (l->smooth == BoolT) {
		/* this works but it's slow if used intensively... */
		np = getbezsplinepts(item->p.drawpt, item->p.npoint + 1, &poly);
		if (fill)
			r = tkinsidepoly(poly, np, l->winding, p);
		else
			r = tklinehit(poly, np, w, p);
		free(poly);
	} else {
		if (fill)
			r = tkinsidepoly(item->p.drawpt, item->p.npoint, l->winding, p);
		else
			r = tklinehit(item->p.drawpt, item->p.npoint + 1, w, p);
	}
	return r;
}
