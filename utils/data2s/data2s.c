#include <lib9.h>
#include <bio.h>

void
main(int argc, char *argv[])
{
	Biobuf bin, bout;
	long len;
	int n;
	uchar block[8], *c;

	if(argc != 2){
		fprint(2, "usage: data2s name\n");
		exits("usage");
	}
	setbinmode();
	Binit(&bin, 0, OREAD);
	Binit(&bout, 1, OWRITE);
	for(len=0; (n=Bread(&bin, block, sizeof(block))) > 0; len += n){
		Bprint(&bout, "DATA %scode+%ld(SB)/%d, $\"", argv[1], len, n);
		for(c=block; c < block+n; c++)
			if(*c)
				Bprint(&bout, "\\%uo", *c);
			else
				Bprint(&bout, "\\z");
		Bprint(&bout, "\"\n");
	}
	if(len == 0)
		Bprint(&bout, "GLOBL %scode+0(SB), $1\n", argv[1]);
	else
		Bprint(&bout, "GLOBL %scode+0(SB), $%ld\n", argv[1], len);
	Bprint(&bout, "GLOBL %slen+0(SB), $4\n", argv[1]);
	Bprint(&bout, "DATA %slen+0(SB)/4, $%ld\n", argv[1], len);
	exits(0);
}
