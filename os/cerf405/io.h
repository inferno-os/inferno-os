typedef struct BD BD;
typedef struct Ring Ring;
typedef struct MALdev MALdev;
typedef struct I2Cdev I2Cdev;

enum
{
	/* 405EP UIC interrupt vectors (IBM bit numbering) */
	VectorUIC= 0,
		VectorUART0=VectorUIC,
		VectorUART1,
		VectorIIC,
		VectorPCIECW,
		VectorRsvd1,
		VectorDMA0,
		VectorDMA1,
		VectorDMA2,
		VectorDMA3,
		VectorEtherwake,
		VectorMALSERR,
		VectorMALTXEOB,
		VectorMALRXEOB,
		VectorMALTXDE,
		VectorMALRXDE,
		VectorEMAC0,
		VectorPCISERR,
		VectorEMAC1,
		VectorPCIPM,
		VectorGPT0,
		VectorGPT1,
		VectorGPT2,
		VectorGPT3,
		VectorGPT4,
		/* 1 reserved */
	VectorIRQ=	VectorUIC+25,	/* IRQ0 to IRQ6 */
	MaxVector=	VectorIRQ+7,

	/* some flags to change polarity and sensitivity */
	IRQmask=		0xFF,	/* actual vector address */
	IRQactivelow=	1<<8,
	IRQedge=		1<<9,
	IRQcritical=	1<<10,
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
	BusOPB,
	BusPLB,
	BusPCI,
	MaxBus
};

/*
 * MAL Buffer Descriptors and IO Rings
 */

struct BD {
	ushort	status;
	ushort	length;
	ulong	addr;
};
#define	MAXIORING	256	/* hardware limit to ring size */
#define	BDBUFLIM	(4096-16)	/* no MAL buffer larger than this */

BD*	bdalloc(ulong);
void	bdfree(BD*, int);
void	dumpbd(char*, BD*, int);

enum {
	/* Rx BDs, bits common to all protocols */
	BDEmpty=	1<<15,
	BDWrap=		1<<14,	/* end of ring */
	BDContin=	1<<13,	/* continuous mode */
	BDLast=		1<<12,	/* last buffer in current packet */
	BDFirst=		1<<11,	/* first buffer in current packet (set by MAL) */
	BDInt=		1<<10,	/* interrupt when done */

	/* Tx BDs */
	BDReady=		1<<15,	/* ready to transmit; set by driver, cleared by MAL */
	/* BDWrap, BDInt, BDLast as above */
};

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

/*
 * one per mal channel
 */
typedef struct Mal Mal;
struct Mal {
	int	n;
	int	len;
	int	tx;
	ulong	mask;

	void*	arg;
	void	(*interrupt)(Ureg*, void*);
};

Mal*	malchannel(int, int, void (*)(Ureg*, void*), void*);
void	maltxreset(Mal*);
void	maltxinit(Mal*, Ring*);
void	maltxenable(Mal*);
void	malrxreset(Mal*);
void	malrxinit(Mal*, Ring*, ulong);
void	malrxenable(Mal*);
void	ioringreserve(int, ulong, int, ulong);
int	ioringinit(Ring*, int, int);

typedef struct Gpioregs Gpioregs;
struct Gpioregs {
	ulong	or;	/* output register */
	ulong	tcr;	/* tristate control */
	ulong	osrh;	/* output select high (0-15) */
	ulong	osrl;	/* output select low (16-31) */
	ulong	tsrh;	/* tristate select high (0-15) */
	ulong	tsrl;	/* tristate select low (16-31) */
	ulong	odr;	/* open drain */
	ulong	ir;	/* input */
	ulong	rr1;	/* receive register */
	ulong	pad[3];
	ulong	isr1h;	/* input select 1 high (0-15) */
	ulong	isr1l;	/* input select 1 low (16-31) */
};

enum {
	/* software configuration bits for gpioconfig */
	Gpio_Alt1=	1<<0,	/* implies specific settings of all the others, but include in or out */
	Gpio_OD=	1<<1,
	Gpio_Tri=		1<<2,
	Gpio_in=		1<<4,
	Gpio_out=	1<<5,
};

void	gpioreserve(ulong);
void	gpioconfig(ulong, ulong);
ulong	gpioget(ulong);
void	gpioset(ulong, ulong);
void	gpiorelease(ulong);

/*
 * used by ../port/devi2c.c and iic.c
 */
struct I2Cdev {
	int	addr;
	int	salen;	/* length in bytes of subaddress, if used; 0 otherwise */
	int	tenbit;	/* 10-bit addresses */
};

long	i2crecv(I2Cdev*, void*, long, ulong);
long	i2csend(I2Cdev*, void*, long, ulong);
void	i2csetup(int);

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
