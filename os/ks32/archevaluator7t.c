#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"ureg.h"
#include	"../port/error.h"

extern int cflag;
extern int consoleprint;
extern int redirectconsole;
extern int main_pool_pcnt;
extern int heap_pool_pcnt;
extern int image_pool_pcnt;

void
archreset(void)
{
}

void
archconfinit(void)
{
	conf.topofmem = 512 * 1024;
	conf.flashbase = 0x01800000;
	conf.cpuspeed = 50000000;

	conf.useminicache = 1;
	conf.cansetbacklight = 0;
	conf.cansetcontrast = 0;
	conf.remaplo = 0;
}

void
archconsole(void)
{
	uartspecial(0, 57600, 'n', &kbdq, &printq, kbdcr2nl);
}

void
archreboot(void)
{
}

void
setleds(uchar val)
{
	ulong leds = IOPDATA;
	IOPDATA = (leds & ~0xf0) | ((val & 0xf) << 4);
}

static void
setled7(uchar val)
{
	ulong leds = IOPDATA;
	IOPDATA = (leds & ~(0x7f << 10)) | ((val & 0x7f) << 10);
}

#define LEDSEGA	0x01
#define LEDSEGB	0x02
#define LEDSEGC	0x04
#define LEDSEGD	0x08
#define LEDSEGE	0x10
#define LEDSEGG	0x20
#define LEDSEGF	0x40

static uchar led7map[] = {
[' '] 0,
['0']	LEDSEGA | LEDSEGB | LEDSEGC | LEDSEGD | LEDSEGE | LEDSEGF,
['1']	LEDSEGB | LEDSEGC,
['2']	LEDSEGA | LEDSEGB | LEDSEGD | LEDSEGE | LEDSEGG,
['3']	LEDSEGA | LEDSEGB | LEDSEGC | LEDSEGD | LEDSEGG,
['4']	LEDSEGB | LEDSEGC | LEDSEGF | LEDSEGG,
['5']	LEDSEGA | LEDSEGC | LEDSEGD | LEDSEGF | LEDSEGG,
['6']	LEDSEGA | LEDSEGC | LEDSEGD | LEDSEGE | LEDSEGF | LEDSEGG,
['7']	LEDSEGA |LEDSEGB | LEDSEGC,
['8']	LEDSEGA | LEDSEGB | LEDSEGC | LEDSEGD | LEDSEGE | LEDSEGF | LEDSEGG,
['9']	LEDSEGA | LEDSEGB | LEDSEGC | LEDSEGD | LEDSEGF | LEDSEGG,
['A']	LEDSEGA | LEDSEGB | LEDSEGC | LEDSEGE | LEDSEGF | LEDSEGG,
['B']	LEDSEGC | LEDSEGD | LEDSEGE | LEDSEGF | LEDSEGG,
['C']	LEDSEGA | LEDSEGD | LEDSEGE | LEDSEGF,
['D']	LEDSEGB | LEDSEGC | LEDSEGD | LEDSEGE | LEDSEGG,
['E']	LEDSEGA | LEDSEGD | LEDSEGE | LEDSEGF | LEDSEGG,
['F']	LEDSEGA | LEDSEGE | LEDSEGF | LEDSEGG,
['H']	LEDSEGC | LEDSEGE | LEDSEGF | LEDSEGG,
['P']	LEDSEGA | LEDSEGB | LEDSEGE | LEDSEGF | LEDSEGG,
['R']	LEDSEGE | LEDSEGG,
['S']	LEDSEGA | LEDSEGC | LEDSEGD | LEDSEGF | LEDSEGG,
['T']	LEDSEGD | LEDSEGE | LEDSEGF | LEDSEGG,
['U']	LEDSEGB | LEDSEGC | LEDSEGD | LEDSEGE | LEDSEGF,
['~']	LEDSEGB | LEDSEGE | LEDSEGG,
};

void
setled7ascii(char c)
{
	if (c <= '~')
		setled7(led7map[c]);
}

void
trace(char c)
{
	int i;
//	int x = splfhi();
	setled7ascii(c);
	for (i = 0; i < 2000000; i++)
		;
//	splx(x);
}

void
ttrace()
{
	static char c = '6';

	trace(c);
	c = '6' + '7' -c;
}

void
lights(ulong val)
{
	IOPDATA = (IOPDATA & (0x7ff << 4)) | ((val & 0x7ff) << 4);
}

void
lcd_setbacklight(int)
{
}

void
lcd_setbrightness(ushort)
{
}

void
lcd_setcontrast(ushort)
{
}

void
archflashwp(int /*wp*/)
{
}

void
screenputs(char *, int)
{
}

void
cursorenable(void)
{
}

void
cursordisable(void)
{
}
