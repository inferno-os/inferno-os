#include "os.h"
#include <libsec.h>

/* increment the rightmost 32 bits of the 128-bit counter in ivec */
static void
inc32(uchar ctr[AESbsize])
{
	int i;

	for(i = AESbsize-1; i >= AESbsize-4; i--)
		if(++ctr[i] != 0)
			break;
}

void
aesCTRencrypt(uchar *p, int len, AESstate *s)
{
	uchar block[AESbsize];
	int i, n;

	for(; len > 0; len -= n){
		aesEncryptBlock(s, s->ivec, block);
		inc32(s->ivec);
		n = len < AESbsize ? len : AESbsize;
		for(i = 0; i < n; i++)
			p[i] ^= block[i];
		p += n;
	}
}

/* CTR mode is symmetric */
void
aesCTRdecrypt(uchar *p, int len, AESstate *s)
{
	aesCTRencrypt(p, len, s);
}
