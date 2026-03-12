/*
 * ML-KEM Key Encapsulation Mechanism (FIPS 203)
 *
 * Implements ML-KEM-768 (NIST Level 3) and ML-KEM-1024 (NIST Level 5).
 * Based on the Module Learning With Errors (MLWE) problem.
 *
 * Adapted from the FIPS 203 reference implementation.
 * All operations are constant-time.
 *
 * Reference: NIST FIPS 203 "Module-Lattice-Based Key-Encapsulation
 * Mechanism Standard" (August 2024).
 */
#include "os.h"
#include <libsec.h>

enum {
	MLKEM_N = 256,
	MLKEM_Q = 3329,
	MLKEM_SYMBYTES = 32,

	/* ML-KEM-768 parameters */
	MLKEM768_K = 3,
	MLKEM768_ETA1 = 2,
	MLKEM768_ETA2 = 2,
	MLKEM768_DU = 10,
	MLKEM768_DV = 4,

	/* ML-KEM-1024 parameters */
	MLKEM1024_K = 4,
	MLKEM1024_ETA1 = 2,
	MLKEM1024_ETA2 = 2,
	MLKEM1024_DU = 11,
	MLKEM1024_DV = 5,

	MLKEM_MAXK = 4,	/* max k for stack allocation */
};

/* Forward declarations for NTT functions (mlkem_ntt.c) */
extern void	mlkem_ntt(int16 r[MLKEM_N]);
extern void	mlkem_invntt(int16 r[MLKEM_N]);
extern void	mlkem_poly_basemul(int16 r[MLKEM_N], const int16 a[MLKEM_N], const int16 b[MLKEM_N]);
extern void	mlkem_poly_add(int16 r[MLKEM_N], const int16 a[MLKEM_N], const int16 b[MLKEM_N]);
extern void	mlkem_poly_sub(int16 r[MLKEM_N], const int16 a[MLKEM_N], const int16 b[MLKEM_N]);
extern void	mlkem_poly_reduce(int16 r[MLKEM_N]);
extern void	mlkem_poly_normalize(int16 r[MLKEM_N]);
extern int16	mlkem_barrett_reduce(int16 a);
extern int16	mlkem_montgomery_reduce(int32 a);

/* Forward declarations for polynomial operations (mlkem_poly.c) */
extern void	mlkem_poly_sample_ntt(int16 r[MLKEM_N], const uchar seed[32], uchar x, uchar y);
extern void	mlkem_poly_sample_cbd(int16 r[MLKEM_N], const uchar seed[32], uchar nonce, int eta);
extern void	mlkem_poly_encode(uchar *out, const int16 r[MLKEM_N], int bits);
extern void	mlkem_poly_decode(int16 r[MLKEM_N], const uchar *in, int bits);
extern void	mlkem_poly_compress(int16 r[MLKEM_N], int d);
extern void	mlkem_poly_decompress(int16 r[MLKEM_N], int d);
extern void	mlkem_poly_tomont(int16 r[MLKEM_N]);

/*
 * Matrix-vector multiplication: t = A * s (in NTT domain).
 * A is a k x k matrix of polynomials; s is a k-vector.
 * Both A and s are in NTT domain.
 */
static void
matvec_mul(int16 t[][MLKEM_N], int16 a[][MLKEM_MAXK][MLKEM_N],
	int16 s[][MLKEM_N], int k)
{
	int i, j;
	int16 tmp[MLKEM_N];

	for(i = 0; i < k; i++){
		mlkem_poly_basemul(t[i], a[i][0], s[0]);
		for(j = 1; j < k; j++){
			mlkem_poly_basemul(tmp, a[i][j], s[j]);
			mlkem_poly_add(t[i], t[i], tmp);
		}
		mlkem_poly_reduce(t[i]);
	}
}

/*
 * Inner product of two k-vectors in NTT domain.
 */
static void
inner_product(int16 r[MLKEM_N], int16 a[][MLKEM_N],
	int16 b[][MLKEM_N], int k)
{
	int i;
	int16 tmp[MLKEM_N];

	mlkem_poly_basemul(r, a[0], b[0]);
	for(i = 1; i < k; i++){
		mlkem_poly_basemul(tmp, a[i], b[i]);
		mlkem_poly_add(r, r, tmp);
	}
	mlkem_poly_reduce(r);
}

/*
 * Heap-allocated state for CPAPKE keygen/encrypt to avoid
 * stack overflow in Inferno's 32KB thread stacks.
 */
typedef struct {
	int16	a[MLKEM_MAXK][MLKEM_MAXK][MLKEM_N];
	int16	s[MLKEM_MAXK][MLKEM_N];
	int16	e[MLKEM_MAXK][MLKEM_N];
	int16	t[MLKEM_MAXK][MLKEM_N];
} MLKEMKeygenState;

/*
 * K-PKE.KeyGen: Generate CPAPKE key pair.
 * Algorithm 4 in FIPS 203.
 */
static int
cpapke_keygen(uchar *pk, uchar *sk, const uchar seed[32], int k, int eta1)
{
	MLKEMKeygenState *st;
	uchar rho[32], sigma[32];
	uchar buf[64];
	int i, j;
	uchar nonce;

	st = malloc(sizeof(MLKEMKeygenState));
	if(st == nil)
		return -1;

	/* G(seed) = (rho, sigma) */
	sha3_512(seed, 32, buf);
	memmove(rho, buf, 32);
	memmove(sigma, buf+32, 32);

	/* Generate matrix A from rho (in NTT domain) */
	for(i = 0; i < k; i++)
		for(j = 0; j < k; j++)
			mlkem_poly_sample_ntt(st->a[i][j], rho, (uchar)j, (uchar)i);

	/* Sample secret s and error e from CBD */
	nonce = 0;
	for(i = 0; i < k; i++){
		mlkem_poly_sample_cbd(st->s[i], sigma, nonce, eta1);
		nonce++;
	}
	for(i = 0; i < k; i++){
		mlkem_poly_sample_cbd(st->e[i], sigma, nonce, eta1);
		nonce++;
	}

	/* NTT(s), NTT(e) */
	for(i = 0; i < k; i++){
		mlkem_ntt(st->s[i]);
		mlkem_ntt(st->e[i]);
	}

	/* t = A * s + e (in NTT domain) */
	matvec_mul(st->t, st->a, st->s, k);
	for(i = 0; i < k; i++){
		mlkem_poly_tomont(st->t[i]);
		mlkem_poly_add(st->t[i], st->t[i], st->e[i]);
	}

	/* Encode public key: pk = (t_encoded || rho) */
	for(i = 0; i < k; i++){
		mlkem_poly_normalize(st->t[i]);
		mlkem_poly_encode(pk + i * 384, st->t[i], 12);
	}
	memmove(pk + k * 384, rho, 32);

	/* Encode secret key: sk = s_encoded */
	for(i = 0; i < k; i++){
		mlkem_poly_normalize(st->s[i]);
		mlkem_poly_encode(sk + i * 384, st->s[i], 12);
	}

	/* Clear sensitive data */
	secureZero(sigma, sizeof(sigma));
	secureZero(st, sizeof(MLKEMKeygenState));
	free(st);
	return 0;
}

/*
 * Heap-allocated state for CPAPKE encryption.
 */
typedef struct {
	int16	a[MLKEM_MAXK][MLKEM_MAXK][MLKEM_N];
	int16	t[MLKEM_MAXK][MLKEM_N];
	int16	r[MLKEM_MAXK][MLKEM_N];
	int16	e1[MLKEM_MAXK][MLKEM_N];
	int16	e2[MLKEM_N];
	int16	u[MLKEM_MAXK][MLKEM_N];
	int16	v[MLKEM_N];
	int16	m[MLKEM_N];
} MLKEMEncState;

/*
 * K-PKE.Encrypt: CPAPKE encryption.
 * Algorithm 5 in FIPS 203.
 */
static int
cpapke_enc(uchar *ct, const uchar *pk, const uchar msg[32],
	const uchar coins[32], int k, int eta1, int eta2, int du, int dv)
{
	MLKEMEncState *st;
	uchar rho[32];
	int i, j;
	uchar nonce;
	int du_bytes, dv_bytes;

	st = malloc(sizeof(MLKEMEncState));
	if(st == nil)
		return -1;

	/* Decode public key */
	for(i = 0; i < k; i++)
		mlkem_poly_decode(st->t[i], pk + i * 384, 12);
	memmove(rho, pk + k * 384, 32);

	/* Regenerate matrix A from rho (same as keygen) */
	for(i = 0; i < k; i++)
		for(j = 0; j < k; j++)
			mlkem_poly_sample_ntt(st->a[i][j], rho, (uchar)j, (uchar)i);

	/* Sample r, e1, e2 */
	nonce = 0;
	for(i = 0; i < k; i++){
		mlkem_poly_sample_cbd(st->r[i], coins, nonce, eta1);
		nonce++;
	}
	for(i = 0; i < k; i++){
		mlkem_poly_sample_cbd(st->e1[i], coins, nonce, eta2);
		nonce++;
	}
	mlkem_poly_sample_cbd(st->e2, coins, nonce, eta2);
	nonce++;

	/* NTT(r) */
	for(i = 0; i < k; i++)
		mlkem_ntt(st->r[i]);

	/* u = A^T * r + e1 */
	/* Note: A^T means we swap i,j indices */
	for(i = 0; i < k; i++){
		int16 tmp[MLKEM_N];
		mlkem_poly_basemul(st->u[i], st->a[0][i], st->r[0]);
		for(j = 1; j < k; j++){
			mlkem_poly_basemul(tmp, st->a[j][i], st->r[j]);
			mlkem_poly_add(st->u[i], st->u[i], tmp);
		}
		mlkem_poly_reduce(st->u[i]);
		mlkem_invntt(st->u[i]);
		mlkem_poly_add(st->u[i], st->u[i], st->e1[i]);
	}

	/* v = t^T * r + e2 + Decompress(Decode(msg), 1) */
	/* First: NTT domain inner product t^T * r */
	inner_product(st->v, st->t, st->r, k);
	mlkem_invntt(st->v);
	mlkem_poly_add(st->v, st->v, st->e2);

	/* Decode message as polynomial */
	mlkem_poly_decode(st->m, msg, 1);
	mlkem_poly_decompress(st->m, 1);
	mlkem_poly_add(st->v, st->v, st->m);

	/* Compress and encode u */
	du_bytes = du * MLKEM_N / 8;
	for(i = 0; i < k; i++){
		mlkem_poly_compress(st->u[i], du);
		mlkem_poly_encode(ct + i * du_bytes, st->u[i], du);
	}

	/* Compress and encode v */
	dv_bytes = dv * MLKEM_N / 8;
	mlkem_poly_compress(st->v, dv);
	mlkem_poly_encode(ct + k * du_bytes, st->v, dv);

	/* Clear sensitive data */
	secureZero(st, sizeof(MLKEMEncState));
	free(st);
	return 0;
}

/*
 * K-PKE.Decrypt: CPAPKE decryption.
 * Algorithm 6 in FIPS 203.
 */
static void
cpapke_dec(uchar msg[32], const uchar *ct, const uchar *sk,
	int k, int du, int dv)
{
	int16 u[MLKEM_MAXK][MLKEM_N];
	int16 s[MLKEM_MAXK][MLKEM_N];
	int16 v[MLKEM_N];
	int16 w[MLKEM_N];
	int i;
	int du_bytes, dv_bytes;

	du_bytes = du * MLKEM_N / 8;
	dv_bytes = dv * MLKEM_N / 8;

	/* Decode and decompress u */
	for(i = 0; i < k; i++){
		mlkem_poly_decode(u[i], ct + i * du_bytes, du);
		mlkem_poly_decompress(u[i], du);
		mlkem_ntt(u[i]);
	}

	/* Decode and decompress v */
	mlkem_poly_decode(v, ct + k * du_bytes, dv);
	mlkem_poly_decompress(v, dv);

	/* Decode secret key s */
	for(i = 0; i < k; i++)
		mlkem_poly_decode(s[i], sk + i * 384, 12);

	/* w = v - s^T * NTT^{-1}(u) */
	inner_product(w, s, u, k);
	mlkem_invntt(w);
	mlkem_poly_sub(w, v, w);

	/* Compress to 1 bit and encode as message */
	mlkem_poly_compress(w, 1);
	mlkem_poly_encode(msg, w, 1);

	/* Clear sensitive data */
	secureZero(s, sizeof(s));
}

/*
 * Constant-time comparison of two byte arrays.
 * Returns 0 if equal, non-zero otherwise.
 */
static int
ct_memcmp(const uchar *a, const uchar *b, int len)
{
	int i;
	uchar diff;

	diff = 0;
	for(i = 0; i < len; i++)
		diff |= a[i] ^ b[i];
	return diff;
}

/*
 * Constant-time conditional move: if b != 0, copy src to dst.
 */
static void
ct_cmov(uchar *dst, const uchar *src, int len, uchar b)
{
	int i;
	uchar mask;

	/* b must be 0 or 1 */
	mask = -(uchar)(b != 0);
	for(i = 0; i < len; i++)
		dst[i] ^= mask & (dst[i] ^ src[i]);
}

/*
 * ML-KEM.KeyGen: Full key generation.
 * Algorithm 15 in FIPS 203.
 *
 * pk: public key (encapsulation key)
 * sk: secret key (decapsulation key)
 *
 * The secret key contains: (s || pk || H(pk) || z)
 * where z is a random value for implicit rejection.
 */
static int
mlkem_keygen_internal(uchar *pk, uchar *sk, int k, int eta1,
	int pklen, int sklen_inner)
{
	uchar seed[64];
	uchar h[32];
	int skoff;

	/* Random seed */
	genrandom(seed, 32);

	/* Additional randomness z for implicit rejection */
	genrandom(seed+32, 32);

	/* Generate CPAPKE key pair */
	if(cpapke_keygen(pk, sk, seed, k, eta1) != 0){
		secureZero(seed, sizeof(seed));
		return -1;
	}

	/* Full secret key: sk_cpapke || pk || H(pk) || z */
	skoff = sklen_inner;		/* after CPAPKE secret key */
	memmove(sk + skoff, pk, pklen);
	skoff += pklen;

	sha3_256(pk, pklen, h);
	memmove(sk + skoff, h, 32);
	skoff += 32;

	memmove(sk + skoff, seed+32, 32);	/* z */

	secureZero(seed, sizeof(seed));
	return 0;
}

/*
 * ML-KEM.Encaps: Encapsulation.
 * Algorithm 16 in FIPS 203.
 *
 * ct: ciphertext
 * ss: shared secret (32 bytes)
 * pk: public key
 */
static int
mlkem_encaps_internal(uchar *ct, uchar *ss, const uchar *pk,
	int k, int eta1, int eta2, int du, int dv, int pklen, int ctlen)
{
	uchar m[32], h[32];
	uchar g_input[64], g_output[64];
	uchar *Kbar, *r;

	/* Random message m */
	genrandom(m, 32);

	/* H(pk) */
	sha3_256(pk, pklen, h);

	/* (K, r) = G(m || H(pk)) */
	memmove(g_input, m, 32);
	memmove(g_input+32, h, 32);
	sha3_512(g_input, 64, g_output);
	Kbar = g_output;		/* first 32 bytes */
	r = g_output + 32;		/* second 32 bytes */

	/* ct = Encrypt(pk, m, r) */
	if(cpapke_enc(ct, pk, m, r, k, eta1, eta2, du, dv) != 0){
		secureZero(m, sizeof(m));
		secureZero(g_input, sizeof(g_input));
		secureZero(g_output, sizeof(g_output));
		return -1;
	}

	/* ss = K */
	memmove(ss, Kbar, 32);

	secureZero(m, sizeof(m));
	secureZero(g_input, sizeof(g_input));
	secureZero(g_output, sizeof(g_output));
	return 0;
}

/*
 * ML-KEM.Decaps: Decapsulation.
 * Algorithm 17 in FIPS 203.
 *
 * Implements implicit rejection: if the ciphertext is invalid,
 * returns a pseudorandom shared secret derived from z and ct,
 * rather than failing. This prevents chosen-ciphertext attacks.
 */
static int
mlkem_decaps_internal(uchar *ss, const uchar *ct, const uchar *sk,
	int k, int eta1, int eta2, int du, int dv,
	int pklen, int ctlen, int sklen_inner)
{
	const uchar *sk_cpapke, *pk, *hpk, *z;
	uchar m[32], g_input[64], g_output[64];
	uchar *Kbar, *r;
	uchar ct2[MLKEM1024_CTLEN];	/* max ciphertext size */
	uchar Krej[32];
	SHA3state js;
	int fail;

	/* Parse secret key: sk_cpapke || pk || H(pk) || z */
	sk_cpapke = sk;
	pk = sk + sklen_inner;
	hpk = pk + pklen;
	z = hpk + 32;

	/* m' = Decrypt(sk_cpapke, ct) */
	cpapke_dec(m, ct, sk_cpapke, k, du, dv);

	/* (K', r') = G(m' || H(pk)) */
	memmove(g_input, m, 32);
	memmove(g_input+32, hpk, 32);
	sha3_512(g_input, 64, g_output);
	Kbar = g_output;
	r = g_output + 32;

	/* ct' = Encrypt(pk, m', r') */
	if(cpapke_enc(ct2, pk, m, r, k, eta1, eta2, du, dv) != 0){
		secureZero(m, sizeof(m));
		secureZero(g_input, sizeof(g_input));
		secureZero(g_output, sizeof(g_output));
		secureZero(Krej, sizeof(Krej));
		return -1;
	}

	/* Implicit rejection: K_reject = J(z || ct) */
	shake256_init(&js);
	shake256_absorb(&js, z, 32);
	shake256_absorb(&js, ct, ctlen);
	shake256_finalize(&js);
	shake256_squeeze(&js, Krej, 32);

	/* Constant-time selection: if ct == ct', use Kbar; else use Krej */
	fail = ct_memcmp(ct, ct2, ctlen);
	ct_cmov(Kbar, Krej, 32, (uchar)(fail != 0));

	memmove(ss, Kbar, 32);

	secureZero(m, sizeof(m));
	secureZero(g_input, sizeof(g_input));
	secureZero(g_output, sizeof(g_output));
	secureZero(Krej, sizeof(Krej));
	secureZero(ct2, sizeof(ct2));
	return 0;
}

/*
 * Public API: ML-KEM-768
 */

int
mlkem768_keygen(uchar pk[MLKEM768_PKLEN], uchar sk[MLKEM768_SKLEN])
{
	return mlkem_keygen_internal(pk, sk, MLKEM768_K, MLKEM768_ETA1,
		MLKEM768_PKLEN, MLKEM768_K * 384);
}

int
mlkem768_encaps(uchar ct[MLKEM768_CTLEN], uchar ss[32], const uchar pk[MLKEM768_PKLEN])
{
	return mlkem_encaps_internal(ct, ss, pk, MLKEM768_K,
		MLKEM768_ETA1, MLKEM768_ETA2,
		MLKEM768_DU, MLKEM768_DV,
		MLKEM768_PKLEN, MLKEM768_CTLEN);
}

int
mlkem768_decaps(uchar ss[32], const uchar ct[MLKEM768_CTLEN], const uchar sk[MLKEM768_SKLEN])
{
	return mlkem_decaps_internal(ss, ct, sk, MLKEM768_K,
		MLKEM768_ETA1, MLKEM768_ETA2,
		MLKEM768_DU, MLKEM768_DV,
		MLKEM768_PKLEN, MLKEM768_CTLEN,
		MLKEM768_K * 384);
}

/*
 * Public API: ML-KEM-1024
 */

int
mlkem1024_keygen(uchar pk[MLKEM1024_PKLEN], uchar sk[MLKEM1024_SKLEN])
{
	return mlkem_keygen_internal(pk, sk, MLKEM1024_K, MLKEM1024_ETA1,
		MLKEM1024_PKLEN, MLKEM1024_K * 384);
}

int
mlkem1024_encaps(uchar ct[MLKEM1024_CTLEN], uchar ss[32], const uchar pk[MLKEM1024_PKLEN])
{
	return mlkem_encaps_internal(ct, ss, pk, MLKEM1024_K,
		MLKEM1024_ETA1, MLKEM1024_ETA2,
		MLKEM1024_DU, MLKEM1024_DV,
		MLKEM1024_PKLEN, MLKEM1024_CTLEN);
}

int
mlkem1024_decaps(uchar ss[32], const uchar ct[MLKEM1024_CTLEN], const uchar sk[MLKEM1024_SKLEN])
{
	return mlkem_decaps_internal(ss, ct, sk, MLKEM1024_K,
		MLKEM1024_ETA1, MLKEM1024_ETA2,
		MLKEM1024_DU, MLKEM1024_DV,
		MLKEM1024_PKLEN, MLKEM1024_CTLEN,
		MLKEM1024_K * 384);
}
