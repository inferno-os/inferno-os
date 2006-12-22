/*
 * Manga Balance Plus
 */
#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	"io.h"

#include "../port/netif.h"
#include "etherif.h"
#include	"../port/flashif.h"

enum {
	/* GPIO assignment ... */

	Maxmac=	4,	/* number of MAC addresses taken from EEPROM */
};

static uchar	macaddrs[Maxmac][Eaddrlen] = {
[0] {0x00, 0x10, 0xa1, 0x00, 0x10, 0x01},
[1] {0x00, 0x11, 0x6E, 0x00, 0x4A, 0xD4},
[2] {0x00, 0x10, 0xa1, 0x00, 0x20, 0x01},	/* TO DO */
};

void
archreset(void)
{
	/* TO DO: set GPIO and other key registers? */
	GPIOREG->iopm |= (1<<GPIO_status_orange_o)|(1<<GPIO_status_green_o);
	GPIOREG->iopm &= ~(1<<GPIO_button_i);
	GPIOREG->iopd &= ~(1<<GPIO_status_orange_o);
	GPIOREG->iopd &= ~(1<<GPIO_status_green_o);
	GPIOREG->iopc |= 0x8888;
	m->cpuhz = 166000000;	/* system clock is 125 = 5*CLOCKFREQ */
	m->delayloop = m->cpuhz/1000;
/*
	uartdebuginit();
*/
}

void
ledset(int n)
{
	int s;

	s = splhi();
	if(n)
		GPIOREG->iopd |= 1<<GPIO_status_green_o;
	else
		GPIOREG->iopd &= ~(1<<GPIO_status_green_o);
	splx(s);
}

void
archconfinit(void)
{
	ulong *p;

	p = KADDR(PHYSMEMCR+0x30);
	conf.topofmem = (((p[0]>>22)<<16)|0xFFFF)+1;
//	w = PMGRREG->ppcr & 0x1f;
//	m->cpuhz = CLOCKFREQ*(27*2*2);
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
	GPIOREG->iopd |= 1<<GPIO_status_green_o;
	GPIOREG->iopd &= ~(1<<GPIO_status_orange_o);
//	mmuputctl(mmugetctl() & ~CpCaltivec);	/* restore bootstrap's vectors */
//	RESETREG->rsrr = 1;	/* software reset */
	for(;;)
		//spllo();
		splhi();
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
	ulong *p;
	int w;

	p = KADDR(PHYSMEMCR+0x10);
iprint("Flash %8.8lux %8.8lux %8.8lux\n", p[0], p[1], p[4]);
	w = p[4]&3;
	if(bank > 0 || w == 0)
		return -1;
	if(w == 3)
		w = 4;
	f->type = "cfi8";
	f->addr = (void*)FLASHMEM;
	f->size = 0;
	f->width = w;
	f->interleave = 0;
	return 0;
}

/*
 * set ether parameters: the contents should be derived from EEPROM or NVRAM
 */
int
archether(int ctlno, Ether *ether)
{
	ether->nopt = 0;
	ether->itype = IRQ;
	switch(ctlno){
	case 0:
		sprint(ether->type, "ks8695");
		ether->mem = PHYSWANDMA;
		ether->port = 0;
		ether->irq = IRQwmrps;
		break;
	case 1:
		sprint(ether->type, "ks8695");
		ether->mem = PHYSLANDMA;
		ether->port = 1;
		ether->irq = IRQlmrps;
		ether->maxmtu = ETHERMAXTU+4;	/* 802.1[pQ] tags */
		break;
	case 2:
		sprint(ether->type, "rtl8139");
		ether->mem = 0;
		ether->port = 0;
		ether->irq = -1;
		break;
	default:
		return -1;
	}
	memmove(ether->ea, macaddrs[ctlno], Eaddrlen);
	return 1;
}

/*
 * TO DO: extract some boot data from user area of flash
 */

void
eepromscan(void)
{
}
