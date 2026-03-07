/*
 * SLH-DSA (FIPS 205) Hash Functions
 *
 * Tweakable hash functions and address scheme for SLH-DSA.
 * All functions use SHAKE-256 as the underlying hash.
 *
 * ADRS (address) is a 32-byte structure used for domain separation.
 *
 * Reference: NIST FIPS 205 "Stateless Hash-Based Digital Signature
 * Standard" (August 2024), Sections 4, 7.1, 10.1 (SHAKE instantiation).
 */
#include "os.h"
#include <libsec.h>

/*
 * ADRS byte offsets (32 bytes total)
 * See FIPS 205 Section 4.1
 */
enum {
	ADRS_LAYER	= 0,	/* bytes 0-3: layer address */
	ADRS_TREE	= 4,	/* bytes 4-15: tree address (96-bit) */
	ADRS_TYPE	= 16,	/* bytes 16-19: address type */
	ADRS_WORD1	= 20,	/* bytes 20-23: type-specific */
	ADRS_WORD2	= 24,	/* bytes 24-27: type-specific */
	ADRS_WORD3	= 28,	/* bytes 28-31: type-specific */
	ADRS_BYTES	= 32,

	/* Address types */
	ADRS_WOTS_HASH	= 0,
	ADRS_WOTS_PK	= 1,
	ADRS_TREE_ADDR	= 2,
	ADRS_FORS_TREE	= 3,
	ADRS_FORS_ROOTS	= 4,
	ADRS_WOTS_PRF	= 5,
	ADRS_FORS_PRF	= 6,
};

/*
 * Store 32-bit big-endian value in ADRS field
 */
static void
adrs_set32(uchar adrs[ADRS_BYTES], int off, u32int v)
{
	adrs[off]   = (v >> 24) & 0xff;
	adrs[off+1] = (v >> 16) & 0xff;
	adrs[off+2] = (v >> 8) & 0xff;
	adrs[off+3] = v & 0xff;
}

/*
 * Store 64-bit big-endian tree address in ADRS
 * FIPS 205 uses 96-bit tree address but upper 32 bits are 0
 * for parameter sets with h' * (d-1) <= 64
 */
static void
adrs_set_tree(uchar adrs[ADRS_BYTES], u64int tree)
{
	adrs[4] = 0;
	adrs[5] = 0;
	adrs[6] = 0;
	adrs[7] = 0;
	adrs[8] = (tree >> 56) & 0xff;
	adrs[9] = (tree >> 48) & 0xff;
	adrs[10] = (tree >> 40) & 0xff;
	adrs[11] = (tree >> 32) & 0xff;
	adrs[12] = (tree >> 24) & 0xff;
	adrs[13] = (tree >> 16) & 0xff;
	adrs[14] = (tree >> 8) & 0xff;
	adrs[15] = tree & 0xff;
}

void
slhdsa_adrs_init(uchar adrs[ADRS_BYTES])
{
	memset(adrs, 0, ADRS_BYTES);
}

void
slhdsa_adrs_set_layer(uchar adrs[ADRS_BYTES], u32int layer)
{
	adrs_set32(adrs, ADRS_LAYER, layer);
}

void
slhdsa_adrs_set_tree(uchar adrs[ADRS_BYTES], u64int tree)
{
	adrs_set_tree(adrs, tree);
}

void
slhdsa_adrs_set_type(uchar adrs[ADRS_BYTES], u32int type)
{
	adrs_set32(adrs, ADRS_TYPE, type);
	/* Zero out type-specific fields when type changes */
	adrs_set32(adrs, ADRS_WORD1, 0);
	adrs_set32(adrs, ADRS_WORD2, 0);
	adrs_set32(adrs, ADRS_WORD3, 0);
}

void
slhdsa_adrs_set_keypair(uchar adrs[ADRS_BYTES], u32int kp)
{
	adrs_set32(adrs, ADRS_WORD1, kp);
}

void
slhdsa_adrs_set_chain(uchar adrs[ADRS_BYTES], u32int chain)
{
	adrs_set32(adrs, ADRS_WORD2, chain);
}

void
slhdsa_adrs_set_hash(uchar adrs[ADRS_BYTES], u32int hash)
{
	adrs_set32(adrs, ADRS_WORD3, hash);
}

void
slhdsa_adrs_set_height(uchar adrs[ADRS_BYTES], u32int height)
{
	adrs_set32(adrs, ADRS_WORD2, height);
}

void
slhdsa_adrs_set_index(uchar adrs[ADRS_BYTES], u32int index)
{
	adrs_set32(adrs, ADRS_WORD3, index);
}

/*
 * Copy ADRS, preserving layer and tree but changing type
 */
void
slhdsa_adrs_copy(uchar dst[ADRS_BYTES], const uchar src[ADRS_BYTES])
{
	memmove(dst, src, ADRS_BYTES);
}

/*
 * F: SHAKE256(PK.seed || ADRS || M)
 * One-block tweakable hash function
 * Output: n bytes
 *
 * FIPS 205 Section 10.1, Algorithm 1
 */
void
slhdsa_F(uchar *out, int n,
	const uchar *pkseed, int seedlen,
	const uchar adrs[ADRS_BYTES],
	const uchar *m, int mlen)
{
	SHA3state s;

	shake256_init(&s);
	shake256_absorb(&s, pkseed, seedlen);
	shake256_absorb(&s, adrs, ADRS_BYTES);
	shake256_absorb(&s, m, mlen);
	shake256_finalize(&s);
	shake256_squeeze(&s, out, n);
}

/*
 * H: SHAKE256(PK.seed || ADRS || M1 || M2)
 * Two-block tweakable hash function
 * Output: n bytes
 *
 * FIPS 205 Section 10.1, Algorithm 2
 */
void
slhdsa_H(uchar *out, int n,
	const uchar *pkseed, int seedlen,
	const uchar adrs[ADRS_BYTES],
	const uchar *m1, int m1len,
	const uchar *m2, int m2len)
{
	SHA3state s;

	shake256_init(&s);
	shake256_absorb(&s, pkseed, seedlen);
	shake256_absorb(&s, adrs, ADRS_BYTES);
	shake256_absorb(&s, m1, m1len);
	shake256_absorb(&s, m2, m2len);
	shake256_finalize(&s);
	shake256_squeeze(&s, out, n);
}

/*
 * T_l: SHAKE256(PK.seed || ADRS || M)
 * Multi-block tweakable hash for WOTS+ public key compression
 * Output: n bytes
 *
 * FIPS 205 Section 10.1, Algorithm 3
 */
void
slhdsa_Tl(uchar *out, int n,
	const uchar *pkseed, int seedlen,
	const uchar adrs[ADRS_BYTES],
	const uchar *m, int mlen)
{
	SHA3state s;

	shake256_init(&s);
	shake256_absorb(&s, pkseed, seedlen);
	shake256_absorb(&s, adrs, ADRS_BYTES);
	shake256_absorb(&s, m, mlen);
	shake256_finalize(&s);
	shake256_squeeze(&s, out, n);
}

/*
 * PRF: SHAKE256(PK.seed || ADRS || SK.seed)
 * Pseudorandom function for secret value generation
 * Output: n bytes
 *
 * FIPS 205 Section 10.1
 */
void
slhdsa_PRF(uchar *out, int n,
	const uchar *pkseed, int seedlen,
	const uchar *skseed, int skseedlen,
	const uchar adrs[ADRS_BYTES])
{
	SHA3state s;

	shake256_init(&s);
	shake256_absorb(&s, pkseed, seedlen);
	shake256_absorb(&s, adrs, ADRS_BYTES);
	shake256_absorb(&s, skseed, skseedlen);
	shake256_finalize(&s);
	shake256_squeeze(&s, out, n);
}

/*
 * PRF_msg: SHAKE256(SK.prf || opt_rand || M)
 * Pseudorandom function for randomized message hashing
 * Output: n bytes
 *
 * FIPS 205 Section 10.1
 */
void
slhdsa_PRF_msg(uchar *out, int n,
	const uchar *skprf, int skprflen,
	const uchar *optrand, int optrandlen,
	const uchar *msg, ulong msglen)
{
	SHA3state s;

	shake256_init(&s);
	shake256_absorb(&s, skprf, skprflen);
	shake256_absorb(&s, optrand, optrandlen);
	shake256_absorb(&s, msg, msglen);
	shake256_finalize(&s);
	shake256_squeeze(&s, out, n);
}

/*
 * H_msg: SHAKE256(R || PK.seed || PK.root || M)
 * Message hash function
 * Output: m bytes (digest length for FORS)
 *
 * FIPS 205 Section 10.1
 */
void
slhdsa_H_msg(uchar *out, int outlen,
	const uchar *R, int Rlen,
	const uchar *pkseed, int pkseedlen,
	const uchar *pkroot, int pkrootlen,
	const uchar *msg, ulong msglen)
{
	SHA3state s;

	shake256_init(&s);
	shake256_absorb(&s, R, Rlen);
	shake256_absorb(&s, pkseed, pkseedlen);
	shake256_absorb(&s, pkroot, pkrootlen);
	shake256_absorb(&s, msg, msglen);
	shake256_finalize(&s);
	shake256_squeeze(&s, out, outlen);
}
