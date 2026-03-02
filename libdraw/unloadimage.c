#include "lib9.h"
#include "draw.h"
#include "kernel.h"
#include "interp.h"

int
unloadimage(Image *i, Rectangle r, uchar *data, int ndata)
{
	int bpl, n, ntot, dy;
	uchar *a;
	Display *d;
	int chunk;

	if(!rectinrect(r, i->r)){
		kwerrstr("unloadimage: bad rectangle");
		return -1;
	}
	bpl = bytesperline(r, i->depth);
	if(ndata < bpl*Dy(r)){
		kwerrstr("unloadimage: buffer too small");
		return -1;
	}

	d = i->display;
	flushimage(d, 0);	/* make sure subsequent flush is for us only */

	/*
	 * Response data comes through the data channel (iounit 64KB),
	 * not through bufimage.  Use 64KB as the chunk limit instead of
	 * the old hardcoded 8000 which was the bufimage command buffer
	 * size — irrelevant for read responses.
	 */
	chunk = 64*1024;

	ntot = 0;
	while(r.min.y < r.max.y){
		a = bufimage(d, 1+4+4*4);
		if(a == 0){
			kwerrstr("unloadimage: %r");
			return -1;
		}
		dy = chunk/bpl;
		if(dy <= 0){
			/* Row wider than 64KB — still try one row at a time */
			dy = 1;
		}
		if(dy > Dy(r))
			dy = Dy(r);
		a[0] = 'r';
		BPLONG(a+1, i->id);
		BPLONG(a+5, r.min.x);
		BPLONG(a+9, r.min.y);
		BPLONG(a+13, r.max.x);
		BPLONG(a+17, r.min.y+dy);
		if(flushimage(d, 0) < 0)
			return -1;
		if(d->local == 0)
			release();
		n = kchanio(d->datachan, data+ntot, ndata-ntot, OREAD);
		if(d->local == 0)
			acquire();
		if(n < 0)
			return n;
		ntot += n;
		r.min.y += dy;
	}
	return ntot;
}
