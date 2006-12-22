#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"

/*
 * initialise the keyboard Queue if uartinstall hasn't already done so
 */
void
kbdinit(void)
{
	if(kbdq == nil){
		kbdq = qopen(4*1024, 0, 0, 0);
		qnoblock(kbdq, 1);
	}
	archkbdinit();
}
