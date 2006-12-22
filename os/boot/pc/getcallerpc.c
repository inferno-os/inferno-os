#include "u.h"
#include "lib.h"

ulong
getcallerpc(void *x)
{
	return (((ulong*)(x))[-1]);
}
