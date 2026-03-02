#include "os.h"
#include <libsec.h>

/*
 * AES-GCM (Galois/Counter Mode) per NIST SP 800-38D.
 *
 * Uses Shoup's 4-bit table method for GF(2^128) multiplication.
 * The GHASH key H is AES_K(0^128).
 */

/* GF(2^128) multiplication using precomputed 4-bit table.
 * The field polynomial is x^128 + x^7 + x^2 + x + 1.
 */

/* load a 128-bit big-endian value into two u64int (MSB first) */
static void
be128load(uchar b[16], u64int v[2])
{
	v[0] = (u64int)b[0]<<56 | (u64int)b[1]<<48 | (u64int)b[2]<<40 | (u64int)b[3]<<32
	     | (u64int)b[4]<<24 | (u64int)b[5]<<16 | (u64int)b[6]<<8 | (u64int)b[7];
	v[1] = (u64int)b[8]<<56 | (u64int)b[9]<<48 | (u64int)b[10]<<40 | (u64int)b[11]<<32
	     | (u64int)b[12]<<24 | (u64int)b[13]<<16 | (u64int)b[14]<<8 | (u64int)b[15];
}

/* store two u64int as 128-bit big-endian */
static void
be128store(u64int v[2], uchar b[16])
{
	b[0] = v[0]>>56; b[1] = v[0]>>48; b[2] = v[0]>>40; b[3] = v[0]>>32;
	b[4] = v[0]>>24; b[5] = v[0]>>16; b[6] = v[0]>>8;  b[7] = v[0];
	b[8] = v[1]>>56; b[9] = v[1]>>48; b[10]= v[1]>>40; b[11]= v[1]>>32;
	b[12]= v[1]>>24; b[13]= v[1]>>16; b[14]= v[1]>>8;  b[15]= v[1];
}

/*
 * Precompute GHASH table: Htable[i] = i * H in GF(2^128)
 * for i = 0..15, stored as pairs of u64int.
 * Uses the bit-reflected convention.
 */
static void
ghash_precomp(uchar H[16], u64int Htable[16*2])
{
	u64int h[2], v[2], r;
	int i, j;

	/* GCM bit ordering: MSB of byte 0 = x^0, which is already
	 * the reflected convention for right-shift multiplication */
	be128load(H, h);

	/* Htable[0] = 0 */
	Htable[0] = 0;
	Htable[1] = 0;

	/* Htable[8] = H (since bit 3 = x^0 in reflected order) */
	Htable[8*2] = h[0];
	Htable[8*2+1] = h[1];

	/* compute Htable[4] = 2*H, Htable[2] = 4*H, Htable[1] = 8*H
	 * by doubling in GF(2^128). Double = shift right by 1 (reflected),
	 * XOR reduction polynomial if low bit set.
	 * Reduction: x^128 + x^7 + x^2 + x + 1 reflected = 0xe1 << 56
	 */
	v[0] = h[0];
	v[1] = h[1];
	for(i = 4; i >= 1; i >>= 1){
		r = (u64int)(-(v[1] & 1)) & ((u64int)0xe1 << 56);
		v[1] = (v[1] >> 1) | (v[0] << 63);
		v[0] = (v[0] >> 1) ^ r;
		Htable[i*2] = v[0];
		Htable[i*2+1] = v[1];
	}

	/* fill in the rest by XOR: Htable[i^j] = Htable[i] ^ Htable[j] */
	for(i = 2; i < 16; i <<= 1)
		for(j = 1; j < i; j++){
			Htable[(i+j)*2] = Htable[i*2] ^ Htable[j*2];
			Htable[(i+j)*2+1] = Htable[i*2+1] ^ Htable[j*2+1];
		}
}

/*
 * GHASH: multiply-accumulate in GF(2^128).
 * Y = Y ^ X, then Y = Y * H.
 * Uses 4-bit table lookup (Shoup's method).
 */
static void
ghash_block(u64int Htable[16*2], u64int Y[2], uchar X[16])
{
	u64int Xv[2], z[2], r;
	int i;

	/* load input block (already in GCM reflected bit order) */
	be128load(X, Xv);

	/* XOR into accumulator */
	Y[0] ^= Xv[0];
	Y[1] ^= Xv[1];

	/* multiply Y * H using 4-bit table */
	z[0] = 0;
	z[1] = 0;

	/* process 4 bits at a time, from LSB of Y[1] up to MSB of Y[0]
	 * (high-degree to low-degree for right-shift Horner evaluation) */
	for(i = 31; i >= 0; i--){
		int nibble;
		if(i < 16)
			nibble = (Y[0] >> (60 - 4*i)) & 0xf;
		else
			nibble = (Y[1] >> (60 - 4*(i-16))) & 0xf;

		if(i < 31){
			/* shift z right by 4 in GF(2^128) */
			r = z[1] & 0xf;
			z[1] = (z[1] >> 4) | (z[0] << 60);
			z[0] = (z[0] >> 4);
			/* reduction for each of the 4 shifted-out bits */
			z[0] ^= (u64int)(
				/* precomputed reduction for 4 bits (matches OpenSSL rem_4bit) */
				(r & 1 ? (u64int)0x1c20 << 48 : 0) ^
				(r & 2 ? (u64int)0x3840 << 48 : 0) ^
				(r & 4 ? (u64int)0x7080 << 48 : 0) ^
				(r & 8 ? (u64int)0xe100 << 48 : 0)
			);
		}

		z[0] ^= Htable[nibble*2];
		z[1] ^= Htable[nibble*2+1];
	}

	Y[0] = z[0];
	Y[1] = z[1];
}

/* GHASH over arbitrary data, with zero-padding to block boundary */
static void
ghash_update(u64int Htable[16*2], u64int Y[2], uchar *data, ulong len)
{
	uchar block[16];

	for(; len >= 16; len -= 16, data += 16)
		ghash_block(Htable, Y, data);

	if(len > 0){
		memset(block, 0, 16);
		memmove(block, data, len);
		ghash_block(Htable, Y, block);
	}
}

/* increment the rightmost 32 bits of J (counter) */
static void
gcm_inc32(uchar J[16])
{
	int i;
	for(i = 15; i >= 12; i--)
		if(++J[i] != 0)
			break;
}

void
setupAESGCMstate(AESGCMstate *s, uchar *key, int keylen, uchar *iv, int ivlen)
{
	uchar zero[AESbsize];

	memset(s, 0, sizeof(*s));
	setupAESstate(&s->a, key, keylen, nil);

	/* H = AES_K(0^128) */
	memset(zero, 0, AESbsize);
	aesEncryptBlock(&s->a, zero, s->hkey);

	/* precompute GHASH table */
	ghash_precomp(s->hkey, s->htable);

	/* compute J0 (initial counter) */
	if(ivlen == 12){
		/* common case: J0 = IV || 0^31 || 1 */
		memmove(s->J0, iv, 12);
		s->J0[12] = 0;
		s->J0[13] = 0;
		s->J0[14] = 0;
		s->J0[15] = 1;
	} else {
		/* general case: J0 = GHASH_H(IV || pad || len64) */
		u64int Y[2];
		uchar lenblock[16];

		Y[0] = 0;
		Y[1] = 0;
		ghash_update(s->htable, Y, iv, ivlen);
		memset(lenblock, 0, 8);
		lenblock[8]  = ((u64int)ivlen*8) >> 56;
		lenblock[9]  = ((u64int)ivlen*8) >> 48;
		lenblock[10] = ((u64int)ivlen*8) >> 40;
		lenblock[11] = ((u64int)ivlen*8) >> 32;
		lenblock[12] = ((u64int)ivlen*8) >> 24;
		lenblock[13] = ((u64int)ivlen*8) >> 16;
		lenblock[14] = ((u64int)ivlen*8) >> 8;
		lenblock[15] = ((u64int)ivlen*8);
		ghash_block(s->htable, Y, lenblock);

		/* convert Y to bytes for J0 */
		be128store(Y, s->J0);
	}
}

/*
 * AES-GCM encrypt.
 * dat is plaintext on input, ciphertext on output.
 * tag receives the 16-byte authentication tag.
 * Returns 0 on success.
 */
int
aesgcm_encrypt(uchar *dat, ulong ndat, uchar *aad, ulong naad,
	uchar tag[16], AESGCMstate *s)
{
	uchar J[AESbsize], S[AESbsize], block[AESbsize];
	u64int Y[2];
	uchar lenblock[16];
	ulong i, n;

	/* start counter at J0 + 1 */
	memmove(J, s->J0, AESbsize);
	gcm_inc32(J);

	/* encrypt plaintext with AES-CTR */
	for(i = 0; i < ndat; i += AESbsize){
		aesEncryptBlock(&s->a, J, block);
		gcm_inc32(J);
		n = ndat - i;
		if(n > AESbsize) n = AESbsize;
		for(ulong k = 0; k < n; k++)
			dat[i+k] ^= block[k];
	}

	/* GHASH over AAD and ciphertext */
	Y[0] = 0;
	Y[1] = 0;
	ghash_update(s->htable, Y, aad, naad);
	ghash_update(s->htable, Y, dat, ndat);

	/* length block: [len(AAD) in bits || len(C) in bits] */
	lenblock[0]  = ((u64int)naad*8) >> 56;
	lenblock[1]  = ((u64int)naad*8) >> 48;
	lenblock[2]  = ((u64int)naad*8) >> 40;
	lenblock[3]  = ((u64int)naad*8) >> 32;
	lenblock[4]  = ((u64int)naad*8) >> 24;
	lenblock[5]  = ((u64int)naad*8) >> 16;
	lenblock[6]  = ((u64int)naad*8) >> 8;
	lenblock[7]  = ((u64int)naad*8);
	lenblock[8]  = ((u64int)ndat*8) >> 56;
	lenblock[9]  = ((u64int)ndat*8) >> 48;
	lenblock[10] = ((u64int)ndat*8) >> 40;
	lenblock[11] = ((u64int)ndat*8) >> 32;
	lenblock[12] = ((u64int)ndat*8) >> 24;
	lenblock[13] = ((u64int)ndat*8) >> 16;
	lenblock[14] = ((u64int)ndat*8) >> 8;
	lenblock[15] = ((u64int)ndat*8);
	ghash_block(s->htable, Y, lenblock);

	/* convert GHASH result to bytes */
	be128store(Y, S);

	/* tag = GHASH_result XOR AES_K(J0) */
	aesEncryptBlock(&s->a, s->J0, block);
	for(i = 0; i < 16; i++)
		tag[i] = S[i] ^ block[i];

	return 0;
}

/*
 * AES-GCM decrypt.
 * dat is ciphertext on input, plaintext on output.
 * tag is the 16-byte authentication tag to verify.
 * Returns 0 on success, -1 on authentication failure.
 */
int
aesgcm_decrypt(uchar *dat, ulong ndat, uchar *aad, ulong naad,
	uchar tag[16], AESGCMstate *s)
{
	uchar J[AESbsize], S[AESbsize], block[AESbsize];
	uchar computed_tag[16];
	u64int Y[2];
	uchar lenblock[16];
	ulong i, n;
	int diff;

	/* GHASH over AAD and ciphertext (before decryption) */
	Y[0] = 0;
	Y[1] = 0;
	ghash_update(s->htable, Y, aad, naad);
	ghash_update(s->htable, Y, dat, ndat);

	/* length block */
	lenblock[0]  = ((u64int)naad*8) >> 56;
	lenblock[1]  = ((u64int)naad*8) >> 48;
	lenblock[2]  = ((u64int)naad*8) >> 40;
	lenblock[3]  = ((u64int)naad*8) >> 32;
	lenblock[4]  = ((u64int)naad*8) >> 24;
	lenblock[5]  = ((u64int)naad*8) >> 16;
	lenblock[6]  = ((u64int)naad*8) >> 8;
	lenblock[7]  = ((u64int)naad*8);
	lenblock[8]  = ((u64int)ndat*8) >> 56;
	lenblock[9]  = ((u64int)ndat*8) >> 48;
	lenblock[10] = ((u64int)ndat*8) >> 40;
	lenblock[11] = ((u64int)ndat*8) >> 32;
	lenblock[12] = ((u64int)ndat*8) >> 24;
	lenblock[13] = ((u64int)ndat*8) >> 16;
	lenblock[14] = ((u64int)ndat*8) >> 8;
	lenblock[15] = ((u64int)ndat*8);
	ghash_block(s->htable, Y, lenblock);

	/* convert GHASH result to bytes */
	be128store(Y, S);

	/* computed tag = GHASH XOR AES_K(J0) */
	aesEncryptBlock(&s->a, s->J0, block);
	for(i = 0; i < 16; i++)
		computed_tag[i] = S[i] ^ block[i];

	/* constant-time comparison */
	diff = 0;
	for(i = 0; i < 16; i++)
		diff |= computed_tag[i] ^ tag[i];
	if(diff != 0)
		return -1;

	/* decrypt ciphertext with AES-CTR */
	memmove(J, s->J0, AESbsize);
	gcm_inc32(J);
	for(i = 0; i < ndat; i += AESbsize){
		aesEncryptBlock(&s->a, J, block);
		gcm_inc32(J);
		n = ndat - i;
		if(n > AESbsize) n = AESbsize;
		for(ulong k = 0; k < n; k++)
			dat[i+k] ^= block[k];
	}

	return 0;
}
