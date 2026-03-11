/*
 * SLH-DSA (FIPS 205) Merkle Tree and Hypertree
 *
 * XMSS (eXtended Merkle Signature Scheme) trees are composed of
 * WOTS+ signatures at the leaves and Merkle authentication paths.
 *
 * The hypertree is d layers of XMSS trees, each of height h'.
 * Total tree height h = h' * d.
 *
 * SLH-DSA-SHAKE-192s: h=63, d=7, h'=9
 * SLH-DSA-SHAKE-256s: h=64, d=8, h'=8
 *
 * Reference: FIPS 205 Sections 6, 9
 */
#include "os.h"
#include <libsec.h>

/* Forward declarations */
extern void slhdsa_adrs_init(uchar*);
extern void slhdsa_adrs_set_layer(uchar*, u32int);
extern void slhdsa_adrs_set_tree(uchar*, u64int);
extern void slhdsa_adrs_set_type(uchar*, u32int);
extern void slhdsa_adrs_set_keypair(uchar*, u32int);
extern void slhdsa_adrs_set_height(uchar*, u32int);
extern void slhdsa_adrs_set_index(uchar*, u32int);
extern void slhdsa_adrs_copy(uchar*, const uchar*);
extern void slhdsa_H(uchar*, int, const uchar*, int, const uchar*, const uchar*, int, const uchar*, int);
extern void slhdsa_wots_pkgen(uchar*, int, const uchar*, int, const uchar*, int, uchar*);
extern void slhdsa_wots_sign(uchar*, int, const uchar*, const uchar*, int, const uchar*, int, uchar*);
extern void slhdsa_wots_pk_from_sig(uchar*, int, const uchar*, const uchar*, const uchar*, int, uchar*);
extern int  slhdsa_wots_len(int);

/*
 * treehash: compute Merkle tree root and optionally an auth path.
 *
 * Builds a binary Merkle tree of height h' over WOTS+ public keys.
 * If auth_idx >= 0, also computes the authentication path.
 *
 * Algorithm 10 from FIPS 205
 */
int
slhdsa_treehash(uchar *root, uchar *auth, int n,
	const uchar *pkseed, int seedlen,
	const uchar *skseed, int skseedlen,
	u32int layer, u64int tree, int hprime,
	int auth_idx)
{
	uchar adrs[32];
	uchar *stack;	/* (hprime+1) * n */
	uchar node[64];	/* current node being merged up (max n=32) */
	uchar tmp[64];
	int i, j, leaves;

	leaves = 1 << hprime;
	stack = malloc((hprime + 1) * n);
	if(stack == nil)
		return -1;

	slhdsa_adrs_init(adrs);
	slhdsa_adrs_set_layer(adrs, layer);
	slhdsa_adrs_set_tree(adrs, tree);

	for(i = 0; i < leaves; i++){
		/* Generate WOTS+ public key for leaf i */
		slhdsa_adrs_set_type(adrs, 0);	/* WOTS_HASH */
		slhdsa_adrs_set_keypair(adrs, i);
		slhdsa_wots_pkgen(node, n, pkseed, seedlen, skseed, skseedlen, adrs);

		slhdsa_adrs_set_type(adrs, 2);	/* TREE */

		/* Save auth path node at height 0 if this is the sibling */
		if(auth != nil && auth_idx >= 0 && i == (auth_idx ^ 1))
			memmove(auth, node, n);

		/*
		 * Merge up the tree: when bit j of i is set, there's a
		 * completed subtree of height j at stack[j] (left child).
		 * node is the right child. Hash them together.
		 */
		for(j = 0; (i >> j) & 1; j++){
			slhdsa_adrs_set_height(adrs, j + 1);
			slhdsa_adrs_set_index(adrs, i >> (j + 1));
			/* left=stack[j], right=node */
			slhdsa_H(tmp, n, pkseed, seedlen, adrs,
				stack + j*n, n, node, n);
			memmove(node, tmp, n);

			/* Save auth path node at height j+1 if sibling */
			if(auth != nil && auth_idx >= 0){
				u32int sib = (auth_idx >> (j+1)) ^ 1;
				if((u32int)(i >> (j+1)) == sib)
					memmove(auth + (j+1)*n, node, n);
			}
		}
		/* Store at the first empty stack position */
		memmove(stack + j*n, node, n);
	}

	memmove(root, stack + hprime*n, n);
	secureZero(stack, (hprime + 1) * n);
	free(stack);
	return 0;
}

/*
 * Generate XMSS signature at a given layer
 * Produces: WOTS+ signature || authentication path
 *
 * Algorithm 11 from FIPS 205
 */
void
slhdsa_xmss_sign(uchar *sig, int n,
	const uchar *msg,
	const uchar *pkseed, int seedlen,
	const uchar *skseed, int skseedlen,
	u32int layer, u64int tree, int hprime, int idx)
{
	uchar adrs[32];
	int wots_siglen;
	uchar root[64]; /* unused but needed by treehash */

	wots_siglen = slhdsa_wots_len(n) * n;

	slhdsa_adrs_init(adrs);
	slhdsa_adrs_set_layer(adrs, layer);
	slhdsa_adrs_set_tree(adrs, tree);
	slhdsa_adrs_set_type(adrs, 0);	/* WOTS_HASH */
	slhdsa_adrs_set_keypair(adrs, idx);

	/* Generate WOTS+ signature on msg */
	slhdsa_wots_sign(sig, n, msg, pkseed, seedlen, skseed, skseedlen, adrs);

	/* Compute authentication path using treehash */
	slhdsa_treehash(root, sig + wots_siglen, n,
		pkseed, seedlen, skseed, skseedlen,
		layer, tree, hprime, idx);
}

/*
 * Compute XMSS root from signature
 *
 * Algorithm 12 from FIPS 205 (partial - computes root)
 */
void
slhdsa_xmss_root_from_sig(uchar *root, int n,
	const uchar *sig, int idx,
	const uchar *msg,
	const uchar *pkseed, int seedlen,
	u32int layer, u64int tree, int hprime)
{
	uchar adrs[32];
	int wots_siglen;
	const uchar *auth;
	uchar node[64];
	uchar tmp[64];
	int j;

	wots_siglen = slhdsa_wots_len(n) * n;
	auth = sig + wots_siglen;

	slhdsa_adrs_init(adrs);
	slhdsa_adrs_set_layer(adrs, layer);
	slhdsa_adrs_set_tree(adrs, tree);
	slhdsa_adrs_set_type(adrs, 0);	/* WOTS_HASH */
	slhdsa_adrs_set_keypair(adrs, idx);

	/* Recover WOTS+ public key */
	slhdsa_wots_pk_from_sig(node, n, sig, msg, pkseed, seedlen, adrs);

	/* Walk up the tree using auth path */
	slhdsa_adrs_set_type(adrs, 2);	/* TREE */
	for(j = 0; j < hprime; j++){
		slhdsa_adrs_set_height(adrs, j + 1);
		slhdsa_adrs_set_index(adrs, idx >> (j + 1));

		if((idx >> j) & 1){
			/* node is right child */
			slhdsa_H(tmp, n, pkseed, seedlen, adrs,
				auth + j*n, n, node, n);
		} else {
			/* node is left child */
			slhdsa_H(tmp, n, pkseed, seedlen, adrs,
				node, n, auth + j*n, n);
		}
		memmove(node, tmp, n);
	}

	memmove(root, node, n);
}

/*
 * Generate hypertree signature
 *
 * Algorithm 13 from FIPS 205
 *
 * Signs message M using d layers of XMSS trees.
 * idx_tree encodes the tree path, idx_leaf selects the leaf.
 */
void
slhdsa_ht_sign(uchar *sig, int n,
	const uchar *msg,
	const uchar *pkseed, int seedlen,
	const uchar *skseed, int skseedlen,
	u64int idx_tree, u32int idx_leaf,
	int hprime, int d)
{
	uchar root[64];
	int xmss_siglen;
	int i;
	u32int leafidx;
	u64int treeidx;

	xmss_siglen = (slhdsa_wots_len(n) + hprime) * n;

	/* Layer 0: sign the message */
	slhdsa_xmss_sign(sig, n, msg, pkseed, seedlen, skseed, skseedlen,
		0, idx_tree, hprime, idx_leaf);

	/* Get root for verification of next layer */
	slhdsa_xmss_root_from_sig(root, n, sig, idx_leaf, msg,
		pkseed, seedlen, 0, idx_tree, hprime);
	sig += xmss_siglen;

	/* Layers 1 to d-1: each signs the root of the layer below */
	treeidx = idx_tree;
	for(i = 1; i < d; i++){
		leafidx = treeidx & ((1ULL << hprime) - 1);
		treeidx >>= hprime;

		slhdsa_xmss_sign(sig, n, root, pkseed, seedlen, skseed, skseedlen,
			i, treeidx, hprime, leafidx);

		if(i < d - 1){
			slhdsa_xmss_root_from_sig(root, n, sig, leafidx, root,
				pkseed, seedlen, i, treeidx, hprime);
		}
		sig += xmss_siglen;
	}
}

/*
 * Verify hypertree signature
 *
 * Algorithm 14 from FIPS 205
 *
 * Returns 1 if valid, 0 if invalid.
 */
int
slhdsa_ht_verify(const uchar *sig, int n,
	const uchar *msg,
	const uchar *pkseed, int seedlen,
	const uchar *pkroot,
	u64int idx_tree, u32int idx_leaf,
	int hprime, int d)
{
	uchar node[64];
	int xmss_siglen;
	int i;
	u32int leafidx;
	u64int treeidx;

	xmss_siglen = (slhdsa_wots_len(n) + hprime) * n;

	/* Layer 0: recover root from signature */
	slhdsa_xmss_root_from_sig(node, n, sig, idx_leaf, msg,
		pkseed, seedlen, 0, idx_tree, hprime);
	sig += xmss_siglen;

	/* Layers 1 to d-1 */
	treeidx = idx_tree;
	for(i = 1; i < d; i++){
		leafidx = treeidx & ((1ULL << hprime) - 1);
		treeidx >>= hprime;

		slhdsa_xmss_root_from_sig(node, n, sig, leafidx, node,
			pkseed, seedlen, i, treeidx, hprime);
		sig += xmss_siglen;
	}

	/* Compare with known root (constant-time) */
	{
		int i;
		uchar diff;

		diff = 0;
		for(i = 0; i < n; i++)
			diff |= node[i] ^ pkroot[i];
		return diff == 0;
	}
}
