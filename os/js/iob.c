#include "u.h"

void
outb(ulong addr, uchar val)
{
	*(uchar*)addr = val;
}

uchar
inb(ulong addr)
{
	return *(uchar*)addr;
}
