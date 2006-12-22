#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"

#include "../port/netif.h"
#include "../mpc/etherif.h"
#include "../port/flashif.h"

#include	<draw.h>
#include	<memdraw.h>
#include	<cursor.h> 
#include	"screen.h"

#include	"archfads.h"

/*
 * board-specific support for the 8xxFADS (including 860/21 development system)
 */

enum {
	/* CS assignment on FADS boards */
	BOOTCS = 0,
	BCSRCS = 1,
	DRAM1 = 2,
	DRAM2 = 3,
	SDRAM = 4,

	/* sccr */
	RTSEL = IBIT(8),	/* =0, select main oscillator (OSCM); =1, select external crystal (EXTCLK) */
	RTDIV = IBIT(7),	/* =0, divide by 4; =1, divide by 512 */
	CRQEN = IBIT(9),	/* =1, switch to high frequency when CPM active */
	PRQEN = IBIT(10),	/* =1, switch to high frequency when interrupt pending */

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
	int mf;

	m->bcsr = KADDR(PHYSBCSR);
	m->bcsr[1] |= DisableRS232a | DisableIR | DisableEther | DisablePCMCIA | DisableRS232b;
	m->bcsr[1] &= ~(DisableDRAM|DisableFlash);
	m->bcsr[1] &= ~EnableSDRAM;
	m->bcsr[4] &= ~EnableVideoClock;
	m->bcsr[4] |= DisableVideoLamp;
	io = m->iomem;	/* run by reset code: no need to lock */
	if(1 || (io->sccr & RTDIV) != 0){
		/* oscillator frequency can't be determined independently: check a switch */
		if((m->bcsr[2]>>19)&(1<<2))
			m->clockgen = 5*MHz;
		else
			m->clockgen = 4*MHz;
	} else
		m->clockgen = 32768;
	m->oscclk = m->clockgen/MHz;	/* TO DO: 32k clock */
	io->plprcrk = KEEP_ALIVE_KEY;
	io->plprcr &= ~CSRC;	/* general system clock is DFNH */
	mf = (io->plprcr >> 20)+1;	/* use timing set by bootstrap */
	io->plprcrk = ~KEEP_ALIVE_KEY;
	io->sccrk = KEEP_ALIVE_KEY;
	io->sccr |= CRQEN | PRQEN;
	io->sccr |= RTSEL;	/* select EXTCLK */
	io->sccrk = ~KEEP_ALIVE_KEY;
	m->cpuhz = m->clockgen*mf;
	m->speed = m->cpuhz/MHz;
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
	conf.nocts2 = 1;	/* not connected on the FADS board */

	conf.npage0 = 0;
	if((m->bcsr[1] & DisableDRAM) == 0){
		nbytes = banksize(DRAM1, &pa);
		if(nbytes){
			conf.npage0 = nbytes/BY2PG;
			conf.base0 = pa;
		}
	}

	conf.npage1 = 0;
	if(m->bcsr[1] & EnableSDRAM){
		nbytes = banksize(SDRAM, &pa);
		if(nbytes){
			conf.npage1 = nbytes/BY2PG;
			conf.base1 = pa;
		}
	}

	/* the following assumes the kernel text and/or data is in bank 0 */
	ktop = PGROUND((ulong)end);
	ktop = PADDR(ktop) - conf.base0;
	conf.npage0 -= ktop/BY2PG;
	conf.base0 += ktop;
}

static void
archidprint(void)
{
	int f, i;
	ulong v;

	/* 8xx and FADS specific */
	print("IMMR: ");
	v = getimmr() & 0xFFFF;
	switch(v>>8){
	case 0x00:	print("MPC860/821"); break;
	case 0x20:	print("MPC823"); break;
	case 0x21:	print("MPC823A"); break;
	default:	print("Type #%lux", v>>8); break;
	}
	print(", mask #%lux\n", v&0xFF);
	v = m->bcsr[3]>>16;
	print("MPC8xxFADS rev %lud, DB: ", ((v>>4)&8)|((v>>1)&4)|(v&3));
	f = (v>>8)&0x3F;
	switch(f){
	default:	print("ID#%x", f); break;
	case 0x00:	print("MPC860/821"); break;
	case 0x01:	print("MPC813"); break;
	case 0x02:	print("MPC821"); break;
	case 0x03:	print("MPC823"); break;
	case 0x20:	print("MPC801"); break;
	case 0x21:	print("MPC850"); break;
	case 0x22:	print("MPC860"); break;
	case 0x23:	print("MPC860SAR"); break;
	case 0x24:	print("MPC860T"); break;
	}
	print("ADS, rev #%lux\n", (m->bcsr[2]>>16)&7);
	for(i=0; i<=4; i++)
		print("BCSR%d: %8.8lux\n", i, m->bcsr[i]);
	v = m->bcsr[2];
	f = (v>>28)&0xF;
	switch(f){
	default:	print("Unknown"); break;
	case 4:	print("SM732A2000/SM73228 - 8M SIMM"); break;
	case 5:	print("SM732A1000A/SM73218 - 4M SIMM"); break;
	case 6:	print("MCM29080 - 8M SIMM"); break;
	case 7:	print("MCM29040 - 4M SIMM"); break;
	case 8:	print("MCM29020 - 2M SIMM"); break;
	}
	switch((m->bcsr[3]>>20)&7){
	default:	i = 0; break;
	case 1:	i = 150; break;
	case 2:	i = 120; break;
	case 3:	i = 90; break;
	}
	print(" flash, %dns\n", i);
	f = (v>>23)&0xF;
	switch(f&3){
	case 0:	i = 4; break;
	case 1:	i = 32; break;
	case 2:	i = 16; break;
	case 3:	i = 8; break;
	}
	print("%dM SIMM, ", i);
	switch(f>>2){
	default: 	i = 0; break;
	case 2:	i = 70; break;
	case 3:	i = 60; break;
	}
	print("%dns\n", i);
	print("options: #%lux\n", (m->bcsr[2]>>19)&0xF);
	print("plprcr=%8.8lux sccr=%8.8lux\n", m->iomem->plprcr, m->iomem->sccr);
}

void
cpuidprint(void)
{
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
	archidprint();
	print("%lud MHz system\n", m->cpuhz/MHz);
	print("\n");
}

/*
 * provide value for #r/switch (devrtc.c)
 */
int
archoptionsw(void)
{
	return (m->bcsr[2]>>19)&0xF;	/* value of switch DS1 */
}

/*
 * invoked by clock.c:/^clockintr
 */
static void
twinkle(void)
{
	if(m->ticks%MS2TK(1000) == 0)
		m->bcsr[4] ^= DisableLamp;
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
	char *t;
	int mbyte;

	if(bank != 0)
		return -1;
	switch((m->bcsr[2]>>28)&0xF){
	default:	return -1;	/* unknown or not there */
	case 4:	mbyte=8; t = "SM732x8"; break;
	case 5:	mbyte=4; t = "SM732x8"; break;
	case 6:	mbyte=8; t = "AMD29F0x0"; break;
	case 7:	mbyte=4; t = "AMD29F0x0"; break;
	case 8:	mbyte=2; t = "AMD29F0x0"; break;
	}
	f->type = t;
	f->addr = KADDR(PHYSFLASH);
	f->size = mbyte*1024*1024;
	f->width = 4;
	f->interleave = 3;
	return 0;
}

void
archflashwp(Flash*, int)
{
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

	USED(mbps, fullduplex);	/* TO DO */
	switch(cpmid){
	default:
		/* no other SCCs are wired on the FADS board */
		return -1;

	case CPscc2:	/* assume 8xxFADS board with 823DABS */
		io = ioplock();
		m->bcsr[1] |= DisableIR|DisableRS232b;
		m->bcsr[1] &= ~DisableEther;
		io->papar |= SIBIT(6)|SIBIT(5);	/* enable CLK2 and CLK3 */
		io->padir &= ~(SIBIT(6)|SIBIT(5));
		/* ETHLOOP etc reset in BCSR elsewhere */
		iopunlock();
		*rcs = CLK2;
		*tcs = CLK3;
		break;

	case CPscc1:	/* assume 860/21 development board */
		io = ioplock();
		m->bcsr[1] |= DisableIR|DisableRS232b;	/* TO DO: might not be shared with RS232b */
		m->bcsr[1] &= ~DisableEther;
		io->papar |= SIBIT(6)|SIBIT(7);	/* enable CLK2 and CLK1 */
		io->padir &= ~(SIBIT(6)|SIBIT(7));

		/* settings peculiar to 860/821 development board */
		io->pcpar &= ~(SIBIT(4)|SIBIT(5)|SIBIT(6));	/* ETHLOOP, TPFULDL~, TPSQEL~ */
		io->pcdir |= SIBIT(4)|SIBIT(5)|SIBIT(6);
		io->pcdat &= ~SIBIT(4);
		io->pcdat |= SIBIT(5)|SIBIT(6);
		iopunlock();
		*rcs = CLK2;
		*tcs = CLK1;
		break;
	}
	return 0;
}

/*
 * do anything extra required to enable the UART on the given CPM port
 */
void
archenableuart(int id, int irda)
{
	switch(id){
	case CPsmc1:
		m->bcsr[1] &= ~DisableRS232a;
		break;
	case CPscc2:
		m->bcsr[1] |= DisableEther|DisableIR|DisableRS232b;
		if(irda)
			m->bcsr[1] &= ~DisableIR;
		else
			m->bcsr[1] &= ~DisableRS232b;
		break;
	default:
		/* nothing special */
		break;
	}
}

/*
 * do anything extra required to disable the UART on the given CPM port
 */
void
archdisableuart(int id)
{
	switch(id){
	case CPsmc1:
		m->bcsr[1] |= DisableRS232a;
		break;
	case CPscc2:
		m->bcsr[1] |= DisableIR|DisableRS232b;
		break;
	default:
		/* nothing special */
		break;
	}
}

/*
 * enable the external USB transceiver
 *	speed is 12MHz if highspeed is non-zero; 1.5MHz if zero
 *	master is non-zero if the node is acting as USB Host and should provide power
 */
void
archenableusb(int highspeed, int master)
{
	if(highspeed)
		m->bcsr[4] |= USBFullSpeed;
	else
		m->bcsr[4] &= ~USBFullSpeed;
	if(master)
		m->bcsr[4] &= ~DisableUSBVcc;
	else
		m->bcsr[4] |= DisableUSBVcc;
	eieio();
	m->bcsr[4] &= ~DisableUSB;
}

/*
 * shut down the USB transceiver
 */
void
archdisableusb(void)
{
	m->bcsr[4] |= DisableUSBVcc | DisableUSB;
}

/*
 * set the external infrared transceiver to the given speed
 */
void
archsetirxcvr(int highspeed)
{
	if(!highspeed){
		/* force low edge after enable to put TFDS6000 xcvr in low-speed mode (see 4.9.2.1 in FADS manual) */
		m->bcsr[1] |= DisableIR;
		microdelay(2);
	}
	m->bcsr[1] &= ~DisableIR;
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
	m->iomem->padat &= ~SIBIT(4);	/* drop backlight */
	eieio();
	io->sdcr = 1;
	eieio();
	io->lccr = 0;
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
	m->bcsr[1] = (m->bcsr[1] | PCCVPPHiZ) & ~PCCVPP5V;
	m->bcsr[1] |= PCCVCC0V;
	m->bcsr[1] &= ~DisablePCMCIA;
	m->bcsr[1] &= ~PCCVCC5V;	/* apply Vcc */
	iopunlock();
}

int
pcmpowered(int)
{
	ulong r;

	r = ~m->bcsr[1]&PCCVCCMask;	/* active low */
	if(r == PCCVCC5V)
		return 5;
	if(r == PCCVCC3V)
		return 3;
	return 0;
}

void
pcmsetvcc(int, int v)
{
	if(v == 5)
		v = PCCVCC5V;
	else if(v == 3)
		v = PCCVCC3V;
	else
		v = 0;
	ioplock();
	m->bcsr[1] = (m->bcsr[1] | PCCVCCMask) & ~v;	/* active low */
	iopunlock();
}

void
pcmsetvpp(int, int v)
{
	if(v == 5)
		v = PCCVPP5V;
	else if(v == 12)
		v = PCCVPP12V;
	else if(v == 0)
		v = PCCVPP0V;
	else
		v = 0;	/* Hi-Z */
	ioplock();
	m->bcsr[1] = (m->bcsr[1] | PCCVPPHiZ) & ~v;	/* active low */
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
 * enable/disable the LCD panel's backlight via
 * York touch panel interface (does no harm without it)
 */
void
archbacklight(int on)
{
	IMM *io;

	delay(2);
	io = ioplock();
	io->papar &= ~SIBIT(4);
	io->padir |= SIBIT(4);
	if(on)
		io->padat |= SIBIT(4);
	else
		io->padat &= ~SIBIT(4);
	iopunlock();
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
	m->lcd.vpw = 2;
	m->lcd.wbf = 34;
	m->lcd.wbl = 106;
	m->lcd.flags = IsColour | IsTFT | OELow | HsyncLow | VsyncLow;
	m->lcd.notpdpar = SIBIT(6);
	return 0;
}

/*
 * reset 823 video port for devvid.c
 */
void
archresetvideo(void)
{
	ioplock();
	m->bcsr[4] &= ~DisableVideoLamp;
	m->bcsr[4] |= EnableVideoPort;
	eieio();
	m->bcsr[4] &= ~EnableVideoPort;	/* falling edge to reset */
	iopunlock();
	delay(6);
	ioplock();
	m->bcsr[4] |= EnableVideoPort;
	iopunlock();
	delay(6);
}

/*
 * enable 823 video port and clock
 */
void
archenablevideo(void)
{
	ioplock();
	m->bcsr[4] |= EnableVideoClock|EnableVideoPort;	/* enable AFTER pdpar/pddir to avoid damage */
	iopunlock();
}

/*
 * disable 823 video port and clock
 */
void
archdisablevideo(void)
{
	ioplock();
	m->bcsr[4] &= ~(EnableVideoClock|EnableVideoPort);
	m->bcsr[4] |= DisableVideoLamp;
	iopunlock();
}

/*
 * allocate a frame buffer for the video, aligned on 16 byte boundary
 */
uchar*
archvideobuffer(long nbytes)
{
	/* we shall use the on-board SDRAM if the kernel hasn't grabbed it */
	if((m->bcsr[1] & EnableSDRAM) == 0){
		m->bcsr[1] |= EnableSDRAM;
		return KADDR(PHYSSDRAM);
	}
	return xspanalloc(nbytes, 16, 0);
}

/*
 * there isn't a hardware keyboard port
 */
void
archkbdinit(void)
{
}
