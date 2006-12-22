Draw: module
{
	PATH:	con	"$Draw";

	# predefined colors; pass to Display.color
	Opaque:	con int 16rFFFFFFFF;
	Transparent:	con int 16r00000000;		# only useful for Display.newimage
	Black:	con int 16r000000FF;
	White:	con int 16rFFFFFFFF;
	Red:	con int 16rFF0000FF;
	Green:	con int 16r00FF00FF;
	Blue:	con int 16r0000FFFF;
	Cyan:	con int 16r00FFFFFF;
	Magenta:	con int 16rFF00FFFF;
	Yellow:	con int 16rFFFF00FF;
	Grey:	con int 16rEEEEEEFF;
	Paleyellow:	con int 16rFFFFAAFF;
	Darkyellow:	con int 16rEEEE9EFF;
	Darkgreen:	con int 16r448844FF;
	Palegreen:	con int 16rAAFFAAFF;
	Medgreen:	con int 16r88CC88FF;
	Darkblue:	con int 16r000055FF;
	Palebluegreen:	con int 16rAAFFFFFF;
	Paleblue:	con int 16r0000BBFF;
	Bluegreen:	con int 16r008888FF;
	Greygreen:	con int 16r55AAAAFF;
	Palegreygreen:	con int 16r9EEEEEFF;
	Yellowgreen:	con int 16r99994CFF;
	Medblue:	con int 16r000099FF;
	Greyblue:	con int 16r005DBBFF;
	Palegreyblue:	con int 16r4993DDFF;
	Purpleblue:	con int 16r8888CCFF;

	Notacolor:	con int 16rFFFFFF00;
	Nofill:		con Notacolor;

	# end styles for line
	Endsquare:	con 0;
	Enddisc:	con 1;
	Endarrow:	con 2;

	# flush control
	Flushoff:	con 0;
	Flushon:	con 1;
	Flushnow:	con 2;

	# image backing store
	Refbackup:	con 0;
	Refnone:	con 1;

	# compositing operators
	SinD:	con 1<<3;
	DinS:	con 1<<2;
	SoutD:	con 1<<1;
	DoutS:	con 1<<0;

	S:		con SinD|SoutD;
	SoverD:	con SinD|SoutD|DoutS;
	SatopD:	con SinD|DoutS;
	SxorD:	con SoutD|DoutS;

	D:		con DinS|DoutS;
	DoverS:	con DinS|DoutS|SoutD;
	DatopS:	con DinS|SoutD;
	DxorS:	con DoutS|SoutD;

	Clear:	con 0;

	# Image channels descriptor
	Chans: adt
	{
		desc:	int;		# descriptor packed into an int

		# interpret standard channel string
		mk:	fn(s: string): Chans;
		# standard printable form
		text:	fn(c: self Chans): string;
		# equality
		eq:	fn(c: self Chans, d: Chans): int;
		# bits per pixel
		depth:	fn(c: self Chans): int;
	};

	CRed, CGreen, CBlue, CGrey, CAlpha, CMap, CIgnore: con iota;

	GREY1: con Chans((CGrey<<4) | 1);
	GREY2: con Chans((CGrey<<4) | 2);
	GREY4: con Chans((CGrey<<4) | 4);
	GREY8: con Chans((CGrey<<4) | 8);
	CMAP8: con Chans((CMap<<4) | 8);
	RGB15: con Chans(((CIgnore<<4)|1)<<24 | ((CRed<<4)|5)<<16 | ((CGreen<<4)|5)<<8 | ((CBlue<<4)|5));
	RGB16: con Chans(((CRed<<4)|5)<<16 | ((CGreen<<4)|6)<<8 | ((CBlue<<4)|5));
	RGB24: con Chans(((CRed<<4)|8)<<16 | ((CGreen<<4)|8)<<8 | ((CBlue<<4)|8));
	RGBA32: con Chans((((CRed<<4)|8)<<16 | ((CGreen<<4)|8)<<8 | ((CBlue<<4)|8))<<8 | ((CAlpha<<4)|8));
	ARGB32: con Chans(((CAlpha<<4)|8)<<24 | ((CRed<<4)|8)<<16 | ((CGreen<<4)|8)<<8 | ((CBlue<<4)|8));	# stupid VGAs
	XRGB32: con Chans(((CIgnore<<4)|8)<<24 | ((CRed<<4)|8)<<16 | ((CGreen<<4)|8)<<8 | ((CBlue<<4)|8));	# stupid VGAs

	# Coordinate of a pixel on display
	Point: adt
	{
		x:	int;
		y:	int;

		# arithmetic
		add:	fn(p: self Point, q: Point): Point;
		sub:	fn(p: self Point, q: Point): Point;
		mul:	fn(p: self Point, i: int): Point;
		div:	fn(p: self Point, i: int): Point;
		# equality
		eq:	fn(p: self Point, q: Point): int;
		# inside rectangle
		in:	fn(p: self Point, r: Rect): int;
	};

	# Rectangle of pixels on the display; min <= max
	Rect: adt
	{
		min:	Point;	# upper left corner
		max:	Point;	# lower right corner

		# make sure min <= max
		canon:		fn(r: self Rect): Rect;
		# extent
		dx:		fn(r: self Rect): int;
		dy:		fn(r: self Rect): int;
		size:		fn(r: self Rect): Point;
		# equality
		eq:		fn(r: self Rect, s: Rect): int;
		# intersection and clipping
		Xrect:		fn(r: self Rect, s: Rect): int;
		inrect:		fn(r: self Rect, s: Rect): int;
		clip:		fn(r: self Rect, s: Rect): (Rect, int);
		contains:	fn(r: self Rect, p: Point): int;
		combine:	fn(r: self Rect, s: Rect): Rect;
		# arithmetic
		addpt:		fn(r: self Rect, p: Point): Rect;
		subpt:		fn(r: self Rect, p: Point): Rect;
		inset:		fn(r: self Rect, n: int): Rect;
	};

	# a picture; if made by Screen.newwindow, a window.  always attached to a Display
	Image: adt
	{
		# these data are local copies, but repl and clipr
		# are monitored by the runtime and may be modified as desired.
		r:	Rect;		# rectangle in data area, local coords
		clipr:	Rect;		# clipping region
		depth:	int;		# number of bits per pixel
		chans:	Chans;
		repl:	int;		# whether data area replicates to tile the plane
		display:	ref Display; # where Image resides
		screen:		ref Screen;	 # nil if not window
		iname:	string;

		# graphics operators
		drawop:		fn(dst: self ref Image, r: Rect, src: ref Image, matte: ref Image, p: Point, op: int);
		draw:		fn(dst: self ref Image, r: Rect, src: ref Image, matte: ref Image, p: Point);
		gendrawop:		fn(dst: self ref Image, r: Rect, src: ref Image, p0: Point, matte: ref Image, p1: Point, op: int);
		gendraw:		fn(dst: self ref Image, r: Rect, src: ref Image, p0: Point, matte: ref Image, p1: Point);
		lineop:		fn(dst: self ref Image, p0,p1: Point, end0,end1,radius: int, src: ref Image, sp: Point, op: int);
		line:		fn(dst: self ref Image, p0,p1: Point, end0,end1,radius: int, src: ref Image, sp: Point);
		polyop:		fn(dst: self ref Image, p: array of Point, end0,end1,radius: int, src: ref Image, sp: Point, op: int);
		poly:		fn(dst: self ref Image, p: array of Point, end0,end1,radius: int, src: ref Image, sp: Point);
		bezsplineop:		fn(dst: self ref Image, p: array of Point, end0,end1,radius: int, src: ref Image, sp: Point, op: int);
		bezspline:		fn(dst: self ref Image, p: array of Point, end0,end1,radius: int, src: ref Image, sp: Point);
		fillpolyop:	fn(dst: self ref Image, p: array of Point, wind: int, src: ref Image, sp: Point, op: int);
		fillpoly:	fn(dst: self ref Image, p: array of Point, wind: int, src: ref Image, sp: Point);
		fillbezsplineop:	fn(dst: self ref Image, p: array of Point, wind: int, src: ref Image, sp: Point, op: int);
		fillbezspline:	fn(dst: self ref Image, p: array of Point, wind: int, src: ref Image, sp: Point);
		ellipseop:	fn(dst: self ref Image, c: Point, a, b, thick: int, src: ref Image, sp: Point, op: int);
		ellipse:	fn(dst: self ref Image, c: Point, a, b, thick: int, src: ref Image, sp: Point);
		fillellipseop:	fn(dst: self ref Image, c: Point, a, b: int, src: ref Image, sp: Point, op: int);
		fillellipse:	fn(dst: self ref Image, c: Point, a, b: int, src: ref Image, sp: Point);
		arcop:	fn(dst: self ref Image, c: Point, a, b, thick: int, src: ref Image, sp: Point, alpha, phi: int, op: int);
		arc:	fn(dst: self ref Image, c: Point, a, b, thick: int, src: ref Image, sp: Point, alpha, phi: int);
		fillarcop:	fn(dst: self ref Image, c: Point, a, b: int, src: ref Image, sp: Point, alpha, phi: int, op: int);
		fillarc:	fn(dst: self ref Image, c: Point, a, b: int, src: ref Image, sp: Point, alpha, phi: int);
		bezierop:	fn(dst: self ref Image, a,b,c,d: Point, end0,end1,radius: int, src: ref Image, sp: Point, op: int);
		bezier:	fn(dst: self ref Image, a,b,c,d: Point, end0,end1,radius: int, src: ref Image, sp: Point);
		fillbezierop:	fn(dst: self ref Image, a,b,c,d: Point, wind:int, src: ref Image, sp: Point, op: int);
		fillbezier:	fn(dst: self ref Image, a,b,c,d: Point, wind:int, src: ref Image, sp: Point);
		textop:		fn(dst: self ref Image, p: Point, src: ref Image, sp: Point, font: ref Font, str: string, op: int): Point;
		text:		fn(dst: self ref Image, p: Point, src: ref Image, sp: Point, font: ref Font, str: string): Point;
		textbgop:		fn(dst: self ref Image, p: Point, src: ref Image, sp: Point, font: ref Font, str: string, bg: ref Image, bgp: Point, op: int): Point;
		textbg:		fn(dst: self ref Image, p: Point, src: ref Image, sp: Point, font: ref Font, str: string, bg: ref Image, bgp: Point): Point;
		border:	fn(dst: self ref Image, r: Rect, i: int, src: ref Image, sp: Point);
		arrow:		fn(a,b,c: int): int;
		# direct access to pixels
		readpixels:	fn(src: self ref Image, r: Rect, data: array of byte): int;
		writepixels:	fn(dst: self ref Image, r: Rect, data: array of byte): int;
		# publishing
		name:	fn(src: self ref Image, name: string, in: int): int;
		# windowing
		top:		fn(win: self ref Image);
		bottom:		fn(win: self ref Image);
		flush:		fn(win: self ref Image, func: int);
		origin:		fn(win: self ref Image, log, scr: Point): int;
	};

	# a frame buffer, holding a connection to /dev/draw
	Display: adt
	{
		image:	ref Image;	# holds the contents of the display
		white:	ref Image;
		black:	ref Image;
		opaque:	ref Image;
		transparent:	ref Image;

		# allocate and start refresh slave
		allocate:	fn(dev: string): ref Display;
		startrefresh:	fn(d: self ref Display);
		# attach to existing Screen
		publicscreen:	fn(d: self ref Display, id: int): ref Screen;
		getwindow:	fn(d: self ref Display, winname: string, screen: ref Screen, image: ref Image, backup: int): (ref Screen, ref Image);
		# image creation
		newimage:	fn(d: self ref Display, r: Rect, chans: Chans, repl, color: int): ref Image;
		color:		fn(d: self ref Display, color: int): ref Image;
		colormix:		fn(d: self ref Display, c1: int, c2: int): ref Image;
		rgb:		fn(d: self ref Display, r, g, b: int): ref Image;
		# attach to named Image
		namedimage:	fn(d: self ref Display, name: string): ref Image;
		# I/O to files
		open:		fn(d: self ref Display, name: string): ref Image;
		readimage:	fn(d: self ref Display, fd: ref Sys->FD): ref Image;
		writeimage:	fn(d: self ref Display, fd: ref Sys->FD, i: ref Image): int;
		# color map
		rgb2cmap:	fn(d: self ref Display, r, g, b: int): int;
		cmap2rgb:	fn(d: self ref Display, c: int): (int, int, int);
		cmap2rgba:	fn(d: self ref Display, c: int): int;
	};

	# a mapping between characters and pictures; always attached to a Display
	Font: adt
	{
		name:	string;		# *default* or a file name (this may change)
		height:	int;		# interline spacing of font
		ascent:	int;		# distance from baseline to top
		display:	ref Display;	# where Font resides

		# read from file or construct from local description
		open:		fn(d: ref Display, name: string): ref Font;
		build:		fn(d: ref Display, name, desc: string): ref Font;
		# string extents
		width:		fn(f: self ref Font, str: string): int;
		bbox:		fn(f: self ref Font, str: string): Rect;
	};

	# a collection of windows; always attached to a Display
	Screen: adt
	{
		id:		int;		# for export when public
		image:		ref Image;	# root of window tree
		fill:		ref Image;	# picture to use when repainting
		display:	ref Display;	# where Screen resides

		# create; see also Display.publicscreen
		allocate:	fn(image, fill: ref Image, public: int): ref Screen;
		# allocate a new window
		newwindow:	fn(screen: self ref Screen, r: Rect, backing: int, color: int): ref Image;
		# raise or lower a group of windows
		top:		fn(screen: self ref Screen, wins: array of ref Image);
		bottom:		fn(screen: self ref Screen, wins: array of ref Image);
	};

	# the state of a pointer device, e.g. a mouse or stylus
	Pointer: adt
	{
		buttons:	int;	# bits 1 2 4 ... represent state of buttons left to right; 1 means pressed
		xy:		Point;	# position
		msec:	int;	# millisecond time stamp
	};

	# graphics context
	Context: adt
	{
		display: 	ref Display;		# frame buffer on which windows reside
		screen:		ref Screen;			# place to make windows (mux only)
		wm:	chan of (string, chan of (string, ref Wmcontext));		# connect to window manager
	};

	# connection to window manager for one or more windows (as Images)
	Wmcontext: adt
	{
		kbd: 		chan of int;		# incoming characters from keyboard
		ptr: 		chan of ref Pointer;	# incoming stream of mouse positions
		ctl:		chan of string;		# commands from wm to application
		wctl:		chan of string;		# commands from application to wm
		images:	chan of ref Image;	# exchange of images
		connfd:	ref Sys->FD;		# connection control
		ctxt:		ref Context;
	};

	# functions that don't fit well in any adt
	setalpha:	fn(c: int, a: int): int;
	bytesperline:	fn(r: Rect, d: int): int;
	icossin:	fn(deg: int): (int, int);
	icossin2:	fn(p: Point): (int, int);
};
