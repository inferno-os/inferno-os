#include "lib9.h"
#include "draw.h"
#include "tk.h"
#include "textw.h"

#define istring u.string
#define iwin u.win
#define imark u.mark
#define iline u.line

static char* tkttagadd(Tk*, char*, char**);
static char* tkttagbind(Tk*, char*, char**);
static char* tkttagcget(Tk*, char*, char**);
static char* tkttagconfigure(Tk*, char*, char**);
static char* tkttagdelete(Tk*, char*, char**);
static char* tkttaglower(Tk*, char*, char**);
static char* tkttagnames(Tk*, char*, char**);
static char* tkttagnextrange(Tk*, char*, char**);
static char* tkttagprevrange(Tk*, char*, char**);
static char* tkttagraise(Tk*, char*, char**);
static char* tkttagranges(Tk*, char*, char**);
static char* tkttagremove(Tk*, char*, char**);

#define	O(t, e)		((long)(&((t*)0)->e))

#define TKTEO		(O(TkTtaginfo, env))
static 
TkOption tagopts[] =
{
	"borderwidth",
		OPTnndist, O(TkTtaginfo, opts[TkTborderwidth]),	nil,
	"justify",
		OPTstab, O(TkTtaginfo, opts[TkTjustify]),	tkjustify,
	"lineheight",
		OPTnndist, O(TkTtaginfo, opts[TkTlineheight]),	IAUX(TKTEO),
	"lmargin1",
		OPTdist, O(TkTtaginfo, opts[TkTlmargin1]),	IAUX(TKTEO),
	"lmargin2",
		OPTdist, O(TkTtaginfo, opts[TkTlmargin2]),	IAUX(TKTEO),
	"lmargin3",
		OPTdist, O(TkTtaginfo, opts[TkTlmargin3]),	IAUX(TKTEO),
	"rmargin",
		OPTdist, O(TkTtaginfo, opts[TkTrmargin]),	IAUX(TKTEO),
	"spacing1",
		OPTnndist, O(TkTtaginfo, opts[TkTspacing1]),	IAUX(TKTEO),
	"spacing2",
		OPTnndist, O(TkTtaginfo, opts[TkTspacing2]),	IAUX(TKTEO),
	"spacing3",
		OPTnndist, O(TkTtaginfo, opts[TkTspacing3]),	IAUX(TKTEO),
	"offset",	
		OPTdist, O(TkTtaginfo, opts[TkToffset]),	IAUX(TKTEO),
	"underline",
		OPTstab, O(TkTtaginfo, opts[TkTunderline]),	tkbool,
	"overstrike",
		OPTstab, O(TkTtaginfo, opts[TkToverstrike]),	tkbool,
	"relief",
		OPTstab, O(TkTtaginfo, opts[TkTrelief]),	tkrelief,
	"tabs",	
		OPTtabs, O(TkTtaginfo, tabs),			IAUX(TKTEO),
	"wrap",
		OPTstab, O(TkTtaginfo, opts[TkTwrap]),		tkwrap,
	nil,
};

static 
TkOption tagenvopts[] =
{
	"foreground",	OPTcolr,	O(TkTtaginfo, env),	IAUX(TkCforegnd),
	"background",	OPTcolr,	O(TkTtaginfo, env),	IAUX(TkCbackgnd),
	"fg",		OPTcolr,	O(TkTtaginfo, env),	IAUX(TkCforegnd),
	"bg",		OPTcolr,	O(TkTtaginfo, env),	IAUX(TkCbackgnd),
	"font",		OPTfont,	O(TkTtaginfo, env),	nil,
	nil
};

TkCmdtab
tkttagcmd[] =
{
	"add",		tkttagadd,
	"bind",		tkttagbind,
	"cget",		tkttagcget,
	"configure",	tkttagconfigure,
	"delete",	tkttagdelete,
	"lower",	tkttaglower,
	"names",	tkttagnames,
	"nextrange",	tkttagnextrange,
	"prevrange",	tkttagprevrange,
	"raise",	tkttagraise,
	"ranges",	tkttagranges,
	"remove",	tkttagremove,
	nil
};

int
tktanytags(TkTitem *it)
{
	int i;

	if(it->tagextra == 0)
		return (it->tags[0] != 0);
	for(i = 0; i <= it->tagextra; i++)
		if(it->tags[i] != 0)
			return 1;
	return 0;
}

int
tktsametags(TkTitem *i1, TkTitem *i2)
{
	int i, j;

	for(i = 0; i <= i1->tagextra && i <= i2->tagextra; i++)
		if(i1->tags[i] != i2->tags[i])
			return 0;
	for(j = i; j <= i1->tagextra; j++)
		if(i1->tags[j] != 0)
			return 0;
	for(j = i; j <= i2->tagextra; j++)
		if(i2->tags[j] != 0)
			return 0;
	return 1;
}

int
tkttagset(TkTitem *it, int id)
{
	int i;

	if(it->tagextra == 0 && it->tags[0] == 0)
		return 0;
	for(i = 0; i <= it->tagextra; i++) {
		if(id < 32)
			return ((it->tags[i] & (1<<id)) != 0);
		id -= 32;
	}
	return 0;
}

char *
tkttagname(TkText *tkt, int id)
{
	TkTtaginfo *t;

	for(t = tkt->tags; t != nil; t = t->next) {
		if(t->id == id)
			return t->name;
	}
	return "";
}

/* return 1 if this actually changes the value */
int
tkttagbit(TkTitem *it, int id, int val)
{
	int i, changed;
	ulong z, b;

	changed = 0;
	for(i = 0; i <= it->tagextra; i++) {
		if(id < 32) {
			b = (1<<id);
			z = it->tags[i];
			if(val == 0) {
				if(z & b) {
					changed = 1;
					it->tags[i] = z & (~b);
				}
			}
			else {
				if((z & b) == 0) {
					changed = 1;
					it->tags[i] = z | b;
				}
			}
			break;
		}
		id -= 32;
	}
	return changed;
}

void
tkttagcomb(TkTitem *i1, TkTitem *i2, int add)
{
	int i;

	for(i = 0; i <= i1->tagextra && i <= i2->tagextra; i++) {
		if(add == 1)
			i1->tags[i] |= i2->tags[i];
		else if(add == 0)
			/* intersect */
			i1->tags[i] &= i2->tags[i];
		else
			/* subtract */
			i1->tags[i] &= ~i2->tags[i];
	}
}

char*
tktaddtaginfo(Tk *tk, char *name, TkTtaginfo **ret)
{
	int i, *ntagp;
	TkTtaginfo *ti;
	TkText *tkt, *tktshare;

	tkt = TKobj(TkText, tk);
	ti = malloc(sizeof(TkTtaginfo));
	if(ti == nil)
		return TkNomem;

	ntagp = &tkt->nexttag;
	if(tkt->tagshare != nil) {
		tktshare = TKobj(TkText, tkt->tagshare);
		ntagp = &tktshare->nexttag;
	}
	ti->id = *ntagp;
	ti->name = strdup(name);
	if(ti->name == nil) {
		free(ti);
		return TkNomem;
	}
	ti->env = tknewenv(tk->env->top);
	if(ti->env == nil) {
		free(ti->name);
		free(ti);
		return TkNomem;
	}

	ti->tabs = nil;
	for(i = 0; i < TkTnumopts; i++)
		ti->opts[i] = TkTunset;
	ti->next = tkt->tags;
	tkt->tags = ti;

	(*ntagp)++;
	if(tkt->tagshare)
		tkt->nexttag = *ntagp;

	*ret = ti;
	return nil;
}

TkTtaginfo *
tktfindtag(TkTtaginfo *t, char *name)
{
	while(t != nil) {
		if(strcmp(t->name, name) == 0)
			return t;
		t = t->next;
	}
	return nil;
}

void
tktfreetags(TkTtaginfo *t)
{
	TkTtaginfo *n;

	while(t != nil) {
		n = t->next;
		free(t->name);
		tktfreetabs(t->tabs);
		tkputenv(t->env);
		tkfreebind(t->binds);
		free(t);
		t = n;
	}
}

int
tkttagind(Tk *tk, char *name, int first, TkTindex *ans)
{
	int id;
	TkTtaginfo *t;
	TkText *tkt;

	tkt = TKobj(TkText, tk);

	if(strcmp(name, "sel") == 0) {
		if(tkt->selfirst == nil)
			return 0;
		if(first)
			tktitemind(tkt->selfirst, ans);
		else
			tktitemind(tkt->sellast, ans);
		return 1;
	}

	t = tktfindtag(tkt->tags, name);
	if(t == nil)
		return 0;
	id = t->id;

	if(first) {
		tktstartind(tkt, ans);
		while(!tkttagset(ans->item, id))
			if(!tktadjustind(tkt, TkTbyitem, ans))
				return 0;
	}
	else {
		tktendind(tkt, ans);
		while(!tkttagset(ans->item, id))
			if(!tktadjustind(tkt, TkTbyitemback, ans))
				return 0;
		tktadjustind(tkt, TkTbyitem, ans);
	}

	return 1;
}

/*
 * Fill in opts and e, based on info from tags set in it,
 * using tags order for priority.
 * If dflt != 0, options not set are filled from tk,
 * otherwise iInteger options not set by any tag are left 'TkTunset'
 * and environment values not set are left nil.
 */
void
tkttagopts(Tk *tk, TkTitem *it, int *opts, TkEnv *e, TkTtabstop **tb, int dflt)
{
	int i;
	int colset;
	TkEnv *te;
	TkTtaginfo *tags;
	TkText *tkt = TKobj(TkText, tk);

	if (tb != nil)
		*tb = tkt->tabs;

	tags = tkt->tags;

	if(opts != nil)
		for(i = 0; i < TkTnumopts; i++)
			opts[i] = TkTunset;

	memset(e, 0, sizeof(TkEnv));
	e->top = tk->env->top;
	colset = 0;
	while(tags != nil) {
		if(tkttagset(it, tags->id)) {
			if(opts != nil) {
				for(i = 0; i < TkTnumopts; i++) {
					if(opts[i] == TkTunset && tags->opts[i] != TkTunset)
						opts[i] = tags->opts[i];
				}
			}

			te = tags->env;
			for(i = 0; i < TkNcolor; i++)
				if(!(colset & (1<<i)) && te->set & (1<<i)) {
					e->colors[i] = te->colors[i];
					colset |= 1<<i;
				}

			if(e->font == nil && te->font != nil)
				e->font = te->font;

			if (tb != nil && tags->tabs != nil)
				*tb = tags->tabs;
		}
		tags = tags->next;
	}
	e->set |= colset;
	if(dflt) {
		if(opts != nil) {
			for(i = 0; i < TkTnumopts; i++)
				if(opts[i] == TkTunset)
					opts[i] = tkt->opts[i];
		}
		te = tk->env;
		for(i = 0; i < TkNcolor; i++)
			if(!(e->set & (1<<i))) {
				e->colors[i] = te->colors[i];
				e->set |= 1<<i;
			}
		if(e->font == nil)
			e->font = te->font;
	}
}

char*
tkttagparse(Tk *tk, char **parg, TkTtaginfo **ret)
{
	char *e, *buf;
	TkText *tkt = TKobj(TkText, tk);

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	*parg = tkword(tk->env->top, *parg, buf, buf+Tkmaxitem, nil);
	if(*buf == '\0') {
		free(buf);
		return TkOparg;
	}
	if(buf[0] >= '0' && buf[0] <= '9'){
		free(buf);
		return TkBadtg;
	}

	*ret = tktfindtag(tkt->tags, buf);
	if(*ret == nil) {
		e = tktaddtaginfo(tk, buf, ret);
		if(e != nil) {
			free(buf);
			return e;
		}
	}
	free(buf);

	return nil;
}

int
tkttagnrange(TkText *tkt, int tid, TkTindex *i1, TkTindex *i2,
			TkTindex *istart, TkTindex *iend)
{
	int found;

	found = 0;
	while(i1->line != &tkt->end) {
		if(i1->item == i2->item && i2->pos == 0)
			break;
		if(tkttagset(i1->item, tid)) {
			if(!found) {
				found = 1;
				*istart = *i1;
			}
			if(i1->item == i2->item) {
				/* i2->pos > 0 */
				*iend = *i2;
				return 1;
			}
		}
		else
		if(i1->item == i2->item || (found && i1->item->kind != TkTmark && i1->item->kind != TkTcontline))
			break;
		tktadjustind(tkt, TkTbyitem, i1);
	}
	if(found)
		*iend = *i1;

	return found;
}

static int
tkttagprange(TkText *tkt, int tid, TkTindex *i1, TkTindex *i2,
			TkTindex *istart, TkTindex *iend)
{
	int found;

	found = 0;
	while(i1->line != &tkt->start && i1->item != i2->item) {
		tktadjustind(tkt, TkTbyitemback, i1);
		if(tkttagset(i1->item, tid)) {
			if(!found) {
				found = 1;
				*iend = *i1;
			}
		}
		else
		if(found && i1->item->kind != TkTmark && i1->item->kind != TkTcontline)
			break;
	}
	if(found) {
		tktadjustind(tkt, TkTbyitem, i1);
		*istart = *i1;
		if(i1->item == i2->item)
			istart->pos = i2->pos;
	}

	return found;
}

/* XXX - Tad: potential memory leak on memory allocation failure */
char *
tkttagchange(Tk *tk, int tid, TkTindex *i1, TkTindex *i2, int add)
{
	char *e;
	int samei, nextra, j, changed;
	TkTline *lmin, *lmax;
	TkTindex ixprev;
	TkTitem *nit;
	TkText *tkt = TKobj(TkText, tk);

	if(!tktindbefore(i1, i2))
		return nil;

	nextra = tid/32;
	lmin = nil;
	lmax = nil;
	tktadjustind(tkt, TkTbycharstart, i1);
	tktadjustind(tkt, TkTbycharstart, i2);
	samei = (i1->item == i2->item);
	if(i2->pos != 0) {
		e = tktsplititem(i2);
		if(e != nil)
			return e;
		if(samei) {
			/* split means i1 should now point to previous item */
			ixprev = *i2;
			tktadjustind(tkt, TkTbyitemback, &ixprev);
			i1->item = ixprev.item;
		}
	}
	if(i1->pos != 0) {
		e = tktsplititem(i1);
		if(e != nil)
			return e;
	}
	/* now i1 and i2 both point to beginning of non-mark/contline items */
	if(tid == TkTselid) {
		/*
		 * Cache location of selection.
		 * Note: there can be only one selection range in widget
		 */
		if(add) {
			if(tkt->selfirst != nil)
				return TkBadsl;
			tkt->selfirst = i1->item;
			tkt->sellast = i2->item;
		}
		else {
			tkt->selfirst = nil;
			tkt->sellast = nil;
		}
	}
	while(i1->item != i2->item) {
		if(i1->item->kind != TkTmark && i1->item->kind != TkTcontline) {
			if(tid >= 32 && i1->item->tagextra < nextra) {
				nit = realloc(i1->item, sizeof(TkTitem) + nextra * sizeof(long));
				if(nit == nil)
					return TkNomem;
				for(j = nit->tagextra+1; j <= nextra; j++)
					nit->tags[j] = 0;
				nit->tagextra = nextra;
				if(i1->line->items == i1->item)
					i1->line->items = nit;
				else {
					ixprev = *i1;
					tktadjustind(tkt, TkTbyitemback, &ixprev);
					ixprev.item->next = nit;
				}
				/* check nit against cached items */
				if(tkt->selfirst == i1->item)
					tkt->selfirst = nit;
				if(tkt->sellast == i1->item)
					tkt->sellast = nit;
				i1->item = nit;
			}
			changed = tkttagbit(i1->item, tid, add);
			if(lmin == nil) {
				if(changed) {
					lmin = i1->line;
					lmax = lmin;
				}
			}
			else {
				if(changed)
					lmax = i1->line;
			}
		}
		if(!tktadjustind(tkt, TkTbyitem, i1))
			break;
	}
	if(lmin != nil) {
		tktfixgeom(tk, tktprevwrapline(tk, lmin), lmax, 0);
		tktextsize(tk, 1);
	}
	return nil;
}

static char*
tkttagaddrem(Tk *tk, char *arg, int add)
{
	char *e;
	TkText *tkt;
	TkTtaginfo *ti;
	TkTindex ix1, ix2;

	tkt = TKobj(TkText, tk);

	e = tkttagparse(tk, &arg, &ti);
	if(e != nil)
		return e;

	while(*arg != '\0') {
		e = tktindparse(tk, &arg, &ix1);
		if(e != nil)
			return e;
		if(*arg != '\0') {
			e = tktindparse(tk, &arg, &ix2);
			if(e != nil)
				return e;
		}
		else {
			ix2 = ix1;
			tktadjustind(tkt, TkTbychar, &ix2);
		}
		if(!tktindbefore(&ix1, &ix2))
			continue;

		e = tkttagchange(tk, ti->id, &ix1, &ix2, add);
		if(e != nil)
			return e;
	}

	return nil;
}


/* Text Tag Command (+ means implemented)
	+add
	+bind
	+cget
	+configure
	+delete
	+lower
	+names
	+nextrange
	+prevrange
	+raise
	+ranges
	+remove
*/

static char*
tkttagadd(Tk *tk, char *arg, char **val)
{
	USED(val);

	return tkttagaddrem(tk, arg, 1);
}

static char*
tkttagbind(Tk *tk, char *arg, char **val)
{
	char *e;
	Rune r;
	TkTtaginfo *ti;
	TkAction *a;
	int event, mode;
	char *cmd, buf[Tkmaxitem];


	e = tkttagparse(tk, &arg, &ti);
	if(e != nil)
		return e;

	arg = tkskip(arg, " \t");
	if (arg[0] == '\0')
		return TkBadsq;
	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if(buf[0] == '<') {
		event = tkseqparse(buf+1);
		if(event == -1)
			return TkBadsq;
	}
	else {
		chartorune(&r, buf);
		event = TkKey | r;
	}
	if(event == 0)
		return TkBadsq;

	arg = tkskip(arg, " \t");
	if(*arg == '\0') {
		for(a = ti->binds; a; a = a->link)
				if(event == a->event)
					return tkvalue(val, "%s", a->arg);
		return nil;		
	}

	mode = TkArepl;
	if(*arg == '+') {
		mode = TkAadd;
		arg++;
	}
	else if(*arg == '-'){
		mode = TkAsub;
		arg++;
	}

	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	cmd = strdup(buf);
	if(cmd == nil)
		return TkNomem;
	return tkaction(&ti->binds, event, TkDynamic, cmd, mode);
}

static char*
tkttagcget(Tk *tk, char *arg, char **val)
{
	char *e;
	TkTtaginfo *ti;
	TkOptab tko[3];

	e = tkttagparse(tk, &arg, &ti);
	if(e != nil)
		return e;

	tko[0].ptr = ti;
	tko[0].optab = tagopts;
	tko[1].ptr = ti;
	tko[1].optab = tagenvopts;
	tko[2].ptr = nil;

	return tkgencget(tko, arg, val, tk->env->top);
}

static char*
tkttagconfigure(Tk *tk, char *arg, char **val)
{
	char *e;
	TkOptab tko[3];
	TkTtaginfo *ti;
	TkTindex ix;
	TkText *tkt = TKobj(TkText, tk);

	USED(val);

	e = tkttagparse(tk, &arg, &ti);
	if(e != nil)
		return e;

	tko[0].ptr = ti;
	tko[0].optab = tagopts;
	tko[1].ptr = ti;
	tko[1].optab = tagenvopts;
	tko[2].ptr = nil;

	e = tkparse(tk->env->top, arg, tko, nil);
	if(e != nil)
		return e;

	if(tkttagind(tk, ti->name, 1, &ix)) {
		tktfixgeom(tk, tktprevwrapline(tk, ix.line), tkt->end.prev, 0);
		tktextsize(tk, 1);
	}

	return nil;
}

static void
tktunlinktag(TkText *tkt, TkTtaginfo *t)
{
	TkTtaginfo *f, **l;

	l = &tkt->tags;
	for(f = *l; f != nil; f = f->next) {
		if(f == t) {
			*l = t->next;
			return;
		}
		l = &f->next;
	}
}

static char*
tkttagdelete(Tk *tk, char *arg, char **val)
{
	TkText *tkt;
	TkTtaginfo *t;
	TkTindex ix;
	char *e;
	int found;

	USED(val);

	tkt = TKobj(TkText, tk);

	e = tkttagparse(tk, &arg, &t);
	if(e != nil)
		return e;

	found = 0;
	while(t != nil) {
		if(t->id == TkTselid)
			return TkBadvl;

		while(tkttagind(tk, t->name, 1, &ix)) {
			found = 1;
			tkttagbit(ix.item, t->id, 0);
		}

		tktunlinktag(tkt, t);
		t->next = nil;
		tktfreetags(t);

		if(*arg != '\0') {
			e = tkttagparse(tk, &arg, &t);
			if(e != nil)
				return e;
		}
		else
			t = nil;
	}
	if (found) {
		tktfixgeom(tk, &tkt->start, tkt->end.prev, 0);
		tktextsize(tk, 1);
	}

	return nil;
}

static char*
tkttaglower(Tk *tk, char *arg, char **val)
{
	TkText *tkt;
	TkTindex ix;
	TkTtaginfo *t, *tbelow, *f, **l;
	char *e;

	USED(val);

	tkt = TKobj(TkText, tk);

	e = tkttagparse(tk, &arg, &t);
	if(e != nil)
		return e;

	if(*arg != '\0') {
		e = tkttagparse(tk, &arg, &tbelow);
		if(e != nil)
			return e;
	}
	else
		tbelow = nil;

	tktunlinktag(tkt, t);

	if(tbelow != nil) {
		t->next = tbelow->next;
		tbelow->next = t;
	}
	else {
		l = &tkt->tags;
		for(f = *l; f != nil; f = f->next)
			l = &f->next;
		*l = t;
		t->next = nil;
	}
	if(tkttagind(tk, t->name, 1, &ix)) {
		tktfixgeom(tk, tktprevwrapline(tk, ix.line), tkt->end.prev, 0);
		tktextsize(tk, 1);
	}

	return nil;
}


static char*
tkttagnames(Tk *tk, char *arg, char **val)
{
	char *e, *r, *fmt;
	TkTtaginfo *t;
	TkTindex i;
	TkText *tkt = TKobj(TkText, tk);
	TkTitem *tagit;

	if(*arg != '\0') {
		e = tktindparse(tk, &arg, &i);
		if(e != nil)
			return e;
		/* make sure we're actually on a character */
		tktadjustind(tkt, TkTbycharstart, &i);
		tagit = i.item;
	}
	else
		tagit = nil;

	/* generate in order highest-to-lowest priority (contrary to spec) */
	fmt = "%s";
	for(t = tkt->tags; t != nil; t = t->next) {
		if(tagit == nil || tkttagset(tagit, t->id)) {
			r = tkvalue(val, fmt, t->name);
			if(r != nil)
				return r;
			fmt = " %s";
		}
	}
	return nil;
}

static char*
tkttagnextrange(Tk *tk, char *arg, char **val)
{
	char *e;
	TkTtaginfo *t;
	TkTindex i1, i2, istart, iend;
	TkText *tkt = TKobj(TkText, tk);

	e = tkttagparse(tk, &arg, &t);
	if(e != nil)
		return e;
	e = tktindparse(tk, &arg, &i1);
	if(e != nil)
		return e;
	if(*arg != '\0') {
		e = tktindparse(tk, &arg, &i2);
		if(e != nil)
			return e;
	}
	else
		tktendind(tkt, &i2);

	if(tkttagnrange(tkt, t->id, &i1, &i2, &istart, &iend))
		return tkvalue(val, "%d.%d %d.%d",
			tktlinenum(tkt, &istart), tktlinepos(tkt, &istart),
			tktlinenum(tkt, &iend), tktlinepos(tkt, &iend));

	return nil;
}

static char*
tkttagprevrange(Tk *tk, char *arg, char **val)
{
	char *e;
	TkTtaginfo *t;
	TkTindex i1, i2, istart, iend;
	TkText *tkt = TKobj(TkText, tk);

	e = tkttagparse(tk, &arg, &t);
	if(e != nil)
		return e;
	e = tktindparse(tk, &arg, &i1);
	if(e != nil)
		return e;
	if(*arg != '\0') {
		e = tktindparse(tk, &arg, &i2);
		if(e != nil)
			return e;
	}
	else
		tktstartind(tkt, &i2);

	if(tkttagprange(tkt, t->id, &i1, &i2, &istart, &iend))
		return tkvalue(val, "%d.%d %d.%d",
			tktlinenum(tkt, &istart), tktlinepos(tkt, &istart),
			tktlinenum(tkt, &iend), tktlinepos(tkt, &iend));

	return nil;
}

static char*
tkttagraise(Tk *tk, char *arg, char **val)
{
	TkText *tkt;
	TkTindex ix;
	TkTtaginfo *t, *tabove, *f, **l;
	char *e;

	USED(val);

	tkt = TKobj(TkText, tk);

	e = tkttagparse(tk, &arg, &t);
	if(e != nil)
		return e;

	if(*arg != '\0') {
		e = tkttagparse(tk, &arg, &tabove);
		if(e != nil)
			return e;
	}
	else
		tabove = nil;

	tktunlinktag(tkt, t);

	if(tabove != nil) {
		l = &tkt->tags;
		for(f = *l; f != nil; f = f->next) {
			if(f == tabove) {
				*l = t;
				t->next = tabove;
				break;
			}
			l = &f->next;
		}
	}
	else {
		t->next = tkt->tags;
		tkt->tags = t;
	}

	if(tkttagind(tk, t->name, 1, &ix)) {
		tktfixgeom(tk, tktprevwrapline(tk, ix.line), tkt->end.prev, 0);
		tktextsize(tk, 1);
	}
	return nil;
}

static char*
tkttagranges(Tk *tk, char *arg, char **val)
{
	char *e, *fmt;
	TkTtaginfo *t;
	TkTindex i1, i2, istart, iend;
	TkText *tkt = TKobj(TkText, tk);

	e = tkttagparse(tk, &arg, &t);
	if(e != nil)
		return e;

	tktstartind(tkt, &i1);
	tktendind(tkt, &i2);

	fmt = "%d.%d %d.%d";
	while(tkttagnrange(tkt, t->id, &i1, &i2, &istart, &iend)) {
		e = tkvalue(val, fmt,
			tktlinenum(tkt, &istart), tktlinepos(tkt, &istart),
			tktlinenum(tkt, &iend), tktlinepos(tkt, &iend));
		if(e != nil)
			return e;

		fmt = " %d.%d %d.%d";
		i1 = iend;
	}

	return nil;
}

static char*
tkttagremove(Tk *tk, char *arg, char **val)
{
	USED(val);

	return tkttagaddrem(tk, arg, 0);
}
