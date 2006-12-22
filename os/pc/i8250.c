#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "../port/error.h"

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
	 Fenabd=(3<<6),		/*  on if fifo's enabled */
	Fifoctl=2,		/* fifo control (write) */
	 Fena=	(1<<0),		/*  enable xmit/rcv fifos */
	 Ftrig=	(1<<6),		/*  trigger after 4 input characters */
	 Fclear=(3<<1),		/*  clear xmit & rcv fifos */
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
	uchar	sticky[8];	/* sticky write register values */
	int	nofifo;

	void	(*rx)(int);	/* routine to take a received character */
	int	(*tx)(void);	/* routine to get a character to transmit */

	ulong	frame;
	ulong	overrun;
};

static Uart i8250uart[1];

#define UartFREQ 1843200

#define i8250regw(u, r, v)	outb((u)->port+(r), (u)->sticky[(r)]|(v))
#define i8250regr(u, r)		inb((u)->port+(r))

/*
 *  set the baud rate by calculating and setting the baudrate
 *  generator constant.  This will work with fairly non-standard
 *  baud rates.
 */
static void
i8250setbaud(Uart* uart, int rate)
{
	ulong brconst;

	brconst = (UartFREQ+8*rate-1)/(16*rate);

	i8250regw(uart, Format, Dra);
	outb(uart->port+Dmsb, (brconst>>8) & 0xff);
	outb(uart->port+Dlsb, brconst & 0xff);
	i8250regw(uart, Format, 0);
}

/*
 *  toggle DTR
 */
static void
i8250dtr(Uart* uart, int n)
{
	if(n)
		uart->sticky[Mctl] |= Dtr;
	else
		uart->sticky[Mctl] &= ~Dtr;
	i8250regw(uart, Mctl, 0);
}

/*
 *  toggle RTS
 */
static void
i8250rts(Uart* uart, int n)
{
	if(n)
		uart->sticky[Mctl] |= Rts;
	else
		uart->sticky[Mctl] &= ~Rts;
	i8250regw(uart, Mctl, 0);
}

/*
 * Enable/disable FIFOs (if possible).
 */
static void
i8250fifo(Uart* uart, int n)
{
	int i, s;

	if(uart->nofifo)
		return;

	s = splhi();

	/* reset fifos */
	i8250regw(uart, Fifoctl, Fclear);

	/* empty buffer and interrupt conditions */
	for(i = 0; i < 16; i++){
		if(i8250regr(uart, Istat))
			{}
		if(i8250regr(uart, Data))
			{}
	}
  
	/* turn on fifo */
	if(n){
		i8250regw(uart, Fifoctl, Fena|Ftrig);

		if((i8250regr(uart, Istat) & Fenabd) == 0){
			/* didn't work, must be an earlier chip type */
			uart->nofifo = 1;
		}
	}

	splx(s);
}

#ifdef notdef
static void
i8250intr(Ureg*, void* arg)
{
	Uart *uart;
	int ch;
	int s, l, loops;

	uart = arg;
	for(loops = 0; loops < 1024; loops++){
		s = i8250regr(uart, Istat);
		switch(s & 0x3F){
		case 6:	/* receiver line status */
			l = i8250regr(uart, Lstat);
			if(l & Ferror)
				uart->frame++;
			if(l & Oerror)
				uart->overrun++;
			break;
	
		case 4:	/* received data available */
		case 12:
			ch = inb(uart->port+Data);
			if(uart->rx)
				(*uart->rx)(ch & 0x7F);
			break;
	
		case 2:	/* transmitter empty */
			ch = -1;
			if(uart->tx)
				ch = (*uart->tx)();
			if(ch != -1)
				outb(uart->port+Data, ch);
			break;
	
		case 0:	/* modem status */
			i8250regr(uart, Mstat);
			break;
	
		default:
			if(s&1)
				return;
			print("weird modem interrupt #%2.2ux\n", s);
			break;
		}
	}
	panic("i8250intr: 0x%2.2ux\n", i8250regr(uart, Istat));
}
#endif /* notdef */

/*
 *  turn on a port's interrupts.  set DTR and RTS
 */
static void
i8250enable(Uart* uart)
{
	/*
 	 *  turn on interrupts
	 */
	uart->sticky[Iena] = 0;
#ifdef notdef
	if(uart->tx)
		uart->sticky[Iena] |= Ixmt;
	if(uart->rx)
		uart->sticky[Iena] |= Ircv|Irstat;
#endif /* notdef */

	/*
	 *  turn on DTR and RTS
	 */
	i8250dtr(uart, 1);
	i8250rts(uart, 1);
	i8250fifo(uart, 1);

	i8250regw(uart, Iena, 0);
}

void
i8250special(int port, void (*rx)(int), int (*tx)(void), int baud)
{
	Uart *uart = &i8250uart[0];

	if(uart->port)
		return;

	switch(port){

	case 0:
		uart->port = 0x3F8;
#ifdef notdef
		intrenable(VectorUART0, i8250intr, uart, BUSUNKNOWN);
#endif /* notdef */
		break;

	case 1:
		uart->port = 0x2F8;
#ifdef notdef
		intrenable(VectorUART1, i8250intr, uart, BUSUNKNOWN);
#endif /* notdef */
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
	i8250setbaud(uart, 9600);
	uart->sticky[Format] = Bits8;
	i8250regw(uart, Format, 0);
	uart->sticky[Mctl] |= Inton;
	i8250regw(uart, Mctl, 0x0);

	uart->rx = rx;
	uart->tx = tx;
	i8250enable(uart);
	if(baud)
		i8250setbaud(uart, baud);
}

int
i8250getc(void)
{
	Uart *uart = &i8250uart[0];

	if(i8250regr(uart, Lstat) & Inready)
		return inb(uart->port+Data);
	return 0;
}

void
i8250putc(int c)
{
	Uart *uart = &i8250uart[0];
	int i;

	for(i = 0; i < 100; i++){
		if(i8250regr(uart, Lstat) & Outready)
			break;
		delay(1);
	}
	outb(uart->port+Data, c);
}

void
i8250puts(char* s, int n)
{
	int x;

	x = splhi();
	while(n--){
		if(*s == '\n')
			i8250putc('\r');
		i8250putc(*s++);
	}
	splx(x);
}
