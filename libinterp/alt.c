#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "raise.h"

#define OP(fn)	void fn(void)
#define W(p)	*((WORD*)(p))

#define CANGET(c)	((c)->size > 0)
#define CANPUT(c)	((c)->buf != H && (c)->size < (c)->buf->len)

extern	OP(isend);
extern	OP(irecv);

/*
 * Count the number of ready channels in an array of channels
 * Set each channel's alt pointer to the owning prog
 */
static int
altmark(Channel *c, Prog *p)
{
	int nrdy;
	Array *a;
	Channel **ca, **ec;

	nrdy = 0;
	a = (Array*)c;
	ca = (Channel**)a->data;
	ec = ca + a->len;
	while(ca < ec) {
		c = *ca;
		if(c != H) {
			if(c->send->prog || CANGET(c))
				nrdy++;
			cqadd(&c->recv, p);
		}
		ca++;
	}

	return nrdy;
}

/*
 * Remove alt references to an array of channels
 */
static void
altunmark(Channel *c, WORD *ptr, Prog *p, int sr, Channel **sel, int dn)
{
	int n;
	Array *a;
	Channel **ca, **ec;

	n = 0;
	a = (Array*)c;
	ca = (Channel**)a->data;
	ec = ca + a->len;
	while(ca < ec) {
		c = *ca;
		if(c != H && c->recv->prog)
			cqdelp(&c->recv, p);
		if(sr == 1 && *sel == c) {
			W(p->R.d) = dn;
			p->ptr = ptr + 1;
			ptr[0] = n;
			*sel = nil;
		}
		ca++;
		n++;
	}
}

/*
 * ALT Pass 1 - Count the number of ready channels and mark
 * each channel as ALT by this prog
 */
static int
altrdy(Alt *a, Prog *p)
{
	char *e;
	Type *t;
	int nrdy;
	Channel *c;
	Altc *ac, *eac;

	e = nil;
	nrdy = 0;

	ac = a->ac + a->nsend;
	eac = ac + a->nrecv;
	while(ac < eac) {
		c = ac->c;
		ac++;
		if(c == H) {
			e = exNilref;
			continue;
		}
		t = D2H(c)->t;
		if(t == &Tarray)
			nrdy += altmark(c, p);
		else {
			if(c->send->prog || CANGET(c))
				nrdy++;
			cqadd(&c->recv, p);
		}
	}

	ac = a->ac;
	eac = ac + a->nsend;
	while(ac < eac) {
		c = ac->c;
		ac++;
		if(c == H) {
			e = exNilref;
			continue;
		}
		if(c->recv->prog || CANPUT(c)) {
			if(c->recv->prog == p) {
				e = exAlt;
				continue;
			}
			nrdy++;
		}
		cqadd(&c->send, p);
	}

	if(e != nil) {
		altdone(a, p, nil, -1);
		error(e);
	}

	return nrdy;
}

/*
 * ALT Pass 3 - Pull out of an ALT cancelling the channel pointers in each item
 */
void
altdone(Alt *a, Prog *p, Channel *sel, int sr)
{
	int n;
	Type *t;
	Channel *c;
	Altc *ac, *eac;

	n = 0;
	ac = a->ac;
	eac = a->ac + a->nsend;
	while(ac < eac) {
		c = ac->c;
		if(c != H) {
			if(c->send->prog)
				cqdelp(&c->send, p);
			if(sr == 0 && c == sel) {
				p->ptr = ac->ptr;
				W(p->R.d) = n;
				sel = nil;
			}
		}
		ac++;
		n++;
	}

	eac = a->ac + a->nsend + a->nrecv;
	while(ac < eac) {
		c = ac->c;
		if(c != H) {
			t = D2H(c)->t;
			if(t == &Tarray)
				altunmark(c, ac->ptr, p, sr, &sel, n);
			else {
				if(c->recv->prog)
					cqdelp(&c->recv, p);
				if(sr == 1 && c == sel) {
					p->ptr = ac->ptr;
					W(p->R.d) = n;
					sel = nil;
				}
			}
		}
		ac++;
		n++;
	}
}

/*
 * ALT Pass 2 - Perform the communication on the chosen channel
 */
static void
altcomm(Alt *a, int which)
{
	Type *t;
	Array *r;
	int n, an;
	WORD *ptr;
	Altc *ac, *eac;
	Channel *c, **ca, **ec;

	n = 0;
	ac = a->ac;
	eac = ac + a->nsend;
	while(ac < eac) {
		c = ac->c;
		if((c->recv->prog != nil || CANPUT(c)) && which-- == 0) {
			W(R.d) = n;
			R.s = ac->ptr;
			R.d = &c;
			isend();
			return;
		}
		ac++;
		n++;
	}

	eac = eac + a->nrecv;
	while(ac < eac) {
		c = ac->c;
		t = D2H(c)->t;
		if(t == &Tarray) {
			an = 0;
			r = (Array*)c;
			ca = (Channel**)r->data;
			ec = ca + r->len;
			while(ca < ec) {
				c = *ca;
				if(c != H && (c->send->prog != nil || CANGET(c)) && which-- == 0) {
					W(R.d) = n;
					R.s = &c;
					ptr = ac->ptr;
					R.d = ptr + 1;
					ptr[0] = an;
					irecv();
					return;
				}
				ca++;
				an++;
			}
		}
		else
		if((c->send->prog != nil || CANGET(c)) && which-- == 0) {
			W(R.d) = n;
			R.s = &c;
			R.d = ac->ptr;
			irecv();
			return;	
		}
		ac++;
		n++;
	}
	return;
}

void
altgone(Prog *p)
{
	Alt *a;

	if (p->state == Palt) {
		a = p->R.s;
		altdone(a, p, nil, -1);
		p->kill = "alt channel hungup";
		addrun(p);
	}
}

void
xecalt(int block)
{
	Alt *a;
	Prog *p;
	int nrdy;
	static int xrand = -1;

	p = currun();

	a = R.s;
	nrdy = altrdy(a, p);
	if(nrdy == 0) {
		if(block) {
			delrun(Palt);
			p->R.s = R.s;
			p->R.d = R.d;
			R.IC = 1;
			R.t = 1;
			return;
		}
		W(R.d) = a->nsend + a->nrecv;
		altdone(a, p, nil, -1);
		return;
	}

	xrand += xrand;
	if(xrand < 0)
		xrand ^= 0x88888EEF;

	altcomm(a, xrand%nrdy);
	altdone(a, p, nil, -1);
}
