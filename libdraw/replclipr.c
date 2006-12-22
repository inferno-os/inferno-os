#include "lib9.h"
#include "draw.h"

void
replclipr(Image *i, int repl, Rectangle clipr)
{
	uchar *b;

	b = bufimage(i->display, 22);
	if (b == 0) {
		_drawprint(2, "replclipr: no bufimage\n");
		return;
	}
	b[0] = 'c';
	BPLONG(b+1, i->id);
	repl = repl!=0;
	b[5] = repl;
	BPLONG(b+6, clipr.min.x);
	BPLONG(b+10, clipr.min.y);
	BPLONG(b+14, clipr.max.x);
	BPLONG(b+18, clipr.max.y);
	i->repl = repl;
	i->clipr = clipr;
}
