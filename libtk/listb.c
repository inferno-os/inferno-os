#include "lib9.h"
#include "draw.h"
#include "keyboard.h"
#include "tk.h"
#include "listb.h"

#define	O(t, e)		((long)(&((t*)0)->e))

/* Layout constants */
enum {
	Listpadx	= 2,	/* X padding of text in listboxes */
};

typedef struct TkLentry TkLentry;
typedef struct TkListbox TkListbox;

struct TkLentry
{
	TkLentry*	link;
	int		flag;
	int		width;
	char		text[TKSTRUCTALIGN];
};

struct TkListbox
{
	TkLentry*	head;
	TkLentry*	anchor;
	TkLentry*	active;
	int		yelem;		/* Y element at top of box */
	int		xdelta;		/* h-scroll position */
	int		nitem;
	int		nwidth;
	int		selmode;
	int		sborderwidth;
	char*		xscroll;
	char*		yscroll;
};

TkStab tkselmode[] =
{
	"single",	TKsingle,
	"browse",	TKbrowse,
	"multiple",	TKmultiple,
	"extended",	TKextended,
	nil
};

static
TkOption opts[] =
{
	"xscrollcommand",	OPTtext,	O(TkListbox, xscroll),	nil,
	"yscrollcommand",	OPTtext,	O(TkListbox, yscroll),	nil,
	"selectmode",		OPTstab,	O(TkListbox, selmode),	tkselmode,
	"selectborderwidth",	OPTnndist,	O(TkListbox, sborderwidth),	nil,
	nil
};

static
TkEbind b[] = 
{
	{TkButton1P,		"%W tkListbButton1P %y"},
	{TkButton1R,	"%W tkListbButton1R"},
	{TkButton1P|TkMotion,	"%W tkListbButton1MP %y"},
	{TkMotion,		""},
	{TkKey,	"%W tkListbKey 0x%K"},
};


static int
lineheight(Tk *tk)
{
	TkListbox *l = TKobj(TkListbox, tk);
	return tk->env->font->height+2*(l->sborderwidth+tk->highlightwidth);
}

char*
tklistbox(TkTop *t, char *arg, char **ret)
{
	Tk *tk;
	char *e;
	TkName *names;
	TkListbox *tkl;
	TkOptab tko[3];

	tk = tknewobj(t, TKlistbox, sizeof(Tk)+sizeof(TkListbox));
	if(tk == nil)
		return TkNomem;

	tkl = TKobj(TkListbox, tk);
	tkl->sborderwidth = 1;
	tk->relief = TKsunken;
	tk->borderwidth = 1;
	tk->highlightwidth = 1;
	tk->flag |= Tktakefocus;
	tk->req.width = 170;
	tk->req.height = lineheight(tk)*10;

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkl;
	tko[1].optab = opts;
	tko[2].ptr = nil;

	names = nil;
	e = tkparse(t, arg, tko, &names);
	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}
	tksettransparent(tk, tkhasalpha(tk->env, TkCbackgnd));

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

char*
tklistbcget(Tk *tk, char *arg, char **val)
{
	TkOptab tko[3];
	TkListbox *tkl = TKobj(TkListbox, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkl;
	tko[1].optab = opts;
	tko[2].ptr = nil;

	return tkgencget(tko, arg, val, tk->env->top);
}

void
tkfreelistb(Tk *tk)
{
	TkLentry *e, *next;
	TkListbox *l = TKobj(TkListbox, tk);

	for(e = l->head; e; e = next) {
		next = e->link;
		free(e);
	}
	if(l->xscroll != nil)
		free(l->xscroll);
	if(l->yscroll != nil)
		free(l->yscroll);
}

char*
tkdrawlistb(Tk *tk, Point orig)
{
	Point p;
	TkEnv *env;
	TkLentry *e;
	int lh, w, n, ly;
	Rectangle r, a;
	Image *i, *fg;
	TkListbox *l = TKobj(TkListbox, tk);

	env = tk->env;

	r.min = ZP;
	r.max.x = tk->act.width + 2*tk->borderwidth;
	r.max.y = tk->act.height + 2*tk->borderwidth;
	i = tkitmp(env, r.max, TkCbackgnd);
	if(i == nil)
		return nil;

	w = tk->act.width;
	if (w < l->nwidth)
		w = l->nwidth;
	lh = lineheight(tk);
	ly = tk->borderwidth;
	p.x = tk->borderwidth+l->sborderwidth+tk->highlightwidth+Listpadx-l->xdelta;
	p.y = tk->borderwidth+l->sborderwidth+tk->highlightwidth;
	n = 0;
	for(e = l->head; e && ly < r.max.y; e = e->link) {
		if(n++ < l->yelem)
			continue;

		a.min.x = tk->borderwidth;
		a.min.y = ly;
		a.max.x = a.min.x + tk->act.width;
		a.max.y = a.min.y + lh;
		if(e->flag & Tkactivated) {
			draw(i, a, tkgc(env, TkCselectbgnd), nil, ZP);
		}

		if(e->flag & Tkactivated)
			fg = tkgc(env, TkCselectfgnd);
		else
			fg = tkgc(env, TkCforegnd);
		string(i, p, fg, p, env->font, e->text);
		if((e->flag & Tkactive) && tkhaskeyfocus(tk)) {
			a.min.x = tk->borderwidth-l->xdelta;
			a.max.x = a.min.x+w;
			a = insetrect(a, l->sborderwidth);
			tkbox(i, a, tk->highlightwidth, fg);
		}
		ly += lh;
		p.y += lh;
	}

	tkdrawrelief(i, tk, ZP, TkCbackgnd, tk->relief);

	p.x = tk->act.x + orig.x;
	p.y = tk->act.y + orig.y;
	r = rectaddpt(r, p);
	draw(tkimageof(tk), r, i, nil, ZP);

	return nil;
}

int
tklindex(Tk *tk, char *buf)
{
	int index;
	TkListbox *l;
	TkLentry *e, *s;

	l = TKobj(TkListbox, tk);

	if(*buf == '@') {
		while(*buf && *buf != ',')
			buf++;
		index = l->yelem + atoi(buf+1)/lineheight(tk);
		if (index < 0)
			return 0;
		if (index > l->nitem)
			return l->nitem;
		return index;
	}
	if(*buf >= '0' && *buf <= '9')
		return atoi(buf);

	if(strcmp(buf, "end") == 0) {
		if(l->nitem == 0)
			return 0;
		return l->nitem-1;
	}

	index = 0;
	if(strcmp(buf, "active") == 0)
		s = l->active;
	else
	if(strcmp(buf, "anchor") == 0)
		s = l->anchor;
	else
		return -1;

	for(e = l->head; e; e = e->link) {
		if(e == s)
			return index;
		index++;
	}
	return -1;
}

void
tklistsv(Tk *tk)
{
	TkListbox *l;
	int nl, lh, top, bot;
	char val[Tkminitem], cmd[Tkmaxitem], *v, *e;

	l = TKobj(TkListbox, tk);
	if(l->yscroll == nil)
		return;

	top = 0;
	bot = TKI2F(1);

	if(l->nitem != 0) {
		lh = lineheight(tk);
		nl = tk->act.height/lh;			/* Lines in the box */
		top = TKI2F(l->yelem)/l->nitem;
		bot = TKI2F(l->yelem+nl)/l->nitem;
	}

	v = tkfprint(val, top);
	*v++ = ' ';
	tkfprint(v, bot);
	snprint(cmd, sizeof(cmd), "%s %s", l->yscroll, val);
	e = tkexec(tk->env->top, cmd, nil);
	if ((e != nil) && (tk->name != nil))
		print("tk: yscrollcommand \"%s\": %s\n", tk->name->name, e);
}

void
tklistsh(Tk *tk)
{
	int nl, top, bot;
	char val[Tkminitem], cmd[Tkmaxitem], *v, *e;
	TkListbox *l = TKobj(TkListbox, tk);

	if(l->xscroll == nil)
		return;

	top = 0;
	bot = TKI2F(1);

	if(l->nwidth != 0) {
		nl = tk->act.width;
		top = TKI2F(l->xdelta)/l->nwidth;
		bot = TKI2F(l->xdelta+nl)/l->nwidth;
	}

	v = tkfprint(val, top);
	*v++ = ' ';
	tkfprint(v, bot);
	snprint(cmd, sizeof(cmd), "%s %s", l->xscroll, val);
	e = tkexec(tk->env->top, cmd, nil);
	if ((e != nil) && (tk->name != nil))
		print("tk: xscrollcommand \"%s\": %s\n", tk->name->name, e);
}

void
tklistbgeom(Tk *tk)
{
	tklistsv(tk);
	tklistsh(tk);
}

static void
listbresize(Tk *tk)
{
	TkLentry *e;
	TkListbox *l = TKobj(TkListbox, tk);

	l->nwidth = 0;
	for (e = l->head; e != nil; e = e->link) {
		e->width = stringwidth(tk->env->font, e->text)+2*(Listpadx+l->sborderwidth+tk->highlightwidth);
		if(e->width > l->nwidth)
			l->nwidth = e->width;
	}
	tklistbgeom(tk);
}


/* Widget Commands (+ means implemented)
	+activate
	 bbox
	+cget
	+configure
	+curselection
	+delete
	+get
	+index
	+insert
	+nearest
	+see
	+selection
	+size
	+xview
	+yview
*/

char*
tklistbconf(Tk *tk, char *arg, char **val)
{
	char *e;
	TkGeom g;
	int bd, sbw, hlw;
	TkOptab tko[3];
	Font *f;
	TkListbox *tkl = TKobj(TkListbox, tk);

	sbw = tkl->sborderwidth;
	hlw = tk->highlightwidth;
	f = tk->env->font;
	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkl;
	tko[1].optab = opts;
	tko[2].ptr = nil;

	if(*arg == '\0')
		return tkconflist(tko, val);

	g = tk->req;
	bd = tk->borderwidth;
	e = tkparse(tk->env->top, arg, tko, nil);
	tksettransparent(tk, tkhasalpha(tk->env, TkCbackgnd));
	tkgeomchg(tk, &g, bd);

	if (sbw != tkl->sborderwidth || f != tk->env->font || hlw != tk->highlightwidth)
		listbresize(tk);
	tk->dirty = tkrect(tk, 1);
	return e;
}

static void
entryactivate(Tk *tk, int index)
{
	TkListbox *l = TKobj(TkListbox, tk);
	TkLentry *e;
	int flag = Tkactive;

	if (l->selmode == TKbrowse)
		flag |= Tkactivated;
	for(e = l->head; e; e = e->link) {
		if(index-- == 0) {
			e->flag |= flag;
			l->active = e;
		} else
			e->flag &= ~flag;
	}
	tk->dirty = tkrect(tk, 1);
}

char*
tklistbactivate(Tk *tk, char *arg, char **val)
{
	int index;
	char buf[Tkmaxitem];

	USED(val);
	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	index = tklindex(tk, buf);
	if(index == -1)
		return TkBadix;

	entryactivate(tk, index);
	return nil;
}

char*
tklistbnearest(Tk *tk, char *arg, char **val)
{
	int lh, y, index;
	TkListbox *l = TKobj(TkListbox, tk);

	lh = lineheight(tk);	/* Line height */
	y = atoi(arg);
	index = l->yelem + y/lh;
	if(index > l->nitem)
		index = l->nitem;
	return tkvalue(val, "%d", index);
}

char*
tklistbindex(Tk *tk, char *arg, char **val)
{
	int index;
	char buf[Tkmaxitem];
	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	index = tklindex(tk, buf);
	if(index == -1)
		return TkBadix;
	return tkvalue(val, "%d", index);
}

char*
tklistbsize(Tk *tk, char *arg, char **val)
{
	TkListbox *l = TKobj(TkListbox, tk);

	USED(arg);
	return tkvalue(val, "%d", l->nitem);
}

char*
tklistbinsert(Tk *tk, char *arg, char **val)
{
	int n, index;
	TkListbox *l;
	TkLentry *e, **el;
	char *tbuf, buf[Tkmaxitem];

	USED(val);
	l = TKobj(TkListbox, tk);

	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if(strcmp(buf, "end") == 0) {
		el = &l->head;
		if(*el != nil) {
			for(e = *el; e->link; e = e->link)
				;
			el = &e->link;
		}
	}
	else {
		index = tklindex(tk, buf);
		if(index == -1)
			return TkBadix;
		el = &l->head;
		for(e = *el; e && index-- > 0; e = e->link)
			el = &e->link;
	}

	n = strlen(arg);
	if(n > Tkmaxitem) {
		n = (n*3)/2;
		tbuf = malloc(n);
		if(tbuf == nil)
			return TkNomem;
	}
	else {
		tbuf = buf;
		n = sizeof(buf);
	}

	while(*arg) {
		arg = tkword(tk->env->top, arg, tbuf, &tbuf[n], nil);
		e = malloc(sizeof(TkLentry)+strlen(tbuf)+1);
		if(e == nil)
			return TkNomem;

		e->flag = 0;
		strcpy(e->text, tbuf);
		e->link = *el;
		*el = e;
		el = &e->link;
		e->width = stringwidth(tk->env->font, e->text)+2*(Listpadx+l->sborderwidth+tk->highlightwidth);
		if(e->width > l->nwidth)
			l->nwidth = e->width;
		l->nitem++;
	}

	if(tbuf != buf)
		free(tbuf);

	tklistbgeom(tk);
	tk->dirty = tkrect(tk, 1);
	return nil;
}

int
tklistbrange(Tk *tk, char *arg, int *s, int *e)
{
	char buf[Tkmaxitem];

	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	*s = tklindex(tk, buf);
	if(*s == -1)
		return -1;
	*e = *s;
	if(*arg == '\0')
		return 0;

	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	*e = tklindex(tk, buf);
	if(*e == -1)
		return -1;
	return 0;
}

char*
tklistbselection(Tk *tk, char *arg, char **val)
{
	TkTop *t;
	TkLentry *f;
	TkListbox *l;
	int s, e, indx;
	char buf[Tkmaxitem];

	l = TKobj(TkListbox, tk);

	t = tk->env->top;
	arg = tkword(t, arg, buf, buf+sizeof(buf), nil);
	if(strcmp(buf, "includes") == 0) {
		tkword(t, arg, buf, buf+sizeof(buf), nil);
		indx = tklindex(tk, buf);
		if(indx == -1)
			return TkBadix;
		for(f = l->head; f && indx > 0; f = f->link)
			indx--;
		s = 0;
		if(f && (f->flag&Tkactivated))
			s = 1;
		return tkvalue(val, "%d", s);
	}

	if(strcmp(buf, "anchor") == 0) {
		tkword(t, arg, buf, buf+sizeof(buf), nil);
		indx = tklindex(tk, buf);
		if(indx == -1)
			return TkBadix;
		for(f = l->head; f && indx > 0; f = f->link)
			indx--;
		if(f != nil)
			l->anchor = f;
		return nil;
	}
	indx = 0;
	if(strcmp(buf, "clear") == 0) {
		if(tklistbrange(tk, arg, &s, &e) != 0)
			return TkBadix;
		for(f = l->head; f; f = f->link) {
			if(indx <= e && indx++ >= s)
				f->flag &= ~Tkactivated;
		}
		tk->dirty = tkrect(tk, 1);
		return nil;
	}
	if(strcmp(buf, "set") == 0) {
		if(tklistbrange(tk, arg, &s, &e) != 0)
			return TkBadix;
		for(f = l->head; f; f = f->link) {
			if(indx <= e && indx++ >= s)
				f->flag |= Tkactivated;
		}
		tk->dirty = tkrect(tk, 1);
		return nil;
	}
	return TkBadcm;
}

char*
tklistbdelete(Tk *tk, char *arg, char **val)
{
	TkLentry *e, **el;
	int start, end, indx, bh;
	TkListbox *l = TKobj(TkListbox, tk);

	USED(val);
	if(tklistbrange(tk, arg, &start, &end) != 0)
		return TkBadix;

	indx = 0;
	el = &l->head;
	for(e = l->head; e && indx < start; e = e->link) {
		indx++;
		el = &e->link;
	}
	while(e != nil && indx <= end) {
		*el = e->link;
		if(e->width == l->nwidth)
			l->nwidth = 0;
		if (e == l->anchor)
			l->anchor = nil;
		if (e == l->active)
			l->active = nil;
		free(e);
		e = *el;
		indx++;
		l->nitem--;
	}
	if(l->nwidth == 0) {
		for(e = l->head; e; e = e->link)
			if(e->width > l->nwidth)
				l->nwidth = e->width;
	}
	bh = tk->act.height/lineheight(tk);	/* Box height */
	if(l->yelem + bh > l->nitem)
		l->yelem = l->nitem - bh;
	if(l->yelem < 0)
		l->yelem = 0;

	tklistbgeom(tk);
	tk->dirty = tkrect(tk, 1);
	return nil;
}

char*
tklistbget(Tk *tk, char *arg, char **val)
{
	TkLentry *e;
	char *r, *fmt;
	int start, end, indx;
	TkListbox *l = TKobj(TkListbox, tk);

	if(tklistbrange(tk, arg, &start, &end) != 0)
		return TkBadix;

	indx = 0;
	for(e = l->head; e && indx < start; e = e->link)
		indx++;
	fmt = "%s";
	while(e != nil && indx <= end) {
		r = tkvalue(val, fmt, e->text);
		if(r != nil)
			return r;
		indx++;
		fmt = " %s";
		e = e->link;
	}
	return nil;		
}

char*
tklistbcursel(Tk *tk, char *arg, char **val)
{
	int indx;
	TkLentry *e;
	char *r, *fmt;
	TkListbox *l = TKobj(TkListbox, tk);

	USED(arg);
	indx = 0;
	fmt = "%d";
	for(e = l->head; e; e = e->link) {
		if(e->flag & Tkactivated) {
			r = tkvalue(val, fmt, indx);
			if(r != nil)
				return r;
			fmt = " %d";
		}
		indx++;
	}
	return nil;		
}

static char*
tklistbview(Tk *tk, char *arg, char **val, int nl, int *posn, int max)
{
	int top, bot, amount;
	char buf[Tkmaxitem];
	char *v, *e;

	top = 0;
	if(*arg == '\0') {
		if ( max <= nl || max == 0 ) {	/* Double test redundant at
						 * this time, but want to
						 * protect against future
						 * calls. -- DBK */
			top = 0;
			bot = TKI2F(1);
		}
		else {
			top = TKI2F(*posn)/max;
			bot = TKI2F(*posn+nl)/max;
		}
		v = tkfprint(buf, top);
		*v++ = ' ';
		tkfprint(v, bot);
		return tkvalue(val, "%s", buf);
	}

	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if(strcmp(buf, "moveto") == 0) {
		e = tkfracword(tk->env->top, &arg, &top, nil);
		if (e != nil)
			return e;
		*posn = TKF2I((top+1)*max);
	}
	else
	if(strcmp(buf, "scroll") == 0) {
		arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
		amount = atoi(buf);
		tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
		if(buf[0] == 'p')		/* Pages */
			amount *= nl;
		*posn += amount;
	}
	else {
		top = tklindex(tk, buf);
		if(top == -1)
			return TkBadix;
		*posn = top;
	}

	bot = max - nl;
	if(*posn > bot)
		*posn = bot;
	if(*posn < 0)
		*posn = 0;

	tk->dirty = tkrect(tk, 1);
	return nil;
}

static int
entrysee(Tk *tk, int index)
{
	TkListbox *l = TKobj(TkListbox, tk);
	int bh;

	/* Box height in lines */
	bh = tk->act.height/lineheight(tk);
	if (bh > l->nitem)
		bh = l->nitem;
	if (index >= l->nitem)
		index = l->nitem -1;
	if (index < 0)
		index = 0;

	/* If the item is already visible, do nothing */
	if (l->nitem == 0 || index >= l->yelem && index < l->yelem+bh)
		return index;

	if (index < l->yelem)
		l->yelem = index;
	else
		l->yelem = index - (bh-1);

	tklistsv(tk);
	tk->dirty = tkrect(tk, 1);
	return index;
}

char*
tklistbsee(Tk *tk, char *arg, char **val)
{
	int index;
	char buf[Tkmaxitem];

	USED(val);
	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	index = tklindex(tk, buf);
	if(index == -1)
		return TkBadix;

	entrysee(tk, index);
	return nil;
}

char*
tklistbyview(Tk *tk, char *arg, char **val)
{
	int bh;
	char *e;
	TkListbox *l = TKobj(TkListbox, tk);

	bh = tk->act.height/lineheight(tk);	/* Box height */
	e = tklistbview(tk, arg, val, bh, &l->yelem, l->nitem);
	tklistsv(tk);
	return e;
}

char*
tklistbxview(Tk *tk, char *arg, char **val)
{
	char *e;
	TkListbox *l = TKobj(TkListbox, tk);

	e = tklistbview(tk, arg, val, tk->act.width, &l->xdelta, l->nwidth);
	tklistsh(tk);
	return e;
}

static TkLentry*
entryset(TkListbox *l, int indx, int toggle)
{
	TkLentry *e, *anchor;

	anchor = nil;
	for(e = l->head; e; e = e->link) {
		if (indx-- == 0) {
			anchor = e;
			if (toggle) {
				e->flag ^= Tkactivated;
				break;
			} else
				e->flag |= Tkactivated;
			continue;
		}
		if (!toggle)
			e->flag &= ~Tkactivated;
	}
	return anchor;
}

static void
selectto(TkListbox *l, int indx)
{
	TkLentry *e;
	int inrange;

	if (l->anchor == nil)
		return;
	inrange = 0;
	for(e = l->head; e; e = e->link) {
		if(indx == 0)
			inrange = !inrange;
		if(e == l->anchor)
			inrange = !inrange;
		if(inrange || e == l->anchor || indx == 0)
			e->flag |= Tkactivated;
		else
			e->flag &= ~Tkactivated;
		indx--;
	}
}

static char*
dragto(Tk *tk, int y)
{
	int indx;
	TkLentry *e;
	TkListbox *l = TKobj(TkListbox, tk);

	indx = y/lineheight(tk);
	if (y < 0)
		indx--;	/* int division rounds towards 0 */
	if (y < tk->act.height && indx >= l->nitem)
		return nil;
	indx = entrysee(tk, l->yelem+indx);
	entryactivate(tk, indx);

	if(l->selmode == TKsingle || l->selmode == TKmultiple)
		return nil;

	if(l->selmode == TKbrowse) {
		for(e = l->head; e; e = e->link) {
			if(indx-- == 0) {
				if (e == l->anchor)
					return nil;
				l->anchor = e;
				e->flag |= Tkactivated;
			} else
				e->flag &= ~Tkactivated;
		}
		return nil;
	}
	/* extended selection mode */
	selectto(l, indx);
	tk->dirty = tkrect(tk, 1);
	return nil;
}

static void
autoselect(Tk *tk, void *v, int cancelled)
{
	Point pt;
	int y, eh, ne;

	USED(v);
	if (cancelled)
		return;

	pt = tkposn(tk);
	pt.y += tk->borderwidth;
	y = tk->env->top->ctxt->mstate.y;
	y -= pt.y;
	eh = lineheight(tk);
	ne = tk->act.height/eh;
	if (y >= 0 && y < eh*ne)
		return;
	dragto(tk, y);
	tkdirty(tk);
	tkupdate(tk->env->top);
}

static char*
tklistbbutton1p(Tk *tk, char *arg, char **val)
{
	TkListbox *l = TKobj(TkListbox, tk);
	int y, indx;

	USED(val);

	y = atoi(arg);
	indx = y/lineheight(tk);
	indx += l->yelem;
	if (indx < l->nitem) {
		l->anchor = entryset(l, indx, l->selmode == TKmultiple);
		entryactivate(tk, indx);
		entrysee(tk, indx);
	}
	tkrepeat(tk, autoselect, nil, TkRptpause, TkRptinterval);
	return nil;
}

char *
tklistbbutton1r(Tk *tk, char *arg, char **val)
{
	USED(arg);
	USED(val);
	tkcancelrepeat(tk);
	return nil;
}

char*
tklistbbutton1m(Tk *tk, char *arg, char **val)
{
	int y, eh, ne;
	USED(val);

	eh = lineheight(tk);
	ne = tk->act.height/eh;
	y = atoi(arg);
	/* If outside the box, let autoselect handle it */
	if (y < 0 || y >= ne * eh)
		return nil;
	return dragto(tk, y);
}

char*
tklistbkey(Tk *tk, char *arg, char **val)
{
	TkListbox *l = TKobj(TkListbox, tk);
	TkLentry *e;
	int key, active;
	USED(val);

	if(tk->flag & Tkdisabled)
		return nil;

	key = atoi(arg);
	active = 0;
	for (e = l->head; e != nil; e = e->link) {
		if (e->flag & Tkactive)
			break;
		active++;
	}

	if (key == '\n' || key == ' ') {
		l->anchor = entryset(l, active, l->selmode == TKmultiple);
		tk->dirty = tkrect(tk, 0);
		return nil;
	}
	if (key == Up)
		active--;
	else if (key == Down)
		active++;
	else
		return nil;

	if (active < 0)
		active = 0;
	if (active >= l->nitem)
		active = l->nitem-1;
	entryactivate(tk, active);
	if (l->selmode == TKextended) {
		selectto(l, active);
		tk->dirty = tkrect(tk, 0);
	}
	entrysee(tk, active);
	return nil;
}

static
TkCmdtab tklistcmd[] =
{
	"activate",		tklistbactivate,
	"cget",			tklistbcget,
	"configure",		tklistbconf,
	"curselection",		tklistbcursel,
	"delete",		tklistbdelete,
	"get",			tklistbget,
	"index",		tklistbindex,
	"insert",		tklistbinsert,
	"nearest",		tklistbnearest,
	"selection",		tklistbselection, 
	"see",			tklistbsee,
	"size",			tklistbsize,
	"xview",		tklistbxview,
	"yview",		tklistbyview,
	"tkListbButton1P",	tklistbbutton1p,
	"tkListbButton1R",	tklistbbutton1r,
	"tkListbButton1MP",	tklistbbutton1m,
	"tkListbKey",	tklistbkey,
	nil
};

TkMethod listboxmethod = {
	"listbox",
	tklistcmd,
	tkfreelistb,
	tkdrawlistb,
	tklistbgeom
};
