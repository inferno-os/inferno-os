#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "../port/error.h"
#include "io.h"

#include <draw.h>
#include <memdraw.h>
#include <cursor.h>

#include "screen.h"

enum {
	Backgnd = 0xFF,	/* white */
	Foregnd =	0x00,	/* black */
};

#define	DPRINT	if(1)iprint

static Memdata xgdata;
static Memimage xgscreen =
{
	{0, 0, 0, 0},	/* r */
	{0, 0, 0, 0},	/* clipr */
	8,			/* depth */
	1,			/* nchan */
	CMAP8,		/* chan */
	nil,			/* cmap */
	&xgdata,		/* data */
	0,			/* zero */
	0,			/* width */
	nil,			/* layer */
	0,			/* flags */
};

Memimage *gscreen;
Memimage *conscol;
Memimage *back;

Memsubfont *memdefont;

static Point curpos;
static Rectangle window;

typedef struct SWcursor SWcursor;

static Vdisplay *vd;
static SWcursor *swc = nil;

SWcursor* swcurs_create(ulong *, int, int, Rectangle, int);
void swcurs_destroy(SWcursor*);
void swcurs_enable(SWcursor*);
void swcurs_disable(SWcursor*);
void swcurs_hide(SWcursor*);
void swcurs_unhide(SWcursor*);
void swcurs_load(SWcursor*, Cursor*);
void swcursupdate(int, int, int, int);

static char printbuf[1024];
static int printbufpos = 0;
static void	lcdscreenputs(char*, int);
static void screenpbuf(char*, int);
void (*screenputs)(char*, int) = screenpbuf;

static Cursor arrow = {
	{ -1, -1 },
	{ 0xFF, 0xFF, 0x80, 0x01, 0x80, 0x02, 0x80, 0x0C,
	  0x80, 0x10, 0x80, 0x10, 0x80, 0x08, 0x80, 0x04,
	  0x80, 0x02, 0x80, 0x01, 0x80, 0x02, 0x8C, 0x04,
	  0x92, 0x08, 0x91, 0x10, 0xA0, 0xA0, 0xC0, 0x40,
	},
	{ 0x00, 0x00, 0x7F, 0xFE, 0x7F, 0xFC, 0x7F, 0xF0,
	  0x7F, 0xE0, 0x7F, 0xE0, 0x7F, 0xF0, 0x7F, 0xF8,
	  0x7F, 0xFC, 0x7F, 0xFE, 0x7F, 0xFC, 0x73, 0xF8,
	  0x61, 0xF0, 0x60, 0xE0, 0x40, 0x40, 0x00, 0x00,
	},
};

static	ushort	palette16[256];
static	void	(*flushpixels)(Rectangle, ulong*, int, ulong*, int);
static	void	flush8to4(Rectangle, ulong*, int, ulong*, int);
static	void	flush8to4r(Rectangle, ulong*, int, ulong*, int);
static	void	flush8to16(Rectangle, ulong*, int, ulong*, int);
static	void	flush8to16r(Rectangle, ulong*, int, ulong*, int);

/*
lccr0=000000b9 lccr1=0b100930 lccr2=0a0108ef lccr3=00300010
	---
vd->wid=320 bwid=640 gscreen->width=60 fb=d0b7cb80 data=d0ba25c0
 */

int
setcolor(ulong p, ulong r, ulong g, ulong b)
{
	if(vd->depth >= 8)
		p &= 0xff;
	else
		p &= 0xf;
	vd->colormap[p][0] = r;
	vd->colormap[p][1] = g;
	vd->colormap[p][2] = b;
	palette16[p] = ((r>>(32-4))<<12)|((g>>(32-4))<<7)|((b>>(32-4))<<1);
	lcd_setcolor(p, r, g, b);
	return ~0;
}

void
getcolor(ulong p, ulong *pr, ulong *pg, ulong *pb)
{
	if(vd->depth >= 8)
		p = (p&0xff)^0xff;
	else
		p = (p&0xf)^0xf;
	*pr = vd->colormap[p][0];
	*pg = vd->colormap[p][1];
	*pb = vd->colormap[p][2];
}

void
graphicscmap(int invert)
{
	int num, den, i, j;
	int r, g, b, cr, cg, cb, v, p;

	for(r=0,i=0;r!=4;r++) for(v=0;v!=4;v++,i+=16){
		for(g=0,j=v-r;g!=4;g++) for(b=0;b!=4;b++,j++){
			den=r;
			if(g>den) den=g;
			if(b>den) den=b;
			if(den==0)	/* divide check -- pick grey shades */
				cr=cg=cb=v*17;
			else{
				num=17*(4*den+v);
				cr=r*num/den;
				cg=g*num/den;
				cb=b*num/den;
			}
			p = (i+(j&15));
			if(invert)
				p ^= 0xFF;
			if(vd->depth == 4) {
				if((p&0xf) != (p>>4))
					continue;
				p &= 0xf;
			}
			setcolor(p,
				cr*0x01010101,
				cg*0x01010101,
				cb*0x01010101);
		}
	}
	lcd_flush();
}

static uchar lum[256]={
  0,   7,  15,  23,  39,  47,  55,  63,  79,  87,  95, 103, 119, 127, 135, 143,
154,  17,   9,  17,  25,  49,  59,  62,  68,  89,  98, 107, 111, 129, 138, 146,
157, 166,  34,  11,  19,  27,  59,  71,  69,  73,  99, 109, 119, 119, 139, 148,
159, 169, 178,  51,  13,  21,  29,  69,  83,  75,  78, 109, 120, 131, 128, 149,
 28,  35,  43,  60,  68,  75,  83, 100, 107, 115, 123, 140, 147, 155, 163,  20,
 25,  35,  40,  47,  75,  85,  84,  89, 112, 121, 129, 133, 151, 159, 168, 176,
190,  30,  42,  44,  50,  90, 102,  94,  97, 125, 134, 144, 143, 163, 172, 181,
194, 204,  35,  49,  49,  54, 105, 119, 103, 104, 137, 148, 158, 154, 175, 184,
 56,  63,  80,  88,  96, 103, 120, 128, 136, 143, 160, 168, 175, 183,  40,  48,
 54,  63,  69,  90,  99, 107, 111, 135, 144, 153, 155, 173, 182, 190, 198,  45,
 50,  60,  70,  74, 100, 110, 120, 120, 150, 160, 170, 167, 186, 195, 204, 214,
229,  55,  66,  77,  79, 110, 121, 131, 129, 165, 176, 187, 179, 200, 210, 219,
 84, 100, 108, 116, 124, 140, 148, 156, 164, 180, 188, 196, 204,  60,  68,  76,
 82,  91, 108, 117, 125, 134, 152, 160, 169, 177, 195, 204, 212, 221,  66,  74,
 80,  89,  98, 117, 126, 135, 144, 163, 172, 181, 191, 210, 219, 228, 238,  71,
 76,  85,  95, 105, 126, 135, 145, 155, 176, 185, 195, 205, 225, 235, 245, 255,
};

void flushmemscreen(Rectangle r);

void
screenclear(void)
{
	memimagedraw(gscreen, gscreen->r, memwhite, ZP, memopaque, ZP, SoverD);
	curpos = window.min;
	flushmemscreen(gscreen->r);
}

static void
setscreen(LCDmode *mode)
{
	int h;

	if(swc != nil)
		swcurs_destroy(swc);

	vd = lcd_init(mode);
	if(vd == nil)
		panic("can't initialise LCD");

	if(lum[255] == 255) {
		int i;
		for(i=0; i<256; i++)
			lum[i] >>= 4;	/* could support depths other than 4 */
	}

	gscreen = &xgscreen;
	xgdata.ref = 1;

	if(conf.portrait == 0)
		gscreen->r = Rect(0, 0, vd->x, vd->y);
	else
		gscreen->r = Rect(0, 0, vd->y, vd->x);
	gscreen->clipr = gscreen->r;
	gscreen->depth = 8;
	gscreen->width = wordsperline(gscreen->r, gscreen->depth);
	if(vd->depth == 4 || vd->depth == 16 || conf.portrait) {	/* use 8 to 4 bit fakeout for speed */
		if((xgdata.bdata = xspanalloc(gscreen->width*gscreen->r.max.y*BY2WD+CACHELINESZ, CACHELINESZ, 0)) == nil)
			panic("can't alloc vidmem");
		xgdata.bdata = minicached(xgdata.bdata);
		if(conf.portrait == 0)
			flushpixels = vd->depth==4? flush8to4: flush8to16;
		else
			flushpixels = vd->depth==4? flush8to4r: flush8to16r;
	} else{
		xgdata.bdata = (uchar*)vd->fb;
		flushpixels = nil;
	}
	memimageinit();
	memdefont = getmemdefont();

	memsetchan(gscreen, CMAP8);	/* TO DO: could now use RGB16 */
	back = memwhite;
	conscol = memblack;
	memimagedraw(gscreen, gscreen->r, memwhite, ZP, memopaque, ZP, SoverD);

	DPRINT("vd->wid=%d bwid=%d gscreen->width=%ld fb=%p data=%p\n",
		vd->x, vd->bwid, gscreen->width, vd->fb, xgdata.bdata);
	graphicscmap(0);
	h = memdefont->height;
	window = insetrect(gscreen->r, 4);
	window.max.y = window.min.y+(Dy(window)/h)*h;
	screenclear();

//	swc = swcurs_create(gscreendata.data, gscreen.width, gscreen.ldepth, gscreen.r, 1);

	drawcursor(nil);
}

void
screeninit(void)
{
	LCDmode lcd;

	memset(&lcd, 0, sizeof(lcd));
	if(archlcdmode(&lcd) < 0)
		return;
	setscreen(&lcd);
	screenputs = lcdscreenputs;
	if(printbufpos)
		screenputs("", 0);
	blanktime = 3;	/* minutes */
}

uchar*
attachscreen(Rectangle *r, ulong *chan, int* d, int *width, int *softscreen)
{
	*r = gscreen->r;
	*d = gscreen->depth;
	*chan = gscreen->chan;
	*width = gscreen->width;
	*softscreen = (gscreen->data->bdata != (uchar*)vd->fb);

	return (uchar*)gscreen->data->bdata;
}

void
detachscreen(void)
{
}

static void
flush8to4(Rectangle r, ulong *s, int sw, ulong *d, int dw)
{
	int i, h, w;

/*
	print("1) s=%ux sw=%d d=%ux dw=%d r=(%d,%d)(%d,%d)\n",
		s, sw, d, dw, r.min.x, r.min.y, r.max.x, r.max.y);
*/

	r.min.x &= ~7;
	r.max.x = (r.max.x + 7) & ~7;
	s += (r.min.y*sw)+(r.min.x>>2);
	d += (r.min.y*dw)+(r.min.x>>3);
	h = Dy(r);
	w = Dx(r) >> 3;
	sw -= w*2;
	dw -= w;

	while(h--) {
		for(i=w; i; i--) {
			ulong v1 = *s++;
			ulong v2 = *s++;
			*d++ = 	 (lum[v2>>24]<<28)
				|(lum[(v2>>16)&0xff]<<24)
				|(lum[(v2>>8)&0xff]<<20)
				|(lum[v2&0xff]<<16)
				|(lum[v1>>24]<<12)
				|(lum[(v1>>16)&0xff]<<8)
				|(lum[(v1>>8)&0xff]<<4)
				|(lum[v1&0xff])
				;
		}
		s += sw;
		d += dw;
	}
}

static void
flush8to16(Rectangle r, ulong *s, int sw, ulong *d, int dw)
{
	int i, h, w;
	ushort *p;

	if(0)
		iprint("1) s=%p sw=%d d=%p dw=%d r=[%d,%d, %d,%d]\n",
		s, sw, d, dw, r.min.x, r.min.y, r.max.x, r.max.y);

	r.min.x &= ~3;
	r.max.x = (r.max.x + 3) & ~3;	/* nearest ulong */
	s += (r.min.y*sw)+(r.min.x>>2);
	d += (r.min.y*dw)+(r.min.x>>1);
	h = Dy(r);
	w = Dx(r) >> 2;	/* also ulong */
	sw -= w;
	dw -= w*2;
	if(0)
		iprint("h=%d w=%d sw=%d dw=%d\n", h, w, sw, dw);

	p = palette16;
	while(--h >= 0){
		for(i=w; --i>=0;){
			ulong v = *s++;
			*d++ = (p[(v>>8)&0xFF]<<16) | p[v & 0xFF];
			*d++ = (p[v>>24]<<16) | p[(v>>16)&0xFF];
		}
		s += sw;
		d += dw;
	}
}

static void
flush8to4r(Rectangle r, ulong *s, int sw, ulong *d, int dw)
{
	flush8to4(r, s, sw, d, dw);	/* rotation not implemented */
}

static void
flush8to16r(Rectangle r, ulong *s, int sw, ulong *d, int dw)
{
	int x, y, w, dws;
	ushort *p;
	ushort *ds;

	if(0)
		iprint("1) s=%p sw=%d d=%p dw=%d r=[%d,%d, %d,%d]\n",
		s, sw, d, dw, r.min.x, r.min.y, r.max.x, r.max.y);

	r.min.y &= ~3;
	r.max.y = (r.max.y+3) & ~3;
	r.min.x &= ~7;
	r.max.x = (r.max.x + 7) & ~7;
	s += (r.min.y*sw)+(r.min.x>>2);
//	d += (r.min.y*dw)+(r.min.x>>1);
	w = Dx(r) >> 2;	/* also ulong */
	sw -= w;
	dws = dw*2;
	if(0)
		iprint("h=%d w=%d sw=%d dw=%d x,y=%d,%d %d\n", Dy(r), w, sw, dw, r.min.x,r.min.y, dws);

	p = palette16;
	for(y=r.min.y; y<r.max.y; y++){
		for(x=r.min.x; x<r.max.x; x+=4){
			ulong v = *s++;
			ds = (ushort*)(d + x*dw) + (gscreen->r.max.y-(y+1));
			ds[0] = p[v & 0xFF];
			ds[dws] = p[(v>>8)&0xFF];
			ds[dws*2] = p[(v>>16)&0xFF];
			ds[dws*3] = p[(v>>24)&0xFF];
		}
		s += sw;
	}
}

void
flushmemscreen(Rectangle r)
{
	if(rectclip(&r, gscreen->r) == 0)
		return;
	if(r.min.x >= r.max.x || r.min.y >= r.max.y)
		return;
	if(flushpixels != nil)
		flushpixels(r, (ulong*)gscreen->data->bdata, gscreen->width, (ulong*)vd->fb, vd->bwid >> 2);
	lcd_flush();
}

static void
scroll(void)
{
	int o;
	Point p;
	Rectangle r;

	o = 4*memdefont->height;
	r = Rpt(window.min, Pt(window.max.x, window.max.y-o));
	p = Pt(window.min.x, window.min.y+o);
	memimagedraw(gscreen, r, gscreen, p, nil, p, SoverD);
	flushmemscreen(r);
	r = Rpt(Pt(window.min.x, window.max.y-o), window.max);
	memimagedraw(gscreen, r, back, ZP, nil, ZP, SoverD);
	flushmemscreen(r);

	curpos.y -= o;
}

static void
clearline(void)
{
	Rectangle r;
	int yloc = curpos.y;

	r = Rpt(Pt(window.min.x, window.min.y + yloc),
		Pt(window.max.x, window.min.y+yloc+memdefont->height));
	memimagedraw(gscreen, r, back, ZP, nil, ZP, SoverD);
}

static void
screenputc(char *buf)
{
	Point p;
	int h, w, pos;
	Rectangle r;
	static int *xp;
	static int xbuf[256];

	h = memdefont->height;
	if(xp < xbuf || xp >= &xbuf[sizeof(xbuf)])
		xp = xbuf;

	switch(buf[0]) {
	case '\n':
		if(curpos.y+h >= window.max.y)
			scroll();
		curpos.y += h;
		/* fall through */
	case '\r':
		xp = xbuf;
		curpos.x = window.min.x;
		break;
	case '\t':
		if(curpos.x == window.min.x)
			clearline();
		p = memsubfontwidth(memdefont, " ");
		w = p.x;
		*xp++ = curpos.x;
		pos = (curpos.x-window.min.x)/w;
		pos = 8-(pos%8);
		r = Rect(curpos.x, curpos.y, curpos.x+pos*w, curpos.y+h);
		memimagedraw(gscreen, r, back, ZP, nil, ZP, SoverD);
		flushmemscreen(r);
		curpos.x += pos*w;
		break;
	case '\b':
		if(xp <= xbuf)
			break;
		xp--;
		r = Rpt(Pt(*xp, curpos.y), Pt(curpos.x, curpos.y + h));
		memimagedraw(gscreen, r, back, ZP, nil, ZP, SoverD);
		flushmemscreen(r);
		curpos.x = *xp;
		break;
	case '\0':
		break;
	default:
		p = memsubfontwidth(memdefont, buf);
		w = p.x;

		if(curpos.x >= window.max.x-w)
			screenputc("\n");

		if(curpos.x == window.min.x)
			clearline();
		if(xp < xbuf+nelem(xbuf))
			*xp++ = curpos.x;
		r = Rect(curpos.x, curpos.y, curpos.x+w, curpos.y+h);
		memimagedraw(gscreen, r, back, ZP, nil, ZP, SoverD);
		memimagestring(gscreen, curpos, conscol, ZP, memdefont, buf);
		flushmemscreen(r);
		curpos.x += w;
	}
}

static void
screenpbuf(char *s, int n)
{
	if(printbufpos+n > sizeof(printbuf))
		n = sizeof(printbuf)-printbufpos;
	if(n > 0) {
		memmove(&printbuf[printbufpos], s, n);
		printbufpos += n;
	}
}

static void
screendoputs(char *s, int n)
{
	int i;
	Rune r;
	char buf[4];

	while(n > 0) {
		i = chartorune(&r, s);
		if(i == 0){
			s++;
			--n;
			continue;
		}
		memmove(buf, s, i);
		buf[i] = 0;
		n -= i;
		s += i;
		screenputc(buf);
	}
}

void
screenflush(void)
{
	int j = 0;
	int k;

	for (k = printbufpos; j < k; k = printbufpos) {
		screendoputs(printbuf + j, k - j);
		j = k;
	}
	printbufpos = 0;
}

static void
lcdscreenputs(char *s, int n)
{
	static Proc *me;

	if(!canlock(vd)) {
		/* don't deadlock trying to print in interrupt */
		/* don't deadlock trying to print while in print */
		if(islo() == 0 || up != nil && up == me){
			/* save it for later... */
			/* In some cases this allows seeing a panic message
			  that would be locked out forever */
			screenpbuf(s, n);
			return;
		}
		lock(vd);
	}

	me = up;
	if (printbufpos)
		screenflush();
	screendoputs(s, n);
	if (printbufpos)
		screenflush();
	me = nil;

	unlock(vd);
}

/*
 *	Software cursor code: done by hand, might be better to use memdraw
 */
 
typedef struct SWcursor {
	ulong	*fb;	/* screen frame buffer */
	Rectangle r;
	int	d;	/* ldepth of screen */
	int 	width;	/* width of screen in ulongs */
	int	x;
	int	y;
	int	hotx;
	int	hoty;
	uchar	cbwid;	/* cursor byte width */
	uchar	f;	/* flags */
	uchar	cwid;
	uchar	chgt;
	int	hidecount;
	uchar	data[CURSWID*CURSHGT];
	uchar	mask[CURSWID*CURSHGT];
	uchar	save[CURSWID*CURSHGT];
} SWcursor;

enum {
	CUR_ENA = 0x01,		/* cursor is enabled */
	CUR_DRW = 0x02,		/* cursor is currently drawn */
	CUR_SWP = 0x10,		/* bit swap */
};

static Rectangle cursoroffrect;
static int	cursorisoff;

static void swcursorflush(int, int);
static void	swcurs_draw_or_undraw(SWcursor *);

static void
cursorupdate0(void)
{
	int inrect, x, y;
	Point m;

	m = mousexy();
	x = m.x - swc->hotx;
	y = m.y - swc->hoty;
	inrect = (x >= cursoroffrect.min.x && x < cursoroffrect.max.x
		&& y >= cursoroffrect.min.y && y < cursoroffrect.max.y);
	if (cursorisoff == inrect)
		return;
	cursorisoff = inrect;
	if (inrect)
		swcurs_hide(swc);
	else {
		swc->hidecount = 0;
		swcurs_draw_or_undraw(swc);
	}
	swcursorflush(m.x, m.y);
}

void
cursorupdate(Rectangle r)
{
	lock(vd);
	r.min.x -= 16;
	r.min.y -= 16;
	cursoroffrect = r;
	if (swc != nil)
		cursorupdate0();
	unlock(vd);
}

void
cursorenable(void)
{
	Point m;

	lock(vd);
	if(swc != nil) {
		swcurs_enable(swc);
		m = mousexy();
		swcursorflush(m.x, m.y);
	}
	unlock(vd);
}

void
cursordisable(void)
{
	Point m;

	lock(vd);
	if(swc != nil) {
		swcurs_disable(swc);
		m = mousexy();
		swcursorflush(m.x, m.y);
	}
	unlock(vd);
}

void
swcursupdate(int oldx, int oldy, int x, int y)
{

	if(!canlock(vd))
		return;		/* if can't lock, don't wake up stuff */

	if(x < gscreen->r.min.x)
		x = gscreen->r.min.x;
	if(x >= gscreen->r.max.x)
		x = gscreen->r.max.x;
	if(y < gscreen->r.min.y)
		y = gscreen->r.min.y;
	if(y >= gscreen->r.max.y)
		y = gscreen->r.max.y;
	if(swc != nil) {
		swcurs_hide(swc);
		swc->x = x;
		swc->y = y;
		cursorupdate0();
		swcurs_unhide(swc);
		swcursorflush(oldx, oldy);
		swcursorflush(x, y);
	}

	unlock(vd);
}

void
drawcursor(Drawcursor* c)
{
	Point p, m;
	Cursor curs, *cp;
	int j, i, h, bpl;
	uchar *bc, *bs, *cclr, *cset;

	if(swc == nil)
		return;

	/* Set the default system cursor */
	if(c == nil || c->data == nil){
		swcurs_disable(swc);
		return;
	}
	else {
		cp = &curs;
		p.x = c->hotx;
		p.y = c->hoty;
		cp->offset = p;
		bpl = bytesperline(Rect(c->minx, c->miny, c->maxx, c->maxy), 1);

		h = (c->maxy-c->miny)/2;
		if(h > 16)
			h = 16;

		bc = c->data;
		bs = c->data + h*bpl;

		cclr = cp->clr;
		cset = cp->set;
		for(i = 0; i < h; i++) {
			for(j = 0; j < 2; j++) {
				cclr[j] = bc[j];
				cset[j] = bs[j];
			}
			bc += bpl;
			bs += bpl;
			cclr += 2;
			cset += 2;
		}
	}
	swcurs_load(swc, cp);
	m = mousexy();
	swcursorflush(m.x, m.y);
	swcurs_enable(swc);
}

SWcursor*
swcurs_create(ulong *fb, int width, int ldepth, Rectangle r, int bitswap)
{
	SWcursor *swc;

	swc = (SWcursor*)malloc(sizeof(SWcursor));
	swc->fb = fb;
	swc->r = r;
	swc->d = ldepth;
	swc->width = width;
	swc->f = bitswap ? CUR_SWP : 0;
	swc->x = swc->y = 0;
	swc->hotx = swc->hoty = 0;
	swc->hidecount = 0;
	return swc;
}

void
swcurs_destroy(SWcursor *swc)
{
	swcurs_disable(swc);
	free(swc);
}

static void
swcursorflush(int x, int y)
{
	Rectangle r;

	/* XXX a little too paranoid here */
	r.min.x = x-16;
	r.min.y = y-16;
	r.max.x = x+17;
	r.max.y = y+17;
	flushmemscreen(r);
}

static void
swcurs_draw_or_undraw(SWcursor *swc)
{
	uchar *p;
	uchar *cs;
	int w, vw;
	int x1 = swc->r.min.x;
	int y1 = swc->r.min.y;
	int x2 = swc->r.max.x;
	int y2 = swc->r.max.y; 
	int xp = swc->x - swc->hotx;
	int yp = swc->y - swc->hoty;
	int ofs;

	if(((swc->f & CUR_ENA) && (swc->hidecount <= 0))
			 == ((swc->f & CUR_DRW) != 0))
		return;
	w = swc->cbwid*BI2BY/(1 << swc->d);
	x1 = xp < x1 ? x1 : xp;
	y1 = yp < y1 ? y1 : yp;
	x2 = xp+w >= x2 ? x2 : xp+w;
	y2 = yp+swc->chgt >= y2 ? y2 : yp+swc->chgt;
	if(x2 <= x1 || y2 <= y1)
		return;
	p = (uchar*)(swc->fb + swc->width*y1)
		+ x1*(1 << swc->d)/BI2BY;
	y2 -= y1;
	x2 = (x2-x1)*(1 << swc->d)/BI2BY;
	vw = swc->width*BY2WD - x2;
	w = swc->cbwid - x2;
	ofs = swc->cbwid*(y1-yp)+(x1-xp);
	cs = swc->save + ofs;
	if((swc->f ^= CUR_DRW) & CUR_DRW) {
		uchar *cm = swc->mask + ofs; 
		uchar *cd = swc->data + ofs;
		while(y2--) {
			x1 = x2;
			while(x1--) {
				*p = ((*cs++ = *p) & *cm++) ^ *cd++;
				p++;
			}
			cs += w;
			cm += w;
			cd += w;
			p += vw;
		}
	} else {
		while(y2--) {
			x1 = x2;
			while(x1--) 
				*p++ = *cs++;
			cs += w;
			p += vw;
		}
	}
}

void
swcurs_hide(SWcursor *swc)
{
	++swc->hidecount;
	swcurs_draw_or_undraw(swc);
}

void
swcurs_unhide(SWcursor *swc)
{
	if (--swc->hidecount < 0)
		swc->hidecount = 0;
	swcurs_draw_or_undraw(swc);
}

void
swcurs_enable(SWcursor *swc)
{
	swc->f |= CUR_ENA;
	swcurs_draw_or_undraw(swc);
}

void
swcurs_disable(SWcursor *swc)
{
	swc->f &= ~CUR_ENA;
	swcurs_draw_or_undraw(swc);
}

void
swcurs_load(SWcursor *swc, Cursor *c)
{
	int i, k;
	uchar *bc, *bs, *cd, *cm;
	static uchar bdv[4] = {0,Backgnd,Foregnd,0xff};
	static uchar bmv[4] = {0xff,0,0,0xff};
	int bits = 1<<swc->d;
	uchar mask = (1<<bits)-1;
	int bswp = (swc->f&CUR_SWP) ? 8-bits : 0;

	bc = c->clr;
	bs = c->set;

	swcurs_hide(swc);
	cd = swc->data;
	cm = swc->mask;
	swc->hotx = c->offset.x;
	swc->hoty = c->offset.y;
	swc->chgt = CURSHGT;
	swc->cwid = CURSWID;
	swc->cbwid = CURSWID*(1<<swc->d)/BI2BY;
	for(i = 0; i < CURSWID/BI2BY*CURSHGT; i++) {
		uchar bcb = *bc++;
		uchar bsb = *bs++;
		for(k=0; k<BI2BY;) {
			uchar cdv = 0;
			uchar cmv = 0;
			int z;
			for(z=0; z<BI2BY; z += bits) {
				int n = ((bsb&(0x80))|((bcb&(0x80))<<1))>>7;
				int s = z^bswp;
				cdv |= (bdv[n]&mask) << s;
				cmv |= (bmv[n]&mask) << s;
				bcb <<= 1;
				bsb <<= 1;
				k++;
			}
			*cd++ = cdv;
			*cm++ = cmv;
		}
	}
	swcurs_unhide(swc);
}
