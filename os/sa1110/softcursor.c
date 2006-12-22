#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "../port/error.h"
#include "io.h"

#include <draw.h>
#include <memdraw.h>
#include <cursor.h>

#include "gscreen.h"

/*
 * Software cursor code: done by hand, might be better to use memimagedraw
 * but that would need to be done by a process
 */
 
typedef struct Cursordata Cursordata;
struct Cursordata {
	Physdisplay	*vd;
	ulong	*fb;	/* screen frame buffer */
	Rectangle r;
	int	depth;	/* depth of screen */
	int 	width;	/* width of screen in ulongs */
	int	x;
	int	y;
	int	hotx;
	int	hoty;
	int	cbwid;	/* cursor byte width */
	int	f;	/* flags */
	int	dx;
	int	dy;
	int	hidecount;
	uchar	data[CURSWID*CURSHGT];
	uchar	mask[CURSWID*CURSHGT];
	uchar	save[CURSWID*CURSHGT];
};

static Cursordata *cd = nil;

enum {
	Enabled = 0x01,		/* cursor is enabled */
	Drawn = 0x02,		/* cursor is currently drawn */
	Bitswap = 0x10,
};

static Rectangle cursoroffrect;
static int	cursorisoff;

static void swcursorflush(Point);
static void	swcurs_draw_or_undraw(Cursordata *);

static void
cursorupdate0(void)
{
	int inrect, x, y;
	Point m;

	m = mousexy();
	x = m.x - cd->hotx;
	y = m.y - cd->hoty;
	inrect = (x >= cursoroffrect.min.x && x < cursoroffrect.max.x
		&& y >= cursoroffrect.min.y && y < cursoroffrect.max.y);
	if (cursorisoff == inrect)
		return;
	cursorisoff = inrect;
	if (inrect)
		swcurs_hide(swc);
	else {
		cd->hidecount = 0;
		swcurs_draw_or_undraw(swc);
	}
	swcursorflush(m);
}

void
cursorupdate(Rectangle r)
{
	lock(vd);
	r.min.x -= 16;
	r.min.y -= 16;
	cursoroffrect = r;
	if (vd->cursor != nil)
		cursorupdate0();
	unlock(vd);
}

void
cursorenable(void)
{
	lock(vd);
	if(vd->cursor != nil)
		vd->cursor->enable(swc);
//		swcursorflush(mousexy());
	unlock(vd);
}

void
cursordisable(void)
{

	lock(vd);
	if(swc != nil) {
		swcurs_disable(swc);
		swcursorflush(mousexy());
	}
	unlock(vd);
}

static void
swcursupdate(int oldx, int oldy, int x, int y)
{

	if(!canlock(vd))
		return;		/* if can't lock, don't wake up stuff */

	if(x < gscreen->r.min.x)
		x = gscreen->r.min.x;
	if(x >= gscreen->r.max.x)
		x = gscreen->r.max.x;
	if(y < gscreen->r.min.y)
		y = gscreen->r.min.y;
	if(y >= gscreen->r.max.y)
		y = gscreen->r.max.y;
	if(swc != nil) {
		swcurs_hide(swc);
		cd->x = x;
		cd->y = y;
		cursorupdate0();
		swcurs_unhide(swc);
		swcursorflush(oldx, oldy);
		swcursorflush(x, y);
	}

	unlock(vd);
}

void
drawcursor(Drawcursor* c)
{
	Point p;
	Cursor curs, *cp;
	int j, i, h, bpl;
	uchar *bc, *bs, *cclr, *cset;

	if(swc == nil)
		return;

	/* Set the default system cursor */
	if(c == nil || c->data == nil){
		swcurs_disable(swc);
		return;
	}
	else {
		cp = &curs;
		p.x = c->hotx;
		p.y = c->hoty;
		cp->offset = p;
		bpl = bytesperline(Rect(c->minx, c->miny, c->maxx, c->maxy), 1);

		h = (c->maxy-c->miny)/2;
		if(h > 16)
			h = 16;

		bc = c->data;
		bs = c->data + h*bpl;

		cclr = cp->clr;
		cset = cp->set;
		for(i = 0; i < h; i++) {
			for(j = 0; j < 2; j++) {
				cclr[j] = bc[j];
				cset[j] = bs[j];
			}
			bc += bpl;
			bs += bpl;
			cclr += 2;
			cset += 2;
		}
	}
	swcurs_load(swc, cp);
	swcursorflush(mousexy());
	swcurs_enable(swc);
}

void*
create(Physdisplay *vd)
{
	Cursordata *cd;

	swc = (Cursordata*)malloc(sizeof(Cursordata));
	cd->vd = vd;
	cd->fb = vd->gscreen->data->bdata;	/* or vd->fb? */
	cd->r = vd->gscreen->r;
	cd->d = vd->gscreen->depth;
	cd->width = vd->gscreen->width;
//	cd->f = bitswap ? Bitswap : 0;
	cd->f = Bitswap;	/* ??? */
	cd->x = cd->y = 0;
	cd->hotx = cd->hoty = 0;
	cd->hidecount = 0;
	return cd;
}

void
swcurs_destroy(Cursordata *cd)
{
	swcurs_disable(cd);
	free(cd);
}

static void
swcursorflush(Point p)
{
	Rectangle r;

	/* XXX a little too paranoid here */
	r.min.x = p.x-16;
	r.min.y = p.y-16;
	r.max.x = p.x+17;
	r.max.y = p.y+17;
	flushmemscreen(r);
}

static void
swcurs_draw_or_undraw(Cursordata *cd)
{
	uchar *p;
	uchar *cs;
	int w, vw;
	int x1 = cd->r.min.x;
	int y1 = cd->r.min.y;
	int x2 = cd->r.max.x;
	int y2 = cd->r.max.y; 
	int xp = cd->x - cd->hotx;
	int yp = cd->y - cd->hoty;
	int ofs;

	if(((cd->f & Enabled) && (cd->hidecount <= 0))
			 == ((cd->f & Drawn) != 0))
		return;
	w = cd->cbwid*BI2BY/cd->depth;
	x1 = xp < x1 ? x1 : xp;
	y1 = yp < y1 ? y1 : yp;
	x2 = xp+w >= x2 ? x2 : xp+w;
	y2 = yp+cd->dy >= y2 ? y2 : yp+cd->dy;
	if(x2 <= x1 || y2 <= y1)
		return;
	p = (uchar*)(cd->fb + cd->width*y1) + x1*(1 << cd->d)/BI2BY;
	y2 -= y1;
	x2 = (x2-x1)*cd->depth/BI2BY;
	vw = cd->width*BY2WD - x2;
	w = cd->cbwid - x2;
	ofs = cd->cbwid*(y1-yp)+(x1-xp);
	cs = cd->save + ofs;
	if((cd->f ^= Drawn) & Drawn) {
		uchar *cm = cd->mask + ofs; 
		uchar *cd = cd->data + ofs;
		while(y2--) {
			x1 = x2;
			while(x1--) {
				*cs++ = *p;
				*p = (*p & *cm++) ^ *cd++;
				p++;
			}
			cs += w;
			cm += w;
			cd += w;
			p += vw;
		}
	} else {
		while(--y2 >= 0){
			for(x1 = x2; --x1 >= 0;)
				*p++ = *cs++;
			cs += w;
			p += vw;
		}
	}
}

static void
swcurs_hide(Cursordata *cd)
{
	++cd->hidecount;
	swcurs_draw_or_undraw(swc);
}

static void
swcurs_unhide(Cursordata *cd)
{
	if (--cd->hidecount < 0)
		cd->hidecount = 0;
	swcurs_draw_or_undraw(swc);
}

static void
swcurs_enable(Cursordata *cd)
{
	cd->f |= Enabled;
	swcurs_draw_or_undraw(swc);
}

void
swcurs_disable(Cursordata *cd)
{
	cd->f &= ~Enabled;
	swcurs_draw_or_undraw(swc);
}

static void
load(Cursordata *cd, Cursor *c)
{
	int i, k;
	uchar *bc, *bs, *cd, *cm;
	static uchar bdv[4] = {0,Backgnd,Foregnd,0xff};
	static uchar bmv[4] = {0xff,0,0,0xff};
	int bits = 1<<cd->depth;
	uchar mask = (1<<bits)-1;
	int bswp = (cd->f&Bitswap) ? 8-bits : 0;

	bc = c->clr;
	bs = c->set;

	swcurs_hide(swc);
	cd = cd->data;
	cm = cd->mask;
	cd->hotx = c->offset.x;
	cd->hoty = c->offset.y;
	cd->dy = CURSHGT;
	cd->dx = CURSWID;
	cd->cbwid = CURSWID*(1<<cd->d)/BI2BY;
	for(i = 0; i < CURSWID/BI2BY*CURSHGT; i++) {
		uchar bcb = *bc++;
		uchar bsb = *bs++;
		for(k=0; k<BI2BY;) {
			uchar cdv = 0;
			uchar cmv = 0;
			int z;
			for(z=0; z<BI2BY; z += bits) {
				int n = ((bsb&(0x80))|((bcb&(0x80))<<1))>>7;
				int s = z^bswp;
				cdv |= (bdv[n]&mask) << s;
				cmv |= (bmv[n]&mask) << s;
				bcb <<= 1;
				bsb <<= 1;
				k++;
			}
			*cd++ = cdv;
			*cm++ = cmv;
		}
	}
	swcurs_unhide(swc);
}

Physcursor softcursor = {
	.name = "softcursor",
	.create = create,
	.enable = swenable,
	.disable = swdisable,
	.load = load,
	.move = move,
	.destroy = destroy,
};
