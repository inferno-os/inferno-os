#include "u.h"
#include "lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"

#include "etherif.h"

static Ctlr ether[MaxEther];

static struct {
	char	*type;
	int	(*reset)(Ctlr*);
} cards[] = {
	{ "SCC", sccethreset, },
	{ "SCC2", sccethreset, },
	{ 0, }
};

int
etherinit(void)
{
	Ctlr *ctlr;
	int ctlrno, i, mask, n;

	mask = 0;
	for(ctlrno = 0; ctlrno < MaxEther; ctlrno++){
		ctlr = &ether[ctlrno];
		memset(ctlr, 0, sizeof(Ctlr));
		if(isaconfig("ether", ctlrno, &ctlr->card) == 0)
			continue;
		for(n = 0; cards[n].type; n++){
			if(strcmp(cards[n].type, ctlr->card.type))
				continue;
			ctlr->ctlrno = ctlrno;
			if((*cards[n].reset)(ctlr))
				break;

			ctlr->iq = qopen(16*1024, 1, 0, 0);
			ctlr->oq = qopen(16*1024, 1, 0, 0);

			ctlr->present = 1;
			mask |= 1<<ctlrno;

			print("ether%d: %s: port 0x%luX irq %d",
				ctlr->ctlrno, ctlr->card.type, ctlr->card.port, ctlr->card.irq);
			if(ctlr->card.mem)
				print(" addr 0x%luX", PADDR(ctlr->card.mem));
			if(ctlr->card.size)
				print(" size 0x%luX", ctlr->card.size);
			print(":");
			for(i = 0; i < sizeof(ctlr->card.ea); i++)
				print(" %2.2uX", ctlr->card.ea[i]);
			print("\n"); uartwait();
			setvec(VectorPIC + ctlr->card.irq, ctlr->card.intr, ctlr);
			break;
		}
	}

	return mask;
}

static Ctlr*
attach(int ctlrno)
{
	Ctlr *ctlr;

	if(ctlrno >= MaxEther || ether[ctlrno].present == 0)
		return 0;

	ctlr = &ether[ctlrno];
	if(ctlr->present == 1){
		ctlr->present = 2;
		(*ctlr->card.attach)(ctlr);
	}

	return ctlr;
}

uchar*
etheraddr(int ctlrno)
{
	Ctlr *ctlr;

	if((ctlr = attach(ctlrno)) == 0)
		return 0;

	return ctlr->card.ea;
}

int
etherrxpkt(int ctlrno, Etherpkt *pkt, int timo)
{
	int n;
	Ctlr *ctlr;
	Block *b;
	ulong start;

	if((ctlr = attach(ctlrno)) == 0)
		return 0;

	start = m->ticks;
	while((b = qget(ctlr->iq)) == 0){
		if(TK2MS(m->ticks - start) >= timo){
			/*
			print("ether%d: rx timeout\n", ctlrno);
			 */
			return 0;
		}
	}

	n = BLEN(b);
	memmove(pkt, b->rp, n);
	freeb(b);

	return n;
}

int
etheriq(Ctlr *ctlr, Block *b, int freebp)
{
	if(memcmp(((Etherpkt*)b->rp)->d, ctlr->card.ea, Eaddrlen) != 0 &&
	   memcmp(((Etherpkt*)b->rp)->d, broadcast, Eaddrlen) != 0){
		if(freebp)
			freeb(b);
		return 0;
	}
	qbwrite(ctlr->iq, b);
	return 1;
}

int
ethertxpkt(int ctlrno, Etherpkt *pkt, int len, int)
{
	Ctlr *ctlr;
	Block *b;
	int s;

	if((ctlr = attach(ctlrno)) == 0)
		return 0;

	if(qlen(ctlr->oq) > 16*1024){
		print("ether%d: tx queue full\n", ctlrno);
		return 0;
	}
	b = iallocb(sizeof(Etherpkt));
	memmove(b->wp, pkt, len);
	memmove(((Etherpkt*)b->wp)->s, ctlr->card.ea, Eaddrlen);
	b->wp += len;
	qbwrite(ctlr->oq, b);
	s = splhi();
	(*ctlr->card.transmit)(ctlr);
	splx(s);

	return 1;
}
