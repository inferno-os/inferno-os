#include <lib9.h>
#include <kernel.h>
#include <isa.h>
#include "interp.h"
#include "../libinterp/runt.h"
#include "mp.h"
#include "libsec.h"
#include "keys.h"

static char*	pkattr[] = { "n", "ek", nil };
static char*	skattr[] = { "n", "ek", "!dk", "!p", "!q", "!kp", "!kq", "!c2", nil };
static char*	sigattr[] = { "val", nil };

static void*
rsa_str2sk(char *str, char **strp)
{
	RSApriv *rsa;
	char *p;

	rsa = rsaprivalloc();
	rsa->pub.n = base64tobig(str, &p);
	rsa->pub.ek = base64tobig(p, &p);
	rsa->dk = base64tobig(p, &p);
	rsa->p = base64tobig(p, &p);
	rsa->q = base64tobig(p, &p);
	rsa->kp = base64tobig(p, &p);
	rsa->kq = base64tobig(p, &p);
	rsa->c2 = base64tobig(p, &p);
	if(strp)
		*strp = p;

	return rsa;
}

static void*
rsa_str2pk(char *str, char **strp)
{
	RSApub *rsa;
	char *p;

	rsa = rsapuballoc();
	rsa->n = base64tobig(str, &p);
	rsa->ek = base64tobig(p, &p);
	if(strp)
		*strp = p;

	return rsa;
}

static void*
rsa_str2sig(char *str, char **strp)
{
	mpint *rsa;
	char *p;

	rsa = base64tobig(str, &p);
	if(strp)
		*strp = p;
	return rsa;
}

static int
rsa_sk2str(void *vrsa, char *buf, int len)
{
	RSApriv *rsa;
	char *cp, *ep;

	rsa = vrsa;
	ep = buf + len - 1;
	cp = buf;

	cp += snprint(cp, ep - cp, "%U\n", rsa->pub.n);
	cp += snprint(cp, ep - cp, "%U\n", rsa->pub.ek);
	cp += snprint(cp, ep - cp, "%U\n", rsa->dk);
	cp += snprint(cp, ep - cp, "%U\n", rsa->p);
	cp += snprint(cp, ep - cp, "%U\n", rsa->q);
	cp += snprint(cp, ep - cp, "%U\n", rsa->kp);
	cp += snprint(cp, ep - cp, "%U\n", rsa->kq);
	cp += snprint(cp, ep - cp, "%U\n", rsa->c2);
	*cp = 0;

	return cp - buf;
}

static int
rsa_pk2str(void *vrsa, char *buf, int len)
{
	RSApub *rsa;
	char *cp, *ep;

	rsa = vrsa;
	ep = buf + len - 1;
	cp = buf;
	cp += snprint(cp, ep - cp, "%U\n", rsa->n);
	cp += snprint(cp, ep - cp, "%U\n", rsa->ek);
	*cp = 0;

	return cp - buf;
}

static int
rsa_sig2str(void *vrsa, char *buf, int len)
{
	mpint *rsa;
	char *cp, *ep;

	rsa = vrsa;
	ep = buf + len - 1;
	cp = buf;

	cp += snprint(cp, ep - cp, "%U\n", rsa);
	*cp = 0;

	return cp - buf;
}

static void*
rsa_sk2pk(void *vs)
{
	return rsaprivtopub((RSApriv*)vs);
}

/* generate an rsa secret key */
static void*
rsa_gen(int len)
{
	RSApriv *key;

	for(;;){
		key = rsagen(len, 6, 0);
		if(mpsignif(key->pub.n) == len)
			return key;
		rsaprivfree(key);
	}
}

/* generate an rsa secret key with same params as a public key */
static void*
rsa_genfrompk(void *vpub)
{
	RSApub *pub;

	pub = vpub;
	return rsagen(mpsignif(pub->n), mpsignif(pub->ek), 0);
}

static void*
rsa_sign(mpint* m, void *key)
{
	return rsadecrypt((RSApriv*)key, m, nil);
}

static int
rsa_verify(mpint* m, void *sig, void *key)
{
	mpint *t;
	int r;

	t = rsaencrypt((RSApub*)key, (mpint*)sig, nil);
	r = mpcmp(t, m) == 0;
	mpfree(t);
	return r;
}

static void
rsa_freepriv(void *a)
{
	rsaprivfree((RSApriv*)a);
}

static void
rsa_freepub(void *a)
{
	rsapubfree((RSApub*)a);
}

static void
rsa_freesig(void *a)
{
	mpfree(a);
}

SigAlgVec*
rsainit(void)
{
	SigAlgVec *vec;

	vec = malloc(sizeof(SigAlgVec));
	if(vec == nil)
		return nil;

	vec->name = "rsa";

	vec->pkattr = pkattr;
	vec->skattr = skattr;
	vec->sigattr = sigattr;

	vec->str2sk = rsa_str2sk;
	vec->str2pk = rsa_str2pk;
	vec->str2sig = rsa_str2sig;

	vec->sk2str = rsa_sk2str;
	vec->pk2str = rsa_pk2str;
	vec->sig2str = rsa_sig2str;

	vec->sk2pk = rsa_sk2pk;

	vec->gensk = rsa_gen;
	vec->genskfrompk = rsa_genfrompk;
	vec->sign = rsa_sign;
	vec->verify = rsa_verify;

	vec->skfree = rsa_freepriv;
	vec->pkfree = rsa_freepub;
	vec->sigfree = rsa_freesig;

	return vec;
}
