typedef struct PCMconftab PCMconftab;
typedef struct PCMmap	PCMmap;
typedef struct PCMslot	PCMslot;

/*
 * physical device addresses are mapped to the same virtual ones,
 * allowing the same addresses to be used with or without mmu.
 */

#define PCMCIAcard(n)	(PHYSPCMCIA0+((n)*PCMCIASIZE))
#define PCMCIAIO(n)	(PCMCIAcard(n)+0x0)		/* I/O space */
#define PCMCIAAttr(n)	(PCMCIAcard(n)+0x8000000) /* Attribute space*/
#define PCMCIAMem(n)	(PCMCIAcard(n)+0xC000000) /* Memory space */

#define INTRREG 	((IntrReg*)PHYSINTR)
typedef struct IntrReg IntrReg;
struct IntrReg {
	ulong	icip;	/*  IRQ pending */
	ulong	icmr;	/*  mask */
	ulong	iclr;	/*  level */
	ulong	iccr;	/*  control */
	ulong	icfp;	/*  FIQ pending */
	ulong	rsvd[3];
	ulong	icpr;	/*  pending */
};

#define GPIObit(n)	(n)			/* GPIO Edge Detect bits */
#define LCDbit		(12)			/* LCD Service Request */
#define UDCbit		(13)			/* UDC Service Request */
#define SDLCbit		(14)			/* SDLC Service Request */
#define UARTbit(n)	(15+((n)-1))		/* UART Service Request */
#define HSSPbit		(16)			/* HSSP Service Request */
#define MCPbit		(18)			/* MCP Service Request */
#define SSPbit		(19)			/* SSP Serivce Request */
#define DMAbit(chan)	(20+(chan))		/* DMA channel Request */
#define OSTimerbit(n)	(26+(n))		/* OS Timer Request */
#define RTCticbit	(30)			/* One Hz tic occured */
#define RTCalarmbit	(31)			/* RTC = alarm register */
#define MaxIRQbit	31			/* Maximum IRQ */
#define MaxGPIObit	27			/* Maximum GPIO */

#define GPIOREG		((GpioReg*)PHYSGPIO)
typedef struct GpioReg GpioReg;
struct GpioReg {
	ulong gplr;
	ulong gpdr;
	ulong gpsr;
	ulong gpcr;
	ulong grer;
	ulong gfer;
	ulong gedr;
	ulong gafr;
};

enum {
	/* GPIO alternative functions if gafr bit set (see table on page 9-9) */
	GPIO_32KHZ_OUT_o = 1<<27,	/* raw 32.768kHz oscillator output */
	GPIO_RCLK_OUT_o = 1<<26,	/* internal clock/2 (must also set TUCR) */
	GPIO_RTC_clock_o = 1<<25,	/* real time clock out */
	GPIO_TREQB_i = 1<<23,	/* TIC request B */
	GPIO_TREQA_i = 1<<22,	/* TIC request A (or MBREQ) */
	GPIO_TICK_ACK_o = 1<<21,	/* TIC ack (or MBGNT), when output */
	GPIO_MCP_CLK_i = 1<<21,	/* MCP clock in, when input */
	GPIO_UART_SCLK3_i = 1<<20,	/* serial port 3 UART sample clock input */
	GPIO_SSP_CLK_i = 1<<19,	/* serial port 2 SSP sample clock input */
	GPIO_UART_SCLK1_i = 1<<18,	/* serial port 1 UART sample clock input */
	GPIO_GPCLK_OUT_o = 1<<16,	/* serial port 1 general-purpose clock out */
	GPIO_UART_RXD_i = 1<<15,	/* serial port 1 UART receive */
	GPIO_UART_TXD_o = 1<<14,	/* serial port 1 UART transmit */
	GPIO_SSP_SFRM_o = 1<<13,	/* SSP frame clock out */
	GPIO_SSP_SCLK_o = 1<<12,	/* SSP serial clock out */
	GPIO_SSP_RXD_i = 1<<11,	/* SSP receive */
	GPIO_SSP_TXD_o = 1<<10,	/* SSP transmit */
	GPIO_LDD8_15_o = 0xFF<<2,	/* high-order LCD data (bits 8-15) */
	GPIO_LDD15_o = 1<<9,
	GPIO_LDD14_o = 1<<8,
	GPIO_LDD13_o = 1<<7,
	GPIO_LDD12_o = 1<<6,
	GPIO_LDD11_o = 1<<5,
	GPIO_LDD10_o = 1<<4,
	GPIO_LDD9_o = 1<<3,
	GPIO_LDD8_o = 1<<2,
};

#define RTCREG		((RtcReg*)PHYSRTC)
typedef struct RtcReg RtcReg;
struct RtcReg {
	ulong	rtar;	/*  alarm */
	ulong	rcnr;	/*  count */
	ulong	rttr;	/*  trim */
	ulong	rsvd;
	ulong	rtsr;	/*  status */
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
	ulong	pcfr;		/*  general conf */
	ulong	ppcr;	/*  PLL configuration */
	ulong	pgsr;		/*  GPIO sleep state */
	ulong	posr;		/*  oscillator status */
};

enum
{
	/* page 9-35 to 40 */
	PCFR_opde	= 1<<0,	/* oscillator powers down in sleep */
	PCFR_fp		= 1<<1,	/* float pcmcia */
	PCFR_fs		= 1<<2,	/* float static memory */
	PCFR_fo		= 1<<3,	/* force 32k oscillator on */

	PWER_rtc		= 1<<31,	/* wakeup by RTC alarm */

	PSSR_sss		= 1<<0,	/* software sleep status */
	PSSR_bfs		= 1<<1,	/* battery fault status */
	PSSR_vfs		= 1<<2,	/* VDD fault status */
	PSSR_dh		= 1<<3,	/* DRAM control held */
	PSSR_ph		= 1<<4,	/* peripheral control hold */
};

#define RESETREG	((ResetReg*)PHYSRESET)
typedef struct ResetReg ResetReg;
struct ResetReg {
	ulong	rsrr;		/*  software reset */
	ulong	rcsr;		/*  status */
	ulong	tucr;		/*  reserved for test */
};

#define MEMCFGREG	((MemcfgReg*)PHYSMEMCFG)
typedef struct MemcfgReg MemcfgReg;
struct MemcfgReg {
	ulong	mdcnfg;		/*  DRAM config */
	ulong	mdcas0[3];	/* dram banks 0/1 */
	ulong	msc0;		/* static memory or devices */
	ulong	msc1;
	ulong	mecr;		/* expansion bus (pcmcia, CF) */
	ulong	mdrefr;		/* dram refresh */
	ulong	mdcas2[3];	/* dram banks 2/3 */
	ulong	msc2;		/* static memory or devices */
	ulong	smcnfg;		/* SMROM config */
};

#define DMAREG(n)	((DmaReg*)(PHYSDMA+0x20*(n)))
typedef struct DmaReg DmaReg;
struct DmaReg {
	ulong	ddar;	/*  DMA device address */
	ulong	dcsr_s;	/*  set  */
	ulong	dcsr_c; /*  clear  */
	ulong	dcsr;   /*  read */
	struct {
		ulong	start;
		ulong	count;
	} buf[2];
};

#define LCDREG		((LcdReg*)PHYSLCD)
typedef struct LcdReg LcdReg;
struct LcdReg {
	ulong	lccr0;	/*  control 0 */
	ulong	lcsr;		/*  status  */
	ulong	rsvd[2];
	ulong	dbar1;	/*  DMA chan 1, base */
	ulong	dcar1;	/*  DMA chan 1, count */
	ulong	dbar2;	/*  DMA chan 2, base */
	ulong	dcar2;	/*  DMA chan 2, count */
	ulong	lccr1;	/*  control 1 */
	ulong	lccr2;	/*  control 2 */
	ulong	lccr3;	/*  control 3 */
};

/* Serial devices:
 *	0	USB		Serial Port 0
 *	1	UART	Serial Port 1
 *	2	SDLC		"
 *	3	UART	Serial Port 2 (eia1)
 *	4	ICP/HSSP		"
 *	5	ICP/UART	Serial Port 3 (eia0)
 *	6	MPC		Serial Port 4
 *	7	SSP			"
 */ 

#define USBREG	((UsbReg*)PHYSUSB)
typedef struct UsbReg UsbReg;
struct UsbReg {
	ulong	udccr;	/*  control */
	ulong	udcar;	/*  address */
	ulong	udcomp;	/*  out max packet */
	ulong	udcimp;	/*  in max packet */
	ulong	udccs0;	/*  endpoint 0 control/status */
	ulong	udccs1;	/*  endpoint 1(out) control/status */
	ulong	udccs2;	/*  endpoint 2(int) control/status */
	ulong	udcd0;	/*  endpoint 0 data register */
	ulong	udcwc;	/*  endpoint 0 write control register */
	ulong	rsvd1;
	ulong	udcdr;	/*  transmit/receive data register (FIFOs) */
	ulong	rsvd2;
	ulong	dcsr;	/*  status/interrupt register */
};

#define GPCLKREG	((GpclkReg*)PHYSGPCLK)
typedef struct GpclkReg GpclkReg;
struct GpclkReg {
	ulong	gpclkr0;
	ulong	rsvd[2];
	ulong	gpclkr1;
	ulong	gpclkr2;
};

/* UARTs 1, 2, 3 are mapped to serial devices 1, 3, and 5 */
#define UARTREG(n)	((UartReg*)(PHYSSERIAL(2*(n)-1)))
typedef struct UartReg UartReg;
struct UartReg {
	ulong	utcr0;	/*  control 0 (bits, parity, clocks) */
	ulong	utcr1;	/*  control 1 (bps div hi) */
	ulong	utcr2;	/*  control 2 (bps div lo) */
	ulong	utcr3;	/*  control 3 */
	ulong	utcr4;	/*  control 4 (only serial port 2 (device 3)) */
	ulong	utdr;		/*  data */
	ulong	rsvd;
	ulong	utsr0;	/*  status 0 */
	ulong	utsr1;	/*  status 1 */
};

#define HSSPREG		((HsspReg*)(0x80040060))
typedef struct HsspReg HsspReg;
struct HsspReg {
	ulong	hscr0;	/*  control 0 */
	ulong	hscr1;	/*  control 1 */
	ulong	rsvd1;
	ulong	hsdr;		/*  data */
	ulong	rsvd2;
	ulong	hssr0;	/*  status 0 */
	ulong	hssr1;	/*  status 1 */
};

#define MCPREG		((McpReg*)(PHYSMCP))
typedef struct McpReg McpReg;
struct McpReg {
	ulong	mccr;
	ulong	rsvd1;
	ulong	mcdr0;
	ulong	mcdr1;
	ulong	mcdr2;
	ulong	rsvd2;
	ulong	mcsr;
};

enum {
	MCCR_M_LBM= 0x800000,
	MCCR_M_ARM= 0x400000,
	MCCR_M_ATM= 0x200000,
	MCCR_M_TRM= 0x100000,
	MCCR_M_TTM= 0x080000,
	MCCR_M_ADM= 0x040000,
	MCCR_M_ECS= 0x020000,
	MCCR_M_MCE= 0x010000,
	MCCR_V_TSD= 8,
	MCCR_V_ASD= 0,

	MCDR2_M_nRW= 0x010000,
	MCDR2_V_RN= 17,

	MCSR_M_TCE= 0x8000,
	MCSR_M_ACE= 0X4000,
	MCSR_M_CRC= 0x2000,
	MCSR_M_CWC= 0x1000,
	MCSR_M_TNE= 0x0800,
	MCSR_M_TNF= 0x0400,
	MCSR_M_ANE= 0x0200,
	MCSR_M_ANF= 0x0100,
	MCSR_M_TRO= 0x0080,
	MCSR_M_TTU= 0x0040,
	MCSR_M_ARO= 0x0020,
	MCSR_M_ATU= 0x0010,
	MCSR_M_TRS= 0x0008,
	MCSR_M_TTS= 0x0004,
	MCSR_M_ARS= 0x0002,
	MCSR_M_ATS= 0x0001,
};

#define SSPREG		((SspReg*)PHYSSSP)
typedef struct SspReg SspReg;
struct SspReg {
	ulong	sscr0;	/*  control 0 */
	ulong	sscr1;	/*  control 1 */
	ulong	rsvd1;
	ulong	ssdr;	/*  data */
	ulong	rsvd2;
	ulong	sssr;	/*  status */
};

enum {
	SSCR0_V_SCR= 0x08,
	SSCR0_V_SSE= 0x07,
	SSCR0_V_ECS= 0x06,
	SSCR0_V_FRF= 0x04,

	SSPCR0_M_DSS= 0x0000000F,
	SSPCR0_M_FRF= 0x00000030,
	SSPCR0_M_SSE= 0x00000080,
	SSPCR0_M_SCR= 0x0000FF00,
	SSPCR0_V_DSS= 0,
	SSPCR0_V_FRF= 4,
	SSPCR0_V_SSE= 7,
	SSPCR0_V_SCR= 8,

	SSPCR1_M_RIM= 0x00000001,
	SSPCR1_M_TIN= 0x00000002,
	SSPCR1_M_LBM= 0x00000004,
	SSPCR1_V_RIM= 0,
	SSPCR1_V_TIN= 1,
	SSPCR1_V_LBM= 2,

	SSPSR_M_TNF= 0x00000002,
	SSPSR_M_RNE= 0x00000004,
	SSPSR_M_BSY= 0x00000008,
	SSPSR_M_TFS= 0x00000010,
	SSPSR_M_RFS= 0x00000020,
	SSPSR_M_ROR= 0x00000040,
	SSPSR_V_TNF= 1,
	SSPSR_V_RNE= 2,
	SSPSR_V_BSY= 3,
	SSPSR_V_TFS= 4,
	SSPSR_V_RFS= 5,
	SSPSR_V_ROR= 6,
};

#define PPCREG		((PpcReg*)PHYSPPC)
typedef struct PpcReg PpcReg;
struct PpcReg {
	ulong	ppdr;	/*  pin direction */
	ulong	ppsr;		/*  pin state */
	ulong	ppar;	/*  pin assign */
	ulong	psdr;		/*  sleep mode */
	ulong	ppfr;		/*  pin flag reg */
	uchar	rsvd[0x1c]; /*  pad to 0x30 */
	ulong	mccr1;	/*  MCP control register 1 */
};

enum {
	/* ppdr and ppsr: =0, pin is general-purpose input; =1, pin is general-purpose output (11-168)*/
	PPC_LDD0_7=	0xFF<<0,	/* LCD data pins 0 to 7 */
	PPC_L_PCLK=	1<<8,	/* LCD pixel clock */
	PPC_L_LCLK=	1<<9,	/* LCD line clock */
	PPC_L_FCLK=	1<<10,	/* LCD frame clock */
	PPC_L_BIAS=	1<<11,	/* LCD AC bias */
	PPC_TXD1=	1<<12,	/* serial port 1 UART transmit */
	PPC_RXD1=	1<<13,	/* serial port 1 UART receive */
	PPC_TXD2=	1<<14,	/* serial port 2 IPC transmit */
	PPC_RXD2=	1<<15,	/* serial port 2 IPC receive */
	PPC_TXD3=	1<<16,	/* serial port 3 UART transmit */
	PPC_RXD3=	1<<17,	/* serial port 3 UART receive */
	PPC_TXD4=	1<<18,	/* serial port 4 MCP/SSP transmit */
	PPC_RXD4=	1<<19,	/* serial port 4 MCP/SSP receive */
	PPC_SCLK=	1<<20,	/* serial port 4 MCP/SSP serial clock */
	PPC_SFRM=	1<<21,	/* serial port 4 MCP/SSP frame clock */

	PPAR_UPR=	1<<12,	/* =1, serial port 1 GPCLK/UART pins reassigned */
	PPAR_SPR=	1<<18,	/* =1, SSP pins reassigned */
};

/*
 *	Irq Bus goo
 */

enum {
	BusCPU= 1,
	BusGPIOfalling= 2,	/* falling edge */
	BusGPIOrising = 3,	/* rising edge */
	BusGPIOboth = 4,	/* both edges */
	BusMAX= 4,
	BUSUNKNOWN= -1,
};

enum {
	/*  DMA configuration parameters */

	 /*  DMA Direction */
	DmaOUT=		0,
	DmaIN=		1,

	 /*  dma endianess */
	DmaLittle=	0,
	DmaBig=		1,

	 /*  dma devices */
	DmaUDC=		0,
	DmaSDLC=	2,
	DmaUART0=	4,
	DmaHSSP=	6,
	DmaUART1=	7,	/*  special case (is really 6) */
	DmaUART2=	8,
	DmaMCPaudio=	10,
	DmaMCPtelecom=	12,
	DmaSSP=		14,
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
	struct {
		ulong	start;
		ulong	len;
	} io[16];
	int	nio;
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
	int	ncfg;		/* number of configurations */
	struct {
		ushort	cpresent;	/* config registers present */
		ulong	caddr;		/* relative address of config registers */
	} cfg[8];
	int	nctab;		/* number of config table entries */
	PCMconftab	ctab[8];
	PCMconftab	*def;		/* default conftab */

	/* maps are fixed */
	PCMmap memmap;
	PCMmap attrmap;
};
