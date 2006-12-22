#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "raise.h"
#include "pool.h"
#include "kernel.h"
#include "dynld.h"

Module*
newdyncode(int fd, char *path, Dir *dir)
{
	USED(fd);
	USED(path);
	USED(dir);
	return nil;
}

void
freedyncode(Module *m)
{
	USED(m);
}

void
newdyndata(Modlink *ml)
{
	USED(ml);
}

void
freedyndata(Modlink *ml)
{
	USED(ml);
}

Dynobj*
dynld(int fd)
{
	USED(fd);
	return nil;
}

int
dynldable(int fd)
{
	USED(fd);
	return 0;
}
