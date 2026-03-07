/*
 * CBMC Stubs for Quantum-Safe Crypto Verification
 *
 * Provides minimal implementations of Inferno primitives needed
 * to verify ML-KEM, ML-DSA, and SLH-DSA C implementations with CBMC.
 *
 * These stubs link against the actual libsec crypto code while
 * providing the OS-level abstractions (genrandom, malloc, etc.)
 * needed to make them verifiable.
 */

#ifndef CBMC_CRYPTO_STUBS_H
#define CBMC_CRYPTO_STUBS_H

#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <assert.h>

/* ====== Basic Types (matching Inferno's type system) ====== */

typedef unsigned char uchar;
typedef unsigned short ushort;
typedef unsigned int uint;
typedef unsigned long ulong;
typedef long long vlong;
typedef unsigned long long uvlong;
typedef int16_t int16;
typedef uint16_t u16int;
typedef int32_t int32;
typedef uint32_t u32int;
typedef int64_t int64;
typedef uint64_t u64int;

#define nil  ((void*)0)
#define USED(x)  ((void)(x))

/* ====== SHA-3 / SHAKE state ====== */

typedef struct SHA3state SHA3state;
struct SHA3state
{
	u64int	a[25];
	uchar	buf[200];
	int	rate;
	int	pt;
	int	mdlen;
};

/* ====== ML-KEM Constants ====== */

enum {
	MLKEM_N = 256,
	MLKEM_Q = 3329,

	MLKEM768_PKLEN  = 1184,
	MLKEM768_SKLEN  = 2400,
	MLKEM768_CTLEN  = 1088,

	MLKEM1024_PKLEN = 1568,
	MLKEM1024_SKLEN = 3168,
	MLKEM1024_CTLEN = 1568,

	MLKEM_SSLEN     = 32,
};

/* ====== ML-DSA Constants ====== */

enum {
	MLDSA_N = 256,
	MLDSA_Q = 8380417,

	MLDSA65_PKLEN  = 1952,
	MLDSA65_SKLEN  = 4032,
	MLDSA65_SIGLEN = 3309,

	MLDSA87_PKLEN  = 2592,
	MLDSA87_SKLEN  = 4896,
	MLDSA87_SIGLEN = 4627,
};

/* ====== Function prototypes from libsec ====== */

/* SHA-3 */
extern void	sha3_256(const uchar *in, ulong inlen, uchar out[32]);
extern void	sha3_512(const uchar *in, ulong inlen, uchar out[64]);
extern void	shake128_init(SHA3state *s);
extern void	shake128_absorb(SHA3state *s, const uchar *in, ulong inlen);
extern void	shake128_finalize(SHA3state *s);
extern void	shake128_squeeze(SHA3state *s, uchar *out, ulong outlen);
extern void	shake256_init(SHA3state *s);
extern void	shake256_absorb(SHA3state *s, const uchar *in, ulong inlen);
extern void	shake256_finalize(SHA3state *s);
extern void	shake256_squeeze(SHA3state *s, uchar *out, ulong outlen);
extern void	shake256(const uchar *in, ulong inlen, uchar *out, ulong outlen);

/* ML-KEM NTT */
extern int16	mlkem_barrett_reduce(int16 a);
extern int16	mlkem_montgomery_reduce(int32 a);
extern int16	mlkem_cond_sub_q(int16 a);
extern void	mlkem_ntt(int16 r[256]);
extern void	mlkem_invntt(int16 r[256]);
extern void	mlkem_poly_basemul(int16 r[256], const int16 a[256], const int16 b[256]);
extern void	mlkem_poly_add(int16 r[256], const int16 a[256], const int16 b[256]);
extern void	mlkem_poly_sub(int16 r[256], const int16 a[256], const int16 b[256]);
extern void	mlkem_poly_reduce(int16 r[256]);
extern void	mlkem_poly_normalize(int16 r[256]);
extern void	mlkem_poly_encode(uchar *out, const int16 r[256], int bits);
extern void	mlkem_poly_decode(int16 r[256], const uchar *in, int bits);
extern void	mlkem_poly_compress(int16 r[256], int d);
extern void	mlkem_poly_decompress(int16 r[256], int d);

/* ML-DSA NTT */
extern int32	mldsa_barrett_reduce(int32 a);
extern int32	mldsa_montgomery_reduce(int64 a);
extern void	mldsa_ntt(int32 r[256]);
extern void	mldsa_invntt(int32 r[256]);
extern void	mldsa_poly_pointwise(int32 r[256], const int32 a[256], const int32 b[256]);
extern void	mldsa_poly_add(int32 r[256], const int32 a[256], const int32 b[256]);
extern void	mldsa_poly_sub(int32 r[256], const int32 a[256], const int32 b[256]);
extern void	mldsa_poly_reduce(int32 r[256]);

/* ====== Stub for genrandom (deterministic for CBMC) ====== */

static unsigned char _cbmc_rng_state = 0;

static void
genrandom(uchar *buf, int n)
{
	int i;
	for(i = 0; i < n; i++)
		buf[i] = _cbmc_rng_state++;
}

#endif /* CBMC_CRYPTO_STUBS_H */
