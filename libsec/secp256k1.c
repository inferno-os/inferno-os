/*
 * secp256k1 ECDSA (Ethereum/Bitcoin).
 * Uses 64-bit limbs with __int128 for intermediate products.
 *
 * Field arithmetic over GF(p) where p = 2^256 - 2^32 - 977.
 * Curve: y^2 = x^3 + 7 (a = 0, b = 7).
 * Point multiplication uses a constant-time Montgomery ladder in Jacobian coordinates.
 * ECDSA scalar arithmetic uses libmp's mpint for mod-n operations.
 *
 * Follows the same structure as ecc.c (P-256) for consistency and auditability.
 *
 * References:
 *   SEC 2: Recommended Elliptic Curve Domain Parameters, v2.0
 *   go-ethereum: github.com/ethereum/go-ethereum/crypto
 *   bitcoin-core/libsecp256k1 (test vectors)
 */
#include "os.h"
#include <mp.h>
#include <libsec.h>
#include "uint128.h"

typedef u64int k1fe[4];	/* field element: 4x64-bit limbs, little-endian */

/*
 * Curve parameters (SEC 2, section 2.7.1)
 *
 * p = FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
 *   = 2^256 - 2^32 - 977
 */
static const k1fe K1_P = {
	0xFFFFFFFEFFFFFC2FULL,
	0xFFFFFFFFFFFFFFFFULL,
	0xFFFFFFFFFFFFFFFFULL,
	0xFFFFFFFFFFFFFFFFULL
};

/*
 * n = FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
 */
static const k1fe K1_N = {
	0xBFD25E8CD0364141ULL,
	0xBAAEDCE6AF48A03BULL,
	0xFFFFFFFFFFFFFFFEULL,
	0xFFFFFFFFFFFFFFFFULL
};

/* b = 7 */
static const k1fe K1_B = {
	0x0000000000000007ULL,
	0x0000000000000000ULL,
	0x0000000000000000ULL,
	0x0000000000000000ULL
};

/* base point G */
static const k1fe K1_Gx = {
	0x59F2815B16F81798ULL,
	0x029BFCDB2DCE28D9ULL,
	0x55A06295CE870B07ULL,
	0x79BE667EF9DCBBACULL
};
static const k1fe K1_Gy = {
	0x9C47D08FFB10D4B8ULL,
	0xFD17B448A6855419ULL,
	0x5DA4FBFC0E1108A8ULL,
	0x483ADA7726A3C465ULL
};

/* n/2, precomputed for low-S normalization */
static const k1fe K1_HALFN = {
	0xDFE92F46681B20A0ULL,
	0x5D576E7357A4501DULL,
	0xFFFFFFFFFFFFFFFFULL,
	0x7FFFFFFFFFFFFFFFULL
};

/*
 * Basic field element helpers (identical to ecc.c)
 */

static void
k1_fe_copy(k1fe r, const k1fe a)
{
	r[0] = a[0]; r[1] = a[1]; r[2] = a[2]; r[3] = a[3];
}

static void
k1_fe_zero(k1fe r)
{
	r[0] = 0; r[1] = 0; r[2] = 0; r[3] = 0;
}

static int
k1_fe_is_zero(const k1fe a)
{
	return (a[0] | a[1] | a[2] | a[3]) == 0;
}

static int
k1_fe_eq(const k1fe a, const k1fe b)
{
	return ((a[0]^b[0]) | (a[1]^b[1]) | (a[2]^b[2]) | (a[3]^b[3])) == 0;
}

/* constant-time conditional swap */
static void
k1_fe_cswap(k1fe a, k1fe b, int bit)
{
	u64int mask = (u64int)0 - (u64int)bit;
	u64int t;
	int i;

	for(i = 0; i < 4; i++){
		t = mask & (a[i] ^ b[i]);
		a[i] ^= t;
		b[i] ^= t;
	}
}

/* return 1 if a >= b, 0 otherwise */
static int
k1_fe_gte(const k1fe a, const k1fe b)
{
	int i;
	u64int borrow = 0;

	for(i = 0; i < 4; i++){
		u128 t = SUB128_64(SUB128(U128_FROM64(a[i]), U128_FROM64(b[i])), borrow);
		borrow = HI128(t) & 1;
	}
	return borrow == 0;
}

/* conditional subtract: r = a mod p, assumes a < 2*p */
static void
k1_fe_mod(k1fe r, const k1fe a, const k1fe p)
{
	k1fe t;
	u64int borrow = 0;
	u64int mask;
	int i;

	for(i = 0; i < 4; i++){
		u128 v = SUB128_64(SUB128(U128_FROM64(a[i]), U128_FROM64(p[i])), borrow);
		t[i] = LO128(v);
		borrow = HI128(v) & 1;
	}
	/* if borrow, a < p, use a; else use t */
	mask = (u64int)0 - borrow;
	for(i = 0; i < 4; i++)
		r[i] = (a[i] & mask) | (t[i] & ~mask);
}

/* r = a + b mod p, handles carry when a + b >= 2^256 */
static void
k1_fe_add(k1fe r, const k1fe a, const k1fe b, const k1fe p)
{
	u128 c = U128_FROM64(0);
	k1fe t, t2;
	int i;
	u64int carry, borrow, mask;

	for(i = 0; i < 4; i++){
		c = ADD128_64(ADD128_64(c, a[i]), b[i]);
		t[i] = LO128(c);
		c = U128_FROM64(SHR128_64(c));
	}
	carry = LO128(c);

	/* subtract p from (carry:t) */
	borrow = 0;
	for(i = 0; i < 4; i++){
		u128 v = SUB128_64(SUB128(U128_FROM64(t[i]), U128_FROM64(p[i])), borrow);
		t2[i] = LO128(v);
		borrow = HI128(v) & 1;
	}
	/* underflow if carry < borrow: means (carry:t) < p, use t */
	mask = (u64int)0 - (carry < borrow);
	for(i = 0; i < 4; i++)
		r[i] = (t[i] & mask) | (t2[i] & ~mask);
}

/* r = a - b mod p */
static void
k1_fe_sub(k1fe r, const k1fe a, const k1fe b, const k1fe p)
{
	u64int borrow = 0;
	u64int mask;
	u128 c;
	k1fe t;
	int i;

	for(i = 0; i < 4; i++){
		u128 v = SUB128_64(SUB128(U128_FROM64(a[i]), U128_FROM64(b[i])), borrow);
		t[i] = LO128(v);
		borrow = HI128(v) & 1;
	}
	/* if borrow, add p */
	mask = (u64int)0 - borrow;
	c = U128_FROM64(0);
	for(i = 0; i < 4; i++){
		c = ADD128_64(ADD128_64(c, t[i]), p[i] & mask);
		r[i] = LO128(c);
		c = U128_FROM64(SHR128_64(c));
	}
}

/* forward declarations */
static void k1_bytes_to_fe(k1fe r, const uchar *b);
static void k1_fe_to_bytes(uchar *b, const k1fe a);

/*
 * Reduce a 512-bit product mod p using mpint.
 *
 * secp256k1's prime p = 2^256 - 2^32 - 977 allows efficient
 * special reduction, but we use mpint for correctness first.
 */
static void
k1_reduce(k1fe r, const u64int res[8])
{
	mpint *mres, *mp;
	uchar rbuf[64], outbuf[33];
	uchar pbuf[32];
	int i, n;

	/* convert 512-bit LE result to big-endian bytes */
	for(i = 0; i < 8; i++){
		int j = (7-i)*8;
		rbuf[j]   = res[i]>>56; rbuf[j+1] = res[i]>>48;
		rbuf[j+2] = res[i]>>40; rbuf[j+3] = res[i]>>32;
		rbuf[j+4] = res[i]>>24; rbuf[j+5] = res[i]>>16;
		rbuf[j+6] = res[i]>>8;  rbuf[j+7] = res[i];
	}
	k1_fe_to_bytes(pbuf, K1_P);
	mres = betomp(rbuf, 64, nil);
	mp = betomp(pbuf, 32, nil);
	mpmod(mres, mp, mres);

	memset(pbuf, 0, 32);
	n = mptobe(mres, outbuf, sizeof(outbuf), nil);
	if(n > 0 && n <= 32)
		memmove(pbuf + 32 - n, outbuf, n);
	else if(n > 32)
		memmove(pbuf, outbuf + n - 32, 32);
	k1_bytes_to_fe(r, pbuf);
	mpfree(mres);
	mpfree(mp);
}

/*
 * r = a * b mod p
 * Uses operand scanning (same as ecc.c).
 */
static void
k1_fe_mul(k1fe r, const k1fe a, const k1fe b, const k1fe p)
{
	u64int res[8];
	u128 acc;
	int i, j, k;

	USED(p);
	memset(res, 0, sizeof(res));

	for(i = 0; i < 4; i++){
		acc = U128_FROM64(0);
		for(j = 0; j < 4; j++){
			acc = ADD128(ADD128_64(acc, res[i+j]), MUL128(a[i], b[j]));
			res[i+j] = LO128(acc);
			acc = U128_FROM64(SHR128_64(acc));
		}
		for(k = i+4; !IS_ZERO128(acc) && k < 8; k++){
			acc = ADD128_64(acc, res[k]);
			res[k] = LO128(acc);
			acc = U128_FROM64(SHR128_64(acc));
		}
	}

	k1_reduce(r, res);
}

/* r = a^2 mod p */
static void
k1_fe_sqr(k1fe r, const k1fe a)
{
	k1_fe_mul(r, a, a, K1_P);
}

/*
 * r = a^(p-2) mod p (modular inverse via Fermat's little theorem).
 *
 * For secp256k1, p-2 = FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2D
 * We use an addition chain optimized for this specific prime.
 */
static void
k1_fe_inv(k1fe r, const k1fe a)
{
	k1fe x2, x3, x6, x9, x11, x22, x44, x88, x176, x220, x223, e;
	int i;

	/* x2 = a^3 */
	k1_fe_sqr(x2, a);
	k1_fe_mul(x2, x2, a, K1_P);

	/* x3 = a^7 */
	k1_fe_sqr(x3, x2);
	k1_fe_mul(x3, x3, a, K1_P);

	/* x6 = a^(2^6 - 1) */
	k1_fe_copy(e, x3);
	for(i = 0; i < 3; i++) k1_fe_sqr(e, e);
	k1_fe_mul(x6, e, x3, K1_P);

	/* x9 = a^(2^9 - 1) */
	k1_fe_copy(e, x6);
	for(i = 0; i < 3; i++) k1_fe_sqr(e, e);
	k1_fe_mul(x9, e, x3, K1_P);

	/* x11 = a^(2^11 - 1) */
	k1_fe_copy(e, x9);
	for(i = 0; i < 2; i++) k1_fe_sqr(e, e);
	k1_fe_mul(x11, e, x2, K1_P);

	/* x22 = a^(2^22 - 1) */
	k1_fe_copy(e, x11);
	for(i = 0; i < 11; i++) k1_fe_sqr(e, e);
	k1_fe_mul(x22, e, x11, K1_P);

	/* x44 = a^(2^44 - 1) */
	k1_fe_copy(e, x22);
	for(i = 0; i < 22; i++) k1_fe_sqr(e, e);
	k1_fe_mul(x44, e, x22, K1_P);

	/* x88 = a^(2^88 - 1) */
	k1_fe_copy(e, x44);
	for(i = 0; i < 44; i++) k1_fe_sqr(e, e);
	k1_fe_mul(x88, e, x44, K1_P);

	/* x176 = a^(2^176 - 1) */
	k1_fe_copy(e, x88);
	for(i = 0; i < 88; i++) k1_fe_sqr(e, e);
	k1_fe_mul(x176, e, x88, K1_P);

	/* x220 = a^(2^220 - 1) */
	k1_fe_copy(e, x176);
	for(i = 0; i < 44; i++) k1_fe_sqr(e, e);
	k1_fe_mul(x220, e, x44, K1_P);

	/* x223 = a^(2^223 - 1) */
	k1_fe_copy(e, x220);
	for(i = 0; i < 3; i++) k1_fe_sqr(e, e);
	k1_fe_mul(x223, e, x3, K1_P);

	/*
	 * p - 2 = 2^256 - 2^32 - 979
	 *       = (2^223 - 1) * 2^33 + 2^32 - 979
	 *
	 * Decomposition:
	 *   e = x223 * 2^23    (shift left 23 bits)
	 *   e *= a^(2^10 - 979) ... but simpler to use the known chain:
	 *
	 * p-2 in hex: FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2D
	 * Low 32 bits of p-2: FFFFFC2D = 11111111 11111111 11111100 00101101
	 *
	 * Chain: x223, then <<33, then apply low bits pattern.
	 */
	k1_fe_copy(e, x223);
	for(i = 0; i < 23; i++) k1_fe_sqr(e, e);
	k1_fe_mul(e, e, x22, K1_P);
	for(i = 0; i < 5; i++) k1_fe_sqr(e, e);
	k1_fe_mul(e, e, a, K1_P);
	for(i = 0; i < 3; i++) k1_fe_sqr(e, e);
	k1_fe_mul(e, e, x2, K1_P);
	k1_fe_sqr(e, e);
	k1_fe_sqr(e, e);
	k1_fe_mul(r, e, a, K1_P);
}

/*
 * Byte conversion (32-byte big-endian <-> k1fe little-endian 64-bit limbs)
 */

static void
k1_bytes_to_fe(k1fe r, const uchar *b)
{
	int i;
	for(i = 0; i < 4; i++){
		int j = (3-i)*8;
		r[i] = (u64int)b[j]<<56 | (u64int)b[j+1]<<48
		     | (u64int)b[j+2]<<40 | (u64int)b[j+3]<<32
		     | (u64int)b[j+4]<<24 | (u64int)b[j+5]<<16
		     | (u64int)b[j+6]<<8 | (u64int)b[j+7];
	}
}

static void
k1_fe_to_bytes(uchar *b, const k1fe a)
{
	int i;
	for(i = 0; i < 4; i++){
		int j = (3-i)*8;
		b[j]   = a[i]>>56; b[j+1] = a[i]>>48;
		b[j+2] = a[i]>>40; b[j+3] = a[i]>>32;
		b[j+4] = a[i]>>24; b[j+5] = a[i]>>16;
		b[j+6] = a[i]>>8;  b[j+7] = a[i];
	}
}

/*
 * Jacobian point operations.
 * A point (X, Y, Z) represents affine (X/Z^2, Y/Z^3).
 * Point at infinity: Z = 0.
 * Curve: y^2 = x^3 + 7 (a = 0).
 */

/*
 * Point doubling: R = 2*P
 * For a = 0: alpha = 3*X1^2 (not 3*(X1-delta)*(X1+delta))
 * Cost: 4M + 4S
 */
static void
k1_point_double(k1fe X3, k1fe Y3, k1fe Z3,
	const k1fe X1, const k1fe Y1, const k1fe Z1)
{
	k1fe gamma, beta, alpha, t1, t2;

	if(k1_fe_is_zero(Z1)){
		k1_fe_zero(X3); k1_fe_zero(Y3); k1_fe_zero(Z3);
		return;
	}

	k1_fe_sqr(gamma, Y1);			/* gamma = Y1^2 */
	k1_fe_mul(beta, X1, gamma, K1_P);	/* beta = X1 * gamma */

	/* alpha = 3*X1^2 (since a = 0, no delta terms needed) */
	k1_fe_sqr(alpha, X1);
	k1_fe_add(t1, alpha, alpha, K1_P);
	k1_fe_add(alpha, t1, alpha, K1_P);	/* alpha = 3 * X1^2 */

	/* X3 = alpha^2 - 8*beta */
	k1_fe_sqr(X3, alpha);
	k1_fe_add(t1, beta, beta, K1_P);	/* 2*beta */
	k1_fe_add(t1, t1, t1, K1_P);		/* 4*beta */
	k1_fe_add(t2, t1, t1, K1_P);		/* 8*beta */
	k1_fe_sub(X3, X3, t2, K1_P);

	/* Z3 = 2*Y1*Z1 */
	k1_fe_mul(Z3, Y1, Z1, K1_P);
	k1_fe_add(Z3, Z3, Z3, K1_P);

	/* Y3 = alpha*(4*beta - X3) - 8*gamma^2 */
	k1_fe_sub(t2, t1, X3, K1_P);		/* 4*beta - X3 */
	k1_fe_mul(Y3, alpha, t2, K1_P);
	k1_fe_sqr(t1, gamma);			/* gamma^2 */
	k1_fe_add(t1, t1, t1, K1_P);		/* 2*gamma^2 */
	k1_fe_add(t1, t1, t1, K1_P);		/* 4*gamma^2 */
	k1_fe_add(t1, t1, t1, K1_P);		/* 8*gamma^2 */
	k1_fe_sub(Y3, Y3, t1, K1_P);
}

/* point addition: R = P + Q, cost: 11M + 5S */
static void
k1_point_add(k1fe X3, k1fe Y3, k1fe Z3,
	const k1fe X1, const k1fe Y1, const k1fe Z1,
	const k1fe X2, const k1fe Y2, const k1fe Z2)
{
	k1fe Z1Z1, Z2Z2, U1, U2, S1, S2, H, I, J, rr, V, t;

	if(k1_fe_is_zero(Z1)){
		k1_fe_copy(X3, X2); k1_fe_copy(Y3, Y2); k1_fe_copy(Z3, Z2);
		return;
	}
	if(k1_fe_is_zero(Z2)){
		k1_fe_copy(X3, X1); k1_fe_copy(Y3, Y1); k1_fe_copy(Z3, Z1);
		return;
	}

	k1_fe_sqr(Z1Z1, Z1);
	k1_fe_sqr(Z2Z2, Z2);
	k1_fe_mul(U1, X1, Z2Z2, K1_P);
	k1_fe_mul(U2, X2, Z1Z1, K1_P);
	k1_fe_mul(S1, Y1, Z2, K1_P);
	k1_fe_mul(S1, S1, Z2Z2, K1_P);
	k1_fe_mul(S2, Y2, Z1, K1_P);
	k1_fe_mul(S2, S2, Z1Z1, K1_P);

	k1_fe_sub(H, U2, U1, K1_P);
	if(k1_fe_is_zero(H)){
		k1_fe_sub(t, S2, S1, K1_P);
		if(k1_fe_is_zero(t)){
			k1_point_double(X3, Y3, Z3, X1, Y1, Z1);
			return;
		}
		k1_fe_zero(X3); k1_fe_zero(Y3); k1_fe_zero(Z3);
		return;
	}

	k1_fe_add(I, H, H, K1_P);
	k1_fe_sqr(I, I);			/* I = (2*H)^2 */
	k1_fe_mul(J, H, I, K1_P);		/* J = H * I */
	k1_fe_sub(rr, S2, S1, K1_P);
	k1_fe_add(rr, rr, rr, K1_P);		/* rr = 2*(S2 - S1) */
	k1_fe_mul(V, U1, I, K1_P);

	/* X3 = rr^2 - J - 2*V */
	k1_fe_sqr(X3, rr);
	k1_fe_sub(X3, X3, J, K1_P);
	k1_fe_sub(X3, X3, V, K1_P);
	k1_fe_sub(X3, X3, V, K1_P);

	/* Y3 = rr*(V - X3) - 2*S1*J */
	k1_fe_sub(t, V, X3, K1_P);
	k1_fe_mul(Y3, rr, t, K1_P);
	k1_fe_mul(t, S1, J, K1_P);
	k1_fe_add(t, t, t, K1_P);
	k1_fe_sub(Y3, Y3, t, K1_P);

	/* Z3 = ((Z1+Z2)^2 - Z1Z1 - Z2Z2) * H */
	k1_fe_add(Z3, Z1, Z2, K1_P);
	k1_fe_sqr(Z3, Z3);
	k1_fe_sub(Z3, Z3, Z1Z1, K1_P);
	k1_fe_sub(Z3, Z3, Z2Z2, K1_P);
	k1_fe_mul(Z3, Z3, H, K1_P);
}

/* convert Jacobian to affine coordinates */
static void
k1_point_to_affine(uchar outx[32], uchar outy[32],
	const k1fe X, const k1fe Y, const k1fe Z)
{
	k1fe zinv, zinv2, zinv3, ax, ay;

	k1_fe_inv(zinv, Z);
	k1_fe_sqr(zinv2, zinv);
	k1_fe_mul(zinv3, zinv2, zinv, K1_P);
	k1_fe_mul(ax, X, zinv2, K1_P);
	k1_fe_mul(ay, Y, zinv3, K1_P);
	k1_fe_to_bytes(outx, ax);
	k1_fe_to_bytes(outy, ay);
}

/*
 * Constant-time Montgomery ladder scalar multiplication.
 * Processes bits from MSB to LSB.
 * scalar is 32 bytes, big-endian.
 */
static void
k1_point_mul(k1fe RX, k1fe RY, k1fe RZ,
	const uchar scalar[32],
	const k1fe PX, const k1fe PY, const k1fe PZ)
{
	k1fe R0X, R0Y, R0Z;
	k1fe R1X, R1Y, R1Z;
	int i, bit, swap;

	/* R0 = infinity, R1 = P */
	k1_fe_zero(R0X); k1_fe_zero(R0Y); k1_fe_zero(R0Z);
	k1_fe_copy(R1X, PX); k1_fe_copy(R1Y, PY); k1_fe_copy(R1Z, PZ);

	swap = 0;
	for(i = 255; i >= 0; i--){
		bit = (scalar[31 - i/8] >> (i & 7)) & 1;
		swap ^= bit;
		k1_fe_cswap(R0X, R1X, swap);
		k1_fe_cswap(R0Y, R1Y, swap);
		k1_fe_cswap(R0Z, R1Z, swap);
		swap = bit;

		k1_point_add(R1X, R1Y, R1Z,
			R0X, R0Y, R0Z, R1X, R1Y, R1Z);
		k1_point_double(R0X, R0Y, R0Z,
			R0X, R0Y, R0Z);
	}
	k1_fe_cswap(R0X, R1X, swap);
	k1_fe_cswap(R0Y, R1Y, swap);
	k1_fe_cswap(R0Z, R1Z, swap);

	k1_fe_copy(RX, R0X);
	k1_fe_copy(RY, R0Y);
	k1_fe_copy(RZ, R0Z);
}

/* check that affine point (x, y) is on the curve: y^2 = x^3 + 7 */
static int
k1_point_on_curve(const k1fe x, const k1fe y)
{
	k1fe lhs, rhs;

	k1_fe_sqr(lhs, y);			/* y^2 */
	k1_fe_sqr(rhs, x);
	k1_fe_mul(rhs, rhs, x, K1_P);		/* x^3 */
	k1_fe_add(rhs, rhs, K1_B, K1_P);	/* x^3 + 7 */
	return k1_fe_eq(lhs, rhs);
}

/*
 * mpint helpers for scalar arithmetic mod n
 */

static mpint*
k1_fe_to_mp(const k1fe a)
{
	uchar buf[32];
	k1_fe_to_bytes(buf, a);
	return betomp(buf, 32, nil);
}

static void
k1_mp_to_bytes(uchar out[32], mpint *m)
{
	uchar buf[33];
	int n;

	memset(out, 0, 32);
	n = mptobe(m, buf, sizeof(buf), nil);
	if(n > 0 && n <= 32)
		memmove(out + 32 - n, buf, n);
	else if(n > 32)
		memmove(out, buf + n - 32, 32);
}

/*
 * RFC 6979 deterministic k generation.
 * Required for Ethereum transaction signing (deterministic signatures).
 *
 * Uses HMAC-SHA256 as the DRBG, per RFC 6979 Section 3.2.
 */
static void
k1_rfc6979_k(uchar kout[32], const uchar privkey[32], const uchar hash[32])
{
	uchar V[32], K[32], tmp[32];
	uchar buf[32+1+32+32];  /* V || 0x00/0x01 || privkey || hash */
	int i;

	/* Step a: V = 0x01 0x01 ... (32 bytes) */
	memset(V, 0x01, 32);

	/* Step b: K = 0x00 0x00 ... (32 bytes) */
	memset(K, 0x00, 32);

	/* Step d: K = HMAC_K(V || 0x00 || privkey || hash) */
	memmove(buf, V, 32);
	buf[32] = 0x00;
	memmove(buf+33, privkey, 32);
	memmove(buf+65, hash, 32);
	hmac_sha256(buf, 97, K, 32, tmp, nil);
	memmove(K, tmp, 32);

	/* Step e: V = HMAC_K(V) */
	hmac_sha256(V, 32, K, 32, tmp, nil);
	memmove(V, tmp, 32);

	/* Step f: K = HMAC_K(V || 0x01 || privkey || hash) */
	memmove(buf, V, 32);
	buf[32] = 0x01;
	memmove(buf+33, privkey, 32);
	memmove(buf+65, hash, 32);
	hmac_sha256(buf, 97, K, 32, tmp, nil);
	memmove(K, tmp, 32);

	/* Step g: V = HMAC_K(V) */
	hmac_sha256(V, 32, K, 32, tmp, nil);
	memmove(V, tmp, 32);

	/* Step h: generate k candidates until valid */
	for(i = 0; i < 100; i++){
		mpint *km, *nm;
		uchar nbuf[32];

		/* V = HMAC_K(V) */
		hmac_sha256(V, 32, K, 32, tmp, nil);
		memmove(V, tmp, 32);

		/* check 0 < k < n */
		km = betomp(V, 32, nil);
		k1_fe_to_bytes(nbuf, K1_N);
		nm = betomp(nbuf, 32, nil);
		if(mpcmp(km, mpzero) > 0 && mpcmp(km, nm) < 0){
			memmove(kout, V, 32);
			mpfree(km);
			mpfree(nm);
			/* zero temporaries */
			secureZero(K, 32);
			secureZero(tmp, 32);
			secureZero(buf, sizeof(buf));
			return;
		}
		mpfree(km);
		mpfree(nm);

		/* K = HMAC_K(V || 0x00) */
		memmove(buf, V, 32);
		buf[32] = 0x00;
		hmac_sha256(buf, 33, K, 32, tmp, nil);
		memmove(K, tmp, 32);

		/* V = HMAC_K(V) */
		hmac_sha256(V, 32, K, 32, tmp, nil);
		memmove(V, tmp, 32);
	}

	/* should never reach here; fallback to random */
	prng(kout, 32);
	secureZero(K, 32);
	secureZero(tmp, 32);
	secureZero(buf, sizeof(buf));
}

/*
 * Public API
 */

int
secp256k1_keygen(uchar priv[32], uchar pub[65])
{
	k1fe kfe, one;
	k1fe RX, RY, RZ;
	uchar kbuf[32];

	/* generate random scalar, ensure 0 < k < n */
	prng(kbuf, 32);
	k1_bytes_to_fe(kfe, kbuf);
	if(k1_fe_is_zero(kfe) || k1_fe_gte(kfe, K1_N))
		kbuf[0] = 1;  /* simple fix for edge cases */

	memmove(priv, kbuf, 32);

	/* compute public key = k * G */
	one[0] = 1; one[1] = 0; one[2] = 0; one[3] = 0;
	k1_point_mul(RX, RY, RZ, priv, K1_Gx, K1_Gy, one);

	if(k1_fe_is_zero(RZ))
		return -1;

	/* uncompressed format: 0x04 || x || y */
	pub[0] = 0x04;
	k1_point_to_affine(pub + 1, pub + 33, RX, RY, RZ);

	/* validate generated point is on curve */
	{
		k1fe chkx, chky;
		k1_bytes_to_fe(chkx, pub + 1);
		k1_bytes_to_fe(chky, pub + 33);
		if(!k1_point_on_curve(chkx, chky))
			return -1;
	}

	memset(kbuf, 0, sizeof(kbuf));
	return 0;
}

void
secp256k1_pubkey(uchar pub[65], uchar priv[32])
{
	k1fe one, RX, RY, RZ;

	one[0] = 1; one[1] = 0; one[2] = 0; one[3] = 0;
	k1_point_mul(RX, RY, RZ, priv, K1_Gx, K1_Gy, one);

	pub[0] = 0x04;
	k1_point_to_affine(pub + 1, pub + 33, RX, RY, RZ);
}

/*
 * ECDSA sign with recovery ID.
 * sig[65] = r[32] || s[32] || v[1]
 * v = recovery ID (0 or 1), used by Ethereum's ecrecover.
 *
 * Uses RFC 6979 deterministic k for Ethereum compatibility.
 * Applies low-S normalization (BIP-62 / EIP-2).
 */
int
secp256k1_sign(uchar sig[65], uchar priv[32], uchar *hash, int hashlen)
{
	mpint *n, *k, *r, *s, *e, *d, *kinv, *t, *halfn;
	k1fe one, RX, RY, RZ;
	uchar kbuf[32], xbuf[32], ybuf[32];
	uchar hbuf[32], nbuf[32];
	int recid;

	/* load curve order */
	k1_fe_to_bytes(nbuf, K1_N);
	n = betomp(nbuf, 32, nil);

	/* load private key */
	d = betomp(priv, 32, nil);

	/* truncate hash to 256 bits */
	if(hashlen >= 32)
		memmove(hbuf, hash, 32);
	else{
		memset(hbuf, 0, 32);
		memmove(hbuf + 32 - hashlen, hash, hashlen);
	}
	e = betomp(hbuf, 32, nil);
	mpmod(e, n, e);

	one[0] = 1; one[1] = 0; one[2] = 0; one[3] = 0;
	r = mpnew(256);
	s = mpnew(256);
	kinv = mpnew(256);
	t = mpnew(512);

	/* load n/2 for low-S check */
	k1_fe_to_bytes(nbuf, K1_HALFN);
	halfn = betomp(nbuf, 32, nil);

	/* RFC 6979 deterministic k */
	k1_rfc6979_k(kbuf, priv, hbuf);
	k = betomp(kbuf, 32, nil);

	/* compute (x1, y1) = k * G */
	k1_point_mul(RX, RY, RZ, kbuf, K1_Gx, K1_Gy, one);
	if(k1_fe_is_zero(RZ))
		goto fail;

	/* r = x1 mod n */
	k1_point_to_affine(xbuf, ybuf, RX, RY, RZ);
	mpfree(r);
	r = betomp(xbuf, 32, nil);

	/* recovery ID: bit 0 = y1 parity */
	recid = ybuf[31] & 1;

	k1_fe_to_bytes(nbuf, K1_N);
	mpfree(n);
	n = betomp(nbuf, 32, nil);
	mpmod(r, n, r);
	if(mpcmp(r, mpzero) == 0)
		goto fail;

	/* s = k^(-1) * (e + r*d) mod n */
	mpinvert(k, n, kinv);
	mpmul(r, d, t);		/* t = r * d */
	mpmod(t, n, t);
	mpadd(e, t, t);		/* t = e + r*d */
	mpmod(t, n, t);
	mpmul(kinv, t, s);		/* s = kinv * (e + r*d) */
	mpmod(s, n, s);

	if(mpcmp(s, mpzero) == 0)
		goto fail;

	/* low-S normalization (BIP-62 / EIP-2): if s > n/2, s = n - s */
	if(mpcmp(s, halfn) > 0){
		mpsub(n, s, s);
		recid ^= 1;	/* flip recovery ID */
	}

	/* output (r, s, v) */
	k1_mp_to_bytes(sig, r);
	k1_mp_to_bytes(sig + 32, s);
	sig[64] = recid;

	mpfree(r); mpfree(s); mpfree(kinv); mpfree(t);
	mpfree(n); mpfree(d); mpfree(e); mpfree(k); mpfree(halfn);
	memset(kbuf, 0, sizeof(kbuf));
	memset(hbuf, 0, sizeof(hbuf));
	return 0;

fail:
	mpfree(r); mpfree(s); mpfree(kinv); mpfree(t);
	mpfree(n); mpfree(d); mpfree(e); mpfree(k); mpfree(halfn);
	memset(kbuf, 0, sizeof(kbuf));
	memset(hbuf, 0, sizeof(hbuf));
	return -1;
}

/*
 * Recover public key from signature and hash.
 * sig[65] = r[32] || s[32] || v[1]
 * pub[65] = 0x04 || x[32] || y[32]
 *
 * Returns 0 on success, -1 on failure.
 */
int
secp256k1_recover(uchar pub[65], uchar *hash, int hashlen, uchar sig[65])
{
	mpint *n, *r, *s, *e, *rinv, *u1m, *u2m;
	k1fe px, py, one;
	k1fe P1X, P1Y, P1Z, P2X, P2Y, P2Z, RX, RY, RZ;
	uchar xbuf[32], ybuf[32], u1buf[32], u2buf[32], hbuf[32], nbuf[32];
	k1fe rx, t1;
	int recid;

	recid = sig[64] & 1;

	/* load signature (r, s) */
	r = betomp(sig, 32, nil);
	s = betomp(sig + 32, 32, nil);

	/* load curve order */
	k1_fe_to_bytes(nbuf, K1_N);
	n = betomp(nbuf, 32, nil);

	/* validate r, s in [1, n-1] */
	if(mpcmp(r, mpzero) <= 0 || mpcmp(r, n) >= 0 ||
	   mpcmp(s, mpzero) <= 0 || mpcmp(s, n) >= 0){
		mpfree(r); mpfree(s); mpfree(n);
		return -1;
	}

	/* recover R point: x = r, compute y from curve equation */
	k1_mp_to_bytes(xbuf, r);
	k1_bytes_to_fe(rx, xbuf);

	/* y^2 = x^3 + 7 mod p */
	k1_fe_sqr(t1, rx);
	k1_fe_mul(t1, t1, rx, K1_P);
	k1_fe_add(t1, t1, K1_B, K1_P);

	/*
	 * Compute square root: y = t1^((p+1)/4) mod p
	 * This works because p ≡ 3 (mod 4) for secp256k1.
	 */
	{
		mpint *ymp, *pmp, *exp;
		uchar pbuf[32], ybuf2[33];
		int nn;

		k1_fe_to_bytes(pbuf, K1_P);
		pmp = betomp(pbuf, 32, nil);

		/* exp = (p + 1) / 4 */
		exp = mpcopy(pmp);
		mpadd(exp, mpone, exp);
		mpright(exp, 2, exp);

		k1_fe_to_bytes(pbuf, t1);
		ymp = betomp(pbuf, 32, nil);
		mpexp(ymp, exp, pmp, ymp);

		memset(ybuf, 0, 32);
		nn = mptobe(ymp, ybuf2, sizeof(ybuf2), nil);
		if(nn > 0 && nn <= 32)
			memmove(ybuf + 32 - nn, ybuf2, nn);
		else if(nn > 32)
			memmove(ybuf, ybuf2 + nn - 32, 32);

		/* choose correct y parity */
		if((ybuf[31] & 1) != recid){
			/* y = p - y */
			k1fe yfe;
			k1_bytes_to_fe(yfe, ybuf);
			k1_fe_sub(yfe, K1_P, yfe, K1_P);
			k1_fe_to_bytes(ybuf, yfe);
		}

		mpfree(ymp); mpfree(pmp); mpfree(exp);
	}

	/* validate recovered point */
	k1_bytes_to_fe(px, xbuf);
	k1_bytes_to_fe(py, ybuf);
	if(!k1_point_on_curve(px, py)){
		mpfree(r); mpfree(s); mpfree(n);
		return -1;
	}

	/* load hash */
	if(hashlen >= 32)
		memmove(hbuf, hash, 32);
	else{
		memset(hbuf, 0, 32);
		memmove(hbuf + 32 - hashlen, hash, hashlen);
	}
	e = betomp(hbuf, 32, nil);
	mpmod(e, n, e);

	/* r^(-1) mod n */
	rinv = mpnew(256);
	mpinvert(r, n, rinv);

	/* u1 = -e * r^(-1) mod n, u2 = s * r^(-1) mod n */
	u1m = mpnew(512);
	u2m = mpnew(512);
	mpmul(e, rinv, u1m);
	mpmod(u1m, n, u1m);
	mpsub(n, u1m, u1m);	/* u1 = n - (e * rinv mod n) = -e * rinv mod n */
	mpmul(s, rinv, u2m);
	mpmod(u2m, n, u2m);

	k1_mp_to_bytes(u1buf, u1m);
	k1_mp_to_bytes(u2buf, u2m);

	/* Q = u1*G + u2*R */
	one[0] = 1; one[1] = 0; one[2] = 0; one[3] = 0;
	k1_point_mul(P1X, P1Y, P1Z, u1buf, K1_Gx, K1_Gy, one);
	k1_point_mul(P2X, P2Y, P2Z, u2buf, px, py, one);
	k1_point_add(RX, RY, RZ, P1X, P1Y, P1Z, P2X, P2Y, P2Z);

	if(k1_fe_is_zero(RZ)){
		mpfree(r); mpfree(s); mpfree(n); mpfree(e);
		mpfree(rinv); mpfree(u1m); mpfree(u2m);
		return -1;
	}

	pub[0] = 0x04;
	k1_point_to_affine(pub + 1, pub + 33, RX, RY, RZ);

	mpfree(r); mpfree(s); mpfree(n); mpfree(e);
	mpfree(rinv); mpfree(u1m); mpfree(u2m);
	return 0;
}

int
secp256k1_verify(uchar sig[64], uchar pub[65], uchar *hash, int hashlen)
{
	mpint *n, *r, *s, *e, *w, *u1m, *u2m;
	k1fe px, py, one;
	k1fe P1X, P1Y, P1Z, P2X, P2Y, P2Z, RX, RY, RZ;
	k1fe zinv, zinv2, ax;
	uchar u1buf[32], u2buf[32], hbuf[32], nbuf[32];
	int ok;

	/* pub must start with 0x04 (uncompressed) */
	if(pub[0] != 0x04)
		return 0;

	/* load signature (r, s) */
	r = betomp(sig, 32, nil);
	s = betomp(sig + 32, 32, nil);

	/* load curve order */
	k1_fe_to_bytes(nbuf, K1_N);
	n = betomp(nbuf, 32, nil);

	/* check 1 <= r, s <= n-1 */
	if(mpcmp(r, mpzero) <= 0 || mpcmp(r, n) >= 0 ||
	   mpcmp(s, mpzero) <= 0 || mpcmp(s, n) >= 0){
		mpfree(r); mpfree(s); mpfree(n);
		return 0;
	}

	/* load hash */
	if(hashlen >= 32)
		memmove(hbuf, hash, 32);
	else{
		memset(hbuf, 0, 32);
		memmove(hbuf + 32 - hashlen, hash, hashlen);
	}
	e = betomp(hbuf, 32, nil);
	mpmod(e, n, e);

	/* w = s^(-1) mod n */
	w = mpnew(256);
	mpinvert(s, n, w);

	/* u1 = e * w mod n, u2 = r * w mod n */
	u1m = mpnew(512);
	u2m = mpnew(512);
	mpmul(e, w, u1m);
	mpmod(u1m, n, u1m);
	mpmul(r, w, u2m);
	mpmod(u2m, n, u2m);

	k1_mp_to_bytes(u1buf, u1m);
	k1_mp_to_bytes(u2buf, u2m);

	/* validate public key */
	k1_bytes_to_fe(px, pub + 1);
	k1_bytes_to_fe(py, pub + 33);
	if(!k1_point_on_curve(px, py)){
		mpfree(r); mpfree(s); mpfree(n); mpfree(e);
		mpfree(w); mpfree(u1m); mpfree(u2m);
		return 0;
	}

	/* compute u1*G + u2*Q */
	one[0] = 1; one[1] = 0; one[2] = 0; one[3] = 0;
	k1_point_mul(P1X, P1Y, P1Z, u1buf, K1_Gx, K1_Gy, one);
	k1_point_mul(P2X, P2Y, P2Z, u2buf, px, py, one);
	k1_point_add(RX, RY, RZ, P1X, P1Y, P1Z, P2X, P2Y, P2Z);

	ok = 0;
	if(!k1_fe_is_zero(RZ)){
		/* x1 = X / Z^2 */
		k1_fe_inv(zinv, RZ);
		k1_fe_sqr(zinv2, zinv);
		k1_fe_mul(ax, RX, zinv2, K1_P);

		/* check x1 mod n == r */
		k1_fe_to_bytes(u1buf, ax);
		{
			mpint *xmp = betomp(u1buf, 32, nil);
			mpmod(xmp, n, xmp);
			ok = mpcmp(xmp, r) == 0;
			mpfree(xmp);
		}
	}

	mpfree(r); mpfree(s); mpfree(n); mpfree(e);
	mpfree(w); mpfree(u1m); mpfree(u2m);
	return ok;
}
