/*
 * Called from l.s in EPROM to set up a minimal working environment.
 * Since there is no DRAM yet, and therefore no stack, no function
 * calls may be made from sysinit0, and values can't be stored,
 * except to INTMEM.  Global values are accessed by offset from SB,
 * which has been set by l.s to point into EPROM.
 *
 * This is PowerPAQ-specific:
 *	- assumes 8mbytes
 *	- powerpaq CS assignment
 */

#include "u.h"
#include "lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"

#include "archpaq.h"

#define	MB	(1024*1024)

enum {
	DRAMSIZE = 8*MB,
	FLASHSIZE = 8*MB,

	UPMSIZE = 64,	/* memory controller instruction RAM */
	SPEED = 50,	/* maximum memory clock in MHz */

	/* mcr */
	WriteRAM = 0<<30,
	ReadRAM = 1<<30,
	ExecRAM = 2<<30,

	SelUPMA = 0<<23,
	SelUPMB = 1<<23,

	Once = 1<<8,
};

/*
 * mpc8bug uses the following for 60ns EDO DRAMs 32-50MHz
 */
static ulong upmb50[UPMSIZE] = {
	0x8FFFEC24,	0xFFFEC04,	0xCFFEC04,	0xFFEC04,       
	0xFFEC00,	0x37FFEC47,	0xFFFFFFFF,	0xFFFFFFFF,
	0x8FFFEC24,	0xFFFEC04,	0x8FFEC04,	0xFFEC0C,
	0x3FFEC00,	0xFFEC44,	0xFFCC08,	0xCFFCC44,
	0xFFEC0C,	0x3FFEC00,	0xFFEC44,	0xFFCC00,
	0x3FFFC847,	0x3FFFEC47,	0xFFFFFFFF,	0xFFFFFFFF,
	0x8FAFCC24,	0xFAFCC04,	0xCAFCC00,	0x11BFCC47,
	0xC0FFCC84,	0xFFFFFFFF,	0xFFFFFFFF,	0xFFFFFFFF,
	0x8FAFCC24,	0xFAFCC04,	0xCAFCC00,	0x3AFCC4C,
	0xCAFCC00,	0x3AFCC4C,	0xCAFCC00,	0x3AFCC4C,
	0xCAFCC00,	0x33BFCC4F,	0xFFFFFFFF,	0xFFFFFFFF,
	0xFFFFFFFF,	0xFFFFFFFF,	0xFFFFFFFF,	0xFFFFFFFF,
	0xC0FFCC84,	0xFFCC04,	0x7FFCC04,	0x3FFFCC06,
	0xFFFFCC85,	0xFFFFCC05,	0xFFFFCC05,	0xFFFFFFFF,
	0xFFFFFFFF,	0xFFFFFFFF,	0xFFFFFFFF,	0xFFFFFFFF,
	0x33FFCC07,	0xFFFFFFFF,	0xFFFFFFFF,	0xFFFFFFFF,
};

void
sysinit0(int inrom)
{
	ulong *upm;
	IMM *io;
	int i;

	io = (IMM*)INTMEM;		/* running before maps, no KADDR */

	/* system interface unit initialisation, FADS manual table 3-2, except as noted */
	io->siumcr = 0x01012440;
	io->sypcr = 0xFFFFFF88;
	io->tbscrk = KEEP_ALIVE_KEY;
	io->tbscr = 0xC3;	/* time base enabled */
	io->rtcsck = KEEP_ALIVE_KEY;
	io->rtcsc = 0xC1;	/* don't FRZ, real-time clock enabled */
	io->rtcsck = ~KEEP_ALIVE_KEY;
	io->piscrk = KEEP_ALIVE_KEY;
	io->piscr = 0x82;

	io->memc[BOOTCS].base = FLASHMEM | 1;
	io->memc[BOOTCS].option = ~(FLASHSIZE-1)|(1<<8)|(2<<4);	/* mask, BIH, 2 wait states */

	if(!inrom)
		return;	/* can't initialise DRAM controller from DRAM */

	/* could check DRAM speed here; assume 60ns */
	/* could probe DRAM for size here; assume DRAMSIZE */
	io->mptpr = 0x400;	/* powerpaq flash has 0x1000 */
	io->mbmr = (0xC0<<24) | 0xA21114;	/* 50MHz BRGCLK */
	upm = upmb50;
	for(i=0; i<UPMSIZE; i++){
		io->mdr = upm[i];
		io->mcr = WriteRAM | SelUPMB | i;
	}
	io->memc[DRAM1].option = ~(DRAMSIZE-1)|0x0800;	/* address mask, SAM=1 */
	io->memc[DRAM1].base = 0 | 0xC1;	/* base at 0, 32-bit port size, no parity, UPMB */
}
