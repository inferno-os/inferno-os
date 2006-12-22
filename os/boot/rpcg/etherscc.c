/*
 * SCCn ethernet
 */

#include "u.h"
#include "lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"

#include "etherif.h"

enum {
	Nrdre		= 32,	/* receive descriptor ring entries */
	Ntdre		= 4,	/* transmit descriptor ring entries */

	Rbsize		= ETHERMAXTU+4,		/* ring buffer size (+4 for CRC) */
	Bufsize		= (Rbsize+7)&~7,	/* aligned */
};

enum {
	/* ether-specific Rx BD bits */
	RxMiss=		1<<8,
	RxeLG=		1<<5,
	RxeNO=		1<<4,
	RxeSH=		1<<3,
	RxeCR=		1<<2,
	RxeOV=		1<<1,
	RxeCL=		1<<0,
	RxError=		(RxeLG|RxeNO|RxeSH|RxeCR|RxeOV|RxeCL),	/* various error flags */

	/* ether-specific Tx BD bits */
	TxPad=		1<<14,	/* pad short frames */
	TxTC=		1<<10,	/* transmit CRC */
	TxeDEF=		1<<9,
	TxeHB=		1<<8,
	TxeLC=		1<<7,
	TxeRL=		1<<6,
	TxeUN=		1<<1,
	TxeCSL=		1<<0,

	/* scce */
	RXB=	1<<0,
	TXB=	1<<1,
	BSY=		1<<2,
	RXF=		1<<3,
	TXE=		1<<4,

	/* gsmrl */
	ENR=	1<<5,
	ENT=	1<<4,

	/* port A */
	RXD1=	SIBIT(15),
	TXD1=	SIBIT(14),

	/* port B */
	RTS1=	IBIT(19),

	/* port C */
	CTS1=	SIBIT(11),
	CD1=	SIBIT(10),
};

typedef struct Etherparam Etherparam;
struct Etherparam {
	SCCparam;
	ulong	c_pres;		/* preset CRC */
	ulong	c_mask;		/* constant mask for CRC */
	ulong	crcec;		/* CRC error counter */
	ulong	alec;		/* alighnment error counter */
	ulong	disfc;		/* discard frame counter */
	ushort	pads;		/* short frame PAD characters */
	ushort	ret_lim;	/* retry limit threshold */
	ushort	ret_cnt;	/* retry limit counter */
	ushort	mflr;		/* maximum frame length reg */
	ushort	minflr;		/* minimum frame length reg */
	ushort	maxd1;		/* maximum DMA1 length reg */
	ushort	maxd2;		/* maximum DMA2 length reg */
	ushort	maxd;		/* rx max DMA */
	ushort	dma_cnt;	/* rx dma counter */
	ushort	max_b;		/* max bd byte count */
	ushort	gaddr[4];		/* group address filter */
	ulong	tbuf0_data0;	/* save area 0 - current frm */
	ulong	tbuf0_data1;	/* save area 1 - current frm */
	ulong	tbuf0_rba0;
	ulong	tbuf0_crc;
	ushort	tbuf0_bcnt;
	ushort	paddr[3];	/* physical address LSB to MSB increasing */
	ushort	p_per;		/* persistence */
	ushort	rfbd_ptr;	/* rx first bd pointer */
	ushort	tfbd_ptr;	/* tx first bd pointer */
	ushort	tlbd_ptr;	/* tx last bd pointer */
	ulong	tbuf1_data0;	/* save area 0 - next frame */
	ulong	tbuf1_data1;	/* save area 1 - next frame */
	ulong	tbuf1_rba0;
	ulong	tbuf1_crc;
	ushort	tbuf1_bcnt;
	ushort	tx_len;		/* tx frame length counter */
	ushort	iaddr[4];		/* individual address filter*/
	ushort	boff_cnt;	/* back-off counter */
	ushort	taddr[3];	/* temp address */
};

typedef struct {
	SCC*	scc;
	int	port;
	int	cpm;

	BD*	rdr;				/* receive descriptor ring */
	void*	rrb;				/* receive ring buffers */
	int	rdrx;				/* index into rdr */

	BD*	tdr;				/* transmit descriptor ring */
	void*	trb;				/* transmit ring buffers */
	int	tdrx;				/* index into tdr */
} Mot;
static Mot mot[MaxEther];

static	int	sccid[] = {-1, SCC1ID, SCC2ID, SCC3ID, SCC4ID};
static	int	sccparam[] = {-1, SCC1P, SCC2P, SCC3P, SCC4P};
static	int	sccreg[] = {-1, 0xA00, 0xA20, 0xA40, 0xA60};
static	int	sccirq[] = {-1, 0x1E, 0x1D, 0x1C, 0x1B};

static void
attach(Ctlr *ctlr)
{
	mot[ctlr->ctlrno].scc->gsmrl |= ENR|ENT;
	eieio();
}

static void
transmit(Ctlr *ctlr)
{
	int len;
	Mot *motp;
	Block *b;
	BD *tdre;

	motp = &mot[ctlr->ctlrno];
	while(((tdre = &motp->tdr[motp->tdrx])->status & BDReady) == 0){
		b = qget(ctlr->oq);
		if(b == 0)
			break;

		/*
		 * Copy the packet to the transmit buffer.
		 */
		len = BLEN(b);
		memmove(KADDR(tdre->addr), b->rp, len);
	
		/*
		 * Give ownership of the descriptor to the chip, increment the
		 * software ring descriptor pointer and tell the chip to poll.
		 */
		tdre->length = len;
		eieio();
		tdre->status = (tdre->status & BDWrap) | BDReady|TxPad|BDInt|BDLast|TxTC;
		eieio();
		motp->scc->todr = 1<<15;	/* transmit now */
		eieio();
		motp->tdrx = NEXT(motp->tdrx, Ntdre);

		freeb(b);
	
	}
}

static void
interrupt(Ureg*, void *ap)
{
	int len, events, status;
	Mot *motp;
	BD *rdre;
	Block *b;
	Ctlr *ctlr;

	ctlr = ap;
	motp = &mot[ctlr->ctlrno];

	/*
	 * Acknowledge all interrupts and whine about those that shouldn't
	 * happen.
	 */
	events = motp->scc->scce;
	eieio();
	motp->scc->scce = events;
	eieio();
	if(events & (TXE|BSY|RXB))
		print("ETHER.SCC#%d: scce = 0x%uX\n", ctlr->ctlrno, events);
	//print(" %ux|", events);
	/*
	 * Receiver interrupt: run round the descriptor ring logging
	 * errors and passing valid receive data up to the higher levels
	 * until we encounter a descriptor still owned by the chip.
	 */
	if(events & (RXF|RXB) || 1){
		rdre = &motp->rdr[motp->rdrx];
		while(((status = rdre->status) & BDEmpty) == 0){
			if(status & RxError || (status & (BDFirst|BDLast)) != (BDFirst|BDLast)){
				//if(status & RxBuff)
				//	ctlr->buffs++;
				if(status & (1<<2))
					ctlr->crcs++;
				if(status & (1<<1))
					ctlr->overflows++;
				//print("eth rx: %ux\n", status);
				if(status & RxError)
					print("~");
				else if((status & BDLast) == 0)
					print("@");
			}
			else{
				/*
				 * We have a packet. Read it into the next
				 * free ring buffer, if any.
				 */
				len = rdre->length-4;
				if((b = iallocb(len)) != 0){
					memmove(b->wp, KADDR(rdre->addr), len);
					b->wp += len;
					etheriq(ctlr, b, 1);
				}
			}

			/*
			 * Finished with this descriptor, reinitialise it,
			 * give it back to the chip, then on to the next...
			 */
			rdre->length = 0;
			rdre->status = (rdre->status & BDWrap) | BDEmpty | BDInt;
			eieio();

			motp->rdrx = NEXT(motp->rdrx, Nrdre);
			rdre = &motp->rdr[motp->rdrx];
		}
	}

	/*
	 * Transmitter interrupt: handle anything queued for a free descriptor.
	 */
	if(events & TXB)
		transmit(ctlr);
	if(events & TXE)
		cpmop(RestartTx, motp->cpm, 0);
}

static void
ringinit(Mot* motp)
{
	int i, x;

	/*
	 * Initialise the receive and transmit buffer rings. The ring
	 * entries must be aligned on 16-byte boundaries.
	 */
	if(motp->rdr == 0)
		motp->rdr = bdalloc(Nrdre);
	if(motp->rrb == 0)
		motp->rrb = ialloc(Nrdre*Bufsize, 0);
	x = PADDR(motp->rrb);
	for(i = 0; i < Nrdre; i++){
		motp->rdr[i].length = 0;
		motp->rdr[i].addr = x;
		motp->rdr[i].status = BDEmpty|BDInt;
		x += Bufsize;
	}
	motp->rdr[i-1].status |= BDWrap;
	motp->rdrx = 0;

	if(motp->tdr == 0)
		motp->tdr = bdalloc(Ntdre);
	if(motp->trb == 0)
		motp->trb = ialloc(Ntdre*Bufsize, 0);
	x = PADDR(motp->trb);
	for(i = 0; i < Ntdre; i++){
		motp->tdr[i].addr = x;
		motp->tdr[i].length = 0;
		motp->tdr[i].status = TxPad|BDInt|BDLast|TxTC;
		x += Bufsize;
	}
	motp->tdr[i-1].status |= BDWrap;
	motp->tdrx = 0;
}

/*
 * This follows the MPC823 user guide: section16.9.23.7's initialisation sequence,
 * except that it sets the right bits for the MPC823ADS board when SCC2 is used,
 * and those for the 860/821 development board for SCC1.
 */
static void
sccsetup(Mot *ctlr, SCC *scc, uchar *ea)
{
	int i, rcs, tcs, w;
	Etherparam *p;
	IMM *io;


	i = 2*(ctlr->port-1);
	io = ioplock();
	w = (TXD1|RXD1)<<i;	/* TXDn and RXDn in port A */
	io->papar |= w;	/* enable TXDn and RXDn pins */
	io->padir &= ~w;
	io->paodr &= ~w;	/* not open drain */

	w = (CD1|CTS1)<<i;	/* CLSN and RENA: CDn and CTSn in port C */
	io->pcpar &= ~w;	/* enable CLSN (CTSn) and RENA (CDn) */
	io->pcdir &= ~w;
	io->pcso |= w;
	iopunlock();

	/* clocks and transceiver control: details depend on the board's wiring */
	archetherenable(ctlr->cpm, &rcs, &tcs);

	sccnmsi(ctlr->port, rcs, tcs);	/* connect the clocks */

	p = (Etherparam*)KADDR(sccparam[ctlr->port]);
	memset(p, 0, sizeof(*p));
	p->rfcr = 0x18;
	p->tfcr = 0x18;
	p->mrblr = Bufsize;
	p->rbase = PADDR(ctlr->rdr);
	p->tbase = PADDR(ctlr->tdr);

	cpmop(InitRxTx, ctlr->cpm, 0);

	p->c_pres = ~0;
	p->c_mask = 0xDEBB20E3;
	p->crcec = 0;
	p->alec = 0;
	p->disfc = 0;
	p->pads = 0x8888;
	p->ret_lim = 0xF;
	p->mflr = Rbsize;
	p->minflr = ETHERMINTU+4;
	p->maxd1 = Bufsize;
	p->maxd2 = Bufsize;
	p->p_per = 0;	/* only moderate aggression */

	for(i=0; i<Eaddrlen; i+=2)
		p->paddr[2-i/2] = (ea[i+1]<<8)|ea[i];	/* it's not the obvious byte order */

	scc->psmr = (2<<10)|(5<<1);	/* 32-bit CRC, ignore 22 bits before SFD */
	scc->dsr = 0xd555;
	scc->gsmrh = 0;	/* normal operation */
	scc->gsmrl = (1<<28)|(4<<21)|(1<<19)|0xC;	/* transmit clock invert, 48 bit preamble, repetitive 10 preamble, ethernet */
	eieio();
	scc->scce = ~0;	/* clear all events */
	eieio();
	scc->sccm = TXE | RXF | TXB;	/* enable interrupts */
	eieio();

	io = ioplock();
	w = RTS1<<(ctlr->port-1);	/* enable TENA pin (RTSn) */
	io->pbpar |= w;
	io->pbdir |= w;
	iopunlock();

	/* gsmrl enable is deferred until attach */
}

/*
 * Prepare the SCCx ethernet for booting.
 */
int
sccethreset(Ctlr* ctlr)
{
	uchar ea[Eaddrlen];
	Mot *motp;
	SCC *scc;
	char line[50], def[50];

	/*
	 * Since there's no EPROM, insist that the configuration entry
	 * (see conf.c and flash.c) holds the Ethernet address.
	 */
	memset(ea, 0, Eaddrlen);
	if(memcmp(ea, ctlr->card.ea, Eaddrlen) == 0){
		print("no preset Ether address\n");
		for(;;){
			strcpy(def, "00108bf12900");	/* valid MAC address to be used only for initial configuration */
			if(getstr("ether MAC address", line, sizeof(line), def) < 0)
				return -1;
			if(parseether(ctlr->card.ea, line) >= 0 || ctlr->card.ea[0] == 0xFF)
				break;
			print("invalid MAC address\n");
		}
	}

	scc = IOREGS(sccreg[ctlr->card.port], SCC);
	ctlr->card.irq = VectorCPIC+sccirq[ctlr->card.port];

	motp = &mot[ctlr->ctlrno];
	motp->scc = scc;
	motp->port = ctlr->card.port;
	motp->cpm = sccid[ctlr->card.port];

	ringinit(motp);

	sccsetup(motp, scc, ctlr->card.ea);

	/* enable is deferred until attach */

	ctlr->card.reset = sccethreset;
	ctlr->card.attach = attach;
	ctlr->card.transmit = transmit;
	ctlr->card.intr = interrupt;

	return 0;
}
