#include	"u.h"
#include 	"mem.h"
#include	"../port/lib.h"
#include 	"dat.h"
#include 	"draw.h"
#include	"fns.h"
#include	"io.h"
#include	<memdraw.h>
#include	"screen.h"

#define	DPRINT	if(1)iprint

enum {
	/* lccr0 */
	EnableCtlr = 1<<0,	/* controller enable */
	IsColour = 0<<1,
	IsMono = 1<<1,
	SinglePanel = 0<<2,
	DualPanel = 1<<2,
	DisableDone = 1<<3,
	DisableBAU = 1<<4,
	DisableErr = 1<<5,
	PassivePanel = 0<<7,
	ActivePanel = 1<<7,
	BigEndian = 1<<8,
	DoublePixel = 1<<9,
	/* 19:12 is palette dma delay */

	/* lcsr */
	CtlrReady = 1<<0,

	/* lccr3 */
	VsyncLow = 1<<20,
	HsyncLow = 1<<21,
	PixelClockLow = 1<<22,
	OELow = 1<<23,
};

typedef struct {
	Vdisplay;
	LCDparam;
	ushort*	palette;
	uchar*	upper;
	uchar*	lower;
} LCDdisplay;

static LCDdisplay	*vd;	// current active display

void
lcd_setcolor(ulong p, ulong r, ulong g, ulong b)
{
	if(vd->pbs == 0 && p > 15 ||
	   vd->pbs == 1 && p > 255 ||
	   vd->pbs == 2)
		return;
	vd->palette[p] = (vd->pbs<<12) |
			((r>>(32-4))<<8) |
			((g>>(32-4))<<4) |
			(b>>(32-4));
}

static void
disablelcd(void)
{
	LcdReg *lcd = LCDREG;
	int i;

	/* if LCD enabled, turn off and wait for current frame to end */
	if(lcd->lccr0 & EnableCtlr) {
		lcd->lccr0 &= ~EnableCtlr;
		for(i=0; i < 50 && !(lcd->lcsr & CtlrReady); i++)
			delay(5);
	}
}

static void
setlcdmode(LCDdisplay *vd)
{
	LCDmode *p;
	int ppf, pclk, clockdiv;
	ulong v, c;
	LcdReg *lcd = LCDREG;
	GpioReg *gpio = GPIOREG;

	p = (LCDmode*)&vd->Vmode;
	ppf = ((((p->x+p->sol_wait+p->eol_wait) *
		       (p->mono ? 1 : 3)) >> (3-p->mono)) +
			p->hsync_wid) *
		       (p->y/(p->dual+1)+p->vsync_hgt+
			p->sof_wait+p->eof_wait);
	pclk = ppf*p->hz;
	clockdiv = ((m->cpuhz/pclk) >> 1)-2;
	DPRINT(" oclockdiv=%d\n", clockdiv);
clockdiv=0x10;
	disablelcd();
	lcd->lccr0 = 0;	/* reset it */

	DPRINT("  pclk=%d clockdiv=%d\n", pclk, clockdiv);
	lcd->lccr3 =  (clockdiv << 0) |
		(p->acbias_lines << 8) |
		(p->lines_per_int << 16) |
		VsyncLow | HsyncLow;	/* vsync active low, hsync active low */
	lcd->lccr2 =  (((p->y/(p->dual+1))-1) << 0) |
		(p->vsync_hgt << 10) |
		(p->eof_wait << 16) |
		(p->sof_wait << 24);
	lcd->lccr1 =  ((p->x-16) << 0) |
		(p->hsync_wid << 10) |
		(p->eol_wait << 16) |
		(p->sol_wait << 24);

	// enable LCD controller, CODEC, and lower 4/8 data bits (for tft/dual)
	v = p->obits < 12? 0: p->obits < 16? 0x3c: 0x3fc;
	c = p->obits == 12? 0x3c0: 0;
	gpio->gafr |= v;
	gpio->gpdr |= v | c;
	gpio->gpcr = c;

	lcd->dbar1 = PADDR(vd->palette);
	if(vd->dual)
		lcd->dbar2 = PADDR(vd->lower);

	// Enable LCD
	lcd->lccr0 = EnableCtlr | (p->mono?IsMono:IsColour)
		| (p->palette_delay << 12)
		| (p->dual ? DualPanel : SinglePanel)
		| (p->active? ActivePanel: PassivePanel)
		| DisableDone | DisableBAU | DisableErr;

	// recalculate actual HZ
	pclk = (m->cpuhz/(clockdiv+2)) >> 1;
	p->hz = pclk/ppf;

	archlcdenable(1);
iprint("lccr0=%8.8lux lccr1=%8.8lux lccr2=%8.8lux lccr3=%8.8lux\n", lcd->lccr0, lcd->lccr1, lcd->lccr2, lcd->lccr3);
}
static LCDdisplay main_display;	/* TO DO: limits us to a single display */

Vdisplay*
lcd_init(LCDmode *p)
{
	int palsize;
	int fbsize;

	vd = &main_display;
	vd->Vmode = *p;
	vd->LCDparam = *p;
	DPRINT("%dx%dx%d: hz=%d\n", vd->x, vd->y, vd->depth, vd->hz); /* */

	palsize = vd->pbs==1? 256 : 16;
	fbsize = palsize*2+(((vd->x*vd->y) * vd->depth) >> 3);
	if((vd->palette = xspanalloc(fbsize+CACHELINESZ+512, CACHELINESZ, 0)) == nil)	/* at least 16-byte alignment */
		panic("no vidmem, no party...");
	vd->palette[0] = (vd->pbs<<12);
	vd->palette = minicached(vd->palette);
	vd->upper = (uchar*)(vd->palette + palsize);
	vd->bwid = (vd->x << vd->pbs) >> 1;
	vd->lower = vd->upper+((vd->bwid*vd->y) >> 1);
	vd->fb = vd->upper;
	DPRINT("  fbsize=%d p=%p u=%p l=%p\n", fbsize, vd->palette, vd->upper, vd->lower); /* */

	setlcdmode(vd);
	return vd;
}

void
lcd_flush(void)
{
	if(conf.useminicache)
		minidcflush();
	else
		dcflushall();	/* need more precise addresses */
}

void
blankscreen(int blank)
{
	if (blank) {
		disablelcd();
		archlcdenable(0);
	} else {
		archlcdenable(1);
		setlcdmode(&main_display);
	}
}
