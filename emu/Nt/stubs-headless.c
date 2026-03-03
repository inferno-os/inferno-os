/* Headless emulator stubs for graphics functions (Windows) */
#include "dat.h"
#include "fns.h"
#include "draw.h"
#include "memdraw.h"
#include "cursor.h"

/* Graphics stubs - do nothing in headless mode */
void setpointer(int x, int y) {
	USED(x);
	USED(y);
}

uchar* attachscreen(Rectangle *r, ulong *chan, int *d, int *width, int *softscreen) {
	USED(r);
	USED(chan);
	USED(d);
	USED(width);
	USED(softscreen);
	return nil;
}

void flushmemscreen(Rectangle r) {
	/* Rectangle is a struct, can't use USED macro on it */
}

void drawcursor(Drawcursor *c) {
	USED(c);
}

char* clipread(void) {
	return nil;
}

int clipwrite(char *buf) {
	USED(buf);
	return 0;
}
