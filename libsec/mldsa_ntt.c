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
	       0, 25847, -2608894,  -518909, 237124,  -777960,  -876248,   466468,
	 1826347, 2353451,  -359251, -2091905, 3119733, -2884855,  3111497,  2680103,
	 2725464, 1024112, -1079900,  3585928, -549488, -1119584,  2619752, -2108549,
	-2118186, -3859737, -1399561, -3277672, 1757237,   -19422,  4010497,   280005,
	 2706023,   95776,  3077325,  3530437,-1661693, -3592106, -2537516,  3915439,
	-3861115, -3043716,  3574422, -2867647, 3539968, -300467,   2348700, -539299,
	-1699267, -1643818,  3505694, -3821735, 3507263, -2140649, -1600420,  3699596,
	  811944,   531354,   954230,  3881043, 3900724, -2556880,  2071892, -2797779,
	-3930395, -1528703, -3677745, -3041255,-1452451,  3475950,  2176455, -1585221,
	-1257611,  1939314, -4083598, -1000202,-3190144, -3## continuing partial table */
	  357540,  1843818,  -925157, -2142802,-3724868,  -174570,  1198719, -1398905,
	-3250266, -2812194, -3815725,  2809635,-1026610,   161527,   -31929, -2275770,
	 -915721, -2978632, -3291524,  2490817, 2291089,  2139498,   297878, -2297100,
	 -311038, -1144548,  1904893, -2478432,-3354910, -2243389, -2777771,  1808005,
	-2126526,  1167676,   344396, -2782583, 653797,   397657,  -1900783, -1709506,
	 -346240,  -810837, -1364032,  -269549, 3929906,  2299014,   685005,   750918,
	 -737225,  2455674,  2489497, -2887157,-3025326, -1556224,  3549571,  -536247,
	 -257761,  -111378,  -949437,  2903371,-3908292,  -393746,  2541963,  -310891,
	 2009922, -1039416,  2210292,  -777714,-2399880,  1767825,   535698, -3261102,
	 3732042,  2154645, -1709437, -3281754, 3932056,   354595,  -597587, -1174053,
	 1104741,   -96645,  2758372,  1758150, 2394514,  -972506, -3614460, -1698048,
	 -260838,  1676355,  -267283,  -290971, 3282913,  1697934,   753539, -3283061,
	 -423195,  1040478,  -823709,  -252218,-2289699, -3199750, -2020731,  1421463,
	-2326728,  1178360,  -365147,  1449347, 1843003,   -906561,   -18588, 3838383,
	  -94254,  1757610,  -549026, -2662583,-1783442,  2100378,   397178, -2198321,
	-1222960, -1631154,  -773738,  -153500,-2217235,   605987,   766915,  -399679,
	   23753,  2765260,  2759265,  2100775,-1783974,   -73863, -3009558, -3131461,
	  133116,  -162973,  -538368,  -373994, 1032726,    63481,    -22522, -1063110,
	 2508980,   276756,  -227093,  1085187,-2362628,  2134572, -2147801, -1777846,
	  407880, -3096296,  1835011, -1641785,-3428058,  3098167,  -284532,  1108145,
	 2194472,  -838934, -2038900, -3024413,-2013908,  2825503,  -994731,  1568710,
	-1505587,  -308785, -1316706,  1023737, 3816714,   -836773, -3362783,  -395544,
};

/*
 * Barrett reduction for q = 8380417.
 * Returns r in (-q, q) such that r ≡ a (mod q) for |a| <= 2^31.
 */
int32
mldsa_barrett_reduce(int32 a)
{
	int32 t;
	int64 v;

	/* v = round(2^47 / q) */
	v = 16777259;	/* 2^47 / q rounded */
	t = (int32)(((int64)a * v + ((int64)1 << 46)) >> 47);
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
