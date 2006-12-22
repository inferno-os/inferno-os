#include <lib9.h>
#include <kernel.h>
#include "interp.h"
#include "isa.h"
#include "runt.h"
#include "raise.h"
#include "drawmod.h"
#include "draw.h"
#include "drawif.h"
#include "memdraw.h"
#include "memlayer.h"

/*
 * When a Display is remote, it must be locked to synchronize the
 * outgoing message buffer with the refresh demon, which runs as a
 * different process.  When it is local, the refresh demon does nothing
 * and it is sufficient to use the interpreter's own acquire/release protection
 * to lock the buffer.
 *
 * Most action to the buffer is caused by calls from Limbo, so locking at
 * the top before going into the library is good enough.  However, the
 * garbage collector can call the free routines at other times, so they
 * need to protect themselves whether called through the Draw module
 * or not; hence the need for check against recursive locking in lockdisplay().
 * This also means that we needn't lock around calls to destroy if it's
 * extra work to do so.
 */

typedef struct Cache Cache;
typedef struct DRef DRef;
typedef struct DDisplay DDisplay;
typedef struct DImage DImage;
typedef struct DScreen DScreen;
typedef struct DFont DFont;

struct Cache
{
	int	ref;
	char*	name;
	Display*display;
	union{
		Subfont*	sf;
		Font*		f;
		void*		ptr;
	}u;
	Cache*	next;
};

/* not visible to Limbo; used only for internal reference counting */
struct DRef
{
	int		ref;
	Display*	display;
};

struct DDisplay
{
	Draw_Display	drawdisplay;
	Display*	display;
	DRef*		dref;
};

struct DImage
{
	Draw_Image	drawimage;
	Image*		image;
	void*		refreshptr;
	DRef*		dref;
	int		flush;
};

struct DScreen
{
	Draw_Screen	drawscreen;
	Screen*		screen;
	DRef*		dref;
};

struct DFont
{
	Draw_Font	drawfont;
	Font*		font;
	DRef*		dref;
};

Cache*	sfcache[BIHASH];
Cache*	fcache[BIHASH];
void*	cacheqlock;

static	Cache	*cachelookup(Cache**, Display*, char*);

uchar fontmap[] = Draw_Font_map;
uchar imagemap[] = Draw_Image_map;
uchar screenmap[] = Draw_Screen_map;
uchar displaymap[] = Draw_Display_map;

Type*	TFont;
Type*	TImage;
Type*	TScreen;
Type*	TDisplay;

Draw_Image*	allocdrawimage(DDisplay*, Draw_Rect, ulong, Image*, int, int);
Draw_Image*	color(DDisplay*, ulong);
Draw_Screen	*mkdrawscreen(Screen*, Draw_Display*);

char		deffontname[] = "*default*";
void		refreshslave(Display*);
void		subfont_close(Subfont*);
void		freeallsubfonts(Display*);

void
drawmodinit(void)
{
	TFont = dtype(freedrawfont, sizeof(DFont), fontmap, sizeof(fontmap));
	TImage = dtype(freedrawimage, sizeof(DImage), imagemap, sizeof(imagemap));
	TScreen = dtype(freedrawscreen, sizeof(DScreen), screenmap, sizeof(screenmap));
	TDisplay = dtype(freedrawdisplay, sizeof(DDisplay), displaymap, sizeof(displaymap));
	builtinmod("$Draw", Drawmodtab, Drawmodlen);
}

static int
drawhash(char *s)
{
	int h;

	h = 0;
	while(*s){
		h += *s++;
		h <<= 1;
		if(h & (1<<8))
			h |= 1;
	}
	return (h&0xFFFF)%BIHASH;
}

static Cache*
cachelookup(Cache *cache[], Display *d, char *name)
{
	Cache *c;

	libqlock(cacheqlock);
	c = cache[drawhash(name)];
	while(c!=nil && (d!=c->display || strcmp(name, c->name)!=0))
		c = c->next;
	libqunlock(cacheqlock);
	return c;
}

Cache*
cacheinstall(Cache **cache, Display *d, char *name, void *ptr, char *type)
{
	Cache *c;
	int hash;

	USED(type);
	c = cachelookup(cache, d, name);
	if(c){
/*		print("%s %s already in cache\n", type, name); /**/
		return nil;
	}
	c = malloc(sizeof(Cache));
	if(c == nil)
		return nil;
	hash = drawhash(name);
	c->ref = 0;	/* will be incremented by caller */
	c->display = d;
	c->name = strdup(name);
	c->u.ptr = ptr;
	libqlock(cacheqlock);
	c->next = cache[hash];
	cache[hash] = c;
	libqunlock(cacheqlock);
	return c;
}

void
cacheuninstall(Cache **cache, Display *d, char *name, char *type)
{
	Cache *c, *prev;
	int hash;

	hash = drawhash(name);
	libqlock(cacheqlock);
	c = cache[hash];
	if(c == nil){
   Notfound:
		libqunlock(cacheqlock);
		print("%s not in %s cache\n", name, type);
		return;
	}
	prev = nil;
	while(c!=nil && (d!=c->display || strcmp(name, c->name)!=0)){
		prev = c;
		c = c->next;
	}
	if(c == nil)
		goto Notfound;
	if(prev == 0)
		cache[hash] = c->next;
	else
		prev->next = c->next;
	libqunlock(cacheqlock);
	free(c->name);
	free(c);
}

Image*
lookupimage(Draw_Image *di)
{
	Display *disp;
	Image *i;
	int locked;

	if(di == H || D2H(di)->t != TImage)
		return nil;
	i = ((DImage*)di)->image;
	if(i == nil)
		return nil;
	if(!eqrect(IRECT(di->clipr), i->clipr) || di->repl!=i->repl){
		disp = i->display;
		locked = lockdisplay(disp);
		replclipr(i, di->repl, IRECT(di->clipr));
		if(locked)
			unlockdisplay(disp);
	}
	return i;
}

Screen*
lookupscreen(Draw_Screen *ds)
{
	if(ds == H || D2H(ds)->t != TScreen)
		return nil;
	return ((DScreen*)ds)->screen;
}

Font*
lookupfont(Draw_Font *df)
{
	if(df == H || D2H(df)->t != TFont)
		return nil;
	return ((DFont*)df)->font;
}

Display*
lookupdisplay(Draw_Display *dd)
{
	if(dd == H || D2H(dd)->t != TDisplay)
		return nil;
	return ((DDisplay*)dd)->display;
}

Image*
checkimage(Draw_Image *di)
{
	Image *i;

	if(di == H)
		error("nil Image");
	i = lookupimage(di);
	if(i == nil)
		error(exType);
	return i;
}

Screen*
checkscreen(Draw_Screen *ds)
{
	Screen *s;

	if(ds == H)
		error("nil Screen");
	s = lookupscreen(ds);
	if(s == nil)
		error(exType);
	return s;
}

Font*
checkfont(Draw_Font *df)
{
	Font *f;

	if(df == H)
		error("nil Font");
	f = lookupfont(df);
	if(f == nil)
		error(exType);
	return f;
}

Display*
checkdisplay(Draw_Display *dd)
{
	Display *d;

	if(dd == H)
		error("nil Display");
	d = lookupdisplay(dd);
	if(d == nil)
		error(exType);
	return d;
}

void
Display_allocate(void *fp)
{
	F_Display_allocate *f;
	char buf[128], *dev;
	Subfont *df;
	Display *display;
	DDisplay *dd;
	Heap *h;
	Draw_Rect r;
	DRef *dr;
	Cache *c;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;
	if(cacheqlock == nil){
		cacheqlock = libqlalloc();
		if(cacheqlock == nil)
			return;
	}
	dev = string2c(f->dev);
	if(dev[0] == 0)
		dev = 0;
	display = initdisplay(dev, dev, nil);	/* TO DO: win, error */
	if(display == 0)
		return;

	dr = malloc(sizeof(DRef));
	if(dr == nil)
		return;
	h = heap(TDisplay);
	if(h == H){
		closedisplay(display);
		return;
	}
	dd = H2D(DDisplay*, h);
	dd->display = display;
	*f->ret = &dd->drawdisplay;
	dd->dref = dr;
	display->limbo = dr;
	dr->display = display;
	dr->ref = 1;
	df = getdefont(display);
	if(df){
		display->defaultsubfont = df;
		sprint(buf, "%d %d\n0 %d\t%s\n", df->height, df->ascent,
			df->n-1, deffontname);
		display->defaultfont = buildfont(display, buf, deffontname);
		if(display->defaultfont){
			c = cacheinstall(fcache, display, deffontname, display->defaultfont, "font");
			if(c)
				c->ref++;
			/* else BUG? */
		}
	}

	R2R(r, display->image->r);
	dd->drawdisplay.image = allocdrawimage(dd, r, display->image->chan, display->image, 0, 0);
	R2R(r, display->white->r);
	dd->drawdisplay.black = allocdrawimage(dd, r, display->black->chan, display->black, 1, 0);
	dd->drawdisplay.white = allocdrawimage(dd, r, display->white->chan, display->white, 1, 0);
	dd->drawdisplay.opaque = allocdrawimage(dd, r, display->opaque->chan, display->opaque, 1, 0);
	dd->drawdisplay.transparent = allocdrawimage(dd, r, display->transparent->chan, display->transparent, 1, 0);

	/* don't call unlockdisplay because the qlock was left up by initdisplay */
	libqunlock(display->qlock);
}

void
Display_getwindow(void *fp)
{
	F_Display_getwindow *f;
	Display *disp;
	int locked;
	Image *image;
	Screen *screen;
	char *wn;
	void *r;

	f = fp;
	r = f->ret->t0;
	f->ret->t0 = H;
	destroy(r);
	r = f->ret->t1;
	f->ret->t1 = H;
	destroy(r);
	disp = checkdisplay(f->d);
	if(f->winname == H)
		wn = "/dev/winname";
	else
		wn = string2c(f->winname);
	if(f->image == H)
		image = nil;
	else
		image = checkimage(f->image);
	if(f->screen == H)
		screen = nil;
	else
		screen = checkscreen(f->screen);
	locked = lockdisplay(disp);
	if(gengetwindow(disp, wn, &image, &screen, f->backup) < 0){
		/* TO DO: eliminate f->image and f->screen's references to Image and Screen */
		goto Return;
	}
	if(screen != nil){
		if(f->screen != H){
			f->ret->t0 = f->screen;
			D2H(f->screen)->ref++;
		}else
			f->ret->t0 = mkdrawscreen(screen, f->d);
	}
	if(image != nil){
		if(f->image != H){
			f->ret->t1 = f->image;
			D2H(f->image)->ref++;
		}else
			f->ret->t1 = mkdrawimage(image, f->ret->t0, f->d, nil);
	}

Return:
	if(locked)
		unlockdisplay(disp);
}

void
Display_startrefresh(void *fp)
{
	F_Display_startrefresh *f;
	Display *disp;

	f = fp;
	disp = checkdisplay(f->d);
	refreshslave(disp);
}

void
display_dec(void *v)
{
	DRef *dr;
	Display *d;
	int locked;

	dr = v;
	if(dr->ref-- != 1)
		return;

	d = dr->display;
	locked = lockdisplay(d);
	font_close(d->defaultfont);
	subfont_close(d->defaultsubfont);
	if(locked)
		unlockdisplay(d);
	freeallsubfonts(d);
	closedisplay(d);
	free(dr);
}

void
freedrawdisplay(Heap *h, int swept)
{
	DDisplay *dd;
	Display *d;

	dd = H2D(DDisplay*, h);

	if(!swept) {
		destroy(dd->drawdisplay.image);
		destroy(dd->drawdisplay.black);
		destroy(dd->drawdisplay.white);
		destroy(dd->drawdisplay.opaque);
		destroy(dd->drawdisplay.transparent);
	}
	/* we've now released dd->image etc.; make sure they're not freed again */
	d = dd->display;
	d->image = nil;
	d->white = nil;
	d->black = nil;
	d->opaque = nil;
	d->transparent = nil;
	display_dec(dd->dref);
	/* Draw_Display header will be freed by caller */
}

void
Display_color(void *fp)
{
	F_Display_color *f;
	Display *d;
	int locked;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;
	d = checkdisplay(f->d);
	locked = lockdisplay(d);
	*f->ret = color((DDisplay*)f->d, f->color);
	if(locked)
		unlockdisplay(d);
}

void
Image_flush(void *fp)
{
	F_Image_flush *f;
	Image *d;
	DImage *di;
	int locked;

	f = fp;
	d = checkimage(f->win);
	di = (DImage*)f->win;
	switch(f->func){
	case 0:	/* Draw->Flushoff */
		di->flush = 0;
		break;
	case 1:	/* Draw->Flushon */
		di->flush = 1;
		/* fall through */
	case 2:	/* Draw->Flushnow */
		locked = lockdisplay(d->display);
		if(d->id==0 || d->screen!=0)
			flushimage(d->display, 1);
		if(locked)
			unlockdisplay(d->display);
		break;
	default:
		error(exInval);
	}
}

void
checkflush(Draw_Image *dst)
{
	DImage  *di;

	di = (DImage*)dst;
	if(di->flush && (di->image->id==0 || di->image->screen!=nil))
		flushimage(di->image->display, 1);
}

static void
imagedraw(void *fp, int op)
{
	F_Image_draw *f;
	Image *d, *s, *m;
	int locked;

	f = fp;
	d = checkimage(f->dst);
	if(f->src == H)
		s = d->display->black;
	else
		s = checkimage(f->src);
	if(f->matte == H)
		m = d->display->white;	/* ones */
	else
		m = checkimage(f->matte);
	if(d->display!=s->display || d->display!=m->display)
		return;
	locked = lockdisplay(d->display);
	drawop(d, IRECT(f->r), s, m, IPOINT(f->p), op);
	checkflush(f->dst);
	if(locked)
		unlockdisplay(d->display);
}

void
Image_draw(void *fp)
{
	imagedraw(fp, SoverD);
}

void
Image_drawop(void *fp)
{
	F_Image_drawop *f;

	f = fp;
	imagedraw(fp, f->op);
}

static void
imagegendraw(void *fp, int op)
{
	F_Image_gendraw *f;
	Image *d, *s, *m;
	int locked;

	f = fp;
	d = checkimage(f->dst);
	if(f->src == H)
		s = d->display->black;
	else
		s = checkimage(f->src);
	if(f->matte == H)
		m = d->display->white;	/* ones */
	else
		m = checkimage(f->matte);
	if(d->display!=s->display || d->display!=m->display)
		return;
	locked = lockdisplay(d->display);
	gendrawop(d, IRECT(f->r), s, IPOINT(f->p0), m, IPOINT(f->p1), op);
	checkflush(f->dst);
	if(locked)
		unlockdisplay(d->display);
}

void
Image_gendraw(void *fp)
{
	imagegendraw(fp, SoverD);
}

void
Image_gendrawop(void *fp)
{
	F_Image_gendrawop *f;

	f = fp;
	imagegendraw(fp, f->op);
}

static void
drawline(void *fp, int op)
{
	F_Image_line *f;
	Image *d, *s;
	int locked;

	f = fp;
	d = checkimage(f->dst);
	s = checkimage(f->src);
	if(d->display != s->display || f->radius < 0)
		return;
	locked = lockdisplay(d->display);
	lineop(d, IPOINT(f->p0), IPOINT(f->p1), f->end0, f->end1, f->radius, s, IPOINT(f->sp), op);
	checkflush(f->dst);
	if(locked)
		unlockdisplay(d->display);
}

void
Image_line(void *fp)
{
	drawline(fp, SoverD);
}

void
Image_lineop(void *fp)
{
	F_Image_lineop *f;

	f = fp;
	drawline(fp, f->op);
}

static void
drawsplinepoly(void *fp, int smooth, int op)
{
	F_Image_poly *f;
	Image *d, *s;
	int locked;

	f = fp;
	d = checkimage(f->dst);
	s = checkimage(f->src);
	if(d->display != s->display|| f->radius < 0)
		return;
	locked = lockdisplay(d->display);
	/* sleazy: we know that Draw_Points have same shape as Points */
	if(smooth)
		bezsplineop(d, (Point*)f->p->data, f->p->len,
			f->end0, f->end1, f->radius, s, IPOINT(f->sp), op);
	else
		polyop(d, (Point*)f->p->data, f->p->len, f->end0,
			f->end1, f->radius, s, IPOINT(f->sp), op);
	checkflush(f->dst);
	if(locked)
		unlockdisplay(d->display);
}

void
Image_poly(void *fp)
{
	drawsplinepoly(fp, 0, SoverD);
}

void
Image_polyop(void *fp)
{
	F_Image_polyop *f;

	f = fp;
	drawsplinepoly(fp, 0, f->op);
}

void
Image_bezspline(void *fp)
{
	drawsplinepoly(fp, 1, SoverD);
}

void
Image_bezsplineop(void *fp)
{
	F_Image_bezsplineop *f;

	f = fp;
	drawsplinepoly(fp, 1, f->op);
}

static void
drawbezier(void *fp, int op)
{
	F_Image_bezier *f;
	Image *d, *s;
	int locked;

	f = fp;
	d = checkimage(f->dst);
	s = checkimage(f->src);
	if(d->display != s->display || f->radius < 0)
		return;
	locked = lockdisplay(d->display);
	bezierop(d, IPOINT(f->a), IPOINT(f->b), IPOINT(f->c),
		  IPOINT(f->d), f->end0, f->end1, f->radius, s, IPOINT(f->sp), op);
	checkflush(f->dst);
	if(locked)
		unlockdisplay(d->display);
}

void
Image_bezier(void *fp)
{
	drawbezier(fp, SoverD);
}

void
Image_bezierop(void *fp)
{
	F_Image_bezierop *f;

	f = fp;
	drawbezier(fp, f->op);
}

static void
drawfillbezier(void *fp, int op)
{
	F_Image_fillbezier *f;
	Image *d, *s;
	int locked;

	f = fp;
	d = checkimage(f->dst);
	s = checkimage(f->src);
	if(d->display != s->display)
		return;
	locked = lockdisplay(d->display);
	fillbezierop(d, IPOINT(f->a), IPOINT(f->b), IPOINT(f->c),
			IPOINT(f->d), f->wind, s, IPOINT(f->sp), op);
	checkflush(f->dst);
	if(locked)
		unlockdisplay(d->display);
}

void
Image_fillbezier(void *fp)
{
	drawfillbezier(fp, SoverD);
}

void
Image_fillbezierop(void *fp)
{
	F_Image_fillbezierop *f;

	f = fp;
	drawfillbezier(fp, f->op);
}

static void
drawfillsplinepoly(void *fp, int smooth, int op)
{
	F_Image_fillpoly *f;
	Image *d, *s;
	int locked;

	f = fp;
	d = checkimage(f->dst);
	s = checkimage(f->src);
	if(d->display != s->display)
		return;
	locked = lockdisplay(d->display);
	/* sleazy: we know that Draw_Points have same shape as Points */
	if(smooth)
		fillbezsplineop(d, (Point*)f->p->data, f->p->len,
			f->wind, s, IPOINT(f->sp), op);
	else
		fillpolyop(d, (Point*)f->p->data, f->p->len,
			f->wind, s, IPOINT(f->sp), op);
	checkflush(f->dst);
	if(locked)
		unlockdisplay(d->display);
}

void
Image_fillpoly(void *fp)
{
	drawfillsplinepoly(fp, 0, SoverD);
}

void
Image_fillpolyop(void *fp)
{
	F_Image_fillpolyop *f;

	f = fp;
	drawfillsplinepoly(fp, 0, f->op);
}

void
Image_fillbezspline(void *fp)
{
	drawfillsplinepoly(fp, 1, SoverD);
}

void
Image_fillbezsplineop(void *fp)
{
	F_Image_fillbezsplineop *f;

	f = fp;
	drawfillsplinepoly(fp, 1, f->op);
}

static void
drawarcellipse(void *fp, int isarc, int alpha, int phi, int op)
{
	F_Image_arc *f;
	Image *d, *s;
	int locked;

	f = fp;
	d = checkimage(f->dst);
	s = checkimage(f->src);
	if(d->display != s->display || f->thick < 0 || f->a<0 || f->b<0)
		return;

	locked = lockdisplay(d->display);
	if(isarc)
		arcop(d, IPOINT(f->c), f->a, f->b, f->thick, s,
			IPOINT(f->sp), alpha, phi, op);
	else
		ellipseop(d, IPOINT(f->c), f->a, f->b, f->thick, s,
			IPOINT(f->sp), op);
	checkflush(f->dst);
	if(locked)
		unlockdisplay(d->display);
}

void
Image_ellipse(void *fp)
{
	drawarcellipse(fp, 0, 0, 0, SoverD);
}

void
Image_ellipseop(void *fp)
{
	F_Image_ellipseop *f;

	f = fp;
	drawarcellipse(fp, 0, 0, 0, f->op);
}

void
Image_arc(void *fp)
{
	F_Image_arc *f;

	f = fp;
	drawarcellipse(fp, 1, f->alpha, f->phi, SoverD);
}

void
Image_arcop(void *fp)
{
	F_Image_arcop *f;

	f = fp;
	drawarcellipse(fp, 1, f->alpha, f->phi, f->op);
}

static void
drawfillarcellipse(void *fp, int isarc, int alpha, int phi, int op)
{
	F_Image_fillarc *f;
	Image *d, *s;
	int locked;

	f = fp;
	d = checkimage(f->dst);
	s = checkimage(f->src);
	if(d->display != s->display || f->a<0 || f->b<0)
		return;

	locked = lockdisplay(d->display);
	if(isarc)
		fillarcop(d, IPOINT(f->c), f->a, f->b, s, IPOINT(f->sp), alpha, phi, op);
	else
		fillellipseop(d, IPOINT(f->c), f->a, f->b, s, IPOINT(f->sp), op);
	checkflush(f->dst);
	if(locked)
		unlockdisplay(d->display);
}

void
Image_fillellipse(void *fp)
{
	drawfillarcellipse(fp, 0, 0, 0, SoverD);
}

void
Image_fillellipseop(void *fp)
{
	F_Image_fillellipseop *f;

	f = fp;
	drawfillarcellipse(fp, 0, 0, 0, f->op);
}

void
Image_fillarc(void *fp)
{
	F_Image_fillarc *f;

	f = fp;
	drawfillarcellipse(fp, 1, f->alpha, f->phi, SoverD);
}

void
Image_fillarcop(void *fp)
{
	F_Image_fillarcop *f;

	f = fp;
	drawfillarcellipse(fp, 1, f->alpha, f->phi, f->op);
}

static void
drawtext(void *fp, int op)
{
	F_Image_text *f;
	Font *font;
	Point pt;
	Image *s, *d;
	String *str;
	int locked;

	f = fp;
	if(f->dst == H || f->src == H)
		goto Return;
	if(f->font == H || f->str == H)
		goto Return;
	str = f->str;
	d = checkimage(f->dst);
	s = checkimage(f->src);
	font = checkfont(f->font);
	if(d->display!=s->display || d->display!=font->display)
		return;
	locked = lockdisplay(d->display);
	if(str->len >= 0)
		pt = stringnop(d, IPOINT(f->p), s, IPOINT(f->sp), font, str->Sascii, str->len, op);
	else
		pt = runestringnop(d, IPOINT(f->p), s, IPOINT(f->sp), font, str->Srune, -str->len, op);
	checkflush(f->dst);
	if(locked)
		unlockdisplay(d->display);
    Return:
	P2P(*f->ret, pt);
}

void
Image_text(void *fp)
{
	drawtext(fp, SoverD);
}

void
Image_textop(void *fp)
{
	F_Image_textop *f;

	f = fp;
	drawtext(fp, f->op);
}

static void
drawtextbg(void *fp, int op)
{
	F_Image_textbg *f;
	Font *font;
	Point pt;
	Image *s, *d, *bg;
	String *str;
	int locked;

	f = fp;
	if(f->dst == H || f->src == H)
		goto Return;
	if(f->font == H || f->str == H)
		goto Return;
	str = f->str;
	d = checkimage(f->dst);
	s = checkimage(f->src);
	bg = checkimage(f->bg);
	font = checkfont(f->font);
	if(d->display!=s->display || d->display!=font->display)
		return;
	locked = lockdisplay(d->display);
	if(str->len >= 0)
		pt = stringnbgop(d, IPOINT(f->p), s, IPOINT(f->sp), font, str->Sascii, str->len, bg, IPOINT(f->bgp), op);
	else
		pt = runestringnbgop(d, IPOINT(f->p), s, IPOINT(f->sp), font, str->Srune, -str->len, bg, IPOINT(f->bgp), op);
	checkflush(f->dst);
	if(locked)
		unlockdisplay(d->display);
    Return:
	P2P(*f->ret, pt);
}

void
Image_textbg(void *fp)
{
	drawtextbg(fp, SoverD);
}

void
Image_textbgop(void *fp)
{
	F_Image_textbgop *f;

	f = fp;
	drawtextbg(fp, f->op);
}

static void
drawborder(void *fp, int op)
{
	F_Image_border *f;
	Image *d, *s;
	int locked;

	f = fp;
	d = checkimage(f->dst);
	s = checkimage(f->src);
	if(d->display != s->display)
		return;
	locked = lockdisplay(d->display);
	borderop(d, IRECT(f->r), f->i, s, IPOINT(f->sp), op);
	checkflush(f->dst);
	if(locked)
		unlockdisplay(d->display);
}

void
Image_border(void *fp)
{
	drawborder(fp, SoverD);
}

void
Display_newimage(void *fp)
{
	F_Display_newimage *f;
	Display *d;
	int locked;

	f = fp;
	d = checkdisplay(f->d);
	destroy(*f->ret);
	*f->ret = H;
	locked = lockdisplay(d);
	*f->ret = allocdrawimage((DDisplay*)f->d, f->r, f->chans.desc,
				nil, f->repl, f->color);
	if(locked)
		unlockdisplay(d);
}

void
Display_colormix(void *fp)
{
	F_Display_colormix *f;
	Display *disp;
	Image *i;
	int locked;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;
	disp = checkdisplay(f->d);
	locked = lockdisplay(disp);
	i = allocimagemix(disp, f->c1, f->c2);
	if(locked)
		unlockdisplay(disp);
	*f->ret = mkdrawimage(i, H, f->d, nil);
}

void
Image_readpixels(void *fp)
{
	F_Image_readpixels *f;
	Rectangle r;
	Image *i;
	int locked;

	f = fp;
	R2R(r, f->r);
	i = checkimage(f->src);
	locked = lockdisplay(i->display);
	*f->ret = unloadimage(i, r, f->data->data, f->data->len);
	if(locked)
		unlockdisplay(i->display);
}

void
Image_writepixels(void *fp)
{
	Rectangle r;
	F_Image_writepixels *f;
	Image *i;
	int locked;

	f = fp;
	R2R(r, f->r);
	i = checkimage(f->dst);
	locked = lockdisplay(i->display);
	*f->ret = loadimage(i, r, f->data->data, f->data->len);
	checkflush(f->dst);
	if(locked)
		unlockdisplay(i->display);
}

void
Image_arrow(void *fp)
{
	F_Image_arrow *f;

	f = fp;
	*f->ret = ARROW(f->a, f->b, f->c);
}

void
Image_name(void *fp)
{
	F_Image_name *f;
	Image *i;
	int locked, ok;
	char *name;

	f = fp;
	*f->ret = -1;
	i = checkimage(f->src);
	name = string2c(f->name);
	locked = lockdisplay(i->display);
	*f->ret = ok = nameimage(i, name, f->in);
	if(locked)
		unlockdisplay(i->display);
	if(ok){
		destroy(f->src->iname);
		if(f->in){
			f->src->iname = f->name;
			D2H(f->name)->ref++;
		}else
			f->src->iname = H;
	}
}

Image*
display_open(Display *disp, char *name)
{
	Image *i;
	int fd;

	fd = libopen(name, OREAD);
	if(fd < 0)
		return nil;

	i = readimage(disp, fd, 1);
	libclose(fd);
	return i;
}

void
Display_open(void *fp)
{
	Image *i;
	Display *disp;
	F_Display_open *f;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;
	disp = lookupdisplay(f->d);
	if(disp == nil)
		return;
	i = display_open(disp, string2c(f->name));
	if(i == nil)
		return;
	*f->ret = allocdrawimage((DDisplay*)f->d, DRECT(i->r), i->chan, i, 0, 0);
}

void
Display_namedimage(void *fp)
{
	F_Display_namedimage *f;
	Display *d;
	Image *i;
	Draw_Image *di;
	int locked;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;
	d = checkdisplay(f->d);
	locked = lockdisplay(d);
	i = namedimage(d, string2c(f->name));
	if(locked)
		unlockdisplay(d);
	if(i == nil)
		return;
	di =  allocdrawimage((DDisplay*)f->d, DRECT(i->r), i->chan, i, i->repl, 0);
	*f->ret = di;
	if(di == H){
		locked = lockdisplay(d);
		freeimage(i);
		if(locked)
			unlockdisplay(d);
	}else{
		di->iname = f->name;
		D2H(f->name)->ref++;
	}
}

void
Display_readimage(void *fp)
{
	Image *i;
	Display *disp;
	F_Display_readimage *f;
	Sys_FD *fd;
	int locked;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;
	fd = f->fd;
	if(fd == H)
		return;
	disp = checkdisplay(f->d);
	i = readimage(disp, fd->fd, 1);
	if(i == nil)
		return;
	*f->ret = allocdrawimage((DDisplay*)f->d, DRECT(i->r), i->chan, i, 0, 0);
	if(*f->ret == H){
		locked = lockdisplay(disp);
		freeimage(i);
		if(locked)
			unlockdisplay(disp);
	}
}

void
Display_writeimage(void *fp)
{
	Image *i;
	F_Display_writeimage *f;
	Sys_FD *fd;

	f = fp;
	*f->ret = -1;
	fd = f->fd;
	if(fd == H)
		return;
	i = checkimage(f->i);
	if(checkdisplay(f->d) != i->display)
		return;
	*f->ret = writeimage(fd->fd, i, 1);	/* TO DO: dolock? */
}

Draw_Screen*
mkdrawscreen(Screen *s, Draw_Display *display)
{
	Heap *h;
	DScreen *ds;
	Draw_Image *dimage, *dfill;

	dimage = mkdrawimage(s->image, H, display, nil);
	dfill = mkdrawimage(s->fill, H, display, nil);
	h = heap(TScreen);
	if(h == H)
		return nil;
	ds = H2D(DScreen*, h);
	ds->screen = s;
	ds->drawscreen.fill = dfill;
	D2H(dfill)->ref++;
	ds->drawscreen.image = dimage;
	D2H(dimage)->ref++;
	ds->drawscreen.display = dimage->display;
	D2H(dimage->display)->ref++;
	ds->drawscreen.id = s->id;
	ds->dref = s->display->limbo;
	ds->dref->ref++;
	return &ds->drawscreen;
}

static DScreen*
allocdrawscreen(Draw_Image *dimage, Draw_Image *dfill, int public)
{
	Heap *h;
	Screen *s;
	DScreen *ds;
	Image *image, *fill;

	image = ((DImage*)dimage)->image;
	fill = ((DImage*)dfill)->image;
	s = allocscreen(image, fill, public);
	if(s == 0)
		return nil;
	h = heap(TScreen);
	if(h == H)
		return nil;
	ds = H2D(DScreen*, h);
	ds->screen = s;
	ds->drawscreen.fill = dfill;
	D2H(dfill)->ref++;
	ds->drawscreen.image = dimage;
	D2H(dimage)->ref++;
	ds->drawscreen.display = dimage->display;
	D2H(dimage->display)->ref++;
	ds->drawscreen.id = s->id;
	ds->dref = image->display->limbo;
	ds->dref->ref++;
	return ds;
}

void
Screen_allocate(void *fp)
{
	F_Screen_allocate *f;
	DScreen *ds;
	Image *image;
	int locked;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;
	image = checkimage(f->image);
	checkimage(f->fill);
	locked = lockdisplay(image->display);
	ds = allocdrawscreen(f->image, f->fill, f->public);
	if(ds != nil)
		*f->ret = &ds->drawscreen;
	if(locked)
		unlockdisplay(image->display);
}

void
Display_publicscreen(void *fp)
{
	F_Display_publicscreen *f;
	Heap *h;
	Screen *s;
	DScreen *ds;
	Display *disp;
	int locked;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;
	disp = checkdisplay(f->d);
	locked = lockdisplay(disp);
	s = publicscreen(disp, f->id, disp->image->chan);
	if(locked)
		unlockdisplay(disp);
	if(s == nil)
		return;
	h = heap(TScreen);
	if(h == H)
		return;
	ds = H2D(DScreen*, h);
	ds->screen = s;
	ds->drawscreen.fill = H;
	ds->drawscreen.image =H;
	ds->drawscreen.id = s->id;
	ds->drawscreen.display = f->d;
	D2H(f->d)->ref++;
	ds->dref = disp->limbo;
	ds->dref->ref++;
	*f->ret = &ds->drawscreen;
}

void
freedrawscreen(Heap *h, int swept)
{
	DScreen *ds;
	Screen *s;
	Display *disp;
	int locked;

	ds = H2D(DScreen*, h);
	if(!swept) {
		destroy(ds->drawscreen.image);
		destroy(ds->drawscreen.fill);
		destroy(ds->drawscreen.display);
	}
	s = lookupscreen(&ds->drawscreen);
	if(s == nil){
		if(!swept)
			freeptrs(ds, TScreen);
		return;
	}
	disp = s->display;
	locked = lockdisplay(disp);
	freescreen(s);
	if(locked)
		unlockdisplay(disp);
	display_dec(ds->dref);
	/* screen header will be freed by caller */
}

void
Font_build(void *fp)
{
	F_Font_build *f;
	Font *font;
	DFont *dfont;
	Heap *h;
	char buf[128];
	char *name, *data;
	Subfont *df;
	Display *disp;
	int locked;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;
	disp = checkdisplay(f->d);

	name = string2c(f->name);
	font = font_open(disp, name);
	if(font == nil) {
		if(strcmp(name, deffontname) == 0) {
			df = disp->defaultsubfont;
			sprint(buf, "%d %d\n0 %d\t%s\n",
				df->height, df->ascent, df->n-1, name);
			data = buf;
		}
		else
		if(f->desc == H)
			return;
		else
			data = string2c(f->desc);

		locked = lockdisplay(disp);
		font = buildfont(disp, data, name);
		if(locked)
			unlockdisplay(disp);
		if(font == nil)
			return;
	}

	h = heap(TFont);
	if(h == H)
		return;

	dfont = H2D(DFont*, h);
	dfont->font = font;
	dfont->drawfont.name = f->name;
	D2H(f->name)->ref++;
	dfont->drawfont.height = font->height;
	dfont->drawfont.ascent = font->ascent;
	dfont->drawfont.display = f->d;
	D2H(f->d)->ref++;
	dfont->dref = disp->limbo;
	dfont->dref->ref++;

	*f->ret = &dfont->drawfont;
}

Font*
font_open(Display *display, char *name)
{
	Cache *c;
	Font *font;
	int locked;

	c = cachelookup(fcache, display, name);
	if(c)
		font = c->u.f;
	else {
		locked = lockdisplay(display);
		font = openfont(display, name);
		if(locked)
			unlockdisplay(display);
		if(font == nil)
			return nil;
		c = cacheinstall(fcache, display, name, font, "font");
	}
	if(c)
		c->ref++;

	return font;
}

void
font_close(Font *f)
{
	Cache *c;
	Display *disp;
	int locked;
	disp = f->display;
	if(f->name == nil)
		return;

	/* fonts from Font_build() aren't always in fcache, but we still need to free them */
	c = cachelookup(fcache, disp, f->name);
	if(c != nil && f == c->u.f) {
		if(c->ref <= 0)
			return;
		if(c->ref-- != 1)
			return;
		cacheuninstall(fcache, disp, f->name, "font");
	}

	locked = lockdisplay(disp);
	freefont(f);
	if(locked)
		unlockdisplay(disp);
}

void
freecachedsubfont(Subfont *sf)
{
	Cache *c;
	Display *disp;

	disp = sf->bits->display;
	c = cachelookup(sfcache, disp, sf->name);
	if(c == nil){
		fprint(2, "subfont %s not cached\n", sf->name);
		return;
	}
	if(c->ref > 0)
		c->ref--;
	/* if ref is zero, we leave it around for later harvesting by freeallsubfonts */
}

void
freeallsubfonts(Display *d)
{
	int i;
	Cache *c, *prev, *o;
	Subfont *sf;
	int locked;
	if(cacheqlock == nil)	/* may not have allocated anything yet */
		return;
	libqlock(cacheqlock);
	for(i=0; i<BIHASH; i++){
		c = sfcache[i];
		prev = 0;
		while(c != nil){
			if(c->ref==0 && (d==nil || c->display==d)){
				if(prev == 0)
					sfcache[i] = c->next;
				else
					prev->next = c->next;
				free(c->name);
				sf = c->u.sf;
				if(--sf->ref==0){
					free(sf->info);
					locked = lockdisplay(c->display);
					freeimage(sf->bits);
					if(locked)
						unlockdisplay(c->display);
					free(sf);
				}
				o = c;
				c = c->next;
				free(o);
			}else{
				prev = c;
				c = c->next;
			}
		}
	}
	libqunlock(cacheqlock);
}

void
subfont_close(Subfont *sf)
{
	freecachedsubfont(sf);
}

void
freesubfont(Subfont *sf)
{
	freecachedsubfont(sf);
}

void
Font_open(void *fp)
{
	Heap *h;
	Font *font;
	Display *disp;
	DFont *df;
	F_Font_open *f;

	f = fp;

	destroy(*f->ret);
	*f->ret = H;
	disp = checkdisplay(f->d);

	font = font_open(disp, string2c(f->name));
	if(font == 0)
		return;

	h = heap(TFont);
	if(h == H)
		return;

	df = H2D(DFont*, h);
	df->font = font;
	df->drawfont.name = f->name;
	D2H(f->name)->ref++;
	df->drawfont.height = font->height;
	df->drawfont.ascent = font->ascent;
	df->drawfont.display = f->d;
	D2H(f->d)->ref++;
	df->dref = disp->limbo;
	df->dref->ref++;
	*f->ret = &df->drawfont;
}

void
Font_width(void *fp)
{
	F_Font_width *f;
	Font *font;
	char *s;
	int locked;

	f = fp;
	s = string2c(f->str);
	if(f->f == H || s[0]=='\0')
		*f->ret = 0;
	else{
		font = checkfont(f->f);
		locked = lockdisplay(font->display);
		*f->ret = stringwidth(font, s);
		if(locked)
			unlockdisplay(font->display);
	}
}

void
Font_bbox(void *fp)
{
	F_Font_bbox *f;
	Draw_Rect *ret;

	/* place holder for the real thing */
	f = fp;
	ret = f->ret;
	ret->min.x = ret->min.y = 0;
	ret->max.x = ret->max.y = 0;
}

/*
 * BUG: would be nice if this cached the whole font.
 * Instead only the subfonts are cached and the fonts are
 * freed when released.
 */
void
freedrawfont(Heap*h, int swept)
{
	Draw_Font *d;
	Font *f;
	d = H2D(Draw_Font*, h);
	f = lookupfont(d);
	if(!swept) {
		destroy(d->name);
		destroy(d->display);
	}
	font_close(f);
	display_dec(((DFont*)d)->dref);
}

void
Chans_text(void *fp)
{
	F_Chans_text *f;
	char buf[16];

	f = fp;
	destroy(*f->ret);
	*f->ret = H;
	if(chantostr(buf, f->c.desc) != nil)
		retstr(buf, f->ret);
}

void
Chans_depth(void *fp)
{
	F_Chans_depth *f;

	f = fp;
	*f->ret = chantodepth(f->c.desc);
}

void
Chans_eq(void *fp)
{
	F_Chans_eq *f;

	f = fp;
	*f->ret = f->c.desc == f->d.desc;
}

void
Chans_mk(void *fp)
{
	F_Chans_mk *f;

	f = fp;
	f->ret->desc = strtochan(string2c(f->s));
}

void
Display_rgb(void *fp)
{
	ulong c;
	Display *disp;
	F_Display_rgb *f;
	int locked;
	void *r;

	f = fp;
	r = *f->ret;
	*f->ret = H;
	destroy(r);
	disp = checkdisplay(f->d);

	c = ((f->r&255)<<24)|((f->g&255)<<16)|((f->b&255)<<8)|0xFF;

	locked = lockdisplay(disp);
	*f->ret = color((DDisplay*)f->d, c);
	if(locked)
		unlockdisplay(disp);
}

void
Display_rgb2cmap(void *fp)
{
	F_Display_rgb2cmap *f;

	f = fp;
	/* f->display is unused, but someday may have color map */
	*f->ret = rgb2cmap(f->r, f->g, f->b);
}

void
Display_cmap2rgb(void *fp)
{
	F_Display_cmap2rgb *f;
	ulong c;

	f = fp;
	/* f->display is unused, but someday may have color map */
	c = cmap2rgb(f->c);
	f->ret->t0 = (c>>16)&0xFF;
	f->ret->t1 = (c>>8)&0xFF;
	f->ret->t2 = (c>>0)&0xFF;
}

void
Display_cmap2rgba(void *fp)
{
	F_Display_cmap2rgba *f;

	f = fp;
	/* f->display is unused, but someday may have color map */
	*f->ret = cmap2rgba(f->c);
}

void
Draw_setalpha(void *fp)
{
	F_Draw_setalpha *f;

	f = fp;
	*f->ret = setalpha(f->c, f->a);
}

void
Draw_icossin(void *fp)
{
	F_Draw_icossin *f;
	int s, c;

	f = fp;
	icossin(f->deg, &s, &c);
	f->ret->t0 = s;
	f->ret->t1 = c;
}

void
Draw_icossin2(void *fp)
{
	F_Draw_icossin2 *f;
	int s, c;

	f = fp;
	icossin2(f->p.x, f->p.y, &s, &c);
	f->ret->t0 = s;
	f->ret->t1 = c;
}

void
Draw_bytesperline(void *fp)
{
	F_Draw_bytesperline *f;

	f = fp;
	*f->ret = bytesperline(IRECT(f->r), f->d);
}

Draw_Image*
color(DDisplay *dd, ulong color)
{
	int c;
	Draw_Rect r;

	r.min.x = 0;
	r.min.y = 0;
	r.max.x = 1;
	r.max.y = 1;
	c = (color&0xff) == 0xff ? RGB24: RGBA32;
	return allocdrawimage(dd, r, c, nil, 1, color);
}

Draw_Image*
mkdrawimage(Image *i, Draw_Screen *screen, Draw_Display *display, void *ref)
{
	Heap *h;
	DImage *di;

	h = heap(TImage);
	if(h == H)
		return H;

	di = H2D(DImage*, h);
	di->image = i;
	di->drawimage.screen = screen;
	if(screen != H)
		D2H(screen)->ref++;
	di->drawimage.display = display;
	if(display != H)
		D2H(display)->ref++;
	di->refreshptr = ref;

	R2R(di->drawimage.r, i->r);
	R2R(di->drawimage.clipr, i->clipr);
	di->drawimage.chans.desc = i->chan;
	di->drawimage.depth = i->depth;
	di->drawimage.repl = i->repl;
	di->flush = 1;
	di->dref = i->display->limbo;
	di->dref->ref++;
	return &di->drawimage;
}

void
Screen_newwindow(void *fp)
{
	F_Screen_newwindow *f;
	Image *i;
	Screen *s;
	Rectangle r;
	int locked;
	void *v;

	f = fp;
	s = checkscreen(f->screen);
	R2R(r, f->r);

	if(f->backing != Refnone && f->backing != Refbackup)
		f->backing = Refbackup;

	v = *f->ret;
	*f->ret = H;
	destroy(v);

	locked = lockdisplay(s->display);
	i = allocwindow(s, r, f->backing, f->color);
	if(locked)
		unlockdisplay(s->display);
	if(i == nil)
		return;

	*f->ret = mkdrawimage(i, f->screen, f->screen->display, 0);
}

static
void
screentopbot(Draw_Screen *screen, Array *array, void (*topbot)(Image **, int))
{
	Screen *s;
	Draw_Image **di;
	Image **ip;
	int i, n, locked;

	s = checkscreen(screen);
	di = (Draw_Image**)array->data;
	ip = malloc(array->len * sizeof(Image*));
	if(ip == nil)
		return;
	n = 0;
	for(i=0; i<array->len; i++)
		if(di[i] != H){
			ip[n] = lookupimage(di[i]);
			if(ip[n]==nil || ip[n]->screen != s){
				free(ip);
				return;
			}
			n++;
		}
	if(n == 0){
		free(ip);
		return;
	}
	locked = lockdisplay(s->display);
	(*topbot)(ip, n);
	free(ip);
	flushimage(s->display, 1);
	if(locked)
		unlockdisplay(s->display);
}

void
Screen_top(void *fp)
{
	F_Screen_top *f;
	f = fp;
	screentopbot(f->screen, f->wins, topnwindows);
}

void
Screen_bottom(void *fp)
{
	F_Screen_top *f;
	f = fp;
	screentopbot(f->screen, f->wins, bottomnwindows);
}

void
freedrawimage(Heap *h, int swept)
{
	Image *i;
	int locked;
	Display *disp;
	Draw_Image *d;

	d = H2D(Draw_Image*, h);
	i = lookupimage(d);
	if(i == nil) {
		if(!swept)
			freeptrs(d, TImage);
		return;
	}
	disp = i->display;
	locked = lockdisplay(disp);
	freeimage(i);
	if(locked)
		unlockdisplay(disp);
	display_dec(((DImage*)d)->dref);
	/* image/layer header will be freed by caller */
}

void
Image_top(void *fp)
{
	F_Image_top *f;
	Image *i;
	int locked;

	f = fp;
	i = checkimage(f->win);
	locked = lockdisplay(i->display);
	topwindow(i);
	flushimage(i->display, 1);
	if(locked)
		unlockdisplay(i->display);
}

void
Image_origin(void *fp)
{
	F_Image_origin *f;
	Image *i;
	int locked;

	f = fp;
	i = checkimage(f->win);
	locked = lockdisplay(i->display);
	if(originwindow(i, IPOINT(f->log), IPOINT(f->scr)) < 0)
		*f->ret = -1;
	else{
		f->win->r = DRECT(i->r);
		f->win->clipr = DRECT(i->clipr);
		*f->ret = 1;
	}
	if(locked)
		unlockdisplay(i->display);
}

void
Image_bottom(void *fp)
{
	F_Image_top *f;
	Image *i;
	int locked;

	f = fp;
	i = checkimage(f->win);
	locked = lockdisplay(i->display);
	bottomwindow(i);
	flushimage(i->display, 1);
	if(locked)
		unlockdisplay(i->display);
}

Draw_Image*
allocdrawimage(DDisplay *ddisplay, Draw_Rect r, ulong chan, Image *iimage, int repl, int color)
{
	Heap *h;
	DImage *di;
	Rectangle rr;
	Image *image;

	image = iimage;
	if(iimage == nil){
		R2R(rr, r);
		image = allocimage(ddisplay->display, rr, chan, repl, color);
		if(image == nil)
			return H;
	}

	h = heap(TImage);
	if(h == H){
		if(iimage == nil)
			freeimage(image);
		return H;
	}

	di = H2D(DImage*, h);
	di->drawimage.r = r;
	R2R(di->drawimage.clipr, image->clipr);
	di->drawimage.chans.desc = chan;
	di->drawimage.depth = chantodepth(chan);
	di->drawimage.repl = repl;
	di->drawimage.display = (Draw_Display*)ddisplay;
	D2H(di->drawimage.display)->ref++;
	di->drawimage.screen = H;
	di->dref = ddisplay->display->limbo;
	di->dref->ref++;
	di->image = image;
	di->refreshptr = 0;
	di->flush = 1;

	return &di->drawimage;
}

/*
 * Entry points called from the draw library
 */
Subfont*
lookupsubfont(Display *d, char *name)
{
	Cache *c;

	c = cachelookup(sfcache, d, name);
	if(c == nil)
		return nil;
	/*c->u.sf->ref++;*/	/* TO DO: need to revisit the reference counting */
	return c->u.sf;
}

void
installsubfont(char *name, Subfont *subfont)
{
	Cache *c;

	c = cacheinstall(sfcache, subfont->bits->display, name, subfont, "subfont");
	if(c)
		c->ref++;
}

/*
 * BUG version
 */
char*
subfontname(char *cfname, char *fname, int maxdepth)
{
	char *t, *u, tmp1[256], tmp2[256];
	int i, fd;

	if(strcmp(cfname, deffontname) == 0)
		return strdup(cfname);
	t = cfname;
	if(t[0] != '/'){
		strcpy(tmp2, fname);
		u = utfrrune(tmp2, '/');
		if(u)
			u[0] = 0;
		else
			strcpy(tmp2, ".");
		snprint(tmp1, sizeof tmp1, "%s/%s", tmp2, t);
		t = tmp1;
	}

	if(maxdepth > 8)
		maxdepth = 8;

	for(i=3; i>=0; i--){
		if((1<<i) > maxdepth)
			continue;
		/* try i-bit grey */
		snprint(tmp2, sizeof tmp2, "%s.%d", t, i);
		fd = libopen(tmp2, OREAD);
		if(fd >= 0){
			libclose(fd);
			return strdup(tmp2);
		}
	}

	return strdup(t);
}

void
refreshslave(Display *d)
{
	int i, n, id;
	uchar buf[5*(5*4)], *p;
	Rectangle r;
	Image *im;
	int locked;

	for(;;){
		release();
		n = kchanio(d->refchan, buf, sizeof buf, OREAD);
		acquire();
		if(n < 0)	/* probably caused by closedisplay() closing refchan */
			return;	/* will fall off end of thread and close down */
		locked = lockdisplay(d);
		p = buf;
		for(i=0; i<n; i+=5*4,p+=5*4){
			id = BGLONG(p+0*4);
			r.min.x = BGLONG(p+1*4);
			r.min.y = BGLONG(p+2*4);
			r.max.x = BGLONG(p+3*4);
			r.max.y = BGLONG(p+4*4);
			for(im=d->windows; im; im=im->next)
				if(im->id == id)
					break;
			if(im && im->screen && im->reffn)
				(*im->reffn)(im, r, im->refptr);
		}
		flushimage(d, 1);
		if(locked)
			unlockdisplay(d);
	}
}

void
startrefresh(Display *disp)
{
	USED(disp);
}

static
int
doflush(Display *d)
{
	int m, n;
	char err[ERRMAX];
	uchar *tp;

	n = d->bufp-d->buf;
	if(n <= 0)
		return 1;

	if(d->local == 0)
		release();
	if((m = kchanio(d->datachan, d->buf, n, OWRITE)) != n){
		if(d->local == 0)
			acquire();
		kgerrstr(err, sizeof err);
		if(_drawdebug || strcmp(err, "screen id in use") != 0 && strcmp(err, exImage) != 0){
			print("flushimage fail: (%d not %d) d=%lux: %s\nbuffer: ", m, n, (ulong)d, err);
			for(tp = d->buf; tp < d->bufp; tp++)
				print("%.2x ", (int)*tp);
			print("\n");
		}
		d->bufp = d->buf;	/* might as well; chance of continuing */
		return -1;
	}
	d->bufp = d->buf;
	if(d->local == 0)
		acquire();
	return 1;
}

int
flushimage(Display *d, int visible)
{
	int ret;
	Refreshq *r;

	for(;;){
		if(visible)
			*d->bufp++ = 'v';	/* one byte always reserved for this */
		ret = doflush(d);
		if(d->refhead == nil)
			break;
		while(r = d->refhead){	/* assign = */
			d->refhead = r->next;
			if(d->refhead == nil)
				d->reftail = nil;
			r->reffn(nil, r->r, r->refptr);
			free(r);
		}
	}
	return ret;
}

/*
 * Turn off refresh for this window and remove any pending refresh events for it.
 */
void
delrefresh(Image *i)
{
	Refreshq *r, *prev, *next;
	int locked;
	Display *d;
	void *refptr;

	d = i->display;
	/*
	 * Any refresh function will do, because the data pointer is nil.
	 * Can't use nil, though, because that turns backing store back on.
	 */
	if(d->local)
		drawlsetrefresh(d->dataqid, i->id, memlnorefresh, nil);
	refptr = i->refptr;
	i->refptr = nil;
	if(d->refhead==nil || refptr==nil)
		return;
	locked = lockdisplay(d);
	prev = nil;
	for(r=d->refhead; r; r=next){
		next = r->next;
		if(r->refptr == refptr){
			if(prev)
				prev->next = next;
			else
				d->refhead = next;
			if(d->reftail == r)
				d->reftail = prev;
			free(r);
		}else
			prev = r;
	}
	if(locked)
		unlockdisplay(d);
}

void
queuerefresh(Image *i, Rectangle r, Reffn reffn, void *refptr)
{
	Display *d;
	Refreshq *rq;

	d = i->display;
	rq = malloc(sizeof(Refreshq));
	if(rq == nil)
		return;
	if(d->reftail)
		d->reftail->next = rq;
	else
		d->refhead = rq;
	d->reftail = rq;
	rq->reffn = reffn;
	rq->refptr = refptr;
	rq->r = r;
}

uchar*
bufimage(Display *d, int n)
{
	uchar *p;

	if(n<0 || n>Displaybufsize){
		kwerrstr("bad count in bufimage");
		return 0;
	}
	if(d->bufp+n > d->buf+Displaybufsize){
		if(d->local==0 && currun()!=libqlowner(d->qlock)) {
			print("bufimage: %lux %lux\n", (ulong)libqlowner(d->qlock), (ulong)currun());
			abort();
		}
		if(doflush(d) < 0)
			return 0;
	}
	p = d->bufp;
	d->bufp += n;
	/* return with buffer locked */
	return p;
}

void
drawerror(Display *d, char *s)
{
	USED(d);
	fprint(2, "draw: %s: %r\n", s);
}
