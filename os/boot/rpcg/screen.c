#include	"all.h"
#include	<libg.h>
#include	<gnot.h>

enum {
	Colldepth		= 3,
	Colmaxx		= 640,
	Colmaxxvis	= 640,
	Colmaxy		= 480,
};

#define	MINX	8

extern	GSubfont	defont0;

struct{
	Point	pos;
	int	bwid;
}out;

typedef struct Mode Mode;
struct Mode {
	int	x;
	int	y;
	int	d;
	char*	aperture;
	int	apsize;
};

GBitmap	gscreen;
Point	gchar(GBitmap*, Point, GFont*, int, Fcode);
int	setcolor(ulong, ulong, ulong, ulong);
static	void	lcdinit(Mode*);

void
screeninit(void)
{
	Mode m;

	m.x = Colmaxx;
	m.y = Colmaxy;
	m.d = Colldepth;
	m.aperture = 0;
	lcdinit(&m);
	if(m.aperture == 0)
		return;
	gscreen.ldepth = 3;
	gscreen.base = (ulong*)m.aperture;
	gscreen.width = Colmaxx/BY2WD;
	gscreen.r = Rect(0, 0, Colmaxxvis, Colmaxy);
	gscreen.clipr = gscreen.r;
	/*
	 * For now, just use a fixed colormap:
	 * 0 == white and 255 == black
	 */
	setcolor(0, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF);
	setcolor(255, 0x00000000, 0x00000000, 0x00000000);

	gbitblt(&gscreen, Pt(0, 0), &gscreen, gscreen.r, Zero);
	out.pos.x = MINX;
	out.pos.y = 0;
	out.bwid = defont0.info[' '].width;
}

void
screenputc(int c)
{
	Fontchar *i;
	Point p;

	if(gscreen.base == nil)
		return;
	switch(c){
	case '\n':
		out.pos.x = MINX;
		out.pos.y += defont0.height;
		if(out.pos.y > gscreen.r.max.y-defont0.height)
			out.pos.y = gscreen.r.min.y;
		gbitblt(&gscreen, Pt(0, out.pos.y), &gscreen,
		  Rect(0, out.pos.y, gscreen.r.max.x, out.pos.y+2*defont0.height),
		  Zero);
		break;
	case '\t':
		out.pos.x += (8-((out.pos.x-MINX)/out.bwid&7))*out.bwid;
		if(out.pos.x >= gscreen.r.max.x)
			screenputc('\n');
		break;
	case '\b':
		if(out.pos.x >= out.bwid+MINX){
			out.pos.x -= out.bwid;
			screenputc(' ');
			out.pos.x -= out.bwid;
		}
		break;
	default:
		if(out.pos.x >= gscreen.r.max.x-out.bwid)
			screenputc('\n');
		c &= 0x7f;
		if(c <= 0 || c >= defont0.n)
			break;
		i = defont0.info + c;
		p = out.pos;
		gbitblt(&gscreen, Pt(p.x+i->left, p.y), defont0.bits,
			Rect(i[0].x, 0, i[1].x, defont0.height),
			S);
		out.pos.x = p.x + i->width;
		break;
	}
}

void
screenputs(char *s, int n)
{
	while(n-- > 0)
		screenputc(*s++);
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
	
/*
 * support for the Sharp LQ64D341 TFT colour display
 */

enum {
	COLS = 640,
	ROWS = 480,
	LDEPTH = 3,	/* screen depth */
	LCDFREQ = 25000000,

	/* lccr */
	ClockLow = 1<<11,
	OELow = 1<<10,
	HsyncLow = 1<<9,
	VsyncLow = 1<<8,
	DataLow = 1<<7,
	Passive8 = 1<<4,
	DualScan = 1<<3,
	IsColour = 1<<2,
	IsTFT = 1<<1,
	Enable = 1<<0,

	/* lchcr */
	BigEndian = 1<<24,
	AT7 = 7<<21,	/* access type */

	/* sdcr */
	LAM = 1<<6,	/* ``LCD aggressive mode'' */
};

/*
 * TO DO: most of the data could come from a table
 */
static void
lcdinit(Mode *mode)
{
	IMM *io;
	int i, d;
	long hz;

	io = m->iomem;
	mode->y = ROWS;
	mode->x = COLS;
	mode->d = LDEPTH;
	mode->aperture = ialloc(mode->x*mode->y, 16);
	mode->apsize = mode->x*mode->y;

	io->sdcr &= ~LAM;	/* MPC823 errata: turn off LAM before disabling controller */
	io->lcfaa = PADDR(mode->aperture);
	io->lccr = (((mode->x*mode->y*(1<<LDEPTH)+127)/128) << 17) | (LDEPTH << 5) | IsColour | IsTFT | OELow | VsyncLow | ClockLow;

	switch(LDEPTH){
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

	io->lcvcr = (mode->y << 11) | (1<<28) | 33;	/* 2 line vsync pulse, 34 line wait between frames */
	io->lchcr = (mode->x<<10) | BigEndian | 228;	/* clock cycles between lines */

	hz = m->cpuhz;
	d = hz/LCDFREQ;
	if(hz/d > LCDFREQ)
		d++;
	if(d >= 16)
		d = 16;

	/*
	 * enable LCD outputs
	 */
	io->pddat = 0;
	io->pdpar = 0x1fff;
io->pdpar &= ~SIBIT(6);	/* 823 bug fix? */
	io->pddir = 0x1fff;
	io->pbpar |= IBIT(31) | IBIT(19) | IBIT(17);
	io->pbdir |= IBIT(31) | IBIT(19) | IBIT(17);
	io->pbodr &= ~(IBIT(31) | IBIT(19) | IBIT(17));

	eieio();
	io->sccrk = KEEP_ALIVE_KEY;
	eieio();
	io->sccr  = (io->sccr & ~0x1F) | lcdclock[d];
	eieio();
	io->sccrk = ~KEEP_ALIVE_KEY;
	eieio();
	gscreen.width = gscreen.width;	/* access external memory before enabling (mpc823 errata) */
	io->lcsr = 7;	/* clear status */
	eieio();
	io->lccr |= Enable;
	archbacklight(1);
}

int
setcolor(ulong p, ulong r, ulong g, ulong b)
{
	r >>= 28;
	g >>= 28;
	b >>= 28;
	m->iomem->lcdmap[~p&0xFF] = (r<<8) | (g<<4) | b;	/* TO DO: it's a function of the ldepth */
	return 1;
}
