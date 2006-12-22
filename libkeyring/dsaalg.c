#include <lib9.h>
#include <kernel.h>
#include <isa.h>
#include "interp.h"
#include "../libinterp/runt.h"
#include "mp.h"
#include "libsec.h"
#include "keys.h"

static char*	pkattr[] = { "p", "q", "alpha", "key", nil };
static char*	skattr[] = { "p", "q", "alpha", "key", "!secret", nil };
static char*	sigattr[] = { "r", "s", nil };

static void*
dsa_str2sk(char *str, char **strp)
{
	DSApriv *dsa;
	char *p;

	dsa = dsaprivalloc();
	dsa->pub.p = base64tobig(str, &p);
	dsa->pub.q = base64tobig(str, &p);
	dsa->pub.alpha = base64tobig(p, &p);
	dsa->pub.key = base64tobig(p, &p);
	dsa->secret = base64tobig(p, &p);
	if(strp)
		*strp = p;
	return dsa;
}

static void*
dsa_str2pk(char *str, char **strp)
{
	DSApub *dsa;
	char *p;

	dsa = dsapuballoc();
	dsa->p = base64tobig(str, &p);
	dsa->q = base64tobig(str, &p);
	dsa->alpha = base64tobig(p, &p);
	dsa->key = base64tobig(p, &p);
	if(strp)
		*strp = p;
	return dsa;
}

static void*
dsa_str2sig(char *str, char **strp)
{
	DSAsig *dsa;
	char *p;

	dsa = dsasigalloc();
	dsa->r = base64tobig(str, &p);
	dsa->s = base64tobig(p, &p);
	if(strp)
		*strp = p;
	return dsa;
}

static int
dsa_sk2str(void *veg, char *buf, int len)
{
	DSApriv *dsa;
	char *cp, *ep;

	dsa = veg;
	ep = buf + len - 1;
	cp = buf;

	cp += snprint(cp, ep - cp, "%U\n", dsa->pub.p);
	cp += snprint(cp, ep - cp, "%U\n", dsa->pub.q);
	cp += snprint(cp, ep - cp, "%U\n", dsa->pub.alpha);
	cp += snprint(cp, ep - cp, "%U\n", dsa->pub.key);
	cp += snprint(cp, ep - cp, "%U\n", dsa->secret);
	*cp = 0;

	return cp - buf;
}

static int
dsa_pk2str(void *veg, char *buf, int len)
{
	DSApub *dsa;
	char *cp, *ep;

	dsa = veg;
	ep = buf + len - 1;
	cp = buf;

	cp += snprint(cp, ep - cp, "%U\n", dsa->p);
	cp += snprint(cp, ep - cp, "%U\n", dsa->q);
	cp += snprint(cp, ep - cp, "%U\n", dsa->alpha);
	cp += snprint(cp, ep - cp, "%U\n", dsa->key);
	*cp = 0;

	return cp - buf;
}

static int
dsa_sig2str(void *veg, char *buf, int len)
{
	DSAsig *dsa;
	char *cp, *ep;

	dsa = veg;
	ep = buf + len - 1;
	cp = buf;

	cp += snprint(cp, ep - cp, "%U\n", dsa->r);
	cp += snprint(cp, ep - cp, "%U\n", dsa->s);
	*cp = 0;

	return cp - buf;
}

static void*
dsa_sk2pk(void *vs)
{
	return dsaprivtopub((DSApriv*)vs);
}

/* generate a dsa secret key with new params */
static void*
dsa_gen(int len)
{
	USED(len);
	return dsagen(nil);
}

/* generate a dsa secret key with same params as a public key */
static void*
dsa_genfrompk(void *vpub)
{
	return dsagen((DSApub*)vpub);
}

static void
dsa_freepub(void *a)
{
	dsapubfree((DSApub*)a);
}

static void
dsa_freepriv(void *a)
{
	dsaprivfree((DSApriv*)a);
}

static void
dsa_freesig(void *a)
{
	dsasigfree((DSAsig*)a);
}

static void*
dsa_sign(BigInt md, void *key)
{
	return dsasign((DSApriv*)key, md);
}

static int
dsa_verify(BigInt md, void *sig, void *key)
{
	return dsaverify((DSApub*)key, (DSAsig*)sig, md) == 0;
}

SigAlgVec*
dsainit(void)
{
	SigAlgVec *vec;

	vec = malloc(sizeof(SigAlgVec));
	if(vec == nil)
		return nil;

	vec->name = "dsa";

	vec->pkattr = pkattr;
	vec->skattr = skattr;
	vec->sigattr = sigattr;

	vec->str2sk = dsa_str2sk;
	vec->str2pk = dsa_str2pk;
	vec->str2sig = dsa_str2sig;

	vec->sk2str = dsa_sk2str;
	vec->pk2str = dsa_pk2str;
	vec->sig2str = dsa_sig2str;

	vec->sk2pk = dsa_sk2pk;

	vec->gensk = dsa_gen;
	vec->genskfrompk = dsa_genfrompk;
	vec->sign = dsa_sign;
	vec->verify = dsa_verify;

	vec->skfree = dsa_freepriv;
	vec->pkfree = dsa_freepub;
	vec->sigfree = dsa_freesig;

	return vec;
}
