/*
 * SLH-DSA (FIPS 205) WOTS+ One-Time Signatures
 *
 * WOTS+ (Winternitz One-Time Signature) with w=16.
 * Each WOTS+ signature signs a single n-byte message.
 *
 * With w=16 (base-16):
 *   len1 = ceil(8n/4) = 2n  (message digits)
 *   len2 = floor(log_16(len1 * 15)) + 1  (checksum digits)
 *   len = len1 + len2
 *
 * Reference: FIPS 205 Section 5
 */
#include "os.h"
#include <libsec.h>

/*
 * WOTS+ parameters for w=16
 */
enum {
	WOTS_W = 16,		/* Winternitz parameter */
	WOTS_LOGW = 4,		/* log2(w) */
};

/* Forward declarations for hash functions (slhdsa_hash.c) */
extern void slhdsa_adrs_set_type(uchar*, u32int);
extern void slhdsa_adrs_set_keypair(uchar*, u32int);
extern void slhdsa_adrs_set_chain(uchar*, u32int);
extern void slhdsa_adrs_set_hash(uchar*, u32int);
extern void slhdsa_adrs_copy(uchar*, const uchar*);
extern void slhdsa_F(uchar*, int, const uchar*, int, const uchar*, const uchar*, int);
extern void slhdsa_PRF(uchar*, int, const uchar*, int, const uchar*, int, const uchar*);
extern void slhdsa_Tl(uchar*, int, const uchar*, int, const uchar*, const uchar*, int);

/*
 * Compute WOTS+ len parameters
 * len1 = 2*n (for w=16)
 * len2 depends on n:
 *   n=24: len2=3, len=51
 *   n=32: len2=3, len=67
 */
int
slhdsa_wots_len(int n)
{
	int len1;

	len1 = 2 * n;	/* ceil(8n/log2(16)) = 2n */
	/* len2 = floor(log_16(len1 * (w-1))) + 1
	 * For n=24: len1=48, 48*15=720, log_16(720)=2.37, len2=3
	 * For n=32: len1=64, 64*15=960, log_16(960)=2.48, len2=3
	 */
	USED(n);
	return len1 + 3;	/* len2=3 for both 192s and 256s */
}

/*
 * Convert message to base-16 digits and compute checksum
 * msg: n-byte message
 * digits: output array of len base-16 digits
 */
static void
wots_chain_lengths(int *digits, const uchar *msg, int n)
{
	int i, len1, csum;

	len1 = 2 * n;

	/* Extract base-16 digits from message */
	for(i = 0; i < n; i++){
		digits[2*i]     = (msg[i] >> 4) & 0x0f;
		digits[2*i + 1] = msg[i] & 0x0f;
	}

	/* Compute checksum */
	csum = 0;
	for(i = 0; i < len1; i++)
		csum += WOTS_W - 1 - digits[i];

	/* Encode checksum as base-16 digits (3 digits for both levels) */
	/* csum max = len1 * 15, fits in 12 bits for n<=32 */
	csum <<= (8 - ((3 * WOTS_LOGW) % 8)) % 8;	/* left-align */
	digits[len1]     = (csum >> 8) & 0x0f;
	digits[len1 + 1] = (csum >> 4) & 0x0f;
	digits[len1 + 2] = csum & 0x0f;
}

/*
 * WOTS+ chain function
 * Apply F() iteratively: chain(x, start, steps)
 *   tmp = x
 *   for i = start to start+steps-1:
 *     ADRS.setHash(i)
 *     tmp = F(PK.seed, ADRS, tmp)
 */
static void
wots_chain(uchar *out, const uchar *in, int n,
	int start, int steps,
	const uchar *pkseed, int seedlen,
	uchar adrs[32])
{
	int i;

	memmove(out, in, n);
	for(i = start; i < start + steps; i++){
		slhdsa_adrs_set_hash(adrs, i);
		slhdsa_F(out, n, pkseed, seedlen, adrs, out, n);
	}
}

/*
 * Generate WOTS+ public key
 *
 * Algorithm 6 from FIPS 205
 */
void
slhdsa_wots_pkgen(uchar *pk, int n,
	const uchar *pkseed, int seedlen,
	const uchar *skseed, int skseedlen,
	uchar adrs[32])
{
	uchar skadrs[32];
	uchar pkadrs[32];
	uchar *tmp;
	uchar sk[64];	/* max n=32 */
	int i, len;

	len = slhdsa_wots_len(n);

	/* Allocate temporary buffer for concatenated public key chains */
	tmp = malloc(len * n);
	if(tmp == nil)
		return;

	/* Generate each chain's public value */
	slhdsa_adrs_copy(skadrs, adrs);
	slhdsa_adrs_set_type(skadrs, 5);	/* WOTS_PRF */
	slhdsa_adrs_set_keypair(skadrs, 0);

	/* Copy keypair address from input ADRS */
	memmove(skadrs + 20, adrs + 20, 4);

	for(i = 0; i < len; i++){
		slhdsa_adrs_set_chain(skadrs, i);
		slhdsa_adrs_set_hash(skadrs, 0);
		slhdsa_PRF(sk, n, pkseed, seedlen, skseed, skseedlen, skadrs);

		slhdsa_adrs_set_chain(adrs, i);
		wots_chain(tmp + i*n, sk, n, 0, WOTS_W - 1, pkseed, seedlen, adrs);
	}

	/* Compress: pk = T_l(PK.seed, ADRS, tmp0 || ... || tmp_{len-1}) */
	slhdsa_adrs_copy(pkadrs, adrs);
	slhdsa_adrs_set_type(pkadrs, 1);	/* WOTS_PK */
	slhdsa_adrs_set_keypair(pkadrs, 0);
	memmove(pkadrs + 20, adrs + 20, 4);

	slhdsa_Tl(pk, n, pkseed, seedlen, pkadrs, tmp, len * n);

	memset(sk, 0, sizeof(sk));
	memset(tmp, 0, len * n);
	free(tmp);
}

/*
 * Generate WOTS+ signature
 *
 * Algorithm 7 from FIPS 205
 */
void
slhdsa_wots_sign(uchar *sig, int n,
	const uchar *msg,
	const uchar *pkseed, int seedlen,
	const uchar *skseed, int skseedlen,
	uchar adrs[32])
{
	uchar skadrs[32];
	uchar sk[64];
	int *digits;
	int i, len;

	len = slhdsa_wots_len(n);

	digits = malloc(len * sizeof(int));
	if(digits == nil)
		return;

	wots_chain_lengths(digits, msg, n);

	slhdsa_adrs_copy(skadrs, adrs);
	slhdsa_adrs_set_type(skadrs, 5);	/* WOTS_PRF */
	slhdsa_adrs_set_keypair(skadrs, 0);
	memmove(skadrs + 20, adrs + 20, 4);

	for(i = 0; i < len; i++){
		slhdsa_adrs_set_chain(skadrs, i);
		slhdsa_adrs_set_hash(skadrs, 0);
		slhdsa_PRF(sk, n, pkseed, seedlen, skseed, skseedlen, skadrs);

		slhdsa_adrs_set_chain(adrs, i);
		wots_chain(sig + i*n, sk, n, 0, digits[i], pkseed, seedlen, adrs);
	}

	memset(sk, 0, sizeof(sk));
	free(digits);
}

/*
 * Compute WOTS+ public key from signature
 *
 * Algorithm 8 from FIPS 205
 */
void
slhdsa_wots_pk_from_sig(uchar *pk, int n,
	const uchar *sig,
	const uchar *msg,
	const uchar *pkseed, int seedlen,
	uchar adrs[32])
{
	uchar pkadrs[32];
	uchar *tmp;
	int *digits;
	int i, len;

	len = slhdsa_wots_len(n);

	digits = malloc(len * sizeof(int));
	tmp = malloc(len * n);
	if(digits == nil || tmp == nil){
		free(digits);
		free(tmp);
		return;
	}

	wots_chain_lengths(digits, msg, n);

	for(i = 0; i < len; i++){
		slhdsa_adrs_set_chain(adrs, i);
		wots_chain(tmp + i*n, sig + i*n, n,
			digits[i], WOTS_W - 1 - digits[i],
			pkseed, seedlen, adrs);
	}

	/* Compress */
	slhdsa_adrs_copy(pkadrs, adrs);
	slhdsa_adrs_set_type(pkadrs, 1);	/* WOTS_PK */
	slhdsa_adrs_set_keypair(pkadrs, 0);
	memmove(pkadrs + 20, adrs + 20, 4);

	slhdsa_Tl(pk, n, pkseed, seedlen, pkadrs, tmp, len * n);

	free(digits);
	memset(tmp, 0, len * n);
	free(tmp);
}
