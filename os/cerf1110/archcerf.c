/*
 * Intrinsyc Cerf cube
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

#include "../port/netif.h"
#include "etherif.h"
#include	"../port/flashif.h"

enum {
	/* Cerf GPIO assignment */
	LED0 = 1<<0,	/* active high */
	LED1 = 1<<1,
	LED2 = 1<<2,
	LED3 = 1<<3,
	/* 4 to 15 appear on J2 */
	CFBVD1 = 1<<20,
	CFBVD2 = 1<<19,
	CFReset = 1<<21,	/* active low for IDE mode; active high for IO or memory mode */
	CFRdypin = 22,
	CFRdy = 1<<CFRdypin,	/* RDY/nBSY */
	CFnCDxpin = 23,
	CFnCDx = 1<<CFnCDxpin,	/* low => card inserted */
	EnableRS232In = 1<<24,
	EnableRS232Out = 1<<25,
	/* CS8900 interrupt on 26, active high */
	/* CS8900 nHWSLEEP on 27 */
};

void
archreset(void)
{
	GpioReg *g = GPIOREG;

	g->grer = 0;
	g->gfer = 0;
	g->gedr = g->gedr;
	g->gpdr = 0;

	g->gpdr = EnableRS232In | EnableRS232Out | CFReset;
	g->gpsr = EnableRS232In | EnableRS232Out;

	GPCLKREG->gpclkr0 |= 1;	/* SUS=1 for uart on serial 1 */
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
archconsole(void)
{
	uartspecial(0, 38400, 'n', &kbdq, &printq, kbdcr2nl);
}

void
archuartpower(int, int)
{
}

void
kbdinit(void)
{
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
archflashwp(Flash*, int)
{
}

/*
 * for devflash.c:/^flashreset
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
	f->size = 0;
	f->width = 2;
	return 0;
}

/*
 * pcmcia
 */
int
pcmpowered(int slotno)
{
	if(slotno)
		return 0;
	return 3;
}

void
pcmpower(int slotno, int on)
{
	USED(slotno, on);
}

void
pcmreset(int slot)
{
	if(slot != 0)
		return;
	GPIOREG->gpsr = CFReset;
	delay(100);
	GPIOREG->gpcr = CFReset;
}

int
pcmpin(int slot, int type)
{
	if(slot)
		return -1;
	switch(type){
	case PCMready:
		return CFRdypin;
	case PCMeject:
		return CFnCDxpin;
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
	if(ctlno > 0)
		return -1;
	sprint(ether->type, "CS8900");
	ether->nopt = 0;
	ether->irq = 26;	 /* GPIO */
	ether->itype = BusGPIOrising;
	return 1;
}
