#include <lib9.h>
#include <bio.h>

void
main(int argc, char *argv[])
{
	Biobuf bin, bout;
	long len;
	int n;
	uchar block[4];

	if(argc != 2){
		fprint(2, "usage: data2texts name\n");
		exits("usage");
	}
	setbinmode();
	Binit(&bin, 0, OREAD);
	Binit(&bout, 1, OWRITE);
        Bprint(&bout, "TEXT %scode(SB), 0, $-4\n", argv[1]);
	for(len=0; (n=Bread(&bin, block, sizeof(block))) > 0; len += n){

                ulong w = *(ulong *)block;
	        Bprint(&bout, "WORD $0x%08ux\n", w);
	}
	Bprint(&bout, "TEXT %slen(SB), 0, $-4\n", argv[1]);
	Bprint(&bout, "WORD $%ld\n", len);
	exits(0);
}
