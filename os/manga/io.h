typedef struct BD BD;
typedef struct Ring Ring;

/*
 *  types of interrupts
 */
enum
{
	/* some flags to change polarity and sensitivity */
	IRQmask=		0xFF,	/* actual vector address */
	IRQactivelow=	0<<8,
	IRQactivehigh=	1<<8,
	IRQrising=	2<<8,
	IRQfalling=	4<<8,
	IRQmode=	IRQactivelow | IRQactivehigh | IRQrising | IRQfalling,
	IRQsoft=	1<<11,	/* configure ext0 to ext3 as GPIO output */
	IRQ=	0,	/* notional bus */
};

enum {
	IRQwmlc=	31,	/* WAN link changed (edge) */
	IRQwmts=	30,	/* WAN MAC transmit status (edge) */
	IRQwmrs=	29,	/* WAN MAC receive status (edge) */
	IRQwmtbu=	28,	/* WAN MAC transmit buffer unavailable (edge) */
	IRQwmrbu=	27,	/* WAN MAC receive buffer unavailable (edge) */
	IRQwmtps=	26,	/* WAN MAC transmit process stopped (edge) */
	IRQwmrps=	25,	/* WAN MAC receive process stopped (edge) */
	IRQaber=	24,		/* AMBA bus error (level) */
	IRQlmts=	17,		/* LAN MAC transmit status (edge) */
	IRQlmrs=	16,		/* LAN MAC receive status (edge) */
	IRQlmtbu=	15,	/* LAN AMC transmit buffer unavailable (edge) */
	IRQlmrbu=	14,	/* LAN MAC receive buffer unavailable (edge) */
	IRQlmtps=	13,	/* LAN MAC transmit process stopped (edge) */
	IRQlmrps=	12,	/* LAN MAC receive process stopped (edge) */
	IRQums=	11,		/* UART modem status (level) */
	IRQule=	10,		/* UART line status (level) */
	IRQurs=	9,		/* UART receive status (level) */
	IRQuts=	8,		/* UART transmit status (level) */
	IRQtm1=	7,		/* timer 1 (edge) */
	IRQtm0=	6,		/* timer 0 (edge) */
	IRQext3=	5,		/* external interrupts (gpio control selects edge or level) */
	IRQext2=	4,
	IRQext1=	3,
	IRQext0=	2,
	IRQccts=	1,		/* comms channel transmit status (level) */
	IRQccrs=	0,		/* comms channel receive status (level) */
};

/*
 * these are defined to keep the interface compatible with other
 * architectures, but only BUSUNKNOWN is currently used
 */
#define MKBUS(t,b,d,f)	(((t)<<24)|(((b)&0xFF)<<16)|(((d)&0x1F)<<11)|(((f)&0x07)<<8))
#define BUSFNO(tbdf)	(((tbdf)>>8)&0x07)
#define BUSDNO(tbdf)	(((tbdf)>>11)&0x1F)
#define BUSBNO(tbdf)	(((tbdf)>>16)&0xFF)
#define BUSTYPE(tbdf)	((tbdf)>>24)
#define BUSBDF(tbdf)	((tbdf)&0x00FFFF00)
#define BUSUNKNOWN	(-1)

enum {
	BusIRQ = IRQ,
	BusPCI,
	MaxBus
};

#define INTRREG 	((IntrReg*)PHYSINTR)
typedef struct IntrReg IntrReg;
struct IntrReg {
	ulong	mc;	/* mode control */
	ulong	en;	/* enable */
	ulong	st;		/* status */
	ulong	pw;	/* priority for WAN */
	ulong	pad0;
	ulong	pl;		/* priority for LAN */
	ulong	pt;	/* priority for timer */
	ulong	pu;	/* priority for UART */
	ulong	pe;	/* priority for external */
	ulong	pc;	/* priority for comms channel */
	ulong	pbe;	/* priority for bus error response */
	ulong	ms;	/* mask status */
	ulong	hpf;	/* highest priority for FIQ */
	ulong	hpi;	/* highest priority for IRQ */
};

#define TIMERREG	((TimerReg*)PHYSTIMER)
typedef struct TimerReg TimerReg;
struct TimerReg {
	ulong	enable;	/* 1<<n to enable timer n */
	ulong	count1;
	ulong	count0;	/* 0 becomes watchdog if byte 0 is 0xFF */
	ulong	pulse1;
	ulong	pulse0;
};

#define GPIOREG		((GpioReg*)PHYSGPIO)
typedef struct GpioReg GpioReg;
struct GpioReg {
	ulong	iopm;	/* mode (1=output) */
	ulong	iopc;		/* control */
	ulong	iopd;		/* data */
};

enum {
	/* WLAN and BT values are probably wrong */
	GPIO_WLAN_act_o=	7,
	GPIO_WLAN_100_o=	8,
	GPIO_BT_act_o=	9,
	GPIO_BT_100_o=	10,
	GPIO_status_orange_o=	11,
	GPIO_status_green_o=	12,
	GPIO_button_i=	15,	/* reset button, active low */
	GPIO_misc_mask_o=	(1<<13)|(1<<14)|(1<<15)|(1<<4)|(1<<5)|(1<<6),	/* no idea */
};

void	gpioreserve(int);
void	gpioconfig(int, ulong);
ulong	gpioget(int);
void	gpioset(int, int);
void	gpiorelease(int);

enum {
	/* software configuration bits for gpioconfig */
	Gpio_in=		0<<4,
	Gpio_out=	1<<4,
};

/*
 * Host Communication buffer descriptors
 */

struct BD  {
	ulong	ctrl;		/* BdBusy and rx flags */
	ulong	size;		/* buffer size, also BdLast and tx flags */
	ulong	addr;
	ulong	next;		/* next descriptor address */
};

enum {
	/* ctrl */
	BdBusy=	1<<31,	/* device owns it */

	RxFS=	1<<30,	/* first buffer of frame */
	RxLS=	1<<29,	/* last buffer of frame */
	RxIPE=	1<<28,	/* IP checksum error */
	RxTCPE=	1<<27,	/* TCP checksum error */
	RxUDPE=	1<<26,	/* UDP checksum error */
	RxES=	1<<25,	/* error summary */
	RxMF=	1<<24,	/* multicast */
	RxRE=	1<<19,	/* physical level reported error */
	RxTL=	1<<18,	/* frame too long */
	RxRF=	1<<17,	/* runt */
	RxCE=	1<<16,	/* CRC error */
	RxFT=	1<<15,	/* =0, Ether; =1, 802.3 */
	RxFL=	0x7FF,	/* frame length */

	/* size and tx flags */
	BdWrap=	1<<25,	/* wrap to base of ring */
	TxIC=	1<<31,	/* interrupt on completion */
	TxFS=	1<<30,	/* first segment */
	TxLS=	1<<29,	/* last segment */
	TxIPG=	1<<28,	/* generate IP checksum */
	TxTCPG=	1<<27,	/* generate tcp/ip checksum */
	TxUDPG=	1<<26,	/* generate udp/ip checksum */
};

BD*	bdalloc(ulong);
void	bdfree(BD*, int);
void	dumpbd(char*, BD*, int);

struct Ring {
	BD*	rdr;				/* receive descriptor ring */
	Block**	rxb;			/* receive ring buffers */
	int	rdrx;				/* index into rdr */
	int	nrdre;			/* length of rdr */

	BD*	tdr;				/* transmit descriptor ring */
	Block**	txb;			/* transmit ring buffers */
	int	tdrh;				/* host index into tdr */
	int	tdri;				/* interface index into tdr */
	int	ntdre;			/* length of tdr */
	int	ntq;				/* pending transmit requests */
};

#define NEXT(x, l)	(((x)+1)%(l))
#define PREV(x, l)	(((x) == 0) ? (l)-1: (x)-1)
#define	HOWMANY(x, y)	(((x)+((y)-1))/(y))
#define ROUNDUP(x, y)	(HOWMANY((x), (y))*(y))

int	ioringinit(Ring*, int, int);

enum {
	/*  DMA configuration parameters */

	 /*  DMA Direction */
	DmaOut=		0,
	DmaIn=		1,
};

/*
 * PCI support code.
 */
enum {					/* type 0 and type 1 pre-defined header */
	PciVID		= 0x00,		/* vendor ID */
	PciDID		= 0x02,		/* device ID */
	PciPCR		= 0x04,		/* command */
	PciPSR		= 0x06,		/* status */
	PciRID		= 0x08,		/* revision ID */
	PciCCRp		= 0x09,		/* programming interface class code */
	PciCCRu		= 0x0A,		/* sub-class code */
	PciCCRb		= 0x0B,		/* base class code */
	PciCLS		= 0x0C,		/* cache line size */
	PciLTR		= 0x0D,		/* latency timer */
	PciHDT		= 0x0E,		/* header type */
	PciBST		= 0x0F,		/* BIST */

	PciBAR0		= 0x10,		/* base address */
	PciBAR1		= 0x14,

	PciINTL		= 0x3C,		/* interrupt line */
	PciINTP		= 0x3D,		/* interrupt pin */
};

enum {					/* type 0 pre-defined header */
	PciBAR2		= 0x18,
	PciBAR3		= 0x1C,
	PciBAR4		= 0x20,
	PciBAR5		= 0x24,
	PciCIS		= 0x28,		/* cardbus CIS pointer */
	PciSVID		= 0x2C,		/* subsystem vendor ID */
	PciSID		= 0x2E,		/* cardbus CIS pointer */
	PciEBAR0	= 0x30,		/* expansion ROM base address */
	PciMGNT		= 0x3E,		/* burst period length */
	PciMLT		= 0x3F,		/* maximum latency between bursts */
};

enum {					/* type 1 pre-defined header */
	PciPBN		= 0x18,		/* primary bus number */
	PciSBN		= 0x19,		/* secondary bus number */
	PciUBN		= 0x1A,		/* subordinate bus number */
	PciSLTR		= 0x1B,		/* secondary latency timer */
	PciIBR		= 0x1C,		/* I/O base */
	PciILR		= 0x1D,		/* I/O limit */
	PciSPSR		= 0x1E,		/* secondary status */
	PciMBR		= 0x20,		/* memory base */
	PciMLR		= 0x22,		/* memory limit */
	PciPMBR		= 0x24,		/* prefetchable memory base */
	PciPMLR		= 0x26,		/* prefetchable memory limit */
	PciPUBR		= 0x28,		/* prefetchable base upper 32 bits */
	PciPULR		= 0x2C,		/* prefetchable limit upper 32 bits */
	PciIUBR		= 0x30,		/* I/O base upper 16 bits */
	PciIULR		= 0x32,		/* I/O limit upper 16 bits */
	PciEBAR1	= 0x28,		/* expansion ROM base address */
	PciBCR		= 0x3E,		/* bridge control register */
};

enum {					/* type 2 pre-defined header */
	PciCBExCA	= 0x10,
	PciCBSPSR	= 0x16,
	PciCBPBN	= 0x18,		/* primary bus number */
	PciCBSBN	= 0x19,		/* secondary bus number */
	PciCBUBN	= 0x1A,		/* subordinate bus number */
	PciCBSLTR	= 0x1B,		/* secondary latency timer */
	PciCBMBR0	= 0x1C,
	PciCBMLR0	= 0x20,
	PciCBMBR1	= 0x24,
	PciCBMLR1	= 0x28,
	PciCBIBR0	= 0x2C,		/* I/O base */
	PciCBILR0	= 0x30,		/* I/O limit */
	PciCBIBR1	= 0x34,		/* I/O base */
	PciCBILR1	= 0x38,		/* I/O limit */
	PciCBSVID	= 0x40,		/* subsystem vendor ID */
	PciCBSID	= 0x42,		/* subsystem ID */
	PciCBLMBAR	= 0x44,		/* legacy mode base address */
};

typedef struct Pcisiz Pcisiz;
struct Pcisiz
{
	Pcidev*	dev;
	int	siz;
	int	bar;
};

typedef struct Pcidev Pcidev;
struct Pcidev
{
	int	tbdf;			/* type+bus+device+function */
	ushort	vid;			/* vendor ID */
	ushort	did;			/* device ID */

	uchar	rid;
	uchar	ccrp;
	uchar	ccru;
	uchar	ccrb;

	struct {
		ulong	bar;		/* base address */
		int	size;
	} mem[6];

	struct {
		ulong	bar;	
		int	size;
	} rom;
	uchar	intl;			/* interrupt line */

	Pcidev*	list;
	Pcidev*	link;			/* next device on this bno */

	Pcidev*	bridge;			/* down a bus */
	struct {
		ulong	bar;
		int	size;
	} ioa, mema;
	ulong	pcr;
};

#define PCIWINDOW	0x80000000
#define PCIWADDR(va)	(PADDR(va)+PCIWINDOW)
