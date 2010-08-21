#include <lib9.h>
#include <kernel.h>
#include "draw.h"
#include "tk.h"
#include "canvs.h"

char*
tkparsepts(TkTop *t, TkCpoints *i, char **arg, int close)
{
	char *s, *e;
	Point *p, *d;
	int n, npoint;

	i->parampt = nil;
	i->drawpt = nil;
	i->bb = bbnil;
	s = *arg;
	npoint = 0;
	while(*s) {
		s = tkskip(s, " \t");
		if(*s == '-' && (s[1] < '0' || s[1] > '9'))
			break;
		while(*s && *s != ' ' && *s != '\t')
			s++;
		npoint++;
	}

	i->parampt = mallocz(npoint*sizeof(Point), 0);
	if(i->parampt == nil)
		return TkNomem;

	s = *arg;
	p = i->parampt;
	npoint = 0;
	while(*s) {
		e = tkfracword(t, &s, &p->x, nil);
		if(e != nil)
			goto Error;
		e = tkfracword(t, &s, &p->y, nil);
		if(e != nil)
			goto Error;
		npoint++;
		s = tkskip(s, " \t");
		if(*s == '-' && (s[1] < '0' || s[1] > '9'))
			break;
		p++;
	}
	*arg = s;
	close = (close != 0);
	i->drawpt = mallocz((npoint+close)*sizeof(Point), 0);
	if(i->drawpt == nil){
		e = TkNomem;
		goto Error;
	}

	d = i->drawpt;
	p = i->parampt;
	for(n = 0; n < npoint; n++) {
		d->x = TKF2I(p->x);
		d->y = TKF2I(p->y);
		if(d->x < i->bb.min.x)
			i->bb.min.x = d->x;
		if(d->x > i->bb.max.x)
			i->bb.max.x = d->x;
		if(d->y < i->bb.min.y)
			i->bb.min.y = d->y;
		if(d->y > i->bb.max.y)
			i->bb.max.y = d->y;
		d++;
		p++;
	}
	if (close)
		*d = i->drawpt[0];			

	i->npoint = npoint;
	return nil;

Error:
	tkfreepoint(i);
	i->parampt = nil;
	i->drawpt = nil;
	return e;
}

TkCitem*
tkcnewitem(Tk *tk, int t, int n)
{
	TkCitem *i;

	i = malloc(n);
	if(i == nil)
		return nil;
	memset(i, 0, n);

	i->type = t;
	i->env = tk->env;
	i->env->ref++;

	return i;
}

/*
 * expand the canvas's dirty rectangle, clipping
 * appropriately to its boundaries.
 */
void
tkcvssetdirty(Tk *tk)
{
	TkCanvas *c;
	Rectangle r;
	c = TKobj(TkCanvas, tk);

	r = tkrect(tk, 0);
	if (rectclip(&r, rectsubpt(c->update, c->view)))
		combinerect(&tk->dirty, r);
}

void
tkxlatepts(Point *p, int npoints, int x, int y)
{
	while(npoints--) {
		p->x += x;
		p->y += y;
		p++;
	}
}

void
tkbbmax(Rectangle *bb, Rectangle *r)
{
	if(r->min.x < bb->min.x)
		bb->min.x = r->min.x;
	if(r->min.y < bb->min.y)
		bb->min.y = r->min.y;
	if(r->max.x > bb->max.x)
		bb->max.x = r->max.x;
	if(r->max.y > bb->max.y)
		bb->max.y = r->max.y;
}

void
tkpolybound(Point *p, int n, Rectangle *r)
{
	while(n--) {
		if(p->x < r->min.x)
			r->min.x = p->x;
		if(p->y < r->min.y)
			r->min.y = p->y;
		if(p->x > r->max.x)
			r->max.x = p->x;
		if(p->y > r->max.y)
			r->max.y = p->y;
		p++;
	}
}

/*
 * look up a tag for a canvas item.
 * if n is non-nil, and the tag isn't found,
 * then add it to the canvas's taglist.
 * NB if there are no binds done on the
 * canvas, these tags never get cleared out,
 * even if nothing refers to them.
 */
TkName*
tkctaglook(Tk* tk, TkName *n, char *name)
{
	ulong h;
	TkCanvas *c;
	char *p, *s;
	TkName *f, **l;

	c = TKobj(TkCanvas, tk);

	s = name;
	if(s == nil)
		s = n->name;

	if(strcmp(s, "current") == 0)
		return c->current;

	h = 0;
	for(p = s; *p; p++)
		h += 3*h + *p;

	l = &c->thash[h%TkChash];
	for(f = *l; f; f = f->link)
		if(strcmp(f->name, s) == 0)
			return f;

	if(n == nil)
		return nil;
	n->link = *l;
	*l = n;
	return n;
}

char*
tkcaddtag(Tk *tk, TkCitem *i, int new)
{
	TkCtag *t;
	TkCanvas *c;
	char buf[16];
	TkName *n, *f, *link;

	c = TKobj(TkCanvas, tk);
	if(new != 0) {
		i->id = ++c->id;
		snprint(buf, sizeof(buf), "%d", i->id);
		n = tkmkname(buf);
		if(n == nil)
			return TkNomem;
		n->link = i->tags;
		i->tags = n;
	}

	for(n = i->tags; n; n = link) {
		link = n->link;
		f = tkctaglook(tk, n, nil);
		if(n != f)
			free(n);

		for(t = i->stag; t; t = t->itemlist)
			if(t->name == f)
				break;
		if(t == nil) {
			t = malloc(sizeof(TkCtag));
			if(t == nil) {
				tkfreename(link);
				return TkNomem;
			}
			t->name = f;
			t->taglist = f->obj;		/* add to head of items with this tag */
			f->obj = t;
			t->item = i;
			t->itemlist = i->stag;	/* add to head of tags for this item */
			i->stag = t;
		}
	}
	i->tags = nil;

	if(new != 0) {
		i->tags = tkmkname("all");
		if(i->tags == nil)
			return TkNomem;		/* XXX - Tad: memory leak? */
		return tkcaddtag(tk, i, 0);
	}

	return nil;
}

void
tkfreepoint(TkCpoints *p)
{
	free(p->drawpt);
	free(p->parampt);
}

/*
 * of all the items in ilist tagged with tag,
 * return that tag for the first (topmost) item.
 */
TkCtag*
tkclasttag(TkCitem *ilist, TkCtag* tag)
{
	TkCtag *last, *t;

	if (tag == nil || tag->taglist == nil)
		return tag;
	last = nil;
	while(ilist) {
		for(t = tag; t; t = t->taglist) {
			if(t->item == ilist) {
				last = t;
				break;
			}
		}
		ilist = ilist->next;
	}
	return last;
}

/*
 * of all the items in ilist tagged with tag,
 * return that tag for the first (bottommost) item.
 */
TkCtag*
tkcfirsttag(TkCitem *ilist, TkCtag* tag)
{
	TkCtag *t;

	if (tag == nil || tag->taglist == nil)
		return tag;
	for (; ilist != nil; ilist = ilist->next)
		for(t = tag; t; t = t->taglist)
			if(t->item == ilist)
				return t;
	return nil;
}
		
void
tkmkpen(Image **pen, TkEnv *e, Image *stipple)
{
	int locked;
	Display *d;
	Image *new, *fill;

	fill = tkgc(e, TkCfill);

	d = e->top->display;
	locked = lockdisplay(d);
	if(*pen != nil) {
		freeimage(*pen);
		*pen = nil;
	}
	if(stipple == nil) {
		if(locked)
			unlockdisplay(d);
		return;
	}

	if(fill == nil)
		fill = d->black;
	new = allocimage(d, stipple->r, RGBA32, 1, DTransparent);	/* XXX RGBA32 is excessive sometimes... */
	if (new != nil)
		draw(new, stipple->r, fill, stipple, ZP);
	else
		new = fill;
	if(locked)
		unlockdisplay(d);
	*pen = new;
}

Point
tkcvsanchor(Point dp, int w, int h, int anchor)
{
	Point o;

	if(anchor & Tknorth)
		o.y = dp.y;
	else
	if(anchor & Tksouth)
		o.y = dp.y - h;
	else
		o.y = dp.y - h/2;

	if(anchor & Tkwest)
		o.x = dp.x;
	else
	if(anchor & Tkeast)
		o.x = dp.x - w;
	else
		o.x = dp.x - w/2;

	return o;
}

static TkCitem*
tkcvsmousefocus(TkCanvas *c, Point p)
{
	TkCitem *i, *s;
	int (*hit)(TkCitem*, Point);

	if (c->grab != nil)
		return c->grab;
	s = nil;
	for(i = c->head; i; i = i->next)
		if(ptinrect(p, i->p.bb)) {
			if ((hit = tkcimethod[i->type].hit) != nil && !(*hit)(i, p))
				continue;
			s = i;
		}

	return s;
}

Tk*
tkcvsinwindow(Tk *tk, Point *p)
{
	TkCanvas *c;
	TkCitem *i;
	Point q;
	TkCwind *w;

	c = TKobj(TkCanvas, tk);

	q = addpt(*p, c->view);
	i = tkcvsmousefocus(c, addpt(*p, c->view));
	if (i == nil || i->type != TkCVwindow)
		return tk;
	w = TKobj(TkCwind, i);
	if (w->sub == nil)
		return tk;
	p->x = q.x - (i->p.bb.min.x + w->sub->borderwidth);
	p->y = q.y - (i->p.bb.min.y + w->sub->borderwidth);
	return w->sub;
}

static Tk*
tkcvsmouseinsub(TkCwind *w, TkMouse m)
{
	Point g, mp;
	int bd;

	g = tkposn(w->sub);
	bd = w->sub->borderwidth;
	mp.x = m.x - (g.x + bd);
	mp.y = m.y - (g.y + bd);
	return tkinwindow(w->sub, mp, 0);
}

static Tk*
tkcvsdeliver(Tk *tk, TkCitem *i, int event, void *data)
{
	Tk *ftk, *dest;
	TkCtag *t;
	TkCwind *w;
	TkAction *a;

	if(i->type == TkCVwindow) {
		dest = nil;
		w = TKobj(TkCwind, i);
		if(w->sub == nil)
			return nil;

		if(!(event & TkKey) && (event & TkEmouse)) {
			ftk = tkcvsmouseinsub(w, *(TkMouse*)data);
			if(ftk != w->focus) {
{TkCitem *si; if(w->focus != nil && (si = tkcvsfindwin(w->focus)) != i)print("focus botch 4: i=%p si=%p\n", i, si);}
				tkdeliver(w->focus, TkLeave, data);
{TkCitem *si; if(ftk != nil && (si = tkcvsfindwin(ftk)) != i)print("focus botch: i=%p si=%p\n", i, si);}
if(0)print("focus %p %q %p %q\n", w->sub, tkname(w->sub), ftk, tkname(ftk));
				tkdeliver(ftk, TkEnter, data);
				w->focus = ftk;
			}
else{TkCitem *si; if(ftk != nil && (si = tkcvsfindwin(ftk)) != i)print("focus botch 2: i=%p si=%p\n", i, si);}
			if(ftk != nil)
				dest = tkdeliver(ftk, event, data);
		} else {
{TkCitem *si; if(w->focus != nil && (si = tkcvsfindwin(w->focus)) != i)print("focus botch 3: i=%p si=%p\n", i, si);}
			if(event & TkLeave) {
				tkdeliver(w->focus, TkLeave, data);
				w->focus = nil;
			} else if(event & TkEnter) {
				ftk = tkcvsmouseinsub(w, *(TkMouse*)data);
				tkdeliver(ftk, TkEnter, data);
				w->focus = ftk;
			} else
				dest = tkdeliver(w->sub, event, data);
		}
		return dest;
	}

	for(t = i->stag; t != nil; t = t->itemlist) {
		a = t->name->prop.binds;
		if(a != nil)
			tksubdeliver(tk, a, event, data, 0);
	}
	return nil;
}

Tk*
tkcvsevent(Tk *tk, int event, void *data)
{
	TkMouse m;
	TkCitem *f;
	Point mp, g;
	TkCanvas *c;
	Tk *dest;

	c = TKobj(TkCanvas, tk);

	if(event == TkLeave && c->mouse != nil) {
		tkcvsdeliver(tk, c->mouse, TkLeave, data);
		c->mouse = nil;
	}

	dest = nil;
	if(!(event & TkKey) && (event & TkEmouse) || (event & TkEnter)) {
		m = *(TkMouse*)data;
		g = tkposn(tk);
		mp.x = (m.x - g.x - tk->borderwidth) + c->view.x;
		mp.y = (m.y - g.y - tk->borderwidth) + c->view.y;
		f = tkcvsmousefocus(c, mp);
		if(c->mouse != f) {
			if(c->mouse != nil) {
				tkcvsdeliver(tk, c->mouse, TkLeave, data);
				c->current->obj = nil;
			}
			if(f != nil) {
				c->current->obj = &c->curtag;
				c->curtag.item = f;
				tkcvsdeliver(tk, f, TkEnter, data);
			}
			c->mouse = f;
		}
		f = c->mouse;
		if(f != nil && (event & TkEnter) == 0)
			dest = tkcvsdeliver(tk, f, event, &m);
	}

	if(event & TkKey) {
		f = c->focus;
		if(f != nil)
			tkcvsdeliver(tk, f, event, data);
	}
	if(dest == nil)
		tksubdeliver(tk, tk->binds, event, data, 0);
	return dest;
}

/*
 * debugging
 */
void
tkcvsdump(Tk *tk)
{
	TkCanvas *c;
	TkCitem *it;
	TkCwind *w;
	char v1[Tkminitem], v2[Tkminitem];
	int i;

	if(tk == nil)
		return;
	c = TKobj(TkCanvas, tk);
	tkfprint(v1, c->width);
	tkfprint(v2, c->height);
	print("%q configure -width %s -height %s", tkname(tk), v1, v2);
	print(" # focus %#p mouse %#p grab %#p\n", c->focus, c->mouse, c->grab);
	for(it = c->head; it != nil; it = it->next){
		print("%q create %q", tkname(tk), tkcimethod[it->type].name);
		for(i = 0; i < it->p.npoint; i++){
			tkfprint(v1, it->p.parampt[i].x);
			tkfprint(v2, it->p.parampt[i].y);
			print(" %s %s", v1, v2);
		}
		if(it->type == TkCVwindow){
			w = TKobj(TkCwind, it);
			if(w->sub != nil)
				print(" -window %q", tkname(w->sub));
			print(" # item %#p id %d sub %#p focus [%#p %q]\n", it, it->id, w->sub, w->focus, tkname(w->focus));
		}else
			print("# item %#p id %d\n", it, it->id);
	}
}
