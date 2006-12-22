#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"ureg.h"

/*
 * uart for initial port
 */

typedef struct Uartregs Uartregs;
struct Uartregs {
	uchar	rbr;
#define	thr	rbr
#define	dll	rbr
	uchar	ier;
#define	dlm	ier
	uchar	fcr;
#define	iir	fcr
	uchar	lcr;
	uchar	mcr;
	uchar	lsr;
	uchar	msr;
	uchar	scr;
};

#define	UARTREGS(n)	((Uartregs*)(PHYSUART0+(n)*0x100))

enum {
	/* ier */
	Edssi=	1<<3,
	Elsi=		1<<2,
	Etbei=	1<<1,
	Erbfi=	1<<0,

	/* iir */
	Fci0=	0<<4,
	Fci3=	3<<4,
	Ipl=		7<<1,
	Ip=		1<<0,

	/* fcr */
	Rftl1=	0<<6,	/* receiver trigger level 1, 16, 32, 56 */
	Rftl16=	1<<6,
	Rftl32=	2<<6,
	Rftl56=	3<<6,
	Dms=	1<<3,	/* =0, single transfer; =1, multiple transfers */
	Tfr=		1<<2,	/* transmitter fifo reset */
	Rfr=		1<<1,	/* receiver fifo reset */
	Fifoe=	1<<0,	/* =0, disable fifos; =1, enable fifos */

	/* lcr */
	Dlab=	1<<7,	/* =0, normal; =1, dll/dlm visible */
	Sb=		1<<6,	/* set break */
	Sp=		1<<5,	/* =1, enable sticky parity */
	Eps=		1<<4,	/* =1, generate even parity */
	Pen=		1<<3,	/* =1, enable parity checking */
	Sbs=		1<<2,	/* =0, 1 stop bit; =1, 1.5 or 2 stop bits (see Wls) */
	Wls=		3<<0,	/* set to nbit-5 for nbit characters */

	/* mcr */
	Afc=		1<<5,	/* =1, auto flow control enabled */
	Loop=	1<<4,	/* =1, loop back mode enabled */
	Out2=	1<<3,	/* =0, OUT2# active */
	Out1=	1<<2,	/* =0, OUT1# active */
	Rts=		1<<1,	/* =0, RTS# inactive (1); =1, RTS# active (0) */
	Dtr=		1<<0,	/* =0, DTS# inactive; =1, DTS# active */

	/* lsr */
	Rfe=		1<<7,	/* error instances in fifo */
	Temt=	1<<6,	/* transmitter empty */
	Thre=	1<<5,	/* transmitter holding register/fifo empty */
	Be=		1<<4,	/* break (interrupt) */
	Fe=		1<<3,	/* framing error */
	Pe=		1<<2,	/* parity error */
	Oe=		1<<1,	/* overrun error */
	Dr=		1<<0,	/* receiver data ready */

	/* msr */
	Dcd=	1<<7,	/* follows Out2 */
	Ri=		1<<6,	/* follows Out1 */
	Dsr=		1<<5,	/* follows Dtr */
	Cts=		1<<4,	/* follows Rts */
	Ddcd=	1<<3,	/* Dcd input changed */
	Teri=	1<<2,	/* Ri changed from 0 to 1 */
	Ddsr=	1<<1,	/* Dsr input changed */
	Dcts=	1<<0,	/* Cts input changed */
};

void (*serwrite)(char*, int) = uartputs;

void
uartinstall(void)
{
}

void
uartspecial(int, int, Queue**, Queue**, int (*)(Queue*, int))
{
}

void
uartputc(int c)
{
	Uartregs *r;

	if(c == 0)
		return;
	r = UARTREGS(0);
	while((r->lsr & Thre) == 0)
		{}
	r->thr = c;
	if(c == '\n')
		while((r->lsr & Thre) == 0)	/* flush xmit fifo */
			{}
}

void
uartputs(char *data, int len)
{
	int s;

//	if(!uartspcl && !redirectconsole)
//		return;
	s = splhi();
	while(--len >= 0){
		if(*data == '\n')
			uartputc('\r');
		uartputc(*data++);
	}
	splx(s);
}

void
uartwait(void)
{
}
