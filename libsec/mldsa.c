/*
 * ML-DSA Digital Signature Algorithm (FIPS 204)
 *
 * Implements ML-DSA-65 (NIST Level 3) and ML-DSA-87 (NIST Level 5).
 * Based on the Module Learning With Errors / Short Integer Solution
 * (MLWE/MSIS) problems.
 *
 * Working state is heap-allocated to avoid stack overflow in the
 * Inferno emulator's 32KB thread stacks.
 *
 * Reference: NIST FIPS 204 "Module-Lattice-Based Digital Signature
 * Standard" (August 2024).
 */
#include "os.h"
#include <libsec.h>

enum {
	MLDSA_N = 256,
	MLDSA_Q = 8380417,
	MLDSA_D = 13,	/* dropped bits from t */

	/* ML-DSA-65 parameters */
	MLDSA65_K = 6,
	MLDSA65_L = 5,
	MLDSA65_ETA = 4,
	MLDSA65_TAU = 49,
	MLDSA65_BETA = 196,		/* tau * eta */
	MLDSA65_GAMMA1 = (1 << 19),
	MLDSA65_GAMMA2 = (MLDSA_Q - 1) / 32,	/* 261888 */
	MLDSA65_OMEGA = 55,
	MLDSA65_CTILDELEN = 48,

	/* ML-DSA-87 parameters */
	MLDSA87_K = 8,
	MLDSA87_L = 7,
	MLDSA87_ETA = 2,
	MLDSA87_TAU = 60,
	MLDSA87_BETA = 120,		/* tau * eta */
	MLDSA87_GAMMA1 = (1 << 19),
	MLDSA87_GAMMA2 = (MLDSA_Q - 1) / 32,	/* 261888 */
	MLDSA87_OMEGA = 75,
	MLDSA87_CTILDELEN = 64,

	MLDSA_MAXK = 8,
	MLDSA_MAXL = 7,
};

/* Forward declarations for poly operations (mldsa_poly.c) */
extern void	mldsa_poly_uniform(int32 r[MLDSA_N], const uchar rho[32], uchar i, uchar j);
extern void	mldsa_poly_uniform_eta(int32 r[MLDSA_N], const uchar rhoprime[64], u16int nonce, int eta);
extern void	mldsa_poly_uniform_gamma1(int32 r[MLDSA_N], const uchar seed[64], u16int nonce, int gamma1_bits);
extern void	mldsa_poly_pack_t1(uchar *out, const int32 r[MLDSA_N]);
extern void	mldsa_poly_unpack_t1(int32 r[MLDSA_N], const uchar *in);
extern void	mldsa_poly_pack_t0(uchar *out, const int32 r[MLDSA_N]);
extern void	mldsa_poly_unpack_t0(int32 r[MLDSA_N], const uchar *in);
extern int	mldsa_poly_chknorm(const int32 r[MLDSA_N], int32 bound);
extern void	mldsa_power2round(int32 *a1, int32 *a0, int32 a);
extern int32	mldsa_highbits(int32 a, int32 gamma2);
extern int32	mldsa_lowbits(int32 a, int32 gamma2);
extern int	mldsa_makehint(int32 z, int32 r, int32 gamma2);
extern int32	mldsa_usehint(int32 h, int32 a, int32 gamma2);
extern void	mldsa_poly_pack_eta(uchar *out, const int32 r[MLDSA_N], int eta);
extern void	mldsa_poly_unpack_eta(int32 r[MLDSA_N], const uchar *in, int eta);
extern int	mldsa_pack_hint(uchar *out, int outlen, const int32 h[][MLDSA_N], int k, int omega);
extern int	mldsa_unpack_hint(int32 h[][MLDSA_N], int k, const uchar *in, int omega);

/*
 * Sample challenge polynomial c with exactly tau +/-1 coefficients.
 */
static void
sample_challenge(int32 c[MLDSA_N], const uchar *seed, int seedlen, int tau)
{
	SHA3state s;
	uchar buf[8];
	u64int signs;
	int i, b, pos;

	memset(c, 0, MLDSA_N * sizeof(int32));

	shake256_init(&s);
	shake256_absorb(&s, seed, seedlen);
	shake256_finalize(&s);

	/* First 8 bytes encode sign bits */
	shake256_squeeze(&s, buf, 8);
	signs = 0;
	for(i = 0; i < 8; i++)
		signs |= (u64int)buf[i] << (8*i);

	for(i = MLDSA_N - tau; i < MLDSA_N; i++){
		/* Sample j uniform in [0, i] */
		do {
			shake256_squeeze(&s, buf, 1);
			b = buf[0];
		} while(b > i);

		pos = b;
		c[i] = c[pos];
		c[pos] = 1 - 2 * (int32)(signs & 1);
		signs >>= 1;
	}
}

/*
 * Matrix-vector multiplication in NTT domain: t = A * s
 * A is k x l, s is l-vector, t is k-vector.
 * Uses heap-allocated temporaries to avoid stack overflow.
 */
static void
matvec_mul_dsa(int32 t[][MLDSA_N],
	const uchar rho[32], int k, int l,
	int32 s[][MLDSA_N])
{
	int i, j;
	int32 *a_ij, *tmp;

	a_ij = malloc(MLDSA_N * sizeof(int32));
	tmp = malloc(MLDSA_N * sizeof(int32));
	if(a_ij == nil || tmp == nil){
		free(a_ij);
		free(tmp);
		return;
	}

	for(i = 0; i < k; i++){
		mldsa_poly_uniform(a_ij, rho, (uchar)i, 0);
		mldsa_poly_pointwise(t[i], a_ij, s[0]);

		for(j = 1; j < l; j++){
			mldsa_poly_uniform(a_ij, rho, (uchar)i, (uchar)j);
			mldsa_poly_pointwise(tmp, a_ij, s[j]);
			mldsa_poly_add(t[i], t[i], tmp);
		}
		mldsa_poly_reduce(t[i]);
	}

	free(a_ij);
	free(tmp);
}

/*
 * Heap-allocated state for keygen to avoid stack overflow.
 */
typedef struct {
	int32	s1[MLDSA_MAXL][MLDSA_N];
	int32	s2[MLDSA_MAXK][MLDSA_N];
	int32	t[MLDSA_MAXK][MLDSA_N];
	int32	t1[MLDSA_N];
	int32	t0[MLDSA_N];
} MLDSAKeygenState;

/*
 * ML-DSA.KeyGen: Key generation.
 * Algorithm 1 in FIPS 204.
 */
static int
mldsa_keygen_internal(uchar *pk, uchar *sk,
	int k, int l, int eta)
{
	MLDSAKeygenState *st;
	uchar seed[32], buf[128];
	uchar rho[32], rhoprime[64], K[32];
	int i, j;
	u16int nonce;
	int pkoff, skoff, eta_bytes;

	st = malloc(sizeof(MLDSAKeygenState));
	if(st == nil)
		return -1;

	/* Random seed */
	genrandom(seed, 32);

	/* (rho, rhoprime, K) = H(seed || k || l) */
	{
		SHA3state hs;
		uchar kl[2];

		kl[0] = (uchar)k;
		kl[1] = (uchar)l;
		shake256_init(&hs);
		shake256_absorb(&hs, seed, 32);
		shake256_absorb(&hs, kl, 2);
		shake256_finalize(&hs);
		shake256_squeeze(&hs, buf, 128);
	}
	memmove(rho, buf, 32);
	memmove(rhoprime, buf+32, 64);
	memmove(K, buf+96, 32);

	/* Sample s1 (l polynomials) and s2 (k polynomials) */
	nonce = 0;
	for(i = 0; i < l; i++)
		mldsa_poly_uniform_eta(st->s1[i], rhoprime, nonce++, eta);
	for(i = 0; i < k; i++)
		mldsa_poly_uniform_eta(st->s2[i], rhoprime, nonce++, eta);

	/* Pack s1, s2 into sk BEFORE NTT (eta-dependent bit packing) */
	eta_bytes = (eta == 4) ? 128 : 96;
	skoff = 128;	/* skip rho(32) + K(32) + tr(64) header */
	for(i = 0; i < l; i++){
		mldsa_poly_pack_eta(sk + skoff, st->s1[i], eta);
		skoff += eta_bytes;
	}
	for(i = 0; i < k; i++){
		mldsa_poly_pack_eta(sk + skoff, st->s2[i], eta);
		skoff += eta_bytes;
	}

	/* NTT(s1) for matrix multiplication */
	for(i = 0; i < l; i++)
		mldsa_ntt(st->s1[i]);

	/* t = A * NTT(s1) */
	matvec_mul_dsa(st->t, rho, k, l, st->s1);

	/* t = INTT(t) + s2 */
	for(i = 0; i < k; i++){
		mldsa_invntt(st->t[i]);
		mldsa_poly_add(st->t[i], st->t[i], st->s2[i]);
		mldsa_poly_reduce(st->t[i]);
	}

	/* Power2Round: t = t1 * 2^d + t0 */
	/* Public key: pk = (rho || t1) */
	memmove(pk, rho, 32);
	pkoff = 32;

	for(i = 0; i < k; i++){
		for(j = 0; j < MLDSA_N; j++){
			int32 hi, lo;
			mldsa_power2round(&hi, &lo, st->t[i][j]);
			st->t1[j] = hi;
			st->t0[j] = lo;
		}
		mldsa_poly_pack_t1(pk + pkoff, st->t1);
		pkoff += 320;

		/* Pack t0 into sk */
		mldsa_poly_pack_t0(sk + skoff, st->t0);
		skoff += 416;
	}

	/* Fill sk header: rho || K || tr */
	{
		uchar tr[64];
		shake256((const uchar *)pk, pkoff, tr, 64);

		memmove(sk, rho, 32);
		memmove(sk + 32, K, 32);
		memmove(sk + 64, tr, 64);
	}

	/* Clear sensitive data */
	memset(seed, 0, sizeof(seed));
	memset(rhoprime, 0, sizeof(rhoprime));
	memset(K, 0, sizeof(K));
	memset(st, 0, sizeof(MLDSAKeygenState));
	free(st);

	return 0;
}

/*
 * Heap-allocated state for signing to avoid stack overflow.
 */
typedef struct {
	int32	s1[MLDSA_MAXL][MLDSA_N];
	int32	s2[MLDSA_MAXK][MLDSA_N];
	int32	t0[MLDSA_MAXK][MLDSA_N];
	int32	y[MLDSA_MAXL][MLDSA_N];
	int32	w[MLDSA_MAXK][MLDSA_N];
	int32	w1[MLDSA_MAXK][MLDSA_N];
	int32	z[MLDSA_MAXL][MLDSA_N];
	int32	c[MLDSA_N];
	int32	h[MLDSA_MAXK][MLDSA_N];
	int32	yhat[MLDSA_MAXL][MLDSA_N];
	int32	chat[MLDSA_N];
	int32	tmp[MLDSA_N];
	int32	tmp2[MLDSA_N];
} MLDSASignState;

/*
 * ML-DSA.Sign: Signature generation.
 * Algorithm 2 in FIPS 204.
 */
static int
mldsa_sign_internal(uchar *sig, const uchar *msg, ulong msglen,
	const uchar *sk, int k, int l, int eta, int tau, int32 beta,
	int gamma1_bits, int32 gamma2, int omega, int ctildelen)
{
	MLDSASignState *st;
	uchar rho[32], K[32], tr[64];
	uchar mu[64], rhoprime[64];
	uchar ctilde[64];
	int skoff, i, j;
	u16int kappa;
	int reject, hints_n;
	int sigoff, eta_bytes;

	st = malloc(sizeof(MLDSASignState));
	if(st == nil)
		return -1;

	/* Unpack secret key */
	eta_bytes = (eta == 4) ? 128 : 96;
	skoff = 0;
	memmove(rho, sk + skoff, 32); skoff += 32;
	memmove(K, sk + skoff, 32); skoff += 32;
	memmove(tr, sk + skoff, 64); skoff += 64;

	for(i = 0; i < l; i++){
		mldsa_poly_unpack_eta(st->s1[i], sk + skoff, eta);
		skoff += eta_bytes;
	}
	for(i = 0; i < k; i++){
		mldsa_poly_unpack_eta(st->s2[i], sk + skoff, eta);
		skoff += eta_bytes;
	}
	for(i = 0; i < k; i++){
		mldsa_poly_unpack_t0(st->t0[i], sk + skoff);
		skoff += 416;
	}

	/* mu = H(tr || msg) */
	{
		SHA3state hs;
		shake256_init(&hs);
		shake256_absorb(&hs, tr, 64);
		shake256_absorb(&hs, msg, msglen);
		shake256_finalize(&hs);
		shake256_squeeze(&hs, mu, 64);
	}

	/* rhoprime = H(K || mu) for deterministic signing */
	{
		SHA3state hs;
		shake256_init(&hs);
		shake256_absorb(&hs, K, 32);
		shake256_absorb(&hs, mu, 64);
		shake256_finalize(&hs);
		shake256_squeeze(&hs, rhoprime, 64);
	}

	/* NTT(s1), NTT(s2), NTT(t0) for later use */
	for(i = 0; i < l; i++)
		mldsa_ntt(st->s1[i]);
	for(i = 0; i < k; i++){
		mldsa_ntt(st->s2[i]);
		mldsa_ntt(st->t0[i]);
	}

	/* Rejection sampling loop */
	kappa = 0;
	for(;;){
		/* Sample y */
		for(i = 0; i < l; i++)
			mldsa_poly_uniform_gamma1(st->y[i], rhoprime, kappa + (u16int)i, gamma1_bits);
		kappa += (u16int)l;

		/* w = A * NTT(y) */
		for(i = 0; i < l; i++){
			memmove(st->yhat[i], st->y[i], sizeof(st->y[i]));
			mldsa_ntt(st->yhat[i]);
		}
		matvec_mul_dsa(st->w, rho, k, l, st->yhat);

		for(i = 0; i < k; i++){
			mldsa_invntt(st->w[i]);
			mldsa_poly_reduce(st->w[i]);
		}

		/* w1 = HighBits(w) */
		for(i = 0; i < k; i++)
			for(j = 0; j < MLDSA_N; j++)
				st->w1[i][j] = mldsa_highbits(st->w[i][j], gamma2);

		/* ctilde = H(mu || w1_encoded) */
		{
			SHA3state hs;
			uchar w1_byte;

			shake256_init(&hs);
			shake256_absorb(&hs, mu, 64);
			for(i = 0; i < k; i++)
				for(j = 0; j < MLDSA_N; j++){
					w1_byte = (uchar)(st->w1[i][j] & 0xFF);
					shake256_absorb(&hs, &w1_byte, 1);
				}
			shake256_finalize(&hs);
			shake256_squeeze(&hs, ctilde, ctildelen);
		}

		/* c = SampleInBall(ctilde) */
		sample_challenge(st->c, ctilde, ctildelen, tau);

		/* z = y + c * s1 (NTT domain) */
		memmove(st->chat, st->c, sizeof(st->c));
		mldsa_ntt(st->chat);

		reject = 0;
		for(i = 0; i < l; i++){
			mldsa_poly_pointwise(st->tmp, st->chat, st->s1[i]);
			mldsa_invntt(st->tmp);
			mldsa_poly_add(st->z[i], st->y[i], st->tmp);
			mldsa_poly_reduce(st->z[i]);
		}

		/* Check ||z||_inf < gamma1 - beta */
		for(i = 0; i < l; i++)
			reject |= mldsa_poly_chknorm(st->z[i], (1 << gamma1_bits) - beta);

		if(reject)
			continue;

		/* r0 = LowBits(w - c*s2) */
		/* Check ||r0||_inf < gamma2 - beta */
		for(i = 0; i < k; i++){
			mldsa_poly_pointwise(st->tmp2, st->chat, st->s2[i]);
			mldsa_invntt(st->tmp2);
			mldsa_poly_sub(st->tmp, st->w[i], st->tmp2);
			mldsa_poly_reduce(st->tmp);
			for(j = 0; j < MLDSA_N; j++){
				int32 r0 = mldsa_lowbits(st->tmp[j], gamma2);
				if(r0 < 0) r0 = -r0;
				if(r0 >= gamma2 - beta){
					reject = 1;
					break;
				}
			}
			if(reject) break;
		}
		if(reject)
			continue;

		/* Compute hints */
		hints_n = 0;
		for(i = 0; i < k; i++){
			mldsa_poly_pointwise(st->tmp2, st->chat, st->t0[i]);
			mldsa_invntt(st->tmp2);

			/* Check ||ct0||_inf < gamma2 */
			if(mldsa_poly_chknorm(st->tmp2, gamma2)){
				reject = 1;
				break;
			}

			/* w - cs2 + ct0 */
			{
				int32 *cs2 = st->tmp;
				mldsa_poly_pointwise(cs2, st->chat, st->s2[i]);
				mldsa_invntt(cs2);
				mldsa_poly_sub(st->tmp, st->w[i], cs2);
				mldsa_poly_add(st->tmp, st->tmp, st->tmp2);
				mldsa_poly_reduce(st->tmp);
			}

			for(j = 0; j < MLDSA_N; j++){
				st->h[i][j] = mldsa_makehint(-st->tmp2[j], st->tmp[j], gamma2);
				hints_n += st->h[i][j];
			}
		}
		if(reject)
			continue;

		if(hints_n > omega)
			continue;

		break;	/* Success! */
	}

	/* Pack signature: (ctilde || z || hints) */
	sigoff = 0;
	memmove(sig + sigoff, ctilde, ctildelen);
	sigoff += ctildelen;

	/* Pack z: gamma1_bits+1 bits per coefficient */
	for(i = 0; i < l; i++){
		if(gamma1_bits == 17){
			for(j = 0; j < MLDSA_N/4; j++){
				u32int t[4];
				int jj;
				for(jj = 0; jj < 4; jj++)
					t[jj] = (u32int)((1 << 17) - st->z[i][4*j+jj]);
				sig[sigoff+0] = (uchar)t[0];
				sig[sigoff+1] = (uchar)((t[0]>>8) | (t[1]<<2));
				sig[sigoff+2] = (uchar)((t[1]>>6) | (t[2]<<4));
				sig[sigoff+3] = (uchar)((t[2]>>4) | (t[3]<<6));
				sig[sigoff+4] = (uchar)(t[3]>>2);
				sig[sigoff+5] = (uchar)((t[0]>>16) | (t[1]>>14<<2));
				sig[sigoff+6] = (uchar)((t[1]>>14) | (t[2]>>12<<4));
				sig[sigoff+7] = (uchar)((t[2]>>12) | (t[3]>>10<<6));
				sig[sigoff+8] = (uchar)(t[3]>>10);
				sigoff += 9;
			}
		} else {
			/* gamma1_bits == 19: 20-bit packing */
			for(j = 0; j < MLDSA_N/2; j++){
				u32int t0v, t1v;
				t0v = (u32int)((1 << 19) - st->z[i][2*j+0]);
				t1v = (u32int)((1 << 19) - st->z[i][2*j+1]);
				sig[sigoff+0] = (uchar)t0v;
				sig[sigoff+1] = (uchar)(t0v>>8);
				sig[sigoff+2] = (uchar)((t0v>>16) | (t1v<<4));
				sig[sigoff+3] = (uchar)(t1v>>4);
				sig[sigoff+4] = (uchar)(t1v>>12);
				sigoff += 5;
			}
		}
	}

	/* Pack hints */
	mldsa_pack_hint(sig + sigoff, omega + k, st->h, k, omega);

	/* Clear sensitive data */
	memset(K, 0, sizeof(K));
	memset(rhoprime, 0, sizeof(rhoprime));
	memset(st, 0, sizeof(MLDSASignState));
	free(st);

	return 0;
}

/*
 * Heap-allocated state for verification.
 */
typedef struct {
	int32	t1[MLDSA_MAXK][MLDSA_N];
	int32	z[MLDSA_MAXL][MLDSA_N];
	int32	c[MLDSA_N];
	int32	h[MLDSA_MAXK][MLDSA_N];
	int32	w1prime[MLDSA_MAXK][MLDSA_N];
	int32	zhat[MLDSA_MAXL][MLDSA_N];
	int32	chat[MLDSA_N];
	int32	tmp[MLDSA_N];
} MLDSAVerifyState;

/*
 * ML-DSA.Verify: Signature verification.
 * Algorithm 3 in FIPS 204.
 */
static int
mldsa_verify_internal(const uchar *sig, const uchar *msg, ulong msglen,
	const uchar *pk, int k, int l, int eta, int tau, int32 beta,
	int gamma1_bits, int32 gamma2, int omega, int ctildelen, int siglen)
{
	MLDSAVerifyState *st;
	uchar rho[32];
	uchar mu[64], tr[64];
	const uchar *ctilde;
	uchar ctilde2[64];
	int pkoff, sigoff, i, j;
	int result;

	USED(eta);
	USED(siglen);

	st = malloc(sizeof(MLDSAVerifyState));
	if(st == nil)
		return 0;

	/* Unpack public key */
	memmove(rho, pk, 32);
	pkoff = 32;
	for(i = 0; i < k; i++){
		mldsa_poly_unpack_t1(st->t1[i], pk + pkoff);
		pkoff += 320;
	}

	/* tr = H(pk) */
	shake256((const uchar *)pk, pkoff, tr, 64);

	/* mu = H(tr || msg) */
	{
		SHA3state hs;
		shake256_init(&hs);
		shake256_absorb(&hs, tr, 64);
		shake256_absorb(&hs, msg, msglen);
		shake256_finalize(&hs);
		shake256_squeeze(&hs, mu, 64);
	}

	/* Unpack signature: (ctilde || z || hints) */
	sigoff = 0;
	ctilde = sig + sigoff;
	sigoff += ctildelen;

	/* Unpack z */
	for(i = 0; i < l; i++){
		if(gamma1_bits == 19){
			for(j = 0; j < MLDSA_N/2; j++){
				u32int t0v, t1v;
				t0v  = (u32int)sig[sigoff+0];
				t0v |= (u32int)sig[sigoff+1] << 8;
				t0v |= ((u32int)sig[sigoff+2] & 0x0F) << 16;
				t1v  = (u32int)sig[sigoff+2] >> 4;
				t1v |= (u32int)sig[sigoff+3] << 4;
				t1v |= (u32int)sig[sigoff+4] << 12;
				t0v &= 0xFFFFF;
				t1v &= 0xFFFFF;
				st->z[i][2*j+0] = (1 << 19) - (int32)t0v;
				st->z[i][2*j+1] = (1 << 19) - (int32)t1v;
				sigoff += 5;
			}
		} else {
			/* gamma1_bits == 17: 18-bit unpacking */
			for(j = 0; j < MLDSA_N/4; j++){
				sigoff += 9;
			}
		}
	}

	/* Check ||z||_inf < gamma1 - beta */
	for(i = 0; i < l; i++)
		if(mldsa_poly_chknorm(st->z[i], (1 << gamma1_bits) - beta)){
			free(st);
			return 0;
		}

	/* Unpack hints */
	if(mldsa_unpack_hint(st->h, k, sig + sigoff, omega) < 0){
		free(st);
		return 0;
	}

	/* c = SampleInBall(ctilde) */
	sample_challenge(st->c, ctilde, ctildelen, tau);

	/* w1' = UseHint(h, A*NTT(z) - NTT(c)*NTT(t1*2^d)) */
	for(i = 0; i < l; i++){
		memmove(st->zhat[i], st->z[i], sizeof(st->z[i]));
		mldsa_ntt(st->zhat[i]);
	}
	memmove(st->chat, st->c, sizeof(st->c));
	mldsa_ntt(st->chat);

	/* Az = A * NTT(z) */
	matvec_mul_dsa(st->w1prime, rho, k, l, st->zhat);

	/* w1' = Az - c * t1 * 2^d */
	for(i = 0; i < k; i++){
		int32 *t1_scaled = st->tmp;
		for(j = 0; j < MLDSA_N; j++)
			t1_scaled[j] = st->t1[i][j] << MLDSA_D;
		mldsa_ntt(t1_scaled);
		mldsa_poly_pointwise(st->tmp, st->chat, t1_scaled);
		mldsa_poly_sub(st->w1prime[i], st->w1prime[i], st->tmp);
		mldsa_invntt(st->w1prime[i]);
		mldsa_poly_reduce(st->w1prime[i]);

		/* Apply hints */
		for(j = 0; j < MLDSA_N; j++)
			st->w1prime[i][j] = mldsa_usehint(st->h[i][j], st->w1prime[i][j], gamma2);
	}

	/* ctilde' = H(mu || w1'_encoded) */
	{
		SHA3state hs;
		uchar w1_byte;

		shake256_init(&hs);
		shake256_absorb(&hs, mu, 64);
		for(i = 0; i < k; i++)
			for(j = 0; j < MLDSA_N; j++){
				w1_byte = (uchar)(st->w1prime[i][j] & 0xFF);
				shake256_absorb(&hs, &w1_byte, 1);
			}
		shake256_finalize(&hs);
		shake256_squeeze(&hs, ctilde2, ctildelen);
	}

	/* Compare ctilde == ctilde' */
	{
		int diff = 0;
		for(i = 0; i < ctildelen; i++)
			diff |= ctilde[i] ^ ctilde2[i];
		result = (diff == 0);
	}

	free(st);
	return result;
}

/*
 * Public API: ML-DSA-65
 */

int
mldsa65_keygen(uchar *pk, uchar *sk)
{
	return mldsa_keygen_internal(pk, sk, MLDSA65_K, MLDSA65_L, MLDSA65_ETA);
}

int
mldsa65_sign(uchar *sig, const uchar *msg, ulong msglen, const uchar *sk)
{
	return mldsa_sign_internal(sig, msg, msglen, sk,
		MLDSA65_K, MLDSA65_L, MLDSA65_ETA, MLDSA65_TAU, MLDSA65_BETA,
		19, MLDSA65_GAMMA2, MLDSA65_OMEGA, MLDSA65_CTILDELEN);
}

int
mldsa65_verify(const uchar *sig, const uchar *msg, ulong msglen, const uchar *pk)
{
	return mldsa_verify_internal(sig, msg, msglen, pk,
		MLDSA65_K, MLDSA65_L, MLDSA65_ETA, MLDSA65_TAU, MLDSA65_BETA,
		19, MLDSA65_GAMMA2, MLDSA65_OMEGA, MLDSA65_CTILDELEN, MLDSA65_SIGLEN);
}

/*
 * Public API: ML-DSA-87
 */

int
mldsa87_keygen(uchar *pk, uchar *sk)
{
	return mldsa_keygen_internal(pk, sk, MLDSA87_K, MLDSA87_L, MLDSA87_ETA);
}

int
mldsa87_sign(uchar *sig, const uchar *msg, ulong msglen, const uchar *sk)
{
	return mldsa_sign_internal(sig, msg, msglen, sk,
		MLDSA87_K, MLDSA87_L, MLDSA87_ETA, MLDSA87_TAU, MLDSA87_BETA,
		19, MLDSA87_GAMMA2, MLDSA87_OMEGA, MLDSA87_CTILDELEN);
}

int
mldsa87_verify(const uchar *sig, const uchar *msg, ulong msglen, const uchar *pk)
{
	return mldsa_verify_internal(sig, msg, msglen, pk,
		MLDSA87_K, MLDSA87_L, MLDSA87_ETA, MLDSA87_TAU, MLDSA87_BETA,
		19, MLDSA87_GAMMA2, MLDSA87_OMEGA, MLDSA87_CTILDELEN, MLDSA87_SIGLEN);
}
