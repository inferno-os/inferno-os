#include <lib9.h>
#include <kernel.h>
#include "draw.h"
#include "tk.h"
#include "keyboard.h"

#define	O(t, e)		((long)(&((t*)0)->e))

typedef struct TkScale TkScale;
struct TkScale
{
	int	value;
	int	bigi;
	int	digits;
	int	digwidth;
	int	from;		/* Base of range */
	int	to;		/* Limit of range */
	int	len;		/* Length of groove */
	int	res;		/* Resolution */
	int	sv;		/* Show value */
	int	sl;		/* Slider length */
	int	sw;		/* Slider width div 2 */
	int	relief;
	int	tick;
	int	orient;
	char*	command;
	char*	label;
	int	pixmin;
	int	pixmax;
	int	pixpos;
	int	center;
	int	pix;
	int	base;
	int	flag;
	int	jump;
};

enum {
	Dragging = (1<<0),
	Autorepeat = (1<<1),
};

static
TkOption opts[] =
{
	"bigincrement",		OPTnnfrac,	O(TkScale, bigi),	nil,
	"digits",		OPTdist,	O(TkScale, digits),	nil,
	"from",			OPTfrac,	O(TkScale, from),	nil,
	"to",			OPTfrac,	O(TkScale, to),		nil,
	"length",		OPTdist,	O(TkScale, len),	nil,
	"resolution",		OPTnnfrac,	O(TkScale, res),	nil,
	"showrange",	OPTignore,	0,	nil,
	"showvalue",		OPTstab,	O(TkScale, sv),		tkbool,
	"jump",		OPTstab, O(TkScale, jump),	tkbool,
	"sliderlength",		OPTdist,	O(TkScale, sl),		nil,
	"sliderrelief",		OPTstab,	O(TkScale, relief),	tkrelief,
	"tickinterval",		OPTfrac,	O(TkScale, tick),	nil,
	"tick",		OPTfrac,	O(TkScale, tick),	nil,
	"label",		OPTtext,	O(TkScale, label),	nil,
	"command",		OPTtext,	O(TkScale, command),	nil,
	"orient",		OPTstab,	O(TkScale, orient),	tkorient,
	nil
};

static char trough1[] = "trough1";
static char trough2[] = "trough2";
static char slider[]  = "slider";

static
TkEbind b[] = 
{
	{TkMotion,		"%W tkScaleMotion %x %y"},
	{TkButton1P|TkMotion,	"%W tkScaleDrag %x %y"},
	{TkButton1P,		"%W tkScaleMotion %x %y; %W tkScaleBut1P %x %y"},
	{TkButton1P|TkDouble,	"%W tkScaleMotion %x %y; %W tkScaleBut1P %x %y"},
	{TkButton1R,		"%W tkScaleDrag %x %y; %W tkScaleBut1R; %W tkScaleMotion %x %y"},
	{TkKey,		"%W tkScaleKey 0x%K"},
};

enum
{
	Scalewidth	= 18,
	ScalePad	= 2,
	ScaleBW		= 1,
	ScaleSlider	= 16,
	ScaleLen	= 80,

};

static int
maximum(int a, int b)
{
	if (a > b)
		return a;
	return b;
}

void
tksizescale(Tk *tk)
{
	Point p;
	char buf[32];
	TkScale *tks;
	int fh, w, h, digits, digits2;

	tks = TKobj(TkScale, tk);

	digits = tks->digits;
	if(digits <= 0) {
		digits = tkfprint(buf, tks->from) - buf;
		digits2 = tkfprint(buf, tks->to) - buf;
		digits = maximum(digits, digits2);
		if (tks->res > 0) {
			digits2 = tkfprint(buf, tks->from + tks->res) - buf;
			digits = maximum(digits, digits2);
			digits2 = tkfprint(buf, tks->to - tks->res) - buf;
			digits = maximum(digits, digits2);
		}
	}

	digits *= tk->env->wzero;
	if(tks->sv != BoolT)
		digits = 0;

	tks->digwidth = digits;

	p = tkstringsize(tk, tks->label);
	if(tks->orient == Tkvertical) {
		h = tks->len + 2*ScaleBW + 2*ScalePad;
		w = Scalewidth + 2*ScalePad + 2*ScaleBW;
		if (p.x)
			w += p.x + ScalePad;
		if (tks->sv == BoolT)
			w += digits + ScalePad;
	} else {
		w = maximum(p.x, tks->len + ScaleBW + 2*ScalePad);
		h = Scalewidth + 2*ScalePad + 2*ScaleBW;
		fh = tk->env->font->height;
		if(tks->label != nil)
			h += fh + ScalePad;
		if(tks->sv == BoolT)
			h += fh + ScalePad;
	}
	w += 2*tk->highlightwidth;
	h += 2*tk->highlightwidth;
	if(!(tk->flag & Tksetwidth))
		tk->req.width = w;
	if(!(tk->flag & Tksetheight))
		tk->req.height = h;
}

static int
tkscalecheckvalue(Tk *tk)
{
	int v;
	TkScale *tks = TKobj(TkScale, tk);
	int limit = 1;

	v = tks->value;
	if (tks->res > 0)
		v = (v / tks->res) * tks->res;
	if (tks->to >= tks->from) {
		if (v < tks->from)
			v = tks->from;
		else if (v > tks->to)
			v = tks->to;
		else
			limit = 0;
	} else {
		if (v < tks->to)
			v = tks->to;
		else if (v > tks->from)
			v = tks->from;
		else
			limit = 0;
	}
	/*
	 *  it's possible for the value to end up as a non-whole
	 * multiple of resolution here, if the end points aren't
	 * themselves such a multiple. if so, tough - that's
	 * what you asked for! (it does mean that the endpoints
	 * are always accessible however, which could be a good thing).
	 */
	tks->value = v;
	return limit;
}

char*
tkscale(TkTop *t, char *arg, char **ret)
{
	Tk *tk;
	char *e;
	TkName *names;
	TkScale *tks;
	TkOptab tko[3];

	tk = tknewobj(t, TKscale, sizeof(Tk)+sizeof(TkScale));
	if(tk == nil)
		return TkNomem;

	tk->flag |= Tktakefocus;
	tks = TKobj(TkScale, tk);
	tks->res = TKI2F(1);
	tks->to = TKI2F(100);
	tks->len = ScaleLen;
	tks->orient = Tkvertical;
	tks->relief = TKraised;
	tks->sl = ScaleSlider;
	tks->sv = BoolT;
	tks->bigi = 0;

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tks;
	tko[1].optab = opts;
	tko[2].ptr = nil;

	names = nil;
	e = tkparse(t, arg, tko, &names);
	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}
	tksettransparent(tk, tkhasalpha(tk->env, TkCbackgnd));
	tkscalecheckvalue(tk);
	tksizescale(tk);
	if (tks->bigi == 0)
		tks->bigi = TKI2F(TKF2I(tks->to - tks->from) / 10);
	e = tkbindings(t, tk, b, nelem(b));

	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}

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
tkscalecget(Tk *tk, char *arg, char **val)
{
	TkOptab tko[3];
	TkScale *tks = TKobj(TkScale, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tks;
	tko[1].optab = opts;
	tko[2].ptr = nil;

	return tkgencget(tko, arg, val, tk->env->top);
}

void
tkfreescale(Tk *tk)
{
	TkScale *tks = TKobj(TkScale, tk);

	if(tks->command != nil)
		free(tks->command);
	if(tks->label != nil)
		free(tks->label);
}

static void
tkscalehoriz(Tk *tk, Image *i)
{
	TkEnv *e;
	char sv[32];
	TkScale *tks;
	Image *d, *l;
	Rectangle r, r2, sr;
	Point p, q;
	int fh, sh, gh, sl, v, w, h, len;
	int fgnd;

	e = tk->env;
	tks = TKobj(TkScale, tk);


	fh = e->font->height;
	fgnd = TkCforegnd;
	if (tk->flag & Tkdisabled)
		fgnd = TkCdisablefgnd;

	r = Rect(0, 0, tk->act.width, tk->act.height);
	r = rectaddpt(r, Pt(tk->borderwidth, tk->borderwidth));
	r = insetrect(r, tk->highlightwidth);
	r = insetrect(r, ScalePad);

	if(tks->label != nil) {
		string(i, r.min, tkgc(e, fgnd), ZP, e->font, tks->label);
		r.min.y += fh + ScalePad;
	}
	if(tks->sv == BoolT)
		r.min.y += fh + ScalePad;

	sr = insetrect(r, ScaleBW);
	w = Dx(sr);
	h = Dy(sr);
	sl = tks->sl + 2*ScaleBW;

	l = tkgc(e, TkCbackgndlght);
	d = tkgc(e, TkCbackgnddark);
	tkbevel(i, r.min, w, h, ScaleBW, d, l);

	tks->pixmin = sr.min.x;
	tks->pixmax = sr.max.x;

	sh = h - 2*ScaleBW;
	tks->sw = sh/2;

	w -= sl;
	if (w <= 0)
		w = 1;
	p.x = sr.min.x;
	p.y = sr.max.y;
	if(tks->tick > 0){
		int j, t, l;
		t = tks->tick;
		l = tks->to-tks->from;
		if (l < 0)
			l = -l;
		if (l == 0)
			l = 1;
		r2.min.y = p.y;
		r2.max.y = p.y + ScaleBW + ScalePad;
		for(j = 0; j <= l; j += t){
			r2.min.x = p.x+((vlong)j*w)/l+sl/2;
			r2.max.x = r2.min.x+1;
			draw(i, r2, tkgc(e, fgnd), nil, ZP);
		}
	}
	v = tks->value-tks->from;
	len = tks->to-tks->from;
	if (len != 0)
		p.x += ((vlong)v*w)/len;
	p.y = sr.min.y;
	q = p;
	q.x += tks->sl/2 + 1;
	if(ScaleBW > 1) {
		gh = sh;
		q.y++;
	} else
		gh = sh-1;
	if(tk->flag & Tkactivated) {
		r2.min = p;
		r2.max.x = p.x+sl;
		r2.max.y = sr.max.y;
		draw(i, r2, tkgc(e, TkCactivebgnd), nil, ZP);
	}
	switch(tks->relief) {
	case TKsunken:
		tkbevel(i, p, tks->sl, sh, ScaleBW, d, l);
		tkbevel(i, q, 0, gh, 1, l, d);
		break;
	case TKraised:
		tkbevel(i, p, tks->sl, sh, ScaleBW, l, d);
		tkbevel(i, q, 0, gh, 1, d, l);
		break;
	}
	tks->pixpos = p.x;
	tks->center = p.y + sh/2 + ScaleBW;

	if(tks->sv != BoolT)
		return;

	tkfprint(sv, tks->value);
	if(tks->digits > 0 && tks->digits < strlen(sv))
		sv[tks->digits] = '\0';

	w = stringwidth(e->font, sv);
	p.x = q.x;
	p.x -= w/2;
	p.y = r.min.y - fh - ScalePad;
	if(p.x < tks->pixmin)
		p.x = tks->pixmin;
	if(p.x+w > tks->pixmax)
		p.x = tks->pixmax - w;
	
	string(i, p, tkgc(e, fgnd), ZP, e->font, sv);
}

static void
tkscalevert(Tk *tk, Image *i)
{
	TkEnv *e;
	TkScale *tks;
	char sv[32];
	Image *d, *l;
	Rectangle r, r2, sr;
	Point p, q;
	int fh, v, sw, gw, w, h, len, sl;
	int fgnd;

	e = tk->env;
	tks = TKobj(TkScale, tk);

	fh = e->font->height;
	fgnd = TkCforegnd;
	if (tk->flag & Tkdisabled)
		fgnd = TkCdisablefgnd;

	r = Rect(0, 0, tk->act.width, tk->act.height);
	r = rectaddpt(r, Pt(tk->borderwidth, tk->borderwidth));
	r = insetrect(r, tk->highlightwidth);
	r = insetrect(r, ScalePad);

	if (tks->sv)
		r.min.x += tks->digwidth + ScalePad;

	if(tks->label != nil) {
		p =  stringsize(e->font, tks->label);
		r.max.x -= p.x;
		string(i, Pt(r.max.x, r.min.y), tkgc(e, fgnd), ZP, e->font, tks->label);
		r.max.x -= ScalePad;
	}

	sr = insetrect(r, ScaleBW);
	h = Dy(sr);
	w = Dx(sr);
	sl = tks->sl + 2*ScaleBW;

	l = tkgc(e, TkCbackgndlght);
	d = tkgc(e, TkCbackgnddark);
	tkbevel(i, r.min, w, h, ScaleBW, d, l);

	tks->pixmin = sr.min.y;
	tks->pixmax = sr.max.y;

	sw = w - 2*ScaleBW;
	tks->sw = sw/2;

	h -= sl;
	if (h <= 0)
		h = 1;
	p.x = sr.max.x;
	p.y = sr.min.y;
	if(tks->tick > 0){
		int j, t, l;
		t = tks->tick;
		l = tks->to-tks->from;
		if (l < 0)
			l = -l;
		if (l == 0)
			l = 1;
		r2.min = p;
		r2.max.x = p.x + ScaleBW + ScalePad;
		for(j = 0; j <= l; j += t){
			r2.min.y = p.y+((vlong)j*h)/l+sl/2;
			r2.max.y = r2.min.y+1;
			draw(i, r2, tkgc(e, fgnd), nil, ZP);
		}
	}

	v = tks->value-tks->from;
	len  = tks->to-tks->from;
	if (len != 0)
		p.y += ((vlong)v*h)/len;
	p.x = sr.min.x;
	q = p;
	if(ScaleBW > 1) {
		q.x++;
		gw = sw;
	} else
		gw = sw-1;
	q.y += tks->sl/2 + 1;
	if(tk->flag & Tkactivated) {
		r2.min = p;
		r2.max.x = sr.max.x;
		r2.max.y = p.y+sl;
		draw(i, r2, tkgc(e, TkCactivebgnd), nil, ZP);
	}
	switch(tks->relief) {
	case TKsunken:
		tkbevel(i, p, sw, tks->sl, ScaleBW, d, l);
		tkbevel(i, q, gw, 0, 1, l, d);
		break;
	case TKraised:
		tkbevel(i, p, sw, tks->sl, ScaleBW, l, d);
		tkbevel(i, q, gw, 0, 1, d, l);
		break;
	}
	tks->pixpos = p.y;
	tks->center = p.x + sw/2 + ScaleBW;

	if(tks->sv != BoolT)
		return;

	tkfprint(sv, tks->value);
	if(tks->digits > 0 && tks->digits < strlen(sv))
		sv[tks->digits] = '\0';

	p.x = r.min.x - ScalePad - stringwidth(e->font, sv);
	p.y = q.y;
	p.y -= fh/2;
	if (p.y < tks->pixmin)
		p.y = tks->pixmin;
	if (p.y + fh > tks->pixmax)
		p.y = tks->pixmax - fh;
	string(i, p, tkgc(e, fgnd), ZP, e->font, sv);
}

char*
tkdrawscale(Tk *tk, Point orig)
{
	Point p;
	TkEnv *env;
	TkScale *tks;
	Rectangle r, fr;
	Image *i;

	tks = TKobj(TkScale, tk);
	env = tk->env;

	r.min = ZP;
	r.max.x = tk->act.width + 2*tk->borderwidth;
	r.max.y = tk->act.height + 2*tk->borderwidth;
	i = tkitmp(env, r.max, TkCbackgnd);
	if(i == nil)
		return nil;

	if(tks->orient == Tkvertical)
		tkscalevert(tk, i);
	else
		tkscalehoriz(tk, i);

	tkdrawrelief(i, tk, ZP, TkCbackgnd, tk->relief);
	if (tkhaskeyfocus(tk)) {
		fr = insetrect(r, tk->borderwidth);
		tkbox(i, fr, tk->highlightwidth, tkgc(env, TkChighlightfgnd));
	}

	p.x = tk->act.x + orig.x;
	p.y = tk->act.y + orig.y;
	r = rectaddpt(r, p);
	draw(tkimageof(tk), r, i, nil, ZP);

	return nil;
}

/* Widget Commands (+ means implemented)
	+cget
	+configure
	+coords
	+get
	+identify
	+set
*/

static char*
tkscaleconf(Tk *tk, char *arg, char **val)
{
	char *e;
	TkGeom g;
	int bd;
	TkOptab tko[3];
	TkScale *tks = TKobj(TkScale, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tks;
	tko[1].optab = opts;
	tko[2].ptr = nil;

	if(*arg == '\0')
		return tkconflist(tko, val);

	g = tk->req;
	bd = tk->borderwidth;
	e = tkparse(tk->env->top, arg, tko, nil);
	tksettransparent(tk, tkhasalpha(tk->env, TkCbackgnd));
	tkscalecheckvalue(tk);
	tksizescale(tk);
	tkgeomchg(tk, &g, bd);

	tk->dirty = tkrect(tk, 1);
	return e;
}

char*
tkscaleposn(TkEnv *env, Tk *tk, char *arg, int *z)
{
	int x, y;
	TkScale *tks = TKobj(TkScale, tk);
	char *e;

	e = tkfracword(env->top, &arg, &x, env);
	if(e != nil)
		return e;
	e = tkfracword(env->top, &arg, &y, env);
	if(e != nil)
		return e;

	x = TKF2I(x) + tk->borderwidth;
	y = TKF2I(y) + tk->borderwidth;

	if(tks->orient == Tkvertical) {
		if(z != nil) {
			z[0] = x;
			z[1] = y;
		}
		x = y;
	}
	else {
		if(z != nil) {
			z[0] = y;
			z[1] = x;
		}
	}
	if(x > tks->pixmin && x < tks->pixpos)
		return trough1;
	else if(x >= tks->pixpos && x < tks->pixpos+tks->sl+2*ScaleBW)
		return slider;
	else if(x >= tks->pixpos+tks->sl+2*ScaleBW && x < tks->pixmax)
		return trough2;

	return "";
}

static char*
tkscaleident(Tk *tk, char *arg, char **val)
{
	char *v;

	v = tkscaleposn(tk->env, tk, arg, nil);
	if(v == nil)
		return TkBadvl;
	return tkvalue(val, "%s", v);
}

static char*
tkscalecoords(Tk *tk, char *arg, char **val)
{
	int p, x, y, l, value;
	TkScale *tks = TKobj(TkScale, tk);
	char *e;

	value = tks->value;
	if(arg != nil && arg[0] != '\0') {
		e = tkfracword(tk->env->top, &arg, &value, tk->env);
		if (e != nil)
			return e;
	}

	value -= tks->from;
	p = tks->pixmax - tks->pixmin;
	l = TKF2I(tks->to-tks->from);
	if (l==0)
		p /= 2;
	else
		p = TKF2I(value*p/l);
	p += tks->pixmin;
	if(tks->orient == Tkvertical) {
		x = tks->center;
		y = p;
	}
	else {
		x = p;
		y = tks->center;
	}
	return tkvalue(val, "%d %d", x, y);
}

static char*
tkscaleget(Tk *tk, char *arg, char **val)
{
	int x, y, value, v, l;
	char buf[Tkminitem], *e;
	TkScale *tks = TKobj(TkScale, tk);

	value = tks->value;
	if(arg[0] != '\0') {
		e = tkfracword(tk->env->top, &arg, &x, tk->env);
		if (e != nil)
			return e;
		e = tkfracword(tk->env->top, &arg, &y, tk->env);
		if (e != nil)
			return e;
		if(tks->orient == Tkvertical)
			v = TKF2I(y) + tk->borderwidth;
		else
			v = TKF2I(x) + tk->borderwidth;

		if(v < tks->pixmin)
			value = tks->from;
		else
		if(v > tks->pixmax)
			value = tks->to;
		else {
			l = tks->pixmax-tks->pixmin;
			value = 0;
			if (l!=0)
				value = v * ((tks->to-tks->from)/l);
			value += tks->from;
		}
		if(tks->res > 0)
			value = (value/tks->res)*tks->res;
	}
	tkfprint(buf, value);
	return tkvalue(val, "%s", buf);
}

static char*
tkscaleset(Tk *tk, char *arg, char **val)
{
	TkScale *tks = TKobj(TkScale, tk);
	char *e;

	USED(val);

	e = tkfracword(tk->env->top, &arg, &tks->value, tk->env);
	if (e != nil)
		return e;
	tkscalecheckvalue(tk);
	tk->dirty = tkrect(tk, 1);
	return nil;		
}

/* tkScaleMotion %x %y */
static char*
tkscalemotion(Tk *tk, char *arg, char **val)
{
	int o, z[2];
	char *v;
	TkScale *tks = TKobj(TkScale, tk);
	extern int tkstylus;

	USED(val);
	v = tkscaleposn(tk->env, tk, arg, z);
	if(v == nil)
		return TkBadvl;

	o = tk->flag;
	if(v != slider || z[0] < tks->center-tks->sw || z[0] > tks->center+tks->sw)
		tk->flag &= ~Tkactivated;
	else if(tkstylus == 0 || tk->env->top->ctxt->mstate.b != 0)
		tk->flag |= Tkactivated;

	if((o & Tkactivated) != (tk->flag & Tkactivated))
		tk->dirty = tkrect(tk, 1);

	return nil;
}

static char*
tkscaledrag(Tk *tk, char *arg, char **val)
{
	int x, y, v;
	char *e, buf[Tkmaxitem], f[32];
	TkScale *tks = TKobj(TkScale, tk);

	USED(val);
	if((tks->flag & Dragging) == 0)
		return nil;
	if(tks->flag & Autorepeat)
		return nil;

	e = tkfracword(tk->env->top, &arg, &x, tk->env);
	if(e != nil)
		return e;
	e = tkfracword(tk->env->top, &arg, &y, tk->env);
	if(e != nil)
		return e;

	if(tks->orient == Tkvertical)
		v = TKF2I(y) + tk->borderwidth;
	else
		v = TKF2I(x) + tk->borderwidth;

	v -= tks->pix;
	x = tks->pixmax-tks->pixmin;
	if (x!=tks->sl)
		v = tks->base + (vlong)v * (tks->to-tks->from)/(x-tks->sl);
	else
		v = tks->base;
	if(tks->res > 0) {
		int a = tks->res / 2;
		if (v < 0)
			a = -a;
		v = ((v+a)/tks->res)*tks->res;
	}

	tks->value = v;
	tkscalecheckvalue(tk);

	if(tks->command != nil && tks->jump != BoolT) {
		tkfprint(f, tks->value);
		snprint(buf, sizeof(buf), "%s %s", tks->command, f);
		e = tkexec(tk->env->top, buf, nil);
	}
	tk->dirty = tkrect(tk, 1);
	return e;
}

static int
sgn(int v)
{
	return v >= 0 ? 1 : -1;
}

static char*
stepscale(Tk *tk, char *pos, int *end)
{
	TkScale *tks = TKobj(TkScale, tk);
	char *e, buf[Tkmaxitem], f[32];
	int s;

	s = sgn(tks->to - tks->from);
	if(pos == trough1) {
		tks->value -= s * tks->bigi;
	} else {
		/* trough2 */
		tks->value += s * tks->bigi;
	}
	s = !tkscalecheckvalue(tk);
	if (end != nil)
		*end = s;
	e = nil;
	if(tks->command != nil) {
		/* XXX perhaps should only send command if value has actually changed */
		tkfprint(f, tks->value);
		snprint(buf, sizeof(buf), "%s %s", tks->command, f);
		e = tkexec(tk->env->top, buf, nil);
	}
	return e;
}

static void
screpeat(Tk *tk, void *v, int cancelled)
{
	char *e, *pos;
	int repeat;
	TkScale *tks = TKobj(TkScale, tk);

	pos = v;
	if (cancelled) {
		tks->flag &= ~Autorepeat;
		return;
	}
	e = stepscale(tk, pos, &repeat);
	if(e != nil || !repeat) {
		tks->flag &= ~Autorepeat;
		tkcancelrepeat(tk);
	}
	tk->dirty = tkrect(tk, 1);
	tkupdate(tk->env->top);
}

static char*
tkscalebut1p(Tk *tk, char *arg, char **val)
{
	int z[2];
	char *v, *e;
	TkScale *tks = TKobj(TkScale, tk);
	int repeat;

	USED(val);
	v = tkscaleposn(tk->env, tk, arg, z);
	if(v == nil)
		return TkBadvl;

	e = nil;
	if(v[0] == '\0' || z[0] < tks->center-tks->sw || z[0] > tks->center+tks->sw)
		return nil;
	if(v == slider) {
		tks->flag |= Dragging;
		tks->relief = TKsunken;
		tks->pix = z[1];
		tks->base = tks->value;
		tkscalecheckvalue(tk);
	} else  {
		e = stepscale(tk, v, &repeat);
		if (e == nil && repeat) {
			tks->flag |= Autorepeat;
			tkrepeat(tk, screpeat, v, TkRptpause, TkRptinterval);
		}
	}

	tk->dirty = tkrect(tk, 1);
	return e;
}

static char*
tkscalebut1r(Tk *tk, char *arg, char **val)
{
	TkScale *tks = TKobj(TkScale, tk);
	char *e, buf[Tkmaxitem], f[32];
	USED(val);
	USED(arg);
	if(tks->flag & Autorepeat) {
		tkcancelrepeat(tk);
		tks->flag &= ~Autorepeat;
	}
	e = nil;
	if (tks->flag & Dragging) {
		if (tks->command != nil && tks->jump == BoolT && (tks->flag & Dragging)) {
			tkfprint(f, tks->value);
			snprint(buf, sizeof(buf), "%s %s", tks->command, f);
			e = tkexec(tk->env->top, buf, nil);
		}
		tks->relief = TKraised;
		tks->flag &= ~Dragging;
		tk->dirty = tkrect(tk, 1);
	}
	return e;
}

static char*
tkscalekey(Tk *tk, char *arg, char **val)
{
	char *e;
	int key;
	char *pos = nil;
	USED(arg);
	USED(val);

	if(tk->flag & Tkdisabled)
		return nil;

	key = strtol(arg, nil, 0);
	if (key == Up || key == Left)
		pos = trough1;
	else if (key == Down || key == Right)
		pos = trough2;
	if (pos != nil) {
		e = stepscale(tk, pos, nil);
		tk->dirty = tkrect(tk, 1);
		return e;
	}
	return nil;
}

TkCmdtab tkscalecmd[] =
{
	"cget",			tkscalecget,
	"configure",		tkscaleconf,
	"set",			tkscaleset,
	"identify",		tkscaleident,
	"get",			tkscaleget,
	"coords",		tkscalecoords,
	"tkScaleMotion",	tkscalemotion,
	"tkScaleDrag",		tkscaledrag,
	"tkScaleBut1P",		tkscalebut1p,
	"tkScaleBut1R",		tkscalebut1r,
	"tkScaleKey",		tkscalekey,
	nil
};

TkMethod scalemethod = {
	"scale",
	tkscalecmd,
	tkfreescale,
	tkdrawscale
};
