#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

#include	"interp.h"
#include	<isa.h>
#include	"runt.h"
#include	"mp.h"
#include	"libsec.h"
#include "../../libkeyring/keys.h"

/*
 * experimental version of signed modules
 */

enum
{
	Qdir,
	Qkey,
	Qctl,

	Maxkey = 2048
};

static Dirtab signdir[] =
{
	".",		{Qdir, 0, QTDIR},	0,	DMDIR|0555,
	"signerkey",	{Qkey},	0,			0644,
	"signerctl",	{Qctl},	0,			0600,
};

typedef struct Get Get;
struct Get {
	uchar*	p;
	uchar*	ep;
};

#define	G32(b)	((b[0]<<24)|(b[1]<<16)|(b[2]<<8)|b[3])

static	int	vc(Get*);
static	int	vs(void*, int, Get*, int);
static Signerkey* findsignerkey(Skeyset*, char*, int, char*);
extern vlong		osusectime(void);

int
verifysigner(uchar *sign, int len, uchar *data, ulong ndata)
{
	Get sig;
	int alg;
	ulong issued, expires, now;
	int footprint, r, n;
	uchar buf[128], digest[SHA1dlen];
	DigestState *ds;
	volatile struct {BigInt b;} b;
	volatile struct {BigInt s;} s;
	SigAlgVec *sa;
	Signerkey *key;
	Skeyset *sigs;

	/* alg[1] issued[4] expires[4] footprint[2] signer[n] sig[m] */
	sigs = up->env->sigs;
	if(sigs == nil)
		return 1;	/* not enforcing signed modules */
	sig.p = sign;
	sig.ep = sign+len;
	alg = vc(&sig);
	if(alg != 2)
		return 0;	/* we do only SHA1/RSA */
	sa = findsigalg("rsa");
	if(sa == nil)
		return 0;
	if(vs(buf, sizeof(buf), &sig, 4) < 0)
		return 0;
	now = osusectime()/1000000;
	issued = G32(buf);
	if(vs(buf, sizeof(buf), &sig, 4) < 0)
		return 0;
	if(issued != 0 && now < issued)
		return 0;
	expires = G32(buf);
	if(expires != 0 && now >= expires)
		return 0;
	footprint = vc(&sig) << 8;
	footprint |= vc(&sig);
	if(footprint < 0)
		return 0;
	r = 0;
	b.b = nil;
	s.s = nil;
	qlock(sigs);
	if(waserror())
		goto out;
	if((n = vs(buf, sizeof(buf)-NUMSIZE-1, &sig, -1)) < 0)	/* owner */
		goto out;
	buf[n] = 0;
	key = findsignerkey(sigs, sa->name, footprint, (char*)buf);
	if(key == nil)
		goto out;
	n += snprint((char*)buf+n, NUMSIZE, " %lud", expires);
	ds = sha1(buf, n, nil, nil);
	sha1(data, ndata, digest, ds);
	b.b = betomp(digest, SHA1dlen, nil);
	if(b.b == nil)
		goto out;
	s.s = betomp(sig.p, sig.ep-sig.p, nil);
	if(s.s == nil)
		goto out;
	r = (*sa->verify)(b.b, s.s, key->pk);
out:
	qunlock(sigs);
	if(b.b != nil)
		mpfree(b.b);
	if(s.s != nil)
		mpfree(s.s);
	return r;
}

int
mustbesigned(char *path, uchar*, ulong, Dir *dir)
{
	USED(path);
if(0)print("load %s: %d %C\n", path, up->env->sigs!=nil, dir==nil?'?':dir->type);
	/* allow only signed modules and those in #/; already loaded modules are reloaded from cache */
	return up->env->sigs != nil && (dir == nil || dir->type != '/');
}

static int
vc(Get *g)
{
	return g->p < g->ep? *g->p++: -1;
}

static int
vs(void *s, int lim, Get *g, int n)
{
	int nr;

	if(n < 0){
		if(g->p >= g->ep)
			return -1;
		n = *g->p++;
		lim--;
	}
	if(n > lim)
		return -1;
	nr = g->ep - g->p;
	if(n > nr)
		return -1;
	if(s != nil)
		memmove(s, g->p, n);
	g->p += n;
	return n;
}

static char*
cstring(char *str, char **strp)
{
	char *p, *s;
	int n;

	p = strchr(str, '\n');
	if(p == 0)
		p = str + strlen(str);
	n = p - str;
	s = malloc(n+1);
	if(s == nil)
		return nil;
	memmove(s, str, n);
	s[n] = 0;

	if(strp){
		if(*p)
			p++;
		*strp = p;
	}

	return s;
}

static SigAlgVec*
cstrtoalg(char *str, char **strp)
{
	int n;
	char *p, name[KNAMELEN];

	p = strchr(str, '\n');
	if(p == 0){
		p = str + strlen(str);
		if(strp)
			*strp = p;
	} else {
		if(strp)
			*strp = p+1;
	}

	n = p - str;
	if(n >= sizeof(name))
		return nil;
	strncpy(name, str, n);
	name[n] = 0;
	return findsigalg(name);
}

static Signerkey*
strtopk(char *buf)
{
	SigAlgVec *sa;
	char *p;
	Signerkey *key;

	key = malloc(sizeof(*key));
	if(key == nil)
		return nil;
	key->ref = 1;
	sa = cstrtoalg(buf, &p);
	if(sa == nil){
		free(key);
		return nil;
	}
	key->alg = sa;
	key->pkfree = sa->pkfree;
	key->owner = cstring(p, &p);
	if(key->owner == nil){
		free(key);
		return nil;
	}
	key->pk = (*sa->str2pk)(p, &p);
	if(key->pk == nil){
		free(key->owner);
		free(key);
		return nil;
	}
	return key;
}

static Signerkey*
findsignerkey(Skeyset *sigs, char *alg, int footprint, char *owner)
{
	int i;
	Signerkey *key;

	for(i=0; i<sigs->nkey; i++){
		key = sigs->keys[i];
		if(key->footprint == footprint &&
		   strcmp(alg, ((SigAlgVec*)key->alg)->name) == 0 &&
		   strcmp(key->owner, owner) == 0)
			return key;
	}
	return nil;
}

static Chan*
signattach(char *spec)
{
	return devattach(L'Σ', spec);
}

static Walkqid*
signwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, signdir, nelem(signdir), devgen);
}

static int
signstat(Chan *c, uchar *db, int n)
{
	return devstat(c, db, n, signdir, nelem(signdir), devgen);
}

static Chan*
signopen(Chan *c, int omode)
{
	if(c->qid.type & QTDIR) {
		if(omode != OREAD)
			error(Eisdir);
		c->mode = openmode(omode);
		c->flag |= COPEN;
		c->offset = 0;
		return c;
	}

	switch((ulong)c->qid.path){
	case Qctl:
		if(!iseve())
			error(Eperm);
		break;

	case Qkey:
		if(omode != OREAD && !iseve())
			error(Eperm);
		break;
	}

	c->mode = openmode(omode);
	c->flag |= COPEN;
	c->offset = 0;
	return c;
}

static void
signclose(Chan *c)
{
	USED(c);
}

static long
signread(Chan *c, void *va, long n, vlong offset)
{
	char *buf, *p;
	SigAlgVec *sa;
	Skeyset *sigs;
	Signerkey *key;
	int i;

	if(c->qid.type & QTDIR)
		return devdirread(c, va, n, signdir, nelem(signdir), devgen);
	sigs = up->env->sigs;
	if(sigs == nil)
		return 0;
	switch((ulong)c->qid.path){
	case Qkey:
		buf = smalloc(Maxkey);
		if(waserror()){
			free(buf);
			nexterror();
		}
		qlock(sigs);
		if(waserror()){
			qunlock(sigs);
			nexterror();
		}
		p = buf;
		for(i=0; i<sigs->nkey; i++){
			key = sigs->keys[i];
			sa = key->alg;
			p = seprint(p, buf+Maxkey, "owner=%s alg=%s footprint=%ud expires=%lud\n",
				key->owner, sa->name, key->footprint, key->expires);
		}
		poperror();
		qunlock(sigs);
		n = readstr(offset, va, n, buf);
		poperror();
		free(buf);
		return n;

	case Qctl:
		return readnum(offset, va, n, sigs->nkey, NUMSIZE);
	}
	return 0;
}

static long
signwrite(Chan *c, void *va, long n, vlong offset)
{
	char *buf;
	Skeyset *sigs;
	Signerkey *okey, *key;
	int i;

	if(c->qid.type & QTDIR)
		error(Eisdir);
	USED(offset);
	switch((ulong)c->qid.path){
	case Qkey:
		if(n >= Maxkey)
			error(Etoobig);
		buf = smalloc(Maxkey);
		if(waserror()){
			free(buf);
			nexterror();
		}
		memmove(buf, va, n);
		buf[n] = 0;

		key = strtopk(buf);
		if(key == nil)
			error("bad key syntax");
		poperror();
		free(buf);

		if(waserror()){
			freeskey(key);
			nexterror();
		}
		sigs = up->env->sigs;
		if(sigs == nil){
			sigs = malloc(sizeof(*sigs));
			if(sigs == nil)
				error(Enomem);
			sigs->ref = 1;
			up->env->sigs = sigs;
		}
		qlock(sigs);
		if(waserror()){
			qunlock(sigs);
			nexterror();
		}
		for(i=0; i<sigs->nkey; i++){
			okey = sigs->keys[i];
			if(strcmp(okey->owner, key->owner) == 0){
				/* replace existing key */
				sigs->keys[i] = key;
				freeskey(okey);
				break;
			}
		}
		if(i >= sigs->nkey){
			if(sigs->nkey >= nelem(sigs->keys))
				error("too many keys");
			sigs->keys[sigs->nkey++] = key;
		}
		poperror();
		qunlock(sigs);
		poperror();	/* key */

		return n;
	case Qctl:
		error(Ebadctl);
		break;
	}
	return 0;
}

Dev signdevtab = {
	L'Σ',
	"sign",

	devreset,
	devinit,
	devshutdown,
	signattach,
	signwalk,
	signstat,
	signopen,
	devcreate,
	signclose,
	signread,
	devbread,
	signwrite,
	devbwrite,
	devremove,
	devwstat
};
