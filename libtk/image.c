#include "lib9.h"
#include <kernel.h>
#include "draw.h"
#include "tk.h"

#define	O(t, e)		((long)(&((t*)0)->e))

char*	tkimgbmcreate(TkTop*, char*, int, char**);
char*	tkimgbmdel(TkImg*);
void	tkimgbmfree(TkImg*);

static Rectangle huger = { -1000000, -1000000, 1000000, 1000000 };

typedef struct TkImgtype TkImgtype;
struct TkImgtype
{
	char*	type;
	char*	(*create)(TkTop*, char*, int, char**);
	char*	(*delete)(TkImg*);
	void	(*destroy)(TkImg*);
} tkimgopts[] = 
{
	"bitmap",	tkimgbmcreate,		tkimgbmdel, 	tkimgbmfree,
	nil,
};

typedef struct Imgargs Imgargs;
struct Imgargs {
	Image*	fgimg;
	Image*	maskimg;
};

TkImg*
tkname2img(TkTop *t, char *name)
{
	TkImg *tki;

	for(tki = t->imgs; tki; tki = tki->link)
		if((tki->name != nil) && strcmp(tki->name->name, name) == 0)
			return tki;

	return nil;
}

TkOption
bitopt[] =
{
	"file",		OPTbmap,	O(Imgargs, fgimg),	nil,
	"maskfile",	OPTbmap,	O(Imgargs, maskimg),	nil,
	nil
};

void
tksizeimage(Tk *tk, TkImg *tki)
{
	int dx, dy, repack;

	dx = 0;
	dy = 0;
	if(tki->img != nil) {
		dx = Dx(tki->img->r);
		dy = Dy(tki->img->r);
	}
	repack = 0;
	if(tki->ref > 1 && (tki->w != dx || tki->h != dy))
		repack = 1;
	tki->w = dx;
	tki->h = dy;

	if(repack) {
		tkpackqit(tk);
		tkrunpack(tk->env->top);
	}
}

char*
tkimgbmcreate(TkTop *t, char *arg, int type, char **ret)
{
	TkName *names;
	TkImg *tki, *f;
	TkOptab tko[2];
	char buf[32];
	static int id;
	char *e = nil;
	Imgargs iargs;
	Rectangle r;
	Display *d;
	int chan;
	int locked;

	d = t->display;
	locked = 0;

	tki = malloc(sizeof(TkImg));
	if(tki == nil)
		return TkNomem;

	tki->env = tkdefaultenv(t);
	if(tki->env == nil)
		goto err;
	tki->type = type;
	tki->ref = 1;
	tki->top = t;

	iargs.fgimg = nil;
	iargs.maskimg = nil;

	tko[0].ptr = &iargs;
	tko[0].optab = bitopt;
	tko[1].ptr = nil;

	names = nil;
	e = tkparse(t, arg, tko, &names);
	if(e != nil)
		goto err;

	if (iargs.fgimg == nil && iargs.maskimg != nil) {
		locked = lockdisplay(d);
		r = Rect(0, 0, Dx(iargs.maskimg->r), Dy(iargs.maskimg->r));
		tki->img = allocimage(d, r, CHAN2(CAlpha, 8, CGrey, 8), 0, DTransparent);
		if (tki->img != nil)
			draw(tki->img, r, nil, iargs.maskimg, iargs.maskimg->r.min);
		freeimage(iargs.maskimg);

	} else if (iargs.fgimg != nil && iargs.maskimg != nil) {
		locked = lockdisplay(d);
		r = Rect(0, 0, Dx(iargs.fgimg->r), Dy(iargs.fgimg->r));
		if (tkchanhastype(iargs.fgimg->chan, CGrey))
			chan = CHAN2(CAlpha, 8, CGrey, 8);
		else
			chan = RGBA32;
		tki->img = allocimage(d, r, chan, 0, DTransparent);
		if (tki->img != nil)
			draw(tki->img, r, iargs.fgimg, iargs.maskimg, iargs.fgimg->r.min);
		freeimage(iargs.fgimg);
		freeimage(iargs.maskimg);
	} else {
		tki->img = iargs.fgimg;
	}
	if (locked)
		unlockdisplay(d);

	if(names == nil) {
		sprint(buf, "image%d", id++);
		tki->name = tkmkname(buf);
		if(tki->name == nil)
			goto err;
	}
	else {
		/* XXX should mark as dirty any widgets using the named
		 * image - some notification scheme needs putting in place
		 */
		tki->name = names;
		tkfreename(names->link);
		names->link = nil;
	}

	tksizeimage(t->root, tki);

	if (tki->name != nil) {
		f = tkname2img(t, tki->name->name);
		if(f != nil)
			tkimgopts[f->type].delete(f);
	}

	tki->link = t->imgs;
	t->imgs = tki;
	
	if (tki->name != nil) {
		e = tkvalue(ret, "%s", tki->name->name);
		if(e == nil)
			return nil;
	}
err:
	tkputenv(tki->env);
	if(tki->img != nil) {
		locked = lockdisplay(d);
		freeimage(tki->img);
		if (locked)
			unlockdisplay(d);
	}
	tkfreename(tki->name);
	free(tki);
	return e != nil ? e : TkNomem;
}

char*
tkimgbmdel(TkImg *tki)
{
	TkImg **l, *f;

	l = &tki->top->imgs;
	for(f = *l; f; f = f->link) {
		if(f == tki) {
			*l = tki->link;
			tkimgput(tki);
			return nil;
		}
		l = &f->link;
	}
	return TkBadvl;
}

void
tkimgbmfree(TkImg *tki)
{
	int locked;
	Display *d;

	d = tki->top->display;
	locked = lockdisplay(d);
	freeimage(tki->img);
	if(locked)
		unlockdisplay(d);

	free(tki->cursor);
	tkfreename(tki->name);
	tkputenv(tki->env);

	free(tki);
}

char*
tkimage(TkTop *t, char *arg, char **ret)
{
	int i;
	TkImg *tkim;
	char *fmt, *e, *buf, *cmd;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	cmd = mallocz(Tkminitem, 0);
	if(cmd == nil) {
		free(buf);
		return TkNomem;
	}

	arg = tkword(t, arg, cmd, cmd+Tkminitem, nil);
	if(strcmp(cmd, "create") == 0) {
		arg = tkword(t, arg, buf, buf+Tkmaxitem, nil);
		for(i = 0; tkimgopts[i].type != nil; i++)
			if(strcmp(buf, tkimgopts[i].type) == 0) {
				e = tkimgopts[i].create(t, arg, i, ret);
				goto ret;
			}
		e = TkBadvl;
		goto ret;
	}
	if(strcmp(cmd, "names") == 0) {
		fmt = "%s";
		for(tkim = t->imgs; tkim; tkim = tkim->link) {
		        if (tkim->name != nil) {
				e = tkvalue(ret, fmt, tkim->name->name);
				if(e != nil)
					goto ret;
			}
			fmt = " %s";
		}
		e = nil;
		goto ret;
	}

	arg = tkword(t, arg, buf, buf+Tkmaxitem, nil);
	tkim = tkname2img(t, buf);
	if(tkim == nil) {
		e = TkBadvl;
		goto ret;
	}

	if(strcmp(cmd, "height") == 0) {
		e = tkvalue(ret, "%d", tkim->h);
		goto ret;
	}
	if(strcmp(cmd, "width") == 0) {
		e = tkvalue(ret, "%d", tkim->w);
		goto ret;
	}
	if(strcmp(cmd, "type") == 0) {
		e = tkvalue(ret, "%s", tkimgopts[tkim->type].type);
		goto ret;
	}
	if(strcmp(cmd, "delete") == 0) {
		for (;;) {
			e = tkimgopts[tkim->type].delete(tkim);
			if (e != nil)
				break;
			arg = tkword(t, arg, buf, buf+Tkmaxitem, nil);
			if (buf[0] == '\0')
				 break;
			tkim = tkname2img(t, buf);
			if (tkim == nil) {
				e = TkBadvl;
				break;
			}
		}
		goto ret;
	}

	e = TkBadcm;
ret:
	free(cmd);
	free(buf);
	return e;
}

void
tkimgput(TkImg *tki)
{
	if(tki == nil)
		return;

	if(--tki->ref > 0)
		return;

	tkimgopts[tki->type].destroy(tki);	
}

TkImg*
tkauximage(TkTop *t, char* s, TkMemimage *m, int repl)
{
	TkName *name;
	TkCtxt *c;
	TkImg *tki;
	Display *d;
	Image *i;
	int locked, nbytes;

	tki = tkname2img(t, s);
	if (tki != nil) {
		tki->ref++;
		return tki;
	}

	name = tkmkname(s);
	if (name == nil)
		return nil;
	tki = mallocz(sizeof(*tki), 1);
	if (tki == nil)
		goto err;
	tki->env = tkdefaultenv(t);
	if(tki->env == nil)
		goto err;

	c = t->ctxt;
	d = c->display;

	nbytes = bytesperline(m->r, chantodepth(m->chans))*Dy(m->r);
	locked = lockdisplay(d);
	i = allocimage(d, m->r, m->chans, repl, DTransparent);
	if (i != nil) {
		if (loadimage(i, m->r, m->data, nbytes) != nbytes) {
			freeimage(i);
			i = nil;
		}
		if (repl)
			replclipr(i, 1, huger);	/* TO DO: doesn't allocimage do this? */
	}
	if (locked)
		unlockdisplay(d);
	if (i == nil)
		goto err;
	tki->top = t;
	tki->ref = 2;	/* t->imgs ref and the ref we are returning */
	tki->type = 0;	/* bitmap */
	tki->w = Dx(m->r);
	tki->h = Dy(m->r);
	tki->img = i;
	tki->name = name;
	tki->link = t->imgs;
	t->imgs = tki;
	return tki;
err:
	if (tki != nil) {
		tkputenv(tki->env);
		free(tki);
	}
	tkfreename(name);
	return nil;
}
