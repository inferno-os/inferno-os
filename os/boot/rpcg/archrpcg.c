#include	"u.h"
#include	"lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"

#include	"archrpcg.h"
#include "etherif.h"

/*
 * board-specific support for the RPCG RXLite
 */

enum {
	SYSMHZ =	66,	/* target frequency */

	/* sccr */
	RTSEL = IBIT(8),	/* =0, select main oscillator (OSCM); =1, select external crystal (EXTCLK) */
	RTDIV = IBIT(7),	/* =0, divide by 4; =1, divide by 512 */
	CRQEN = IBIT(9),	/* =1, switch to high frequency when CPM active */
	PRQEN = IBIT(10),	/* =1, switch to high frequency when interrupt pending */

	/* plprcr */
	CSRC = IBIT(21),	/* =0, clock is DFNH; =1, clock is DFNL */
};

static	char	flashsig[] = "RPXsignature=1.0\nNAME=qbrpcg\nSTART=FFC20100\nVERSION=1.1\n";
static	char*	geteeprom(char*);

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
	ulong v;

	v = getimmr() & 0xFFFF;
	switch(v>>8){
	case 0x00:	t = 0x86000; break;
	case 0x20:	t = 0x82300; break;
	case 0x21:	t = 0x823a0; break;
	default:	t = 0; break;
	}
	m->cputype = t;
	m->bcsr = KADDR(BCSRMEM);
	io = m->iomem;
	m->clockgen = 8*MHz;
	mf = (io->plprcr >> 20)+1;	/* use timing set by bootstrap */
	m->cpuhz = m->clockgen*mf;
	m->bcsr[0] = DisableColTest | DisableFullDplx | DisableUSB | HighSpdUSB | LedOff;	/* first write enables bcsr regs */
return;
	io->plprcrk = KEEP_ALIVE_KEY;
	io->plprcr &= ~CSRC;	/* general system clock is DFNH */
/*	io->mptpr = 0x0800;	/* memory prescaler = 8 for refresh */
	/* use memory refresh time set by RPXLite monitor */
	io->plprcrk = ~KEEP_ALIVE_KEY;
}

void
cpuidprint(void)
{
	int t, v;

	print("Inferno bootstrap\n");
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
	print("options: #%lux\n", archoptionsw());
	print("bcsr: %8.8lux\n", m->bcsr[0]);
	print("PLPRCR=%8.8lux SCCR=%8.8lux\n", m->iomem->plprcr, m->iomem->sccr);
	print("%lud MHz system\n", m->cpuhz/MHz);
	print("\n");
//print("%s\n", geteeprom("EA"));
print("BR0=%8.8lux OR0=%8.8lux\n", m->iomem->memc[0].base, m->iomem->memc[0].option);
print("MPTPR=%8.8lux\n", m->iomem->mptpr);
}

static	char*	defplan9ini[2] = {
	/* 860/821 */
	"ether0=type=SCC port=1 ea=0010ec000051\r\n"
	"vgasize=640x480x8\r\n"
	"kernelpercent=40\r\n"
	"console=0\r\nbaud=9600\r\n",

	/* 823 */
	"ether0=type=SCC port=2 ea=0010ec000051\r\n"
	"vgasize=640x480x8\r\n"
	"kernelpercent=40\r\n"
	"console=0\r\nbaud=9600\r\n",
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
 * for flash.c:/^flashreset
 * retrieve flash type, virtual base and length and return 0;
 * return -1 on error (no flash)
 */
int
archflashreset(char *type, void **addr, long *length)
{
	if((m->iomem->memc[BOOTCS].base & 1) == 0)
		return -1;		/* shouldn't happen */
	strcpy(type, "AMD29F0x0");
	*addr = KADDR(FLASHMEM);
	*length = 4*1024*1024;
	return 0;
}

int
archether(int ctlrno, Card *ether)
{
	char *ea;

	if(ctlrno > 0)
		return -1;
	strcpy(ether->type, "SCC");
	ether->port = 2;
	ea = geteeprom("EA");
	if(ea != nil)
		parseether(ether->ea, ea);
	return 1;
}

/*
 * enable the clocks for the given SCC ether and reveal them to the caller.
 * do anything else required to prepare the transceiver (eg, set full-duplex, reset loopback).
 */
int
archetherenable(int cpmid, int *rcs, int *tcs)
{
	IMM *io;

	switch(cpmid){
	default:
		/* no other SCCs are wired for ether on RPXLite*/
		return -1;

	case SCC2ID:
		io = ioplock();
		m->bcsr[0] |= EnableEnet;
		io->papar |= SIBIT(6)|SIBIT(4);	/* enable CLK2 and CLK4 */
		io->padir &= ~(SIBIT(6)|SIBIT(4));
		*rcs = CLK4;
		*tcs = CLK2;
		iopunlock();
		break;
	}
	return 0;
}

void
archetherdisable(int id)
{
	USED(id);
	m->bcsr[0] &= ~EnableEnet;
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
 * enable/disable the LCD panel's backlight
 */
void
archbacklight(int on)
{
	USED(on);
}

static char*
geteeprom(char *s)
{
	static int init;
	static char res[64];
	static uchar eeprom[257];
	uchar *l, *p;
	int i, j;

	if(!init){
		i2csetup();
		if(i2crecv(0xa8|1|(0<<8), eeprom, 128) < 0 ||
		   i2crecv(0xa8|1|(128<<8), eeprom+128, 128) < 0){
			print("i2c failed\n");
			return nil;
		}
		if(0){
			print("eeprom:\n");
			for(i=0; i<16; i++){for(j=0; j<16; j++)print(" %2.2ux[%c]", eeprom[i*16+j], eeprom[i*16+j]); print("\n");}
		}
		eeprom[256] = 0xFF;
		init = 1;
	}
	for(l = eeprom; *l != 0xFF && *l != '\n';){
		p = l;
		while(*l != '\n' && *l != 0xFF && *l != '=')
			l++;
		if(*l == '='){
			if(l-p == strlen(s) && strncmp(s, (char*)p, strlen(s)) == 0){
				p = l+1;
				while(*l != '\n' && *l != 0xFF)
					l++;
				memmove(res, p, l-p);
				res[l-p] = 0;
				return res;
			}
		}
		while(*l != '\n' && *l != 0xFF)
			l++;
		if(*l == '\n')
			l++;
	}
	return nil;
}
