/*
 * SLH-DSA (FIPS 205) FORS Few-Time Signatures
 *
 * FORS (Forest Of Random Subsets) is a few-time signature scheme
 * used to sign the message digest in SLH-DSA.
 *
 * FORS uses k binary trees of height a.
 * The message digest is split into k a-bit indices.
 * Each index selects a leaf from the corresponding tree.
 *
 * SLH-DSA-SHAKE-192s: k=17, a=14, sig_fors = k*(a+1)*n = 17*15*24 = 6120
 * SLH-DSA-SHAKE-256s: k=22, a=14, sig_fors = k*(a+1)*n = 22*15*32 = 10560
 *
 * Reference: FIPS 205 Section 8
 */
#include "os.h"
#include <libsec.h>

/* Forward declarations for hash functions (slhdsa_hash.c) */
extern void slhdsa_adrs_set_type(uchar*, u32int);
extern void slhdsa_adrs_set_keypair(uchar*, u32int);
extern void slhdsa_adrs_set_height(uchar*, u32int);
extern void slhdsa_adrs_set_index(uchar*, u32int);
extern void slhdsa_adrs_copy(uchar*, const uchar*);
extern void slhdsa_F(uchar*, int, const uchar*, int, const uchar*, const uchar*, int);
extern void slhdsa_H(uchar*, int, const uchar*, int, const uchar*, const uchar*, int, const uchar*, int);
extern void slhdsa_PRF(uchar*, int, const uchar*, int, const uchar*, int, const uchar*);
extern void slhdsa_Tl(uchar*, int, const uchar*, int, const uchar*, const uchar*, int);

/*
 * Extract a-bit index from message digest at position i
 */
static u32int
fors_get_index(const uchar *md, int i, int a)
{
	u32int idx;
	int bitoff, byteoff, j;

	idx = 0;
	bitoff = i * a;
	for(j = 0; j < a; j++){
		byteoff = (bitoff + j) / 8;
		if(md[byteoff] & (1 << (7 - ((bitoff + j) % 8))))
			idx |= (1 << (a - 1 - j));
	}
	return idx;
}

/*
 * Compute leaf node of FORS tree
 * leaf = F(PK.seed, ADRS, PRF(PK.seed, SK.seed, ADRS))
 */
static void
fors_leaf(uchar *out, int n,
	const uchar *pkseed, int seedlen,
	const uchar *skseed, int skseedlen,
	uchar adrs[32], u32int idx)
{
	uchar skadrs[32];
	uchar sk[64];

	slhdsa_adrs_copy(skadrs, adrs);
	slhdsa_adrs_set_type(skadrs, 6);	/* FORS_PRF */
	slhdsa_adrs_set_keypair(skadrs, 0);
	memmove(skadrs + 20, adrs + 20, 4);
	slhdsa_adrs_set_height(skadrs, 0);
	slhdsa_adrs_set_index(skadrs, idx);

	slhdsa_PRF(sk, n, pkseed, seedlen, skseed, skseedlen, skadrs);

	slhdsa_adrs_set_height(adrs, 0);
	slhdsa_adrs_set_index(adrs, idx);
	slhdsa_F(out, n, pkseed, seedlen, adrs, sk, n);

	secureZero(sk, sizeof(sk));
}

/*
 * Compute internal node of FORS tree by hashing two children
 */
static void
fors_node(uchar *out, int n,
	const uchar *left, const uchar *right,
	const uchar *pkseed, int seedlen,
	uchar adrs[32], u32int height, u32int idx)
{
	slhdsa_adrs_set_height(adrs, height);
	slhdsa_adrs_set_index(adrs, idx);
	slhdsa_H(out, n, pkseed, seedlen, adrs, left, n, right, n);
}

/*
 * Compute FORS tree root using treehash
 * Builds the tree bottom-up
 */
static void
fors_treehash(uchar *root, int n,
	const uchar *pkseed, int seedlen,
	const uchar *skseed, int skseedlen,
	uchar adrs[32], int a, u32int tree_idx)
{
	uchar *stack;
	uchar node[64]; /* current node (max n=32) */
	uchar tmp[64];
	int i, j, leaves;
	u32int base;

	leaves = 1 << a;
	/* Stack: max height a+1 entries of n bytes */
	stack = malloc((a + 1) * n);
	if(stack == nil)
		return;

	base = tree_idx * leaves;

	for(i = 0; i < leaves; i++){
		fors_leaf(node, n, pkseed, seedlen, skseed, skseedlen,
			adrs, base + i);

		/* Merge up: stack[j] is left child, node is right child */
		for(j = 0; (i >> j) & 1; j++){
			fors_node(tmp, n,
				stack + j*n, node,
				pkseed, seedlen,
				adrs, j + 1, (base + i) >> (j + 1));
			memmove(node, tmp, n);
		}
		memmove(stack + j*n, node, n);
	}

	memmove(root, stack + a*n, n);
	secureZero(stack, (a + 1) * n);
	free(stack);
}

/*
 * Generate FORS signature
 *
 * Algorithm 16 from FIPS 205
 *
 * For each of k trees:
 *   1. Extract a-bit index from message digest
 *   2. Output the secret value at that index
 *   3. Output the authentication path (a nodes)
 *
 * sig_fors = k * (1 + a) * n bytes
 */
void
slhdsa_fors_sign(uchar *sig, int n,
	const uchar *md,
	const uchar *pkseed, int seedlen,
	const uchar *skseed, int skseedlen,
	uchar adrs[32],
	int k, int a)
{
	uchar skadrs[32];
	uchar *auth;
	uchar *nodes;
	u32int idx, base, s;
	int i, j, leaves;

	leaves = 1 << a;

	/* Allocate space for computing auth paths */
	nodes = malloc(leaves * n);
	if(nodes == nil)
		return;

	slhdsa_adrs_set_type(adrs, 3);	/* FORS_TREE */

	for(i = 0; i < k; i++){
		idx = fors_get_index(md, i, a);
		base = i * leaves;

		/* Output secret value at index */
		slhdsa_adrs_copy(skadrs, adrs);
		slhdsa_adrs_set_type(skadrs, 6);	/* FORS_PRF */
		slhdsa_adrs_set_keypair(skadrs, 0);
		memmove(skadrs + 20, adrs + 20, 4);
		slhdsa_adrs_set_height(skadrs, 0);
		slhdsa_adrs_set_index(skadrs, base + idx);

		slhdsa_PRF(sig, n, pkseed, seedlen, skseed, skseedlen, skadrs);
		sig += n;

		/* Compute all leaf nodes for this tree */
		for(j = 0; j < leaves; j++)
			fors_leaf(nodes + j*n, n, pkseed, seedlen,
				skseed, skseedlen, adrs, base + j);

		/* Compute authentication path: a nodes */
		auth = sig;
		s = idx;
		for(j = 0; j < a; j++){
			/* Sibling of s at height j */
			u32int sib = s ^ 1;
			if(sib < (u32int)leaves)
				memmove(auth, nodes + sib*n, n);
			auth += n;

			/* Merge pairs for next level */
			{
				int p;
				int newnodes = leaves >> (j + 1);
				for(p = 0; p < newnodes; p++){
					fors_node(nodes + p*n, n,
						nodes + 2*p*n, nodes + (2*p+1)*n,
						pkseed, seedlen,
						adrs, j + 1, base / leaves * newnodes + p);
				}
			}
			s >>= 1;
		}
		sig = auth;
	}

	secureZero(nodes, leaves * n);
	free(nodes);
}

/*
 * Compute FORS public key from signature
 *
 * Algorithm 17 from FIPS 205
 */
void
slhdsa_fors_pk_from_sig(uchar *pk, int n,
	const uchar *sig,
	const uchar *md,
	const uchar *pkseed, int seedlen,
	uchar adrs[32],
	int k, int a)
{
	uchar *roots;
	uchar node0[64], node1[64];
	uchar pkadrs[32];
	u32int idx, base;
	int i, j;
	const uchar *auth;

	roots = malloc(k * n);
	if(roots == nil)
		return;

	slhdsa_adrs_set_type(adrs, 3);	/* FORS_TREE */

	for(i = 0; i < k; i++){
		idx = fors_get_index(md, i, a);
		base = i * (1 << a);

		/* Compute leaf from secret value */
		slhdsa_adrs_set_height(adrs, 0);
		slhdsa_adrs_set_index(adrs, base + idx);
		slhdsa_F(node0, n, pkseed, seedlen, adrs, sig, n);
		sig += n;

		/* Reconstruct root using auth path */
		auth = sig;
		for(j = 0; j < a; j++){
			slhdsa_adrs_set_height(adrs, j + 1);

			if((idx >> j) & 1){
				/* node is right child */
				slhdsa_adrs_set_index(adrs, (base + idx) >> (j + 1));
				slhdsa_H(node1, n, pkseed, seedlen, adrs,
					auth, n, node0, n);
			} else {
				/* node is left child */
				slhdsa_adrs_set_index(adrs, (base + idx) >> (j + 1));
				slhdsa_H(node1, n, pkseed, seedlen, adrs,
					node0, n, auth, n);
			}
			memmove(node0, node1, n);
			auth += n;
		}
		memmove(roots + i*n, node0, n);
		sig = auth;
	}

	/* Compress k roots into pk */
	slhdsa_adrs_copy(pkadrs, adrs);
	slhdsa_adrs_set_type(pkadrs, 4);	/* FORS_ROOTS */
	slhdsa_adrs_set_keypair(pkadrs, 0);
	memmove(pkadrs + 20, adrs + 20, 4);

	slhdsa_Tl(pk, n, pkseed, seedlen, pkadrs, roots, k * n);

	free(roots);
}
