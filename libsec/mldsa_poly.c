/*
 * ML-DSA polynomial operations (FIPS 204)
 *
 * Polynomial sampling, packing/unpacking, hint operations,
 * and decomposition functions.
 *
 * Reference: FIPS 204, Sections 8.1, 8.3, 8.4.
 */
#include "os.h"
#include <libsec.h>

enum {
	MLDSA_N = 256,
	MLDSA_Q = 8380417,
};

/*
 * Power2Round: decompose a into (a1, a0) where a = a1*2^d + a0.
 * Used in key generation.
 * d = 13 for ML-DSA.
 */
void
mldsa_power2round(int32 *a1, int32 *a0, int32 a)
{
	int32 t;

	/* Ensure a is positive */
	a += (a >> 31) & MLDSA_Q;
	t = a & ((1 << 13) - 1);	/* a mod 2^13 */

	/* Center a0 around 0 */
	if(t > (1 << 12))
		t -= (1 << 13);

	*a0 = t;
	*a1 = (a - t) >> 13;
}

/*
 * Decompose: split a into high and low bits.
 * For ML-DSA-65: gamma2 = (q-1)/32 = 261888
 * For ML-DSA-87: gamma2 = (q-1)/32 = 261888
 */
void
mldsa_decompose(int32 *a1, int32 *a0, int32 a, int32 gamma2)
{
	int32 t;

	/* Ensure positive */
	a += (a >> 31) & MLDSA_Q;

	*a0 = a % (2 * gamma2);
	if(*a0 > gamma2)
		*a0 -= 2 * gamma2;

	if(a - *a0 == MLDSA_Q - 1){
		*a1 = 0;
		*a0 = -1;
	} else {
		t = a - *a0;
		*a1 = t / (2 * gamma2);
	}
}

/*
 * HighBits: extract high bits of a.
 */
int32
mldsa_highbits(int32 a, int32 gamma2)
{
	int32 a1, a0;

	mldsa_decompose(&a1, &a0, a, gamma2);
	return a1;
}

/*
 * LowBits: extract low bits of a.
 */
int32
mldsa_lowbits(int32 a, int32 gamma2)
{
	int32 a1, a0;

	mldsa_decompose(&a1, &a0, a, gamma2);
	return a0;
}

/*
 * MakeHint: returns 1 if HighBits(a, gamma2) != HighBits(a - z, gamma2).
 */
int
mldsa_makehint(int32 z, int32 r, int32 gamma2)
{
	int32 h1, h2;

	h1 = mldsa_highbits(r, gamma2);
	h2 = mldsa_highbits(r + z, gamma2);
	return h1 != h2;
}

/*
 * UseHint: adjust high bits based on hint.
 */
int32
mldsa_usehint(int32 h, int32 a, int32 gamma2)
{
	int32 a1, a0;
	int32 m;

	mldsa_decompose(&a1, &a0, a, gamma2);

	m = (MLDSA_Q - 1) / (2 * gamma2);

	if(h == 0)
		return a1;

	if(a0 > 0)
		return (a1 + 1) % m;
	else
		return (a1 - 1 + m) % m;
}

/*
 * ExpandA: sample matrix A from rho using SHAKE-128.
 * Each element is a polynomial with coefficients uniform in [0, q).
 */
void
mldsa_poly_uniform(int32 r[MLDSA_N], const uchar rho[32], uchar i, uchar j)
{
	SHA3state s;
	uchar buf[168];	/* SHAKE-128 rate */
	int ctr, pos;
	u32int val;
	uchar idx[2];

	idx[0] = j;	/* FIPS 204 uses (j, i) order for nonce */
	idx[1] = i;

	shake128_init(&s);
	shake128_absorb(&s, rho, 32);
	shake128_absorb(&s, idx, 2);
	shake128_finalize(&s);

	ctr = 0;
	while(ctr < MLDSA_N){
		shake128_squeeze(&s, buf, sizeof(buf));
		for(pos = 0; pos + 3 <= (int)sizeof(buf) && ctr < MLDSA_N; pos += 3){
			val = (u32int)buf[pos];
			val |= (u32int)buf[pos+1] << 8;
			val |= (u32int)buf[pos+2] << 16;
			val &= 0x7FFFFF;
			if(val < (u32int)MLDSA_Q)
				r[ctr++] = (int32)val;
		}
	}
}

/*
 * Sample short polynomial with coefficients in [-eta, eta].
 * eta=4 for ML-DSA-65, eta=2 for ML-DSA-87.
 * Uses SHAKE-256 with (rhoprime || nonce).
 */
void
mldsa_poly_uniform_eta(int32 r[MLDSA_N], const uchar rhoprime[64],
	u16int nonce, int eta)
{
	SHA3state s;
	uchar buf[136];	/* SHAKE-256 rate */
	uchar nbuf[2];
	int ctr, pos;
	u32int t;
	int32 a, b;

	nbuf[0] = nonce & 0xFF;
	nbuf[1] = nonce >> 8;

	shake256_init(&s);
	shake256_absorb(&s, rhoprime, 64);
	shake256_absorb(&s, nbuf, 2);
	shake256_finalize(&s);

	ctr = 0;
	while(ctr < MLDSA_N){
		shake256_squeeze(&s, buf, sizeof(buf));
		for(pos = 0; pos < (int)sizeof(buf) && ctr < MLDSA_N; pos++){
			t = buf[pos];
			if(eta == 2){
				/* Sample from {0,1,2,3,4}, reject >= 15 */
				a = t & 0x0F;
				b = t >> 4;
				if(a < 15){
					a = a % 5;
					r[ctr++] = 2 - a;
				}
				if(ctr < MLDSA_N && b < 15){
					b = b % 5;
					r[ctr++] = 2 - b;
				}
			} else {
				/* eta == 4: sample from {0,...,8}, reject >= 9 */
				a = t & 0x0F;
				b = t >> 4;
				if(a < 9)
					r[ctr++] = 4 - a;
				if(ctr < MLDSA_N && b < 9)
					r[ctr++] = 4 - b;
			}
		}
	}
}

/*
 * Sample masking polynomial with coefficients in [-(gamma1-1), gamma1].
 * gamma1 = 2^17 for ML-DSA-65, 2^19 for ML-DSA-87.
 */
void
mldsa_poly_uniform_gamma1(int32 r[MLDSA_N], const uchar seed[64],
	u16int nonce, int gamma1_bits)
{
	SHA3state s;
	uchar buf[640];	/* enough for 256 coefficients at 20 bits each */
	uchar nbuf[2];
	int i, len;

	nbuf[0] = nonce & 0xFF;
	nbuf[1] = nonce >> 8;

	shake256_init(&s);
	shake256_absorb(&s, seed, 64);
	shake256_absorb(&s, nbuf, 2);
	shake256_finalize(&s);

	if(gamma1_bits == 17){
		/* 18-bit encoding: 4 coefficients per 9 bytes */
		len = MLDSA_N * 18 / 8;	/* 576 bytes */
		shake256_squeeze(&s, buf, len);
		for(i = 0; i < MLDSA_N/4; i++){
			u32int t0, t1, t2, t3;
			t0  = (u32int)buf[9*i+0];
			t0 |= (u32int)buf[9*i+1] << 8;
			t0 |= (u32int)buf[9*i+2] << 16;
			t0 &= 0x3FFFF;

			t1  = (u32int)buf[9*i+2] >> 2;
			t1 |= (u32int)buf[9*i+3] << 6;
			t1 |= (u32int)buf[9*i+4] << 14;
			t1 &= 0x3FFFF;

			t2  = (u32int)buf[9*i+4] >> 4;
			t2 |= (u32int)buf[9*i+5] << 4;
			t2 |= (u32int)buf[9*i+6] << 12;
			t2 &= 0x3FFFF;

			t3  = (u32int)buf[9*i+6] >> 6;
			t3 |= (u32int)buf[9*i+7] << 2;
			t3 |= (u32int)buf[9*i+8] << 10;
			t3 &= 0x3FFFF;

			r[4*i+0] = (1 << 17) - (int32)t0;
			r[4*i+1] = (1 << 17) - (int32)t1;
			r[4*i+2] = (1 << 17) - (int32)t2;
			r[4*i+3] = (1 << 17) - (int32)t3;
		}
	} else {
		/* gamma1_bits == 19: 20-bit encoding: 4 coefficients per 10 bytes */
		len = MLDSA_N * 20 / 8;	/* 640 bytes */
		shake256_squeeze(&s, buf, len);
		for(i = 0; i < MLDSA_N/2; i++){
			u32int t0, t1;
			t0  = (u32int)buf[5*i+0];
			t0 |= (u32int)buf[5*i+1] << 8;
			t0 |= (u32int)buf[5*i+2] << 16;
			t0 &= 0xFFFFF;

			t1  = (u32int)buf[5*i+2] >> 4;
			t1 |= (u32int)buf[5*i+3] << 4;
			t1 |= (u32int)buf[5*i+4] << 12;
			t1 &= 0xFFFFF;

			r[2*i+0] = (1 << 19) - (int32)t0;
			r[2*i+1] = (1 << 19) - (int32)t1;
		}
	}
}

/*
 * Pack polynomial with coefficients in [0, 2^bits - 1].
 * Used for packing t1 (10-bit coefficients).
 */
void
mldsa_poly_pack_t1(uchar *out, const int32 r[MLDSA_N])
{
	int i;

	/* 10-bit encoding: 4 coefficients per 5 bytes */
	for(i = 0; i < MLDSA_N/4; i++){
		u32int a = (u32int)r[4*i+0];
		u32int b = (u32int)r[4*i+1];
		u32int c = (u32int)r[4*i+2];
		u32int d = (u32int)r[4*i+3];
		out[5*i+0] = (uchar)a;
		out[5*i+1] = (uchar)((a >> 8) | (b << 2));
		out[5*i+2] = (uchar)((b >> 6) | (c << 4));
		out[5*i+3] = (uchar)((c >> 4) | (d << 6));
		out[5*i+4] = (uchar)(d >> 2);
	}
}

/*
 * Unpack t1 polynomial.
 */
void
mldsa_poly_unpack_t1(int32 r[MLDSA_N], const uchar *in)
{
	int i;

	for(i = 0; i < MLDSA_N/4; i++){
		r[4*i+0] = ((u32int)in[5*i+0]       | ((u32int)in[5*i+1] << 8)) & 0x3FF;
		r[4*i+1] = ((u32int)in[5*i+1] >> 2 | ((u32int)in[5*i+2] << 6)) & 0x3FF;
		r[4*i+2] = ((u32int)in[5*i+2] >> 4 | ((u32int)in[5*i+3] << 4)) & 0x3FF;
		r[4*i+3] = ((u32int)in[5*i+3] >> 6 | ((u32int)in[5*i+4] << 2)) & 0x3FF;
	}
}

/*
 * Pack t0 polynomial (13-bit signed coefficients centered at 0).
 */
void
mldsa_poly_pack_t0(uchar *out, const int32 r[MLDSA_N])
{
	int i;
	int32 t[8];

	for(i = 0; i < MLDSA_N/8; i++){
		int j;
		for(j = 0; j < 8; j++)
			t[j] = (1 << 12) - r[8*i+j];

		out[13*i+ 0] = (uchar)t[0];
		out[13*i+ 1] = (uchar)((t[0] >>  8) | (t[1] << 5));
		out[13*i+ 2] = (uchar)(t[1] >>  3);
		out[13*i+ 3] = (uchar)((t[1] >> 11) | (t[2] << 2));
		out[13*i+ 4] = (uchar)((t[2] >>  6) | (t[3] << 7));
		out[13*i+ 5] = (uchar)(t[3] >>  1);
		out[13*i+ 6] = (uchar)((t[3] >>  9) | (t[4] << 4));
		out[13*i+ 7] = (uchar)(t[4] >>  4);
		out[13*i+ 8] = (uchar)((t[4] >> 12) | (t[5] << 1));
		out[13*i+ 9] = (uchar)((t[5] >>  7) | (t[6] << 6));
		out[13*i+10] = (uchar)(t[6] >>  2);
		out[13*i+11] = (uchar)((t[6] >> 10) | (t[7] << 3));
		out[13*i+12] = (uchar)(t[7] >>  5);
	}
}

/*
 * Unpack t0 polynomial.
 */
void
mldsa_poly_unpack_t0(int32 r[MLDSA_N], const uchar *in)
{
	int i;

	for(i = 0; i < MLDSA_N/8; i++){
		r[8*i+0] = (u32int)in[13*i+0]       | ((u32int)in[13*i+1] << 8);
		r[8*i+0] &= 0x1FFF;

		r[8*i+1] = (u32int)in[13*i+1] >> 5 | ((u32int)in[13*i+2] << 3)
			  | ((u32int)in[13*i+3] << 11);
		r[8*i+1] &= 0x1FFF;

		r[8*i+2] = (u32int)in[13*i+3] >> 2 | ((u32int)in[13*i+4] << 6);
		r[8*i+2] &= 0x1FFF;

		r[8*i+3] = (u32int)in[13*i+4] >> 7 | ((u32int)in[13*i+5] << 1)
			  | ((u32int)in[13*i+6] << 9);
		r[8*i+3] &= 0x1FFF;

		r[8*i+4] = (u32int)in[13*i+6] >> 4 | ((u32int)in[13*i+7] << 4)
			  | ((u32int)in[13*i+8] << 12);
		r[8*i+4] &= 0x1FFF;

		r[8*i+5] = (u32int)in[13*i+8] >> 1 | ((u32int)in[13*i+9] << 7);
		r[8*i+5] &= 0x1FFF;

		r[8*i+6] = (u32int)in[13*i+9] >> 6 | ((u32int)in[13*i+10] << 2)
			  | ((u32int)in[13*i+11] << 10);
		r[8*i+6] &= 0x1FFF;

		r[8*i+7] = (u32int)in[13*i+11] >> 3 | ((u32int)in[13*i+12] << 5);
		r[8*i+7] &= 0x1FFF;

		/* Center around 0 */
		{
			int j;
			for(j = 0; j < 8; j++)
				r[8*i+j] = (1 << 12) - r[8*i+j];
		}
	}
}

/*
 * Check infinity norm of polynomial against bound.
 * Returns 1 if any coefficient has |coeff| >= bound.
 * Constant-time.
 */
int
mldsa_poly_chknorm(const int32 r[MLDSA_N], int32 bound)
{
	int i;
	int32 t;
	u32int fail;

	fail = 0;
	for(i = 0; i < MLDSA_N; i++){
		/* Absolute value, constant-time */
		t = r[i] >> 31;
		t = r[i] - (2 * r[i] & t);
		/* fail if t >= bound */
		fail |= (u32int)(bound - 1 - t) >> 31;
	}
	return (int)(fail & 1);
}

/*
 * Pack hint polynomial (sparse representation).
 * Returns the number of nonzero hints (omega).
 */
int
mldsa_pack_hint(uchar *out, int outlen, const int32 h[][MLDSA_N], int k, int omega)
{
	int i, j, cnt, total;

	memset(out, 0, outlen);
	total = 0;

	for(i = 0; i < k; i++){
		cnt = 0;
		for(j = 0; j < MLDSA_N; j++){
			if(h[i][j] != 0){
				if(total >= omega)
					return -1;	/* too many hints */
				out[total++] = (uchar)j;
				cnt++;
			}
		}
		out[omega + i] = (uchar)total;
	}

	return total;
}

/*
 * Unpack hint polynomial.
 */
int
mldsa_unpack_hint(int32 h[][MLDSA_N], int k, const uchar *in, int omega)
{
	int i, j, idx, prev;

	for(i = 0; i < k; i++)
		memset(h[i], 0, MLDSA_N * sizeof(int32));

	idx = 0;
	for(i = 0; i < k; i++){
		int limit = in[omega + i];
		if(limit < idx || limit > omega)
			return -1;
		prev = -1;
		for(j = idx; j < limit; j++){
			/* Indices must be strictly increasing */
			if((int)in[j] <= prev)
				return -1;
			prev = in[j];
			h[i][in[j]] = 1;
		}
		idx = limit;
	}

	/* Remaining entries must be zero */
	for(j = idx; j < omega; j++)
		if(in[j] != 0)
			return -1;

	return 0;
}
