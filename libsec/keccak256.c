/*
 * Keccak-256 (Ethereum variant).
 *
 * Identical to SHA3-256 except for the domain separator byte:
 *   Keccak-256 uses 0x01 (original Keccak submission)
 *   SHA3-256 uses 0x06 (NIST FIPS 202 standardization)
 *
 * The Keccak-f[1600] permutation and sponge construction are
 * shared with sha3.c.  Only the finalization differs.
 *
 * Reference:
 *   Ethereum Yellow Paper, Appendix F
 *   The Keccak Reference (Bertoni et al., 2011)
 */
#include "os.h"
#include <libsec.h>

/*
 * Keccak-f[1600] round constants (same as sha3.c)
 */
static const u64int K256_RC[24] = {
	0x0000000000000001ULL, 0x0000000000008082ULL,
	0x800000000000808aULL, 0x8000000080008000ULL,
	0x000000000000808bULL, 0x0000000080000001ULL,
	0x8000000080008081ULL, 0x8000000000008009ULL,
	0x000000000000008aULL, 0x0000000000000088ULL,
	0x0000000080008009ULL, 0x000000008000000aULL,
	0x000000008000808bULL, 0x800000000000008bULL,
	0x8000000000008089ULL, 0x8000000000008003ULL,
	0x8000000000008002ULL, 0x8000000000000080ULL,
	0x000000000000800aULL, 0x800000008000000aULL,
	0x8000000080008081ULL, 0x8000000000008080ULL,
	0x0000000080000001ULL, 0x8000000080008008ULL,
};

static const int K256_Rotc[24] = {
	 1,  3,  6, 10, 15, 21, 28, 36,
	45, 55,  2, 14, 27, 41, 56,  8,
	25, 43, 62, 18, 39, 61, 20, 44,
};

static const int K256_Piln[24] = {
	10,  7, 11, 17, 18,  3,  5, 16,
	 8, 21, 24,  4, 15, 23, 19, 13,
	12,  2, 20, 14, 22,  9,  6,  1,
};

#define K256_ROTL64(x, n) (((x) << (n)) | ((x) >> (64-(n))))

/*
 * Keccak-f[1600] permutation.
 * Duplicated from sha3.c to keep keccak256 self-contained
 * and avoid exposing sha3.c's static function.
 */
static void
k256_keccakf(u64int st[25])
{
	u64int t, bc[5];
	int i, j, r;

	for(r = 0; r < 24; r++){
		/* theta */
		for(i = 0; i < 5; i++)
			bc[i] = st[i] ^ st[i+5] ^ st[i+10] ^ st[i+15] ^ st[i+20];
		for(i = 0; i < 5; i++){
			t = bc[(i+4) % 5] ^ K256_ROTL64(bc[(i+1) % 5], 1);
			for(j = 0; j < 25; j += 5)
				st[j+i] ^= t;
		}

		/* rho and pi */
		t = st[1];
		for(i = 0; i < 24; i++){
			j = K256_Piln[i];
			bc[0] = st[j];
			st[j] = K256_ROTL64(t, K256_Rotc[i]);
			t = bc[0];
		}

		/* chi */
		for(j = 0; j < 25; j += 5){
			for(i = 0; i < 5; i++)
				bc[i] = st[j+i];
			for(i = 0; i < 5; i++)
				st[j+i] ^= (~bc[(i+1) % 5]) & bc[(i+2) % 5];
		}

		/* iota */
		st[0] ^= K256_RC[r];
	}
}

/*
 * Keccak-256: one-shot hash.
 *
 * rate = 136 bytes (1088 bits), capacity = 512 bits, output = 32 bytes.
 * Domain separator = 0x01 (NOT 0x06 as in SHA3-256).
 */
void
keccak256(const uchar *in, ulong inlen, uchar out[32])
{
	u64int st[25];
	uchar *sb;
	int i;
	ulong j;

	memset(st, 0, sizeof(st));
	sb = (uchar*)st;

	/* absorb */
	j = 0;
	for(; inlen > 0; inlen--){
		sb[j++] ^= *in++;
		if(j >= 136){
			k256_keccakf(st);
			j = 0;
		}
	}

	/* pad and finalize: Keccak uses 0x01, NOT SHA3's 0x06 */
	sb[j] ^= 0x01;
	sb[135] ^= 0x80;
	k256_keccakf(st);

	/* squeeze: output first 32 bytes */
	for(i = 0; i < 32; i++)
		out[i] = sb[i];
}
