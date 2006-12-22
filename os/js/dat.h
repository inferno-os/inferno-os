typedef struct Conf	Conf;
typedef struct FPenv	FPenv;
typedef struct FPU	FPU;
typedef struct Label	Label;
typedef struct Lock	Lock;
typedef struct Mach	Mach;
typedef struct Ureg	Ureg;
typedef struct Lance	Lance;
typedef struct Lancemem	Lancemem;
typedef struct Etherpkt	Etherpkt;
typedef struct Lancepkt	Lancepkt;

typedef	ulong	Instr;

struct Conf
{
	int	nmach;		/* processors */
	int	nproc;		/* processes */
	ulong	monitor;	/* graphics monitor id; 0 for none */
	char	ss2;		/* is a sparcstation 2 */
	char	ss2cachebug;	/* has sparcstation2 cache bug */
	int	ncontext;	/* in mmu */
	int	vacsize;	/* size of virtual address cache, in bytes */
	int	vaclinesize;	/* size of cache line */
	ulong	npage0;		/* total physical pages of memory, bank 0 */
	ulong	npage1;		/* total physical pages of memory, bank 1 */
	ulong	base0;		/* base of bank 0 */
	ulong	base1;		/* base of bank 1 */
	ulong	ialloc;		/* max interrupt time allocation in bytes */
	ulong	npage;		/* total physical pages of memory */
	int	copymode;	/* 0 is copy on write, 1 is copy on reference */
	ulong	ipif;		/* Ip protocol interfaces */
	ulong	ip;		/* Ip conversations per interface */
	ulong	arp;		/* Arp table size */
	ulong	frag;		/* Ip fragment assemble queue size */
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
	ulong	pad;
};

/*
 * This structure must agree with fpsave and fprestore asm routines
 */
struct	FPU
{

	double	regs[17];	/* floating point registers */
	FPenv	env;
};

/*
 *  machine dependent definitions used by ../port/dat.h
 */

struct Label
{
	ulong	sp;
	ulong	pc;
};

struct Lock
{
	ulong	key;
	ulong	pc;
	ulong	sr;
	int	pri;
};

#include "../port/portdat.h"

/*
 *  machine dependent definitions not used by ../port/dat.h
 */

struct Mach
{
	ulong	ticks;			/* of the clock since boot time */
	int		machno;			/* physical id of this processor */
	Proc	*proc;			/* current process on this processor */
	Label	sched;			/* scheduler wakeup */
	Lock	alarmlock;		/* access to alarm list */
	void	*alarm;			/* alarms bound to this clock */
	ulong	*contexts;		/* hardware context table */
	ulong	*ctx;			/* the context */
	int	fptrap;			/* FP trap occurred while unsave */

	int	nrdy;

	int	stack[1];
};

/*
 * XXX - Eric: It just works....
 */

/*
 *  LANCE CSR3 (bus control bits)
 */
#define BSWP	0x4
#define ACON	0x2
#define BCON	0x1

struct Lancepkt
{
	uchar	d[6];
	uchar	s[6];
	uchar	type[2];
	uchar	data[1500];
	uchar	crc[4];
};

/*
 *  system dependent lance stuff
 *  filled by lancesetup() 
 */
struct Lance
{
	ushort	lognrrb;	/* log2 number of receive ring buffers */
	ushort	logntrb;	/* log2 number of xmit ring buffers */
	ushort	nrrb;		/* number of receive ring buffers */
	ushort	ntrb;		/* number of xmit ring buffers */
	ushort	*rap;		/* lance address register */
	ushort	*rdp;		/* lance data register */
	ushort	busctl;		/* bus control bits */
	uchar	ea[6];		/* our ether addr */
	int	sep;		/* separation between shorts in lance ram
				    as seen by host */
	ushort	*lanceram;	/* start of lance ram as seen by host */
	Lancemem *lm;		/* start of lance ram as seen by lance */
	Lancepkt *rp;		/* receive buffers (host address) */
	Lancepkt *tp;		/* transmit buffers (host address) */
	Lancepkt *lrp;		/* receive buffers (lance address) */
	Lancepkt *ltp;		/* transmit buffers (lance address) */
};

/*
 * Fake kmap
 */
typedef void		KMap;
#define	VA(k)		((ulong)(k))
#define	kmap(p)		(KMap*)((p)->pa|KZERO)
#define	kunmap(k)
#define	MACHP(n)	(n==0? &mach0 : *(Mach**)0)

extern Mach *m;
extern Proc *up;
extern Mach mach0;

#define	swcursor	1
