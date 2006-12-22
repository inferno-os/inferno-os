typedef struct Conf	Conf;
typedef struct FPU	FPU;
typedef struct FPenv	FPenv;
typedef struct IMM	IMM;
typedef struct Irqctl	Irqctl;
typedef struct ISAConf	ISAConf;
typedef struct Label	Label;
typedef struct Lock	Lock;
typedef struct Mach	Mach;
typedef struct Map	Map;
typedef struct Power Power;
typedef struct RMap RMap;
typedef struct Ureg	Ureg;

typedef ulong Instr;

#define	MACHP(n)	(n==0? &mach0 : *(Mach**)0)

struct	Lock
{
	ulong	key;
	ulong	pc;
	ulong	sr;
	int	pri;
};

struct	Label
{
	ulong	sp;
	ulong	pc;
};

/*
 * Proc.fpstate
 */
enum
{
	FPINIT,
	FPACTIVE,
	FPINACTIVE,
};

/*
 * This structure must agree with FPsave and FPrestore asm routines
 */
struct FPenv
{
	union {
		double	fpscrd;
		struct {
			ulong	pad;
			ulong	fpscr;
		};
	};
	int	fpistate;	/* emulated fp */
	ulong	emreg[32][3];	/* emulated fp */
};
/*
 * This structure must agree with fpsave and fprestore asm routines
 */
struct	FPU
{
	double	fpreg[32];
	FPenv	env;
};

struct Conf
{
	ulong	nmach;		/* processors */
	ulong	nproc;		/* processes */
	ulong	npage0;		/* total physical pages of memory */
	ulong	npage1;		/* total physical pages of memory */
	ulong	npage;		/* total physical pages of memory */
	ulong	base0;		/* base of bank 0 */
	ulong	base1;		/* base of bank 1 */
	ulong	ialloc;		/* max interrupt time allocation in bytes */

	int	nscc;	/* number of SCCs implemented */
	ulong	smcuarts;		/* bits for SMCs to define as eiaN */
	ulong	sccuarts;		/* bits for SCCs to define as eiaN  */
	int	nocts2;	/* CTS2 and CD2 aren't connected */
	uchar*	nvrambase;	/* virtual address of nvram */
	ulong	nvramsize;	/* size in bytes */
};

#include "../port/portdat.h"

/*
 *  machine dependent definitions not used by ../port/dat.h
 */

struct Mach
{
	/* OFFSETS OF THE FOLLOWING KNOWN BY l.s */
	int	machno;			/* physical id of processor (unused) */
	ulong	splpc;			/* pc of last caller to splhi (unused) */
	int	mmask;			/* 1<<m->machno (unused) */

	/* ordering from here on irrelevant */
	ulong	ticks;			/* of the clock since boot time */
	Proc	*proc;			/* current process on this processor */
	Label	sched;			/* scheduler wakeup */
	Lock	alarmlock;		/* access to alarm list */
	void	*alarm;			/* alarms bound to this clock */
	int	nrdy;
	int	speed;	/* general system clock in MHz */
	long	oscclk;	/* oscillator frequency (MHz) */
	long	cpuhz;	/* general system clock (cycles) */
	long	clockgen;	/* clock generator frequency (cycles) */
	int	cputype;
	ulong	delayloop;
	ulong*	bcsr;
	IMM*	iomem;	/* MPC8xx internal i/o control memory */

	/* MUST BE LAST */
	int	stack[1];
};
extern	Mach	mach0;


/*
 *  a parsed .ini line
 */
#define NISAOPT		8

struct ISAConf {
	char*	type;
	ulong	port;
	ulong	irq;
	ulong	mem;
	int	dma;
	ulong	size;
	ulong	freq;
	uchar	bus;

	int	nopt;
	char*	opt[NISAOPT];
};

struct Map {
	int	size;
	ulong	addr;
};

struct RMap {
	char*	name;
	Map*	map;
	Map*	mapend;

	Lock;
};

struct Power {
	Dev*	dev;
	int	(*powerdown)(Power*);
	int	(*powerup)(Power*);
	int	state;
	void*	arg;
};

extern register Mach	*m;
extern register Proc	*up;
