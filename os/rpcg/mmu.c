#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"

void
mmuinit(void)
{
	/* the l.s initial TLB settings do all that's required */
}

int
segflush(void *a, ulong n)
{
	/* flush dcache then invalidate icache */
	dcflush(a, n);
	icflush(a, n);
	return 0;
}
