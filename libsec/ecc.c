/*
 * P-256 (secp256r1) ECDH and ECDSA.
 * Uses 64-bit limbs with __int128 for intermediate products.
 *
 * Field arithmetic over GF(p) where p = 2^256 - 2^224 + 2^192 + 2^96 - 1.
 * Point multiplication uses a constant-time Montgomery ladder in Jacobian coordinates.
 * ECDSA scalar arithmetic uses libmp's mpint for mod-n operations.
 */
#include "os.h"
#include <mp.h>
#include <libsec.h>

typedef unsigned __int128 u128;
typedef u64int fe[4];	/* field element: 4x64-bit limbs, little-endian */

/* p = 2^256 - 2^224 + 2^192 + 2^96 - 1 */
static const fe P256_P = {
	0xFFFFFFFFFFFFFFFFULL,
	0x00000000FFFFFFFFULL,
	0x0000000000000000ULL,
	0xFFFFFFFF00000001ULL
};

/* order n of the base point */
static const fe P256_N = {
	0xF3B9CAC2FC632551ULL,
	0xBCE6FAADA7179E84ULL,
	0xFFFFFFFFFFFFFFFFULL,
	0xFFFFFFFF00000000ULL
};

/* curve parameter b */
static const fe P256_B = {
	0x3BCE3C3E27D2604BULL,
	0x651D06B0CC53B0F6ULL,
	0xB3EBBD55769886BCULL,
	0x5AC635D8AA3A93E7ULL
};

/* base point G */
static const fe P256_Gx = {
	0xF4A13945D898C296ULL,
	0x77037D812DEB33A0ULL,
	0xF8BCE6E563A440F2ULL,
	0x6B17D1F2E12C4247ULL
};
static const fe P256_Gy = {
	0xCBB6406837BF51F5ULL,
	0x2BCE33576B315ECEULL,
	0x8EE7EB4A7C0F9E16ULL,
	0x4FE342E2FE1A7F9BULL
};

/*
 * Basic field element helpers
 */

static void
fe_copy(fe r, const fe a)
{
	r[0] = a[0]; r[1] = a[1]; r[2] = a[2]; r[3] = a[3];
}

static void
fe_zero(fe r)
{
	r[0] = 0; r[1] = 0; r[2] = 0; r[3] = 0;
}

static int
fe_is_zero(const fe a)
{
	return (a[0] | a[1] | a[2] | a[3]) == 0;
}

static int
fe_eq(const fe a, const fe b)
{
	return ((a[0]^b[0]) | (a[1]^b[1]) | (a[2]^b[2]) | (a[3]^b[3])) == 0;
}

/* constant-time conditional swap */
static void
fe_cswap(fe a, fe b, int bit)
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
fe_gte(const fe a, const fe b)
{
	int i;
	u64int borrow = 0;

	for(i = 0; i < 4; i++){
		u128 t = (u128)a[i] - b[i] - borrow;
		borrow = (t >> 64) & 1;
	}
	return borrow == 0;
}

/* conditional subtract: r = a mod p, assumes a < 2*p */
static void
fe_mod(fe r, const fe a, const fe p)
{
	fe t;
	u64int borrow = 0;
	u64int mask;
	int i;

	for(i = 0; i < 4; i++){
		u128 v = (u128)a[i] - p[i] - borrow;
		t[i] = (u64int)v;
		borrow = (v >> 64) & 1;
	}
	/* if borrow, a < p, use a; else use t */
	mask = (u64int)0 - borrow;
	for(i = 0; i < 4; i++)
		r[i] = (a[i] & mask) | (t[i] & ~mask);
}

/* r = a + b mod p, handles carry when a + b >= 2^256 */
static void
fe_add(fe r, const fe a, const fe b, const fe p)
{
	u128 c = 0;
	fe t, t2;
	int i;
	u64int carry, borrow, mask;

	for(i = 0; i < 4; i++){
		c += (u128)a[i] + b[i];
		t[i] = (u64int)c;
		c >>= 64;
	}
	carry = (u64int)c;

	/* subtract p from (carry:t) */
	borrow = 0;
	for(i = 0; i < 4; i++){
		u128 v = (u128)t[i] - p[i] - borrow;
		t2[i] = (u64int)v;
		borrow = (v >> 64) & 1;
	}
	/* underflow if carry < borrow: means (carry:t) < p, use t */
	mask = (u64int)0 - (carry < borrow);
	for(i = 0; i < 4; i++)
		r[i] = (t[i] & mask) | (t2[i] & ~mask);
}

/* r = a - b mod p */
static void
fe_sub(fe r, const fe a, const fe b, const fe p)
{
	u64int borrow = 0;
	u64int mask;
	u128 c;
	fe t;
	int i;

	for(i = 0; i < 4; i++){
		u128 v = (u128)a[i] - b[i] - borrow;
		t[i] = (u64int)v;
		borrow = (v >> 64) & 1;
	}
	/* if borrow, add p */
	mask = (u64int)0 - borrow;
	c = 0;
	for(i = 0; i < 4; i++){
		c += (u128)t[i] + (p[i] & mask);
		r[i] = (u64int)c;
		c >>= 64;
	}
}

/* forward declarations */
static void bytes_to_fe(fe r, const uchar *b);
static void fe_to_bytes(uchar *b, const fe a);

/*
 * Reduce a 512-bit product mod p using mpint.
 * Correct reference implementation; can be replaced with NIST fast
 * reduction once verified.
 */
static void
p256_reduce(fe r, const u64int res[8])
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
	fe_to_bytes(pbuf, P256_P);
	mres = betomp(rbuf, 64, nil);
	mp = betomp(pbuf, 32, nil);
	mpmod(mres, mp, mres);

	/* mptobe writes left-justified (minimal bytes);
	 * we need right-justified in a 32-byte buffer */
	memset(pbuf, 0, 32);
	n = mptobe(mres, outbuf, sizeof(outbuf), nil);
	if(n > 0 && n <= 32)
		memmove(pbuf + 32 - n, outbuf, n);
	else if(n > 32)
		memmove(pbuf, outbuf + n - 32, 32);
	bytes_to_fe(r, pbuf);
	mpfree(mres);
	mpfree(mp);
}

/*
 * r = a * b mod p
 * Uses operand scanning to avoid u128 overflow in accumulators.
 * Invariant: acc = carry(<2^64) + res[k](<2^64) + product(<2^128)
 *          ≤ (2^64-1) + (2^64-1) + (2^128-2^65+1) = 2^128-1
 */
static void
fe_mul(fe r, const fe a, const fe b, const fe p)
{
	u64int res[8];
	u128 acc;
	int i, j, k;

	USED(p);
	memset(res, 0, sizeof(res));

	for(i = 0; i < 4; i++){
		acc = 0;
		for(j = 0; j < 4; j++){
			acc += (u128)res[i+j] + (u128)a[i] * b[j];
			res[i+j] = (u64int)acc;
			acc >>= 64;
		}
		/* propagate remaining carry */
		for(k = i+4; acc != 0 && k < 8; k++){
			acc += res[k];
			res[k] = (u64int)acc;
			acc >>= 64;
		}
	}

	p256_reduce(r, res);
}

/* r = a^2 mod p */
static void
fe_sqr(fe r, const fe a)
{
	fe_mul(r, a, a, P256_P);
}

/* r = a^(p-2) mod p (modular inverse via Fermat's little theorem) */
static void
fe_inv(fe r, const fe a)
{
	fe x2, x3, x6, x12, x15, x30, x32, e;
	int i;

	/* x2 = a^(2^2 - 1) = a^3 */
	fe_sqr(x2, a);
	fe_mul(x2, x2, a, P256_P);

	/* x3 = a^(2^3 - 1) = a^7 */
	fe_sqr(x3, x2);
	fe_mul(x3, x3, a, P256_P);

	/* x6 = a^(2^6 - 1) */
	fe_copy(e, x3);
	for(i = 0; i < 3; i++) fe_sqr(e, e);
	fe_mul(x6, e, x3, P256_P);

	/* x12 = a^(2^12 - 1) */
	fe_copy(e, x6);
	for(i = 0; i < 6; i++) fe_sqr(e, e);
	fe_mul(x12, e, x6, P256_P);

	/* x15 = a^(2^15 - 1) */
	fe_copy(e, x12);
	for(i = 0; i < 3; i++) fe_sqr(e, e);
	fe_mul(x15, e, x3, P256_P);

	/* x30 = a^(2^30 - 1) */
	fe_copy(e, x15);
	for(i = 0; i < 15; i++) fe_sqr(e, e);
	fe_mul(x30, e, x15, P256_P);

	/* x32 = a^(2^32 - 1) */
	fe_copy(e, x30);
	fe_sqr(e, e);
	fe_sqr(e, e);
	fe_mul(x32, e, x2, P256_P);

	/*
	 * p-2 in binary (MSB first):
	 * 32 ones | 31 zeros | 1 | 96 zeros | 32 ones | 32 ones | 30 ones | 0 | 1
	 */
	fe_copy(e, x32);				/* bits 255..224: 32 ones */
	for(i = 0; i < 32; i++) fe_sqr(e, e);	/* bits 223..193: 31 zeros + bit 192 */
	fe_mul(e, e, a, P256_P);			/* bit 192 = 1 */
	for(i = 0; i < 96; i++) fe_sqr(e, e);	/* bits 191..96: 96 zeros */
	for(i = 0; i < 32; i++) fe_sqr(e, e);	/* bits 95..64 */
	fe_mul(e, e, x32, P256_P);			/* 32 ones */
	for(i = 0; i < 32; i++) fe_sqr(e, e);	/* bits 63..32 */
	fe_mul(e, e, x32, P256_P);			/* 32 ones */
	for(i = 0; i < 30; i++) fe_sqr(e, e);	/* bits 31..2: 30 ones */
	fe_mul(e, e, x30, P256_P);
	fe_sqr(e, e);				/* bit 1: 0 */
	fe_sqr(e, e);				/* bit 0: 1 */
	fe_mul(r, e, a, P256_P);
}

/*
 * Byte conversion (32-byte big-endian <-> fe little-endian 64-bit limbs)
 */

static void
bytes_to_fe(fe r, const uchar *b)
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
fe_to_bytes(uchar *b, const fe a)
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
 * Curve: y^2 = x^3 - 3x + b (a = -3 enables faster doubling).
 */

/* point doubling: R = 2*P, cost: 4M + 4S (using a = -3) */
static void
point_double(fe X3, fe Y3, fe Z3,
	const fe X1, const fe Y1, const fe Z1)
{
	fe delta, gamma, beta, alpha, t1, t2;

	if(fe_is_zero(Z1)){
		fe_zero(X3); fe_zero(Y3); fe_zero(Z3);
		return;
	}

	fe_sqr(delta, Z1);			/* delta = Z1^2 */
	fe_sqr(gamma, Y1);			/* gamma = Y1^2 */
	fe_mul(beta, X1, gamma, P256_P);	/* beta = X1 * gamma */

	/* alpha = 3*(X1 - delta)*(X1 + delta) */
	fe_sub(t1, X1, delta, P256_P);
	fe_add(t2, X1, delta, P256_P);
	fe_mul(alpha, t1, t2, P256_P);
	fe_add(t1, alpha, alpha, P256_P);
	fe_add(alpha, t1, alpha, P256_P);	/* alpha = 3 * ... */

	/* X3 = alpha^2 - 8*beta */
	fe_sqr(X3, alpha);
	fe_add(t1, beta, beta, P256_P);	/* 2*beta */
	fe_add(t1, t1, t1, P256_P);		/* 4*beta */
	fe_add(t2, t1, t1, P256_P);		/* 8*beta */
	fe_sub(X3, X3, t2, P256_P);

	/* Z3 = (Y1+Z1)^2 - gamma - delta */
	fe_add(Z3, Y1, Z1, P256_P);
	fe_sqr(Z3, Z3);
	fe_sub(Z3, Z3, gamma, P256_P);
	fe_sub(Z3, Z3, delta, P256_P);

	/* Y3 = alpha*(4*beta - X3) - 8*gamma^2 */
	fe_sub(t2, t1, X3, P256_P);		/* 4*beta - X3 */
	fe_mul(Y3, alpha, t2, P256_P);
	fe_sqr(t1, gamma);			/* gamma^2 */
	fe_add(t1, t1, t1, P256_P);		/* 2*gamma^2 */
	fe_add(t1, t1, t1, P256_P);		/* 4*gamma^2 */
	fe_add(t1, t1, t1, P256_P);		/* 8*gamma^2 */
	fe_sub(Y3, Y3, t1, P256_P);
}

/* point addition: R = P + Q, cost: 11M + 5S */
static void
point_add(fe X3, fe Y3, fe Z3,
	const fe X1, const fe Y1, const fe Z1,
	const fe X2, const fe Y2, const fe Z2)
{
	fe Z1Z1, Z2Z2, U1, U2, S1, S2, H, I, J, rr, V, t;

	if(fe_is_zero(Z1)){
		fe_copy(X3, X2); fe_copy(Y3, Y2); fe_copy(Z3, Z2);
		return;
	}
	if(fe_is_zero(Z2)){
		fe_copy(X3, X1); fe_copy(Y3, Y1); fe_copy(Z3, Z1);
		return;
	}

	fe_sqr(Z1Z1, Z1);
	fe_sqr(Z2Z2, Z2);
	fe_mul(U1, X1, Z2Z2, P256_P);
	fe_mul(U2, X2, Z1Z1, P256_P);
	fe_mul(S1, Y1, Z2, P256_P);
	fe_mul(S1, S1, Z2Z2, P256_P);
	fe_mul(S2, Y2, Z1, P256_P);
	fe_mul(S2, S2, Z1Z1, P256_P);

	fe_sub(H, U2, U1, P256_P);
	if(fe_is_zero(H)){
		fe_sub(t, S2, S1, P256_P);
		if(fe_is_zero(t)){
			point_double(X3, Y3, Z3, X1, Y1, Z1);
			return;
		}
		fe_zero(X3); fe_zero(Y3); fe_zero(Z3);
		return;
	}

	fe_add(I, H, H, P256_P);
	fe_sqr(I, I);			/* I = (2*H)^2 */
	fe_mul(J, H, I, P256_P);	/* J = H * I */
	fe_sub(rr, S2, S1, P256_P);
	fe_add(rr, rr, rr, P256_P);	/* rr = 2*(S2 - S1) */
	fe_mul(V, U1, I, P256_P);

	/* X3 = rr^2 - J - 2*V */
	fe_sqr(X3, rr);
	fe_sub(X3, X3, J, P256_P);
	fe_sub(X3, X3, V, P256_P);
	fe_sub(X3, X3, V, P256_P);

	/* Y3 = rr*(V - X3) - 2*S1*J */
	fe_sub(t, V, X3, P256_P);
	fe_mul(Y3, rr, t, P256_P);
	fe_mul(t, S1, J, P256_P);
	fe_add(t, t, t, P256_P);
	fe_sub(Y3, Y3, t, P256_P);

	/* Z3 = ((Z1+Z2)^2 - Z1Z1 - Z2Z2) * H */
	fe_add(Z3, Z1, Z2, P256_P);
	fe_sqr(Z3, Z3);
	fe_sub(Z3, Z3, Z1Z1, P256_P);
	fe_sub(Z3, Z3, Z2Z2, P256_P);
	fe_mul(Z3, Z3, H, P256_P);
}

/* convert Jacobian to affine coordinates */
static void
point_to_affine(uchar outx[32], uchar outy[32],
	const fe X, const fe Y, const fe Z)
{
	fe zinv, zinv2, zinv3, ax, ay;

	fe_inv(zinv, Z);
	fe_sqr(zinv2, zinv);
	fe_mul(zinv3, zinv2, zinv, P256_P);
	fe_mul(ax, X, zinv2, P256_P);
	fe_mul(ay, Y, zinv3, P256_P);
	fe_to_bytes(outx, ax);
	fe_to_bytes(outy, ay);
}

/*
 * Constant-time Montgomery ladder scalar multiplication.
 * Processes bits from MSB to LSB.
 * scalar is 32 bytes, big-endian.
 */
static void
point_mul(fe RX, fe RY, fe RZ,
	const uchar scalar[32],
	const fe PX, const fe PY, const fe PZ)
{
	fe R0X, R0Y, R0Z;
	fe R1X, R1Y, R1Z;
	int i, bit, swap;

	/* R0 = infinity, R1 = P */
	fe_zero(R0X); fe_zero(R0Y); fe_zero(R0Z);
	fe_copy(R1X, PX); fe_copy(R1Y, PY); fe_copy(R1Z, PZ);

	swap = 0;
	for(i = 255; i >= 0; i--){
		bit = (scalar[31 - i/8] >> (i & 7)) & 1;
		swap ^= bit;
		fe_cswap(R0X, R1X, swap);
		fe_cswap(R0Y, R1Y, swap);
		fe_cswap(R0Z, R1Z, swap);
		swap = bit;

		point_add(R1X, R1Y, R1Z,
			R0X, R0Y, R0Z, R1X, R1Y, R1Z);
		point_double(R0X, R0Y, R0Z,
			R0X, R0Y, R0Z);
	}
	fe_cswap(R0X, R1X, swap);
	fe_cswap(R0Y, R1Y, swap);
	fe_cswap(R0Z, R1Z, swap);

	fe_copy(RX, R0X);
	fe_copy(RY, R0Y);
	fe_copy(RZ, R0Z);
}

/* check that affine point (x, y) is on the curve: y^2 = x^3 - 3x + b */
static int
point_on_curve(const fe x, const fe y)
{
	fe lhs, rhs, t;

	fe_sqr(lhs, y);			/* y^2 */
	fe_sqr(rhs, x);
	fe_mul(rhs, rhs, x, P256_P);		/* x^3 */
	fe_add(t, x, x, P256_P);
	fe_add(t, t, x, P256_P);		/* 3*x */
	fe_sub(rhs, rhs, t, P256_P);		/* x^3 - 3x */
	fe_add(rhs, rhs, P256_B, P256_P);	/* x^3 - 3x + b */
	return fe_eq(lhs, rhs);
}

/*
 * Public API
 */

int
p256_keygen(uchar priv[32], ECpoint *pub)
{
	fe kfe, one;
	fe RX, RY, RZ;
	uchar kbuf[32];

	/* generate random scalar, ensure 0 < k < n */
	genrandom(kbuf, 32);
	bytes_to_fe(kfe, kbuf);
	if(fe_is_zero(kfe) || fe_gte(kfe, P256_N))
		kbuf[0] = 1;  /* simple fix for edge cases */

	memmove(priv, kbuf, 32);

	/* compute public key = k * G */
	one[0] = 1; one[1] = 0; one[2] = 0; one[3] = 0;
	point_mul(RX, RY, RZ, priv, P256_Gx, P256_Gy, one);

	if(fe_is_zero(RZ))
		return -1;

	point_to_affine(pub->x, pub->y, RX, RY, RZ);

	/* validate generated point is on curve */
	{
		fe chkx, chky;
		bytes_to_fe(chkx, pub->x);
		bytes_to_fe(chky, pub->y);
		if(!point_on_curve(chkx, chky))
			return -1;
	}
	return 0;
}

int
p256_ecdh(uchar shared[32], uchar priv[32], ECpoint *peerpub)
{
	fe px, py, one;
	fe RX, RY, RZ;
	fe zinv, zinv2, ax;

	bytes_to_fe(px, peerpub->x);
	bytes_to_fe(py, peerpub->y);

	/* validate peer public key */
	if(fe_is_zero(px) && fe_is_zero(py))
		return -1;
	if(!point_on_curve(px, py))
		return -1;

	one[0] = 1; one[1] = 0; one[2] = 0; one[3] = 0;
	point_mul(RX, RY, RZ, priv, px, py, one);

	if(fe_is_zero(RZ))
		return -1;

	/* shared secret = x-coordinate of result */
	fe_inv(zinv, RZ);
	fe_sqr(zinv2, zinv);
	fe_mul(ax, RX, zinv2, P256_P);
	fe_to_bytes(shared, ax);
	return 0;
}

/*
 * ECDSA uses mpint for scalar arithmetic mod n.
 */

/* helper: convert 32-byte big-endian to mpint */
static mpint*
fe_to_mp(const uchar *b, int len)
{
	return betomp((uchar*)b, len, nil);
}

/* helper: convert mpint to 32-byte big-endian, zero-padded */
static void
mp_to_bytes(uchar out[32], mpint *m)
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

int
p256_ecdsa_sign(uchar sig[64], uchar priv[32], uchar *hash, int hashlen)
{
	mpint *n, *k, *r, *s, *e, *d, *kinv, *t;
	fe one, RX, RY, RZ;
	uchar kbuf[32], xbuf[32];
	uchar hbuf[32];
	int i;

	n = fe_to_mp((uchar*)P256_N, 0);
	/* rebuild n from constant since fe is LE but betomp expects BE */
	{
		uchar nbuf[32];
		fe_to_bytes(nbuf, P256_N);
		mpfree(n);
		n = betomp(nbuf, 32, nil);
	}

	/* load private key */
	d = betomp(priv, 32, nil);

	/* load and truncate hash to 256 bits */
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

	for(i = 0; i < 100; i++){	/* retry loop */
		/* generate random k, 0 < k < n */
		genrandom(kbuf, 32);
		k = betomp(kbuf, 32, nil);
		mpmod(k, n, k);
		if(mpcmp(k, mpzero) == 0){
			mpfree(k);
			continue;
		}

		/* compute (x1, y1) = k * G */
		point_mul(RX, RY, RZ, kbuf, P256_Gx, P256_Gy, one);
		if(fe_is_zero(RZ)){
			mpfree(k);
			continue;
		}

		/* r = x1 mod n */
		point_to_affine(xbuf, hbuf, RX, RY, RZ);  /* reuse hbuf for y */
		mpfree(r);
		r = betomp(xbuf, 32, nil);
		mpmod(r, n, r);
		if(mpcmp(r, mpzero) == 0){
			mpfree(k);
			continue;
		}

		/* s = k^(-1) * (e + r*d) mod n */
		mpinvert(k, n, kinv);
		mpmul(r, d, t);		/* t = r * d */
		mpmod(t, n, t);
		mpadd(e, t, t);		/* t = e + r*d */
		mpmod(t, n, t);
		mpmul(kinv, t, s);		/* s = kinv * (e + r*d) */
		mpmod(s, n, s);
		mpfree(k);

		if(mpcmp(s, mpzero) == 0)
			continue;

		/* output (r, s) */
		mp_to_bytes(sig, r);
		mp_to_bytes(sig + 32, s);

		mpfree(r); mpfree(s); mpfree(kinv); mpfree(t);
		mpfree(n); mpfree(d); mpfree(e);
		return 0;
	}

	mpfree(r); mpfree(s); mpfree(kinv); mpfree(t);
	mpfree(n); mpfree(d); mpfree(e);
	return -1;
}

int
p256_ecdsa_verify(uchar sig[64], ECpoint *pub, uchar *hash, int hashlen)
{
	mpint *n, *r, *s, *e, *w, *u1m, *u2m;
	fe px, py, one;
	fe P1X, P1Y, P1Z, P2X, P2Y, P2Z, RX, RY, RZ;
	fe zinv, zinv2, ax;
	uchar u1buf[32], u2buf[32], hbuf[32], nbuf[32];
	int ok;

	/* load signature (r, s) */
	r = betomp(sig, 32, nil);
	s = betomp(sig + 32, 32, nil);

	/* load curve order */
	fe_to_bytes(nbuf, P256_N);
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

	mp_to_bytes(u1buf, u1m);
	mp_to_bytes(u2buf, u2m);

	/* validate public key */
	bytes_to_fe(px, pub->x);
	bytes_to_fe(py, pub->y);
	if(!point_on_curve(px, py)){
		mpfree(r); mpfree(s); mpfree(n); mpfree(e);
		mpfree(w); mpfree(u1m); mpfree(u2m);
		return 0;
	}

	/* compute u1*G + u2*Q */
	one[0] = 1; one[1] = 0; one[2] = 0; one[3] = 0;
	point_mul(P1X, P1Y, P1Z, u1buf, P256_Gx, P256_Gy, one);
	point_mul(P2X, P2Y, P2Z, u2buf, px, py, one);
	point_add(RX, RY, RZ, P1X, P1Y, P1Z, P2X, P2Y, P2Z);

	ok = 0;
	if(!fe_is_zero(RZ)){
		/* x1 = X / Z^2 */
		fe_inv(zinv, RZ);
		fe_sqr(zinv2, zinv);
		fe_mul(ax, RX, zinv2, P256_P);

		/* check x1 mod n == r */
		/* since p > n, x1 might need reduction mod n */
		fe_to_bytes(u1buf, ax);		/* reuse buffer */
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

/*
 * P-384 (secp384r1) ECDSA verify only.
 * Uses 64-bit limbs with __int128 for intermediate products.
 *
 * Field arithmetic over GF(p) where p = 2^384 - 2^128 - 2^96 + 2^32 - 1.
 * Same structure as P-256 but with 6 limbs (384 bits).
 * Only verification is implemented (no keygen, ECDH, or sign).
 */

typedef u64int fe384[6];	/* field element: 6x64-bit limbs, little-endian */

/* p = 2^384 - 2^128 - 2^96 + 2^32 - 1 */
static const fe384 P384_P = {
	0x00000000FFFFFFFFULL,
	0xFFFFFFFF00000000ULL,
	0xFFFFFFFFFFFFFFFEULL,
	0xFFFFFFFFFFFFFFFFULL,
	0xFFFFFFFFFFFFFFFFULL,
	0xFFFFFFFFFFFFFFFFULL
};

/* order n of the base point */
static const fe384 P384_N = {
	0xECEC196ACCC52973ULL,
	0x581A0DB248B0A77AULL,
	0xC7634D81F4372DDFULL,
	0xFFFFFFFFFFFFFFFFULL,
	0xFFFFFFFFFFFFFFFFULL,
	0xFFFFFFFFFFFFFFFFULL
};

/* curve parameter b */
static const fe384 P384_B = {
	0x2A85C8EDD3EC2AEFULL,
	0xC656398D8A2ED19DULL,
	0x0314088F5013875AULL,
	0x181D9C6EFE814112ULL,
	0x988E056BE3F82D19ULL,
	0xB3312FA7E23EE7E4ULL
};

/* base point Gx */
static const fe384 P384_Gx = {
	0x3A545E3872760AB7ULL,
	0x5502F25DBF55296CULL,
	0x59F741E082542A38ULL,
	0x6E1D3B628BA79B98ULL,
	0x8EB1C71EF320AD74ULL,
	0xAA87CA22BE8B0537ULL
};

/* base point Gy */
static const fe384 P384_Gy = {
	0x7A431D7C90EA0E5FULL,
	0x0A60B1CE1D7E819DULL,
	0xE9DA3113B5F0B8C0ULL,
	0xF8F41DBD289A147CULL,
	0x5D9E98BF9292DC29ULL,
	0x3617DE4A96262C6FULL
};

/*
 * P-384 field element helpers
 */

static void
fe384_copy(fe384 r, const fe384 a)
{
	int i;
	for(i = 0; i < 6; i++)
		r[i] = a[i];
}

static void
fe384_zero(fe384 r)
{
	int i;
	for(i = 0; i < 6; i++)
		r[i] = 0;
}

static int
fe384_is_zero(const fe384 a)
{
	return (a[0] | a[1] | a[2] | a[3] | a[4] | a[5]) == 0;
}

static int
fe384_eq(const fe384 a, const fe384 b)
{
	u64int d = 0;
	int i;
	for(i = 0; i < 6; i++)
		d |= a[i] ^ b[i];
	return d == 0;
}

/* constant-time conditional swap */
static void
fe384_cswap(fe384 a, fe384 b, int bit)
{
	u64int mask = (u64int)0 - (u64int)bit;
	u64int t;
	int i;

	for(i = 0; i < 6; i++){
		t = mask & (a[i] ^ b[i]);
		a[i] ^= t;
		b[i] ^= t;
	}
}

/* r = a + b mod p, handles carry when a + b >= 2^384 */
static void
fe384_add(fe384 r, const fe384 a, const fe384 b, const fe384 p)
{
	u128 c = 0;
	fe384 t, t2;
	int i;
	u64int carry, borrow, mask;

	for(i = 0; i < 6; i++){
		c += (u128)a[i] + b[i];
		t[i] = (u64int)c;
		c >>= 64;
	}
	carry = (u64int)c;

	/* subtract p from (carry:t) */
	borrow = 0;
	for(i = 0; i < 6; i++){
		u128 v = (u128)t[i] - p[i] - borrow;
		t2[i] = (u64int)v;
		borrow = (v >> 64) & 1;
	}
	/* underflow if carry < borrow: means (carry:t) < p, use t */
	mask = (u64int)0 - (carry < borrow);
	for(i = 0; i < 6; i++)
		r[i] = (t[i] & mask) | (t2[i] & ~mask);
}

/* r = a - b mod p */
static void
fe384_sub(fe384 r, const fe384 a, const fe384 b, const fe384 p)
{
	u64int borrow = 0;
	u64int mask;
	u128 c;
	fe384 t;
	int i;

	for(i = 0; i < 6; i++){
		u128 v = (u128)a[i] - b[i] - borrow;
		t[i] = (u64int)v;
		borrow = (v >> 64) & 1;
	}
	/* if borrow, add p */
	mask = (u64int)0 - borrow;
	c = 0;
	for(i = 0; i < 6; i++){
		c += (u128)t[i] + (p[i] & mask);
		r[i] = (u64int)c;
		c >>= 64;
	}
}

/* forward declarations */
static void bytes384_to_fe(fe384 r, const uchar *b);
static void fe384_to_bytes(uchar *b, const fe384 a);

/*
 * Reduce a 768-bit product mod p using mpint.
 */
static void
p384_reduce(fe384 r, const u64int res[12])
{
	mpint *mres, *mp;
	uchar rbuf[96], outbuf[49];
	uchar pbuf[48];
	int i, n;

	/* convert 768-bit LE result to big-endian bytes */
	for(i = 0; i < 12; i++){
		int j = (11-i)*8;
		rbuf[j]   = res[i]>>56; rbuf[j+1] = res[i]>>48;
		rbuf[j+2] = res[i]>>40; rbuf[j+3] = res[i]>>32;
		rbuf[j+4] = res[i]>>24; rbuf[j+5] = res[i]>>16;
		rbuf[j+6] = res[i]>>8;  rbuf[j+7] = res[i];
	}
	fe384_to_bytes(pbuf, P384_P);
	mres = betomp(rbuf, 96, nil);
	mp = betomp(pbuf, 48, nil);
	mpmod(mres, mp, mres);

	memset(pbuf, 0, 48);
	n = mptobe(mres, outbuf, sizeof(outbuf), nil);
	if(n > 0 && n <= 48)
		memmove(pbuf + 48 - n, outbuf, n);
	else if(n > 48)
		memmove(pbuf, outbuf + n - 48, 48);
	bytes384_to_fe(r, pbuf);
	mpfree(mres);
	mpfree(mp);
}

/*
 * r = a * b mod p
 * Operand scanning to avoid u128 overflow.
 */
static void
fe384_mul(fe384 r, const fe384 a, const fe384 b, const fe384 p)
{
	u64int res[12];
	u128 acc;
	int i, j, k;

	USED(p);
	memset(res, 0, sizeof(res));

	for(i = 0; i < 6; i++){
		acc = 0;
		for(j = 0; j < 6; j++){
			acc += (u128)res[i+j] + (u128)a[i] * b[j];
			res[i+j] = (u64int)acc;
			acc >>= 64;
		}
		for(k = i+6; acc != 0 && k < 12; k++){
			acc += res[k];
			res[k] = (u64int)acc;
			acc >>= 64;
		}
	}

	p384_reduce(r, res);
}

/* r = a^2 mod p */
static void
fe384_sqr(fe384 r, const fe384 a)
{
	fe384_mul(r, a, a, P384_P);
}

/* r = a^(p-2) mod p (modular inverse via Fermat's little theorem) */
static void
fe384_inv(fe384 r, const fe384 a)
{
	uchar pbuf[48], p2buf[48];
	int i, bit;

	/*
	 * Binary exponentiation: r = a^(p-2) mod p.
	 * p-2 is 384 bits. We scan from bit 383 down to 0.
	 */
	fe384_to_bytes(pbuf, P384_P);

	/* compute p-2 in big-endian bytes */
	memmove(p2buf, pbuf, 48);
	/* subtract 2 from the least significant byte */
	{
		int borrow = 2;
		for(i = 47; i >= 0 && borrow > 0; i--){
			int v = (int)p2buf[i] - borrow;
			if(v < 0){
				p2buf[i] = (uchar)(v + 256);
				borrow = 1;
			} else {
				p2buf[i] = (uchar)v;
				borrow = 0;
			}
		}
	}

	fe384_copy(r, a);
	for(i = 382; i >= 0; i--){
		fe384_sqr(r, r);
		bit = (p2buf[47 - i/8] >> (i & 7)) & 1;
		if(bit)
			fe384_mul(r, r, a, P384_P);
	}
}

/*
 * Byte conversion (48-byte big-endian <-> fe384 little-endian 64-bit limbs)
 */

static void
bytes384_to_fe(fe384 r, const uchar *b)
{
	int i;
	for(i = 0; i < 6; i++){
		int j = (5-i)*8;
		r[i] = (u64int)b[j]<<56 | (u64int)b[j+1]<<48
		     | (u64int)b[j+2]<<40 | (u64int)b[j+3]<<32
		     | (u64int)b[j+4]<<24 | (u64int)b[j+5]<<16
		     | (u64int)b[j+6]<<8 | (u64int)b[j+7];
	}
}

static void
fe384_to_bytes(uchar *b, const fe384 a)
{
	int i;
	for(i = 0; i < 6; i++){
		int j = (5-i)*8;
		b[j]   = a[i]>>56; b[j+1] = a[i]>>48;
		b[j+2] = a[i]>>40; b[j+3] = a[i]>>32;
		b[j+4] = a[i]>>24; b[j+5] = a[i]>>16;
		b[j+6] = a[i]>>8;  b[j+7] = a[i];
	}
}

/*
 * P-384 Jacobian point operations.
 * Same formulas as P-256 (both curves use a = -3).
 */

/* point doubling: R = 2*P */
static void
point384_double(fe384 X3, fe384 Y3, fe384 Z3,
	const fe384 X1, const fe384 Y1, const fe384 Z1)
{
	fe384 delta, gamma, beta, alpha, t1, t2;

	if(fe384_is_zero(Z1)){
		fe384_zero(X3); fe384_zero(Y3); fe384_zero(Z3);
		return;
	}

	fe384_sqr(delta, Z1);
	fe384_sqr(gamma, Y1);
	fe384_mul(beta, X1, gamma, P384_P);

	/* alpha = 3*(X1 - delta)*(X1 + delta) */
	fe384_sub(t1, X1, delta, P384_P);
	fe384_add(t2, X1, delta, P384_P);
	fe384_mul(alpha, t1, t2, P384_P);
	fe384_add(t1, alpha, alpha, P384_P);
	fe384_add(alpha, t1, alpha, P384_P);

	/* X3 = alpha^2 - 8*beta */
	fe384_sqr(X3, alpha);
	fe384_add(t1, beta, beta, P384_P);
	fe384_add(t1, t1, t1, P384_P);
	fe384_add(t2, t1, t1, P384_P);
	fe384_sub(X3, X3, t2, P384_P);

	/* Z3 = (Y1+Z1)^2 - gamma - delta */
	fe384_add(Z3, Y1, Z1, P384_P);
	fe384_sqr(Z3, Z3);
	fe384_sub(Z3, Z3, gamma, P384_P);
	fe384_sub(Z3, Z3, delta, P384_P);

	/* Y3 = alpha*(4*beta - X3) - 8*gamma^2 */
	fe384_sub(t2, t1, X3, P384_P);
	fe384_mul(Y3, alpha, t2, P384_P);
	fe384_sqr(t1, gamma);
	fe384_add(t1, t1, t1, P384_P);
	fe384_add(t1, t1, t1, P384_P);
	fe384_add(t1, t1, t1, P384_P);
	fe384_sub(Y3, Y3, t1, P384_P);
}

/* point addition: R = P + Q */
static void
point384_add(fe384 X3, fe384 Y3, fe384 Z3,
	const fe384 X1, const fe384 Y1, const fe384 Z1,
	const fe384 X2, const fe384 Y2, const fe384 Z2)
{
	fe384 Z1Z1, Z2Z2, U1, U2, S1, S2, HH, I, J, rr, V, t;

	if(fe384_is_zero(Z1)){
		fe384_copy(X3, X2); fe384_copy(Y3, Y2); fe384_copy(Z3, Z2);
		return;
	}
	if(fe384_is_zero(Z2)){
		fe384_copy(X3, X1); fe384_copy(Y3, Y1); fe384_copy(Z3, Z1);
		return;
	}

	fe384_sqr(Z1Z1, Z1);
	fe384_sqr(Z2Z2, Z2);
	fe384_mul(U1, X1, Z2Z2, P384_P);
	fe384_mul(U2, X2, Z1Z1, P384_P);
	fe384_mul(S1, Y1, Z2, P384_P);
	fe384_mul(S1, S1, Z2Z2, P384_P);
	fe384_mul(S2, Y2, Z1, P384_P);
	fe384_mul(S2, S2, Z1Z1, P384_P);

	fe384_sub(HH, U2, U1, P384_P);
	if(fe384_is_zero(HH)){
		fe384_sub(t, S2, S1, P384_P);
		if(fe384_is_zero(t)){
			point384_double(X3, Y3, Z3, X1, Y1, Z1);
			return;
		}
		fe384_zero(X3); fe384_zero(Y3); fe384_zero(Z3);
		return;
	}

	fe384_add(I, HH, HH, P384_P);
	fe384_sqr(I, I);
	fe384_mul(J, HH, I, P384_P);
	fe384_sub(rr, S2, S1, P384_P);
	fe384_add(rr, rr, rr, P384_P);
	fe384_mul(V, U1, I, P384_P);

	/* X3 = rr^2 - J - 2*V */
	fe384_sqr(X3, rr);
	fe384_sub(X3, X3, J, P384_P);
	fe384_sub(X3, X3, V, P384_P);
	fe384_sub(X3, X3, V, P384_P);

	/* Y3 = rr*(V - X3) - 2*S1*J */
	fe384_sub(t, V, X3, P384_P);
	fe384_mul(Y3, rr, t, P384_P);
	fe384_mul(t, S1, J, P384_P);
	fe384_add(t, t, t, P384_P);
	fe384_sub(Y3, Y3, t, P384_P);

	/* Z3 = ((Z1+Z2)^2 - Z1Z1 - Z2Z2) * H */
	fe384_add(Z3, Z1, Z2, P384_P);
	fe384_sqr(Z3, Z3);
	fe384_sub(Z3, Z3, Z1Z1, P384_P);
	fe384_sub(Z3, Z3, Z2Z2, P384_P);
	fe384_mul(Z3, Z3, HH, P384_P);
}

/* convert Jacobian to affine coordinates */
static void
point384_to_affine(uchar outx[48], uchar outy[48],
	const fe384 X, const fe384 Y, const fe384 Z)
{
	fe384 zinv, zinv2, zinv3, ax, ay;

	fe384_inv(zinv, Z);
	fe384_sqr(zinv2, zinv);
	fe384_mul(zinv3, zinv2, zinv, P384_P);
	fe384_mul(ax, X, zinv2, P384_P);
	fe384_mul(ay, Y, zinv3, P384_P);
	fe384_to_bytes(outx, ax);
	fe384_to_bytes(outy, ay);
}

/*
 * Constant-time Montgomery ladder scalar multiplication.
 * scalar is 48 bytes, big-endian.
 */
static void
point384_mul(fe384 RX, fe384 RY, fe384 RZ,
	const uchar scalar[48],
	const fe384 PX, const fe384 PY, const fe384 PZ)
{
	fe384 R0X, R0Y, R0Z;
	fe384 R1X, R1Y, R1Z;
	int i, bit, swap;

	fe384_zero(R0X); fe384_zero(R0Y); fe384_zero(R0Z);
	fe384_copy(R1X, PX); fe384_copy(R1Y, PY); fe384_copy(R1Z, PZ);

	swap = 0;
	for(i = 383; i >= 0; i--){
		bit = (scalar[47 - i/8] >> (i & 7)) & 1;
		swap ^= bit;
		fe384_cswap(R0X, R1X, swap);
		fe384_cswap(R0Y, R1Y, swap);
		fe384_cswap(R0Z, R1Z, swap);
		swap = bit;

		point384_add(R1X, R1Y, R1Z,
			R0X, R0Y, R0Z, R1X, R1Y, R1Z);
		point384_double(R0X, R0Y, R0Z,
			R0X, R0Y, R0Z);
	}
	fe384_cswap(R0X, R1X, swap);
	fe384_cswap(R0Y, R1Y, swap);
	fe384_cswap(R0Z, R1Z, swap);

	fe384_copy(RX, R0X);
	fe384_copy(RY, R0Y);
	fe384_copy(RZ, R0Z);
}

/* check that affine point (x, y) is on the P-384 curve: y^2 = x^3 - 3x + b */
static int
point384_on_curve(const fe384 x, const fe384 y)
{
	fe384 lhs, rhs, t;

	fe384_sqr(lhs, y);
	fe384_sqr(rhs, x);
	fe384_mul(rhs, rhs, x, P384_P);
	fe384_add(t, x, x, P384_P);
	fe384_add(t, t, x, P384_P);
	fe384_sub(rhs, rhs, t, P384_P);
	fe384_add(rhs, rhs, P384_B, P384_P);
	return fe384_eq(lhs, rhs);
}

/* helper: convert mpint to 48-byte big-endian, zero-padded */
static void
mp384_to_bytes(uchar out[48], mpint *m)
{
	uchar buf[49];
	int n;

	memset(out, 0, 48);
	n = mptobe(m, buf, sizeof(buf), nil);
	if(n > 0 && n <= 48)
		memmove(out + 48 - n, buf, n);
	else if(n > 48)
		memmove(out, buf + n - 48, 48);
}

/*
 * P-384 ECDSA verification.
 * sig = r[48] || s[48], pub = affine point, hash = message digest.
 */
int
p384_ecdsa_verify(uchar sig[96], ECpoint384 *pub, uchar *hash, int hashlen)
{
	mpint *n, *r, *s, *e, *w, *u1m, *u2m;
	fe384 px, py, one;
	fe384 P1X, P1Y, P1Z, P2X, P2Y, P2Z, RX, RY, RZ;
	fe384 zinv, zinv2, ax;
	uchar u1buf[48], u2buf[48], hbuf[48], nbuf[48];
	int ok;

	/* load signature (r, s) */
	r = betomp(sig, 48, nil);
	s = betomp(sig + 48, 48, nil);

	/* load curve order */
	fe384_to_bytes(nbuf, P384_N);
	n = betomp(nbuf, 48, nil);

	/* check 1 <= r, s <= n-1 */
	if(mpcmp(r, mpzero) <= 0 || mpcmp(r, n) >= 0 ||
	   mpcmp(s, mpzero) <= 0 || mpcmp(s, n) >= 0){
		mpfree(r); mpfree(s); mpfree(n);
		return 0;
	}

	/* load and truncate hash to 384 bits */
	if(hashlen >= 48)
		memmove(hbuf, hash, 48);
	else{
		memset(hbuf, 0, 48);
		memmove(hbuf + 48 - hashlen, hash, hashlen);
	}
	e = betomp(hbuf, 48, nil);
	mpmod(e, n, e);

	/* w = s^(-1) mod n */
	w = mpnew(384);
	mpinvert(s, n, w);

	/* u1 = e * w mod n, u2 = r * w mod n */
	u1m = mpnew(768);
	u2m = mpnew(768);
	mpmul(e, w, u1m);
	mpmod(u1m, n, u1m);
	mpmul(r, w, u2m);
	mpmod(u2m, n, u2m);

	mp384_to_bytes(u1buf, u1m);
	mp384_to_bytes(u2buf, u2m);

	/* validate public key */
	bytes384_to_fe(px, pub->x);
	bytes384_to_fe(py, pub->y);
	if(!point384_on_curve(px, py)){
		mpfree(r); mpfree(s); mpfree(n); mpfree(e);
		mpfree(w); mpfree(u1m); mpfree(u2m);
		return 0;
	}

	/* compute u1*G + u2*Q */
	one[0] = 1; one[1] = 0; one[2] = 0; one[3] = 0; one[4] = 0; one[5] = 0;
	point384_mul(P1X, P1Y, P1Z, u1buf, P384_Gx, P384_Gy, one);
	point384_mul(P2X, P2Y, P2Z, u2buf, px, py, one);
	point384_add(RX, RY, RZ, P1X, P1Y, P1Z, P2X, P2Y, P2Z);

	ok = 0;
	if(!fe384_is_zero(RZ)){
		/* x1 = X / Z^2 */
		fe384_inv(zinv, RZ);
		fe384_sqr(zinv2, zinv);
		fe384_mul(ax, RX, zinv2, P384_P);

		/* check x1 mod n == r */
		fe384_to_bytes(u1buf, ax);
		{
			mpint *xmp = betomp(u1buf, 48, nil);
			mpmod(xmp, n, xmp);
			ok = mpcmp(xmp, r) == 0;
			mpfree(xmp);
		}
	}

	mpfree(r); mpfree(s); mpfree(n); mpfree(e);
	mpfree(w); mpfree(u1m); mpfree(u2m);
	return ok;
}
