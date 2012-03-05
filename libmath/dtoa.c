/* derived from /netlib/fp/dtoa.c assuming IEEE, Standard C */
/* kudos to dmg@bell-labs.com, gripes to ehg@bell-labs.com */
#include "lib9.h"
#define ACQUIRE_DTOA_LOCK(n)	/*nothing*/
#define FREE_DTOA_LOCK(n)	/*nothing*/

/* let's provide reasonable defaults for usual implementation of IEEE f.p. */
#ifndef DBL_DIG
#define DBL_DIG		15
#endif
#ifndef DBL_MAX_10_EXP
#define DBL_MAX_10_EXP	308
#endif
#ifndef DBL_MAX_EXP
#define DBL_MAX_EXP	1024
#endif
#ifndef FLT_RADIX
#define FLT_RADIX	2
#endif
#ifndef FLT_ROUNDS
#define FLT_ROUNDS 1
#endif
#ifndef Storeinc
#define Storeinc(a,b,c) (*a++ = b << 16 | c & 0xffff)
#endif

#define Sign_Extend(a,b) if (b < 0) a |= 0xffff0000;

#ifdef USE_FPdbleword
#define word0(x) ((FPdbleword*)&x)->hi
#define word1(x) ((FPdbleword*)&x)->lo
#else
#ifdef __LITTLE_ENDIAN
#define word0(x) ((unsigned  long *)&x)[1]
#define word1(x) ((unsigned  long *)&x)[0]
#else
#define word0(x) ((unsigned  long *)&x)[0]
#define word1(x) ((unsigned  long *)&x)[1]
#endif
#endif

/* #define P DBL_MANT_DIG */
/* Ten_pmax = floor(P*log(2)/log(5)) */
/* Bletch = (highest power of 2 < DBL_MAX_10_EXP) / 16 */
/* Quick_max = floor((P-1)*log(FLT_RADIX)/log(10) - 1) */
/* Int_max = floor(P*log(FLT_RADIX)/log(10) - 1) */

#define Exp_shift  20
#define Exp_shift1 20
#define Exp_msk1    0x100000
#define Exp_msk11   0x100000
#define Exp_mask  0x7ff00000
#define P 53
#define Bias 1023
#define Emin (-1022)
#define Exp_1  0x3ff00000
#define Exp_11 0x3ff00000
#define Ebits 11
#define Frac_mask  0xfffff
#define Frac_mask1 0xfffff
#define Ten_pmax 22
#define Bletch 0x10
#define Bndry_mask  0xfffff
#define Bndry_mask1 0xfffff
#define LSB 1
#define Sign_bit 0x80000000
#define Log2P 1
#define Tiny0 0
#define Tiny1 1
#define Quick_max 14
#define Int_max 14
#define Infinite(x) (word0(x) == 0x7ff00000) /* sufficient test for here */
#define Avoid_Underflow

#define rounded_product(a,b) a *= b
#define rounded_quotient(a,b) a /= b

#define Big0 (Frac_mask1 | Exp_msk1*(DBL_MAX_EXP+Bias-1))
#define Big1 0xffffffff

#define Kmax 15

struct
Bigint {
	struct Bigint *next;
	int	k, maxwds, sign, wds;
	unsigned  long x[1];
};

typedef struct Bigint Bigint;

static Bigint *freelist[Kmax+1];

static Bigint *
Balloc(int k)
{
	int	x;
	Bigint * rv;

	ACQUIRE_DTOA_LOCK(0);
	if (rv = freelist[k]) {
		freelist[k] = rv->next;
	} else {
		x = 1 << k;
		rv = (Bigint * )malloc(sizeof(Bigint) + (x - 1) * sizeof(unsigned  long));
		if(rv == nil)
			return nil;
		rv->k = k;
		rv->maxwds = x;
	}
	FREE_DTOA_LOCK(0);
	rv->sign = rv->wds = 0;
	return rv;
}

static void
Bfree(Bigint *v)
{
	if (v) {
		ACQUIRE_DTOA_LOCK(0);
		v->next = freelist[v->k];
		freelist[v->k] = v;
		FREE_DTOA_LOCK(0);
	}
}

#define Bcopy(x,y) memcpy((char *)&x->sign, (char *)&y->sign, \
y->wds*sizeof(long) + 2*sizeof(int))

static Bigint *
multadd(Bigint *b, int m, int a)	/* multiply by m and add a */
{
	int	i, wds;
	unsigned  long * x, y;
	unsigned  long xi, z;
	Bigint * b1;

	wds = b->wds;
	x = b->x;
	i = 0;
	do {
		xi = *x;
		y = (xi & 0xffff) * m + a;
		z = (xi >> 16) * m + (y >> 16);
		a = (int)(z >> 16);
		*x++ = (z << 16) + (y & 0xffff);
	} while (++i < wds);
	if (a) {
		if (wds >= b->maxwds) {
			b1 = Balloc(b->k + 1);
			Bcopy(b1, b);
			Bfree(b);
			b = b1;
		}
		b->x[wds++] = a;
		b->wds = wds;
	}
	return b;
}

static Bigint *
s2b(const char *s, int nd0, int nd, unsigned  long y9)
{
	Bigint * b;
	int	i, k;
	long x, y;

	x = (nd + 8) / 9;
	for (k = 0, y = 1; x > y; y <<= 1, k++) 
		;
	b = Balloc(k);
	b->x[0] = y9;
	b->wds = 1;

	i = 9;
	if (9 < nd0) {
		s += 9;
		do 
			b = multadd(b, 10, *s++ - '0');
		while (++i < nd0);
		s++;
	} else
		s += 10;
	for (; i < nd; i++)
		b = multadd(b, 10, *s++ - '0');
	return b;
}

static int	
hi0bits(register unsigned  long x)
{
	register int	k = 0;

	if (!(x & 0xffff0000)) {
		k = 16;
		x <<= 16;
	}
	if (!(x & 0xff000000)) {
		k += 8;
		x <<= 8;
	}
	if (!(x & 0xf0000000)) {
		k += 4;
		x <<= 4;
	}
	if (!(x & 0xc0000000)) {
		k += 2;
		x <<= 2;
	}
	if (!(x & 0x80000000)) {
		k++;
		if (!(x & 0x40000000))
			return 32;
	}
	return k;
}

static int	
lo0bits(unsigned  long *y)
{
	register int	k;
	register unsigned  long x = *y;

	if (x & 7) {
		if (x & 1)
			return 0;
		if (x & 2) {
			*y = x >> 1;
			return 1;
		}
		*y = x >> 2;
		return 2;
	}
	k = 0;
	if (!(x & 0xffff)) {
		k = 16;
		x >>= 16;
	}
	if (!(x & 0xff)) {
		k += 8;
		x >>= 8;
	}
	if (!(x & 0xf)) {
		k += 4;
		x >>= 4;
	}
	if (!(x & 0x3)) {
		k += 2;
		x >>= 2;
	}
	if (!(x & 1)) {
		k++;
		x >>= 1;
		if (!x & 1)
			return 32;
	}
	*y = x;
	return k;
}

static Bigint *
i2b(int i)
{
	Bigint * b;

	b = Balloc(1);
	b->x[0] = i;
	b->wds = 1;
	return b;
}

static Bigint *
mult(Bigint *a, Bigint *b)
{
	Bigint * c;
	int	k, wa, wb, wc;
	unsigned  long carry, y, z;
	unsigned  long * x, *xa, *xae, *xb, *xbe, *xc, *xc0;
	unsigned  long z2;

	if (a->wds < b->wds) {
		c = a;
		a = b;
		b = c;
	}
	k = a->k;
	wa = a->wds;
	wb = b->wds;
	wc = wa + wb;
	if (wc > a->maxwds)
		k++;
	c = Balloc(k);
	for (x = c->x, xa = x + wc; x < xa; x++)
		*x = 0;
	xa = a->x;
	xae = xa + wa;
	xb = b->x;
	xbe = xb + wb;
	xc0 = c->x;
	for (; xb < xbe; xb++, xc0++) {
		if (y = *xb & 0xffff) {
			x = xa;
			xc = xc0;
			carry = 0;
			do {
				z = (*x & 0xffff) * y + (*xc & 0xffff) + carry;
				carry = z >> 16;
				z2 = (*x++ >> 16) * y + (*xc >> 16) + carry;
				carry = z2 >> 16;
				Storeinc(xc, z2, z);
			} while (x < xae);
			*xc = carry;
		}
		if (y = *xb >> 16) {
			x = xa;
			xc = xc0;
			carry = 0;
			z2 = *xc;
			do {
				z = (*x & 0xffff) * y + (*xc >> 16) + carry;
				carry = z >> 16;
				Storeinc(xc, z, z2);
				z2 = (*x++ >> 16) * y + (*xc & 0xffff) + carry;
				carry = z2 >> 16;
			} while (x < xae);
			*xc = z2;
		}
	}
	for (xc0 = c->x, xc = xc0 + wc; wc > 0 && !*--xc; --wc) 
		;
	c->wds = wc;
	return c;
}

static Bigint *p5s;

static Bigint *
pow5mult(Bigint *b, int k)
{
	Bigint * b1, *p5, *p51;
	int	i;
	static int	p05[3] = { 
		5, 25, 125 	};

	if (i = k & 3)
		b = multadd(b, p05[i-1], 0);

	if (!(k >>= 2))
		return b;
	if (!(p5 = p5s)) {
		/* first time */
		ACQUIRE_DTOA_LOCK(1);
		if (!(p5 = p5s)) {
			p5 = p5s = i2b(625);
			p5->next = 0;
		}
		FREE_DTOA_LOCK(1);
	}
	for (; ; ) {
		if (k & 1) {
			b1 = mult(b, p5);
			Bfree(b);
			b = b1;
		}
		if (!(k >>= 1))
			break;
		if (!(p51 = p5->next)) {
			ACQUIRE_DTOA_LOCK(1);
			if (!(p51 = p5->next)) {
				p51 = p5->next = mult(p5, p5);
				p51->next = 0;
			}
			FREE_DTOA_LOCK(1);
		}
		p5 = p51;
	}
	return b;
}

static Bigint *
lshift(Bigint *b, int k)
{
	int	i, k1, n, n1;
	Bigint * b1;
	unsigned  long * x, *x1, *xe, z;

	n = k >> 5;
	k1 = b->k;
	n1 = n + b->wds + 1;
	for (i = b->maxwds; n1 > i; i <<= 1)
		k1++;
	b1 = Balloc(k1);
	x1 = b1->x;
	for (i = 0; i < n; i++)
		*x1++ = 0;
	x = b->x;
	xe = x + b->wds;
	if (k &= 0x1f) {
		k1 = 32 - k;
		z = 0;
		do {
			*x1++ = *x << k | z;
			z = *x++ >> k1;
		} while (x < xe);
		if (*x1 = z)
			++n1;
	} else 
		do
			*x1++ = *x++;
		while (x < xe);
	b1->wds = n1 - 1;
	Bfree(b);
	return b1;
}

static int	
cmp(Bigint *a, Bigint *b)
{
	unsigned  long * xa, *xa0, *xb, *xb0;
	int	i, j;

	i = a->wds;
	j = b->wds;
	if (i -= j)
		return i;
	xa0 = a->x;
	xa = xa0 + j;
	xb0 = b->x;
	xb = xb0 + j;
	for (; ; ) {
		if (*--xa != *--xb)
			return * xa < *xb ? -1 : 1;
		if (xa <= xa0)
			break;
	}
	return 0;
}

static Bigint *
diff(Bigint *a, Bigint *b)
{
	Bigint * c;
	int	i, wa, wb;
	long borrow, y;	/* We need signed shifts here. */
	unsigned  long * xa, *xae, *xb, *xbe, *xc;
	long z;

	i = cmp(a, b);
	if (!i) {
		c = Balloc(0);
		c->wds = 1;
		c->x[0] = 0;
		return c;
	}
	if (i < 0) {
		c = a;
		a = b;
		b = c;
		i = 1;
	} else
		i = 0;
	c = Balloc(a->k);
	c->sign = i;
	wa = a->wds;
	xa = a->x;
	xae = xa + wa;
	wb = b->wds;
	xb = b->x;
	xbe = xb + wb;
	xc = c->x;
	borrow = 0;
	do {
		y = (*xa & 0xffff) - (*xb & 0xffff) + borrow;
		borrow = y >> 16;
		Sign_Extend(borrow, y);
		z = (*xa++ >> 16) - (*xb++ >> 16) + borrow;
		borrow = z >> 16;
		Sign_Extend(borrow, z);
		Storeinc(xc, z, y);
	} while (xb < xbe);
	while (xa < xae) {
		y = (*xa & 0xffff) + borrow;
		borrow = y >> 16;
		Sign_Extend(borrow, y);
		z = (*xa++ >> 16) + borrow;
		borrow = z >> 16;
		Sign_Extend(borrow, z);
		Storeinc(xc, z, y);
	}
	while (!*--xc)
		wa--;
	c->wds = wa;
	return c;
}

static double	
ulp(double x)
{
	register long L;
	double	a;

	L = (word0(x) & Exp_mask) - (P - 1) * Exp_msk1;
#ifndef Sudden_Underflow
	if (L > 0) {
#endif
		word0(a) = L;
		word1(a) = 0;
#ifndef Sudden_Underflow
	} else {
		L = -L >> Exp_shift;
		if (L < Exp_shift) {
			word0(a) = 0x80000 >> L;
			word1(a) = 0;
		} else {
			word0(a) = 0;
			L -= Exp_shift;
			word1(a) = L >= 31 ? 1 : 1 << 31 - L;
		}
	}
#endif
	return a;
}

static double	
b2d(Bigint *a, int *e)
{
	unsigned  long * xa, *xa0, w, y, z;
	int	k;
	double	d;
#define d0 word0(d)
#define d1 word1(d)

	xa0 = a->x;
	xa = xa0 + a->wds;
	y = *--xa;
	k = hi0bits(y);
	*e = 32 - k;
	if (k < Ebits) {
		d0 = Exp_1 | y >> Ebits - k;
		w = xa > xa0 ? *--xa : 0;
		d1 = y << (32 - Ebits) + k | w >> Ebits - k;
		goto ret_d;
	}
	z = xa > xa0 ? *--xa : 0;
	if (k -= Ebits) {
		d0 = Exp_1 | y << k | z >> 32 - k;
		y = xa > xa0 ? *--xa : 0;
		d1 = z << k | y >> 32 - k;
	} else {
		d0 = Exp_1 | y;
		d1 = z;
	}
ret_d:
#undef d0
#undef d1
	return d;
}

static Bigint *
d2b(double d, int *e, int *bits)
{
	Bigint * b;
	int	de, i, k;
	unsigned  long * x, y, z;
#define d0 word0(d)
#define d1 word1(d)

	b = Balloc(1);
	x = b->x;

	z = d0 & Frac_mask;
	d0 &= 0x7fffffff;	/* clear sign bit, which we ignore */
#ifdef Sudden_Underflow
	de = (int)(d0 >> Exp_shift);
	z |= Exp_msk11;
#else
	if (de = (int)(d0 >> Exp_shift))
		z |= Exp_msk1;
#endif
	if (y = d1) {
		if (k = lo0bits(&y)) {
			x[0] = y | z << 32 - k;
			z >>= k;
		} else
			x[0] = y;
		i = b->wds = (x[1] = z) ? 2 : 1;
	} else {
		k = lo0bits(&z);
		x[0] = z;
		i = b->wds = 1;
		k += 32;
	}
#ifndef Sudden_Underflow
	if (de) {
#endif
		*e = de - Bias - (P - 1) + k;
		*bits = P - k;
#ifndef Sudden_Underflow
	} else {
		*e = de - Bias - (P - 1) + 1 + k;
		*bits = 32 * i - hi0bits(x[i-1]);
	}
#endif
	return b;
}

#undef d0
#undef d1

static double	
ratio(Bigint *a, Bigint *b)
{
	double	da, db;
	int	k, ka, kb;

	da = b2d(a, &ka);
	db = b2d(b, &kb);
	k = ka - kb + 32 * (a->wds - b->wds);
	if (k > 0)
		word0(da) += k * Exp_msk1;
	else {
		k = -k;
		word0(db) += k * Exp_msk1;
	}
	return da / db;
}

static const double
tens[] = {
	1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9,
	1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19,
	1e20, 1e21, 1e22
};

static const double
bigtens[] = { 
	1e16, 1e32, 1e64, 1e128, 1e256 };

static const double tinytens[] = { 
	1e-16, 1e-32, 1e-64, 1e-128,
	9007199254740992.e-256
};

/* The factor of 2^53 in tinytens[4] helps us avoid setting the underflow */
/* flag unnecessarily.  It leads to a song and dance at the end of strtod. */
#define Scale_Bit 0x10
#define n_bigtens 5

#define NAN_WORD0 0x7ff80000

#define NAN_WORD1 0

static int	
match(const char **sp, char *t)
{
	int	c, d;
	const char * s = *sp;

	while (d = *t++) {
		if ((c = *++s) >= 'A' && c <= 'Z')
			c += 'a' - 'A';
		if (c != d)
			return 0;
	}
	*sp = s + 1;
	return 1;
}

double
strtod(const char *s00, char **se)
{
	int	scale;
	int	bb2, bb5, bbe, bd2, bd5, bbbits, bs2, c, dsign,
	e, e1, esign, i, j, k, nd, nd0, nf, nz, nz0, sign;
	const char * s, *s0, *s1;
	double	aadj, aadj1, adj, rv, rv0;
	long L;
	unsigned  long y, z;
	Bigint * bb, *bb1, *bd, *bd0, *bs, *delta;
	sign = nz0 = nz = 0;
	rv = 0.;
	for (s = s00; ; s++) 
		switch (*s) {
		case '-':
			sign = 1;
			/* no break */
		case '+':
			if (*++s)
				goto break2;
			/* no break */
		case 0:
			s = s00;
			goto ret;
		case '\t':
		case '\n':
		case '\v':
		case '\f':
		case '\r':
		case ' ':
			continue;
		default:
			goto break2;
		}
break2:
	if (*s == '0') {
		nz0 = 1;
		while (*++s == '0') 
			;
		if (!*s)
			goto ret;
	}
	s0 = s;
	y = z = 0;
	for (nd = nf = 0; (c = *s) >= '0' && c <= '9'; nd++, s++)
		if (nd < 9)
			y = 10 * y + c - '0';
		else if (nd < 16)
			z = 10 * z + c - '0';
	nd0 = nd;
	if (c == '.') {
		c = *++s;
		if (!nd) {
			for (; c == '0'; c = *++s)
				nz++;
			if (c > '0' && c <= '9') {
				s0 = s;
				nf += nz;
				nz = 0;
				goto have_dig;
			}
			goto dig_done;
		}
		for (; c >= '0' && c <= '9'; c = *++s) {
have_dig:
			nz++;
			if (c -= '0') {
				nf += nz;
				for (i = 1; i < nz; i++)
					if (nd++ < 9)
						y *= 10;
					else if (nd <= DBL_DIG + 1)
						z *= 10;
				if (nd++ < 9)
					y = 10 * y + c;
				else if (nd <= DBL_DIG + 1)
					z = 10 * z + c;
				nz = 0;
			}
		}
	}
dig_done:
	e = 0;
	if (c == 'e' || c == 'E') {
		if (!nd && !nz && !nz0) {
			s = s00;
			goto ret;
		}
		s00 = s;
		esign = 0;
		switch (c = *++s) {
		case '-':
			esign = 1;
		case '+':
			c = *++s;
		}
		if (c >= '0' && c <= '9') {
			while (c == '0')
				c = *++s;
			if (c > '0' && c <= '9') {
				L = c - '0';
				s1 = s;
				while ((c = *++s) >= '0' && c <= '9')
					L = 10 * L + c - '0';
				if (s - s1 > 8 || L > 19999)
					/* Avoid confusion from exponents
					 * so large that e might overflow.
					 */
					e = 19999; /* safe for 16 bit ints */
				else
					e = (int)L;
				if (esign)
					e = -e;
			} else
				e = 0;
		} else
			s = s00;
	}
	if (!nd) {
		if (!nz && !nz0) {
			/* Check for Nan and Infinity */
			switch (c) {
			case 'i':
			case 'I':
				if (match(&s, "nfinity")) {
					word0(rv) = 0x7ff00000;
					word1(rv) = 0;
					goto ret;
				}
				break;
			case 'n':
			case 'N':
				if (match(&s, "an")) {
					word0(rv) = NAN_WORD0;
					word1(rv) = NAN_WORD1;
					goto ret;
				}
			}
			s = s00;
		}
		goto ret;
	}
	e1 = e -= nf;

	/* Now we have nd0 digits, starting at s0, followed by a
	 * decimal point, followed by nd-nd0 digits.  The number we're
	 * after is the integer represented by those digits times
	 * 10**e */

	if (!nd0)
		nd0 = nd;
	k = nd < DBL_DIG + 1 ? nd : DBL_DIG + 1;
	rv = y;
	if (k > 9)
		rv = tens[k - 9] * rv + z;
	bd0 = 0;
	if (nd <= DBL_DIG
	     && FLT_ROUNDS == 1
	    ) {
		if (!e)
			goto ret;
		if (e > 0) {
			if (e <= Ten_pmax) {
				/* rv = */ rounded_product(rv, tens[e]);
				goto ret;
			}
			i = DBL_DIG - nd;
			if (e <= Ten_pmax + i) {
				/* A fancier test would sometimes let us do
				 * this for larger i values.
				 */
				e -= i;
				rv *= tens[i];
				/* rv = */ rounded_product(rv, tens[e]);
				goto ret;
			}
		} else if (e >= -Ten_pmax) {
			/* rv = */ rounded_quotient(rv, tens[-e]);
			goto ret;
		}
	}
	e1 += nd - k;

	scale = 0;

	/* Get starting approximation = rv * 10**e1 */

	if (e1 > 0) {
		if (i = e1 & 15)
			rv *= tens[i];
		if (e1 &= ~15) {
			if (e1 > DBL_MAX_10_EXP) {
ovfl:
				/* Can't trust HUGE_VAL */
				word0(rv) = Exp_mask;
				word1(rv) = 0;
				if (bd0)
					goto retfree;
				goto ret;
			}
			if (e1 >>= 4) {
				for (j = 0; e1 > 1; j++, e1 >>= 1)
					if (e1 & 1)
						rv *= bigtens[j];
				/* The last multiplication could overflow. */
				word0(rv) -= P * Exp_msk1;
				rv *= bigtens[j];
				if ((z = word0(rv) & Exp_mask)
				     > Exp_msk1 * (DBL_MAX_EXP + Bias - P))
					goto ovfl;
				if (z > Exp_msk1 * (DBL_MAX_EXP + Bias - 1 - P)) {
					/* set to largest number */
					/* (Can't trust DBL_MAX) */
					word0(rv) = Big0;
					word1(rv) = Big1;
				} else
					word0(rv) += P * Exp_msk1;
			}

		}
	} else if (e1 < 0) {
		e1 = -e1;
		if (i = e1 & 15)
			rv /= tens[i];
		if (e1 &= ~15) {
			e1 >>= 4;
			if (e1 >= 1 << n_bigtens)
				goto undfl;
			if (e1 & Scale_Bit)
				scale = P;
			for (j = 0; e1 > 0; j++, e1 >>= 1)
				if (e1 & 1)
					rv *= tinytens[j];
			if (!rv) {
undfl:
				rv = 0.;
				if (bd0)
					goto retfree;
				goto ret;
			}
		}
	}

	/* Now the hard part -- adjusting rv to the correct value.*/

	/* Put digits into bd: true value = bd * 10^e */

	bd0 = s2b(s0, nd0, nd, y);

	for (; ; ) {
		bd = Balloc(bd0->k);
		Bcopy(bd, bd0);
		bb = d2b(rv, &bbe, &bbbits);	/* rv = bb * 2^bbe */
		bs = i2b(1);

		if (e >= 0) {
			bb2 = bb5 = 0;
			bd2 = bd5 = e;
		} else {
			bb2 = bb5 = -e;
			bd2 = bd5 = 0;
		}
		if (bbe >= 0)
			bb2 += bbe;
		else
			bd2 -= bbe;
		bs2 = bb2;
#ifdef Sudden_Underflow
		j = P + 1 - bbbits;
#else
		i = bbe + bbbits - 1;	/* logb(rv) */
		if (i < Emin)	/* denormal */
			j = bbe + (P - Emin);
		else
			j = P + 1 - bbbits;
#endif
		bb2 += j;
		bd2 += j;
		bd2 += scale;
		i = bb2 < bd2 ? bb2 : bd2;
		if (i > bs2)
			i = bs2;
		if (i > 0) {
			bb2 -= i;
			bd2 -= i;
			bs2 -= i;
		}
		if (bb5 > 0) {
			bs = pow5mult(bs, bb5);
			bb1 = mult(bs, bb);
			Bfree(bb);
			bb = bb1;
		}
		if (bb2 > 0)
			bb = lshift(bb, bb2);
		if (bd5 > 0)
			bd = pow5mult(bd, bd5);
		if (bd2 > 0)
			bd = lshift(bd, bd2);
		if (bs2 > 0)
			bs = lshift(bs, bs2);
		delta = diff(bb, bd);
		dsign = delta->sign;
		delta->sign = 0;
		i = cmp(delta, bs);
		if (i < 0) {
			/* Error is less than half an ulp -- check for
			 * special case of mantissa a power of two.
			 */
			if (dsign || word1(rv) || word0(rv) & Bndry_mask
			     || (word0(rv) & Exp_mask) <= Exp_msk1
			    ) {
				if (!delta->x[0] && delta->wds == 1)
					dsign = 2;
				break;
			}
			delta = lshift(delta, Log2P);
			if (cmp(delta, bs) > 0)
				goto drop_down;
			break;
		}
		if (i == 0) {
			/* exactly half-way between */
			if (dsign) {
				if ((word0(rv) & Bndry_mask1) == Bndry_mask1
				     &&  word1(rv) == 0xffffffff) {
					/*boundary case -- increment exponent*/
					word0(rv) = (word0(rv) & Exp_mask)
					 + Exp_msk1
					    ;
					word1(rv) = 0;
					dsign = 0;
					break;
				}
			} else if (!(word0(rv) & Bndry_mask) && !word1(rv)) {
				dsign = 2;
drop_down:
				/* boundary case -- decrement exponent */
#ifdef Sudden_Underflow
				L = word0(rv) & Exp_mask;
				if (L <= Exp_msk1)
					goto undfl;
				L -= Exp_msk1;
#else
				L = (word0(rv) & Exp_mask) - Exp_msk1;
#endif
				word0(rv) = L | Bndry_mask1;
				word1(rv) = 0xffffffff;
				break;
			}
			if (!(word1(rv) & LSB))
				break;
			if (dsign)
				rv += ulp(rv);
			else {
				rv -= ulp(rv);
#ifndef Sudden_Underflow
				if (!rv)
					goto undfl;
#endif
			}
			dsign = 1 - dsign;
			break;
		}
		if ((aadj = ratio(delta, bs)) <= 2.) {
			if (dsign)
				aadj = aadj1 = 1.;
			else if (word1(rv) || word0(rv) & Bndry_mask) {
#ifndef Sudden_Underflow
				if (word1(rv) == Tiny1 && !word0(rv))
					goto undfl;
#endif
				aadj = 1.;
				aadj1 = -1.;
			} else {
				/* special case -- power of FLT_RADIX to be */
				/* rounded down... */

				if (aadj < 2. / FLT_RADIX)
					aadj = 1. / FLT_RADIX;
				else
					aadj *= 0.5;
				aadj1 = -aadj;
			}
		} else {
			aadj *= 0.5;
			aadj1 = dsign ? aadj : -aadj;
			if (FLT_ROUNDS == 0)
				aadj1 += 0.5;
		}
		y = word0(rv) & Exp_mask;

		/* Check for overflow */

		if (y == Exp_msk1 * (DBL_MAX_EXP + Bias - 1)) {
			rv0 = rv;
			word0(rv) -= P * Exp_msk1;
			adj = aadj1 * ulp(rv);
			rv += adj;
			if ((word0(rv) & Exp_mask) >= 
			    Exp_msk1 * (DBL_MAX_EXP + Bias - P)) {
				if (word0(rv0) == Big0 && word1(rv0) == Big1)
					goto ovfl;
				word0(rv) = Big0;
				word1(rv) = Big1;
				goto cont;
			} else
				word0(rv) += P * Exp_msk1;
		} else {
#ifdef Sudden_Underflow
			if ((word0(rv) & Exp_mask) <= P * Exp_msk1) {
				rv0 = rv;
				word0(rv) += P * Exp_msk1;
				adj = aadj1 * ulp(rv);
				rv += adj;
				if ((word0(rv) & Exp_mask) <= P * Exp_msk1) {
					if (word0(rv0) == Tiny0
					     && word1(rv0) == Tiny1)
						goto undfl;
					word0(rv) = Tiny0;
					word1(rv) = Tiny1;
					goto cont;
				} else
					word0(rv) -= P * Exp_msk1;
			} else {
				adj = aadj1 * ulp(rv);
				rv += adj;
			}
#else
			/* Compute adj so that the IEEE rounding rules will
			 * correctly round rv + adj in some half-way cases.
			 * If rv * ulp(rv) is denormalized (i.e.,
			 * y <= (P-1)*Exp_msk1), we must adjust aadj to avoid
			 * trouble from bits lost to denormalization;
			 * example: 1.2e-307 .
			 */
			if (y <= (P - 1) * Exp_msk1 && aadj >= 1.) {
				aadj1 = (double)(int)(aadj + 0.5);
				if (!dsign)
					aadj1 = -aadj1;
			}
			adj = aadj1 * ulp(rv);
			rv += adj;
#endif
		}
		z = word0(rv) & Exp_mask;
		if (!scale)
			if (y == z) {
				/* Can we stop now? */
				L = aadj;
				aadj -= L;
				/* The tolerances below are conservative. */
				if (dsign || word1(rv) || word0(rv) & Bndry_mask) {
					if (aadj < .4999999 || aadj > .5000001)
						break;
				} else if (aadj < .4999999 / FLT_RADIX)
					break;
			}
cont:
		Bfree(bb);
		Bfree(bd);
		Bfree(bs);
		Bfree(delta);
	}
	if (scale) {
		if ((word0(rv) & Exp_mask) <= P * Exp_msk1
		     && word1(rv) & 1
		     && dsign != 2)
			if (dsign)
				rv += ulp(rv);
			else
				word1(rv) &= ~1;
		word0(rv0) = Exp_1 - P * Exp_msk1;
		word1(rv0) = 0;
		rv *= rv0;
	}
retfree:
	Bfree(bb);
	Bfree(bd);
	Bfree(bs);
	Bfree(bd0);
	Bfree(delta);
ret:
	if (se)
		*se = (char *)s;
	return sign ? -rv : rv;
}

static int	
quorem(Bigint *b, Bigint *S)
{
	int	n;
	long borrow, y;
	unsigned  long carry, q, ys;
	unsigned  long * bx, *bxe, *sx, *sxe;
	long z;
	unsigned  long si, zs;

	n = S->wds;
	if (b->wds < n)
		return 0;
	sx = S->x;
	sxe = sx + --n;
	bx = b->x;
	bxe = bx + n;
	q = *bxe / (*sxe + 1);	/* ensure q <= true quotient */
	if (q) {
		borrow = 0;
		carry = 0;
		do {
			si = *sx++;
			ys = (si & 0xffff) * q + carry;
			zs = (si >> 16) * q + (ys >> 16);
			carry = zs >> 16;
			y = (*bx & 0xffff) - (ys & 0xffff) + borrow;
			borrow = y >> 16;
			Sign_Extend(borrow, y);
			z = (*bx >> 16) - (zs & 0xffff) + borrow;
			borrow = z >> 16;
			Sign_Extend(borrow, z);
			Storeinc(bx, z, y);
		} while (sx <= sxe);
		if (!*bxe) {
			bx = b->x;
			while (--bxe > bx && !*bxe)
				--n;
			b->wds = n;
		}
	}
	if (cmp(b, S) >= 0) {
		q++;
		borrow = 0;
		carry = 0;
		bx = b->x;
		sx = S->x;
		do {
			si = *sx++;
			ys = (si & 0xffff) + carry;
			zs = (si >> 16) + (ys >> 16);
			carry = zs >> 16;
			y = (*bx & 0xffff) - (ys & 0xffff) + borrow;
			borrow = y >> 16;
			Sign_Extend(borrow, y);
			z = (*bx >> 16) - (zs & 0xffff) + borrow;
			borrow = z >> 16;
			Sign_Extend(borrow, z);
			Storeinc(bx, z, y);
		} while (sx <= sxe);
		bx = b->x;
		bxe = bx + n;
		if (!*bxe) {
			while (--bxe > bx && !*bxe)
				--n;
			b->wds = n;
		}
	}
	return q;
}

static char	*
rv_alloc(int i)
{
	int	j, k, *r;

	j = sizeof(unsigned  long);
	for (k = 0; 
	    sizeof(Bigint) - sizeof(unsigned  long) - sizeof(int) + j <= i; 
	    j <<= 1)
		k++;
	r = (int * )Balloc(k);
	*r = k;
	return
	    (char *)(r + 1);
}

static char	*
nrv_alloc(char *s, char **rve, int n)
{
	char	*rv, *t;

	t = rv = rv_alloc(n);
	while (*t = *s++) 
		t++;
	if (rve)
		*rve = t;
	return rv;
}

/* freedtoa(s) must be used to free values s returned by dtoa
 * when MULTIPLE_THREADS is #defined.  It should be used in all cases,
 * but for consistency with earlier versions of dtoa, it is optional
 * when MULTIPLE_THREADS is not defined.
 */

void
freedtoa(char *s)
{
	Bigint * b = (Bigint * )((int *)s - 1);
	b->maxwds = 1 << (b->k = *(int * )b);
	Bfree(b);
}

/* dtoa for IEEE arithmetic (dmg): convert double to ASCII string.
 *
 * Inspired by "How to Print Floating-Point Numbers Accurately" by
 * Guy L. Steele, Jr. and Jon L. White [Proc. ACM SIGPLAN '90, pp. 92-101].
 *
 * Modifications:
 *	1. Rather than iterating, we use a simple numeric overestimate
 *	   to determine k = floor(log10(d)).  We scale relevant
 *	   quantities using O(log2(k)) rather than O(k) multiplications.
 *	2. For some modes > 2 (corresponding to ecvt and fcvt), we don't
 *	   try to generate digits strictly left to right.  Instead, we
 *	   compute with fewer bits and propagate the carry if necessary
 *	   when rounding the final digit up.  This is often faster.
 *	3. Under the assumption that input will be rounded nearest,
 *	   mode 0 renders 1e23 as 1e23 rather than 9.999999999999999e22.
 *	   That is, we allow equality in stopping tests when the
 *	   round-nearest rule will give the same floating-point value
 *	   as would satisfaction of the stopping test with strict
 *	   inequality.
 *	4. We remove common factors of powers of 2 from relevant
 *	   quantities.
 *	5. When converting floating-point integers less than 1e16,
 *	   we use floating-point arithmetic rather than resorting
 *	   to multiple-precision integers.
 *	6. When asked to produce fewer than 15 digits, we first try
 *	   to get by with floating-point arithmetic; we resort to
 *	   multiple-precision integer arithmetic only if we cannot
 *	   guarantee that the floating-point calculation has given
 *	   the correctly rounded result.  For k requested digits and
 *	   "uniformly" distributed input, the probability is
 *	   something like 10^(k-15) that we must resort to the long
 *	   calculation.
 */

char	*
dtoa(double d, int mode, int ndigits, int *decpt, int *sign, char **rve)
{
	/*	Arguments ndigits, decpt, sign are similar to those
	of ecvt and fcvt; trailing zeros are suppressed from
	the returned string.  If not null, *rve is set to point
	to the end of the return value.  If d is +-Infinity or NaN,
	then *decpt is set to 9999.

	mode:
		0 ==> shortest string that yields d when read in
			and rounded to nearest.
		1 ==> like 0, but with Steele & White stopping rule;
			e.g. with IEEE P754 arithmetic , mode 0 gives
			1e23 whereas mode 1 gives 9.999999999999999e22.
		2 ==> max(1,ndigits) significant digits.  This gives a
			return value similar to that of ecvt, except
			that trailing zeros are suppressed.
		3 ==> through ndigits past the decimal point.  This
			gives a return value similar to that from fcvt,
			except that trailing zeros are suppressed, and
			ndigits can be negative.
		4-9 should give the same return values as 2-3, i.e.,
			4 <= mode <= 9 ==> same return as mode
			2 + (mode & 1).  These modes are mainly for
			debugging; often they run slower but sometimes
			faster than modes 2-3.
		4,5,8,9 ==> left-to-right digit generation.
		6-9 ==> don't try fast floating-point estimate
			(if applicable).

		Values of mode other than 0-9 are treated as mode 0.

		Sufficient space is allocated to the return value
		to hold the suppressed trailing zeros.
	*/

	int	bbits, b2, b5, be, dig, i, ieps, ilim, ilim0, ilim1,
	j, j1, k, k0, k_check, leftright, m2, m5, s2, s5,
	spec_case, try_quick;
	long L;
#ifndef Sudden_Underflow
	int	denorm;
	unsigned  long x;
#endif
	Bigint * b, *b1, *delta, *mlo, *mhi, *S;
	double	d2, ds, eps;
	char	*s, *s0;

	if (word0(d) & Sign_bit) {
		/* set sign for everything, including 0's and NaNs */
		*sign = 1;
		word0(d) &= ~Sign_bit;	/* clear sign bit */
	} else
		*sign = 0;

	if ((word0(d) & Exp_mask) == Exp_mask) {
		/* Infinity or NaN */
		*decpt = 9999;
		if (!word1(d) && !(word0(d) & 0xfffff))
			return nrv_alloc("Infinity", rve, 8);
		return nrv_alloc("NaN", rve, 3);
	}
	if (!d) {
		*decpt = 1;
		return nrv_alloc("0", rve, 1);
	}

	b = d2b(d, &be, &bbits);
#ifdef Sudden_Underflow
	i = (int)(word0(d) >> Exp_shift1 & (Exp_mask >> Exp_shift1));
#else
	if (i = (int)(word0(d) >> Exp_shift1 & (Exp_mask >> Exp_shift1))) {
#endif
		word0(d2) = (word0(d) & Frac_mask1) | Exp_11;
		word1(d2) = word1(d);

		/* log(x)	~=~ log(1.5) + (x-1.5)/1.5
		 * log10(x)	 =  log(x) / log(10)
		 *		~=~ log(1.5)/log(10) + (x-1.5)/(1.5*log(10))
		 * log10(d) = (i-Bias)*log(2)/log(10) + log10(d2)
		 *
		 * This suggests computing an approximation k to log10(d) by
		 *
		 * k = (i - Bias)*0.301029995663981
		 *	+ ( (d2-1.5)*0.289529654602168 + 0.176091259055681 );
		 *
		 * We want k to be too large rather than too small.
		 * The error in the first-order Taylor series approximation
		 * is in our favor, so we just round up the constant enough
		 * to compensate for any error in the multiplication of
		 * (i - Bias) by 0.301029995663981; since |i - Bias| <= 1077,
		 * and 1077 * 0.30103 * 2^-52 ~=~ 7.2e-14,
		 * adding 1e-13 to the constant term more than suffices.
		 * Hence we adjust the constant term to 0.1760912590558.
		 * (We could get a more accurate k by invoking log10,
		 *  but this is probably not worthwhile.)
		 */

		i -= Bias;
#ifndef Sudden_Underflow
		denorm = 0;
	} else {
		/* d is denormalized */

		i = bbits + be + (Bias + (P - 1) - 1);
		x = i > 32  ? word0(d) << 64 - i | word1(d) >> i - 32
		     : word1(d) << 32 - i;
		d2 = x;
		word0(d2) -= 31 * Exp_msk1; /* adjust exponent */
		i -= (Bias + (P - 1) - 1) + 1;
		denorm = 1;
	}
#endif
	ds = (d2 - 1.5) * 0.289529654602168 + 0.1760912590558 + i * 0.301029995663981;
	k = (int)ds;
	if (ds < 0. && ds != k)
		k--;	/* want k = floor(ds) */
	k_check = 1;
	if (k >= 0 && k <= Ten_pmax) {
		if (d < tens[k])
			k--;
		k_check = 0;
	}
	j = bbits - i - 1;
	if (j >= 0) {
		b2 = 0;
		s2 = j;
	} else {
		b2 = -j;
		s2 = 0;
	}
	if (k >= 0) {
		b5 = 0;
		s5 = k;
		s2 += k;
	} else {
		b2 -= k;
		b5 = -k;
		s5 = 0;
	}
	if (mode < 0 || mode > 9)
		mode = 0;
	try_quick = 1;
	if (mode > 5) {
		mode -= 4;
		try_quick = 0;
	}
	leftright = 1;
	switch (mode) {
	case 0:
	case 1:
		ilim = ilim1 = -1;
		i = 18;
		ndigits = 0;
		break;
	case 2:
		leftright = 0;
		/* no break */
	case 4:
		if (ndigits <= 0)
			ndigits = 1;
		ilim = ilim1 = i = ndigits;
		break;
	case 3:
		leftright = 0;
		/* no break */
	case 5:
		i = ndigits + k + 1;
		ilim = i;
		ilim1 = i - 1;
		if (i <= 0)
			i = 1;
	}
	s = s0 = rv_alloc(i);

	if (ilim >= 0 && ilim <= Quick_max && try_quick) {

		/* Try to get by with floating-point arithmetic. */

		i = 0;
		d2 = d;
		k0 = k;
		ilim0 = ilim;
		ieps = 2; /* conservative */
		if (k > 0) {
			ds = tens[k&0xf];
			j = k >> 4;
			if (j & Bletch) {
				/* prevent overflows */
				j &= Bletch - 1;
				d /= bigtens[n_bigtens-1];
				ieps++;
			}
			for (; j; j >>= 1, i++)
				if (j & 1) {
					ieps++;
					ds *= bigtens[i];
				}
			d /= ds;
		} else if (j1 = -k) {
			d *= tens[j1 & 0xf];
			for (j = j1 >> 4; j; j >>= 1, i++)
				if (j & 1) {
					ieps++;
					d *= bigtens[i];
				}
		}
		if (k_check && d < 1. && ilim > 0) {
			if (ilim1 <= 0)
				goto fast_failed;
			ilim = ilim1;
			k--;
			d *= 10.;
			ieps++;
		}
		eps = ieps * d + 7.;
		word0(eps) -= (P - 1) * Exp_msk1;
		if (ilim == 0) {
			S = mhi = 0;
			d -= 5.;
			if (d > eps)
				goto one_digit;
			if (d < -eps)
				goto no_digits;
			goto fast_failed;
		}
		/* Generate ilim digits, then fix them up. */
		eps *= tens[ilim-1];
		for (i = 1; ; i++, d *= 10.) {
			L = d;
			d -= L;
			*s++ = '0' + (int)L;
			if (i == ilim) {
				if (d > 0.5 + eps)
					goto bump_up;
				else if (d < 0.5 - eps) {
					while (*--s == '0')
						;
					s++;
					goto ret1;
				}
				break;
			}
		}
fast_failed:
		s = s0;
		d = d2;
		k = k0;
		ilim = ilim0;
	}

	/* Do we have a "small" integer? */

	if (be >= 0 && k <= Int_max) {
		/* Yes. */
		ds = tens[k];
		if (ndigits < 0 && ilim <= 0) {
			S = mhi = 0;
			if (ilim < 0 || d <= 5 * ds)
				goto no_digits;
			goto one_digit;
		}
		for (i = 1; ; i++) {
			L = d / ds;
			d -= L * ds;
			*s++ = '0' + (int)L;
			if (i == ilim) {
				d += d;
				if (d > ds || d == ds && L & 1) {
bump_up:
					while (*--s == '9')
						if (s == s0) {
							k++;
							*s = '0';
							break;
						}
					++ * s++;
				}
				break;
			}
			if (!(d *= 10.))
				break;
		}
		goto ret1;
	}

	m2 = b2;
	m5 = b5;
	mhi = mlo = 0;
	if (leftright) {
		if (mode < 2) {
			i = 
#ifndef Sudden_Underflow
			    denorm ? be + (Bias + (P - 1) - 1 + 1) : 
#endif
			    1 + P - bbits;
		} else {
			j = ilim - 1;
			if (m5 >= j)
				m5 -= j;
			else {
				s5 += j -= m5;
				b5 += j;
				m5 = 0;
			}
			if ((i = ilim) < 0) {
				m2 -= i;
				i = 0;
			}
		}
		b2 += i;
		s2 += i;
		mhi = i2b(1);
	}
	if (m2 > 0 && s2 > 0) {
		i = m2 < s2 ? m2 : s2;
		b2 -= i;
		m2 -= i;
		s2 -= i;
	}
	if (b5 > 0) {
		if (leftright) {
			if (m5 > 0) {
				mhi = pow5mult(mhi, m5);
				b1 = mult(mhi, b);
				Bfree(b);
				b = b1;
			}
			if (j = b5 - m5)
				b = pow5mult(b, j);
		} else
			b = pow5mult(b, b5);
	}
	S = i2b(1);
	if (s5 > 0)
		S = pow5mult(S, s5);

	/* Check for special case that d is a normalized power of 2. */

	spec_case = 0;
	if (mode < 2) {
		if (!word1(d) && !(word0(d) & Bndry_mask)
#ifndef Sudden_Underflow
		     && word0(d) & Exp_mask
#endif
		    ) {
			/* The special case */
			b2 += Log2P;
			s2 += Log2P;
			spec_case = 1;
		}
	}

	/* Arrange for convenient computation of quotients:
	 * shift left if necessary so divisor has 4 leading 0 bits.
	 *
	 * Perhaps we should just compute leading 28 bits of S once
	 * and for all and pass them and a shift to quorem, so it
	 * can do shifts and ors to compute the numerator for q.
	 */
	if (i = ((s5 ? 32 - hi0bits(S->x[S->wds-1]) : 1) + s2) & 0x1f)
		i = 32 - i;
	if (i > 4) {
		i -= 4;
		b2 += i;
		m2 += i;
		s2 += i;
	} else if (i < 4) {
		i += 28;
		b2 += i;
		m2 += i;
		s2 += i;
	}
	if (b2 > 0)
		b = lshift(b, b2);
	if (s2 > 0)
		S = lshift(S, s2);
	if (k_check) {
		if (cmp(b, S) < 0) {
			k--;
			b = multadd(b, 10, 0);	/* we botched the k estimate */
			if (leftright)
				mhi = multadd(mhi, 10, 0);
			ilim = ilim1;
		}
	}
	if (ilim <= 0 && mode > 2) {
		if (ilim < 0 || cmp(b, S = multadd(S, 5, 0)) <= 0) {
			/* no digits, fcvt style */
no_digits:
			k = -1 - ndigits;
			goto ret;
		}
one_digit:
		*s++ = '1';
		k++;
		goto ret;
	}
	if (leftright) {
		if (m2 > 0)
			mhi = lshift(mhi, m2);

		/* Compute mlo -- check for special case
		 * that d is a normalized power of 2.
		 */

		mlo = mhi;
		if (spec_case) {
			mhi = Balloc(mhi->k);
			Bcopy(mhi, mlo);
			mhi = lshift(mhi, Log2P);
		}

		for (i = 1; ; i++) {
			dig = quorem(b, S) + '0';
			/* Do we yet have the shortest decimal string
			 * that will round to d?
			 */
			j = cmp(b, mlo);
			delta = diff(S, mhi);
			j1 = delta->sign ? 1 : cmp(b, delta);
			Bfree(delta);
			if (j1 == 0 && !mode && !(word1(d) & 1)) {
				if (dig == '9')
					goto round_9_up;
				if (j > 0)
					dig++;
				*s++ = dig;
				goto ret;
			}
			if (j < 0 || j == 0 && !mode
			     && !(word1(d) & 1)
			    ) {
				if (j1 > 0) {
					b = lshift(b, 1);
					j1 = cmp(b, S);
					if ((j1 > 0 || j1 == 0 && dig & 1)
					     && dig++ == '9')
						goto round_9_up;
				}
				*s++ = dig;
				goto ret;
			}
			if (j1 > 0) {
				if (dig == '9') { /* possible if i == 1 */
round_9_up:
					*s++ = '9';
					goto roundoff;
				}
				*s++ = dig + 1;
				goto ret;
			}
			*s++ = dig;
			if (i == ilim)
				break;
			b = multadd(b, 10, 0);
			if (mlo == mhi)
				mlo = mhi = multadd(mhi, 10, 0);
			else {
				mlo = multadd(mlo, 10, 0);
				mhi = multadd(mhi, 10, 0);
			}
		}
	} else
		for (i = 1; ; i++) {
			*s++ = dig = quorem(b, S) + '0';
			if (i >= ilim)
				break;
			b = multadd(b, 10, 0);
		}

	/* Round off last digit */

	b = lshift(b, 1);
	j = cmp(b, S);
	if (j > 0 || j == 0 && dig & 1) {
roundoff:
		while (*--s == '9')
			if (s == s0) {
				k++;
				*s++ = '1';
				goto ret;
			}
		++ * s++;
	} else {
		while (*--s == '0')
			;
		s++;
	}
ret:
	Bfree(S);
	if (mhi) {
		if (mlo && mlo != mhi)
			Bfree(mlo);
		Bfree(mhi);
	}
ret1:
	Bfree(b);
	*s = 0;
	*decpt = k + 1;
	if (rve)
		*rve = s;
	return s0;
}

