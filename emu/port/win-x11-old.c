#include "dat.h"
#include "fns.h"
#include "cursor.h"
#include "keyboard.h"
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>

#define ABS(x) ((x) < 0 ? -(x) : (x))

/*
 * alias defs for image types to overcome name conflicts
 */
typedef struct ICursor		ICursor;
typedef struct IPoint		IPoint;
typedef struct IRectangle	IRectangle;
typedef struct CRemapTbl	CRemapTbl;
struct ICursor
{
	int	w;
	int	h;
	int	hotx;
	int	hoty;
	char	*src;
	char	*mask;
};

struct IPoint
{
	int	x;
	int	y;
};

struct IRectangle
{
	IPoint	min;
	IPoint	max;
};

struct CRemapTbl
{
	ulong inferno[256];	/* The corresponding inferno colormap vals */
	ulong openslot[256];	
	Bool cellused[256];
	int cnt;
	int opencnt;
};

enum
{
	DblTime	= 300		/* double click time in msec */
};

XColor			map[256];	/* Inferno colormap array */
XColor			map7[128];	/* Inferno colormap array */
uchar			map7to8[128][2];
Colormap		xcmap;		/* Default shared colormap  */
int 			infernotox11[256]; /* Values for mapping between */
int 			x11toinferno[256]; /* X11 and inferno */
int				x24bitswap = 0;	/* swap endian for 24bit RGB */

static	int		triedscreen;
static	XModifierKeymap *modmap;
static	int		keypermod;
static	Drawable	xdrawable;
static	Atom		wm_take_focus;
static	void		xexpose(XEvent*);
static	void		xmouse(XEvent*);
static	void		xkeyboard(XEvent*);
static	void		xmapping(XEvent*);
static	void		xproc(void*);
static	void		xinitscreen(int, int);
static	void		initmap(Window);
static	GC		creategc(Drawable);
static 	CRemapTbl	crtbl;
static	void		graphicscmap(XColor*);
	int		xscreendepth;
	Drawable	xscreenid;
	Display*	xdisplay;
	Display*	xkmcon;
	Visual		*xvis;
	GC		xgcfill, xgccopy, xgcsimplesrc, xgczero, xgcreplsrc;
	GC		xgcfill0, xgccopy0, xgcsimplesrc0, xgczero0, xgcreplsrc0;

char *gkscanid = "emu_x11";


ulong*
attachscreen(IRectangle *r, int *ld, int *width, int *softscreen)
{
	extern ulong* makememones();

	r->min.x = 0;
	r->min.y = 0;
	r->max.x = Xsize;
	r->max.y = Ysize;
	*ld = 3;
	*width = Xsize/4;
	*softscreen = 1;
	if(!triedscreen){
		triedscreen = 1;
		xinitscreen(Xsize, Ysize);
		if(kproc("xproc", xproc, nil, 0) < 0) {
			fprint(2, "emu: win-x11 can't make X proc\n");
			return 0;
		}
	}
	return makememones();
}

void
flushmemscreen(IRectangle r)
{
	if(r.min.x > r.max.x)
		return;
	XCopyArea(xdisplay, xscreenid, xdrawable, xgccopy,
		r.min.x, r.min.y,
		r.max.x-r.min.x, r.max.y-r.min.y, r.min.x, r.min.y);
	XFlush(xdisplay);
}

static int
revbyte(int b)
{
	int r;

	r = 0;
	r |= (b&0x01) << 7;
	r |= (b&0x02) << 5;
	r |= (b&0x04) << 3;
	r |= (b&0x08) << 1;
	r |= (b&0x10) >> 1;
	r |= (b&0x20) >> 3;
	r |= (b&0x40) >> 5;
	r |= (b&0x80) >> 7;
	return r;
}

static void
gotcursor(ICursor c)
{
	Cursor xc;
	XColor fg, bg;
	Pixmap xsrc, xmask;
	static Cursor xcursor;

	if(c.src == nil){
		if(xcursor != 0) {
			XFreeCursor(xdisplay, xcursor);
			xcursor = 0;
		}
		XUndefineCursor(xdisplay, xdrawable);
		XFlush(xdisplay);
		return;
	}
	xsrc = XCreateBitmapFromData(xdisplay, xdrawable, c.src, c.w, c.h);
	xmask = XCreateBitmapFromData(xdisplay, xdrawable, c.mask, c.w, c.h);

	fg = map[255];
	bg = map[0];
	fg.pixel = infernotox11[255];
	bg.pixel = infernotox11[0];
	xc = XCreatePixmapCursor(xdisplay, xsrc, xmask, &fg, &bg, -c.hotx, -c.hoty);
	if(xc != 0) {
		XDefineCursor(xdisplay, xdrawable, xc);
		if(xcursor != 0)
			XFreeCursor(xdisplay, xcursor);
		xcursor = xc;
	}
	XFreePixmap(xdisplay, xsrc);
	XFreePixmap(xdisplay, xmask);
	XFlush(xdisplay);
	free(c.src);
}

void
setcursor(IPoint p)
{
	XWarpPointer(xdisplay, None, xdrawable, 0, 0, 0, 0, p.x, p.y);
	XFlush(xdisplay);
}

void
drawcursor(Drawcursor* c)
{
	ICursor ic;
	IRectangle ir;
	uchar *bs, *bc;
	int i, h, j, bpl;
	char *src, *mask, *csrc, *cmask;

	/* Set the default system cursor */
	src = nil;
	mask = nil;
	if(c->data != nil){
		h = (c->maxy-c->miny)/2;
		ir.min.x = c->minx;
		ir.min.y = c->miny;
		ir.max.x = c->maxx;
		ir.max.y = c->maxy;
		/* passing IRectangle to Rectangle is safe */
		bpl = bytesperline(ir, 1);

		i = h*bpl;
		src = malloc(2*i);
		if(src == nil)
			return;
		mask = src + i;

		csrc = src;
		cmask = mask;
		bc = c->data;
		bs = c->data + h*bpl;
		for(i = 0; i < h; i++){
			for(j = 0; j < bpl; j++) {
				*csrc++ = revbyte(bs[j]);
				*cmask++ = revbyte(bs[j] | bc[j]);
			}
			bs += bpl;
			bc += bpl;
		}
	}
	ic.w = 8*bpl;
	ic.h = h;
	ic.hotx = c->hotx;
	ic.hoty = c->hoty;
	ic.src = src;
	ic.mask = mask;

	gotcursor(ic);
}

static void
xproc(void *arg)
{
	ulong mask;
	XEvent event;

	closepgrp(up->env->pgrp);
	closefgrp(up->env->fgrp);
	closeegrp(up->env->egrp);
	closesigs(up->env->sigs);

	mask = 	KeyPressMask|
		KeyReleaseMask|
		ButtonPressMask|
		ButtonReleaseMask|
		PointerMotionMask|
		Button1MotionMask|
		Button2MotionMask|
		Button3MotionMask|
		ExposureMask;

	XSelectInput(xkmcon, xdrawable, mask);		
	for(;;) {
		XWindowEvent(xkmcon, xdrawable, mask, &event);
		switch(event.type) {
		case KeyPress:
		case KeyRelease:
			xkeyboard(&event);
			break;
		case ButtonPress:
		case ButtonRelease:
		case MotionNotify:
			xmouse(&event);
			break;
		case Expose:
			xexpose(&event);
			break;
		case MappingNotify:
			xmapping(&event);
			break;
		default:
			break;
		}
	}
}

static int
shutup(Display *d, XErrorEvent *e)
{
	char buf[200];
	print("X error: error code=%d, request_code=%d, minor=%d\n", e->error_code, e->request_code, e->minor_code);
	XGetErrorText(d, e->error_code, buf, sizeof(buf));
	print("%s\n", buf);
	USED(d);
	USED(e);
	return 0;
}

static void
xinitscreen(int xsize, int ysize)
{
	int i, pmid;
	char *argv[2];
	char *disp_val;
	Window rootwin;
	XWMHints hints;
	Screen *screen;
	XVisualInfo xvi;
	int rootscreennum;
	XTextProperty name;
	XClassHint classhints;
	XSizeHints normalhints;
	XSetWindowAttributes attrs;
 
	xscreenid = 0;
	xdrawable = 0;

	xdisplay = XOpenDisplay(NULL);
	if(xdisplay == 0){
		disp_val = getenv("DISPLAY");
		if(disp_val == 0)
			disp_val = "not set";
		fprint(2, "emu: win-x11 open %r, DISPLAY is %s\n", disp_val);
		cleanexit(0);
	}

	rootscreennum = DefaultScreen(xdisplay);
	rootwin = DefaultRootWindow(xdisplay);

	xscreendepth = DefaultDepth(xdisplay, rootscreennum);
	if(XMatchVisualInfo(xdisplay, rootscreennum, 24, TrueColor, &xvi)
	|| XMatchVisualInfo(xdisplay, rootscreennum, 24, DirectColor, &xvi)){
		xvis = xvi.visual;
		xscreendepth = 24;
		xtblbit = 1;
	}
	else if(XMatchVisualInfo(xdisplay, rootscreennum, 8, PseudoColor, &xvi)
	|| XMatchVisualInfo(xdisplay, rootscreennum, 8, StaticColor, &xvi)){
		if(xscreendepth > 8) {
			fprint(2, "emu: win-x11 can't deal with depth %d screens\n", xscreendepth);
			cleanexit(0);
		}
		xvis = xvi.visual;
		xscreendepth = 8;
	}
	else{
		if(xscreendepth != 8){
			fprint(2, "emu: win-x11 can't deal with depth %d screens\n", xscreendepth);
			cleanexit(0);
		}
		xvis = DefaultVisual(xdisplay, rootscreennum);
	}

	screen = DefaultScreenOfDisplay(xdisplay);
	xcmap = DefaultColormapOfScreen(screen);

	if(xvis->class != StaticColor){
		graphicscmap(map);
		initmap(rootwin);
	}

	if(modmap = XGetModifierMapping(xdisplay))
		keypermod = modmap->max_keypermod;

	attrs.colormap = xcmap;
	attrs.background_pixel = 0;
	attrs.border_pixel = 0;
	/* attrs.override_redirect = 1;*/ /* WM leave me alone! |CWOverrideRedirect */
	xdrawable = XCreateWindow(xdisplay, rootwin, 0, 0, xsize, ysize, 0, xscreendepth, InputOutput, xvis, CWBackPixel|CWBorderPixel|CWColormap, &attrs);

	/*
	 * set up property as required by ICCCM
	 */
	name.value = "inferno";
	name.encoding = XA_STRING;
	name.format = 8;
	name.nitems = strlen(name.value);
	normalhints.flags = USSize|PMaxSize;
	normalhints.max_width = normalhints.width = xsize;
	normalhints.max_height = normalhints.height = ysize;
	hints.flags = InputHint|StateHint;
	hints.input = 1;
	hints.initial_state = NormalState;
	classhints.res_name = "inferno";
	classhints.res_class = "Inferno";
	argv[0] = "inferno";
	argv[1] = nil;
	XSetWMProperties(xdisplay, xdrawable,
		&name,			/* XA_WM_NAME property for ICCCM */
		&name,			/* XA_WM_ICON_NAME */
		argv,			/* XA_WM_COMMAND */
		1,			/* argc */
		&normalhints,		/* XA_WM_NORMAL_HINTS */
		&hints,			/* XA_WM_HINTS */
		&classhints);		/* XA_WM_CLASS */

	/*
	 * put the window on the screen
	 */
	XMapWindow(xdisplay, xdrawable);

	xscreenid = XCreatePixmap(xdisplay, xdrawable, xsize, ysize, xscreendepth);
	XFlush(xdisplay);

	xgcfill = creategc(xscreenid);
	XSetFillStyle(xdisplay, xgcfill, FillSolid);
	xgccopy = creategc(xscreenid);
	xgcsimplesrc = creategc(xscreenid);
	XSetFillStyle(xdisplay, xgcsimplesrc, FillStippled);
	xgczero = creategc(xscreenid);
	xgcreplsrc = creategc(xscreenid);
	XSetFillStyle(xdisplay, xgcreplsrc, FillTiled);

	pmid = XCreatePixmap(xdisplay, xdrawable, 1, 1, 1);
	xgcfill0 = creategc(pmid);
	XSetFillStyle(xdisplay, xgcfill0, FillSolid);
	xgccopy0 = creategc(pmid);
	xgcsimplesrc0 = creategc(pmid);
	XSetFillStyle(xdisplay, xgcsimplesrc0, FillStippled);
	xgczero0 = creategc(pmid);
	xgcreplsrc0 = creategc(pmid);
	XSetFillStyle(xdisplay, xgcreplsrc0, FillTiled);
	XFreePixmap(xdisplay, pmid);

	XSetForeground(xdisplay, xgccopy, infernotox11[0]);
	XFillRectangle(xdisplay, xscreenid, xgccopy, 0, 0, xsize, ysize);

	xkmcon = XOpenDisplay(NULL);
	if(xkmcon == 0){
		disp_val = getenv("DISPLAY");
		if(disp_val == 0)
			disp_val = "not set";
		fprint(2, "emu: win-x11 open %r, DISPLAY is %s\n", disp_val);
		cleanexit(0);
	}
}

static void
graphicscmap(XColor *map)
{
	int r, g, b, cr, cg, cb, v, num, den, idx, v7, idx7;

	for(r=0; r!=4; r++) {
		for(g = 0; g != 4; g++) {
			for(b = 0; b!=4; b++) {
				for(v = 0; v!=4; v++) {
					den=r;
					if(g > den)
						den=g;
					if(b > den)
						den=b;
					/* divide check -- pick grey shades */
					if(den==0)
						cr=cg=cb=v*17;
					else {
						num=17*(4*den+v);
						cr=r*num/den;
						cg=g*num/den;
						cb=b*num/den;
					}
					idx = r*64 + v*16 + ((g*4 + b + v - r) & 15);
					idx = 255 - idx;
					map[idx].red = cr*0x0101;
					map[idx].green = cg*0x0101;
					map[idx].blue = cb*0x0101;
					map[idx].pixel = idx;
					map[idx].flags = DoRed|DoGreen|DoBlue;

					v7 = v >> 1;
					idx7 = r*32 + v7*16 + g*4 + b;
					if((v & 1) == v7){
						map7to8[idx7][0] = idx;
						if(den == 0) { 		/* divide check -- pick grey shades */
							cr = ((255.0/7.0)*v7)+0.5;
							cg = cr;
							cb = cr;
						}
						else {
							num=17*15*(4*den+v7*2)/14;
							cr=r*num/den;
							cg=g*num/den;
							cb=b*num/den;
						}
						map7[idx7].red = cr*0x0101;
						map7[idx7].green = cg*0x0101;
						map7[idx7].blue = cb*0x0101;
						map7[idx7].pixel = idx7;
						map7[idx7].flags = DoRed|DoGreen|DoBlue;
					}
					else
						map7to8[idx7][1] = idx;
				}
			}
		}
	}
}

/*
 * Initialize and install the Inferno colormap as a private colormap for this
 * application.  Inferno gets the best colors here when it has the cursor focus.
 */  
static void 
initmap(Window w)
{
	XColor c;
	XColor xcol;
	ulong v;
	int i, pix, ncmaps;

	if(xscreendepth <= 1)
		return;

	if(xvis->class == TrueColor || xvis->class == DirectColor) {
	int color_order_init = 0;
	uint pp, p;

		for(i = 0; i < 256; i++) {
			c = map[i];
			/* find out index into colormap for our RGB */
			if(!XAllocColor(xdisplay, xcmap, &c)) {
				fprint(2, "emu: win-x11 can't alloc color\n");
				cleanexit(0);
			}

			/* The pixel value returned from XGetPixel needs to
			 * be converted to RGB so we can call rgb2cmap()
			 * to translate between 24 bit X and our color. Unfortunately,
			 * the return value appears to be display server endian 
			 * dependant. Therefore, we run some heuristics to later
			 * determine how to mask the int value correctly.
			 * Yeah, I know we can look at xvis->byte_order but 
			 * some displays say MSB even though they run on LSB.
			 * Besides, this is more anal.
			 */

			p  = c.pixel;
			pp = rgb2cmap((p>>16)&0xff,(p>>8)&0xff,p&0xff);
			if(!color_order_init && (pp!=map[i].pixel)) {
				/* check if endian is other way */
				pp = rgb2cmap(p&0xff,(p>>8)&0xff,(p>>16)&0xff);
				if(pp!=map[i].pixel) {
					fprint(2, "emu: win-x11 can't convert 24bit colors\n");
					cleanexit(0);
				}
				color_order_init = 1;
				x24bitswap = 1;
			}

			if(color_order_init) {
				pp = rgb2cmap(p&0xff,(p>>8)&0xff,(p>>16)&0xff);
				if(pp!=map[i].pixel) {
					fprint(2, "emu: win-x11 can't convert 24bit colors\n");
					cleanexit(0);
				}
				/* no x11toinferno; later use rgb2cmap() */
				infernotox11[map[i].pixel] = c.pixel;
			}
			else if(pp!=map[i].pixel) {
				fprint(2, "emu: win-x11 can't convert 24bit colors\n");
				cleanexit(0);
			}
			else {
				/* no x11toinferno; later use rgb2cmap() */
				infernotox11[map[i].pixel] = c.pixel;
			}
		}
	}
	else if(xvis->class == PseudoColor) {
		if(xtblbit == 0){
			xcmap = XCreateColormap(xdisplay, w, xvis, AllocAll); 
			XStoreColors(xdisplay, xcmap, map, 256);
			for(i = 0; i < 256; i++) {
				infernotox11[i] = i;
				x11toinferno[i] = i;
			}
		}
		else {
			for(i = 0; i < 128; i++) {
				c = map7[i];
				if(!XAllocColor(xdisplay, xcmap, &c)) {
					fprint(2, "emu: win-x11 can't alloc colors in default map, don't use -7\n");
					cleanexit(0);
				}
				infernotox11[map7to8[i][0]] = c.pixel;
				infernotox11[map7to8[i][1]] = c.pixel;
				x11toinferno[c.pixel] = map7to8[i][0];
			}
		}
	}
	else {
		xtblbit = 0;
		fprint(2, "emu: win-x11 unsupported visual class %d\n", xvis->class);
	}
	return;
}

static void
xmapping(XEvent *e)
{
	XMappingEvent *xe;

	if(e->type != MappingNotify)
		return;
	xe = (XMappingEvent*)e;
	if(modmap)
		XFreeModifiermap(modmap);
	modmap = XGetModifierMapping(xe->display);
	if(modmap)
		keypermod = modmap->max_keypermod;
}


/*
 * Disable generation of GraphicsExpose/NoExpose events in the GC.
 */
static GC
creategc(Drawable d)
{
	XGCValues gcv;

	gcv.function = GXcopy;
	gcv.graphics_exposures = False;
	return XCreateGC(xdisplay, d, GCFunction|GCGraphicsExposures, &gcv);
}

static void
xexpose(XEvent *e)
{
	IRectangle r;
	XExposeEvent *xe;

	if(e->type != Expose)
		return;
	xe = (XExposeEvent*)e;
	r.min.x = xe->x;
	r.min.y = xe->y;
	r.max.x = xe->x + xe->width;
	r.max.y = xe->y + xe->height;
	drawxflush(r);
}


static void
xkeyboard(XEvent *e)
{
	int ind, n;
	KeySym k;
	Rune r;
	unsigned int md;
	char buf[1];

	if(gkscanq) {
		uchar ch = (KeyCode)e->xkey.keycode;
		if(e->xany.type == KeyRelease)
			ch |= 0x80;
		qproduce(gkscanq, &ch, 1);
		return;
	}
	
	/*
	 * I tried using XtGetActionKeysym, but it didn't seem to
	 * do case conversion properly
	 * (at least, with Xterminal servers and R4 intrinsics)
	 */
	if(e->xany.type != KeyPress)
		return;

	md = e->xkey.state;
	ind = 0;
	if(md & ShiftMask)
		ind = 1;

	k = XKeycodeToKeysym(e->xany.display, (KeyCode)e->xkey.keycode, ind);

	/* May have to try unshifted version */
	if(k == NoSymbol && ind == 1)
		k = XKeycodeToKeysym(e->xany.display, (KeyCode)e->xkey.keycode, 0);

	if(k == XK_Multi_key || k == NoSymbol)
		return;
	if(k&0xFF00){
		switch(k){
		case XK_BackSpace:
		case XK_Tab:
		case XK_Escape:
		case XK_Delete:
		case XK_KP_0:
		case XK_KP_1:
		case XK_KP_2:
		case XK_KP_3:
		case XK_KP_4:
		case XK_KP_5:
		case XK_KP_6:
		case XK_KP_7:
		case XK_KP_8:
		case XK_KP_9:
		case XK_KP_Divide:
		case XK_KP_Multiply:
		case XK_KP_Subtract:
		case XK_KP_Add:
		case XK_KP_Decimal:
			k &= 0x7F;
			break;
		case XK_Linefeed:
			k = '\r';
			break;
		case XK_KP_Enter:
		case XK_Return:
			k = '\n';
			break;
		case XK_Alt_L:
		case XK_Alt_R:
		case XK_Meta_L:
		case XK_Meta_R:
			k = Latin;
			break;
		case XK_Left:
		case XK_KP_Left:
		  k = Left;
		  break;
		case XK_Down:
		case XK_KP_Down:
		  k = Down;
		  break;
		case XK_Right:
		case XK_KP_Right:
		  k = Right;
		  break;
		case XK_Up:
		case XK_KP_Up:
		  k = Up;
		  break;
		case XK_Home:
		case XK_KP_Home:
		  k = Home;
		  break;
		case XK_End:
		case XK_KP_End:
		  k = End;
		  break;
		case XK_Page_Up:
		case XK_KP_Page_Up:
		  k = Pgup;
		  break;
		case XK_Page_Down:
		case XK_KP_Page_Down:
		  k = Pgdown;
		  break;
		default:		/* not ISO-1 or tty control */
			return;
		}
	}
	/* Compensate for servers that call a minus a hyphen */
	if(k == XK_hyphen)
		k = XK_minus;
	/* Do control mapping ourselves if translator doesn't */
	if(md & ControlMask)
		k &= 0x9f;
	if(k == '\t' && ind)
		k = BackTab;
	
	if(md & Mod1Mask)
		k = APP|(k&0xff);
	if(k == NoSymbol) 
		return;

	gkbdputc(gkbdq, k);
}

static void
xmouse(XEvent *e)
{
	int s, dbl;
	XButtonEvent *be;
	XMotionEvent *me;
	XEvent motion;
	Pointer m;
	static ulong lastb, lastt;

	dbl = 0;
	switch(e->type){
	case ButtonPress:
		be = (XButtonEvent *)e;
		m.x = be->x;
		m.y = be->y;
		s = be->state;
		if(be->button == lastb && be->time - lastt < DblTime)
			dbl = 1;
		lastb = be->button;
		lastt = be->time;
		switch(be->button){
		case 1:
			s |= Button1Mask;
			break;
		case 2:
			s |= Button2Mask;
			break;
		case 3:
			s |= Button3Mask;
			break;
		}
		break;
	case ButtonRelease:
		be = (XButtonEvent *)e;
		m.x = be->x;
		m.y = be->y;
		s = be->state;
		switch(be->button){
		case 1:
			s &= ~Button1Mask;
			break;
		case 2:
			s &= ~Button2Mask;
			break;
		case 3:
			s &= ~Button3Mask;
			break;
		}
		break;
	case MotionNotify:
		me = (XMotionEvent *) e;

		/* remove excess MotionNotify events from queue and keep last one */
		while(XCheckTypedWindowEvent(xkmcon, xdrawable, MotionNotify, &motion) == True)
			me = (XMotionEvent *) &motion;

		s = me->state;
		m.x = me->x;
		m.y = me->y;
		break;
	default:
		return;
	}

	m.b = 0;
	if(s & Button1Mask)
		m.b |= 1;
	if(s & Button2Mask)
		m.b |= 2;
	if(s & Button3Mask)
		m.b |= 4;
	if(dbl)
		m.b |= 1<<4;

	m.modify = 1;
	mouseproduce(m);
}

