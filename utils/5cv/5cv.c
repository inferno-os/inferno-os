#include <lib9.h>
#include <bio.h>
#include <mach.h>

char *Cmd;
int Hdrtype;
int Strip;
long Txtaddr = -1;

int Ofd;
int Ifd;
Fhdr Ihdr;

int Debug;

static void	get_file(char *);
static void	put_file(char *);
static void	Usage(char *);
static long	strxtol(char *);

char	*fail	= "error";

void
main(int argc, char	*argv[])
{
	char *ifile, *ofile;

	Cmd = argv[0];
	Hdrtype = 2;

	ARGBEGIN {
	/*
	 * Options without args
	 */
	case 's':
		Strip = 1;
		break;
	/*
	 * Options with args
	 */
	case 'T':
		Txtaddr = strxtol(ARGF());
		break;
	case 'H':
		Hdrtype = strxtol(ARGF());
		break;
	case 'D':
		Debug |= strxtol(ARGF());
		break;
	default:
		Usage("Invalid option");
	} ARGEND

	if (argc != 2)
		Usage("Wrong number of arguments");

	ifile = argv[0];
	ofile = argv[1];

	get_file(ifile);
	put_file(ofile);
	exits(0);
}

char usagemsg[] =
"Usage: %s  options infile outfile\n\t options (for outfile): -H[123456] -s -T<text> \n";

static void
Usage(char *msg)
{
	fprint(2, "***Error: %s\n", msg);
	fprint(2, usagemsg, Cmd);
	exits("usage");
}

static long
strxtol(char *s)
{
	char *es;
	int base = 0;
	long r;

	if (*s == '0')
		if (*++s == 'x'){
			base = 16;
			s++;
		}
		else
			base = 8;
	r = strtol(s, &es, base);
	if (*es)
		Usage("bad number");
	return(r);
}

static void
get_file(char *ifile)
{
	int h;
	int d;

	Ifd = open(ifile, OREAD);
	if (Ifd < 0) {
		fprint(2, "5cv: open %s: %r\n", ifile);
		exits("open");
	}
	h = crackhdr(Ifd, &Ihdr);
	if (!h || Debug){
		fprint(2, "Crackhdr: %d, type: %d, name: %s\n", h, Ihdr.type, Ihdr.name);
		fprint(2, "txt %llux, ent %llux, txtsz %lux, dataddr %llux\n",
			Ihdr.txtaddr, Ihdr.entry, Ihdr.txtsz, Ihdr.dataddr);
	}
	if (!h)
		Usage("File type not recognized");
	machbytype(Ihdr.type);
	if (Debug)
		fprint(2, "name: <%s> pgsize:%ux\n", mach->name, mach->pgsize);

	if (Txtaddr != -1){
		d = Txtaddr - Ihdr.txtaddr;
		Ihdr.txtaddr += d;
		Ihdr.dataddr = Ihdr.txtaddr + Ihdr.txtsz;
	}
}

char Wbuf[128];
char *wp = Wbuf;

void
lput(long l)
{
	wp[0] = l>>24;
	wp[1] = l>>16;
	wp[2] = l>>8;
	wp[3] = l;
	wp += 4;
}

void
lputl(long l)
{
	wp[3] = l>>24;
	wp[2] = l>>16;
	wp[1] = l>>8;
	wp[0] = l;
	wp += 4;
}

static void
copyseg(long sz)
{
	char	buf[1024];

	while (sz > 0){
		long n;
		long r;

		n = sz;
		if (n > sizeof buf)
			n = sizeof buf;
		sz -= n;

		if ((r = read(Ifd, buf, n)) != n){
			fprint(2, "%ld = read(...%ld) at %ld\n", r, n, (long)seek(Ifd, 0, 1));
			perror("Premature eof");
			exits(fail);
		}
		if ((r = write(Ofd, buf, n)) != n){
			fprint(2, "%ld = write(...%ld)\n", r, n);
			perror("Write error!");
			exits(fail);
		}
	}
}

static void
zero(long sz)
{
	char	buf[1024];

	memset(buf, 0, sizeof buf);
	while (sz > 0){
		long n;
		long r;

		n = sz;
		if (n > sizeof buf)
			n = sizeof buf;
		sz -= n;

		if ((r = write(Ofd, buf, n)) != n){
			fprint(2, "%ld = write(...%ld)\n", r, n);
			perror("Write error!");
			exits(fail);
		}
	}
}

static long
rnd(long v, long r)
{
	long c;

	if(r <= 0)
		return v;
	v += r - 1;
	c = v % r;
	if(c < 0)
		c += r;
	v -= c;
	return v;
}

static void
put_file(char *ofile)
{
	int ii;
	long doff;
	long dsize;
	long hlen;
	long pad;

	Ofd = create(ofile, OWRITE, 0666);
	if (Ofd < 0) {
		fprint(2, "5cv: create %s: %r\n", ofile);
		exits("create");
	}

	pad = 0;

	switch(Hdrtype) {
	case 1:	/* aif for risc os */
		Strip = 1;
		hlen = 128;
		lputl(0xe1a00000);		/* NOP - decompress code */
		lputl(0xe1a00000);		/* NOP - relocation code */
		lputl(0xeb000000 + 12);		/* BL - zero init code */
		lputl(0xeb000000 +
			(Ihdr.entry
			 - Ihdr.txtaddr
			 + hlen
			 - 12
			 - 8) / 4);		/* BL - entry code */

		lputl(0xef000011);		/* SWI - exit code */
		doff = Ihdr.txtsz+hlen;
		lputl(doff);			/* text size */
		dsize = Ihdr.datsz;
		lputl(dsize);			/* data size */
		lputl(0);			/* sym size */

		lputl(Ihdr.bsssz);		/* bss size */
		lputl(0);			/* sym type */
		lputl(Ihdr.txtaddr-hlen);	/* text addr */
		lputl(0);			/* workspace - ignored */

		lputl(32);			/* addr mode / data addr flag */
		lputl(0);			/* data addr */
		for(ii=0; ii<2; ii++)
			lputl(0);		/* reserved */

		for(ii=0; ii<15; ii++)
			lputl(0xe1a00000);	/* NOP - zero init code */
		lputl(0xe1a0f00e);		/* B (R14) - zero init return */
		break;

	case 2:	/* plan 9 */
		hlen = 32;
		doff = hlen + Ihdr.txtsz;
		dsize = Ihdr.datsz;
		lput(0x647);			/* magic */
		lput(Ihdr.txtsz);		/* sizes */
		lput(Ihdr.datsz);
		lput(Ihdr.bsssz);
		if (Strip)			/* nsyms */
			lput(0);
		else
			lput(Ihdr.symsz);
		lput(Ihdr.entry);		/* va of entry */
		lput(0L);
		lput(Ihdr.lnpcsz);
		break;

	case 3:	/* boot for NetBSD */
		hlen = 32;
		doff = rnd(hlen+Ihdr.txtsz, 4096);
		dsize = rnd(Ihdr.datsz, 4096);
		lput((143<<16)|0413);		/* magic */
		lputl(doff);
		lputl(dsize);
		lputl(Ihdr.bsssz);
		if (Strip)			/* nsyms */
			lputl(0);
		else
			lputl(Ihdr.symsz);
		lputl(Ihdr.entry);		/* va of entry */
		lputl(0L);
		lputl(0L);
		break;
	case 4:	/* no header, stripped, padded to 2K, for serial bootstrap */
		hlen = 0;
		Strip = 1;
		doff = hlen + Ihdr.txtsz;
		dsize = Ihdr.datsz;
		pad = 2048;
		break;
	case 5:	/* no header, stripped, for all sorts */
		hlen = 0;
		Strip = 1;
		doff = hlen + Ihdr.txtsz;
		dsize = Ihdr.datsz;
		break;
	case 6:	/* fake EPOC IMG format header */
		hlen = 256;
		*wp++ = 'E';
		*wp++ = 'P';
		Strip = 1;
		doff = hlen + Ihdr.txtsz;
		dsize = Ihdr.datsz;
		break;
	default:
		Usage("Bad -Htype");
		return;
	}
	write(Ofd, Wbuf, hlen);

	seek(Ifd, Ihdr.txtoff, 0);
	copyseg(Ihdr.txtsz);

	seek(Ifd, Ihdr.datoff, 0);
	seek(Ofd, doff, 0);
	copyseg(Ihdr.datsz);

	if (!Strip) {
		/* Write symbols */
		seek(Ofd, doff + dsize, 0);
		if (Ihdr.symsz){
			seek(Ifd, Ihdr.symoff, 0);
			copyseg(Ihdr.symsz);
		}
		if (Hdrtype == 2)
			copyseg(Ihdr.lnpcsz);
	}

	if (pad) {
		if (doff + Ihdr.datsz > pad) {
			perror("Too big!");
			exits(fail);
		}
		else if (doff + Ihdr.datsz < pad)
			zero(pad - (doff + Ihdr.datsz));
	}
}
