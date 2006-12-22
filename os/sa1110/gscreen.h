typedef struct Cursor Cursor;
typedef struct LCDmode LCDmode;
typedef struct LCDparam LCDparam;
typedef struct Vmode Vmode;
typedef struct Physdisplay Physdisplay;
typedef struct Physcursor Physcursor;

#define CURSWID	16
#define CURSHGT	16

struct Cursor {
	Point	offset;
	uchar	clr[CURSWID/BI2BY*CURSHGT];
	uchar	set[CURSWID/BI2BY*CURSHGT];
};

struct Vmode {
	int	x;	/* 0 -> default or any match for all fields */
	int	y;
	uchar	depth;
	uchar	hz;
};

struct Physdisplay {
	uchar*	fb;		/* frame buffer */
	ulong	colormap[256][3];
	Rectangle	r;
	int	bwid;
	void*	aux;
	Memimage*	gscreen;
	Memsubfont*	memdefont;
	Physcursor*	cursor;
	void*	cdata;	/* cursor data */
	Lock;
	Vmode;
};

struct LCDparam {
	uchar	pbs;
	uchar	dual;
	uchar	mono;
	uchar	active;
	uchar	hsync_wid;
	uchar	sol_wait;
	uchar	eol_wait;
	uchar	vsync_hgt;
	uchar	sof_wait;
	uchar	eof_wait;
	uchar	lines_per_int;
	uchar	palette_delay;
	uchar	acbias_lines;
	uchar	obits;
	uchar	vsynclow;
	uchar	hsynclow;
};

struct LCDmode {
	Vmode;
	LCDparam;
};

int	archlcdmode(LCDmode*);

Vdisplay	*lcd_init(LCDmode*);
void	lcd_setcolor(ulong, ulong, ulong, ulong);
void	lcd_flush(void);

extern void	blankscreen(int);
extern void	drawblankscreen(int);
extern ulong blanktime;
extern Point mousexy(void);

enum {
	Backgnd = 0xFF,	/* white */
	Foregnd =	0x00,	/* black */
};

struct Physcursor {
	char*	name;

	void	(*create)(Physdisplay*);
	void	(*enable)(Physdisplay*);
	void	(*disable)(Physdisplay*);
	void	(*load)(Physdisplay*, Cursor*);
	int	(*move)(Physdisplay*, Point);
	void	(*destroy)(Physdisplay*);
};
