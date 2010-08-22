typedef struct TkText TkText;
typedef struct TkTitem TkTitem;
typedef struct TkTline TkTline;
typedef struct TkTindex TkTindex;
typedef struct TkTmarkinfo TkTmarkinfo;
typedef struct TkTtaginfo TkTtaginfo;
typedef struct TkTwind TkTwind;

enum
{
	/* text item types */
	TkTascii,	/* contiguous string of ascii chars, all with same tags */
	TkTrune,	/* printable utf (one printing position) */
	TkTtab,
	TkTnewline,	/* line field contains pointer to containing line */
	TkTcontline,	/* end of non-newline line; line field as with TkTnewline */
	TkTwin,
	TkTmark,

	TkTbyitem = 0,	/* adjustment units */
	TkTbyitemback,
	TkTbytline,
	TkTbytlineback,
	TkTbychar,
	TkTbycharback,
	TkTbycharstart,
	TkTbyline,
	TkTbylineback,
	TkTbylinestart,
	TkTbylineend,
	TkTbywordstart,
	TkTbywordend,
	TkTbywrapstart,
	TkTbywrapend,

	TkTselid	= 0,		/* id of sel tag */
	TkTmaxtag	= 32,
	Textwidth	= 40,		/* default width, in chars */
	Textheight	= 10,		/* default height, in chars */

	TkTfirst	= (1<<0),	/* first line in buffer, or after a TkTlast */
	TkTlast		= (1<<1),	/* TkTnewline at end of line */
	TkTdrawn	= (1<<2),	/* screen cache copy is ok */
	TkTdlocked	= (1<<3),	/* display already locked */
	TkTjustfoc	= (1<<4),	/* got focus on last B1 press */
	TkTnodrag		= (1<<5),	/* ignore B1 drag until B1 up */
	TkTunset 	= (1<<31),	/* marks int tag options "unspecified" */

	TkTborderwidth	= 0,
	TkTjustify,
	TkTlmargin1,
	TkTlmargin2,
	TkTlmargin3,
	TkTrmargin,
	TkTspacing1,
	TkTspacing2,
	TkTspacing3,
	TkToffset,
	TkTunderline,
	TkToverstrike,
	TkTrelief,
	TkTwrap,
	TkTlineheight,

	TkTnumopts
};

struct TkTline
{
	Point		orig;		/* where to put first item of line */
	int		width;
	int		height;
	int		ascent;
	int		flags;
	TkTitem*	items;
	TkTline*	next;
	TkTline*	prev;
};

struct TkText
{
	TkTline		start;		/* fake before-the-first line */
	TkTline		end;		/* fake after-the-last line */
	Tk*			tagshare;
	TkTtabstop*	tabs;
	TkTtaginfo*	tags;
	TkTmarkinfo*	marks;
	char*		xscroll;
	char*		yscroll;
	uchar		selunit;	/* select adjustment unit */
	uchar		tflag;		/* various text-specific flags */
	int			nlines;	/* number of nl items in widget */
	TkTitem*	selfirst;	/* first item marked with sel tag */
	TkTitem*	sellast;	/* item after last marked with sel tag */
	Point		deltatv;	/* vector from text-space to view-space */
	Point		deltaiv;	/* vector from image-space to view-space */
	Point		current;	/* last known mouse pos */
	Point		track;	/* for use when B1 or B2 is down */
	int		nexttag;	/* next usable tag index */
	TkTitem*	mouse;		/* mouse focus */
	int		inswidth;	/* width of insertion cursor */
	int		sborderwidth;
	int		opts[TkTnumopts];
	int		propagate;
	int		scrolltop[2];
	int		scrollbot[2];
	Image*		image;
	uchar		cur_flag;	/* text cursor to be shown up? */
	Rectangle	cur_rec;	/* last text cursor rectangle */
};

struct TkTwind
{
	Tk*		sub;		/* Subwindow of canvas */
	Tk*		focus;		/* Current Mouse focus */
	int		width;		/* current internal width */
	int		height;		/* current internal height */
	int		owned;	/* true if window is destroyed on item deletion */
	int		align;		/* how to align within line */
	char*		create;		/* creation script */
	int		padx;		/* extra space on each side */
	int		pady;		/* extra space on top and bot */
	int		ascent;		/* distance from top of widget to baseline */
	int		stretch;	/* true if need to stretch height */
};

struct TkTitem
{
	uchar		kind;		/* e.g. TkTascii, etc */
	uchar		tagextra;
	short		width;
	TkTitem		*next;
	union	{
		char*		string;
		TkTwind*	win;
		TkTmarkinfo*	mark;
		TkTline*	line;
	} u;
	ulong		tags[1];
	/* TkTitem length extends tagextra ulongs beyond */
};

struct TkTmarkinfo
{
	char*		name;
	int		gravity;
	TkTitem*	cur;
	TkTmarkinfo*	next;
};

struct TkTtaginfo
{
	int		id;
	char*		name;
	TkEnv*		env;
	TkTtabstop*	tabs;
	TkTtaginfo*	next;
	TkAction*	binds;		/* Binding of current events */
	int		opts[TkTnumopts];
};

struct TkTindex
{
	TkTitem*	item;
	TkTline*	line;
	int		pos;		/* index within multichar item */
};

extern	TkCmdtab	tkttagcmd[];
extern	TkCmdtab	tktmarkcmd[];
extern	TkCmdtab	tktwincmd[];

extern	void		tkfreetext(Tk*);
extern	char*		tktaddmarkinfo(TkText*, char*, TkTmarkinfo**);
extern	char*		tktaddtaginfo(Tk*, char*, TkTtaginfo**);
extern	int		tktadjustind(TkText*, int, TkTindex*);
extern	int		tktanytags(TkTitem*);
extern	Rectangle	tktbbox(Tk*, TkTindex*);
extern	void		tktdirty(Tk*);
extern	int		tktdispwidth(Tk*, TkTtabstop *tabs, TkTitem*, Font*, int, int, int);
extern	void		tktendind(TkText*, TkTindex*);
extern	char*	tktextcursor(Tk*, char*, char **);
extern	Tk*		tktextevent(Tk*, int, void*);
extern	Tk*		tktinwindow(Tk*, Point*);
extern	char*		tktextselection(Tk*, char*, char**);
extern	void		tktextsize(Tk*, int);
extern	TkTmarkinfo*	tktfindmark(TkTmarkinfo*, char*);
extern	int		tktfindsubitem(Tk*, TkTindex*);
extern	TkTtaginfo*	tktfindtag(TkTtaginfo*, char*);
extern	char*		tktfixgeom(Tk*, TkTline*, TkTline*, int);
extern	void		tktfreeitems(TkText*, TkTitem*, int);
extern	void		tktfreelines(TkText*, TkTline*, int);
extern	void		tktfreemarks(TkTmarkinfo*);
extern	void		tktfreetabs(TkTtabstop*);
extern	void		tktfreetags(TkTtaginfo*);
extern	int		tktindcompare(TkText*, TkTindex*, int, TkTindex*);
extern	int		tktindbefore(TkTindex*, TkTindex*);
extern	int		tktindrune(TkTindex*);
extern	char*		tktinsert(Tk*, TkTindex*, char*, TkTitem*);
extern	int	tktisbreak(int);
extern	void		tktitemind(TkTitem*, TkTindex*);
extern	char*		tktiteminsert(TkText*, TkTindex*, TkTitem*);
extern	TkTline*	tktitemline(TkTitem*);
extern	char*		tktindparse(Tk*, char**, TkTindex*);
extern	TkTitem*	tktlastitem(TkTitem*);
extern	int		tktlinenum(TkText*, TkTindex*);
extern	int		tktlinepos(TkText*, TkTindex*);
extern	int		tktmarkind(Tk*, char*, TkTindex*);
extern	char*		tktmarkmove(Tk*, TkTmarkinfo*, TkTindex*);
extern	char*		tktmarkparse(Tk*, char**, TkTmarkinfo**);
extern	int		tktmaxwid(TkTline*);
extern	char*		tktnewitem(int, int, TkTitem**);
extern	char*		tktnewline(int, TkTitem*, TkTline*, TkTline*, TkTline**);
extern	int		tktposcount(TkTitem*);
extern	TkTline*	tktprevwrapline(Tk*, TkTline*);
extern	void		tktremitem(TkText*, TkTindex*);
extern	int		tktsametags(TkTitem*, TkTitem*);
extern	char*		tktsplititem(TkTindex*);
extern	void		tktstartind(TkText*, TkTindex*);
extern	char*		tkttagchange(Tk*, int, TkTindex*, TkTindex*, int);
extern	int		tkttagbit(TkTitem*, int, int);
extern	void		tkttagcomb(TkTitem*, TkTitem*, int);
extern	int		tkttagind(Tk*, char*, int, TkTindex*);
extern	char*		tkttagname(TkText*, int);
extern	int		tkttagnrange(TkText*, int, TkTindex*, TkTindex*, TkTindex*, TkTindex*);
extern	void		tkttagopts(Tk*, TkTitem*, int*, TkEnv*, TkTtabstop **, int);
extern	char*		tkttagparse(Tk*, char**, TkTtaginfo**);
extern	int		tkttagset(TkTitem*, int);
extern	int		tktxyind(Tk*, int, int, TkTindex*);
extern	void		tktxtforgetsub(Tk*, Tk*);
