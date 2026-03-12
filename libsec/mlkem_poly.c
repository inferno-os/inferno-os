/*
 * ML-KEM polynomial operations (FIPS 203)
 *
 * Polynomial sampling, compression/decompression,
 * encoding/decoding, and CBD sampling.
 *
 * Reference: FIPS 203, Sections 4.1, 4.2.
 */
#include "os.h"
#include <libsec.h>

enum {
	MLKEM_N = 256,
	MLKEM_Q = 3329,
};

/*
 * Centered Binomial Distribution sampling (CBD).
 * Sample polynomial with coefficients from CBD_eta.
 *
 * For eta=2: each coefficient is sum of 2 random bits minus sum of 2 random bits.
 * For eta=3: each coefficient is sum of 3 random bits minus sum of 3 random bits.
 */
void
mlkem_cbd2(int16 r[MLKEM_N], const uchar buf[128])
{
	u32int t, d;
	int i, j;

	for(i = 0; i < MLKEM_N/8; i++){
		t  = (u32int)buf[4*i];
		t |= (u32int)buf[4*i+1] << 8;
		t |= (u32int)buf[4*i+2] << 16;
		t |= (u32int)buf[4*i+3] << 24;
		d = t & 0x55555555;
		d += (t >> 1) & 0x55555555;
		for(j = 0; j < 8; j++){
			int16 a, b;
			a = (d >> (4*j)) & 0x3;
			b = (d >> (4*j+2)) & 0x3;
			r[8*i+j] = a - b;
		}
	}
}

void
mlkem_cbd3(int16 r[MLKEM_N], const uchar buf[192])
{
	u32int t, d;
	int i, j;

	for(i = 0; i < MLKEM_N/4; i++){
		t  = (u32int)buf[3*i];
		t |= (u32int)buf[3*i+1] << 8;
		t |= (u32int)buf[3*i+2] << 16;
		d = t & 0x00249249;
		d += (t >> 1) & 0x00249249;
		d += (t >> 2) & 0x00249249;
		for(j = 0; j < 4; j++){
			int16 a, b;
			a = (d >> (6*j)) & 0x7;
			b = (d >> (6*j+3)) & 0x7;
			r[4*i+j] = a - b;
		}
	}
}

/*
 * Sample polynomial from SHAKE-128 output via rejection sampling.
 * This generates a uniformly random polynomial in NTT domain.
 * Used for sampling the matrix A.
 */
void
mlkem_poly_sample_ntt(int16 r[MLKEM_N], const uchar seed[32], uchar x, uchar y)
{
	SHA3state s;
	uchar buf[168];	/* one SHAKE-128 block */
	int ctr, j;
	u16int val0, val1;

	shake128_init(&s);
	shake128_absorb(&s, seed, 32);
	shake128_absorb(&s, &x, 1);
	shake128_absorb(&s, &y, 1);
	shake128_finalize(&s);

	ctr = 0;
	while(ctr < MLKEM_N){
		shake128_squeeze(&s, buf, sizeof(buf));
		for(j = 0; j + 3 <= (int)sizeof(buf) && ctr < MLKEM_N; j += 3){
			val0 = ((u16int)buf[j]   | ((u16int)buf[j+1] << 8)) & 0x0FFF;
			val1 = ((u16int)buf[j+1] >> 4 | ((u16int)buf[j+2] << 4)) & 0x0FFF;
			if(val0 < MLKEM_Q)
				r[ctr++] = (int16)val0;
			if(ctr < MLKEM_N && val1 < MLKEM_Q)
				r[ctr++] = (int16)val1;
		}
	}
}

/*
 * Sample noise polynomial using CBD from SHAKE-256 output.
 * eta=2 for ML-KEM-768, eta=3 for ML-KEM-512.
 */
void
mlkem_poly_sample_cbd(int16 r[MLKEM_N], const uchar seed[32], uchar nonce, int eta)
{
	SHA3state s;
	uchar buf[192];	/* max(eta*N/4) = max(128, 192) */
	int len;

	len = eta * MLKEM_N / 4;	/* 128 for eta=2, 192 for eta=3 */

	shake256_init(&s);
	shake256_absorb(&s, seed, 32);
	shake256_absorb(&s, &nonce, 1);
	shake256_finalize(&s);
	shake256_squeeze(&s, buf, len);

	if(eta == 2)
		mlkem_cbd2(r, buf);
	else
		mlkem_cbd3(r, buf);
}

/*
 * Compress: round(2^d / q * x) mod 2^d
 * Constant-time compression of a coefficient.
 */
static u16int
compress(int16 x, int d)
{
	u32int t;

	/* Ensure x is in [0, q) */
	t = (u32int)(int32)x;
	t += (MLKEM_Q & (0u - (t >> 31)));	/* if negative, add q */

	/* round((2^d * t + q/2) / q) mod 2^d */
	t = ((t << d) + MLKEM_Q/2) / MLKEM_Q;
	t &= (1u << d) - 1;
	return (u16int)t;
}

/*
 * Decompress: round(q / 2^d * x)
 */
static int16
decompress(u16int x, int d)
{
	u32int t;

	t = ((u32int)x * MLKEM_Q + (1u << (d-1))) >> d;
	return (int16)t;
}

/*
 * Encode polynomial to byte array.
 * Each coefficient is encoded using 'bits' bits.
 */
void
mlkem_poly_encode(uchar *out, const int16 r[MLKEM_N], int bits)
{
	int i;

	if(bits == 12){
		/* 12-bit encoding: 2 coefficients per 3 bytes */
		for(i = 0; i < MLKEM_N/2; i++){
			u16int a, b;
			a = (u16int)r[2*i];
			b = (u16int)r[2*i+1];
			out[3*i]   = (uchar)a;
			out[3*i+1] = (uchar)((a >> 8) | (b << 4));
			out[3*i+2] = (uchar)(b >> 4);
		}
	} else if(bits == 10){
		/* 10-bit encoding: 4 coefficients per 5 bytes */
		for(i = 0; i < MLKEM_N/4; i++){
			u16int a = (u16int)r[4*i];
			u16int b = (u16int)r[4*i+1];
			u16int c = (u16int)r[4*i+2];
			u16int d = (u16int)r[4*i+3];
			out[5*i]   = (uchar)a;
			out[5*i+1] = (uchar)((a >> 8) | (b << 2));
			out[5*i+2] = (uchar)((b >> 6) | (c << 4));
			out[5*i+3] = (uchar)((c >> 4) | (d << 6));
			out[5*i+4] = (uchar)(d >> 2);
		}
	} else if(bits == 11){
		/* 11-bit encoding: 8 coefficients per 11 bytes */
		for(i = 0; i < MLKEM_N/8; i++){
			u16int t[8];
			int j;
			for(j = 0; j < 8; j++)
				t[j] = (u16int)r[8*i+j];
			out[11*i+0]  = (uchar)t[0];
			out[11*i+1]  = (uchar)((t[0]>>8) | (t[1]<<3));
			out[11*i+2]  = (uchar)((t[1]>>5) | (t[2]<<6));
			out[11*i+3]  = (uchar)(t[2]>>2);
			out[11*i+4]  = (uchar)((t[2]>>10) | (t[3]<<1));
			out[11*i+5]  = (uchar)((t[3]>>7) | (t[4]<<4));
			out[11*i+6]  = (uchar)((t[4]>>4) | (t[5]<<7));
			out[11*i+7]  = (uchar)(t[5]>>1);
			out[11*i+8]  = (uchar)((t[5]>>9) | (t[6]<<2));
			out[11*i+9]  = (uchar)((t[6]>>6) | (t[7]<<5));
			out[11*i+10] = (uchar)(t[7]>>3);
		}
	} else if(bits == 1){
		/* 1-bit encoding */
		for(i = 0; i < MLKEM_N/8; i++){
			int j;
			out[i] = 0;
			for(j = 0; j < 8; j++)
				out[i] |= (uchar)((r[8*i+j] & 1) << j);
		}
	} else if(bits == 4){
		/* 4-bit encoding: 2 coefficients per byte */
		for(i = 0; i < MLKEM_N/2; i++)
			out[i] = (uchar)((r[2*i] & 0xF) | ((r[2*i+1] & 0xF) << 4));
	} else if(bits == 5){
		/* 5-bit encoding: 8 coefficients per 5 bytes */
		for(i = 0; i < MLKEM_N/8; i++){
			u16int t[8];
			int j;
			for(j = 0; j < 8; j++)
				t[j] = (u16int)(r[8*i+j] & 0x1F);
			out[5*i+0] = (uchar)(t[0] | (t[1]<<5));
			out[5*i+1] = (uchar)((t[1]>>3) | (t[2]<<2) | (t[3]<<7));
			out[5*i+2] = (uchar)((t[3]>>1) | (t[4]<<4));
			out[5*i+3] = (uchar)((t[4]>>4) | (t[5]<<1) | (t[6]<<6));
			out[5*i+4] = (uchar)((t[6]>>2) | (t[7]<<3));
		}
	}
}

/*
 * Decode byte array to polynomial.
 */
void
mlkem_poly_decode(int16 r[MLKEM_N], const uchar *in, int bits)
{
	int i;

	if(bits == 12){
		for(i = 0; i < MLKEM_N/2; i++){
			r[2*i]   = ((u16int)in[3*i]   | ((u16int)in[3*i+1] << 8)) & 0x0FFF;
			r[2*i+1] = ((u16int)in[3*i+1] >> 4 | ((u16int)in[3*i+2] << 4)) & 0x0FFF;
		}
	} else if(bits == 10){
		for(i = 0; i < MLKEM_N/4; i++){
			r[4*i]   = ((u16int)in[5*i]   | ((u16int)in[5*i+1] << 8)) & 0x03FF;
			r[4*i+1] = ((u16int)in[5*i+1] >> 2 | ((u16int)in[5*i+2] << 6)) & 0x03FF;
			r[4*i+2] = ((u16int)in[5*i+2] >> 4 | ((u16int)in[5*i+3] << 4)) & 0x03FF;
			r[4*i+3] = ((u16int)in[5*i+3] >> 6 | ((u16int)in[5*i+4] << 2)) & 0x03FF;
		}
	} else if(bits == 11){
		for(i = 0; i < MLKEM_N/8; i++){
			r[8*i+0] = ((u16int)in[11*i+0]       | ((u16int)in[11*i+1]<<8)) & 0x7FF;
			r[8*i+1] = ((u16int)in[11*i+1] >> 3 | ((u16int)in[11*i+2]<<5)) & 0x7FF;
			r[8*i+2] = ((u16int)in[11*i+2] >> 6 | ((u16int)in[11*i+3]<<2) | ((u16int)in[11*i+4]<<10)) & 0x7FF;
			r[8*i+3] = ((u16int)in[11*i+4] >> 1 | ((u16int)in[11*i+5]<<7)) & 0x7FF;
			r[8*i+4] = ((u16int)in[11*i+5] >> 4 | ((u16int)in[11*i+6]<<4)) & 0x7FF;
			r[8*i+5] = ((u16int)in[11*i+6] >> 7 | ((u16int)in[11*i+7]<<1) | ((u16int)in[11*i+8]<<9)) & 0x7FF;
			r[8*i+6] = ((u16int)in[11*i+8] >> 2 | ((u16int)in[11*i+9]<<6)) & 0x7FF;
			r[8*i+7] = ((u16int)in[11*i+9] >> 5 | ((u16int)in[11*i+10]<<3)) & 0x7FF;
		}
	} else if(bits == 1){
		for(i = 0; i < MLKEM_N/8; i++){
			int j;
			for(j = 0; j < 8; j++)
				r[8*i+j] = (in[i] >> j) & 1;
		}
	} else if(bits == 4){
		for(i = 0; i < MLKEM_N/2; i++){
			r[2*i]   = in[i] & 0x0F;
			r[2*i+1] = in[i] >> 4;
		}
	} else if(bits == 5){
		for(i = 0; i < MLKEM_N/8; i++){
			r[8*i+0] = in[5*i+0] & 0x1F;
			r[8*i+1] = ((in[5*i+0]>>5) | (in[5*i+1]<<3)) & 0x1F;
			r[8*i+2] = (in[5*i+1]>>2) & 0x1F;
			r[8*i+3] = ((in[5*i+1]>>7) | (in[5*i+2]<<1)) & 0x1F;
			r[8*i+4] = ((in[5*i+2]>>4) | (in[5*i+3]<<4)) & 0x1F;
			r[8*i+5] = (in[5*i+3]>>1) & 0x1F;
			r[8*i+6] = ((in[5*i+3]>>6) | (in[5*i+4]<<2)) & 0x1F;
			r[8*i+7] = in[5*i+4]>>3;
		}
	}
}

/*
 * Compress all coefficients of a polynomial.
 */
void
mlkem_poly_compress(int16 r[MLKEM_N], int d)
{
	int i;

	mlkem_poly_normalize(r);
	for(i = 0; i < MLKEM_N; i++)
		r[i] = compress(r[i], d);
}

/*
 * Decompress all coefficients of a polynomial.
 */
void
mlkem_poly_decompress(int16 r[MLKEM_N], int d)
{
	int i;

	for(i = 0; i < MLKEM_N; i++)
		r[i] = decompress((u16int)r[i], d);
}

/*
 * Convert polynomial to Montgomery form.
 */
void
mlkem_poly_tomont(int16 r[MLKEM_N])
{
	int i;
	static const int16 f = (int16)(((u64int)1 << 32) % MLKEM_Q);

	for(i = 0; i < MLKEM_N; i++)
		r[i] = mlkem_montgomery_reduce((int32)r[i] * f);
}
