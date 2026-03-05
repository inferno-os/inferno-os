/*
 * ML-KEM Number Theoretic Transform (FIPS 203)
 *
 * NTT and inverse NTT over Z_q where q = 3329.
 * All arithmetic is constant-time.
 *
 * Reference: FIPS 203, Section 4.3 (NTT and NTT^{-1}).
 */
#include "os.h"
#include <libsec.h>

/*
 * ML-KEM constants
 */
enum {
	MLKEM_Q = 3329,
	MLKEM_N = 256,
	MLKEM_QINV = 62209,	/* q^{-1} mod 2^16 */
	MLKEM_MONT = 2285,	/* 2^16 mod q */
	MLKEM_HALF_Q = 1665,	/* (q-1)/2 */
};

/*
 * Precomputed zetas (powers of primitive 256th root of unity mod q).
 * zeta = 17 is a primitive 256th root of unity mod 3329.
 * Table: zetas[i] = 17^(brv(i)) * 2^16 mod q  (Montgomery form)
 */
static const int16 mlkem_zetas[128] = {
	 2285, 2571, 2970, 1812, 1493, 1422,  287,  202,
	 3158,  622, 1577,  182,  962, 2127, 1855, 1468,
	  573, 2004,  264,  383, 2500, 1458, 1727, 3199,
	 2648, 1017,  732,  608, 1787,  411, 3124, 1758,
	 1223,  652, 2777, 1015, 2036, 1491, 3047, 1785,
	  516, 3321, 3009, 2663, 1711, 2167,  126, 1469,
	 2476, 3239, 3058,  830,  107, 1908, 3082, 2378,
	 2931,  961, 1821, 2604,  448, 2264,  677, 2054,
	 2226,  430,  555,  843, 2078,  871, 1550,  105,
	  422,  587,  177, 3094, 3038, 2869, 1574, 1653,
	 3083,  778, 1159, 3182, 2552, 1483, 2727, 1119,
	 1739,  644, 2457,  349,  418,  329, 3173, 3254,
	  817, 1097,  603,  610, 1322, 2044, 1864,  384,
	 2114, 3193, 1218, 1994, 2455,  220, 2142, 1670,
	 2144, 1799, 2051,  794, 1819, 2475, 2459,  478,
	 3221, 3021,  996,  991,  958, 1869, 1522, 1628,
};

/*
 * Barrett reduction: compute a mod q for |a| < 2^15 * q.
 * Returns r in [0, q) such that r ≡ a (mod q).
 */
int16
mlkem_barrett_reduce(int16 a)
{
	int16 t;
	int32 v;

	/* v = round(2^26 / q) = 20159 */
	v = 20159;
	t = (int16)((v * (int32)a + (1 << 25)) >> 26);
	t *= MLKEM_Q;
	return a - t;
}

/*
 * Montgomery reduction: given a 32-bit integer a, compute
 * a * 2^{-16} mod q.
 */
int16
mlkem_montgomery_reduce(int32 a)
{
	int16 t;

	t = (int16)((int16)a * (int16)MLKEM_QINV);
	t = (int16)((a - (int32)t * MLKEM_Q) >> 16);
	return t;
}

/*
 * Conditional subtraction of q.
 * If a >= q, returns a - q; else returns a.
 */
int16
mlkem_cond_sub_q(int16 a)
{
	a -= MLKEM_Q;
	a += (a >> 15) & MLKEM_Q;
	return a;
}

/*
 * Forward NTT (in-place, Cooley-Tukey butterfly).
 *
 * Input: polynomial coefficients r[0..255] in normal order.
 * Output: NTT representation.
 *
 * After NTT, pointwise multiplication can be used.
 */
void
mlkem_ntt(int16 r[MLKEM_N])
{
	int len, start, j, k;
	int16 t, zeta;

	k = 1;
	for(len = 128; len >= 2; len >>= 1){
		for(start = 0; start < MLKEM_N; start += 2*len){
			zeta = mlkem_zetas[k++];
			for(j = start; j < start + len; j++){
				t = mlkem_montgomery_reduce((int32)zeta * r[j + len]);
				r[j + len] = r[j] - t;
				r[j] = r[j] + t;
			}
		}
	}
}

/*
 * Inverse NTT (in-place, Gentleman-Sande butterfly).
 *
 * Input: NTT representation.
 * Output: polynomial coefficients (not yet reduced by Montgomery factor).
 *
 * The output needs to be multiplied by N^{-1} = 3303 (Montgomery form).
 */
void
mlkem_invntt(int16 r[MLKEM_N])
{
	int len, start, j, k;
	int16 t, zeta;
	static const int16 f = 1441;	/* 128^{-1} * 2^16 mod q */

	k = 127;
	for(len = 2; len <= 128; len <<= 1){
		for(start = 0; start < MLKEM_N; start += 2*len){
			zeta = mlkem_zetas[k--];
			for(j = start; j < start + len; j++){
				t = r[j];
				r[j] = mlkem_barrett_reduce(t + r[j + len]);
				r[j + len] = mlkem_montgomery_reduce(
					(int32)zeta * (r[j + len] - t));
			}
		}
	}
	for(j = 0; j < MLKEM_N; j++)
		r[j] = mlkem_montgomery_reduce((int32)f * r[j]);
}

/*
 * Basemul: multiply two NTT-domain elements in Z_q[X]/(X^2 - zeta).
 * Computes r = a * b in each degree-2 quotient ring.
 */
void
mlkem_basemul(int16 r[2], const int16 a[2], const int16 b[2], int16 zeta)
{
	r[0] = mlkem_montgomery_reduce((int32)a[1] * b[1]);
	r[0] = mlkem_montgomery_reduce((int32)r[0] * zeta);
	r[0] += mlkem_montgomery_reduce((int32)a[0] * b[0]);

	r[1] = mlkem_montgomery_reduce((int32)a[0] * b[1]);
	r[1] += mlkem_montgomery_reduce((int32)a[1] * b[0]);
}

/*
 * Pointwise multiplication of two NTT-domain polynomials.
 * Uses basemul for each pair of coefficients.
 */
void
mlkem_poly_basemul(int16 r[MLKEM_N], const int16 a[MLKEM_N], const int16 b[MLKEM_N])
{
	int i;

	for(i = 0; i < MLKEM_N/4; i++){
		mlkem_basemul(&r[4*i],   &a[4*i],   &b[4*i],   mlkem_zetas[64 + i]);
		mlkem_basemul(&r[4*i+2], &a[4*i+2], &b[4*i+2], -mlkem_zetas[64 + i]);
	}
}

/*
 * Add two polynomials coefficient-wise.
 */
void
mlkem_poly_add(int16 r[MLKEM_N], const int16 a[MLKEM_N], const int16 b[MLKEM_N])
{
	int i;

	for(i = 0; i < MLKEM_N; i++)
		r[i] = a[i] + b[i];
}

/*
 * Subtract two polynomials coefficient-wise.
 */
void
mlkem_poly_sub(int16 r[MLKEM_N], const int16 a[MLKEM_N], const int16 b[MLKEM_N])
{
	int i;

	for(i = 0; i < MLKEM_N; i++)
		r[i] = a[i] - b[i];
}

/*
 * Reduce all coefficients of a polynomial mod q.
 */
void
mlkem_poly_reduce(int16 r[MLKEM_N])
{
	int i;

	for(i = 0; i < MLKEM_N; i++)
		r[i] = mlkem_barrett_reduce(r[i]);
}

/*
 * Convert polynomial to standard form: all coefficients in [0, q).
 */
void
mlkem_poly_normalize(int16 r[MLKEM_N])
{
	int i;

	mlkem_poly_reduce(r);
	for(i = 0; i < MLKEM_N; i++){
		/* Barrett reduce gives (-q, q); make non-negative first */
		r[i] += (r[i] >> 15) & MLKEM_Q;
		/* Now in [0, 2q); subtract q if >= q */
		r[i] = mlkem_cond_sub_q(r[i]);
	}
}
