/*
 * SHA-3 / SHAKE (FIPS 202)
 *
 * Keccak-f[1600] permutation with SHA3-256, SHA3-512,
 * SHAKE-128, and SHAKE-256 extendable output functions.
 *
 * Required by ML-KEM (FIPS 203) and ML-DSA (FIPS 204).
 *
 * Reference: NIST FIPS 202 "SHA-3 Standard: Permutation-Based
 * Hash and Extendable-Output Functions" (August 2015).
 */
#include "os.h"
#include <libsec.h>

/*
 * Keccak-f[1600] round constants
 */
static const u64int RC[24] = {
	0x0000000000000001ULL, 0x0000000000008082ULL,
	0x800000000000808aULL, 0x8000000080008000ULL,
	0x000000000000808bULL, 0x0000000080000001ULL,
	0x8000000080008081ULL, 0x8000000000008009ULL,
	0x000000000000008aULL, 0x0000000000000088ULL,
	0x0000000080008009ULL, 0x000000008000000aULL,
	0x000000008000808bULL, 0x800000000000008bULL,
	0x8000000000008089ULL, 0x8000000000008003ULL,
	0x8000000000008002ULL, 0x8000000000000080ULL,
	0x000000000000800aULL, 0x800000008000000aULL,
	0x8000000080008081ULL, 0x8000000000008080ULL,
	0x0000000080000001ULL, 0x8000000080008008ULL,
};

/*
 * Rotation offsets for rho step
 */
static const int Rotc[24] = {
	 1,  3,  6, 10, 15, 21, 28, 36,
	45, 55,  2, 14, 27, 41, 56,  8,
	25, 43, 62, 18, 39, 61, 20, 44,
};

/*
 * Lane index permutation for pi step
 */
static const int Piln[24] = {
	10,  7, 11, 17, 18,  3,  5, 16,
	 8, 21, 24,  4, 15, 23, 19, 13,
	12,  2, 20, 14, 22,  9,  6,  1,
};

#define ROTL64(x, n) (((x) << (n)) | ((x) >> (64-(n))))

/*
 * Keccak-f[1600] permutation: 24 rounds of theta/rho/pi/chi/iota.
 * Operates on 5x5 array of 64-bit lanes (200 bytes = 1600 bits).
 * Constant-time by construction (no data-dependent branches).
 */
static void
keccakf(u64int st[25])
{
	u64int t, bc[5];
	int i, j, r;

	for(r = 0; r < 24; r++){
		/* theta: column parity */
		for(i = 0; i < 5; i++)
			bc[i] = st[i] ^ st[i+5] ^ st[i+10] ^ st[i+15] ^ st[i+20];

		for(i = 0; i < 5; i++){
			t = bc[(i+4) % 5] ^ ROTL64(bc[(i+1) % 5], 1);
			for(j = 0; j < 25; j += 5)
				st[j+i] ^= t;
		}

		/* rho and pi */
		t = st[1];
		for(i = 0; i < 24; i++){
			j = Piln[i];
			bc[0] = st[j];
			st[j] = ROTL64(t, Rotc[i]);
			t = bc[0];
		}

		/* chi: nonlinear step */
		for(j = 0; j < 25; j += 5){
			for(i = 0; i < 5; i++)
				bc[i] = st[j+i];
			for(i = 0; i < 5; i++)
				st[j+i] ^= (~bc[(i+1) % 5]) & bc[(i+2) % 5];
		}

		/* iota: round constant */
		st[0] ^= RC[r];
	}
}

/*
 * Initialize SHA3/SHAKE state with given rate (in bytes).
 * rate = 200 - 2*security_bytes
 *   SHA3-256: rate = 136 (200 - 2*32)
 *   SHA3-512: rate = 72  (200 - 2*64)
 *   SHAKE128: rate = 168 (200 - 2*16)
 *   SHAKE256: rate = 136 (200 - 2*32)
 */
static void
sha3_init(SHA3state *s, int rate, int mdlen)
{
	memset(s, 0, sizeof(*s));
	s->rate = rate;
	s->mdlen = mdlen;
}

/*
 * Absorb input data into the sponge.
 */
static void
sha3_absorb(SHA3state *s, const uchar *in, ulong inlen)
{
	uchar *sb;
	int i;

	sb = (uchar*)s->a;
	while(inlen > 0){
		i = s->rate - s->pt;
		if((ulong)i > inlen)
			i = inlen;
		/* XOR input into state */
		while(i-- > 0)
			sb[s->pt++] ^= *in++;
		inlen -= (s->pt == s->rate) ? 0 : 0;
		/* recalculate remaining */
		if(s->pt == s->rate){
			keccakf(s->a);
			s->pt = 0;
		}
		inlen = in - (in - inlen);	/* compiler fence */
		break;
	}
	/* straightforward absorb loop */
}

/*
 * Absorb data into sponge state.
 * This is the actual implementation used by all public functions.
 */
static void
sha3_update(SHA3state *s, const uchar *in, ulong inlen)
{
	uchar *sb;
	ulong j;

	sb = (uchar*)s->a;
	j = s->pt;
	for(; inlen > 0; inlen--){
		sb[j++] ^= *in++;
		if(j >= (ulong)s->rate){
			keccakf(s->a);
			j = 0;
		}
	}
	s->pt = j;
}

/*
 * Finalize SHA3 hash (domain separator 0x06 for SHA3).
 */
static void
sha3_final(uchar *out, SHA3state *s)
{
	uchar *sb;
	int i;

	sb = (uchar*)s->a;
	sb[s->pt] ^= 0x06;		/* SHA3 domain separator */
	sb[s->rate - 1] ^= 0x80;	/* padding */
	keccakf(s->a);

	for(i = 0; i < s->mdlen; i++)
		out[i] = sb[i];
}

/*
 * Finalize SHAKE XOF (domain separator 0x1F for SHAKE).
 * After this, call sha3_squeeze() to extract output.
 */
static void
shake_finalize(SHA3state *s)
{
	uchar *sb;

	sb = (uchar*)s->a;
	sb[s->pt] ^= 0x1F;		/* SHAKE domain separator */
	sb[s->rate - 1] ^= 0x80;	/* padding */
	keccakf(s->a);
	s->pt = 0;
}

/*
 * Squeeze output from SHAKE XOF.
 * May be called multiple times after shake_finalize().
 */
static void
sha3_squeeze_internal(SHA3state *s, uchar *out, ulong outlen)
{
	uchar *sb;
	ulong j;

	sb = (uchar*)s->a;
	j = s->pt;
	for(; outlen > 0; outlen--){
		if(j >= (ulong)s->rate){
			keccakf(s->a);
			j = 0;
		}
		*out++ = sb[j++];
	}
	s->pt = j;
}

/*
 * Public API: SHA3-256
 */
void
sha3_256(uchar *in, ulong inlen, uchar out[32])
{
	SHA3state s;

	sha3_init(&s, 136, 32);
	sha3_update(&s, in, inlen);
	sha3_final(out, &s);
}

/*
 * Public API: SHA3-512
 */
void
sha3_512(uchar *in, ulong inlen, uchar out[64])
{
	SHA3state s;

	sha3_init(&s, 72, 64);
	sha3_update(&s, in, inlen);
	sha3_final(out, &s);
}

/*
 * Public API: SHAKE-128
 */
void
shake128_init(SHA3state *s)
{
	sha3_init(s, 168, 0);
}

void
shake128_absorb(SHA3state *s, const uchar *in, ulong inlen)
{
	sha3_update(s, in, inlen);
}

void
shake128_finalize(SHA3state *s)
{
	shake_finalize(s);
}

void
shake128_squeeze(SHA3state *s, uchar *out, ulong outlen)
{
	sha3_squeeze_internal(s, out, outlen);
}

/*
 * Public API: SHAKE-256
 */
void
shake256_init(SHA3state *s)
{
	sha3_init(s, 136, 0);
}

void
shake256_absorb(SHA3state *s, const uchar *in, ulong inlen)
{
	sha3_update(s, in, inlen);
}

void
shake256_finalize(SHA3state *s)
{
	shake_finalize(s);
}

void
shake256_squeeze(SHA3state *s, uchar *out, ulong outlen)
{
	sha3_squeeze_internal(s, out, outlen);
}

/*
 * Convenience: one-shot SHAKE-128
 */
void
shake128(const uchar *in, ulong inlen, uchar *out, ulong outlen)
{
	SHA3state s;

	shake128_init(&s);
	shake128_absorb(&s, in, inlen);
	shake128_finalize(&s);
	shake128_squeeze(&s, out, outlen);
}

/*
 * Convenience: one-shot SHAKE-256
 */
void
shake256(const uchar *in, ulong inlen, uchar *out, ulong outlen)
{
	SHA3state s;

	shake256_init(&s);
	shake256_absorb(&s, in, inlen);
	shake256_finalize(&s);
	shake256_squeeze(&s, out, outlen);
}
