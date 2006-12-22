/*
 * use this when devenv.c not used
 */
#include "u.h"
#include "../port/lib.h"
#include "../port/error.h"
#include "mem.h"
#include	"dat.h"
#include	"fns.h"

/*
 * null kernel interface
 */
Egrp*
newegrp(void)
{
	return nil;
}

void
closeegrp(Egrp*)
{
}

void
egrpcpy(Egrp*, Egrp*)
{
}

void
ksetenv(char*, char*, int)
{
}
