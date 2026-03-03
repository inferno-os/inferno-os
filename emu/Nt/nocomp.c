/*
 * Stub JIT compiler for interpreter-only builds.
 * Provides compile() and comvec symbols required by libinterp.
 */
#include "dat.h"
#include "fns.h"
#include "interp.h"

void	(*comvec)(void) = nil;

int
compile(Module *m, int size, Modlink *ml)
{
	USED(m);
	USED(size);
	USED(ml);
	return 0;
}
