#include	<lib9.h>
#include	<bio.h>
#include	<mach.h>

int fd;
static void readf(void);

static void
usage(char *msg)
{
	fprint(2, "***Error: %s\n", msg);
	exits("usage");
}

static int
cget(void)
{
	uchar b[1];

	if(read(fd, b, 1) != 1){
		fprint(2, "bad cget\n");
		exits("cget");
	}
	return b[0];
}

static int
hget(void)
{
	uchar b[2];

	if(read(fd, b, 2) != 2){
		fprint(2, "bad hget\n");
		exits("hget");
	}
	return b[1]<<8 | b[0];
}

static int
lget(void)
{
	uchar b[4];

	if(read(fd, b, 4) != 4){
		fprint(2, "bad lget\n");
		exits("lget");
	}
	return b[3]<<24 | b[2]<<16 | b[1]<<8 | b[0];
}

static char *
sget(char *st)
{
	int i;
	static uchar buf[8+1];

	for(i = 0; i < 8+1; i++)
		buf[i] = 0;
	if(read(fd, buf, 8) != 8){
		fprint(2, "bad sget\n");
		exits("sget");
	}
	if(buf[0] == 0 && buf[1] == 0 && buf[2] == 0 && buf[3] == 0)
		return st+(buf[7]<<24|buf[6]<<16|buf[5]<<8|buf[4]);
	return (char*)buf;
}
		
void
main(int argc, char	*argv[])
{
	if (argc != 2)
		usage("Wrong number of arguments");

	fd = open(argv[1], OREAD);
	if (fd < 0) {
		fprint(2, "5coff: open %s: %r\n", argv[1]);
		exits("open");
	}
	readf();
	exits(0);
}

static void
section(int i, char *st, int *linoff, int *linn)
{
	int pa, va, sz, off, rel, lin, nrel, nlin, f, res, pno;
	char *nm;

	nm = sget(st);
	pa = lget();
	va = lget();
	sz = lget();
	off = lget();
	rel = lget();
	lin = lget();
	nrel = lget();
	nlin = lget();
	f = lget();
	res = hget();
	pno = hget();
	print("sect %d %s: pa=0x%x va=0x%x sz=%d off=%d rel=%d lin=%d nrel=%d nlin=%d f=0x%x res=%d pno=%d\n", i, nm, pa, va, sz, off, rel, lin, nrel, nlin, f, res, pno);
	*linoff = lin;
	*linn = nlin;
}

static void
opthdr(void)
{
	int mag, ver, textsz, datasz, bsssz, entry, text, data;

	mag = hget();
	ver = hget();
	textsz = lget();
	datasz = lget();
	bsssz = lget();
	entry = lget();
	text = lget();
	data = lget();
	print("opt: mag=0x%x ver=%d txtsz=%d datsz=%d bsssz=%d ent=0x%x txt=0x%x dat=0x%x\n", mag, ver, textsz, datasz, bsssz, entry, text, data);
}

static void
readhdr(int *o, int *ns, int *sy, int *nsy)
{
	int vid, nsec, date, sym, nsym, opt, f, tid;

	vid = hget();
	nsec = hget();
	date = lget();
	sym = lget();
	nsym = lget();
	opt = hget();
	f = hget();
	tid = hget();
	print("hdr: vid=0x%x nsect=%d date=%d sym=%d nsym=%d opt=%d f=0x%x tid=0x%x\n", vid, nsec, date, sym, nsym, opt, f, tid);
	*o = opt;
	*ns = nsec;
	*sy = sym;
	*nsy = nsym;
}

static void
readauxsect(int i)
{
	int sz, nrel, ln;

	sz = lget();
	nrel = hget();
	ln = hget();
	lget();
	hget();
	lget();
	print("sym auxsect %d: sz=%d nrel=%d ln=%d\n", i, sz, nrel, ln);
}

static void
readauxfun(int i)
{
	int ind, sz, fpln, nind;

	ind = lget();
	sz = lget();
	fpln = lget();
	nind = lget();
	hget();
	print("sym auxfun %d: ind=%d sz=%d fpln=%d nind=%d\n", i, ind, sz, fpln, nind);
}

static void
readauxbf(int i)
{
	int rsav, lno, lns, fsz, nind;

	rsav = lget();
	lno = hget();
	lns = hget();
	fsz = lget();
	nind = lget();
	hget();
	print("sym auxbf %d: rsav=%x lno=%d lns=%d fsz=%d nind=%d\n", i, rsav, lno, lns, fsz, nind);
}

static void
readauxef(int i)
{
	int lno;

	lget();
	lno = hget();
	lget();
	lget();
	lget();
	print("sym auxef %d: lno=%d\n", i, lno);
}

static void
readauxother(int i)
{
	lget();
	lget();
	hget();
	lget();
	lget();
	print("sym auxother %d\n", i);
}

static int
readsym(int i, char *st)
{
	int v, s, t, c, aux;
	char *nm;

	nm = sget(st);
	v = lget();
	s = hget();
	t = hget();
	c = cget();
	aux = cget();
	print("sym %d %s: val=%d sec=%d type=%d class=%d aux=%d\n", i, nm, v, s, t, c, aux);
	if(aux){
		i++;
		if(strcmp(nm, ".text") == 0 || strcmp(nm, ".data") == 0 || strcmp(nm, ".bss") == 0)
			readauxsect(i);
		else if(strcmp(nm, ".bf") == 0)
			readauxbf(i);
		else if(strcmp(nm, ".ef") == 0)
			readauxef(i);
		else if((t&0x30) == 0x20)	// will do
			readauxfun(i);
		else
			readauxother(i);
		return 1;
	}
	return 0;
}

static char *
readstr(int n)
{
	char *s = malloc(n);

	if(read(fd, s+4, n-4) != n-4){
		fprint(2, "bad readstr\n");
		exits("sget");
	}
	return s;
}

static void
readln(int i)
{
	int a, l;

	a = lget();
	l = hget();
	if(l == 0)
		print("line %d: sym=%d\n", i, a);
	else
		print("line %d: addr=0x%x line=%d\n", i, a, l);
}
	
static void
readf()
{
	int i, opt, nsec, sym, nsym, stoff, strsz, linoff, nlin, lino, linn;
	char *st;

	seek(fd, 0, 0);
	readhdr(&opt, &nsec, &sym, &nsym);
	if(opt)
		opthdr();
	stoff = sym+18*nsym;
	seek(fd, stoff, 0);
	strsz = lget();
	st = readstr(strsz);
	linoff = nlin = 0;
	seek(fd, 22+28, 0);
	for(i = 0; i < nsec; i++){
		section(i, st, &lino, &linn);
		if(linn != 0){
			if(nlin == 0){
				nlin = linn;
				linoff = lino;
			}
			else
				print("multiple line no. tables\n");
		}
	}
	seek(fd, sym, 0);
	for(i = 0; i < nsym; i++)
		i += readsym(i, st);
	print("strsz = %d\n", strsz);
	if(nlin != 0){
		seek(fd, linoff, 0);
		for(i = 0; i < nlin; i++)
			readln(i);
	}
}
