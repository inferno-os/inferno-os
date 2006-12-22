/*
 * most device registers are memory mapped, but
 * a few things are accessed using putphys/getphys
 */
#define	SBUS(n)		(0x30000000+(n)*0x10000000)
#define	FRAMEBUF(n)	SBUS(n)
#define	FRAMEBUFID(n)	(SBUS(n)+0x000000)
#define	DISPLAYRAM(n)	(SBUS(n)+0x800000)
#define	CLOCK		0x71D00000
#define	CLOCKFREQ	1000000		/* one microsecond increments */

#define SUPERIO_PHYS_PAGE		0x71300000
#define SUPERIO_INDEX_OFFSET		0x398
#define SUPERIO_DATA_OFFSET		0x399
#define SUPERIO_MOUSE_KBD_DATA_PORT	0x60
#define SUPERIO_MOUSE_KBD_CTL_PORT	0x64

#define AUDIO_PHYS_PAGE		0x66666666
#define AUDIO_INDEX_OFFSET	0x830

enum
{
	Mousevec = 13,
	Kbdvec = 13
};

#define	NVR_CKSUM_PHYS	0x71200000	/* non-volatile RAM cksum page */
#define	NVR_PHYS	0x71201000	/* non-volatile RAM */
#define DMA		0x78400000	/* SCSI and Ether DMA registers */
#define SCSI		0x78800000	/* NCR53C90 registers */
#define	ETHER		0x78C00000	/* RDP, RAP */
#define	FLOPPY		0x71400000
#define	SYSINTR		0x71E10000	/* system interrupt control registers */

#define	TIMECONFIG	0x71D10010	/* timer configuration register (phys) */
#define	AUXIO1		0x71900000
#define	AUXIO2		0x71910000

typedef struct Sysint Sysint;
struct Sysint
{
	ulong	pending;
	ulong	mask;
	ulong	maskclr;
	ulong	maskset;
	ulong	target;
};

enum {
	MaskAllIntr = 1<<31,
	MEIntr = 1<<30,
	MSIIntr = 1<<29,
	EMCIntr = 1<<28,
	VideoIntr = 1<<20,	/* supersparc only */
	Timer10 = 1<<19,
	EtherIntr = 1<<16,
	SCCIntr = 1<<15,
	KbdIntr = 1<<13,
	/* bits 7 to 13 are SBUS levels 1 to 7 */
};
#define	SBUSINTR(x)	(1<<((x)+6))

typedef struct SCCdev	SCCdev;
struct SCCdev
{
	uchar	ptrb;
	uchar	dummy1;
	uchar	datab;
	uchar	dummy2;
	uchar	ptra;
	uchar	dummy3;
	uchar	dataa;
	uchar	dummy4;
};

/*
 *  non-volatile ram
 */
#define NVREAD	(4096-32)	/* minus RTC */
#define NVWRITE	(0x800)		/* */
#define	IDOFF	(4096-8-32)

/*
 * real-time clock
 */
typedef struct RTCdev	RTCdev;
struct RTCdev
{
	uchar	control;		/* read or write the device */
	uchar	sec;
	uchar	min;
	uchar	hour;
	uchar	wday;
	uchar	mday;
	uchar	mon;
	uchar	year;
};
#define RTCOFF		0xFF8
#define RTCREAD		(0x40)
#define RTCWRITE	(0x80)

/*
 * dma
 */
typedef struct DMAdev DMAdev;
struct DMAdev {
	/* ESP/SCSI DMA */
	ulong	csr;			/* Control/Status */
	ulong	addr;			/* address in 16Mb segment */
	ulong	count;			/* transfer byte count */
	ulong	diag;

	/* Ether DMA */
	ulong	ecsr;			/* Control/Status */
	ulong	ediag;
	ulong	cache;			/* cache valid bits */
	uchar	base;			/* base address (16Mb segment) */
};

enum {
	Int_pend	= 0x00000001,	/* interrupt pending */
	Err_pend	= 0x00000002,	/* error pending */
	Pack_cnt	= 0x0000000C,	/* pack count (mask) */
	Int_en		= 0x00000010,	/* interrupt enable */
	Dma_Flush	= 0x00000020,	/* flush pack end error */
	Drain		= 0x00000040,	/* drain pack to memory */
	Dma_Reset	= 0x00000080,	/* hardware reset (sticky) */
	Write		= 0x00000100,	/* set for device to memory (!) */
	En_dma		= 0x00000200,	/* enable DMA */
	Req_pend	= 0x00000400,	/* request pending */
	Byte_addr	= 0x00001800,	/* next byte addr (mask) */
	En_cnt		= 0x00002000,	/* enable count */
	Tc		= 0x00004000,	/* terminal count */
	Ilacc		= 0x00008000,	/* which ether chip */
	Dev_id		= 0xF0000000,	/* device ID */
};

/*
 *  NCR53C90 SCSI controller (every 4th location)
 */
typedef struct SCSIdev	SCSIdev;
struct SCSIdev {
	uchar	countlo;		/* byte count, low bits */
	uchar	pad1[3];
	uchar	countmi;		/* byte count, middle bits */
	uchar	pad2[3];
	uchar	fifo;			/* data fifo */
	uchar	pad3[3];
	uchar	cmd;			/* command byte */
	uchar	pad4[3];
	union {
		struct {		/* read only... */
			uchar	status;		/* status */
			uchar	pad05[3];
			uchar	intr;		/* interrupt status */
			uchar	pad06[3];
			uchar	step;		/* sequence step */
			uchar	pad07[3];
			uchar	fflags;		/* fifo flags */
			uchar	pad08[3];
			uchar	config;		/* RW: configuration */
			uchar	pad09[3];
			uchar	Reserved1;
			uchar	pad0A[3];
			uchar	Reserved2;
			uchar	pad0B[3];
			uchar	conf2;		/* RW: configuration */
			uchar	pad0C[3];
			uchar	conf3;		/* RW: configuration */
			uchar	pad0D[3];
			uchar	partid;		/* unique part id */
			uchar	pad0E[3];
			uchar	fbottom;	/* RW: fifo bottom */
			uchar	pad0F[3];
		};
		struct {		/* write only... */
			uchar	destid;		/* destination id */
			uchar	pad15[3];
			uchar	timeout;	/* during selection */
			uchar	pad16[3];
			uchar	syncperiod;	/* synchronous xfr period */
			uchar	pad17[3];
			uchar	syncoffset;	/* synchronous xfr offset */
			uchar	pad18[3];
			uchar	RW0;
			uchar	pad19[3];
			uchar	clkconf;
			uchar	pad1A[3];
			uchar	test;	
			uchar	pad1B[3];
			uchar	RW1;
			uchar	pad1C[3];
			uchar	RW2;
			uchar	pad1D[3];
			uchar	counthi;	/* byte count, hi bits */
			uchar	pad1E[3];
			uchar	RW3;
			uchar	pad1F[3];
		};
	};
};

/*
 * DMA2 ENET
 */
enum {
	E_Int_pend	= 0x00000001,	/* interrupt pending */
	E_Err_pend	= 0x00000002,	/* error pending */
	E_draining	= 0x0000000C,	/* E-cache draining */
	E_Int_en	= 0x00000010,	/* interrupt enable */
	E_Invalidate	= 0x00000020,	/* mark E-cache invalid */
	E_Slave_err	= 0x00000040,	/* slave access size error (sticky) */
	E_Reset		= 0x00000080,	/* invalidate cache & reset interface (sticky) */
	E_Drain		= 0x00000400,	/* force draining of E-cache to memory */
	E_Dsbl_wr_drn	= 0x00000800,	/* disable E-cache drain on descriptor writes from ENET */
	E_Dsbl_rd_drn	= 0x00001000,	/* disable E-cache drain on slave reads to ENET */
	E_Ilacc		= 0x00008000,	/* `modifies ENET DMA cycle' */
	E_Dsbl_buf_wr	= 0x00010000,	/* disable buffering of slave writes to ENET */
	E_Dsbl_wr_inval	= 0x00020000,	/* do not invalidate E-cache on slave writes */
	E_Burst_size	= 0x000C0000,	/* DMA burst size */
	E_Loop_test	= 0x00200000,	/* loop back mode */
	E_TP_select	= 0x00400000,	/* zero for AUI mode */
	E_Dev_id	= 0xF0000000,	/* device ID */
};
