#pragma	src	"/sys/src/libg"
#pragma	lib	"libg.a"

enum	/* constants for I/O to devgraphics */
{
	Tilehdr = 40,
	Tilesize = 8000
};

/*
 *  you may think it's a blit, but it's gnot
 */
enum
{
	EMAXMSG = 128+8192,	/* size of 9p header+data */
};

/*
 * Types
 */

typedef struct	Bitmap		Bitmap;
typedef struct	Display	Display;
typedef struct	Point		Point;
typedef struct	Rectangle 	Rectangle;
typedef struct	Cursor		Cursor;
typedef struct	Mouse		Mouse;
typedef struct	Menu		Menu;
typedef struct	Font		Font;
typedef struct	Fontchar	Fontchar;
typedef struct	Subfont		Subfont;
typedef struct	Cachefont	Cachefont;
typedef struct	Cacheinfo	Cacheinfo;
typedef struct	Cachesubf	Cachesubf;
typedef struct	Event		Event;
typedef struct	Slave		Slave;
typedef struct	Ebuf		Ebuf;
typedef struct	RGB		RGB;
typedef struct	Linedesc	Linedesc;
typedef struct	DRefret	DRefret;

struct DRefret
{
	int		n;	/* number of bytes */
	int		dy;	/* number of lines */
	uchar	*dp;	/* pointer to data */
};

struct	Point
{
	int	x;
	int	y;
};

struct Rectangle
{
	Point min;
	Point max;
};

typedef	DRefret DRefresh(Display*, int, Rectangle, uchar*, uchar*, int);

struct	Bitmap
{
	Rectangle		r;		/* rectangle in data area, local coords */
	Rectangle 	clipr;		/* clipping region */
	int			ldepth;	/* log base 2 of number of bits per pixel */
	ulong		*base;	/* pointer to start of data */
	int			zero;		/* base+zero=&word containing (0,0) */
	ulong		width;	/* width in words of total data area */
	Display		*display;	/* if present */
};

struct	Display
{
	uchar		*data;	/* transfer buffer */
	Rectangle		r;
	int			ldepth;
	Rectangle		bb;		/* bounding box of changes */
	int			waste;	/* unused part of bb */
	Rectangle		bound;	/* memory for boundin/boundout */
	Bitmap		*image;	/* owner */
	int			id;
	int			fd;
	int			ctlfd;
	int			local;
	int			bytewidth;
	void			*drdata1;	/* storage for drefresh() */
	void			*drdata2;	/* storage for drefresh() */
	DRefresh		*drefresh;
};


struct	Mouse
{
	int	buttons;	/* bit array: LMR=124 */
	Point	xy;
	ulong	msec;
};

struct	Cursor
{
	Point	offset;
	uchar	clr[2*16];
	uchar	set[2*16];
};

struct Menu
{
	char	**item;
	char	*(*gen)(int);
	int	lasthit;
};

struct Linedesc
{
	int	x0;
	int	y0;
	char	xmajor;
	char	slopeneg;
	long	dminor;
	long	dmajor;
};

/*
 * Subfonts
 *
 * given char c, Subfont *f, Fontchar *i, and Point p, one says
 *	i = f->info+c;
 *	bitblt(b, Pt(p.x+i->left,p.y+i->top),
 *		bitmap, Rect(i->x,i->top,(i+1)->x,i->bottom),
 *		fc);
 *	p.x += i->width;
 * where bitmap b is the repository of the images.
 *
 */

struct	Fontchar
{
	short	x;		/* left edge of bits */
	uchar	top;		/* first non-zero scan-line */
	uchar	bottom;		/* last non-zero scan-line + 1 */
	char	left;		/* offset of baseline */
	uchar	width;		/* width of baseline */
};

struct	Subfont
{
	short	n;		/* number of chars in font */
	uchar	height;		/* height of bitmap */
	char	ascent;		/* top of bitmap to baseline */
	Fontchar *info;		/* n+1 character descriptors */
	Bitmap	*bits;		/* of font */
};

enum
{
	/* starting values */
	LOG2NFCACHE =	6,
	NFCACHE =	(1<<LOG2NFCACHE),	/* #chars cached */
	NFLOOK =	5,			/* #chars to scan in cache */
	NFSUBF =	2,			/* #subfonts to cache */
	/* max value */
	MAXFCACHE =	2048+NFLOOK,		/* generous upper limit */
	MAXSUBF =	50,			/* generous upper limit */
	/* deltas */
	DSUBF = 	4,
	/* expiry ages */
	SUBFAGE	=	10000,
	CACHEAGE =	10000,
};

struct Cachefont
{
	Rune	min;	/* lowest rune value to be taken from subfont */
	Rune	max;	/* highest rune value+1 to be taken from subfont */
	int	offset;	/* position in subfont of character at min */
	int	abs;	/* name has been made absolute */
	char	*name;
};

struct Cacheinfo
{
	Rune		value;	/* value of character at this slot in cache */
	ushort		age;
	ulong		xright;	/* right edge of bits */
	Fontchar;
};

struct Cachesubf
{
	ulong		age;	/* for replacement */
	Cachefont	*cf;	/* font info that owns us */
	Subfont		*f;	/* attached subfont */
};

struct Font
{
	char		*name;
	short		height;	/* max height of bitmap, interline spacing */
	short		ascent;	/* top of bitmap to baseline */
	int			maxldepth;	/* over all loaded subfonts */
	short		width;	/* widest so far; used in caching only */	
	short		ldepth;	/* of images */
	short		nsub;	/* number of subfonts */
	ulong		age;	/* increasing counter; used for LRU */
	int		ncache;	/* size of cache */
	int		nsubf;	/* size of subfont list */
	Cacheinfo	*cache;
	Cachesubf	*subf;
	Cachefont	**sub;	/* as read from file */
	Bitmap	*cacheimage;
};

struct	Event
{
	int	kbdc;
	Mouse	mouse;
	int	n;		/* number of characters in mesage */
	uchar	data[EMAXMSG];	/* message from an arbitrary file descriptor */
};

struct Slave{
	int	pid;
	Ebuf	*head;		/* queue of messages for this descriptor */
	Ebuf	*tail;
};

struct Ebuf{
	Ebuf	*next;
	int	n;		/* number of bytes in buf */
	uchar	buf[EMAXMSG];
};

struct RGB
{
	ulong	red;
	ulong	green;
	ulong	blue;
};

/*
 * Codes for bitblt etc.
 *
 *	       D
 *	     0   1
 *         ---------
 *	 0 | 1 | 2 |
 *     S   |---|---|
 * 	 1 | 4 | 8 |
 *         ---------
 *
 *	Usually used as D|S; DorS is so tracebacks are readable.
 */
typedef
enum	Fcode
{
	Zero		= 0x0,
	DnorS		= 0x1,
	DandnotS	= 0x2,
	notS		= 0x3,
	notDandS	= 0x4,
	notD		= 0x5,
	DxorS		= 0x6,
	DnandS		= 0x7,
	DandS		= 0x8,
	DxnorS		= 0x9,
	D		= 0xA,
	DornotS		= 0xB,
	S		= 0xC,
	notDorS		= 0xD,
	DorS		= 0xE,
	F		= 0xF,
} Fcode;

/*
 * Miscellany
 */

extern Point	 add(Point, Point), sub(Point, Point);
extern Point	 mul(Point, int), div(Point, int);
extern Rectangle rsubp(Rectangle, Point), raddp(Rectangle, Point), inset(Rectangle, int);
extern Rectangle rmul(Rectangle, int), rdiv(Rectangle, int);
extern Rectangle rshift(Rectangle, int), rcanon(Rectangle);
extern Bitmap*	 balloc(Rectangle, int);
extern Bitmap*	 ballocnomem(Rectangle, int);
extern Bitmap*	 brealloc(Bitmap*, Rectangle, int);
extern Bitmap*	 breallocnomem(Bitmap*, Rectangle, int);
extern int		bbytewidth(Bitmap*, int*, int*);
extern void	 bfree(Bitmap*);
extern void	 bfreemem(Bitmap*);
extern int	 rectclip(Rectangle*, Rectangle);
extern void	 binit(void(*)(char*), char*, char*);
extern void	 binit1(void(*)(char*), char*, char*, int);
extern void	 bclose(void);
extern void	 berror(char*);
extern void	 bitblt(Bitmap*, Point, Bitmap*, Rectangle, Fcode);
extern int	 bitbltclip(void*);
extern Font*	 rdfontfile(char*, int);
extern void	 ffree(Font*);
extern void	fminldepth(Font*);
extern Font*	 mkfont(Subfont*, Rune);
extern Subfont*	 subfalloc(int, int, int, Fontchar*, Bitmap*);
extern void	 subffree(Subfont*);
extern int	 cachechars(Font*, char**, ushort*, int, int*);
extern Point	 string(Bitmap*, Point, Font*, char*, Fcode);
extern Point	 subfstring(Bitmap*, Point, Subfont*, char*, Fcode);
extern void	 segment(Bitmap*, Point, Point, int, Fcode);
extern void	 point(Bitmap*, Point, int, Fcode);
extern void	 arc(Bitmap*, Point, Point, Point, int, Fcode);
extern void	 circle(Bitmap*, Point, int, int, Fcode);
extern void	 disc(Bitmap*, Point, int, int, Fcode);
extern void	 ellipse(Bitmap*, Point, int, int, int, Fcode);
extern long	 strwidth(Font*, char*);
extern void	 agefont(Font*);
extern int	 loadchar(Font*, Rune, Cacheinfo*, int, int);
extern Point	 strsize(Font*, char*);
extern long	 charwidth(Font*, Rune);
extern void	 texture(Bitmap*, Rectangle, Bitmap*, Fcode);
extern void	 wrbitmap(Bitmap*, int, int, uchar*);
extern void	 rdbitmap(Bitmap*, int, int, uchar*);
extern void	 wrbitmapfile(int, Bitmap*);
extern Bitmap*	 rdbitmapfile(int);
extern void	 wrsubfontfile(int, Subfont*);
extern void	 wrcolmap(Bitmap*, RGB*);
extern void	 rdcolmap(Bitmap*, RGB*);
extern Subfont*	 rdsubfontfile(int, Bitmap*);
extern void	_unpackinfo(Fontchar*, uchar*, int);

extern int	 ptinrect(Point, Rectangle), rectinrect(Rectangle, Rectangle);
extern int	 rectXrect(Rectangle, Rectangle);
extern int	 eqpt(Point, Point), eqrect(Rectangle, Rectangle);
extern void	 border(Bitmap*, Rectangle, int, Fcode);
extern void	 cursorswitch(Cursor*);
extern void	 cursorset(Point);
extern Rectangle bscreenrect(Rectangle*);
extern void	 bflush(void);
extern void	 bexit(void);
extern int	 _clipline(Rectangle, Point*, Point*, Linedesc*);
extern int	 clipline(Rectangle, Point*, Point*);
extern int	 clipr(Bitmap*, Rectangle);

extern void	 einit(ulong);
extern ulong	 estart(ulong, int, int);
extern ulong	 etimer(ulong, int);
extern ulong	 event(Event*);
extern ulong	 eread(ulong, Event*);
extern Ebuf*	 ebread(Slave*);
extern Mouse	 emouse(void);
extern int	 ekbd(void);
extern int	 ecanread(ulong);
extern int	 ecanmouse(void);
extern int	 ecankbd(void);
extern void	 ereshaped(Rectangle);	/* supplied by user */
extern int	 menuhit(int, Mouse*, Menu*);
extern Rectangle getrect(int, Mouse*);
extern ulong	 rgbpix(Bitmap*, RGB);
extern int	_gminor(long, Linedesc*);

enum{
	Emouse		= 1,
	Ekeyboard	= 2,
};

enum
{
	MAXSLAVE = 32,
};

#define	Pt(x, y)		((Point){(x), (y)})
#define	Rect(x1, y1, x2, y2)	((Rectangle){Pt(x1, y1), Pt(x2, y2)})
#define	Rpt(p1, p2)		((Rectangle){(p1), (p2)})


#define	Dx(r)	((r).max.x-(r).min.x)
#define	Dy(r)	((r).max.y-(r).min.y)

extern	Bitmap	screen;
extern	Font	*font;
extern	uchar	_btmp[8192];

extern	int	_mousefd;
extern	int	_cursorfd;

#define	BGSHORT(p)		(((p)[0]<<0) | ((p)[1]<<8))
#define	BGLONG(p)		((BGSHORT(p)<<0) | (BGSHORT(p+2)<<16))
#define	BPSHORT(p, v)		((p)[0]=(v), (p)[1]=((v)>>8))
#define	BPLONG(p, v)		(BPSHORT(p, (v)), BPSHORT(p+2, (v)>>16))

ulong	*wordaddr(Bitmap*, Point);
uchar	*byteaddr(Bitmap*, Point);
int		dfree(Display*);
int		dwritectl(Display*, char*, int);
int		dreadctl(Display*, char*, int);
int		dinfo(Display*, int, int*, Rectangle*);
void*	dinit(Display*, Bitmap*, int, int);
int		ddelete(Display*);
void		dfreemem(Display*);
int		dreadctl(Display*, char*, int);
int		dwritectl(Display*, char*, int);
void	dbound(Display*, Rectangle);
void	bload(Bitmap*, Rectangle, uchar*);
ulong	bunload(Bitmap*, Rectangle, uchar*);
void		drefresh(Display*, Rectangle);
Display	*dopen(char*, int, DRefresh*);
Bitmap*	dbitmap(Display*, DRefresh*, int);
void		dclose(Display*);
void		dflush(Display*);
void		_bltinit(void);
Bitmap*	battach(Bitmap*, int, int);
int		readmouse(Mouse*);
int		atomouse(Mouse*, char*, int);

/*
 * Refresh functions
 */
DRefresh	drtexture;
DRefresh	drbackstore;
