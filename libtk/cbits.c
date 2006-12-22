#include "lib9.h"
#include "draw.h"
#include "tk.h"
#include "canvs.h"

#define	O(t, e)		((long)(&((t*)0)->e))

/* Bitmap Options (+ means implemented)
	+anchor
	+bitmap
*/

typedef struct TkCbits TkCbits;
struct TkCbits
{
	int	anchor;
	Point	anchorp;
	Image*	bitmap;
};

static
TkOption bitopts[] =
{
	"anchor",	OPTstab,	O(TkCbits, anchor),	tkanchor,
	"bitmap",	OPTbmap,	O(TkCbits, bitmap),	nil,
	nil
};

static
TkOption itemopts[] =
{
	"tags",		OPTctag,	O(TkCitem, tags),	nil,
	"background",	OPTcolr,	O(TkCitem, env),	IAUX(TkCbackgnd),
	"foreground",	OPTcolr,	O(TkCitem, env),	IAUX(TkCforegnd),
	nil
};

void
tkcvsbitsize(TkCitem *i)
{
	Point o;
	int dx, dy;
	TkCbits *b;

	b = TKobj(TkCbits, i);
	i->p.bb = bbnil;
	if(b->bitmap == nil)
		return;

	dx = Dx(b->bitmap->r);
	dy = Dy(b->bitmap->r);

	o = tkcvsanchor(i->p.drawpt[0], dx, dy, b->anchor);

	i->p.bb.min.x = o.x;
	i->p.bb.min.y = o.y;
	i->p.bb.max.x = o.x + dx;
	i->p.bb.max.y = o.y + dy;
	b->anchorp = subpt(o, i->p.drawpt[0]);
}

char*
tkcvsbitcreat(Tk* tk, char *arg, char **val)
{
	char *e;
	TkCbits *b;
	TkCitem *i;
	TkCanvas *c;
	TkOptab tko[3];

	c = TKobj(TkCanvas, tk);

	i = tkcnewitem(tk, TkCVbitmap, sizeof(TkCitem)+sizeof(TkCbits));
	if(i == nil)
		return TkNomem;

	b = TKobj(TkCbits, i);

	e = tkparsepts(tk->env->top, &i->p, &arg, 0);
	if(e != nil) {
		tkcvsfreeitem(i);
		return e;
	}
	if(i->p.npoint != 1) {
		tkcvsfreeitem(i);
		return TkFewpt;
	}

	tko[0].ptr = b;
	tko[0].optab = bitopts;
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

	tkcvsbitsize(i);
	tkcvsappend(c, i);

	tkbbmax(&c->update, &i->p.bb);
	tkcvssetdirty(tk);
	return tkvalue(val, "%d", i->id);
}

char*
tkcvsbitcget(TkCitem *i, char *arg, char **val)
{
	TkOptab tko[3];
	TkCbits *b = TKobj(TkCbits, i);

	tko[0].ptr = b;
	tko[0].optab = bitopts;
	tko[1].ptr = i;
	tko[1].optab = itemopts;
	tko[2].ptr = nil;

	return tkgencget(tko, arg, val, i->env->top);
}

char*
tkcvsbitconf(Tk *tk, TkCitem *i, char *arg)
{
	char *e;
	TkOptab tko[3];
	TkCbits *b = TKobj(TkCbits, i);

	tko[0].ptr = b;
	tko[0].optab = bitopts;
	tko[1].ptr = i;
	tko[1].optab = itemopts;
	tko[2].ptr = nil;

	e = tkparse(tk->env->top, arg, tko, nil);
	tkcvsbitsize(i);
	return e;
}

void
tkcvsbitfree(TkCitem *i)
{
	TkCbits *b;

	b = TKobj(TkCbits, i);
	if(b->bitmap)
		freeimage(b->bitmap);
}

void
tkcvsbitdraw(Image *img, TkCitem *i, TkEnv *pe)
{
	TkEnv *e;
	TkCbits *b;
	Rectangle r;
	Image *bi;

	USED(pe);

	e = i->env;
	b = TKobj(TkCbits, i);

	bi = b->bitmap;
	if(bi == nil)
		return;

	r.min = addpt(b->anchorp, i->p.drawpt[0]);
	r.max = r.min;
	r.max.x += Dx(bi->r);
	r.max.y += Dy(bi->r);

	if(bi->depth != 1) {
		draw(img, r, bi, nil, ZP);
		return;
	}
	gendraw(img, r, tkgc(e, TkCbackgnd), r.min, nil, ZP);
	draw(img, r, tkgc(e, TkCforegnd), bi, ZP);
}

char*
tkcvsbitcoord(TkCitem *i, char *arg, int x, int y)
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
		if(p.npoint != 1) {
			tkfreepoint(&p);
			return TkFewpt;
		}
		tkfreepoint(&i->p);
		i->p = p;
		tkcvsbitsize(i);
	}
	return nil;
}
