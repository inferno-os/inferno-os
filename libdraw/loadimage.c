#include "lib9.h"
#include "draw.h"
#include "kernel.h"

int
loadimage(Image *i, Rectangle r, uchar *data, int ndata)
{
	long dy;
	int n, bpl, roff, dstroff, lskip, llen, y;
	uchar *a;
	int chunk;
	Rectangle dstr;

	chunk = i->display->bufsize - 64;

	bpl = bytesperline(r, i->depth);
	n = bpl*Dy(r);
	if(n > ndata){
		kwerrstr("loadimage: insufficient data");
		return -1;
	}

	dstr = r;
	rectclip(&dstr, i->r);
	rectclip(&dstr, i->clipr);

	if (!rectinrect(dstr, i->r))
		return 0;

	roff = (r.min.x*i->depth)>>3;
	dstroff = dstr.min.x * i->depth >> 3;
	lskip = dstroff - roff;
	llen = (dstr.max.x*i->depth + 7 >> 3) - dstroff;
	data += (dstr.min.y - r.min.y) * bpl + lskip;

	ndata = 0;
	while(dstr.max.y > dstr.min.y){
		dy = dstr.max.y - dstr.min.y;
		if(dy*llen > chunk)
			dy = chunk/llen;
		if(dy <= 0){
			kwerrstr("loadimage: image too wide for buffer");
			return -1;
		}
		n = dy*llen;
		a = bufimage(i->display, 21+n);
		if(a == nil){
			kwerrstr("bufimage failed");
			return -1;
		}
		a[0] = 'y';
		BPLONG(a+1, i->id);
		BPLONG(a+5, dstr.min.x);
		BPLONG(a+9, dstr.min.y);
		BPLONG(a+13, dstr.max.x);
		BPLONG(a+17, dstr.min.y+dy);
		a += 21;
		for (y = 0; y < dy; y++) {
			memmove(a, data, llen);
			a += llen;
			ndata += llen;
			data += bpl;
		}
		dstr.min.y += dy;
	}
	if(flushimage(i->display, 0) < 0)
		return -1;
	return ndata;
}

