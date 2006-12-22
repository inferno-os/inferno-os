#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"

#define	MAXDCR	0x220

#define	DCRF(n)	((((n)>>5)&0x1F)|(((n)&0x1F)<<5))
#define	MTDCR(s,n)	((31<<26)|((s)<<21)|(DCRF(n)<<11)|(451<<1))
#define	MFDCR(n,t)	((31<<26)|((t)<<21)|(DCRF(n)<<11)|(323<<1))
#define	RETURN	0x4e800020
ulong	_getdcr[MAXDCR][2];
ulong	_putdcr[MAXDCR][2];

void
compiledcr(void)
{
	ulong *p;
	int i;

	for(i=0; i<MAXDCR; i++){
		p = _getdcr[i];
		p[0] = MFDCR(i, 3);
		p[1] = RETURN;
		p = _putdcr[i];
		p[0] = MTDCR(3, i);
		p[1] = RETURN;
	}
	dcflush(_getdcr, sizeof(_getdcr));
	dcflush(_putdcr, sizeof(_putdcr));
	/* no need to flush icache since they won't be there */
}
