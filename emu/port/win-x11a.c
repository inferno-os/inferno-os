/*
 * This implementation of the screen functions for X11 uses the
 * portable implementation of the Inferno drawing operations (libmemdraw)
 * to do the work, then has flushmemscreen copy the result to the X11 display.
 * Thus it potentially supports all colour depths but with a possible
 * performance penalty (although it tries to use the X11 shared memory extension
 * to copy the result to the screen, which might reduce the latter).
 *
 *       CraigN 
 */

#define _GNU_SOURCE 1
#define XTHREADS
#include "dat.h"
#include "fns.h"
#undef log2
#include <draw.h>
#include "cursor.h"
#include "keyboard.h"
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#define Colormap	XColormap
#define Cursor		XCursor
#define Display		XDisplay
#define Drawable	XDrawable
#define Font		XFont
#define GC		XGC
#define Point		XPoint
#define Rectangle	XRectangle
#define Screen		XScreen
#define Visual		XVisual
#define Window		XWindow

#define XLIB_ILLEGAL_ACCESS

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>
#include <X11/extensions/XShm.h>

#include "keysym2ucs.h"

#undef Colormap
#undef Cursor
#undef Display
#undef XDrawable
#undef Font
#undef GC
#undef Point
#undef Rectangle
#undef Screen
#undef Visual
#undef Window

#include <sys/ipc.h>
#include <sys/shm.h>

static int displaydepth;
extern ulong displaychan;

enum
{
	DblTime	= 300		/* double click time in msec */
};

/* screen data .... */
static uchar*	gscreendata;
static uchar*	xscreendata;

XColor	map[256];	/* Inferno colormap array */
XColor	mapr[256];	/* Inferno red colormap array */
XColor	mapg[256];	/* Inferno green colormap array */
XColor	mapb[256];	/* Inferno blue colormap array */
XColor	map7[128];	/* Inferno colormap array */
uchar	map7to8[128][2];

/* for copy/paste, lifted from plan9ports via drawterm */
static Atom clipboard; 
static Atom utf8string;
static Atom targets;
static Atom text;
static Atom compoundtext;

static Atom cursorchange;

static XColormap		xcmap;		/* Default shared colormap  */
static int 		infernotox11[256]; /* Values for mapping between */
static int 		infernortox11[256]; /* Values for mapping between */
static int 		infernogtox11[256]; /* Values for mapping between */
static int 		infernobtox11[256]; /* Values for mapping between */
static int		triedscreen;
static XDrawable		xdrawable;
static void		xexpose(XEvent*);
static void		xmouse(XEvent*);
static void		xkeyboard(XEvent*);
static void		xsetcursor(XEvent*);
static void		xkbdproc(void*);
static void		xdestroy(XEvent*);
static void		xselect(XEvent*, XDisplay*);
static void		xproc(void*);
static void		xinitscreen(int, int, ulong, ulong*, int*);
static void		initxcmap(XWindow);
static XGC		creategc(XDrawable);
static void		graphicsgmap(XColor*, int);
static void		graphicscmap(XColor*);
static void		graphicsrgbmap(XColor*, XColor*, XColor*);

static int		xscreendepth;
static	XDisplay*	xdisplay;	/* used holding draw lock */
static	XDisplay*	xmcon;	/* used only in xproc */
static	XDisplay*	xkbdcon;	/* used only in xkbdproc */
static	XDisplay*	xsnarfcon;	/* used holding clip.lk */
static XVisual		*xvis;
static XGC		xgc;
static XImage 		*img;
static int              is_shm;

static int putsnarf, assertsnarf;
char *gkscanid = "emu_x11";

/*
 * The documentation for the XSHM extension implies that if the server
 * supports XSHM but is not the local machine, the XShm calls will
 * return False; but this turns out not to be the case.  Instead, the
 * server throws a BadAccess error.  So, we need to catch X errors
 * around all of our XSHM calls, sigh.
 */
static int shm_got_x_error = 0;
static XErrorHandler old_handler = 0;
static XErrorHandler old_io_handler = 0;

static int
shm_ehandler(XDisplay *dpy, XErrorEvent *error)
{
	shm_got_x_error = 1;
	return 0;
}

static void
clean_errhandlers(void)
{
	/* remove X11 error handler(s) */
	if(old_handler)
		XSetErrorHandler(old_handler); 
	old_handler = 0;
	if(old_io_handler)
		XSetErrorHandler(old_io_handler); 
	old_io_handler = 0;
}

static int
makesharedfb(void)
{
	XShmSegmentInfo *shminfo;

	shminfo = malloc(sizeof(XShmSegmentInfo));
	if(shminfo == nil) {
		fprint(2, "emu: cannot allocate XShmSegmentInfo\n");
		cleanexit(0);
	}

	/* setup to catch X11 error(s) */
	XSync(xdisplay, 0); 
	shm_got_x_error = 0; 
	if(old_handler != shm_ehandler)
		old_handler = XSetErrorHandler(shm_ehandler);
	if(old_io_handler != shm_ehandler)
		old_io_handler = XSetErrorHandler(shm_ehandler);

	img = XShmCreateImage(xdisplay, xvis, xscreendepth, ZPixmap, 
			      NULL, shminfo, Xsize, Ysize);
	XSync(xdisplay, 0);

	/* did we get an X11 error? if so then try without shm */
	if(shm_got_x_error) {
		free(shminfo);
		shminfo = NULL;
		clean_errhandlers();
		return 0;
	}
	
	if(img == nil) {
		fprint(2, "emu: cannot allocate virtual screen buffer\n");
		cleanexit(0);
	}
	
	shminfo->shmid = shmget(IPC_PRIVATE, img->bytes_per_line * img->height, IPC_CREAT|0777);
	shminfo->shmaddr = img->data = shmat(shminfo->shmid, 0, 0);
	shminfo->readOnly = True;

	if(!XShmAttach(xdisplay, shminfo)) {
		fprint(2, "emu: cannot allocate virtual screen buffer\n");
		cleanexit(0);
	}
	XSync(xdisplay, 0);

	/*
	 * Delete the shared segment right now; the segment
	 * won't actually go away until both the client and
	 * server have deleted it.  The server will delete it
	 * as soon as the client disconnects, so we might as
	 * well delete our side now as later.
	 */
	shmctl(shminfo->shmid, IPC_RMID, 0);

	/* did we get an X11 error? if so then try without shm */
	if(shm_got_x_error) {
		XDestroyImage(img);
		XSync(xdisplay, 0);
		free(shminfo);
		shminfo = NULL;
		clean_errhandlers();
		return 0;
	}

	gscreendata = malloc(Xsize * Ysize * (displaydepth >> 3));
	if(gscreendata == nil) {
		fprint(2, "emu: cannot allocate screen buffer (%dx%dx%d)\n", Xsize, Ysize, displaydepth);
		cleanexit(0);
	}
	xscreendata = (uchar*)img->data;
	
	clean_errhandlers();
	return 1;
}

uchar*
attachscreen(Rectangle *r, ulong *chan, int *d, int *width, int *softscreen)
{
	int depth;

	Xsize &= ~0x3;	/* ensure multiple of 4 */

	r->min.x = 0;
	r->min.y = 0;
	r->max.x = Xsize;
	r->max.y = Ysize;

	if(!triedscreen){
		xinitscreen(Xsize, Ysize, displaychan, chan, d);
		/*
		 * moved xproc from here to end since it could cause an expose event and
		 * hence a flushmemscreen before xscreendata is initialized
		 */
	}
	else{
		*chan = displaychan;
		*d = displaydepth;
	}

	*width = (Xsize/4)*(*d/8);
	*softscreen = 1;
	displaychan = *chan;
	displaydepth = *d;

	/* check for X Shared Memory Extension */
	is_shm = XShmQueryExtension(xdisplay);
	
	if(!is_shm || !makesharedfb()){
		is_shm = 0;
		depth = xscreendepth;
		if(depth == 24)
			depth = 32;

		/* allocate virtual screen */	
		gscreendata = malloc(Xsize * Ysize * (displaydepth >> 3));
		xscreendata = malloc(Xsize * Ysize * (depth >> 3));
		if(gscreendata == nil || xscreendata == nil) {
			fprint(2, "emu: can not allocate virtual screen buffer (%dx%dx%d[%d])\n", Xsize, Ysize, displaydepth, depth);
			return 0;
		}
		img = XCreateImage(xdisplay, xvis, xscreendepth, ZPixmap, 0, 
				   (char*)xscreendata, Xsize, Ysize, 8, Xsize * (depth >> 3));
		if(img == nil) {
			fprint(2, "emu: can not allocate virtual screen buffer (%dx%dx%d)\n", Xsize, Ysize, depth);
			return 0;
		}
		
	}

	if(!triedscreen){
		triedscreen = 1;
		kproc("xproc", xproc, xmcon, 0);
		kproc("xkbdproc", xkbdproc, xkbdcon, KPX11);	/* silly stack size for bloated X11 */
	}

	return gscreendata;
}

static void
copy32to32(Rectangle r)
{
	int dx, width;
	uchar *p, *ep, *cp;
	u32int v, w, *dp, *wp, *edp, *lp;

	width = Dx(r);
	dx = Xsize - width;
	dp = (u32int*)(gscreendata + (r.min.y * Xsize + r.min.x) * 4);
	wp = (u32int*)(xscreendata + (r.min.y * Xsize + r.min.x) * 4);
	edp = (u32int*)(gscreendata + (r.max.y * Xsize + r.max.x) * 4);
	while(dp < edp) {
		lp = dp + width;
		while(dp < lp){
			v = *dp++;
			w = infernortox11[(v>>16)&0xff]<<16|infernogtox11[(v>>8)&0xff]<<8|infernobtox11[(v>>0)&0xff]<<0;
			*wp++ = w;
		}
		dp += dx;
		wp += dx;
	}
}

static void
copy8to32(Rectangle r)
{
	int dx, width;
	uchar *p, *ep, *lp;
	u32int *wp;

	width = Dx(r);
	dx = Xsize - width;
	p = gscreendata + r.min.y * Xsize + r.min.x;
	wp = (u32int *)(xscreendata + (r.min.y * Xsize + r.min.x) * 4);
	ep = gscreendata + r.max.y * Xsize + r.max.x;
	while(p < ep) {
		lp = p + width;
		while(p < lp) 
			*wp++ = infernotox11[*p++];
		p += dx;
		wp += dx;
	}
}

static void
copy8to24(Rectangle r)
{
	int dx, width, v;
	uchar *p, *cp, *ep, *lp;

	width = Dx(r);
	dx = Xsize - width;
	p = gscreendata + r.min.y * Xsize + r.min.x;
	cp = xscreendata + (r.min.y * Xsize + r.min.x) * 3;
	ep = gscreendata + r.max.y * Xsize + r.max.x;
	while(p < ep) {
		lp = p + width;
		while(p < lp){
			v = infernotox11[*p++];
			cp[0] = (v>>16)&0xff;
			cp[1] = (v>>8)&0xff;
			cp[2] = (v>>0)&0xff;
			cp += 3;
		}
		p += dx;
		cp += 3*dx;
	}
}

static void
copy8to16(Rectangle r)
{
	int dx, width;
	uchar *p, *ep, *lp;
	u16int *sp;

	width = Dx(r);
	dx = Xsize - width;
	p = gscreendata + r.min.y * Xsize + r.min.x;
	sp = (unsigned short *)(xscreendata + (r.min.y * Xsize + r.min.x) * 2);
	ep = gscreendata + r.max.y * Xsize + r.max.x;
	while(p < ep) {
		lp = p + width;
		while(p < lp) 
			*sp++ = infernotox11[*p++];
		p += dx;
		sp += dx;
	}
}

static void
copy8to8(Rectangle r)
{
	int dx, width;
	uchar *p, *cp, *ep, *lp;

	width = Dx(r);
	dx = Xsize - width;
	p = gscreendata + r.min.y * Xsize + r.min.x;
	cp = xscreendata + r.min.y * Xsize + r.min.x;
	ep = gscreendata + r.max.y * Xsize + r.max.x;
	while(p < ep) {
		lp = p + width;
		while(p < lp)
			*cp++ = infernotox11[*p++];
		p += dx;
		cp += dx;
	}
}

static void
copy8topixel(Rectangle r)
{
	int x, y;
	uchar *p;

	/* mainly for 4-bit greyscale */
	for (y = r.min.y; y < r.max.y; y++) {
		x = r.min.x;
		p = gscreendata + y * Xsize + x;
		while (x < r.max.x)
			XPutPixel(img, x++, y, infernotox11[*p++]);
	}
}

void
flushmemscreen(Rectangle r)
{
	char chanbuf[16];

	// Clip to screen
	if(r.min.x < 0)
		r.min.x = 0;
	if(r.min.y < 0)
		r.min.y = 0;
	if(r.max.x >= Xsize)
		r.max.x = Xsize - 1;
	if(r.max.y >= Ysize)
                r.max.y = Ysize - 1;
	if(r.max.x <= r.min.x || r.max.y <= r.min.y)
		return;

	switch(displaydepth){
	case 32:
		copy32to32(r);
		break;
	case 8:
		switch(xscreendepth){
		case 24:
			/* copy8to24(r); */	/* doesn't happen? */
			/* break */
		case 32:
			copy8to32(r);
			break;
		case 16:
			copy8to16(r);
			break;
		case 8:
			copy8to8(r);
			break;
		default:
			copy8topixel(r);
			break;
		}
		break;
	default:
		fprint(2, "emu: bad display depth %d chan %s xscreendepth %d\n", displaydepth,
			chantostr(chanbuf, displaychan), xscreendepth);
		cleanexit(0);
	}

	XLockDisplay(xdisplay);
	/* Display image on X11 */
	if(is_shm)
		XShmPutImage(xdisplay, xdrawable, xgc, img, r.min.x, r.min.y, r.min.x, r.min.y, Dx(r), Dy(r), 0);
	else
		XPutImage(xdisplay, xdrawable, xgc, img, r.min.x, r.min.y, r.min.x, r.min.y, Dx(r), Dy(r));
	XSync(xdisplay, 0);
	XUnlockDisplay(xdisplay);
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

void
setpointer(int x, int y)
{
	drawqlock();
	XLockDisplay(xdisplay);
	XWarpPointer(xdisplay, None, xdrawable, 0, 0, 0, 0, x, y);
	XFlush(xdisplay);
	XUnlockDisplay(xdisplay);
	drawqunlock();
}

static void
xkbdproc(void *arg)
{
	XEvent event;
	XDisplay *xd;

	xd = arg;

	/* BEWARE: the value of up is not defined for this proc on some systems */

	XLockDisplay(xd);	/* should be ours alone */
	XSelectInput(xd, xdrawable, KeyPressMask | KeyReleaseMask);		
	for(;;){
		XNextEvent(xd, &event);
		xkeyboard(&event);
		xsetcursor(&event);
	}
}

static void
xproc(void *arg)
{
	ulong mask;
	XEvent event;
	XDisplay *xd;

	closepgrp(up->env->pgrp);
	closefgrp(up->env->fgrp);
	closeegrp(up->env->egrp);
	closesigs(up->env->sigs);

	xd = arg;
	mask = ButtonPressMask|
		ButtonReleaseMask|
		PointerMotionMask|
		Button1MotionMask|
		Button2MotionMask|
		Button3MotionMask|
		Button4MotionMask|
		Button5MotionMask|
		ExposureMask|
		StructureNotifyMask;

	XLockDisplay(xd);	/* should be ours alone */
	XSelectInput(xd, xdrawable, mask);		
	for(;;){
		XNextEvent(xd, &event);
		xselect(&event, xd);
		xmouse(&event);
		xexpose(&event);
		xdestroy(&event);
	}
}

/*
 * this crud is here because X11 can put huge amount of data
 * on the stack during keyboard translation and cursor changing(!).
 * we do both in a dedicated process with lots of stack, perhaps even enough.
 */

enum {
	CursorSize=	32	/* biggest cursor size */
};

typedef struct ICursor ICursor;
struct ICursor {
	int	inuse;
	int	modify;
	int	hotx;
	int	hoty;
	int	w;
	int	h;
	uchar	src[(CursorSize/8)*CursorSize];	/* image and mask bitmaps */
	uchar	mask[(CursorSize/8)*CursorSize];
};
static ICursor icursor;

static void
xcurslock(void)
{
	while(_tas(&icursor.inuse) != 0)
		osyield();
}

static void
xcursunlock(void)
{
	icursor.inuse = 0;
}

static void
xcursnotify(void)
{
	XClientMessageEvent e;

	memset(&e, 0, sizeof e);
	e.type = ClientMessage;
	e.window = xdrawable;
	e.message_type = cursorchange;
	e.format = 8;
	XSendEvent(xkbdcon, xdrawable, True, KeyPressMask, (XEvent*)&e);
	XFlush(xkbdcon);
}

void
drawcursor(Drawcursor* c)
{
	uchar *bs, *bc, *ps, *pm;
	int i, j, w, h, bpl;

	if(c->data == nil){
		drawqlock();
		if(icursor.h != 0){
			xcurslock();
			icursor.h = 0;
			icursor.modify = 1;
			xcursunlock();
		}
		xcursnotify();
		drawqunlock();
		return;
	}

	drawqlock();
	xcurslock();
	icursor.modify = 0;	/* xsetcursor will now ignore it */
	xcursunlock();

	h = (c->maxy-c->miny)/2;	/* image, then mask */
	bpl = bytesperline(Rect(c->minx, c->miny, c->maxx, c->maxy), 1);
	w = bpl;
	if(w > CursorSize/8)
		w = CursorSize/8;

	ps = icursor.src;
	pm = icursor.mask;
	bc = c->data;
	bs = c->data + h*bpl;
	for(i = 0; i < h; i++){
		for(j = 0; j < bpl && j < w; j++) {
			*ps++ = revbyte(bs[j]);
			*pm++ = revbyte(bs[j] | bc[j]);
		}
		bs += bpl;
		bc += bpl;
	}
	icursor.h = h;
	icursor.w = w*8;
	icursor.hotx = c->hotx;
	icursor.hoty = c->hoty;
	icursor.modify = 1;
	xcursnotify();
	drawqunlock();
}

static void
xsetcursor(XEvent *e)
{
	ICursor ic;
	XCursor xc;
	XColor fg, bg;
	Pixmap xsrc, xmask;
	static XCursor xcursor;

	if(e->type != ClientMessage || !e->xclient.send_event || e->xclient.message_type != cursorchange)
		return;

	xcurslock();
	if(icursor.modify == 0){
		xcursunlock();
		return;
	}
	icursor.modify = 0;
	if(icursor.h == 0){
		xcursunlock();
		/* set the default system cursor */
		if(xcursor != 0) {
			XFreeCursor(xkbdcon, xcursor);
			xcursor = 0;
		}
		XUndefineCursor(xkbdcon, xdrawable);
		XFlush(xkbdcon);
		return;
	}
	ic = icursor;
	xcursunlock();

	xsrc = XCreateBitmapFromData(xkbdcon, xdrawable, (char*)ic.src, ic.w, ic.h);
	xmask = XCreateBitmapFromData(xkbdcon, xdrawable, (char*)ic.mask, ic.w, ic.h);

	fg = map[0];
	bg = map[255];
	fg.pixel = infernotox11[0];
	bg.pixel = infernotox11[255];
	xc = XCreatePixmapCursor(xkbdcon, xsrc, xmask, &fg, &bg, -ic.hotx, -ic.hoty);
	if(xc != 0) {
		XDefineCursor(xkbdcon, xdrawable, xc);
		if(xcursor != 0)
			XFreeCursor(xkbdcon, xcursor);
		xcursor = xc;
	}
	XFreePixmap(xkbdcon, xsrc);
	XFreePixmap(xkbdcon, xmask);
	XFlush(xkbdcon);
}

typedef struct Mg Mg;
struct Mg
{
	int	code;
	int	bit;
	int	len;
	ulong	mask;
};

static int
maskx(Mg* g, int code, ulong mask)
{
	int i;

	for(i=0; i<32; i++)
		if(mask & (1<<i))
			break;
	if(i == 32)
		return 0;
	g->code = code;
	g->bit = i;
	g->mask = mask;
	for(g->len = 0; i<32 && (mask & (1<<i))!=0; i++)
		g->len++;
	return 1;
}

/*
 * for a given depth, we need to check the available formats
 * to find how many actual bits are used per pixel.
 */
static int
xactualdepth(int screenno, int depth)
{
	XPixmapFormatValues *pfmt;
	int i, n;

	pfmt = XListPixmapFormats(xdisplay, &n);
	for(i=0; i<n; i++)
		if(pfmt[i].depth == depth)
			return pfmt[i].bits_per_pixel;
	return -1;
}

static int
xtruevisual(int screenno, int reqdepth, XVisualInfo *vi, ulong *chan)
{
	XVisual *xv;
	Mg r, g, b;
	int pad, d;
	ulong c;
	char buf[30];

	if(XMatchVisualInfo(xdisplay, screenno, reqdepth, TrueColor, vi) ||
	   XMatchVisualInfo(xdisplay, screenno, reqdepth, DirectColor, vi)){
		xv = vi->visual;
		if(maskx(&r, CRed, xv->red_mask) &&
		   maskx(&g, CGreen, xv->green_mask) &&
		   maskx(&b, CBlue, xv->blue_mask)){
			d = xactualdepth(screenno, reqdepth);
			if(d < 0)
				return 0;
			pad = d - (r.len + g.len + b.len);
			if(0){
				fprint(2, "r: %8.8lux %d %d\ng: %8.8lux %d %d\nb: %8.8lux %d %d\n",
				 xv->red_mask, r.bit, r.len, xv->green_mask, g.bit, g.len, xv->blue_mask, b.bit, b.len);
			}
			if(r.bit > b.bit)
				c = CHAN3(CRed, r.len, CGreen, g.len, CBlue, b.len);
			else
				c = CHAN3(CBlue, b.len, CGreen, g.len, CRed, r.len);
			if(pad > 0)
				c |= CHAN1(CIgnore, pad) << 24;
			*chan = c;
			xscreendepth = reqdepth;
			if(0)
				fprint(2, "chan=%s reqdepth=%d bits=%d\n", chantostr(buf, c), reqdepth, d);
			return 1;
		}
	}
	return 0;
}

static int
xmapvisual(int screenno, XVisualInfo *vi, ulong *chan)
{
	if(XMatchVisualInfo(xdisplay, screenno, 8, PseudoColor, vi) ||
	   XMatchVisualInfo(xdisplay, screenno, 8, StaticColor, vi)){
		*chan = CMAP8;
		xscreendepth = 8;
		return 1;
	}
	return 0;
}

static void
xinitscreen(int xsize, int ysize, ulong reqchan, ulong *chan, int *d)
{
	char *argv[2];
	char *dispname;
	XWindow rootwin;
	XWMHints hints;
	XVisualInfo xvi;
	XScreen *screen;
	int rootscreennum;
	XTextProperty name;
	XClassHint classhints;
	XSizeHints normalhints;
	XSetWindowAttributes attrs;
	char buf[30];
	int i;
 
	xdrawable = 0;

	dispname = getenv("DISPLAY");
	if(dispname == nil)
		dispname = "not set";
	XInitThreads();
	xdisplay = XOpenDisplay(NULL);
	if(xdisplay == 0){
		fprint(2, "emu: win-x11 open %r, DISPLAY is %s\n", dispname);
		cleanexit(0);
	}

	rootscreennum = DefaultScreen(xdisplay);
	rootwin = DefaultRootWindow(xdisplay);
	xscreendepth = DefaultDepth(xdisplay, rootscreennum);
	xvis = DefaultVisual(xdisplay, rootscreennum);
	screen = DefaultScreenOfDisplay(xdisplay);
	xcmap = DefaultColormapOfScreen(screen);

	if(reqchan == 0){
		*chan = 0;
		if(xscreendepth <= 16){	/* try for better colour */
			xtruevisual(rootscreennum, 16, &xvi, chan) ||
			xtruevisual(rootscreennum, 15, &xvi, chan) ||
			xtruevisual(rootscreennum, 24, &xvi, chan) ||
			xmapvisual(rootscreennum, &xvi, chan);
		}else{
			xtruevisual(rootscreennum, xscreendepth, &xvi, chan) ||
			xtruevisual(rootscreennum, 24, &xvi, chan);
		}
		if(*chan == 0){
			fprint(2, "emu: could not find suitable x11 pixel format for depth %d on this display\n", xscreendepth);
			cleanexit(0);
		}
		reqchan = *chan;
		*d = chantodepth(reqchan);
		xvis = xvi.visual;
	}else{
		*chan = reqchan;		/* not every channel description will work */
		*d = chantodepth(reqchan);
		if(*d != xactualdepth(rootscreennum, *d)){
			fprint(2, "emu: current x11 display configuration does not support %s (depth %d) directly\n",
				chantostr(buf, reqchan), *d);
			cleanexit(0);
		}
	}

	if(xvis->class != StaticColor) {
		if(TYPE(*chan) == CGrey)
			graphicsgmap(map, NBITS(reqchan));
		else{
			graphicscmap(map);
			graphicsrgbmap(mapr, mapg, mapb);
		}
		initxcmap(rootwin);
	}

	memset(&attrs, 0, sizeof(attrs));
	attrs.colormap = xcmap;
	attrs.background_pixel = 0;
	attrs.border_pixel = 0;
	/* attrs.override_redirect = 1;*/ /* WM leave me alone! |CWOverrideRedirect */
	xdrawable = XCreateWindow(xdisplay, rootwin, 0, 0, xsize, ysize, 0, xscreendepth, 
				  InputOutput, xvis, CWBackPixel|CWBorderPixel|CWColormap, &attrs);

	/*
	 * set up property as required by ICCCM
	 */
	memset(&name, 0, sizeof(name));
	name.value = (uchar*)"inferno";
	name.encoding = XA_STRING;
	name.format = 8;
	name.nitems = strlen((char*)name.value);

	memset(&normalhints, 0, sizeof(normalhints));
	normalhints.flags = USSize|PMaxSize;
	normalhints.max_width = normalhints.width = xsize;
	normalhints.max_height = normalhints.height = ysize;
	hints.flags = InputHint|StateHint;
	hints.input = 1;
	hints.initial_state = NormalState;

	memset(&classhints, 0, sizeof(classhints));
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

	XMapWindow(xdisplay, xdrawable);
	XFlush(xdisplay);

	xgc = creategc(xdrawable);

	xmcon = XOpenDisplay(NULL);
	xsnarfcon = XOpenDisplay(NULL);
	xkbdcon = XOpenDisplay(NULL);
	if(xmcon == 0 || xsnarfcon == 0 || xkbdcon == 0){
		fprint(2, "emu: win-x11 open %r, DISPLAY is %s\n", dispname);
		cleanexit(0);
	}

	clipboard = XInternAtom(xmcon, "CLIPBOARD", False);
	utf8string = XInternAtom(xmcon, "UTF8_STRING", False);
	targets = XInternAtom(xmcon, "TARGETS", False);
	text = XInternAtom(xmcon, "TEXT", False);
	compoundtext = XInternAtom(xmcon, "COMPOUND_TEXT", False);

	cursorchange = XInternAtom(xkbdcon, "TheCursorHasChanged", False);

}

static void
graphicsgmap(XColor *map, int d)
{
	int i, j, s, m, p;

	s = 8-d;
	m = 1;
	while(--d >= 0)
		m *= 2;
	m = 255/(m-1);
	for(i=0; i < 256; i++){
		j = (i>>s)*m;
		p = 255-i;
		map[p].red = map[p].green = map[p].blue = (255-j)*0x0101;
		map[p].pixel = p;
		map[p].flags = DoRed|DoGreen|DoBlue;
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
					/* was idx = 255 - idx; */
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

static void
graphicsrgbmap(XColor *mapr, XColor *mapg, XColor *mapb)
{
	int i;

	memset(mapr, 0, 256*sizeof(XColor));
	memset(mapg, 0, 256*sizeof(XColor));
	memset(mapb, 0, 256*sizeof(XColor));
	for(i=0; i < 256; i++){
		mapr[i].red = mapg[i].green = mapb[i].blue = i*0x0101;
		mapr[i].pixel = mapg[i].pixel = mapb[i].pixel = i;
		mapr[i].flags = mapg[i].flags = mapb[i].flags = DoRed|DoGreen|DoBlue;
	}
}

/*
 * Initialize and install the Inferno colormap as a private colormap for this
 * application.  Inferno gets the best colors here when it has the cursor focus.
 */  
static void 
initxcmap(XWindow w)
{
	XColor c;
	int i;

	if(xscreendepth <= 1)
		return;

	switch(xvis->class){
	case TrueColor:
	case DirectColor:
		for(i = 0; i < 256; i++) {
			c = map[i];
			/* find index into colormap for our RGB */
			if(!XAllocColor(xdisplay, xcmap, &c)) {
				fprint(2, "emu: win-x11 can't alloc color\n");
				cleanexit(0);
			}
			infernotox11[map[i].pixel] = c.pixel;
			if(xscreendepth >= 24){
				c = mapr[i];
				XAllocColor(xdisplay, xcmap, &c);
				infernortox11[i] = (c.pixel>>16)&0xff;
				c = mapg[i];
				XAllocColor(xdisplay, xcmap, &c);
				infernogtox11[i] = (c.pixel>>8)&0xff;
				c = mapb[i];
				XAllocColor(xdisplay, xcmap, &c);
				infernobtox11[i] = (c.pixel>>0)&0xff;
			}
		}
if(0){int i, j; for(i=0;i<256; i+=16){print("%3d", i); for(j=i; j<i+16; j++)print(" %2.2ux/%2.2ux/%2.2ux", infernortox11[j], infernogtox11[j],infernobtox11[j]); print("\n");}}
		/* TO DO: if the map(s) used give the identity map, don't use the map during copy */
		break;

	case PseudoColor:
		if(xtblbit == 0){
			xcmap = XCreateColormap(xdisplay, w, xvis, AllocAll); 
			XStoreColors(xdisplay, xcmap, map, 256);
			for(i = 0; i < 256; i++)
				infernotox11[i] = i;
			/* TO DO: the map is the identity, so don't need the map in copy */
		} else {
			for(i = 0; i < 128; i++) {
				c = map7[i];
				if(!XAllocColor(xdisplay, xcmap, &c)) {
					fprint(2, "emu: win-x11 can't alloc colors in default map, don't use -7\n");
					cleanexit(0);
				}
				infernotox11[map7to8[i][0]] = c.pixel;
				infernotox11[map7to8[i][1]] = c.pixel;
			}
		}
		break;

	default:
		xtblbit = 0;
		fprint(2, "emu: win-x11 unsupported visual class %d\n", xvis->class);
		break;
	}
}

static void
xdestroy(XEvent *e)
{
	XDestroyWindowEvent *xe;
	if(e->type != DestroyNotify)
		return;
	xe = (XDestroyWindowEvent*)e;
	if(xe->window == xdrawable)
		cleanexit(0);
}

/*
 * Disable generation of GraphicsExpose/NoExpose events in the XGC.
 */
static XGC
creategc(XDrawable d)
{
	XGCValues gcv;

	gcv.function = GXcopy;
	gcv.graphics_exposures = False;
	return XCreateGC(xdisplay, d, GCFunction|GCGraphicsExposures, &gcv);
}

static void
xexpose(XEvent *e)
{
	Rectangle r;
	XExposeEvent *xe;

	if(e->type != Expose)
		return;
	xe = (XExposeEvent*)e;
	r.min.x = xe->x;
	r.min.y = xe->y;
	r.max.x = xe->x + xe->width;
	r.max.y = xe->y + xe->height;
	drawqlock();
	flushmemscreen(r);
	drawqunlock();
}

static void
xkeyboard(XEvent *e)
{
	int ind, md;
	KeySym k;

	if(gkscanq != nil && (e->type == KeyPress || e->type == KeyRelease)){
		uchar ch = e->xkey.keycode;
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
	if(0){
		k = XKeycodeToKeysym(e->xany.display, (KeyCode)e->xkey.keycode, ind);

		/* May have to try unshifted version */
		if(k == NoSymbol && ind == 1)
			k = XKeycodeToKeysym(e->xany.display, (KeyCode)e->xkey.keycode, 0);
	}else
		XLookupString((XKeyEvent*)e, NULL, 0, &k, NULL);

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
		case XK_KP_Space:
			k = ' ';
			break;
//		case XK_Home:
//		case XK_KP_Home:
//			k = Khome;
//			break;
		case XK_Left:
		case XK_KP_Left:
			k = Left;
			break;
		case XK_Up:
		case XK_KP_Up:
			k = Up;
			break;
		case XK_Down:
		case XK_KP_Down:
			k = Down;
			break;
		case XK_Right:
		case XK_KP_Right:
			k = Right;
			break;
//		case XK_Page_Down:
//		case XK_KP_Page_Down:
//			k = Kpgdown;
//			break;
		case XK_End:
		case XK_KP_End:
			k = End;
			break;
//		case XK_Page_Up:	
//		case XK_KP_Page_Up:
//			k = Kpgup;
//			break;
//		case XK_Insert:
//		case XK_KP_Insert:
//			k = Kins;
//			break;
		case XK_KP_Enter:
		case XK_Return:
			k = '\n';
			break;
		case XK_Alt_L:
		case XK_Alt_R:
			k = Latin;
			break;
		case XK_Shift_L:
		case XK_Shift_R:
		case XK_Control_L:
		case XK_Control_R:
		case XK_Caps_Lock:
		case XK_Shift_Lock:

		case XK_Meta_L:
		case XK_Meta_R:
		case XK_Super_L:
		case XK_Super_R:
		case XK_Hyper_L:
		case XK_Hyper_R:
			return;
		default:                /* not ISO-1 or tty control */
 			if(k>0xff){
				k = keysym2ucs(k); /* supplied by X */
				if(k == -1)
					return;
			}
			break;
		}
	}

	/* Compensate for servers that call a minus a hyphen */
	if(k == XK_hyphen)
		k = XK_minus;
	/* Do control mapping ourselves if translator doesn't */
	if(md & ControlMask)
		k &= 0x9f;
	if(0){
		if(k == '\t' && ind)
			k = BackTab;

		if(md & Mod1Mask)
			k = APP|(k&0xff);
	}
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
	int x, y, b;
	static ulong lastb, lastt;

	if(putsnarf != assertsnarf){
		assertsnarf = putsnarf;
		XSetSelectionOwner(xmcon, XA_PRIMARY, xdrawable, CurrentTime);
		if(clipboard != None)
			XSetSelectionOwner(xmcon, clipboard, xdrawable, CurrentTime);
		XFlush(xmcon);
	}

	dbl = 0;
	switch(e->type){
	case ButtonPress:
		be = (XButtonEvent *)e;
		/* 
		 * Fake message, just sent to make us announce snarf.
		 * Apparently state and button are 16 and 8 bits on
		 * the wire, since they are truncated by the time they
		 * get to us.
		 */
		if(be->send_event
		&& (~be->state&0xFFFF)==0
		&& (~be->button&0xFF)==0)
			return;
		x = be->x;
		y = be->y;
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
		case 4:
			s |= Button4Mask;
			break;
		case 5:
			s |= Button5Mask;
			break;
		}
		break;
	case ButtonRelease:
		be = (XButtonEvent *)e;
		x = be->x;
		y = be->y;
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
		case 4:
			s &= ~Button4Mask;
			break;
		case 5:
			s &= ~Button5Mask;
			break;
		}
		break;
	case MotionNotify:
		me = (XMotionEvent *) e;

		/* remove excess MotionNotify events from queue and keep last one */
		while(XCheckTypedWindowEvent(xmcon, xdrawable, MotionNotify, &motion) == True)
			me = (XMotionEvent *) &motion;

		s = me->state;
		x = me->x;
		y = me->y;
		break;
	default:
		return;
	}

	b = 0;
	if(s & Button1Mask)
		b |= 1;
	if(s & Button2Mask)
		b |= 2;
	if(s & Button3Mask)
		b |= 4;
	if(s & Button4Mask)
		b |= 8;
	if(s & Button5Mask)
		b |= 16;
	if(dbl)
		b |= 1<<8;

	mousetrack(b, x, y, 0);
}

#include "x11-keysym2ucs.c"

/*
 * Cut and paste.  Just couldn't stand to make this simple...
 */

enum{
	SnarfSize=	100*1024
};

typedef struct Clip Clip;
struct Clip
{
	char buf[SnarfSize];
	QLock lk;
};
Clip clip;

#undef long	/* sic */
#undef ulong

static char*
_xgetsnarf(XDisplay *xd)
{
	uchar *data, *xdata;
	Atom clipboard, type, prop;
	unsigned long len, lastlen, dummy;
	int fmt, i;
	XWindow w;

	qlock(&clip.lk);
	/*
	 * Have we snarfed recently and the X server hasn't caught up?
	 */
	if(putsnarf != assertsnarf)
		goto mine;

	/*
	 * Is there a primary selection (highlighted text in an xterm)?
	 */
	clipboard = XA_PRIMARY;
	w = XGetSelectionOwner(xd, XA_PRIMARY);
	if(w == xdrawable){
	mine:
		data = (uchar*)strdup(clip.buf);
		goto out;
	}

	/*
	 * If not, is there a clipboard selection?
	 */
	if(w == None && clipboard != None){
		clipboard = clipboard;
		w = XGetSelectionOwner(xd, clipboard);
		if(w == xdrawable)
			goto mine;
	}

	/*
	 * If not, give up.
	 */
	if(w == None){
		data = nil;
		goto out;
	}
		
	/*
	 * We should be waiting for SelectionNotify here, but it might never
	 * come, and we have no way to time out.  Instead, we will clear
	 * local property #1, request our buddy to fill it in for us, and poll
	 * until he's done or we get tired of waiting.
	 *
	 * We should try to go for utf8string instead of XA_STRING,
	 * but that would add to the polling.
	 */
	prop = 1;
	XChangeProperty(xd, xdrawable, prop, XA_STRING, 8, PropModeReplace, (uchar*)"", 0);
	XConvertSelection(xd, clipboard, XA_STRING, prop, xdrawable, CurrentTime);
	XFlush(xd);
	lastlen = 0;
	for(i=0; i<10 || (lastlen!=0 && i<30); i++){
		osmillisleep(100);
		XGetWindowProperty(xd, xdrawable, prop, 0, 0, 0, AnyPropertyType,
			&type, &fmt, &dummy, &len, &data);
		if(lastlen == len && len > 0)
			break;
		lastlen = len;
	}
	if(i == 10){
		data = nil;
		goto out;
	}
	/* get the property */
	data = nil;
	XGetWindowProperty(xd, xdrawable, prop, 0, SnarfSize/sizeof(unsigned long), 0, 
		AnyPropertyType, &type, &fmt, &len, &dummy, &xdata);
	if((type != XA_STRING && type != utf8string) || len == 0){
		if(xdata)
			XFree(xdata);
		data = nil;
	}else{
		if(xdata){
			data = (uchar*)strdup((char*)xdata);
			XFree(xdata);
		}else
			data = nil;
	}
out:
	qunlock(&clip.lk);
	return (char*)data;
}

static void
_xputsnarf(XDisplay *xd, char *data)
{
	XButtonEvent e;

	if(strlen(data) >= SnarfSize)
		return;
	qlock(&clip.lk);
	strcpy(clip.buf, data);

	/* leave note for mouse proc to assert selection ownership */
	putsnarf++;

	/* send mouse a fake event so snarf is announced */
	memset(&e, 0, sizeof e);
	e.type = ButtonPress;
	e.window = xdrawable;
	e.state = ~0;
	e.button = ~0;
	XSendEvent(xd, xdrawable, True, ButtonPressMask, (XEvent*)&e);
	XFlush(xd);
	qunlock(&clip.lk);
}

static void
xselect(XEvent *e, XDisplay *xd)
{
	char *name;
	XEvent r;
	XSelectionRequestEvent *xe;
	Atom a[4];

	if(e->xany.type != SelectionRequest)
		return;

	memset(&r, 0, sizeof r);
	xe = (XSelectionRequestEvent*)e;
if(0) iprint("xselect target=%d requestor=%d property=%d selection=%d\n",
	xe->target, xe->requestor, xe->property, xe->selection);
	r.xselection.property = xe->property;
	if(xe->target == targets){
		a[0] = XA_STRING;
		a[1] = utf8string;
		a[2] = text;
		a[3] = compoundtext;

		XChangeProperty(xd, xe->requestor, xe->property, xe->target,
			8, PropModeReplace, (uchar*)a, sizeof a);
	}else if(xe->target == XA_STRING || xe->target == utf8string || xe->target == text || xe->target == compoundtext){
		/* if the target is STRING we're supposed to reply with Latin1 XXX */
		qlock(&clip.lk);
		XChangeProperty(xd, xe->requestor, xe->property, xe->target,
			8, PropModeReplace, (uchar*)clip.buf, strlen(clip.buf));
		qunlock(&clip.lk);
	}else{
		iprint("get %d\n", xe->target);
		name = XGetAtomName(xd, xe->target);
		if(name == nil)
			iprint("XGetAtomName failed\n");
		else if(strcmp(name, "TIMESTAMP") != 0)
			iprint("%s: cannot handle selection request for '%s' (%d)\n", argv0, name, (int)xe->target);
		r.xselection.property = None;
	}

	r.xselection.display = xe->display;
	/* r.xselection.property filled above */
	r.xselection.target = xe->target;
	r.xselection.type = SelectionNotify;
	r.xselection.requestor = xe->requestor;
	r.xselection.time = xe->time;
	r.xselection.send_event = True;
	r.xselection.selection = xe->selection;
	XSendEvent(xd, xe->requestor, False, 0, &r);
	XFlush(xd);
}

char*
clipread(void)
{
	char *p;

	if(xsnarfcon == nil)
		return nil;
	XLockDisplay(xsnarfcon);
	p = _xgetsnarf(xsnarfcon);
	XUnlockDisplay(xsnarfcon);
	return p;
}

int
clipwrite(char *buf)
{
	if(xsnarfcon == nil)
		return 0;
	XLockDisplay(xsnarfcon);
	_xputsnarf(xsnarfcon, buf);
	XUnlockDisplay(xsnarfcon);
	return 0;
}
