#include "boot.h"

/*
 * this doesn't yet use the crc
 */

typedef struct Uboot Uboot;
struct Uboot {
	Queue*	iq;
	Block*	partial;
	ulong	csum;
	long	bno;
	uchar	buf[64];
	int	nleft;
	int	ntimeout;
};

static	Uboot	uboot;
ulong	crc32(void *buf, int n, ulong crc);

static void
uartbrecv(uchar *p, int n)
{
	Uboot *ub;
	Block *b;

	ub = &uboot;
	if(n > 0 && ub->iq != nil){
		b = iallocb(n);
		memmove(b->wp, p, n);
		b->wp += n;
		qbwrite(ub->iq, b);
	}
}

int
uartinit(void)
{
	return 1<<0;
}

Partition*
setuartpart(int, char *s)
{
	static Partition pp[1];

	if(strcmp(s, "boot") != 0 && strcmp(s, "disk") != 0)
		return 0;
	pp[0].start = 0;
	pp[0].end = 2*1024*1024;
	strcpy(pp[0].name, "boot");
	return pp;
}

long
uartseek(int, long)
{
	/* start the boot */
	if(uboot.iq == nil)
		uboot.iq = qopen(64*1024, 0, 0, 0);
	if(uboot.partial){
		freeb(uboot.partial);
		uboot.partial = 0;
	}
	print("uart: start transmission\n");
	uartsetboot(uartbrecv);
	uboot.csum = ~0;
	uboot.bno = 0;
	uboot.nleft = 0;
	uboot.ntimeout = 0;
	return 0;
}

static long
uartreadn(void *buf, int nb)
{
	ulong start;
	Uboot *ub;
	int l;
	Block *b;
	uchar *p;

	p = buf;
	ub = &uboot;
	start = m->ticks;
	while(nb > 0){
		b = ub->partial;
		ub->partial = nil;
		if(b == nil){
			ub->ntimeout = 0;
			while((b = qget(ub->iq)) == 0){
				if(TK2MS(m->ticks - start) >= 15*1000){
					if(++ub->ntimeout >= 3){
						print("uart: timeout\n");
						return 0;
					}
					uartputs("n", 1);
				}
			}
		}
		l = BLEN(b);
		if(l > nb)
			l = nb;
		memmove(p, b->rp, l);
		b->rp += l;
		if(b->rp >= b->wp)
			freeb(b);
		else
			ub->partial = b;
		nb -= l;
		p += l;
	}
	return p-(uchar*)buf;
}

long
uartread(int, void *buf, long n)
{
	uchar *p;
	int l;
	static uchar lbuf[64];

	p = buf;
	if((l = uboot.nleft) > 0){
		if(l > n)
			l = n;
		uboot.nleft -= l;
		memmove(p, uboot.buf, l);
		p += l;
		n -= l;
	}
	while(n > 0){
		l = uartreadn(lbuf, sizeof(lbuf));
		if(l < sizeof(lbuf))
			return 0;
		if(l > n){
			uboot.nleft = l-n;
			memmove(uboot.buf, lbuf+n, uboot.nleft);
			l = n;
		}
		memmove(p, lbuf, l);
		n -= l;
		p += l;
		uboot.bno++;
		uartputs("y", 1);
	}
	return p-(uchar*)buf;
}

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
