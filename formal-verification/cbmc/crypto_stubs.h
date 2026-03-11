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

#include <assert.h>

/*
 * Types and SHA3 state are provided by os.h and libsec.h stubs,
 * which are also used by the actual libsec source files (mlkem_ntt.c,
 * mlkem_poly.c) to avoid double definitions when linking.
 */
#include "os.h"
#include "libsec.h"

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

/* ====== Function prototypes not in libsec.h ====== */

/* SHA-3 hash functions (not needed by current harnesses) */
extern void	sha3_256(const uchar *in, ulong inlen, uchar out[32]);
extern void	sha3_512(const uchar *in, ulong inlen, uchar out[64]);
extern void	shake256(const uchar *in, ulong inlen, uchar *out, ulong outlen);

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
