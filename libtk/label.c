#include <lib9.h>
#include <kernel.h>
#include "draw.h"
#include "tk.h"
#include "label.h"

#define	O(t, e)		((long)(&((t*)0)->e))

TkOption tklabelopts[] =
{
	"text",		OPTtext,	O(TkLabel, text),	nil,
	"label",	OPTtext,	O(TkLabel, text),	nil,
	"underline",	OPTdist,	O(TkLabel, ul),		nil,
	"justify",	OPTflag,	O(TkLabel, justify),	tkjustify,
	"anchor",	OPTflag,	O(TkLabel, anchor),	tkanchor,
	"bitmap",	OPTbmap,	O(TkLabel, bitmap),	nil,
	"image",	OPTimag,	O(TkLabel, img),	nil,
	nil
};

char*
tklabel(TkTop *t, char *arg, char **ret)
{
	Tk *tk;
	char *e;
	TkLabel *tkl;
	TkName *names;
	TkOptab tko[3];

	tk = tknewobj(t, TKlabel, sizeof(Tk)+sizeof(TkLabel));
	if(tk == nil)
		return TkNomem;

	tkl = TKobj(TkLabel, tk);
	tkl->ul = -1;
	tkl->justify = Tkleft;

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkl;
	tko[1].optab = tklabelopts;
	tko[2].ptr = nil;

	names = nil;
	e = tkparse(t, arg, tko, &names);
	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}

	tksizelabel(tk);
	tksettransparent(tk, tkhasalpha(tk->env, TkCbackgnd));

	e = tkaddchild(t, tk, &names);
	tkfreename(names);
	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}
	tk->name->link = nil;

	return tkvalue(ret, "%s", tk->name->name);
}

static char*
tklabelcget(Tk *tk, char *arg, char **val)
{
	TkOptab tko[3];
	TkLabel *tkl = TKobj(TkLabel, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkl;
	tko[1].optab = tklabelopts;
	tko[2].ptr = nil;

	return tkgencget(tko, arg, val, tk->env->top);
}

static char*
tklabelconf(Tk *tk, char *arg, char **val)
{
	char *e;
	TkGeom g;
	int bd;
	TkOptab tko[3];
	TkLabel *tkl = TKobj(TkLabel, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkl;
	tko[1].optab = tklabelopts;
	tko[2].ptr = nil;

	if(*arg == '\0')
		return tkconflist(tko, val);

	g = tk->req;
	bd = tk->borderwidth;
	e = tkparse(tk->env->top, arg, tko, nil);
	tksizelabel(tk);
	tksettransparent(tk, tkhasalpha(tk->env, TkCbackgnd));
	tkgeomchg(tk, &g, bd);

	tk->dirty = tkrect(tk, 1);
	return e;
}

void
tksizelabel(Tk *tk)
{
	Point p;
	int w, h;
	TkLabel *tkl;
	
	tkl = TKobj(TkLabel, tk);
	if(tkl->anchor == 0)	
		tkl->anchor = Tkcenter;

	w = 0;
	h = 0;
	tkl->textheight = 0;
	if(tkl->img != nil) {
		w = tkl->img->w + 2*Bitpadx;
		h = tkl->img->h + 2*Bitpady;
	} else if(tkl->bitmap != nil) {
		w = Dx(tkl->bitmap->r) + 2*Bitpadx;
		h = Dy(tkl->bitmap->r) + 2*Bitpady;
	} else if(tkl->text != nil) {
		p = tkstringsize(tk, tkl->text);
		w = p.x + 2*Textpadx;
		h = p.y + 2*Textpady;
		if(tkl->ul != -1 && tkl->ul > strlen(tkl->text))
			tkl->ul = strlen(tkl->text);	/* underline all */
		tkl->textheight = p.y;
	}

	if(tk->type == TKcascade) {
		w += CheckButton + 2*CheckButtonBW;
		if(h < CheckButton)
			h = CheckButton;
	}
	w += 2*tk->highlightwidth;
	h += 2*tk->highlightwidth;
	tkl->w = w;
	tkl->h = h;
	if((tk->flag & Tksetwidth) == 0)
		tk->req.width = w;
	if((tk->flag & Tksetheight) == 0)
		tk->req.height = h;
}

int
tklabelmargin(Tk *tk)
{
	TkLabel *tkl;
	Image *img;

	switch(tk->type){
	case TKseparator:
		return 0;

	case TKlabel:
	case TKcascade:
		tkl = TKobj(TkLabel, tk);
		img = nil;
		if (tkl->img != nil)
			img = tkl->img->img;
		else if (tkl->bitmap != nil)
			img = tkl->bitmap;
		if (img != nil)
			return Bitpadx;
		return Textpadx;

	default:
		fprint(2, "label margin: type %d\n", tk->type);
		return 0;
	}
}

void
tkfreelabel(Tk *tk)
{
	Image *i;
	int locked;
	Display *d;
	TkLabel *tkl;

	tkl = TKobj(TkLabel, tk);

	if(tkl->text != nil)
		free(tkl->text);
	if(tkl->command != nil)
		free(tkl->command);
	if(tkl->value != nil)
		free(tkl->value);
	if(tkl->variable != nil) {
		tkfreevar(tk->env->top, tkl->variable, tk->flag & Tkswept);
		free(tkl->variable);
	}
	if(tkl->img != nil)
		tkimgput(tkl->img);
	i = tkl->bitmap;
	if(i != nil) {
		d = i->display;
		locked = lockdisplay(d);
		freeimage(i);
		if(locked)
			unlockdisplay(d);
	}
	if(tkl->menu != nil)
		free(tkl->menu);
}

static void
tktriangle(Point u, Image *i, TkEnv *e)
{	
	Point p[3];

	u.y++;
	p[0].x = u.x + CheckButton;
	p[0].y = u.y + CheckButton/2;
	p[1].x = u.x;
	p[1].y = u.y + CheckButton;
	p[2].x = u.x;
	p[2].y = u.y;
	fillpoly(i, p, 3, ~0, tkgc(e, TkCforegnd), p[0]);
}

/*
 * draw TKlabel, TKseparator, and TKcascade (cascade should really be a button)
 */
char*
tkdrawlabel(Tk *tk, Point orig)
{
 	TkEnv *e;
	TkLabel *tkl;
	Rectangle r, s, mainr, focusr;
	int dx, dy, h;
	Point p, u, v;
	Image *i, *dst, *ct, *img;
	char *o;
	int relief, bgnd, fgnd;

	e = tk->env;

	dst = tkimageof(tk);
	if(dst == nil)
		return nil;

	v.x = tk->act.width + 2*tk->borderwidth;
	v.y = tk->act.height + 2*tk->borderwidth;

	r.min = ZP;
	r.max = v;
	focusr = insetrect(r, tk->borderwidth);
	mainr = insetrect(focusr, tk->highlightwidth);
	relief = tk->relief;

	tkl = TKobj(TkLabel, tk);

	fgnd = TkCforegnd;
	bgnd = TkCbackgnd;
	if (tk->flag & Tkdisabled)
		fgnd = TkCdisablefgnd;
	else if (tk->flag & Tkactive) {
		fgnd = TkCactivefgnd;
		bgnd = TkCactivebgnd;
	}

	i = tkitmp(e, r.max, bgnd);
	if(i == nil)
		return nil;

	if(tk->flag & Tkactive)
		draw(i, r, tkgc(e, bgnd), nil, ZP);

	p = mainr.min;
	h = tkl->h - 2 * tk->highlightwidth;

	dx = tk->act.width - tkl->w - tk->ipad.x;
	dy = tk->act.height - tkl->h - tk->ipad.y;
	if((tkl->anchor & (Tknorth|Tksouth)) == 0)
		p.y += dy/2;
	else if(tkl->anchor & Tksouth)
		p.y += dy;

	if((tkl->anchor & (Tkeast|Tkwest)) == 0)
		p.x += dx/2;
	else if(tkl->anchor & Tkeast)
		p.x += dx;

	if(tk->type == TKcascade) {
		u.x = mainr.max.x - CheckButton - CheckButtonBW;	/* TO DO: CheckButton etc is really the triangle/arrow */
		u.y = p.y + ButtonBorder + (h-CheckSpace)/2;
		tktriangle(u, i, e);
	}

	p.x += tk->ipad.x/2;
	p.y += tk->ipad.y/2;
	u = ZP;

	img = nil;
	if(tkl->img != nil && tkl->img->img != nil)
		img = tkl->img->img;
	else if (tkl->bitmap != nil)
		img = tkl->bitmap;
	if(img != nil) {
		s.min.x = p.x + Bitpadx;
		s.min.y = p.y + Bitpady;
		s.max.x = s.min.x + Dx(img->r);
		s.max.y = s.min.y + Dy(img->r);
		s = rectaddpt(s, u);
		if(tkchanhastype(img->chan, CGrey))
			draw(i, s, tkgc(e, fgnd), img, ZP);
		else
			draw(i, s, img, nil, ZP);
	} else if(tkl->text != nil) {
		u.x += Textpadx;
		u.y += Textpady;
		ct = tkgc(e, fgnd);
		
		p.y += (h - tkl->textheight) / 2;
		o = tkdrawstring(tk, i, addpt(u, p), tkl->text, tkl->ul, ct, tkl->justify);
		if(o != nil)
			return o;
	}

	if(tkhaskeyfocus(tk))
		tkbox(i, focusr, tk->highlightwidth, tkgc(e, TkChighlightfgnd));
	tkdrawrelief(i, tk, ZP, bgnd, relief);

	p.x = tk->act.x + orig.x;
	p.y = tk->act.y + orig.y;
	r = rectaddpt(r, p);
	draw(dst, r, i, nil, ZP);

	return nil;
}

void
tklabelgetimgs(Tk *tk, Image **image, Image **mask)
{
	TkLabel *tkl;

	tkl = TKobj(TkLabel, tk);
	*mask = nil;
	if (tkl->img != nil)
		*image = tkl->img->img;
	else
		*image = tkl->bitmap;
}

static
TkCmdtab tklabelcmd[] =
{
	"cget",			tklabelcget,
	"configure",		tklabelconf,
	nil
};

TkMethod labelmethod = {
	"label",
	tklabelcmd,
	tkfreelabel,
	tkdrawlabel,
	nil,
	tklabelgetimgs
};
