#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "runt.h"
#include "loadermod.h"
#include "raise.h"
#include <kernel.h>

static uchar	Instmap[] = Loader_Inst_map;
static Type*	Tinst;
static uchar	Tdescmap[] = Loader_Typedesc_map;
static Type*	Tdesc;
static uchar	Tlinkmap[] = Loader_Link_map;
static Type*	Tlink;

void
loadermodinit(void)
{
	sysinit();
	builtinmod("$Loader", Loadermodtab, Loadermodlen);
	Tinst = dtype(freeheap, sizeof(Loader_Inst), Instmap, sizeof(Instmap));
	Tdesc = dtype(freeheap, sizeof(Loader_Typedesc), Tdescmap, sizeof(Tdescmap));
	Tlink = dtype(freeheap, sizeof(Loader_Link), Tlinkmap, sizeof(Tlinkmap));
}

static void
brunpatch(Loader_Inst *ip, Module *m)
{
	switch(ip->op) {
	case ICALL:
	case IJMP:
	case IBEQW:
	case IBNEW:
	case IBLTW:
	case IBLEW:
	case IBGTW:
	case IBGEW:
	case IBEQB:
	case IBNEB:
	case IBLTB:
	case IBLEB:
	case IBGTB:
	case IBGEB:
	case IBEQF:
	case IBNEF:
	case IBLTF:
	case IBLEF:
	case IBGTF:
	case IBGEF:
	case IBEQC:
	case IBNEC:
	case IBLTC:
	case IBLEC:
	case IBGTC:
	case IBGEC:
	case IBEQL:
	case IBNEL:
	case IBLTL:
	case IBLEL:
	case IBGTL:
	case IBGEL:
	case ISPAWN:
		ip->dst = (Inst*)ip->dst - m->prog;
		break;
	}
}

void
Loader_ifetch(void *a)
{
	Heap *h;
	Array *ar;
	Module *m;
	Inst *i, *ie;
	Loader_Inst *li;
	F_Loader_ifetch *f;

	f = a;
	destroy(*f->ret);
	*f->ret = H;

	if(f->mp == H)
		return;
	m = f->mp->m;
	if(m == H)
		return;
	if(m->compiled) {
		kwerrstr("compiled module");
		return;
	}

	h = nheap(sizeof(Array)+m->nprog*sizeof(Loader_Inst));
	h->t = &Tarray;
	h->t->ref++;
	ar = H2D(Array*, h);
	ar->t = Tinst;
	Tinst->ref++;
	ar->len = m->nprog;
	ar->root = H;
	ar->data = (uchar*)ar+sizeof(Array);

	li = (Loader_Inst*)ar->data;
	i = m->prog;
	ie = i + m->nprog;
	while(i < ie) {
		li->op = i->op;
		li->addr = i->add;
		li->src = i->s.imm;
		li->dst = i->d.imm;
		li->mid = i->reg;
		if(UDST(i->add) == AIMM)
			brunpatch(li, m);
		li++;
		i++;
	}

	*f->ret = ar;
}

void
Loader_link(void *a)
{
	Link *p;
	Heap *h;
	Type **t;
	int nlink;
	Module *m;
	Array *ar;
	Loader_Link *ll;
	F_Loader_link *f;
	
	f = a;
	destroy(*f->ret);
	*f->ret = H;

	if(f->mp == H)
		return;
	m = f->mp->m;
	if(m == H)
		return;

	nlink = 0;
	for(p = m->ext; p->name; p++)
		nlink++;

	h = nheap(sizeof(Array)+nlink*sizeof(Loader_Link));
	h->t = &Tarray;
	h->t->ref++;
	ar = H2D(Array*, h);
	ar->t = Tlink;
	Tlink->ref++;
	ar->len = nlink;
	ar->root = H;
	ar->data = (uchar*)ar+sizeof(Array);

	ll = (Loader_Link*)ar->data + nlink;
	for(p = m->ext; p->name; p++) {
		ll--;
		ll->name = c2string(p->name, strlen(p->name));
		ll->sig = p->sig;
		if(m->prog == nil) {
			ll->pc = -1;
			ll->tdesc = -1;
		} else {
			ll->pc = p->u.pc - m->prog;
			ll->tdesc = 0;
			for(t = m->type; *t != p->frame; t++)
				ll->tdesc++;
		}
	}

	*f->ret = ar;
}

void
Loader_tdesc(void *a)
{
	int i;
	Heap *h;
	Type *t;
	Array *ar;
	Module *m;
	F_Loader_tdesc *f;
	Loader_Typedesc *lt;

	f = a;
	destroy(*f->ret);
	*f->ret = H;

	if(f->mp == H)
		return;
	m = f->mp->m;
	if(m == H)
		return;

	h = nheap(sizeof(Array)+m->ntype*sizeof(Loader_Typedesc));
	h->t = &Tarray;
	h->t->ref++;
	ar = H2D(Array*, h);
	ar->t = Tdesc;
	Tdesc->ref++;
	ar->len = m->ntype;
	ar->root = H;
	ar->data = (uchar*)ar+sizeof(Array);

	lt = (Loader_Typedesc*)ar->data;
	for(i = 0; i < m->ntype; i++) {
		t = m->type[i];
		lt->size = t->size;
		lt->map = H;
		if(t->np != 0)
			lt->map = mem2array(t->map, t->np);
		lt++;
	}

	*f->ret = ar;
}

void
Loader_newmod(void *a)
{
	Heap *h;
	Module *m;
	Array *ia;
	Modlink *ml;
	Inst *i, *ie;
	Loader_Inst *li;
	F_Loader_newmod *f;

	f = a;
	destroy(*f->ret);
	*f->ret = H;

	if(f->inst == H || f->data == H) {
		kwerrstr("nil parameters");
		return;
	}
	if(f->nlink < 0) {
		kwerrstr("bad nlink");
		return;
	}

	m = malloc(sizeof(Module));
	if(m == nil) {
		kwerrstr(exNomem);
		return;
	}
	m->origmp = H;
	m->ref = 1;
	m->ss = f->ss;
	m->name = strdup(string2c(f->name));
	m->path = strdup(m->name);
	m->ntype = 1;
	m->type = malloc(sizeof(Type*));
	if(m->name == nil || m->path == nil || m->type == nil) {
		kwerrstr(exNomem);
		goto bad;
	}
	m->origmp = (uchar*)f->data;
	h = D2H(f->data);
	h->ref++;
	Setmark(h);
	m->type[0] = h->t;
	h->t->ref++;

	ia = f->inst;
	m->nprog = ia->len;
	m->prog = malloc(m->nprog*sizeof(Inst));
	if(m->prog == nil)
		goto bad;
	i = m->prog;
	ie = i + m->nprog;
	li = (Loader_Inst*)ia->data;
	while(i < ie) {
		i->op = li->op;
		i->add = li->addr;
		i->reg = li->mid;
		i->s.imm = li->src;
		i->d.imm = li->dst;
		if(brpatch(i, m) == 0) {
			kwerrstr("bad branch addr");
			goto bad;
		}
		i++;
		li++;
	}
	m->entryt = nil;
	m->entry = m->prog;

	ml = mklinkmod(m, f->nlink);
	ml->MP = m->origmp;
	m->origmp = H;
	m->pctab = nil;
	*f->ret = ml;
	return;
bad:
	destroy(m->origmp);
	freemod(m);
}

void
Loader_tnew(void *a)
{
	int mem;
	Module *m;
	Type *t, **nt;
	Array *ar, az;
	F_Loader_tnew *f;

	f = a;
	*f->ret = -1;
	if(f->mp == H)
		return;
	m = f->mp->m;
	if(m == H)
		return;
	if(m->origmp != H){
		kwerrstr("need newmod");
		return;
	}

	ar = f->map;
	if(ar == H) {
		ar = &az;
		ar->len = 0;
		ar->data = nil;
	}

	t = dtype(freeheap, f->size, ar->data, ar->len);
	if(t == nil)
		return;

	mem = (m->ntype+1)*sizeof(Type*);
	if(msize(m->type) > mem) {
		*f->ret = m->ntype;
		m->type[m->ntype++] = t;
		return;
	}
	nt = realloc(m->type, mem);
	if(nt == nil) {
		kwerrstr(exNomem);
		return;
	}
	m->type = nt;
	f->mp->type = nt;
	*f->ret = m->ntype;
	m->type[m->ntype++] = t;
}

void
Loader_ext(void *a)
{
	Modl *l;
	Module *m;
	Modlink *ml;
	F_Loader_ext *f;

	f = a;
	*f->ret = -1;
	if(f->mp == H) {
		kwerrstr("nil mp");
		return;
	}
	ml = f->mp;
	m = ml->m;
	if(f->tdesc < 0 || f->tdesc >= m->ntype) {
		kwerrstr("bad tdesc");
		return;
	}
	if(f->pc < 0 || f->pc >= m->nprog) {
		kwerrstr("bad pc");
		return;
	}
	if(f->idx < 0 || f->idx >= ml->nlinks) {
		kwerrstr("bad idx");
		return;
	}
	l = &ml->links[f->idx];
	l->u.pc = m->prog + f->pc;
	l->frame = m->type[f->tdesc];
	*f->ret = 0;
}

void
Loader_dnew(void *a)
{
	F_Loader_dnew *f;
	Heap *h;
	Array *ar, az;
	Type *t;
 
        f = a;
        *f->ret = H;
        if(f->map == H)
                return;
        ar = f->map;
        if(ar == H) {
                ar = &az;
                ar->len = 0;
                ar->data = nil;
        }
        t = dtype(freeheap, f->size, ar->data, ar->len);
        if(t == nil) {
                kwerrstr(exNomem);
                return;
        }

	h=heapz(t);
	if(h == nil) {
		freetype(t);
		kwerrstr(exNomem);
		return;
        }
		
	*f->ret=H2D(Loader_Niladt*, h);
}

void
Loader_compile(void *a)
{
	Module *m;
	F_Loader_compile *f;

	f = a;
	*f->ret = -1;
	if(f->mp == H) {
		kwerrstr("nil mp");
		return;
	}
	m = f->mp->m;
	if(m->compiled) {
		kwerrstr("compiled module");
		return;
	}
	*f->ret = 0;
	m->origmp = f->mp->MP;
	if(cflag || f->flag)
	if(compile(m, m->nprog, f->mp)) {
		f->mp->prog = m->prog;
		f->mp->compiled = 1;
	} else
		*f->ret = -1;
	m->origmp = H;
}
