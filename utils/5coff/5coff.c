#include	"auxi.h"

#define RND(x, y)	((((x)+(y)-1)/(y))*(y))

char *cmd;
int sflag, dflag;

int ifd, ofd;
Fhdr ihdr;

long	HEADR, INITTEXT, INITDAT, INITRND, INITENTRY;
long textsize, datsize, bsssize;

int cout;
int thumb;

static void	get_file(char *);
static void	put_file(char *);
static void	usage(char *);
static long	strxtol(char *);
static void	readsyms(void);

char	*fail	= "error";

void
main(int argc, char	*argv[])
{
	char *a, *ifile, *ofile;

	cmd = argv[0];

	INITTEXT = -1;
	INITDAT = -1;
	INITRND = -1;
	INITENTRY = -1;

	ARGBEGIN {
	/*
	 * Options without args
	 */
	case 's':
		sflag = 1;
		break;
	/*
	 * Options with args
	 */
	case 'T':
		a = ARGF();
		if(a)
			INITTEXT = strxtol(a);
		break;
	case 'D':
		a = ARGF();
		if(a)
			INITDAT = strxtol(a);
		break;
	case 'R':
		a = ARGF();
		if(a)
			INITRND = strxtol(a);
		break;
	case 'E':
		a = ARGF();
		if(a)
			INITENTRY = strxtol(a);
		break;
	case 'd':
		dflag |= strxtol(ARGF());
		break;
	default:
		usage("Invalid option");
	} ARGEND

	if (argc != 2)
		usage("Wrong number of arguments");

	ifile = argv[0];
	ofile = argv[1];

	get_file(ifile);
	put_file(ofile);
	exits(0);
}

char usagemsg[] =
"usage: %s  options infile outfile\n\t options (for outfile): -H[1234] -s -T<text> -D<data> -R<rnd> -E<entry>\n";

static void
usage(char *msg)
{
	fprint(2, "***Error: %s\n", msg);
	fprint(2, usagemsg, cmd);
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
		usage("bad number");
	return(r);
}

static void
get_file(char *ifile)
{
	int h;

	ifd = open(ifile, OREAD);
	if (ifd < 0) {
		fprint(2, "5coff: open %s: %r\n", ifile);
		exits("open");
	}
	h = crackhdr(ifd, &ihdr);
	if (!h || dflag){
		fprint(2, "Crackhdr: %d, type: %d, name: %s\n", h, ihdr.type, ihdr.name);
		fprint(2, "txt %llux, ent %llux, txtsz %lux, dataddr %llux\n",
			ihdr.txtaddr, ihdr.entry, ihdr.txtsz, ihdr.dataddr);
	}
	if (!h)
		usage("File type not recognized");
	machbytype(ihdr.type);
	if (dflag)
		fprint(2, "name: <%s> pgsize:%ux\n", mach->name, mach->pgsize);

	HEADR = 22+28+3*48;
	if(INITTEXT == -1)
		INITTEXT = ihdr.txtaddr;
	else
		ihdr.txtaddr = INITTEXT;
	if(INITDAT == -1)
		INITDAT = ihdr.dataddr;
	else
		ihdr.dataddr = INITDAT;
	if(INITENTRY == -1)
		INITENTRY = ihdr.entry;
	else
		ihdr.entry = INITENTRY;
	textsize = ihdr.txtsz;
	datsize = ihdr.datsz;
	bsssize = ihdr.bsssz;
	if(INITRND > 0)
		ihdr.dataddr = INITDAT = RND(INITTEXT+textsize, INITRND);
	if(0){
		INITTEXT = INITENTRY;
		INITDAT = RND(INITTEXT+textsize, 4);
	}
	if(0){
		print("H=%lux T=%lux D=%lux t=%lux d=%lux b=%lux e=%lux\n", HEADR, INITTEXT, INITDAT, textsize, datsize, bsssize, INITENTRY);
		print("%llux %llux %llux %lux %lux %lux\n", ihdr.txtaddr, ihdr.dataddr, ihdr.entry, ihdr.txtsz, ihdr.datsz, ihdr.bsssz);
	}

	readsyms();
}

#define WB	128
#define WSAFE	(WB-4)
char Wbuf[WB];
char *wp = Wbuf;

void
cflush(void)
{
	if(wp > Wbuf)
		write(ofd, Wbuf, wp-Wbuf);
	wp = Wbuf;
}

void
lput(long l)
{
	wp[0] = l>>24;
	wp[1] = l>>16;
	wp[2] = l>>8;
	wp[3] = l;
	wp += 4;
	if(wp >= Wbuf+WSAFE)
		cflush();
}

void
cput(int l)
{
	wp[0] = l;
	wp += 1;
	if(wp >= Wbuf+WSAFE)
		cflush();
}

void
hputl(int l)
{
	wp[1] = l>>8;
	wp[0] = l;
	wp += 2;
	if(wp >= Wbuf+WSAFE)
		cflush();
}

void
lputl(long l)
{
	wp[3] = l>>24;
	wp[2] = l>>16;
	wp[1] = l>>8;
	wp[0] = l;
	wp += 4;
	if(wp >= Wbuf+WSAFE)
		cflush();
}

static void
copyseg(long sz)
{
	char	buf[1024];

	cflush();
	while (sz > 0){
		long n;
		long r;

		n = sz;
		if (n > sizeof buf)
			n = sizeof buf;
		sz -= n;

		if ((r = read(ifd, buf, n)) != n){
			fprint(2, "%ld = read(...%ld) at %ld\n", r, n, (long)seek(ifd, 0, 1));
			perror("Premature eof");
			exits(fail);
		}
		if ((r = write(ofd, buf, n)) != n){
			fprint(2, "%ld = write(...%ld)\n", r, n);
			perror("Write error!");
			exits(fail);
		}
	}
	cflush();
}

static void
put_file(char *ofile)
{
	ofd = create(ofile, OWRITE, 0666);
	if (ofd < 0) {
		fprint(2, "5coff: create %s: %r\n", ofile);
		exits("create");
	}
	cout = ofd;

	/* TBS lput for Plan9 header before ? */

	seek(ifd, ihdr.txtoff, 0);
	seek(ofd, HEADR, 0);
	copyseg(ihdr.txtsz);

	seek(ifd, ihdr.datoff, 0);
	seek(ofd, HEADR+textsize, 0);
	copyseg(ihdr.datsz);

	seek(ofd, HEADR+textsize+datsize, 0);
	coffsym();
	cflush();
	cofflc();
	cflush();
	
	seek(ofd, 0, 0);
	coffhdr();
	cflush();

	close(ifd);
	close(ofd);
}

long
entryvalue(void)
{
	return INITENTRY;
}

void
diag(char *s, ...)
{
	fprint(2, "%s\n", s);
	exits("error");
}

static void
readsyms(void)
{
	int i;
	long n;
	Sym *s;

	if(sflag)
		return;
	n = syminit(ifd, &ihdr);
	beginsym();
	for(i = 0; i < n; i++){
		s = getsym(i);
		newsym(i, s->name, s->value, s->type);
	}
	endsym();
}
