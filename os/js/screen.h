typedef struct Cursor Cursor;
typedef struct Vctlr Vctlr;
typedef struct Video Video;
typedef struct Thc Thc;

#define FSVSLOT 2			/* MrCoffee Hard Coded FB Location */

struct	Cursor
{
	Point	offset;
	uchar	clr[2*16];
	uchar	set[2*16];
};

struct Vctlr {
	char*	name;
	Vctlr*	(*init)(Vctlr*, int, int, int);
	void	(*page)(int);
	int	(*setcolor)(ulong, ulong, ulong, ulong);

	void	(*enable)(void);
	void	(*disable)(void);
	void	(*move)(int, int);
	void	(*load)(Cursor*);
	int	(*isloaded)(void);
	int	(*cursorintersectsoff)(Rectangle*);

	int	x;
	int	y;
	int	d;

	Vctlr*	link;

	int	hidecount;
	int	loaded;
	Cursor	cursor;
	Lock	l;
};


struct Video
{
	/* Brooktree 458/451 */
	ulong	addr;		/* address register */
	ulong	color;		/* color palette */
	ulong	cntrl;		/* control register */
	ulong	ovrl;		/* overlay palette */
};

