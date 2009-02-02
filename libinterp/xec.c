#include <lib9.h>
#include "isa.h"
#include "interp.h"
#include "raise.h"
#include "pool.h"

REG	R;			/* Virtual Machine registers */
String	snil;			/* String known to be zero length */

#define Stmp	*((WORD*)(R.FP+NREG*IBY2WD))
#define Dtmp	*((WORD*)(R.FP+(NREG+2)*IBY2WD))

#define OP(fn)	void fn(void)
#define B(r)	*((BYTE*)(R.r))
#define W(r)	*((WORD*)(R.r))
#define UW(r)	*((UWORD*)(R.r))
#define F(r)	*((REAL*)(R.r))
#define V(r)	*((LONG*)(R.r))	
#define UV(r)	*((ULONG*)(R.r))	
#define	S(r)	*((String**)(R.r))
#define	A(r)	*((Array**)(R.r))
#define	L(r)	*((List**)(R.r))
#define P(r)	*((WORD**)(R.r))
#define C(r)	*((Channel**)(R.r))
#define T(r)	*((void**)(R.r))
#define JMP(r)	R.PC = *(Inst**)(R.r)
#define SH(r)	*((SHORT*)(R.r))
#define SR(r)	*((SREAL*)(R.r))

OP(runt) {}
OP(negf) { F(d) = -F(s); }
OP(jmp)  { JMP(d); }
OP(movpc){ T(d) = &R.M->prog[W(s)]; }
OP(movm) { memmove(R.d, R.s, W(m)); }
OP(lea)  { W(d) = (WORD)R.s; }
OP(movb) { B(d) = B(s); }
OP(movw) { W(d) = W(s); }
OP(movf) { F(d) = F(s); }
OP(movl) { V(d) = V(s); }
OP(cvtbw){ W(d) = B(s); }
OP(cvtwb){ B(d) = W(s); }
OP(cvtrf){ F(d) = SR(s); }
OP(cvtfr){ SR(d) = F(s); }
OP(cvtws){ SH(d) = W(s); }
OP(cvtsw){ W(d) = SH(s); }
OP(cvtwf){ F(d) = W(s); }
OP(addb) { B(d) = B(m) + B(s); }
OP(addw) { W(d) = W(m) + W(s); }
OP(addl) { V(d) = V(m) + V(s); }
OP(addf) { F(d) = F(m) + F(s); }
OP(subb) { B(d) = B(m) - B(s); }
OP(subw) { W(d) = W(m) - W(s); }
OP(subl) { V(d) = V(m) - V(s); }
OP(subf) { F(d) = F(m) - F(s); }
OP(divb) { B(d) = B(m) / B(s); }
OP(divw) { W(d) = W(m) / W(s); }
OP(divl) { V(d) = V(m) / V(s); }
OP(divf) { F(d) = F(m) / F(s); }
OP(modb) { B(d) = B(m) % B(s); }
OP(modw) { W(d) = W(m) % W(s); }
OP(modl) { V(d) = V(m) % V(s); }
OP(mulb) { B(d) = B(m) * B(s); }
OP(mulw) { W(d) = W(m) * W(s); }
OP(mull) { V(d) = V(m) * V(s); }
OP(mulf) { F(d) = F(m) * F(s); }
OP(andb) { B(d) = B(m) & B(s); }
OP(andw) { W(d) = W(m) & W(s); }
OP(andl) { V(d) = V(m) & V(s); }
OP(xorb) { B(d) = B(m) ^ B(s); }
OP(xorw) { W(d) = W(m) ^ W(s); }
OP(xorl) { V(d) = V(m) ^ V(s); }
OP(orb)  { B(d) = B(m) | B(s); }
OP(orw)  { W(d) = W(m) | W(s); }
OP(orl)  { V(d) = V(m) | V(s); }
OP(shlb) { B(d) = B(m) << W(s); }
OP(shlw) { W(d) = W(m) << W(s); }
OP(shll) { V(d) = V(m) << W(s); }
OP(shrb) { B(d) = B(m) >> W(s); }
OP(shrw) { W(d) = W(m) >> W(s); }
OP(shrl) { V(d) = V(m) >> W(s); }
OP(lsrw) { W(d) = UW(m) >> W(s); }
OP(lsrl) { V(d) = UV(m) >> W(s); }
OP(beqb) { if(B(s) == B(m)) JMP(d); }
OP(bneb) { if(B(s) != B(m)) JMP(d); }
OP(bltb) { if(B(s) <  B(m)) JMP(d); }
OP(bleb) { if(B(s) <= B(m)) JMP(d); }
OP(bgtb) { if(B(s) >  B(m)) JMP(d); }
OP(bgeb) { if(B(s) >= B(m)) JMP(d); }
OP(beqw) { if(W(s) == W(m)) JMP(d); }
OP(bnew) { if(W(s) != W(m)) JMP(d); }
OP(bltw) { if(W(s) <  W(m)) JMP(d); }
OP(blew) { if(W(s) <= W(m)) JMP(d); }
OP(bgtw) { if(W(s) >  W(m)) JMP(d); }
OP(bgew) { if(W(s) >= W(m)) JMP(d); }
OP(beql) { if(V(s) == V(m)) JMP(d); }
OP(bnel) { if(V(s) != V(m)) JMP(d); }
OP(bltl) { if(V(s) <  V(m)) JMP(d); }
OP(blel) { if(V(s) <= V(m)) JMP(d); }
OP(bgtl) { if(V(s) >  V(m)) JMP(d); }
OP(bgel) { if(V(s) >= V(m)) JMP(d); }
OP(beqf) { if(F(s) == F(m)) JMP(d); }
OP(bnef) { if(F(s) != F(m)) JMP(d); }
OP(bltf) { if(F(s) <  F(m)) JMP(d); }
OP(blef) { if(F(s) <= F(m)) JMP(d); }
OP(bgtf) { if(F(s) >  F(m)) JMP(d); }
OP(bgef) { if(F(s) >= F(m)) JMP(d); }
OP(beqc) { if(stringcmp(S(s), S(m)) == 0) JMP(d); }
OP(bnec) { if(stringcmp(S(s), S(m)) != 0) JMP(d); }
OP(bltc) { if(stringcmp(S(s), S(m)) <  0) JMP(d); }
OP(blec) { if(stringcmp(S(s), S(m)) <= 0) JMP(d); }
OP(bgtc) { if(stringcmp(S(s), S(m)) >  0) JMP(d); }
OP(bgec) { if(stringcmp(S(s), S(m)) >= 0) JMP(d); }
OP(iexit){ error(""); }
OP(cvtwl){ V(d) = W(s); }
OP(cvtlw){ W(d) = V(s); }
OP(cvtlf){ F(d) = V(s); }
OP(cvtfl)
{
	REAL f;

	f = F(s);
	V(d) = f < 0 ? f - .5 : f + .5;
}
OP(cvtfw)
{
	REAL f;

	f = F(s);
	W(d) = f < 0 ? f - .5 : f + .5;
}
OP(cvtcl)
{
	String *s;

	s = S(s);
	if(s == H)
		V(d) = 0;
	else
		V(d) = strtoll(string2c(s), nil, 10);
}
OP(iexpw)
{
	int inv;
	WORD x, n, r;

	x = W(m);
	n = W(s);
	inv = 0;
	if(n < 0){
		n = -n;
		inv = 1;
	}
	r = 1;
	for(;;){
		if(n&1)
			r *= x;
		if((n >>= 1) == 0)
			break;
		x *= x;
	}
	if(inv)
		r = 1/r;
	W(d) = r;
}
OP(iexpl)
{
	int inv;
	WORD n;
	LONG x, r;

	x = V(m);
	n = W(s);
	inv = 0;
	if(n < 0){
		n = -n;
		inv = 1;
	}
	r = 1;
	for(;;){
		if(n&1)
			r *= x;
		if((n >>= 1) == 0)
			break;
		x *= x;
	}
	if(inv)
		r = 1/r;
	V(d) = r;
}
OP(iexpf)
{
	int inv;
	WORD n;
	REAL x, r;

	x = F(m);
	n = W(s);
	inv = 0;
	if(n < 0){
		n = -n;
		inv = 1;
	}
	r = 1;
	for(;;){
		if(n&1)
			r *= x;
		if((n >>= 1) == 0)
			break;
		x *= x;
	}
	if(inv)
		r = 1/r;
	F(d) = r;
}
OP(indx)
{
	ulong i;
	Array *a;

	a = A(s);
	i = W(d);
	if(a == H || i >= a->len)
		error(exBounds);
	W(m) = (WORD)(a->data+i*a->t->size);
}
OP(indw)
{
	ulong i;
	Array *a;

	a = A(s);
	i = W(d);
	if(a == H || i >= a->len)
		error(exBounds);
	W(m) = (WORD)(a->data+i*sizeof(WORD));
}
OP(indf)
{
	ulong i;
	Array *a;

	a = A(s);
	i = W(d);
	if(a == H || i >= a->len)
		error(exBounds);
	W(m) = (WORD)(a->data+i*sizeof(REAL));
}
OP(indl)
{
	ulong i;
	Array *a;

	a = A(s);
	i = W(d);
	if(a == H || i >= a->len)
		error(exBounds);
	W(m) = (WORD)(a->data+i*sizeof(LONG));
}
OP(indb)
{
	ulong i;
	Array *a;

	a = A(s);
	i = W(d);
	if(a == H || i >= a->len)
		error(exBounds);
	W(m) = (WORD)(a->data+i*sizeof(BYTE));
}
OP(movp)
{
	Heap *h;
	WORD *dv, *sv;

	sv = P(s);
	if(sv != H) {
		h = D2H(sv);
		h->ref++;
		Setmark(h);
	}
	dv = P(d);
	P(d) = sv;
	destroy(dv);
}
OP(movmp)
{
	Type *t;

	t = R.M->type[W(m)];

	incmem(R.s, t);
	if (t->np)
		freeptrs(R.d, t);
	memmove(R.d, R.s, t->size);
}
OP(new)
{
	Heap *h;
	WORD **wp, *t;

	h = heap(R.M->type[W(s)]);
	wp = R.d;
	t = *wp;
	*wp = H2D(WORD*, h);
	destroy(t);
}
OP(newz)
{
	Heap *h;
	WORD **wp, *t;

	h = heapz(R.M->type[W(s)]);
	wp = R.d;
	t = *wp;
	*wp = H2D(WORD*, h);
	destroy(t);
}
OP(mnewz)
{
	Heap *h;
	WORD **wp, *t;
	Modlink *ml;

	ml = *(Modlink**)R.s;
	if(ml == H)
		error(exModule);
	h = heapz(ml->type[W(m)]);
	wp = R.d;
	t = *wp;
	*wp = H2D(WORD*, h);
	destroy(t);
}
OP(frame)
{
	Type *t;
	Frame *f;
	uchar *nsp;

	t = R.M->type[W(s)];
	nsp = R.SP + t->size;
	if(nsp >= R.TS) {
		R.s = t;
		extend();
		T(d) = R.s;
		return;
	}
	f = (Frame*)R.SP;
	R.SP  = nsp;
	f->t  = t;
	f->mr = nil;
	if (t->np)
		initmem(t, f);
	T(d) = f;
}
OP(mframe)
{
	Type *t;
	Frame *f;
	uchar *nsp;
	Modlink *ml;
	int o;

	ml = *(Modlink**)R.s;
	if(ml == H)
		error(exModule);

	o = W(m);
	if(o >= 0){
		if(o >= ml->nlinks)
			error("invalid mframe");
		t = ml->links[o].frame;
	}
	else
		t = ml->m->ext[-o-1].frame;
	nsp = R.SP + t->size;
	if(nsp >= R.TS) {
		R.s = t;
		extend();
		T(d) = R.s;
		return;
	}
	f = (Frame*)R.SP;
	R.SP = nsp;
	f->t = t;
	f->mr = nil;
	if (t->np)
		initmem(t, f);
	T(d) = f;
}
void
acheck(int tsz, int sz)
{
	if(sz < 0)
		error(exNegsize);
	/* test for overflow; assumes sz >>> tsz */
	if((int)(sizeof(Array) + sizeof(Heap) + tsz*sz) < sz && tsz != 0)
		error(exHeap);
}
OP(newa)
{
	int sz;
	Type *t;
	Heap *h;
	Array *a, *at, **ap;

	t = R.M->type[W(m)];
	sz = W(s);
	acheck(t->size, sz);
	h = nheap(sizeof(Array) + (t->size*sz));
	h->t = &Tarray;
	Tarray.ref++;
	a = H2D(Array*, h);
	a->t = t;
	a->len = sz;
	a->root = H;
	a->data = (uchar*)a + sizeof(Array);
	initarray(t, a);

	ap = R.d;
	at = *ap;
	*ap = a;
	destroy(at);
}
OP(newaz)
{
	int sz;
	Type *t;
	Heap *h;
	Array *a, *at, **ap;

	t = R.M->type[W(m)];
	sz = W(s);
	acheck(t->size, sz);
	h = nheap(sizeof(Array) + (t->size*sz));
	h->t = &Tarray;
	Tarray.ref++;
	a = H2D(Array*, h);
	a->t = t;
	a->len = sz;
	a->root = H;
	a->data = (uchar*)a + sizeof(Array);
	memset(a->data, 0, t->size*sz);
	initarray(t, a);

	ap = R.d;
	at = *ap;
	*ap = a;
	destroy(at);
}
Channel*
cnewc(Type *t, void (*mover)(void), int len)
{
	Heap *h;
	Channel *c;

	h = heap(&Tchannel);
	c = H2D(Channel*, h);
	c->send = malloc(sizeof(Progq));
	c->recv = malloc(sizeof(Progq));
	if(c->send == nil || c->recv == nil){
		free(c->send);
		free(c->recv);
		error(exNomem);
	}
	c->send->prog = c->recv->prog = nil;
	c->send->next = c->recv->next = nil;
	c->mover = mover;
	c->buf = H;
	if(len > 0)
		c->buf = H2D(Array*, heaparray(t, len));
	c->front = 0;
	c->size = 0;
	if(mover == movtmp){
		c->mid.t = t;
		t->ref++;
	}
	return c;
}
Channel*
newc(Type *t, void (*mover)(void))
{
	Channel **cp, *oldc;
	WORD len;

	len = 0;
	if(R.m != R.d){
		len = W(m);
		if(len < 0)
			error(exNegsize);
	}
	cp = R.d;
	oldc = *cp;
	*cp = cnewc(t, mover, len);
	destroy(oldc);
	return *cp;
}
OP(newcl)  { newc(&Tlong, movl);  }
OP(newcb)  { newc(&Tbyte, movb);  }
OP(newcw)  { newc(&Tword, movw);  }
OP(newcf)  { newc(&Treal, movf);  }
OP(newcp)  { newc(&Tptr, movp);  }
OP(newcm)
{
	Channel *c;
	Type *t;

	t = nil;
	if(R.m != R.d && W(m) > 0)
		t = dtype(nil, W(s), nil, 0);
	c = newc(t, movm);
	c->mid.w = W(s);
	if(t != nil)
		freetype(t);
}
OP(newcmp)
{
	newc(R.M->type[W(s)], movtmp);
}
OP(icase)
{
	WORD v, *t, *l, d, n, n2;

	v = W(s);
	t = (WORD*)((WORD)R.d + IBY2WD);
	n = t[-1];
	d = t[n*3];

	while(n > 0) {
		n2 = n >> 1;
		l = t + n2*3;
		if(v < l[0]) {
			n = n2;
			continue;
		}
		if(v >= l[1]) {
			t = l+3;
			n -= n2 + 1;
			continue;
		}
		d = l[2];
		break;
	}
	if(R.M->compiled) {
		R.PC = (Inst*)d;
		return;
	}
	R.PC = R.M->prog + d;
}
OP(casel)
{
	WORD *t, *l, d, n, n2;
	LONG v;

	v = V(s);
	t = (WORD*)((WORD)R.d + 2*IBY2WD);
	n = t[-2];
	d = t[n*6];

	while(n > 0) {
		n2 = n >> 1;
		l = t + n2*6;
		if(v < ((LONG*)l)[0]) {
			n = n2;
			continue;
		}
		if(v >= ((LONG*)l)[1]) {
			t = l+6;
			n -= n2 + 1;
			continue;
		}
		d = l[4];
		break;
	}
	if(R.M->compiled) {
		R.PC = (Inst*)d;
		return;
	}
	R.PC = R.M->prog + d;
}
OP(casec)
{
	WORD *l, *t, *e, n, n2, r;
	String *sl, *sh, *sv;
	
	sv = S(s);
	t = (WORD*)((WORD)R.d + IBY2WD);
	n = t[-1];
	e = t + n*3;
	if(n > 2){
		while(n > 0){
			n2 = n>>1;
			l = t + n2*3;
			sl = (String*)l[0];
			r = stringcmp(sv, sl);
			if(r == 0){
				e = &l[2];
				break;
			}
			if(r < 0){
				n = n2;
				continue;
			}
			sh = (String*)l[1];
			if(sh == H || stringcmp(sv, sh) > 0){
				t = l+3;
				n -= n2+1;
				continue;
			}
			e = &l[2];
			break;
		}
		t = e;
	}
	else{
		while(t < e) {
			sl = (String*)t[0];
			sh = (String*)t[1];
			if(sh == H) {
				if(stringcmp(sl, sv) == 0) {
					t = &t[2];
					goto found;
				}
			}
			else
			if(stringcmp(sl, sv) <= 0 && stringcmp(sh, sv) >= 0) {
				t = &t[2];
				goto found;
			}
			t += 3;
		}
	}
found:
	if(R.M->compiled) {
		R.PC = (Inst*)*t;
		return;
	}
	R.PC = R.M->prog + t[0];
}
OP(igoto)
{
	WORD *t;

	t = (WORD*)((WORD)R.d + (W(s) * IBY2WD));
	if(R.M->compiled) {
		R.PC = (Inst*)t[0];
		return;
	}
	R.PC = R.M->prog + t[0];
}
OP(call)
{
	Frame *f;

	f = T(s);
	f->lr = R.PC;
	f->fp = R.FP;
	R.FP = (uchar*)f;
	JMP(d);
}
OP(spawn)
{
	Prog *p;

	p = newprog(currun(), R.M);
	p->R.PC = *(Inst**)R.d;
	newstack(p);
	unframe();
}
OP(mspawn)
{
	Prog *p;
	Modlink *ml;
	int o;

	ml = *(Modlink**)R.d;
	if(ml == H)
		error(exModule);
	if(ml->prog == nil)
		error(exSpawn);
	p = newprog(currun(), ml);
	o = W(m);
	if(o >= 0)
		p->R.PC = ml->links[o].u.pc;
	else
		p->R.PC = ml->m->ext[-o-1].u.pc;
	newstack(p);
	unframe();
}
OP(ret)
{
	Frame *f;
	Modlink *m;

	f = (Frame*)R.FP;
	R.FP = f->fp;
	if(R.FP == nil) {
		R.FP = (uchar*)f;
		error("");
	}
	R.SP = (uchar*)f;
	R.PC = f->lr;
	m = f->mr;

	if(f->t == nil)
		unextend(f);
	else if (f->t->np)
		freeptrs(f, f->t);

	if(m != nil) {
		if(R.M->compiled != m->compiled) {
			R.IC = 1;
			R.t = 1;
		}
		destroy(R.M);
		R.M = m;
		R.MP = m->MP;
	}
}
OP(iload)
{
	char *n;
	Import *ldt;
	Module *m;
	Modlink *ml, **mp, *t;
	Heap *h;

	n = string2c(S(s));
	m = R.M->m;
	if(m->rt & HASLDT)
		ldt = m->ldt[W(m)];
	else{
		ldt = nil;
		error("obsolete dis");
	}

	if(strcmp(n, "$self") == 0) {
		m->ref++;
		ml = linkmod(m, ldt, 0);
		if(ml != H) {
			ml->MP = R.M->MP;
			h = D2H(ml->MP);
			h->ref++;
			Setmark(h);
		}
	}
	else {
		m = readmod(n, lookmod(n), 1);
		ml = linkmod(m, ldt, 1);
	}

	mp = R.d;
	t = *mp;
	*mp = ml;
	destroy(t);
}
OP(mcall)
{
	Heap *h;
	Prog *p;
	Frame *f;
	Linkpc *l;
	Modlink *ml;
	int o;

	ml = *(Modlink**)R.d;
	if(ml == H)
		error(exModule);
	f = T(s);
	f->lr = R.PC;
	f->fp = R.FP;
	f->mr = R.M;

	R.FP = (uchar*)f;
	R.M = ml;
	h = D2H(ml);
	h->ref++;

	o = W(m);
	if(o >= 0)
		l = &ml->links[o].u;
	else
		l = &ml->m->ext[-o-1].u;
	if(ml->prog == nil) {
		l->runt(f);
		h->ref--;
		R.M = f->mr;
		R.SP = R.FP;
		R.FP = f->fp;
		if(f->t == nil)
			unextend(f);
		else if (f->t->np)
			freeptrs(f, f->t);
		p = currun();
		if(p->kill != nil)
			error(p->kill);
		R.t = 0;
		return;
	}
	R.MP = R.M->MP;
	R.PC = l->pc;
	R.t = 1;

	if(f->mr->compiled != R.M->compiled)
		R.IC = 1;
}
OP(lena)
{
	WORD l;
	Array *a;

	a = A(s);
	l = 0;
	if(a != H)
		l = a->len;
	W(d) = l;
}
OP(lenl)
{
	WORD l;
	List *a;

	a = L(s);
	l = 0;
	while(a != H) {
		l++;
		a = a->tail;
	}
	W(d) = l;
}
static int
cgetb(Channel *c, void *v)
{
	Array *a;
	void *w;

	if((a = c->buf) == H)
		return 0;
	if(c->size > 0){
		w = a->data+c->front*a->t->size;
		c->front++;
		if(c->front == c->buf->len)
			c->front = 0;
		c->size--;
		R.s = w;
		R.m = &c->mid;
		R.d = v;
		c->mover();
		if(a->t->np){
			freeptrs(w, a->t);
			initmem(a->t, w);
		}
		return 1;
	}
	return 0;
}
static int
cputb(Channel *c, void *v)
{
	Array *a;
	WORD len, r;

	if((a = c->buf) == H)
		return 0;
	len = c->buf->len;
	if(c->size < len){
		r = c->front+c->size;
		if(r >= len)
			r -= len;
		c->size++;
		R.s = v;
		R.m = &c->mid;
		R.d = a->data+r*a->t->size;
		c->mover();
		return 1;
	}
	return 0;
}
/*
int
cqsize(Progq *q)
{
	int n;

	n = 0;
	for( ; q != nil; q = q->next)
		if(q->prog != nil)
			n++;
	return n;
}
*/
void
cqadd(Progq **q, Prog *p)
{
	Progq *n;

	if((*q)->prog == nil){
		(*q)->prog = p;
		return;
	}
	n = (Progq*)malloc(sizeof(Progq));
	if(n == nil)
		error(exNomem);
	n->prog = p;
	n->next = nil;
	for( ; *q != nil; q = &(*q)->next)
		;
	*q = n;
}
void
cqdel(Progq **q)
{
	Progq *f;

	if((*q)->next == nil){
		(*q)->prog = nil;
		return;
	}
	f = *q;
	*q = f->next;
	free(f);
}
void
cqdelp(Progq **q, Prog *p)
{
	Progq *f;

	if((*q)->next == nil){
		if((*q)->prog == p)
			(*q)->prog = nil;
		return;
	}
	for( ; *q != nil; ){
		if((*q)->prog == p){
			f = *q;
			*q = (*q)->next;
			free(f);
		}
		else
			q = &(*q)->next;
	}
}	
OP(isend)
{
	Channel *c;
 	Prog *p;

	c = C(d);
	if(c == H)
		error(exNilref);

	if((p = c->recv->prog) == nil) {
		if(c->buf != H && cputb(c, R.s))
			return;
		p = delrun(Psend);
		p->ptr = R.s;
		p->chan = c;	/* for killprog */
		R.IC = 1;	
		R.t = 1;
		cqadd(&c->send, p);
		return;
	}

	if(c->buf != H && c->size > 0)
		print("non-empty buffer in isend\n");

	cqdel(&c->recv);
	if(p->state == Palt)
		altdone(p->R.s, p, c, 1);

	R.m = &c->mid;
	R.d = p->ptr;
	p->ptr = nil;
	c->mover();
	addrun(p);
	R.t = 0;
}
OP(irecv)
{
	Channel *c;
	Prog *p;

	c = C(s);
	if(c == H)
		error(exNilref);

	if((p = c->send->prog) == nil) {
		if(c->buf != H && cgetb(c, R.d))
			return;
		p = delrun(Precv);
		p->ptr = R.d;
		p->chan = c;	/* for killprog */
		R.IC = 1;
		R.t = 1;
		cqadd(&c->recv, p);
		return;
	}

	if(c->buf != H && c->size != c->buf->len)
		print("non-full buffer in irecv\n");

	cqdel(&c->send);
	if(p->state == Palt)
		altdone(p->R.s, p, c, 0);

	if(c->buf != H){
		cgetb(c, R.d);
		cputb(c, p->ptr);
		p->ptr = nil;
	}
	else{
		R.m = &c->mid;
		R.s = p->ptr;
		p->ptr = nil;
		c->mover();
	}
	addrun(p);
	R.t = 0;
}
int
csendalt(Channel *c, void *ip, Type *t, int len)
{
	REG rsav;

	if(c == H)
		error(exNilref);

	if(c->recv->prog == nil && (c->buf == H || c->size == c->buf->len)){
		if(c->buf != H){
			print("csendalt failed\n");
			freeptrs(ip, t);
			return 0;
		}
		c->buf = H2D(Array*, heaparray(t, len));
	}

	rsav = R;
	R.s = ip;
	R.d = &c;
	isend();
	R = rsav;
	freeptrs(ip, t);
	return 1;
}

List*
cons(ulong size, List **lp)
{
	Heap *h;
	List *lv, *l;

	h = nheap(sizeof(List) + size - sizeof(((List*)0)->data));
	h->t = &Tlist;
	Tlist.ref++;
	l = H2D(List*, h);
	l->t = nil;

	lv = *lp;
	if(lv != H) {
		h = D2H(lv);
		Setmark(h);
	}
	l->tail = lv;
	*lp = l;
	return l;
}
OP(consb)
{
	List *l;

	l = cons(IBY2WD, R.d);
	*(BYTE*)l->data = B(s);
}
OP(consw)
{
	List *l;

	l = cons(IBY2WD, R.d);
	*(WORD*)l->data = W(s);
}
OP(consl)
{
	List *l;

	l = cons(IBY2LG, R.d);
	*(LONG*)l->data = V(s);
}
OP(consp)
{
	List *l;
	Heap *h;
	WORD *sv;

	l = cons(IBY2WD, R.d);
	sv = P(s);
	if(sv != H) {
		h = D2H(sv);
		h->ref++;
		Setmark(h);
	}
	l->t = &Tptr;
	Tptr.ref++;
	*(WORD**)l->data = sv;
}
OP(consf)
{
	List *l;

	l = cons(sizeof(REAL), R.d);
	*(REAL*)l->data = F(s);
}
OP(consm)
{
	int v;
	List *l;

	v = W(m);
	l = cons(v, R.d);
	memmove(l->data, R.s, v);
}
OP(consmp)
{
	List *l;
	Type *t;

	t = R.M->type[W(m)];
	l = cons(t->size, R.d);
	incmem(R.s, t);
	memmove(l->data, R.s, t->size);
	l->t = t;
	t->ref++;
}
OP(headb)
{
	List *l;

	l = L(s);
	B(d) = *(BYTE*)l->data;
}
OP(headw)
{
	List *l;

	l = L(s);
	W(d) = *(WORD*)l->data;
}
OP(headl)
{
	List *l;

	l = L(s);
	V(d) = *(LONG*)l->data;
}
OP(headp)
{
	List *l;

	l = L(s);
	R.s = l->data;
	movp();
}
OP(headf)
{
	List *l;

	l = L(s);
	F(d) = *(REAL*)l->data;
}
OP(headm)
{
	List *l;

	l = L(s);
	memmove(R.d, l->data, W(m));
}
OP(headmp)
{
	List *l;

	l = L(s);
	R.s = l->data;
	movmp();
}
OP(tail)
{
	List *l;

	l = L(s);
	R.s = &l->tail;
	movp();
}
OP(slicea)
{
	Type *t;
	Heap *h;
	Array *at, *ss, *ds;
	int v, n, start;

	v = W(m);
	start = W(s);
	n = v - start;
	ds = A(d);

	if(ds == H) {
		if(n == 0)
			return;
		error(exNilref);
	}
	if(n < 0 || (ulong)start > ds->len || (ulong)v > ds->len)
		error(exBounds);

	t = ds->t;
	h = heap(&Tarray);
	ss = H2D(Array*, h);
	ss->len = n;
	ss->data = ds->data + start*t->size;
	ss->t = t;
	t->ref++;

	if(ds->root != H) {			/* slicing a slice */
		ds = ds->root;
		h = D2H(ds);
		h->ref++;
		at = A(d);
		A(d) = ss;
		ss->root = ds;
		destroy(at);
	}
	else {
		h = D2H(ds);
		ss->root = ds;
		A(d) = ss;
	}
	Setmark(h);
}
OP(slicela)
{
	Type *t;
	int l, dl;
	Array *ss, *ds;
	uchar *sp, *dp, *ep;

	ss = A(s);
	dl = W(m);
	ds = A(d);
	if(ss == H)
		return;
	if(ds == H)
		error(exNilref);
	if(dl < 0 || dl+ss->len > ds->len)
		error(exBounds);

	t = ds->t;
	if(t->np == 0) {
		memmove(ds->data+dl*t->size, ss->data, ss->len*t->size);
		return;
	}
	sp = ss->data;
	dp = ds->data+dl*t->size;

	if(dp > sp) {
		l = ss->len * t->size;
		sp = ss->data + l;
		ep = dp + l;
		while(ep > dp) {
			ep -= t->size;
			sp -= t->size;
			incmem(sp, t);
			if (t->np)
				freeptrs(ep, t);
		}
	}
	else {
		ep = dp + ss->len*t->size;
		while(dp < ep) {
			incmem(sp, t);
			if (t->np)
				freeptrs(dp, t);
			dp += t->size;
			sp += t->size;
		}
	}
	memmove(ds->data+dl*t->size, ss->data, ss->len*t->size);
}
OP(alt)
{
	R.t = 0;
	xecalt(1);
}
OP(nbalt)
{
	xecalt(0);
}
OP(tcmp)
{
	void *s, *d;

	s = T(s);
	d = T(d);
	if(s != H && (d == H || D2H(s)->t != D2H(d)->t))
		error(exTcheck);
}
OP(eclr)
{
	/* spare slot */
}
OP(badop)
{
	error(exOp);
}
OP(iraise)
{
	void *v;
	Heap *h;
	Prog *p;

	p = currun();
	v = T(s);
	if(v == H)
		error(exNilref);
	p->exval = v;
	h = D2H(v);
	h->ref++;
	if(h->t == &Tstring)
		error(string2c((String*)v));
	else
		error(string2c(*(String**)v));
}
OP(mulx)
{
	WORD p;
	LONG r;

	p = Dtmp;
	r = (LONG)W(m)*(LONG)W(s);
	if(p >= 0)
		r <<= p;
	else
		r >>= (-p);
	W(d) = (WORD)r;
}
OP(divx)
{
	WORD p;
	LONG s;

	p = Dtmp;
	s = (LONG)W(m);
	if(p >= 0)
		s <<= p;
	else
		s >>= (-p);
	s /= (LONG)W(s);
	W(d) = (WORD)s;
}
OP(cvtxx)
{
	WORD p;
	LONG r;

	p = W(m);
	r = (LONG)W(s);
	if(p >= 0)
		r <<= p;
	else
		r >>= (-p);
	W(d) = (WORD)r;
}
OP(mulx0)
{
	WORD x, y, p, a;
	LONG r;

	x = W(m);
	y = W(s);
	p = Dtmp;
	a = Stmp;
	if(x == 0 || y == 0){
		W(d) = 0;
		return;
	}
	r = (LONG)x*(LONG)y;
	if(p >= 0)
		r <<= p;
	else
		r >>= (-p);
	r /= (LONG)a;
	W(d) = (WORD)r;
}
OP(divx0)
{
	WORD x, y, p, b;
	LONG s;

	x = W(m);
	y = W(s);
	p = Dtmp;
	b = Stmp;
	if(x == 0){
		W(d) = 0;
		return;
	}
	s = (LONG)b*(LONG)x;
	if(p >= 0)
		s <<= p;
	else
		s >>= (-p);
	s /= (LONG)y;
	W(d) = (WORD)s;
}
OP(cvtxx0)
{
	WORD x, p, a;
	LONG r;

	x = W(s);
	p = W(m);
	a = Stmp;
	if(x == 0){
		W(d) = 0;
		return;
	}
	r = (LONG)x;
	if(p >= 0)
		r <<= p;
	else
		r >>= (-p);
	r /= (LONG)a;
	W(d) = (WORD)r;
}
OP(mulx1)
{
	WORD x, y, p, a, v;
	int vnz, wnz;
	LONG w, r;

	x = W(m);
	y = W(s);
	p = Dtmp;
	a = Stmp;
	if(x == 0 || y == 0){
		W(d) = 0;
		return;
	}
	vnz = p&2;
	wnz = p&1;
	p >>= 2;
	v = 0;
	w = 0;
	if(vnz){
		v = a-1;
		if(x >= 0 && y < 0 || x < 0 && y >= 0)
			v = -v;
	}
	if(wnz){
		if((!vnz && (x > 0 && y < 0 || x < 0 && y > 0)) ||
		(vnz && (x > 0 && y > 0 || x < 0 && y < 0)))
			w = ((LONG)1<<(-p)) - 1;
	}
	r = (LONG)x*(LONG)y + w;
	if(p >= 0)
		r <<= p;
	else
		r >>= (-p);
	r += (LONG)v;
	r /= (LONG)a;
	W(d) = (WORD)r;
}
OP(divx1)
{
	WORD x, y, p, b, v;
	int vnz, wnz;
	LONG w, s;

	x = W(m);
	y = W(s);
	p = Dtmp;
	b = Stmp;
	if(x == 0){
		W(d) = 0;
		return;
	}
	vnz = p&2;
	wnz = p&1;
	p >>= 2;
	v = 0;
	w = 0;
	if(vnz){
		v = 1;
		if(x >= 0 && y < 0 || x < 0 && y >= 0)
			v = -v;
	}
	if(wnz){
		if(x <= 0)
			w = ((LONG)1<<(-p)) - 1;
	}
	s = (LONG)b*(LONG)x + w;
	if(p >= 0)
		s <<= p;
	else
		s >>= (-p);
	s /= (LONG)y;
	W(d) = (WORD)s + v;
}
OP(cvtxx1)
{
	WORD x, p, a, v;
	int vnz, wnz;
	LONG w, r;

	x = W(s);
	p = W(m);
	a = Stmp;
	if(x == 0){
		W(d) = 0;
		return;
	}
	vnz = p&2;
	wnz = p&1;
	p >>= 2;
	v = 0;
	w = 0;
	if(vnz){
		v = a-1;
		if(x < 0)
			v = -v;
	}
	if(wnz){
		if(!vnz && x < 0 || vnz && x > 0)
			w = ((LONG)1<<(-p)) - 1;
	}
	r = (LONG)x + w;
	if(p >= 0)
		r <<= p;
	else
		r >>= (-p);
	r += (LONG)v;
	r /= (LONG)a;
	W(d) = (WORD)r;
}
/*
OP(cvtxx)
{
	REAL v;

	v = (REAL)W(s)*F(m);
	v = v < 0 ? v-0.5: v+0.5;
	W(d) = (WORD)v;
}
*/
OP(cvtfx)
{
	REAL v;

	v = F(s)*F(m);
	v = v < 0 ? v-0.5: v+0.5;
	W(d) = (WORD)v;
}
OP(cvtxf)
{
	F(d) = (REAL)W(s)*F(m);
}

OP(self)
{
	Modlink *ml, **mp, *t;
	Heap *h;

	ml = R.M;
	h = D2H(ml);
	h->ref++;
	Setmark(h);
	mp = R.d;
	t = *mp;
	*mp = ml;
	destroy(t);
}

void
destroystack(REG *reg)
{
	Type *t;
	Frame *f, *fp;
	Modlink *m;
	Stkext *sx;
	uchar *ex;

	ex = reg->EX;
	reg->EX = nil;
	while(ex != nil) {
		sx = (Stkext*)ex;
		fp = sx->reg.tos.fr;
		do {
			f = (Frame*)reg->FP;
			if(f == nil)
				break;
			reg->FP = f->fp;
			t = f->t;
			if(t == nil)
				t = sx->reg.TR;
			m = f->mr;
			if (t->np)
				freeptrs(f, t);
			if(m != nil) {
				destroy(reg->M);
				reg->M = m;
			}
		} while(f != fp);
		ex = sx->reg.EX;
		free(sx);
	}
	destroy(reg->M);
	reg->M = H;	/* for devprof */
}

Prog*
isave(void)
{
	Prog *p;

	p = delrun(Prelease);
	p->R = R;
	return p;
}

void
irestore(Prog *p)
{
	R = p->R;
	R.IC = 1;
}

void
movtmp(void)		/* Used by send & receive */
{
	Type *t;

	t = (Type*)W(m);

	incmem(R.s, t);
	if (t->np)
		freeptrs(R.d, t);
	memmove(R.d, R.s, t->size);
}

extern OP(cvtca);
extern OP(cvtac);
extern OP(cvtwc);
extern OP(cvtcw);
extern OP(cvtfc);
extern OP(cvtcf);
extern OP(insc);
extern OP(indc);
extern OP(addc);
extern OP(lenc);
extern OP(slicec);
extern OP(cvtlc);

#include "optab.h"

void
opinit(void)
{
	int i;

	for(i = 0; i < 256; i++)
		if(optab[i] == nil)
			optab[i] = badop;
}

void
xec(Prog *p)
{
	int op;

	R = p->R;
	R.MP = R.M->MP;
	R.IC = p->quanta;

	if(p->kill != nil) {
		char *m;
		m = p->kill;
		p->kill = nil;
		error(m);
	}

// print("%lux %lux %lux %lux %lux\n", (ulong)&R, R.xpc, R.FP, R.MP, R.PC);

	if(R.M->compiled)
		comvec();
	else do {
		dec[R.PC->add]();
		op = R.PC->op;
		R.PC++;
		optab[op]();
	} while(--R.IC != 0);

	p->R = R;
}
