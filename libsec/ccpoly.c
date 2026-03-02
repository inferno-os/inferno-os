/*
 * ChaCha20-Poly1305 AEAD construction (RFC 8439, Section 2.8).
 *
 * Combines ChaCha20 encryption with Poly1305 authentication.
 * The Poly1305 one-time key is derived from the first ChaCha20 block.
 */
#include "os.h"
#include <libsec.h>

static void
put64le(uchar *p, u64int v)
{
	p[0] = v; p[1] = v>>8; p[2] = v>>16; p[3] = v>>24;
	p[4] = v>>32; p[5] = v>>40; p[6] = v>>48; p[7] = v>>56;
}

/*
 * Generate the Poly1305 one-time key by encrypting 32 zero bytes
 * with ChaCha20 using counter = 0.
 */
static void
ccpoly_otk(uchar otk[32], uchar key[32], uchar nonce[12])
{
	ChaChastate s;
	uchar zeros[32];

	setupChaChastate(&s, key, 32, nonce, 12, 20);
	memset(zeros, 0, 32);
	chacha_encrypt(zeros, 32, &s);
	memmove(otk, zeros, 32);
}

/*
 * Poly1305 MAC over (AAD || pad || ciphertext || pad || lengths).
 * Padding to 16-byte boundary between sections.
 */
static void
ccpoly_mac(uchar tag[16], uchar *aad, int naad, uchar *ct, int nct, uchar otk[32])
{
	Poly1305state ps;
	uchar zeros[16];
	uchar lenblock[16];
	int padlen;

	memset(zeros, 0, sizeof(zeros));
	setupPoly1305(&ps, otk);

	/* AAD */
	if(naad > 0)
		poly1305_update(&ps, aad, naad);
	padlen = (16 - (naad & 15)) & 15;
	if(padlen > 0)
		poly1305_update(&ps, zeros, padlen);

	/* ciphertext */
	if(nct > 0)
		poly1305_update(&ps, ct, nct);
	padlen = (16 - (nct & 15)) & 15;
	if(padlen > 0)
		poly1305_update(&ps, zeros, padlen);

	/* lengths as 64-bit little-endian */
	put64le(lenblock, naad);
	put64le(lenblock+8, nct);
	poly1305_update(&ps, lenblock, 16);

	poly1305_finish(tag, &ps);
}

/*
 * Encrypt dat in place and produce authentication tag.
 */
void
ccpoly_encrypt(uchar *dat, int ndat, uchar *aad, int naad,
	uchar tag[16], uchar key[32], uchar nonce[12])
{
	ChaChastate s;
	uchar otk[32];

	/* generate one-time Poly1305 key (counter 0) */
	ccpoly_otk(otk, key, nonce);

	/* encrypt with ChaCha20 starting at counter 1 */
	setupChaChastate(&s, key, 32, nonce, 12, 20);
	chacha_setctr(&s, 1);
	chacha_encrypt(dat, ndat, &s);

	/* compute authentication tag */
	ccpoly_mac(tag, aad, naad, dat, ndat, otk);
}

/*
 * Verify tag, then decrypt dat in place.
 * Returns 0 on success, -1 on authentication failure.
 */
int
ccpoly_decrypt(uchar *dat, int ndat, uchar *aad, int naad,
	uchar tag[16], uchar key[32], uchar nonce[12])
{
	ChaChastate s;
	uchar otk[32];
	uchar computed[16];
	int i, diff;

	/* generate one-time Poly1305 key */
	ccpoly_otk(otk, key, nonce);

	/* verify tag before decrypting */
	ccpoly_mac(computed, aad, naad, dat, ndat, otk);

	diff = 0;
	for(i = 0; i < 16; i++)
		diff |= computed[i] ^ tag[i];
	if(diff != 0)
		return -1;

	/* decrypt with ChaCha20 starting at counter 1 */
	setupChaChastate(&s, key, 32, nonce, 12, 20);
	chacha_setctr(&s, 1);
	chacha_encrypt(dat, ndat, &s);

	return 0;
}
