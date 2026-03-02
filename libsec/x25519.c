/*
 * X25519 Diffie-Hellman key exchange (RFC 7748).
 * Montgomery ladder scalar multiplication on Curve25519.
 *
 * Based on curve25519-donna-c64 (public domain, Adam Langley).
 * Uses 128-bit integers via __int128 GCC extension (native on ARM64).
 */
#include "os.h"
#include <libsec.h>

typedef unsigned __int128 uint128_t;
typedef u64int felem[5];  /* field element: 5 limbs, 51 bits each */

#define MASK51 ((1ULL<<51)-1)

static void
fexpand(felem out, const uchar *in)
{
	out[0] = (u64int)in[0] | ((u64int)in[1]<<8) | ((u64int)in[2]<<16)
	       | ((u64int)in[3]<<24) | ((u64int)in[4]<<32)
	       | ((u64int)in[5]<<40) | (((u64int)in[6]&0x07)<<48);
	out[1] = ((u64int)in[6]>>3) | ((u64int)in[7]<<5) | ((u64int)in[8]<<13)
	       | ((u64int)in[9]<<21) | ((u64int)in[10]<<29)
	       | ((u64int)in[11]<<37) | (((u64int)in[12]&0x3f)<<45);
	out[2] = ((u64int)in[12]>>6) | ((u64int)in[13]<<2) | ((u64int)in[14]<<10)
	       | ((u64int)in[15]<<18) | ((u64int)in[16]<<26)
	       | ((u64int)in[17]<<34) | ((u64int)in[18]<<42)
	       | (((u64int)in[19]&0x01)<<50);
	out[3] = ((u64int)in[19]>>1) | ((u64int)in[20]<<7) | ((u64int)in[21]<<15)
	       | ((u64int)in[22]<<23) | ((u64int)in[23]<<31)
	       | ((u64int)in[24]<<39) | (((u64int)in[25]&0x0f)<<47);
	out[4] = ((u64int)in[25]>>4) | ((u64int)in[26]<<4) | ((u64int)in[27]<<12)
	       | ((u64int)in[28]<<20) | ((u64int)in[29]<<28)
	       | ((u64int)in[30]<<36) | (((u64int)in[31]&0x7f)<<44);
}

static void
fcontract(uchar *out, const felem in)
{
	u64int t[5];
	int i;
	u64int mask;

	t[0] = in[0]; t[1] = in[1]; t[2] = in[2]; t[3] = in[3]; t[4] = in[4];

	/* carry and reduce */
	for(i = 0; i < 3; i++){
		t[1] += t[0] >> 51; t[0] &= MASK51;
		t[2] += t[1] >> 51; t[1] &= MASK51;
		t[3] += t[2] >> 51; t[2] &= MASK51;
		t[4] += t[3] >> 51; t[3] &= MASK51;
		t[0] += 19 * (t[4] >> 51); t[4] &= MASK51;
	}

	/* conditional subtraction of p = 2^255-19 */
	t[0] += 19;
	t[1] += t[0] >> 51; t[0] &= MASK51;
	t[2] += t[1] >> 51; t[1] &= MASK51;
	t[3] += t[2] >> 51; t[2] &= MASK51;
	t[4] += t[3] >> 51; t[3] &= MASK51;
	mask = ~((t[4] >> 51) - 1);
	t[4] &= MASK51;
	t[0] -= 19 & ~mask;
	t[1] += t[0] >> 63; t[0] &= MASK51;
	t[2] += t[1] >> 63; t[1] &= MASK51;
	t[3] += t[2] >> 63; t[2] &= MASK51;
	t[4] += t[3] >> 63; t[3] &= MASK51;

	out[0] = t[0]; out[1] = t[0]>>8; out[2] = t[0]>>16;
	out[3] = t[0]>>24; out[4] = t[0]>>32; out[5] = t[0]>>40;
	out[6] = (t[0]>>48) | (t[1]<<3);
	out[7] = t[1]>>5; out[8] = t[1]>>13; out[9] = t[1]>>21;
	out[10] = t[1]>>29; out[11] = t[1]>>37;
	out[12] = (t[1]>>45) | (t[2]<<6);
	out[13] = t[2]>>2; out[14] = t[2]>>10; out[15] = t[2]>>18;
	out[16] = t[2]>>26; out[17] = t[2]>>34; out[18] = t[2]>>42;
	out[19] = (t[2]>>50) | (t[3]<<1);
	out[20] = t[3]>>7; out[21] = t[3]>>15; out[22] = t[3]>>23;
	out[23] = t[3]>>31; out[24] = t[3]>>39;
	out[25] = (t[3]>>47) | (t[4]<<4);
	out[26] = t[4]>>4; out[27] = t[4]>>12; out[28] = t[4]>>20;
	out[29] = t[4]>>28; out[30] = t[4]>>36;
	out[31] = t[4]>>44;
}

static void
fmul(felem out, const felem a, const felem b)
{
	uint128_t t[5];
	u64int r0, r1, r2, r3, r4, c;
	u64int b19_1, b19_2, b19_3, b19_4;

	b19_1 = 19*b[1]; b19_2 = 19*b[2]; b19_3 = 19*b[3]; b19_4 = 19*b[4];

	t[0] = (uint128_t)a[0]*b[0] + (uint128_t)a[4]*b19_1
	     + (uint128_t)a[1]*b19_4 + (uint128_t)a[3]*b19_2 + (uint128_t)a[2]*b19_3;
	t[1] = (uint128_t)a[0]*b[1] + (uint128_t)a[1]*b[0]
	     + (uint128_t)a[4]*b19_2 + (uint128_t)a[2]*b19_4 + (uint128_t)a[3]*b19_3;
	t[2] = (uint128_t)a[0]*b[2] + (uint128_t)a[2]*b[0] + (uint128_t)a[1]*b[1]
	     + (uint128_t)a[4]*b19_3 + (uint128_t)a[3]*b19_4;
	t[3] = (uint128_t)a[0]*b[3] + (uint128_t)a[3]*b[0] + (uint128_t)a[1]*b[2] + (uint128_t)a[2]*b[1]
	     + (uint128_t)a[4]*b19_4;
	t[4] = (uint128_t)a[0]*b[4] + (uint128_t)a[4]*b[0] + (uint128_t)a[1]*b[3]
	     + (uint128_t)a[3]*b[1] + (uint128_t)a[2]*b[2];

	r0 = (u64int)t[0] & MASK51; c = (u64int)(t[0] >> 51);
	t[1] += c;
	r1 = (u64int)t[1] & MASK51; c = (u64int)(t[1] >> 51);
	t[2] += c;
	r2 = (u64int)t[2] & MASK51; c = (u64int)(t[2] >> 51);
	t[3] += c;
	r3 = (u64int)t[3] & MASK51; c = (u64int)(t[3] >> 51);
	t[4] += c;
	r4 = (u64int)t[4] & MASK51; c = (u64int)(t[4] >> 51);
	r0 += c * 19; c = r0 >> 51; r0 &= MASK51;
	r1 += c;

	out[0] = r0; out[1] = r1; out[2] = r2; out[3] = r3; out[4] = r4;
}

static void
fsquare(felem out, const felem a)
{
	fmul(out, a, a);
}

static void
fadd(felem out, const felem a, const felem b)
{
	out[0] = a[0]+b[0]; out[1] = a[1]+b[1]; out[2] = a[2]+b[2];
	out[3] = a[3]+b[3]; out[4] = a[4]+b[4];
}

static void
fsub(felem out, const felem a, const felem b)
{
	out[0] = a[0]+2*(MASK51-18)-b[0];
	out[1] = a[1]+2*MASK51-b[1];
	out[2] = a[2]+2*MASK51-b[2];
	out[3] = a[3]+2*MASK51-b[3];
	out[4] = a[4]+2*MASK51-b[4];
}

static void
fscalar(felem out, const felem a, u64int s)
{
	uint128_t t;
	u64int c;

	t = (uint128_t)a[0]*s; out[0] = (u64int)t & MASK51; c = (u64int)(t>>51);
	t = (uint128_t)a[1]*s+c; out[1] = (u64int)t & MASK51; c = (u64int)(t>>51);
	t = (uint128_t)a[2]*s+c; out[2] = (u64int)t & MASK51; c = (u64int)(t>>51);
	t = (uint128_t)a[3]*s+c; out[3] = (u64int)t & MASK51; c = (u64int)(t>>51);
	t = (uint128_t)a[4]*s+c; out[4] = (u64int)t & MASK51; c = (u64int)(t>>51);
	out[0] += c*19;
}

static void
fsquare_times(felem out, const felem a, int count)
{
	int i;
	memmove(out, a, sizeof(felem));
	for(i = 0; i < count; i++)
		fsquare(out, out);
}

/* z^(p-2) where p = 2^255-19, so p-2 = 2^255-21 */
static void
finvert(felem out, const felem z)
{
	felem z2, z9, z11, t;
	felem z_5_0;	/* z^(2^5 - 1) */
	felem z_10_0;	/* z^(2^10 - 1) */
	felem z_50_0;	/* z^(2^50 - 1) */
	felem z_100_0;	/* z^(2^100 - 1) */

	/* z^2 */
	fsquare(z2, z);
	/* z^4 */
	fsquare(t, z2);
	/* z^8 */
	fsquare(t, t);
	/* z^9 */
	fmul(z9, t, z);
	/* z^11 */
	fmul(z11, z9, z2);
	/* z^22 */
	fsquare(t, z11);
	/* z^(2^5-1) = z^31 */
	fmul(z_5_0, t, z9);

	/* z^(2^10-1) */
	fsquare_times(t, z_5_0, 5);
	fmul(z_10_0, t, z_5_0);

	/* z^(2^20-1) */
	fsquare_times(t, z_10_0, 10);
	fmul(t, t, z_10_0);

	/* z^(2^40-1) */
	fsquare_times(out, t, 20);
	fmul(t, out, t);

	/* z^(2^50-1) */
	fsquare_times(t, t, 10);
	fmul(z_50_0, t, z_10_0);

	/* z^(2^100-1) */
	fsquare_times(t, z_50_0, 50);
	fmul(z_100_0, t, z_50_0);

	/* z^(2^200-1) */
	fsquare_times(t, z_100_0, 100);
	fmul(t, t, z_100_0);

	/* z^(2^250-1) */
	fsquare_times(t, t, 50);
	fmul(t, t, z_50_0);

	/* z^(2^255-32) */
	fsquare_times(t, t, 5);

	/* z^(2^255-21) = z^(p-2) */
	fmul(out, t, z11);
}

static void
cswap(felem a, felem b, u64int sw)
{
	u64int mask = (u64int)0 - sw;
	u64int t;
	int k;

	for(k = 0; k < 5; k++){
		t = mask & (a[k] ^ b[k]);
		a[k] ^= t;
		b[k] ^= t;
	}
}

/*
 * Montgomery ladder: compute scalar * point on Curve25519.
 * scalar and point are 32 bytes, little-endian.
 */
void
x25519(uchar out[32], uchar scalar[32], uchar point[32])
{
	felem x1, x2, z2, x3, z3, tmp0, tmp1;
	uchar e[32];
	int pos, b, swap;

	memmove(e, scalar, 32);
	e[0] &= 248;
	e[31] &= 127;
	e[31] |= 64;

	fexpand(x1, point);

	x2[0] = 1; x2[1] = 0; x2[2] = 0; x2[3] = 0; x2[4] = 0;
	memset(z2, 0, sizeof(felem));
	memmove(x3, x1, sizeof(felem));
	z3[0] = 1; z3[1] = 0; z3[2] = 0; z3[3] = 0; z3[4] = 0;

	swap = 0;
	for(pos = 254; pos >= 0; pos--){
		b = (e[pos/8] >> (pos & 7)) & 1;
		swap ^= b;
		cswap(x2, x3, swap);
		cswap(z2, z3, swap);
		swap = b;

		fsub(tmp0, x3, z3);
		fsub(tmp1, x2, z2);
		fadd(x2, x2, z2);
		fadd(z2, x3, z3);
		fmul(z3, tmp0, x2);
		fmul(z2, z2, tmp1);
		fsquare(tmp0, tmp1);
		fsquare(tmp1, x2);
		fadd(x3, z3, z2);
		fsub(z2, z3, z2);
		fmul(x2, tmp1, tmp0);
		fsub(tmp1, tmp1, tmp0);
		fsquare(z2, z2);
		fscalar(z3, tmp1, 121666);
		fsquare(x3, x3);
		fadd(tmp0, tmp0, z3);
		fmul(z3, x1, z2);
		fmul(z2, tmp1, tmp0);
	}
	cswap(x2, x3, swap);
	cswap(z2, z3, swap);

	finvert(z2, z2);
	fmul(x2, x2, z2);
	fcontract(out, x2);
}

static uchar basepoint[32] = {9};

void
x25519_base(uchar out[32], uchar scalar[32])
{
	x25519(out, scalar, basepoint);
}
