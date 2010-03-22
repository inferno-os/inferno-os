#include "lib9.h"
#include "draw.h"
#include "tk.h"
#include <kernel.h>
#include <interp.h>

enum
{
	Cmask,
	Cctl,
	Ckey,
	Cbp,
	Cbr,
};

struct 
{
	char*	event;
	int	mask;
	int	action;
} etab[] =
{
	"Motion",		TkMotion,	Cmask,
	"Double",		TkDouble,	Cmask,	
	"Map",			TkMap,		Cmask,
	"Unmap",		TkUnmap,	Cmask,
	"Destroy",		TkDestroy, Cmask,
	"Enter",		TkEnter,	Cmask,
	"Leave",		TkLeave,	Cmask,
	"FocusIn",		TkFocusin,	Cmask,
	"FocusOut",		TkFocusout,	Cmask,
	"Configure",		TkConfigure,	Cmask,
	"Control",		0,		Cctl,
	"Key",			0,		Ckey,
	"KeyPress",		0,		Ckey,
	"Button",		0,		Cbp,
	"ButtonPress",		0,		Cbp,
	"ButtonRelease",	0,		Cbr,
};

static
TkOption tkcurop[] =
{
	"x",		OPTdist,	O(TkCursor, p.x),	nil,
	"y",		OPTdist,	O(TkCursor, p.y),	nil,
	"bitmap",	OPTbmap,	O(TkCursor, bit),	nil,
	"image",	OPTimag,	O(TkCursor, img),	nil,
	"default",	OPTbool,	O(TkCursor, def),	nil,
	nil
};

static
TkOption focusopts[] = {
	"global",			OPTbool,	0,	nil,
	nil
};

static char*
tkseqitem(char *buf, char *arg)
{
	while(*arg && (*arg == ' ' || *arg == '-'))
		arg++;
	while(*arg && *arg != ' ' && *arg != '-' && *arg != '>')
		*buf++ = *arg++;
	*buf = '\0';
	return arg;
}

static char*
tkseqkey(Rune *r, char *arg)
{
	char *narg;

	while(*arg && (*arg == ' ' || *arg == '-'))
		arg++;
	if (*arg == '\\') {
		if (*++arg == '\0') {
			*r = 0;
			return arg;
		}
	} else if (*arg == '\0' || *arg == '>' || *arg == '-') {
		*r = 0;
		return arg;
	}
	narg = arg + chartorune(r, arg);
	return narg;
}

int
tkseqparse(char *seq)
{
	Rune r;
	int i, event;
	char *buf;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return -1;

	event = 0;

	while(*seq && *seq != '>') {
		seq = tkseqitem(buf, seq);
	
		for(i = 0; i < nelem(etab); i++)	
			if(strcmp(buf, etab[i].event) == 0)
				break;
	
		if(i >= nelem(etab)) {
			seq = tkextnparseseq(buf, seq, &event);
			if (seq == nil) {
				free(buf);
				return -1;
			}
			continue;
		}
	
	
		switch(etab[i].action) {
		case Cmask:
			event |= etab[i].mask;
			break;
		case Cctl:
			seq = tkseqkey(&r, seq);
			if(r == 0) {
				free(buf);
				return -1;
			}
			if(r <= '~')
				r &= 0x1f;
			event |= TkKey|TKKEY(r);
			break;	
		case Ckey:
			seq = tkseqkey(&r, seq);
			if(r != 0)
				event |= TKKEY(r);
			event |= TkKey;
			break;
		case Cbp:
			seq = tkseqitem(buf, seq);
			switch(buf[0]) {
			default:
				free(buf);
				return -1;
			case '\0':
				event |= TkEpress;
				break;
			case '1':
				event |= TkButton1P;
				break;
			case '2':
				event |= TkButton2P;
				break;
			case '3':
				event |= TkButton3P;
				break;
			case '4':
				event |= TkButton4P;
				break;
			case '5':
				event |= TkButton5P;
				break;
			case '6':
				event |= TkButton6P;
				break;
			}
			break;
		case Cbr:
			seq = tkseqitem(buf, seq);
			switch(buf[0]) {
			default:
				free(buf);
				return -1;
			case '\0':
				event |= TkErelease;
				break;
			case '1':
				event |= TkButton1R;
				break;
			case '2':
				event |= TkButton2R;
				break;
			case '3':
				event |= TkButton3R;
				break;
			case '4':
				event |= TkButton4R;
				break;
			case '5':
				event |= TkButton5R;
				break;
			case '6':
				event |= TkButton6R;
				break;
			}
			break;
		}
	}
	free(buf);
	return event;
}

void
tkcmdbind(Tk *tk, int event, char *s, void *data)
{
	Point p;
	TkMouse *m;
	TkGeom *g;
	int v, len;
	char *e, *c, *ec, *cmd;
	TkTop *t;

	if(s == nil)
		return;
	cmd = malloc(2*Tkmaxitem);
	if (cmd == nil) {
		print("tk: bind command \"%s\": %s\n",
			tk->name ? tk->name->name : "(noname)", TkNomem);
		return;
	}

	m = (TkMouse*)data;
	c = cmd;
	ec = cmd+2*Tkmaxitem-1;
	while(*s && c < ec) {
		if(*s != '%') {
			*c++ = *s++;
			continue;
		}
		s++;
		len = ec-c;
		switch(*s++) {
		def:
		default:
			*c++ = s[-1];
			break;
		case '%':
			*c++ = '%';
			break;
		case 'b':
			v = 0;
			if (!(event & TkKey)) {
				if(event & (TkButton1P|TkButton1R))
					v = 1;
				else if(event & (TkButton2P|TkButton2R))
					v = 2;
				else if(event & (TkButton3P|TkButton3R))
					v = 3;
			}
			c += snprint(c, len, "%d", v);
			break;
		case 'h':
			if((event & TkConfigure) == 0)
				goto def;
			g = (TkGeom*)data;
			c += snprint(c, len, "%d", g->height);
			break;
		case 's':
			if((event & TkKey))
				c += snprint(c, len, "%d", TKKEY(event));
			else if((event & (TkEmouse|TkEnter)))
				c += snprint(c, len, "%d", m->b);
			else if((event & TkFocusin))
				c += snprint(c, len, "%d", (int)data);
			else
				goto def;
			break;
		case 'w':
			if((event & TkConfigure) == 0)
				goto def;
			g = (TkGeom*)data;
			c += snprint(c, len, "%d", g->width);
			break;
		case 'x':		/* Relative mouse coords */
		case 'y':
			if((event & TkKey) || (event & (TkEmouse|TkEnter)) == 0)
				goto def;
			p = tkposn(tk);
			if(s[-1] == 'x')
				v = m->x - p.x;
			else
				v = m->y - p.y;
			c += snprint(c, len, "%d", v - tk->borderwidth);
			break;
		case 'X':		/* Absolute mouse coords */
		case 'Y':
			if((event & TkKey) || (event & TkEmouse) == 0)
				goto def;
			c += snprint(c, len, "%d", s[-1] == 'X' ? m->x : m->y);
			break;
		case 'A':
			if((event & TkKey) == 0)
				goto def;
			v = TKKEY(event);
			if(v == '{' || v == '}' || v == '\\')
				c += snprint(c, len, "\\%C", v);
			else if(v != '\0')
				c += snprint(c, len, "%C", v);
			break;
		case 'K':
			if((event & TkKey) == 0)
				goto def;
			c += snprint(c, len, "%.4X", TKKEY(event));
			break;
		case 'W':
		        if (tk->name != nil) 
			  c += snprint(c, len, "%s", tk->name->name);
			break;
		}
	}
	*c = '\0';
	e = nil;
	t = tk->env->top;
	t->execdepth = 0;
	if(cmd[0] == '|')
		tkexec(t, cmd+1, nil);
	else if(cmd[0] != '\0')
		e = tkexec(t, cmd, nil);
	t->execdepth = -1;

	if(e == nil) {
		free(cmd);
		return;
	}

	if(tk->name != nil){
		char *s;

		if(t->errx[0] != '\0')
			s = tkerrstr(t, e);
		else
			s = e;
		print("tk: bind command \"%s\": %s: %s\n", tk->name->name, cmd, s);
		if(s != e)
			free(s);
	}
	free(cmd);
}

char*
tkbind(TkTop *t, char *arg, char **ret)
{
	Rune r;
	Tk *tk;
	TkAction **ap;
	int i, mode, event;
	char *cmd, *tag, *seq;
	char *e;

	USED(ret);

	tag = mallocz(Tkmaxitem, 0);
	if(tag == nil)
		return TkNomem;
	seq = mallocz(Tkmaxitem, 0);
	if(seq == nil) {
		free(tag);
		return TkNomem;
	}

	arg = tkword(t, arg, tag, tag+Tkmaxitem, nil);
	if(tag[0] == '\0') {
		e = TkBadtg;
		goto err;
	}

	arg = tkword(t, arg, seq, seq+Tkmaxitem, nil);
	if(seq[0] == '<') {
		event = tkseqparse(seq+1);
		if(event == -1) {
			e = TkBadsq;
			goto err;
		}
	}
	else {
		chartorune(&r, seq);
		event = TkKey | r;
	}
	if(event == 0) {
		e = TkBadsq;
		goto err;
	}

	arg = tkskip(arg, " \t");

	mode = TkArepl;
	if(*arg == '+') {
		mode = TkAadd;
		arg++;
	}
	else if(*arg == '-'){
		mode = TkAsub;
		arg++;
	}

	if(*arg == '{') {
		cmd = tkskip(arg+1, " \t");
		if(*cmd == '}') {
			tk = tklook(t, tag, 0);
			if(tk == nil) {
				for(i = 0; ; i++) {
					if(i >= TKwidgets) {
						e = TkBadwp;
						tkerr(t, tag);
						goto err;
					}
					if(strcmp(tag, tkmethod[i]->name) == 0) {
						ap = &(t->binds[i]);
						break;
					}
				}
			}
			else
				ap = &tk->binds;
			tkcancel(ap, event);
		}
	}

	tkword(t, arg, seq, seq+Tkmaxitem, nil);
	if(tag[0] == '.') {
		tk = tklook(t, tag, 0);
		if(tk == nil) {
			e = TkBadwp;
			tkerr(t, tag);
			goto err;
		}

		cmd = strdup(seq);
		if(cmd == nil) {
			e = TkNomem;
			goto err;
		}
		e = tkaction(&tk->binds, event, TkDynamic, cmd, mode);
		if(e != nil)
			goto err;	/* tkaction does free(cmd) */
		free(tag);
		free(seq);
		return nil;
	}
	/* documented but doesn't work */
	if(strcmp(tag, "all") == 0) {
		for(tk = t->root; tk; tk = tk->next) {
			cmd = strdup(seq);
			if(cmd == nil) {
				e = TkNomem;
				goto err;
			}
			e = tkaction(&tk->binds, event, TkDynamic, cmd, mode);
			if(e != nil)
				goto err;
		}
		free(tag);
		free(seq);
		return nil;
	}
	/* undocumented, probably unused, and doesn't work consistently */
	for(i = 0; i < TKwidgets; i++) {
		if(strcmp(tag, tkmethod[i]->name) == 0) {
			cmd = strdup(seq);
			if(cmd == nil) {
				e = TkNomem;
				goto err;
			}
			e = tkaction(t->binds + i,event, TkDynamic, cmd, mode);
			if(e != nil)
				goto err;
			free(tag);
			free(seq);
			return nil;
		}
	}

	e = TkBadtg;
err:
	free(tag);
	free(seq);

	return e;
}

char*
tksend(TkTop *t, char *arg, char **ret)
{

	TkVar *v;
	char *var;

	USED(ret);

	var = mallocz(Tkmaxitem, 0);
	if(var == nil)
		return TkNomem;

	arg = tkword(t, arg, var, var+Tkmaxitem, nil);
	v = tkmkvar(t, var, 0);
	free(var);
	if(v == nil)
		return TkBadvr;
	if(v->type != TkVchan)
		return TkNotvt;

	arg = tkskip(arg, " \t");
	if(tktolimbo(v->value, arg) == 0)
		return TkMovfw;

	return nil;
}

static Tk*
tknextfocus(TkTop *t, int d)
{
	int i, n, j, k;
	Tk *oldfocus;

	if (t->focusorder == nil)
		tkbuildfocusorder(t);

	oldfocus = t->ctxt->tkkeygrab;
	n = t->nfocus;
	if (n == 0)
		return oldfocus;
	for (i = 0; i < n; i++)
		if (t->focusorder[i] == oldfocus)
			break;
	if (i == n) {
		for (i = 0; i < n; i++)
			if ((t->focusorder[i]->flag & Tkdisabled) == 0)
				return t->focusorder[i];
		return oldfocus;
	}
	for (j = 1; j < n; j++) {
		k = (i + d * j + n) % n;
		if ((t->focusorder[k]->flag & Tkdisabled) == 0)
			return t->focusorder[k];
	}
	return oldfocus;
}

/* our dirty little secret */
static void
focusdirty(Tk *tk)
{
	if(tk->highlightwidth > 0){
		tk->dirty = tkrect(tk, 1);
		tkdirty(tk);
	}
}

void
tksetkeyfocus(TkTop *top, Tk *new, int dir)
{
	TkCtxt *c;
	Tk *old;

	c = top->ctxt;
	old = c->tkkeygrab;

	if(old == new)
		return;
	c->tkkeygrab = new;
	if(top->focused == 0)
		return;
	if(old != nil && old != top->root){
		tkdeliver(old, TkFocusout, nil);
		focusdirty(old);
	}
	if(new != nil && new != top->root){
		tkdeliver(new, TkFocusin, (void*)dir);
		focusdirty(new);
	}
}

void
tksetglobalfocus(TkTop *top, int in)
{
	Tk *tk;
	in = (in != 0);
	if (in != top->focused){
		top->focused = in;
		tk = top->ctxt->tkkeygrab;
		if(in){
			tkdeliver(top->root, TkFocusin, (void*)0);
			if(tk != nil && tk != top->root){
				tkdeliver(tk, TkFocusin, (void*)0);
				focusdirty(tk);
			}
		}else{
			if(tk != nil && tk != top->root){
				tkdeliver(tk, TkFocusout, nil);
				focusdirty(tk);
			}
			tkdeliver(top->root, TkFocusout, nil);
		}
	}
}

char*
tkfocus(TkTop *top, char *arg, char **ret)
{
	Tk *tk;
	char *wp, *e;
	int dir, global;
	TkOptab tko[2];
	TkName *names;

	tko[0].ptr = &global;
	tko[0].optab = focusopts;
	tko[1].ptr = nil;

	global = 0;
	
	names = nil;
	e = tkparse(top, arg, tko, &names);
	if (e != nil)
		return e;

	if(names == nil){
		if(global)
			return tkvalue(ret, "%d", top->focused);
		tk = top->ctxt->tkkeygrab;
		if (tk != nil && tk->name != nil)
			return tkvalue(ret, "%s", tk->name->name);
		return nil;
	}

	if(global){
		tksetglobalfocus(top, atoi(names->name));
		return nil;
	}

	wp = mallocz(Tkmaxitem, 0);
	if(wp == nil)
		return TkNomem;

	tkword(top, arg, wp, wp+Tkmaxitem, nil);
	if (!strcmp(wp, "next")) {
		tk = tknextfocus(top, 1);		/* can only return nil if c->tkkeygrab is already nil */
		dir = +1;
	} else if (!strcmp(wp, "previous")) {
		tk = tknextfocus(top, -1);
		dir = -1;
	} else if(*wp == '\0') {
		tk = nil;
		dir = 0;
	} else {
		tk = tklook(top, wp, 0);
		if(tk == nil){
			tkerr(top, wp);
			free(wp);
			return TkBadwp;
		}
		dir = 0;
	}
	free(wp);

	tksetkeyfocus(top, tk, dir);
	return nil;
}

char*
tkraise(TkTop *t, char *arg, char **ret)
{
	Tk *tk;
	char *wp;

	USED(ret);

	wp = mallocz(Tkmaxitem, 0);
	if(wp == nil)
		return TkNomem;
	tkword(t, arg, wp, wp+Tkmaxitem, nil);
	tk = tklook(t, wp, 0);
	if(tk == nil){
		tkerr(t, wp);
		free(wp);
		return TkBadwp;
	}
	free(wp);

	if((tk->flag & Tkwindow) == 0)
		return TkNotwm;

	tkwreq(tk->env->top, "raise %s", tk->name->name);
	return nil;
}

char*
tklower(TkTop *t, char *arg, char **ret)
{
	Tk *tk;
	char *wp;

	USED(ret);
	wp = mallocz(Tkmaxitem, 0);
	if(wp == nil)
		return TkNomem;
	tkword(t, arg, wp, wp+Tkmaxitem, nil);
	tk = tklook(t, wp, 0);
	if(tk == nil){
		tkerr(t, wp);
		free(wp);
		return TkBadwp;
	}
	free(wp);

	if((tk->flag & Tkwindow) == 0)
		return TkNotwm;

	tkwreq(tk->env->top, "lower %s", tk->name->name);
	return nil;
}

char*
tkgrab(TkTop *t, char *arg, char **ret)
{
	Tk *tk;
	TkCtxt *c;
	char *r, *buf, *wp;

	USED(ret);

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;

	wp = mallocz(Tkmaxitem, 0);
	if(wp == nil) {
		free(buf);
		return TkNomem;
	}
	arg = tkword(t, arg, buf, buf+Tkmaxitem, nil);

	tkword(t, arg, wp, wp+Tkmaxitem, nil);
	tk = tklook(t, wp, 0);
	if(tk == nil) {
		free(buf);
		tkerr(t, wp);
		free(wp);
		return TkBadwp;
	}
	free(wp);

	c = t->ctxt;
	if(strcmp(buf, "release") == 0) {
		free(buf);
		if(c->mgrab == tk)
			tksetmgrab(t, nil);
		return nil;
	}
	if(strcmp(buf, "set") == 0) {
		free(buf);
		return tksetmgrab(t, tk);
	}
	if(strcmp(buf, "ifunset") == 0) {
		free(buf);
		if(c->mgrab == nil)
			return tksetmgrab(t, tk);
		return nil;
	}
	if(strcmp(buf, "status") == 0) {
		free(buf);
		r = "none";
		if ((c->mgrab != nil) && (c->mgrab->name != nil))
			r = c->mgrab->name->name;
		return tkvalue(ret, "%s", r);
	}
	free(buf);
	return TkBadcm;
}

char*
tkputs(TkTop *t, char *arg, char **ret)
{
	char *buf;

	USED(ret);

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	tkword(t, arg, buf, buf+Tkmaxitem, nil);
	print("%s\n", buf);
	free(buf);
	return nil;
}

char*
tkdestroy(TkTop *t, char *arg, char **ret)
{
	int found, len, isroot;
	Tk *tk, **l, *next, *slave;
	char *n, *e, *buf;

	USED(ret);
	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	e = nil;
	for(;;) {
		arg = tkword(t, arg, buf, buf+Tkmaxitem, nil);
		if(buf[0] == '\0')
			break;

		len = strlen(buf);
		found = 0;
		isroot = (strcmp(buf, ".") == 0);
		for(tk = t->root; tk; tk = tk->siblings) {
		        if (tk->name != nil) {
				n = tk->name->name;
				if(strcmp(buf, n) == 0) {
					tk->flag |= Tkdestroy;
					found = 1;
				} else if(isroot || (strncmp(buf, n, len) == 0 &&n[len] == '.'))
					tk->flag |= Tkdestroy;
			}
		}
		if(!found) {
			e = TkBadwp;
			tkerr(t, buf);
			break;
		}
	}
	free(buf);

	for(tk = t->root; tk; tk = tk->siblings) {
		if((tk->flag & Tkdestroy) == 0)
			continue;
		if(tk->flag & Tkwindow) {
			tkunmap(tk);
			if((tk->name != nil) 
			   && (strcmp(tk->name->name, ".") == 0))
				tk->flag &= ~Tkdestroy;
			else
				tkdeliver(tk, TkDestroy, nil);
		} else
			tkdeliver(tk, TkDestroy, nil);
		if(tk->destroyed != nil)
			tk->destroyed(tk);
		tkpackqit(tk->master);
		tkdelpack(tk);
		for (slave = tk->slave; slave != nil; slave = next) {
			next = slave->next;
			slave->master = nil;
			slave->next = nil;
		}
		tk->slave = nil;
		if(tk->parent != nil && tk->geom != nil)		/* XXX this appears to be bogus */
			tk->geom(tk, 0, 0, 0, 0);
		if(tk->grid){
			tkfreegrid(tk->grid);
			tk->grid = nil;
		}
	}
	tkrunpack(t);

	l = &t->windows;
	for(tk = t->windows; tk; tk = next) {
		next = TKobj(TkWin, tk)->next;
		if(tk->flag & Tkdestroy) {
			*l = next;
			continue;
		}
		l = &TKobj(TkWin, tk)->next;		
	}
	l = &t->root;
	for(tk = t->root; tk; tk = next) {
		next = tk->siblings;
		if(tk->flag & Tkdestroy) {
			*l = next;
			tkfreeobj(tk);
			continue;
		}
		l = &tk->siblings;
	}

	return e;
}

char*
tkupdatecmd(TkTop *t, char *arg, char **ret)
{
	Tk *tk;
	int x, y;
	Rectangle *dr;
	char buf[Tkmaxitem];

	USED(ret);

	tkword(t, arg, buf, buf+sizeof(buf), nil);
	if(strcmp(buf, "-onscreen") == 0){
		tk = t->root;
		dr = &t->screenr;
		x = tk->act.x;
		if(x+tk->act.width > dr->max.x)
			x = dr->max.x - tk->act.width;
		if(x < 0)
			x = 0;
		y = tk->act.y;
		if(y+tk->act.height > dr->max.y)
			y = dr->max.y - tk->act.height;
		if(y < 0)
			y = 0;
		tkmovewin(tk, Pt(x, y));
	}else if(strcmp(buf, "-disable") == 0){
		t->noupdate = 1;
	}else if(strcmp(buf, "-enable") == 0){
		t->noupdate = 0;
	}
	return tkupdate(t);
}

char*
tkwinfo(TkTop *t, char *arg, char **ret)
{
	Tk *tk;
	char *cmd, *arg1;

	cmd = mallocz(Tkmaxitem, 0);
	if(cmd == nil)
		return TkNomem;

	arg = tkword(t, arg, cmd, cmd+Tkmaxitem, nil);
	if(strcmp(cmd, "class") == 0) {
		arg1 = mallocz(Tkmaxitem, 0);
		if(arg1 == nil) {
			free(cmd);
			return TkNomem;
		}
		tkword(t, arg, arg1, arg1+Tkmaxitem, nil);
		tk = tklook(t, arg1, 0);
		if(tk == nil){
			tkerr(t, arg1);
			free(arg1);
			free(cmd);
			return TkBadwp;
		}
		free(arg1);
		free(cmd);
		return tkvalue(ret, "%s", tkmethod[tk->type]->name);
	}
	free(cmd);
	return TkBadvl;
}

char*
tkcursorcmd(TkTop *t, char *arg, char **ret)
{
	char *e;
	int locked;
	Display *d;
	TkCursor c;
	TkOptab tko[3];
	enum {Notset = 0x80000000};

	c.def = 0;
	c.p.x = Notset;
	c.p.y = Notset;
	c.bit = nil;
	c.img = nil;
	
	USED(ret);

	c.def = 0;
	tko[0].ptr = &c;
	tko[0].optab = tkcurop;
	tko[1].ptr = nil;
	e = tkparse(t, arg, tko, nil);
	if(e != nil)
		return e;

	d = t->display;
	locked = lockdisplay(d);
	if(c.def)
		tkcursorswitch(t, nil, nil);
	if(c.img != nil || c.bit != nil){
		e = tkcursorswitch(t, c.bit, c.img);
		tkimgput(c.img);
		freeimage(c.bit);
	}
	if(e == nil){
		if(c.p.x != Notset && c.p.y != Notset)
			tkcursorset(t, c.p);
	}
	if(locked)
		unlockdisplay(d);
	return e;	
}

char *
tkbindings(TkTop *t, Tk *tk, TkEbind *b, int blen)
{
	TkAction *a, **ap;
	char *cmd, *e;
	int i;

	e = nil;
	for(i = 0; e == nil && i < blen; i++)	/* default bindings */ {
		int how = TkArepl;
		char *cmd = b[i].cmd;
		if(cmd[0] == '+') {
			how = TkAadd;
			cmd++;
		}
		else if(cmd[0] == '-'){
			how = TkAsub;
			cmd++;
		}
		e = tkaction(&tk->binds, b[i].event, TkStatic, cmd, how);
	}
	
	if(e != nil)
		return e;

	ap = &tk->binds;
	for(a = t->binds[tk->type]; a; a = a->link) {	/* user "defaults" */
		cmd = strdup(a->arg);
		if(cmd == nil)
			return TkNomem;

		e = tkaction(ap, a->event, TkDynamic, cmd,
						(a->type >> 8) & 0xff);
		if(e != nil)
			return e;
		ap = &(*ap)->link;
	}
	return nil;
}
