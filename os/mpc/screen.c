#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"

#include	<draw.h>
#include	<memdraw.h>
#include	<cursor.h>

#include	"screen.h"

enum {
	Backgnd = 0xFF,	/* white */
	Foregnd =	0x00,	/* black */
};

Cursor	arrow = {
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

int	novgascreen;	/* optionally set by configuration file */
static	int	lcdpdpar;	/* value to load into io->pdpar */

Memimage *gscreen;
Memimage *conscol;
Memimage *back;

static	Memsubfont *memdefont;
static	Lock	palettelock;			/* access to DAC registers */
static	Lock	screenlock;
static	int	h;
static	Point	curpos;
static	Rectangle window;

typedef struct SWcursor SWcursor;
static SWcursor *swc = nil;
SWcursor* swcurs_create(ulong *, int, int, Rectangle, int);
void swcurs_destroy(SWcursor*);
void swcurs_enable(SWcursor*);
void swcurs_disable(SWcursor*);
void swcurs_hide(SWcursor*);
void swcurs_unhide(SWcursor*);
void swcurs_load(SWcursor*, Cursor*);

static	void	screenputc(char*);
static	void	scroll(void);
static	void	setscreen(Mode*);
static	void	cursorlock(Rectangle);
static	void	cursorunlock(void);
static	void	lcdinit(Mode*);
static	void	lcdsetrgb(int, ulong, ulong, ulong);

/*
 *  Called by main().
 */
void
screeninit(void)
{
	Mode m;

novgascreen=1; return;

	/* default size and parameters */
	memset(&m.lcd, 0, sizeof(m.lcd));
	m.x = 640;
	m.y = 480;
	m.d = 3;
	if(novgascreen == 0 && archlcdmode(&m) >= 0){
		memdefont = getmemdefont();
		setscreen(&m);
	}
}

/*
 * On 8 bit displays, load the default color map
 */
void
graphicscmap(int invert)
{
	int num, den, i, j;
	int r, g, b, cr, cg, cb, v;

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
			if(invert)
				setcolor(255-i-(j&15),
					cr*0x01010101, cg*0x01010101, cb*0x01010101);
			else
				setcolor(i+(j&15),
					cr*0x01010101, cg*0x01010101, cb*0x01010101);
		}
	}
}

/*
 *  reconfigure screen shape
 */
static void
setscreen(Mode *mode)
{
	int h;

	if(swc)
		swcurs_destroy(swc);

	gscreen = &xgscreen;
	xgdata.ref = 1;
	lcdinit(mode);
	xgdata.bdata = (uchar*)mode->aperture;
	if(xgdata.bdata == nil)
		panic("setscreen: vga soft memory");

	gscreen->r = Rect(0, 0, mode->x, mode->y);
	gscreen->clipr = gscreen->r;
	gscreen->depth = 1<<mode->d;
	gscreen->width = wordsperline(gscreen->r, gscreen->depth);
	memimageinit();
	memdefont = getmemdefont();

	memsetchan(gscreen, CMAP8);
	back = memwhite;
	conscol = memblack;
	memimagedraw(gscreen, gscreen->r, memwhite, ZP, memopaque, ZP, SoverD);
	graphicscmap(0);

	/* get size for a system window */
	h = memdefont->height;
	window = insetrect(gscreen->r, 4);
	window.max.y = window.min.y+(Dy(window)/h)*h;
	curpos = window.min;
//	screenclear();

	graphicscmap(0);

//	swc = swcurs_create(gscreendata.data, gscreen.width, gscreen.ldepth, gscreen.r, 1);

	drawcursor(nil);
}

enum {
	ScreenCached = 1	/* non-zero if screen region not write-through */
};

void
flushmemscreen(Rectangle r)
{
	if(rectclip(&r, gscreen->r) == 0)
		return;
	if(r.min.x >= r.max.x || r.min.y >= r.max.y)
		return;
	if(ScreenCached)
		dcflush((ulong*)gscreen->data->bdata + gscreen->width*r.min.y, gscreen->width*Dy(r));
}

/* 
 * export screen to interpreter
 */
uchar*
attachscreen(Rectangle *r, ulong *chan, int* d, int *width, int *softscreen)
{
	*r = gscreen->r;
	*d = gscreen->depth;
	*chan = gscreen->chan;
	*width = gscreen->width;
	*softscreen = ScreenCached;

	return (uchar*)gscreen->data->bdata;
}

void
detachscreen(void)
{
}

/*
 *  write a string to the screen
 */
void
screenputs(char *s, int n)
{
	int i;
	Rune r;
	char buf[4];

	if(novgascreen || xgdata.bdata == nil || memdefont == nil)
		return;
	if(islo() == 0) {
		/* don't deadlock trying to print in interrupt */
		if(!canlock(&screenlock))
			return;	
	} else
		lock(&screenlock);

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
	/* Only OK for now */
	flushmemscreen(gscreen->r);

	unlock(&screenlock);
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

int
setcolor(ulong p, ulong r, ulong g, ulong b)
{
	ulong x;

	if(gscreen->depth >= 8)
		x = 0xFF;
	else
		x = 0xF;
	p &= x;
	p ^= x;
	lock(&palettelock);
	lcdsetrgb(p, r, g, b);
	unlock(&palettelock);
	return ~0;
}

void
getcolor(ulong p, ulong *pr, ulong *pg, ulong *pb)
{
	/* TO DO */
	*pr = *pg = *pb = 0;
}

/*
 * See section 5.2.1 (page 5-6) of the MPC823 manual
 */
static uchar lcdclock[17] = {	/* (a<<2)|b => divisor of (1<<a)*((b<<1)+1) */
	0, 0, (1<<2), 1,
	(2<<2), 2, (1<<2)|1, 3,
	(3<<2), (1<<2)|2, (1<<2)|2, (2<<2)|1,
	(2<<2)|1, (1<<2)|3, (1<<2)|3, (4<<2),
	(4<<2)
};

enum {
	/* lccr */
	Enable = 1<<0,

	/* lchcr */
	BigEndian = 1<<24,
	AT7 = 7<<21,	/* access type */

	/* sdcr */
	LAM = 1<<6,	/* ``LCD aggressive mode'' */
};

/*
 * initialise MPC8xx LCD controller incorporating board or display-specific values in Mode.lcd
 */
static void
lcdinit(Mode *mode)
{
	IMM *io;
	int i, d;
	long hz;

	io = m->iomem;
	mode->aperture = xspanalloc(mode->x*mode->y, 16, 0);
	mode->apsize = mode->x*mode->y;

	io->sdcr = 1;	/* MPC823 errata: turn off LAM before disabling controller */
	eieio();
	io->lcfaa = PADDR(mode->aperture);
	io->lccr = (((mode->x*mode->y*(1<<mode->d)+127)/128) << 17) | (mode->d << 5) | mode->lcd.flags;
	switch(mode->d){
	default:
	case 0:
		/* monochrome/greyscale identity map */
		for(i=0; i<16; i++)
			io->lcdmap[i] = i;
		break;
	case 2:
		/* 4-bit grey scale map */
		for(i=0; i<16; i++)
			io->lcdmap[0] = (i<<8)|(i<<4)|i;
		break;
	case 3:
		/* 8-bit linear map */
		for(i=0; i<256; i++)
			io->lcdmap[i] = (i<<8)|(i<<4)|i;
		break;
	}

	io->lcvcr = (mode->y << 11) | (mode->lcd.vpw<<28) | (mode->lcd.ac<<21) | mode->lcd.wbf;
	io->lchcr = (mode->x<<10) | BigEndian | mode->lcd.wbl;

	hz = m->cpuhz;
	d = hz/mode->lcd.freq;
	if(hz/d > mode->lcd.freq)
		d++;
	if(d >= 16)
		d = 16;

	/*
	 * enable LCD outputs
	 */
	io->pddat = 0;
	lcdpdpar = 0x1fff & ~mode->lcd.notpdpar;
	io->pdpar = lcdpdpar;
	io->pddir = 0x1fff;
	io->pbpar |= IBIT(31) | IBIT(19) | IBIT(17);
	io->pbdir |= IBIT(31) | IBIT(19) | IBIT(17);
	io->pbodr &= ~(IBIT(31) | IBIT(19) | IBIT(17));
 
	/*
	 * with the data cache off, early revisions of the 823 did not require
	 * the `aggressive' DMA priority to avoid flicker, but flicker is obvious
	 * on the 823A when the cache is on, so LAM is now set
	 */
	io->sdcr = (io->sdcr & ~0xF) | LAM;	/* LAM=1, LAID=0, RAID=0 */

//	gscreen.width = gscreen.width;	/* access external memory before enabling (mpc823 errata) */
	eieio();
	io->sccrk = KEEP_ALIVE_KEY;
	eieio();
	io->sccr  = (io->sccr & ~0x1F) | lcdclock[d];
	eieio();
	io->sccrk= ~KEEP_ALIVE_KEY;
	io->lcsr = 7;	/* clear status */
	eieio();
	io->lccr |= Enable;
	archbacklight(1);
}

static void
lcdsetrgb(int p, ulong r, ulong g, ulong b)
{
	r >>= 28;
	g >>= 28;
	b >>= 28;
	m->iomem->lcdmap[p&0xFF] = (r<<8) | (g<<4) | b;
}

void
blankscreen(int blank)
{
	USED(blank);	/* TO DO */
}

/*
 * enable/disable LCD panel (eg, when using video subsystem)
 */
void
lcdpanel(int on)
{
	IMM *io;

	if(on){
		archbacklight(1);
		io = ioplock();
		io->pddat = 0;
		io->pdpar = lcdpdpar;
		io->pddir = 0x1fff;
		io->lccr |= Enable;
		iopunlock();
	}else{
		io = ioplock();
		io->sdcr = 1;	/* MPC823 errata: turn off LAM before disabling controller */
		eieio();
		io->pddir = 0;
		eieio();
		io->lccr &= ~Enable;
		iopunlock();
		archbacklight(0);
	}
}

/*
 *	Software cursor code.  Interim version (for baseline).
 *	we may want to replace code here by memdraw primitives.
 */

enum {
	CUR_ENA = 0x01,		/* cursor is enabled */
	CUR_DRW = 0x02,		/* cursor is currently drawn */
	CUR_SWP = 0x10,		/* bit swap */
	CURSWID	= 16,
	CURSHGT	= 16,
};

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
	lock(&screenlock);
	r.min.x -= 16;
	r.min.y -= 16;
	cursoroffrect = r;
	if (swc)
		cursorupdate0();
	unlock(&screenlock);
}

void
cursorenable(void)
{
	Point m;

	lock(&screenlock);
	if(swc) {
		swcurs_enable(swc);
		m = mousexy();
		swcursorflush(m.x, m.y);
	}
	unlock(&screenlock);
}

void
cursordisable(void)
{
	Point m;

	lock(&screenlock);
	if(swc) {
		swcurs_disable(swc);
		m = mousexy();
		swcursorflush(m.x, m.y);
	}
	unlock(&screenlock);
}

void
drawcursor(Drawcursor* c)
{
	Point p;
	Cursor curs, *cp;
	int j, i, h, bpl;
	uchar *bc, *bs, *cclr, *cset;

	if(!swc)
		return;

	/* Set the default system cursor */
	if(!c || c->data == nil)
		cp = &arrow /*&crosshair_black*/;
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

	if(swc) {
		swcurs_load(swc, cp);
		p = mousexy();
		swcursorflush(p.x, p.y);
	}
}

SWcursor*
swcurs_create(ulong *fb, int width, int ldepth, Rectangle r, int bitswap)
{
	SWcursor *swc = (SWcursor*)malloc(sizeof(SWcursor));
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

