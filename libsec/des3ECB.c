#include "os.h"
#include <mp.h>
#include <libsec.h>

/*
 * Triple-DES ECB mode.
 * Input length MUST be a multiple of 8 bytes (DES block size).
 * Callers are responsible for padding.
 *
 * Previously, partial blocks were handled by encrypting the fixed
 * pattern [0,1,2,3,4,5,6,7] and XORing — this produced a static
 * keystream identical across all calls with the same key, which is
 * cryptographically broken.  Now we reject partial blocks.
 */

void
des3ECBencrypt(uchar *p, int len, DES3state *s)
{
	if(len % 8 != 0){
		fprint(2, "des3ECBencrypt: input length %d not a multiple of DES block size (8)\n", len);
		abort();
	}
	for(; len >= 8; len -= 8){
		triple_block_cipher(s->expanded, p, DES3EDE);
		p += 8;
	}
}

void
des3ECBdecrypt(uchar *p, int len, DES3state *s)
{
	if(len % 8 != 0){
		fprint(2, "des3ECBdecrypt: input length %d not a multiple of DES block size (8)\n", len);
		abort();
	}
	for(; len >= 8; len -= 8){
		triple_block_cipher(s->expanded, p, DES3DED);
		p += 8;
	}
}
