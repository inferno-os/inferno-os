#include "os.h"
#include <mp.h>
#include <libsec.h>

/*
 * DES ECB mode.
 * Input length MUST be a multiple of 8 bytes (DES block size).
 * Callers are responsible for padding.
 *
 * Previously, partial blocks were handled by encrypting the fixed
 * pattern [0,1,2,3,4,5,6,7] and XORing — this produced a static
 * keystream identical across all calls with the same key, which is
 * cryptographically broken.  Now we reject partial blocks.
 */

void
desECBencrypt(uchar *p, int len, DESstate *s)
{
	if(len % 8 != 0){
		fprint(2, "desECBencrypt: input length %d not a multiple of DES block size (8)\n", len);
		abort();
	}
	for(; len >= 8; len -= 8){
		block_cipher(s->expanded, p, 0);
		p += 8;
	}
}

void
desECBdecrypt(uchar *p, int len, DESstate *s)
{
	if(len % 8 != 0){
		fprint(2, "desECBdecrypt: input length %d not a multiple of DES block size (8)\n", len);
		abort();
	}
	for(; len >= 8; len -= 8){
		block_cipher(s->expanded, p, 1);
		p += 8;
	}
}
