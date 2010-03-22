typedef struct TkLabel TkLabel;

/*
 * widgets that use the label code:
 *	label
 *	checkbutton
 *	button
 *	menubutton
 *	separator
 *	cascade
 *	radiobutton
 */

struct TkLabel
{
	char*		text;		/* Label value */
	Image*		bitmap;		/* Bitmap to display */
	TkImg*		img;
	int			justify;
	int			anchor;
//	int			flags;		/* justify/anchor */
	int		w;
	int		h;
	int		textheight;

	/* button fields */
	char*		command;	/* Command to execute at invoke */
	char*		value;		/* Variable value in radio button */
	char*		offvalue;		/* Off value for check button */
	char*		variable;		/* Variable name in radio button */
	int		ul;
	int		check;		/* check/radiobutton/choicebutton state */
	int		indicator;		/* -indicatoron setting */
	char*		menu;

	char**	values;
	int nvalues;
	/* current value of choicebutton is represented by check */
};

/* Layout constants */
enum {
	Textpadx	= 3,
	Textpady	= 0,
	Bitpadx	= 0,	/* Bitmap padding in labels */
	Bitpady	= 0,
	CheckButton	= 10,
	CheckButtonBW	= 2,
	ButtonBorder	= 4,
};

extern	TkOption	tkbutopts[];
extern	TkOption	tkradopts[];
extern	TkOption	tkcbopts[];

/* label.c */
extern	void		tksizelabel(Tk*);
extern	char*	tkdrawlabel(Tk*, Point);
extern	void		tkfreelabel(Tk*);
extern	void		tklabelgetimgs(Tk*, Image**, Image**);
extern	char*	tksetvar(TkTop*, char*, char*);

/* buton.c */
extern	Tk*	tkmkbutton(TkTop*, int);
extern	void	tksizebutton(Tk*);
extern	char*	tkbuttoninvoke(Tk*, char*, char**);
extern	char*	tkradioinvoke(Tk*, char*, char**);

/* support for menus */
extern	int		tklabelmargin(Tk*);
extern	int		tkbuttonmargin(Tk*);
