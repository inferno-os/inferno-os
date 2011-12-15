#include "logfsos.h"
#include "logfs.h"
#include "nandfs.h"

static unsigned long row4 = 0x001fffc0;
static unsigned long row3 = 0x0fe03fc0;
static unsigned long row2 = 0x71e3c3c0;
static unsigned long row1 = 0xb66cccc0;
static unsigned long row0 = 0xdab55540;

static char map[] = {
	-5, -4, 0, -3, 1, 2, 3, -2,
	4, 5, 6, 7, 8, 9, 10, -1, 11,
	12, 13, 14, 15, 16, 17, 18,
	19, 20, 21, 22, 23, 24, 25,
};

#define mashbits(rown) \
	c = (in) & (rown); \
	c ^= c >> 16; \
	c ^= c >> 8; \
	c ^= c >> 4; \
	c ^= c >> 2; \
	c = (c ^ (c >> 1)) & 1; \

static uchar
_nandfshamming31_26calcparity(ulong in)
{
	ulong c;
	uchar out;
	mashbits(row4); out = c;
	mashbits(row3); out = (out << 1) | c;
	mashbits(row2); out = (out << 1) | c;
	mashbits(row1); out = (out << 1) | c;
	mashbits(row0); out = (out << 1) | c;
	return out;
}

ulong
_nandfshamming31_26calc(ulong in)
{
	in &= 0xffffffc0;
	return in | _nandfshamming31_26calcparity(in);
}

int
_nandfshamming31_26correct(ulong *in)
{
	uchar eparity, parity;
	ulong e;
	eparity = _nandfshamming31_26calcparity(*in);
	parity = (*in) & 0x1f;
	e = eparity ^ parity;
	if (e == 0)
		return 0;
	e--;
	if (map[e] < 0)
		return 1;		// error in parity bits
	e = map[e];
	*in ^= 1 << (31 - e);
	return 1;
}
