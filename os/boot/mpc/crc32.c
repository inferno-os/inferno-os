#include "boot.h"

/*
 * from Rob Warnock
 */
static	ulong	crc32tab[256];	/* initialised on first call to crc32 */

enum {
	CRC32POLY = 0x04c11db7     /* AUTODIN II, Ethernet, & FDDI */
};

/*
 * Build auxiliary table for parallel byte-at-a-time CRC-32.
 */
static void
initcrc32(void)
{
	int i, j;
	ulong c;

	for(i = 0; i < 256; i++) {
		for(c = i << 24, j = 8; j > 0; j--)
			if(c & (1<<31))
				c = (c<<1) ^ CRC32POLY;
			else
				c <<= 1;
		crc32tab[i] = c;
	}
}

ulong
crc32(void *buf, int n, ulong crc)
{
	uchar *p;

	if(crc32tab[1] == 0)
		initcrc32();
	crc = ~crc;
	for(p = buf; --n >= 0;)
		crc = (crc << 8) ^ crc32tab[(crc >> 24) ^ *p++];
	return ~crc;
}
