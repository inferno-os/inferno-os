#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	"../port/netif.h"


void
hnputv(void *p, vlong v)
{
	uchar *a;

	a = p;
	hnputl(a, v>>32);
	hnputl(a+4, v);
}

void
hnputl(void *p, ulong v)
{
	uchar *a;

	a = p;
	a[0] = v>>24;
	a[1] = v>>16;
	a[2] = v>>8;
	a[3] = v;
}

void
hnputs(void *p, ushort v)
{
	uchar *a;

	a = p;
	a[0] = v>>8;
	a[1] = v;
}

vlong
nhgetv(void *p)
{
	uchar *a;

	a = p;
	return ((vlong)nhgetl(a) << 32) | nhgetl(a+4);
}

ulong
nhgetl(void *p)
{
	uchar *a;

	a = p;
	return (a[0]<<24)|(a[1]<<16)|(a[2]<<8)|(a[3]<<0);
}

ushort
nhgets(void *p)
{
	uchar *a;

	a = p;
	return (a[0]<<8)|(a[1]<<0);
}
