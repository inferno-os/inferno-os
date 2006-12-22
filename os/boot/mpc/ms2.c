#include <u.h>
#include <libc.h>
#include <bio.h>
#include <mach.h>

void	record(uchar*, int);
void	usage(void);
void	dosegment(long, int);
void trailer(ulong);

enum
{
	Recordsize = 32,
};

int	dsegonly;
int	supressend;
int	binary;
int	addr4;
ulong	addr;
ulong 	psize = 4096;
ulong	startaddr = 0x030000;
Biobuf 	stdout;
Biobuf	bio;

void
main(int argc, char **argv)
{
	Dir dir;
	Fhdr f;
	int fd;

	ARGBEGIN{
	case 'd':
		dsegonly++;
		break;
	case 's':
		supressend++;
		break;
	case 'a':
		addr = strtoul(ARGF(), 0, 0);
		break;
	case 'p':
		psize = strtoul(ARGF(), 0, 0);
		break;
	case 'b':
		binary++;
		break;
	case 'S':
		startaddr = strtoul(ARGF(), 0, 0);
		break;
	case '4':
		addr4++;
		break;
	default:
		usage();
	}ARGEND

	if(argc != 1)
		usage();

	Binit(&stdout, 1, OWRITE);

	fd = open(argv[0], OREAD);
	if(fd < 0) {
		fprint(2, "ms2: open %s: %r\n", argv[0]);
		exits("open");
	}

	if(binary) {
		if(dirfstat(fd, &dir) < 0) {
			fprint(2, "ms2: stat failed %r");
			exits("dirfstat");
		}
		Binit(&bio, fd, OREAD);
		dosegment(0, dir.length);
		if(supressend == 0)
			trailer(startaddr);
		Bterm(&stdout);
		Bterm(&bio);
		exits(0);
	}

	if(crackhdr(fd, &f) == 0){
		fprint(2, "ms2: bad magic: %r\n");
		exits("magic");
	}
	seek(fd, 0, 0);

	Binit(&bio, fd, OREAD);

	if(dsegonly)
		dosegment(f.datoff, f.datsz);
	else {
		dosegment(f.txtoff, f.txtsz);
		addr = (addr+(psize-1))&~(psize-1);
		dosegment(f.datoff, f.datsz);
	}

	if(supressend == 0)
		trailer(startaddr);

	Bterm(&stdout);
	Bterm(&bio);
	exits(0);
}

void
dosegment(long foff, int len)
{
	int l, n;
	uchar buf[2*Recordsize];

	Bseek(&bio, foff, 0);
	for(;;) {
		l = len;
		if(l > Recordsize)
			l = Recordsize;
		n = Bread(&bio, buf, l);
		if(n == 0)
			break;
		if(n < 0) {
			fprint(2, "ms2: read error: %r\n");
			exits("read");
		}
		record(buf, l);
		len -= l;
	}
}

void
record(uchar *s, int l)
{
	int i;
	ulong cksum;

	if(addr4 || addr & (0xFF<<24)){
		Bprint(&stdout, "S3%.2X%.8luX", l+5, addr);
		cksum = l+5;
		cksum += (addr>>24)&0xff;
	}else{
		Bprint(&stdout, "S2%.2X%.6X", l+4, addr);
		cksum = l+4;
	}
	cksum += addr&0xff;
	cksum += (addr>>8)&0xff;
	cksum += (addr>>16)&0xff;

	for(i = 0; i < l; i++) {
		cksum += *s;
		Bprint(&stdout, "%.2X", *s++);
	}
	Bprint(&stdout, "%.2X\n", (~cksum)&0xff);
	addr += l;
}

void
trailer(ulong a)
{
	ulong cksum;

	cksum = 0;
	if(addr4 || a & (0xFF<<24)){
		Bprint(&stdout, "S7%.8luX", a);
		cksum += (a>>24)&0xff;
	}else
		Bprint(&stdout, "S9%.6X", a);
	cksum += a&0xff;
	cksum += (a>>8)&0xff;
	cksum += (a>>16)&0xff;
	Bprint(&stdout, "%.2X\n", (~cksum)&0xff);
}

void
usage(void)
{
	fprint(2, "usage: ms2 [-ds] [-a address] [-p pagesize] ?.out\n");
	exits("usage");
}
