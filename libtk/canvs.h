typedef struct TkCimeth TkCimeth;
typedef struct TkCitem TkCitem;
typedef struct TkCanvas TkCanvas;
typedef struct TkCline TkCline;
typedef struct TkCtag TkCtag;
typedef struct TkCpoints TkCpoints;
typedef struct TkCwind TkCwind;

struct TkCline
{
	int		arrow;
	int		shape[3];
	int		width;
	Image*		stipple;
	Image*		pen;
	int		arrowf;
	int		arrowl;
	int		capstyle;
	int		smooth;
	int		steps;
};

struct TkCwind
{
	Tk*		sub;		/* Subwindow of canvas */
	Tk*		focus;		/* Current Mouse focus */
	int		width;		/* Requested width */
	int		height;		/* Requested height */
	int		flags;		/* possible: Tkanchor|Tksetwidth|Tksetheight */
};

struct TkCpoints
{
	int		npoint;		/* Number of points */
	Point*		parampt;	/* Parameters in fixed point */
	Point*		drawpt;		/* Draw coord in pixels */
	Rectangle	bb;		/* Bounding box in pixels */
};

struct TkCitem
{
	int		id;		/* Unique id */
	int		type;		/* Object type */
	TkCpoints	p;		/* Points plus bounding box */
	TkEnv*		env;		/* Colors & fonts */
	TkCitem*	next;		/* Z order */
	TkName*		tags;		/* Temporary tag spot */
	TkCtag*		stag;		/* Real tag structure */
//	char		obj[TKSTRUCTALIGN];
};

struct TkCtag
{
	TkCitem*	item;		/* Link to item */
	TkName*		name;		/* Text name or id */
	TkCtag*		taglist;	/* link items with this tag */
	TkCtag*		itemlist;	/* link tags for this item */
};

enum
{
	/* Item types */
	TkCVline,
	TkCVtext,
	TkCVrect,
	TkCVoval,
	TkCVbitmap,
	TkCVpoly,
	TkCVwindow,
	TkCVimage,
	TkCVarc,

	TkCselto	= 0,
	TkCselfrom,
	TkCseladjust,

	TkCbufauto	= 0,
	TkCbufnone,
	TkCbufvisible,
	TkCbufall,

	TkCadd		= 0,
	TkCfind,
	
	TkChash		= 32,

	TkCarrowf	= (1<<0),
	TkCarrowl	= (1<<1),
	Tknarrow	= 6		/* Number of points in arrow */
};

struct TkCanvas
{
	int		close;
	int		confine;
	int		cleanup;
	int		scrollr[4];
	Rectangle	region;
	Rectangle	update;		/* Area to paint next draw */
	Point		view;
	TkCitem*	selection;
	int		width;
	int		height;
	int		sborderwidth;
	int		xscrolli;	/* Scroll increment */
	int		yscrolli;
	char*		xscroll;	/* Scroll commands */
	char*		yscroll;
	int		id;		/* Unique id */
	TkCitem*	head;		/* Items in Z order */
	TkCitem*	tail;		/* Head is lowest, tail is highest */
	TkCitem*	focus;		/* Keyboard focus */
	TkCitem*	mouse;		/* Mouse focus */
	TkCitem* grab;
	TkName*		current;	/* Fake for current tag */
	TkCtag		curtag;
	Image*		image;		/* Drawing space */
	int			ialloc;		/* image was allocated by us? */
	Image*		mask;		/* mask space (for stippling) */
	TkName*		thash[TkChash];	/* Tag hash */
	int		actions;
	int		actlim;
	int		buffer;
};

struct TkCimeth
{
	char*	name;
	char*	(*create)(Tk*, char *arg, char **val);
	void	(*draw)(Image*, TkCitem*, TkEnv*);
	void	(*free)(TkCitem*);
	char*	(*coord)(TkCitem*, char*, int, int);
	char*	(*cget)(TkCitem*, char*, char**);
	char*	(*conf)(Tk*, TkCitem*, char*);
	int		(*hit)(TkCitem*, Point);
};

extern	TkCimeth	tkcimethod[];
extern	int	cvslshape[];
extern	Rectangle	bbnil;
extern	Rectangle	huger;

/* General */
extern	char*		tkcaddtag(Tk*, TkCitem*, int);
extern	TkCtag*		tkcfirsttag(TkCitem*, TkCtag*);
extern	TkCtag*		tkclasttag(TkCitem*, TkCtag*);
extern	void		tkcvsappend(TkCanvas*, TkCitem*);
extern	TkCitem*	 tkcnewitem(Tk*, int, int);
extern	void		tkcvsfreeitem(TkCitem*);
extern	Point		tkcvsrelpos(Tk*);
extern	Tk*		tkcvsinwindow(Tk*, Point*);
extern	char*		tkcvstextdchar(Tk*, TkCitem*, char*);
extern	char*		tkcvstextindex(Tk*, TkCitem*, char*, char **val);
extern	char*		tkcvstextinsert(Tk*, TkCitem*, char*);
extern	char*		tkcvstexticursor(Tk*, TkCitem*, char*);
extern	void		tkmkpen(Image**, TkEnv*, Image*);
extern	void		tkcvstextfocus(Tk*, TkCitem*, int);
extern	char*		tkcvstextselect(Tk*, TkCitem*, char*, int);
extern	void		tkcvstextclr(Tk*);
extern	Tk*		tkcvsevent(Tk*, int, void*);
extern	Point		tkcvsanchor(Point, int, int, int);
extern	void		tkcvsdirty(Tk*);
extern	void		tkfreectag(TkCtag*);
extern	char*		tkparsepts(TkTop*, TkCpoints*, char**, int);
extern	void		tkfreepoint(TkCpoints*);
extern	void		tkxlatepts(Point*, int, int, int);
extern	void		tkpolybound(Point*, int, Rectangle*);
extern	TkName*		tkctaglook(Tk*, TkName*, char*);
extern	void		tkbbmax(Rectangle*, Rectangle*);
extern	void		tkcvssetdirty(Tk*);

/* Canvas Item methods - required to populate tkcimethod in canvs.c */
extern	char*	tkcvslinecreat(Tk*, char *arg, char **val);
extern	void	tkcvslinedraw(Image*, TkCitem*, TkEnv*);
extern	void	tkcvslinefree(TkCitem*);
extern	char*	tkcvslinecoord(TkCitem*, char*, int, int);
extern	char*	tkcvslinecget(TkCitem*, char*, char**);
extern	char*	tkcvslineconf(Tk*, TkCitem*, char*);
extern	int		tkcvslinehit(TkCitem*, Point);

extern	char*	tkcvstextcreat(Tk*, char *arg, char **val);
extern	void	tkcvstextdraw(Image*, TkCitem*, TkEnv*);
extern	void	tkcvstextfree(TkCitem*);
extern	char*	tkcvstextcoord(TkCitem*, char*, int, int);
extern	char*	tkcvstextcget(TkCitem*, char*, char**);
extern	char*	tkcvstextconf(Tk*, TkCitem*, char*);

extern	char*	tkcvsrectcreat(Tk*, char *arg, char **val);
extern	void	tkcvsrectdraw(Image*, TkCitem*, TkEnv*);
extern	void	tkcvsrectfree(TkCitem*);
extern	char*	tkcvsrectcoord(TkCitem*, char*, int, int);
extern	char*	tkcvsrectcget(TkCitem*, char*, char**);
extern	char*	tkcvsrectconf(Tk*, TkCitem*, char*);

extern	char*	tkcvsovalcreat(Tk*, char *arg, char **val);
extern	void	tkcvsovaldraw(Image*, TkCitem*, TkEnv*);
extern	void	tkcvsovalfree(TkCitem*);
extern	char*	tkcvsovalcoord(TkCitem*, char*, int, int);
extern	char*	tkcvsovalcget(TkCitem*, char*, char**);
extern	char*	tkcvsovalconf(Tk*, TkCitem*, char*);
extern	int		tkcvsovalhit(TkCitem*, Point);

extern	char*	tkcvsarccreat(Tk*, char *arg, char **val);
extern	void	tkcvsarcdraw(Image*, TkCitem*, TkEnv*);
extern	void	tkcvsarcfree(TkCitem*);
extern	char*	tkcvsarccoord(TkCitem*, char*, int, int);
extern	char*	tkcvsarccget(TkCitem*, char*, char**);
extern	char*	tkcvsarcconf(Tk*, TkCitem*, char*);

extern	char*	tkcvsbitcreat(Tk*, char *arg, char **val);
extern	void	tkcvsbitdraw(Image*, TkCitem*, TkEnv*);
extern	void	tkcvsbitfree(TkCitem*);
extern	char*	tkcvsbitcoord(TkCitem*, char*, int, int);
extern	char*	tkcvsbitcget(TkCitem*, char*, char**);
extern	char*	tkcvsbitconf(Tk*, TkCitem*, char*);

extern	char*	tkcvswindcreat(Tk*, char *arg, char **val);
extern	void	tkcvswinddraw(Image*, TkCitem*, TkEnv*);
extern	void	tkcvswindfree(TkCitem*);
extern	char*	tkcvswindcoord(TkCitem*, char*, int, int);
extern	char*	tkcvswindcget(TkCitem*, char*, char**);
extern	char*	tkcvswindconf(Tk*, TkCitem*, char*);

extern	char*	tkcvspolycreat(Tk*, char *arg, char **val);
extern	void	tkcvspolydraw(Image*, TkCitem*, TkEnv*);
extern	void	tkcvspolyfree(TkCitem*);
extern	char*	tkcvspolycoord(TkCitem*, char*, int, int);
extern	char*	tkcvspolycget(TkCitem*, char*, char**);
extern	char*	tkcvspolyconf(Tk*, TkCitem*, char*);
extern	int		tkcvspolyhit(TkCitem*, Point);

extern	char*	tkcvsimgcreat(Tk*, char *arg, char **val);
extern	void	tkcvsimgdraw(Image*, TkCitem*, TkEnv*);
extern	void	tkcvsimgfree(TkCitem*);
extern	char*	tkcvsimgcoord(TkCitem*, char*, int, int);
extern	char*	tkcvsimgcget(TkCitem*, char*, char**);
extern	char*	tkcvsimgconf(Tk*, TkCitem*, char*);

extern	TkCitem*	tkcvsfindwin(Tk*);
extern	void		tkcvsforgetsub(Tk*, Tk*);
