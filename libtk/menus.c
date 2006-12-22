#include "lib9.h"
#include "draw.h"
#include "keyboard.h"
#include "tk.h"
#include "frame.h"
#include "label.h"

/*
arrow annotation for choicebutton: how do we make sure
the menu items come up the same size?
	- set menu items to same req.width & height as button itself.

autorepeat:
when we get mouse event at the edge of the screen
and the menu overlaps that edge,
start autorepeat timer to slide the menu the opposite direction.

variable setting + command invocation:
is the value of the variable the text or the index?
same for the value appended to the command, text or index?

if it's reimplemented as a custom widget, how does the custom widget
get notified of variable changes?
*/

/* Widget Commands (+ means implemented)
	+activate
	+add
	+cget
	+configure
	+delete
	+entrycget
	+entryconfigure
	+index
	+insert
	+invoke
	+post
	+postcascade
	+type
	+unpost
	+yposition
*/

#define	O(t, e)		((long)(&((t*)0)->e))

/* Layout constants */
enum {
	Sepheight	= 6,	/* Height of menu separator */
};

#define NOCHOICE "-----"

enum {
	Startspeed = TKI2F(1),
};

static
TkOption mbopts[] =
{
	"text",		OPTtext,	O(TkLabel, text),		nil,
	"anchor",	OPTflag,	O(TkLabel, anchor),	tkanchor,
	"underline",	OPTdist,	O(TkLabel, ul),		nil,
	"justify",	OPTstab,	O(TkLabel, justify),	tkjustify,
	"menu",		OPTtext,	O(TkLabel, menu),		nil,
	"bitmap",	OPTbmap,	O(TkLabel, bitmap),		nil,
	"image",	OPTimag,	O(TkLabel, img),		nil,
	nil
};

static
TkOption choiceopts[] =
{
	"variable",	OPTtext,	O(TkLabel, variable),	nil,
	"values",	OPTlist,	O(TkLabel, values), nil,
	"command", OPTtext, O(TkLabel, command), nil,
	nil
};

static
TkEbind mbbindings[] = 
{
	{TkEnter,		"%W tkMBenter %s"},
	{TkLeave,		"%W tkMBleave"},
	{TkButton1P,		"%W tkMBpress 1"},
	{TkKey,		"%W tkMBkey 0x%K"},
	{TkButton1P|TkMotion,	"%W tkMBpress 0"},
};

extern Rectangle bbnil;
static char* tkmpost(Tk*, int, int, int, int, int);
static void menuclr(Tk*);
static void freemenu(Tk*);
static void appenditem(Tk*, Tk*, int);
static void layout(Tk*);
static Tk* tkmenuindex2ptr(Tk*, char**);
static void activateitem(Tk*);

/*
 * unmap menu cascade upto (but not including) tk
 */
static void
tkunmapmenus(TkTop *top, Tk *tk)
{
	TkTop *t;
	Tk *menu;
	TkWin *tkw;

	menu = top->ctxt->tkmenu;
	if (menu == nil)
		return;
	t = menu->env->top;

	/* if something went wrong, clear down all menus */
	if (tk != nil && tk->env->top != t)
		tk = nil;

	while (menu != nil && menu != tk) {
		menuclr(menu);
		tkunmap(menu);
		tkcancelrepeat(menu);
		tkw = TKobj(TkWin, menu);
		if (tkw->cascade != nil) {
			menu = tklook(t, tkw->cascade, 0);
			free(tkw->cascade);
			tkw->cascade = nil;
		} else
			menu = nil;
	}
	top->ctxt->tkmenu = menu;
	tksetmgrab(top, menu);
}

static void
tkunmapmenu(Tk *tk)
{
	TkTop *t;
	TkWin *tkw;
	Tk *parent;

	parent = nil;
	tkw = TKobj(TkWin, tk);
	t = tk->env->top;
	if (tkw->cascade != nil)
		parent = tklook(t, tkw->cascade, 0);
	tkunmapmenus(t, parent);
	if (tkw->freeonunmap)
		freemenu(tk);
}

static void
tksizemenubutton(Tk *tk)
{
	int w, h;
	char **v, *cur;
	TkLabel *tkl = TKobj(TkLabel, tk);

	tksizelabel(tk);
	if (tk->type != TKchoicebutton)
		return;
	w = tk->req.width;
	h = tk->req.height;
	v = tkl->values;
	if (v == nil || *v == nil)
		return;
	cur = tkl->text;
	for (; *v; v++) {
		tkl->text = *v;
		tksizelabel(tk);
		if (tk->req.width > w)
			w = tk->req.width;
		if (tk->req.height > h)
			h = tk->req.height;
	}
	tkl->text = cur;
	tksizelabel(tk);
	tk->req.width = w;
	tk->req.height = h;
}

static char*
tkmkmenubutton(TkTop *t, char *arg, char **ret, int type, TkOption *opts)
{
	Tk *tk;
	char *e, **v;
	TkName *names;
	TkLabel *tkl;
	TkOptab tko[3];

/* need to get the label from elsewhere */
	tk = tknewobj(t, type, sizeof(Tk)+sizeof(TkLabel));
	if(tk == nil)
		return TkNomem;
	tk->borderwidth = 2;
	tk->flag |= Tknograb;

	tkl = TKobj(TkLabel, tk);
	tkl->ul = -1;
	if(type == TKchoicebutton)
		tkl->anchor = Tknorth|Tkwest;

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
	tkl->nvalues = 0;
	if (tkl->values != nil) {
		for (v = tkl->values; *v; v++)
			;
		tkl->nvalues = v - tkl->values;
	}
	if(type == TKchoicebutton){
		if(tkl->nvalues > 0)
			tkl->text = strdup(tkl->values[0]);
		else
			tkl->text = strdup(NOCHOICE);
	}
	tksettransparent(tk, 
		tkhasalpha(tk->env, TkCbackgnd) ||
		tkhasalpha(tk->env, TkCselectbgnd) ||
		tkhasalpha(tk->env, TkCactivebgnd));

	e = tkbindings(t, tk, mbbindings, nelem(mbbindings));

	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}
	tksizemenubutton(tk);

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
tkchoicebutton(TkTop *t, char *arg, char **ret)
{
	return tkmkmenubutton(t, arg, ret, TKchoicebutton, choiceopts);
}

char*
tkmenubutton(TkTop *t, char *arg, char **ret)
{
	return tkmkmenubutton(t, arg, ret, TKmenubutton, mbopts);
}

static char*
tkmenubutcget(Tk *tk, char *arg, char **val)
{
	TkOptab tko[3];
	TkLabel *tkl = TKobj(TkLabel, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkl;
	tko[1].optab = (tk->type == TKchoicebutton ? choiceopts : mbopts);
	tko[2].ptr = nil;

	return tkgencget(tko, arg, val, tk->env->top);
}

static char*
tkmenubutconf(Tk *tk, char *arg, char **val)
{
	char *e, **v;
	TkGeom g;
	int bd;
	TkOptab tko[3];
	TkLabel *tkl = TKobj(TkLabel, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkl;
	tko[1].optab = (tk->type == TKchoicebutton ? choiceopts : mbopts);
	tko[2].ptr = nil;

	if(*arg == '\0')
		return tkconflist(tko, val);

	g = tk->req;
	bd = tk->borderwidth;
	e = tkparse(tk->env->top, arg, tko, nil);

	if (tk->type == TKchoicebutton) {
		tkl->nvalues = 0;
		if (tkl->values != nil) {
			for (v = tkl->values; *v; v++)
				;
			tkl->nvalues = v - tkl->values;
		}
		if (tkl->check >= tkl->nvalues || strcmp(tkl->text, tkl->values[tkl->check])) {
			/*
			 * try to keep selected value the same if possible
			 */
			for (v = tkl->values; v && *v; v++)
				if (!strcmp(*v, tkl->text))
					break;
			free(tkl->text);
			if (v == nil || *v == nil) {
				tkl->text = strdup(tkl->nvalues > 0 ? tkl->values[0] : NOCHOICE);
				tkl->check = 0;
			} else {
				tkl->check = v - tkl->values;
				tkl->text = strdup(*v);
			}
		}
	}
	tksettransparent(tk, 
		tkhasalpha(tk->env, TkCbackgnd) ||
		tkhasalpha(tk->env, TkCselectbgnd) ||
		tkhasalpha(tk->env, TkCactivebgnd));
	tksizemenubutton(tk);
	tkgeomchg(tk, &g, bd);

	tk->dirty = tkrect(tk, 1);
	return e;
}

static char*
tkMBleave(Tk *tk, char *arg, char **val)
{
	USED(arg);
	USED(val);

	tk->flag &= ~Tkactive;
	tk->dirty = tkrect(tk, 1);
	return nil;
}

static Tk*
mkchoicemenu(Tk *tkb)
{
	Tk *menu, *tkc;
	int i;
	TkLabel *tkl, *tkcl;
	TkWin *tkw;
	TkTop *t;

	tkl = TKobj(TkLabel, tkb);
	t = tkb->env->top;

	menu = tknewobj(t, TKmenu, sizeof(Tk)+sizeof(TkWin));
	if(menu == nil)
		return nil;

	menu->relief = TKraised;
	menu->flag |= Tknograb;
	menu->borderwidth = 2;
	tkputenv(menu->env);
	menu->env = tkb->env;
	menu->env->ref++;

	menu->flag |= Tkwindow;
	menu->geom = tkmoveresize;
	tkw = TKobj(TkWin, menu);
	tkw->cbname = strdup(tkb->name->name);
	tkw->di = (void*)-1;			// XXX

	for(i = tkl->nvalues - 1; i >= 0; i--){
		tkc = tknewobj(t, TKlabel, sizeof(Tk)+sizeof(TkLabel));
		/* XXX recover from malloc failure */
		tkc->flag = Tkwest|Tkfillx|Tktop;
		tkc->highlightwidth = 0;
		tkc->borderwidth = 1;
		tkc->relief = TKflat;
		tkputenv(tkc->env);
		tkc->env = tkb->env;
		tkc->env->ref++;
		tkcl = TKobj(TkLabel, tkc);
		tkcl->anchor = Tkwest;
		tkcl->ul = -1;
		tkcl->justify = Tkleft;
		tkcl->text = strdup(tkl->values[i]);
		tkcl->command = smprint("%s invoke %d", tkb->name->name, i);
		/* XXX recover from malloc failure */
		tksizelabel(tkc);
		tkc->req.height = tkb->req.height;
		appenditem(menu, tkc, 0);
	}
	layout(menu);

	tkw->next = t->windows;
	tkw->freeonunmap = 1;
	t->windows = menu;
	return menu;
}

static char*
tkMBpress(Tk *tk, char *arg, char **val)
{
	Tk *menu, *item;
	TkLabel *tkl = TKobj(TkLabel, tk);
	Point g;
	char buf[12], *bufp, *e;

	USED(arg);
	USED(val);

	g = tkposn(tk);
	if (tk->type == TKchoicebutton) {
		menu = mkchoicemenu(tk);
		if (menu == nil)
			return TkNomem;
		sprint(buf, "%d", tkl->check);
		bufp = buf;
		item = tkmenuindex2ptr(menu, &bufp);
		if(item == nil)
			return nil;
		g.y -= item->act.y;
		e = tkmpost(menu, g.x, g.y, 0, 0, 0);
		activateitem(item);
		return e;
	} else {
		if (tkl->menu == nil)
			return nil;
		menu = tklook(tk->env->top, tkl->menu, 0);
		if(menu == nil || menu->type != TKmenu)
			return TkBadwp;

		if(menu->flag & Tkmapped) {
			if(atoi(arg))
				tkunmapmenu(menu);
			return nil;
		}
		return tkmpost(menu, g.x, g.y, 0, tk->act.height + 2*tk->borderwidth, 1);
	}
}

static char*
tkMBkey(Tk *tk, char *arg, char **val)
{
	int key;
	USED(val);

	if(tk->flag & Tkdisabled)
		return nil;

	key = atoi(arg);
	if (key == '\n' || key == ' ')
		return tkMBpress(tk, "1", nil);
	return nil;
}

static char*
tkMBenter(Tk *tk, char *arg, char **val)
{
	USED(arg);
	USED(val);

	tk->flag |= Tkactive;
	tk->dirty = tkrect(tk, 1);
	return nil;
}

static char*
tkchoicebutset(Tk *tk, char *arg, char **val)
{
	char buf[12], *e;
	int v;
	TkLabel *tkl = TKobj(TkLabel, tk);

	USED(val);

	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if (*buf == '\0')
		return TkBadvl;
	v = atoi(buf);
	if (v < 0 || v >= tkl->nvalues)
		return TkBadvl;
	if (v == tkl->check)
		return nil;
	free(tkl->text);
	tkl->text = strdup(tkl->values[v]);
	/* XXX recover from malloc error */
	tkl->check = v;

	sprint(buf, "%d", v);
	e = tksetvar(tk->env->top, tkl->variable, buf);
	if(e != nil)
		return e;

	tk->dirty = tkrect(tk, 1);
	return nil;
}

static char*
tkchoicebutinvoke(Tk *tk, char *arg, char **val)
{
	TkLabel *tkl = TKobj(TkLabel, tk);
	char *e;

	e = tkchoicebutset(tk, arg, val);
	if(e != nil)
		return e;
	if(tkl->command)
		return tkexec(tk->env->top, tkl->command, val);
	return nil;
}

static char*
tkchoicebutgetvalue(Tk *tk, char *arg, char **val)
{
	char buf[12];
	int gotarg, v;
	TkLabel *tkl = TKobj(TkLabel, tk);
	if (tkl->nvalues == 0)
		return nil;
	tkword(tk->env->top, arg, buf, buf+sizeof(buf), &gotarg);
	if (!gotarg)
		return tkvalue(val, "%s", tkl->values[tkl->check]);
	v = atoi(buf);
	if (buf[0] < '0' || buf[0] > '9' || v >= tkl->nvalues)
		return TkBadvl;
	return tkvalue(val, "%s", tkl->values[tkl->check]);
}

static char*
tkchoicebutsetvalue(Tk *tk, char *arg, char **val)
{
	char *buf;
	char **v;
	int gotarg;
	TkLabel *tkl = TKobj(TkLabel, tk);

	USED(val);
	if (tkl->nvalues == 0)
		return TkBadvl;
	buf = mallocz(Tkmaxitem, 0);
	if (buf == nil)
		return TkNomem;
	tkword(tk->env->top, arg, buf, buf+Tkmaxitem, &gotarg);
	if (!gotarg) {
		free(buf);
		return TkBadvl;
	}
	for (v = tkl->values; *v; v++)
		if (strcmp(*v, buf) == 0)
			break;
	free(buf);
	if (*v == nil)
		return TkBadvl;
	free(tkl->text);
	tkl->text = strdup(*v);
	/* XXX recover from malloc error */
	tkl->check = v - tkl->values;

	tk->dirty = tkrect(tk, 1);
	return nil;
}

static char*
tkchoicebutget(Tk *tk, char *arg, char **val)
{
	TkLabel *tkl = TKobj(TkLabel, tk);
	char *buf, **v;
	int gotarg;
	
	if (tkl->nvalues == 0)
		return nil;
	buf = mallocz(Tkmaxitem, 0);
	if (buf == nil)
		return TkNomem;
	tkword(tk->env->top, arg, buf, buf+Tkmaxitem, &gotarg);
	if (!gotarg) {
		free(buf);
		return tkvalue(val, "%d", tkl->check);
	}

	for (v = tkl->values; *v; v++)
		if (strcmp(*v, buf) == 0)
			break;
	free(buf);
	if (*v)
		return tkvalue(val, "%d", v - tkl->values);
	return nil;
}

static char*
tkchoicebutvaluecount(Tk *tk, char *arg, char **val)
{
	TkLabel *tkl = TKobj(TkLabel, tk);
	USED(arg);
	return tkvalue(val, "%d", tkl->nvalues);
}


static void
tkchoicevarchanged(Tk *tk, char *var, char *value)
{
	TkLabel *tkl = TKobj(TkLabel, tk);
	int v;

	if(tkl->variable != nil && strcmp(tkl->variable, var) == 0){
		if(value[0] < '0' || value[0] > '9')
			return;
		v = atoi(value);
		if(v < 0 || v > tkl->nvalues)
			return;		/* what else can we do? */
		free(tkl->text);
		tkl->text = strdup(tkl->values[v]);
		/* XXX recover from malloc error */
		tkl->check = v;
		tk->dirty = tkrect(tk, 0);
		tkdirty(tk);
	}
}

Tk *
tkfindchoicemenu(Tk *tkb)
{
	Tk *tk, *next;
	TkTop *top;
	TkWin *tkw;

	top = tkb->env->top;
	for (tk = top->windows; tk != nil; tk = next){
		tkw = TKobj(TkWin, tk);
		if(tk->name == nil){
			assert(strcmp(tkw->cbname, tkb->name->name) == 0);
			return tk;
		}
		next = tkw->next;
	}
	return nil;
}

static
TkOption menuopt[] =
{
	"postcommand",	OPTtext,	O(TkWin, postcmd),		nil,
	nil,
};

char*
tkmenu(TkTop *t, char *arg, char **ret)
{
	Tk *tk;
	char *e;
	TkWin *tkw;
	TkName *names;
	TkOptab tko[3];

	tk = tknewobj(t, TKmenu, sizeof(Tk)+sizeof(TkWin));
	if(tk == nil)
		return TkNomem;

	tkw = TKobj(TkWin, tk);
	tkw->di = (void*)-1;		// XXX
	tk->relief = TKraised;
	tk->flag |= Tknograb;
	tk->borderwidth = 2;

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkw;
	tko[1].optab = menuopt;
	tko[2].ptr = nil;

	names = nil;
	e = tkparse(t, arg, tko, &names);
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

	tk->flag |= Tkwindow;
	tk->geom = tkmoveresize;

	tkw->next = t->windows;
	t->windows = tk;

	return tkvalue(ret, "%s", tk->name->name);
}

static void
freemenu(Tk *top)
{
	Tk *tk, *f, *nexttk, *nextf;
	TkWin *tkw;

	tkunmapmenu(top);
	tkw = TKobj(TkWin, top);
	for(tk = tkw->slave; tk; tk = nexttk) {
		nexttk = tk->next;
		for(f = tk->slave; f; f = nextf) {
			nextf = f->next;
			tkfreeobj(f);
		}
		tkfreeobj(tk);
	}
	top->slave = nil;
	tkfreeframe(top);
}

static
TkOption mopt[] =
{
	"menu",		OPTtext,	O(TkLabel, menu),		nil,
	nil,
};

static void
tkbuildmopt(TkOptab *tko, int n, Tk *tk)
{
	memset(tko, 0, n*sizeof(TkOptab));

	n = 0;
	tko[n].ptr = tk;
	tko[n++].optab = tkgeneric;

	switch(tk->type) {
	case TKcascade:
		tko[n].ptr = TKobj(TkLabel, tk);
		tko[n++].optab = mopt;
		goto norm;
	case TKradiobutton:	
		tko[n].ptr = TKobj(TkLabel, tk);
		tko[n++].optab = tkradopts;
		goto norm;
	case TKcheckbutton:
		tko[n].ptr = TKobj(TkLabel, tk);
		tko[n++].optab = tkcbopts;
		/* fall through */
	case TKlabel:
	norm:
		tko[n].ptr = TKobj(TkLabel, tk);
		tko[n].optab = tkbutopts;
		break;	
	}
}

static char*
tkmenuentryconf(Tk *menu, Tk *tk, char *arg)
{
	char *e;
	TkOptab tko[4];

	USED(menu);

	tkbuildmopt(tko, nelem(tko), tk);
	e = tkparse(tk->env->top, arg, tko, nil);
	switch (tk->type) {
	case TKlabel:
	case TKcascade:
		tksizelabel(tk);
		break;
	case TKradiobutton:
	case TKcheckbutton:
		tksizebutton(tk);
	}

	return e;
}

static void
layout(Tk *menu)
{
	TkWin *tkw;
	Tk *tk;
	int m, w, y, maxmargin, maxw;

	y = 0;
	maxmargin = 0;
	maxw = 0;

	tkw = TKobj(TkWin, menu);

	/* determine padding for item text alignment */
	for (tk = tkw->slave; tk != nil; tk = tk->next) {
		m = tklabelmargin(tk);
		tk->act.x = m;		/* temp store */
		if (m > maxmargin)
			maxmargin = m;
	}
	/* set x pos and determine max width */
	for (tk = tkw->slave; tk != nil; tk = tk->next) {
		tk->act.x = tk->borderwidth + maxmargin - tk->act.x;
		tk->act.y = y + tk->borderwidth;
		tk->act.height = tk->req.height;
		tk->act.width = tk->req.width;
		y += tk->act.height+2*tk->borderwidth;
		w = tk->act.x + tk->req.width + 2* tk->borderwidth;
		if (w > maxw)
			maxw = w;
	}
	/* expand separators and cascades and mark all as dirty */
	for (tk = tkw->slave; tk != nil; tk = tk->next) {
		switch (tk->type) {
		case TKseparator:
			tk->act.x = tk->borderwidth;
			/*FALLTHRU*/
		case TKcascade:
			tk->act.width = (maxw - tk->act.x) - tk->borderwidth;
		}
		tk->dirty = tkrect(tk, 1);
	}
	menu->dirty = tkrect(menu, 1);
	tkmoveresize(menu, 0, 0, maxw, y);
}

static void
menuitemgeom(Tk *sub, int x, int y, int w, int h)
{
	if (sub->parent == nil)
		return;
	if(w < 0)
		w = 0;
	if(h < 0)
		h = 0;
	sub->req.x = x;
	sub->req.y = y;
	sub->req.width = w;
	sub->req.height = h;
	layout(sub->parent);
}

static void
appenditem(Tk *menu, Tk *item, int where)
{
	TkWin *tkw;
	Tk *f, **l;

	tkw = TKobj(TkWin, menu);
	l = &tkw->slave;
	for (f = *l; f != nil; f = f->next) {
		if (where-- == 0)
			break;
		l = &f->next;
	}
	*l = item;
	item->next = f;
	item->parent = menu;
	item->geom = menuitemgeom;
}

static char*
menuadd(Tk *menu, char *arg, int where)
{
	Tk *tkc;
	int configure;
	char *e;
	TkTop *t;
	TkLabel *tkl;
	char buf[Tkmaxitem];
	
	t = menu->env->top;
	arg = tkword(t, arg, buf, buf+sizeof(buf), nil);
	configure = 1;
	e = nil;

	if(strcmp(buf, "checkbutton") == 0)
		tkc = tkmkbutton(t, TKcheckbutton);
	else if(strcmp(buf, "radiobutton") == 0)
		tkc = tkmkbutton(t, TKradiobutton);
	else if(strcmp(buf, "command") == 0)
		tkc = tknewobj(t, TKlabel, sizeof(Tk)+sizeof(TkLabel));
	else if(strcmp(buf, "cascade") == 0)
		tkc = tknewobj(t, TKcascade, sizeof(Tk)+sizeof(TkLabel));
	else if(strcmp(buf, "separator") == 0) {
		tkc = tknewobj(t, TKseparator, sizeof(Tk));	/* it's really a frame */
		if (tkc != nil) {
			tkc->flag = Tkfillx|Tktop;
			tkc->req.height = Sepheight;
			configure = 0;
		}
	}
	else
		return TkBadvl;

	if (tkc == nil)
		e = TkNomem;

	if (e == nil) {
		if(tkc->env == t->env && menu->env != t->env) {
			tkputenv(tkc->env);
			tkc->env = menu->env;
			tkc->env->ref++;
		}
		if (configure) {
			tkc->flag = Tkwest|Tkfillx|Tktop;
			tkc->highlightwidth = 0;
			tkc->borderwidth = 1;
			tkc->relief = TKflat;
			tkl = TKobj(TkLabel, tkc);
			tkl->anchor = Tkwest;
			tkl->ul = -1;
			tkl->justify = Tkleft;
			e = tkmenuentryconf(menu, tkc, arg);
		}
	}

	if(e != nil) {
		if (tkc != nil)
			tkfreeobj(tkc);
		return e;
	}	

	appenditem(menu, tkc, where);
	layout(menu);
	return nil;
}

static int
tkmindex(Tk *tk, char *p)
{
	TkWin *tkw;
	int y, n;

	if(*p >= '0' && *p <= '9')
		return atoi(p);

	tkw = TKobj(TkWin, tk);
	n = 0;
	if(*p == '@') {
		y = atoi(p+1);
		for(tk = tkw->slave; tk; tk = tk->next) {
			if(y >= tk->act.y && y < tk->act.y+tk->act.height+2*tk->borderwidth )
				return n;
			n++;
		}
	}
	if(strcmp(p, "end") == 0 || strcmp(p, "last") == 0) {
		for(tk = tkw->slave; tk && tk->next; tk = tk->next)
			n++;
		return n;
	}
	if(strcmp(p, "active") == 0) {
		for(tk = tkw->slave; tk; tk = tk->next) {
			if(tk->flag & Tkactive)
				return n;
			n++;
		}
		return -2;
	}
	if(strcmp(p, "none") == 0)
		return -2;

	return -1;
}

static int
tkmenudel(Tk *tk, int y)
{
	TkWin *tkw;
	Tk *f, **l, *next;

	tkw = TKobj(TkWin, tk);
	l = &tkw->slave;
	for(tk = *l; tk; tk = tk->next) {
		if(y-- == 0) {
			*l = tk->next;
			for(f = tk->slave; f; f = next) {
				next = f->next;
				tkfreeobj(f);
			}
			tkfreeobj(tk);
			return 1;
		}
		l = &tk->next;
	}
	return 0;	
}

static char*
tkmpost(Tk *tk, int x, int y, int cascade, int bh, int adjust)
{
	char *e;
	TkWin *w;
	TkTop *t;
	Rectangle *dr;

	t = tk->env->top;
	if(adjust){
		dr = &t->screenr;
		if(x+tk->act.width > dr->max.x)
			x = dr->max.x - tk->act.width;
		if(x < 0)
			x = 0;
		if(y+bh+tk->act.height > dr->max.y)
			y -= tk->act.height + 2* tk->borderwidth;
		else
			y += bh;
		if(y < 0)
			y = 0;
	}
	menuclr(tk);
	tkmovewin(tk, Pt(x, y));

	/* stop possible postcommand recursion */
	if (tk->flag & Tkmapped)
		return nil;

	w = TKobj(TkWin, tk);
	if(w->postcmd != nil) {
		e = tkexec(tk->env->top, w->postcmd, nil);
		if(e != nil) {
			print("%s: postcommand: %s: %s\n", tkname(tk), w->postcmd, e);
			return e;
		}
	}
	if (!cascade)
		tkunmapmenus(t, nil);

	e = tkmap(tk);
	if(e != nil)
		return e;

	if (t->ctxt->tkmenu != nil)
		w->cascade = strdup(t->ctxt->tkmenu->name->name);
	t->ctxt->tkmenu = tk;
	tksetmgrab(t, tk);

	/* Make sure slaves are redrawn */
	return tkupdate(tk->env->top);
}

static Tk*
tkmenuindex2ptr(Tk *tk, char **arg)
{
	TkWin *tkw;
	int index;
	char *buf;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return nil;
	*arg = tkword(tk->env->top, *arg, buf, buf+Tkmaxitem, nil);
	index = tkmindex(tk, buf);
	free(buf);
	if(index < 0)
		return nil;

	tkw = TKobj(TkWin, tk);
	for(tk = tkw->slave; tk && index; tk = tk->next)
		index--;

	if(tk == nil)
		return nil;

	return tk;
}

static char*
tkmenuentrycget(Tk *tk, char *arg, char **val)
{
	Tk *etk;
	TkOptab tko[4];

	etk = tkmenuindex2ptr(tk, &arg);
	if(etk == nil)
		return TkBadix;

	tkbuildmopt(tko, nelem(tko), etk);
	return tkgencget(tko, arg, val, tk->env->top);
}

static char*
tkmenucget(Tk *tk, char *arg, char **val)
{
	TkWin *tkw;
	TkOptab tko[4];

	tkw = TKobj(TkWin, tk);
	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkw;
	tko[1].optab = tktop;
	tko[2].ptr = tkw;
	tko[2].optab = menuopt;
	tko[3].ptr = nil;

	return tkgencget(tko, arg, val, tk->env->top);
}

static char*
tkmenuconf(Tk *tk, char *arg, char **val)
{
	char *e;
	TkGeom g;
	int bd;
	TkWin *tkw;
	TkOptab tko[3];

	tkw = TKobj(TkWin, tk);
	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkw;
	tko[1].optab = menuopt;
	tko[2].ptr = nil;

	if(*arg == '\0')
		return tkconflist(tko, val);

	g = tk->req;
	bd = tk->borderwidth;
	e = tkparse(tk->env->top, arg, tko, nil);
	tkgeomchg(tk, &g, bd);
	tk->dirty = tkrect(tk, 1);
	return e;
}

static char*
tkmenuadd(Tk *tk, char *arg, char **val)
{
	USED(val);
	return menuadd(tk, arg, -1);	
}

static char*
tkmenuinsert(Tk *tk, char *arg, char **val)
{
	int index;
	char *buf;

	USED(val);
	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	arg = tkword(tk->env->top, arg, buf, buf+Tkmaxitem, nil);
	index = tkmindex(tk, buf);
	free(buf);
	if (index < 0)
		return TkBadix;
	return menuadd(tk, arg, index);
}

static void
menuitemdirty(Tk *item)
{
	Tk *menu;
	Rectangle r;

	menu = item->parent;
	if (menu == nil)
		return;
	item->dirty = tkrect(item, 1);
	r = rectaddpt(item->dirty, Pt(item->act.x, item->act.y));
	combinerect(&menu->dirty, r);
}

static void
menuclr(Tk *tk)
{
	TkWin *tkw;
	Tk *f;
	tkw = TKobj(TkWin, tk);
	for(f = tkw->slave; f; f = f->next) {
		if(f->flag & Tkactive) {
			f->flag &= ~Tkactive;
			menuitemdirty(f);
		}
	}
}

static char*
tkpostcascade(Tk *parent, Tk *tk, int toggle)
{
	Tk *tkm;
	TkWin *tkw;
	Point g;
	TkTop *t;
	TkLabel *tkl;
	char *e;

	if(tk->flag & Tkdisabled)
		return nil;

	tkl = TKobj(TkLabel, tk);
	t = tk->env->top;
	tkm = tklook(t, tkl->menu, 0);
	if(tkm == nil || tkm->type != TKmenu)
		return TkBadwp;

	if((tkm->flag & Tkmapped)) {
		if (toggle) {
			tkunmapmenus(t, parent);
			return nil;
		} else {
			/* check that it is immediate cascade */
			tkw = TKobj(TkWin, t->ctxt->tkmenu);
			if (strcmp(tkw->cascade, parent->name->name) == 0)
				return nil;
		}
	}

	tkunmapmenus(t, parent);

	tkl = TKobj(TkLabel, tk);
	if(tkl->command != nil) {
		e = tkexec(t, tkl->command, nil);
		if (e != nil)
			return e;
	}

	g = tkposn(tk);
	g.x += tk->act.width;
	g.y -= tkm->borderwidth;
	e = tkmpost(tkm, g.x, g.y, 1, 0, 1);
	return e;
}

static void
activateitem(Tk *item)
{
	Tk *menu;
	if (item == nil || (menu = item->parent) == nil)
		return;
	menuclr(menu);
	if (!(item->flag & Tkdisabled)) {
		item->flag |= Tkactive;
		menuitemdirty(item);
	}
}

static char*
tkmenuactivate(Tk *tk, char *arg, char **val)
{
	Tk *f;
	TkWin *tkw;
	int index;
	char *buf;
	
	USED(val);
	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	tkword(tk->env->top, arg, buf, buf+Tkmaxitem, nil);
	index = tkmindex(tk, buf);
	free(buf);
	if (index == -1)
		return TkBadix;
	if (index == -2) {
		menuclr(tk);
		return nil;
	}

	tkw = TKobj(TkWin, tk);
	for(f = tkw->slave; f; f = f->next)
		if(index-- == 0)
			break;

	if(f == nil || f->flag & Tkdisabled) {
		menuclr(tk);
		return nil;
	}
	if(f->flag & Tkactive)
		return nil;

	activateitem(f);
	return nil;
}

static int
iteminvoke(Tk *tk, Tk *tki, char *arg)
{
	int unmap = 0;
	menuitemdirty(tki);
	switch(tki->type) {
	case TKlabel:
		unmap = 1;
	case TKcheckbutton:
	case TKradiobutton:
		tkbuttoninvoke(tki, arg, nil);
		break;
	case TKcascade:
		tkpostcascade(tk, tki, 0);
		break;
	}
	return unmap;
}

static char*
tkmenuinvoke(Tk *tk, char *arg, char **val)
{
	Tk *tki;
	USED(val);
	tki = tkmenuindex2ptr(tk, &arg);
	if(tki == nil)
		return nil;
	iteminvoke(tk, tki, arg);
	return nil;
}

static char*
tkmenudelete(Tk *tk, char *arg, char **val)
{
	int index1, index2;
	char *buf;

	USED(val);
	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	arg = tkitem(buf, arg);
	index1 = tkmindex(tk, buf);
	if(index1 < 0) {
		free(buf);
		return TkBadix;
	}
	index2 = index1;
	if(*arg != '\0') {
		tkitem(buf, arg);
		index2 = tkmindex(tk, buf);
	}
	free(buf);
	if(index2 < 0)
		return TkBadix;
	while(index2 >= index1 && tkmenudel(tk, index2))
		index2--;

	layout(tk);
	return nil;
}

static char*
tkmenupost(Tk *tk, char *arg, char **val)
{
	int x, y;
	TkTop *t;
	char *buf;

	USED(val);

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	t = tk->env->top;
	arg = tkword(t, arg, buf, buf+Tkmaxitem, nil);
	if(buf[0] == '\0') {
		free(buf);
		return TkBadvl;
	}
	x = atoi(buf);
	tkword(t, arg, buf, buf+Tkmaxitem, nil);
	if(buf[0] == '\0') {
		free(buf);
		return TkBadvl;
	}
	y = atoi(buf);
	free(buf);

	return tkmpost(tk, x, y, 0, 0, 1);
}

static char*
tkmenuunpost(Tk *tk, char *arg, char **val)
{
	USED(arg);
	USED(val);
	tkunmapmenu(tk);
	return nil;
}

static char*
tkmenuindex(Tk *tk, char *arg, char **val)
{
	char *buf;
	int index;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	tkword(tk->env->top, arg, buf, buf+Tkmaxitem, nil);
	index = tkmindex(tk, buf);
	free(buf);
	if (index == -1)
		return TkBadix;
	if (index == -2)
		return "none";
	return tkvalue(val, "%d", index);
}

static char*
tkmenuyposn(Tk *tk, char *arg, char **val)
{
	tk = tkmenuindex2ptr(tk, &arg);
	if(tk == nil)
		return TkBadix;
	return tkvalue(val, "%d", tk->act.y);
}

static char*
tkmenupostcascade(Tk *tk, char *arg, char **val)
{
	Tk *tki;
	USED(val);
	tki = tkmenuindex2ptr(tk, &arg);
	if(tki == nil || tki->type != TKcascade)
		return nil;

	return tkpostcascade(tk, tki, 0);
}

static char*
tkmenutype(Tk *tk, char *arg, char **val)
{
	tk = tkmenuindex2ptr(tk, &arg);
	if(tk == nil)
		return TkBadix;

	return tkvalue(val, tk->type == TKlabel ? "command" : tkmethod[tk->type]->name);
}

static char*
tkmenususpend(Tk *tk, char *arg, char **val)
{
	USED(arg);
	USED(val);
	if(tk->type == TKchoicebutton){
		tk = tkfindchoicemenu(tk);
		if(tk == nil)
			return TkNotwm;
	}
	tk->flag |= Tksuspended;
	return nil;
}

static char*
tkmenuentryconfig(Tk *tk, char *arg, char **val)
{
	Tk *etk;
	char *e;

	USED(val);
	etk = tkmenuindex2ptr(tk, &arg);
	if(etk == nil)
		return TkBadix;

	e = tkmenuentryconf(tk, etk, arg);
	layout(tk);
	return e;
}

static Tk*
xymenuitem(Tk *tk, int x, int y)
{
	TkWin *tkw = TKobj(TkWin, tk);
	x -= tkw->act.x;
	y -= tkw->act.y;

	x -= tk->borderwidth;
	y -= tk->act.y + tk->borderwidth;
	if (x < tk->act.x || x > tk->act.x+tk->act.width)
		return nil;
	for(tk = tkw->slave; tk; tk = tk->next) {
		if(y >= tk->act.y && y < tk->act.y+tk->act.height+2*tk->borderwidth)
			return tk;
	}
	return nil;
}

static char *
menukey(Tk *tk, int key)
{
	Tk *scan, *active, *first, *last, *prev, *next;
	TkWin *tkw;
	TkTop *top;

	top = tk->env->top;

	active = first = last = prev = next = nil;
	tkw = TKobj(TkWin, tk);
	for(scan = tkw->slave; scan != nil; scan = scan->next) {
		if(scan->type == TKseparator)
			continue;
		if(first == nil)
			first = scan;
		if (active != nil && next == nil)
			next = scan;
		if(active == nil && scan->flag & Tkactive)
			active = scan;
		if (active == nil)
			prev = scan;
		last = scan;
	}
	if (next == nil)
		next = first;
	if (prev == nil)
		prev = last;

	switch (key) {
	case Esc:
		tkunmapmenus(top, nil);
		break;
	case Left:
		if (tkw->cascade != nil)
			tkunmapmenu(tk);
		break;
	case Right:
		if (active == nil || active->type != TKcascade)
			break;
	case ' ':
	case '\n':
		if (active != nil) {
			if (iteminvoke(tk, active, nil))
				tkunmapmenus(top, nil);
		}
		break;
	case Up:
		next = prev;
	case Down:
		if (next != nil)
			activateitem(next);
	}
	return nil;
}

static char*
drawmenu(Tk *tk, Point orig)
{
	Image *dst;
	TkWin *tkw;
	Tk *sub;
	Point p, bd;
	int bg;
	Rectangle mainr, clientr, subr;

	tkw = TKobj(TkWin, tk);
	dst = tkimageof(tk);

	bd = Pt(tk->borderwidth, tk->borderwidth);
	mainr.min = addpt(orig, Pt(tk->act.x, tk->act.y));
	clientr.min = addpt(mainr.min, bd);
	clientr.max = addpt(clientr.min, Pt(tk->act.width, tk->act.height));
	mainr.max = addpt(clientr.max, bd);

	/*
	 * note that we draw item background to get full menu width
	 * active indicator, this means we must dirty the entire
	 * item rectangle to ensure it is fully redrawn
	 */
	p = clientr.min;
	subr = clientr;
	for (sub = tkw->slave; sub != nil; sub = sub->next) {
		if (Dx(sub->dirty) == 0)
			continue;
		subr.min.y = p.y + sub->act.y - sub->borderwidth;
		subr.max.y = p.y + sub->act.y + sub->act.height + sub->borderwidth;
		bg = TkCbackgnd;
		if (sub->flag & Tkactive)
			bg = TkCactivebgnd;
		draw(dst, subr, tkgc(sub->env, bg), nil, ZP);
		sub->dirty = tkrect(sub, 1);
		sub->flag |= Tkrefresh;
		tkmethod[sub->type]->draw(sub, p);
		sub->dirty = bbnil;
		sub->flag &= ~Tkrefresh;
	}
	/* todo: dirty check */
	tkdrawrelief(dst, tk, mainr.min, TkCbackgnd, tk->relief);
	return nil;
}

static void
menudirty(Tk *sub)
{
	menuitemdirty(sub);
}

static Point
menurelpos(Tk *sub)
{
	return Pt(sub->act.x-sub->borderwidth, sub->act.y-sub->borderwidth);
}

static void
autoscroll(Tk *tk, void *v, int cancelled)
{
	TkWin *tkw;
	Rectangle r, dr;
	Point delta, od;
	TkMouse *m;
	Tk *item;
	USED(v);

	tkw = TKobj(TkWin, tk);
	if (cancelled) {
		tkw->speed = 0;
		return;
	}
	if(!eqpt(tkw->act, tkw->req)){
print("not autoscrolling, act: %P, req: %P\n", tkw->act, tkw->req);
		return;
}
	dr = tk->env->top->screenr;
	delta.x = TKF2I(tkw->delta.x * tkw->speed);
	delta.y = TKF2I(tkw->delta.y * tkw->speed);
	r = rectaddpt(tkrect(tk, 1), Pt(tk->borderwidth + tkw->act.x, tk->borderwidth + tkw->act.y));

	od = delta;
	/* make sure we don't go too far */
	if (delta.x > 0 && r.min.x + delta.x > dr.min.x)
		delta.x = dr.min.x - r.min.x;
	else if (delta.x < 0 && r.max.x + delta.x < dr.max.x)
		delta.x = dr.max.x - r.max.x;
	if (delta.y > 0 && r.min.y + delta.y > dr.min.y)
		delta.y = dr.min.y - r.min.y;
	else if (delta.y < 0 && r.max.y + delta.y < dr.max.y)
		delta.y = dr.max.y - r.max.y;

	m = &tk->env->top->ctxt->mstate;
	item = xymenuitem(tk, m->x - delta.x, m->y - delta.y);
	if (item == nil)
		menuclr(tk);
	else
		activateitem(item);
	tkmovewin(tk, Pt(tkw->req.x + delta.x, tkw->req.y + delta.y));
	tkupdate(tk->env->top);
	/* tkenterleave won't do this for us, so we have to do it ourselves */

	tkw->speed += tkw->speed / 3;

	r = rectaddpt(tkrect(tk, 1), Pt(tk->borderwidth + tkw->act.x, tk->borderwidth + tkw->act.y));
	if((delta.y > 0 && r.min.x >= dr.min.x) || (delta.x < 0 && r.max.x <= dr.max.x))
		tkw->delta.x = 0;
	if((delta.y > 0 && r.min.y >= dr.min.y) || (delta.y < 0 && r.max.y <= dr.max.y))
		tkw->delta.y = 0;
	if (eqpt(tkw->delta, ZP)) {
		tkcancelrepeat(tk);
		tkw->speed = 0;
	}
}

static void
startautoscroll(Tk *tk, TkMouse *m)
{
	Rectangle dr, r;
	Point d;
	TkWin *tkw;
	tkw = TKobj(TkWin, tk);
	dr = tk->env->top->screenr;
	r = rectaddpt(tkrect(tk, 1), Pt(tk->borderwidth + tkw->act.x, tk->borderwidth + tkw->act.y));
	d = Pt(0, 0);
	if(m->x <= 0 && r.min.x < dr.min.x)
		d.x = 1;
	else if (m->x >= dr.max.x - 1 && r.max.x >= dr.max.x)
		d.x = -1;
	if(m->y <= 0 && r.min.y < dr.min.y)
		d.y = 1;
	else if (m->y >= dr.max.y - 1 && r.max.y >= dr.max.y)
		d.y = -1;
//print("startautoscroll, delta %P\n", d);
	if (d.x == 0 && d.y == 0){
		if (tkw->speed > 0){
			tkcancelrepeat(tk);
			tkw->speed = 0;
		}
		return;
	}
	if (tkw->speed == 0) {
		tkw->speed = TKI2F(Dy(r)) / 100;
		tkrepeat(tk, autoscroll, nil, 0, TkRptinterval/2);
	}
	tkw->delta = d;
}

static void
menuevent1(Tk *tk, int event, void *a)
{
	TkMouse *m;
	Tk *item;

	if (event & TkKey) {
		menukey(tk, event & 0xffff);
		return;
	}

	if (event & TkLeave) {
		menuclr(tk);
		return;
	}

	if ((!(event & TkEmouse) || (event & TkTakefocus)) && !(event & TkEnter))
		return;

	m = (TkMouse*)a;

	startautoscroll(tk, m);

	item = xymenuitem(tk, m->x, m->y);
	if (item == nil)
		menuclr(tk);
	else
		activateitem(item);
	if ((event & (TkMotion|TkEnter)) && item == nil)
		return;
	if (event & TkEpress) {
		if (item == nil) {
			tkunmapmenus(tk->env->top, nil);
			return;
		}
		if (item->type == TKcascade)
			tkpostcascade(tk, item, !(event & TkMotion));
		else
			tkunmapmenus(tk->env->top, tk);
		return;
	}
	if ((event & TkErelease) && m->b == 0) {
		if (item != nil) {
			if (item->type == TKcascade)
				return;
			if (!iteminvoke(tk, item, nil))
				return;
		}
		tkunmapmenus(tk->env->top, nil);
	}
}

static Tk*
menuevent(Tk *tk, int event, void *a)
{
	menuevent1(tk, event, a);
	tksubdeliver(tk, tk->binds, event, a, 0);
	return nil;
}

static
TkCmdtab menucmd[] =
{
	"activate",		tkmenuactivate,
	"add",			tkmenuadd,
	"cget",			tkmenucget,
	"configure",		tkmenuconf,
	"delete",		tkmenudelete,
	"entryconfigure",	tkmenuentryconfig,
	"entrycget",		tkmenuentrycget,
	"index",		tkmenuindex,
	"insert",		tkmenuinsert,
	"invoke",		tkmenuinvoke,
	"post",			tkmenupost,
	"postcascade",		tkmenupostcascade,
	"type",			tkmenutype,
	"unpost",		tkmenuunpost,
	"yposition",		tkmenuyposn,
	"suspend",		tkmenususpend,
	nil
};

static
TkCmdtab menubutcmd[] =
{
	"cget",			tkmenubutcget,
	"configure",		tkmenubutconf,
	"tkMBenter",		tkMBenter,
	"tkMBleave",		tkMBleave,
	"tkMBpress",		tkMBpress,
	"tkMBkey",		tkMBkey,
	nil
};

static
TkCmdtab choicebutcmd[] =
{
	"cget",			tkmenubutcget,
	"configure",		tkmenubutconf,
	"set",			tkchoicebutset,
	"get",			tkchoicebutget,
	"setvalue",		tkchoicebutsetvalue,
	"getvalue",		tkchoicebutgetvalue,
	"invoke",			tkchoicebutinvoke,
	"valuecount",		tkchoicebutvaluecount,
	"tkMBenter",		tkMBenter,
	"tkMBleave",		tkMBleave,
	"tkMBpress",		tkMBpress,
	"tkMBkey",		tkMBkey,
	"suspend",		tkmenususpend,
	nil
};

TkMethod menumethod = {
	"menu",
	menucmd,
	freemenu,
	drawmenu,
	nil,
	nil,
	nil,
	menudirty,
	menurelpos,
	menuevent
};

TkMethod menubuttonmethod = {
	"menubutton",
	menubutcmd,
	tkfreelabel,
	tkdrawlabel
};

TkMethod choicebuttonmethod = {
	"choicebutton",
	choicebutcmd,
	tkfreelabel,
	tkdrawlabel,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	tkchoicevarchanged
};

TkMethod separatormethod = {
	"separator",
	nil,
	tkfreeframe,
	tkdrawframe
};

TkMethod cascademethod = {
	"cascade",
	nil,
	tkfreelabel,
	tkdrawlabel
};
