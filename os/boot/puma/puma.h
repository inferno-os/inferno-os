/*
 * Teralogic TL750 - Puma Evaluation Board
 */
 
/*
 * Puma addresses
 */
#define EPROM_BASE	0x80000000	/* EPROM */
#define FLASH_BASE	0xa0000000	/* Flash */
#define TL750_BASE	0xc0000000	/* TL750 registers */
#define ISAMEM_BASE	0xe0000000	/* ISA memory space */
#define ISAIO_BASE		0xf0000000	/* ISA I/O space */

#define ISAIO_SHIFT	2
#define IOBADDR(io_port) (ISAIO_BASE + (io_port << ISAIO_SHIFT))

/* Hardware address register for interrupts (HARI) */
#define HARI1			0xE2000000 /* Interrupt status on read, User interrupt on write */
#define HARI2			0xE3000000 /* More interrupt status on read, LEDs on write */	
#define HARI1_FIQ_MASK	0x92	/* FIQ indicator bits in HARI1, others are IRQ */
#define HARI2_INIT			0x20	/* No timer2 aborts, Ethernet on IRQ */			



/*
 * Interrupt Vectors
 * corresponding to the HARIx_xxx_IRQ/FIQ bits above. 
 *
 * HARI1 interrupts 
 */
#define V_LPT				0		/* Parallel port interrupt */
#define V_NM0			1		/* MPEG Decode Interrupt */
#define V_NM1			2		/* MPEG Decode Interrupt */
#define V_COM2			3		/* Serial Port 2 Interrupt */
#define V_COM1			4       	/* Serial Port 1 Interrupt */
#define V_MOUSE			5		/* Mouse Interrupt */
#define V_KEYBOARD		6		/* Keyboard Interrupt */
#define V_ETHERNET		7		/* Ethernet Interrupt */
/* 
 * HARI2 interrupts 
 */
#define V_TIMER0			8		/* 82C54 Timer 0 Interrupt */
#define V_TIMER1			9		/* 82C54 Timer 1 Interrupt */
#define V_TIMER2			10		/* 82C54 Timer 2 Interrupt */
#define V_SOFTWARE		11		/* Software Interrupt */
#define V_IDE				12		/* IDE Hard Drive Interrupt */
#define V_SMARTCARD		13		/* Smart Card Interrupt */
#define V_TL750			14		/* TL750 Interrupt */
								/* Nothing in vector 15 for now */
#define V_MAXNUM     		15

/*
 * Definitions for National Semiconductor PC87306 SuperIO configuration
 */
#define SIO_CONFIG_INDEX		0x398	/* SuperIO configuration index register */
#define SIO_CONFIG_DATA			0x399	/* SuperIO configuration data register */

#define SIO_CONFIG_RESET_VAL		0x88	/* Value read from first read of sio_config_index reg after reset */
/*
 * PC87306 Configuration Registers (The value listed is the configuration space
 * index.)
 */
#define SIO_CONFIG_FER			0x00	/* Function Enable Register */

#define     FER_LPT_ENABLE				0x01	/* Enable Parallel Port */
#define     FER_UART1_ENABLE				0x02	/* Enable Serial Port 1 */
#define     FER_UART2_ENABLE				0x04	/* Enable Serial Port 2 */
#define     FER_FDC_ENABLE				0x08	/* Enable Floppy Controller */
#define     FER_FDC_4DRIVE_ENCODING			0x10	/* Select Floppy 4 Drive Encoding */
#define     FER_FDC_ADDR_ENABLE				0x20	/* Select Floppy Secondary Address */
								/* 0: [0x3F0..0x3F7] */
								/* 1: [0x370..0x377] */
#define     FER_IDE_ENABLE				0x40	/* Enable IDE Controller */
#define     FER_IDE_ADDR_SELECT				0x80	/* Select IDE Secondary Address */
								/* 0: [0x1F0..0x1F7,0x3F6,0x3F7] */
								/* 1: [0x170..0x177,0x376,0x377] */

#define SIO_CONFIG_FAR			0x01	/* Function Address Register */

#define     FAR_LPT_ADDR_MASK				0x03	/* Select LPT Address */
								/* If (PNP0[4] == 0) then: */
								/*     0: LPTB [0x378..0x37F] IRQ5/7 */
								/*     1: LPTA [0x3BC..0x3BE] IRQ7 */
								/*     2: LPTC [0x278..0x27F] IRQ5 */
								/*     3: Reserved */
								/* Else ignored. */
#define	FAR_LPT_LPTB	0	/* 0: LPTB 0x378 irq5/7 */
#define	FAR_LPT_LPTA	1	/* 1: LPTA 0x3BC irq 7 */
#define	FAR_LPT_LPTC	2	/* 2: LPTC 0x278 irq5 */

#define     FAR_UART1_ADDR_MASK				0x0C	/* Select Serial Port 1 Address */
								/* 0: COM1 [0x3F8..0x3FF] */
								/* 1: COM2 [0x2F8..0x2FF] */
								/* 2: COM3 (See FAR[7:6]) */
								/* 3: COM4 (See FAR[7:6]) */
#define	FAR_UART1_COM1		0x00 
#define     FAR_UART2_ADDR_MASK				0x30	/* Select Serial Port 2 Address */
								/* 0: COM1 [0x3F8..0x3FF] */
								/* 1: COM2 [0x2F8..0x2FF] */
								/* 2: COM3 (See FAR[7:6]) */
								/* 3: COM4 (See FAR[7:6]) */
#define	FAR_UART2_COM2		0x10
#define     FAR_EXTENDED_UART_ADDR_SELECT		0xC0	/* Extended Address Selects */
								/*    COM3@IRQ4,  COM4@IRQ3 */
								/* 0: COM3@0x3E8, COM4@0x2E8 */
								/* 1: COM3@0x338, COM4@0x238 */
								/* 2: COM3@0x2E8, COM4@0x2E0 */
								/* 3: COM3@0x220, COM4@0x228 */

#define SIO_CONFIG_PTR			0x02	/* Power & Test Register */

#define     PTR_POWER_DOWN				0x01	/* Power down all enabled functions */
#define     PTR_LPT_IRQ_SELECT				0x08	/* Select LPT IRQ if (FAR[1:0] == 0) */
								/* 0: IRQ5 */
								/* 1: IRQ7 */
#define     PTR_UART1_TEST_MODE				0x10	/* Set serial port 1 test mode */
#define     PTR_UART2_TEST_MODE				0x20	/* Set serial port 2 test mode */
#define     PTR_LOCK_CONFIGURATION			0x40	/* Prevent all further config writes */
								/* Only a RESET will reenable writes */
#define     PTR_LPT_EXTENDED_MODE_SELECT		0x80	/* Select Mode if not EPP/ECP */
								/* 0: Compatible Mode */
								/* 1: Extended Mode */

#define SIO_CONFIG_FCR			0x03	/* Function Control Register */
							/* WARNING: The FCR register must be written */
							/* using read-modify-write! */
#define     FCR_TDR_MODE_SELECT				0x01	/* ? (floppy/tape) */
#define     FCR_IDE_DMA_ENABLE				0x02	/* Enable IDE DMA mode */
#define     FCR_EPP_ZERO_WAIT_STATE			0x40	/* Enable EPP zero wait state */

#define SIO_CONFIG_PCR			0x04	/* Printer Control Register */

#define     PCR_EPP_ENABLE				0x01	/* Enable parallel port EPP mode */
#define     PCR_EPP_VERSION_SELECT			0x02	/* Select version of EPP mode */
								/* 0: Version 1.7 */
								/* 1: Version 1.9 (IEEE 1284) */
#define     PCR_ECP_ENABLE				0x04	/* Enable parallel port ECP mode */
#define     PCR_ECP_POWER_DOWN_CLOCK_ENABLE		0x08	/* Enable clock in power-down state */
								/* 0: Freeze ECP clock */
								/* 1: Run ECP clock */
#define     PCR_ECP_INT_POLARITY_CONTROL		0x20	/* Interrupt polarity control */
								/* 0: Level high or negative pulse */
								/* 1: Level low or positive pulse */
#define     PCR_ECP_INT_IO_CONTROL			0x40	/* Interrupt I/O control */
								/* WARNING: Slightly safer to choose */
								/* open drain if you don't know the */
								/* exact requirements of the circuit */
								/* 0: Totem-pole output */
								/* 1: Open drain output */
#define     PCR_RTC_RAM_WRITE_DISABLE			0x80	/* Disable writes to RTC RAM */
								/* 0: Enable writes */
								/* 1: Disable writes */

#define SIO_CONFIG_KRR			0x05	/* Keyboard & RTC Control Register */
							/* WARNING: The KRR register must be written */
							/* with a 1 in bit 2, else the KBC will not */
							/* work! */
#define     KRR_KBC_ENABLE				0x01	/* Enable keyboard controller */
#define     KRR_KBC_SPEED_CONTROL			0x02	/* Select clock divisor if !KRR[7] */
								/* 0: Divide by 3 */
								/* 1: Divide by 2 */
#define	    KRR_KBC_MUST_BE_1				0x04	/* Reserved: This bit must be 1! */
#define     KRR_RTC_ENABLE				0x08	/* Enable real time clock */
#define     KRR_RTC_RAMSEL				0x20	/* Select RTC RAM bank */
#define     KRR_KBC_CLOCK_SOURCE_SELECT			0x80	/* Select clock source */
								/* 0: Use X1 clock source */
								/* 1: Use SYSCLK clock source */

#define SIO_CONFIG_PMC			0x06	/* Power Management Control Register */

#define     PMC_IDE_TRISTATE_CONTROL			0x01	/* ? (power management) */
#define     PMC_FDC_TRISTATE_CONTROL			0x02	/* ? (power management) */
#define     PMC_UART1_TRISTATE_CONTROL			0x04	/* ? (power management) */
#define     PMC_SELECTIVE_LOCK				0x20	/* ? (power management) */
#define     PMC_LPT_TRISTATE_CONTROL			0x40	/* ? (power management) */

#define SIO_CONFIG_TUP			0x07	/* Tape, UARTS & Parallel Port Register */

#define     TUP_EPP_TIMEOUT_INT_ENABLE			0x04	/* Enable EPP timeout interrupts */

#define SIO_CONFIG_SID			0x08	/* Super I/O Identification Register */

#define     SID_ID_MASK					0xF8	/* Super I/O ID field */
#define         SID_ID_PC87306					0x70	/* PC87306 ID value */

#define SIO_CONFIG_ASC			0x09	/* Advanced Super I/O Config Register */
							/* WARNING: The ASC register must be written */
							/* with a 0 in bit 3! */
							/* WARNING: The ASC register resets to 1 in */
							/* bit 7 (PC/AT mode)! */
#define     ASC_VLD_MASK				0x03	/* ? (floppy/tape) */
#define     ASC_ENHANCED_TDR_SUPPORT			0x04	/* ? (floppy/tape) */
#define     ASC_MUST_BE_0				0x08	/* Reserved: Must be 0 */
#define     ASC_ECP_CNFGA				0x20	/* ? */
#define     ASC_DENSEL_POLARITY_BIT			0x40	/* ? (floppy/tape) */
#define     ASC_SYSTEM_OPERATION_MODE			0x80	/* Select system operation mode */
								/* 0: PS/2 mode */
								/* 1: PC/AT mode */

#define SIO_CONFIG_CS0LA			0x0A	/* Chip Select 0 Low Address Register */

#define SIO_CONFIG_CS0CF			0x0B	/* Chip Select 0 Configuration Register */
							/* WARNING: The CS0CF register must be */
							/* written with a 1 in bit 7! */
#define     CS0CF_CS0_DECODE				0x08	/* Select CS0 decode sensitivity */
								/* 0: Decode full 16-bit address */
								/* 1: Decode only bits 15 thru 12 */
#define     CS0CF_CS0_WRITE_ENABLE			0x10	/* Enable CS0 on write cycles */
#define     CS0CF_CS0_READ_ENABLE			0x20	/* Enable CS0 on read cycles */
#define     CS0CF_CS0_MUST_BE_1				0x80	/* Reserved: Must be 1 */

#define SIO_CONFIG_CS1LA			0x0C	/* Chip Select 1 Low Address Register */

#define SIO_CONFIG_CS1CF			0x0D	/* Chip Select 1 Configuration Register */

#define     CS1CF_CS1_DECODE				0x08	/* Select CS1 decode sensitivity */
								/* 0: Decode full 16-bit address */
								/* 1: Decode only bits 15 thru 12 */
#define     CS1CF_CS1_WRITE_ENABLE			0x10	/* Enable CS1 on write cycles */
#define     CS1CF_CS1_READ_ENABLE			0x20	/* Enable CS1 on read cycles */

#define SIO_CONFIG_IRC			0x0E	/* Infrared Configuration Register */

#define     IRC_UART2_INTERFACE_MODE			0x01	/* Select UART2 interface mode */
								/* 0: Normal (modem) mode */
								/* 1: IR mode */
#define     IRC_IR_FULL_DUPLEX				0x02	/* Select IR duplex mode */
								/* 0: Full duplex mode */
								/* 1: Half duplex mode */
#define     IRC_ENCODED_IR_TRANSMITTER_DRIVE		0x10	/* IR transmitter drive control */
								/* 0: IRTX active for 1.6usec */
								/* 1: IRTX active for 3/16 baud */
#define     IRC_ENCODED_IR_MODE				0x20	/* IR encode mode */
								/* 0: Encoded mode */
								/* 1: Non-encoded mode */

#define SIO_CONFIG_GPBA			0x0F	/* GP I/O Port Base Address Config Register */

#define SIO_CONFIG_CS0HA			0x10	/* Chip Select 0 High Address Register */

#define SIO_CONFIG_CS1HA			0x11	/* Chip Select 1 High Address Register */

#define SIO_CONFIG_SCF0			0x12	/* Super I/O Configuration Register 0 */

#define     SCF0_RTC_RAM_LOCK				0x01	/* Lock (1) will prevent all further */
								/* accesses to RTC RAM.  Only RESET */
								/* return this bit to a 0. */
#define     SCF0_IRQ1_12_LATCH_ENABLE			0x02	/* Enable IRQ1/IRQ12 latching */
#define     SCF0_IRQ12_TRISTATE				0x04	/* IRQ12 tri-state control */
								/* 0: Use quasi-bidirectional buffer */
								/* 1: Tri-state IRQ12 */
#define     SCF0_UART2_TRISTATE				0x08	/* Force UART2/IR outputs to */
								/* tri-state when disabled */
#define     SCF0_GPIO_PORT1_ENABLE			0x10	/* Enable GPIO port 1 */
#define     SCF0_GPIO_PORT2_ENABLE			0x20	/* Enable GPIO port 2 */

#define SIO_CONFIG_SCF1			0x18	/* Super I/O Configuration Register 1 */

#define     SCF1_REPORTED_ECP_DMA			0x06	/* Reported ECP DMA number */
								/* 0: Jumpered 8-bit DMA */
								/* 1: DMA channel 1 */
								/* 2: DMA channel 2 */
								/* 3: DMA channel 3 */
#define     SCF1_SELECTED_ECP_DMA			0x08	/* Selected ECP DMA pins */
								/* 0: PDRQ0 & PDACK0 */
								/* 1: PDRQ1 & PDACK1 */
#define     SCF1_SCRATCH_BITS				0xC0	/* ? */

#define SIO_CONFIG_LPTBA			0x19	/* LPT Base Address */

#define SIO_CONFIG_PNP0			0x1B	/* Plug & Play Configuration Register 0 */

#define     PNP0_LPT_INT_SELECT_CONTROL			0x10	/* LPT IRQ select control */
								/* 0: IRQ selected by FAR[1:0] */
								/* 1: IRQ selected by PNP0[5] */
#define     PNP0_LPT_INT_MAPPING			0x20	/* LPT IRQ mapping */
								/* 0: IRQ5 */
								/* 1: IRQ7 */
#define     PNP0_LPTA_BASE_ADDR_SELECT			0x40	/* LPTA base address */
								/* 0: Always 0x3BC */
								/* 1: Selected by LPTBA[7:0] */

#define SIO_CONFIG_PNP1			0x1C	/* Plug & Play Configuration Register 1 */

#define     PNP1_UARTS_INT_SELECT_CONTROL		0x01	/* UART interrupt select control */
								/* 0: Use FAR[3:2] & FAR[5:4] */
								/* 1: Use PNP1[2] & PNP1[6] */
#define     PNP1_UART1_INT_MAPPING			0x04	/* UART1 interrupt mapping */
								/* 0: IRQ3 */
								/* 1: IRQ4 */
#define     PNP1_UART2_INT_MAPPING			0x40	/* UART2 interrupt mapping */
								/* 0: IRQ3 */
								/* 1: IRQ4 */
/*---------------------------------------------------------------------------*/

/*
 * Definitions for the SuperIO UART.
 */
#define COM1_PORT       0x3f8   
#define COM2_PORT       0x2f8

/*
 * Register offsets.
 */
#define UART_RX    		0      /* Receive port, read only */
#define UART_TX         0      /* transmit port, write only */
#define UART_IER        1      /* Interrupt enable, read/write */
#define UART_IIR        2      /* Interrupt id, read only */
#define UART_FIFO_CONTROL 2    /* FIFO control, write only */
#define UART_LCR        3      /* Line control register */
#define UART_MCR      	4      /* Modem control register */
#define UART_LSR        5      /* Line Status register */
#define UART_MSR        6      /* Modem Status register */

/* with the DLAB bit set, the first two registers contain the baud rate */
#define UART_DLLSB      0
#define UART_DLMSB      1

/*
 * Line control register 
 */
#define LCR_DB          3      /* Data bits in transmission (0 = 5, 1 = 6, 2 = 7, 3 = 8) */
#define LCR_SB          4      /* Stop bit */
#define LCR_PE          8      /* Parity enable */
#define LCR_EP          16     /* Even parity */
#define LCR_SP          32     /* Stick parity */
#define LCR_BC          64     /* break control */
#define LCR_DLAB        128    /* Divisor latch access bit */


/*
 *  Modem Control register
 */
#define MCR_DTR			1	/* Data Terminal Ready */
#define MCR_RTS			2	/* Request To Send */
#define MCR_OUT1		4	/* Out1 (not used) */
#define MCR_IRQ_ENABLE  8	/* Enable IRQ */
#define MCR_LOOP		16	/* Loopback mode */

/*
 * Line status bits.
 */
#define    LSR_DR     0x01        /* Data ready                         */
#define    LSR_OE     0x02        /* Overrun error                      */
#define    LSR_PE     0x04        /* Parity error                       */
#define    LSR_FE     0x08        /* Framing error                      */
#define    LSR_BI     0x10        /* Break interrupt                    */
#define    LSR_THRE   0x20        /* Transmitter holding register empty */
#define    LSR_TEMT   0x40        /* Transmitter empty                  */
#define    LSR_FFE    0x80        /* Receiver FIFO error                */

#define LSR_ERROR       (LSR_OE | LSR_PE | LSR_FE) 

/*
 * Interrupt Identification register (IIR)
 */
#define IIR_IP          1     /* No Interrupt pending */
#define IIR_RECEIVE_LINE_STATUS	6 /* Overrun, Parity, Framing erros, Break */
#define IIR_RDA			4     /* Receive data available */
#define IIR_FIFO_FLAG	8     /* FIFO flag */
#define IIR_FIFO_TIMEOUT (IIR_RDA+IIR_FIFO_FLAG)  /* Got data some time ago, but FIFO time out */
#define IIR_THRE		2     /* Transmitter holding register empty. */
#define IIR_MS			0     /* CTS, DSR, RING, DCD changed */
#define IIR_HPIP        6     /* Highest priority interrupt pending */

/*
 * Interrupt enable register (IER)
 */
#define IER_RDA         1     /* Received data available */
#define IER_THRE        2     /* Transmitter holding register empty */
#define IER_RLS         4     /* Receiver line status */
#define IER_MS          8     /* Modem status */

/*
 * PC87306 Parallel I/O Port
 */
#define LPT1_PORT		0x03BC

/*
 * PC87306 General Purpose I/O Ports
 */
#define GPIO1_PORT		0x0078
#define GPIO2_PORT		0x0079

/*
 * PC87306 IDE Port
 */
#define IDE_PORT_1		0x01F0
#define IDE_PORT_2		0x03F6
#define IDE_PORT_3		0x03F7

/*
 * PC87306 Floppy Port
 */
#define FDC_PORT		0x03F0

/*
 * PC87306 Real Time Clock/battery backed up RAM port
 */
#define RTC_INDEX_PORT		0x0070
#define RTC_DATA_PORT		0x0071

/*
 * Offsets in RTC memory (RAMSEL = 0)
 */
#define RTC_SECONDS			0
#define	RTC_SECONDS_ALARM	1
#define RTC_MINUTES			2
#define RTC_MINUTES_ALARM	3
#define RTC_HOURS			4
#define RTC_HOURS_ALARM		5
#define RTC_DAY_OF_WEEK		6
#define RTC_DAY_OF_MONTH	7
#define RTC_MONTH			8
#define RTC_YEAR			9
#define RTC_CONTROL_A		0xA
#define RTC_CONTROL_B		0xB
#define RTC_CONTROL_C		0xC
#define RTC_CONTROL_D		0xD

#define RTC_NVRAM0_START	0xE
#define RTC_NVRAM0_SIZE		114
#define RTC_NVRAM1_START	0
#define RTC_NVRAM1_SIZE		128
#define	RTC_NVRAM_SIZE		(RTC_NVRAM0_SIZE+RTC_NVRAM1_SIZE)

#define RTC_PWNVRAM_START	0x38	/* Start of protected NVRAM */
#define RTC_PWNVRAM_SIZE	8		/* Size of protected NVRAM */


/*
 * PC87306 Keyboard controller ports
 */
#define KEYBD_DATA_PORT		0x0060
#define KEYBD_CTRL_PORT 	0x0064
