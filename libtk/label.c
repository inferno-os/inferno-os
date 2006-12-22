#include <lib9.h>
#include <kernel.h>
#include "draw.h"
#include "tk.h"
#include "label.h"

#define	O(t, e)		((long)(&((t*)0)->e))

/* Layout constants */
enum {
	CheckSpace = CheckButton + 2*CheckButtonBW + 2*ButtonBorder,
};

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
	}
	else
	if(tkl->bitmap != nil) {
		w = Dx(tkl->bitmap->r) + 2*Bitpadx;
		h = Dy(tkl->bitmap->r) + 2*Bitpady;
	}
	else 
	if(tkl->text != nil) {
		p = tkstringsize(tk, tkl->text);
		w = p.x + 2*Textpadx;
		h = p.y + 2*Textpady;
		if(tkl->ul != -1 && tkl->ul > strlen(tkl->text))
			tkl->ul = -1;
		tkl->textheight = p.y;
	}

	if((tk->type == TKcheckbutton || tk->type == TKradiobutton) && tkl->indicator != BoolF) {
		w += CheckSpace;
		if(h < CheckSpace)
			h = CheckSpace;
	} else if(tk->type == TKcascade) {
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

	if (tk->type == TKseparator)
		return 0;
	if (tk->type == TKlabel || tk->type == TKcascade) {
		tkl = TKobj(TkLabel, tk);
		img = nil;
		if (tkl->img != nil)
			img = tkl->img->img;
		else if (tkl->bitmap != nil)
			img = tkl->bitmap;
		if (img != nil)
			return Bitpadx;
		return Textpadx;
	}
	return tkbuttonmargin(tk);
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
	int j;
	Point p[3];

	u.y++;
	p[0].x = u.x + CheckButton;
	p[0].y = u.y + CheckButton/2;
	p[1].x = u.x;
	p[1].y = u.y + CheckButton;
	p[2].x = u.x;
	p[2].y = u.y;
	fillpoly(i, p, 3, ~0, tkgc(e, TkCbackgnddark), p[0]);
	for(j = 0; j < 3; j++)
		p[j].y -= 2;
	
	fillpoly(i, p, 3, ~0, tkgc(e, TkCbackgndlght), p[0]);
}

/*
 * draw TKlabel, TKcheckbutton, TKradiobutton
 */
char*
tkdrawlabel(Tk *tk, Point orig)
{
 	TkEnv *e;
	TkLabel *tkl;
	Rectangle r, s, mainr, focusr;
	int dx, dy, h;
	Point p, u, v, *pp;
	Image *i, *dst, *cd, *cl, *ct, *img;
	char *o;
	int relief, bgnd, fgnd;

	e = tk->env;

	dst = tkimageof(tk);
	if(dst == nil)
		return nil;

	v.x = tk->act.width + 2*tk->borderwidth;
	v.y = tk->act.height + 2*tk->borderwidth;

	r.min = ZP;
	r.max.x = v.x;
	r.max.y = v.y;
	focusr = insetrect(r, tk->borderwidth);
	mainr = insetrect(focusr, tk->highlightwidth);
	relief = tk->relief;

	tkl = TKobj(TkLabel, tk);

	fgnd = TkCforegnd;
	bgnd = TkCbackgnd;
	if (tk->flag & Tkdisabled)
		fgnd = TkCdisablefgnd;
	else if ((tk->type == TKcheckbutton || tk->type == TKradiobutton) && tkl->indicator == BoolF && tkl->check)
		bgnd = TkCselect;
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
	else
	if(tkl->anchor & Tksouth)
		p.y += dy;

	if((tkl->anchor & (Tkeast|Tkwest)) == 0)
		p.x += dx/2;
	else
	if(tkl->anchor & Tkeast)
		p.x += dx;

	switch(tk->type) {
	case TKcheckbutton:
		if (tkl->indicator == BoolF) {
			relief = tkl->check?TKsunken:TKraised;
			break;
		}
		u.x = p.x + ButtonBorder;
		u.y = p.y + ButtonBorder + (h - CheckSpace) / 2;

		cl = tkgc(e, bgnd+TkLightshade);
		cd = tkgc(e, bgnd+TkDarkshade);
		if(tkl->check) {
			tkbevel(i, u, CheckButton, CheckButton, CheckButtonBW, cd, cl);
			u.x += CheckButtonBW;
			u.y += CheckButtonBW;
			s.min = u;
			s.max.x = u.x + CheckButton;
			s.max.y = u.y + CheckButton;
			draw(i, s, tkgc(e, TkCselect), nil, ZP);
		}
		else
			tkbevel(i, u, CheckButton, CheckButton, CheckButtonBW, cl, cd);
		break;
	case TKradiobutton:
		if (tkl->indicator == BoolF) {
			relief = tkl->check?TKsunken:TKraised;
			break;
		}
		u.x = p.x + ButtonBorder;
		u.y = p.y + ButtonBorder + (h - CheckSpace) / 2;
		pp = mallocz(4*sizeof(Point), 0);
		if(pp == nil)
			return TkNomem;
		pp[0].x = u.x + CheckButton/2;
		pp[0].y = u.y;
		pp[1].x = u.x + CheckButton;
		pp[1].y = u.y + CheckButton/2;
		pp[2].x = pp[0].x;
		pp[2].y = u.y + CheckButton;
		pp[3].x = u.x;
		pp[3].y = pp[1].y;
		cl = tkgc(e, bgnd+TkLightshade);
		cd = tkgc(e, bgnd+TkDarkshade);
		if(tkl->check)
			fillpoly(i, pp, 4, ~0, tkgc(e, TkCselect), pp[0]);
		else {
			ct = cl;
			cl = cd;
			cd = ct;
		}
		line(i, pp[0], pp[1], 0, Enddisc, CheckButtonBW/2, cd, pp[0]);
		line(i, pp[1], pp[2], 0, Enddisc, CheckButtonBW/2, cl, pp[1]);
		line(i, pp[2], pp[3], 0, Enddisc, CheckButtonBW/2, cl, pp[2]);
		line(i, pp[3], pp[0], 0, Enddisc, CheckButtonBW/2, cd, pp[3]);
		free(pp);
		break;
	case TKcascade:
		u.x = mainr.max.x - CheckButton - CheckButtonBW;
		u.y = p.y + ButtonBorder + (h-CheckSpace)/2;
		tktriangle(u, i, e);
		break;
	case TKbutton:
		if ((tk->flag & (Tkactivated|Tkactive)) == (Tkactivated|Tkactive))
			relief = TKsunken;
		break;
	}

	p.x += tk->ipad.x/2;
	p.y += tk->ipad.y/2;
	u = ZP;
	if(tk->type == TKbutton && relief == TKsunken) {
		u.x++;
		u.y++;
	}
	if((tk->type == TKcheckbutton || tk->type == TKradiobutton) && tkl->indicator != BoolF)
		u.x += CheckSpace;

	img = nil;
	if (tkl->img != nil && tkl->img->img != nil)
		img = tkl->img->img;
	else if (tkl->bitmap != nil)
		img = tkl->bitmap;
	if (img != nil) {
		s.min.x = p.x + Bitpadx;
		s.min.y = p.y + Bitpady;
		s.max.x = s.min.x + Dx(img->r);
		s.max.y = s.min.y + Dy(img->r);
		s = rectaddpt(s, u);
		if (tkchanhastype(img->chan, CGrey))
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

	if (tkhaskeyfocus(tk))
		tkbox(i, focusr, tk->highlightwidth, tkgc(e, TkChighlightfgnd));
	tkdrawrelief(i, tk, ZP, bgnd, relief);

	p.x = tk->act.x + orig.x;
	p.y = tk->act.y + orig.y;
	r = rectaddpt(r, p);
	draw(dst, r, i, nil, ZP);

	return nil;
}

char*
tksetvar(TkTop *top, char *c, char *newval)
{
	TkVar *v;
	TkWin *tkw;
	Tk *f, *m;
	void (*vc)(Tk*, char*, char*);

	if (c == nil || c[0] == '\0')
		return nil;

	v = tkmkvar(top, c, TkVstring);
	if(v == nil)
		return TkNomem;
	if(v->type != TkVstring)
		return TkNotvt;

	if(newval == nil)
		newval = "";

	if(v->value != nil) {
		if (strcmp(v->value, newval) == 0)
			return nil;
		free(v->value);
	}

	v->value = strdup(newval);
	if(v->value == nil)
		return TkNomem;

	for(f = top->root; f; f = f->siblings) {
		if(f->type == TKmenu) {
			tkw = TKobj(TkWin, f);
			for(m = tkw->slave; m; m = m->next)
				if ((vc = tkmethod[m->type]->varchanged) != nil)
					(*vc)(m, c, newval);
		} else
			if ((vc = tkmethod[f->type]->varchanged) != nil)
				(*vc)(f, c, newval);
	}

	return nil;
}

char*
tkvariable(TkTop *t, char *arg, char **ret)
{
	TkVar *v;
	char *fmt, *e, *buf, *ebuf, *val;
	int l;

	l = strlen(arg) + 2;
	buf = malloc(l);
	if(buf == nil)
		return TkNomem;
	ebuf = buf+l;

	arg = tkword(t, arg, buf, ebuf, nil);
	arg = tkskip(arg, " \t");
	if (*arg == '\0') {
		if(strcmp(buf, "lasterror") == 0) {
			free(buf);
			if(t->err == nil)
				return nil;
			fmt = "%s: %s";
			if(strlen(t->errcmd) == sizeof(t->errcmd)-1)
				fmt = "%s...: %s";
			e = tkvalue(ret, fmt, t->errcmd, t->err);
			t->err = nil;
			return e;
		}
		v = tkmkvar(t, buf, 0);
		free(buf);
		if(v == nil || v->value == nil)
			return nil;
		if(v->type != TkVstring)
			return TkNotvt;
		return tkvalue(ret, "%s", v->value);
	}
	val = buf+strlen(buf)+1;
	tkword(t, arg, val, ebuf, nil);
	e = tksetvar(t, buf, val);
	free(buf);
	return e;
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
