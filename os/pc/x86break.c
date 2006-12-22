#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "ureg.h"
#include "../port/error.h"

//
// from trap.c
//

uchar BREAK = 0xcc;
static ulong skipflags;
extern int (*breakhandler)(Ureg *ur, Proc*);
static Bkpt *skip;
int breakmatch(BkptCond *cond, Ureg *ur, Proc *p);
void breaknotify(Bkpt *b, Proc *p);
void breakrestore(Bkpt *b);
Bkpt* breakclear(int id);

void
skiphandler(Ureg *ur, void*)
{
	if (skip == 0)
		panic("single step outside of skip");

	breakrestore( skip );
	skip = 0;
	ur->flags = skipflags;
	if (up != 0)
		up->state = Running;
}

void
machbreakinit(void)
{
	breakhandler = breakhit;
	trapenable(VectorDBG, skiphandler, nil, "bkpt.skip");
}

Instr
machinstr(ulong addr)
{
	if (addr < KTZERO)
		error(Ebadarg);
	return *(uchar*)addr;
}

void
machbreakset(ulong addr)
{
	if (addr < KTZERO)
		error(Ebadarg);
	*(uchar*)addr = BREAK;
}

void
machbreakclear(ulong addr, Instr i)
{
	if (addr < KTZERO)
		error(Ebadarg);
	*(uchar*)addr = i;
}

//
// Called from the exception handler when a breakpoint instruction has been
// hit.  This cannot not be called unless at least one breakpoint with this
// address is in the list of breakpoints.  (All breakpoint notifications must
// previously have been set via setbreak())
//
//	foreach breakpoint in list
//		if breakpoint matches conditions
//			notify the break handler
//	if no breakpoints matched the conditions
//		pick a random breakpoint set to this address
//
//		set a breakpoint at the next instruction to be executed,
//		and pass the current breakpoint to the "skiphandler"
//
//		clear the current breakpoint
//
//		Tell the scheduler to stop scheduling, so the caller is
//		guaranteed to execute the instruction, followed by the
//		added breakpoint.
//
//

extern Bkpt *breakpoints;


int
breakhit(Ureg *ur, Proc *p)
{
	Bkpt *b;
	int nmatched;

	ur->pc--;

	nmatched = 0;
	for(b = breakpoints; b != nil; b = b->next) {
		if(breakmatch(b->conditions, ur, p)) {
			breaknotify(b, p);
			++nmatched;
		}
	}

	if (nmatched)
		return 1;

	if (skip != nil)
		panic("x86break: non-nil skip in breakhit\n");

	for(b = breakpoints; b != (Bkpt*) nil;  b = b->next) {
		if(b->addr == ur->pc) {
			if(breakclear(b->id) == 0)
				panic("breakhit: breakclear() failed");
			
			skip = b;
			skipflags = ur->flags;
			if (p != 0)
				p->state = Stopped;			/* this should disable scheduling */

			if (ur->flags & (1 << 9)) {		/* mask all interrupts */
				ur->flags &= ~(1<<9);
			}
			ur->flags |= (1 << 8);
		}
	}
	return 1;
}

int
isvalid_va(void*)
{
	return 1;
}
