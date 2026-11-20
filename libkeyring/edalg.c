#include <lib9.h>
#include <kernel.h>
#include <isa.h>
#include "interp.h"
#include "../libinterp/keyringif.h"
#include "mp.h"
#include "libsec.h"
#include "keys.h"

/*
 * Signature algorithms that sign bytes, not big integers:
 *
 *	ed25519		Ed25519 (RFC 8032)
 *	ed25519mldsa65	Ed25519 and ML-DSA-65 (FIPS 204) together: a
 *			signature is one of each over the same bytes,
 *			and is good only if both are
 *
 * In text, a public key is one line of base64 for each part; a secret
 * key is its public key followed by a 32-byte seed for each part; and
 * a signature is one line for each part. What is signed is Sigprefix,
 * a zero byte, and the digest the certificate names (sha256 for
 * preference). ML-DSA signs deterministically, with an empty context.
 */

typedef struct Ekey Ekey;
typedef struct Esig Esig;

enum {
	Seedlen = 32
};

struct Ekey
{
	int	secret;
	int	hybrid;
	uchar	edpub[Ed25519publen];
	uchar	edseed[Seedlen];
	uchar	mlseed[MLDSA65seedlen];
	uchar	mlpub[MLDSA65pklen];	/* hybrid only */
};

struct Esig
{
	uchar	ed[Ed25519siglen];
	uchar	ml[MLDSA65siglen];	/* hybrid only */
};

static char Sigprefix[] = "inferno signature 1";

static char*	pkattr[] = { "pk", nil };
static char*	skattr[] = { "pk", "!seed", nil };
static char*	sigattr[] = { "val", nil };
static char*	hpkattr[] = { "pk", "pqpk", nil };
static char*	hskattr[] = { "pk", "pqpk", "!seed", "!pqseed", nil };
static char*	hsigattr[] = { "val", "pqval", nil };

/*
 * one line of base64 holding exactly n bytes; the start of the next line, or nil
 */
static char*
getline(char *s, uchar *buf, int n)
{
	char *e;

	if(s == nil)
		return nil;
	e = strchr(s, '\n');
	if(e == nil)
		e = s + strlen(s);
	if(e-s != (n+2)/3*4 || dec64(buf, n, s, e-s) != n)
		return nil;
	if(*e == '\n')
		e++;
	return e;
}

static int
putline(char *buf, int len, uchar *a, int n)
{
	int m;

	if(len < (n+2)/3*4 + 2)
		return 0;
	m = enc64(buf, len-1, a, n);
	if(m < 0)
		return 0;
	buf[m++] = '\n';
	buf[m] = 0;
	return m;
}

/* the public halves must belong to the seeds */
static int
seedsmatch(Ekey *k)
{
	uchar pub[Ed25519publen], *mlpub;
	int ok;

	ed25519pub(pub, k->edseed);
	ok = memcmp(pub, k->edpub, sizeof pub) == 0;
	if(ok && k->hybrid){
		mlpub = malloc(MLDSA65pklen);
		if(mlpub == nil)
			return 0;
		mldsa65pub(mlpub, k->mlseed);
		ok = memcmp(mlpub, k->mlpub, MLDSA65pklen) == 0;
		free(mlpub);
	}
	return ok;
}

static void*
str2sk(char *str, char **strp, int hybrid)
{
	Ekey *k;
	char *p;

	k = mallocz(sizeof(*k), 1);
	if(k == nil)
		return nil;
	k->secret = 1;
	k->hybrid = hybrid;
	p = getline(str, k->edpub, sizeof k->edpub);
	if(hybrid)
		p = getline(p, k->mlpub, sizeof k->mlpub);
	p = getline(p, k->edseed, sizeof k->edseed);
	if(hybrid)
		p = getline(p, k->mlseed, sizeof k->mlseed);
	if(p == nil || !seedsmatch(k)){
		memset(k, 0, sizeof(*k));
		free(k);
		return nil;
	}
	if(strp)
		*strp = p;
	return k;
}

static void*
str2pk(char *str, char **strp, int hybrid)
{
	Ekey *k;
	char *p;

	k = mallocz(sizeof(*k), 1);
	if(k == nil)
		return nil;
	k->hybrid = hybrid;
	p = getline(str, k->edpub, sizeof k->edpub);
	if(hybrid)
		p = getline(p, k->mlpub, sizeof k->mlpub);
	if(p == nil){
		free(k);
		return nil;
	}
	if(strp)
		*strp = p;
	return k;
}

static void*
str2sig(char *str, char **strp, int hybrid)
{
	Esig *sig;
	char *p;

	sig = mallocz(sizeof(*sig), 1);
	if(sig == nil)
		return nil;
	p = getline(str, sig->ed, sizeof sig->ed);
	if(hybrid)
		p = getline(p, sig->ml, sizeof sig->ml);
	if(p == nil){
		free(sig);
		return nil;
	}
	if(strp)
		*strp = p;
	return sig;
}

static void*	ed_str2sk(char *s, char **p) { return str2sk(s, p, 0); }
static void*	ed_str2pk(char *s, char **p) { return str2pk(s, p, 0); }
static void*	ed_str2sig(char *s, char **p) { return str2sig(s, p, 0); }
static void*	hy_str2sk(char *s, char **p) { return str2sk(s, p, 1); }
static void*	hy_str2pk(char *s, char **p) { return str2pk(s, p, 1); }
static void*	hy_str2sig(char *s, char **p) { return str2sig(s, p, 1); }

static int
ed_pk2str(void *vk, char *buf, int len)
{
	Ekey *k;
	int n;

	k = vk;
	n = putline(buf, len, k->edpub, sizeof k->edpub);
	if(k->hybrid)
		n += putline(buf+n, len-n, k->mlpub, sizeof k->mlpub);
	return n;
}

static int
ed_sk2str(void *vk, char *buf, int len)
{
	Ekey *k;
	int n;

	k = vk;
	n = ed_pk2str(k, buf, len);
	n += putline(buf+n, len-n, k->edseed, sizeof k->edseed);
	if(k->hybrid)
		n += putline(buf+n, len-n, k->mlseed, sizeof k->mlseed);
	return n;
}

/* a signature is plain or hybrid by its length in text; each vector prints its own kind */
static int
ed_sig2str(void *vsig, char *buf, int len)
{
	Esig *sig;

	sig = vsig;
	return putline(buf, len, sig->ed, sizeof sig->ed);
}

static int
hy_sig2str(void *vsig, char *buf, int len)
{
	Esig *sig;
	int n;

	sig = vsig;
	n = putline(buf, len, sig->ed, sizeof sig->ed);
	n += putline(buf+n, len-n, sig->ml, sizeof sig->ml);
	return n;
}

static void*
ed_sk2pk(void *vk)
{
	Ekey *k, *pk;

	k = vk;
	pk = mallocz(sizeof(*pk), 1);
	if(pk == nil)
		return nil;
	pk->hybrid = k->hybrid;
	memmove(pk->edpub, k->edpub, sizeof pk->edpub);
	memmove(pk->mlpub, k->mlpub, sizeof pk->mlpub);
	return pk;
}

static void*
gen(int hybrid)
{
	Ekey *k;

	k = mallocz(sizeof(*k), 1);
	if(k == nil)
		return nil;
	k->secret = 1;
	k->hybrid = hybrid;
	genrandom(k->edseed, sizeof k->edseed);
	ed25519pub(k->edpub, k->edseed);
	if(hybrid){
		genrandom(k->mlseed, sizeof k->mlseed);
		mldsa65pub(k->mlpub, k->mlseed);
	}
	return k;
}

static void*	ed_gen(int len) { USED(len); return gen(0); }
static void*	hy_gen(int len) { USED(len); return gen(1); }

static void*
ed_genfrompk(void *pk)
{
	return gen(((Ekey*)pk)->hybrid);
}

/* Sigprefix, a zero, the digest */
static int
sigtext(uchar *m, uchar *digest, int n)
{
	if(n < 0 || n > SHA512dlen)
		return -1;
	memmove(m, Sigprefix, sizeof Sigprefix);
	memmove(m+sizeof Sigprefix, digest, n);
	return sizeof Sigprefix + n;
}

static void*
ed_signb(uchar *digest, int n, void *vk)
{
	Ekey *k;
	Esig *sig;
	uchar m[sizeof Sigprefix + SHA512dlen];

	k = vk;
	n = sigtext(m, digest, n);
	if(n < 0 || !k->secret)
		return nil;
	sig = mallocz(sizeof(*sig), 1);
	if(sig == nil)
		return nil;
	ed25519sign(sig->ed, k->edseed, m, n);
	if(k->hybrid && mldsa65sign(sig->ml, k->mlseed, m, n, nil, 0) < 0){
		free(sig);
		return nil;
	}
	return sig;
}

static int
ed_verifyb(uchar *digest, int n, void *vsig, void *vk)
{
	Ekey *k;
	Esig *sig;
	int ok;
	uchar m[sizeof Sigprefix + SHA512dlen];

	k = vk;
	sig = vsig;
	n = sigtext(m, digest, n);
	if(n < 0)
		return 0;
	/* both halves are always checked */
	ok = ed25519verify(k->edpub, m, n, sig->ed);
	if(k->hybrid)
		ok &= mldsa65verify(k->mlpub, m, n, nil, 0, sig->ml);
	return ok;
}

/* for signm and verifym, which hand over a big integer */
static void*
ed_sign(mpint *b, void *vk)
{
	uchar buf[SHA512dlen];
	int n;

	if(mpsignif(b) > 8*sizeof buf)
		return nil;
	n = mptobe(b, buf, sizeof buf, nil);
	if(n < 0)
		return nil;
	return ed_signb(buf, n, vk);
}

static int
ed_verify(mpint *b, void *vsig, void *vk)
{
	uchar buf[SHA512dlen];
	int n;

	if(mpsignif(b) > 8*sizeof buf)
		return 0;
	n = mptobe(b, buf, sizeof buf, nil);
	if(n < 0)
		return 0;
	return ed_verifyb(buf, n, vsig, vk);
}

static void
ed_freekey(void *a)
{
	if(a != nil)
		memset(a, 0, sizeof(Ekey));
	free(a);
}

static void
ed_freesig(void *a)
{
	free(a);
}

static SigAlgVec*
mkvec(char *name, int hybrid)
{
	SigAlgVec *vec;

	vec = mallocz(sizeof(SigAlgVec), 1);
	if(vec == nil)
		return nil;

	vec->name = name;

	vec->pkattr = hybrid? hpkattr: pkattr;
	vec->skattr = hybrid? hskattr: skattr;
	vec->sigattr = hybrid? hsigattr: sigattr;

	vec->str2sk = hybrid? hy_str2sk: ed_str2sk;
	vec->str2pk = hybrid? hy_str2pk: ed_str2pk;
	vec->str2sig = hybrid? hy_str2sig: ed_str2sig;

	vec->sk2str = ed_sk2str;
	vec->pk2str = ed_pk2str;
	vec->sig2str = hybrid? hy_sig2str: ed_sig2str;

	vec->sk2pk = ed_sk2pk;

	vec->gensk = hybrid? hy_gen: ed_gen;
	vec->genskfrompk = ed_genfrompk;
	vec->sign = ed_sign;
	vec->verify = ed_verify;
	vec->signb = ed_signb;
	vec->verifyb = ed_verifyb;

	vec->skfree = ed_freekey;
	vec->pkfree = ed_freekey;
	vec->sigfree = ed_freesig;

	return vec;
}

SigAlgVec*
ed25519init(void)
{
	return mkvec("ed25519", 0);
}

SigAlgVec*
ed25519mldsa65init(void)
{
	return mkvec("ed25519mldsa65", 1);
}
