/*
 * AM79C960
 * PCnet Single-Chip Ethernet Controller for ISA Bus
 * To do:
 *	only issue transmit interrupt if necessary?
 *	dynamically increase rings as necessary?
 *	use Blocks as receive buffers?
 *	currently hardwires 10Base-T
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

#define	chatty 1
#define	DPRINT	if(chatty)print

enum {
	Lognrdre	= 6,
	Nrdre		= (1<<Lognrdre),	/* receive descriptor ring entries */
	Logntdre	= 4,
	Ntdre		= (1<<Logntdre),	/* transmit descriptor ring entries */

	Rbsize		= ETHERMAXTU+4,		/* ring buffer size (+4 for CRC) */
};

enum {						/* I/O resource map */
	Aprom		= 0x0000,		/* physical address */
	Rdp		= 0x0010,		/* register data port */
	Rap		= 0x0012,		/* register address port */
	Sreset		= 0x0014,		/* software reset */
	/*Bdp		= 0x001C,		/* bus configuration register data port */
	Idp		= 0x0016,		/* ISA data port */
};

enum {						/* ISACSR2 */
	Isa10		= 0x0001,		/* 10base-T */
	Isamedia		= 0x0003,		/* media selection mask */
	Isaawake		= 0x0004,		/* Auto-Wake */
};

enum {						/* CSR0 */
	Init		= 0x0001,		/* begin initialisation */
	Strt		= 0x0002,		/* enable chip */
	Stop		= 0x0004,		/* disable chip */
	Tdmd		= 0x0008,		/* transmit demand */
	Txon		= 0x0010,		/* transmitter on */
	Rxon		= 0x0020,		/* receiver on */
	Iena		= 0x0040,		/* interrupt enable */
	Intr		= 0x0080,		/* interrupt flag */
	Idon		= 0x0100,		/* initialisation done */
	Tint		= 0x0200,		/* transmit interrupt */
	Rint		= 0x0400,		/* receive interrupt */
	Merr		= 0x0800,		/* memory error */
	Miss		= 0x1000,		/* missed frame */
	Cerr		= 0x2000,		/* collision */
	Babl		= 0x4000,		/* transmitter timeout */
	Err		= 0x8000,		/* Babl|Cerr|Miss|Merr */
};
	
enum {						/* CSR3 */
	Emba		= 0x0008,		/* enable modified back-off algorithm */
	Dxmt2pd		= 0x0010,		/* disable transmit two part deferral */
	Lappen		= 0x0020,		/* look-ahead packet processing enable */
	Idonm		= 0x0100,		/* initialisation done mask */
	Tintm		= 0x0200,		/* transmit interrupt mask */
	Rintm		= 0x0400,		/* receive interrupt mask */
	Merrm		= 0x0800,		/* memory error mask */
	Missm		= 0x1000,		/* missed frame mask */
	Bablm		= 0x4000,		/* babl mask */
};

enum {						/* CSR4 */
	ApadXmt		= 0x0800,		/* auto pad transmit */
};

enum {						/* CSR15 */
	Prom		= 0x8000,		/* promiscuous mode */
	TenBaseT		= 0x0080,		/* 10Base-T */
};

typedef struct {				/* Initialisation Block */
	ushort	mode;
	uchar	padr[6];
	uchar	ladr[8];
	ushort	rdra0;			/* bits 0-15 */
	uchar	rdra16;			/* bits 16-23 */
	uchar	rlen;				/* upper 3 bits */
	ushort	tdra0;			/* bits 0-15 */
	uchar	tdra16;			/* bits 16-23 */
	uchar	tlen;				/* upper 3 bits */
} Iblock;

typedef struct {				/* receive descriptor ring entry */
	ushort	rbadr;				/* buffer address 0-15 */
	ushort	rmd1;				/* status|buffer address 16-23 */
	ushort	rmd2;				/* bcnt */
	ushort	rmd3;				/* mcnt */
} Rdre;

typedef struct {				/* transmit descriptor ring entry */
	ushort	tbadr;				/* buffer address 0-15 */
	ushort	tmd1;				/* status|buffer address 16-23 */
	ushort	tmd2;				/* bcnt */
	ushort	tmd3;				/* errors */
} Tdre;

enum {						/* [RT]dre status bits */
	Enp		= 0x0100,		/* end of packet */
	Stp		= 0x0200,		/* start of packet */
	RxBuff		= 0x0400,		/* buffer error */
	TxDef		= 0x0400,		/* deferred */
	RxCrc		= 0x0800,		/* CRC error */
	TxOne		= 0x0800,		/* one retry needed */
	RxOflo		= 0x1000,		/* overflow error */
	TxMore		= 0x1000,		/* more than one retry needed */
	Fram		= 0x2000,		/* framing error */
	RxErr		= 0x4000,		/* Fram|Oflo|Crc|RxBuff */
	TxErr		= 0x4000,		/* Uflo|Lcol|Lcar|Rtry */
	Own			= 0x8000,
};

typedef struct {
	Lock;

	int	init;			/* initialisation in progress */
	Iblock	iblock;

	Rdre*	rdr;				/* receive descriptor ring */
	void*	rrb;				/* receive ring buffers */
	int	rdrx;				/* index into rdr */

	Tdre*	tdr;				/* transmit descriptor ring */
	void*	trb;				/* transmit ring buffers */
	int	tdrx;				/* index into tdr */
} Ctlr;

static void
attach(Ether* ether)
{
	Ctlr *ctlr;
	int port;

	ctlr = ether->ctlr;
	ilock(ctlr);
	if(ctlr->init){
		iunlock(ctlr);
		return;
	}
	port = ether->port;
	outs(port+Rdp, Iena|Strt);
	iunlock(ctlr);
}

static void
ringinit(Ctlr* ctlr)
{
	int i, x;

	/*
	 * Initialise the receive and transmit buffer rings. The ring
	 * entries must be aligned on 16-byte boundaries.
	 *
	 * This routine is protected by ctlr->init.
	 */
	if(ctlr->rdr == 0)
		ctlr->rdr = xspanalloc(Nrdre*sizeof(Rdre), 0x10, 0);
	if(ctlr->rrb == 0)
		ctlr->rrb = xalloc(Nrdre*Rbsize);

	x = PADDR(ctlr->rrb);
	if ((x >> 24)&0xFF)
		panic("ether79c960: address>24bit");
	for(i = 0; i < Nrdre; i++){
		ctlr->rdr[i].rbadr = x&0xFFFF;
		ctlr->rdr[i].rmd1 = Own|(x>>16)&0xFF;
		x += Rbsize;
		ctlr->rdr[i].rmd2 = 0xF000|-Rbsize&0x0FFF;
		ctlr->rdr[i].rmd3 = 0;
	}
	ctlr->rdrx = 0;

	if(ctlr->tdr == 0)
		ctlr->tdr = xspanalloc(Ntdre*sizeof(Tdre), 0x10, 0);
	if(ctlr->trb == 0)
		ctlr->trb = xalloc(Ntdre*Rbsize);

	x = PADDR(ctlr->trb);
	if ((x >> 24)&0xFF)
		panic("ether79c960: address>24bit");
	for(i = 0; i < Ntdre; i++){
		ctlr->tdr[i].tbadr = x&0xFFFF;
		ctlr->tdr[i].tmd1 = (x>>16)&0xFF;
		x += Rbsize;
		ctlr->tdr[i].tmd2 = 0xF000|-Rbsize&0x0FFF;
	}
	ctlr->tdrx = 0;
}

static void
promiscuous(void* arg, int on)
{
	Ether *ether;
	int port, x;
	Ctlr *ctlr;

	ether = arg;
	port = ether->port;
	ctlr = ether->ctlr;

	/*
	 * Put the chip into promiscuous mode. First we must wait until
	 * anyone transmitting is done, then we can stop the chip and put
	 * it in promiscuous mode. Restarting is made harder by the chip
	 * reloading the transmit and receive descriptor pointers with their
	 * base addresses when Strt is set (unlike the older Lance chip),
	 * so the rings must be re-initialised.
	 */
	ilock(ctlr);
	if(ctlr->init){
		iunlock(ctlr);
		return;
	}
	ctlr->init = 1;
	iunlock(ctlr);

	outs(port+Rdp, Stop);

	outs(port+Rap, 15);
	x = ins(port+Rdp) & ~Prom;
	if(on)
		x |= Prom;	/* BUG: multicast ... */
	outs(port+Rdp, x);
	outs(port+Rap, 0);

	ringinit(ctlr);

	ilock(ctlr);
	ctlr->init = 0;
	outs(port+Rdp, Iena|Strt);
	iunlock(ctlr);
}

static int
owntdre(void* arg)
{
	return (((Tdre*)arg)->tmd1 & Own) == 0;
}

static void
txstart(Ether *ether)
{
	int port;
	Ctlr *ctlr;
	Tdre *tdre;
	Etherpkt *pkt;
	Block *bp;
	int n;

	port = ether->port;
	ctlr = ether->ctlr;

	if(ctlr->init)
		return;

	/*
	 * Take the next transmit buffer, if it is free.
	 */
	tdre = &ctlr->tdr[ctlr->tdrx];
	if(owntdre(tdre) == 0)
		return;
	bp = qget(ether->oq);
	if(bp == nil)
		return;

	/*
	 * Copy the packet to the transmit buffer and fill in our
	 * source ethernet address. There's no need to pad to ETHERMINTU
	 * here as we set ApadXmit in CSR4.
	 */
	n = BLEN(bp);
	pkt = KADDR(tdre->tbadr|(tdre->tmd1&0xFF)<<16);
	memmove(pkt->d, bp->rp, n);
	memmove(pkt->s, ether->ea, sizeof(pkt->s));
	freeb(bp);

	/*
	 * Give ownership of the descriptor to the chip, increment the
	 * software ring descriptor pointer and tell the chip to poll.
	 */
	tdre->tmd3 = 0;
	tdre->tmd2 = 0xF000|(-n)&0x0FFF;
	tdre->tmd1 |= Own|Stp|Enp;
	ctlr->tdrx = NEXT(ctlr->tdrx, Ntdre);
	outs(port+Rdp, Iena|Tdmd);

	ether->outpackets++;
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
interrupt(Ureg*, void* arg)
{
	Ether *ether;
	int port, csr0, status;
	Ctlr *ctlr;
	Rdre *rdre;
	Etherpkt *pkt;
	Block *bp;
	int len;

	ether = arg;
	port = ether->port;
	ctlr = ether->ctlr;

	/*
	 * Acknowledge all interrupts and whine about those that shouldn't
	 * happen.
	 */
	csr0 = ins(port+Rdp);
	outs(port+Rdp, Babl|Cerr|Miss|Merr|Rint|Tint|Iena);
	if(csr0 & (Babl|Miss|Merr))
		print("AMD70C960#%d: csr0 = 0x%uX\n", ether->ctlrno, csr0);

	/*
	 * Receiver interrupt: run round the descriptor ring logging
	 * errors and passing valid receive data up to the higher levels
	 * until we encounter a descriptor still owned by the chip.
	 */
	if(csr0 & Rint){
		rdre = &ctlr->rdr[ctlr->rdrx];
		while(((status = rdre->rmd1) & Own) == 0){
			if(status & RxErr){
				if(status & RxBuff)
					ether->buffs++;
				if(status & RxCrc)
					ether->crcs++;
				if(status & RxOflo)
					ether->overflows++;
			}
			else {
				len = (rdre->rmd3 & 0x0FFF)-4;
				if((bp = iallocb(len)) != nil){
					ether->inpackets++;
					pkt = KADDR(rdre->rbadr|(rdre->rmd1&0xFF)<<16);
					memmove(bp->wp, pkt, len);
					bp->wp += len;
					etheriq(ether, bp, 1);
				}
			}

			/*
			 * Finished with this descriptor, reinitialise it,
			 * give it back to the chip, then on to the next...
			 */
			rdre->rmd3 = 0;
			rdre->rmd2 = 0xF000|-Rbsize&0x0FFF;
			rdre->rmd1 |= Own;	

			ctlr->rdrx = NEXT(ctlr->rdrx, Nrdre);
			rdre = &ctlr->rdr[ctlr->rdrx];
		}
	}

	/*
	 * Transmitter interrupt: start next block if waiting for free descriptor.
	 */
	if(csr0 & Tint){
		lock(ctlr);
		txstart(ether);
		unlock(ctlr);
	}
}

static int
reset(Ether* ether)
{
	int port, x, i;
	uchar ea[Eaddrlen];
	Ctlr *ctlr;

	if(ether->port == 0)
		ether->port = 0x300;
	if(ether->irq == 0)
		ether->irq = 10;
	if(ether->irq == 2)
		ether->irq = 9;
	if(ether->dma == 0)
		ether->dma = 5;
	port = ether->port;

	if(port == 0 || ether->dma == 0)
		return -1;

	/*
	 * Allocate a controller structure and start to fill in the
	 * initialisation block (must be DWORD aligned).
	 */
	ether->ctlr = malloc(sizeof(Ctlr));
	ctlr = ether->ctlr;

	ilock(ctlr);
	ctlr->init = 1;

	/*
	 * Set the auto pad transmit in CSR4.
	 */
	/*outs(port+Rdp, 0x00);/**/
	ins(port+Sreset); /**/
	delay(1);
	outs(port+Rap, 0);
	outs(port+Rdp, Stop);

	outs(port+Rap, 4);
	x = ins(port+Rdp) & 0xFFFF;
	outs(port+Rdp, ApadXmt|x);

	outs(port+Rap, 0);

	/*
	 * Check if we are going to override the adapter's station address.
	 * If not, read it from the I/O-space and set in ether->ea prior to loading the
	 * station address in the initialisation block.
	 */
	memset(ea, 0, Eaddrlen);
	if(memcmp(ea, ether->ea, Eaddrlen) == 0){
		for(i=0; i<6; i++)
			ether->ea[i] = inb(port + Aprom + i);
	}

	ctlr->iblock.rlen = Lognrdre<<5;
	ctlr->iblock.tlen = Logntdre<<5;
	memmove(ctlr->iblock.padr, ether->ea, sizeof(ctlr->iblock.padr));

	ringinit(ctlr);

	x = PADDR(ctlr->rdr);
	ctlr->iblock.rdra0 = x&0xFFFF;
	ctlr->iblock.rdra16 = (x >> 16)&0xFF;
	x = PADDR(ctlr->tdr);
	ctlr->iblock.tdra0 = x&0xFFFF;
	ctlr->iblock.tdra16 = (x >> 16)&0xFF;

	/*
	 * set the DMA controller to cascade mode for bus master
	 */
	switch(ether->dma){
	case 5:
		outb(0xd6, 0xc1); outb(0xd4, 1); break;
	case 6:
		outb(0xd6, 0xc2); outb(0xd4, 2); break;
	case 7:
		outb(0xd6, 0xc3); outb(0xd4, 3); break;
	}

	/*
	  * Ensure 10Base-T (for now)
	  */
	ctlr->iblock.mode = TenBaseT;
	outs(port+Rap, 2);
	x = ins(port+Idp);
	x &= ~Isamedia;
	x |= Isa10;
	x |= Isaawake;
	outs(port+Idp, x);

	/*
	 * Point the chip at the initialisation block and tell it to go.
	 * Mask the Idon interrupt and poll for completion. Strt and interrupt
	 * enables will be set later when we're ready to attach to the network.
	 */
	x = PADDR(&ctlr->iblock);
	if((x>>24)&0xFF)
		panic("ether79c960: address>24bit");
	outs(port+Rap, 1);
	outs(port+Rdp, x & 0xFFFF);
	outs(port+Rap, 2);
	outs(port+Rdp, (x>>16) & 0xFF);
	outs(port+Rap, 3);
	outs(port+Rdp, Idonm);
	outs(port+Rap, 0);
	outs(port+Rdp, Init);

	while((ins(port+Rdp) & Idon) == 0)
		;
	outs(port+Rdp, Idon|Stop);
	ctlr->init = 0;
	iunlock(ctlr);

	ether->port = port;
	ether->attach = attach;
	ether->transmit = transmit;
	ether->interrupt = interrupt;
	ether->ifstat = 0;

	ether->promiscuous = promiscuous;
	ether->arg = ether;

	return 0;
}

void
ether79c960link(void)
{
	addethercard("AMD79C960",  reset);
}
