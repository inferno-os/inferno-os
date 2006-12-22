#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "raise.h"
#include "pool.h"

#define OP(fn)	void fn(void)
#define B(r)	*((BYTE*)(R.r))
#define W(r)	*((WORD*)(R.r))
#define F(r)	*((REAL*)(R.r))
#define V(r)	*((LONG*)(R.r))
#define	S(r)	*((String**)(R.r))
#define	A(r)	*((Array**)(R.r))
#define	L(r)	*((List**)(R.r))
#define P(r)	*((WORD**)(R.r))
#define C(r)	*((Channel**)(R.r))
#define T(r)	*((void**)(R.r))

OP(indc)
{
	int l;
	ulong v;
	String *ss;

	v = W(m);
	ss = S(s);

	if(ss == H)
		error(exNilref);

	l = ss->len;
	if(l < 0) {
		if(v >= -l)
e:			error(exBounds);
		l = ss->Srune[v];			
	}
	else {
		if(v >= l)
			goto e;
		l = ss->Sascii[v];			
	}
	W(d) = l;
}

OP(insc)
{
	ulong v;
	int l, r, expand;
	String *ss, *ns, **sp;

	r = W(s);
	v = W(m);
	ss = S(d);

	expand = r >= Runeself;

	if(ss == H) {
		ss = newstring(0);
		if(expand) {
			l = 0;
			ss->max /= sizeof(Rune);
			goto r;
		}
	}
	else
	if(D2H(ss)->ref > 1 || (expand && ss->len > 0))
		ss = splitc(R.d, expand);

	l = ss->len;
	if(l < 0 || expand) {
		l = -l;
r:
		if(v < l)
			ss->Srune[v] = r;
		else
		if(v == l && v < ss->max) {
			ss->len = -(v+1);
			ss->Srune[v] = r;
		}
		else {
			if(v != l)
				error(exBounds);
			ns = newstring((v + 1 + v/4)*sizeof(Rune));
			memmove(ns->Srune, ss->Srune, -ss->len*sizeof(Rune));
			ns->Srune[v] = r;
			ns->len = -(v+1);
			ns->max /= sizeof(Rune);
			ss = ns;
		}
	}
	else {
		if(v < l)
			ss->Sascii[v] = r;
		else
		if(v == l && v < ss->max) {
			ss->len = v+1;
			ss->Sascii[v] = r;
		}
		else {
			if(v != l)
				error(exBounds);
			ns = newstring(v + 1 + v/4);
			memmove(ns->Sascii, ss->Sascii, l);
			ns->Sascii[v] = r;
			ns->len = v+1;
			ss = ns;
		}
	}
	if(ss != S(d)) {
		sp = R.d;
		destroy(*sp);
		*sp = ss;
	}
}

String*
slicer(ulong start, ulong v, String *ds)
{
	String *ns;
	int l, nc;

	if(ds == H) {
		if(start == 0 && v == 0)
			return H;

		error(exBounds);
	}

	nc = v - start;
	if(ds->len < 0) {
		l = -ds->len;
		if(v < start || v > l)
			error(exBounds);
		ns = newrunes(nc);
		memmove(ns->Srune, &ds->Srune[start], nc*sizeof(Rune));
	}
	else {
		l = ds->len;
		if(v < start || v > l)
			error(exBounds);
		ns = newstring(nc);
		memmove(ns->Sascii, &ds->Sascii[start], nc);
	}

	return ns;
}

OP(slicec)
{
	String *ns, **sp;

	ns = slicer(W(s), W(m), S(d));
	sp = R.d;
	destroy(*sp);
	*sp = ns;
}

void
cvtup(Rune *r, String *s)
{
	uchar *bp, *ep;

	bp = (uchar*)s->Sascii;
	ep = bp + s->len;
	while(bp < ep)
		*r++ = *bp++;
}

String*
addstring(String *s1, String *s2, int append)
{
	Rune *r;
	String *ns;
	int l, l1, l2;

	if(s1 == H) {
		if(s2 == H)
			return H;
		return stringdup(s2);
	}
	if(D2H(s1)->ref > 1)
		append = 0;
	if(s2 == H) {
		if(append)
			return s1;
		return stringdup(s1);
	}

	if(s1->len < 0) {
		l1 = -s1->len;
		if(s2->len < 0) 
			l = l1 - s2->len;
		else
			l = l1 + s2->len;
		if(append && l <= s1->max)
			ns = s1;
		else {
			ns = newrunes(append? (l+l/4): l);
			memmove(ns->Srune, s1->Srune, l1*sizeof(Rune));
		}
		ns->len = -l;
		r = &ns->Srune[l1];
		if(s2->len < 0)
			memmove(r, s2->Srune, -s2->len*sizeof(Rune));
		else
			cvtup(r, s2);

		return ns;
	}

	if(s2->len < 0) {
		l2 = -s2->len;
		l = s1->len + l2;
		ns = newrunes(append? (l+l/4): l);
		ns->len = -l;
		cvtup(ns->Srune, s1);
		memmove(&ns->Srune[s1->len], s2->Srune, l2*sizeof(Rune));
		return ns;
	}

	l1 = s1->len;
	l = l1 + s2->len;
	if(append && l <= s1->max)
		ns = s1;
	else {
		ns = newstring(append? (l+l/4): l);
		memmove(ns->Sascii, s1->Sascii, l1);
	}
	ns->len = l;
	memmove(ns->Sascii+l1, s2->Sascii, s2->len);

	return ns;
}

OP(addc)
{
	String *ns, **sp;

	ns = addstring(S(m), S(s), R.m == R.d);

	sp = R.d;
	if(ns != *sp) {
		destroy(*sp);
		*sp = ns;
	}
}

OP(cvtca)
{
	int l;
	Rune *r;
	char *p;
	String *ss;
 	Array *a, **ap;

	ss = S(s);
	if(ss == H) {
		a = mem2array(nil, 0);
		goto r;
	}
	if(ss->len < 0) {
		l = -ss->len;
		a = mem2array(nil, runenlen(ss->Srune, l));
		p = (char*)a->data;
		r = ss->Srune;
		while(l--)
			p += runetochar(p, r++);	
		goto r;
	}
	a = mem2array(ss->Sascii, ss->len);

r:	ap = R.d;
	destroy(*ap);
	*ap = a;
}

OP(cvtac)
{
	Array *a;
	String *ds, **dp;

	ds = H;
	a = A(s);
	if(a != H)
		ds = c2string((char*)a->data, a->len);

	dp = R.d;
	destroy(*dp);
	*dp = ds;
}

OP(lenc)
{
	int l;
	String *ss;

	l = 0;
	ss = S(s);
	if(ss != H) {
		l = ss->len;
		if(l < 0)
			l = -l;
	}
	W(d) = l;
}

OP(cvtcw)
{
	String *s;

	s = S(s);
	if(s == H)
		W(d) = 0;
	else
	if(s->len < 0)
		W(d) = strtol(string2c(s), nil, 10);
	else {
		s->Sascii[s->len] = '\0';
		W(d) = strtol(s->Sascii, nil, 10);
	}
}

OP(cvtcf)
{
	String *s;

	s = S(s);
	if(s == H)
		F(d) = 0.0;
	else
	if(s->len < 0)
		F(d) = strtod(string2c(s), nil);
	else {
		s->Sascii[s->len] = '\0';
		F(d) = strtod(s->Sascii, nil);
	}
}

OP(cvtwc)
{
	String *ds, **dp;

	ds = newstring(16);
	ds->len = sprint(ds->Sascii, "%d", W(s));

	dp = R.d;
	destroy(*dp);
	*dp = ds;
}

OP(cvtlc)
{
	String *ds, **dp;

	ds = newstring(16);
	ds->len = sprint(ds->Sascii, "%lld", V(s));
	
	dp = R.d;
	destroy(*dp);
	*dp = ds;
}

OP(cvtfc)
{
	String *ds, **dp;

	ds = newstring(32);
	ds->len = sprint(ds->Sascii, "%g", F(s));	
	dp = R.d;
	destroy(*dp);
	*dp = ds;
}

char*
string2c(String *s)
{
	char *p;
	int c, l, nc;
	Rune *r, *er;

	if(s == H)
		return "";

	if(s->len >= 0) {
		s->Sascii[s->len] = '\0';
		return s->Sascii;
	}

	nc = -s->len;
	l = (nc * UTFmax) + UTFmax;
	if(s->tmp == nil || msize(s->tmp) < l) {
		free(s->tmp);
		s->tmp = malloc(l);
		if(s->tmp == nil)
			error(exNomem);
	}

	p = s->tmp;
	r = s->Srune;
	er = r + nc;
	while(r < er) {
		c = *r++;
		if(c < Runeself)
			*p++ = c;
		else
			p += runetochar(p, r-1);
	}

	*p = 0;

	return s->tmp;
}

String*
c2string(char *cs, int len)
{
	uchar *p;
	char *ecs;
	String *s;
	Rune *r, junk;
	int c, nc, isrune;

	isrune = 0;
	ecs = cs+len;
	p = (uchar*)cs;
	while(len--) {
		c = *p++;
		if(c >= Runeself) {
			isrune = 1;
			break;
		}
	}

	if(isrune == 0) {
		nc = ecs - cs;
		s = newstring(nc);
		memmove(s->Sascii, cs, nc);
		return s;
	}

	p--;
	nc = p - (uchar*)cs;
	while(p < (uchar*)ecs) {
		c = *p;
		if(c < Runeself)
			p++;
		else if(p+UTFmax<=(uchar*)ecs || fullrune((char*)p, (uchar*)ecs-p))
			p += chartorune(&junk, (char*)p);
		else
			break;
		nc++;
	}
	s = newrunes(nc);
	r = s->Srune;
	while(nc--)
		cs += chartorune(r++, cs);

	return s;
}

String*
newstring(int nb)
{
	Heap *h;
	String *s;

	h = nheap(sizeof(String)+nb);
	h->t = &Tstring;
	Tstring.ref++;
	s = H2D(String*, h);
	s->tmp = nil;
	s->len = nb;
	s->max = hmsize(h) - (sizeof(String)+sizeof(Heap));
	return s;
}

String*
newrunes(int nr)
{
	Heap *h;
	String *s;

	if(nr == 0)
		return newstring(nr);
	if(nr < 0)
		nr = -nr;
	h = nheap(sizeof(String)+nr*sizeof(Rune));
	h->t = &Tstring;
	Tstring.ref++;
	s = H2D(String*, h);
	s->tmp = nil;
	s->len = -nr;
	s->max = (hmsize(h) - (sizeof(String)+sizeof(Heap)))/sizeof(Rune);
	return s;
}

String*
stringdup(String *s)
{
	String *ns;

	if(s == H)
		return H;

	if(s->len >= 0) {
		ns = newstring(s->len);
		memmove(ns->Sascii, s->Sascii, s->len);
		return ns;
	}

	ns = newrunes(-s->len);
	memmove(ns->Srune, s->Srune,-s->len*sizeof(Rune));

	return ns;
}

int
stringcmp(String *s1, String *s2)
{
	Rune *r1, *r2;
	char *a1, *a2;
	int v, n, n1, n2, c1, c2;
	static String snil = { 0, 0, nil };

	if(s1 == H)
		s1 = &snil;
	if(s2 == H)
		s2 = &snil;

	if(s1 == s2)
		return 0;

	v = 0;
	n1 = s1->len;
	if(n1 < 0) {
		n1 = -n1;
		v |= 1;
	}
	n2 = s2->len;
	if(n2 < 0) {
		n2 = -n2;
		v |= 2;
	}

	n = n1;
	if(n2 < n)
		n = n2;

	switch(v) {
	case 0:		/* Ascii Ascii */
		n = memcmp(s1->Sascii, s2->Sascii, n);
		if(n == 0)
			n = n1 - n2;
		return n;
	case 1:		/* Rune Ascii */
		r1 = s1->Srune;
		a2 = s2->Sascii;
		while(n > 0) {
			c1 = *r1++;
			c2 = *a2++;
			if(c1 != c2)
				goto ne;
			n--;
		}
		break;
	case 2:		/* Ascii Rune */
		a1 = s1->Sascii;
		r2 = s2->Srune;
		while(n > 0) {
			c1 = *a1++;
			c2 = *r2++;
			if(c1 != c2)
				goto ne;
			n--;
		}
		break;
	case 3:		/* Rune Rune */
		r1 = s1->Srune;
		r2 = s2->Srune;
		while(n > 0) {
			c1 = *r1++;
			c2 = *r2++;
			if(c1 != c2)
				goto ne;
			n--;
		}
		break;
	}
	return n1 - n2;

ne:	if(c1 < c2)
		return -1;
	return 1;
}

String*
splitc(String **s, int expand)
{
	String *ss, *ns;

	ss = *s;
	if(expand && ss->len > 0) {
		ns = newrunes(ss->len);
		cvtup(ns->Srune, ss);
	}
	else
		ns = stringdup(ss);

	destroy(ss);
	*s = ns;
	return ns;
}
