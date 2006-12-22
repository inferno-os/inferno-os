#include "u.h"
#include "lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"

/*
 *  SMC1 in UART mode
 */

typedef struct Uartsmc Uartsmc;
struct Uartsmc {
	IOCparam;
	ushort	maxidl;
	ushort	idlc;
	ushort	brkln;
	ushort	brkec;
	ushort	brkcr;
	ushort	rmask;
};

typedef struct Uart	Uart;
struct Uart
{
	int	port;
	int	setup;
	uchar	txbusy;

	Queue*	iq;
	Queue*	oq;
	void	(*rx)(Queue*, int);
	void	(*boot)(uchar*, int);

	ulong	frame;
	ulong	overrun;
	uchar	rxbuf[128];
	char	txbuf[16];
	BD*	rxb;
	BD*	txb;
};

Uart	uart[1];
int	predawn = 1;

static	void	uartintr(Ureg*, void*);
static	void	uartkick(void*);

static int
baudgen(int baud)
{
	int d;

	d = ((m->cpuhz/baud)+8)>>4;
	if(d >= (1<<12))
		return ((d+15)>>3)|1;
	return d<<1;
}

static void
smcsetup(Uart *up, int baud)
{
	IMM *io;
	Uartsmc *p;
	BD *bd;
	SMC *smc;

	archenableuart(SMC1ID, 0);
	io = m->iomem;
	io->pbpar |= IBIT(24)|IBIT(25);	/* enable SMC1 TX/RX */
	io->pbdir &= ~(IBIT(24)|IBIT(25));
	io->brgc1 = baudgen(baud) | BaudEnable;
	io->simode &= ~0xF000;	/* SMC1 to NMSI mode, Tx/Rx clocks are BRG1 */

	bd = bdalloc(1);
	p = (Uartsmc*)KADDR(SMC1P);
	p->rbase = (ushort)bd;
	up->rxb = bd;
	bd->status = BDEmpty|BDWrap|BDInt;
	bd->length = 0;
	bd->addr = PADDR(up->rxbuf);
	bd = bdalloc(1);
	p->tbase = (ushort)bd;
	up->txb = bd;
	bd->status = BDWrap|BDInt;
	bd->length = 0;
	bd->addr = PADDR(up->txbuf);

	cpmop(InitRxTx, SMC1ID, 0);

	/* protocol parameters */
	p->rfcr = 0x18;
	p->tfcr = 0x18;
	p->mrblr = 1;
	p->maxidl = 1;
	p->brkln = 0;
	p->brkec = 0;
	p->brkcr = 1;
	smc = IOREGS(0xA80, SMC);
	smc->smce = 0xff;	/* clear events */
	smc->smcm = 0x17;	/* enable all possible interrupts */
	setvec(VectorCPIC+4, uartintr, up);
	smc->smcmr = 0x4820;	/* 8-bit mode, no parity, 1 stop bit, UART mode, ... */
	smc->smcmr |= 3;	/* enable rx/tx */
}

static void
uartintr(Ureg*, void *arg)
{
	Uart *up;
	int ch, i;
	BD *bd;
	SMC *smc;
	Block *b;

	up = arg;
	smc = IOREGS(0xA80, SMC);
	smc->smce = 0xff;	/* clear all events */
	if((bd = up->rxb) != nil && (bd->status & BDEmpty) == 0){
		if(up->iq != nil && bd->length > 0){
			if(up->boot != nil){
				up->boot(up->rxbuf, bd->length);
			}else if(up->rx != nil){
				for(i=0; i<bd->length; i++){
					ch = up->rxbuf[i];
					up->rx(up->iq, ch);
				}
			}else{
				b = iallocb(bd->length);
				memmove(b->wp, up->rxbuf, bd->length);
				b->wp += bd->length;
				qbwrite(up->iq, b);
			}
		}
		bd->status |= BDEmpty|BDInt;
	} else if((bd = up->txb) != nil && (bd->status & BDReady) == 0){
		ch = -1;
		if(up->oq)
			ch = qbgetc(up->oq);
		if(ch != -1){
			up->txbuf[0] = ch;
			bd->length = 1;
			bd->status |= BDReady;
		}else
			up->txbusy = 0;
	}
	/* TO DO: modem status, errors, etc */
}

static void
uartkick(void *arg)
{
	Uart *up = arg;
	int s, c, i;

	s = splhi();
	while(up->txbusy == 0 && (c = qbgetc(up->oq)) != -1){
		if(predawn){
			while(up->txb->status & BDReady)
				;
		} else {
			for(i = 0; i < 100; i++){
				if((up->txb->status & BDReady) == 0)
					break;
				delay(1);
			}
		}
		up->txbuf[0] = c;
		up->txb->length = 1;
		up->txb->status |= BDReady;
		up->txbusy = !predawn;
	}
	splx(s);
}

void
uartspecial(int port, int baud, Queue **iq, Queue **oq, void (*rx)(Queue*,int))
{
	Uart *up = &uart[0];

	if(up->setup)
		return;
	up->setup = 1;

	*iq = up->iq = qopen(4*1024, 0, 0, 0);
	*oq = up->oq = qopen(16*1024, 0, uartkick, up);
	up->rx = rx;
	USED(port);
	up->port = SMC1ID;
	if(baud == 0)
		baud = 9600;
	smcsetup(up, baud);
	/* if using SCCn's UART, would also set DTR and RTS, but SMC doesn't use them */
}

void
uartsetboot(void (*f)(uchar*, int))
{
	uart[0].boot = f;
}

void
uartputs(char *s, int n)
{
	Uart *up = &uart[0];
	Block *b;
	int nl;
	char *p;

	nl = 0;
	for(p = s; p < s+n; p++)
		if(*p == '\n')
			nl++;
	b = iallocb(n+nl);
	while(n--){
		if(*s == '\n')
			*b->wp++ = '\r';
		*b->wp++ = *s++;
	}
	qbwrite(up->oq, b);
}

void
uartwait(void)
{
	Uart *up = &uart[0];

	while(up->txbusy)
		;
}
