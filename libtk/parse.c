#include "lib9.h"
#include "kernel.h"
#include "draw.h"
#include "tk.h"

#define	O(t, e)		((long)(&((t*)0)->e))

static char* pdist(TkTop*, TkOption*, void*, char**, char*, char*);
static char* pstab(TkTop*, TkOption*, void*, char**, char*, char*);
static char* ptext(TkTop*, TkOption*, void*, char**, char*, char*);
static char* pwinp(TkTop*, TkOption*, void*, char**, char*, char*);
static char* pbmap(TkTop*, TkOption*, void*, char**, char*, char*);
static char* pbool(TkTop*, TkOption*, void*, char**, char*, char*);
static char* pfont(TkTop*, TkOption*, void*, char**, char*, char*);
static char* pfrac(TkTop*, TkOption*, void*, char**, char*, char*);
static char* pnnfrac(TkTop*, TkOption*, void*, char**, char*, char*);
static char* pctag(TkTop*, TkOption*, void*, char**, char*, char*);
static char* ptabs(TkTop*, TkOption*, void*, char**, char*, char*);
static char* pcolr(TkTop*, TkOption*, void*, char**, char*, char*);
static char* pimag(TkTop*, TkOption*, void*, char**, char*, char*);
static char* psize(TkTop*, TkOption*, void*, char**, char*, char*);
static char* pnndist(TkTop*, TkOption*, void*, char**, char*, char*);
static char* pact(TkTop*, TkOption*, void*, char**, char*, char*);
static char* pignore(TkTop*, TkOption*, void*, char**, char*, char*);
static char* psticky(TkTop*, TkOption*, void*, char**, char*, char*);
static char* plist(TkTop*, TkOption*, void*, char**, char*, char*);

static char* (*oparse[])(TkTop*, TkOption*, void*, char**, char*, char*) =
{
	/* OPTdist */	pdist,
	/* OPTstab */	pstab,
	/* OPTtext */	ptext,
	/* OPTwinp */	pwinp,
	/* OPTflag */	pstab,
	/* OPTbmap */	pbmap,
	/* OPTbool */	pbool,
	/* OPTfont */	pfont,
	/* OPTfrac */	pfrac,
	/* OPTnnfrac */	pnnfrac,
	/* OPTctag */	pctag,
	/* OPTtabs */	ptabs,
	/* OPTcolr */	pcolr,
	/* OPTimag */	pimag,
	/* OPTsize */	psize,
	/* OPTnndist */	pnndist,
	/* OPTact */	pact,
	/* OPTignore */	pignore,
	/* OPTsticky */	psticky,
	/* OPTlist */ plist,
};

char*
tkskip(char *s, char *bl)
{
	char *p;

	while(*s) {
		for(p = bl; *p; p++)
			if(*p == *s)
				break;
		if(*p == '\0')
			return s;	
		s++;
	}
	return s;
}

/* XXX - Tad: error propagation? */
char*
tkword(TkTop *t, char *str, char *buf, char *ebuf, int *gotarg)
{
	int c, lev, tmp;
	char *val, *e, *p, *cmd;
	if (gotarg == nil)
		gotarg = &tmp;

	/*
	 * ebuf is one beyond last byte in buf; leave room for nul byte in
	 * all cases.
	 */
	--ebuf;

	str = tkskip(str, " \t");
	*gotarg = 1;
	lev = 1;
	switch(*str) {
	case '{':
		/* XXX - DBK: According to Ousterhout (p.37), while back=
		 * slashed braces don't count toward finding the matching
		 * closing braces, the backslashes should not be removed.
		 * Presumably this also applies to other backslashed
		 * characters: the backslash should not be removed.
		 */
		str++;
		while(*str && buf < ebuf) {
			c = *str++;
			if(c == '\\') {
				if(*str == '}' || *str == '{' || *str == '\\')
					c = *str++;
			} else if(c == '}') {
				lev--;
				if(lev == 0)
					break;
			} else if(c == '{')
				lev++;
			*buf++ = c;
		}
		break;
	case '[':
		/* XXX - DBK: According to Ousterhout (p. 33) command
		 * substitution may occur anywhere within a word, not
		 * only (as here) at the beginning.
		 */
		cmd = malloc(strlen(str));	/* not strlen+1 because the first character is skipped */
		if ( cmd == nil ) {
			buf[0] = '\0';	/* DBK - Why not an error message? */
			return str;
		}
		p = cmd;
		str++;
		while(*str) {
			c = *str++;
			if(c == '\\') {
				if(*str == ']' || *str == '[' || *str == '\\')
					c = *str++;
			} else if(c == ']') {
				lev--;
				if(lev == 0)
					break;
			} else if(c == '[')
				lev++;
			*p++ = c;
		}
		*p = '\0';
		val = nil;
		e = tkexec(t, cmd, &val);
		free(cmd);
		 /* XXX - Tad: is this appropriate behavior?
		  *	      Am I sure that the error doesn't need to be
		  *	      propagated back to the caller?
		  */
		if(e == nil && val != nil) {
			strncpy(buf, val, ebuf-buf);
			buf = ebuf;
			free(val);
		}
		break;
	case '\'':
		str++;
		while(*str && buf < ebuf)
			*buf++ = *str++;
		break;
	case '\0':
		*gotarg = 0;
		break;
	default:
		/* XXX - DBK: See comment above about command substitution.
		 * Also, any backslashed character should be replaced by
		 * itself (e.g. to put a space, tab, or [ into a word.
		 * We assume that the C compiler has already done the
		 * standard ANSI C substitutions.  (But should we?)
		 */
		while(*str && *str != ' ' && *str != '\t' && buf < ebuf)
			*buf++ = *str++;
	}
	*buf = '\0';
	return str;
}

static TkOption*
Getopt(TkOption *o, char *buf)
{
	while(o->o != nil) {
		if(strcmp(buf, o->o) == 0)
			return o;
		o++;
	}
	return nil;
}

TkName*
tkmkname(char *name)
{
	TkName *n;

	n = malloc(sizeof(struct TkName)+strlen(name));
	if(n == nil)
		return nil;
	strcpy(n->name, name);
	n->link = nil;
	n->obj = nil;
	return n;
}

char*
tkparse(TkTop *t, char *str, TkOptab *ot, TkName **nl)
{
	int l;
	TkOptab *ft;
	TkOption *o;
	TkName *f, *n;
	char *e, *buf, *ebuf;

	l = strlen(str);
	if (l < Tkmaxitem)
		l = Tkmaxitem;
	buf = malloc(l + 1);
	if(buf == 0)
		return TkNomem;
	ebuf = buf + l + 1;

	e = nil;
	while(e == nil) {
		str = tkword(t, str, buf, ebuf, nil);
		switch(*buf) {
		case '\0':
			goto done;
		case '-':
			if (buf[1] != '\0') {
				for(ft = ot; ft->ptr; ft++) {
					o = Getopt(ft->optab, buf+1);
					if(o != nil) {
						e = oparse[o->type](t, o, ft->ptr, &str, buf, ebuf);
						break;
					}
				}
				if(ft->ptr == nil){
					e = TkBadop;
					tkerr(t, buf);
				}
				break;
			}
			/* fall through if we've got a singleton '-' */
		default:
			if(nl == nil) {
				e = TkBadop;
				tkerr(t, buf);
				break;
			}
			n = tkmkname(buf);
			if(n == nil) {
				e = TkNomem;
				break;
			}
			if(*nl == nil)
				*nl = n;
			else {
				for(f = *nl; f->link; f = f->link)
					;
				f->link = n;
			}
		}		
	}

	if(e != nil && nl != nil)
		tkfreename(*nl);
done:
	free(buf);
	return e;
}

char*
tkconflist(TkOptab *ot, char **val)
{
	TkOption *o;
	char *f, *e;

	f = "-%s";
	while(ot->ptr != nil) {
		o = ot->optab;
		while(o->o != nil) {
			e = tkvalue(val, f, o->o);
			if(e != nil)
				return e;
			f = " -%s";
			o++;
		}
		ot++;
	}
	return nil;
}

char*
tkgencget(TkOptab *ft, char *arg, char **val, TkTop *t)
{
	Tk *w;
	char *c;
	Point g;
	TkEnv *e;
	TkStab *s;
	TkOption *o;
	int wh, con, i, n, flag, *v;
	char *r, *buf, *fmt;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;

	tkitem(buf, arg);
	r = buf;
	if(*r == '-')
		r++;
	o = nil;
	while(ft->ptr) {
		o = Getopt(ft->optab, r);
		if(o != nil)
			break;
		ft++;
	}
	if(o == nil) {
		tkerr(t, r);
		free(buf);
		return TkBadop;
	}

	switch(o->type) {
	default:
		tkerr(t, r);
		free(buf);
		return TkBadop;
	case OPTignore:
		return nil;
	case OPTact:
		w = ft->ptr;
		g = tkposn(w);
		n = g.y;
		if(o->aux == 0)
			n = g.x;
		free(buf);
		return tkvalue(val, "%d", n);
	case OPTdist:
	case OPTnndist:
		free(buf);
		return tkvalue(val, "%d", OPTION(ft->ptr, int, o->offset));
	case OPTsize:
		w = ft->ptr;
		if(strcmp(r, "width") == 0)
			wh = w->req.width;
		else
			wh = w->req.height;
		free(buf);
		return tkvalue(val, "%d", wh);
	case OPTtext:
		c = OPTION(ft->ptr, char*, o->offset);
		if(c == nil)
			c = "";
		free(buf);
		return tkvalue(val, "%s", c);
	case OPTwinp:
		w = OPTION(ft->ptr, Tk*, o->offset);
		if(w == nil || w->name == nil)
			c = "";
		else
			c = w->name->name;
		free(buf);
		return tkvalue(val, "%s", c);
	case OPTstab:
		s = o->aux;
		c = "";
		con = OPTION(ft->ptr, int, o->offset);
		while(s->val) {
			if(con == s->con) {
				c = s->val;
				break;
			}
			s++;
		}
		free(buf);
		return tkvalue(val, "%s", c);
	case OPTflag:
		con = OPTION(ft->ptr, int, o->offset);
		flag = 0;
		for (s = o->aux; s->val != nil; s++)
			flag |= s->con;
		c = "";
		for (s = o->aux; s->val != nil; s++) {
			if ((con & flag) == s->con) {
				c = s->val;
				break;
			}
		}
		free(buf);
		return tkvalue(val, "%s", c);
	case OPTfont:
		e = OPTION(ft->ptr, TkEnv*, o->offset);
		free(buf);
		if (e->font != nil)
			return tkvalue(val, "%s", e->font->name);
		return nil;
	case OPTcolr:
		e = OPTION(ft->ptr, TkEnv*, o->offset);
		i = AUXI(o->aux);
		free(buf);
		return tkvalue(val, "#%.8lux", e->colors[i]);
	case OPTfrac:
	case OPTnnfrac:
		v = &OPTION(ft->ptr, int, o->offset);
		n = (int)o->aux;
		if(n == 0)
			n = 1;
		fmt = "%s";
		for(i = 0; i < n; i++) {
			tkfprint(buf, *v++);
			r = tkvalue(val, fmt, buf);
			if(r != nil) {
				free(buf);
				return r;
			}
			fmt = " %s";
		}
		free(buf);
		return nil;
	case OPTbmap:
		return tkvalue(val, "%d", OPTION(ft->ptr, Image*, o->offset) != nil);
	case OPTimag:
		return tkvalue(val, "%d", OPTION(ft->ptr, TkImg*, o->offset) != nil);
	}
}

static char*
pact(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	USED(buf);
	USED(ebuf);
	USED(str);
	USED(place);
	tkerr(t, o->o);
	return TkBadop;
}

static char*
pignore(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	char *p;
	USED(t);
	USED(o);
	USED(place);

	p = tkword(t, *str, buf, ebuf, nil);
	if(*buf == '\0')
		return TkOparg;
	*str = p;
	return nil;
}

static char*
pdist(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	int d;
	char *e;
	TkEnv *env;

	USED(buf);
	USED(ebuf);

	/*
	 * this is a bit of a hack, as 0 is a valid option offset,
	 * but a nil aux is commonly used when 'w' and 'h' suffixes
	 * aren't appropriate.
	 * just make sure that no structure placed in TkOptab->ptr
	 * with an OPTdist element has a TkEnv as its first member.
	 */

	if (o->aux == nil)
		env = nil;
	else
		env = OPTION(place, TkEnv*, AUXI(o->aux));
	e = tkfracword(t, str, &d, env);
	if(e != nil)
		return e;
	OPTION(place, int, o->offset) = TKF2I(d);
	return nil;
}

static char*
pnndist(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	char* e;
	int oldv;

	oldv = OPTION(place, int, o->offset);
	e = pdist(t, o, place, str, buf, ebuf);
	if(e == nil && OPTION(place, int, o->offset) < 0) {
		OPTION(place, int, o->offset) = oldv;
		return TkBadvl;
	}
	return e;	
}

static char*
psize(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	Tk *tk;
	char *e;
	int d, off;

	USED(ebuf);
	e = tkfracword(t, str, &d, OPTION(place, TkEnv*, AUXI(o->aux)));
	if (e != nil)
		return e;
	if(d < 0)
		return TkBadvl;

	tk = place;
	/*
	 * XXX there's no way of resetting Tksetwidth or Tksetheight.
	 * could perhaps allow it by setting width/height to {}
	 */
	if(strcmp(buf+1, "width") == 0) {
		tk->flag |= Tksetwidth;
		off = O(Tk, req.width);
	}
	else {
		tk->flag |= Tksetheight;
		off = O(Tk, req.height);
	}
	OPTION(place, int, off) = TKF2I(d);
	return nil;
}

static char*
pstab(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	char *p;
	int mask;
	TkStab *s, *c;

	p = tkword(t, *str, buf, ebuf, nil);
	if(*buf == '\0')
		return TkOparg;

	for(s = o->aux; s->val; s++)
		if(strcmp(s->val, buf) == 0)
			break;
	if(s->val == nil)
		return TkBadvl;

	*str = p;
	if(o->type == OPTstab) {
		OPTION(place, int, o->offset) = s->con;
		return nil;
	}

	mask = 0;
	for(c = o->aux; c->val; c++)
		mask |= c->con;

	OPTION(place, int, o->offset) &= ~mask;
	OPTION(place, int, o->offset) |= s->con;

	/*
	 * a hack, but otherwise we have to dirty the focus order
	 * every time any command is executed on a widget
	 */
	if (!strcmp(o->o, "takefocus"))
		tkdirtyfocusorder(t);
	return nil;
}

enum {
	Stickyn = (1<<0),
	Stickye = (1<<1),
	Stickys = (1<<2),
	Stickyw = (1<<3)
};

static int stickymap[16] =
{
	0,
	Tknorth,
	Tkeast,
	Tknorth|Tkeast,
	Tksouth,
	Tkfilly,
	Tksouth|Tkeast,
	Tkeast|Tkfilly,
	Tkwest,
	Tknorth|Tkwest,
	Tkfillx,
	Tknorth|Tkfillx,
	Tksouth|Tkwest,
	Tkwest|Tkfilly,
	Tksouth|Tkfillx,
	Tkfillx|Tkfilly,
};

static char*
psticky(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	char *p, *s;
	int flag, sflag;

	p = tkword(t, *str, buf, ebuf, nil);
	*str = p;

	flag = 0;
	for (s = buf; *s; s++) {
		switch (*s) {
		case 'n':
			flag |= Stickyn;
			break;
		case 's':
			flag |= Stickys;
			break;
		case 'e':
			flag |= Stickye;
			break;
		case 'w':
			flag |= Stickyw;
			break;
		case ' ':
		case ',':
			break;
		default:
			return TkBadvl;
		}
	}
	sflag =  OPTION(place, int, o->offset) & ~(Tkanchor|Tkfill);
	OPTION(place, int, o->offset) = sflag | stickymap[flag];
	return nil;
}

static char*
ptext(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	char **p;

	*str = tkword(t, *str, buf, ebuf, nil);

	p = &OPTION(place, char*, o->offset);
	if(*p != nil)
		free(*p);
	if(buf[0] == '\0')
		*p = nil;
	else {
		*p = strdup(buf);
		if(*p == nil)
			return TkNomem;
	}
	return nil;
}

static char*
pimag(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	int locked;
	Display *d;
	TkImg **p, *i;

	i = nil;
	p = &OPTION(place, TkImg*, o->offset);
	*str = tkword(t, *str, buf, ebuf, nil);
	if(*buf != '\0') {
		i = tkname2img(t, buf);
		if(i == nil)
			return TkBadvl;
		i->ref++;
	}

	if(*p != nil) {
		d = t->display;
		locked = lockdisplay(d);
		tkimgput(*p);
		if(locked)
			unlockdisplay(d);
	}
	*p = i;
	return nil;
}

static char*
pbmap(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	Display *d;
	Image *i, **p;
	int locked, fd;
	char *c;

	p = &OPTION(place, Image*, o->offset);

	d = t->display;
	*str = tkword(t, *str, buf, ebuf, nil);
	if(*buf == '\0' || *buf == '-') {
		if(*p != nil) {
			locked = lockdisplay(d);
			freeimage(*p);
			if(locked)
				unlockdisplay(d);
			*p = nil;
		}
		return nil;
	}

	if(buf[0] == '@')
		i = display_open(d, buf+1);
 else if(buf[0] == '<') {
		buf++;
		fd = strtoul(buf, &c, 0);
		if(c == buf) {
			return TkBadvl;
		}
		i = readimage(d, fd, 1);
	}
	else {
		char *file;

		file = mallocz(Tkmaxitem, 0);
		if(file == nil)
			return TkNomem;

		snprint(file, Tkmaxitem, "/icons/tk/%s", buf);
		i = display_open(d, file);
		free(file);
	}
	if(i == nil)
		return TkBadbm;

	if(*p != nil) {
		locked = lockdisplay(d);
		freeimage(*p);
		if(locked)
			unlockdisplay(d);
	}
	*p = i;
	return nil;
}

static char*
pfont(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	TkEnv *e;
	Display *d;
	int locked;
	Font *font;

	*str = tkword(t, *str, buf, ebuf, nil);
	if(*buf == '\0')
		return TkOparg;

	d = t->display;
	font = font_open(d, buf);
	if(font == nil)
		return TkBadft;

	e = tkdupenv(&OPTION(place, TkEnv*, o->offset));
	if(e == nil) {
		freefont(font);		/* XXX lockdisplay around this? */
		return TkNomem;
	}
	if(e->font)
		font_close(e->font);
	e->font = font;

	locked = lockdisplay(d);
	e->wzero = stringwidth(font, "0");
	if ( e->wzero <= 0 )
		e->wzero = e->font->height / 2;
	if(locked)
		unlockdisplay(d);

	return nil;
}

static int
hex(int c)
{
	if(c >= 'a')
		c -= 'a'-'A';
	if(c >= 'A')
		c = 10 + (c - 'A');
	else
		c -= '0';
	return c;
}

static ulong
changecol(TkEnv *e, int setcol, int col, ulong rgba)
{
	if (setcol) {
		e->set |= (1<<col);
	} else {
		rgba = 0;
		e->set &= ~(1<<col);
	}
	e->colors[col] = rgba;
	return rgba;
}

char*
tkparsecolor(char *buf, ulong *rgba)
{
	char *p, *q, *e;
	int R, G, B, A;
	int i, alpha, len, alen;
	/*
	 * look for alpha modifier in *#AA or *0.5 format
	 */
	len = strlen(buf);
	p = strchr(buf, '*');
	if(p != nil) {
		alen = len - (p - buf);
		if(p[1] == '#') {
			if(alen != 4)
				return TkBadvl;
			alpha = (hex(p[2])<<4) | (hex(p[3]));
		} else {
			q = p+1;
			e = tkfrac(&q, &alpha, nil);
			if (e != nil)
				return e;
			alpha = TKF2I(alpha * 0xff);
		}
		*p = '\0';
		len -= alen;
	} else
		alpha = 0xff;
	
	if (*buf == '#') {
		switch(len) {
		case 4:			/* #RGB */
			R = hex(buf[1]);
			G = hex(buf[2]);
			B = hex(buf[3]);
			*rgba = (R<<28) | (G<<20) | (B<<12) | 0xff;
			break;
		case 7:			/* #RRGGBB */
			R = (hex(buf[1])<<4)|(hex(buf[2]));
			G = (hex(buf[3])<<4)|(hex(buf[4]));
			B = (hex(buf[5])<<4)|(hex(buf[6]));
			*rgba = (R<<24) | (G<<16) | (B<<8) | 0xff;
			break;
		case 9:			/* #RRGGBBAA */
			R = (hex(buf[1])<<4)|(hex(buf[2]));
			G = (hex(buf[3])<<4)|(hex(buf[4]));
			B = (hex(buf[5])<<4)|(hex(buf[6]));
			A = (hex(buf[7])<<4)|(hex(buf[8]));
			*rgba = (R<<24) | (G<<16) | (B<<8) | A;
			break;
		default:
			return TkBadvl;
		}
	} else {
		for(i = 0; tkcolortab[i].val != nil; i++)
			if (!strcmp(tkcolortab[i].val, buf))
				break;
		if (tkcolortab[i].val == nil)
			return TkBadvl;
		*rgba = tkcolortab[i].con;
	}
	if (alpha != 0xff) {
		tkrgbavals(*rgba, &R, &G, &B, &A);
		A = (A * alpha) / 255;
		*rgba = tkrgba(R, G, B, A);
	}
	return nil;
}

static char*
pcolr(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	TkEnv *env;
	char *e;
	ulong rgba, dark, light;
	int color, setcol;

	*str = tkword(t, *str, buf, ebuf, nil);
	rgba = 0;
	if(*buf == '\0') {
		setcol = 0;
	} else {
		setcol = 1;
		e = tkparsecolor(buf, &rgba);
		if(e != nil)
			return e;
	}
		
	env = tkdupenv(&OPTION(place, TkEnv*, o->offset));
	if(env == nil)
		return TkNomem;

	color = AUXI(o->aux);
	rgba = changecol(env, setcol, color, rgba);
	if(color == TkCbackgnd || color == TkCselectbgnd || color == TkCactivebgnd) {
		if (setcol) {
			light = tkrgbashade(rgba, TkLightshade);
			dark = tkrgbashade(rgba, TkDarkshade);
		} else
			light = dark = 0;
		changecol(env, setcol, color+1, light);
		changecol(env, setcol, color+2, dark);
	}
	return nil;
}

static char*
pbool(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	USED(buf);
	USED(ebuf);
	USED(str);
	USED(t);
	OPTION(place, int, o->offset) = 1;
	return nil;
}

static char*
pwinp(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	Tk *f;
	char *p;

	p = tkword(t, *str, buf, ebuf, nil);
	if(*buf == '\0')
		return TkOparg;
	*str = p;
	
	f = tklook(t, buf, 0);
	if(f == nil){
		tkerr(t, buf);
		return TkBadwp;
	}

	OPTION(place, Tk*, o->offset) = f;
	return nil;
}

static char*
pctag(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	char *p;
	TkName *n, *l;

	*str = tkword(t, *str, buf, ebuf, nil);

	l = nil;
	p = buf;
	while(*p) {
		p = tkskip(p, " \t");
		buf = p;
		while(*p && *p != ' ' && *p != '\t')
			p++;
		if(*p != '\0')
			*p++ = '\0';

		if(p == buf || buf[0] >= '0' && buf[0] <= '9') {
			tkfreename(l);
			return TkBadtg;
		}
		n = tkmkname(buf);
		if(n == nil) {
			tkfreename(l);
			return TkNomem;
		}
		n->link = l;
		l = n;
	}
	tkfreename(OPTION(place, TkName*, o->offset));
	OPTION(place, TkName*, o->offset) = l;
	return nil;
}

static char*
pfrac(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	char *p, *e;
	int i, n, d, *v;

	*str = tkword(t, *str, buf, ebuf, nil);

	v = &OPTION(place, int, o->offset);
	n = (int)o->aux;
	if(n == 0)
		n = 1;
	p = buf;
	for(i = 0; i < n; i++) {
		p = tkskip(p, " \t");
		if(*p == '\0')
			return TkOparg;
		e = tkfracword(t, &p, &d, nil);
		if (e != nil)
			return e;
		*v++ = d;
	}
	return nil;
}

/*
 * N.B. nnfrac only accepts aux==nil (can't deal with several items)
 */
static char*
pnnfrac(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	int oldv;
	char *e;

	oldv = OPTION(place, int, o->offset);

	e = pfrac(t, o, place, str, buf, ebuf);
	if(e == nil && OPTION(place, int, o->offset) < 0) {
		OPTION(place, int, o->offset) = oldv;
		return TkBadvl;
	}
	return e;	

}

typedef struct Tabspec {
	int	dist;
	int	just;
	TkEnv	*env;
} Tabspec;

static char*
ptabs(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	char *e, *p, *eibuf;
	TkOption opd, opj;
	Tabspec tspec;
	TkTtabstop *tabfirst, *tab, *tabprev;
	char *ibuf;

	ibuf = mallocz(Tkmaxitem, 0);
	if(ibuf == nil)
		return TkNomem;
	eibuf = ibuf + Tkmaxitem;
	tspec.env = OPTION(place, TkEnv*, AUXI(o->aux));
	opd.offset = O(Tabspec, dist);
	opd.aux = IAUX(O(Tabspec, env));
	opj.offset = O(Tabspec, dist);
	opj.aux = tktabjust;
	tabprev = nil;
	tabfirst = nil;

	p = tkword(t, *str, buf, ebuf, nil);
	if(*buf == '\0') {
		free(ibuf);
		return TkOparg;
	}
	*str = p;

	p = buf;
	while(*p != '\0') {
		e = pdist(t, &opd, &tspec, &p, ibuf, eibuf);
		if(e != nil) {
			free(ibuf);
			return e;
		}

		e = pstab(t, &opj, &tspec, &p, ibuf, eibuf);
		if(e != nil)
			tspec.just = Tkleft;

		tab = malloc(sizeof(TkTtabstop));
		if(tab == nil) {
			free(ibuf);
			return TkNomem;
		}

		tab->pos = tspec.dist;
		tab->justify = tspec.just;
		tab->next = nil;
		if(tabfirst == nil)
			tabfirst = tab;
		else
			tabprev->next = tab;
		tabprev = tab;
	}
	free(ibuf);

	tab = OPTION(place, TkTtabstop*, o->offset);
	if(tab != nil)
		free(tab);
	OPTION(place, TkTtabstop*, o->offset) = tabfirst;
	return nil;
}

char*
tkxyparse(Tk* tk, char **parg, Point *p)
{
	char *buf;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;

	*parg = tkword(tk->env->top, *parg, buf, buf+Tkmaxitem, nil);
	if(*buf == '\0') {
		free(buf);
		return TkOparg;
	}
	p->x = atoi(buf);

	*parg = tkword(tk->env->top, *parg, buf, buf+Tkmaxitem, nil);
	if(*buf == '\0') {
		free(buf);
		return TkOparg;
	}
	p->y = atoi(buf);

	free(buf);
	return nil;
}

static char*
plist(TkTop *t, TkOption *o, void *place, char **str, char *buf, char *ebuf)
{
	char *w, ***p, *wbuf, *ewbuf, **v, **nv;
	int n, m, i, found;

	*str = tkword(t, *str, buf, ebuf, nil);
	n = strlen(buf) + 1;
	wbuf = mallocz(n, 0);
	if (wbuf == nil)
		return TkNomem;		/* XXX should we free old values too? */
	ewbuf = &wbuf[n];

	p = &OPTION(place, char**, o->offset);
	if (*p != nil){
		for (v = *p; *v; v++)
			free(*v);
		free(*p);
	}
	n = 0;
	m = 4;
	w = buf;
	v = malloc(m * sizeof(char*));
	if (v == nil)
		goto Error;
	for (;;) {
		w = tkword(t, w, wbuf, ewbuf, &found);
		if (!found)
			break;
		if (n == m - 1) {
			m += m/2;
			nv = realloc(v, m * sizeof(char*));
			if (nv == nil)
				goto Error;
			v = nv;
		}
		v[n] = strdup(wbuf);
		if (v[n] == nil)
			goto Error;
		n++;
	}
	v[n++] = nil;
	*p = realloc(v, n * sizeof(char*));
	free(wbuf);
	return nil;
Error:
	free(buf);
	for (i = 0; i < n; i++)
		free(v[i]);
	free(v);
	*p = nil;
	return TkNomem;
}
