#include <lib9.h>
#include <kernel.h>
#include "draw.h"
#include "tk.h"
#include "canvs.h"

#define	O(t, e)		((long)(&((t*)0)->e))

/* Text Options (+ means implemented)
	+anchor
	+fill
	+font
	+justify
	+stipple
	+tags
	+text
	+width
*/

/* Layout constants */
enum {
	Cvsicursor	= 1,	/* Extra height of insertion cursor in canvas */
};

typedef struct TkCtext TkCtext;
struct TkCtext
{
	int	anchor;
	Point	anchorp;
	int	justify;
	int	icursor;
	int	focus;
	int	pixwidth;
	int	pixheight;
	int	sell;
	int	self;
	int	selfrom;
	int	sbw;
	int	width;
	int	nlines;
	Image*	stipple;
	Image*	pen;
	char*	text;
	int	tlen;
	TkEnv	*env;
};

static
TkOption textopts[] =
{
	"anchor",	OPTstab,	O(TkCtext, anchor),	tkanchor,
	"justify",	OPTstab,	O(TkCtext, justify),	tktabjust,
	"width",	OPTdist,	O(TkCtext, width),	IAUX(O(TkCtext, env)),
	"stipple",	OPTbmap,	O(TkCtext, stipple),	nil,
	"text",		OPTtext,	O(TkCtext, text),	nil,
	nil
};

static
TkOption itemopts[] =
{
	"tags",		OPTctag,	O(TkCitem, tags),	nil,
	"font",		OPTfont,	O(TkCitem, env),	nil,
	"fill",		OPTcolr,	O(TkCitem, env),	IAUX(TkCfill),
	nil
};

static char*
tkcvstextgetl(TkCtext *t, Font *font, char *start, int *len)
{
	int w, n;
	char *lspc, *posn;

	w = t->width;
	if(w <= 0)
		w = 1000000;

	n = 0;
	lspc = nil;
	posn = start;
	while(*posn && *posn != '\n') {
		if(*posn == ' ')
			lspc = posn;
		n += stringnwidth(font, posn, 1);
		if(n >= w && posn != start) {
			if(lspc != nil)
				posn = lspc;
			*len = posn - start;
			if(lspc != nil)
				posn++;
			return posn;
		}
		posn++;
	}
	*len = posn - start;
	if(*posn == '\n')
		posn++;
	return posn;
}

void
tkcvstextsize(TkCitem *i)
{
	Point o;
	Font *font;
	TkCtext *t;
	Display *d;
	char *next, *p;
	int len, pixw, locked;

	t = TKobj(TkCtext, i);

	font = i->env->font;
	d = i->env->top->display;
	t->pixwidth = 0;
	t->pixheight = 0;

	p = t->text;
	if(p != nil) {
		locked = lockdisplay(d);
		while(*p) {
			next = tkcvstextgetl(t, font, p, &len);
			pixw = stringnwidth(font, p, len);
			if(pixw > t->pixwidth)
				t->pixwidth = pixw;
			t->pixheight += font->height;
			p = next;
		}
		if(locked)
			unlockdisplay(d);
	}

	o = tkcvsanchor(i->p.drawpt[0], t->pixwidth, t->pixheight, t->anchor);

	i->p.bb.min.x = o.x;
	i->p.bb.min.y = o.y - Cvsicursor;
	i->p.bb.max.x = o.x + t->pixwidth;
	i->p.bb.max.y = o.y + t->pixheight + Cvsicursor;
	i->p.bb = insetrect(i->p.bb, -2*t->sbw);
	t->anchorp = subpt(o, i->p.drawpt[0]);
}

char*
tkcvstextcreat(Tk* tk, char *arg, char **val)
{
	char *e;
	TkCtext *t;
	TkCitem *i;
	TkCanvas *c;
	TkOptab tko[3];

	c = TKobj(TkCanvas, tk);

	i = tkcnewitem(tk, TkCVtext, sizeof(TkCitem)+sizeof(TkCtext));
	if(i == nil)
		return TkNomem;

	t = TKobj(TkCtext, i);
	t->justify = Tkleft;
	t->anchor = Tkcenter;
	t->sell = -1;
	t->self = -1;
	t->icursor = -1;
	t->sbw = c->sborderwidth;
	t->env = tk->env;

	e = tkparsepts(tk->env->top, &i->p, &arg, 0);
	if(e != nil) {
		tkcvsfreeitem(i);
		return e;
	}
	if(i->p.npoint != 1) {
		tkcvsfreeitem(i);
		return TkFewpt;
	}

	tko[0].ptr = t;
	tko[0].optab = textopts;
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

	t->tlen = 0;
	if(t->text != nil)
		t->tlen = strlen(t->text);

	tkmkpen(&t->pen, i->env, t->stipple);
	tkcvstextsize(i);
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
tkcvstextcget(TkCitem *i, char *arg, char **val)
{
	TkOptab tko[3];
	TkCtext *t = TKobj(TkCtext, i);

	tko[0].ptr = t;
	tko[0].optab = textopts;
	tko[1].ptr = i;
	tko[1].optab = itemopts;
	tko[2].ptr = nil;

	return tkgencget(tko, arg, val, i->env->top);
}

char*
tkcvstextconf(Tk *tk, TkCitem *i, char *arg)
{
	char *e;
	TkOptab tko[3];
	TkCtext *t = TKobj(TkCtext, i);

	tko[0].ptr = t;
	tko[0].optab = textopts;
	tko[1].ptr = i;
	tko[1].optab = itemopts;
	tko[2].ptr = nil;

	e = tkparse(tk->env->top, arg, tko, nil);

	t->tlen = 0;
	if(t->text != nil)
		t->tlen = strlen(t->text);

	tkmkpen(&t->pen, i->env, t->stipple);
	tkcvstextsize(i);

	return e;
}

void
tkcvstextfree(TkCitem *i)
{
	TkCtext *t;

	t = TKobj(TkCtext, i);
	if(t->stipple != nil)
		freeimage(t->stipple);
	if(t->pen != nil)
		freeimage(t->pen);
	if(t->text != nil)
		free(t->text);
}

void
tkcvstextdraw(Image *img, TkCitem *i, TkEnv *pe)
{
	TkEnv *e;
	TkCtext *t;
	Point o, dp;
	Rectangle r;
	char *p, *next;
	Image *pen;
	int len, lw, end, start;

	t = TKobj(TkCtext, i);

	e = i->env;
	pen = t->pen;
	if(pen == nil) {
		if (e->set & (1<<TkCfill))
			pen = tkgc(e, TkCfill);
		else
			pen = img->display->black;
	}


	o = addpt(t->anchorp, i->p.drawpt[0]);
	p = t->text;
	while(p && *p) {
		next = tkcvstextgetl(t, e->font, p, &len);
		dp = o;
		if(t->justify != Tkleft) {
			lw = stringnwidth(e->font, p, len);
			if(t->justify == Tkcenter)
				dp.x += (t->pixwidth - lw)/2;
			else
			if(t->justify == Tkright)
				dp.x += t->pixwidth - lw;
		}
		lw = p - t->text;
		if(t->self != -1 && lw+len > t->self) {
			if(t->sell >= t->self) {
				start = t->self - lw;
				end = t->sell - lw;
			}
			else {
				start = t->sell - lw;
				end = t->self - lw;
			}
			if(start < 0)
				r.min.x = o.x;
			else
				r.min.x = dp.x + stringnwidth(e->font, p, start);
			r.min.y = dp.y;
			if(end > len)
				r.max.x = o.x + t->pixwidth;
			else
				r.max.x = dp.x + stringnwidth(e->font, p, end);
			r.max.y = dp.y + e->font->height;
			tktextsdraw(img, r, pe, t->sbw);
			r.max.y = dp.y;
			if(start > 0)
				stringn(img, dp, pen, dp, e->font, p, start);
			if(end > start)
				stringn(img, r.min, tkgc(pe, TkCselectfgnd), r.min, e->font, p+start, end-start);
			if(len > end)
				stringn(img, r.max, pen, r.max, e->font, p+end, len-end);
		}
		else
			stringn(img, dp, pen, dp, e->font, p, len);
		if(t->focus) {
			lw = p - t->text;
			if(t->icursor >= lw && t->icursor <= lw+len) {
				lw = t->icursor - lw;
				if(lw > 0)
					lw = stringnwidth(e->font, p, lw);
				r.min.x = dp.x + lw;
				r.min.y = dp.y - 1;
				r.max.x = r.min.x + 2;
				r.max.y = r.min.y + e->font->height + 1;
				draw(img, r, pen, nil, ZP);
			}
		}
		o.y += e->font->height;
		p = next;
	}
}

char*
tkcvstextcoord(TkCitem *i, char *arg, int x, int y)
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
		tkcvstextsize(i);
	}
	return nil;
}

int
tkcvstextsrch(TkCitem *i, int x, int y)
{
	TkCtext *t;
	Font *font;
	Display *d;
	char *p, *next;
	int n, len, locked;

	t = TKobj(TkCtext, i);

	n = 0;
	font = i->env->font;
	d = i->env->top->display;
	p = t->text;
	if(p == nil)
		return 0;
	while(*p) {
		next = tkcvstextgetl(t, font, p, &len);
		if(y <= font->height) {
			locked = lockdisplay(d);
			for(n = 0; n < len && x > stringnwidth(font, p, n+1); n++)
				;
			if(locked)
				unlockdisplay(d);
			break;
		}
		y -= font->height;
		p = next;
	}	
	return p - t->text + n;
}

static char*
tkcvsparseindex(TkCitem *i, char *buf, int *index)
{
	Point o;
	char *p;
	int x, y;
	TkCtext *t;

	t = TKobj(TkCtext, i);

	if(strcmp(buf, "end") == 0) {
		*index = t->tlen;
		return nil;
	}
	if(strcmp(buf, "sel.first") == 0) {
		if(t->self < 0)
			return TkBadix;
		*index = t->self;
		return nil;
	}
	if(strcmp(buf, "sel.last") == 0) {
		if(t->sell < 0)
			return TkBadix;
		*index = t->sell;
		return nil;
	}
	if(strcmp(buf, "insert") == 0) {
		*index = t->icursor;
		return nil;
	}
	if(buf[0] == '@') {
		x = atoi(buf+1);
		p = strchr(buf, ',');
		if(p == nil)
			return TkBadix;
		y = atoi(p+1);
		o = i->p.drawpt[0];
		*index = tkcvstextsrch(i, (x-t->anchorp.x)-o.x, (y-t->anchorp.y)-o.y);
		return nil;
	}

	if(buf[0] < '0' || buf[0] > '9')
		return TkBadix;
	x = atoi(buf);
	if(x < 0)
		x = 0;
	if(x > t->tlen)
		x = t->tlen;
	*index = x;	
	return nil;
}

char*
tkcvstextdchar(Tk *tk, TkCitem *i, char *arg)
{
	TkTop *top;
	TkCtext *t;
	int first, last;
	char *e, buf[Tkmaxitem];

	t = TKobj(TkCtext, i);

	top = tk->env->top;
	arg = tkword(top, arg, buf, buf+sizeof(buf), nil);
	e = tkcvsparseindex(i, buf, &first);
	if(e != nil)
		return e;

	last = first+1;
	if(*arg != '\0') {
		tkword(top, arg, buf, buf+sizeof(buf), nil);
		e = tkcvsparseindex(i, buf, &last);
		if(e != nil)
			return e;
	}
	if(last <= first || t->tlen == 0)
		return nil;

	tkbbmax(&TKobj(TkCanvas, tk)->update, &i->p.bb);

	memmove(t->text+first, t->text+last, t->tlen-last+1);
	t->tlen -= last-first;

	tkcvstextsize(i);
	tkbbmax(&TKobj(TkCanvas, tk)->update, &i->p.bb);

	tkcvssetdirty(tk);
	return nil;
}

char*
tkcvstextinsert(Tk *tk, TkCitem *i, char *arg)
{
	TkTop *top;
	TkCtext *t;
	int first, n;
	char *e, *text, buf[Tkmaxitem];

	t = TKobj(TkCtext, i);

	top = tk->env->top;
	arg = tkword(top, arg, buf, buf+sizeof(buf), nil);
	e = tkcvsparseindex(i, buf, &first);
	if(e != nil)
		return e;

	if(*arg == '\0')
		return nil;

	text = malloc(Tkcvstextins);
	if(text == nil)
		return TkNomem;

	tkword(top, arg, text, text+Tkcvstextins, nil);
	n = strlen(text);
	t->text = realloc(t->text, t->tlen+n+1);
	if(t->text == nil) {
		free(text);
		return TkNomem;
	}
	if(t->tlen == 0)
		t->text[0] = '\0';

	tkbbmax(&TKobj(TkCanvas, tk)->update, &i->p.bb);

	memmove(t->text+first+n, t->text+first, t->tlen-first+1);
	memmove(t->text+first, text, n);
	t->tlen += n;
	free(text);

	tkcvstextsize(i);
	tkbbmax(&TKobj(TkCanvas, tk)->update, &i->p.bb);

	tkcvssetdirty(tk);
	return nil;
}

char*
tkcvstextindex(Tk *tk, TkCitem *i, char *arg, char **val)
{
	int first;
	char *e, buf[Tkmaxitem];

	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	e = tkcvsparseindex(i, buf, &first);
	if(e != nil)
		return e;

	return tkvalue(val, "%d", first);
}

char*
tkcvstexticursor(Tk *tk, TkCitem *i, char *arg)
{
	int first;
	TkCanvas *c;
	char *e, buf[Tkmaxitem];

	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	e = tkcvsparseindex(i, buf, &first);
	if(e != nil)
		return e;

	TKobj(TkCtext, i)->icursor = first;

	c = TKobj(TkCanvas, tk);
	if(c->focus == i) {
		tkbbmax(&c->update, &i->p.bb);
		tkcvssetdirty(tk);
	}
	return nil;
}

void
tkcvstextfocus(Tk *tk, TkCitem *i, int x)
{
	TkCtext *t;
	TkCanvas *c;

	if(i == nil)
		return;

	t = TKobj(TkCtext, i);
	c = TKobj(TkCanvas, tk);

	if(t->focus != x) {
		t->focus = x;
		tkbbmax(&c->update, &i->p.bb);
		tkcvssetdirty(tk);
	}
}

void
tkcvstextclr(Tk *tk)
{
	TkCtext *t;
	TkCanvas *c;
	TkCitem *item;

	c = TKobj(TkCanvas, tk);
	item = c->selection;
	if(item == nil)
		return;

	c->selection = nil;
	t = TKobj(TkCtext, item);
	t->sell = -1;
	t->self = -1;
	tkbbmax(&c->update, &item->p.bb);
	tkcvssetdirty(tk);
}

char*
tkcvstextselect(Tk *tk, TkCitem *i, char *arg, int op)
{
	int indx;
	TkCtext *t;
	TkCanvas *c;
	char *e, buf[Tkmaxitem];

	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	e = tkcvsparseindex(i, buf, &indx);
	if(e != nil)
		return e;

	c = TKobj(TkCanvas, tk);
	t = TKobj(TkCtext, i);
	switch(op) {
	case TkCselfrom:
		t->selfrom = indx;
		return nil;
	case TkCseladjust:
		if(c->selection == i) {
			if(abs(t->self-indx) < abs(t->sell-indx)) {
				t->self = indx;
				t->selfrom = t->sell;
			}
			else {
				t->sell = indx;
				t->selfrom = t->self;
			}
		}
		/* No break */
	case TkCselto:
		if(c->selection != i)
			tkcvstextclr(tk);
		c->selection = i;
		t->self = t->selfrom;
		t->sell = indx;
		break;
	}
	t->sbw = c->sborderwidth;
	tkbbmax(&TKobj(TkCanvas, tk)->update, &i->p.bb);
	tkcvssetdirty(tk);
	return nil;
}
