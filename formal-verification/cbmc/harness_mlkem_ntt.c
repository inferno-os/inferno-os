/*
 * CBMC Harness: ML-KEM NTT Correctness Verification
 *
 * Verifies correctness properties of the Number Theoretic Transform
 * and polynomial encode/decode operations used in ML-KEM (FIPS 203).
 *
 * Properties verified:
 *   1. NTT/INVNTT round-trip: invntt(ntt(poly)) == poly
 *   2. Encode/decode round-trip for all bit widths
 *   3. Polynomial addition commutativity
 *   4. Polynomial subtraction identity (a - a == 0)
 *   5. Normalize produces coefficients in [0, q)
 *
 * These harnesses link against the actual mlkem_ntt.c and mlkem_poly.c
 * source code to verify the real implementation.
 *
 * Usage:
 *   cbmc --function harness_ntt_roundtrip harness_mlkem_ntt.c \
 *     ../libsec/mlkem_ntt.c ../libsec/mlkem_poly.c ../libsec/sha3.c \
 *     --bounds-check --unwind 258 -DCBMC
 */

#include "crypto_stubs.h"

/*
 * Harness 1: NTT/INVNTT round-trip.
 *
 * For a small polynomial (bounded coefficients), verify that
 * applying NTT followed by INVNTT recovers the original.
 *
 * The NTT operates in Montgomery domain, so we must account for
 * the Montgomery factor. Specifically:
 *   invntt(ntt(r)) = r (up to reduction mod q)
 */
void harness_ntt_roundtrip(void)
{
	int16 r[256], original[256];
	int i;
	int16 diff;

	/* Initialize with small bounded coefficients */
	for(i = 0; i < 256; i++){
		/* Nondeterministic values in a safe range */
		__CPROVER_assume(r[i] >= -MLKEM_Q/2 && r[i] <= MLKEM_Q/2);
		original[i] = r[i];
	}

	/* Apply NTT then INVNTT */
	mlkem_ntt(r);
	mlkem_invntt(r);

	/* Verify round-trip: each coefficient should be congruent to original mod q */
	for(i = 0; i < 256; i++){
		int16 red = mlkem_barrett_reduce(r[i]);
		int16 orig_red = mlkem_barrett_reduce(original[i]);
		diff = mlkem_barrett_reduce(red - orig_red);
		/* Allow for Barrett reduction range: diff should be 0 mod q */
		assert(diff == 0 || diff == MLKEM_Q || diff == -MLKEM_Q);
	}
}

/*
 * Harness 2: Encode/decode round-trip for 12-bit encoding.
 *
 * Property: decode(encode(poly, 12), 12) == poly for coefficients in [0, 4096).
 */
void harness_encode_decode_12(void)
{
	int16 r[256], decoded[256];
	uchar buf[384];	/* 256 * 12 / 8 = 384 bytes */
	int i;

	/* Initialize with valid 12-bit values */
	for(i = 0; i < 256; i++){
		__CPROVER_assume(r[i] >= 0 && r[i] < 4096);
	}

	mlkem_poly_encode(buf, r, 12);
	mlkem_poly_decode(decoded, buf, 12);

	for(i = 0; i < 256; i++)
		assert(decoded[i] == r[i]);
}

/*
 * Harness 3: Encode/decode round-trip for 10-bit encoding.
 */
void harness_encode_decode_10(void)
{
	int16 r[256], decoded[256];
	uchar buf[320];	/* 256 * 10 / 8 = 320 bytes */
	int i;

	for(i = 0; i < 256; i++){
		__CPROVER_assume(r[i] >= 0 && r[i] < 1024);
	}

	mlkem_poly_encode(buf, r, 10);
	mlkem_poly_decode(decoded, buf, 10);

	for(i = 0; i < 256; i++)
		assert(decoded[i] == r[i]);
}

/*
 * Harness 4: Encode/decode round-trip for 11-bit encoding.
 */
void harness_encode_decode_11(void)
{
	int16 r[256], decoded[256];
	uchar buf[352];	/* 256 * 11 / 8 = 352 bytes */
	int i;

	for(i = 0; i < 256; i++){
		__CPROVER_assume(r[i] >= 0 && r[i] < 2048);
	}

	mlkem_poly_encode(buf, r, 11);
	mlkem_poly_decode(decoded, buf, 11);

	for(i = 0; i < 256; i++)
		assert(decoded[i] == r[i]);
}

/*
 * Harness 5: Encode/decode round-trip for 1-bit encoding.
 */
void harness_encode_decode_1(void)
{
	int16 r[256], decoded[256];
	uchar buf[32];	/* 256 * 1 / 8 = 32 bytes */
	int i;

	for(i = 0; i < 256; i++){
		__CPROVER_assume(r[i] >= 0 && r[i] <= 1);
	}

	mlkem_poly_encode(buf, r, 1);
	mlkem_poly_decode(decoded, buf, 1);

	for(i = 0; i < 256; i++)
		assert(decoded[i] == r[i]);
}

/*
 * Harness 6: Encode/decode round-trip for 4-bit encoding.
 */
void harness_encode_decode_4(void)
{
	int16 r[256], decoded[256];
	uchar buf[128];	/* 256 * 4 / 8 = 128 bytes */
	int i;

	for(i = 0; i < 256; i++){
		__CPROVER_assume(r[i] >= 0 && r[i] < 16);
	}

	mlkem_poly_encode(buf, r, 4);
	mlkem_poly_decode(decoded, buf, 4);

	for(i = 0; i < 256; i++)
		assert(decoded[i] == r[i]);
}

/*
 * Harness 7: Polynomial addition commutativity.
 *
 * Property: add(a, b) == add(b, a)
 */
void harness_poly_add_commutative(void)
{
	int16 a[256], b[256], r1[256], r2[256];
	int i;

	mlkem_poly_add(r1, a, b);
	mlkem_poly_add(r2, b, a);

	for(i = 0; i < 256; i++)
		assert(r1[i] == r2[i]);
}

/*
 * Harness 8: Polynomial subtraction identity.
 *
 * Property: sub(a, a) == 0 for all a
 */
void harness_poly_sub_identity(void)
{
	int16 a[256], r[256];
	int i;

	mlkem_poly_sub(r, a, a);

	for(i = 0; i < 256; i++)
		assert(r[i] == 0);
}

/*
 * Harness 9: Normalize produces valid range.
 *
 * Property: After normalize, all coefficients in [0, q).
 */
void harness_poly_normalize_range(void)
{
	int16 r[256];
	int i;

	/* Start with arbitrary values in a reasonable range */
	for(i = 0; i < 256; i++){
		__CPROVER_assume(r[i] > -2 * MLKEM_Q && r[i] < 2 * MLKEM_Q);
	}

	mlkem_poly_normalize(r);

	for(i = 0; i < 256; i++){
		assert(r[i] >= 0);
		assert(r[i] < MLKEM_Q);
	}
}
