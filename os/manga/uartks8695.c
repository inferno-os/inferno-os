#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "../port/error.h"

#include "../port/uart.h"

/*
 * KS8695 uart; similar to 8250 etc but registers are slightly different,
 * and interrupt control is quite different
 */
enum {
	UartFREQ	= CLOCKFREQ,
};

/*
 * similar to i8250/16450/16550 (slight differences)
 */

enum {					/* I/O ports */
	Rbr		= 0,		/* Receiver Buffer (RO) */
	Thr		= 1,		/* Transmitter Holding (WO) */
	Fcr		= 2,		/* FIFO Control  */
	Lcr		= 3,		/* Line Control */
	Mcr		= 4,		/* Modem Control */
	Lsr		= 5,		/* Line Status */
	Msr		= 6,		/* Modem Status */
	Div		= 7,		/* Divisor  */
	Usr		= 8,		/* Status */
};

enum {					/* Fcr */
	FIFOena		= 0x01,		/* FIFO enable */
	FIFOrclr	= 0x02,		/* clear Rx FIFO */
	FIFOtclr	= 0x04,		/* clear Tx FIFO */
	FIFO1		= 0x00,		/* Rx FIFO trigger level 1 byte */
	FIFO4		= 0x40,		/*	4 bytes */
	FIFO8		= 0x80,		/*	8 bytes */
	FIFO14		= 0xC0,		/*	14 bytes */
};

enum {					/* Lcr */
	Wls5		= 0x00,		/* Word Length Select 5 bits/byte */
	Wls6		= 0x01,		/*	6 bits/byte */
	Wls7		= 0x02,		/*	7 bits/byte */
	Wls8		= 0x03,		/*	8 bits/byte */
	WlsMASK		= 0x03,
	Stb		= 0x04,		/* 2 stop bits */
	Pen		= 0x08,		/* Parity Enable */
	Eps		= 0x10,		/* Even Parity Select */
	Stp		= 0x20,		/* Stick Parity */
	Brk		= 0x40,		/* Break */
	Dlab		= 0x80,		/* Divisor Latch Access Bit */
};

enum {					/* Mcr */
	Dtr		= 0x01,		/* Data Terminal Ready */
	Rts		= 0x02,		/* Ready To Send */
	Out1		= 0x04,		/* UART OUT1 asserted */
	Out2		= 0x08,		/* UART OUT2 asserted */
	Dm		= 0x10,		/* Diagnostic Mode loopback */
};

enum {					/* Lsr */
	Dr		= 0x01,		/* Data Ready */
	Oe		= 0x02,		/* Overrun Error */
	Pe		= 0x04,		/* Parity Error */
	Fe		= 0x08,		/* Framing Error */
	Bi		= 0x10,		/* Break Interrupt */
	Thre		= 0x20,		/* Thr Empty */
	Temt		= 0x40,		/* Tramsmitter Empty */
	FIFOerr		= 0x80,		/* error in receiver FIFO */
	LsrInput		= FIFOerr|Oe|Pe|Fe|Dr|Bi,	/* input status only */
};

enum {					/* Msr */
	Dcts		= 0x01,		/* Delta Cts */
	Ddsr		= 0x02,		/* Delta Dsr */
	Teri		= 0x04,		/* Trailing Edge of Ri */
	Ddcd		= 0x08,		/* Delta Dcd */
	Cts		= 0x10,		/* Clear To Send */
	Dsr		= 0x20,		/* Data Set Ready */
	Ri		= 0x40,		/* Ring Indicator */
	Dcd		= 0x80,		/* Data Set Ready */
};

enum {					/* Usr */
	Uti		= 0x01,		/* INTST[9]=1=> =1, interrupt is timeout; =0, receive FIFO trigger */
};

typedef struct Ctlr {
	ulong*	regs;
	int	irq;
	int	iena;

	Lock;
	int	fena;
} Ctlr;

extern PhysUart ks8695physuart;


static Ctlr ks8695_ctlr[1] = {
{	.regs	= (ulong*)PHYSUART,
	.irq	= IRQuts,	/* base: ts then rs, ls, ms */
},
};

static Uart ks8695_uart[1] = {
{	.regs	= &ks8695_ctlr[0],
	.name	= "eia0",
	.freq	= UartFREQ,
	.phys	= &ks8695physuart,
	.special= 0,
	.next	= nil, },
};

#define csr8r(c, r)	((c)->regs[(r)])
#define csr8w(c, r, v)	((c)->regs[(r)] = (v))

static long
ks8695_status(Uart* uart, void* buf, long n, long offset)
{
	char *p;
	Ctlr *ctlr;
	uchar ier, lcr, mcr, msr;

	ctlr = uart->regs;
	p = malloc(READSTR);
	mcr = csr8r(ctlr, Mcr);
	msr = csr8r(ctlr, Msr);
	ier = INTRREG->en;
	lcr = csr8r(ctlr, Lcr);
	snprint(p, READSTR,
		"b%d c%d d%d e%d l%d m%d p%c r%d s%d i%d ier=%ux\n"
		"dev(%d) type(%d) framing(%d) overruns(%d)%s%s%s%s\n",

		uart->baud,
		uart->hup_dcd, 
		(msr & Dsr) != 0,
		uart->hup_dsr,
		(lcr & WlsMASK) + 5,
		(ier & (1<<IRQums)) != 0, 
		(lcr & Pen) ? ((lcr & Eps) ? 'e': 'o'): 'n',
		(mcr & Rts) != 0,
		(lcr & Stb) ? 2: 1,
		ctlr->fena,
		ier,

		uart->dev,
		uart->type,
		uart->ferr,
		uart->oerr, 
		(msr & Cts) ? " cts": "",
		(msr & Dsr) ? " dsr": "",
		(msr & Dcd) ? " dcd": "",
		(msr & Ri) ? " ring": ""
	);
	n = readstr(offset, buf, n, p);
	free(p);

	return n;
}

static void
ks8695_fifo(Uart* uart, int level)
{
	Ctlr *ctlr;

	ctlr = uart->regs;

	/*
	 * Changing the FIFOena bit in Fcr flushes data
	 * from both receive and transmit FIFOs; there's
	 * no easy way to guarantee not losing data on
	 * the receive side, but it's possible to wait until
	 * the transmitter is really empty.
	 */
	ilock(ctlr);
	while(!(csr8r(ctlr, Lsr) & Temt))
		;

	/*
	 * Set the trigger level, default is the max.
	 * value.
	 */
	ctlr->fena = level;
	switch(level){
	case 0:
		break;
	case 1:
		level = FIFO1|FIFOena;
		break;
	case 4:
		level = FIFO4|FIFOena;
		break;
	case 8:
		level = FIFO8|FIFOena;
		break;
	default:
		level = FIFO14|FIFOena;
		break;
	}
	csr8w(ctlr, Fcr, level);
	iunlock(ctlr);
}

static void
ks8695_dtr(Uart* uart, int on)
{
	Ctlr *ctlr;
	int r;

	/*
	 * Toggle DTR.
	 */
	ctlr = uart->regs;
	r = csr8r(ctlr, Mcr);
	if(on)
		r |= Dtr;
	else
		r &= ~Dtr;
	csr8w(ctlr, Mcr, r);
}

static void
ks8695_rts(Uart* uart, int on)
{
	Ctlr *ctlr;
	int r;

	/*
	 * Toggle RTS.
	 */
	ctlr = uart->regs;
	r = csr8r(ctlr, Mcr);
	if(on)
		r |= Rts;
	else
		r &= ~Rts;
	csr8w(ctlr, Mcr, r);
}

static void
ks8695_modemctl(Uart* uart, int on)
{
	Ctlr *ctlr;

	ctlr = uart->regs;
	ilock(&uart->tlock);
	if(on){
		INTRREG->en |= 1<<IRQums;	/* TO DO */
		uart->modem = 1;
		uart->cts = csr8r(ctlr, Msr) & Cts;
	}
	else{
		INTRREG->en &= ~(1<<IRQums);
		uart->modem = 0;
		uart->cts = 1;
	}
	iunlock(&uart->tlock);

	/* modem needs fifo */
	(*uart->phys->fifo)(uart, on);
}

static int
ks8695_parity(Uart* uart, int parity)
{
	int lcr;
	Ctlr *ctlr;

	ctlr = uart->regs;
	lcr = csr8r(ctlr, Lcr) & ~(Eps|Pen);

	switch(parity){
	case 'e':
		lcr |= Eps|Pen;
		break;
	case 'o':
		lcr |= Pen;
		break;
	case 'n':
	default:
		break;
	}
	csr8w(ctlr, Lcr, lcr);

	uart->parity = parity;

	return 0;
}

static int
ks8695_stop(Uart* uart, int stop)
{
	int lcr;
	Ctlr *ctlr;

	ctlr = uart->regs;
	lcr = csr8r(ctlr, Lcr);
	switch(stop){
	case 1:
		lcr &= ~Stb;
		break;
	case 2:
		lcr |= Stb;
		break;
	default:
		return -1;
	}
	csr8w(ctlr, Lcr, lcr);
	uart->stop = stop;
	return 0;
}

static int
ks8695_bits(Uart* uart, int bits)
{
	int lcr;
	Ctlr *ctlr;

	ctlr = uart->regs;
	lcr = csr8r(ctlr, Lcr) & ~WlsMASK;

	switch(bits){
	case 5:
		lcr |= Wls5;
		break;
	case 6:
		lcr |= Wls6;
		break;
	case 7:
		lcr |= Wls7;
		break;
	case 8:
		lcr |= Wls8;
		break;
	default:
		return -1;
	}
	csr8w(ctlr, Lcr, lcr);

	uart->bits = bits;

	return 0;
}

static int
ks8695_baud(Uart* uart, int baud)
{
	ulong bgc;
	Ctlr *ctlr;

	if(uart->freq == 0 || baud <= 0)
		return -1;
	ctlr = uart->regs;
	bgc = (uart->freq+baud-1)/baud;
	csr8w(ctlr, Div, bgc);
	uart->baud = baud;
	return 0;
}

static void
ks8695_break(Uart* uart, int ms)
{
	Ctlr *ctlr;
	int lcr;

	/*
	 * Send a break.
	 */
	if(ms == 0)
		ms = 200;

	ctlr = uart->regs;
	lcr = csr8r(ctlr, Lcr);
	csr8w(ctlr, Lcr, lcr|Brk);
	tsleep(&up->sleep, return0, 0, ms);
	csr8w(ctlr, Lcr, lcr);
}

static void
ks8695_kick(Uart* uart)
{
	int i;
	Ctlr *ctlr;

	if(uart->cts == 0 || uart->blocked)
		return;

	ctlr = uart->regs;
	for(i = 0; i < 16; i++){
		if(!(csr8r(ctlr, Lsr) & Thre))
			break;
		if(uart->op >= uart->oe && uartstageoutput(uart) == 0)
			break;
		csr8w(ctlr, Thr, *uart->op++);
	}
}

static void
ks8695_modemintr(Ureg*, void *arg)
{
	Ctlr *ctlr;
	Uart *uart;
	int old, r;

	uart = arg;
	ctlr = uart->regs;
	r = csr8r(ctlr, Msr);
	if(r & Dcts){
		ilock(&uart->tlock);
		old = uart->cts;
		uart->cts = r & Cts;
		if(old == 0 && uart->cts)
			uart->ctsbackoff = 2;
		iunlock(&uart->tlock);
	}
 	if(r & Ddsr){
		old = r & Dsr;
		if(uart->hup_dsr && uart->dsr && !old)
			uart->dohup = 1;
		uart->dsr = old;
	}
 	if(r & Ddcd){
		old = r & Dcd;
		if(uart->hup_dcd && uart->dcd && !old)
			uart->dohup = 1;
		uart->dcd = old;
	}
}

static void
ks8695_rxintr(Ureg*, void* arg)
{
	Ctlr *ctlr;
	Uart *uart;
	int lsr, r;

	/* handle line error status here as well */
	uart = arg;
	ctlr = uart->regs;
	while((lsr = csr8r(ctlr, Lsr) & LsrInput) != 0){
		/*
		 * Consume any received data.
		 * If the received byte came in with a break,
		 * parity or framing error, throw it away;
		 * overrun is an indication that something has
		 * already been tossed.
		 */
		if(lsr & (FIFOerr|Oe))
			uart->oerr++;
		if(lsr & Pe)
			uart->perr++;
		if(lsr & Fe)
			uart->ferr++;
		if(lsr & Dr){
			r = csr8r(ctlr, Rbr);
			if(!(lsr & (Bi|Fe|Pe)))
				uartrecv(uart, r);
		}
	}
}

static void
ks8695_txintr(Ureg*, void* arg)
{
	uartkick(arg);
}

static void
ks8695_disable(Uart* uart)
{
	Ctlr *ctlr;

	/*
 	 * Turn off DTR and RTS, disable interrupts and fifos.
	 */
	(*uart->phys->dtr)(uart, 0);
	(*uart->phys->rts)(uart, 0);
	(*uart->phys->fifo)(uart, 0);

	ctlr = uart->regs;

	if(ctlr->iena != 0){
		intrdisable(IRQ, ctlr->irq, ks8695_txintr, uart, uart->name);
		intrdisable(IRQ, ctlr->irq+1, ks8695_rxintr, uart, uart->name);
		intrdisable(IRQ, ctlr->irq+2, ks8695_rxintr, uart, uart->name);
		intrdisable(IRQ, ctlr->irq+3, ks8695_modemintr, uart, uart->name);
		ctlr->iena = 0;
	}
}

static void
ks8695_enable(Uart* uart, int ie)
{
	Ctlr *ctlr;

	ctlr = uart->regs;

	/*
 	 * Enable interrupts and turn on DTR and RTS.
	 * Be careful if this is called to set up a polled serial line
	 * early on not to try to enable interrupts as interrupt-
	 * -enabling mechanisms might not be set up yet.
	 */
	if(ctlr->iena == 0 && ie){
		intrenable(IRQ, ctlr->irq, ks8695_txintr, uart, uart->name);
		intrenable(IRQ, ctlr->irq+1, ks8695_rxintr, uart, uart->name);
		intrenable(IRQ, ctlr->irq+2, ks8695_rxintr, uart, uart->name);
		intrenable(IRQ, ctlr->irq+3, ks8695_modemintr, uart, uart->name);
		ctlr->iena = 1;
	}

	(*uart->phys->dtr)(uart, 1);
	(*uart->phys->rts)(uart, 1);
}

static Uart*
ks8695_pnp(void)
{
	return ks8695_uart;
}

static int
ks8695_getc(Uart *uart)
{
	Ctlr *ctlr;

	ctlr = uart->regs;
	while(!(csr8r(ctlr, Lsr)&Dr))
		delay(1);
	return csr8r(ctlr, Rbr);
}

static void
ks8695_putc(Uart *uart, int c)
{
	serialputc(c);
#ifdef ROT
	int i;
	Ctlr *ctlr;

	ctlr = uart->regs;
	for(i = 0; !(csr8r(ctlr, Lsr)&Thre) && i < 256; i++)
		delay(1);
	csr8w(ctlr, Thr, c);
	if(c == '\n')
		while((csr8r(ctlr, Lsr) & Temt) == 0){	/* let fifo drain */
			/* skip */
		}
#endif
}

PhysUart ks8695physuart = {
	.name		= "ks8695",
	.pnp		= ks8695_pnp,
	.enable		= ks8695_enable,
	.disable	= ks8695_disable,
	.kick		= ks8695_kick,
	.dobreak	= ks8695_break,
	.baud		= ks8695_baud,
	.bits		= ks8695_bits,
	.stop		= ks8695_stop,
	.parity		= ks8695_parity,
	.modemctl	= ks8695_modemctl,
	.rts		= ks8695_rts,
	.dtr		= ks8695_dtr,
	.status		= ks8695_status,
	.fifo		= ks8695_fifo,
	.getc		= ks8695_getc,
	.putc		= ks8695_putc,
};

void
uartconsole(void)
{
	Uart *uart;

	uart = &ks8695_uart[0];
	(*uart->phys->enable)(uart, 0);
	uartctl(uart, "b38400 l8 pn s1");
	consuart = uart;
	uart->console = 1;
}

#define	UR(p,r)	((ulong*)(p))[r]

void
serialputc(int c)
{
	ulong *p;

	if(c == 0)
		return;
	p = (ulong*)PHYSUART;
	while((UR(p,Lsr) & Thre) == 0){
		/* skip */
	}
	UR(p,Thr) = c;
	if(c == '\n')
		while((UR(p,Lsr) & Temt) == 0){	/* let fifo drain */
			/* skip */
		}
}

/*
 *  for iprint, just write it
 */
void
serialputs(char *data, int len)
{
	ulong *p;

	p = (ulong*)PHYSUART;
	while(--len >= 0){
		if(*data == '\n')
			serialputc('\r');
		serialputc(*data++);
	}
	while((UR(p,Lsr) & Temt) == 0){	/* let fifo drain */
		/* skip */
	}
}
void (*serwrite)(char*, int) = serialputs;
