/*
 * ML-DSA Number Theoretic Transform (FIPS 204)
 *
 * NTT and inverse NTT over Z_q where q = 8380417.
 * All arithmetic is constant-time.
 *
 * Reference: FIPS 204, Section 8.2.
 */
#include "os.h"
#include <libsec.h>

enum {
	MLDSA_Q = 8380417,
	MLDSA_N = 256,
	MLDSA_QINV = 58728449,		/* q^{-1} mod 2^32 */
	MLDSA_MONT = 4193792,		/* 2^32 mod q */
};

/*
 * Precomputed zetas for ML-DSA NTT.
 * zeta = 1753 is a primitive 512th root of unity mod q.
 * Table: zetas[i] = 1753^(brv(i)) mod q (NOT in Montgomery form).
 */
static const int32 mldsa_zetas[256] = {
	       0,    25847, -2608894,  -518909,   237124,  -777960,  -876248,   466468,
	 1826347,  2353451,  -359251, -2091905,  3119733, -2884855,  3111497,  2680103,
	 2725464,  1024112, -1079900,  3585928,  -549488, -1119584,  2619752, -2108549,
	-2118186, -3859737, -1399561, -3277672,  1757237,   -19422,  4010497,   280005,
	 2706023,    95776,  3077325,  3530437, -1661693, -3592148, -2537516,  3915439,
	-3861115, -3043716,  3574422, -2867647,  3539968,  -300467,  2348700,  -539299,
	-1699267, -1643818,  3505694, -3821735,  3507263, -2140649, -1600420,  3699596,
	  811944,   531354,   954230,  3881043,  3900724, -2556880,  2071892, -2797779,
	-3930395, -1528703, -3677745, -3041255, -1452451,  3475950,  2176455, -1585221,
	-1257611,  1939314, -4083598, -1000202, -3190144, -3157330, -3632928,   126922,
	 3412210,  -983419,  2147896,  2715295, -2967645, -3693493,  -411027, -2477047,
	 -671102, -1228525,   -22981, -1308169,  -381987,  1349076,  1852771, -1430430,
	-3343383,   264944,   508951,  3097992,    44288, -1100098,   904516,  3958618,
	-3724342,    -8578,  1653064, -3249728,  2389356,  -210977,   759969, -1316856,
	  189548, -3553272,  3159746, -1851402, -2409325,  -177440,  1315589,  1341330,
	 1285669, -1584928,  -812732, -1439742, -3019102, -3881060, -3628969,  3839961,
	 2091667,  3407706,  2316500,  3817976, -3342478,  2244091, -2446433, -3562462,
	  266997,  2434439, -1235728,  3513181, -3520352, -3759364, -1197226, -3193378,
	  900702,  1859098,   909542,   819034,   495491, -1613174,   -43260,  -522500,
	 -655327, -3122442,  2031748,  3207046, -3556995,  -525098,  -768622, -3595838,
	  342297,   286988, -2437823,  4108315,  3437287, -3342277,  1735879,   203044,
	 2842341,  2691481, -2590150,  1265009,  4055324,  1247620,  2486353,  1595974,
	-3767016,  1250494,  2635921, -3548272, -2994039,  1869119,  1903435, -1050970,
	-1333058,  1237275, -3318210, -1430225,  -451100,  1312455,  3306115, -1962642,
	-1279661,  1917081, -2546312, -1374803,  1500165,   777191,  2235880,  3406031,
	 -542412, -2831860, -1671176, -1846953, -2584293, -3724270,   594136, -3776993,
	-2013608,  2432395,  2454455,  -164721,  1957272,  3369112,   185531, -1207385,
	-3183426,   162844,  1616392,  3014001,   810149,  1652634, -3694233, -1799107,
	-3038916,  3523897,  3866901,   269760,  2213111,  -975884,  1717735,   472078,
	 -426683,  1723600, -1803090,  1910376, -1667432, -1104333,  -260646, -3833893,
	-2939036, -2235985,  -420899, -2286327,   183443,  -976891,  1612842, -3545687,
	 -554416,  3919660,   -48306, -1362209,  3937738,  1400424,  -846154,  1976782,
};

/*
 * Barrett reduction for q = 8380417.
 * Returns r in (-q, q) such that r ≡ a (mod q) for |a| <= 2^31.
 *
 * Uses the approach from the pqcrystals reference implementation:
 * since q ≈ 2^23 (q = 8380417, 2^23 = 8388608), dividing by 2^23
 * approximates division by q with sufficient precision.
 */
int32
mldsa_barrett_reduce(int32 a)
{
	int32 t;

	t = (a + (1 << 22)) >> 23;
	t *= MLDSA_Q;
	return a - t;
}

/*
 * Montgomery reduction for q = 8380417.
 * Given a 64-bit integer a, compute a * 2^{-32} mod q.
 */
int32
mldsa_montgomery_reduce(int64 a)
{
	int32 t;

	t = (int32)((int32)a * (int32)MLDSA_QINV);
	t = (int32)((a - (int64)t * MLDSA_Q) >> 32);
	return t;
}

/*
 * Forward NTT (in-place, Cooley-Tukey butterfly).
 */
void
mldsa_ntt(int32 r[MLDSA_N])
{
	int len, start, j, k;
	int32 zeta, t;

	k = 0;
	for(len = 128; len >= 1; len >>= 1){
		for(start = 0; start < MLDSA_N; start += 2*len){
			zeta = mldsa_zetas[++k];
			for(j = start; j < start + len; j++){
				t = mldsa_montgomery_reduce((int64)zeta * r[j + len]);
				r[j + len] = r[j] - t;
				r[j] = r[j] + t;
			}
		}
	}
}

/*
 * Inverse NTT (in-place, Gentleman-Sande butterfly).
 */
void
mldsa_invntt(int32 r[MLDSA_N])
{
	int len, start, j, k;
	int32 zeta, t;
	static const int32 f = 41978;	/* Mont(128^{-1}) = 128^{-1} * 2^32 mod q */

	k = 256;
	for(len = 1; len <= 128; len <<= 1){
		for(start = 0; start < MLDSA_N; start += 2*len){
			zeta = -mldsa_zetas[--k];
			for(j = start; j < start + len; j++){
				t = r[j];
				r[j] = t + r[j + len];
				r[j + len] = t - r[j + len];
				r[j + len] = mldsa_montgomery_reduce((int64)zeta * r[j + len]);
			}
		}
	}
	for(j = 0; j < MLDSA_N; j++)
		r[j] = mldsa_montgomery_reduce((int64)f * r[j]);
}

/*
 * Pointwise multiplication of two NTT-domain polynomials.
 */
void
mldsa_poly_pointwise(int32 r[MLDSA_N], const int32 a[MLDSA_N], const int32 b[MLDSA_N])
{
	int i;

	for(i = 0; i < MLDSA_N; i++)
		r[i] = mldsa_montgomery_reduce((int64)a[i] * b[i]);
}

/*
 * Add two polynomials coefficient-wise.
 */
void
mldsa_poly_add(int32 r[MLDSA_N], const int32 a[MLDSA_N], const int32 b[MLDSA_N])
{
	int i;

	for(i = 0; i < MLDSA_N; i++)
		r[i] = a[i] + b[i];
}

/*
 * Subtract two polynomials coefficient-wise.
 */
void
mldsa_poly_sub(int32 r[MLDSA_N], const int32 a[MLDSA_N], const int32 b[MLDSA_N])
{
	int i;

	for(i = 0; i < MLDSA_N; i++)
		r[i] = a[i] - b[i];
}

/*
 * Reduce all coefficients mod q.
 */
void
mldsa_poly_reduce(int32 r[MLDSA_N])
{
	int i;

	for(i = 0; i < MLDSA_N; i++)
		r[i] = mldsa_barrett_reduce(r[i]);
}
