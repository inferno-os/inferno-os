#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"

/*
 * Host Communication buffer rings
 */

/*
 * initialise receive and transmit buffer rings
 *
 * the ring entries must be uncached
 */

BD*
bdalloc(ulong nd)
{
	BD *b;

	b = xspanalloc(nd*sizeof(*b), CACHELINESZ, 0);
	if(b == nil)
		panic("bdalloc");
	return mmucacheinhib(b, nd*sizeof(*b));
}

int
ioringinit(Ring* r, int nrdre, int ntdre)
{
	int i;

	r->nrdre = nrdre;
	if(r->rdr == nil)
		r->rdr = bdalloc(nrdre);
	if(r->rxb == nil)
		r->rxb = malloc(nrdre*sizeof(Block*));
	if(r->rdr == nil || r->rxb == nil)
		return -1;
	for(i = 0; i < nrdre; i++){
		r->rxb[i] = nil;
		r->rdr[i].ctrl = 0;
		r->rdr[i].size = 0;
		r->rdr[i].addr = 0;
		if(i)
			r->rdr[i-1].next = PADDR(&r->rdr[i]);
	}
	r->rdr[i-1].next = PADDR(&r->rdr[0]);
	r->rdrx = 0;

	r->ntdre = ntdre;
	if(r->tdr == nil)
		r->tdr = bdalloc(ntdre);
	if(r->txb == nil)
		r->txb = malloc(ntdre*sizeof(Block*));
	if(r->tdr == nil || r->txb == nil)
		return -1;
	for(i = 0; i < ntdre; i++){
		r->txb[i] = nil;
		r->tdr[i].ctrl = 0;
		r->tdr[i].size = 0;
		r->tdr[i].addr = 0;
		if(i)
			r->tdr[i-1].next = PADDR(&r->tdr[i]);
	}
	r->tdr[i-1].next = PADDR(&r->tdr[0]);
	r->tdrh = 0;
	r->tdri = 0;
	r->ntq = 0;
	return 0;
}
