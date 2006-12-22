enum {
	Pcolours	= 256,		/* Palette */
	Pred		= 0,
	Pgreen		= 1,
	Pblue		= 2,

	Pblack		= 0x00,
	Pwhite		= 0xFF,
};

typedef struct Cursor Cursor;
struct	Cursor
{
	Point	offset;
	uchar	clr[2*16];
	uchar	set[2*16];
};

/*
 * MPC8xx LCD controller
 */
typedef struct LCDconfig {
	long	freq;	/* ideal panel frequency in Hz */
	int	wbl;	/* wait between lines (shift/clk cycles) */
	int	vpw;	/* vertical sync pulse width (lines) */
	int	wbf;	/* wait between frames (lines) */
	int	ac;	/* AC timing (frames) */
	ulong	flags;
	ulong	notpdpar;	/* reset mask for pdpar */
} LCDconfig;

enum {
	/* lccr flags stored in LCDconfig.flags */
	ClockLow = 1<<11,
	OELow = 1<<10,
	HsyncLow = 1<<9,
	VsyncLow = 1<<8,
	DataLow = 1<<7,
	Passive8 = 1<<4,
	DualScan = 1<<3,
	IsColour = 1<<2,
	IsTFT = 1<<1,
};

/*
 * physical graphics device properties set by archlcdmode
 */
typedef struct Mode {
	int	x;
	int	y;
	int	d;

	uchar*	aperture;
	int	apsize;
	LCDconfig	lcd;
} Mode;

int	archlcdmode(Mode*);
extern	Point	mousexy(void);
extern void	blankscreen(int);