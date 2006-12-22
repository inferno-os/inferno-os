/*
 * send S records to rpcg
 */

#include <u.h>
#include <libc.h>
#include <bio.h>

static	int	dbg;
static	char	buf[2048];
static	int	run=1;
static	void	stuffbym(char*, int, int);
static	void	getdot(void);

void
main(int argc, char **argv)
{
	int n;
	char *l;
	Biobuf *f;
	static int p;

	ARGBEGIN{
	case 'd': dbg++; break;
	case 'n': run=0; break;
	}ARGEND

	f = Bopen(*argv? *argv: "k.mx", OREAD);
	if(f == 0) {
		fprint(2, "sload: cannot open k.mx: %r\n");
		exits("sload");
	}
	getdot();
	while((l = Brdline(f, '\n')) != 0) {
		l[Blinelen(f)-1] = '\r';
		stuffbym(l, Blinelen(f), 16);
		getdot();
		if(++p % 25 == 0)
			write(2, ".", 1);
	}
	exits(0);
}

static void
stuffbym(char *l, int n, int m)
{
	int nr, ns;

	while(n > 0) {
		ns = n;
		if(ns > m)
			ns = m;
		write(1, l, ns);
		l += ns;
		n -= ns;
	}
}

static void
getdot(void)
{
	char c;

	for(;;){
		if(read(0, &c, 1) != 1)
			exits("bang");
		write(2, &c, 1);
		if(c == '.')
			break;
	}
}
