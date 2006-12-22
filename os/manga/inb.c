#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "../port/error.h"

#define	KIOP(port)	KADDR(PHYSPCIIO+(port))

int
inb(ulong p)
{
	return *(uchar*)KIOP(p);
}

int
ins(ulong p)
{
	return *(ushort*)KIOP(p);
}

ulong
inl(ulong p)
{
	return *(ulong*)KIOP(p);
}

void
outb(ulong p, int v)
{
	*(uchar*)KIOP(p) = v;
}

void
outs(ulong p, int v)
{
	*(ushort*)KIOP(p) = v;
}

void
outl(ulong p, ulong v)
{
	*(ulong*)KIOP(p) = v;
}

void
inss(ulong p, void* buf, int ns)
{
	ushort *addr;

	addr = (ushort*)buf;
	for(;ns > 0; ns--)
		*addr++ = *(ushort*)KIOP(p);
}

void
outss(ulong p, void* buf, int ns)
{
	ushort *addr;

	addr = (ushort*)buf;
	for(;ns > 0; ns--)
		*(ushort*)KIOP(p) = *addr++;
}

void
insb(ulong p, void* buf, int ns)
{
	uchar *addr;

	addr = (uchar*)buf;
	for(;ns > 0; ns--)
		*addr++ = *(uchar*)KIOP(p);
}

void
outsb(ulong p, void* buf, int ns)
{
	uchar *addr;

	addr = (uchar*)buf;
	for(;ns > 0; ns--)
		*(uchar*)KIOP(p) = *addr++;
}
