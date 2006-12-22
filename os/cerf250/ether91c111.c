/*
 * SMsC 91c111 ethernet controller
 * Copyright © 2001,2004 Vita Nuova Holdings Limited.  All rights reserved.
 *
 * TO DO:
 *	- use ethermii
 *	- use DMA where available
 */

#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "../port/netif.h"

#include "etherif.h"

/*
 * chip definitions
 */

typedef struct Ctlr Ctlr;

enum {
	SMSC91C11x,
	SMSC91C110,
	SMSC91C111,
	SMSC91C96,
};

struct Ctlr {
	Lock;
	uchar	*base;
	int	type;
	int	rev;
	int	hasmii;
	int	phyad;
	int	bank;	/* currently selected bank */
	Block*	waiting;	/* waiting for space in FIFO */

	ulong	collisions;
	ulong	toolongs;
	ulong	tooshorts;
	ulong	aligns;
	ulong	txerrors;
	int	oddworks;
	int	bus32bit;
};

#define MKREG(bank, off)		((bank << 8) | (off))

enum {
	/* Bank 0 */
	Tcr=	MKREG(0, 0),	/* transmit control */
	  TcrSwfdup=	1<<15,	/* switched full duplex */
	  TcrEphLoop=	1<<13,	/* internal loopback */
	  TcrStpSqet=	1<<12,	/* stop transmission on SQET error */
	  TcrFduplx=	1<<11,	/* enable full duplex */
	  TcrMonCsn=	1<<10,	/* monitor collision (0 for MII operation) */
	  TcrNoCRC=	1<<8,	/* don't add CRC */
	  TcrPadEn=	1<<7,	/* pad short frames */
	  TcrForceCol=	1<<2,	/* force collision */
	  TcrLoop=	1<<1,	/* PHY loopback */
	  TcrTxena=	1<<0,	/* enable transmitter */
	Eph=	MKREG(0, 2),	/* there are more bits but we don't use them */
	  EphLinkOk=	1<<14,
	  EphCtrRol=	1<<12,	/* counter roll over; clear by reading Ecr */
	Rcr=	MKREG(0, 4),	/* receive control */
	  RcrSoftRst=	1<<15,
	  RcrFiltCar=	1<<14,
	  RcrAbortEnb=	1<<13,
	  RcrStripCRC=	1<<9,
	  RcrRxEn=	1<<8,
	  RcrAlmul=	1<<2,	/* ~=0, accept all multicast frames (=0, match multicast table) */
	  RcrPrms=	1<<1,	/* promiscuous mode */
	  RcrRxAbort=	1<<0,	/* set if receive frame longer than 2k bytes */
	Ecr=	MKREG(0, 6),	/* counter */
	  EcrExcDeferred=	0xF<<12,	/* excessively deferred Tx */
	  EcrDeferred=	0xF<<8,	/* deferred Tx */
	  EcrMultCol=	0xF<<4,	/* multiple collisions */
	  EcrCollision=	0xF<<0,	/* single collision */
	Mir=	MKREG(0, 8),	/* memory information */
	Mcr=	MKREG(0, 0xA),	/* memory config (91cxx) */
	Rpcr=	Mcr,	/* receive/phy control (91c111) */

	/* Bank 1 */
	Config=	MKREG(1, 0),
	  CfgMiiSelect=	1<<15,	/* 91c110 */
	  CfgEphPowerEn=	CfgMiiSelect,	/* =1, powered (after reset MMU); =0, low power mode (91c111) */
	  CfgNoWait=	1<<12,	/* don't request additional wait states */
	  CfgSetSqlch=	1<<9,	/* 91cxx */
	  CfgGpcntrl=	1<<9,	/* general purpose output (CNTRL), perhaps power-enable (91c111) */
	  CfgAuiSelect=	1<<8,	/* 91cxx */
	  CfgExtPhy=	1<<8,	/* enable external PHY/MII (91c111) */
	  Cfg16Bit=	1<<7,	/* 91cxx */
	BaseAddress=	MKREG(1, 2),
	Iaddr0_1=	MKREG(1, 4),
	Iaddr2_3=	MKREG(1, 6),
	Iaddr4_5=	MKREG(1, 8),
	Gpr=		MKREG(1, 0xA),	/* general purpose reg (EEPROM interface) */
	Control=	MKREG(1, 0xC),	/* control register */
	  CtlRcvBad=	1<<14,	/* allow bad CRC packets through */
	  CtlAutoRelease=	1<<11,	/* transmit pages released automatically w/out interrupt */
	  CtlLeEnable=	1<<7,	/* link error enable */
	  CtlCrEnable=	1<<6,	/* counter roll over enable */
	  CtlTeEnable=	1<<5,	/* transmit error enable */
	  CtlEeSelect=	1<<2,	/* EEPROM select */
	  CtlReload=	1<<1,	/* read EEPROM and update relevant registers */
	  CtlStore=	1<<0,	/* store relevant registers in EEPROM */

	/* Bank 2 */
	Mmucr=	MKREG(2, 0),	/* MMU command */
	  McrAllocTx=	1<<5,	/* allocate space for outgoing packet */
	  McrReset=	2<<5,	/* reset to initial state */
	  McrReadFIFO=	3<<5,	/* remove frame from top of FIFO */
	  McrRemove=	4<<5,	/* remove and release top of Rx FIFO */
	  McrFreeTx=	5<<5,	/* release specific packet (eg, packets done Tx) */
	  McrEnqueue=	6<<5,	/* enqueue packet number to Tx FIFO */
	  McrResetTx=	7<<5,	/* reset both Tx FIFOs */
	  McrBusy=	1<<0,
	ArrPnr=	MKREG(2, 2),	/* Pnr (low byte), Arr (high byte) */
	  ArrFailed=	1<<15,
	FifoPorts=	MKREG(2, 4),
	  FifoRxEmpty=	1<<15,
	  FifoTxEmpty=	1<<7,
	Pointer=	MKREG(2, 6),
	  PtrRcv=	1<<15,
	  PtrAutoIncr=	1<<14,
	  PtrRead=	1<<13,
	  PtrEtEn=	1<<12,
	  PtrNotEmpty=	1<<11,
	Data=	MKREG(2, 8),
	Interrupt=	MKREG(2, 0xC),	/* status/ack (low byte), mask (high byte) */
	  IntMii=	1<<7,	/* PHY/MII state change */
	  IntErcv=	1<<6,	/* early receive interrupt (received > Ercv threshold) */
	  IntEph=	1<<5,	/* ethernet protocol interrupt */
	  IntRxOvrn=	1<<4,	/* overrun */
	  IntAlloc=	1<<3,	/* allocation complete */
	  IntTxEmpty=	1<<2,	/* TX FIFO now empty */
	  IntTx=	1<<1,	/* transmit done */
	  IntRcv=	1<<0,	/* packet received */
	IntrMask=	MKREG(2, 0xD),
	  IntrMaskShift=	8,	/* shift for Int... values to mask position in 16-bit register */
	  IntrMaskField=	0xFF00,

	/* Bank 3 */
	Mt0_1=	MKREG(3, 0),	/* multicast table */
	Mt2_3=	MKREG(3, 2),
	Mt4_5=	MKREG(3, 4),
	Mt6_7=	MKREG(3, 6),
	Mgmt=	MKREG(3, 8),	/* management interface (MII) */
	  MgmtMdo=	1<<0,	/* MDO pin */
	  MgmtMdi=	1<<1,	/* MDI pin */
	  MgmtMclk=	1<<2,	/* drive MDCLK */
	  MgmtMdoEn=	1<<3,	/* MDO driven when high, tri-stated when low */
	Revision=		MKREG(3, 0xA),
	Ercv=	MKREG(3, 0xC),	/* early receive */

	/* Bank 4 (91cxx only) */
	EcsrEcor=	MKREG(4, 0),	/* status and option registers */

	/* all banks */
	BankSelect=	MKREG(0, 0xe),
};

enum {
	/* receive frame status word (p 38) */
	RsAlgnErr=	1<<15,
	RsBroadcast=	1<<14,
	RsBadCRC=	1<<13,
	RsOddFrame=	1<<12,
	RsTooLong=	1<<11,
	RsTooShort=	1<<10,
	RsMulticast=	1<<1,
	RsError=	RsBadCRC | RsAlgnErr | RsTooLong | RsTooShort,

	Framectlsize=	6,
};

static void miiw(Ctlr *ctlr, int regad, int val);
static int miir(Ctlr *ctlr, int regad);

/*
 * architecture dependent section - collected here in case
 * we want to port the driver
 */

#define PHYMIIADDR_91C110		3
#define PHYMIIADDR_91C111		0

#define llregr(ctlr, reg)	(*(ushort*)(ctlr->base + (reg)))
#define llregr32(ctlr, reg)	(*(ulong*)(ctlr->base + (reg)))
#define llregw(ctlr, reg, val)	(*(ushort*)(ctlr->base + (reg)) = (val))

static void
adinit(Ether *ether)
{
	Ctlr *ctlr;

	ctlr = ether->ctlr;
	// TODO: code to turn on device clocks
	ctlr->base = (uchar*)mmuphysmap(PHYSCS1, 0x100000) + ether->port;
iprint("adinit: %8.8lux -> %8.8lux mcs0=%8.8lux\n", (ulong)ctlr->base, PADDR(ctlr->base), MEMCFGREG->msc0);
{ulong v; v = *(ulong*)ctlr->base; iprint("value=%8.8lux\n", v);}
	ctlr->bus32bit = 1;
}

static void
adsetfd(Ctlr *ctlr)
{	
	miiw(ctlr, 0x18, miir(ctlr, 0x18) | (1 << 5));
}

/*
 * architecture independent section
 */

static ushort
regr(Ctlr *ctlr, int reg)
{
	int bank;
	ushort val;

	bank = reg >> 8;
	if(ctlr->bank != bank){
		ctlr->bank = bank;
		llregw(ctlr, BankSelect, bank);
	}
	val = llregr(ctlr, reg & 0xff);
	return val;
}

static ulong
regr32(Ctlr *ctlr, int reg)
{
	int bank;
	ulong val;

	bank = reg >> 8;
	if(ctlr->bank != bank){
		ctlr->bank = bank;
		llregw(ctlr, BankSelect, bank);
	}
	val = llregr32(ctlr, reg & 0xff);
	return val;
}

static void
regw(Ctlr *ctlr, int reg, ushort val)
{
	int bank;

	bank = reg >> 8;
	if(ctlr->bank != bank){
		ctlr->bank = bank;
		llregw(ctlr, BankSelect, bank);
	}
	llregw(ctlr, reg & 0xff, val);
}

static void
regwdatam(Ctlr *ctlr, ushort *data, int ns)
{
	int bank;
	ushort *faddr;

	bank = Data >> 8;
	if(ctlr->bank != bank){
		ctlr->bank = bank;
		llregw(ctlr, BankSelect, bank);
	}
	faddr = (ushort*)(ctlr->base + (Data & 0xff));
	while(ns-- > 0){
		*faddr = *data;
		data++;
	}
}

static void
regrdatam(Ctlr *ctlr, void *data, int nb)
{
	int bank;
	ushort *f, *t;
	int laps, ns;

	bank = Data >> 8;
	if(ctlr->bank != bank){
		ctlr->bank = bank;
		llregw(ctlr, BankSelect, bank);
	}

	if((ulong)data & 3)
		iprint("bad buffer alignment\n");

	t = data;
	f = (ushort*)(ctlr->base + (Data & 0xff));
	ns = nb >> 1;
	laps = ns / 8;	
	switch(ns & 7){	/* Duff's device */
	do {
		*t++ = *f;
	case 7: *t++ = *f;
	case 6: *t++ = *f;
	case 5: *t++ = *f;
	case 4: *t++ = *f;
	case 3: *t++ = *f;
	case 2: *t++ = *f;
	case 1: *t++ = *f;
	case 0:
		;
	} while(laps-- > 0);
	}
}

static void
regrdatam32(Ctlr *ctlr, void *data, int nb)
{
	int bank;
	ulong *f, *t;
	int laps, nw;

	bank = Data >> 8;
	if(ctlr->bank != bank){
		ctlr->bank = bank;
		llregw(ctlr, BankSelect, bank);
	}

	if((ulong)data & 3)
		iprint("bad buffer alignment\n");

	t = data;
	f = (ulong*)(ctlr->base + (Data & 0xff));
	nw = nb>>2;
	laps = nw / 8;	
	switch(nw & 7){	/* Duff's device */
	do {
		*t++ = *f;
	case 7: *t++ = *f;
	case 6: *t++ = *f;
	case 5: *t++ = *f;
	case 4: *t++ = *f;
	case 3: *t++ = *f;
	case 2: *t++ = *f;
	case 1: *t++ = *f;
	case 0:
		;
	} while(laps-- > 0);
	}
}

static void
regor(Ctlr *ctlr, int reg, ushort val)
{
	int bank;

	bank = reg >> 8;
	if(ctlr->bank != bank){
		ctlr->bank = bank;
		llregw(ctlr, BankSelect, bank);
	}
	reg &= 0xff;
	llregw(ctlr, reg, llregr(ctlr, reg) | val);
}

static void
regclear(Ctlr *ctlr, int reg, ushort val)
{
	int bank;

	bank = reg >> 8;
	if(ctlr->bank != bank){
		ctlr->bank = bank;
		llregw(ctlr, BankSelect, bank);
	}
	reg &= 0xff;
	llregw(ctlr, reg, llregr(ctlr, reg) & ~val);
}

static long
ifstat(Ether* ether, void* a, long n, ulong offset)
{
	Ctlr *ctlr;
	char *p;
	int len;

	if(n == 0)
		return 0;

	ctlr = ether->ctlr;
	p = smalloc(READSTR);
	if(waserror()){
		free(p);
		nexterror();
	}
	len = snprint(p, READSTR, "Overflow: %ud\n", ether->overflows);
	len += snprint(p+len, READSTR, "Soft Overflow: %ud\n", ether->soverflows);
	len += snprint(p+len, READSTR, "Transmit Error: %lud\n", ctlr->txerrors);
	len += snprint(p+len, READSTR-len, "CRC Error: %ud\n", ether->crcs);
	len += snprint(p+len, READSTR-len, "Collision: %lud\n", ctlr->collisions);
	len += snprint(p+len, READSTR-len, "Align: %lud\n", ctlr->aligns);
	len += snprint(p+len, READSTR-len, "Too Long: %lud\n", ctlr->toolongs);
	snprint(p+len, READSTR-len, "Too Short: %lud\n", ctlr->tooshorts);

	n = readstr(offset, a, n, p);
	poperror();
	free(p);

	return n;
}

static void
promiscuous(void* arg, int on)
{
	Ether *ether;
	Ctlr *ctlr;
	int r;

	ether = arg;
	ctlr = ether->ctlr;
	ilock(ctlr);
	r = regr(ctlr, Rcr);
	if(on)
		r |= RcrPrms;
	else
		r &= ~RcrPrms;
	regw(ctlr, Rcr, r);
	iunlock(ctlr);
}

static void
attach(Ether *ether)
{
	Ctlr *ctlr;

	ctlr = ether->ctlr;

	/*
	 * enable transmit and receive
	 */
	regw(ctlr, Interrupt, (IntMii | IntTx | IntRcv | IntRxOvrn)<<IntrMaskShift);
	regor(ctlr, Rcr, RcrRxEn);
	regor(ctlr, Tcr, TcrTxena);
}

static void
pointtotxpacket(Ctlr *ctlr, int pkt, int read)		 // read=PtrRead in failure case
{
	ushort junk;

	pkt &= 0x3F;
	regw(ctlr, ArrPnr, pkt);
	while(regr(ctlr, Pointer) & PtrNotEmpty)
		;
	regw(ctlr, Pointer, read | PtrAutoIncr);
	junk = llregr(ctlr, BankSelect);			/* possible wait state */
	USED(junk);
}

static void
pointtorxpacket(Ctlr *ctlr, int offset)
{
	ushort junk;

	regw(ctlr, Pointer, PtrRcv | PtrAutoIncr | PtrRead | offset);
	junk = llregr(ctlr, BankSelect);			/* possible wait state */
	USED(junk);
}

static void
mmucommand(Ctlr *ctlr, ushort cmd)
{
	while(regr(ctlr, Mmucr) & McrBusy)	// should signal free resource
		;
	regw(ctlr, Mmucr, cmd);	  // do the work
}

static void
txloadpacket(Ether *ether)
{
	Ctlr *ctlr;
	int pkt;
	Block *b;
	ushort lastw;
	int lenb, lenw;
	int odd;

	ctlr = ether->ctlr;
	b = ctlr->waiting;
	ctlr->waiting = nil;
	if(b == nil)
		return;	/* shouldn't happen */
	pkt = regr(ctlr, ArrPnr);		/* get packet number presumably just allocated */
	if(pkt & 0xC0){
		print("smc91c111: invalid packet number\n");
		freeb(b);
		return;
	}
	
	pointtotxpacket(ctlr, pkt, 0);

	lenb = BLEN(b);
	odd = lenb & 1;
	lenw = lenb >> 1;
	regw(ctlr, Data, 0);		// status word padding
	regw(ctlr, Data, (lenw << 1) + Framectlsize);
	regwdatam(ctlr, (ushort*)b->rp, lenw);	// put packet into 91cxxx memory
	lastw = 0x1000;
	if(odd){
		lastw |= 0x2000;	/* odd byte flag in control byte */
		lastw |= b->rp[lenb - 1];
	}
	regw(ctlr, Data, lastw);
	mmucommand(ctlr, McrEnqueue);  // chip now owns buff
	freeb(b);
	regw(ctlr, Interrupt, (regr(ctlr, Interrupt) & IntrMaskField) | (IntTxEmpty << IntrMaskShift));
}

static void
txstart(Ether *ether)
{
	Ctlr *ctlr;
	int n;

	ctlr = ether->ctlr;
	if(ctlr->waiting != nil)	/* allocate pending; must wait for that */
		return;
	for(;;){
		if((ctlr->waiting = qget(ether->oq)) == nil)
			break;
		/* ctlr->waiting is a new block to transmit: allocate space */
		n = (BLEN(ctlr->waiting) & ~1) + Framectlsize;	/* Framectlsize includes odd byte, if any */
		mmucommand(ctlr, McrAllocTx | (n >> 8));
		if(regr(ctlr, ArrPnr) & ArrFailed){
			regw(ctlr, Interrupt, (regr(ctlr, Interrupt) & IntrMaskField) | (IntAlloc << IntrMaskShift));
			break;
		}
		txloadpacket(ether);
	}
}

static void
transmit(Ether *ether)
{
	Ctlr *ctlr;

	ctlr = ether->ctlr;
	ilock(ctlr);
	txstart(ether);
	iunlock(ctlr);
}

static void
process(Ether *ether)
{
	Ctlr *ctlr;
	int status, intrreg, intr, mask, fifo;
	int pkt;
	ulong data;
	int count, len, alen;
	Block *b;

	ctlr = ether->ctlr;

Recheck:
	intrreg = regr(ctlr, Interrupt);
	regw(ctlr, Interrupt, 0);
	mask = intrreg >> IntrMaskShift;
	intr = intrreg & mask;
	if(intr == 0){
		regw(ctlr, Interrupt, mask<<IntrMaskShift);
		return;
	}

	if(intr & IntAlloc){
		regw(ctlr, Interrupt, IntAlloc);
		intr &= ~IntAlloc;
		if(ctlr->waiting)
			txloadpacket(ether);
		mask &= ~IntAlloc;
		mask |= IntTxEmpty;
	}

	if(intr & IntRxOvrn){
		regw(ctlr, Interrupt, IntRxOvrn);
		intr &= ~IntRxOvrn;
		ether->overflows++;
	}
	if(intr & IntRcv){
		fifo = regr(ctlr, FifoPorts);
		while((fifo & FifoRxEmpty) == 0){
			ether->inpackets++;
			pointtorxpacket(ctlr, 0);
			data = regr32(ctlr, Data);
			status = data & 0xFFFF;
			count = (data>>16) & 0x7FE;
			if(status & RsBadCRC)
				ether->crcs++;
			else if(status & RsAlgnErr)
				ether->frames++;
			else if(status & (RsTooLong | RsTooShort))
				ether->buffs++;
			else {
				len = count - Framectlsize;
				if(len < 0)
					panic("smc:interrupt");
				if(ctlr->type == SMSC91C111 && !ctlr->oddworks)
					len++;
				else if(status & RsOddFrame)
					len++;
				alen = (len + 1) & ~1;
				if(ctlr->bus32bit)
					alen = (alen + 3) & ~3;
				b = iallocb(alen);
				if(b){
					(ctlr->bus32bit? regrdatam32: regrdatam)(ctlr, b->wp, alen);
					b->wp += len;
					etheriq(ether, b, 1);
				}else
					ether->soverflows++;
			}
			mmucommand(ctlr, McrRemove);
			fifo = regr(ctlr, FifoPorts);
		}
		intr &= ~IntRcv;
	}
	if(intr & IntTx){
		/* some kind of failure  */
		fifo = regr(ctlr, FifoPorts);
		ctlr->txerrors++;
		if((fifo & FifoTxEmpty) == 0){
			pkt = fifo & 0x3f;
			pointtotxpacket(ctlr, pkt, PtrRead);
			mmucommand(ctlr, McrFreeTx);
		}					
		regw(ctlr, Interrupt, IntTx);
		intr &= ~IntTx;
	}
	if(intr & IntTxEmpty){
		/* acknowledge and disable TX_EMPTY */
		regw(ctlr, Interrupt, IntTxEmpty);
		mask &= ~IntTxEmpty;
		intr &= ~IntTxEmpty;
	}
	if(intr)
		panic("91c111: unhandled interrupts %.4ux\n", intr);
	regw(ctlr, Interrupt, mask<<IntrMaskShift);
	txstart(ether);
	goto Recheck;
}

static void
interrupt(Ureg*, void *arg)
{
	Ether *ether;
	Ctlr *ctlr;
	int bank;

	ether = arg;
	ctlr = ether->ctlr;
	ilock(ctlr);
	bank = llregr(ctlr, BankSelect);
	process(ether);
	llregw(ctlr, BankSelect, bank);
	ctlr->bank = bank;
	iunlock(ctlr);
}

#define MIIDELAY 5

static int
miimdi(Ctlr *ctlr, int n)
{
	int data, i;

	/*
	 * Read n bits from the MII Management Register.
	 */
	data = 0;
	for(i = n - 1; i >= 0; i--){
		if(regr(ctlr, Mgmt) & MgmtMdi)
			data |= (1 << i);
		microdelay(MIIDELAY);
		regw(ctlr, Mgmt, MgmtMclk);
		microdelay(MIIDELAY);
		regw(ctlr, Mgmt, 0);
		microdelay(MIIDELAY);
	}

	return data;
}

static void
miimdo(Ctlr *ctlr, int bits, int n)
{
	int i, mdo;

	/*
	 * Write n bits to the MII Management Register.
	 */
	for(i = n - 1; i >= 0; i--){
		if(bits & (1 << i))
			mdo = MgmtMdoEn | MgmtMdo;
		else
			mdo = MgmtMdoEn;
		regw(ctlr, Mgmt, mdo);
		microdelay(MIIDELAY);
		regw(ctlr, Mgmt, mdo | MgmtMclk);
		microdelay(MIIDELAY);
		regw(ctlr, Mgmt, mdo);
		microdelay(MIIDELAY);
	}
}

static int
miir(Ctlr *ctlr, int regad)
{
	int data;

	/*
	 * Preamble;
	 * ST+OP+PHYAD+REGAD;
	 * TA + 16 data bits.
	 */
	miimdo(ctlr, 0xFFFFFFFF, 32);
	miimdo(ctlr, 0x1800 | (ctlr->phyad << 5) | regad, 14);
	data = miimdi(ctlr, 18);
	regw(ctlr, Mgmt, 0);
	microdelay(MIIDELAY);

	return data & 0xFFFF;
}

static void
miiw(Ctlr* ctlr, int regad, int data)
{
	/*
	 * Preamble;
	 * ST+OP+PHYAD+REGAD+TA + 16 data bits;
	 * Z.
	 */
	miimdo(ctlr, 0xFFFFFFFF, 32);
	data &= 0xFFFF;
	data |= (0x05 << (5 + 5 + 2 + 16)) | (ctlr->phyad << (5 + 2 +16)) | (regad << (2 + 16)) | (0x02 << 16);
	miimdo(ctlr, data, 32);
	regw(ctlr, Mgmt, 0);
	microdelay(MIIDELAY);
}

static void
miinegostatus(Ctlr *ctlr, int *speed, int *full)
{
	int reg;

	switch(ctlr->type){
	case SMSC91C110:
		reg = miir(ctlr, 25);
		if((reg & (1<<4)) == 0)
			break;
		*speed = (reg & (1 << 5))? 100: 10;
		*full = (reg & (1 << 6)) != 0;
		return;
	case SMSC91C111:
		reg = miir(ctlr, 18);
		*speed = (reg & (1 << 7))? 100: 10;
		*full = (reg & (1 << 6)) != 0;
		return;
	}
	*speed = 0;
	*full = 0;
}

void
dump111phyregs(Ctlr *ctlr)
{
	int x;
	for(x = 0; x < 6; x++)
		iprint("reg%d 0x%.4ux\n", x, miir(ctlr, x));
	for(x = 16; x <= 20; x++)
		iprint("reg%d 0x%.4ux\n", x, miir(ctlr, x));
}

static void
miireset(Ctlr *ctlr)
{
	miiw(ctlr, 0, 0x8000);
	while(miir(ctlr, 0) & 0x8000)
		;
	delay(100);
}

static int
miinegotiate(Ctlr *ctlr, int modes)
{
	ulong now, timeout;
	int success;
	int reg4;

	// Taken from TRM - don't argue

	miireset(ctlr);
	miiw(ctlr, 0, 0);
	regw(ctlr, Rpcr, 0x800 | (4 << 2));
	delay(50);
	reg4 = miir(ctlr, 4);
	reg4 &= ~(0x1f << 5);
	reg4 |= ((modes & 0x1f) << 5);
	miiw(ctlr, 4, reg4);
	miir(ctlr, 18);	// clear the status output so we can tell which bits got set...
	miiw(ctlr, 0, 0x3300);
	now = timer_start();
	timeout = ms2tmr(3000);
	success = 0;
	while(!success && (timer_start() - now) < timeout){
		ushort status;
		status = miir(ctlr, 1);
		if(status & (1 << 5))
			success = 1;
		if(status & (1 << 4)){
			success = 0;
			miiw(ctlr, 0, 0x3300);
		}
	}
	return success;
}

static int
ether91c111reset(Ether* ether)
{
	int i;
	char *p;
	uchar ea[Eaddrlen];
	Ctlr *ctlr;
	ushort rev;

	if(ether->ctlr == nil){
		ether->ctlr = malloc(sizeof(Ctlr));
		if(ether->ctlr == nil)
			return -1;
	}

	ctlr = ether->ctlr;
	ctlr->bank = -1;

	/*
	 * do architecture dependent intialisation
	 */
	adinit(ether);

	regw(ctlr, Rcr, RcrSoftRst);
	regw(ctlr, Config, CfgEphPowerEn|CfgNoWait|Cfg16Bit);
	delay(4*20);			// rkw -  (750us for eeprom alone)4x just to be ultra conservative 10 for linux.
	regw(ctlr, Rcr, 0);		// rkw - now remove reset and let the sig's fly.
	regw(ctlr, Tcr, TcrSwfdup);

	regw(ctlr, Control, CtlAutoRelease | CtlTeEnable);
	mmucommand(ctlr, McrReset);  // rkw - reset the mmu
	delay(5);

	/*
	 * Identify the chip by reading...
	 * 1) the bank select register - the top byte will be 0x33
	 * 2) changing the bank to see if it reads back appropriately
	 * 3) check revision register for code 9
	 */
	if((llregr(ctlr, BankSelect) >> 8) != 0x33){
	gopanic:
		free(ctlr);
		return -1;
	}

	llregw(ctlr, BankSelect, 0xfffb);
	if((llregr(ctlr, BankSelect) & 0xff07) != 0x3303)
		goto gopanic;

	rev = regr(ctlr, Revision);
	
	if((rev >> 8) != 0x33)
		goto gopanic;

	rev &= 0xff;
	switch(rev){
	case 0x40:
		/* 91c96 */
		ctlr->type = SMSC91C96;
		ctlr->oddworks = 1;
		break;
	case 0x90:
		ctlr->type = SMSC91C11x;
		ctlr->hasmii = 1;
		/* 91c110/9c111 */
		/* 91c111s are supposed to be revision one, but it's not the case */
		// See man page 112, revision history.  rev not incremented till 08/01
		ctlr->oddworks = 0;  // dont know if it works at this point
		break;
	case 0x91:
		ctlr->type = SMSC91C111;
		ctlr->hasmii = 1;
		ctlr->oddworks = 1;
		break;
	default:
		iprint("ether91c111: chip 0x%.1ux detected\n", rev);
		goto gopanic;
	}

	memset(ea, 0, sizeof(ea));
	if(memcmp(ether->ea, ea, Eaddrlen) == 0)
		panic("ethernet address not set");
#ifdef YYY
		if((rev == 0x90) || (rev == 0x91))	// assuming no eeprom setup for these
			panic("ethernet address not set in environment");
		for(i = 0; i < Eaddrlen; i += 2){
			ushort w;
			w = regr(ctlr, Iaddr0_1 + i);
			iprint("0x%.4ux\n", w);
			ea[i] = w;
			ea[i + 1] = w >> 8;
		}
	}else{
		for(i = 0; i < 6; i++){
			char buf[3];
			buf[0] = p[i * 2];
			buf[1] = p[i * 2 + 1];
			buf[2] = 0;
			ea[i] = strtol(buf, 0, 16);
		}
	}
	memmove(ether->ea, ea, Eaddrlen);
#endif

	/*
	 * set the local address
	 */
	for(i=0; i<Eaddrlen; i+=2)
		regw(ctlr, Iaddr0_1 + i, ether->ea[i] | (ether->ea[i+1] << 8));

	/*
	 * initialise some registers
	 */
	regw(ctlr, Rcr, RcrRxEn | RcrAbortEnb | RcrStripCRC);	   // strip can now be used again

	if(rev == 0x90){		   // its either a 110 or a 111 rev A at this point
		int reg2, reg3;
		/*
		 * how to tell the difference?
		 * the standard MII dev
		 */
		ctlr->phyad = PHYMIIADDR_91C110;
		ctlr->type = SMSC91C110;
		ctlr->oddworks = 1;		// assume a 110
		reg2 = miir(ctlr, 2);	// check if a 111 RevA
		if(reg2 <= 0){
			ctlr->phyad = PHYMIIADDR_91C111;
			ctlr->type = SMSC91C111;
			reg2 = miir(ctlr, 2);
			ctlr->oddworks = 0;	   // RevA
		}
		if(reg2 > 0){
			reg3 = miir(ctlr, 3);
			iprint("reg2 0x%.4ux reg3 0x%.4ux\n", reg2, reg3);
		}
		else
			panic("ether91c111: can't find phy on MII\n");
	}

	if(ctlr->type == SMSC91C110)
		regor(ctlr, Config, CfgMiiSelect);
	if(rev == 0x40){
		regor(ctlr, Config, CfgSetSqlch);
		regclear(ctlr, Config, CfgAuiSelect);
		regor(ctlr, Config, Cfg16Bit);
	}

	if(ctlr->type == SMSC91C111){
		int modes;
		char *ethermodes;

		miiw(ctlr, 0, 0x1000);				/* clear MII_DIS and enable AUTO_NEG */
//		miiw(ctlr, 16, miir(ctlr, 16) | 0x8000);
		// Rpcr set in INIT.
		ethermodes=nil;	/* was getconf("ethermodes"); */
		if(ethermodes == nil)
			modes = 0xf;
		else {
			char *s;
			char *args[10];
			int nargs;
			int x;

			s = strdup(ethermodes);
			if(s == nil)
				panic("ether91c111reset: no memory for ethermodes");
			nargs = getfields(s, args, nelem(args), 1, ",");
			modes = 0;
			for(x = 0; x < nargs; x++){
				if(cistrcmp(args[x], "10HD") == 0)
					modes |= 1;
				else if(cistrcmp(args[x], "10FD") == 0)
					modes |= 2;
				else if(cistrcmp(args[x], "100HD") == 0)
					modes |= 4;
				else if(cistrcmp(args[x], "100FD") == 0)
					modes |= 8;
			}
			free(s);
		}
		if(!miinegotiate(ctlr, modes)){
			iprint("ether91c111: negotiation timed out\n");
			return -1;
		}
	}

	if(ctlr->hasmii)
		miinegostatus(ctlr, &ether->mbps, &ether->fullduplex);
	else if(regr(ctlr, Eph) & EphLinkOk){
		ether->mbps = 10;
		ether->fullduplex = 0;
	}
	else {
		ether->mbps = 0;
		ether->fullduplex = 0;
	}

	if(ether->fullduplex && ctlr->type == SMSC91C110){
		// application note 79
		regor(ctlr, Tcr, TcrFduplx);
		// application note 85
		adsetfd(ctlr);
	}

	iprint("91c111 enabled: %dmbps %s\n", ether->mbps, ether->fullduplex ? "FDX" : "HDX");
	if(rev == 0x40){
		iprint("EcsrEcor 0x%.4ux\n", regr(ctlr, EcsrEcor));
		regor(ctlr, EcsrEcor, 1);
	}

	/*
	 * Linkage to the generic ethernet driver.
	 */
	ether->attach = attach;
	ether->transmit = transmit;
	ether->interrupt = interrupt;
	ether->ifstat = ifstat;

	ether->arg = ether;
	ether->promiscuous = promiscuous;

	return 0;
}

void
ether91c111link(void)
{
	addethercard("91c111",  ether91c111reset);
}
