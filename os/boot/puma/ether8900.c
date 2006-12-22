/*
 * Crystal CS8900 ethernet controller
 * Specifically for the Teralogic Puma architecture
 */

#include "u.h"
#include "lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"

#include "ether.h"
#include "puma.h"

/*
 * On the Puma board the CS8900 can be addressed from either 
 * ISA I/O space or ISA memory space at the following locations.
 * The cs8900 address pins are shifted by 1 relative to the CPU.
 */
enum {
	IsaIOBase		= 0xf0000000,
	IsaMemBase	= 0xe0000000,

	IOBase		= 0x300,
	MemBase		= 0xc0000,
};

/* I/O accesses */
#define	out16(port, val)	(*((ushort *)IsaIOBase + IOBase + (port)) = (val))
#define	in16(port)			*((ushort *)IsaIOBase + IOBase + (port))
#define	in8(port)			*((uchar *)IsaIOBase + ((IOBase+(port))<<1))
#define	regIOw(reg, val)	 do {out16(PpPtr, (reg)|0x3000); out16(PpData, val);} while(0)
#define	regIOr(reg)		(out16(PpPtr, (reg)|0x3000), in16(PpData))
#define	regIOr1(reg)		(out16(PpPtr, (reg)|0x3000), in16(PpData1))

/* Memory accesses */
#define	regw(reg, val)		*((ushort *)IsaMemBase + MemBase + (reg)) = (val)
#define	regr(reg)			*((ushort *)IsaMemBase + MemBase + (reg))

/* Puma frame copying */
#define	copyout(src, len)	{ \
						int _len = (len); \
						ushort *_src = (ushort *)(src); \
						ushort *_dst = (ushort *)IsaMemBase + MemBase + TxFrame; \
						while(_len > 0) { \
							*_dst++ = *_src++; \
							_dst++; \
							_len -= 2; \
						} \
					}
#define	copyoutIO(src, len)	{ \
						int _len = (len); \
						ushort *_src = (ushort *)(src); \
						while(_len > 0) { \
							out16(RxTxData, *_src); \
							_src++; \
							_len -= 2; \
						} \
					}
#define	copyin(dst, len)	{ \
						int _len = (len), _len2 = (len)&~1; \
						ushort *_src = (ushort *)IsaMemBase + MemBase + RxFrame; \
						ushort *_dst = (ushort *)(dst); \
						while(_len2 > 0) { \
							*_dst++ = *_src++; \
							_src++; \
							_len2 -= 2; \
						} \
						if(_len&1) \
							*(uchar*)_dst = (*_src)&0xff; \
					}
#define	copyinIO(dst, len)	{ \
						int _i, _len = (len), _len2 = (len)&~1; \
						ushort *_dst = (ushort *)(dst); \
						_i = in16(RxTxData); USED(_i); /* RxStatus */ \
						_i = in16(RxTxData); USED(_i); /* RxLen */ \
						while(_len2 > 0) { \
							*_dst++ = in16(RxTxData); \
							_len2 -= 2; \
						} \
						if(_len&1) \
							*(uchar*)_dst = (in16(RxTxData))&0xff; \
					}
						
	

enum {					/* I/O Mode Register Offsets */
	RxTxData	= 0x00,		/* receive/transmit data - port 0 */
	TxCmdIO = 0x04,		/* transmit command */
	TxLenIO	= 0x06,		/* transmit length */
	IsqIO	= 0x08,		/* Interrupt status queue */
	PpPtr	= 0x0a,		/* packet page pointer */
	PpData	= 0x0c,		/* packet page data */
	PpData1	= 0x0e,		/* packet page data - port 1*/
};

enum {					/* Memory Mode Register Offsets */
	/* Bus Interface Registers */
	Ern		= 0x0000,		/* EISA registration numberion */
	Pic		= 0x0002,		/* Product identification code */
	Iob		= 0x0020,		/* I/O base address */
	Intr		= 0x0022,		/* interrupt number */
	Mba		= 0x002c,		/* memory base address */
	
	Ecr		= 0x0040,		/* EEPROM command register */
	Edw		= 0x0042,		/* EEPROM data word */
	Rbc		= 0x0050,		/* receive frame byte counter */

	/* Status and Control Registers */
	RxCfg	= 0x0102,
	RxCtl	= 0x0104,
	TxCfg	= 0x0106,
	BufCfg	= 0x010a,
	LineCtl	= 0x0112,
	SelfCtl	= 0x0114,
	BusCtl	= 0x0116,
	TestCtl	= 0x0118,
	Isq		= 0x0120,
	RxEvent	= 0x0124,
	TxEvent	= 0x0128,
	BufEvent	= 0x012c,
	RxMISS	= 0x0130,
	TxCol	= 0x0132,
	LineSt	= 0x0134,
	SelfSt	= 0x0136,
	BusSt	= 0x0138,
	Tdr		= 0x013c,

	/* Initiate Transmit Registers */
	TxCmd	= 0x0144,		/* transmit command */
	TxLen	= 0x0146,		/* transmit length */

	/* Address Filter Registers */
	IndAddr	= 0x0158,		/* individual address registers */

	/* Frame Location */
	RxStatus	= 0x0400,		/* receive status */
	RxLen	= 0x0402,		/* receive length */
	RxFrame	= 0x0404,		/* receive frame location */
	TxFrame	= 0x0a00,		/* transmit frame location */
};

enum {					/* Ecr */
	Addr			= 0x00ff,		/* EEPROM word address (field) */
	Opcode		= 0x0300,		/* command opcode (field) */
};

enum {					/* Isq */
	Regnum		= 0x003f,		/* register number held by Isq (field) */
		IsqRxEvent	= 0x04,
		IsqTxEvent	= 0x08,
		IsqBufEvent	= 0x0c,
		IsqRxMiss		= 0x10,
		IsqTxCol		= 0x12,
	RegContent 	= 0xffc0,		/* register data contents (field) */
};

enum {					/* RxCfg */
	Skip_1		= 0x0040,
	StreamE		= 0x0080,
	RxOKiE		= 0x0100,
	RxDMAonly	= 0x0200,
	AutoRxDMAE	= 0x0400,
	BufferCRC		= 0x0800,
	CRCerroriE	= 0x1000,
	RuntiE		= 0x2000,
	ExtradataiE	= 0x4000,
};

enum {					/* RxEvent */
	IAHash		= 0x0040,
	Dribblebits	= 0x0080,
	RxOK		= 0x0100,
	Hashed		= 0x0200,
	IndividualAdr	= 0x0400,
	Broadcast		= 0x0800,
	CRCerror		= 0x1000,
	Runt			= 0x2000,
	Extradata		= 0x4000,
};

enum {					/* RxCtl */
	IAHashA		= 0x0040,
	PromiscuousA	= 0x0080,
	RxOKA		= 0x0100,
	MulticastA	= 0x0200,
	IndividualA	= 0x0400,
	BroadcastA	= 0x0800,
	CRCerrorA	= 0x1000,
	RuntA		= 0x2000,
	ExtradataA	= 0x4000,
};

enum {					/* TxCfg */
	LossofCRSiE	= 0x0040,
	SQEerroriE	= 0x0080,
	TxOKiE		= 0x0100,
	OutofWindowiE	= 0x0200,
	JabberiE		= 0x0400,
	AnycolliE		= 0x0800,
	Coll16iE		= 0x8000,
};

enum {					/* TxEvent */
	LossofCRS	= 0x0040,
	SQEerror		= 0x0080,
	TxOK		= 0x0100,
	OutofWindow	= 0x0200,
	Jabber		= 0x0400,
	NTxCols		= 0x7800,		/* number of Tx collisions (field) */
	coll16		= 0x8000,
};

enum {					/* BufCfg */
	SWintX		= 0x0040,
	RxDMAiE		= 0x0080,
	Rdy4TxiE		= 0x0100,
	TxUnderruniE	= 0x0200,
	RxMissiE		= 0x0400,
	Rx128iE		= 0x0800,
	TxColOvfiE	= 0x1000,
	MissOvfloiE	= 0x2000,
	RxDestiE		= 0x8000,
};

enum {					/* BufEvent */
	SWint		= 0x0040,
	RxDMAFrame	= 0x0080,
	Rdy4Tx		= 0x0100,
	TxUnderrun	= 0x0200,
	RxMiss		= 0x0400,
	Rx128		= 0x0800,
	RxDest		= 0x8000,
};

enum {					/* RxMiss */
	MissCount	= 0xffc0,
};

enum {					/* TxCol */
	ColCount	= 0xffc0,
};

enum {					/* LineCtl */
	SerRxOn		= 0x0040,
	SerTxOn		= 0x0080,
	Iface			= 0x0300,		/* (field) 01 - AUI, 00 - 10BASE-T, 10 - Auto select */
	ModBackoffE	= 0x0800,
	PolarityDis	= 0x1000,
	DefDis		= 0x2000,
	LoRxSquelch	= 0x4000,
};

enum {					/* LineSt */
	LinkOK		= 0x0080,
	AUI			= 0x0100,
	TenBT		= 0x0200,
	PolarityOK	= 0x1000,
	CRS			= 0x4000,
};

enum {					/* SelfCtl */
	RESET		= 0x0040,
	SWSuspend	= 0x0100,
	HWSleepE		= 0x0200,
	HWStandbyE	= 0x0400,
};

enum {					/* SelfSt */
	INITD		= 0x0080,
	SIBUSY		= 0x0100,
	EepromPresent	= 0x0200,
	EepromOK	= 0x0400,
	ElPresent		= 0x0800,
	EeSize		= 0x1000,
};

enum {					/* BusCtl */
	ResetRxDMA	= 0x0040,
	UseSA		= 0x0200,
	MemoryE		= 0x0400,
	DMABurst		= 0x0800,
	EnableIRQ		= 0x8000,
};

enum {					/* BusST */
	TxBidErr		= 0x0080,
	Rdy4TxNOW	= 0x0100,
};

enum {					/* TestCtl */
	FDX			= 0x4000,		/* full duplex */
};

enum {					/* TxCmd */
	TxStart		= 0x00c0,		/* bytes before transmit starts (field) */
		TxSt5	= 0x0000,		/* start after 5 bytes */
		TxSt381	= 0x0040,		/* start after 381 bytes */
		TxSt1021	= 0x0080,		/* start after 1021 bytes */
		TxStAll	= 0x00c0,		/* start after the entire frame is in the cs8900 */
	Force		= 0x0100,
	Onecoll		= 0x0200,
	InhibitCRC	= 0x1000,
	TxPadDis		= 0x2000,
};

static Queue *pendingTx[MaxEther];

static void
attach(Ctlr *ctlr)
{
	int reg;

	USED(ctlr);
	/* enable transmit and receive */
	reg = regr(BusCtl);
	regw(BusCtl, reg|EnableIRQ);
	reg = regr(LineCtl);
	regw(LineCtl, reg|SerRxOn|SerTxOn);
}

static char pbuf[200];
int
sprintx(void *f, char *to, int count)
{
	int i, printable;
	char *start = to;
	uchar *from = f;

	if(count < 0) {
		print("BAD DATA COUNT %d\n", count);
		return 0;
	}
	printable = 1;
	if(count > 40)
		count = 40;
	for(i=0; i<count && printable; i++)
		if((from[i]<32 && from[i] !='\n' && from[i] !='\r' && from[i] !='\b' && from[i] !='\t') || from[i]>127)
			printable = 0;
	*to++ = '\'';
	if(printable){
		memmove(to, from, count);
		to += count;
	}else{
		for(i=0; i<count; i++){
			if(i>0 && i%4==0)
				*to++ = ' ';
			sprint(to, "%2.2ux", from[i]);
			to += 2;
		}
	}
	*to++ = '\'';
	*to = 0;
	return to - start;
}

static void
transmit(Ctlr *ctlr)
{
	int len, status;
	Block *b;

	for(;;){
		/* is TxCmd pending ? - check */
		if(qlen(pendingTx[ctlr->ctlrno]) > 0)
			break;
		b = qget(ctlr->oq);
		if(b == 0)
			break;
		len = BLEN(b);
		regw(TxCmd, TxSt381);
		regw(TxLen, len);
		status = regr(BusSt);
		if((status & Rdy4TxNOW) == 0) {
			qbwrite(pendingTx[ctlr->ctlrno], b);
			break;
		}
		/*
		 * Copy the packet to the transmit buffer.
		 */
		copyout(b->rp, len);
		freeb(b);
	}
}

static void
interrupt(Ureg*, Ctlr *ctlr)
{
	int len, events, status;
	Block *b;
	Queue *q;

	while((events = regr(Isq)) != 0) {
		status = events&RegContent;
	
		switch(events&Regnum) {

		case IsqBufEvent:
			if(status&Rdy4Tx) {
				if(qlen(pendingTx[ctlr->ctlrno]) > 0)
					q = pendingTx[ctlr->ctlrno];
				else
					q = ctlr->oq;
				b = qget(q);
				if(b == 0)
					break;
				len = BLEN(b);
				copyout(b->rp, len);
				freeb(b);
			} else
			if(status&TxUnderrun) {
				print("TxUnderrun\n");
			} else
			if(status&RxMiss) {
				print("RxMiss\n");
			} else {
				print("IsqBufEvent status = %ux\n", status);
			}
			break;

		case IsqRxEvent:
			if(status&RxOK) {
				len = regr(RxLen);
				if((b = iallocb(len)) != 0) {
					copyin(b->wp, len);
					b->wp += len;
					etheriq(ctlr, b, 1);
				}
			} else {
				print("IsqRxEvent status = %ux\n", status);
			}
			break;

		case IsqTxEvent:
			if(status&TxOK) {
				if(qlen(pendingTx[ctlr->ctlrno]) > 0)
					q = pendingTx[ctlr->ctlrno];
				else
					q = ctlr->oq;
				b = qget(q);
				if(b == 0)
					break;
				len = BLEN(b);
				regw(TxCmd, TxSt381);
				regw(TxLen, len);
if((regr(BusSt) & Rdy4TxNOW) == 0) {
	print("IsqTxEvent and Rdy4TxNow == 0\n");
}
				copyout(b->rp, len);
				freeb(b);
			} else {
				print("IsqTxEvent status = %ux\n", status);
			}
			break;
		case IsqRxMiss:
			break;
		case IsqTxCol:
			break;
		}
	}
}

int
cs8900reset(Ctlr* ctlr)
{
	int i, reg;
	uchar ea[Eaddrlen];

	ctlr->card.irq = V_ETHERNET;
	pendingTx[ctlr->ctlrno] = qopen(16*1024, 1, 0, 0);

	/*
	 * If the Ethernet address is not set in the plan9.ini file
	 * a) try reading from the Puma board ROM. The ether address is found in
	 * 	bytes 4-9 of the ROM. The Teralogic Organizational Unique Id (OUI) 
	 *	is in bytes 4-6 and should be 00 10 8a.
	 */
	memset(ea, 0, Eaddrlen);
	if(memcmp(ea, ctlr->card.ea, Eaddrlen) == 0) {
		uchar *rom = (uchar *)EPROM_BASE;
		if(rom[4] != 0x00 || rom[5] != 0x10 || rom[6] != 0x8a)
			panic("no ether address");
		memmove(ea, &rom[4], Eaddrlen);
	}
	memmove(ctlr->card.ea, ea, Eaddrlen);

	/* 
	 * Identify the chip by reading the Pic register.
	 * The EISA registration number is in the low word
	 * and the product identification code in the high code.
	 * The ERN for Crystal Semiconductor is 0x630e.
	 * Bits 0-7 and 13-15 of the Pic should be zero for a CS8900.
	 */
	if(regIOr(Ern) != 0x630e || (regIOr(Pic) & 0xe0ff) != 0)
		panic("no cs8900 found");

	/*
	 * Reset the chip and ensure 16-bit mode operation
	 */
	regIOw(SelfCtl, RESET);
	delay(10);
	i=in8(PpPtr); 	USED(i);
	i=in8(PpPtr+1); USED(i);
	i=in8(PpPtr); 	USED(i);
	i=in8(PpPtr+1);	USED(i);

	/*
	 * Wait for initialisation and EEPROM reads to complete
	 */
	i=0;
	for(;;) {
		short st = regIOr(SelfSt);
		if((st&SIBUSY) == 0 && st&INITD)
			break;
		if(i++ > 1000000)
			panic("cs8900: initialisation failed");
	}

	/*
	 * Enable memory mode operation.
	 */
	regIOw(Mba, MemBase & 0xffff);
	regIOw(Mba+2, MemBase >> 16);
	regIOw(BusCtl, MemoryE|UseSA);

	/*
	 * Enable 10BASE-T half duplex, transmit in interrupt mode
	 */
	reg = regr(LineCtl);
	regw(LineCtl, reg&~Iface);
	reg = regr(TestCtl);
	regw(TestCtl, reg&~FDX);
	regw(BufCfg, Rdy4TxiE|TxUnderruniE|RxMissiE);
	regw(TxCfg, TxOKiE|JabberiE|Coll16iE);
	regw(RxCfg, RxOKiE);
	regw(RxCtl, RxOKA|IndividualA|BroadcastA);

	for(i=0; i<Eaddrlen; i+=2)
		regw(IndAddr+i, ea[i] | (ea[i+1] << 8));

	/* Puma IRQ tied to INTRQ0 */
	regw(Intr, 0);

	ctlr->card.reset = cs8900reset;
	ctlr->card.port = 0x300;
	ctlr->card.attach = attach;
	ctlr->card.transmit = transmit;
	ctlr->card.intr = interrupt;

	print("Ether reset...\n");uartwait();

	return 0;
}

