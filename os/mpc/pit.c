/*
 * programmable interrupt timer
 */

#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"ureg.h"

enum {
	/* piscr */
	PTE =	1<<0,
	PITF =	1<<1,
	PIE =	1<<2,
	PS =	1<<7,
};

static void
pitinterrupt(Ureg*, void*)
{
	IMM *io;

	io = m->iomem;
	if(io->piscr & PS){
		io->piscr |= PS;	/* clear by writing 1 */
		/* do whatever is required */
	}
}

static void
pitreset(void)
{
	IMM *io;

	io = ioplock();
	io->piscrk = KEEP_ALIVE_KEY;
	io->piscr = (PITlevel<<8) | PS | PITF;
	if(0)
		io->piscrk = ~KEEP_ALIVE_KEY;
	/* piscrk is left unlocked for interrupt routine */
	iopunlock();
	intrenable(PITlevel, pitinterrupt, nil, BUSUNKNOWN, "pit");
}

static ulong
pitload(ulong usec)
{
	IMM *io;
	ulong v;

	v = ((usec*m->oscclk)/512);
	if(v == 0 || v >= (1<<16))
		return 0;	/* can't do */
	io = ioplock();
	io->pitck = KEEP_ALIVE_KEY;
	io->pitc = (v-1)<<16;
	io->pitck = ~KEEP_ALIVE_KEY;
	io->piscrk = KEEP_ALIVE_KEY;
	io->piscr = (PITlevel<<8) | PS | PIE | PITF | PTE;
	if(0)
		io->piscrk = ~KEEP_ALIVE_KEY;
	/* piscrk is left unlocked for interrupt routine */
	iopunlock();
	return (v*512)/m->oscclk;
}
