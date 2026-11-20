/*
 * ChaCha20-Poly1305 as RFC 8439 defines it (12-byte nonce), built from
 * Monocypher's ChaCha20 and Poly1305. Used by the ssl device's
 * chacha20poly1305 records; XChaCha20-Poly1305 is in modern.c.
 */
#include "os.h"
#include <libsec.h>
#define C99SHIM_HAVE_LIB9
#include "monocypher.h"

static void
polytag(uchar *tag, uchar *key, uchar *nonce, uchar *ad, ulong nad, uchar *ct, ulong n)
{
	uchar block[64], lens[16], zero[16];
	crypto_poly1305_ctx ctx;
	int i;

	crypto_chacha20_ietf(block, nil, sizeof block, key, nonce, 0);
	memset(zero, 0, sizeof zero);
	memset(lens, 0, sizeof lens);
	for(i = 0; i < 4; i++){
		lens[i] = nad >> (8*i);
		lens[8+i] = n >> (8*i);
	}
	crypto_poly1305_init(&ctx, block);
	crypto_poly1305_update(&ctx, ad, nad);
	if(nad & 15)
		crypto_poly1305_update(&ctx, zero, 16 - (nad & 15));
	crypto_poly1305_update(&ctx, ct, n);
	if(n & 15)
		crypto_poly1305_update(&ctx, zero, 16 - (n & 15));
	crypto_poly1305_update(&ctx, lens, sizeof lens);
	crypto_poly1305_final(&ctx, tag);
	crypto_wipe(block, sizeof block);
}

/* encrypts buf in place and sets tag */
void
chachapolyseal(uchar *key, uchar *nonce, uchar *ad, ulong nad, uchar *buf, ulong n, uchar *tag)
{
	crypto_chacha20_ietf(buf, buf, n, key, nonce, 1);
	polytag(tag, key, nonce, ad, nad, buf, n);
}

/* decrypts buf in place; 0 if the tag is right, -1 (buf untouched) if not */
int
chachapolyopen(uchar *key, uchar *nonce, uchar *ad, ulong nad, uchar *buf, ulong n, uchar *tag)
{
	uchar t[16];

	polytag(t, key, nonce, ad, nad, buf, n);
	if(crypto_verify16(t, tag) != 0)
		return -1;
	crypto_chacha20_ietf(buf, buf, n, key, nonce, 1);
	return 0;
}
