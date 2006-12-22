/*
 * Memory Map for Samsung ks32c50100
 */

#define SFRbase	0x7ff0000

#define SYSCFG	(*(ulong *)(SFRbase + 0))

#define IOPbase	(SFRbase + 0x5000)
#define IOPMOD	(*(ulong *)(IOPbase + 0))
#define IOPCON	(*(ulong *)(IOPbase + 4))
#define IOPDATA	(*(ulong *)(IOPbase + 8))

#define MaxIRQbit		20			/* Maximum IRQ */
#define EXT0bit		0
#define EXT1bit		1
#define EXT2bit		2
#define EXT3bit		3
#define UART0TXbit		4
#define UART0RXbit		5
#define UART1TXbit		6
#define UART1RXbit		7
#define GDMA0		8
#define GDMA1		9
#define TIMER0bit		10
#define TIMER1bit		11
#define HDLCATXbit		12
#define HDLCARXbit		13
#define HDLCBTXbit		14
#define HDLCBRXbit		15
#define ETHBDMATXbit	16
#define ETHBDMARXbit	17
#define ETHMACRXint	18
#define ETHMAXTXint	19
#define IICbit			20

#define TIMERbit(n) 		(TIMER0bit + n)
#define UARTTXbit(n)	(UART0TXbit + (n) * 2)
#define UARTRXbit(n)	(UART0RXbit + (n) * 2)

/*
  * Interrupt controller
  */

#define INTbase	(SFRbase + 0x4000)
#define INTREG	((IntReg *)INTbase)

typedef struct IntReg IntReg;
struct IntReg {
	ulong	mod;		/* 00 */
	ulong	pnd;			/* 04 */
	ulong	msk;			/* 08 */
	ulong	pri[6];		/* 0c */
	ulong	offset;		/* 24 */
	ulong	pndpri;		/* 28 */
	ulong	pndtst;		/* 2c */
	ulong	oset_fiq;		/* 30 */
	ulong	oset_irq;		/* 34 */
};

/*
  * UARTs
  */
#define UART0base	(SFRbase + 0xd000)
#define UART1base	(SFRbase + 0xe000)
#define UARTREG	((UartReg *)UART0base)

typedef struct UartReg UartReg;
struct UartReg {
	ulong	lcon;		/* 00 */
	ulong	con;		/* 04 */
	ulong	stat;		/* 08 */
	ulong	txbuf;	/* 0c */
	ulong	rxbuf;	/* 10 */
	ulong	brdiv;	/* 14 */
	ulong	pad[(UART1base - UART0base - 0x18) / 4];
};

#define ULCON_WLMASK		0x03
#define ULCON_WL5		0x00
#define ULCON_WL6		0x01
#define ULCON_WL7		0x02
#define ULCON_WL8		0x03

#define ULCON_STOPMASK	0x04
#define ULCON_STOP1		0x00
#define ULCON_STOP2		0x04

#define ULCON_PMDMASK	0x38
#define ULCON_PMDNONE	0x00
#define ULCON_PMDODD	(4 << 3)
#define ULCON_PMDEVEN	(5 << 3)
#define ULCON_PMDFORCE1	(6 << 3)
#define ULCON_PMDFORCE0	(7 << 3)

#define ULCON_CLOCKMASK	0x40
#define ULCON_CLOCKMCLK	0x00
#define ULCON_CLOCKUCLK	(1 << 6)

#define ULCON_IRMASK		0x80
#define ULCON_IROFF		0x00
#define ULCON_IRON		0x80

#define UCON_RXMDMASK	0x03
#define UCON_RXMDOFF		0x00
#define UCON_RXMDINT		0x01
#define UCON_RXMDGDMA0	0x02
#define UCON_RXMDGDMA1	0x03

#define UCON_SINTMASK	0x04
#define UCON_SINTOFF		0x00
#define UCON_SINTON		0x04

#define UCON_TXMDMASK	0x18
#define UCON_TXMDOFF		(0 << 3)
#define UCON_TXMDINT		(1 << 3)
#define UCON_TXMDGDMA0	(2 << 3)
#define UCON_TXMDGDMA1	(3 << 3)

#define UCON_DSRMASK		0x20
#define UCON_DSRON		(1 << 5)
#define UCON_DSROFF		(0 << 5)

#define UCON_BRKMASK		0x40
#define UCON_BRKON		(1 << 6)
#define UCON_BRKOFF		(0 << 6)

#define UCON_LOOPMASK	0x80
#define UCON_LOOPON		0x80
#define UCON_LOOPOFF		0x00

#define USTAT_OV			0x01
#define USTAT_PE			0x02
#define USTAT_FE			0x04
#define USTAT_BKD			0x08
#define USTAT_DTR			0x10
#define USTAT_RDR			0x20
#define USTAT_TBE			0x40
#define USTAT_TC			0x80

/*
  * Timers
  */
#define TIMERbase	(SFRbase + 0x6000)
#define TIMERREG	((TimerReg *)TIMERbase)

typedef struct TimerReg TimerReg;
struct TimerReg {
	ulong mod;
	ulong data[2];
	ulong cnt[2];
};

/*
 *	PC compatibility support for PCMCIA drivers
 */

extern ulong ins(ulong);		/* return ulong to prevent unecessary compiler shifting */
void outs(ulong, int);
#define inb(addr)	(*((uchar*)(addr)))
#define inl(addr)	(*((ulong*)(addr)))
ulong ins(ulong);
#define outb(addr, val)	*((uchar*)(addr)) = (val)
#define outl(addr, val)	*((ulong*)(addr)) = (val)

void inss(ulong, void*, int);
void outss(ulong, void*, int);

