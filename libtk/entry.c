#include <lib9.h>
#include <kernel.h>
#include "draw.h"
#include "keyboard.h"
#include "tk.h"

/* Widget Commands (+ means implemented)
	+bbox
	+cget
	+configure
	+delete
	+get
	+icursor
	+index
	 scan
	+selection
	+xview
	+see
*/

#define	O(t, e)		((long)(&((t*)0)->e))

#define CNTL(c) ((c)&0x1f)
#define DEL 0x7f

/* Layout constants */
enum {
	Entrypady	= 0,
	Entrypadx	= 0,
	Inswidth = 2,

	Ecursoron = 1<<0,
	Ecenter = 1<<1,
	Eright = 1<<2,
	Eleft = 1<<3,
	Ewordsel = 1<<4,

	Ejustify = Ecenter|Eleft|Eright
};

static TkStab tkjust[] =
{
	"left",	Eleft,
	"right",	Eright,
	"center",	Ecenter,
	nil
};

static
TkEbind b[] = 
{
	{TkKey,			"%W delete sel.first sel.last; %W insert insert {%A};%W see insert"},
	{TkKey|CNTL('a'),	"%W icursor 0;%W see insert;%W selection clear"},
	{TkKey|Home,		"%W icursor 0;%W see insert;%W selection clear"},
	{TkKey|CNTL('d'),	"%W delete insert; %W see insert"},
	{TkKey|CNTL('e'),    "%W icursor end; %W see insert;%W selection clear"},
	{TkKey|End,	     "%W icursor end; %W see insert;%W selection clear"},
	{TkKey|CNTL('h'),	"%W tkEntryBS;%W see insert"},
	{TkKey|CNTL('k'),	"%W delete insert end;%W see insert"},
	{TkKey|CNTL('u'),	"%W delete 0 end;%W see insert"},
	{TkKey|CNTL('w'),	"%W delete sel.first sel.last; %W tkEntryBW;%W see insert"},
	{TkKey|DEL,		"%W tkEntryBS 1;%W see insert"},
	{TkKey|CNTL('\\'),	"%W selection clear"},
	{TkKey|CNTL('/'),	"%W selection range 0 end"},
	{TkKey|Left,	"%W icursor insert-1;%W selection clear;%W selection from insert;%W see insert"},
	{TkKey|Right,	"%W icursor insert+1;%W selection clear;%W selection from insert;%W see insert"},
	{TkButton1P,		"focus %W; %W tkEntryB1P %X"},
	{TkButton1P|TkMotion, 	"%W tkEntryB1M %X"},
	{TkButton1R,		"%W tkEntryB1R"},
	{TkButton1P|TkDouble,	"%W tkEntryB1P %X;%W selection word @%x"},
	{TkButton2P,			"%W tkEntryB2P %x"},
	{TkButton2P|TkMotion,	"%W xview scroll %x scr"},
	{TkFocusin,		"%W tkEntryFocus in"},
	{TkFocusout,		"%W tkEntryFocus out"},
	{TkKey|APP|'\t',	""},
	{TkKey|BackTab,		""},
};

typedef struct TkEntry TkEntry;
struct TkEntry
{
	Rune*	text;
	int		textlen;

	char*	xscroll;
	char*	show;
	int		flag;
	int		oldx;

	int		icursor;		/* index of insertion cursor */
	int		anchor;		/* selection anchor point */
	int		sel0;			/* index of start of selection */
	int		sel1;			/* index of end of selection */

	int		x0;			/* x-offset of visible area */

	/* derived values */
	int		v0;			/* index of first visible character */
	int		v1;			/* index of last visible character + 1 */
	int		xlen;			/* length of text in pixels*/
	int		xv0;			/* position of first visible character */
	int		xsel0;		/* position of start of selection */
	int		xsel1;		/* position of end of selection */
	int		xicursor;		/* position of insertion cursor */
};

static void blinkreset(Tk*);

static
TkOption opts[] =
{
	"xscrollcommand",	OPTtext,	O(TkEntry, xscroll),	nil,
	"justify",		OPTstab,	O(TkEntry, flag),	tkjust,
	"show",			OPTtext,	O(TkEntry, show),	nil,
	nil
};

static int
xinset(Tk *tk)
{
	return Entrypadx + tk->highlightwidth;
}

static int
yinset(Tk *tk)
{
	return Entrypady + tk->highlightwidth;
}

static void
tksizeentry(Tk *tk)
{
	if((tk->flag & Tksetwidth) == 0)
		tk->req.width = tk->env->wzero*25 + 2*xinset(tk) + Inswidth;
	if((tk->flag & Tksetheight) == 0)
		tk->req.height = tk->env->font->height+ 2*yinset(tk);
}

int
entrytextwidth(Tk *tk, int n)
{
	TkEntry *tke = TKobj(TkEntry, tk);
	Rune c;
	Font *f;

	f = tk->env->font;
	if (tke->show != nil) {
		chartorune(&c, tke->show);
		return n * runestringnwidth(f, &c, 1);
	}
	return runestringnwidth(f, tke->text, n);
}

static int
x2index(Tk *tk,  int x, int *xc)
{
	TkEntry *tke = TKobj(TkEntry, tk);
	int t0, t1, r, q;

	t0 = 0;
	t1 = tke->textlen;
	while (t0 <= t1) {
		r = (t0 + t1) / 2;
		q = entrytextwidth(tk, r);
		if (q == x) {
			if (xc != nil)
				*xc = q;
			return r;
		}
		if (q < x)
			t0 = r + 1;
		else
			t1 = r - 1;
	}
	if (xc != nil)
		*xc = t1 > 0 ? entrytextwidth(tk, t1) : 0;
	if (t1 < 0)
		t1 = 0;
	return t1;
}

/*
 * recalculate derived values
 */
static void
recalcentry(Tk *tk)
{
	TkEntry *tke = TKobj(TkEntry, tk);
	int x, avail, locked;

	locked = lockdisplay(tk->env->top->display);

	tke->xlen = entrytextwidth(tk, tke->textlen) + Inswidth;

	avail = tk->act.width - 2*xinset(tk);
	if (tke->xlen < avail) {
		switch(tke->flag & Ejustify) {
		default:
			tke->x0 = 0;
			break;
		case Eright:
			tke->x0 = -(avail - tke->xlen);
			break;
		case Ecenter:
			tke->x0 = -(avail - tke->xlen) / 2;
			break;
		}
	}

	tke->v0 = x2index(tk, tke->x0, &tke->xv0);
	tke->v1 = x2index(tk, tk->act.width + tke->x0, &x);
	/* perhaps include partial last character */
	if (tke->v1 < tke->textlen && x < avail + tke->x0)
		tke->v1++;
	tke->xsel0 = entrytextwidth(tk, tke->sel0);
	tke->xsel1 = entrytextwidth(tk, tke->sel1);
	tke->xicursor = entrytextwidth(tk, tke->icursor);

	if (locked)
		unlockdisplay(tk->env->top->display);
}

char*
tkentry(TkTop *t, char *arg, char **ret)
{
	Tk *tk;
	char *e;
	TkName *names;
	TkEntry *tke;
	TkOptab tko[3];

	tk = tknewobj(t, TKentry, sizeof(Tk)+sizeof(TkEntry));
	if(tk == nil)
		return TkNomem;

	tk->relief = TKsunken;
	tk->borderwidth = 1;
	tk->flag |= Tktakefocus;
	tk->highlightwidth = 1;

	tke = TKobj(TkEntry, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tke;
	tko[1].optab = opts;
	tko[2].ptr = nil;

	names = nil;
	e = tkparse(t, arg, tko, &names);
	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}
	tksettransparent(tk, tkhasalpha(tk->env, TkCbackgnd));
	tksizeentry(tk);
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
	recalcentry(tk);

	return tkvalue(ret, "%s", tk->name->name);
}

static char*
tkentrycget(Tk *tk, char *arg, char **val)
{
	TkOptab tko[3];
	TkEntry *tke = TKobj(TkEntry, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tke;
	tko[1].optab = opts;
	tko[2].ptr = nil;

	return tkgencget(tko, arg, val, tk->env->top);
}

void
tkfreeentry(Tk *tk)
{
	TkEntry *tke = TKobj(TkEntry, tk);

	free(tke->xscroll);
	free(tke->text);
	free(tke->show);
}

static void
tkentrytext(Image *i, Rectangle s, Tk *tk, TkEnv *env)
{
	TkEntry *tke = TKobj(TkEntry, tk);
	Point dp;
	int s0, s1, xs0, xs1, j;
	Rectangle r;
	Rune showr, *text;

	dp = Pt(s.min.x - (tke->x0 - tke->xv0), s.min.y);
	if (tke->show) {
		chartorune(&showr, tke->show);
		text = mallocz(sizeof(Rune) * (tke->textlen+1), 0);
		if (text == nil)
			return;
		for (j = 0; j < tke->textlen; j++)
			text[j] = showr;
	} else
		text = tke->text;

	runestringn(i, dp, tkgc(env, TkCforegnd), dp, env->font,
				text+tke->v0, tke->v1-tke->v0);

	if (tke->sel0 < tke->v1 && tke->sel1 > tke->v0) {
		if (tke->sel0 < tke->v0) {
			s0 = tke->v0;
			xs0 = tke->xv0 - tke->x0;
		} else {
			s0 = tke->sel0;
			xs0 = tke->xsel0 - tke->x0;
		}

		if (tke->sel1 > tke->v1) {
			s1 = tke->v1;
			xs1 = s.max.x;
		} else {
			s1 = tke->sel1;
			xs1 = tke->xsel1 - tke->x0;
		}

		r = rectaddpt(Rect(xs0, 0, xs1, env->font->height), s.min);
		tktextsdraw(i, r, env, 1);
		runestringn(i, r.min, tkgc(env, TkCselectfgnd), r.min, env->font,
				text+s0, s1-s0);
	}

	if((tke->flag&Ecursoron) && tke->icursor >= tke->v0 && tke->icursor <= tke->v1) {
		r = Rect(
			tke->xicursor - tke->x0, 0, 
			tke->xicursor - tke->x0 + Inswidth, env->font->height
		);
		draw(i, rectaddpt(r, s.min), tkgc(env, TkCforegnd), nil, ZP);
	}
	if (tke->show)
		free(text);
}

char*
tkdrawentry(Tk *tk, Point orig)
{
	Point p;
	TkEnv *env;
	Rectangle r, s;
	Image *i;
	int xp, yp;

	env = tk->env;

	r.min = ZP;
	r.max.x = tk->act.width + 2*tk->borderwidth;
	r.max.y = tk->act.height + 2*tk->borderwidth;
	i = tkitmp(env, r.max, TkCbackgnd);
	if(i == nil)
		return nil;

	xp = tk->borderwidth + xinset(tk);
	yp = tk->borderwidth + yinset(tk);
	s = r;
	s.min.x += xp;
	s.max.x -= xp;
	s.min.y += yp;
	s.max.y -= yp;
	tkentrytext(i, s, tk, env);

	tkdrawrelief(i, tk, ZP, TkCbackgnd, tk->relief);

	if (tkhaskeyfocus(tk))
		tkbox(i, insetrect(r, tk->borderwidth), tk->highlightwidth, tkgc(tk->env, TkChighlightfgnd));

	p.x = tk->act.x + orig.x;
	p.y = tk->act.y + orig.y;
	r = rectaddpt(r, p);
	draw(tkimageof(tk), r, i, nil, ZP);

	return nil;
}
	
char*
tkentrysh(Tk *tk)
{
	TkEntry *tke = TKobj(TkEntry, tk);
	int dx, top, bot;
	char *val, *cmd, *v, *e;

	if(tke->xscroll == nil)
		return nil;

	bot = 0;
	top = Tkfpscalar;

	if(tke->text != 0 && tke->textlen != 0) {
		dx = tk->act.width - 2*xinset(tk);

		if (tke->xlen > dx) {
			bot = TKI2F(tke->x0) / tke->xlen;
			top = TKI2F(tke->x0 + dx) / tke->xlen;
		}
	}

	val = mallocz(Tkminitem, 0);
	if(val == nil)
		return TkNomem;
	v = tkfprint(val, bot);
	*v++ = ' ';
	tkfprint(v, top);
	cmd = mallocz(Tkminitem, 0);
	if(cmd == nil) {
		free(val);
		return TkNomem;
	}
	sprint(cmd, "%s %s", tke->xscroll, val);
	e = tkexec(tk->env->top, cmd, nil);
	free(cmd);
	free(val);
	return e;
}

void
tkentrygeom(Tk *tk)
{
	char *e;
	e = tkentrysh(tk);
	if ((e != nil) &&	/* XXX - Tad: should propagate not print */
             (tk->name != nil))
		print("tk: xscrollcommand \"%s\": %s\n", tk->name->name, e);
	recalcentry(tk);
}

static char*
tkentryconf(Tk *tk, char *arg, char **val)
{
	char *e;
	TkGeom g;
	int bd;
	TkOptab tko[3];
	TkEntry *tke = TKobj(TkEntry, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tke;
	tko[1].optab = opts;
	tko[2].ptr = nil;

	if(*arg == '\0')
		return tkconflist(tko, val);

	bd = tk->borderwidth;
	g = tk->req;
	e = tkparse(tk->env->top, arg, tko, nil);
	tksettransparent(tk, tkhasalpha(tk->env, TkCbackgnd));
	tksizeentry(tk);
	tkgeomchg(tk, &g, bd);
	recalcentry(tk);
	tk->dirty = tkrect(tk, 1);
	return e;
}

static char*
tkentryparseindex(Tk *tk, char *buf, int *index)
{
	TkEntry *tke = TKobj(TkEntry, tk);
	TkEnv *env;
	char *mod;
	int i, x, locked, modstart;

	modstart = 0;
	for(mod = buf; *mod != '\0'; mod++)
		if(*mod == '-' || *mod == '+') {
			modstart = *mod;
			*mod = '\0';
			break;
		}
	if(strcmp(buf, "end") == 0)
		i = tke->textlen;
	else
	if(strcmp(buf, "anchor") == 0)
		i = tke->anchor;
	else
	if(strcmp(buf, "insert") == 0)
		i = tke->icursor;
	else
	if(strcmp(buf, "sel.first") == 0)
		i = tke->sel0;
	else
	if(strcmp(buf, "sel.last") == 0)
		i = tke->sel1;
	else
	if(buf[0] >= '0' && buf[0] <= '9')
		i = atoi(buf);
	else
	if(buf[0] == '@') {
		x = atoi(buf+1) - xinset(tk);
		if(tke->textlen == 0) {
			*index = 0;
			return nil;
		}
		env = tk->env;
		locked = lockdisplay(env->top->display);
		i = x2index(tk, x + tke->x0, nil);	/* XXX could possibly select nearest character? */
		if(locked)
			unlockdisplay(env->top->display);
	}
	else
		return TkBadix;

	if(i < 0 || i > tke->textlen)
		return TkBadix;
	if(modstart) {
		*mod = modstart;
		i += atoi(mod);
		if(i < 0)
			i = 0;
		if(i > tke->textlen)
			i = tke->textlen;
	}
	*index = i;
	return nil;
}

/*
 * return bounding box of character at index, in coords relative to
 * the top left position of the text.
 */
static Rectangle
tkentrybbox(Tk *tk, int index)
{
	TkEntry *tke;
	TkEnv *env;
	Display *d;
	int x, cw, locked;
	Rectangle r;

	tke = TKobj(TkEntry, tk);
	env = tk->env;

	d = env->top->display;

	locked = lockdisplay(d);
	x = entrytextwidth(tk, index);
	if (index < tke->textlen)
		cw = entrytextwidth(tk, index+1) - x;
	else
		cw = Inswidth;
	if(locked)
		unlockdisplay(d);

	r.min.x = x;
	r.min.y = 0;
	r.max.x = x + cw;
	r.max.y = env->font->height;
	return r;
}

static void
tkentrysee(Tk *tk, int index, int jump)
{
	TkEntry *tke = TKobj(TkEntry, tk);
	int dx, margin;
	Rectangle r;

	r = tkentrybbox(tk, index);
	dx = tk->act.width - 2*xinset(tk);
	if (jump)
		margin = dx / 4;
	else
		margin = 0;
	if (r.min.x <= tke->x0 || r.max.x > tke->x0 + dx) {
		if (r.min.x <= tke->x0) {
			tke->x0 = r.min.x - margin;
			if (tke->x0 < 0)
				tke->x0 = 0;
		} else if (r.max.x >= tke->x0 + dx) {
			tke->x0 = r.max.x - dx + margin;
			if (tke->x0 > tke->xlen - dx)
				tke->x0 = tke->xlen - dx;
		}
		tk->dirty = tkrect(tk, 0);
	}
	r = rectaddpt(r, Pt(xinset(tk) - tke->x0, yinset(tk)));
	tksee(tk, r, r.min);
}

static char*
tkentryseecmd(Tk *tk, char *arg, char **val)
{
	int index;
	char *e, *buf;

	USED(val);

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	tkword(tk->env->top, arg, buf, buf+Tkmaxitem, nil);
	e = tkentryparseindex(tk, buf, &index);
	free(buf);
	if(e != nil)
		return e;

	tkentrysee(tk, index, 1);
	recalcentry(tk);
	
	return nil;
}

static char*
tkentrybboxcmd(Tk *tk, char *arg, char **val)
{
	TkEntry *tke = TKobj(TkEntry, tk);
	char *r, *buf;
	int index;
	Rectangle bbox;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	tkword(tk->env->top, arg, buf, buf+Tkmaxitem, nil);
	r = tkentryparseindex(tk, buf, &index);
	free(buf);
	if(r != nil)
		return r;
	bbox = rectaddpt(tkentrybbox(tk, index), Pt(xinset(tk) - tke->x0, yinset(tk)));
	return tkvalue(val, "%d %d %d %d", bbox.min.x, bbox.min.y, bbox.max.x, bbox.max.y);
}

static char*
tkentryindex(Tk *tk, char *arg, char **val)
{
	int index;
	char *r, *buf;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	tkword(tk->env->top, arg, buf, buf+Tkmaxitem, nil);
	r = tkentryparseindex(tk, buf, &index);
	free(buf);
	if(r != nil)
		return r;
	return tkvalue(val, "%d", index);
}

static char*
tkentryicursor(Tk *tk, char *arg, char **val)
{
	TkEntry *tke = TKobj(TkEntry, tk);
	int index, locked;
	char *r, *buf;

	USED(val);
	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	tkword(tk->env->top, arg, buf, buf+Tkmaxitem, nil);
	r = tkentryparseindex(tk, buf, &index);
	free(buf);
	if(r != nil)
		return r;
	tke->icursor = index;
	locked = lockdisplay(tk->env->top->display);
	tke->xicursor = entrytextwidth(tk, tke->icursor);
	if (locked)
		unlockdisplay(tk->env->top->display);

	blinkreset(tk);
	tk->dirty = tkrect(tk, 1);
	return nil;
}

static int
adjustforins(int i, int n, int q)
{
	if (i <= q)
		q += n;
	return q;
}

static int
adjustfordel(int d0, int d1, int q)
{
	if (d1 <= q)
		q -= d1 - d0;
	else if (d0 <= q && q <= d1)
		q = d0;
	return q;
}

static char*
tkentryget(Tk *tk, char *arg, char **val)
{
	TkTop *top;
	TkEntry *tke;
	int first, last;
	char *e, *buf;

	tke = TKobj(TkEntry, tk);	
	if(tke->text == nil)
		return nil;

	arg = tkskip(arg, " \t");
	if(*arg == '\0')
		return tkvalue(val, "%.*S", tke->textlen, tke->text);

	top = tk->env->top;
	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	arg = tkword(top, arg, buf, buf+Tkmaxitem, nil);
	e = tkentryparseindex(tk, buf, &first);
	if(e != nil) {
		free(buf);
		return e;
	}
	last = first+1;
	tkword(top, arg, buf, buf+Tkmaxitem, nil);
	if(buf[0] != '\0') {
		e = tkentryparseindex(tk, buf, &last);
		if(e != nil) {
			free(buf);
			return e;
		}
	}
	free(buf);
	if(last <= first || tke->textlen == 0 || first == tke->textlen)
		return tkvalue(val, "%S", L"");
	return tkvalue(val, "%.*S", last-first, tke->text+first);
}

static char*
tkentryinsert(Tk *tk, char *arg, char **val)
{
	TkTop *top;
	TkEntry *tke;
	int ins, i, n, locked;
	char *e, *t, *text, *buf;
	Rune *etext;

	USED(val);
	tke = TKobj(TkEntry, tk);

	top = tk->env->top;
	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	arg = tkword(top, arg, buf, buf+Tkmaxitem, nil);
	e = tkentryparseindex(tk, buf, &ins);
	free(buf);
	if(e != nil)
		return e;

	if(*arg == '\0')
		return nil;

	n = strlen(arg) + 1;
	if(n < Tkmaxitem)
		n = Tkmaxitem;
	text = malloc(n);
	if(text == nil)
		return TkNomem;

	tkword(top, arg, text, text+n, nil);
	n = utflen(text);
	etext = realloc(tke->text, (tke->textlen+n+1)*sizeof(Rune));
	if(etext == nil) {
		free(text);
		return TkNomem;
	}
	tke->text = etext;

	memmove(tke->text+ins+n, tke->text+ins, (tke->textlen-ins)*sizeof(Rune));
	t = text;
	for(i=0; i<n; i++)
		t += chartorune(tke->text+ins+i, t);
	free(text);

	tke->textlen += n;

	tke->sel0 = adjustforins(ins, n, tke->sel0);
	tke->sel1 = adjustforins(ins, n, tke->sel1);
	tke->icursor = adjustforins(ins, n, tke->icursor);
	tke->anchor = adjustforins(ins, n, tke->anchor);

	locked = lockdisplay(tk->env->top->display);
	if (ins < tke->v0)
		tke->x0 += entrytextwidth(tk, tke->v0 + n) + (tke->x0 - tke->xv0);
	if (locked)
		unlockdisplay(tk->env->top->display);
	recalcentry(tk);

	e = tkentrysh(tk);
	blinkreset(tk);
	tk->dirty = tkrect(tk, 1);

	return e;
}

static char*
tkentrydelete(Tk *tk, char *arg, char **val)
{
	TkTop *top;
	TkEntry *tke;
	int d0, d1, locked;
	char *e, *buf;
	Rune *text;

	USED(val);

	tke = TKobj(TkEntry, tk);

	top = tk->env->top;
	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	arg = tkword(top, arg, buf, buf+Tkmaxitem, nil);
	e = tkentryparseindex(tk, buf, &d0);
	if(e != nil) {
		free(buf);
		return e;
	}

	d1 = d0+1;
	tkword(top, arg, buf, buf+Tkmaxitem, nil);
	if(buf[0] != '\0') {
		e = tkentryparseindex(tk, buf, &d1);
		if(e != nil) {
			free(buf);
			return e;
		}
	}
	free(buf);
	if(d1 <= d0 || tke->textlen == 0 || d0 >= tke->textlen)
		return nil;

	memmove(tke->text+d0, tke->text+d1, (tke->textlen-d1)*sizeof(Rune));
	tke->textlen -= d1 - d0;

	text = realloc(tke->text, (tke->textlen+1) * sizeof(Rune));
	if (text != nil)
		tke->text = text;
	tke->sel0 = adjustfordel(d0, d1, tke->sel0);
	tke->sel1 = adjustfordel(d0, d1, tke->sel1);
	tke->icursor = adjustfordel(d0, d1, tke->icursor);
	tke->anchor = adjustfordel(d0, d1, tke->anchor);

	locked = lockdisplay(tk->env->top->display);
	if (d1 < tke->v0)
		tke->x0 = entrytextwidth(tk, tke->v0 - (d1 - d0)) + (tke->x0 - tke->xv0);
	else if (d0 < tke->v0)
		tke->x0 = entrytextwidth(tk, d0);
	if (locked)
		unlockdisplay(tk->env->top->display);
	recalcentry(tk);

	e = tkentrysh(tk);
	blinkreset(tk);
	tk->dirty = tkrect(tk, 1);

	return e;
}

/*	Used for both backspace and DEL.  If a selection exists, delete it.
 *	Otherwise delete the character to the left(right) of the insertion
 *	cursor, if any.
 */
static char*
tkentrybs(Tk *tk, char *arg, char **val)
{
	TkEntry *tke = TKobj(TkEntry, tk);
	char *buf, *e;
	int ix;

	USED(val);
	USED(arg);

	if(tke->textlen == 0)
		return nil;

	if(tke->sel0 < tke->sel1)
		return tkentrydelete(tk, "sel.first sel.last", nil);

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	tkword(tk->env->top, arg, buf, buf+Tkmaxitem, nil);
	ix = -1;
	if(buf[0] != '\0') {
		e = tkentryparseindex(tk, buf, &ix);
		if(e != nil) {
			free(buf);
			return e;
		}
	}
	if(ix > -1) {			/* DEL */
		if(tke->icursor >= tke->textlen) {
			free(buf);
			return nil;
		}
	}
	else {				/* backspace */
		if(tke->icursor == 0) {
			free(buf);
			return nil;
		}
		tke->icursor--;
	}
	snprint(buf, Tkmaxitem, "%d", tke->icursor);
	e = tkentrydelete(tk, buf, nil);
	free(buf);
	return e;
}

static char*
tkentrybw(Tk *tk, char *arg, char **val)
{
	int start;
	Rune *text;
	TkEntry *tke;
	char buf[32];

	USED(val);
	USED(arg);

	tke = TKobj(TkEntry, tk);
	if(tke->textlen == 0 || tke->icursor == 0)
		return nil;

	text = tke->text;
	start = tke->icursor-1;
	while(start > 0 && !tkiswordchar(text[start]))
		--start;
	while(start > 0 && tkiswordchar(text[start-1]))
		--start;

	snprint(buf, sizeof(buf), "%d %d", start, tke->icursor);
	return tkentrydelete(tk, buf, nil);
}

char*
tkentryselect(Tk *tk, char *arg, char **val)
{
	TkTop *top;
	int start, from, to, locked;
	TkEntry *tke;
	char *e, *buf;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;

	tke = TKobj(TkEntry, tk);

	top = tk->env->top;
	arg = tkword(top, arg, buf, buf+Tkmaxitem, nil);
	if(strcmp(buf, "clear") == 0) {
		tke->sel0 = 0;
		tke->sel1 = 0;
	}
	else
	if(strcmp(buf, "from") == 0) {
		tkword(top, arg, buf, buf+Tkmaxitem, nil);
		e = tkentryparseindex(tk, buf, &tke->anchor);
		tke->flag &= ~Ewordsel;
		free(buf);
		return e;
	}
	else
	if(strcmp(buf, "to") == 0) {
		tkword(top, arg, buf, buf+Tkmaxitem, nil);
		e = tkentryparseindex(tk, buf, &to);
		if(e != nil) {
			free(buf);
			return e;
		}
		
		if(to < tke->anchor) {
			if(tke->flag & Ewordsel)
				while(to > 0 && tkiswordchar(tke->text[to-1]))
					--to;
			tke->sel0 = to;
			tke->sel1 = tke->anchor;
		}
		else
		if(to >= tke->anchor) {
			if(tke->flag & Ewordsel)
				while(to < tke->textlen &&
						tkiswordchar(tke->text[to]))
					to++;
			tke->sel0 = tke->anchor;
			tke->sel1 = to;
		}
		tkentrysee(tk, to, 0);
		recalcentry(tk);
	}
	else
	if(strcmp(buf, "word") == 0) {	/* inferno invention */
		tkword(top, arg, buf, buf+Tkmaxitem, nil);
		e = tkentryparseindex(tk, buf, &start);
		if(e != nil) {
			free(buf);
			return e;
		}
		from = start;
		while(from > 0 && tkiswordchar(tke->text[from-1]))
			--from;
		to = start;
		while(to < tke->textlen && tkiswordchar(tke->text[to]))
			to++;
		tke->sel0 = from;
		tke->sel1 = to;
		tke->anchor = from;
		tke->icursor = from;
		tke->flag |= Ewordsel;
		locked = lockdisplay(tk->env->top->display);
		tke->xicursor = entrytextwidth(tk, tke->icursor);
		if (locked)
			unlockdisplay(tk->env->top->display);
	}
	else
	if(strcmp(buf, "present") == 0) {
		e = tkvalue(val, "%d", tke->sel1 > tke->sel0);
		free(buf);
		return e;
	}
	else
	if(strcmp(buf, "range") == 0) {
		arg = tkword(top, arg, buf, buf+Tkmaxitem, nil);
		e = tkentryparseindex(tk, buf, &from);
		if(e != nil) {
			free(buf);
			return e;
		}
		tkword(top, arg, buf, buf+Tkmaxitem, nil);
		e = tkentryparseindex(tk, buf, &to);
		if(e != nil) {
			free(buf);
			return e;
		}
		tke->sel0 = from;
		tke->sel1 = to;
		if(to <= from) {
			tke->sel0 = 0;
			tke->sel1 = 0;
		}
	}
	else
	if(strcmp(buf, "adjust") == 0) {
		tkword(top, arg, buf, buf+Tkmaxitem, nil);
		e = tkentryparseindex(tk, buf, &to);
		if(e != nil) {
			free(buf);
			return e;
		}
		if(tke->sel0 == 0 && tke->sel1 == 0) {
			tke->sel0 = tke->anchor;
			tke->sel1 = to;
		}
		else {
			if(abs(tke->sel0-to) < abs(tke->sel1-to)) {
				tke->sel0 = to;
				tke->anchor = tke->sel1;
			}
			else {
				tke->sel1 = to;
				tke->anchor = tke->sel0;
			}
		}
		if(tke->sel0 > tke->sel1) {
			to = tke->sel0;
			tke->sel0 = tke->sel1;
			tke->sel1 = to;
		}
	}
	else {
		free(buf);
		return TkBadcm;
	}
	locked = lockdisplay(tk->env->top->display);
	tke->xsel0 = entrytextwidth(tk, tke->sel0);
	tke->xsel1 = entrytextwidth(tk, tke->sel1);
	if (locked)
		unlockdisplay(tk->env->top->display);
	tk->dirty = tkrect(tk, 1);
	free(buf);
	return nil;
}


static char*
tkentryb2p(Tk *tk, char *arg, char **val)
{
	TkEntry *tke;
	char *buf;

	USED(val);

	tke = TKobj(TkEntry, tk);
	buf = malloc(Tkmaxitem);
	if (buf == nil)
		return TkNomem;

	tkword(tk->env->top, arg, buf, buf+Tkmaxitem, nil);
	tke->oldx = atoi(buf);
	return nil;
}

static char*
tkentryxview(Tk *tk, char *arg, char **val)
{
	int locked;
	TkEnv *env;
	TkEntry *tke;
	char *buf, *v;
	int dx, top, bot, amount, ix, x;
	char *e;

	tke = TKobj(TkEntry, tk);
	env = tk->env;
	dx = tk->act.width - 2*xinset(tk);

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;

	if(*arg == '\0') {
		if (tke->textlen == 0 || tke->xlen < dx) {
			bot = TKI2F(0);
			top = TKI2F(1);
		} else {
			bot = TKI2F(tke->x0) / tke->xlen;
			top = TKI2F(tke->x0 + dx) / tke->xlen;
		}
		v = tkfprint(buf, bot);
		*v++ = ' ';
		tkfprint(v, top);
		e = tkvalue(val, "%s", buf);
		free(buf);
		return e;
	}

	arg = tkitem(buf, arg);
	if(strcmp(buf, "moveto") == 0) {
		e = tkfracword(env->top, &arg, &top, nil);
		if (e != nil) {
			free(buf);
			return e;
		}
		tke->x0 = TKF2I(top*tke->xlen);
	}
	else
	if(strcmp(buf, "scroll") == 0) {
		arg = tkitem(buf, arg);
		amount = atoi(buf);
		if(*arg == 'p')		/* Pages */
			amount *= (9*tke->xlen)/10;
		else
		if(*arg == 's') {		/* Inferno-ism, "scr", must be used in the context of button2p */
			x = amount;
			amount = x < tke->oldx ? env->wzero : (x > tke->oldx ? -env->wzero : 0);
			tke->oldx = x;
		}
		tke->x0 += amount;
	}
	else {
		e = tkentryparseindex(tk, buf, &ix);
		if(e != nil) {
			free(buf);
			return e;
		}
		locked = lockdisplay(env->top->display);
		tke->x0 = entrytextwidth(tk, ix);
		if (locked)
			unlockdisplay(env->top->display);
	}
	free(buf);

	if (tke->x0 > tke->xlen - dx)
		tke->x0 = tke->xlen - dx;
	if (tke->x0 < 0)
		tke->x0 = 0;
	recalcentry(tk);
	e = tkentrysh(tk);
	blinkreset(tk);
	tk->dirty = tkrect(tk, 1);
	return e;
}

static void
autoselect(Tk *tk, void *v, int cancelled)
{
	TkEntry *tke = TKobj(TkEntry, tk);
	Rectangle hitr;
	char buf[32];
	Point p;

	USED(v);

	if (cancelled)
		return;

	p = tkscrn2local(tk, Pt(tke->oldx, 0));
	p.y = 0;
	if (tkvisiblerect(tk, &hitr) && ptinrect(p, hitr))
		return;

	snprint(buf, sizeof(buf), "to @%d", p.x);
	tkentryselect(tk, buf, nil);
	tkdirty(tk);
	tkupdate(tk->env->top);
}

static char*
tkentryb1p(Tk *tk, char* arg, char **ret)
{
	TkEntry *tke = TKobj(TkEntry, tk);
	Point p;
	int i, locked, x;
	char buf[32], *e;
	USED(ret);

	x = atoi(arg);
	p = tkscrn2local(tk, Pt(x, 0));
	sprint(buf, "@%d", p.x);
	e = tkentryparseindex(tk, buf, &i);
	if (e != nil)
		return e;
	tke->sel0 = 0;
	tke->sel1 = 0;
	tke->icursor = i;
	tke->anchor = i;
	tke->flag &= ~Ewordsel;

	locked = lockdisplay(tk->env->top->display);
	tke->xsel0 = 0;
	tke->xsel1 = 0;
	tke->xicursor = entrytextwidth(tk, tke->icursor);
	if (locked)
		unlockdisplay(tk->env->top->display);

	tke->oldx = x;
	blinkreset(tk);
	tkrepeat(tk, autoselect, nil, TkRptpause, TkRptinterval);
	tk->dirty = tkrect(tk, 0);
	return nil;
}

static char*
tkentryb1m(Tk *tk, char* arg, char **ret)
{
	TkEntry *tke = TKobj(TkEntry, tk);
	Point p;
	Rectangle hitr;
	char buf[32];
	USED(ret);

	p.x = atoi(arg);
	tke->oldx = p.x;
	p = tkscrn2local(tk, p);
	p.y = 0;
	if (!tkvisiblerect(tk, &hitr) || !ptinrect(p, hitr))
		return nil;
	snprint(buf, sizeof(buf), "to @%d", p.x);
	tkentryselect(tk, buf, nil);
	return nil;
}

static char*
tkentryb1r(Tk *tk, char* arg, char **ret)
{
	USED(tk);
	USED(arg);
	USED(ret);
	tkcancelrepeat(tk);
	return nil;
}

static void
blinkreset(Tk *tk)
{
	TkEntry *e = TKobj(TkEntry, tk);
	if (!tkhaskeyfocus(tk) || tk->flag&Tkdisabled)
		return;
	e->flag |= Ecursoron;
	tkblinkreset(tk);
}

static void
showcaret(Tk *tk, int on)
{
	TkEntry *e = TKobj(TkEntry, tk);

	if (on)
		e->flag |= Ecursoron;
	else
		e->flag &= ~Ecursoron;
	tk->dirty = tkrect(tk, 0);
}

char*
tkentryfocus(Tk *tk, char* arg, char **ret)
{
	int on = 0;
	USED(ret);

	if (tk->flag&Tkdisabled)
		return nil;

	if(strcmp(arg, " in") == 0) {
		tkblink(tk, showcaret);
		on = 1;
	}
	else
		tkblink(nil, nil);

	showcaret(tk, on);
	return nil;
}

static
TkCmdtab tkentrycmd[] =
{
	"cget",			tkentrycget,
	"configure",		tkentryconf,
	"delete",		tkentrydelete,
	"get",			tkentryget,
	"icursor",		tkentryicursor,
	"index",		tkentryindex,
	"insert",		tkentryinsert,
	"selection",		tkentryselect,
	"xview",		tkentryxview,
	"tkEntryBS",		tkentrybs,
	"tkEntryBW",		tkentrybw,
	"tkEntryB1P",		tkentryb1p,
	"tkEntryB1M",		tkentryb1m,
	"tkEntryB1R",		tkentryb1r,
	"tkEntryB2P",		tkentryb2p,
	"tkEntryFocus",		tkentryfocus,
	"bbox",			tkentrybboxcmd,
	"see",		tkentryseecmd,
	nil
};

TkMethod entrymethod = {
	"entry",
	tkentrycmd,
	tkfreeentry,
	tkdrawentry,
	tkentrygeom
};
