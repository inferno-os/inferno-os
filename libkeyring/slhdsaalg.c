/*
 * SLH-DSA (FIPS 205) signature algorithm implementation for Inferno keyring
 *
 * SLH-DSA-SHAKE-192s provides NIST Level 3 security:
 * - Secret key: 96 bytes
 * - Public key: 48 bytes
 * - Signature: 16224 bytes
 *
 * SLH-DSA-SHAKE-256s provides NIST Level 5 security:
 * - Secret key: 128 bytes
 * - Public key: 64 bytes
 * - Signature: 29792 bytes
 *
 * Both levels use the same SigAlgVec interface with level-specific
 * key structures that store the actual byte sizes.
 *
 * Signatures are much larger than ML-DSA because SLH-DSA is hash-based
 * (Merkle trees + WOTS+ + FORS), but security relies only on hash function
 * security — no lattice assumptions.
 */

#include <lib9.h>
#include <kernel.h>
#include <isa.h>
#include "interp.h"
#include "../libinterp/keyringif.h"
#include "mp.h"
#include "libsec.h"
#include "keys.h"

/*
 * SLH-DSA key structures
 * We use max-sized arrays and track the actual level for size dispatch.
 */
typedef struct SLHDSApriv SLHDSApriv;
typedef struct SLHDSApub SLHDSApub;
typedef struct SLHDSAsig SLHDSAsig;

struct SLHDSApriv {
	uchar	sk[SLHDSA256S_SKLEN];	/* sized to largest level */
	uchar	pk[SLHDSA256S_PKLEN];
	int	sklen;
	int	pklen;
	int	level;			/* 192 or 256 */
};

struct SLHDSApub {
	uchar	key[SLHDSA256S_PKLEN];
	int	keylen;
	int	level;
};

struct SLHDSAsig {
	uchar	*sig;			/* heap-allocated due to large size */
	int	siglen;
	int	level;
};

/*
 * Allocation functions
 */
static SLHDSApriv*
slhdsaprivalloc(void)
{
	SLHDSApriv *k;
	k = malloc(sizeof(SLHDSApriv));
	if(k == nil)
		return nil;
	memset(k, 0, sizeof(SLHDSApriv));
	return k;
}

static SLHDSApub*
slhdsapuballoc(void)
{
	SLHDSApub *k;
	k = malloc(sizeof(SLHDSApub));
	if(k == nil)
		return nil;
	memset(k, 0, sizeof(SLHDSApub));
	return k;
}

static SLHDSAsig*
slhdsasigalloc(int siglen)
{
	SLHDSAsig *s;
	s = malloc(sizeof(SLHDSAsig));
	if(s == nil)
		return nil;
	memset(s, 0, sizeof(SLHDSAsig));
	s->sig = malloc(siglen);
	if(s->sig == nil){
		free(s);
		return nil;
	}
	memset(s->sig, 0, siglen);
	s->siglen = siglen;
	return s;
}

/*
 * Free functions
 */
static void
slhdsaprivfree(SLHDSApriv *k)
{
	if(k == nil)
		return;
	memset(k, 0, sizeof(SLHDSApriv));	/* clear secret key */
	free(k);
}

static void
slhdsapubfree(SLHDSApub *k)
{
	free(k);
}

static void
slhdsasigfree(SLHDSAsig *s)
{
	if(s == nil)
		return;
	if(s->sig != nil){
		memset(s->sig, 0, s->siglen);
		free(s->sig);
	}
	free(s);
}

/*
 * Attribute lists for serialization
 */
static char* pkattr[] = { "pk", nil };
static char* skattr[] = { "sk", "pk", nil };
static char* sigattr[] = { "sig", nil };

/*
 * Base64 encoding/decoding for byte arrays
 */
static int
bytes2base64(uchar *bytes, int len, char *buf, int buflen)
{
	int n;
	n = enc64(buf, buflen, bytes, len);
	if(n > 0 && n < buflen)
		buf[n++] = '\n';
	buf[n] = 0;
	return n;
}

static int
base64tobytes(char *str, uchar *bytes, int len, char **strp)
{
	char *p;
	int n;

	for(p = str; *p && *p != '\n'; p++)
		;
	n = dec64(bytes, len, str, p - str);
	if(strp){
		if(*p)
			p++;
		*strp = p;
	}
	return n;
}

/*
 * Helper: get key sizes for a level
 */
static void
slhdsa_sizes(int level, int *sklen, int *pklen, int *siglen)
{
	if(level == 256){
		*sklen = SLHDSA256S_SKLEN;
		*pklen = SLHDSA256S_PKLEN;
		*siglen = SLHDSA256S_SIGLEN;
	} else {
		*sklen = SLHDSA192S_SKLEN;
		*pklen = SLHDSA192S_PKLEN;
		*siglen = SLHDSA192S_SIGLEN;
	}
}

/*
 * String to key conversions for SLH-DSA-SHAKE-192s
 */
static void*
slhdsa192s_str2sk(char *str, char **strp)
{
	SLHDSApriv *k;
	char *p;
	int n;

	k = slhdsaprivalloc();
	if(k == nil)
		return nil;

	k->level = 192;
	k->sklen = SLHDSA192S_SKLEN;
	k->pklen = SLHDSA192S_PKLEN;

	/* Read secret key */
	n = base64tobytes(str, k->sk, SLHDSA192S_SKLEN, &p);
	if(n != SLHDSA192S_SKLEN){
		slhdsaprivfree(k);
		return nil;
	}

	/* Read public key */
	n = base64tobytes(p, k->pk, SLHDSA192S_PKLEN, &p);
	if(n != SLHDSA192S_PKLEN){
		slhdsaprivfree(k);
		return nil;
	}

	if(strp)
		*strp = p;

	return k;
}

static void*
slhdsa192s_str2pk(char *str, char **strp)
{
	SLHDSApub *k;
	char *p;
	int n;

	k = slhdsapuballoc();
	if(k == nil)
		return nil;

	k->level = 192;
	k->keylen = SLHDSA192S_PKLEN;

	n = base64tobytes(str, k->key, SLHDSA192S_PKLEN, &p);
	if(n != SLHDSA192S_PKLEN){
		slhdsapubfree(k);
		return nil;
	}

	if(strp)
		*strp = p;

	return k;
}

static void*
slhdsa192s_str2sig(char *str, char **strp)
{
	SLHDSAsig *s;
	char *p;
	int n;

	s = slhdsasigalloc(SLHDSA192S_SIGLEN);
	if(s == nil)
		return nil;

	s->level = 192;

	n = base64tobytes(str, s->sig, SLHDSA192S_SIGLEN, &p);
	if(n != SLHDSA192S_SIGLEN){
		slhdsasigfree(s);
		return nil;
	}

	if(strp)
		*strp = p;

	return s;
}

/*
 * String to key conversions for SLH-DSA-SHAKE-256s
 */
static void*
slhdsa256s_str2sk(char *str, char **strp)
{
	SLHDSApriv *k;
	char *p;
	int n;

	k = slhdsaprivalloc();
	if(k == nil)
		return nil;

	k->level = 256;
	k->sklen = SLHDSA256S_SKLEN;
	k->pklen = SLHDSA256S_PKLEN;

	n = base64tobytes(str, k->sk, SLHDSA256S_SKLEN, &p);
	if(n != SLHDSA256S_SKLEN){
		slhdsaprivfree(k);
		return nil;
	}

	n = base64tobytes(p, k->pk, SLHDSA256S_PKLEN, &p);
	if(n != SLHDSA256S_PKLEN){
		slhdsaprivfree(k);
		return nil;
	}

	if(strp)
		*strp = p;

	return k;
}

static void*
slhdsa256s_str2pk(char *str, char **strp)
{
	SLHDSApub *k;
	char *p;
	int n;

	k = slhdsapuballoc();
	if(k == nil)
		return nil;

	k->level = 256;
	k->keylen = SLHDSA256S_PKLEN;

	n = base64tobytes(str, k->key, SLHDSA256S_PKLEN, &p);
	if(n != SLHDSA256S_PKLEN){
		slhdsapubfree(k);
		return nil;
	}

	if(strp)
		*strp = p;

	return k;
}

static void*
slhdsa256s_str2sig(char *str, char **strp)
{
	SLHDSAsig *s;
	char *p;
	int n;

	s = slhdsasigalloc(SLHDSA256S_SIGLEN);
	if(s == nil)
		return nil;

	s->level = 256;

	n = base64tobytes(str, s->sig, SLHDSA256S_SIGLEN, &p);
	if(n != SLHDSA256S_SIGLEN){
		slhdsasigfree(s);
		return nil;
	}

	if(strp)
		*strp = p;

	return s;
}

/*
 * Key to string conversions (shared for both levels)
 */
static int
slhdsa_sk2str(void *vk, char *buf, int len)
{
	SLHDSApriv *k = (SLHDSApriv*)vk;
	char *cp = buf;
	char *ep = buf + len - 1;

	cp += bytes2base64(k->sk, k->sklen, cp, ep - cp);
	cp += bytes2base64(k->pk, k->pklen, cp, ep - cp);
	*cp = 0;

	return cp - buf;
}

static int
slhdsa_pk2str(void *vk, char *buf, int len)
{
	SLHDSApub *k = (SLHDSApub*)vk;
	char *cp = buf;
	char *ep = buf + len - 1;

	cp += bytes2base64(k->key, k->keylen, cp, ep - cp);
	*cp = 0;

	return cp - buf;
}

static int
slhdsa_sig2str(void *vs, char *buf, int len)
{
	SLHDSAsig *s = (SLHDSAsig*)vs;
	char *cp = buf;
	char *ep = buf + len - 1;

	cp += bytes2base64(s->sig, s->siglen, cp, ep - cp);
	*cp = 0;

	return cp - buf;
}

/*
 * Convert secret key to public key
 */
static void*
slhdsa_sk2pk(void *vs)
{
	SLHDSApriv *sk = (SLHDSApriv*)vs;
	SLHDSApub *pk;

	pk = slhdsapuballoc();
	if(pk == nil)
		return nil;

	pk->level = sk->level;
	pk->keylen = sk->pklen;
	memmove(pk->key, sk->pk, sk->pklen);

	return pk;
}

/*
 * Generate a new SLH-DSA-SHAKE-192s keypair
 */
static void*
slhdsa192s_gen(int len)
{
	SLHDSApriv *k;

	USED(len);

	k = slhdsaprivalloc();
	if(k == nil)
		return nil;

	k->level = 192;
	k->sklen = SLHDSA192S_SKLEN;
	k->pklen = SLHDSA192S_PKLEN;

	if(slhdsa192s_keygen(k->pk, k->sk) != 0){
		slhdsaprivfree(k);
		return nil;
	}

	return k;
}

/*
 * Generate a new SLH-DSA-SHAKE-256s keypair
 */
static void*
slhdsa256s_gen(int len)
{
	SLHDSApriv *k;

	USED(len);

	k = slhdsaprivalloc();
	if(k == nil)
		return nil;

	k->level = 256;
	k->sklen = SLHDSA256S_SKLEN;
	k->pklen = SLHDSA256S_PKLEN;

	if(slhdsa256s_keygen(k->pk, k->sk) != 0){
		slhdsaprivfree(k);
		return nil;
	}

	return k;
}

/*
 * Generate from public key (just generates independent keypair)
 */
static void*
slhdsa192s_genfrompk(void *vpub)
{
	USED(vpub);
	return slhdsa192s_gen(0);
}

static void*
slhdsa256s_genfrompk(void *vpub)
{
	USED(vpub);
	return slhdsa256s_gen(0);
}

/*
 * Sign a message hash
 * Inferno's SigAlgVec passes an mpint (the hash). We convert it
 * to bytes and sign those bytes directly with SLH-DSA.
 */
static void*
slhdsa_sign_hash(mpint *mp, void *key)
{
	SLHDSApriv *sk = (SLHDSApriv*)key;
	SLHDSAsig *sig;
	uchar hash[SHA512dlen];
	int n, rv, sklen, pklen, siglen;

	slhdsa_sizes(sk->level, &sklen, &pklen, &siglen);

	sig = slhdsasigalloc(siglen);
	if(sig == nil)
		return nil;

	/* Convert mpint to bytes (the hash to sign) */
	n = mptobe(mp, hash, sizeof(hash), nil);
	if(n < 0){
		slhdsasigfree(sig);
		return nil;
	}

	sig->level = sk->level;

	if(sk->level == 256)
		rv = slhdsa256s_sign(sig->sig, hash, n, sk->sk);
	else
		rv = slhdsa192s_sign(sig->sig, hash, n, sk->sk);

	memset(hash, 0, sizeof(hash));

	if(rv != 0){
		slhdsasigfree(sig);
		return nil;
	}

	return sig;
}

/*
 * Verify a signature
 */
static int
slhdsa_verify_hash(mpint *mp, void *vsig, void *vkey)
{
	SLHDSApub *pk = (SLHDSApub*)vkey;
	SLHDSAsig *sig = (SLHDSAsig*)vsig;
	uchar hash[SHA512dlen];
	int n, ok;

	/* Convert mpint to bytes */
	n = mptobe(mp, hash, sizeof(hash), nil);
	if(n < 0)
		return 0;

	if(pk->level == 256)
		ok = slhdsa256s_verify(sig->sig, sig->siglen, hash, n, pk->key);
	else
		ok = slhdsa192s_verify(sig->sig, sig->siglen, hash, n, pk->key);

	memset(hash, 0, sizeof(hash));
	return ok;
}

/*
 * Free functions for SigAlgVec
 */
static void
slhdsa_freepub(void *a)
{
	slhdsapubfree((SLHDSApub*)a);
}

static void
slhdsa_freepriv(void *a)
{
	slhdsaprivfree((SLHDSApriv*)a);
}

static void
slhdsa_freesig(void *a)
{
	slhdsasigfree((SLHDSAsig*)a);
}

/*
 * Initialize and return the SLH-DSA-SHAKE-192s signature algorithm vector
 */
SigAlgVec*
slhdsa192sinit(void)
{
	SigAlgVec *vec;

	vec = malloc(sizeof(SigAlgVec));
	if(vec == nil)
		return nil;

	vec->name = "slhdsa192s";

	vec->pkattr = pkattr;
	vec->skattr = skattr;
	vec->sigattr = sigattr;

	vec->str2sk = slhdsa192s_str2sk;
	vec->str2pk = slhdsa192s_str2pk;
	vec->str2sig = slhdsa192s_str2sig;

	vec->sk2str = slhdsa_sk2str;
	vec->pk2str = slhdsa_pk2str;
	vec->sig2str = slhdsa_sig2str;

	vec->sk2pk = slhdsa_sk2pk;

	vec->gensk = slhdsa192s_gen;
	vec->genskfrompk = slhdsa192s_genfrompk;
	vec->sign = slhdsa_sign_hash;
	vec->verify = slhdsa_verify_hash;

	vec->skfree = slhdsa_freepriv;
	vec->pkfree = slhdsa_freepub;
	vec->sigfree = slhdsa_freesig;

	return vec;
}

/*
 * Initialize and return the SLH-DSA-SHAKE-256s signature algorithm vector
 */
SigAlgVec*
slhdsa256sinit(void)
{
	SigAlgVec *vec;

	vec = malloc(sizeof(SigAlgVec));
	if(vec == nil)
		return nil;

	vec->name = "slhdsa256s";

	vec->pkattr = pkattr;
	vec->skattr = skattr;
	vec->sigattr = sigattr;

	vec->str2sk = slhdsa256s_str2sk;
	vec->str2pk = slhdsa256s_str2pk;
	vec->str2sig = slhdsa256s_str2sig;

	vec->sk2str = slhdsa_sk2str;
	vec->pk2str = slhdsa_pk2str;
	vec->sig2str = slhdsa_sig2str;

	vec->sk2pk = slhdsa_sk2pk;

	vec->gensk = slhdsa256s_gen;
	vec->genskfrompk = slhdsa256s_genfrompk;
	vec->sign = slhdsa_sign_hash;
	vec->verify = slhdsa_verify_hash;

	vec->skfree = slhdsa_freepriv;
	vec->pkfree = slhdsa_freepub;
	vec->sigfree = slhdsa_freesig;

	return vec;
}
