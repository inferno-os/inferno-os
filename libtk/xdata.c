#include "lib9.h"
#include "draw.h"
#include "tk.h"

#define	O(t, e)		((long)(&((t*)0)->e))

TkStab tkorient[] =
{
	"vertical",	Tkvertical,
	"horizontal",	Tkhorizontal,
	nil
};

#define RGB(r,g,b) ((r<<24)|(g<<16)|(b<<8)|0xff)

TkStab tkcolortab[] =
{
	"black",	RGB(0,0,0),
	"blue",		RGB(0,0,204),
	"darkblue",	RGB(93,0,187),
	"red",		RGB(255,0,0),
	"yellow",	RGB(255,255,0),
	"green",	RGB(0,128,0),
	"white",	RGB(255,255,255),
	"orange",	RGB(255,170,0),
	"aqua",		RGB(0,255,255),
	"fuchsia",	RGB(255,0,255),
	"gray",		RGB(128,128,128),
	"grey",		RGB(128,128,128),
	"lime",		RGB(0,255,0),
	"maroon",	RGB(128,0,0),
	"navy",		RGB(0,0,128),
	"olive",	RGB(128,128,0),
	"purple",	RGB(128,0,128),
	"silver",	RGB(192,192,192),
	"teal",		RGB(0,128,128),
	"transparent",	DTransparent,
	nil
};

TkStab tkrelief[] =
{
	"raised",	TKraised,
	"sunken",	TKsunken,
	"flat",		TKflat,
	"groove",	TKgroove,
	"ridge",	TKridge,
	nil
};

TkStab tkbool[] =
{
	"0",		BoolF,
	"no",		BoolF,
	"off",		BoolF,
	"false",	BoolF,
	"1",		BoolT,
	"yes",		BoolT,
	"on",		BoolT,
	"true",		BoolT,
	nil
};

TkStab tkanchor[] =
{
	"center",	Tkcenter,
	"c",		Tkcenter,
	"n",		Tknorth,
	"ne",		Tknorth|Tkeast,
	"e",		Tkeast,
	"se",		Tksouth|Tkeast,
	"s",		Tksouth,
	"sw",		Tksouth|Tkwest,
	"w",		Tkwest,
	"nw",		Tknorth|Tkwest,
	nil
};

static
TkStab tkstate[] =
{
	"normal",	0,
	"active",	Tkactive,
	"disabled",	Tkdisabled,
	nil
};

static
TkStab tktakefocus[] =
{
	"0",	0,
	"1",	Tktakefocus,
	nil
};

TkStab tktabjust[] =
{
	"left",		Tkleft,
	"right",	Tkright,
	"center",	Tkcenter,
	"numeric",	Tknumeric,	
	nil
};

TkStab tkwrap[] =
{
	"none",		Tkwrapnone,
	"word",		Tkwrapword,
	"char",		Tkwrapchar,
	nil
};

TkStab tkjustify[] =
{
	"left",		Tkleft,
	"right",	Tkright,
	"center",	Tkcenter,
	nil
};

TkOption tkgeneric[] =
{
 "actx",		OPTact,	0,	IAUX(0),
 "acty",		OPTact,	0,	IAUX(1),
 "actwidth",		OPTdist, O(Tk, act.width),	IAUX(O(Tk, env)),
 "actheight",		OPTdist, O(Tk, act.height),	IAUX(O(Tk, env)),
 "bd",			OPTnndist, O(Tk, borderwidth),	nil,
 "borderwidth",		OPTnndist, O(Tk, borderwidth),	nil,
 "highlightthickness",	OPTnndist, O(Tk, highlightwidth), nil,
 "height",		OPTsize, 0,			IAUX(O(Tk, env)),
 "width",		OPTsize, 0,			IAUX(O(Tk, env)),
 "relief",		OPTstab, O(Tk, relief),		tkrelief,
 "state",		OPTflag, O(Tk, flag),		tkstate,
 "font",		OPTfont, O(Tk, env),		nil,
 "foreground",		OPTcolr, O(Tk, env),		IAUX(TkCforegnd),
 "background",		OPTcolr, O(Tk, env),		IAUX(TkCbackgnd),
 "fg",			OPTcolr, O(Tk, env),		IAUX(TkCforegnd),
 "bg",			OPTcolr, O(Tk, env),		IAUX(TkCbackgnd),
 "selectcolor",		OPTcolr, O(Tk, env),		IAUX(TkCselect),
 "selectforeground",	OPTcolr, O(Tk, env),		IAUX(TkCselectfgnd),
 "selectbackground",	OPTcolr, O(Tk, env),		IAUX(TkCselectbgnd),
 "activeforeground",	OPTcolr, O(Tk, env),		IAUX(TkCactivefgnd),
 "activebackground",	OPTcolr, O(Tk, env),		IAUX(TkCactivebgnd),
 "highlightcolor",	OPTcolr, O(Tk, env),		IAUX(TkChighlightfgnd),
 "disabledcolor",	OPTcolr, O(Tk, env),		IAUX(TkCdisablefgnd),
 "padx",		OPTnndist, O(Tk, pad.x),		nil,
 "pady",		OPTnndist, O(Tk, pad.y),		nil,
 "takefocus",	OPTflag, O(Tk, flag),		tktakefocus,
 nil
};

TkOption tktop[] =
{
	"x",		OPTdist,	O(TkWin, req.x),		nil,
	"y",		OPTdist,	O(TkWin, req.y),		nil,
	nil
};

TkOption tktopdbg[] =
{
	"debug",	OPTbool,	O(TkTop, debug),	nil,
	nil
};

TkMethod *tkmethod[] =
{
	&framemethod,	/* TKframe */
	&labelmethod,		/* TKlabel */
	&checkbuttonmethod,	/* TKcheckbutton */
	&buttonmethod,	/* TKbutton */
	&menubuttonmethod,	/* TKmenubutton */
	&menumethod,	/* TKmenu */
	&separatormethod,	/* TKseparator */
	&cascademethod,	/* TKcascade */	
	&listboxmethod,	/* TKlistbox */
	&scrollbarmethod,	/* TKscrollbar */
	&textmethod,	/* TKtext */
	&canvasmethod,	/* TKcanvas */
	&entrymethod,	/* TKentry */
	&radiobuttonmethod,	/* TKradiobutton */
	&scalemethod,	/* TKscale */
	&panelmethod,	/* TKpanel */
	&choicebuttonmethod,	/*TKchoicebutton */
};

char TkNomem[]	= "!out of memory";
char TkBadop[]	= "!bad option";
char TkOparg[]	= "!arg requires option";
char TkBadvl[]	= "!bad value";
char TkBadwp[]	= "!bad window path";
char TkWpack[]	= "!window is already packed";
char TkNotop[]	= "!no toplevel";
char TkDupli[]  = "!window path already exists";
char TkNotpk[]	= "!window not packed";
char TkBadcm[]	= "!bad command";
char TkIstop[]	= "!can't pack top level";
char TkBadbm[]	= "!failed to load bitmap";
char TkBadft[]	= "!failed to open font";
char TkBadit[]	= "!bad item type";
char TkBadtg[]	= "!bad/no matching tag";
char TkFewpt[]	= "!wrong number of points";
char TkBadsq[]	= "!bad event sequence";
char TkBadix[]	= "!bad index";
char TkNotwm[]	= "!not a window";
char TkBadvr[]	= "!variable does not exist";
char TkNotvt[]	= "!variable is wrong type";
char TkMovfw[]	= "!too many events buffered";
char TkBadsl[]	= "!selection already exists";
char TkSyntx[]	= "!bad [] or {} syntax";
char TkRecur[] = "!cannot pack recursively";
char TkDepth[] = "!execution stack too big";
char TkNomaster[] = "!no master given";
char TkNotgrid[] = "!not a grid";
char TkIsgrid[] = "!cannot use pack inside a grid";
char TkBadgridcell[] = "!grid cell in use";
char TkBadspan[] = "!bad grid span";
char TkBadcursor[] = "!bad cursor image";
