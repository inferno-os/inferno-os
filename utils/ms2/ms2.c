#include <lib9.h>
#include <bio.h>
#include <mach.h>

void	record(uchar*, int);
void	usage(void);
void	dosegment(long, int);
void trailer(ulong);
void header(void);

enum
{
	Recordsize = 32
};

int	dsegonly;
int	supressend;
int	binary;
ulong	addr;
ulong 	psize = 4096;
ulong	startaddr = 0x030000;
Biobuf 	bout;
Biobuf	bio;

void
main(int argc, char **argv)
{
	Dir *dir;
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
	case 'T':
		addr = strtoul(ARGF(), 0, 0);
		break;
	case 'p':
	case 'R':
		psize = strtoul(ARGF(), 0, 0);
		break;
	case 'b':
		binary++;
		break;
	case 'S':
		startaddr = strtoul(ARGF(), 0, 0);
		break;
	default:
		usage();
	}ARGEND

	if(argc != 1)
		usage();

	Binit(&bout, 1, OWRITE);

	fd = open(argv[0], OREAD);
	if(fd < 0) {
		fprint(2, "ms2: open %s: %r\n", argv[0]);
		exits("open");
	}

	if(binary) {
		if((dir = dirfstat(fd)) == nil) {
			fprint(2, "ms2: stat failed %r");
			exits("dirfstat");
		}
		Binit(&bio, fd, OREAD);
		header();
		dosegment(0, dir->length);
		if(supressend == 0)
			trailer(startaddr);
		Bterm(&bout);
		Bterm(&bio);
		free(dir);
		exits(0);
	}

	if(crackhdr(fd, &f) == 0){
		fprint(2, "ms2: bad magic: %r\n");
		exits("magic");
	}
	seek(fd, 0, 0);

	Binit(&bio, fd, OREAD);

	header();
	if(dsegonly)
		dosegment(f.datoff, f.datsz);
	else {
		dosegment(f.txtoff, f.txtsz);
		addr = (addr+(psize-1))&~(psize-1);
		dosegment(f.datoff, f.datsz);
	}

	if(supressend == 0)
		trailer(startaddr);

	Bterm(&bout);
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

	if(addr & (0xFF<<24)){
		Bprint(&bout, "S3%.2X%.8lX", l+5, addr);
		cksum = l+5;
		cksum += (addr>>24)&0xff;
	}else{
		Bprint(&bout, "S2%.2X%.6lX", l+4, addr);
		cksum = l+4;
	}
	cksum += addr&0xff;
	cksum += (addr>>8)&0xff;
	cksum += (addr>>16)&0xff;

	for(i = 0; i < l; i++) {
		cksum += *s;
		Bprint(&bout, "%.2X", *s++);
	}
	Bprint(&bout, "%.2lX\n", (~cksum)&0xff);
	addr += l;
}

void
header(void)
{
	Bprint(&bout, "S0030000FC\n");
}

void
trailer(ulong a)
{
	ulong cksum;

	cksum = 0;
	if(a & (0xFF<<24)){
		Bprint(&bout, "S7%.8lX", a);
		cksum += (a>>24)&0xff;
	}else
		Bprint(&bout, "S9%.6lX", a);
	cksum += a&0xff;
	cksum += (a>>8)&0xff;
	cksum += (a>>16)&0xff;
	Bprint(&bout, "%.2lX\n", (~cksum)&0xff);
}

void
usage(void)
{
	fprint(2, "usage: ms2 [-dsb] [-T address] [-R pagesize] [-S startaddress] ?.out\n");
	exits("usage");
}
