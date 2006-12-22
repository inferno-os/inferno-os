#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "io.h"
#include "dat.h"
#include "fns.h"

#include <draw.h>
#include <memdraw.h>
#include "screen.h"

extern Video *vid;
extern Memimage gscreen;

static Vctlr*	init(Vctlr* vctlr, int x, int y, int d);
static int	setcolour(ulong p, ulong r, ulong g, ulong b);
static void	enable(void);
static void	disable(void);
static void	move(int cx, int cy);
static void	load(Cursor *c);
static int	isloaded(void);

extern void*	memcpy(void*, void*, int);
extern void	cursorupdate0(void);

Vctlr FSV = {
	"FSV",			/* name */
	init,			/* init */
	0,			/* page */
	setcolour,		/* setcolor */

	enable,			/* enable cursor fn */
	disable,		/* disable cursor fn */
	move,			/* move cursor fn */
	load,			/* load cursor fn */
	isloaded,		/* is cursor loaded? */
	0,			/* deprecated */

	1024,			/* screen width (x) */
	768,			/* screen height (y) */
	3,			/* depth */

	0,			/* hidecount */
	0,			/* loaded */
};

static int lastx=-1;
static int lasty=-1;

static Vctlr*
init(Vctlr* vctlr, int x, int y, int d)
{
	USED(vctlr,x,y,d);

	return &FSV;
}

static int
setcolour(ulong p, ulong r, ulong g, ulong b)
{
	if(gscreen.ldepth == 0)
		return 0;	/* can't change mono screen colormap */
	else{
		vid->addr = p << 24;
		vid->color = r << 24;
		vid->color = g << 24;
		vid->color = b << 24;
		return 1;
	}
}

static ulong backingstore[64];
static Memdata backingstoredata = {
	nil,
	backingstore
};

static ulong backingnocursor[64];
static Memdata backingnocursordata = {
	nil,
	backingnocursor
};

static ulong backwithcursor[64];
static Memdata backwithcursordata = {
	nil,
	backwithcursor
};

static Memimage backingnocursormem = {
	{0,0,16,16},
	{0,0,16,16},
	3,
	0,
	&backingnocursordata,
	0,
	16/4,
	0,
	0,
};
static Memimage backingmem = {
	{0,0,16,16},
	{0,0,16,16},
	3,
	0,
	&backingstoredata,
	0,
	16/4,
	0,
	0,
};

static void
disable(void)
{
	if(FSV.hidecount++)
		return;
	if(lastx < 0 || lasty < 0)
		return;

	memimagedraw(&gscreen, Rect(lastx,lasty,lastx+16,lasty+16),
		     &backingnocursormem, Pt(0,0), memones, Pt(0,0));
}

static void
enable(void)
{
	uchar *p;
	uchar mask;
	uchar *cset;
	int i;

	if(--FSV.hidecount > 0)
		return;
	FSV.hidecount = 0;

	if(lastx < 0 || lasty < 0)
		return;

	memimagedraw(&backingmem,Rect(0,0,16,16),&gscreen,Pt(lastx,lasty),memones,
		     Pt(0,0));

	memcpy(backingnocursor,backingstore,256);
	p = (uchar*)backingmem.data->data;

	cset = FSV.cursor.set;

	for(i=0;i<32;i++) {
		mask = ~cset[i];

		if(!(mask&(1<<7))) *p = 0xff;
		++p;
		if(!(mask&(1<<6))) *p = 0xff;
		++p;
		if(!(mask&(1<<5))) *p = 0xff;
		++p;
		if(!(mask&(1<<4))) *p = 0xff;
		++p;
		if(!(mask&(1<<3))) *p = 0xff;
		++p;
		if(!(mask&(1<<2))) *p = 0xff;
		++p;
		if(!(mask&(1<<1))) *p = 0xff;
		++p;
		if(!(mask&(1<<0))) *p = 0xff;
		++p;
	}

	memimagedraw(&gscreen,Rect(lastx,lasty,lastx+16,lasty+16),&backingmem,Pt(0,0),
		     memones,Pt(0,0));
}

static void
move(int cx, int cy)
{
	if(!FSV.loaded)
		return;

	disable();
	cursorupdate0();
	lastx = cx;
	lasty = cy;
	enable();
}


static void
load(Cursor *curs)
{
	FSV.cursor = *curs;
	FSV.loaded=1;
}

static int
isloaded(void)
{
	return FSV.loaded;
}
