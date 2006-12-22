#include "lib9.h"
#include "draw.h"
#include "tk.h"
#include "label.h"

#define	O(t, e)		((long)(&((t*)0)->e))

/* Widget Commands (+ means implemented)
	+cget
	+configure
	+invoke
	+select
	+deselect
	+toggle
 */

enum {
	/* other constants */
	InvokePause	= 200,	/* delay showing button in down state when invoked */
};

TkOption tkbutopts[] =
{
	"text",		OPTtext,	O(TkLabel, text),	nil,
	"label",	OPTtext,	O(TkLabel, text),	nil,
	"underline",	OPTdist,	O(TkLabel, ul),		nil,
	"justify",	OPTstab,	O(TkLabel, justify),	tkjustify,
	"anchor",	OPTflag,	O(TkLabel, anchor),	tkanchor,
	"command",	OPTtext,	O(TkLabel, command),	nil,
	"bitmap",	OPTbmap,	O(TkLabel, bitmap),	nil,
	"image",	OPTimag,	O(TkLabel, img),	nil,
	nil
};

TkOption tkcbopts[] =
{
	"variable",	OPTtext,	O(TkLabel, variable),	nil,
	"indicatoron",	OPTstab,	O(TkLabel, indicator),	tkbool,
	"onvalue",	OPTtext,	O(TkLabel, value),	nil,
	"offvalue",	OPTtext,	O(TkLabel, offvalue), nil,
	nil,
};

TkOption tkradopts[] =
{
	"variable",	OPTtext,	O(TkLabel, variable),	nil,
	"value",	OPTtext,	O(TkLabel, value), nil,
	"indicatoron",	OPTstab,	O(TkLabel, indicator),	tkbool,
	nil,
};

static
TkEbind bb[] =
{
	{TkEnter,	"%W configure -state active"},
	{TkLeave,	"%W configure -state normal"},
	{TkButton1P,	"%W tkButton1P"},
	{TkButton1R,	"%W tkButton1R %x %y"},
	{TkMotion|TkButton1P, 	"" },
	{TkKey,	"%W tkButtonKey 0x%K"},
};

static
TkEbind cb[] = 
{
	{TkEnter,		"%W configure -state active"},
	{TkLeave,		"%W configure -state normal"},
	{TkButton1P,		"%W invoke"},
	{TkMotion|TkButton1P, 	"" },
	{TkKey,	"%W tkButtonKey 0x%K"},
};


static char	tkselbut[] = "selectedButton";

static char*	newbutton(TkTop*, int, char*, char**);
static int	istransparent(Tk*);
static void tkvarchanged(Tk*, char*, char*);

char*
tkbutton(TkTop *t, char *arg, char **ret)
{
	return newbutton(t, TKbutton, arg, ret);
}

char*
tkcheckbutton(TkTop *t, char *arg, char **ret)
{
	return newbutton(t, TKcheckbutton, arg, ret);
}

char*
tkradiobutton(TkTop *t, char *arg, char **ret)
{
	return newbutton(t, TKradiobutton, arg, ret);
}

static char*
newbutton(TkTop *t, int btype, char *arg, char **ret)
{
	Tk *tk;
	char *e;
	TkLabel *tkl;
	TkName *names;
	TkOptab tko[4];
	TkVar *v;

	tk = tkmkbutton(t, btype);
	if(tk == nil)
		return TkNomem;

	tkl = TKobj(TkLabel, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkl;
	tko[1].optab = tkbutopts;
	switch(btype){
	case TKcheckbutton:
		tko[2].ptr = tkl;
		tko[2].optab = tkcbopts;
		break;
	case TKradiobutton:
		tko[2].ptr = tkl;
		tko[2].optab = tkradopts;
		break;
	default:
		tk->relief = TKraised;
		tk->borderwidth = 2;
		tko[2].ptr = nil;
		break;
	}
	tko[3].ptr = nil;

	names = nil;
	e = tkparse(t, arg, tko, &names);
	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}

	tksettransparent(tk, istransparent(tk));
	tksizebutton(tk);

	e = tkaddchild(t, tk, &names);
	tkfreename(names);
	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}
	tk->name->link = nil;

	if (btype == TKradiobutton &&
			tkl->variable != nil &&
			strcmp(tkl->variable, tkselbut) == 0 &&
			tkl->value == nil &&
			tk->name != nil)
		tkl->value = strdup(tk->name->name);

	if (tkl->variable != nil) {
		v = tkmkvar(t, tkl->variable, 0);
		if (v == nil){
			if(btype == TKcheckbutton){
				e = tksetvar(t, tkl->variable, tkl->offvalue ? tkl->offvalue : "0");
				if (e != nil)
					goto err;
			}
		} else if(v->type != TkVstring){
			e = TkNotvt;
			goto err;
		} else
			tkvarchanged(tk, tkl->variable, v->value);
	}

	return tkvalue(ret, "%s", tk->name->name);

err:
	tkfreeobj(tk);
	return e;
}

Tk*
tkmkbutton(TkTop *t, int btype)
{
	Tk *tk;
	TkLabel *tkl;
	char *e;

	tk = tknewobj(t, btype, sizeof(Tk)+sizeof(TkLabel));
	if (tk == nil)
		return nil;

	e = nil;
	tk->relief = TKraised;
	tk->borderwidth = 0;
	tk->highlightwidth = 1;
	tk->flag |= Tktakefocus;
	tkl = TKobj(TkLabel, tk);
	tkl->ul = -1;
	tkl->justify = Tkleft;
	if (btype == TKradiobutton)
		tkl->variable = strdup(tkselbut);

	switch (btype) {
	case TKbutton:
		e = tkbindings(t, tk, bb, nelem(bb));
		break;
	case TKcheckbutton:
	case TKradiobutton:
		e = tkbindings(t, tk, cb, nelem(cb));
		break;
	}

	if (e != nil) {
		print("tkmkbutton internal error: %s\n", e);
		tkfreeobj(tk);
		return nil;
	}
	return tk;
}

void tksizebutton(Tk *tk)
{
	tksizelabel(tk);
}

/* shame that this is separated from the sizing and rendering code in label.c */
int
tkbuttonmargin(Tk *tk)
{
	TkLabel *tkl;
	tkl = TKobj(TkLabel, tk);

	switch (tk->type) {
	case TKbutton:
		if (tkl->img != nil || tkl->bitmap != nil)
			return 0;
		return Textpadx+tk->highlightwidth;
	case TKcheckbutton:
	case TKradiobutton:
		return CheckButton + 2*CheckButtonBW + 2*ButtonBorder;
	}
	return 0;
}

static char*
tkbuttoncget(Tk *tk, char *arg, char **val)
{
	TkOptab tko[4];
	TkLabel *tkl = TKobj(TkLabel, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkl;
	tko[1].optab = tkbutopts;
	switch(tk->type){
	case TKcheckbutton:
		tko[2].ptr = tkl;
		tko[2].optab = tkcbopts;
		break;
	case TKradiobutton:
		tko[2].ptr = tkl;
		tko[2].optab = tkradopts;
		break;
	default:
		tko[2].ptr = nil;
		break;
	}
	tko[3].ptr = nil;
	return tkgencget(tko, arg, val, tk->env->top);
}

static char*
tkbuttonconf(Tk *tk, char *arg, char **val)
{
	char *e;
	TkGeom g;
	int bd;
	TkOptab tko[4];
	TkVar *v;
	TkLabel *tkl = TKobj(TkLabel, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkl;
	tko[1].optab = tkbutopts;
	switch(tk->type){
	case TKcheckbutton:
		tko[2].ptr = tkl;
		tko[2].optab = tkcbopts;
		break;
	case TKradiobutton:
		tko[2].ptr = tkl;
		tko[2].optab = tkradopts;
		break;
	default:
		tko[2].ptr = nil;
		break;
	}
	tko[3].ptr = nil;

	if(*arg == '\0')
		return tkconflist(tko, val);

	g = tk->req;
	bd = tk->borderwidth;
	e = tkparse(tk->env->top, arg, tko, nil);
	tksizebutton(tk);
	tkgeomchg(tk, &g, bd);

	tk->dirty = tkrect(tk, 1);
	tksettransparent(tk, istransparent(tk));
	/*
	 * XXX what happens if we're now disabled, but we were in
	 * active state before?
	 */
	if (tkl->variable != nil) {
		v = tkmkvar(tk->env->top, tkl->variable, 0);
		if (v != nil) {
			if (v->type != TkVstring) {
				e = TkNotvt;
				free(tkl->variable);
				tkl->variable = nil;
			}
			else
				tkvarchanged(tk, tkl->variable, v->value);
		}
	}
	return e;
}

static int
istransparent(Tk *tk)
{
	TkEnv *e = tk->env;
	return (tkhasalpha(e, TkCbackgnd) || tkhasalpha(e, TkCselectbgnd) || tkhasalpha(e, TkCactivebgnd));
}

static void
tkvarchanged(Tk *tk, char *var, char *val)
{
	TkLabel *tkl;
	char *sval;

	tkl = TKobj(TkLabel, tk);
	if (tkl->variable != nil && strcmp(tkl->variable, var) == 0) {
		sval = tkl->value;
		if (sval == nil)
			sval = tk->type == TKcheckbutton ? "1" : "";
		tkl->check = (strcmp(val, sval) == 0);
		tk->dirty = tkrect(tk, 1);
		tkdirty(tk);
	}
}

static char*
tkbutton1p(Tk *tk, char *arg, char **val)
{
	USED(arg);
	USED(val);
	if(tk->flag & Tkdisabled)
		return nil;
	tk->flag |= Tkactivated;
	tk->dirty = tkrect(tk, 1);
	tkdirty(tk);
	return nil;
}

static char*
tkbutton1r(Tk *tk, char *arg, char **val)
{
	char *e;
	Point p;
	Rectangle hitr;

	USED(arg);

	if(tk->flag & Tkdisabled)
		return nil;
	e = tkxyparse(tk, &arg, &p);
	if (e == nil) {
		hitr.min = ZP;
		hitr.max.x = tk->act.width + tk->borderwidth*2;
		hitr.max.y = tk->act.height + tk->borderwidth*2;
		if(ptinrect(p, hitr) && (tk->flag & Tkactivated))
			e = tkbuttoninvoke(tk, nil, val);
	}
	tk->flag &= ~Tkactivated;
	tk->dirty = tkrect(tk, 1);
	tkdirty(tk);
	return e;
}

static char*
tkbuttonkey(Tk *tk, char *arg, char **val)
{
	int key;

	if(tk->flag & Tkdisabled)
		return nil;

	key = atoi(arg);
	if (key == '\n' || key ==' ')
		return tkbuttoninvoke(tk, nil, val);
	return nil;
}

static char*
tkbuttontoggle(Tk *tk, char *arg, char **val)
{
	char *e;
	TkLabel *tkl = TKobj(TkLabel, tk);
	char *v;

	USED(arg);
	USED(val);
	if(tk->flag & Tkdisabled)
		return nil;
	tkl->check = !tkl->check;
	if (tkl->check)
		v = tkl->value ? tkl->value : "1";
	else
		v = tkl->offvalue ? tkl->offvalue : "0";
	e = tksetvar(tk->env->top, tkl->variable, v);
	tk->dirty = tkrect(tk, 0);
	return e;
}

static char*
buttoninvoke(Tk *tk, char **val)
{
	char *e = nil;
	TkTop *top;
	TkLabel *tkl = TKobj(TkLabel, tk);

	top = tk->env->top;
	if (tk->type == TKcheckbutton)
		e = tkbuttontoggle(tk, "", val);
	else if (tk->type == TKradiobutton)
		e = tksetvar(top, tkl->variable, tkl->value);
	if(e != nil)
		return e;
	if(tkl->command != nil)
		return tkexec(tk->env->top, tkl->command, val);
	return nil;
}

static void
cancelinvoke(Tk *tk, void *v, int cancelled)
{
	int unset;
	USED(cancelled);
	USED(v);

	/* if it was active before then leave it active unless cleared since */
	if (v)
		unset = 0;
	else
		unset = Tkactive;
	unset &= (tk->flag & Tkactive);
	unset |= Tkactivated;
	tk->flag &= ~unset;
	tksettransparent(tk, istransparent(tk));
	tk->dirty = tkrect(tk, 1);
	tkdirty(tk);
	tkupdate(tk->env->top);
}

char*
tkbuttoninvoke(Tk *tk, char *arg, char **val)
{
	char *e;
	USED(arg);

	if(tk->flag & Tkdisabled)
		return nil;
	e = buttoninvoke(tk, val);
	if (e == nil && tk->type == TKbutton && !(tk->flag & Tkactivated)) {
		tkrepeat(tk, cancelinvoke, (void*)(tk->flag&Tkactive), InvokePause, 0);
		tk->flag |= Tkactivated | Tkactive;
		tksettransparent(tk, istransparent(tk));
		tk->dirty = tkrect(tk, 1);
		tkdirty(tk);
		tkupdate(tk->env->top);
	}
	return e;
}

static char*
tkbuttonselect(Tk *tk, char *arg, char **val)
{
	char *e, *v;
	TkLabel *tkl = TKobj(TkLabel, tk);

	USED(arg);
	USED(val);
	if (tk->type == TKradiobutton)
		v = tkl->value;
	else if (tk->type == TKcheckbutton) {
		v = tkl->value ? tkl->value : "1";
		tkl->check = 1;
		tk->dirty = tkrect(tk, 0);
	} else
		v = nil;
	e = tksetvar(tk->env->top, tkl->variable, v);
	if(e != nil)
		return e;
	return nil;
}

static char*
tkbuttondeselect(Tk *tk, char *arg, char **val)
{
	char *e, *v;
	TkLabel *tkl = TKobj(TkLabel, tk);

	USED(arg);
	USED(val);

	if (tk->type == TKcheckbutton) {
		v = tkl->offvalue ? tkl->offvalue : "0";
		tkl->check = 0;
		tk->dirty = tkrect(tk, 0);
	} else
		v = nil;

	e = tksetvar(tk->env->top, tkl->variable, v);
	if(e != nil)
		return e;
	return nil;
}

static
TkCmdtab tkbuttoncmd[] =
{
	"cget",			tkbuttoncget,
	"configure",		tkbuttonconf,
	"invoke",		tkbuttoninvoke,
	"tkButton1P",		tkbutton1p,
	"tkButton1R",		tkbutton1r,
	"tkButtonKey",		tkbuttonkey,
	nil
};

static
TkCmdtab tkchkbuttoncmd[] =
{
	"cget",			tkbuttoncget,
	"configure",		tkbuttonconf,
	"invoke",		tkbuttoninvoke,
	"select",		tkbuttonselect,
	"deselect",		tkbuttondeselect,
	"toggle",		tkbuttontoggle,
	"tkButtonKey",		tkbuttonkey,
	nil
};

static
TkCmdtab tkradbuttoncmd[] =
{
	"cget",			tkbuttoncget,
	"configure",		tkbuttonconf,
	"invoke",		tkbuttoninvoke,
	"select",		tkbuttonselect,
	"deselect",		tkbuttondeselect,
	"tkButtonKey",		tkbuttonkey,
	nil
};

TkMethod buttonmethod = {
	"button",
	tkbuttoncmd,
	tkfreelabel,
	tkdrawlabel,
	nil,
	tklabelgetimgs
};

TkMethod checkbuttonmethod = {
	"checkbutton",
	tkchkbuttoncmd,
	tkfreelabel,
	tkdrawlabel,
	nil,
	tklabelgetimgs,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	tkvarchanged
};

TkMethod radiobuttonmethod = {
	"radiobutton",
	tkradbuttoncmd,
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
	tkvarchanged
};
