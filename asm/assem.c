#include "asm.h"
#include "y.tab.h"

typedef struct Exc Exc;
typedef struct Etab Etab;
typedef struct Ldts Ldts;
typedef struct Ldt Ldt;

struct Ldts
{
	int n;
	Ldt *ldt;
	Ldts *next;
};

struct Ldt{
	int sign;
	char *name;
	Ldt *next;
};

struct Exc
{
	int n1, n2, n3, n4, n5, n6;
	Etab *etab;
	Exc	*next;
};

struct Etab
{
	int n;
	char *name;
	Etab *next;
};

static int inldt;
static int nldts;
static Ldts *aldts;
static Ldts *curl;
static int nexcs;
static Exc* aexcs;
static Exc* cure;
static char *srcpath;

static void ldtw(int);
static void ldte(int, char*);

List*
newa(int i, int size)
{
	List *l;
	Array *a;

	a = malloc(sizeof(Array));
	a->i = i;
	a->size = size;
	l = malloc(sizeof(List));
	l->u.a = a;
	l->link = nil;

	return l;
}

List*
newi(vlong v, List *l)
{
	List *n, *t;

	n = malloc(sizeof(List));
	if(l == nil)
		l = n;
	else {
		for(t = l; t->link; t = t->link)
			;
		t->link = n;
	}
	n->link = nil;
	n->u.ival = v;
	n->addr = -1;

	return l;
}

List*
news(String *s, List *l)
{
	List *n;

	n = malloc(sizeof(List));
	n->link = l;
	l = n;
	n->u.str = s;
	n->addr = -1;
	return l;
}

int
digit(char x)
{
	if(x >= 'A' && x <= 'F')
		return x - 'A' + 10;
	if(x >= 'a' && x <= 'f')
		return x - 'a' + 10;
	if(x >= '0' && x <= '9')
		return x - '0';
	diag("bad hex value in pointers");
	return 0;
}

void
heap(int id, int size, String *ptr)
{
	Desc *d, *f;
	char *p;
	int k, i;

	d = malloc(sizeof(Desc));
	d->id = id;
	d->size = size;
	size /= IBY2WD;
	d->map = malloc(size);
	d->np = 0;
	if(dlist == nil)
		dlist = d;
	else {
		for(f = dlist; f->link != nil; f = f->link)
			;
		f->link = d;
	}
	d->link = nil;
	dcount++;

	if(ptr == 0)
		return;
	if(--ptr->len & 1) {
		diag("pointer descriptor has bad length");
		return;	
	}

	k = 0;
	p = ptr->string;
	for(i = 0; i < ptr->len; i += 2) {
		d->map[k++] = (digit(p[0])<<4)|digit(p[1]);
		if(k > size) {
			diag("pointer descriptor too long");
			break;
		}
		p += 2;	
	}
	d->np = k;
}

void
conout(int val)
{
	if(val >= -64 && val <= 63) {
		Bputc(bout, val & ~0x80);
		return;
	}
	if(val >= -8192 && val <= 8191) {
		Bputc(bout, ((val>>8) & ~0xC0) | 0x80);
		Bputc(bout, val);
		return;
	}
	if(val < 0 && ((val >> 29) & 0x7) != 7
	|| val > 0 && (val >> 29) != 0)
		diag("overflow in constant 0x%lux\n", val);
	Bputc(bout, (val>>24) | 0xC0);
	Bputc(bout, val>>16);
	Bputc(bout, val>>8);
	Bputc(bout, val);
}

void
aout(Addr *a)
{
	if(a == nil)
		return;
	if(a->mode & AIND)
		conout(a->off);
	conout(a->val);
}

void
lout(void)
{
	char *p;
	Link *l;

	if(module == nil)
		module = enter("main", 0);

	for(p = module->name; *p; p++)
		Bputc(bout, *p);
	Bputc(bout, '\0');

	for(l = links; l; l = l->link) {
		conout(l->addr);
		conout(l->desc);
		Bputc(bout, l->type>>24);
		Bputc(bout, l->type>>16);
		Bputc(bout, l->type>>8);
		Bputc(bout, l->type);
		for(p = l->name; *p; p++)
			Bputc(bout, *p);
		Bputc(bout, '\0');
	}
}

void
ldtout(void)
{
	Ldts *ls;
	Ldt *l;
	char *p;

	conout(nldts);
	for(ls = aldts; ls != nil; ls = ls->next){
		conout(ls->n);
		for(l = ls->ldt; l != nil; l = l->next){
			Bputc(bout, l->sign>>24);
			Bputc(bout, l->sign>>16);
			Bputc(bout, l->sign>>8);
			Bputc(bout, l->sign);
			for(p = l->name; *p; p++)
				Bputc(bout, *p);
			Bputc(bout, '\0');
		}
	}
	conout(0);
}

void
excout(void)
{
	Exc *e;
	Etab *et;
	char *p;

	if(nexcs == 0)
		return;
	conout(nexcs);
	for(e = aexcs; e != nil; e = e->next){
		conout(e->n3);
		conout(e->n1);
		conout(e->n2);
		conout(e->n4);
		conout(e->n5|(e->n6<<16));
		for(et = e->etab; et != nil; et = et->next){
			if(et->name != nil){
				for(p = et->name; *p; p++)
					Bputc(bout, *p);
				Bputc(bout, '\0');
			}
			conout(et->n);
		}
	}
	conout(0);
}

void
srcout(void)
{
	char *p;

	if(srcpath == nil)
		return;
	for(p = srcpath; *p; p++)
		Bputc(bout, *p);
	Bputc(bout, '\0');
}

void
assem(Inst *i)
{
	Desc *d;
	Inst *f, *link;
	int pc, n, hints, o;

	f = 0;
	while(i) {
		link = i->link;
		i->link = f;
		f = i;
		i = link;
	}
	i = f;

	pc = 0;
	for(f = i; f; f = f->link) {
		f->pc = pc++;
		if(f->sym != nil)
			f->sym->value = f->pc;
	}

	if(pcentry >= pc)
		diag("entry pc out of range");
	if(dentry >= dcount)
		diag("entry descriptor out of range");

	conout(XMAGIC);
	hints = 0;
	if(mustcompile)
		hints |= MUSTCOMPILE;
	if(dontcompile)
		hints |= DONTCOMPILE;
	hints |= HASLDT;
	if(nexcs > 0)
		hints |= HASEXCEPT;
	conout(hints);		/* Runtime flags */
	conout(1024);		/* default stack size */
	conout(pc);
	conout(dseg);
	conout(dcount);
	conout(nlink);
	conout(pcentry);
	conout(dentry);

	for(f = i; f; f = f->link) {
		if(f->dst && f->dst->sym) {
			f->dst->mode = AIMM;
			f->dst->val = f->dst->sym->value;
		}
		o = opcode(f);
		if(o == IRAISE){
			f->src = f->dst;
			f->dst = nil;
		}
		Bputc(bout, o);
		n = 0;
		if(f->src)
			n |= SRC(f->src->mode);
		else
			n |= SRC(AXXX);
		if(f->dst)
			n |= DST(f->dst->mode);
		else
			n |= DST(AXXX);
		if(f->reg)
			n |= f->reg->mode;
		else
			n |= AXNON;
		Bputc(bout, n);
		aout(f->reg);
		aout(f->src);
		aout(f->dst);

		if(listing)
			print("%4ld %i\n", f->pc, f);
	}

	for(d = dlist; d; d = d->link) {
		conout(d->id);
		conout(d->size);
		conout(d->np);
		for(n = 0; n < d->np; n++)
			Bputc(bout, d->map[n]);
	}

	dout();
	lout();
	ldtout();
	excout();
	srcout();
}

void
data(int type, int addr, List *l)
{
	List *f;

	if(inldt){
		ldtw(l->u.ival);
		return;
	}

	l->type = type;
	l->addr = addr;

	if(mdata == nil)
		mdata = l;
	else {
		for(f = mdata; f->link != nil; f = f->link)
			;
		f->link = l;
	}
}

void
ext(int addr, int type, String *s)
{
	int i;
	char *p;
	List *n;

	if(inldt){
		ldte(type, s->string);
		return;
	}

	data(DEFW, addr, newi(type, nil));

	n = nil;
	p = s->string;
	for(i = 0; i < s->len; i++)
		n = newi(*p++, n);
	data(DEFB, addr+IBY2WD, n);

	if(addr+s->len > dseg)
		diag("ext beyond mp");
}

void
mklink(int desc, int addr, int type, String *s)
{
	Link *l;

	for(l = links; l; l = l->link)
		if(strcmp(l->name, s->string) == 0)
			diag("%s already defined", s->string);

	nlink++;
	l = malloc(sizeof(Link));
	l->desc = desc;
	l->addr = addr;
	l->type = type;
	l->name = s->string;
	l->link = nil;

	if(links == nil)
		links = l;
	else
		linkt->link = l;
	linkt = l;
}

void
dout(void)
{
	int n, i;
	List *l, *e;

	e = nil;
	for(l = mdata; l; l = e) {
		switch(l->type) {
		case DEFB:
			n = 1;
			for(e = l->link; e && e->addr == -1; e = e->link)
				n++;
			if(n < DMAX)
				Bputc(bout, DBYTE(DEFB, n));
			else {
				Bputc(bout, DBYTE(DEFB, 0));
				conout(n);
			}
			conout(l->addr);
			while(l != e) {
				Bputc(bout, l->u.ival);
				l = l->link;
			}
			break;
		case DEFW:
			n = 1;
			for(e = l->link; e && e->addr == -1; e = e->link)
				n++;
			if(n < DMAX)
				Bputc(bout, DBYTE(DEFW, n));
			else {
				Bputc(bout, DBYTE(DEFW, 0));
				conout(n);
			}
			conout(l->addr);
			while(l != e) {
				n = (int)l->u.ival;
				Bputc(bout, n>>24);
				Bputc(bout, n>>16);
				Bputc(bout, n>>8);
				Bputc(bout, n);
				l = l->link;
			}
			break;
		case DEFL:
			n = 1;
			for(e = l->link; e && e->addr == -1; e = e->link)
				n++;
			if(n < DMAX)
				Bputc(bout, DBYTE(DEFL, n));
			else {
				Bputc(bout, DBYTE(DEFL, 0));
				conout(n);
			}
			conout(l->addr);
			while(l != e) {
				Bputc(bout, l->u.ival>>56);
				Bputc(bout, l->u.ival>>48);
				Bputc(bout, l->u.ival>>40);
				Bputc(bout, l->u.ival>>32);
				Bputc(bout, l->u.ival>>24);
				Bputc(bout, l->u.ival>>16);
				Bputc(bout, l->u.ival>>8);
				Bputc(bout, l->u.ival);
				l = l->link;
			}
			break;
		case DEFF:
			n = 1;
			for(e = l->link; e && e->addr == -1; e = e->link)
				n++;
			if(n < DMAX)
				Bputc(bout, DBYTE(DEFF, n));
			else {
				Bputc(bout, DBYTE(DEFF, 0));
				conout(n);
			}
			conout(l->addr);
			while(l != e) {
				Bputc(bout, l->u.ival>>56);
				Bputc(bout, l->u.ival>>48);
				Bputc(bout, l->u.ival>>40);
				Bputc(bout, l->u.ival>>32);
				Bputc(bout, l->u.ival>>24);
				Bputc(bout, l->u.ival>>16);
				Bputc(bout, l->u.ival>>8);
				Bputc(bout, l->u.ival);
				l = l->link;
			}
			break;
		case DEFS:
			n = l->u.str->len-1;
			if(n < DMAX && n != 0)
				Bputc(bout, DBYTE(DEFS, n));
			else {
				Bputc(bout, DBYTE(DEFS, 0));
				conout(n);
			}
			conout(l->addr);
			for(i = 0; i < n; i++)
				Bputc(bout, l->u.str->string[i]);

			e = l->link;
			break;
		case DEFA:
			Bputc(bout, DBYTE(DEFA, 1));
			conout(l->addr);
			Bputc(bout, l->u.a->i>>24);
			Bputc(bout, l->u.a->i>>16);
			Bputc(bout, l->u.a->i>>8);
			Bputc(bout, l->u.a->i);
			Bputc(bout, l->u.a->size>>24);
			Bputc(bout, l->u.a->size>>16);
			Bputc(bout, l->u.a->size>>8);
			Bputc(bout, l->u.a->size);
			e = l->link;
			break;
		case DIND:
			Bputc(bout, DBYTE(DIND, 1));
			conout(l->addr);
			Bputc(bout, 0);
			Bputc(bout, 0);
			Bputc(bout, 0);
			Bputc(bout, 0);
			e = l->link;
			break;
		case DAPOP:
			Bputc(bout, DBYTE(DAPOP, 1));
			conout(0);
			e = l->link;
			break;
		}
	}

	Bputc(bout, DBYTE(DEFZ, 0));
}

void
ldts(int n)
{
	nldts = n;
	inldt = 1;
}

static void
ldtw(int n)
{
	Ldts *ls, *p;

	ls = malloc(sizeof(Ldts));
	ls->n = n;
	ls->ldt = nil;
	ls->next = nil;
	if(aldts == nil)
		aldts = ls;
	else{
		for(p = aldts; p->next != nil; p = p->next)
			;
		p->next = ls;
	}
	curl = ls;
}

static void
ldte(int n, char *s)
{
	Ldt *l, *p;

	l = malloc(sizeof(Ldt));
	l->sign = n;
	l->name = s;
	l->next = nil;
	if(curl->ldt == nil)
		curl->ldt = l;
	else{
		for(p = curl->ldt; p->next != nil; p = p->next)
			;
		p->next = l;
	}
}

void
excs(int n)
{
	nexcs = n;
}

void
exc(int n1, int n2, int n3, int n4, int n5, int n6)
{
	Exc *e, *es;

	e = malloc(sizeof(Exc));
	e->n1 = n1;
	e->n2 = n2;
	e->n3 = n3;
	e->n4 = n4;
	e->n5 = n5;
	e->n6 = n6;
	e->etab = nil;
	e->next = nil;
	if(aexcs == nil)
		aexcs = e;
	else{
		for(es = aexcs; es->next != nil; es = es->next)
			;
		es->next = e;
	}
	cure = e;
}

void
etab(String *s, int n)
{
	Etab *et, *ets;

	et = malloc(sizeof(Etab));
	et->n = n;
	if(s != nil)
		et->name = s->string;
	else
		et->name = nil;
	et->next = nil;
	if(cure->etab == nil)
		cure->etab = et;
	else{
		for(ets = cure->etab; ets->next != nil; ets = ets->next)
			;
		ets->next = et;
	}
}

void
source(String *s)
{
	srcpath = s->string;
}
