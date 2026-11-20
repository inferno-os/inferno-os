#include "lib9.h"
#include "kernel.h"
#include <isa.h>
#include "interp.h"
#include "runt.h"
#include "cryptmod.h"
#include <mp.h>
#include <libsec.h>
#include "pool.h"
#include "raise.h"
#include "ipint.h"

#define	MPX(x)	checkIPint((void*)(x))

static Type*	TDigestState;
static Type*	TAESstate;
static Type*	TDESstate;
static Type*	TIDEAstate;
static Type*	TBFstate;
static Type*	TRC4state;

static Type*	TSKdsa;
static Type*	TPKdsa;
static Type*	TPKsigdsa;
static Type*	TSKeg;
static Type*	TPKeg;
static Type*	TPKsigeg;
static Type*	TSKrsa;
static Type*	TPKrsa;
static Type*	TPKsigrsa;

static uchar DigestStatemap[] = Crypt_DigestState_map;
static uchar AESstatemap[] = Crypt_AESstate_map;
static uchar DESstatemap[] = Crypt_DESstate_map;
static uchar IDEAstatemap[] = Crypt_IDEAstate_map;
static uchar BFstatemap[] = Crypt_BFstate_map;
static uchar RC4statemap[] = Crypt_RC4state_map;

static uchar DSAskmap[] = Crypt_SK_DSA_map;
static uchar DSApkmap[] = Crypt_PK_DSA_map;
static uchar DSAsigmap[] = Crypt_PKsig_DSA_map;
static uchar EGskmap[] = Crypt_SK_Elgamal_map;
static uchar EGpkmap[] = Crypt_PK_Elgamal_map;
static uchar EGsigmap[] = Crypt_PKsig_Elgamal_map;
static uchar RSAskmap[] = Crypt_SK_RSA_map;
static uchar RSApkmap[] = Crypt_PK_RSA_map;
static uchar RSAsigmap[] = Crypt_PKsig_RSA_map;

static char exBadBsize[]	= "data not multiple of block size";
static char exBadKey[]	= "bad encryption key";
static char exBadDigest[]	= "bad digest value";
static char exBadIvec[]	= "bad ivec";
static char exBadState[] = "bad encryption state";

/*
 * these structures reveal the C state of Limbo adts in crypt.m
 */

typedef struct XDigestState XDigestState;
typedef struct XAESstate XAESstate;
typedef struct XDESstate XDESstate;
typedef struct XIDEAstate XIDEAstate;
typedef struct XBFstate XBFstate;
typedef struct XRC4state XRC4state;

/* digest state */
struct XDigestState
{
	Crypt_DigestState	x;
	DigestState	state;
};

/* AES state */
struct XAESstate
{
	Crypt_AESstate	x;
	AESstate	state;
};

/* DES state */
struct XDESstate
{
	Crypt_DESstate	x;
	DESstate	state;
};

/* IDEA state */
struct XIDEAstate
{
	Crypt_IDEAstate	x;
	IDEAstate	state;
};

/* BF state */
struct XBFstate
{
	Crypt_BFstate	x;
	BFstate	state;
};

/* RC4 state */
struct XRC4state
{
	Crypt_RC4state	x;
	RC4state	state;
};

static Crypt_PK*
newPK(Type *t, int pick)
{
	Heap *h;
	Crypt_PK *sk;

	h = heap(t);
	sk = H2D(Crypt_PK*, h);
	sk->pick = pick;
	return sk;
}

static Crypt_SK*
newSK(Crypt_SK** ret, Type *t, int pick)
{
	Heap *h;
	Crypt_SK *sk;

	h = heap(t);
	sk = H2D(Crypt_SK*, h);
	sk->pick = pick;
	if(ret != nil)
		*ret = sk;
	switch(pick){
	case Crypt_PK_RSA:
		sk->u.RSA.pk = newPK(TPKrsa, Crypt_PK_RSA);
		break;
	case Crypt_PK_Elgamal:
		sk->u.Elgamal.pk = newPK(TPKeg, Crypt_PK_Elgamal);
		break;
	case Crypt_PK_DSA:
		sk->u.DSA.pk = newPK(TPKdsa, Crypt_PK_DSA);
		break;
	default:
		error(exType);
	}
	return sk;
}

static Crypt_PKsig*
newPKsig(Type *t, int pick)
{
	Heap *h;
	Crypt_PKsig *s;

	h = heap(t);
	s = H2D(Crypt_PKsig*, h);
	s->pick = pick;
	return s;
}

static IPints_IPint*
ipcopymp(mpint* b)
{
	if(b == nil)
		return H;
	return newIPint(mpcopy(b));
}

/*
 *  digests
 */
void
DigestState_copy(void *fp)
{
	F_DigestState_copy *f;
	Heap *h;
	XDigestState *ds, *ods;
	void *r;

	f = fp;
	r = *f->ret;
	*f->ret = H;
	destroy(r);

	if(f->d != H){
		ods = checktype(f->d, TDigestState, "DigestState", 0);
		h = heap(TDigestState);
		ds = H2D(XDigestState*, h); 	
		memmove(&ds->state, &ods->state, sizeof(ds->state)); 
		*f->ret = (Crypt_DigestState*)ds;
	}
}

static Crypt_DigestState*
crypt_digest_x(Array *buf, int n, Array *digest, int dlen, Crypt_DigestState *state, DigestState* (*fn)(uchar*, ulong, uchar*, DigestState*))
{
	Heap *h;
	XDigestState *ds;
	uchar *cbuf, *cdigest;

	if(buf != H){
		if(n > buf->len)
			n = buf->len;
		cbuf = buf->data;
	}else{
		if(n != 0)
			error(exInval);
		cbuf = nil;
	}

	if(digest != H){
		if(digest->len < dlen)
			error(exBadDigest);
		cdigest = digest->data;
	} else
		cdigest = nil;

	if(state == H){
		h = heap(TDigestState);
		ds = H2D(XDigestState*, h);
		memset(&ds->state, 0, sizeof(ds->state));
	} else
		ds = checktype(state, TDigestState, "DigestState", 1);

	(*fn)(cbuf, n, cdigest, &ds->state);

	return (Crypt_DigestState*)ds;
}

void
Crypt_sha1(void *fp)
{
	F_Crypt_sha1 *f;
	void *r;

	f = fp;
	r = *f->ret;
	*f->ret = H;
	destroy(r);

	*f->ret = crypt_digest_x(f->buf, f->n, f->digest, SHA1dlen, f->state, sha1);
}

void
Crypt_sha224(void *fp)
{
	F_Crypt_sha224 *f;
	void *r;

	f = fp;
	r = *f->ret;
	*f->ret = H;
	destroy(r);

	*f->ret = crypt_digest_x(f->buf, f->n, f->digest, SHA224dlen, f->state, sha224);
}

void
Crypt_sha256(void *fp)
{
	F_Crypt_sha256 *f;
	void *r;

	f = fp;
	r = *f->ret;
	*f->ret = H;
	destroy(r);

	*f->ret = crypt_digest_x(f->buf, f->n, f->digest, SHA256dlen, f->state, sha256);
}

void
Crypt_sha384(void *fp)
{
	F_Crypt_sha384 *f;
	void *r;

	f = fp;
	r = *f->ret;
	*f->ret = H;
	destroy(r);

	*f->ret = crypt_digest_x(f->buf, f->n, f->digest, SHA384dlen, f->state, sha384);
}

void
Crypt_sha512(void *fp)
{
	F_Crypt_sha512 *f;
	void *r;

	f = fp;
	r = *f->ret;
	*f->ret = H;
	destroy(r);

	*f->ret = crypt_digest_x(f->buf, f->n, f->digest, SHA512dlen, f->state, sha512);
}

void
Crypt_md5(void *fp)
{
	F_Crypt_md5 *f;
	void *r;

	f = fp;
	r = *f->ret;
	*f->ret = H;
	destroy(r);

	*f->ret = crypt_digest_x(f->buf, f->n, f->digest, MD5dlen, f->state, md5);
}

void
Crypt_md4(void *fp)
{
	F_Crypt_md4 *f;
	void *r;

	f = fp;
	r = *f->ret;
	*f->ret = H;
	destroy(r);

	*f->ret = crypt_digest_x(f->buf, f->n, f->digest, MD4dlen, f->state, md4);
}

static Crypt_DigestState*
crypt_hmac_x(Array *data, int n, Array *key, Array *digest, int dlen, Crypt_DigestState *state, DigestState* (*fn)(uchar*, ulong, uchar*, ulong, uchar*, DigestState*))
{
	Heap *h;
	XDigestState *ds;
	uchar *cdata, *cdigest;

	if(data != H){
		if(n > data->len)
			n = data->len;
		cdata = data->data;
	}else{
		if(n != 0)
			error(exInval);
		cdata = nil;
	}

	if(key == H || key->len > 64)
		error(exBadKey);

	if(digest != H){
		if(digest->len < dlen)
			error(exBadDigest);
		cdigest = digest->data;
	} else
		cdigest = nil;

	if(state == H){
		h = heap(TDigestState);
		ds = H2D(XDigestState*, h);
		memset(&ds->state, 0, sizeof(ds->state));
	} else
		ds = checktype(state, TDigestState, "DigestState", 1);

	(*fn)(cdata, n, key->data, key->len, cdigest, &ds->state);

	return (Crypt_DigestState*)ds;
}

void
Crypt_hmac_sha1(void *fp)
{
	F_Crypt_hmac_sha1 *f;
	void *r;

	f = fp;
	r = *f->ret;
	*f->ret = H;
	destroy(r);
	*f->ret = crypt_hmac_x(f->data, f->n, f->key, f->digest, SHA1dlen, f->state, hmac_sha1);
}

void
Crypt_hmac_md5(void *fp)
{
	F_Crypt_hmac_md5 *f;
	void *r;

	f = fp;
	r = *f->ret;
	*f->ret = H;
	destroy(r);
	*f->ret = crypt_hmac_x(f->data, f->n, f->key, f->digest, MD5dlen, f->state, hmac_md5);
}

void
Crypt_dhparams(void *fp)
{
	F_Crypt_dhparams *f;
	mpint *p, *alpha;
	void *v;

	f = fp;
	v = f->ret->t0;
	f->ret->t0 = H;
	destroy(v);
	v = f->ret->t1;
	f->ret->t1 = H;
	destroy(v);

	p = mpnew(0);
	alpha = mpnew(0);
	release();
	if(f->nbits == 1024)
		DSAprimes(alpha, p, nil);
	else
		gensafeprime(p, alpha, f->nbits, 0);
	acquire();
	f->ret->t0 = newIPint(alpha);
	f->ret->t1 = newIPint(p);
}

void
cryptmodinit(void)
{
	ipintsmodinit();	/* TIPint */

	TDigestState = dtype(freeheap, sizeof(XDigestState), DigestStatemap, sizeof(DigestStatemap));
	TAESstate = dtype(freeheap, sizeof(XAESstate), AESstatemap, sizeof(AESstatemap));
	TDESstate = dtype(freeheap, sizeof(XDESstate), DESstatemap, sizeof(DESstatemap));
	TIDEAstate = dtype(freeheap, sizeof(XIDEAstate), IDEAstatemap, sizeof(IDEAstatemap));
	TBFstate = dtype(freeheap, sizeof(XBFstate), BFstatemap, sizeof(BFstatemap));
	TRC4state = dtype(freeheap, sizeof(XRC4state), RC4statemap, sizeof(RC4statemap));

	TSKdsa = dtype(freeheap, Crypt_SK_DSA_size, DSAskmap, sizeof(DSAskmap));
	TPKdsa = dtype(freeheap, Crypt_PK_DSA_size, DSApkmap, sizeof(DSApkmap));
	TPKsigdsa = dtype(freeheap, Crypt_PKsig_DSA_size, DSAsigmap, sizeof(DSAsigmap));
	TSKeg = dtype(freeheap, Crypt_SK_Elgamal_size, EGskmap, sizeof(EGskmap));
	TPKeg = dtype(freeheap, Crypt_PK_Elgamal_size, EGpkmap, sizeof(EGpkmap));
	TPKsigeg = dtype(freeheap, Crypt_PKsig_Elgamal_size, EGsigmap, sizeof(EGsigmap));
	TSKrsa = dtype(freeheap, Crypt_SK_RSA_size, RSAskmap, sizeof(RSAskmap));
	TPKrsa = dtype(freeheap, Crypt_PK_RSA_size, RSApkmap, sizeof(RSApkmap));
	TPKsigrsa = dtype(freeheap, Crypt_PKsig_RSA_size, RSAsigmap, sizeof(RSAsigmap));

	builtinmod("$Crypt", Cryptmodtab, Cryptmodlen);
}

void
Crypt_dessetup(void *fp)
{
	F_Crypt_dessetup *f;
	Heap *h;
	XDESstate *ds;
	uchar *ivec;
	void *v;

	f = fp;
	v = *f->ret;
	*f->ret = H;
	destroy(v);

	if(f->key == H)
		error(exNilref);
	if(f->key->len < 8)
		error(exBadKey);
	if(f->ivec != H){
		if(f->ivec->len < 8)
			error(exBadIvec);
		ivec = f->ivec->data;
	}else
		ivec = nil;

	h = heap(TDESstate);
	ds = H2D(XDESstate*, h);
	setupDESstate(&ds->state, f->key->data, ivec);

	*f->ret = (Crypt_DESstate*)ds;
}

void
Crypt_desecb(void *fp)
{
	F_Crypt_desecb *f;
	XDESstate *ds;
	int i;
	uchar *p;

	f = fp;

	if(f->buf == H)
		return;
	if(f->n < 0 || f->n > f->buf->len)
		error(exBounds);
	if(f->n & 7)
		error(exBadBsize);

	ds = checktype(f->state, TDESstate, exBadState, 0);
	p = f->buf->data;

	for(i = 8; i <= f->n; i += 8, p += 8)
		block_cipher(ds->state.expanded, p, f->direction);
}

void
Crypt_descbc(void *fp)
{
	F_Crypt_descbc *f;
	XDESstate *ds;
	uchar *p, *ep, *ip, *p2, *eip;
	uchar tmp[8];

	f = fp;

	if(f->buf == H)
		return;
	if(f->n < 0 || f->n > f->buf->len)
		error(exBounds);
	if(f->n & 7)
		error(exBadBsize);

	ds = checktype(f->state, TDESstate, exBadState, 0);
	p = f->buf->data;

	if(f->direction == 0){
		for(ep = p + f->n; p < ep; p += 8){
			p2 = p;
			ip = ds->state.ivec;
			for(eip = ip+8; ip < eip; )
				*p2++ ^= *ip++;
			block_cipher(ds->state.expanded, p, 0);
			memmove(ds->state.ivec, p, 8);
		}
	} else {
		for(ep = p + f->n; p < ep; ){
			memmove(tmp, p, 8);
			block_cipher(ds->state.expanded, p, 1);
			p2 = tmp;
			ip = ds->state.ivec;
			for(eip = ip+8; ip < eip; ){
				*p++ ^= *ip;
				*ip++ = *p2++;
			}
		}
	}
}

void
Crypt_ideasetup(void *fp)
{
	F_Crypt_ideasetup *f;
	Heap *h;
	XIDEAstate *is;
	uchar *ivec;
	void *v;

	f = fp;
	v = *f->ret;
	*f->ret = H;
	destroy(v);

	if(f->key == H)
		error(exNilref);
	if(f->key->len < 16)
		error(exBadKey);
	if(f->ivec != H){
		if(f->ivec->len < 8)
			error(exBadIvec);
		ivec = f->ivec->data;
	}else
		ivec = nil;

	h = heap(TIDEAstate);
	is = H2D(XIDEAstate*, h);

	setupIDEAstate(&is->state, f->key->data, ivec);

	*f->ret = (Crypt_IDEAstate*)is;
}

void
Crypt_ideaecb(void *fp)
{
	F_Crypt_ideaecb *f;
	XIDEAstate *is;
	int i;
	uchar *p;

	f = fp;

	if(f->buf == H)
		return;
	if(f->n < 0 || f->n > f->buf->len)
		error(exBounds);
	if(f->n & 7)
		error(exBadBsize);

	is = checktype(f->state, TIDEAstate, exBadState, 0);
	p = f->buf->data;

	for(i = 8; i <= f->n; i += 8, p += 8)
		idea_cipher(is->state.edkey, p, f->direction);
}

void
Crypt_ideacbc(void *fp)
{
	F_Crypt_ideacbc *f;
	XIDEAstate *is;
	uchar *p, *ep, *ip, *p2, *eip;
	uchar tmp[8];

	f = fp;

	if(f->buf == H)
		return;
	if(f->n < 0 || f->n > f->buf->len)
		error(exBounds);
	if(f->n & 7)
		error(exBadBsize);

	is = checktype(f->state, TIDEAstate, exBadState, 0);
	p = f->buf->data;

	if(f->direction == 0){
		for(ep = p + f->n; p < ep; p += 8){
			p2 = p;
			ip = is->state.ivec;
			for(eip = ip+8; ip < eip; )
				*p2++ ^= *ip++;
			idea_cipher(is->state.edkey, p, 0);
			memmove(is->state.ivec, p, 8);
		}
	} else {
		for(ep = p + f->n; p < ep; ){
			memmove(tmp, p, 8);
			idea_cipher(is->state.edkey, p, 1);
			p2 = tmp;
			ip = is->state.ivec;
			for(eip = ip+8; ip < eip; ){
				*p++ ^= *ip;
				*ip++ = *p2++;
			}
		}
	}
}

void
Crypt_aessetup(void *fp)
{
	F_Crypt_aessetup *f;
	Heap *h;
	XAESstate *is;
	uchar *ivec;
	void *v;

	f = fp;
	v = *f->ret;
	*f->ret = H;
	destroy(v);

	if(f->key == H)
		error(exNilref);
	if(f->key->len != 16 && f->key->len != 24 && f->key->len != 32)
		error(exBadKey);
	if(f->ivec != H){
		if(f->ivec->len < AESbsize)
			error(exBadIvec);
		ivec = f->ivec->data;
	}else
		ivec = nil;

	h = heap(TAESstate);
	is = H2D(XAESstate*, h);

	setupAESstate(&is->state, f->key->data, f->key->len, ivec);

	*f->ret = (Crypt_AESstate*)is;
}

void
Crypt_aescbc(void *fp)
{
	F_Crypt_aescbc *f;
	XAESstate *is;
	uchar *p;

	f = fp;

	if(f->buf == H)
		return;
	if(f->n < 0 || f->n > f->buf->len)
		error(exBounds);

	is = checktype(f->state, TAESstate, exBadState, 0);
	p = f->buf->data;

	if(f->direction == 0)
		aesCBCencrypt(p, f->n, &is->state);
	else
		aesCBCdecrypt(p, f->n, &is->state);
}

void
Crypt_blowfishsetup(void *fp)
{
	F_Crypt_blowfishsetup *f;
	Heap *h;
	XBFstate *is;
	uchar *ivec;
	void *v;

	f = fp;
	v = *f->ret;
	*f->ret = H;
	destroy(v);

	if(f->key == H)
		error(exNilref);
	if(f->key->len <= 0)
		error(exBadKey);
	if(f->ivec != H){
		if(f->ivec->len != BFbsize)
			error(exBadIvec);
		ivec = f->ivec->data;
	}else
		ivec = nil;

	h = heap(TBFstate);
	is = H2D(XBFstate*, h);

	setupBFstate(&is->state, f->key->data, f->key->len, ivec);

	*f->ret = (Crypt_BFstate*)is;
}

void
Crypt_blowfishcbc(void *fp)
{
	F_Crypt_blowfishcbc *f;
	XBFstate *is;
	uchar *p;

	f = fp;

	if(f->state == H)
		return;
	if(f->n < 0 || f->n > f->buf->len)
		error(exBounds);
	if(f->n & 7)
		error(exBadBsize);

	is = checktype(f->state, TBFstate, exBadState, 0);
	p = f->buf->data;

	if(f->direction == 0)
		bfCBCencrypt(p, f->n, &is->state);
	else
		bfCBCdecrypt(p, f->n, &is->state);
}

void
Crypt_rc4setup(void *fp)
{
	F_Crypt_rc4setup *f;
	Heap *h;
	XRC4state *is;
	void *v;

	f = fp;
	v = *f->ret;
	*f->ret = H;
	destroy(v);

	if(f->seed == H)
		error(exNilref);

	h = heap(TRC4state);
	is = H2D(XRC4state*, h);

	setupRC4state(&is->state, f->seed->data, f->seed->len);

	*f->ret = (Crypt_RC4state*)is;
}

void
Crypt_rc4(void *fp)
{
	F_Crypt_rc4 *f;
	XRC4state *is;
	uchar *p;

	f = fp;
	if(f->buf == H)
		return;
	if(f->n < 0 || f->n > f->buf->len)
		error(exBounds);
	is = checktype(f->state, TRC4state, exBadState, 0);
	p = f->buf->data;
	rc4(&is->state, p, f->n);
}

void
Crypt_rc4skip(void *fp)
{
	F_Crypt_rc4skip *f;
	XRC4state *is;

	f = fp;
	is = checktype(f->state, TRC4state, exBadState, 0);
	rc4skip(&is->state, f->n);
}

void
Crypt_rc4back(void *fp)
{
	F_Crypt_rc4back *f;
	XRC4state *is;

	f = fp;
	is = checktype(f->state, TRC4state, exBadState, 0);
	rc4back(&is->state, f->n);
}

/*
 *  public/secret keys, signing and verifying
 */

/*
 * DSA
 */

static void
dsapk2pub(DSApub* p, Crypt_PK* pk)
{
	if(pk == H)
		error(exNilref);
	if(pk->pick != Crypt_PK_DSA)
		error(exType);
	p->p = MPX(pk->u.DSA.p);
	p->q = MPX(pk->u.DSA.q);
	p->alpha = MPX(pk->u.DSA.alpha);
	p->key = MPX(pk->u.DSA.key);
}

static void
dsask2priv(DSApriv* p, Crypt_SK* sk)
{
	if(sk == H)
		error(exNilref);
	if(sk->pick != Crypt_SK_DSA)
		error(exType);
	dsapk2pub(&p->pub, sk->u.DSA.pk);
	p->secret = MPX(sk->u.DSA.secret);
}

static void
dsapriv2sk(Crypt_SK* sk, DSApriv* p)
{
	Crypt_PK *pk;

	pk = sk->u.DSA.pk;
	pk->u.DSA.p = ipcopymp(p->pub.p);
	pk->u.DSA.q = ipcopymp(p->pub.q);
	pk->u.DSA.alpha = ipcopymp(p->pub.alpha);
	pk->u.DSA.key = ipcopymp(p->pub.key);
	sk->u.DSA.secret = ipcopymp(p->secret);
}

static void
dsaxgen(Crypt_SK* sk, DSApub* oldpk)
{
	DSApriv *p;

	release();
	p = dsagen(oldpk);
	acquire();
	dsapriv2sk(sk, p);
	dsaprivfree(p);
}

void
Crypt_dsagen(void *fp)
{
	F_Crypt_dsagen *f;
	Crypt_SK *sk;
	DSApub pub, *oldpk;
	void *v;

	f = fp;
	v = *f->ret;
	*f->ret = H;
	destroy(v);

	sk = newSK(f->ret, TSKdsa, Crypt_SK_DSA);
	oldpk = nil;
	if(f->oldpk != H && f->oldpk->pick == Crypt_PK_DSA){
		dsapk2pub(&pub, f->oldpk);
		oldpk = &pub;
	}
	dsaxgen(sk, oldpk);
}

/*
 * Elgamal
 */

static void
egpk2pub(EGpub* p, Crypt_PK* pk)
{
	if(pk == H)
		error(exNilref);
	if(pk->pick != Crypt_PK_Elgamal)
		error(exType);
	p->p = MPX(pk->u.Elgamal.p);
	p->alpha = MPX(pk->u.Elgamal.alpha);
	p->key = MPX(pk->u.Elgamal.key);
}

static void
egsk2priv(EGpriv* p, Crypt_SK* sk)
{
	if(sk == H)
		error(exNilref);
	if(sk->pick != Crypt_SK_Elgamal)
		error(exType);
	egpk2pub(&p->pub, sk->u.Elgamal.pk);
	p->secret = MPX(sk->u.Elgamal.secret);
}

static void
egpriv2sk(Crypt_SK* sk, EGpriv* p)
{
	Crypt_PK* pk;

	pk = sk->u.Elgamal.pk;
	pk->u.Elgamal.p = ipcopymp(p->pub.p);
	pk->u.Elgamal.alpha = ipcopymp(p->pub.alpha);
	pk->u.Elgamal.key = ipcopymp(p->pub.key);
	sk->u.Elgamal.secret = ipcopymp(p->secret);
}

static void
egxgen(Crypt_SK* sk, int nlen, int nrep)
{
	EGpriv *p;

	release();
	for(;;){
		p = eggen(nlen, nrep);
		if(mpsignif(p->pub.p) == nlen)
			break;
		egprivfree(p);
	}
	acquire();
	egpriv2sk(sk, p);
	egprivfree(p);
}
	

void
Crypt_eggen(void *fp)
{
	F_Crypt_eggen *f;
	Crypt_SK *sk;
	void *v;

	f = fp;
	v = *f->ret;
	*f->ret = H;
	destroy(v);

	sk = newSK(f->ret, TSKeg, Crypt_SK_Elgamal);
	egxgen(sk, f->nlen, f->nrep);
}

/*
 * RSA
 */

static void
rsapk2pub(RSApub* p, Crypt_PK* pk)
{
	if(pk == H)
		error(exNilref);
	if(pk->pick != Crypt_PK_RSA)
		error(exType);
	p->n = MPX(pk->u.RSA.n);
	p->ek = MPX(pk->u.RSA.ek);
}

static void
rsask2priv(RSApriv* p, Crypt_SK* sk)
{
	if(sk == H)
		error(exNilref);
	if(sk->pick != Crypt_SK_RSA)
		error(exType);
	rsapk2pub(&p->pub, sk->u.RSA.pk);
	p->dk = MPX(sk->u.RSA.dk);
	p->p = MPX(sk->u.RSA.p);
	p->q = MPX(sk->u.RSA.q);
	p->kp = MPX(sk->u.RSA.kp);
	p->kq = MPX(sk->u.RSA.kq);
	p->c2 = MPX(sk->u.RSA.c2);
}

static void
rsapriv2sk(Crypt_SK* sk, RSApriv* p)
{
	Crypt_PK *pk;

	pk = sk->u.RSA.pk;
	pk->u.RSA.n = ipcopymp(p->pub.n);
	pk->u.RSA.ek = ipcopymp(p->pub.ek);
	sk->u.RSA.dk = ipcopymp(p->dk);
	sk->u.RSA.p = ipcopymp(p->p);
	sk->u.RSA.q = ipcopymp(p->q);
	sk->u.RSA.kp = ipcopymp(p->kp);
	sk->u.RSA.kq = ipcopymp(p->kq);
	sk->u.RSA.c2 = ipcopymp(p->c2);
}

static void
rsaxgen(Crypt_SK *sk, int nlen, int elen, int nrep)
{
	RSApriv *p;

	release();
	for(;;){
		p = rsagen(nlen, elen, nrep);
		if(mpsignif(p->pub.n) == nlen)
			break;
		rsaprivfree(p);
	}
	acquire();
	rsapriv2sk(sk, p);
	rsaprivfree(p);
}

void
Crypt_rsagen(void *fp)
{
	F_Crypt_rsagen *f;
	Crypt_SK *sk;
	void *v;

	f = fp;
	v = *f->ret;
	*f->ret = H;
	destroy(v);

	sk = newSK(f->ret, TSKrsa, Crypt_SK_RSA);
	rsaxgen(sk, f->nlen, f->elen, f->nrep);
}

void
Crypt_rsafill(void *fp)
{
	F_Crypt_rsafill *f;
	Crypt_SK *sk;
	RSApriv *p;
	void *v;

	f = fp;
	v = *f->ret;
	*f->ret = H;
	destroy(v);

	sk = newSK(f->ret, TSKrsa, Crypt_SK_RSA);
	release();
	p = rsafill(MPX(f->n), MPX(f->ek), MPX(f->dk),
			MPX(f->p), MPX(f->q));
	acquire();
	if(p == nil) {
		*f->ret = H;
		destroy(sk);
	}else{
		rsapriv2sk(sk, p);
		rsaprivfree(p);
	}
}

void
Crypt_rsaencrypt(void *fp)
{
	F_Crypt_rsaencrypt *f;
	RSApub p;
	mpint *m, *o;
	void *v;

	f = fp;
	v = *f->ret;
	*f->ret = H;
	destroy(v);

	rsapk2pub(&p, f->k);
	m = MPX(f->m);
	release();
	o = rsaencrypt(&p, m, nil);
	acquire();
	*f->ret = newIPint(o);
}

void
Crypt_rsadecrypt(void *fp)
{
	F_Crypt_rsadecrypt *f;
	RSApriv p;
	mpint *m, *o;
	void *v;

	f = fp;
	v = *f->ret;
	*f->ret = H;
	destroy(v);

	rsask2priv(&p, f->k);
	m = MPX(f->m);
	release();
	o = rsadecrypt(&p, m, nil);
	acquire();
	*f->ret = newIPint(o);
}

/*
 * generic key functions
 */

void
Crypt_genSK(void *fp)
{
	F_Crypt_genSK *f;
	Crypt_SK *sk;
	char *sa;
	void *v;

	f = fp;
	v = *f->ret;
	*f->ret = H;
	destroy(v);

	sa = string2c(f->algname);
	if(strcmp(sa, "rsa") == 0){
		sk = newSK(f->ret, TSKrsa, Crypt_SK_RSA);
		rsaxgen(sk, f->length, 6, 0);
	}else if(strcmp(sa, "dsa") == 0){
		sk = newSK(f->ret, TSKdsa, Crypt_SK_DSA);
		dsaxgen(sk, nil);
	}else if(strcmp(sa, "elgamal") == 0){
		sk = newSK(f->ret, TSKeg, Crypt_SK_Elgamal);
		egxgen(sk, f->length, 0);
	}
	/* genSK returns nil for unknown algorithm */
}

void
Crypt_genSKfromPK(void *fp)
{
	F_Crypt_genSKfromPK *f;
	Crypt_SK *sk;
	void *v;

	f = fp;
	v = *f->ret;
	*f->ret = H;
	destroy(v);

	if(f->pk == H)
		error(exNilref);
	switch(f->pk->pick){
	case Crypt_PK_RSA: {
			RSApub p;

			rsapk2pub(&p, f->pk);
			sk = newSK(f->ret, TSKrsa, Crypt_SK_RSA);
			rsaxgen(sk, mpsignif(p.n), mpsignif(p.ek), 0);
		}
		break;
	case Crypt_PK_Elgamal: {
			EGpub p;

			egpk2pub(&p, f->pk);
			sk = newSK(f->ret, TSKeg, Crypt_SK_Elgamal);
			egxgen(sk, mpsignif(p.p), 0);
		}
		break;
	case Crypt_PK_DSA: {
			DSApub p;

			dsapk2pub(&p, f->pk);
			sk = newSK(f->ret, TSKdsa, Crypt_SK_DSA);
			dsaxgen(sk, &p);
		}
		break;
	default:
		/* shouldn't happen */
		error(exType);
	}
}

void
Crypt_sktopk(void *fp)
{
	F_Crypt_sktopk *f;
	Crypt_PK *pk;
	void *v;

	f = fp;
	v = *f->ret;
	*f->ret = H;
	destroy(v);
	if(f->sk == H)
		error(exNilref);
	switch(f->sk->pick){
	case Crypt_PK_RSA:
		pk = f->sk->u.RSA.pk;
		break;
	case Crypt_PK_Elgamal:
		pk = f->sk->u.Elgamal.pk;
		break;
	case Crypt_PK_DSA:
		pk = f->sk->u.DSA.pk;
		break;
	default:
		pk = H;
		error(exType);
	}
	if(pk == H)
		return;
	D2H(pk)->ref++;
	*f->ret = pk;
}

void
Crypt_sign(void *fp)
{
	F_Crypt_sign *f;
	Crypt_PKsig *sig;
	mpint *m;
	void *v;
	
	f = fp;
	v = *f->ret;
	*f->ret = H;
	destroy(v);

	if(f->m == H || f->sk == H)
		error(exNilref);
	m = MPX(f->m);
	switch(f->sk->pick){
	case Crypt_SK_RSA: {
			RSApriv p;
			mpint *s;

			rsask2priv(&p, f->sk);
			release();
			s = rsadecrypt(&p, m, nil);
			acquire();
			sig = newPKsig(TPKsigrsa, Crypt_PKsig_RSA);
			sig->u.RSA.n = newIPint(s);
		}
		break;
	case Crypt_SK_Elgamal: {
			EGpriv p;
			EGsig *s;

			egsk2priv(&p, f->sk);
			release();
			s = egsign(&p, m);
			acquire();
			sig = newPKsig(TPKsigeg, Crypt_PKsig_Elgamal);
			sig->u.Elgamal.r = ipcopymp(s->r);
			sig->u.Elgamal.s = ipcopymp(s->s);
			egsigfree(s);
		}
		break;
	case Crypt_SK_DSA: {
			DSApriv p;
			DSAsig *s;

			dsask2priv(&p, f->sk);
			m = MPX(f->m);
			release();
			s = dsasign(&p, m);
			acquire();
			sig = newPKsig(TPKsigdsa, Crypt_PKsig_DSA);
			sig->u.DSA.r = ipcopymp(s->r);
			sig->u.DSA.s = ipcopymp(s->s);
			dsasigfree(s);
		}
		break;
	default:
		sig = H;
		error(exType);
	}
	*f->ret = sig;
}

void
Crypt_verify(void *fp)
{
	F_Crypt_verify *f;
	mpint *m;

	f = fp;
	*f->ret = 0;
	if(f->sig == H || f->pk == H)
		error(exNilref);
	if(f->sig->pick != f->pk->pick)
		return;	/* key type and signature mismatch, doesn't validate */
	m = MPX(f->m);
	switch(f->pk->pick){
	case Crypt_PK_RSA: {
			RSApub p;
			mpint *sig, *t;

			rsapk2pub(&p, f->pk);
			sig = MPX(f->sig->u.RSA.n);
			release();
			t = rsaencrypt(&p, sig, nil);
			*f->ret = mpcmp(t, m) == 0;
			mpfree(t);
			acquire();
		}
		break;
	case Crypt_PK_Elgamal: {
			EGpub p;
			EGsig sig;

			egpk2pub(&p, f->pk);
			sig.r = MPX(f->sig->u.Elgamal.r);
			sig.s = MPX(f->sig->u.Elgamal.s);
			release();
			*f->ret = egverify(&p, &sig, m) == 0;
			acquire();
		}
		break;
	case Crypt_PK_DSA: {
			DSApub p;
			DSAsig sig;

			dsapk2pub(&p, f->pk);
			sig.r = MPX(f->sig->u.DSA.r);
			sig.s = MPX(f->sig->u.DSA.s);
			release();
			*f->ret = dsaverify(&p, &sig, m) == 0;
			acquire();
		}
		break;
	default:
		error(exType);
	}
}

/*
 * modern primitives
 */

static uchar*
bytes(Array *a, int n)
{
	if(a == H || a->len != n)
		return nil;
	return a->data;
}

static void
retarray(Array **ret, Array *a)
{
	void *v;

	v = *ret;
	*ret = a;
	destroy(v);
}

static void
ret2(Array **t0, Array **t1, Array *a, Array *b)
{
	retarray(t0, a);
	retarray(t1, b);
}

void
Crypt_x25519(void *fp)
{
	F_Crypt_x25519 *f;
	uchar *s, *p, out[X25519len];

	f = fp;
	retarray(f->ret, H);
	s = bytes(f->secret, X25519len);
	p = bytes(f->point, X25519len);
	if(s == nil || p == nil)
		return;
	x25519(out, s, p);
	*f->ret = mem2array(out, sizeof out);
}

void
Crypt_x25519base(void *fp)
{
	F_Crypt_x25519base *f;
	uchar *s, out[X25519len];

	f = fp;
	retarray(f->ret, H);
	s = bytes(f->secret, X25519len);
	if(s == nil)
		return;
	x25519base(out, s);
	*f->ret = mem2array(out, sizeof out);
}

void
Crypt_x25519map(void *fp)
{
	F_Crypt_x25519map *f;
	uchar *s, out[X25519len];

	f = fp;
	retarray(f->ret, H);
	s = bytes(f->fe, X25519len);
	if(s == nil)
		return;
	x25519map(out, s);
	*f->ret = mem2array(out, sizeof out);
}

void
Crypt_ed25519pub(void *fp)
{
	F_Crypt_ed25519pub *f;
	uchar *s, out[Ed25519publen];

	f = fp;
	retarray(f->ret, H);
	s = bytes(f->seed, Ed25519seedlen);
	if(s == nil)
		return;
	ed25519pub(out, s);
	*f->ret = mem2array(out, sizeof out);
}

void
Crypt_ed25519sign(void *fp)
{
	F_Crypt_ed25519sign *f;
	uchar *s, out[Ed25519siglen];

	f = fp;
	retarray(f->ret, H);
	s = bytes(f->seed, Ed25519seedlen);
	if(s == nil || f->msg == H)
		return;
	ed25519sign(out, s, f->msg->data, f->msg->len);
	*f->ret = mem2array(out, sizeof out);
}

void
Crypt_ed25519verify(void *fp)
{
	F_Crypt_ed25519verify *f;
	uchar *p, *s;

	f = fp;
	*f->ret = 0;
	p = bytes(f->pub, Ed25519publen);
	s = bytes(f->sig, Ed25519siglen);
	if(p == nil || s == nil || f->msg == H)
		return;
	*f->ret = ed25519verify(p, f->msg->data, f->msg->len, s);
}

void
Crypt_hkdfsha256(void *fp)
{
	F_Crypt_hkdfsha256 *f;
	uchar *salt, *info, *out;
	int nsalt, ninfo;

	f = fp;
	retarray(f->ret, H);
	if(f->ikm == H || f->n < 0 || f->n > 255*SHA256dlen)
		return;
	salt = info = nil;
	nsalt = ninfo = 0;
	if(f->salt != H){
		salt = f->salt->data;
		nsalt = f->salt->len;
	}
	if(f->info != H){
		info = f->info->data;
		ninfo = f->info->len;
	}
	out = malloc(f->n+1);
	if(out == nil)
		error(exNomem);
	hkdfsha256(out, f->n, salt, nsalt, f->ikm->data, f->ikm->len, info, ninfo);
	*f->ret = mem2array(out, f->n);
	free(out);
}

void
Crypt_xchachapolyseal(void *fp)
{
	F_Crypt_xchachapolyseal *f;
	uchar *k, *nonce, *ad, *out;
	int nad;

	f = fp;
	retarray(f->ret, H);
	k = bytes(f->key, XChachakeylen);
	nonce = bytes(f->nonce, XChachanoncelen);
	if(k == nil || nonce == nil || f->plain == H)
		return;
	ad = nil;
	nad = 0;
	if(f->ad != H){
		ad = f->ad->data;
		nad = f->ad->len;
	}
	out = malloc(f->plain->len + Polytaglen);
	if(out == nil)
		error(exNomem);
	xchachapolyseal(out, k, nonce, ad, nad, f->plain->data, f->plain->len);
	*f->ret = mem2array(out, f->plain->len + Polytaglen);
	free(out);
}

void
Crypt_xchachapolyopen(void *fp)
{
	F_Crypt_xchachapolyopen *f;
	uchar *k, *nonce, *ad, *out;
	int nad, n;

	f = fp;
	retarray(f->ret, H);
	k = bytes(f->key, XChachakeylen);
	nonce = bytes(f->nonce, XChachanoncelen);
	if(k == nil || nonce == nil || f->sealed == H || f->sealed->len < Polytaglen)
		return;
	ad = nil;
	nad = 0;
	if(f->ad != H){
		ad = f->ad->data;
		nad = f->ad->len;
	}
	n = f->sealed->len - Polytaglen;
	out = malloc(n+1);
	if(out == nil)
		error(exNomem);
	if(xchachapolyopen(out, k, nonce, ad, nad, f->sealed->data, n) == 0)
		*f->ret = mem2array(out, n);
	free(out);
}

void
Crypt_mlkem768keygen(void *fp)
{
	F_Crypt_mlkem768keygen *f;
	uchar *ek, *dk;

	f = fp;
	ret2(&f->ret->t0, &f->ret->t1, H, H);
	ek = malloc(MLKEM768eklen);
	dk = malloc(MLKEM768dklen);
	if(ek == nil || dk == nil){
		free(ek);
		free(dk);
		error(exNomem);
	}
	release();
	mlkem768keygen(ek, dk);
	acquire();
	f->ret->t0 = mem2array(ek, MLKEM768eklen);
	f->ret->t1 = mem2array(dk, MLKEM768dklen);
	memset(dk, 0, MLKEM768dklen);
	free(ek);
	free(dk);
}

void
Crypt_mlkem768keygenderand(void *fp)
{
	F_Crypt_mlkem768keygenderand *f;
	uchar *ek, *dk, *coins;

	f = fp;
	ret2(&f->ret->t0, &f->ret->t1, H, H);
	coins = bytes(f->coins, 64);
	if(coins == nil)
		return;
	ek = malloc(MLKEM768eklen);
	dk = malloc(MLKEM768dklen);
	if(ek == nil || dk == nil){
		free(ek);
		free(dk);
		error(exNomem);
	}
	mlkem768keygenderand(ek, dk, coins);
	f->ret->t0 = mem2array(ek, MLKEM768eklen);
	f->ret->t1 = mem2array(dk, MLKEM768dklen);
	free(ek);
	free(dk);
}

static void
encap(Array **t0, Array **t1, Array *aek, Array *acoins, int derand)
{
	uchar *ek, *coins, *ct, ss[MLKEM768sslen];

	ret2(t0, t1, H, H);
	ek = bytes(aek, MLKEM768eklen);
	coins = nil;
	if(derand && (coins = bytes(acoins, 32)) == nil)
		return;
	if(ek == nil)
		return;
	ct = malloc(MLKEM768ctlen);
	if(ct == nil)
		error(exNomem);
	if(derand)
		mlkem768encapderand(ct, ss, ek, coins);
	else
		mlkem768encap(ct, ss, ek);
	*t0 = mem2array(ct, MLKEM768ctlen);
	*t1 = mem2array(ss, sizeof ss);
	memset(ss, 0, sizeof ss);
	free(ct);
}

void
Crypt_mlkem768encap(void *fp)
{
	F_Crypt_mlkem768encap *f;

	f = fp;
	encap(&f->ret->t0, &f->ret->t1, f->ek, H, 0);
}

void
Crypt_mlkem768encapderand(void *fp)
{
	F_Crypt_mlkem768encapderand *f;

	f = fp;
	encap(&f->ret->t0, &f->ret->t1, f->ek, f->coins, 1);
}

void
Crypt_mlkem768decap(void *fp)
{
	F_Crypt_mlkem768decap *f;
	uchar *dk, *ct, ss[MLKEM768sslen];

	f = fp;
	retarray(f->ret, H);
	dk = bytes(f->dk, MLKEM768dklen);
	ct = bytes(f->ct, MLKEM768ctlen);
	if(dk == nil || ct == nil)
		return;
	mlkem768decap(ss, ct, dk);
	*f->ret = mem2array(ss, sizeof ss);
	memset(ss, 0, sizeof ss);
}

/*
 * ML-DSA-65. The work is done on copies with the interpreter released,
 * since signing takes milliseconds.
 */
/* nil if there is no memory */
static uchar*
copybytes(Array *a, int *n)
{
	uchar *p;

	*n = 0;
	if(a != H)
		*n = a->len;
	p = malloc(*n + 1);
	if(p != nil && *n != 0)
		memmove(p, a->data, *n);
	return p;
}

void
Crypt_mldsa65pub(void *fp)
{
	F_Crypt_mldsa65pub *f;
	uchar *s, seed[MLDSA65seedlen], *pk;
	Array **ret;

	f = fp;
	ret = f->ret;
	retarray(ret, H);
	s = bytes(f->seed, MLDSA65seedlen);
	if(s == nil)
		return;
	memmove(seed, s, sizeof seed);
	pk = malloc(MLDSA65pklen);
	if(pk == nil)
		error(exHeap);
	release();
	mldsa65pub(pk, seed);
	acquire();
	memset(seed, 0, sizeof seed);
	*ret = mem2array(pk, MLDSA65pklen);
	free(pk);
}

void
Crypt_mldsa65sign(void *fp)
{
	F_Crypt_mldsa65sign *f;
	uchar *s, seed[MLDSA65seedlen], *msg, *ctx, *sig;
	int nmsg, nctx, r;
	Array **ret;

	f = fp;
	ret = f->ret;
	retarray(ret, H);
	s = bytes(f->seed, MLDSA65seedlen);
	if(s == nil || f->ctx != H && f->ctx->len > 255)
		return;
	memmove(seed, s, sizeof seed);
	msg = copybytes(f->msg, &nmsg);
	ctx = copybytes(f->ctx, &nctx);
	sig = malloc(MLDSA65siglen);
	if(msg == nil || ctx == nil || sig == nil){
		free(msg);
		free(ctx);
		free(sig);
		error(exHeap);
	}
	release();
	r = mldsa65sign(sig, seed, msg, nmsg, ctx, nctx);
	acquire();
	memset(seed, 0, sizeof seed);
	if(r == 0)
		*ret = mem2array(sig, MLDSA65siglen);
	free(sig);
	free(msg);
	free(ctx);
}

void
Crypt_mldsa65verify(void *fp)
{
	F_Crypt_mldsa65verify *f;
	uchar *p, *pk, *sig, *msg, *ctx;
	int nmsg, nctx, n, r, *ret;

	f = fp;
	ret = f->ret;
	*ret = 0;
	p = bytes(f->pk, MLDSA65pklen);
	if(p == nil || bytes(f->sig, MLDSA65siglen) == nil || f->ctx != H && f->ctx->len > 255)
		return;
	pk = copybytes(f->pk, &n);
	sig = copybytes(f->sig, &n);
	msg = copybytes(f->msg, &nmsg);
	ctx = copybytes(f->ctx, &nctx);
	if(pk == nil || sig == nil || msg == nil || ctx == nil){
		free(pk);
		free(sig);
		free(msg);
		free(ctx);
		error(exHeap);
	}
	release();
	r = mldsa65verify(pk, msg, nmsg, ctx, nctx, sig);
	acquire();
	*ret = r;
	free(pk);
	free(sig);
	free(msg);
	free(ctx);
}
