/*
 * Stub libsec.h for CBMC verification of libsec crypto code.
 *
 * Provides forward declarations needed by mlkem_poly.c for
 * functions defined in mlkem_ntt.c and sha3.c.
 *
 * SHA3 functions are declared but not defined — CBMC handles
 * unreachable extern functions gracefully. The harnesses under
 * verification (encode/decode, poly_add/sub, normalize) do not
 * call SHA3 functions.
 */
#ifndef CBMC_LIBSEC_H
#define CBMC_LIBSEC_H

#include "os.h"

/* SHA-3 state (needed for mlkem_poly_sample_ntt/cbd declarations) */
typedef struct SHA3state SHA3state;
struct SHA3state
{
	u64int	a[25];
	uchar	buf[200];
	int	rate;
	int	pt;
	int	mdlen;
};

/* SHA-3 / SHAKE functions (not needed by verified harnesses) */
extern void	shake128_init(SHA3state *s);
extern void	shake128_absorb(SHA3state *s, const uchar *in, ulong inlen);
extern void	shake128_finalize(SHA3state *s);
extern void	shake128_squeeze(SHA3state *s, uchar *out, ulong outlen);
extern void	shake256_init(SHA3state *s);
extern void	shake256_absorb(SHA3state *s, const uchar *in, ulong inlen);
extern void	shake256_finalize(SHA3state *s);
extern void	shake256_squeeze(SHA3state *s, uchar *out, ulong outlen);

/* ML-KEM NTT functions (defined in mlkem_ntt.c) */
extern int16	mlkem_barrett_reduce(int16 a);
extern int16	mlkem_montgomery_reduce(int32 a);
extern int16	mlkem_cond_sub_q(int16 a);
extern void	mlkem_ntt(int16 r[256]);
extern void	mlkem_invntt(int16 r[256]);
extern void	mlkem_poly_basemul(int16 r[256], const int16 a[256], const int16 b[256]);

/* ML-KEM polynomial functions (defined in mlkem_poly.c) */
extern void	mlkem_poly_add(int16 r[256], const int16 a[256], const int16 b[256]);
extern void	mlkem_poly_sub(int16 r[256], const int16 a[256], const int16 b[256]);
extern void	mlkem_poly_reduce(int16 r[256]);
extern void	mlkem_poly_normalize(int16 r[256]);
extern void	mlkem_poly_encode(uchar *out, const int16 r[256], int bits);
extern void	mlkem_poly_decode(int16 r[256], const uchar *in, int bits);
extern void	mlkem_poly_compress(int16 r[256], int d);
extern void	mlkem_poly_decompress(int16 r[256], int d);

#endif /* CBMC_LIBSEC_H */
