#include <u.h>
#include <libc.h>
#include <bio.h>
#include <mach.h>

static	char	*kernelfile = "/power/ipaq";
ulong	crc32(void *buf, int n, ulong crc);

void
main(int argc, char **argv)
{
	int ifd, n;
	char buf[64], reply[1];
	int i, execsize;
	Fhdr f;
	ulong csum;

	ARGBEGIN{
	}ARGEND
	ifd = open(kernelfile, OREAD);
	if(ifd < 0){
		fprint(2, "dload: can't open %s: %r\n", kernelfile);
		exits("open");
	}
	i = 0;
	if(crackhdr(ifd, &f) == 0){
		fprint(2, "dload: not an executable file: %r\n");
		exits("format");
	}
	if(f.magic != Q_MAGIC){
		fprint(2, "dload: not a powerpc executable\n");
		exits("format");
	}
	execsize = f.txtsz + f.datsz + f.txtoff;
	seek(ifd, 0, 0);
	csum = ~0;
	while(execsize > 0 && (n = read(ifd, buf, sizeof(buf))) > 0){
		if(n > execsize)
			n = execsize;
		for(;;){
			if(write(1, buf, sizeof(buf)) != sizeof(buf)){	/* always writes full buffer */
				fprint(2, "dload: write error: %r\n");
				exits("write");
			}
			if(read(0, reply, 1) != 1){
				fprint(2, "dload: bad reply\n");
				exits("read");
			}
			if(reply[0] != 'n')
				break;
			fprint(2, "!");
		}
		if(reply[0] != 'y'){
			fprint(2, "dload: bad ack: %c\n", reply[0]);
			exits("reply");
		}
		if(++i%10 == 0)
			fprint(2, ".");
		execsize -= n;
	}
	exits(0);
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
