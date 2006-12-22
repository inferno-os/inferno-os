/*
 * Intrinsyc Cerfboard 250
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
	/* Cerf250 GPIO assignment */
	GPIO_LED0_o = 4,	/* active high */
	GPIO_nCFD_i=	14,	/* compact flash detect, active low: falling edge */

	Maxmac=	4,	/* number of MAC addresses taken from EEPROM */
};

static uchar	macaddrs[Maxmac][Eaddrlen];

void
archreset(void)
{
	GpioReg *g = GPIOREG;

	g->grer[0] = 0;
	g->grer[1] = 0;
	g->grer[2] = 0;
	g->gfer[0] = 0;
	g->gfer[1] = 0;
	g->gfer[2] = 0;
	g->gedr[0] = g->gedr[0];
	g->gedr[1] = g->gedr[1];
	g->gedr[2] = g->gedr[2];

	g->gafr[2] |= GPAF(GPIO_FFRXD_1_i, 1);
	g->gafr[2] |= GPAF(GPIO_FFTXD_2_o, 2);
	g->gpdr[0] |= GPB(GPIO_LED0_o);
	g->gpdr[1] |= GPB(GPIO_FFTXD_2_o);
	g->gpsr[0] = GPB(GPIO_LED0_o);

	uartdebuginit();
}

void
ledset(int n)
{
	if(n)
		GPIOREG->gpsr[0] = GPB(GPIO_LED0_o);
	else
		GPIOREG->gpcr[0] = GPB(GPIO_LED0_o);
}

void
archconfinit(void)
{
	int w;

	conf.topofmem = PHYSMEM0+64*MB;
//	w = PMGRREG->ppcr & 0x1f;
	m->cpuhz = CLOCKFREQ*(27*2*2);
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
	ledset(1);
//	GPIOREG->gedr = 1<<0;
	mmuputctl(mmugetctl() & ~CpCaltivec);	/* restore bootstrap's vectors */
//	RESETREG->rsrr = 1;	/* software reset */
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
	f->width = 4;
	f->interleave = 1;
	return 0;
}

/*
 * set ether parameters: the contents should be derived from EEPROM or NVRAM
 */
int
archether(int ctlno, Ether *ether)
{
	if(ctlno > 0)
		return -1;
	sprint(ether->type, "91c111");
	ether->mem = PHYSCS1;
	ether->nopt = 0;
	ether->port = 0x300;	/* there isn't an ether EEPROM; use chip's default */
	ether->irq = 21;	 /* GPIO */
	ether->itype = GPIOrising;	/* active high */
//	gpioreserve(ether->irq);
//	gpioconfig(ether->irq, Gpio_gpio | Gpio_in);
	memmove(ether->ea, macaddrs[ctlno], Eaddrlen);
	return 1;
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
//	GPIOREG->gpsr = CFReset;
//	delay(100);
//	GPIOREG->gpcr = CFReset;
}

int
pcmpin(int slot, int type)
{
	if(slot)
		return -1;
	return -1;
//	switch(type){
//	case PCMready:
//		return CFRdypin;
//	case PCMeject:
//		return CFnCDxpin;
//	case PCMstschng:
//		return -1;
//	}
}

void
pcmsetvpp(int slot, int vpp)
{
	USED(slot, vpp);
}

/*
 * boot environment in eeprom
 */

enum {
	EEpromHdr=	8,	/* bytes */
	Envitemsize=	64,
	Ekeysize=	48,
};

static I2Cdev eedev;
static struct {
	uchar	buf[Envitemsize];
	int	size;
} bootenv;

static int
eepromitem(uchar *buf, int lim, ulong *off)
{
	int l;
	uchar b;

	if(i2crecv(&eedev, &b, 1, (*off)++) != 1)
		return -1;
	l = b;
	if(l & 0x80){
		if(i2crecv(&eedev, &b, 1, (*off)++) != 1)
			return -1;
		l = ((l & 0x7F)<<8) | b;
	}
	if(buf == nil)
		return l;
	if(l > lim)
		l = lim;
	return i2crecv(&eedev, buf, l, *off);
}

void
eepromscan(void)
{
	int n, l;
	ulong off;
	uchar buf[2];
	char *p;
	int mac;

	eedev.addr = 0x56;
	eedev.salen = 2;
	i2csetup(1);
	n = i2crecv(&eedev, buf, sizeof(buf), 0);
	if(n <= 0){
		iprint("eepromscan: %d\n", n);
		return;
	}
	if(buf[0] != 0xEF || buf[1] != 0xBE){
		iprint("eeprom invalid\n");
		return;
	}
	bootenv.size = 0;
	for(off = EEpromHdr; off < 16384;){
		l = eepromitem(bootenv.buf, sizeof(bootenv.buf), &off);	/* key */
		if(l <= 0)
			break;
		off += l;
		if(memcmp(bootenv.buf, "MACAD", 5) == 0){	/* only look for MAC addresses now */
			mac = bootenv.buf[5] - '0';
			if(mac >= 0 && mac < Maxmac){
				l = eepromitem(bootenv.buf, sizeof(bootenv.buf), &off);
				if(l < 0)
					break;
				if(l == Eaddrlen)
					memmove(macaddrs[mac], bootenv.buf, Eaddrlen);
				off += l+2;
				continue;
			}
		}
		l = eepromitem(nil, 0, &off);	/* skip value */
		if(l < 0)
			break;
		off += l+2;	/* 2 byte crc */
	}
}
