#include <lib9.h>
#include <kernel.h>
#include <isa.h>
#include "interp.h"
#include "../libinterp/runt.h"
#include "mp.h"
#include "libsec.h"
#include "keys.h"

static char*	pkattr[] = { "p", "alpha", "key", nil };
static char*	skattr[] = { "p", "alpha", "key", "!secret", nil };
static char*	sigattr[] = { "r", "s", nil };

static void*
eg_str2sk(char *str, char **strp)
{
	EGpriv *eg;
	char *p;

	eg = egprivalloc();
	eg->pub.p = base64tobig(str, &p);
	eg->pub.alpha = base64tobig(p, &p);
	eg->pub.key = base64tobig(p, &p);
	eg->secret = base64tobig(p, &p);
	if(strp)
		*strp = p;
	return eg;
}

static void*
eg_str2pk(char *str, char **strp)
{
	EGpub *eg;
	char *p;

	eg = egpuballoc();
	eg->p = base64tobig(str, &p);
	eg->alpha = base64tobig(p, &p);
	eg->key = base64tobig(p, &p);
	if(strp)
		*strp = p;
	return eg;
}

static void*
eg_str2sig(char *str, char **strp)
{
	EGsig *eg;
	char *p;

	eg = egsigalloc();
	eg->r = base64tobig(str, &p);
	eg->s = base64tobig(p, &p);
	if(strp)
		*strp = p;
	return eg;
}

static int
eg_sk2str(void *veg, char *buf, int len)
{
	EGpriv *eg;
	char *cp, *ep;

	eg = (EGpriv*)veg;
	ep = buf + len - 1;
	cp = buf;

	cp += snprint(cp, ep - cp, "%U\n", eg->pub.p);
	cp += snprint(cp, ep - cp, "%U\n", eg->pub.alpha);
	cp += snprint(cp, ep - cp, "%U\n", eg->pub.key);
	cp += snprint(cp, ep - cp, "%U\n", eg->secret);
	*cp = 0;

	return cp - buf;
}

static int
eg_pk2str(void *veg, char *buf, int len)
{
	EGpub *eg;
	char *cp, *ep;

	eg = (EGpub*)veg;
	ep = buf + len - 1;
	cp = buf;

	cp += snprint(cp, ep - cp, "%U\n", eg->p);
	cp += snprint(cp, ep - cp, "%U\n", eg->alpha);
	cp += snprint(cp, ep - cp, "%U\n", eg->key);
	*cp = 0;

	return cp - buf;
}

static int
eg_sig2str(void *veg, char *buf, int len)
{
	EGsig *eg;
	char *cp, *ep;

	eg = veg;
	ep = buf + len - 1;
	cp = buf;

	cp += snprint(cp, ep - cp, "%U\n", eg->r);
	cp += snprint(cp, ep - cp, "%U\n", eg->s);
	*cp = 0;

	return cp - buf;
}

static void*
eg_sk2pk(void *vs)
{
	return egprivtopub((EGpriv*)vs);
}

/* generate an el gamal secret key with new params */
static void*
eg_gen(int len)
{
	return eggen(len, 0);
}

/* generate an el gamal secret key with same params as a public key */
static void*
eg_genfrompk(void *vpub)
{
	EGpub *pub;
	EGpriv *priv;
	int nlen;

	pub = vpub;
	priv = egprivalloc();
	priv->pub.p = mpcopy(pub->p);
	priv->pub.alpha = mpcopy(pub->alpha);
	nlen = mpsignif(pub->p);
	pub = &priv->pub;
	pub->key = mpnew(0);
	priv->secret = mpnew(0);
	mprand(nlen-1, genrandom, priv->secret);
	mpexp(pub->alpha, priv->secret, pub->p, pub->key);
	return priv;
}

static void*
eg_sign(BigInt mp, void *key)
{
	return egsign((EGpriv*)key, mp);
}

static int
eg_verify(BigInt mp, void *sig, void *key)
{
	return egverify((EGpub*)key, (EGsig*)sig, mp) == 0;
}

static void
eg_freepub(void *a)
{
	egpubfree((EGpub*)a);
}

static void
eg_freepriv(void *a)
{
	egprivfree((EGpriv*)a);
}

static void
eg_freesig(void *a)
{
	egsigfree((EGsig*)a);
}

SigAlgVec*
elgamalinit(void)
{
	SigAlgVec *vec;

	vec = malloc(sizeof(SigAlgVec));
	if(vec == nil)
		return nil;

	vec->name = "elgamal";

	vec->pkattr = pkattr;
	vec->skattr = skattr;
	vec->sigattr = sigattr;

	vec->str2sk = eg_str2sk;
	vec->str2pk = eg_str2pk;
	vec->str2sig = eg_str2sig;

	vec->sk2str = eg_sk2str;
	vec->pk2str = eg_pk2str;
	vec->sig2str = eg_sig2str;

	vec->sk2pk = eg_sk2pk;

	vec->gensk = eg_gen;
	vec->genskfrompk = eg_genfrompk;
	vec->sign = eg_sign;
	vec->verify = eg_verify;

	vec->skfree = eg_freepriv;
	vec->pkfree = eg_freepub;
	vec->sigfree = eg_freesig;

	return vec;
}
