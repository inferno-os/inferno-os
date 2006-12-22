#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"ureg.h"
#include	"io.h"

enum
{
	MC_IFETCH	= (1<<30),
	MC_STORE	= (1<<11),	/* bit 23 if X-form, bit 3 if D-form => write */
	DSI_STORE	= (1<<25),
	DSI_PROT		= (1<<27),
};

void
faultpower(Ureg *ur)
{
	ulong addr;
	char buf[ERRMAX];
	int read, i;

	addr = ur->pc;			/* assume instr. exception */
	read = 1;
	i = ur->cause >> 8;
	if(i == CDSI || i == CDTLBE || i == CMCHECK && (ur->status&MC_IFETCH) == 0) {	/* data access error including machine check load/store */
		addr = getdar();
		if(getdsisr() & (DSI_STORE|MC_STORE))
			read = 0;
	} else if(i == CDMISS)	/* DTLB miss */
		addr = getdepn() & ~0x3FF;	/* can't distinguish read/write, but Inferno doesn't care */
/*
print("fault %lux %lux %lux %d\n", ur->pc, ur->cause, addr, read);
print("imiss %lux dmiss %lux hash1 %lux dcmp %lux hash2 %lux\n",
	getimiss(), getdmiss(), gethash1(), getdcmp(), gethash2());
print("up %lux %lux %lux\n", m->upage, m->upage->virt, m->upage->phys);
*/

	up->dbgreg = ur;		/* For remote ACID */

	spllo();
	sprint(buf, "trap: fault %s pc=0x%lux addr=0x%lux",
			read ? "read" : "write", ur->pc, addr);
	if(up->type == Interp)
		disfault(ur, buf);
	dumpregs(ur);
	panic("fault: %s\n", buf);
}
