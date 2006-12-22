#include <u.h>
#include <libc.h>
#include <mp.h>
#include "port/dat.h"

int loops = 1;

long randomreg;

void
srand(long seed)
{
	randomreg = seed;
}

long
lrand(void)
{
	randomreg = randomreg*104381 + 81761;
	return randomreg;
}

void
prng(uchar *p, int n)
{
	while(n-- > 0)
		*p++ = lrand();
}


void
testshift(char *str)
{
	mpint *b1, *b2;
	int i;

	b1 = strtomp(str, nil, 16, nil);
	malloccheck();
fprint(2, "A");
	b2 = mpnew(0);
fprint(2, "B");
	malloccheck();
	mpleft(b1, 20, b2);
fprint(2, "C");
	malloccheck();
	mpfree(b1);
fprint(2, "D");
	malloccheck();
	mpfree(b2);
}

void
main(int argc, char **argv)
{
	mpint *x, *y;

	ARGBEGIN{
	case 'n':
		loops = atoi(ARGF());
		break;
	}ARGEND;

	fmtinstall('B', mpfmt);
	fmtinstall('Q', mpfmt);
	srand(0);
	mpsetminbits(2*Dbits);
	testshift("1111111111111111");
	print("done\n");
	exits(0);
}
