/*
 * ethernet
 */

#include "u.h"
#include "lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "../port/error.h"
#include "../port/netif.h"

#include "ethermii.h"
#include "etherif.h"
#include "ureg.h"

/*
 * TO DO:
 *	- test EMAC1
 */

#define	DBG	if(0)iprint
#define	MIIDBG	if(0)iprint

enum {
	Nrdre		= 64,	/* receive descriptor ring entries */
	Ntdre		= 32,	/* transmit descriptor ring entries */
	Nrxchan		= 2,
	Ntxchan		= 2,	/* there are actually 4 but we only use 2 now */

	Rbsize		= ETHERMAXTU,		/* ring buffer size */
	Bufsize		= (Rbsize+CACHELINESZ-1)&~(CACHELINESZ-1),	/* aligned */
};

enum {
	/* emac-specific Rx BD bits */
	RxOverrun=	1<<9,	/* not enough empty space in FIFO */
	RxPause=		1<<8,	/* control pause packet */
	RxBad=		1<<7,	/* packet error */
	RxRunt=		1<<6,
	RxShort=		1<<5,
	RxAlign=		1<<4,
	RxFCS=		1<<3,
	RxLong=		1<<2,
	RxRange=		1<<1,	/* out of range error */
	RxInRange=	1<<0,	/* in range error */
	RxError=		(0x3FF & ~RxPause),	/* error flags */

	/* emac-specific Tx BD bits */
	/* write access */
	TxFCS=		1<<9,	/* generate FCS */
	TxPad=		1<<8,	/* pad short frames */
	TxInsSA=		1<<7,	/* insert source address */
	TxRepSA=		1<<6,	/* replace source address */
	TxInsVLAN=	1<<5,	/* insert VLAN tag */
	TxRepVLAN=	1<<4,	/* replace VLAN tag */

	/* read access (status) */
	TxBadFCS=	1<<9,
	TxBadPrev=	1<<8,	/* bad previous packet in dependent mode */
	TxLostCarrier=	1<<7,
	TxEDef=		1<<6,	/* excessive deferral */
	TxECol=		1<<5,	/* excessive collisions */
	TxLateCol=	1<<4,	/* late collision (half-duplex only) */
	TxManyCol=	1<<3,	/* more than 1 but less than 16 collisions */
	TxCollision=	1<<2,	/* single collision */
	TxUnderrun=	1<<1,	/* didn't fill FIFO in time */
	TxSQE=		1<<0,	/* signal quality test failed (10mbit half-duplex only) */
	TxError=		0x3FF,	/* error flags */
};

typedef struct Emac Emac;
struct Emac {
	ulong	mr0;		/* mode register 0 [see 19-48] */
	ulong	mr1;		/* mode register 1 [Reset] */
	ulong	tmr0;	/* transmit mode register 0 [see 19-28] */
	ulong	tmr1;	/* transmit mode register 1 [see 19-28] */
	ulong	rmr;		/* receive mode register [Reset] */
	ulong	isr;		/* interrupt status register [Always] */
	ulong	iser;		/* interrupt status enable register [Reset] */
	ulong	iahr;		/* individual address high [Reset, R, T]*/
	ulong	ialr;		/* individual address low [Reset, R, T] */
	ulong	vtpid;	/* VLAN Tag Protocol Identifier [Reset, R, T] */
	ulong	vtci;		/* VLAN Tag Control Information [Reset, R, T] */
	ulong	ptr;		/* pause timer [Reset, T] */
	ulong	iaht[4];	/* individual address hash table [Reset, R] */
	ulong	gaht[4];	/* group address hash table [Reset, R] */
	ulong	lsah;		/* last source address high */
	ulong	lsal;		/* last source address low */
	ulong	ipgvr;	/* inter-packet gap value [Reset, T] */
	ulong	stacr;	/* STA control register [see 19-41] */
	ulong	trtr;		/* transmit request threshold register [see 19-42] */
	ulong	rwmr;	/* receive low/high water mark [Reset] */
	ulong	octx;		/* bytes transmitted */
	ulong	ocrx;	/* bytes received */
};

enum {
	/* mode register 0 */
	Mr0Rxi=	1<<31,	/* receive MAC idle */
	Mr0Txi=	1<<30,	/* transmit MAC idle */
	Mr0Srst=	1<<29,	/* soft reset; soft reset in progress */
	Mr0Txe=	1<<28,	/* tx MAC enable */
	Mr0Rxe=	1<<27,	/* rx MAC enable */
	Mr0Wke=	1<<26,	/* enable wake-up packets */

	/* mode register 1 */
	Mr1Fde=	1<<31,	/* full-duplex enable */
	Mr1Ile=	1<<30,	/* internal loop-back enable */
	Mr1Vle=	1<<29,	/* VLAN enable */
	Mr1Eifc=	1<<28,	/* enable integrated flow control */
	Mr1App=	1<<27,	/* allow pause packets */
	Mr1Ist=	1<<24,	/* ignore sqe test (all but half-duplex 10m/bit) */
	Mr1Mf10=	0<<22,	/* medium [MII] frequency is 10 mbps */
	Mr1Mf100=	1<<22,	/* medium frequency is 100 mbps */
	Mr1Rfs512=	0<<20,	/* RX FIFO size (512 bytes) */
	Mr1Rfs1024=	1<<20,
	Mr1Rfs2048=	2<<20,
	Mr1Rfs4096=	3<<20,
	Mr1Tfs1024=	1<<18,	/* TX FIFO size (1024 bytes) */
	Mr1Tfs2048=	2<<18,
	Mr1Tr0sp=	0<<15,	/* transmit request 0: single packet */
	Mr1Tr0mp=	1<<15,	/* multiple packets */
	Mr1Tr0dm=	2<<15,	/* dependent mode */
	Mr1Tr1sp=	0<<13,	/* transmit request 1: single packet */
	Mr1Tr1mp=	1<<13,	/* multiple packets */
	Mr1Tr1dm=	2<<13,	/* dependent mode */

	/* transmit mode register 0 */
	Tmr0Gnp0=	1<<31,	/* get new packet channel 0 */
	Tmr0Gnp1=	1<<30,	/* get new packet channel 1 */
	Tmr0Gnpd=	1<<29,	/* get new packet dependent mode */
	Tmr0Fc=		1<<28,	/* first channel (dependent mode) */

	/* transmit mode register 1 */
	Tmr1Trl_s=	27,		/* transmit low request (shift) */
	Tmr1Tur_s=	16,		/* transmit urgent request (shift) */

	/* receive mode register */
	RmrSp=		1<<31,	/* strip pad/FCS bytes */
	RmrSfcs=		1<<30,	/* strip FCS */
	RmrRrp=		1<<29,	/* receive runt packets */
	RmrRfp=		1<<28,	/* receive packets with FCS error */
	RmrRop=		1<<27,	/* receive oversize packets */
	RmrRpir=		1<<26,	/* receive packets with in range error */
	RmrPpp=		1<<25,	/* propagate pause packet */
	RmrPme=		1<<24,	/* promiscuous mode enable */
	RmrPmme=	1<<23,	/* promiscuous mode multicast enable */
	RmrIae=		1<<22,	/* individual address enable */
	RmrMiae=		1<<21,	/* multiple individual address enable */
	RmrBae=		1<<20,	/* broadcast address enable */
	RmrMae=		1<<19,	/* multicast address enable */

	/* interrupt status register */
	IsrOvr=		1<<25,	/* overrun error */
	IsrPp=		1<<24,	/* pause packet */
	IsrBp=		1<<23,	/* bad packet */
	IsrRp=		1<<22,	/* runt packet */
	IsrSe=		1<<21,	/* short event */
	IsrAle=		1<<20,	/* alignment error */
	IsrBfcs=		1<<19,	/* bad FCS */
	IsrPtle=		1<<18,	/* packet too long error */
	IsrOre=		1<<17,	/* out of range error */
	IsrIre=		1<<16,	/* in range error */
	IsrDbdm=		1<<9,	/* dead bit dependent mode */
	IsrDb0=		1<<8,	/* dead bit 0 */
	IsrSe0=		1<<7,	/* sqe 0 */
	IsrTe0=		1<<6,	/* tx error 0 */
	IsrDb1=		1<<5,	/* dead bit 1 */
	IsrSe1=		1<<4,	/* sqe 1 */
	IsrTe1=		1<<3,	/* tx error 1 */
	IsrMos=		1<<1,	/* MMA operation succeeded */
	IsrMof=		1<<0,	/* MMA operation failed */

	/* STA control register */
	StaOc=		1<<15,	/* operation complete */
	StaPhye=		1<<14,	/* PHY error */
	StaRead=		1<<12,	/* STA read */
	StaWrite=		2<<12,	/* STA write */
	StaOpb50=	0<<10,	/* OPB frequency */
	StaOpb66=	1<<10,
	StaOpb83=	2<<10,
	StaOpb100=	3<<10,

	/* transmit request threshold */
	TrtrTrt_s=		27,	/* threshold (shift) -- and the value is (threshold/64)-1 */

	/* receive low/high water mark register */
	RwmrRlwm_s=	23,	/* low water mark (shift) */
	RwmrRhwm_s=	7,	/* high water mark (shift) */
};

typedef struct {
	Lock;
	int	port;
	int	init;
	int	active;
	Emac	*regs;
	Emac	*miiregs;
	Mal*	rx;
	Mal*	tx;

	Mii	*mii;

	Ring;

	ulong	interrupts;			/* statistics */
	ulong	deferred;
	ulong	heartbeat;
	ulong	latecoll;
	ulong	retrylim;
	ulong	underrun;
	ulong	overrun;
	ulong	carrierlost;
	ulong	retrycount;
} Ctlr;

static void dumpemac(Emac*);

static void
attach(Ether *ether)
{
	Ctlr *ctlr;

	ctlr = ether->ctlr;
	ilock(ctlr);
	if(!ctlr->active){
		malrxenable(ctlr->rx);
		maltxenable(ctlr->tx);
		eieio();
		ctlr->regs->mr0 = Mr0Txe | Mr0Rxe;
		eieio();
		ctlr->active = 1;
	}
	iunlock(ctlr);
}

static void
closed(Ether *ether)
{
	Ctlr *ctlr;

	ctlr = ether->ctlr;
	if(ctlr->active){
		ilock(ctlr);
iprint("ether closed\n");
		ctlr->regs->mr0 &= ~(Mr0Txe | Mr0Rxe);	/* reset enable bits */
		/* TO DO: reset ring */
		/* TO DO: could wait */
		ctlr->active = 0;
		iunlock(ctlr);
	}
}

static void
promiscuous(void* arg, int on)
{
	Ether *ether;
	Ctlr *ctlr;

	ether = (Ether*)arg;
	ctlr = ether->ctlr;

	ilock(ctlr);
	if(on || ether->nmaddr)
		ctlr->regs->rmr |= RmrPme | RmrPmme;
	else
		ctlr->regs->rmr &= ~(RmrPme | RmrPmme);
	iunlock(ctlr);
}

static void
multicast(void* arg, uchar *addr, int on)
{
	Ether *ether;
	Ctlr *ctlr;

	USED(addr, on);	/* if on, could SetGroupAddress; if !on, it's hard */

	ether = (Ether*)arg;
	ctlr = ether->ctlr;

	ilock(ctlr);
	if(ether->prom || ether->nmaddr)
		ctlr->regs->rmr |= RmrPmme;
	else
		ctlr->regs->rmr &= ~RmrPmme;
	iunlock(ctlr);
}

static void
txstart(Ether *ether)
{
	int len;
	Ctlr *ctlr;
	Block *b;
	BD *dre;

	ctlr = ether->ctlr;
	while(ctlr->ntq < ctlr->ntdre-1){
		b = qget(ether->oq);
		if(b == 0)
			break;

		dre = &ctlr->tdr[ctlr->tdrh];
		if(dre->status & BDReady)
			panic("ether: txstart");

		/*
		 * Give ownership of the descriptor to the chip, increment the
		 * software ring descriptor pointer and tell the chip to poll.
		 */
		len = BLEN(b);
		if(ctlr->txb[ctlr->tdrh] != nil)
			panic("etheremac: txstart");
		ctlr->txb[ctlr->tdrh] = b;
		dre->addr = PADDR(b->rp);
		dre->length = len;
		dcflush(b->rp, len);
		eieio();
		dre->status = (dre->status & BDWrap) | BDReady|BDInt|BDLast|TxFCS|TxPad;
		eieio();
		ctlr->regs->tmr0 = Tmr0Gnp0;	/* TO DO: several channels */
		eieio();
		ctlr->ntq++;
		ctlr->tdrh = NEXT(ctlr->tdrh, ctlr->ntdre);
	}
}

static void
transmit(Ether* ether)
{
	Ctlr *ctlr;

	ctlr = ether->ctlr;
	ilock(ctlr);
	txstart(ether);
	iunlock(ctlr);
}

/*
 * allocate receive buffer space on cache-line boundaries
 */
static Block*
clallocb(void)
{
	Block *b;

	b = iallocb(Bufsize+CACHELINESZ-1);
	if(b == nil)
		return b;
	dcflush(b->base, BALLOC(b));
	b->wp = b->rp = (uchar*)(((ulong)b->base + CACHELINESZ - 1) & ~(CACHELINESZ-1));
	return b;
}


static void
rxring(Ureg*, void *arg)
{
	Ether *ether;
	ulong status;
	Ctlr *ctlr;
	BD *dre;
	Block *b, *rb;

	ether = arg;
	ctlr = ether->ctlr;
	ctlr->interrupts++;

	/*
	 * Receiver interrupt: run round the descriptor ring logging
	 * errors and passing valid receive data up to the higher levels
	 * until we encounter a descriptor still owned by the chip.
	 * We rely on the descriptor accesses being uncached.
	 */
	dre = &ctlr->rdr[ctlr->rdrx];
	while(((status = dre->status) & BDEmpty) == 0){
		if(status & RxError || (status & (BDFirst|BDLast)) != (BDFirst|BDLast)){
			if(status & (RxShort|RxLong))
				ether->buffs++;
			if(status & (RxBad|RxAlign|RxRange|RxInRange))
				ether->frames++;
			if(status & RxFCS)
				ether->crcs++;
			if(status & RxOverrun)
				ether->overflows++;
			iprint("eth rx: %lux\n", status);
		}else if((status & RxPause) == 0){
			/*
			 * We have a packet. Read it in.
			 */
			b = clallocb();
			if(b != nil){
				rb = ctlr->rxb[ctlr->rdrx];
				rb->wp += dre->length;
				ctlr->rxb[ctlr->rdrx] = b;
				ctlr->rdr[ctlr->rdrx].addr = PADDR(b->wp);
				etheriq(ether, rb, 1);
			}else
				ether->soverflows++;
		}

		/*
		 * Finished with this descriptor, reinitialise it,
		 * give it back to the chip, then on to the next...
		 */
		dre->status = (status & BDWrap) | BDEmpty | BDInt;
		eieio();

		ctlr->rdrx = NEXT(ctlr->rdrx, ctlr->nrdre);
		dre = &ctlr->rdr[ctlr->rdrx];
	}
}

static void
txring(Ureg*, void *arg)
{
	Ether *ether;
	ulong status;
	Ctlr *ctlr;
	BD *dre;
	Block *b;

	ether = arg;
	ctlr = ether->ctlr;
	ctlr->interrupts++;

	/*
	 * Transmitter interrupt: handle anything queued for a free descriptor.
	 */
	lock(ctlr);
	while(ctlr->ntq){
		dre = &ctlr->tdr[ctlr->tdri];
		status = dre->status;
		if(status & BDReady)
			break;
		if(status & TxEDef)
			ctlr->deferred++;
		if(status & TxLateCol)
			ctlr->latecoll++;
		if(status & TxECol)
			ctlr->retrylim++;
		if(status & TxUnderrun)
			ctlr->underrun++;
		if(status & (TxManyCol|TxCollision))
			ctlr->retrycount++;
		b = ctlr->txb[ctlr->tdri];
		if(b == nil)
			panic("etheremac: bufp");
		ctlr->txb[ctlr->tdri] = nil;
		freeb(b);
		ctlr->ntq--;
		ctlr->tdri = NEXT(ctlr->tdri, ctlr->ntdre);
	}
	txstart(ether);
	unlock(ctlr);
}

static void
interrupt(Ureg*, void *arg)
{
	Ether *ether;
	ulong events;
	Ctlr *ctlr;

	ether = arg;
	ctlr = ether->ctlr;

	events = ctlr->regs->isr;
	eieio();
	ctlr->regs->isr = events;
	eieio();
	ctlr->interrupts++;
//iprint("eth: %8.8lux\n", events);
	if(!ctlr->active || events == 0)
		return;

	if(events & IsrOvr)
		ctlr->overrun++;
	if(events & (IsrTe0|IsrTe1))
		ether->oerrs++;

	rxring(nil, arg);
	txring(nil, arg);
	ctlr->interrupts -= 2;

	/* TO DO: restart tx/rx on error */
}

static long
ifstat(Ether* ether, void* a, long n, ulong offset)
{
	char *p;
	int len;
	Ctlr *ctlr;

	if(n == 0)
		return 0;

	ctlr = ether->ctlr;

	p = malloc(READSTR);
	len = snprint(p, READSTR, "interrupts: %lud\n", ctlr->interrupts);
	len += snprint(p+len, READSTR-len, "carrierlost: %lud\n", ctlr->carrierlost);
	len += snprint(p+len, READSTR-len, "heartbeat: %lud\n", ctlr->heartbeat);
	len += snprint(p+len, READSTR-len, "retrylimit: %lud\n", ctlr->retrylim);
	len += snprint(p+len, READSTR-len, "retrycount: %lud\n", ctlr->retrycount);
	len += snprint(p+len, READSTR-len, "latecollisions: %lud\n", ctlr->latecoll);
	len += snprint(p+len, READSTR-len, "rxoverruns: %lud\n", ctlr->overrun);
	len += snprint(p+len, READSTR-len, "txunderruns: %lud\n", ctlr->underrun);
	snprint(p+len, READSTR-len, "framesdeferred: %lud\n", ctlr->deferred);
	n = readstr(offset, a, n, p);
	free(p);

	return n;
}

static QLock miilock;	/* the PHY are both on EMAC0's MII bus */

static int
miird(Mii *mii, int pa, int ra)
{
	Ctlr *ctlr;
	Emac *em;
	ulong r;
	int i;

	if(up)
		qlock(&miilock);
	ctlr = mii->ctlr;
	em = ctlr->miiregs;
	MIIDBG("r: %x.%x:", pa, ra);
	if((em->stacr & StaOc) == 0)
		iprint("mii-not oc\n");
	em->stacr = StaRead | StaOpb66 | (pa<<5) | ra;
	for(i=0; i<100 && (em->stacr & StaOc) == 0; i++)
		microdelay(1);
	r = em->stacr;
	if(up)
		qunlock(&miilock);
	if((r & StaOc) == 0)
		iprint("mii'-not oc\n");
	if(r & StaPhye)
		return -1;
	MIIDBG(" %8.8lux\n", r);
	return r >> 16;
}

static int
miiwr(Mii *mii, int pa, int ra, int v)
{
	Ctlr *ctlr;
	Emac *em;
	ulong r;
	int i;

	if(up)
		qlock(&miilock);
	ctlr = mii->ctlr;
	em = ctlr->miiregs;
	if((em->stacr & StaOc) == 0)
		iprint("miiw-not oc\n");
	em->stacr = (v<<16) | StaWrite | StaOpb66 | (pa<<5) | ra;
	for(i=0; i<100 && (em->stacr & StaOc) == 0; i++)
		microdelay(1);
	r = em->stacr;
	if(up)
		qunlock(&miilock);
	if((r & StaOc) == 0)
		iprint("miiw'-not oc\n");
	if(r & StaPhye)
		return -1;
	MIIDBG("w: %x.%x: %8.8lux\n", pa, ra, r);
	return 0;
}

static int
emacmii(Ctlr *ctlr)
{
	MiiPhy *phy;
	int i;

	MIIDBG("mii\n");
	if((ctlr->mii = malloc(sizeof(Mii))) == nil)
		return -1;
	ctlr->mii->ctlr = ctlr;
	ctlr->mii->mir = miird;
	ctlr->mii->miw = miiwr;

	if(mii(ctlr->mii, 1<<(ctlr->port+1)) == 0 || (phy = ctlr->mii->curphy) == nil){
		free(ctlr->mii);
		ctlr->mii = nil;
		return -1;
	}

	iprint("oui %X phyno %d\n", phy->oui, phy->phyno);
	if(miistatus(ctlr->mii) < 0){

		miireset(ctlr->mii);
		MIIDBG("miireset\n");
		if(miiane(ctlr->mii, ~0, 0, ~0) < 0){
			iprint("miiane failed\n");
			return -1;
		}
		MIIDBG("miistatus...\n");
		miistatus(ctlr->mii);
		if(miird(ctlr->mii, phy->phyno, Bmsr) & BmsrLs){
			for(i=0;; i++){
				if(i > 600){
					iprint("emac%d: autonegotiation failed\n", ctlr->port);
					break;
				}
				if(miird(ctlr->mii, phy->phyno, Bmsr) & BmsrAnc)
					break;
				delay(10);
			}
			if(miistatus(ctlr->mii) < 0)
				iprint("miistatus failed\n");
		}else{
			iprint("emac%d: no link\n", ctlr->port);
			phy->speed = 10;	/* simple default */
		}
	}

	iprint("emac%d mii: fd=%d speed=%d tfc=%d rfc=%d\n", ctlr->port, phy->fd, phy->speed, phy->tfc, phy->rfc);

	MIIDBG("mii done\n");

	return 0;
}

static void
emacsetup(Ctlr *ctlr, Ether *ether)
{
	int i;
	Emac *em;
	ulong mode;
	MiiPhy *phy;

	/* apparently don't need to set any Alt1 in GPIO */

	em = ctlr->regs;

	/* errata emac_8 */
	if(em->mr0 & Mr0Rxe){	/* probably never happens in our config */
		em->mr0 &= ~Mr0Rxe;
		eieio();
		for(i=0; (em->mr0 & Mr0Rxi) == 0; i++){
			if(i > 100){
				iprint("ethermac: Rxe->Rxi timed out\n");
				break;	/* we'll try soft reset anyway */
			}
			microdelay(100);
		}
	}

	/* soft reset */
	em->mr0 = Mr0Srst;
	eieio();
	for(i=0; em->mr0 & Mr0Srst; i++){
		if(i > 20){
			iprint("ethermac: reset (PHY clocks not running?)");
			i=0;
		}
		microdelay(100);
	}
iprint("%d: rx=%8.8lux tx=%8.8lux\n", ctlr->port, PADDR(ctlr->rdr), PADDR(ctlr->tdr));
//if(ctlr->port)return;

	malrxinit(ctlr->rx, ctlr, Bufsize/16);
	maltxinit(ctlr->tx, ctlr);
	malrxreset(ctlr->rx);
	maltxreset(ctlr->tx);

	em->mr0 = 0;
	mode = Mr1Rfs4096 | Mr1Tfs2048 | Mr1Tr0mp;
	if(ctlr->mii != nil && (phy = ctlr->mii->curphy) != nil){
		if(phy->speed == 10){
			mode |= Mr1Mf10;
			if(phy->fd)
				mode |= Mr1Ist;
		}else
			mode |= Mr1Mf100 | Mr1Ist;
		if(phy->fd)
			mode |= Mr1Fde;
		/* errata emac_9 suggests not using integrated flow control (it's broken); so don't negotiate it */
		if(0 && (phy->rfc || phy->tfc))
			mode |= Mr1App | Mr1Eifc;
		ether->mbps = phy->speed;
		ether->fullduplex = phy->fd;
	}else{
		iprint("mii: didn't work: default 100FD\n");
		mode |= Mr1Mf100 | Mr1Ist | Mr1Fde;
		ether->mbps = 100;
		ether->fullduplex = 1;
	}
		
	em->mr1 = mode;
	em->tmr1 = (9<<Tmr1Trl_s) | (256<<Tmr1Tur_s);	/* TO DO: validate these sizes */
	em->rmr = RmrSp | RmrSfcs | RmrIae | RmrBae;
	em->iahr = (ether->ea[0]<<8) | ether->ea[1];
	em->ialr = (ether->ea[2]<<24) | (ether->ea[3]<<16) | (ether->ea[4]<<8) | ether->ea[5];
	em->vtpid = 0;
	em->vtci = 0;
	em->ptr = 1;		/* pause timer [Reset, T] */
	for(i=0; i<4; i++){
		em->iaht[i] = 0;	/* individual address hash table */
		em->gaht[i] = 0;	/* group address hash table */
	}
	em->ipgvr = (96/8)/3;	/* minimise bit times between packets */
	em->trtr = ((256/64)-1)<<TrtrTrt_s;		/* transmission threshold (probably could be smaller) */
	em->rwmr = (32<<RwmrRlwm_s) | (128<<RwmrRhwm_s);	/* receive low/high water mark (TO DO: check) */
	/* 0x0f002000? */
	//dumpemac(em);
	//dumpmal();
	eieio();
	em->isr = em->isr;		/* clear all events */
	eieio();
	em->iser = IsrOvr | IsrBp | IsrSe | IsrSe0 | IsrTe0 | IsrSe1 | IsrTe1;	/* enable various error interrupts */
	/* packet tx/rx interrupts come from MAL */
	eieio();

	/* tx/rx enable is deferred until attach */
}

static int
reset(Ether* ether)
{
	uchar ea[Eaddrlen];
	Ctlr *ctlr;
	int i;

	ioringreserve(Nrxchan, Nrdre, Ntxchan, Ntdre);

	/*
	 * Insist that the platform-specific code provide the Ethernet address
	 */
	memset(ea, 0, Eaddrlen);
	if(memcmp(ea, ether->ea, Eaddrlen) == 0){
		print("no ether address");
		return -1;
	}

	ctlr = malloc(sizeof(*ctlr));
	ctlr->port = ether->port;

	switch(ether->port){
	case 0:
		ctlr->regs = KADDR(PHYSEMAC0);
		ctlr->miiregs = ctlr->regs;
		ctlr->rx = malchannel(0, 0, rxring, ether);
		ctlr->tx = malchannel(0, 1, txring, ether);
		ether->irq = VectorEMAC0;
		break;
	case 1:
		ctlr->regs = KADDR(PHYSEMAC1);
		ctlr->miiregs = KADDR(PHYSEMAC0);	/* p. 19-41: ``only the MDIO interface for EMAC0 is pinned out'' */
		ctlr->rx = malchannel(1, 0, rxring, ether);
		ctlr->tx = malchannel(2, 1, txring, ether);
		ether->irq = VectorEMAC1;
		break;
	default:
		print("%s ether: no port %lud\n", ether->type, ether->port);
		free(ctlr);
		return -1;
	}

	if(emacmii(ctlr) < 0){
		free(ctlr);
		return -1;
	}

	ether->ctlr = ctlr;

	if(ioringinit(ctlr, Nrdre, Ntdre) < 0)	/* TO DO: there are two transmit rings*/
		panic("etheremac initring");

	for(i = 0; i < ctlr->nrdre; i++){
		ctlr->rxb[i] = clallocb();
		ctlr->rdr[i].addr = PADDR(ctlr->rxb[i]->wp);
	}

	emacsetup(ctlr, ether);

	ether->attach = attach;
	ether->closed = closed;
	ether->transmit = transmit;
	ether->interrupt = interrupt;	/* oddly, it's only error interrupts; see malchannel call above for tx/rx */
	ether->ifstat = ifstat;

	ether->arg = ether;
	ether->promiscuous = promiscuous;
	ether->multicast = multicast;

	return 0;
}

void
etheremaclink(void)
{
	addethercard("EMAC", reset);
}

static void
dumpemac(Emac *r)
{
	iprint("mr0=%8.8lux\n", r->mr0);		/* mode register 0 [see 19-48] */
	iprint("mr1=%8.8lux\n", r->mr1);		/* mode register 1 [Reset] */
	iprint("tmr0=%8.8lux\n", r->tmr0);	/* transmit mode register 0 [see 19-28] */
	iprint("tmr1=%8.8lux\n", r->tmr1);	/* transmit mode register 1 [see 19-28] */
	iprint("rmr=%8.8lux\n", r->rmr);		/* receive mode register [Reset] */
	iprint("isr=%8.8lux\n", r->isr);		/* interrupt status register [Always] */
	iprint("iser=%8.8lux\n", r->iser);		/* interrupt status enable register [Reset] */
	iprint("iahr=%8.8lux\n", r->iahr);		/* individual address high [Reset, R, T]*/
	iprint("ialr=%8.8lux\n", r->ialr);		/* individual address low [Reset, R, T] */
	iprint("vtpid=%8.8lux\n", r->vtpid);	/* VLAN Tag Protocol Identifier [Reset, R, T] */
	iprint("vtci=%8.8lux\n", r->vtci);		/* VLAN Tag Control Information [Reset, R, T] */
	iprint("ptr=%8.8lux\n", r->ptr);		/* pause timer [Reset, T] */
	iprint("lsah=%8.8lux\n", r->lsah);		/* last source address high */
	iprint("lsal=%8.8lux\n", r->lsal);		/* last source address low */
	iprint("ipgvr=%8.8lux\n", r->ipgvr);	/* inter-packet gap value [Reset, T] */
	iprint("stacr=%8.8lux\n", r->stacr);	/* STA control register [see 19-41] */
	iprint("trtr=%8.8lux\n", r->trtr);		/* transmit request threshold register [see 19-42] */
	iprint("rwmr=%8.8lux\n", r->rwmr);	/* receive low/high water mark [Reset] */
	iprint("octx=%8.8lux\n", r->octx);		/* bytes transmitted */
	iprint("ocrx=%8.8lux\n", r->ocrx);	/* bytes received */
}
