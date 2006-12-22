#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "io.h"
#include "dat.h"
#include "fns.h"
#include "../port/error.h"

#include <draw.h>
#include <memdraw.h>
#include <memlayer.h>
#include <cursor.h>

#include "softcursor.h"
#include "screen.h"

#define	Backgnd		(0xFF)


ulong	consbits = 0xC0;
Memdata consdata = {
	nil,
	&consbits
};
Memimage conscol =
{
	{ 0, 0, 1, 1 },
	{ -100000, -100000, 100000, 100000 },
	3,
	1,
	&consdata,
	0,
	1
};

ulong	onesbits = ~0;
Memdata onesdata = {
	nil,
	&onesbits,
};
Memimage	xones =
{
	{ 0, 0, 1, 1 },
	{ -100000, -100000, 100000, 100000 },
	3,
	1,
	&onesdata,
	0,
	1
};
Memimage *memones = &xones;

ulong	zerosbits = 0;
Memdata zerosdata = {
	nil,
	&zerosbits,
};
Memimage	xzeros =
{
	{ 0, 0, 1, 1 },
	{ -100000, -100000, 100000, 100000 },
	3,
	1,
	&zerosdata,
	0,
	1
};
Memimage *memzeros = &xzeros;

ulong	backbits = (Backgnd<<24)|(Backgnd<<16)|(Backgnd<<8)|Backgnd;
Memdata backdata = {
	nil,
	&backbits
};
Memimage	xback =
{
	{ 0, 0, 1, 1 },
	{ -100000, -100000, 100000, 100000 },
	3,
	1,
	&backdata,
	0,
	1
};
Memimage *back = &xback;

Video *vid;
static Memsubfont *memdefont;
static Lock screenlock;
Memimage gscreen;
Memdata gscreendata;
static Point curpos;
static Rectangle window;

static Vctlr* vctlr;

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


void
graphicscmap(int invert)
{
	int num, den, i, j;
	int r, g, b, cr, cg, cb, v;

	if(vctlr->setcolor == nil)
		return;

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
				vctlr->setcolor(255-i-(j&15),
					cr*0x01010101,
					cg*0x01010101,
					cb*0x01010101);
			else
				vctlr->setcolor(i+(j&15),
					cr*0x01010101,
					cg*0x01010101,
					cb*0x01010101);
		}
	}
}

static char s1[] =
{
	0x00, 0x00, 0xC0, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};


void
dacinit(void)
{
	int i;

	/* Control registers */
	vid->addr = 0x01 << 24;
	vid->color = 0x02 << 24;
	for(i = 0; i < sizeof s1; i++)
		vid->cntrl = s1[i] << 24;

	/* Cursor programming */
	vid->addr = 0x00 << 24;
	vid->color = 0x03 << 24;
	vid->cntrl = 0xC0 << 24;
	for(i = 0; i < 12; i++)
		vid->cntrl = 0 << 24;

	/* Load Cursor Ram */
	vid->addr = 0x00 << 24;
	vid->color = 0x04 << 24;
	for(i = 0; i < 0x400; i++)
		vid->cntrl = 0xff << 24;

	graphicscmap(1);

	/* Overlay Palette Ram */
	vid->addr = 0x00 << 24;
	vid->color = 0x01 << 24;
	for(i = 0; i < 0x10; i++) {
		vid->cntrl = 0xff << 24;
		vid->cntrl = 0xff << 24;
		vid->cntrl = 0xff << 24;
	}

	/* Overlay Palette Ram */
	vid->addr = 0x81;
	vid->color = 0x01;
	for(i = 0; i < 3; i++) {
		vid->cntrl = 0xff << 24;
		vid->cntrl = 0xff << 24;
		vid->cntrl = 0xff << 24;
	}
}

void
vctlrinit(int x, int y, int d)
{
	int h;
	ulong va;

	if(vctlr == nil){
		/*
		 * find a controller somehow
		 * and call its init routine
		 */
		extern Vctlr FSV;

		vctlr = FSV.init(0, x, y, d);
		vctlr->load(&arrow);
	}

	if(vctlr == nil)
		panic("%s",Ebadarg);

	gscreen.data = &gscreendata;
	gscreen.r.min = Pt(0, 0);
	gscreen.r.max = Pt(vctlr->x, vctlr->y);
	gscreen.clipr = gscreen.r;
	gscreen.ldepth = vctlr->d;
	gscreen.repl = 0;
	va = kmapsbus(FSVSLOT);			/* FSV is in slot 2 */
	gscreendata.data = (ulong *)(va+0x800000);	/* Framebuffer Magic */
	gscreen.width = (vctlr->x *(1<<gscreen.ldepth)+31)/32;
	

	h = memdefont->height;

	vid = (Video*)(va+0x240000);	/* RAMDAC Magic */
	memset(gscreendata.data, Backgnd, vctlr->x*vctlr->y);
	window = gscreen.r;
	window.max.x = vctlr->x;
	window.max.y = (vctlr->y/h) * h;
	curpos = window.min;
	if (gscreen.ldepth == 3){
		dacinit();
	}

	memset(gscreendata.data, Backgnd, vctlr->x*vctlr->y);
	window = gscreen.r;
	window.max.x = vctlr->x;
	window.max.y = (vctlr->y/h) * h;
	curpos = window.min;
}

void
screeninit(void)
{
	memdefont = getmemdefont();
	vctlrinit(1024, 768, 3);
}

ulong*
attachscreen(Rectangle *r, int *ld, int *width, int *softscreen)
{
	*r = gscreen.r;
	*ld = gscreen.ldepth;
	*width = gscreen.width;
	*softscreen = 0;
	return gscreendata.data;
}

void
detachscreen(void)
{
}

void
flushmemscreen(Rectangle)
{
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
	memdraw(&gscreen, r, &gscreen, p, memones, p);
	r = Rpt(Pt(window.min.x, window.max.y-o), window.max);
	memdraw(&gscreen, r, back, memzeros->r.min, memones, memzeros->r.min);

	curpos.y -= o;
}

void
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
		screenputc("\r");
		break;
	case '\r':
		xp = xbuf;
		curpos.x = window.min.x;
		break;
	case '\t':
		p = memsubfontwidth(memdefont, " ");
		w = p.x;
		*xp++ = curpos.x;
		pos = (curpos.x-window.min.x)/w;
		pos = 8-(pos%8);
		curpos.x += pos*w;
		break;
	case '\b':
		if(xp <= xbuf)
			break;
		xp--;
		r = Rpt(Pt(*xp, curpos.y), Pt(curpos.x, curpos.y + h));
		memdraw(&gscreen, r, back, back->r.min, memones, back->r.min);
		curpos.x = *xp;
		break;
	default:
		p = memsubfontwidth(memdefont, buf);
		w = p.x;

		if(curpos.x >= window.max.x-w)
			screenputc("\n");

		*xp++ = curpos.x;
		memimagestring(&gscreen, curpos, &conscol, memdefont, buf);
		curpos.x += w;
	}
}

void
screenputs(char *s, int n)
{
	int i;
	Rune r;
	char buf[4];
extern int cold;

if(!cold)
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

	unlock(&screenlock);
}


void
cursorenable(void)
{
	if(vctlr->enable == nil)
		return;
	
	vctlr->enable();

	if(!vctlr->isloaded())
		vctlr->load(&arrow);
}

void
cursordisable(void)
{
	if(vctlr->disable == nil)
		return;

	vctlr->disable();
}

static Rectangle cursoroffrect;
static int	cursorisoff;
static Point hot;

void
cursorupdate0(void)
{
	int inrect, x, y;

	x = mouse.x - hot.x;
	y = mouse.y - hot.y;
	inrect = (x >= cursoroffrect.min.x && x < cursoroffrect.max.x
		&& y >= cursoroffrect.min.y && y < cursoroffrect.max.y);
	if (cursorisoff == inrect)
		return;
	cursorisoff = inrect;
	if (inrect)
		cursordisable();
	else
		cursorenable();
}

void
cursorupdate(Rectangle r)
{
	lock(&screenlock);
	r.min.x -= 16;
	r.min.y -= 16;
	cursoroffrect = r;
	if (swcursor)
		cursorupdate0();
	unlock(&screenlock);
}

void
drawcursor(Drawcursor* c)
{
	Cursor curs;
	int j, i, h, bpl;
	uchar *bc, *bs, *cclr, *cset;

	if(vctlr->load == nil)
		return;

	/* Set the default system cursor */
	if(c->data == nil) {
		lock(&screenlock);
		vctlr->load(&arrow);
		unlock(&screenlock);
		return;
	}

	hot.x = c->hotx;
	hot.y = c->hoty;
	curs.offset = hot;
	bpl = bytesperline(Rect(c->minx, c->miny, c->maxx, c->maxy), 0);

	h = (c->maxy-c->miny)/2;
	if(h > 16)
		h = 16;

	bc = c->data;
	bs = c->data + h*bpl;

	cclr = curs.clr;
	cset = curs.set;
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
	lock(&screenlock);
	vctlr->load(&curs);
	unlock(&screenlock);
}

