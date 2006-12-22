/*
 * ipaq
 */
#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	"io.h"
#include	"draw.h"
#include	<memdraw.h>
#include	"screen.h"

#include "../port/netif.h"
#include "etherif.h"
#include	"../port/flashif.h"

#define	EGPIOADDR		0x49000000	/* physical and virtual address of write only register in CS5 space */

static ulong egpiocopy;

static void
egpiosc(ulong set, ulong clr)
{
	int s;

	s = splhi();
	egpiocopy = (egpiocopy & ~clr) | set;
	*(ulong*)EGPIOADDR = egpiocopy;
	splx(s);
}

void
archreset(void)
{
	GpioReg *g;
	PpcReg *p;

	g = GPIOREG;
	g->grer = 0;
	g->gfer = 0;
	g->gedr = g->gedr;
	g->gpcr = ~0;
	g->gpdr = GPIO_CLK_SET0_o | GPIO_CLK_SET1_o;	// | GPIO_LDD8_15_o;
	g->gafr |= GPIO_SYS_CLK_i;	// | GPIO_LDD8_15_o;
	p = PPCREG;
	p->ppdr |= PPC_TXD4 | PPC_SCLK | PPC_SFRM;	/* not sure about PPC_TXD4 here */
	p->ppsr &= ~(PPC_TXD4 | PPC_SCLK | PPC_SFRM);

	archuartpower(3, 1);	/* allow console to work sooner rather than later */
	L3init();
}

void
archpowerdown(void)
{
	PmgrReg *p = PMGRREG;

	p->pwer = GPIO_PWR_ON_i;	/* only power button for now, not RTC */
	p->pcfr = PCFR_opde;	/* stop 3.6MHz oscillator, and drive pcmcia and chip select low */
	p->pgsr = 0;	/* drive all outputs to zero in sleep */
	PPCREG->psdr = 0;	/* all peripheral pins as outputs during sleep */
}

void
archpowerup(void)
{
	GpioReg *g;
	int i;

	g = GPIOREG;
	g->gpdr |= GPIO_COM_RTS_o;	/* just in case it's off */
	g->gpsr = GPIO_COM_RTS_o;
	*(ulong*)EGPIOADDR = egpiocopy;
	for(i=0; i<50*1000; i++)
		;
	while((g->gplr & GPIO_PWR_ON_i) == 0)
		;	/* wait for it to come up */
}

void
archconfinit(void)
{
	int w;

	conf.topofmem = 0xC0000000+32*MB;
	w = PMGRREG->ppcr & 0x1f;
	m->cpuhz = CLOCKFREQ*(w*4+16);

	conf.useminicache = 1;
	conf.portrait = 1;	/* should take from param flash or allow dynamic change */
}

void
kbdinit(void)
{
	addclock0link(kbdclock, MS2HZ);
}

static LCDmode lcd320x240x16tft =
{
//	.x = 320, .y = 240, .depth = 16, .hz = 70,
//	.pbs = 2, .dual = 0, .mono = 0, .active = 1,
//	.hsync_wid = 4-2, .sol_wait = 12-1, .eol_wait = 17-1,
//	.vsync_hgt = 3-1, .soft_wait = 10, .eof_wait = 1,
//	.lines_per_int = 0, .palette_delay = 0, .acbias_lines = 0,
//	.obits = 16,
//	.vsynclow = 1, .hsynclow = 1,
	320, 240, 16, 70,
	2, 0, 0, 1,
	4-2, 12-1, 17-1,
	3-1, 10, 1,
	0, 0, 0,
	16,
	1, 1,
};

int
archlcdmode(LCDmode *m)
{
	*m = lcd320x240x16tft;
	return 0;
}

void
archlcdenable(int on)
{
	if(on)
		egpiosc(EGPIO_LCD_ON|EGPIO_LCD_PCI|EGPIO_LCD_5V_ON|EGPIO_LVDD_ON, 0);
	else
		egpiosc(0, EGPIO_LCD_ON|EGPIO_LCD_PCI|EGPIO_LCD_5V_ON|EGPIO_LVDD_ON);
}

void
archconsole(void)
{
	uartspecial(0, 115200, 'n', &kbdq, &printq, kbdcr2nl);
}

void
archuartpower(int port, int on)
{
	int s;

	if(port != 3)
		return;
	s = splhi();
	GPIOREG->gpdr |= GPIO_COM_RTS_o;	/* should be done elsewhere */
	GPIOREG->gpsr = GPIO_COM_RTS_o;
	splx(s);
	if(on)
		egpiosc(EGPIO_RS232_ON, 0);
	else
		egpiosc(0, EGPIO_RS232_ON);
}

void
archreboot(void)
{
	dcflushall();
	GPIOREG->gedr = 1<<0;
	mmuputctl(mmugetctl() & ~CpCaltivec);	/* restore bootstrap's vectors */
	RESETREG->rsrr = 1;	/* software reset */
	for(;;)
		spllo();
}

void
archflashwp(Flash*, int wp)
{
	if(wp)
		egpiosc(0, EGPIO_VPEN);
	else
		egpiosc(EGPIO_VPEN, 0);
}

/*
 * for ../port/devflash.c:/^flashreset
 * retrieve flash type, virtual base and length and return 0;
 * return -1 on error (no flash)
 */
int
archflashreset(int bank, Flash *f)
{
	if(bank != 0)
		return -1;
	f->type = "cfi16";
	f->addr = KADDR(FLASHMEM);
	if((MEMCFGREG->msc0 & (1<<2)) == 0){
		f->interleave = 1;
		f->width = 4;
	}else
		f->width = 2;
	return 0;
}

int
archaudiopower(int on)
{
	int s;

	if(on)
		egpiosc(EGPIO_CODEC_RESET | EGPIO_AUD_PWR_ON, 0);
	else
		egpiosc(0, EGPIO_CODEC_RESET | EGPIO_AUD_ON | EGPIO_AUD_PWR_ON | EGPIO_QMUTE);
	s = splhi();
	GPIOREG->gafr |= GPIO_SYS_CLK_i;
	GPIOREG->gpdr |= GPIO_CLK_SET0_o | GPIO_CLK_SET1_o;
	GPIOREG->gpsr = GPIO_CLK_SET0_o;
	GPIOREG->gpcr = GPIO_CLK_SET1_o;
	splx(s);
	return 0;
}

void
archcodecreset(void)
{
//	egpiosc(0, EGPIO_CODEC_RESET);
//	egpiosc(EGPIO_CODEC_RESET, 0);
}

void
archaudiomute(int on)
{
	if(on)
		egpiosc(EGPIO_QMUTE, 0);
	else
		egpiosc(0, EGPIO_QMUTE);
}

void
archaudioamp(int on)
{
	if(on)
		egpiosc(EGPIO_AUD_ON, 0);
	else
		egpiosc(0, EGPIO_AUD_ON);
}

enum {
	Fs512 = 0,
	Fs384 = 1,
	Fs256 = 2,

	MHz4_096 = GPIO_CLK_SET1_o,
	MHz5_6245 = GPIO_CLK_SET1_o|GPIO_CLK_SET0_o,
	MHz11_2896 = GPIO_CLK_SET0_o,
	MHz12_288 = 0
};

typedef struct Csel Csel;
struct Csel{
	int	speed;
	int	cfs;		/* codec system clock multiplier */
	int	gclk;		/* gpio clock generator setting */
	int	div;		/* ssp clock divisor */
};
static Csel csel[] = {
	{8000, Fs512, MHz4_096, 16},
	{11025, Fs512, MHz5_6245, 16},
	{16000, Fs256 , MHz4_096, 8},
	{22050, Fs512, MHz11_2896, 16},
	{32000, Fs384, MHz12_288, 12},
	{44100, Fs256, MHz11_2896, 8},
	{48000, Fs256, MHz12_288, 8},
	{0},
};

int
archaudiospeed(int clock, int set)
{
	GpioReg *g;
	SspReg *ssp;
	Csel *cs;
	int s, div, cr0;

	for(cs = csel; cs->speed > 0; cs++)
		if(cs->speed == clock){
			if(!set)
				return cs->cfs;
			div = cs->div;
			if(div == 0)
				div = 4;
			div = div/2 - 1;
			s = splhi();
			g = GPIOREG;
			g->gpsr = cs->gclk;
			g->gpcr = ~cs->gclk & (GPIO_CLK_SET0_o|GPIO_CLK_SET1_o);
			ssp = SSPREG;
			cr0 = (div<<8) | 0x1f;	/* 16 bits, TI frames, not enabled */
			ssp->sscr0 = cr0;
			ssp->sscr1 = 0x0020;	/* ext clock */
			ssp->sscr0 = cr0 | 0x80;	/* enable */
			splx(s);
			return cs->cfs;
		}
	return -1;
}

/*
 * pcmcia
 */
int
pcmpowered(int slotno)
{
	if(slotno)
		return 0;
	if(egpiocopy & EGPIO_OPT_PWR_ON)
		return 3;
	return 0;
}

void
pcmpower(int slotno, int on)
{
	USED(slotno);	/* the pack powers both or none */
	if(on){
		if((egpiocopy & EGPIO_OPT_PWR_ON) == 0){
			egpiosc(EGPIO_OPT_PWR_ON | EGPIO_OPT_ON, 0);
			delay(200);
		}
	}else
		egpiosc(0, EGPIO_OPT_PWR_ON | EGPIO_OPT_ON);
}

void
pcmreset(int slot)
{
	USED(slot);
	egpiosc(EGPIO_CARD_RESET, 0);
	delay(100);	// microdelay(10);
	egpiosc(0, EGPIO_CARD_RESET);
}

int
pcmpin(int slot, int type)
{
	switch(type){
	case PCMready:
		return slot==0? 21: 11;
	case PCMeject:
		return slot==0? 17: 10;
	case PCMstschng:
		return -1;
	}
}

void
pcmsetvpp(int slot, int vpp)
{
	USED(slot, vpp);
}

/*
 * set ether parameters: the contents should be derived from EEPROM or NVRAM
 */
int
archether(int ctlno, Ether *ether)
{
	static char opt[128];

	if(ctlno == 1){
		sprint(ether->type, "EC2T");
		return 1;
	}
	if(ctlno > 0)
		return -1;
	sprint(ether->type, "wavelan");
	if(0)
		strcpy(opt, "mode=0 essid=Limbo station=ipaq1 crypt=off");	/* peertopeer */
	else
		strcpy(opt, "mode=managed essid=Vitanuova1 station=ipaq1 crypt=off");
	ether->nopt = tokenize(opt, ether->opt, nelem(ether->opt));
	return 1;
}
