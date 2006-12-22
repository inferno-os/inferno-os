#include "u.h"
#include "../port/lib.h"
#include "../port/error.h"
#include "mem.h"
#include	"dat.h"
#include	"fns.h"
#include	<a.out.h>
#include	<dynld.h>

/*
 * null kernel interface to dynld, to stop libinterp moaning
 */

void*
dynimport(Dynobj*, char*, ulong)
{
	return nil;
}

void
dynobjfree(Dynobj*)
{
}

Dynobj*
kdynloadfd(int fd, Dynsym *tab, int ntab)
{
	USED(fd, tab, ntab);
	return nil;
}

int
kdynloadable(int)
{
	return 0;
}

Dynobj*
dynld(int)
{
	return nil;
}

int
dynldable(int)
{
	return 0;
}
