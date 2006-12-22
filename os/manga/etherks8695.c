/*
 * KS8695P ethernet
 *	WAN port, LAN port to 4-port switch
 */

#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "../port/error.h"
#include "../port/netif.h"

#include "etherif.h"
#include "ureg.h"

#define	DBG	if(0)iprint
#define	MIIDBG	if(0)iprint

enum {
	Nrdre		= 64,	/* receive descriptor ring entries */
	Ntdre		= 32,	/* transmit descriptor ring entries */

	Rbsize		= ROUNDUP(ETHERMAXTU+4, 4),		/* ring buffer size (+4 for CRC), must be multiple of 4 */
	Bufsize		= ROUNDUP(Rbsize, CACHELINESZ),	/* keep start and end at cache lines */
};

typedef struct DmaReg DmaReg;
struct DmaReg {
	ulong	dtxc;		/* transmit control register */
	ulong	drxc;	/* receive control register */
	ulong	dtsc;		/* transmit start command register */
	ulong	drsc;		/* receive start command register */
	ulong	tdlb;		/* transmit descriptor list base address */
	ulong	rdlb;		/* receive descriptor list base address */
	ulong	mal;		/* mac address low (4 bytes) */
	ulong	mah;		/* mac address high (2 bytes) */
	ulong	pad[0x80-0x20];

	/* pad to 0x80 for */
	ulong	maal[16][2];	/* additional mac addresses */
};

enum {
	/* dtxc */
	TxSoftReset=	1<<31,
	/* 29:24 is burst size in words; 0, 1, 2, 4, 8, 16, 32; 0=unlimited */
	TxUDPck=	1<<18,	/* generate UDP, TCP, IP check sum */
	TxTCPck=		1<<17,
	TxIPck=		1<<16,
	TxFCE=		1<<9,	/* transmit flow control enable */
	TxLB=		1<<8,	/* loop back */
	TxEP=		1<<2,	/* enable padding */
	TxCrc=		1<<1,	/* add CRC */
	TxEnable=	1<<0,	/* enable Tx block */

	/* drxc */
	/* 29:24 is burst size in words */
	RxUDPck=	1<<18,	/* check UDP, TCP, IP check sum */
	RxTCPck=		1<<17,
	RxIPck=		1<<16,
	RxFCE=		1<<9,	/* flow control enable */
	RxRB=		1<<6,	/* receive broadcast */
	RxRM=		1<<5,	/* receive multicast (including broadcast) */
	RxRU=		1<<4,	/* receive unicast */
	RxAE=		1<<3,	/* receive error frames */
	RxRA=		1<<2,	/* receive all */
	RxEnable=	1<<0,	/* enable Rx block */

};

typedef struct WanPhy WanPhy;
struct WanPhy {
	ulong	did;		/* device ID */
	ulong	rid;		/* revision ID */
	ulong	pad0;	/* miscellaneous control in plain 8695 (not P or X) */
	ulong	wmc;	/* WAN miscellaneous control */
	ulong	wppm;	/* phy power management */
	ulong	wpc;		/* phys ctl */
	ulong	wps;		/* phys status */
	ulong	pps;		/* phy power save */
};

enum {
	/* wmc */
	WAnc=	1<<30,	/* auto neg complete */
	WAnr=	1<<29,	/* auto neg restart */
	WAnaP=	1<<28,	/* advertise pause */
	WAna100FD=	1<<27,	/* advertise 100BASE-TX FD */
	WAna100HD=	1<<26,	/* advertise 100BASE-TX */
	WAna10FD=	1<<25,	/* advertise 10BASE-TX FD */
	WAna10HD=	1<<24,	/* advertise 10BASE-TX */
	WLs=	1<<23,	/* link status */
	WDs=	1<<22,	/* duplex status (resolved) */
	WSs=	1<<21,	/* speed status (resolved) */
	WLparP=	1<<20,	/* link partner pause */
	WLpar100FD=	1<<19,	/* link partner 100BASE-TX FD */
	WLpar100HD=	1<<18,
	WLpar10FD=	1<<17,
	WLpar10HD=	1<<16,
	WAnDis=	1<<15,	/* auto negotiation disable */
	WForce100=	1<<14,
	WForceFD=	1<<13,
	/* 6:4 LED1 select */
	/* 2:0 LED0 select */

	/* LED select */
	LedSpeed=	0,
	LedLink,
	LedFD,		/* full duplex */
	LedColl,		/* collision */
	LedTxRx,		/* activity */
	LedFDColl,	/* FD/collision */
	LedLinkTxRx,	/* link and activity */

	/* ppm */
	WLpbk=	1<<14,	/* local (MAC) loopback */
	WRlpblk=	1<<13,	/* remote (PHY) loopback */
	WPhyIso=	1<<12,	/* isolate PHY from MII and Tx+/Tx- */
	WPhyLink=	1<<10,	/* force link in PHY */
	WMdix=	1<<9,	/* =1, MDIX, =0, MDX */
	WFef=	1<<8,	/* far end fault */
	WAmdixp=	1<<7,	/* disable IEEE spec for auto-neg MDIX */
	WTxdis=	1<<6,	/* disable port's transmitter */
	WDfef=	1<<5,	/* disable far end fault detection */
	Wpd=	1<<4,	/* power down */
	WDmdx=	1<<3,	/* disable auto MDI/MDIX */
	WFmdx=	1<<2,	/* if auto disabled, force MDIX */
	WMlpbk=	1<<1,	/* local loopback */

	/* pps */
	Ppsm=	1<<0,	/* enable PHY power save mode */
};

#define	DMABURST(n)	((n)<<24)

typedef struct {
	Lock;
	int	port;
	int	init;
	int	active;
	int	reading;		/* device read process is active */
	ulong	anap;	/* auto negotiate result */
	DmaReg*	regs;
	WanPhy*	wphy;

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

static void	switchinit(uchar*);
static void switchdump(void);

static void
attach(Ether *ether)
{
	Ctlr *ctlr;

	ctlr = ether->ctlr;
	ilock(ctlr);
	if(!ctlr->active){
		/* TO DO: rx/tx enable */
		ctlr->regs->dtxc |= TxEnable;
		ctlr->regs->drxc |= RxEnable;
		microdelay(10);
		ctlr->regs->drsc = 1;	/* start read process */
		microdelay(10);
		ctlr->reading = (INTRREG->st & (1<<IRQwmrps)) == 0;
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
		ctlr->regs->dtxc &= ~TxEnable;
		ctlr->regs->drxc &= ~RxEnable;
		/* TO DO: reset ring? */
		/* TO DO: could wait? */
		ctlr->active = 0;
		iunlock(ctlr);
	}
}

static void
promiscuous(void* arg, int on)
{
	Ether *ether;
	Ctlr *ctlr;
	ulong w;

	ether = (Ether*)arg;
	ctlr = ether->ctlr;

	ilock(ctlr);
	/* TO DO: must disable reader */
	w = ctlr->regs->drxc;
	if(on != ((w&RxRA)!=0)){
		/* TO DO: must disable reader */
		ctlr->regs->drxc = w ^ RxRA;
		/* TO DO: restart reader */
	}
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
	/* TO DO: must disable reader */
	/* TO DO: use internal multicast tables? (probably needs LRU or some such) */
	if(ether->nmaddr)
		ctlr->regs->drxc |= RxRM;
	else
		ctlr->regs->drxc &= ~RxRM;
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
		if(dre->ctrl & BdBusy)
			panic("ether: txstart");

		/*
		 * Give ownership of the descriptor to the chip, increment the
		 * software ring descriptor pointer and tell the chip to poll.
		 */
		len = BLEN(b);
		if(ctlr->txb[ctlr->tdrh] != nil)
			panic("etherks8695: txstart");
		ctlr->txb[ctlr->tdrh] = b;
		dcflush(b->rp, len);
		dre->addr = PADDR(b->rp);
		dre->size = TxIC|TxFS|TxLS | len;
		dre->ctrl = BdBusy;
		ctlr->regs->dtsc = 1;	/* go for it */
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
	while(((status = dre->ctrl) & BdBusy) == 0){
		if(status & RxES || (status & (RxFS|RxLS)) != (RxFS|RxLS)){
			if(status & (RxRF|RxTL))
				ether->buffs++;
			if(status & RxRE)
				ether->frames++;
			if(status & RxCE)
				ether->crcs++;
			//if(status & RxOverrun)
			//	ether->overflows++;
			iprint("eth rx: %lux\n", status);
		}else{
			/*
			 * We have a packet. Read it in.
			 */
			b = clallocb();
			if(b != nil){
				rb = ctlr->rxb[ctlr->rdrx];
				rb->wp += (dre->ctrl & RxFL)-4;
				etheriq(ether, rb, 1);
				ctlr->rxb[ctlr->rdrx] = b;
				dre->addr = PADDR(b->wp);
			}else
				ether->soverflows++;
		}

		/*
		 * Finished with this descriptor,
		 * give it back to the chip, then on to the next...
		 */
		dre->ctrl = BdBusy;

		ctlr->rdrx = NEXT(ctlr->rdrx, ctlr->nrdre);
		dre = &ctlr->rdr[ctlr->rdrx];
	}
}

static void
txring(Ureg*, void *arg)
{
	Ether *ether;
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
		if(dre->ctrl & BdBusy)
			break;
		/* statistics are kept inside the device, but only for LAN */
		/* there seems to be no per-packet error status for transmission */
		b = ctlr->txb[ctlr->tdri];
		if(b == nil)
			panic("etherks8695: bufp");
		ctlr->txb[ctlr->tdri] = nil;
		freeb(b);
		ctlr->ntq--;
		ctlr->tdri = NEXT(ctlr->tdri, ctlr->ntdre);
	}
	txstart(ether);
	unlock(ctlr);
}

/*
 * receive buffer unavailable (overrun)
 */
static void
rbuintr(Ureg*, void *arg)
{
	Ether *ether;
	Ctlr *ctlr;

	ether = arg;
	ctlr = ether->ctlr;

	ctlr->interrupts++;
	if(ctlr->active)
		ctlr->overrun++;
	ctlr->reading = 0;
}

/*
 * read process (in device) stopped
 */
static void
rxstopintr(Ureg*, void *arg)
{
	Ether *ether;
	Ctlr *ctlr;

	ether = arg;
	ctlr = ether->ctlr;

	ctlr->interrupts++;
	if(!ctlr->active)
		return;

iprint("rxstopintr\n");
	ctlr->regs->drsc = 1;
	/* just restart it?  need to fiddle with ring? */
}

static void
txstopintr(Ureg*, void *arg)
{
	Ether *ether;
	Ctlr *ctlr;

	ether = arg;
	ctlr = ether->ctlr;

	ctlr->interrupts++;
	if(!ctlr->active)
		return;

iprint("txstopintr\n");
	ctlr->regs->dtsc = 1;
	/* just restart it?  need to fiddle with ring? */
}


static void
linkchangeintr(Ureg*, void*)
{
	iprint("link change\n");
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
{DmaReg *d = ctlr->regs; len += snprint(p+len, READSTR-len, "dtxc=%8.8lux drxc=%8.8lux\n", d->dtxc, d->drxc);}
	snprint(p+len, READSTR-len, "framesdeferred: %lud\n", ctlr->deferred);
	n = readstr(offset, a, n, p);
	free(p);

	if(ctlr->port == 1)
		switchdump();
	return n;
}

static void
physinit(Ether *ether, int force)
{
	Ctlr *ctlr;
	WanPhy *p;
	ulong anap;
	int i;

	ctlr = ether->ctlr;
	p = ctlr->wphy;
	if(p == nil){
		if(ctlr->port){
			ether->mbps = 100;
			ether->fullduplex = 1;
			switchinit(nil);
		}
		return;
	}
	iprint("phy%d: wmc=%8.8lux wpm=%8.8lux wpc=%8.8lux wps=%8.8lux pps=%8.8lux\n", ctlr->port, p->wmc, p->wppm, p->wpc, p->wps, p->pps);

	p->wppm = 0;	/* enable power, other defaults seem fine */
	if(p->rid & 7)
		p->wpc = 0x0200b000;	/* magic */
	else
		p->wpc = 0xb000;
	if(p->wppm & WFef)
		iprint("ether%d: far end fault\n", ctlr->port);

	if((p->wmc & WLs) == 0){
		iprint("ether%d: no link\n", ctlr->port);
		ether->mbps = 100;	/* could use 10, but this is 2005 */
		ether->fullduplex = 0;
		return;
	}

	if((p->wmc & WAnc) == 0 || force){
		p->wmc = WAnr | WAnaP | WAna100FD | WAna100HD | WAna10FD | WAna10HD | (p->wmc & 0x7F);
		microdelay(10);
		if(p->wmc & WLs){
			for(i=0;; i++){
				if(i > 600){
					iprint("ether%d: auto negotiation failed\n", ctlr->port);
					ether->mbps = 10;	/* we'll assume it's stupid */
					ether->fullduplex = 0;
					return;
				}
				if(p->wmc & WAnc){
					microdelay(10);
					break;
				}
				delay(1);
			}
		}
	}
	anap = p->wmc;
	ether->mbps = anap & WSs? 100: 10;
	if(anap & (WLpar100FD|WLpar10FD) && anap & WDs)
		ether->fullduplex = 1;
	else
		ether->fullduplex = 0;
	ctlr->anap = anap;

	iprint("ks8695%d mii: fd=%d speed=%d wmc=%8.8lux\n", ctlr->port, ether->fullduplex, ether->mbps, anap);
}

static void
ctlrinit(Ctlr *ctlr, Ether *ether)
{
	int i;
	DmaReg *em;
	ulong mode;

	em = ctlr->regs;

	/* soft reset */
	em->dtxc = TxSoftReset;
	microdelay(10);
	for(i=0; em->dtxc & TxSoftReset; i++){
		if(i > 20){
			iprint("etherks8695.%d: soft reset failed\n", ctlr->port);
			i=0;
		}
		microdelay(100);
	}
iprint("%d: rx=%8.8lux tx=%8.8lux\n", ctlr->port, PADDR(ctlr->rdr), PADDR(ctlr->tdr));

	physinit(ether, 0);

	/* set ether address */
	em->mah = (ether->ea[0]<<8) | ether->ea[1];
	em->mal = (ether->ea[2]<<24) | (ether->ea[3]<<16) | (ether->ea[4]<<8) | ether->ea[5];
	if(ctlr->port == 0){
		/* clear other addresses for now */
		for(i=0; i<nelem(em->maal); i++){
			em->maal[i][0] = 0;
			em->maal[i][1] = 0;
		}
	}

	/* transmitter, enabled later by attach  */
	em->tdlb = PADDR(ctlr->tdr);
	em->dtxc = DMABURST(8) | TxFCE | TxCrc;	/* don't set TxEP: there is a h/w bug and it's anyway done by higher levels */

	/* receiver, enabled later by attach */
	em->rdlb = PADDR(ctlr->rdr);
	mode = DMABURST(8) | RxRB | RxRU | RxAE;	/* RxAE just there for testing */
	if(ether->fullduplex)
		mode |= RxFCE;
	em->drxc = mode;

	/* tx/rx enable is deferred until attach */
}

static int
reset(Ether* ether)
{
	uchar ea[Eaddrlen];
	char name[KNAMELEN];
	Ctlr *ctlr;
	int i, irqdelta;

	snprint(name, sizeof(name), "ether%d", ether->ctlrno);

	/*
	 * Insist that the platform-specific code provide the Ethernet address
	 */
	memset(ea, 0, Eaddrlen);
	if(memcmp(ea, ether->ea, Eaddrlen) == 0){
		print("%s (%s %ld): no ether address", name, ether->type, ether->port);
		return -1;
	}

	ctlr = malloc(sizeof(*ctlr));
	ctlr->port = ether->port;

	switch(ether->port){
	case 0:
		ctlr->regs = KADDR(PHYSWANDMA);
		ctlr->wphy = KADDR(PHYSMISC);
		ctlr->wphy->wmc = (ctlr->wphy->wmc & ~0x7F) | (LedLinkTxRx<<0) | (LedSpeed<<4);
		break;
	case 1:
		ctlr->regs = KADDR(PHYSLANDMA);
		ctlr->wphy = nil;
		break;
	default:
		print("%s: %s ether: no port %lud\n", name, ether->type, ether->port);
		free(ctlr);
		return -1;
	}

	ether->ctlr = ctlr;
	irqdelta = ether->irq - IRQwmrps;

	physinit(ether, 0);

	if(ioringinit(ctlr, Nrdre, Ntdre) < 0)
		panic("etherks8695 initring");

	for(i = 0; i < ctlr->nrdre; i++){
		if(ctlr->rxb[i] == nil)
			ctlr->rxb[i] = clallocb();
		ctlr->rdr[i].addr = PADDR(ctlr->rxb[i]->wp);
		ctlr->rdr[i].size = Rbsize;
		ctlr->rdr[i].ctrl = BdBusy;
	}

	ctlrinit(ctlr, ether);

	ether->attach = attach;
	ether->closed = closed;
	ether->transmit = transmit;
	ether->ifstat = ifstat;

	/* there is more than one interrupt: we must enable some ourselves */
	ether->irq = irqdelta + IRQwmrs;	/* set main IRQ to receive status */
	ether->interrupt = rxring;
	intrenable(IRQ, irqdelta+IRQwmts, txring, ether, "ethertx");
//	intrenable(IRQ, irqdelta+IRQwmtbu, tbuintr, ether, "ethertbu");	/* don't care? */
	intrenable(IRQ, irqdelta+IRQwmrbu, rbuintr, ether, "etherrbu");
	intrenable(IRQ, irqdelta+IRQwmrps, rxstopintr, ether, "etherrps");
	intrenable(IRQ, irqdelta+IRQwmtps, txstopintr, ether, "ethertps");
	if(ether->port == 0)
		intrenable(IRQ, IRQwmlc, linkchangeintr, ether, "etherwanlink");

	ether->arg = ether;
	ether->promiscuous = promiscuous;
	ether->multicast = multicast;

	return 0;
}

/*
 * switch engine registers
 *	a 10 microsecond delay is required after each (write?) access
 */
typedef struct Switch Switch;
struct Switch {
	ulong	sec0;	/* control register 0 */
	ulong	sec1;	/* control register 1 */
	ulong	sec2;	/* control register 2, factory default, do not change */
	ulong	cfg[5][3];		/* port configuration registers */
	ulong	an[2];	/* ports 1 to 4 auto negotiation [1,2][3,4] */
	ulong	seiac;	/* indirect access control register */
	ulong	seiadh2;	/* indirect access data register 2 (4:0 is 68-64 of data) */
	ulong	seiadh1;	/* indirect access data register 1 (63-32 of data) */
	ulong	seiadl;	/* indirect access data register low */
	ulong	seafc;	/* advanced feature control */
	ulong	scph;	/* services code priority high (ie, TOS priority) */
	ulong	scpl;		/* services code priority low */
	ulong	mah;		/* switch MAC address high */
	ulong	mal;		/* switch MAC address low */
	ulong	ppm[2];	/* ports 1 to 4 PHY power management */
};

enum {
	/* Sec0 */
	Nbe=	1<<31,	/* new backoff (designed for UNH) enable */
	/* 30:28 802.1p base priority */
	/* 27:25 LAN LED1 select */
	/* 24:22 LAN LED0 select */
	Unh=	1<<21,	/* =1, drop packets with type 8808 or DA=0180c2000001; =0, drop flow control */
	Lca=		1<<20,	/* link change age: faster aging for link->no link transition */
	Paf=		1<<19,	/* pass all frames, including bad ones */
	Sfce=	1<<18,	/* switch MII full-duplex flow control enable */
	Flfc=		1<<17,	/* frame length field check in IEEE (drop invalid ones) */
	Bsm=	1<<16,	/* =1, share all buffers; =0, use only 1/5 of pool */
	Age=	1<<15,	/* enable age function */
	Agef=	1<<14,	/* enable fast ageing */
	Aboe=	1<<13,	/* aggressive backoff enable */
	Uvmd=	1<<12,	/* unicast port-VLAN mismatch discard */
	Mspd=	1<<11,	/* multicast storm protection disable */
	Bpm=	1<<10,	/* =1, carrier sense backpressure; =0, collision backpressure */
	Fair=		1<<9,	/* fair flow control and back pressure */
	Ncd=	1<<8,	/* no excessive collision drop */
	Lmpsd=	1<<7,	/* 1=, drop packet sizes over 1536 bytes; =0, 1522 for tagged, 1518 untagged */
	Pbr=		1<<6,	/* priority buffer reserved */
	Sbpe=	1<<5,	/* switch back pressure enable */
	Shdm=	1<<4,	/* switch half duplex mode */
	PrioHi=	0<<2,	/* always deliver high priority first */
	Prio10_1= 1<<2,	/* high/low at 10:1 */
	Prio5_1=	2<<2,	/* high/low at 5:1 */
	Prio2_1=	3<<2,	/* high/low at 2:1 */
	Etm=	1<<1,	/* enable tag mask */
	Esf=		1<<0,	/* enable switch function */

	/* sec1 */
	/* 31:21 */	/* broadcast storm protection, byte count */
	IEEEneg=	1<<11,	/* follow IEEE spec for auto neg */
	Tpid=	1<<10,	/* special TPID mode used for direct forwarding from port 5 */
	PhyEn=	1<<8,	/* enable PHY MII */
	TfcDis=	1<<7,	/* disable IEEE transmit flow control */
	RfcDis=	1<<6,	/* disable IEEE receive flow control */
	Hps=	1<<5,	/* huge packet support: allow packets up to 1916 bytes */
	VlanEn=	1<<4,	/* 802.1Q VLAN enable; recommended when priority queue on */
	Sw10BT=	1<<1,	/* switch in 10 Mbps mode not 100 Mbps */
	VIDrep=	1<<0,	/* replace null VID with port VID (otherwise no replacement) */

};
#define	BASEPRIO(n)	(((n)&7)<<28)


enum {
	/* cfg[n][0] (SEP1C1-SEP4C1) p. 89 */
	/* 31:16	default tag: 31:29=userprio, 28=CFI bit, 27:16=VID[11:0] */
	AnegDis=	1<<15,	/* disable auto negotiation */
	Force100=	1<<14,	/* force 100BT when auto neg is disabled */
	ForceFD=	1<<13,	/* force full duplex when auto neg is disabled */
	/* 12:8	port VLAN membership: bit 8 is port 1, bit 12 is port 5, 1=member */
	STTxEn=	1<<7,	/* spanning tree transmit enable */
	STRxEn=	1<<6,	/* spanning tree receive enable */
	STLnDis=	1<<5,	/* spanning tree learn disnable */
	Bsp=		1<<4,	/* enable broadcast storm protection */
	Pce=		1<<3,	/* priority classification enable */
	Dpce=	1<<2,	/* diffserv priority classification enable */
	IEEEpce=	1<<1,	/* IEEE (802.1p) classification enable */
	PrioEn=	1<<0,	/* enable priority function on port */

	/* cfg[n][1] (SEP1C2-SEP4C2) p. 91*/
	IngressFilter=	1<<28,	/* discard packets from ingress port not in VLAN */
	DiscardNonPVID=	1<<27,	/* discard packets whose VID does not match port default VID */
	ForcePortFC=	1<<26,	/* force flow control */
	EnablePortBP=	1<<25,	/* enable back pressure */
	/* 23:12 transmit high priority rate control */
	/* 11:0 transmit low priority rate control */

	/* cfg[n][2] */
	/* 13:20	receive high priority rate control */
	/* 19:8	receive low priority rate control */
	Rdprc=	1<<7,	/* receive differential priority rate control */
	Lprrc=	1<<6,	/* low priority receive rate control */
	Hprrc=	1<<5,	/* high priority receive rate control */
	Lprfce=	1<<4,	/* low priority receive flow control enable */
	Hprfce=	1<<3,	/* high priority ... */
	Tdprc=	1<<2,	/* transmit differential priority rate control */
	Lptrc=	1<<1,	/* low priority transmit rate control */
	Hptrc=	1<<0,	/* high priority transmit rate control */

	/* seiac */
	Cread=	1<<12,
	Cwrite=	0<<12,
	  StaticMacs=	0<<10,	/* static mac address table used */
	  VLANs=		1<<10,	/* VLAN table */
	  DynMacs=	2<<10,	/* dynamic address table */
	  MibCounter=	3<<10,	/* MIB counter selected */
	/* 0:9, table index */

	/* seafc */
	/* 26:22	1<<(n+22-1) = removal for port 0 to 4 */
};

/*
 * indirect access to
 *	static MAC address table (3.10.23, p. 107)
 *	VLAN table (3.10.24, p. 108)
 *	dynamic MAC address table (3.10.25, p. 109)
 *	MIB counters (3.10.26, p. 110)
 */
enum {
	/* VLAN table */
	VlanValid=	1<<21,	/* entry is valid */
	/* 20:16 are bits for VLAN membership */
	/* 15:12 are bits for FID (filter id) for up to 16 active VLANs */
	/* 11:0 has 802.1Q 12 bit VLAN ID */

	/* Dynamic MAC table (1024 entries) */
	MACempty=	1<<(68-2*32),
	/* 67:58 is number of valid entries-1 */
	/* 57:56 ageing time stamp */
	NotReady=	1<<(55-32),
	/* 54:52 source port 0 to 5 */
	/* 51:48 FID */
	/* 47:0 MAC */

	NVlans=	16,
	NSMacs=	8,
};

/*
 * per-port counters, table 3, 3.10.26, p. 110
 * cleared when read
 * port counters at n*0x20 [n=0-3]
 */
static char* portmibnames[] = {
	"RxLoPriorityByte",
	"RxHiPriorityByte",
	"RxUndersizePkt",
	"RxFragments",
	"RxOversize",
	"RxJabbers",
	"RxSymbolError",
	"RxCRCerror",
	"RxAlignmentError",
	"RxControl8808Pkts",
	"RxPausePkts",
	"RxBroadcast",
	"RxMulticast",
	"RxUnicast",
	"Rx64Octets",
	"Rx65to127Octets",
	"Rx128to255Octets",
	"Rx256to511Octets",
	"Rx512to1023Octets",
	"Rx1024to1522Octets",
	"TxLoPriorityByte",
	"TxHiPriorityByte",
	"TxLateCollision",
	"TxPausePkts",
	"TxBroadcastPkts",
	"TxMulticastPkts",
	"TxUnicastPkts",
	"TxDeferred",
	"TxTotalCollision",	/* like, totally */
	"TxExcessiveCollision",
	"TxSingleCollision",
	"TxMultipleCollision",
};
enum {
	/* per-port MIB counter format */
	MibOverflow=	1<<31,
	MibValid=		1<<30,
	/* 29:0 counter value */
};

/*
 * 16 bit `all port' counters, not automatically cleared
 *	offset 0x100 and up
 */

static char* allportnames[] = {
	"Port1TxDropPackets",
	"Port2TxDropPackets",
	"Port3TxDropPackets",
	"Port4TxDropPackets",
	"LanTxDropPackets",	/* ie, internal port 5 */
	"Port1RxDropPackets",
	"Port2RxDropPackets",
	"Port3RxDropPackets",
	"Port4RxDropPackets",
	"LanRxDropPackets",
};

static void
switchinit(uchar *ea)
{
	Switch *sw;
	int i;
	ulong an;

	/* TO DO: LED gpio setting */

	GPIOREG->iopm |= 0xF0;	/* bits 4-7 are LAN(?) */
iprint("switch init...\n");
	sw = KADDR(PHYSSWITCH);
	if(sw->sec0 & Esf){
		iprint("already inited\n");
		return;
	}
	sw->seafc = 0;
	microdelay(10);
	sw->scph = 0;
	microdelay(10);
	sw->scpl = 0;
	microdelay(10);
	if(ea != nil){
		sw->mah = (ea[0]<<8) | ea[1];
		microdelay(10);
		sw->mal = (ea[2]<<24) | (ea[3]<<16) | (ea[4]<<8) | ea[5];
		microdelay(10);
	}
	for(i = 0; i < 5; i++){
		sw->cfg[i][0] = (0x1F<<8) | STTxEn | STRxEn | Bsp;	/* port is member of all vlans */
		microdelay(10);
		sw->cfg[i][1] = 0;
		microdelay(10);
		sw->cfg[i][2] = 0;
		microdelay(10);
	}
	sw->ppm[0] = 0;	/* perhaps soft reset? */
	microdelay(10);
	sw->ppm[1] = 0;
	microdelay(10);
	an = WAnr | WAnaP | WAna100FD | WAna100HD | WAna10FD | WAna10HD;
	sw->an[0] = an | (an >> 16);
	microdelay(10);
	sw->an[1] = an | (an >> 16);
	microdelay(10);
	sw->sec1 = (0x4A<<21) | PhyEn;
	microdelay(10);
	sw->sec0 = Nbe | (0<<28) | (LedSpeed<<25) | (LedLinkTxRx<<22) | Sfce | Bsm | Age | Aboe | Bpm | Fair | Sbpe | Shdm | Esf;
	microdelay(10);

	/* off we go */
}

typedef struct Vidmap Vidmap;
struct Vidmap {
	uchar	ports;	/* bit mask for ports 0 to 4 */
	uchar	fid;	/* switch's filter id */
	ushort	vid;	/* 802.1Q vlan id; 0=not valid */
};

static Vidmap
getvidmap(Switch *sw, int i)
{
	ulong w;
	Vidmap v;

	v.ports = 0;
	v.fid = 0;
	v.vid = 0;
	if(i < 0 || i >= NVlans)
		return v;
	sw->seiac = Cread | VLANs | i;
	microdelay(10);
	w = sw->seiadl;
	if((w & VlanValid) == 0)
		return v;
	v.vid = w & 0xFFFF;
	v.fid = (w>>12) & 0xF;
	v.ports = (w>>16) & 0x1F;
	return v;
}

static void
putvidmap(Switch *sw, int i, Vidmap v)
{
	ulong w;

	w = ((v.ports & 0x1F)<<16) | ((v.fid & 0xF)<<12) | (v.vid & 0xFFFF);
	if(v.vid != 0)
		w |= VlanValid;
	sw->seiadl = w;
	microdelay(10);
	sw->seiac = Cwrite | VLANs | i;
	microdelay(10);
}

typedef struct StaticMac StaticMac;
struct StaticMac {
	uchar	valid;
	uchar	fid;
	uchar	usefid;
	uchar	override;	/* override spanning tree tx/rx disable */
	uchar	ports;	/* forward to this set of ports */
	uchar	mac[Eaddrlen];
};

static StaticMac
getstaticmac(Switch *sw, int i)
{
	StaticMac s;
	ulong w;

	memset(&s, 0, sizeof(s));
	if(i < 0 || i >= NSMacs)
		return s;
	sw->seiac = Cread | StaticMacs | i;
	microdelay(10);
	w = sw->seiadh1;
	if((w & (1<<(53-32))) == 0)
		return s;	/* entry not valid */
	s.valid = 1;
	s.fid= (w>>(57-32)) & 0xF;
	s.usefid = (w & (1<<(56-32))) != 0;
	s.override = (w & (1<<(54-32))) != 0;
	s.ports = (w>>(48-32)) & 0x1F;
	s.mac[5] = w >> 8;
	s.mac[4] = w;
	w = sw->seiadl;
	s.mac[3] = w>>24;
	s.mac[2] = w>>16;
	s.mac[1] = w>>8;
	s.mac[0] = w;
	return s;
}

static void
putstaticmac(Switch *sw, int i, StaticMac s)
{
	ulong w;

	if(s.valid){
		w = 1<<(53-32);	/* entry valid */
		if(s.usefid)
			w |= 1<<(55-32);
		if(s.override)
			w |= 1<<(54-32);
		w |= (s.fid & 0xF) << (56-32);
		w |= (s.ports & 0x1F) << (48-32);
		w |= (s.mac[5] << 8) | s.mac[4];
		sw->seiadh1 = w;
		microdelay(10);
		w = (s.mac[3]<<24) | (s.mac[2]<<16) | (s.mac[1]<<8) | s.mac[0];
		sw->seiadl = w;
		microdelay(10);
	}else{
		sw->seiadh1 = 0;	/* valid bit is 0; rest doesn't matter */
		microdelay(10);
	}
	sw->seiac = Cwrite | StaticMacs | i;
	microdelay(10);
}

typedef struct DynMac DynMac;
struct DynMac {
	ushort	nentry;
	uchar	valid;
	uchar	age;
	uchar	port;		/* source port (0 origin) */
	uchar	fid;		/* filter id */
	uchar	mac[Eaddrlen];
};

static DynMac
getdynmac(Switch *sw, int i)
{
	DynMac d;
	ulong w;
	int n, l;

	memset(&d, 0, sizeof d);
	l = 0;
	do{
		if(++l > 100)
			return d;
		sw->seiac = Cread | DynMacs | i;
		microdelay(10);
		w = sw->seiadh2;
		/* peculiar encoding of table size */
		if(w & MACempty)
			return d;
		n = w & 0xF;
		w = sw->seiadh1;
	}while(w & NotReady);	/* TO DO: how long might it delay? */
	d.nentry = ((n<<6) | (w>>(58-32))) + 1;
	if(i < 0 || i >= d.nentry)
		return d;
	d.valid = 1;
	d.age = (w>>(56-32)) & 3;
	d.port = (w>>(52-32)) & 7;
	d.fid = (w>>(48-32)) & 0xF;
	d.mac[5] = w>>8;
	d.mac[4] = w;
	w = sw->seiadl;
	d.mac[3] = w>>24;
	d.mac[2] = w>>16;
	d.mac[1] = w>>8;
	d.mac[0] = w;
	return d;
}

static void
switchdump(void)
{
	Switch *sw;
	int i, j;
	ulong w;

	sw = KADDR(PHYSSWITCH);
	iprint("sec0 %8.8lux\n", sw->sec0);
	iprint("sec1 %8.8lux\n", sw->sec1);
	for(i = 0; i < 5; i++){
		iprint("cfg%d", i);
		for(j = 0; j < 3; j++){
			w = sw->cfg[i][j];
			iprint(" %8.8lux", w);
		}
		iprint("\n");
		if(i < 2){
			w = sw->an[i];
			iprint(" an=%8.8lux pm=%8.8lux\n", w, sw->ppm[i]);
		}
	}
	for(i = 0; i < 8; i++){
		sw->seiac = Cread | DynMacs | i;
		microdelay(10);
		w = sw->seiadh2;
		microdelay(10);
		iprint("dyn%d: %8.8lux", i, w);
		w = sw->seiadh1;
		microdelay(10);
		iprint(" %8.8lux", w);
		w = sw->seiadl;
		microdelay(10);
		iprint(" %8.8lux\n", w);
	}
	for(i=0; i<0x20; i++){
		sw->seiac = Cread | MibCounter | i;
		microdelay(10);
		w = sw->seiadl;
		microdelay(10);
		if(w & (1<<30))
			iprint("%.2ux: %s: %lud\n", i, portmibnames[i], w & ~(3<<30));
	}
}

static void
switchstatproc(void*)
{
	for(;;){
		tsleep(&up->sleep, return0, nil, 30*1000);
	}
}

void
etherks8695link(void)
{
	addethercard("ks8695", reset);
}

/*
 * notes:
 *	switch control
 *	read stats every 30 seconds or so
 */
