#include	"u.h"
#include	"lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"

#include	"archpaq.h"

/*
 * board-specific support for the 82x PowerPAQ
 */

enum {
	SYSMHZ = 50,	/* desired system clock in MHz */

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
	int mf, t;

	switch((getimmr()>>8)&0xFF){
	case 0x00:	t = 0x86000; break;	/* also 821 */
	case 0x20:	t = 0x82300; break;
	case 0x21:	t = 0x823a0; break;
	default:	t = 0; break;
	}
	m->cputype = t;
	m->bcsr = nil;	/* there isn't one */
	m->clockgen = 32*1024;	/* crystal frequency */
	io = m->iomem;
	io->sccrk = KEEP_ALIVE_KEY;
	io->sccr &= ~RTDIV;	/* divide 32k by 4 */
	io->sccr |= RTSEL;
	io->sccrk = ~KEEP_ALIVE_KEY;
	mf = (SYSMHZ*MHz)/m->clockgen;
	m->cpuhz = m->clockgen*mf;
	io->plprcrk = KEEP_ALIVE_KEY;
	io->plprcr &= ~IBIT(21);	/* general system clock is DFNH */
	io->plprcr = (io->plprcr & ((1<<20)-1)) | ((mf-1)<<20);
	io->mptpr = 0x0400;	/* memory prescaler = 16 for refresh */
	io->plprcrk = ~KEEP_ALIVE_KEY;
}

void
cpuidprint(void)
{
	int t, v;

	print("PVR: ");
	t = getpvr()>>16;
	switch(t){
	case 0x01:	print("MPC601"); break;
	case 0x03:	print("MPC603"); break;
	case 0x04:	print("MPC604"); break;
	case 0x06:	print("MPC603e"); break;
	case 0x07:	print("MPC603e-v7"); break;
	case 0x50:	print("MPC8xx"); break;
	default:	print("PowerPC version #%x", t); break;
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
	print("plprcr=%8.8lux sccr=%8.8lux\n", m->iomem->plprcr, m->iomem->sccr);
	print("%lud MHz system\n", m->cpuhz/MHz);
	print("\n");
}

static	char*	defplan9ini[2] = {
	/* 860/821 */
	"ether0=type=SCC port=1 ea=00108bf12900\r\n"
	"vgasize=640x480x8\r\n"
	"kernelpercent=40\r\n"
	"console=0 lcd\r\nbaud=19200\r\n",

	/* 823 */
	"ether0=type=SCC port=2 ea=00108bf12900\r\n"
	"vgasize=640x480x8\r\n"
	"kernelpercent=40\r\n"
	"console=0 lcd\r\nbaud=19200\r\n",
};

char *
archconfig(void)
{
	print("Using default configuration\n");
	return defplan9ini[MPCMODEL(m->cputype) == 0x823];
}

/*
 * provide value for #r/switch (devrtc.c)
 */
int
archoptionsw(void)
{
	return 0;
}

/*
 * invoked by clock.c:/^clockintr
 */
static void
twinkle(void)
{
	/* no easy-to-use LED on PAQ (they use i2c) */
}

void	(*archclocktick)(void) = twinkle;

/*
 * for flash.c:/^flashinit
 * retrieve flash type, virtual base and length and return 0;
 * return -1 on error (no flash)
 */
int
archflashreset(char *type, void **addr, long *length)
{
	strcpy(type, "AMD29F0x0");
	*addr = KADDR(FLASHMEM);
	*length = 8*1024*1024;	/* 8mbytes on some models */
	return 0;
}

/*
 * enable the clocks for the given SCC ether and reveal them to the caller.
 * do anything else required to prepare the transceiver (eg, set full-duplex, reset loopback).
 */
int
archetherenable(int cpmid, int *rcs, int *tcs)
{
	USED(cpmid, rcs, tcs);
	return -1;	/* there isn't an ether on the PAQs */
}

void
archetherdisable(int id)
{
	USED(id);
}

/*
 * do anything extra required to enable the UART on the given CPM port
 */
void
archenableuart(int id, int irda)
{
	IMM *io;

	USED(irda);
	switch(id){
	case SMC1ID:
		io = ioplock();
		io->pbodr &= ~0xc0;
		io->pbdat |= 0xc0;
		io->pcdat |= 0x400;
		io->pcpar &= ~0x400;
		io->pcdir |= 0x400;
		io->pcdat &= ~0x400;	/* enable SMC RS232 buffer */
		iopunlock();
		break;
	case SCC2ID:
		/* TO DO */
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
	case SMC1ID:
		/* TO DO */
		break;
	case SCC2ID:
		/* TO DO */
		break;
	default:
		/* nothing special */
		break;
	}
}

/*
 * enable/disable the LCD panel's backlight via i2c
 */
void
archbacklight(int on)
{
	uchar msg;
	IMM *io;

	i2csetup();
	msg = ~7;
	i2csend(LEDRegI2C, &msg, 1);
	io = ioplock();
	io->pbpar &= ~EnableLCD;
	io->pbodr &= ~EnableLCD;
	io->pbdir |= EnableLCD;
	if(on)
		io->pbdat |= EnableLCD;
	else
		io->pbdat &= ~EnableLCD;
	iopunlock();
	if(on){
		msg = ~(DisablePanelVCC5|DisableTFT);
		i2csend(PanelI2C, &msg, 1);
	}else{
		msg = ~0;
		i2csend(PanelI2C, &msg, 1);
	}
}
