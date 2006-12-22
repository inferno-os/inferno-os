typedef struct Pop Pop;
typedef struct Iop Iop;
typedef struct IPoint IPoint;
typedef struct IRectangle IRectangle;
typedef struct Plugin Plugin;

enum {
	// messages from Plugin to Inferno
	Pgfxkey,
	Pmouse,

	// message from Inferno to Plugin
	Iattachscr,
	Iflushscr,
	Isetcur,
	Idrawcur,
	Iquit,
};

struct Pop {
	int	op;
	union {
		int key;			// Pgfxkey
		struct {
			int	x;
			int	y;
			int	b;
			int	modify;
		} m;				// Pmouse
	} u;
};

struct IPoint
{
	LONG	x;
	LONG	y;
};

struct IRectangle
{
	IPoint	min;
	IPoint	max;
};

struct Iop {
	int	op;
	int	val;
	union {
		IRectangle	r;		// Iflushscr
		// need additional support for Isetcur & Idrawcur
	} u;
};
#define PI_NCLOSE	2

struct Plugin {
	LONG sz;				// size of this data struct (including screen mem)
	HANDLE	conin;		// console input (from plugin) - never NULL
	HANDLE	conout;		// console output (to plugin) - can be NULL
	HANDLE	datain;		// #C data file for initialisation (HACK!)
	HANDLE	dopop;		// new Pop available
	HANDLE	popdone;		// acknowledgement of Pop
	HANDLE	doiop;		// new Iop available
	HANDLE	iopdone;		// acknowledgement of Iop
	HANDLE	closehandles[PI_NCLOSE];
	Pop pop;
	Iop iop;
	int Xsize;				// screen dimensions
	int Ysize;
	ULONG cdesc;			// display chans descriptor
	int cflag;
	ULONG screen[1];
};

#define IOP	(plugin->iop)
#define POP	(plugin->pop)
