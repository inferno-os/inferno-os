/*
 * SLH-DSA Digital Signature Algorithm (FIPS 205)
 *
 * Stateless Hash-Based Digital Signature Standard.
 * Implements SLH-DSA-SHAKE-192s (NIST Level 3) and
 * SLH-DSA-SHAKE-256s (NIST Level 5).
 *
 * SLH-DSA provides conservative, hash-based signatures with no
 * lattice assumptions — security relies only on the hash function
 * (SHAKE-256). This makes it a valuable backup for ML-DSA in case
 * lattice problems are unexpectedly broken.
 *
 * Key sizes:
 *   192s: pk=48, sk=96, sig=16224  (NIST Level 3)
 *   256s: pk=64, sk=128, sig=29792 (NIST Level 5)
 *
 * Working state is heap-allocated to avoid stack overflow in the
 * Inferno emulator's 32KB thread stacks.
 *
 * Reference: NIST FIPS 205 "Stateless Hash-Based Digital Signature
 * Standard" (August 2024).
 */
#include "os.h"
#include <libsec.h>

/*
 * SLH-DSA-SHAKE-192s parameters (FIPS 205 Table 2)
 *   n=24, h=63, d=7, h'=9, a=14, k=17, lg(w)=4
 *   len = 2*24 + 3 = 51  (WOTS+ chains)
 *
 * SLH-DSA-SHAKE-256s parameters (FIPS 205 Table 2)
 *   n=32, h=64, d=8, h'=8, a=14, k=22, lg(w)=4
 *   len = 2*32 + 3 = 67
 */
enum {
	/* SLH-DSA-SHAKE-192s (FIPS 205 Table 2) */
	S192_N		= 24,
	S192_H		= 63,
	S192_D		= 7,
	S192_HPRIME	= 9,	/* h/d = 63/7 */
	S192_A		= 14,
	S192_K		= 17,
	S192_WLEN	= 51,	/* 2*24 + 3 */

	/* SLH-DSA-SHAKE-256s (FIPS 205 Table 2) */
	S256_N		= 32,
	S256_H		= 64,
	S256_D		= 8,
	S256_HPRIME	= 8,	/* h/d = 64/8 */
	S256_A		= 14,
	S256_K		= 22,
	S256_WLEN	= 67,	/* 2*32 + 3 */

	/* Message digest sizes: ceil(k*a/8) + ceil((h-h')/8) + ceil(h'/8) */
	S192_MD_LEN	= 30 + 7 + 2,	/* 39 bytes */
	S256_MD_LEN	= 39 + 7 + 1,	/* 47 bytes */
};

/* Forward declarations */
extern void slhdsa_adrs_init(uchar*);
extern void slhdsa_adrs_set_layer(uchar*, u32int);
extern void slhdsa_adrs_set_tree(uchar*, u64int);
extern void slhdsa_adrs_set_type(uchar*, u32int);
extern void slhdsa_adrs_set_keypair(uchar*, u32int);
extern void slhdsa_adrs_copy(uchar*, const uchar*);
extern void slhdsa_H_msg(uchar*, int, const uchar*, int, const uchar*, int, const uchar*, int, const uchar*, ulong);
extern void slhdsa_PRF_msg(uchar*, int, const uchar*, int, const uchar*, int, const uchar*, ulong);

extern int  slhdsa_treehash(uchar*, uchar*, int, const uchar*, int, const uchar*, int, u32int, u64int, int, int);
extern void slhdsa_fors_sign(uchar*, int, const uchar*, const uchar*, int, const uchar*, int, uchar*, int, int);
extern void slhdsa_fors_pk_from_sig(uchar*, int, const uchar*, const uchar*, const uchar*, int, uchar*, int, int);
extern void slhdsa_ht_sign(uchar*, int, const uchar*, const uchar*, int, const uchar*, int, u64int, u32int, int, int);
extern int  slhdsa_ht_verify(const uchar*, int, const uchar*, const uchar*, int, const uchar*, u64int, u32int, int, int);
extern int  slhdsa_wots_len(int);

/*
 * Extract tree index and leaf index from message digest
 *
 * The H_msg output is split into:
 *   md[0..ceil(k*a/8)-1]         — FORS message digest
 *   followed by bits for idx_tree (h - h/d bits)
 *   followed by bits for idx_leaf (h/d bits)
 */
static void
split_digest(const uchar *digest, int digestlen,
	int k, int a, int h, int hprime,
	u64int *idx_tree, u32int *idx_leaf)
{
	int md_bits, tree_bits, leaf_bits;
	int byte_off, bit_off;
	u64int treev;
	u32int leafv;
	int i;

	md_bits = k * a;
	tree_bits = h - hprime;
	leaf_bits = hprime;

	/* Extract tree index */
	bit_off = md_bits;
	treev = 0;
	for(i = 0; i < tree_bits && i < 64; i++){
		byte_off = (bit_off + i) / 8;
		if(byte_off < digestlen
		&& (digest[byte_off] & (1 << (7 - ((bit_off + i) % 8)))))
			treev |= (1ULL << (tree_bits - 1 - i));
	}

	/* Extract leaf index */
	bit_off = md_bits + tree_bits;
	leafv = 0;
	for(i = 0; i < leaf_bits; i++){
		byte_off = (bit_off + i) / 8;
		if(byte_off < digestlen
		&& (digest[byte_off] & (1 << (7 - ((bit_off + i) % 8)))))
			leafv |= (1U << (leaf_bits - 1 - i));
	}

	*idx_tree = treev;
	*idx_leaf = leafv;
}

/*
 * SLH-DSA key generation (generic for both parameter sets)
 *
 * Algorithm 21 from FIPS 205
 *
 * SK = (SK.seed || SK.prf || PK.seed || PK.root)
 * PK = (PK.seed || PK.root)
 *
 * SK.seed, SK.prf, PK.seed are random; PK.root is computed.
 */
static int
slhdsa_keygen(uchar *pk, uchar *sk, int n, int hprime, int d)
{
	uchar skseed[32], skprf[32], pkseed[32];
	uchar root[32];

	/* Generate random seeds */
	genrandom(skseed, n);
	genrandom(skprf, n);
	genrandom(pkseed, n);

	/* Compute root of the top XMSS tree */
	if(slhdsa_treehash(root, nil, n, pkseed, n, skseed, n,
		d - 1, 0, hprime, -1) != 0){
		secureZero(skseed, sizeof(skseed));
		secureZero(skprf, sizeof(skprf));
		return -1;
	}

	/* Assemble SK: SK.seed || SK.prf || PK.seed || PK.root */
	memmove(sk, skseed, n);
	memmove(sk + n, skprf, n);
	memmove(sk + 2*n, pkseed, n);
	memmove(sk + 3*n, root, n);

	/* Assemble PK: PK.seed || PK.root */
	memmove(pk, pkseed, n);
	memmove(pk + n, root, n);

	secureZero(skseed, sizeof(skseed));
	secureZero(skprf, sizeof(skprf));

	return 0;
}

/*
 * SLH-DSA signing (generic)
 *
 * Algorithm 22 from FIPS 205
 *
 * sig = R || SIG_FORS || SIG_HT
 */
static int
slhdsa_sign_internal(uchar *sig, const uchar *msg, ulong msglen,
	const uchar *sk, int n, int h, int d, int hprime, int a, int k)
{
	const uchar *skseed, *skprf, *pkseed, *pkroot;
	uchar adrs[32];
	uchar *R;
	const uchar *opt_rand;
	uchar *digest;
	int digestlen;
	int fors_siglen;
	u64int idx_tree;
	u32int idx_leaf;
	uchar fors_pk[32];

	skseed = sk;
	skprf = sk + n;
	pkseed = sk + 2*n;
	pkroot = sk + 3*n;

	R = sig;

	/* opt_rand = PK.seed for deterministic signing */
	opt_rand = pkseed;

	/* R = PRF_msg(SK.prf, opt_rand, M) */
	slhdsa_PRF_msg(R, n, skprf, n, opt_rand, n, msg, msglen);
	sig += n;

	/* Compute message digest */
	digestlen = (k * a + 7) / 8 + (h - hprime + 7) / 8 + (hprime + 7) / 8;
	digest = malloc(digestlen);
	if(digest == nil)
		return -1;

	slhdsa_H_msg(digest, digestlen, R, n, pkseed, n, pkroot, n, msg, msglen);

	/* Extract tree and leaf indices */
	split_digest(digest, digestlen, k, a, h, hprime, &idx_tree, &idx_leaf);

	/* FORS signature */
	slhdsa_adrs_init(adrs);
	slhdsa_adrs_set_tree(adrs, idx_tree);
	slhdsa_adrs_set_type(adrs, 3);	/* FORS_TREE */
	slhdsa_adrs_set_keypair(adrs, idx_leaf);

	fors_siglen = k * (a + 1) * n;
	slhdsa_fors_sign(sig, n, digest, pkseed, n, skseed, n, adrs, k, a);

	/* Compute FORS public key */
	slhdsa_adrs_set_type(adrs, 3);
	slhdsa_adrs_set_keypair(adrs, idx_leaf);
	slhdsa_fors_pk_from_sig(fors_pk, n, sig, digest, pkseed, n, adrs, k, a);
	sig += fors_siglen;

	/* Hypertree signature on FORS public key */
	slhdsa_ht_sign(sig, n, fors_pk, pkseed, n, skseed, n,
		idx_tree, idx_leaf, hprime, d);

	free(digest);
	return 0;
}

/*
 * SLH-DSA verification (generic)
 *
 * Algorithm 24 from FIPS 205
 *
 * Returns 1 if valid, 0 if invalid.
 */
static int
slhdsa_verify_internal(const uchar *sig, ulong siglen,
	const uchar *msg, ulong msglen,
	const uchar *pk, int n, int h, int d, int hprime, int a, int k)
{
	const uchar *pkseed, *pkroot;
	const uchar *R;
	uchar adrs[32];
	uchar *digest;
	int digestlen;
	int fors_siglen, ht_siglen;
	int xmss_siglen;
	u64int idx_tree;
	u32int idx_leaf;
	uchar fors_pk[32];
	ulong expected_siglen;

	pkseed = pk;
	pkroot = pk + n;

	/* Compute expected signature length */
	xmss_siglen = (slhdsa_wots_len(n) + hprime) * n;
	fors_siglen = k * (a + 1) * n;
	ht_siglen = d * xmss_siglen;
	expected_siglen = n + fors_siglen + ht_siglen;

	if(siglen != expected_siglen)
		return 0;

	R = sig;
	sig += n;

	/* Compute message digest */
	digestlen = (k * a + 7) / 8 + (h - hprime + 7) / 8 + (hprime + 7) / 8;
	digest = malloc(digestlen);
	if(digest == nil)
		return 0;

	slhdsa_H_msg(digest, digestlen, R, n, pkseed, n, pkroot, n, msg, msglen);

	/* Extract tree and leaf indices */
	split_digest(digest, digestlen, k, a, h, hprime, &idx_tree, &idx_leaf);

	/* Compute FORS public key from signature */
	slhdsa_adrs_init(adrs);
	slhdsa_adrs_set_tree(adrs, idx_tree);
	slhdsa_adrs_set_type(adrs, 3);	/* FORS_TREE */
	slhdsa_adrs_set_keypair(adrs, idx_leaf);

	slhdsa_fors_pk_from_sig(fors_pk, n, sig, digest, pkseed, n, adrs, k, a);
	sig += fors_siglen;

	free(digest);

	/* Verify hypertree signature on FORS public key */
	return slhdsa_ht_verify(sig, n, fors_pk, pkseed, n, pkroot,
		idx_tree, idx_leaf, hprime, d);
}

/*
 * Public API: SLH-DSA-SHAKE-192s
 */
int
slhdsa192s_keygen(uchar *pk, uchar *sk)
{
	return slhdsa_keygen(pk, sk, S192_N, S192_HPRIME, S192_D);
}

int
slhdsa192s_sign(uchar *sig, const uchar *msg, ulong msglen, const uchar *sk)
{
	return slhdsa_sign_internal(sig, msg, msglen, sk,
		S192_N, S192_H, S192_D, S192_HPRIME, S192_A, S192_K);
}

int
slhdsa192s_verify(const uchar *sig, ulong siglen,
	const uchar *msg, ulong msglen, const uchar *pk)
{
	return slhdsa_verify_internal(sig, siglen, msg, msglen, pk,
		S192_N, S192_H, S192_D, S192_HPRIME, S192_A, S192_K);
}

/*
 * Public API: SLH-DSA-SHAKE-256s
 */
int
slhdsa256s_keygen(uchar *pk, uchar *sk)
{
	return slhdsa_keygen(pk, sk, S256_N, S256_HPRIME, S256_D);
}

int
slhdsa256s_sign(uchar *sig, const uchar *msg, ulong msglen, const uchar *sk)
{
	return slhdsa_sign_internal(sig, msg, msglen, sk,
		S256_N, S256_H, S256_D, S256_HPRIME, S256_A, S256_K);
}

int
slhdsa256s_verify(const uchar *sig, ulong siglen,
	const uchar *msg, ulong msglen, const uchar *pk)
{
	return slhdsa_verify_internal(sig, siglen, msg, msglen, pk,
		S256_N, S256_H, S256_D, S256_HPRIME, S256_A, S256_K);
}
