/*
 * Called from l.s in EPROM to set up a minimal working environment.
 * Since there is no DRAM yet, and therefore no stack, no function
 * calls may be made from sysinit0, and values can't be stored,
 * except to INTMEM.  Global values are accessed by offset from SB,
 * which has been set by l.s to point into EPROM.
 *
 * This is FADS-specific in CS assignment and access of the FADS BCSR
 * to discover memory size and speed.
 */

#include "u.h"
#include "lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"

#include "archfads.h"

#define	MB	(1024*1024)

enum {
	UPMSIZE = 64,	/* memory controller instruction RAM */
	SPEED = 50,	/* maximum memory clock in MHz */
	SDRAMSIZE = 4*MB,

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
static ulong upma50[UPMSIZE] = {
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

/*
 * the FADS manual table 3-7 suggests the following for 60ns EDO DRAMs at 20MHz
 */
static ulong upma20[UPMSIZE] = {
	0x8FFFCC04, 0x08FFCC00, 0x33FFCC47, ~0, ~0, ~0, ~0, ~0,
	[0x08]	0x8FFFCC04, 0x08FFCC08, 0x08FFCC08, 0x08FFCC08, 0x08FFCC00, 0x3FFFCC47, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0,
	[0x18]	0x8FEFCC00, 0x39BFCC47, ~0, ~0, ~0, ~0, ~0, ~0,
	[0x20]	0x8FEFCC00, 0x09AFCC48, 0x09AFCC48, 0x08AFCC48, 0x39BFCC47, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0,
	[0x30]	0x80FFCC84, 0x17FFCC04, 0xFFFFCC86, 0xFFFFCC05, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0,
	[0x3C]	0x33FFCC07, ~0, ~0, ~0,
};

void
sysinit0(int inrom)
{
	ulong *upm, *bcsr;
	IMM *io;
	int i, mb;

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

	io->memc[BCSRCS].option = 0xFFFF8110;	/* 32k block, all types access, CS early negate, 1 ws */
	io->memc[BCSRCS].base = BCSRMEM | 1;	/* base, 32-bit port, no parity, GPCM */

	io->memc[BOOTCS].base = FLASHMEM | 1;
	io->memc[BOOTCS].option = 0xFF800D54;

	if(!inrom)
		return;	/* can't initialise DRAM controller from DRAM */

	bcsr = (ulong*)BCSRMEM;
//	bcsr[1] &= ~DisableDRAM;
	/* could check DRAM speed here; assume 60ns */
	switch((bcsr[2]>>23)&3){
	default:	return;	/* can't happen; for the compiler */
	case 0:	mb = 4; break;
	case 1:	mb = 32; break;
	case 2:	mb = 16; break;
	case 3:	mb = 8; break;
	}

	upm = upma50;
	for(i=0; i<UPMSIZE; i++){
		io->mdr = upm[i];
		io->mcr = WriteRAM | SelUPMA | i;
	}
	io->mptpr = 0x0400;
	if(SPEED >= 32)
		io->mamr = (0x9C<<24) | 0xA21114;	/* 50MHz BRGCLK; FADS manual says 0xC0, mpc8bug sets 0x9C */
	else if(SPEED >= 20)
		io->mamr = (0x60<<24) | 0xA21114;	/* 25MHz BRGCLK */
	else
		io->mamr = (0x40<<24) | 0xA21114;	/* 16.67MHz BRGCLK */
	io->memc[DRAM1].option = ~((mb<<20)-1)|0x0800;	/* address mask, SAM=1 */
	io->memc[DRAM1].base = 0 | 0x81;	/* base at 0, 32-bit port size, no parity, UPMA */
}

/*
 * the FADS manual table 3-9's suggestion for MB811171622A-100 32+MHz-50MHz
 */
static ulong upmb50[UPMSIZE] = {
	[0x00]	0x1F07FC04, 0xEEAEFC04, 0x11ADFC04, 0xEFBBBC00, 0x1FF77C47,
	[0x05]	0x1FF77C34, 0xEFEABC34, 0x1FB57C35,
	[0x08]	0x1F07FC04, 0xEEAEFC04, 0x10ADFC04, 0xF0AFFC00, 0xF0AFFC00, 0xF1AFFC00, 0xEFBBBC00, 0x1FF77C47, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0,
	[0x18]	0x1F27FC04, 0xEEAEBC00, 0x01B93C04, 0x1FF77C47, ~0, ~0, ~0, ~0,
	[0x20]	0x1F07FC04, 0xEEAEBC00, 0x10AD7C00, 0xF0AFFC00, 0xF0AFFC00, 0xE1BBBC04, 0x1FF77C47, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0,
	[0x30] 	0x1FF5FC84, 0xFFFFFC04, 0xFFFFFC04, 0xFFFFFC04, 0xFFFFFC84, 0xFFFFFC07, ~0, ~0, ~0, ~0, ~0, ~0,
	[0x3C]	0x7FFFFC07, ~0, ~0, ~0,
};

/*
 * the FADS manual table 3-8's suggestion for MB811171622A-100 up to 32MHz
 */
static	ulong	upmb32[UPMSIZE] = {
	[0x00]	0x126CC04, 0xFB98C00, 0x1FF74C45, ~0, ~0,
	[0x05]	0x1FE77C34, 0xEFAABC34, 0x1FA57C35,
	[0x08]	0x0026FC04, 0x10ADFC00, 0xF0AFFC00, 0xF1AFFC00, 0xEFBBBC00, 0x1FF77C45, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0,
	[0x18]	0x0E26BC04, 0x01B93C00, 0x1FF77C45, ~0, ~0, ~0, ~0, ~0,
	[0x20]	0x0E26BC00, 0x10AD7C00, 0xF0AFFC00, 0xF0AFFC00, 0xE1BBBC04, 0x1FF77C45, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0,
	[0x30]	0x1FF5FC84, 0xFFFFFC04, 0xFFFFFC84, 0xFFFFFC05, ~0, ~0, ~0, ~0, ~0, ~0, ~0, ~0,
	[0x3C]	0x7FFFFC07, ~0, ~0, ~0,
};

/*
 * optionally called by archfads.c:/^archinit to initialise access to SDRAM
 */
void
sdraminit(ulong base)
{
	ulong *upm;
	IMM *io;
	int i;

	io = (IMM*)INTMEM;		/* running before maps, no KADDR */
	if(SPEED > 32)
		upm = upmb50;
	else
		upm = upmb32;
	for(i=0; i<UPMSIZE; i++){
		io->mdr = upm[i];
		io->mcr = WriteRAM | SelUPMB | i;
	}
	io->memc[SDRAM].option = ~(SDRAMSIZE-1)|0x0A00;	/* address mask, SAM=1, G5LS=1 */
	io->memc[SDRAM].base = base | 0xC1;
	if(SPEED > 32){
		io->mbmr = 0xD0802114;	/* 50MHz BRGCLK */
		io->mar = 0x88;
	}else{
		io->mbmr = 0x80802114;	/* 32MHz BRGCLK */
		io->mar = 0x48;
	}
	io->mcr = ExecRAM | SelUPMB | (SDRAM<<13) | Once | 5;	/* run MRS command in locations 5-8 of UPMB */
	io->mbmr = (io->mbmr & ~0xF) | 8;
	io->mcr = ExecRAM | SelUPMB | (SDRAM<<13) | Once | 0x30;	/* run refresh sequence */
	io->mbmr = (io->mbmr & ~0xF) | 4;	/* 4-beat refresh bursts */
}
