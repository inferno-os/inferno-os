typedef struct I2Cdev I2Cdev;
typedef struct PCMconftab PCMconftab;
typedef struct PCMmap	PCMmap;
typedef struct PCMslot	PCMslot;

#define INTRREG 	((IntrReg*)PHYSINTR)
typedef struct IntrReg IntrReg;
struct IntrReg {
	ulong	icip;	/*  IRQ pending */
	ulong	icmr;	/*  mask */
	ulong	iclr;	/*  level */
	ulong	icfp;	/*  FIQ pending */
	ulong	icpr;	/*  pending */
	ulong	iccr;	/*  control */
};

/*
 *  types of interrupts
 */
enum
{
	GPIOrising,
	GPIOfalling,
	GPIOboth,
	IRQ,
};

enum {
	/* first-level interrupts (table 4-36) */
	IRQrtc=	31,
	IRQhz=	30,
	IRQtimer3=	29,
	IRQtimer2=	28,
	IRQtimer1=	27,
	IRQtimer0=	26,
	IRQdma=	25,
	IRQssp=	24,
	IRQmmc=	23,
	IRQffuart=	22,
	IRQbtuart=	21,
	IRQstuart=	20,
	IRQicp=	19,
	IRQi2c=	18,
	IRQlcd=	17,
	IRQnssp=	16,
	IRQac97=	14,
	IRQi2s=	13,
	IRQpmu=	12,
	IRQusb=	11,
	IRQgpio=	10,
	IRQgpio1=	9,
	IRQgpio0=	8,
	IRQhwuart=	7,
};

#define GPIOREG		((GpioReg*)PHYSGPIO)
typedef struct GpioReg GpioReg;
struct GpioReg {
	ulong gplr[3];
	ulong gpdr[3];
	ulong gpsr[3];
	ulong gpcr[3];
	ulong grer[3];
	ulong gfer[3];
	ulong gedr[3];
	ulong gafr[6];
};

enum {
	/* GPIO alternative functions if gafr bits set (see table 4-1, pp. 4-3 to 4-6) */
	GPIO_GP_RST_1_i=	1,	/* active low GP_reset */
	GPIO_FFRXD_1_i=	34,	/* FFUART receive */
	GPIO_FFTXD_2_o=	39,	/* FFUART transmit */

	MaxGPIObit=	84,
	MaxGPIOIRQ=	1,
};
#define	GPB(n)	(1<<((n)&31))
#define	GPR(n)	((n)>>5)
#define	GPAF(n,v)	((v)<<(((n)&15)*2))

void	gpioreserve(int);
void	gpioconfig(int, ulong);
ulong	gpioget(int);
void	gpioset(int, int);
void	gpiorelease(int);

enum {
	/* software configuration bits for gpioconfig */
	Gpio_gpio=	0<<0,
	Gpio_Alt1=	1<<0,
	Gpio_Alt2=	2<<0,
	Gpio_Alt3=	3<<0,
	Gpio_in=		1<<2,
	Gpio_out=	1<<3,
};

/*
 * software structures used by ../port/devi2c.c and iic.c
 */
struct I2Cdev {
	int	addr;
	int	salen;	/* length in bytes of subaddress, if used; 0 otherwise */
	int	tenbit;	/* 10-bit addresses */
};

long	i2crecv(I2Cdev*, void*, long, ulong);
long	i2csend(I2Cdev*, void*, long, ulong);
void	i2csetup(int);

#define COREREG	((Coreregs*)PHYSCORE)
typedef struct Coreregs Coreregs;
struct Coreregs {
	ulong	cccr;	/* core clock config */
	ulong	cken;	/* clock enable */
	ulong	oscc;	/* oscillator configuration */
};

#define RTCREG		((RTCreg*)PHYSRTC)
typedef struct RTCreg RTCreg;
struct RTCreg {
	ulong	rcnr;	/*  count */
	ulong	rtar;	/*  alarm */
	ulong	rtsr;	/*  status */
	ulong	rttr;	/*  trim */
};

#define OSTMRREG	((OstmrReg*)PHYSOSTMR)
typedef struct OstmrReg OstmrReg;
struct OstmrReg {
	ulong	osmr[4];	/*  match */
	ulong	oscr;		/*  counter */
	ulong	ossr;		/*  status */
	ulong	ower;		/*  watchdog */
	ulong	oier;		/*  interrupt enable */
};

#define PMGRREG		((PmgrReg*)PHYSPOWER)
typedef struct PmgrReg PmgrReg;
struct PmgrReg {
	ulong	pmcr;	/*  ctl register */
	ulong	pssr;		/*  sleep status */
	ulong	pspr;		/*  scratch pad */
	ulong	pwer;	/*  wakeup enable */
	ulong	prer;		/* rising-edge detect enable */
	ulong	pfer;		/* falling-edge detect enable */
	ulong	pedr;	/* GPIO edge detect status */
	ulong	pcfr;		/*  general configuration */
	ulong	pgsr[3];		/*  GPIO sleep state */
	ulong	rsvd;
	ulong	rcsr;		/* reset controller status register */
};

enum {
	/* pp. 3-25 to 3-31 */
	PWER_rtc		= 1<<31,	/* wakeup by RTC alarm */
	PWER_we0	= 1<<0,	/* wake-up on GP0 edge detect */

	PSSR_sss		= 1<<0,	/* software sleep status */
	PSSR_bfs		= 1<<1,	/* battery fault status */
	PSSR_vfs		= 1<<2,	/* VDD fault status */
	PSSR_ph		= 1<<4,	/* peripheral control hold */
	PSSR_rdh		= 1<<5,	/* read disable hold */

	PMFW_fwake=	1<<1,	/* fast wakeup enable (no power stabilisation delay) */

	RSCR_gpr=	1<<3,	/* gpio reset has occurred */
	RSCR_smr=	1<<2,	/* sleep mode has occurred */
	RSCR_wdr=	1<<1,	/* watchdog reset has occurred */
	RSCR_hwr=	1<<0,	/* hardware reset has occurred */
};

#define MEMCFGREG	((MemcfgReg*)PHYSMEMCFG)
typedef struct MemcfgReg MemcfgReg;
struct MemcfgReg {
	ulong	mdcnfg;		/*  SDRAM config */
	ulong	mdrefr;		/* dram refresh */
	ulong	msc0;		/* static memory or devices */
	ulong	msc1;
	ulong	msc2;		/* static memory or devices */
	ulong	mecr;		/* expansion bus (pcmcia, CF) */
	ulong	sxcnfg;	/* synchronous static memory control */
	ulong	sxmrs;	/* MRS value to write to SMROM */
	ulong	mcmem0;	/* card interface socket 0 memory timing */
	ulong	mcmem1;	/* card interface socket 1 memory timing */
	ulong	mcatt0;	/* socket 0 attribute memory timing */
	ulong	mcatt1;	/* socket 1 attribute memory timing */
	ulong	mcio0;	/* socket 0 i/o timing */
	ulong	mcio1;	/* socket 1 i/o timing */
	ulong	mdmrs;	/* MRS value to write to SDRAM */
	ulong	boot_def;	/* read-only boot-time register */
	ulong	mdmrslp;	/* low-power SDRAM mode register set config */
	ulong	sa1111cr;	/* SA1111 compatibility */
};

#define LCDREG		((LcdReg*)PHYSLCD)
typedef struct LcdReg LcdReg;
struct LcdReg {
	ulong	lccr0;	/*  control 0 */
	ulong	lccr1;	/*  control 1 */
	ulong	lccr2;	/*  control 2 */
	ulong	lccr3;	/*  control 3 */
	struct {
		ulong	fdadr;	/* dma frame descriptor address register */
		ulong	fsadr;	/* dma frame source address register */
		ulong	fidr;	/* dma frame ID register */
		ulong	ldcmd;	/* dma command */
	} frame[2];
	ulong	fbr[2];	/* frame branch register */
	ulong	lcsr;		/*  status  */
	ulong	liidr;	/* interrupt ID register */
	ulong	trgbr;	/* TMED RGB seed register */
	ulong	tcr;	/* TMED control register */
};

#define USBREG	((UsbReg*)PHYSUSB)
typedef struct UsbReg UsbReg;
struct UsbReg {
	ulong	udccr;	/*  control */
	ulong	udccs[16];	/* endpoint control/status */
	ulong	ufnrh;	/* frame number high */
	ulong	ufnrl;	/* frame number low */
	ulong	udbcr2;
	ulong	udbcr4;
	ulong	udbcr7;
	ulong	udbcr9;
	ulong	udbcr12;
	ulong	udbcr14;
	ulong	uddr[16];	/* endpoint data */
	ulong	uicr0;
	ulong	uicr1;
	ulong	usir0;
	ulong	usir1;
};

enum {
	/*  DMA configuration parameters */

	 /*  DMA Direction */
	DmaOut=		0,
	DmaIn=		1,

	 /*  dma devices */
	DmaDREQ0=		0,
	DmaDREQ1,
	DmaI2S_i,
	DmaI2S_o,
	DmaBTUART_i,
	DmaBTUART_o,
	DmaFFUART_i,
	DmaFFUART_o,
	DmaAC97mic,
	DmaAC97modem_i,
	DmaAC97modem_o,
	DmaAC97audio_i,
	DmaAC97audio_o,
	DmaSSP_i,
	DmaSSP_o,
	DmaNSSP_i,
	DmaNSSP_o,
	DmaICP_i,
	DmaICP_o,
	DmaSTUART_i,
	DmaSTUART_o,
	DmaMMC_i,
	DmaMMC_o,
	DmaRsvd0,
	DmaRsvd1,
	DmaUSB1,
	DmaUSB2,
	DmaUSB3,
	DmaUSB4,
	DmaHWUART_i,
	DmaUSB6,
	DmaUSB7,
	DmaUSB8,
	DmaUSB9,
	DmaHWUART_o,
	DmaUSB11,
	DmaUSB12,
	DmaUSB13,
	DmaUSB14,
	DmaRsvd2,
};

/*
 *	Interface to platform-specific PCMCIA signals, in arch*.c
 */
enum {
	/* argument to pcmpin() */
	PCMready,
	PCMeject,
	PCMstschng,
};

/*
 * physical device addresses are mapped to the same virtual ones,
 * allowing the same addresses to be used with or without mmu.
 */

#define PCMCIAcard(n)	(PHYSPCMCIA0+((n)*PCMCIASIZE))
#define PCMCIAIO(n)	(PCMCIAcard(n)+0x0)		/* I/O space */
#define PCMCIAAttr(n)	(PCMCIAcard(n)+0x8000000) /* Attribute space*/
#define PCMCIAMem(n)	(PCMCIAcard(n)+0xC000000) /* Memory space */

/*
 * PCMCIA structures known by both port/cis.c and the pcmcia driver
 */

/*
 * Map between ISA memory space and PCMCIA card memory space.
 */
struct PCMmap {
	ulong	ca;			/* card address */
	ulong	cea;			/* card end address */
	ulong	isa;			/* local virtual address */
	int	len;			/* length of the ISA area */
	int	attr;			/* attribute memory */
};

/*
 *  a PCMCIA configuration entry
 */
struct PCMconftab
{
	int	index;
	ushort	irqs;		/* legal irqs */
	uchar	irqtype;
	uchar	bit16;		/* true for 16 bit access */
	uchar	nlines;
	struct {
		ulong	start;
		ulong	len;
	} io[16];
	int	nio;
	uchar	vcc;
	uchar	vpp1;
	uchar	vpp2;
	uchar	memwait;
	ulong	maxwait;
	ulong	readywait;
	ulong	otherwait;
};

/*
 *  PCMCIA card slot
 */
struct PCMslot
{
	RWlock;

	Ref	ref;

	long	memlen;		/* memory length */
	uchar	slotno;		/* slot number */
	void	*regs;		/* i/o registers */
	void	*mem;		/* memory */
	void	*attr;		/* attribute memory */

	/* status */
	uchar	occupied;	/* card in the slot */
	uchar	configed;	/* card configured */
	uchar	busy;
	uchar	powered;
	uchar	battery;
	uchar	wrprot;
	uchar	enabled;
	uchar	special;
	uchar	dsize;

	/* cis info */
	int	cisread;	/* set when the cis has been read */
	char	verstr[512];	/* version string */
	uchar	cpresent;	/* config registers present */
	ulong	caddr;		/* relative address of config registers */
	int	nctab;		/* number of config table entries */
	PCMconftab	ctab[8];
	PCMconftab	*def;		/* default conftab */

	/* maps are fixed */
	PCMmap memmap;
	PCMmap attrmap;
};
