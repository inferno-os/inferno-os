#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"

#include	"../port/flashif.h"

/*
 * Intel 28F320B3B in word mode
 */

#define	I(x)	(x)
enum {
	ReadArray = 0x00FF,
};

#include "../port/flashintel"

static int
reset(Flash *f)
{
	f->id = 0x0089;	/* can't use autoselect: might be running in flash */
	f->devid = 0x8897;
	f->write = intelwrite2;
	f->erasezone = intelerase;
	f->width = 2;
	f->cmask = 0x00FF;
	*(ushort*)f->addr = ClearStatus;
	*(ushort*)f->addr = ReadArray;
	f->nr = 2;
	f->regions[0] = (Flashregion){8, 0, 8*(8*1024), 8*1024, 0};
	f->regions[1] = (Flashregion){63, 64*1024, 4*1024*1024, 64*1024, 0};
	return 0;
}

void
flash28f320b3blink(void)
{
	addflashcard("Intel28F320B3B", reset);
}
