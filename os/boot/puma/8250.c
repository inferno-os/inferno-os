#include "boot.h"

/*
 *  INS8250 uart
 */
enum
{
	/*
	 *  register numbers
	 */
	Data=	0,		/* xmit/rcv buffer */
	Iena=	1,		/* interrupt enable */
	 Ircv=	(1<<0),		/*  for char rcv'd */
	 Ixmt=	(1<<1),		/*  for xmit buffer empty */
	 Irstat=(1<<2),		/*  for change in rcv'er status */
	 Imstat=(1<<3),		/*  for change in modem status */
	Istat=	2,		/* interrupt flag (read) */
	Tctl=	2,		/* test control (write) */
	Format=	3,		/* byte format */
	 Bits8=	(3<<0),		/*  8 bits/byte */
	 Stop2=	(1<<2),		/*  2 stop bits */
	 Pena=	(1<<3),		/*  generate parity */
	 Peven=	(1<<4),		/*  even parity */
	 Pforce=(1<<5),		/*  force parity */
	 Break=	(1<<6),		/*  generate a break */
	 Dra=	(1<<7),		/*  address the divisor */
	Mctl=	4,		/* modem control */
	 Dtr=	(1<<0),		/*  data terminal ready */
	 Rts=	(1<<1),		/*  request to send */
	 Ri=	(1<<2),		/*  ring */
	 Inton=	(1<<3),		/*  turn on interrupts */
	 Loop=	(1<<4),		/*  loop back */
	Lstat=	5,		/* line status */
	 Inready=(1<<0),	/*  receive buffer full */
	 Oerror=(1<<1),		/*  receiver overrun */
	 Perror=(1<<2),		/*  receiver parity error */
	 Ferror=(1<<3),		/*  rcv framing error */
	 Outready=(1<<5),	/*  output buffer empty */
	Mstat=	6,		/* modem status */
	 Ctsc=	(1<<0),		/*  clear to send changed */
	 Dsrc=	(1<<1),		/*  data set ready changed */
	 Rire=	(1<<2),		/*  rising edge of ring indicator */
	 Dcdc=	(1<<3),		/*  data carrier detect changed */
	 Cts=	(1<<4),		/*  complement of clear to send line */
	 Dsr=	(1<<5),		/*  complement of data set ready line */
	 Ring=	(1<<6),		/*  complement of ring indicator line */
	 Dcd=	(1<<7),		/*  complement of data carrier detect line */
	Scratch=7,		/* scratchpad */
	Dlsb=	0,		/* divisor lsb */
	Dmsb=	1,		/* divisor msb */

	Serial=	0,
	Modem=	1,
};

typedef struct Uart	Uart;
struct Uart
{
	int	port;
	int	setup;
	uchar	sticky[8];	/* sticky write register values */
	uchar	txbusy;

	Queue	*iq;
	Queue	*oq;
	void	(*rx)(Queue *, int);

	ulong	frame;
	ulong	overrun;
};

Uart	uart[1];

static	void	uartkick(void*);


#define UartFREQ 1843200

#define uartwrreg(u,r,v)	outb((u)->port + r, (u)->sticky[r] | (v))
#define uartrdreg(u,r)		inb((u)->port + r)

/*
 *  set the baud rate by calculating and setting the baudrate
 *  generator constant.  This will work with fairly non-standard
 *  baud rates.
 */
static void
uartsetbaud(Uart *up, int rate)
{
	ulong brconst;

	brconst = (UartFREQ+8*rate-1)/(16*rate);

	uartwrreg(up, Format, Dra);
	outb(up->port+Dmsb, (brconst>>8) & 0xff);
	outb(up->port+Dlsb, brconst & 0xff);
	uartwrreg(up, Format, 0);
}

/*
 *  toggle DTR
 */
static void
uartdtr(Uart *up, int n)
{
	if(n)
		up->sticky[Mctl] |= Dtr;
	else
		up->sticky[Mctl] &= ~Dtr;
	uartwrreg(up, Mctl, 0);
}

/*
 *  toggle RTS
 */
static void
uartrts(Uart *up, int n)
{
	if(n)
		up->sticky[Mctl] |= Rts;
	else
		up->sticky[Mctl] &= ~Rts;
	uartwrreg(up, Mctl, 0);
}

static void
uartintr(Ureg*, void *arg)
{
	Uart *up;
	int ch;
	int s, l, loops;

	up = arg;
	for(loops = 0; loops < 1024; loops++){
		s = uartrdreg(up, Istat);
		switch(s){
		case 6:	/* receiver line status */
			l = uartrdreg(up, Lstat);
			if(l & Ferror)
				up->frame++;
			if(l & Oerror)
				up->overrun++;
			break;
	
		case 4:	/* received data available */
		case 12:
			ch = inb(up->port+Data);
			if(up->iq)
				if(up->rx)
					(*up->rx)(up->iq, ch);
				else
					qbputc(up->iq, ch);
			break;
	
		case 2:	/* transmitter empty */
			ch = -1;
			if(up->oq)
				ch = qbgetc(up->oq);
			if(ch != -1)
				outb(up->port+Data, ch);
			else
				up->txbusy = 0;
			break;
	
		case 0:	/* modem status */
			uartrdreg(up, Mstat);
			break;
	
		default:
			if(s&1)
				return;
			print("weird modem interrupt #%2.2ux\n", s);
			break;
		}
	}
	panic("uartintr: 0x%2.2ux\n", uartrdreg(up, Istat));
}

/*
 *  turn on a port's interrupts.  set DTR and RTS
 */
static void
uartenable(Uart *up)
{
	/*
 	 *  turn on interrupts
	 */
	up->sticky[Iena] = 0;
	if(up->oq)
		up->sticky[Iena] |= Ixmt;
	if(up->iq)
		up->sticky[Iena] |= Ircv|Irstat;
	uartwrreg(up, Iena, 0);

	/*
	 *  turn on DTR and RTS
	 */
	uartdtr(up, 1);
	uartrts(up, 1);
}

void
uartspecial(int port, int baud, Queue **iq, Queue **oq, void (*rx)(Queue *, int))
{
	Uart *up = &uart[0];

	if(up->setup)
		return;
	up->setup = 1;

	*iq = up->iq = qopen(4*1024, 0, 0, 0);
	*oq = up->oq = qopen(16*1024, 0, uartkick, up);
	switch(port){

	case 0:
		up->port = 0x3F8;
		setvec(V_COM1, uartintr, up);
		break;

	case 1:
		up->port = 0x2F8;
		setvec(V_COM2, uartintr, up);
		break;

	default:
		return;
	}

	/*
	 *  set rate to 9600 baud.
	 *  8 bits/character.
	 *  1 stop bit.
	 *  interrupts enabled.
	 */
	uartsetbaud(up, 9600);
	up->sticky[Format] = Bits8;
	uartwrreg(up, Format, 0);
	up->sticky[Mctl] |= Inton;
	uartwrreg(up, Mctl, 0x0);

	up->rx = rx;
	uartenable(up);
	if(baud)
		uartsetbaud(up, baud);
}

static void
uartputc(int c)
{
	Uart *up = &uart[0];
	int i;

	for(i = 0; i < 100; i++){
		if(uartrdreg(up, Lstat) & Outready)
			break;
		delay(1);
	}
	outb(up->port+Data, c);
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

/*
 *  (re)start output
 */
static void
uartkick(void *arg)
{
	Uart *up = arg;
	int x, n, c;

	x = splhi();
	while(up->txbusy == 0 && (c = qbgetc(up->oq)) != -1) {
		n = 0;
		while((uartrdreg(up, Lstat) & Outready) == 0){
			if(++n > 100000){
				print("stuck serial line\n");
				break;
			}
		}
			outb(up->port + Data, c);
	}
	splx(x);
}

void
uartwait(void)
{
	Uart *up = &uart[0];

	while(up->txbusy)
		;
}
