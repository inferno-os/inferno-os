#include "lib9.h"
#include "draw.h"
#include "tk.h"

#define	O(t, e)		((long)(&((t*)0)->e))

typedef struct TkPanel TkPanel;
struct TkPanel
{
	Image*	image;
	Image*	matte;
	Point		view;	/* vector from image origin to widget origin */
	Rectangle		r;		/* drawn rectangle (in image coords) */
	int		anchor;
	int		hasalpha;	/* does the image include an alpha channel? */
};

static TkOption tkpanelopts[] =
{
	"anchor",	OPTflag,	O(TkPanel, anchor),	tkanchor,
	nil
};

static int
tkdrawnrect(Image *image, Image *matte, Rectangle *r)
{
	*r = image->clipr;
	if (matte != nil) {
		if (!rectclip(r, matte->clipr))
			return 0;
		if (!matte->repl && !rectclip(r, matte->r))
			return 0;
	}
	if (!image->repl && !rectclip(r, image->r))
		return 0;
	return 1;
}

char*
tkpanel(TkTop *t, char *arg, char **ret)
{
	TkOptab tko[3];
	Tk *tk;
	TkPanel *tkp;
	TkName *names;
	char *e;

	tk = tknewobj(t, TKpanel, sizeof(Tk)+sizeof(TkPanel));
	if(tk == nil)
		return TkNomem;

	tkp = TKobj(TkPanel, tk);
	tkp->anchor = Tkcenter;

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkp;
	tko[1].optab = tkpanelopts;
	tko[2].ptr = nil;
	names = nil;

	e = tkparse(t, arg, tko, &names);
	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}

	tksettransparent(tk, tkhasalpha(tk->env, TkCbackgnd));

	e = tkaddchild(t, tk, &names);

	tkfreename(names);
	if (e != nil) {
		tkfreeobj(tk);
		return e;
	}

	tk->name->link = nil;
	return tkvalue(ret, "%s", tk->name->name);
}

void
tkgetpanelimage(Tk *tk, Image **i, Image **m)
{
	TkPanel *tkp = TKobj(TkPanel, tk);
	*i = tkp->image;
	*m = tkp->matte;
}

void
tksetpanelimage(Tk *tk, Image *image, Image *matte)
{
	TkPanel *tkp = TKobj(TkPanel, tk);
	int ishuge;
	TkGeom g;

	g = tk->req;

	tkp->image = image;
	tkp->matte = matte;

	if (!tkdrawnrect(image, matte, &tkp->r)) {
		tkp->r.min = image->r.min;
		tkp->r.max = image->r.min;
	}

	tkp->view = tkp->r.min;		/* XXX do we actually want to keep the old one? */
	/*
	 * if both image and matte are replicated, then we've got no idea what
	 * the rectangle should be, so request zero size, and set origin to (0, 0).
	 */
	ishuge = (Dx(tkp->r) >= 10000000);
	if((tk->flag & Tksetwidth) == 0){
		if(ishuge)
			tk->req.width = 0;
		else
			tk->req.width = Dx(tkp->r);
	}
	if(ishuge)
		tkp->view.x = 0;

	ishuge = (Dy(tkp->r) >= 10000000);
	if((tk->flag & Tksetheight) == 0){
		if(ishuge)
			tk->req.height = 0;
		else
			tk->req.height = Dy(tkp->r);
	}
	if(ishuge)
		tkp->view.y = 0;

	tkp->hasalpha = tkchanhastype(image->chan, CAlpha);
	tkgeomchg(tk, &g, tk->borderwidth);
	tksettransparent(tk, tkp->hasalpha || tkhasalpha(tk->env, TkCbackgnd));
	tk->dirty = tkrect(tk, 0);
}

static void
tkfreepanel(Tk *tk)
{
	TkPanel *tkp = TKobj(TkPanel, tk);
	tkdelpanelimage(tk->env->top, tkp->image);
	tkdelpanelimage(tk->env->top, tkp->matte);
}

static Point
tkpanelview(Tk *tk)
{
	int dx, dy;
	Point view;
	TkPanel *tkp = TKobj(TkPanel, tk);
	
	dx = tk->act.width - Dx(tkp->r);
	dy = tk->act.height - Dy(tkp->r);

	view = tkp->view;

	if (dx > 0) {
		if((tkp->anchor & (Tkeast|Tkwest)) == 0)
			view.x -= dx/2;
		else
		if(tkp->anchor & Tkeast)
			view.x -= dx;
	}
	if (dy > 0) {
		if((tkp->anchor & (Tknorth|Tksouth)) == 0)
			view.y -= dy/2;
		else
		if(tkp->anchor & Tksouth)
			view.y -= dy;
	}
	return view;
}

static char*
tkdrawpanel(Tk *tk, Point orig)
{
	Rectangle r, pr;
	TkPanel *tkp = TKobj(TkPanel, tk);
	Image *i;
	int any;
	Point view, p;

	i = tkimageof(tk);
	if (i == nil)
		return nil;

	p.x = orig.x + tk->act.x + tk->borderwidth;
	p.y = orig.y + tk->act.y + tk->borderwidth;

	view = tkpanelview(tk);

	/*
	 * if the image doesn't fully cover the dirty rectangle, then
	 * paint some background in there
	 */
	r = rectsubpt(tkp->r, view);		/* convert to widget coords */
	pr = tkrect(tk, 0);
	any = rectclip(&r, pr);				/* clip to inside widget borders */

	if (!any || tkp->hasalpha || !rectinrect(tk->dirty, r))
		draw(i, rectaddpt(tk->dirty, p), tkgc(tk->env, TkCbackgnd), nil, ZP);

	if (any && rectclip(&r, tk->dirty))
		draw(i, rectaddpt(r, p), tkp->image, tkp->matte, addpt(r.min, view));

	if (!rectinrect(tk->dirty, pr)) {
		p.x -= tk->borderwidth;
		p.y -= tk->borderwidth;
		tkdrawrelief(i, tk, p, TkCbackgnd, tk->relief);
	}
	return nil;
}

static char*
tkpanelcget(Tk *tk, char *arg, char **val)
{
	TkOptab tko[3];
	TkPanel *tkp = TKobj(TkPanel, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkp;
	tko[1].optab = tkpanelopts;
	tko[2].ptr = nil;

	return tkgencget(tko, arg, val, tk->env->top);
}

static char*
tkpanelcvt(Tk *tk, char *arg, int rel, int *p)
{
	char buf[Tkmaxitem];

	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if(buf[0] == '\0')
		return TkBadvl;
	*p = atoi(buf) + rel;
	return nil;
}

/*
 * screen to image
 */
static char*
tkpanelpanelx(Tk *tk, char *arg, char **val)
{
	Point p;
	char *e;

	USED(val);
	p = subpt(tkposn(tk), tkpanelview(tk));
	e = tkpanelcvt(tk, arg, -p.x, &p.x);
	if (e != nil)
		return e;
	return tkvalue(val, "%d", p.x);
}

static char*
tkpanelpanely(Tk *tk, char *arg, char **val)
{
	Point p;
	char *e;

	USED(val);
	p = subpt(tkposn(tk), tkpanelview(tk));
	e = tkpanelcvt(tk, arg, -p.y, &p.y);
	if (e != nil)
		return e;
	return tkvalue(val, "%d", p.y);
}

/*
 * image to screen
 */
static char*
tkpanelscreenx(Tk *tk, char *arg, char **val)
{
	Point p;
	char *e;

	USED(val);
	p = subpt(tkposn(tk), tkpanelview(tk));
	e = tkpanelcvt(tk, arg, p.x, &p.x);
	if (e != nil)
		return e;
	return tkvalue(val, "%d", p.x);
}

static char*
tkpanelscreeny(Tk *tk, char *arg, char **val)
{
	Point p;
	char *e;

	USED(val);
	p = subpt(tkposn(tk), tkpanelview(tk));
	e = tkpanelcvt(tk, arg, p.y, &p.y);
	if (e != nil)
		return e;
	return tkvalue(val, "%d", p.y);
}

static char*
tkpanelconf(Tk *tk, char *arg, char **val)
{
	char *e;
	TkGeom g;
	int bd;
	TkOptab tko[3];
	TkPanel *tkp = TKobj(TkPanel, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkp;
	tko[1].optab = tkpanelopts;
	tko[2].ptr = nil;

	if(*arg == '\0')
		return tkconflist(tko, val);

	g = tk->req;
	bd = tk->borderwidth;
	e = tkparse(tk->env->top, arg, tko, nil);
	tkgeomchg(tk, &g, bd);
	tksettransparent(tk, tkp->hasalpha || tkhasalpha(tk->env, TkCbackgnd));

	tk->dirty = tkrect(tk, 1);

	return e;
}

static char*
tkpaneldirty(Tk *tk, char *arg, char **val)
{
	char buf[Tkmaxitem];
	int n, coords[4];
	Rectangle r;
	char *e, *p;
	TkPanel *tkp = TKobj(TkPanel, tk);

	USED(val);
	n = 0;
	while (n < 4) {
		arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
		if (buf[0] == 0)
			break;
		p = buf;
		e = tkfrac(&p, &coords[n++], nil);
		if (e != nil)
			return TkBadvl;
	}
	if (n == 0)
		r = tkp->r;
	else {
		 if (n != 4)
			return TkBadvl;
		r.min.x = TKF2I(coords[0]);
		r.min.y = TKF2I(coords[1]);
		r.max.x = TKF2I(coords[2]);
		r.max.y = TKF2I(coords[3]);
	}
	if (rectclip(&r, tkp->r)) {
		r = rectsubpt(r, tkpanelview(tk));		/* convert to widget coords */
		if (rectclip(&r, tkrect(tk, 0)))			/* clip to visible area */
			combinerect(&tk->dirty, r);
	}
	return nil;
}

static char*
tkpanelorigin(Tk *tk, char *arg, char **val)
{
	char *e;
	Point view;
	TkPanel *tkp = TKobj(TkPanel, tk);

	e = tkxyparse(tk, &arg, &view);
	if (e != nil) {
		if (e == TkOparg)
			return tkvalue(val, "%d %d", tkp->view.x, tkp->view.y);
		return e;
	}
	tkp->view = view;
	tk->dirty = tkrect(tk, 0);
	return nil;
}

static
TkCmdtab tkpanelcmd[] =
{
	"cget",			tkpanelcget,
	"configure",		tkpanelconf,
	"dirty",			tkpaneldirty,
	"origin",			tkpanelorigin,
	"panelx",			tkpanelpanelx,
	"panely",			tkpanelpanely,
	"screenx",			tkpanelscreenx,
	"screeny",			tkpanelscreeny,
	nil
};

TkMethod panelmethod = {
	"panel",
	tkpanelcmd,
	tkfreepanel,
	tkdrawpanel
};
