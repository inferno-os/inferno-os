#include "lib9.h"
#include "draw.h"
#include "tk.h"
#include "canvs.h"
#include "textw.h"
#include "kernel.h"

TkCtxt*
tknewctxt(Display *d)
{
	TkCtxt *c;
	c = malloc(sizeof(TkCtxt));
	if(c == nil)
		return nil;
	c->lock = libqlalloc();
	if(c->lock == nil){
		free(c);
		return nil;
	}
	if (tkextnnewctxt(c) != 0) {
		free(c->lock);
		free(c);
		return nil;
	}
	c->display = d;
	return c;
}

void
tkfreectxt(TkCtxt *c)
{
	int locked;
	Display *d;

	if(c == nil)
		return;

	tkextnfreectxt(c);

	d = c->display;
	locked = lockdisplay(d);
	tkfreecolcache(c);
	freeimage(c->i);
	freeimage(c->ia);
	if(locked)
		unlockdisplay(d);
	libqlfree(c->lock);
	free(c);
}

Image*
tkitmp(TkEnv *e, Point p, int fillcol)
{
	Image *i, **ip;
	TkTop *t;
	TkCtxt *ti;
	Display *d;
	Rectangle r;
	ulong pix;
	int alpha;
	
	t = e->top;
	ti = t->ctxt;
	d = t->display;

	pix = e->colors[fillcol];
	alpha = (pix & 0xff) != 0xff;
	ip = alpha ? &ti->ia : &ti->i;

	if(*ip != nil) {
		i = *ip;
		if(p.x <= i->r.max.x && p.y <= i->r.max.y) {
			r.min = ZP;
			r.max = p;
			if (alpha)
				drawop(i, r, nil, nil, ZP, Clear);
			draw(i, r, tkgc(e, fillcol), nil, ZP);
			return i;
		}
		r = i->r;
		freeimage(i);
		if(p.x < r.max.x)
			p.x = r.max.x;
		if(p.y < r.max.y)
			p.y = r.max.y;
	}

	r.min = ZP;
	r.max = p;
	*ip = allocimage(d, r, alpha?RGBA32:d->image->chan, 0, pix);

	return *ip;
}

void
tkgeomchg(Tk *tk, TkGeom *g, int bd)
{
	int w, h;
	void (*geomfn)(Tk*);
	if(memcmp(&tk->req, g, sizeof(TkGeom)) == 0 && bd == tk->borderwidth)
		return;

	geomfn = tkmethod[tk->type]->geom;
	if(geomfn != nil)
		geomfn(tk);

	if(tk->master != nil) {
		tkpackqit(tk->master);
		tkrunpack(tk->env->top);
	}
	else
	if(tk->geom != nil) {
		w = tk->req.width;
		h = tk->req.height;
		tk->req.width = 0;
		tk->req.height = 0;
		tk->geom(tk, tk->act.x, tk->act.y, w, h);
		if (tk->slave) {
			tkpackqit(tk);
			tkrunpack(tk->env->top);
		}
	}
	tkdeliver(tk, TkConfigure, g);
}

/*
 * return the widget within tk with by point p (in widget coords)
 */
Tk*
tkinwindow(Tk *tk, Point p, int descend)
{
	Tk *f;
	Point q;
	if (ptinrect(p, tkrect(tk, 1)) == 0)
		return nil;
	for (;;) {
		if (descend && tkmethod[tk->type]->inwindow != nil)
			f = tkmethod[tk->type]->inwindow(tk, &p);
		else {
			q = p;
			for (f = tk->slave; f; f = f->next) {
				q.x = p.x - (f->act.x + f->borderwidth);
				q.y = p.y - (f->act.y + f->borderwidth);
				if (ptinrect(q, tkrect(f, 1)))
					break;
			}
			p = q;
		}
		if (f == nil || f == tk)
			return tk;
		tk = f;
	}
	return nil;	/* for compiler */
}

Tk*
tkfindfocus(TkTop *t, int x, int y, int descend)
{
	Point p, q;
	Tk *tk, *f;
	TkWin *tkw;
	p.x = x;
	p.y = y;
	for(f = t->windows; f != nil; f = TKobj(TkWin, f)->next) {
		assert(f->flag&Tkwindow);
		if(f->flag & Tkmapped) {
			tkw = TKobj(TkWin, f);
			q.x = p.x - (tkw->act.x+f->borderwidth);
			q.y = p.y - (tkw->act.y+f->borderwidth);
			tk = tkinwindow(f, q, descend);
			if(tk != nil)
				return tk;
		}
	}
	return nil;
}

void
tkmovewin(Tk *tk, Point p)
{
	TkWin *tkw;
	if((tk->flag & Tkwindow) == 0)
		return;
	tkw = TKobj(TkWin, tk);
	if(! eqpt(p, tkw->req)){
		tkw->req = p;
		tkw->changed = 1;
	}
}

void
tkmoveresize(Tk *tk, int x, int y, int w, int h)
{
	TkWin *tkw;
	USED(x);
	USED(y);
	assert(tk->flag&Tkwindow);
	tkw = TKobj(TkWin, tk);
	if(w < 0)
		w = 0;
	if(h < 0)
		h = 0;
//print("moveresize %s %d %d +[%d %d], callerpc %lux\n", tk->name->name, x, y, w, h, getcallerpc(&tk));
	tk->req.width = w;
	tk->req.height = h;
	tk->act = tk->req;
	/* XXX perhaps should actually suspend the window here? */
	tkw->changed = 1;
}

static void
tkexterncreatewin(Tk *tk, Rectangle r)
{
	TkWin *tkw;
	TkTop *top;
	char *name;

	top = tk->env->top;
	tkw = TKobj(TkWin, tk);

	/*
	 * for a choicebutton menu, use the name of the choicebutton which created it
	 */
	if(tk->name == nil){
		name = tkw->cbname;
		assert(name != nil);
	} else
		name = tk->name->name;

	tkw->reqid++;
	tkwreq(top, "!reshape %s %d %d %d %d %d", name, tkw->reqid, r.min.x, r.min.y, r.max.x, r.max.y);
	tkw->changed = 0;
	tk->flag |= Tksuspended;
}

/*
 * return non-zero if the window size has changed (XXX choose better return value/function name!)
 */
int
tkupdatewinsize(Tk *tk)
{
	TkWin *tkw;
	Image *previ;
	Rectangle r, or;
	int bw2;

	tkw = TKobj(TkWin, tk);
	bw2 = 2*tk->borderwidth;
	r.min.x = tkw->req.x;
	r.min.y = tkw->req.y;
	r.max.x = r.min.x + tk->act.width + bw2;
	r.max.y = r.min.y + tk->act.height + bw2;
	previ = tkw->image;
	if(previ != nil){
		or.min.x = tkw->act.x;
		or.min.y = tkw->act.y;
		or.max.x = tkw->act.x + Dx(previ->r);
		or.max.y = tkw->act.y + Dy(previ->r);
		if(eqrect(or, r))
			return 0;
	}
	tkexterncreatewin(tk, r);
	return 1;
}

static char*
tkdrawslaves1(Tk *tk, Point orig, Image *dst, int *dirty)
{
	Tk *f;
	char *e = nil;
	Point worig;
	Rectangle r, oclip;

	worig.x = orig.x + tk->act.x + tk->borderwidth;
	worig.y = orig.y + tk->act.y + tk->borderwidth;

	r = rectaddpt(tk->dirty, worig);
	if (Dx(r) > 0 && rectXrect(r, dst->clipr)) {
		e = tkmethod[tk->type]->draw(tk, orig);
		tk->dirty = bbnil;
		*dirty = 1;
	}
	if(e != nil)
		return e;

	/*
	 * grids need clipping
	 * XXX BUG: they can't, 'cos text widgets don't clip appropriately.
	 */
	if (tk->grid != nil) {
		r = rectaddpt(tkrect(tk, 0), worig);
		if (rectclip(&r, dst->clipr) == 0)
			return nil;
		oclip = dst->clipr;
		replclipr(dst, 0, r);
	}
	for(f = tk->slave; e == nil && f; f = f->next)
		e = tkdrawslaves1(f, worig, dst, dirty);
	if (tk->grid != nil)
		replclipr(dst, 0, oclip);
	return e;
}
	
char*
tkdrawslaves(Tk *tk, Point orig, int *dirty)
{
	Image *i;
	char *e;
	i = tkimageof(tk);
	if (i == nil)
		return nil;
	e =  tkdrawslaves1(tk, orig, i, dirty);
	return e;
}

char*
tkupdate(TkTop *t)
{
	Tk* tk;
	int locked;
	TkWin *tkw;
	Display *d;
	char *e;
	int dirty = 0;
	if(t->noupdate)
		return nil;

	d = t->display;
	locked = lockdisplay(d);
	tk = t->windows;
	while(tk) {
		tkw = TKobj(TkWin, tk);
		if((tk->flag & (Tkmapped|Tksuspended)) == Tkmapped) {
			if (tkupdatewinsize(tk) == 0){
				e = tkdrawslaves(tk, ZP, &dirty);
				if(e != nil)
					return e;
			}
		}
		tk = tkw->next;
	}
	if (dirty || t->dirty) {
		flushimage(d, 1);
		t->dirty = 0;
	}
	if(locked)
		unlockdisplay(d);
	return nil;
}

int
tkischild(Tk *tk, Tk *child)
{
	while(child != nil && child != tk){
		if(child->master)
			child = child->master;
		else
			child = child->parent;
	}
	return child == tk;
}

void
tksetbits(Tk *tk, int mask)
{
	tk->flag |= mask;
	for(tk = tk->slave; tk; tk = tk->next)
		tksetbits(tk, mask);
}

char*
tkmap(Tk *tk)
{
/*
	is this necessary?
	tkw = TKobj(TkWin, tk);
	if(tkw->image != nil)
		tkwreq(tk->env->top, "raise %s", tk->name->name);
*/

	if(tk->flag & Tkmapped)
		return nil;

	tk->flag |= Tkmapped;
	tkmoveresize(tk, 0, 0, tk->act.width, tk->act.height);
	tkdeliver(tk, TkMap, nil);
	return nil;
//tkupdate(tk->env->top);
}

void
tkunmap(Tk *tk)
{
	TkTop *t;
	TkCtxt *c;

	while(tk->master)
		tk = tk->master;

	if((tk->flag & Tkmapped) == 0)
		return;

	t = tk->env->top;
	c = t->ctxt;

	if(tkischild(tk, c->mgrab))
		tksetmgrab(t, nil);
	if(tkischild(tk, c->entered)){
		tkdeliver(c->entered, TkLeave, nil);
		c->entered = nil;
	}
	if(tk == t->root)
		tksetglobalfocus(t, 0);

	tk->flag &= ~(Tkmapped|Tksuspended);

	tkdestroywinimage(tk);
	tkdeliver(tk, TkUnmap, nil);
	tkenterleave(t);
	/* XXX should unmap menus too */
}

Image*
tkimageof(Tk *tk)
{
	while(tk) {
		if(tk->flag & Tkwindow)
			return TKobj(TkWin, tk)->image;
		if(tk->parent != nil) {
			tk = tk->parent;
			switch(tk->type) {
			case TKmenu:
				return TKobj(TkWin, tk)->image;
			case TKcanvas:
				return TKobj(TkCanvas, tk)->image;
			case TKtext:
				return TKobj(TkText, tk)->image;
			}
			abort();
		}
		tk = tk->master;
	}
	return nil;
}

void
tktopopt(Tk *tk, char *opt)
{
	TkTop *t;
	TkWin *tkw;
	TkOptab tko[4];

	tkw = TKobj(TkWin, tk);

	t = tk->env->top;

	tko[0].ptr = tkw;
	tko[0].optab = tktop;
	tko[1].ptr = tk;
	tko[1].optab = tkgeneric;
	tko[2].ptr = t;
	tko[2].optab = tktopdbg;
	tko[3].ptr = nil;

	tkparse(t, opt, tko, nil);
}

/* general compare - compare top-left corners, y takes priority */
static int
tkfcmpgen(void *ap, void *bp)
{
	TkWinfo *a = ap, *b = bp;

	if (a->r.min.y > b->r.min.y)
		return 1;
	if (a->r.min.y < b->r.min.y)
		return -1;
	if (a->r.min.x > b->r.min.x)
		return 1;
	if (a->r.min.x < b->r.min.x)
		return -1;
	return 0;
}

/* compare x-coords only */
static int
tkfcmpx(void *ap, void *bp)
{
	TkWinfo *a = ap, *b = bp;
	return a->r.min.x - b->r.min.x;
}

/* compare y-coords only */
static int
tkfcmpy(void *ap, void *bp)
{
	TkWinfo *a = ap, *b = bp;
	return a->r.min.y - b->r.min.y;
}

static void
tkfintervalintersect(int min1, int max1, int min2, int max2, int *min, int *max)
{
	if (min1 < min2)
		min1 = min2;
	if (max1 > max2)
		max1 = max2;
	if (max1 > min1) {
		*min = min1;
		*max = max1;
	} else
		*max = *min;		/* no intersection */
}

void
tksortfocusorder(TkWinfo *inf, int n)
{
	int i;
	Rectangle overlap, r;
	int (*cmpfn)(void*, void*);

	overlap = inf[0].r;
	for (i = 0; i < n; i++) {
		r = inf[i].r;
		tkfintervalintersect(overlap.min.x, overlap.max.x,
				r.min.x, r.max.x, &overlap.min.x, &overlap.max.x);
		tkfintervalintersect(overlap.min.y, overlap.max.y,
				r.min.y, r.max.y, &overlap.min.y, &overlap.max.y);
	}

	if (Dx(overlap) > 0)
		cmpfn = tkfcmpy;
	else if (Dy(overlap) > 0)
		cmpfn = tkfcmpx;
	else
		cmpfn = tkfcmpgen;

	qsort(inf, n, sizeof(*inf), cmpfn);
}

void
tkappendfocusorder(Tk *tk)
{
	TkTop *tkt;
	tkt = tk->env->top;
	if (tk->flag & Tktakefocus)
		tkt->focusorder[tkt->nfocus++] = tk;
	if (tkmethod[tk->type]->focusorder != nil)
		tkmethod[tk->type]->focusorder(tk);
}

void
tkbuildfocusorder(TkTop *tkt)
{
	Tk *tk;
	int n;

	if (tkt->focusorder != nil)
		free(tkt->focusorder);
	n = 0;
	for (tk = tkt->root; tk != nil; tk = tk->siblings)
		if (tk->flag & Tktakefocus)
			n++;
	if (n == 0) {
		tkt->focusorder = nil;
		return;
	}

	tkt->focusorder = malloc(sizeof(*tkt->focusorder) * n);
	tkt->nfocus = 0;
	if (tkt->focusorder == nil)
		return;

	tkappendfocusorder(tkt->root);
}

void
tkdirtyfocusorder(TkTop *tkt)
{
	free(tkt->focusorder);
	tkt->focusorder = nil;
	tkt->nfocus = 0;
}

#define	O(t, e)		((long)(&((t*)0)->e))
#define OA(t, e)	((long)(((t*)0)->e))

typedef struct TkSee TkSee;
struct TkSee {
	int r[4];
	int p[2];
	int query;
};

static
TkOption seeopts[] = {
	"rectangle",		OPTfrac,	OA(TkSee, r),	IAUX(4),
	"point",			OPTfrac,	OA(TkSee, p),	IAUX(2),
	"where",			OPTbool,	O(TkSee, query),	nil,
	nil
};

char*
tkseecmd(TkTop *t, char *arg, char **ret)
{
	TkOptab tko[2];
	TkSee opts;
	TkName *names;
	Tk *tk;
	char *e;
	Rectangle vr;
	Point vp;

	opts.r[0] = bbnil.min.x;
	opts.r[1] = bbnil.min.y;
	opts.r[2] = bbnil.max.x;
	opts.r[3] = bbnil.max.y;
	opts.p[0] = bbnil.max.x;
	opts.p[1] = bbnil.max.y;
	opts.query = 0;

	tko[0].ptr = &opts;
	tko[0].optab = seeopts;
	tko[1].ptr = nil;
	names = nil;
	e = tkparse(t, arg, tko, &names);
	if (e != nil)
		return e;
	if (names == nil)
		return TkBadwp;
	tk = tklook(t, names->name, 0);
	tkfreename(names);
	if (tk == nil)
		return TkBadwp;
	if (opts.query) {
		if (!tkvisiblerect(tk, &vr))
			return nil;
		/* XXX should this be converted into screen coords? */
		return tkvalue(ret, "%d %d %d %d", vr.min.x, vr.min.y, vr.max.x, vr.max.y);
	}
	vr.min.x = opts.r[0];
	vr.min.y = opts.r[1];
	vr.max.x = opts.r[2];
	vr.max.y = opts.r[3];
	vp.x = opts.p[0];
	vp.y = opts.p[1];

	if (eqrect(vr, bbnil))
		vr = tkrect(tk, 1);
	if (eqpt(vp, bbnil.max))
		vp = vr.min;
	tksee(tk, vr, vp);
	return nil;
}

/*
 * make rectangle r in widget tk visible if possible;
 * if not possible, at least make point p visible.
 */
void
tksee(Tk *tk, Rectangle r, Point p)
{
	Point g;
//print("tksee %R, %P in %s\n", r, p, tk->name->name);
	g = Pt(tk->borderwidth, tk->borderwidth);
	if(tk->parent != nil) {
		g = addpt(g, tkmethod[tk->parent->type]->relpos(tk));
		tk = tk->parent;
	} else {
		g.x += tk->act.x;
		g.y += tk->act.y;
		tk = tk->master;
	}
	r = rectaddpt(r, g);
	p = addpt(p, g);
	while (tk != nil) {
		if (tkmethod[tk->type]->see != nil){
//print("see r %R, p %P in %s\n", r, p, tk->name->name);
			tkmethod[tk->type]->see(tk, &r, &p);
//print("now r %R, p %P\n", r, p);
		}
		g = Pt(tk->borderwidth, tk->borderwidth);
		if (tk->parent != nil) {
			g = addpt(g, tkmethod[tk->parent->type]->relpos(tk));
			tk = tk->parent;
		} else {
			g.x += tk->act.x;
			g.y += tk->act.y;
			tk = tk->master;
		}
		r = rectaddpt(r, g);
		p = addpt(p, g);
	}
}
