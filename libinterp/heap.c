#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "pool.h"
#include "raise.h"

void	freearray(Heap*, int);
void	freelist(Heap*, int);
void	freemodlink(Heap*, int);
void	freechan(Heap*, int);
Type	Tarray = { 1, freearray, markarray, sizeof(Array) };
Type	Tstring = { 1, freestring, noptrs, sizeof(String) };
Type	Tlist = { 1, freelist, marklist, sizeof(List) };
Type	Tmodlink = { 1, freemodlink, markheap, -1, 1, 0, 0, { 0x80 } };
Type	Tchannel = { 1, freechan, markheap, sizeof(Channel), 1,0,0,{0x80} };
Type	Tptr = { 1, 0, markheap, sizeof(WORD*), 1, 0, 0, { 0x80 } };
Type	Tbyte = { 1, 0, 0, 1 };
Type Tword = { 1, 0, 0, sizeof(WORD) };
Type Tlong = { 1, 0, 0, sizeof(LONG) };
Type Treal = { 1, 0, 0, sizeof(REAL) };

extern	Pool*	heapmem;
extern	int	mutator;

void	(*heapmonitor)(int, void*, ulong);

#define	BIT(bt, nb)	(bt & (1<<nb))

void
freeptrs(void *v, Type *t)
{
	int c;
	WORD **w, *x;
	uchar *p, *ep;

	if(t->np == 0)
		return;

	w = (WORD**)v;
	p = t->map;
	ep = p + t->np;
	while(p < ep) {
		c = *p;
		if(c != 0) {
 			if(BIT(c, 0) && (x = w[7]) != H) destroy(x);
			if(BIT(c, 1) && (x = w[6]) != H) destroy(x);
 			if(BIT(c, 2) && (x = w[5]) != H) destroy(x);
			if(BIT(c, 3) && (x = w[4]) != H) destroy(x);
			if(BIT(c, 4) && (x = w[3]) != H) destroy(x);
			if(BIT(c, 5) && (x = w[2]) != H) destroy(x);
			if(BIT(c, 6) && (x = w[1]) != H) destroy(x);
			if(BIT(c, 7) && (x = w[0]) != H) destroy(x);
		}
		p++;
		w += 8;
	}
}

/*
void
nilptrs(void *v, Type *t)
{
	int c, i;
	WORD **w;
	uchar *p, *ep;

	w = (WORD**)v;
	p = t->map;
	ep = p + t->np;
	while(p < ep) {
		c = *p;
		for(i = 0; i < 8; i++){
			if(BIT(c, 7)) *w = H;
			c <<= 1;
			w++;
		}
		p++;
	}
}
*/

void
freechan(Heap *h, int swept)
{
	Channel *c;

	USED(swept);
	c = H2D(Channel*, h);
	if(c->mover == movtmp)
		freetype(c->mid.t);
	killcomm(&c->send);
	killcomm(&c->recv);
	if (!swept && c->buf != H)
		destroy(c->buf);
}

void
freestring(Heap *h, int swept)
{
	String *s;

	USED(swept);
	s = H2D(String*, h);
	if(s->tmp != nil)
		free(s->tmp);
}

void
freearray(Heap *h, int swept)
{
	int i;
	Type *t;
	uchar *v;
	Array *a;

	a = H2D(Array*, h);
	t = a->t;

	if(!swept) {
		if(a->root != H)
			destroy(a->root);
		else
		if(t->np != 0) {
			v = a->data;
			for(i = 0; i < a->len; i++) {
				freeptrs(v, t);
				v += t->size;
			}
		}
	}
	if(t->ref-- == 1) {
		free(t->initialize);
		free(t);
	}
}

void
freelist(Heap *h, int swept)
{
	Type *t;
	List *l;
	Heap *th;

	l = H2D(List*, h);
	t = l->t;

	if(t != nil) {
		if(!swept && t->np)
			freeptrs(l->data, t);
		t->ref--;
		if(t->ref == 0) {
			free(t->initialize);
			free(t);
		}
	}
	if(swept)
		return;
	l = l->tail;
	while(l != (List*)H) {
		t = l->t;
		th = D2H((ulong)l);
		if(th->ref-- != 1)
			break;
		th->t->ref--;	/* should be &Tlist and ref shouldn't go to 0 here nor be 0 already */
		if(t != nil) {
			if (t->np)
				freeptrs(l->data, t);
			t->ref--;
			if(t->ref == 0) {
				free(t->initialize);
				free(t);
			}
		}
		l = l->tail;
		if(heapmonitor != nil)
			heapmonitor(1, th, 0);
		poolfree(heapmem, th);
	}
}

void
freemodlink(Heap *h, int swept)
{
	Modlink *ml;

	ml = H2D(Modlink*, h);
	if(ml->m->rt == DYNMOD)
		freedyndata(ml);
	else if(!swept)
		destroy(ml->MP);
	unload(ml->m);
}

int
heapref(void *v)
{
	return D2H(v)->ref;
}

void
freeheap(Heap *h, int swept)
{
	Type *t;

	if(swept)
		return;

	t = h->t;
	if (t->np)
		freeptrs(H2D(void*, h), t);
}

void
destroy(void *v)
{
	Heap *h;
	Type *t;

	if(v == H)
		return;

	h = D2H(v);
	{ Bhdr *b; D2B(b, h); }		/* consistency check */

	if(--h->ref > 0 || gchalt > 64) 	/* Protect 'C' thread stack */
		return;

	if(heapmonitor != nil)
		heapmonitor(1, h, 0);
	t = h->t;
	if(t != nil) {
		gclock();
		t->free(h, 0);
		gcunlock();
		freetype(t);
	}
	poolfree(heapmem, h);
}

void
freetype(Type *t)
{
	if(t == nil || --t->ref > 0)
		return;

	free(t->initialize);
	free(t);
}

void
incmem(void *vw, Type *t)
{
	Heap *h;
	uchar *p;
	int i, c, m;
	WORD **w, **q, *wp;

	w = (WORD**)vw;
	p = t->map;
	for(i = 0; i < t->np; i++) {
		c = *p++;
		if(c != 0) {
			q = w;
			for(m = 0x80; m != 0; m >>= 1) {
				if((c & m) && (wp = *q) != H) {
					h = D2H(wp);
					h->ref++;
					Setmark(h);
				}
				q++;
			}
		}
		w += 8;
	}
}

void
scanptrs(void *vw, Type *t, void (*f)(void*))
{
	uchar *p;
	int i, c, m;
	WORD **w, **q, *wp;

	w = (WORD**)vw;
	p = t->map;
	for(i = 0; i < t->np; i++) {
		c = *p++;
		if(c != 0) {
			q = w;
			for(m = 0x80; m != 0; m >>= 1) {
				if((c & m) && (wp = *q) != H)
					f(D2H(wp));
				q++;
			}
		}
		w += 8;
	}
}

void
initmem(Type *t, void *vw)
{
	int c;
	WORD **w;
	uchar *p, *ep;

	w = (WORD**)vw;
	p = t->map;
	ep = p + t->np;
	while(p < ep) {
		c = *p;
		if(c != 0) {
 			if(BIT(c, 0)) w[7] = H;
			if(BIT(c, 1)) w[6] = H;
			if(BIT(c, 2)) w[5] = H;
			if(BIT(c, 3)) w[4] = H;
			if(BIT(c, 4)) w[3] = H;
			if(BIT(c, 5)) w[2] = H;
			if(BIT(c, 6)) w[1] = H;
			if(BIT(c, 7)) w[0] = H;
		}
		p++;
		w += 8;
	}
}

Heap*
nheap(int n)
{
	Heap *h;

	h = poolalloc(heapmem, sizeof(Heap)+n);
	if(h == nil)
		error(exHeap);

	h->t = nil;
	h->ref = 1;
	h->color = mutator;
	if(heapmonitor != nil)
		heapmonitor(0, h, n);

	return h;
}

Heap*
heapz(Type *t)
{
	Heap *h;

	h = poolalloc(heapmem, sizeof(Heap)+t->size);
	if(h == nil)
		error(exHeap);

	h->t = t;
	t->ref++;
	h->ref = 1;
	h->color = mutator;
	memset(H2D(void*, h), 0, t->size);
	if(t->np)
		initmem(t, H2D(void*, h));
	if(heapmonitor != nil)
		heapmonitor(0, h, t->size);
	return h;
}

Heap*
heap(Type *t)
{
	Heap *h;

	h = poolalloc(heapmem, sizeof(Heap)+t->size);
	if(h == nil)
		error(exHeap);

	h->t = t;
	t->ref++;
	h->ref = 1;
	h->color = mutator;
	if(t->np)
		initmem(t, H2D(void*, h));
	if(heapmonitor != nil)
		heapmonitor(0, h, t->size);
	return h;
}

Heap*
heaparray(Type *t, int sz)
{
	Heap *h;
	Array *a;

	h = nheap(sizeof(Array) + (t->size*sz));
	h->t = &Tarray;
	Tarray.ref++;
	a = H2D(Array*, h);
	a->t = t;
	a->len = sz;
	a->root = H;
	a->data = (uchar*)a + sizeof(Array);
	initarray(t, a);
	return h;
}

int
hmsize(void *v)
{
	return poolmsize(heapmem, v);
}

void
initarray(Type *t, Array *a)
{
	int i;
	uchar *p;

	t->ref++;
	if(t->np == 0)
		return;

	p = a->data;
	for(i = 0; i < a->len; i++) {
		initmem(t, p);
		p += t->size;
	}
}

void*
arraycpy(Array *sa)
{
	int i;
	Heap *dh;
	Array *da;
	uchar *elemp;
	void **sp, **dp;

	if(sa == H)
		return H;

	dh = nheap(sizeof(Array) + sa->t->size*sa->len);
	dh->t = &Tarray;
	Tarray.ref++;
	da = H2D(Array*, dh);
	da->t = sa->t;
	da->t->ref++;
	da->len = sa->len;
	da->root = H;
	da->data = (uchar*)da + sizeof(Array);
	if(da->t == &Tarray) {
		dp = (void**)da->data;
		sp = (void**)sa->data;
		/*
		 * Maximum depth of this recursion is set by DADEPTH
		 * in include/isa.h
		 */
		for(i = 0; i < sa->len; i++)
			dp[i] = arraycpy(sp[i]);			
	}
	else {
		memmove(da->data, sa->data, da->len*sa->t->size);
		elemp = da->data;
		for(i = 0; i < sa->len; i++) {
			incmem(elemp, da->t);
			elemp += da->t->size;
		}
	}
	return da;
}

void
newmp(void *dst, void *src, Type *t)
{
	Heap *h;
	int c, i, m;
	void **uld, *wp, **q;

	memmove(dst, src, t->size);
	uld = dst;
	for(i = 0; i < t->np; i++) {
		c = t->map[i];
		if(c != 0) {
			m = 0x80;
			q = uld;
			while(m != 0) {
				if((m & c) && (wp = *q) != H) {
					h = D2H(wp);
					if(h->t == &Tarray)
						*q = arraycpy(wp);
					else {
						h->ref++;
						Setmark(h);
					}
				}
				m >>= 1;
				q++;
			}
		}
		uld += 8;
	}
}
