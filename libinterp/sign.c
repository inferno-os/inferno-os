#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include <kernel.h>

/*
 * these stubs are used when devsign isn't configured
 */

int
verifysigner(uchar *sign, int len, uchar *data, ulong ndata)
{
	USED(sign);
	USED(len);
	USED(data);
	USED(ndata);

	return 1;
}

int
mustbesigned(char *path, uchar *code, ulong length, Dir *dir)
{
	USED(path);
	USED(code);
	USED(length);
	USED(dir);
	return 0;
}
