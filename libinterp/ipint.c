#include "lib9.h"
#include "kernel.h"
#include <isa.h>
#include "interp.h"
#include "runt.h"
#include <mp.h>
#include <libsec.h>
#include "pool.h"
#include "../libkeyring/keys.h"
#include "raise.h"

enum {
	PSEUDO=0,
	REALLY,
};

void getRandBetween(BigInt p, BigInt q, BigInt result, int type);

extern Type	*TIPint;
#define	MP(x)	(((IPint*)(x))->b)

Keyring_IPint*
newIPint(BigInt b)
{
	Heap *h;
	IPint *ip;

	if(b == nil)
		error(exHeap);
	h = heap(TIPint);	/* TO DO: loss if heap fails */
	ip = H2D(IPint*, h);
	ip->b = b;
	return (Keyring_IPint*)ip;
}

void
freeIPint(Heap *h, int swept)
{
	IPint *ip;

	USED(swept);
	ip = H2D(IPint*, h);
	if(ip->b)
		mpfree(ip->b);
	freeheap(h, 0);
}

void
IPint_iptob64z(void *fp)
{
	F_IPint_iptob64 *f;
	BigInt b;
	char buf[MaxBigBytes];	/* TO DO: should allocate these */
	uchar *p;
	int n, o;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->i == H)
		error(exNilref);

	b = MP(f->i);
	n = (b->top+1)*Dbytes;
	p = malloc(n+1);
	if(p == nil)
		error(exHeap);
	n = mptobe(b, p+1, n, nil);
	if(n < 0){
		free(p);
		return;
	}
	p[0] = 0;
	if(n != 0 && (p[1]&0x80)){
		/* force leading 0 byte for compatibility with older representation */
		o = 0;
		n++;
	}else
		o = 1;
	enc64(buf, sizeof(buf), p+o, n);
	retstr(buf, f->ret);
	free(p);
}

void
IPint_iptob64(void *fp)
{
	F_IPint_iptob64 *f;
	char buf[MaxBigBytes];

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->i == H)
		error(exNilref);

	mptoa(MP(f->i), 64, buf, sizeof(buf));
	retstr(buf, f->ret);
}

void
IPint_iptobytes(void *fp)
{
	F_IPint_iptobytes *f;
	uchar buf[MaxBigBytes];

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->i == H)
		error(exNilref);

	/* TO DO: two's complement or have ipmagtobe? */
	*f->ret = mem2array(buf, mptobe(MP(f->i), buf, sizeof(buf), nil));	/* for now we'll ignore sign */
}

void
IPint_iptobebytes(void *fp)
{
	F_IPint_iptobebytes *f;
	uchar buf[MaxBigBytes];

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->i == H)
		error(exNilref);

	*f->ret = mem2array(buf, mptobe(MP(f->i), buf, sizeof(buf), nil));
}

void
IPint_iptostr(void *fp)
{
	F_IPint_iptostr *f;
	char buf[MaxBigBytes];

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->i == H)
		error(exNilref);

	mptoa(MP(f->i), f->base, buf, sizeof(buf));
	retstr(buf, f->ret);
}

static Keyring_IPint*
strtoipint(String *s, int base)
{
	char *p, *q;
	BigInt b;

	p = string2c(s);
	b = strtomp(p, &q, base, nil);
	if(b == nil)
		return H;
	while(*q == '=')
		q++;
	if(q == p || *q != 0){
		mpfree(b);
		return H;
	}
	return newIPint(b);
}

void
IPint_b64toip(void *fp)
{
	F_IPint_b64toip *f;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	*f->ret = strtoipint(f->str, 64);
}

void
IPint_bytestoip(void *fp)
{
	F_IPint_bytestoip *f;
	BigInt b;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->buf == H)
		error(exNilref);

	b = betomp(f->buf->data, f->buf->len, nil);	/* for now we'll ignore sign */
	*f->ret = newIPint(b);
}

void
IPint_bebytestoip(void *fp)
{
	F_IPint_bebytestoip *f;
	BigInt b;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->mag == H)
		error(exNilref);

	b = betomp(f->mag->data, f->mag->len, nil);
	*f->ret = newIPint(b);
}

void
IPint_strtoip(void *fp)
{
	F_IPint_strtoip *f;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	*f->ret = strtoipint(f->str, f->base);
}

/* create a random integer */
void
IPint_random(void *fp)
{
	F_IPint_random *f;
	BigInt b, min, max;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	b = itomp(1, nil);
	min = mpnew(0);
	max = mpnew(0);
	mpleft(b, f->minbits, min);
	mpleft(b, f->maxbits, max);
	
	release();
	getRandBetween(min, max, b, PSEUDO);	/* TO DO */
	acquire();

	mpfree(min);
	mpfree(max);
	*f->ret = newIPint(b);
}

/* number of bits in number */
void
IPint_bits(void *fp)
{
	F_IPint_bits *f;
	int n;

	f = fp;
	*f->ret = 0;
	if(f->i == H)
		return;

	n = mpsignif(MP(f->i));
	if(n == 0)
		n = 1;	/* compatibility */
	*f->ret = n;
}

/* create a new IP from an int */
void
IPint_inttoip(void *fp)
{
	F_IPint_inttoip *f;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	*f->ret = newIPint(itomp(f->i, nil));
}

void
IPint_iptoint(void *fp)
{
	F_IPint_iptoint *f;

	f = fp;
	*f->ret = 0;
	if(f->i == H)
		return;
	*f->ret = mptoi(MP(f->i));
}

/* modular exponentiation */
void
IPint_expmod(void *fp)
{
	F_IPint_expmod *f;
	BigInt ret, mod;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->base == H || f->exp == H)
		error(exNilref);

	mod = nil;
	if(f->mod != H)
		mod = MP(f->mod);
	ret = mpnew(0);
	if(ret != nil)
		mpexp(MP(f->base), MP(f->exp), mod, ret);
	*f->ret = newIPint(ret);
}

/* multiplicative inverse */
void
IPint_invert(void *fp)
{
	F_IPint_invert *f;
	BigInt ret;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	ret = mpnew(0);
	if(ret != nil)
		mpinvert(MP(f->base), MP(f->mod), ret);
	*f->ret = newIPint(ret);
}

/* basic math */
void
IPint_add(void *fp)
{
	F_IPint_add *f;
	BigInt i1, i2, ret;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->i1 == H || f->i2 == H)
		error(exNilref);

	i1 = ((IPint*)f->i1)->b;
	i2 = ((IPint*)f->i2)->b;
	ret = mpnew(0);
	if(ret != nil)
		mpadd(i1, i2, ret);

	*f->ret = newIPint(ret);
}
void
IPint_sub(void *fp)
{
	F_IPint_sub *f;
	BigInt i1, i2, ret;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->i1 == H || f->i2 == H)
		error(exNilref);

	i1 = ((IPint*)f->i1)->b;
	i2 = ((IPint*)f->i2)->b;
	ret = mpnew(0);
	if(ret != nil)
		mpsub(i1, i2, ret);

	*f->ret = newIPint(ret);
}
void
IPint_mul(void *fp)
{
	F_IPint_mul *f;
	BigInt i1, i2, ret;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->i1 == H || f->i2 == H)
		error(exNilref);

	i1 = ((IPint*)f->i1)->b;
	i2 = ((IPint*)f->i2)->b;
	ret = mpnew(0);
	if(ret != nil)
		mpmul(i1, i2, ret);

	*f->ret = newIPint(ret);
}
void
IPint_div(void *fp)
{
	F_IPint_div *f;
	BigInt i1, i2, quo, rem;

	f = fp;
	destroy(f->ret->t0);
	f->ret->t0 = H;
	destroy(f->ret->t1);
	f->ret->t1 = H;

	if(f->i1 == H || f->i2 == H)
		error(exNilref);

	i1 = ((IPint*)f->i1)->b;
	i2 = ((IPint*)f->i2)->b;
	quo = mpnew(0);
	if(quo == nil)
		error(exHeap);
	rem = mpnew(0);
	if(rem == nil){
		mpfree(quo);
		error(exHeap);
	}
	mpdiv(i1, i2, quo, rem);

	f->ret->t0 = newIPint(quo);
	f->ret->t1 = newIPint(rem);
}
void
IPint_mod(void *fp)
{
	F_IPint_mod *f;
	BigInt i1, i2, ret;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->i1 == H || f->i2 == H)
		error(exNilref);

	i1 = ((IPint*)f->i1)->b;
	i2 = ((IPint*)f->i2)->b;
	ret = mpnew(0);
	if(ret != nil)
		mpmod(i1, i2, ret);

	*f->ret = newIPint(ret);
}
void
IPint_neg(void *fp)
{
	F_IPint_neg *f;
	BigInt i, ret;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->i == H)
		error(exNilref);

	i = ((IPint*)f->i)->b;
	ret = mpcopy(i);
	if(ret == nil)
		error(exHeap);
	ret->sign = -ret->sign;

	*f->ret = newIPint(ret);
}

/* copy */
void
IPint_copy(void *fp)
{
	F_IPint_copy *f;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->i == H)
		return;

	*f->ret = newIPint(mpcopy(MP(f->i)));
}


/* equality */
void
IPint_eq(void *fp)
{
	F_IPint_eq *f;

	f = fp;
	*f->ret = 0;

	if(f->i1 == H || f->i2 == H)
		return;

	*f->ret = mpcmp(MP(f->i1), MP(f->i2)) == 0;
}

/* compare */
void
IPint_cmp(void *fp)
{
	F_IPint_eq *f;

	f = fp;
	*f->ret = 0;

	if(f->i1 == H || f->i2 == H)
		error(exNilref);

	*f->ret = mpcmp(MP(f->i1), MP(f->i2));
}

/* shifts */
void
IPint_shl(void *fp)
{
	F_IPint_shl *f;
	BigInt ret;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->i == H)
		error(exNilref);

	ret = mpnew(0);
	if(ret != nil)
		mpleft(MP(f->i), f->n, ret);
	*f->ret = newIPint(ret);
}
void
IPint_shr(void *fp)
{
	F_IPint_shr *f;
	BigInt ret;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->i == H)
		error(exNilref);

	ret = mpnew(0);
	if(ret != nil)
		mpright(MP(f->i), f->n, ret);
	*f->ret = newIPint(ret);
}

static void
mpand(mpint *b, mpint *m, mpint *res)
{
	int i;

	res->sign = b->sign;
	if(b->top == 0 || m->top == 0){
		res->top = 0;
		return;
	}
	mpbits(res, b->top*Dbits);
	res->top = b->top;
	for(i = b->top; --i >= 0;){
		if(i < m->top)
			res->p[i] = b->p[i] & m->p[i];
		else
			res->p[i] = 0;
	}
	mpnorm(res);
}

static void
mpor(mpint *b1, mpint *b2, mpint *res)
{
	mpint *t;
	int i;

	if(b2->top > b1->top){
		t = b1;
		b1 = b2;
		b2 = t;
	}
	if(b1->top == 0){
		mpassign(b2, res);
		return;
	}
	if(b2->top == 0){
		mpassign(b1, res);
		return;
	}
	mpassign(b1, res);
	for(i = b2->top; --i >= 0;)
		res->p[i] |= b2->p[i];
	mpnorm(res);
}

static void
mpxor(mpint *b1, mpint *b2, mpint *res)
{
	mpint *t;
	int i;

	if(b2->top > b1->top){
		t = b1;
		b1 = b2;
		b2 = t;
	}
	if(b1->top == 0){
		mpassign(b2, res);
		return;
	}
	if(b2->top == 0){
		mpassign(b1, res);
		return;
	}
	mpassign(b1, res);
	for(i = b2->top; --i >= 0;)
		res->p[i] ^= b2->p[i];
	mpnorm(res);
}

static void
mpnot(mpint *b1, mpint *res)
{
	int i;

	mpbits(res, Dbits*b1->top);
	res->sign = 1;
	res->top = b1->top;
	for(i = res->top; --i >= 0;)
		res->p[i] = ~b1->p[i];
	mpnorm(res);
}

/* bits */
void
IPint_and(void *fp)
{
	F_IPint_and *f;
	BigInt ret;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->i1 == H || f->i2 == H)
		error(exNilref);
	ret = mpnew(0);
	if(ret != nil)
		mpand(MP(f->i1), MP(f->i2), ret);
	*f->ret = newIPint(ret);
}

void
IPint_ori(void *fp)
{
	F_IPint_ori *f;
	BigInt ret;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->i1 == H || f->i2 == H)
		error(exNilref);
	ret = mpnew(0);
	if(ret != nil)
		mpor(MP(f->i1), MP(f->i2), ret);
	*f->ret = newIPint(ret);
}

void
IPint_xor(void *fp)
{
	F_IPint_xor *f;
	BigInt ret;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->i1 == H || f->i2 == H)
		error(exNilref);
	ret = mpnew(0);
	if(ret != nil)
		mpxor(MP(f->i1), MP(f->i2), ret);
	*f->ret = newIPint(ret);
}

void
IPint_not(void *fp)
{
	F_IPint_not *f;
	BigInt ret;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	if(f->i1 == H)
		error(exNilref);
	ret = mpnew(0);
	if(ret != nil)
		mpnot(MP(f->i1), ret);
	*f->ret = newIPint(ret);
}

/*
 * return a random number between a and b
 */
void
getRandBetween(BigInt p, BigInt q, BigInt result, int type)
{
	BigInt T, slop, r, diff, one, two;
	int length;

if(0)print("1");
	diff = mpnew(0);
	one = itomp(1, nil);

	/* smaller in p, larger in q */
	if (mpcmp(p, q) > 0) {
		T = p; p = q; q = T;
	}
	
	mpsub(q, p, diff);

	two = itomp(2, nil);
	if(mpcmp(diff, two) < 0){
		mpfree(one);
		mpfree(two);
		itomp(0, result);
		return;
	}
	mpfree(two);
	
	/* generate a random number between 0 and diff */
	T = mpnew(0);
	slop = mpnew(0);
	mpleft(one, mpsignif(diff), T);
	length = mpsignif(T);
	
	mpmod(T, diff, slop);
	mpfree(T);
	
	r = mpnew(0);
	do {
if(0)print("3");
		mprand(length, type == PSEUDO? prng: genrandom, r);
if(0)print("4");
	} while (mpcmp(r, slop) < 0);
	mpfree(slop);
	
	mpmod(r, diff, result);
	mpfree(r);
	mpfree(diff);
	mpfree(one);
	
	/* add smaller number back in */
	mpadd(result, p, result);

if(0)print("2");
}
