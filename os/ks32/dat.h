typedef struct Conf	Conf;
typedef struct FPU	FPU;
typedef struct FPenv	FPenv;
typedef struct Label	Label;
typedef struct Lock	Lock;
typedef struct Mach	Mach;
typedef struct Ureg	Ureg;
typedef struct ISAConf	ISAConf;
typedef struct PCMmap	PCMmap;
typedef struct PCIcfg	PCIcfg;
typedef struct TouchPnt TouchPnt;
typedef struct TouchTrans TouchTrans;
typedef struct TouchCal TouchCal;
typedef struct Vmode Vmode;

typedef ulong Instr;

#define ISAOPTLEN 16
#define NISAOPT 8
struct Conf
{
	ulong	nmach;			/* processors */
	ulong	nproc;			/* processes */
	ulong	npage0;			/* total physical pages of memory */
	ulong	npage1;			/* total physical pages of memory */
	ulong	topofmem;		/* highest physical address + 1 */
	ulong	npage;			/* total physical pages of memory */
	ulong	base0;			/* base of bank 0 */
	ulong	base1;			/* base of bank 1 */
	ulong	ialloc;			/* max interrupt time allocation in bytes */
	ulong	flashbase;
	ulong	cpuspeed;
	ulong	pagetable;

	int		useminicache;		/* screen.c/lcd.c */
	int		cansetbacklight;	/* screen.c/lcd.c */
	int		cansetcontrast;		/* screen.c/lcd.c */
	int		remaplo;			/* use alt ivec */
	int		textwrite;			/* writeable text segment, for debug */
};

struct ISAConf {
	char	type[KNAMELEN];
	ulong	port;
	ulong	irq;
	ulong	sairq;
	ulong	dma;
	ulong	mem;
	ulong	size;
	ulong	freq;

	int	nopt;
	char	opt[NISAOPT][ISAOPTLEN];
};

/*
 * FPenv.status
 */
enum
{
	FPINIT,
	FPACTIVE,
	FPINACTIVE,
};

struct	FPenv
{
	ulong	status;
	ulong	control;
	ushort	fpistate;	/* emulated fp */
	ulong	regs[8][3];	/* emulated fp */	
};

/*
 * This structure must agree with fpsave and fprestore asm routines
 */
struct	FPU
{
	FPenv	env;
	uchar	regs[80];	/* floating point registers */
};

struct Label
{
	ulong	sp;
	ulong	pc;
};

struct Lock
{
	ulong	key;
	ulong	sr;
	ulong	pc;
	int	pri;
};

#include "../port/portdat.h"

/*
 *  machine dependent definitions not used by ../port/dat.h
 */
struct Mach
{
	ulong	ticks;			/* of the clock since boot time */
	Proc	*proc;			/* current process on this processor */
	Label	sched;			/* scheduler wakeup */
	Lock	alarmlock;		/* access to alarm list */
	void	*alarm;			/* alarms bound to this clock */
	int	machno;
	int	nrdy;

	int	stack[1];
};

#define	MACHP(n)	(n == 0 ? (Mach*)(MACHADDR) : (Mach*)0)

extern Mach Mach0;
extern Mach *m;
extern Proc *up;

typedef struct MemBank {
	uint	pbase;
	uint	plimit;
	uint	vbase;
	uint	vlimit;
} MemBank;

enum {
	// DMA configuration parameters

	 // DMA Direction
	DmaOUT=		0,
	DmaIN=		1,

	 // dma endianess
	DmaLittle=	0,
	DmaBig=		1,

	 // dma devices
	DmaUDC=		0,
	DmaSDLC=	2,
	DmaUART0=	4,
	DmaHSSP=	6,
	DmaUART1=	7,	// special case (is really 6)
	DmaUART2=	8,
	DmaMCPaudio=	10,
	DmaMCPtelecom=	12,
	DmaSSP=		14,
};

enum touch_source {
	TOUCH_READ_X1, TOUCH_READ_X2, TOUCH_READ_X3, TOUCH_READ_X4,
	TOUCH_READ_Y1, TOUCH_READ_Y2, TOUCH_READ_Y3, TOUCH_READ_Y4,
	TOUCH_READ_P1, TOUCH_READ_P2,
	TOUCH_READ_RX1, TOUCH_READ_RX2,
	TOUCH_READ_RY1, TOUCH_READ_RY2,
	TOUCH_NUMRAWCAL = 10,
};

struct TouchPnt {
	int	x;
	int	y;
};

struct TouchTrans {
	int	xxm;
	int	xym;
	int	yxm;
	int	yym;
	int	xa;
	int	ya;
};

struct TouchCal {
	TouchPnt	p[4];	// screen points
	TouchPnt	r[4][4];// raw points
	TouchTrans 	t[4];	// transformations
	TouchPnt	err;	// maximum error
	TouchPnt	var;	// usual maximum variance for readings
	int 		ptp;	// pressure threshold for press
	int		ptr;	// pressure threshold for release
};

extern TouchCal touchcal;

struct Vmode {
	int	wid;	/* 0 -> default or any match for all fields */
	int	hgt;
	uchar	d;
	uchar	hz;
	ushort	flags;
};

enum {
	VMODE_MONO = 0x0001,    /* monochrome display */
	VMODE_COLOR = 0x0002,   /* color (RGB) display */
	VMODE_TFT = 0x0004,	/* TFT (active matrix) display */
	VMODE_STATIC = 0x0010,  /* fixed palette */
	VMODE_PSEUDO = 0x0020,  /* changeable palette */
	VMODE_LINEAR = 0x0100,  /* linear frame buffer */
	VMODE_PAGED = 0x0200,   /* paged frame buffer */
	VMODE_PLANAR = 0x1000,  /* pixel bits split between planes */
	VMODE_PACKED = 0x2000,  /* pixel bits packed together */
	VMODE_LILEND = 0x4000,	/* little endian pixel layout */
	VMODE_BIGEND = 0x8000,	/* big endian pixel layout */
};

/*
 *	Interface to PCMCIA stubs
 */
enum {
	/* argument to pcmpin() */
	PCMready,
	PCMeject,
	PCMstschng,
};

#define	swcursor	1
