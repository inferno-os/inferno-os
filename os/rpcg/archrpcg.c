#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"

#include	<draw.h>
#include	<memdraw.h>
#include	<cursor.h> 
#include	"screen.h"

#include "../port/netif.h"
#include "../mpc/etherif.h"
#include "../port/flashif.h"
#include	"archrpcg.h"

/*
 * board-specific support for the 850/823 RPCG board
 */

enum {
	/* sccr */
	COM3=	IBIT(1)|IBIT(2),	/* clock output disabled */
	TBS =	IBIT(6),	/* =0, time base is OSCCLK/{4,16}; =1, time base is GCLK2/16 */
	RTSEL = IBIT(8),	/* =0, select main oscillator (OSCM); =1, select external crystal (EXTCLK) */
	RTDIV = IBIT(7),	/* =0, divide by 4; =1, divide by 512 */
	CRQEN = IBIT(9),	/* =1, switch to high frequency when CPM active */
	PRQEN = IBIT(10),	/* =1, switch to high frequency when interrupt pending */
	EDBF2 = IBIT(14),	/* =1, CLKOUT is GCLK2/2 */

	/* plprcr */
	CSRC = IBIT(21),	/* =0, clock is DFNH; =1, clock is DFNL */
};

/*
 * called early in main.c, after machinit:
 * using board and architecture specific registers, initialise
 * 8xx registers that need it and complete initialisation of the Mach structure.
 */
void
archinit(void)
{
	IMM *io;
	int mf, i;

	m->bcsr = KADDR(PHYSBCSR);
	m->bcsr[0] &= ~EnableEnet;
	io = m->iomem;	/* run by reset code: no need to lock */
	m->clockgen = 8000000;	/* crystal frequency */
	m->oscclk = m->clockgen/MHz;
	io->plprcrk = KEEP_ALIVE_KEY;
	io->plprcr &= ~CSRC;	/* general system clock is DFNH */
	mf = (io->plprcr >> 20)+1;	/* use timing set by bootstrap */
	m->cpuhz = m->clockgen*mf;
	m->speed = m->cpuhz/MHz;
	io->plprcrk = ~KEEP_ALIVE_KEY;
	io->sccrk = KEEP_ALIVE_KEY;
	io->sccr |= COM3 | TBS | CRQEN | PRQEN;
	io->sccrk = ~KEEP_ALIVE_KEY;
	if(0){
		/* reset PCMCIA in case monitor hasn't */
		io->pgcr[1] = 1<<7;	/* OP2 high to disable PCMCIA */
		io->per = 0;
		io->pscr = ~0;
		for(i=0; i<8; i++)
			io->pcmr[i].base = io->pcmr[i].option = 0;
	}
}

static ulong
banksize(int x, ulong *pa)
{
	IMM *io;

	io = m->iomem;
	if((io->memc[x].base & 1) == 0)
		return 0;	/* bank not valid */
	*pa = io->memc[x].base & ~0x7FFF;
	return -(io->memc[x].option&~0x7FFF);
}

/*
 * initialise the kernel's memory configuration:
 * there are two banks (base0, npage0) and (base1, npage1).
 * initialise any other values in conf that are board-specific.
 */
void
archconfinit(void)
{
	ulong nbytes, pa, ktop;

	conf.nscc = 2;
	conf.nocts2 = 1;	/* TO DO: check this */

	conf.npage0 = 0;
	nbytes = banksize(DRAM1CS, &pa);
	if(nbytes){
		conf.npage0 = nbytes/BY2PG;
		conf.base0 = pa;
	}

	conf.npage1 = 0;

	/* the following assumes the kernel text and/or data is in bank 0 */
	ktop = PGROUND((ulong)end);
	ktop = PADDR(ktop) - conf.base0;
	conf.npage0 -= ktop/BY2PG;
	conf.base0 += ktop;

	/* check for NVRAM */
	if(m->bcsr[0] & NVRAMBattGood){
		conf.nvramsize = banksize(NVRAMCS, &pa);
		conf.nvrambase = KADDR(pa);
	}
}

void
cpuidprint(void)
{
	ulong v;
	int i;

	print("PVR: ");
	switch(m->cputype){
	case 0x01:	print("MPC601"); break;
	case 0x03:	print("MPC603"); break;
	case 0x04:	print("MPC604"); break;
	case 0x06:	print("MPC603e"); break;
	case 0x07:	print("MPC603e-v7"); break;
	case 0x50:	print("MPC8xx"); break;
	default:	print("PowerPC version #%x", m->cputype); break;
	}
	print(", revision #%lux\n", getpvr()&0xffff);
	print("IMMR: ");
	v = getimmr() & 0xFFFF;
	switch(v>>8){
	case 0x00:	print("MPC860/821"); break;
	case 0x20:	print("MPC823"); break;
	case 0x21:	print("MPC823A"); break;
	default:	print("Type #%lux", v>>8); break;
	}
	print(", mask #%lux\n", v&0xFF);
	print("plprcr=%8.8lux sccr=%8.8lux bcsr=%8.8lux\n", m->iomem->plprcr, m->iomem->sccr, m->bcsr[0]);
	print("%lud MHz system\n", m->cpuhz/MHz);
	print("%lud pages\n", (conf.npage0-conf.base0)/BY2PG);
	print("%ludK NVRAM\n", conf.nvramsize/1024);
	print("\n");
	for(i=0; i<nelem(m->iomem->pcmr); i++)
		print("%d: %8.8lux %8.8lux\n", i, m->iomem->memc[i].base, m->iomem->memc[i].option);
}

/*
 * provide value for #r/switch (devrtc.c)
 */
int
archoptionsw(void)
{
	return (m->bcsr[0]&DipSwitchMask)>>4;
}

/*
 * invoked by clock.c:/^clockintr
 */
static void
twinkle(void)
{
	if(m->ticks%MS2TK(1000) == 0)
		m->bcsr[0] ^= LedOff;
}

void	(*archclocktick)(void) = twinkle;

/*
 * invoked by ../port/taslock.c:/^ilock:
 * reset watchdog timer here, if there is one and it is enabled
 * (qboot currently disables it on the FADS board)
 */
void
clockcheck(void)
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
	f->type = "AMD29F0x0";
//	f->type = "cfi16";
	f->addr = KADDR(PHYSFLASH);
	f->size = 4*1024*1024;
	f->width = 4;
	f->interleave = 1;
	return 0;
}

int
archether(int ctlrno, Ether *ether)
{
	if(isaconfig("ether", ctlrno, ether) == 0)
		return -1;
	return 1;
}

/*
 * enable the clocks for the given SCC ether and reveal them to the caller.
 * do anything else required to prepare the transceiver (eg, set full-duplex, reset loopback).
 */
int
archetherenable(int cpmid, int *rcs, int *tcs, int mbps, int fullduplex)
{
	IMM *io;

	if(cpmid != CPscc2)
		return -1;
	USED(mbps);
	USED(fullduplex);
	io = ioplock();
	m->bcsr[0] = (m->bcsr[0] & ~(EnableXcrLB|DisableColTest)) | EnableEnet;
	eieio();
	io->papar |= SIBIT(6)|SIBIT(4);	/* enable CLK2 and CLK4 */
	io->padir &= ~(SIBIT(6)|SIBIT(4));
	iopunlock();
	*rcs = CLK4;
	*tcs = CLK2;
	return 0;
}

/*
 * do anything extra required to enable the UART on the given CPM port
 */
void
archenableuart(int id, int irda)
{
	USED(id, irda);
}

/*
 * do anything extra required to disable the UART on the given CPM port
 */
void
archdisableuart(int id)
{
	USED(id);
}

/*
 * enable the external USB transceiver
 *	speed is 12MHz if highspeed is non-zero; 1.5MHz if zero
 *	master is non-zero if the node is acting as USB Host and should provide power
 */
void
archenableusb(int highspeed, int master)
{
	ioplock();
	if(master)
		m->bcsr[0] |= EnableUSBPwr;
	else
		m->bcsr[0] &= ~EnableUSBPwr;
	m->bcsr[0] &= ~DisableUSB;
	if(highspeed)
		m->bcsr[0] |= HighSpdUSB;
	else
		m->bcsr[0] &= ~HighSpdUSB;
	iopunlock();
}

/*
 * shut down the USB transceiver
 */
void
archdisableusb(void)
{
	ioplock();
	m->bcsr[0] |= DisableUSB;
	m->bcsr[0] &= ~EnableUSBPwr;
	iopunlock();
}

/*
 * set the external infrared transceiver to the given speed
 */
void
archsetirxcvr(int highspeed)
{
	USED(highspeed);
}

/*
 * force hardware reset/reboot
 */
void
archreboot(void)
{
	IMM *io;

	io = m->iomem;
	io->plprcrk = KEEP_ALIVE_KEY;
	io->plprcr |= 1<<7;	/* checkstop reset enable */
	io->plprcrk = ~KEEP_ALIVE_KEY;
	eieio();
	io->sdcr = 1;
	eieio();
	io->lccr = 0;	/* switch LCD off */
	eieio();
	firmware(0);
}

/*
 * board-specific PCMCIA support: assumes slot B on 82xFADS
 */
int
pcmslotavail(int slotno)
{
	return slotno == 1;
}

void
pcmenable(void)
{
	ioplock();
	m->bcsr[0] = m->bcsr[0] & ~(VPPMask|VCCMask);	/* power off */
	eieio();
	m->bcsr[0] |= VCC5V | VPPVCC;	/* apply Vcc */
	eieio();
	m->iomem->pgcr[1] = 0;	/* OP2 low to enable PCMCIA */
	iopunlock();
iprint("B=%8.8lux\n", m->bcsr[0]);
}

int
pcmpowered(int)
{
	ulong r;

	r = m->bcsr[0]&VCCMask;
	if(r == VCC5V)
		return 5;
	if(r == VCC3V)
		return 3;
	return 0;
}

void
pcmsetvcc(int, int v)
{
	if(v == 5)
		v = VCC5V;
	else if(v == 3)
		v = VCC3V;
	else
		v = VCC0V;
	ioplock();
	m->bcsr[0] = (m->bcsr[0] & ~VCCMask) | v;
	iopunlock();
}

void
pcmsetvpp(int, int v)
{
	if(v == 5 || v == 3)
		v = VPPVCC;
	else if(v == 12)
		v = VPP12V;
	else if(v == 0)
		v = VPP0V;
	else
		v = VPPHiZ;
	ioplock();
	m->bcsr[0] = (m->bcsr[0] & ~VPPMask) | v;
	iopunlock();
}

void
pcmpower(int slotno, int on)
{
	if(!on){
		pcmsetvcc(slotno, 0);	/* turn off card power */
		pcmsetvpp(slotno, -1);	/* turn off programming voltage (Hi-Z) */
	}else
		pcmsetvcc(slotno, 5);
}

/*
 * enable/disable the LCD panel's backlight
 */
void
archbacklight(int on)
{
	USED(on);
}

/*
 * set parameters to describe the screen
 */
int
archlcdmode(Mode *m)
{
	m->x = 640;
	m->y = 480;
	m->d = 3;
	m->lcd.freq = 25000000;
	m->lcd.ac = 0;
	m->lcd.vpw = 1;
	m->lcd.wbf = 33;
	m->lcd.wbl = 228;
	m->lcd.flags = IsColour | IsTFT | OELow | VsyncLow | ClockLow;
	return -1;	/* there isn't a screen */
}

/*
 * there isn't a keyboard port
 */
void
archkbdinit(void)
{
}

void
archflashwp(Flash*, int)
{
}
