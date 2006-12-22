#include <lib9.h>
#include <kernel.h>
#include "draw.h"
#include "tk.h"
#include "frame.h"

char*
tkframe(TkTop *t, char *arg, char **ret)
{
	Tk *tk;
	char *e;
	TkOptab tko[2];
	TkName *names;

	tk = tknewobj(t, TKframe, sizeof(Tk));
	if(tk == nil)
		return TkNomem;

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = nil;
	names = nil;

	e = tkparse(t, arg, tko, &names);
	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}
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

/*
 * Also used for windows, menus, separators
 */
void
tkfreeframe(Tk *tk)
{
	TkWin *tkw;

	if((tk->flag & Tkwindow) == 0)
		return;

	if(tk->type == TKmenu) {
		tkw = TKobj(TkWin, tk);
		free(tkw->postcmd);
		free(tkw->cascade);
		free(tkw->cbname);
	}

	tkunmap(tk);		/* XXX do this only if (tk->flag&Tkswept)==0 ?? */
}

char*
tkdrawframe(Tk *tk, Point orig)
{	
	int bw;
	Point p;
	Image *i;
	Tk *f;
	Rectangle r, slaver;		/* dribbling, whipping or just square? */

	i = tkimageof(tk);
	if(i == nil)
		return nil;
	
	p.x = orig.x + tk->act.x + tk->borderwidth;
	p.y = orig.y + tk->act.y + tk->borderwidth;

	draw(i, rectaddpt(tk->dirty, p), tkgc(tk->env, TkCbackgnd), nil, ZP);

	/*
	 * doesn't matter about drawing TKseparator
	 * oblivious of dirty rect, as it never has any children to sully anyway
	 */
	if(tk->type == TKseparator) {
		r = rectaddpt(tkrect(tk, 1), p);
		r.min.x += 4;
		r.max.x -= 4;
		r.min.y += (Dy(r) - 2)/2;
		r.max.y = r.min.y+1;
		draw(i, r, tkgc(tk->env, TkCbackgnddark), nil, ZP);
		r.min.y += 1;
		r.max.y += 1;
		draw(i, r, tkgc(tk->env, TkCbackgndlght), nil, ZP);
		return nil;
	}

	/*
	 * make sure all the slaves inside the area we've just drawn
	 * refresh themselves properly.
	 */
	for(f = tk->slave; f; f = f->next) {
		bw = f->borderwidth;
		slaver.min.x = f->act.x;
		slaver.min.y = f->act.y;
		slaver.max.x = slaver.min.x + f->act.width + 2*bw;
		slaver.max.y = slaver.min.y + f->act.height + 2*bw;
		if (rectclip(&slaver, tk->dirty)) {
			f->flag |= Tkrefresh;
			slaver = rectsubpt(slaver, Pt(f->act.x + bw, f->act.y + bw));
			combinerect(&f->dirty, slaver);
		}
	}
	p.x -= tk->borderwidth;
	p.y -= tk->borderwidth;

	if (!rectinrect(tk->dirty, tkrect(tk, 0)))
		tkdrawrelief(i, tk, p, TkCbackgnd, tk->relief);
	return nil;
}

/* Frame commands */

static char*
tkframecget(Tk *tk, char *arg, char **val)
{
	TkOptab tko[3];

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = nil;
	if(tk->flag & Tkwindow){
		tko[1].ptr = TKobj(TkWin, tk);
		tko[1].optab = tktop;
		tko[2].ptr = nil;
	}

	return tkgencget(tko, arg, val, tk->env->top);
}

static char*
tkframeconf(Tk *tk, char *arg, char **val)
{
	char *e;
	TkGeom g;
	int bd;
	Point oldp;
	TkOptab tko[3];
	TkWin *tkw;

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = nil;
	tkw = nil;
	if(tk->flag & Tkwindow) {
		tkw = TKobj(TkWin, tk);
		tko[1].ptr = tkw;
		tko[1].optab = tktop;
		tko[2].ptr = nil;
		oldp = tkw->act;
	}

	if(*arg == '\0')
		return tkconflist(tko, val);

	if(tkw != nil){
		/*
		 * see whether only -x or -y is being configured,
		 * in which case just move the window; don't redraw
		 * everything
		 */
		e = tkparse(tk->env->top, arg, &tko[1], nil);
		if(e == nil){
			if(!eqpt(oldp, tkw->req))
				tkmovewin(tk, tkw->req);
			return nil;
		}
	}

	g = tk->req;
	bd = tk->borderwidth;
	e = tkparse(tk->env->top, arg, tko, nil);
	tksettransparent(tk, tkhasalpha(tk->env, TkCbackgnd));
	tk->req.x = tk->act.x;
	tk->req.y = tk->act.y;
	tkgeomchg(tk, &g, bd);
	if(tkw != nil && !eqpt(oldp, tkw->act))
		tkmovewin(tk, tkw->req);

	tk->dirty = tkrect(tk, 1);

	return e;
}

static char*
tkframesuspend(Tk *tk, char *arg, char **val)
{
	USED(arg);
	USED(val);
	if((tk->flag & Tkwindow) == 0)
		return TkNotwm;
	tk->flag |= Tksuspended;
	return nil;
}

static char*
tkframemap(Tk *tk, char *arg, char **val)
{
	USED(arg);
	USED(val);
	if(tk->flag & Tkwindow)
		return tkmap(tk);
	return TkNotwm;
}

static char*
tkframeunmap(Tk *tk, char *arg, char **val)
{
	USED(arg);
	USED(val);
	if(tk->flag & Tkwindow) {
		tkunmap(tk);
		return nil;
	}
	return TkNotwm;
}

static void
tkframefocusorder(Tk *tk)
{
	int i, n;
	Tk *sub;
	TkWinfo *inf;

	n = 0;
	for (sub = tk->slave; sub != nil; sub = sub->next)
		n++;

	if (n == 0)
		return;

	inf = malloc(sizeof(*inf) * n);
	if (inf == nil)
		return;
	i = 0;
	for (sub = tk->slave; sub != nil; sub = sub->next) {
		inf[i].w = sub;
		inf[i].r = rectaddpt(tkrect(sub, 1), Pt(sub->act.x, sub->act.y));
		i++;
	}
	tksortfocusorder(inf, n);
	for (i = 0; i < n; i++)
		tkappendfocusorder(inf[i].w);
	free(inf);
}

static
TkCmdtab tkframecmd[] =
{
	"cget",			tkframecget,
	"configure",		tkframeconf,
	"map",			tkframemap,
	"unmap",		tkframeunmap,
	"suspend",		tkframesuspend,
	nil
};

TkMethod framemethod = {
	"frame",
	tkframecmd,
	tkfreeframe,
	tkdrawframe,
	nil,
	nil,
	tkframefocusorder
};
