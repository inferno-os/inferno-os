#include "lib9.h"
#include "draw.h"
#include "tk.h"
#include "textw.h"

#define istring u.string
#define iwin u.win
#define imark u.mark
#define iline u.line

#define	O(t, e)		((long)(&((t*)0)->e))

static char* tktwincget(Tk*, char*, char**);
static char* tktwinconfigure(Tk*, char*, char**);
static char* tktwincreate(Tk*, char*, char**);
static char* tktwinnames(Tk*, char*, char**);
static int winowned(Tk *tk, Tk *sub);

static
TkStab tkalign[] =
{
	"top",		Tktop,
	"bottom",	Tkbottom,
	"center",	Tkcenter,
	"baseline",	Tkbaseline,
	nil
};

static
TkOption twinopts[] =
{
	"align",	OPTstab,	O(TkTwind, align),	tkalign,
	"create",	OPTtext,	O(TkTwind, create),	nil,
	"padx",		OPTnndist,	O(TkTwind, padx),	nil,
	"pady",		OPTnndist,	O(TkTwind, pady),	nil,
	"stretch",	OPTstab,	O(TkTwind, stretch),	tkbool,
	"window",	OPTwinp,	O(TkTwind, sub),	nil,
	"ascent",	OPTdist,	O(TkTwind, ascent), nil,
	nil
};

TkCmdtab
tktwincmd[] =
{
	"cget",		tktwincget,
	"configure",	tktwinconfigure,
	"create",	tktwincreate,
	"names",	tktwinnames,
	nil
};

int
tktfindsubitem(Tk *sub, TkTindex *ix)
{
	Tk *tk, *isub;
	TkText *tkt;

	tk = sub->parent;
	if(tk != nil) {
		tkt = TKobj(TkText, tk);
		tktstartind(tkt, ix);
		do {
			if(ix->item->kind == TkTwin) {
				isub = ix->item->iwin->sub;
				if(isub != nil && 
				   isub->name != nil && 
				   strcmp(isub->name->name, sub->name->name) == 0)
				return 1;
			}
		} while(tktadjustind(tkt, TkTbyitem, ix));
	}
	return 0;
}

static void
tktwindsize(Tk *tk, TkTindex *ix)
{
	Tk *s;
	TkTitem *i;
	TkTwind *w;


	i = ix->item;
	/* assert(i->kind == TkTwin); */

	w = i->iwin;
	s = w->sub;
	if(s == nil)
		return;

	if(w->width != s->act.width || w->height != s->act.height) {
		s->act.width = w->width;
		s->act.height = w->height;
		if(s->slave) {
			tkpackqit(s);
			tkrunpack(tk->env->top);
		}
	}

	tktfixgeom(tk, tktprevwrapline(tk, ix->line), ix->line, 0);
	tktextsize(tk, 1);
}

void
tktxtforgetsub(Tk *sub, Tk *tk)
{
	TkTwind *w;
	TkTindex ix;

	if(!tktfindsubitem(sub, &ix))
		return;
	w = ix.item->iwin;
	if(w->focus == tk) {
if(0)print("tktxtforget sub %p %q focus %p %q\n", sub, tkname(sub), tk, tkname(tk));
		w->focus = nil;
	}
}

static void
tktwingeom(Tk *sub, int x, int y, int w, int h)
{
	TkTindex ix;
	Tk *tk;
	TkTwind *win;

	USED(x);
	USED(y);

	tk = sub->parent;
	if(!tktfindsubitem(sub, &ix)) {
		print("tktwingeom: %s not found\n", sub->name->name);
		return;
	}

	win = ix.item->iwin;

	win->width = w;
	win->height = h;

	sub->req.width = w;
	sub->req.height = h;
	tktwindsize(tk, &ix);
}

static void
tktdestroyed(Tk *sub)
{
	TkTindex ix;
	Tk *tk;

	if(tktfindsubitem(sub, &ix)) {
		ix.item->iwin->sub = nil;
		ix.item->iwin->focus = nil;
		if((tk = sub->parent) != nil) {
			tktfixgeom(tk, tktprevwrapline(tk, ix.line), ix.line, 0);
			tktextsize(tk, 1);
			sub->parent = nil;
		}
	}
}

void
tktdirty(Tk *sub)
{
	Tk *tk, *parent, *isub;
	TkText *tkt;
	TkTindex ix;

	parent = nil;
	for(tk = sub; tk && parent == nil; tk = tk->master)
		parent = tk->parent;
	if(tk == nil)
		return;

	tkt = TKobj(TkText, parent);
	tktstartind(tkt, &ix);
	do {
		if(ix.item->kind == TkTwin) {
			isub = ix.item->iwin->sub;
			if(isub != nil) {
				tktfixgeom(parent, tktprevwrapline(parent, ix.line), ix.line, 0);
				if (sub->flag & Tktransparent)
					parent->flag |= Tkrefresh;	/* XXX could be more efficient, by drawing the background locally? */
				return;
			}
		}
	} while(tktadjustind(tkt, TkTbyitem, &ix));
	tktextsize(parent, 1);
}

static char*
tktwinchk(Tk *tk, TkTwind *w, Tk *oldsub)
{
	Tk *sub;

	sub = w->sub;
	if (sub != oldsub) {
		w->sub = oldsub;
		if(sub == nil)
			return nil;

		if(sub->flag & Tkwindow)
			return TkIstop;
	
		if(sub->master != nil || sub->parent != nil)
			return TkWpack;

		if (oldsub != nil) {
			oldsub->parent = nil;
			oldsub->geom = nil;
			oldsub->destroyed = nil;
		}
		w->sub = sub;
		w->focus = nil;

		sub->parent = tk;
		tksetbits(sub, Tksubsub);
		sub->geom = tktwingeom;
		sub->destroyed = tktdestroyed;

		w->width = sub->req.width;
		w->height = sub->req.height;
		w->owned = winowned(tk, sub);
	}

	return nil;
}


/* Text Window Command (+ means implemented)
	+cget
	+configure
	+create
	+names
*/

static char*
tktwincget(Tk *tk, char *arg, char **val)
{
	char *e;
	TkTindex ix;
	TkOptab tko[2];

	e = tktindparse(tk, &arg, &ix);
	if(e != nil)
		return e;
	if(ix.item->kind != TkTwin)
		return TkBadwp;

	tko[0].ptr = ix.item->iwin;
	tko[0].optab = twinopts;
	tko[1].ptr = nil;

	return tkgencget(tko, arg, val, tk->env->top);
}

static char*
tktwinconfigure(Tk *tk, char *arg, char **val)
{
	char *e;
	TkTindex ix;
	TkOptab tko[2];
	Tk *oldsub;

	USED(val);

	e = tktindparse(tk, &arg, &ix);
	if(e != nil)
		return e;
	if(ix.item->kind != TkTwin)
		return TkBadwp;

	oldsub = ix.item->iwin->sub;

	tko[0].ptr = ix.item->iwin;
	tko[0].optab = twinopts;
	tko[1].ptr = nil;

	e = tkparse(tk->env->top, arg, tko, nil);
	if(e != nil)
		return e;

	e = tktwinchk(tk, ix.item->iwin, oldsub);
	if(e != nil)
		return e;

	tktwindsize(tk, &ix);
	return nil;
}

/*
 * return true if tk is an ancestor of sub
 */
static int
winowned(Tk *tk, Tk *sub)
{
	int len;
	if (tk->name == nil || sub->name == nil)
		return 0;
	len = strlen(tk->name->name);
	if (strncmp(tk->name->name, sub->name->name, len) == 0 &&
			sub->name->name[len] == '.')
		return 1;
	return 0;
}

static char*
tktwincreate(Tk *tk, char *arg, char **val)
{
	char *e;
	TkTindex ix;
	TkTitem *i;
	TkText *tkt;
	TkOptab tko[2];

	USED(val);

	tkt = TKobj(TkText, tk);

	e = tktindparse(tk, &arg, &ix);
	if(e != nil)
		return e;

	e = tktnewitem(TkTwin, 0, &i);
	if(e != nil)
		return e;

	i->iwin = malloc(sizeof(TkTwind));
	if(i->iwin == nil) {
		tktfreeitems(tkt, i, 1);
		return TkNomem;
	}

	memset(i->iwin, 0, sizeof(TkTwind));
	i->iwin->align = Tkcenter;
	i->iwin->ascent = -1;

	tko[0].ptr = i->iwin;
	tko[0].optab = twinopts;
	tko[1].ptr = nil;

	e = tkparse(tk->env->top, arg, tko, nil);
	if(e != nil) {
    err1:
		tktfreeitems(tkt, i, 1);
		return e;
	}

	e = tktwinchk(tk, i->iwin, nil);
	if(e != nil)
		goto err1;

	e = tktsplititem(&ix);
	if(e != nil)
		goto err1;

	tktiteminsert(tkt, &ix, i);
	if(e != nil)
		goto err1;

	tktadjustind(tkt, TkTbyitemback, &ix);
	tktwindsize(tk, &ix);

	return nil;
}

static char*
tktwinnames(Tk *tk, char *arg, char **val)
{
	char *e, *fmt;
	TkTindex ix;
	TkText *tkt = TKobj(TkText, tk);

	USED(arg);

	tktstartind(tkt, &ix);
	fmt = "%s";
	do {
		if(ix.item->kind == TkTwin &&
		   ix.item->iwin->sub != nil &&
                     ix.item->iwin->sub->name != nil) {
			e = tkvalue(val, fmt, ix.item->iwin->sub->name->name);
			if(e != nil)
				return e;
			fmt = " %s";
		}
	} while(tktadjustind(tkt, TkTbyitem, &ix));
	return nil;
}
