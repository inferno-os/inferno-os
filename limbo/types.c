#include "limbo.h"
#include "mp.h"
#include "libsec.h"

char *kindname[Tend] =
{
	/* Tnone */	"no type",
	/* Tadt */	"adt",
	/* Tadtpick */	"adt",
	/* Tarray */	"array",
	/* Tbig */	"big",
	/* Tbyte */	"byte",
	/* Tchan */	"chan",
	/* Treal */	"real",
	/* Tfn */	"fn",
	/* Tint */	"int",
	/* Tlist */	"list",
	/* Tmodule */	"module",
	/* Tref */	"ref",
	/* Tstring */	"string",
	/* Ttuple */	"tuple",
	/* Texception */	"exception",
	/* Tfix */	"fixed point",
	/* Tpoly */	"polymorphic",

	/* Tainit */	"array initializers",
	/* Talt */	"alt channels",
	/* Tany */	"polymorphic type",
	/* Tarrow */	"->",
	/* Tcase */	"case int labels",
	/* Tcasel */	"case big labels",
	/* Tcasec */	"case string labels",
	/* Tdot */	".",
	/* Terror */	"type error",
	/* Tgoto */	"goto labels",
	/* Tid */	"id",
	/* Tiface */	"module interface",
	/* Texcept */	"exception handler table",
	/* Tinst */	"instantiated type",
};

Tattr tattr[Tend] =
{
	/*		 isptr	refable	conable	big	vis */
	/* Tnone */	{ 0,	0,	0,	0,	0, },
	/* Tadt */	{ 0,	1,	1,	1,	1, },
	/* Tadtpick */	{ 0,	1,	0,	1,	1, },
	/* Tarray */	{ 1,	0,	0,	0,	1, },
	/* Tbig */	{ 0,	0,	1,	1,	1, },
	/* Tbyte */	{ 0,	0,	1,	0,	1, },
	/* Tchan */	{ 1,	0,	0,	0,	1, },
	/* Treal */	{ 0,	0,	1,	1,	1, },
	/* Tfn */	{ 0,	1,	0,	0,	1, },
	/* Tint */	{ 0,	0,	1,	0,	1, },
	/* Tlist */	{ 1,	0,	0,	0,	1, },
	/* Tmodule */	{ 1,	0,	0,	0,	1, },
	/* Tref */	{ 1,	0,	0,	0,	1, },
	/* Tstring */	{ 1,	0,	1,	0,	1, },
	/* Ttuple */	{ 0,	1,	1,	1,	1, },
	/* Texception */	{ 0,	0,	0,	1,	1, },
	/* Tfix */	{ 0,	0,	1,	0,	1, },
	/* Tpoly */	{ 1,	0,	0,	0,	1, },

	/* Tainit */	{ 0,	0,	0,	1,	0, },
	/* Talt */	{ 0,	0,	0,	1,	0, },
	/* Tany */	{ 1,	0,	0,	0,	0, },
	/* Tarrow */	{ 0,	0,	0,	0,	1, },
	/* Tcase */	{ 0,	0,	0,	1,	0, },
	/* Tcasel */	{ 0,	0,	0,	1,	0, },
	/* Tcasec */	{ 0,	0,	0,	1,	0, },
	/* Tdot */	{ 0,	0,	0,	0,	1, },
	/* Terror */	{ 0,	1,	1,	0,	0, },
	/* Tgoto */	{ 0,	0,	0,	1,	0, },
	/* Tid */	{ 0,	0,	0,	0,	1, },
	/* Tiface */	{ 0,	0,	0,	1,	0, },
	/* Texcept */	{ 0,	0,	0,	1,	0, },
	/* Tinst */	{ 0,	1,	1,	1,	1, },
};

static	Teq	*eqclass[Tend];

static	Type	ztype;
static	int	eqrec;
static	int	eqset;
static	int	tcomset;

static	int	idcompat(Decl*, Decl*, int, int);
static	int	rtcompat(Type *t1, Type *t2, int any, int);
static	int	assumeteq(Type *t1, Type *t2);
static	int	assumetcom(Type *t1, Type *t2);
static	int	cleartcomrec(Type *t);
static	int	rtequal(Type*, Type*);
static	int	cleareqrec(Type*);
static	int	idequal(Decl*, Decl*, int, int*);
static	int	pyequal(Type*, Type*);
static	int	rtsign(Type*, uchar*, int, int);
static	int	clearrec(Type*);
static	int	idsign(Decl*, int, uchar*, int, int);
static	int	idsign1(Decl*, int, uchar*, int, int);
static	int	raisessign(Node *n, uchar *sig, int lensig, int spos);
static	void	ckfix(Type*, double);
static	int	fnunify(Type*, Type*, Tpair**, int);
static	int	rtunify(Type*, Type*, Tpair**, int);
static	int	idunify(Decl*, Decl*, Tpair**, int);
static	int	toccurs(Type*, Tpair**);
static	int	fncleareqrec(Type*, Type*);
static	Type*	comtype(Src*, Type*, Decl*);
static	Type*	duptype(Type*);
static	int	tpolys(Type*);

static void
addtmap(Type *t1, Type *t2, Tpair **tpp)
{
	Tpair *tp;

	tp = allocmem(sizeof *tp);
	tp->t1 = t1;
	tp->t2 = t2;
	tp->nxt = *tpp;
	*tpp = tp;
}

Type*
valtmap(Type *t, Tpair *tp)
{
	for( ; tp != nil; tp = tp->nxt)
		if(tp->t1 == t)
			return tp->t2;
	return t;
}

Typelist*
addtype(Type *t, Typelist *hd)
{
	Typelist *tl, *p;

	tl = allocmem(sizeof(*tl));
	tl->t = t;
	tl->nxt = nil;
	if(hd == nil)
		return tl;
	for(p = hd; p->nxt != nil; p = p->nxt)
		;
	p->nxt = tl;
	return hd;
}

void
typeinit(void)
{
	Decl *id;

	anontupsym = enter(".tuple", 0);

	ztype.sbl = -1;
	ztype.ok = 0;
	ztype.rec = 0;

	tbig = mktype(&noline, &noline, Tbig, nil, nil);
	tbig->size = IBY2LG;
	tbig->align = IBY2LG;
	tbig->ok = OKmask;

	tbyte = mktype(&noline, &noline, Tbyte, nil, nil);
	tbyte->size = 1;
	tbyte->align = 1;
	tbyte->ok = OKmask;

	tint = mktype(&noline, &noline, Tint, nil, nil);
	tint->size = IBY2WD;
	tint->align = IBY2WD;
	tint->ok = OKmask;

	treal = mktype(&noline, &noline, Treal, nil, nil);
	treal->size = IBY2FT;
	treal->align = IBY2FT;
	treal->ok = OKmask;

	tstring = mktype(&noline, &noline, Tstring, nil, nil);
	tstring->size = IBY2WD;
	tstring->align = IBY2WD;
	tstring->ok = OKmask;

	texception = mktype(&noline, &noline, Texception, nil, nil);
	texception->size = IBY2WD;
	texception->align = IBY2WD;
	texception->ok = OKmask;

	tany = mktype(&noline, &noline, Tany, nil, nil);
	tany->size = IBY2WD;
	tany->align = IBY2WD;
	tany->ok = OKmask;

	tnone = mktype(&noline, &noline, Tnone, nil, nil);
	tnone->size = 0;
	tnone->align = 1;
	tnone->ok = OKmask;

	terror = mktype(&noline, &noline, Terror, nil, nil);
	terror->size = 0;
	terror->align = 1;
	terror->ok = OKmask;

	tunknown = mktype(&noline, &noline, Terror, nil, nil);
	tunknown->size = 0;
	tunknown->align = 1;
	tunknown->ok = OKmask;

	tfnptr = mktype(&noline, &noline, Ttuple, nil, nil);
	id = tfnptr->ids = mkids(&nosrc, nil, tany, nil);
	id->store = Dfield;
	id->offset = 0;
	id->sym = enter("t0", 0);
	id->src = nosrc;
	id = tfnptr->ids->next = mkids(&nosrc, nil, tint, nil);
	id->store = Dfield;
	id->offset = IBY2WD;
	id->sym = enter("t1", 0);
	id->src = nosrc;

	rtexception = mktype(&noline, &noline, Tref, texception, nil);
	rtexception->size = IBY2WD;
	rtexception->align = IBY2WD;
	rtexception->ok = OKmask;
}

void
typestart(void)
{
	descriptors = nil;
	nfns = 0;
	nadts = 0;
	selfdecl = nil;
	if(tfnptr->decl != nil)
		tfnptr->decl->desc = nil;

	memset(eqclass, 0, sizeof eqclass);

	typebuiltin(mkids(&nosrc, enter("int", 0), nil, nil), tint);
	typebuiltin(mkids(&nosrc, enter("big", 0), nil, nil), tbig);
	typebuiltin(mkids(&nosrc, enter("byte", 0), nil, nil), tbyte);
	typebuiltin(mkids(&nosrc, enter("string", 0), nil, nil), tstring);
	typebuiltin(mkids(&nosrc, enter("real", 0), nil, nil), treal);
}

Teq*
modclass(void)
{
	return eqclass[Tmodule];
}

Type*
mktype(Line *start, Line *stop, int kind, Type *tof, Decl *args)
{
	Type *t;

	t = allocmem(sizeof *t);
	*t = ztype;
	t->src.start = *start;
	t->src.stop = *stop;
	t->kind = kind;
	t->tof = tof;
	t->ids = args;
	return t;
}

Type*
mktalt(Case *c)
{
	Type *t;
	char buf[32];
	static int nalt;

	t = mktype(&noline, &noline, Talt, nil, nil);
	t->decl = mkdecl(&nosrc, Dtype, t);
	seprint(buf, buf+sizeof(buf), ".a%d", nalt++);
	t->decl->sym = enter(buf, 0);
	t->cse = c;
	return usetype(t);
}

/*
 * copy t and the top level of ids
 */
Type*
copytypeids(Type *t)
{
	Type *nt;
	Decl *id, *new, *last;

	nt = allocmem(sizeof *nt);
	*nt = *t;
	last = nil;
	for(id = t->ids; id != nil; id = id->next){
		new = allocmem(sizeof *id);
		*new = *id;
		if(last == nil)
			nt->ids = new;
		else
			last->next = new;
		last = new;
	}
	return nt;
}

/*
 * make each of the ids have type t
 */
Decl*
typeids(Decl *ids, Type *t)
{
	Decl *id;

	if(ids == nil)
		return nil;

	ids->ty = t;
	for(id = ids->next; id != nil; id = id->next){
		id->ty = t;
	}
	return ids;
}

void
typebuiltin(Decl *d, Type *t)
{
	d->ty = t;
	t->decl = d;
	installids(Dtype, d);
}

Node *
fielddecl(int store, Decl *ids)
{
	Node *n;

	n = mkn(Ofielddecl, nil, nil);
	n->decl = ids;
	for(; ids != nil; ids = ids->next)
		ids->store = store;
	return n;
}

Node *
typedecl(Decl *ids, Type *t)
{
	Node *n;

	if(t->decl == nil)
		t->decl = ids;
	n = mkn(Otypedecl, nil, nil);
	n->decl = ids;
	n->ty = t;
	for(; ids != nil; ids = ids->next)
		ids->ty = t;
	return n;
}

void
typedecled(Node *n)
{
	installids(Dtype, n->decl);
}

Node *
adtdecl(Decl *ids, Node *fields)
{
	Node *n;
	Type *t;

	n = mkn(Oadtdecl, nil, nil);
	t = mktype(&ids->src.start, &ids->src.stop, Tadt, nil, nil);
	n->decl = ids;
	n->left = fields;
	n->ty = t;
	t->decl = ids;
	for(; ids != nil; ids = ids->next)
		ids->ty = t;
	return n;
}

void
adtdecled(Node *n)
{
	Decl *d, *ids;

	d = n->ty->decl;
	installids(Dtype, d);
	if(n->ty->polys != nil){
		pushscope(nil, Sother);
		installids(Dtype, n->ty->polys);
	}
	pushscope(nil, Sother);
	fielddecled(n->left);
	n->ty->ids = popscope();
	if(n->ty->polys != nil)
		n->ty->polys = popscope();
	for(ids = n->ty->ids; ids != nil; ids = ids->next)
		ids->dot = d;
}

void
fielddecled(Node *n)
{
	for(; n != nil; n = n->right){
		switch(n->op){
		case Oseq:
			fielddecled(n->left);
			break;
		case Oadtdecl:
			adtdecled(n);
			return;
		case Otypedecl:
			typedecled(n);
			return;
		case Ofielddecl:
			installids(Dfield, n->decl);
			return;
		case Ocondecl:
			condecled(n);
			gdasdecl(n->right);
			return;
		case Oexdecl:
			exdecled(n);
			return;
		case Opickdecl:
			pickdecled(n);
			return;
		default:
			fatal("can't deal with %O in fielddecled", n->op);
		}
	}
}

int
pickdecled(Node *n)
{
	Decl *d;
	int tag;

	if(n == nil)
		return 0;
	tag = pickdecled(n->left);
	pushscope(nil, Sother);
	fielddecled(n->right->right);
	d = n->right->left->decl;
	d->ty->ids = popscope();
	installids(Dtag, d);
	for(; d != nil; d = d->next)
		d->tag = tag++;
	return tag;
}

/*
 * make the tuple type used to initialize adt t
 */
Type*
mkadtcon(Type *t)
{
	Decl *id, *new, *last;
	Type *nt;

	nt = allocmem(sizeof *nt);
	*nt = *t;
	last = nil;
	nt->ids = nil;
	nt->kind = Ttuple;
	for(id = t->ids; id != nil; id = id->next){
		if(id->store != Dfield)
			continue;
		new = allocmem(sizeof *id);
		*new = *id;
		new->cyc = 0;
		if(last == nil)
			nt->ids = new;
		else
			last->next = new;
		last = new;
	}
	last->next = nil;
	return nt;
}

/*
 * make the tuple type used to initialize t,
 * an adt with pick fields tagged by tg
 */
Type*
mkadtpickcon(Type *t, Type *tgt)
{
	Decl *id, *new, *last;
	Type *nt;

	last = mkids(&tgt->decl->src, nil, tint, nil);
	last->store = Dfield;
	nt = mktype(&t->src.start, &t->src.stop, Ttuple, nil, last);
	for(id = t->ids; id != nil; id = id->next){
		if(id->store != Dfield)
			continue;
		new = allocmem(sizeof *id);
		*new = *id;
		new->cyc = 0;
		last->next = new;
		last = new;
	}
	for(id = tgt->ids; id != nil; id = id->next){
		if(id->store != Dfield)
			continue;
		new = allocmem(sizeof *id);
		*new = *id;
		new->cyc = 0;
		last->next = new;
		last = new;
	}
	last->next = nil;
	return nt;
}

/*
 * make an identifier type
 */
Type*
mkidtype(Src *src, Sym *s)
{
	Type *t;

	t = mktype(&src->start, &src->stop, Tid, nil, nil);
	if(s->unbound == nil){
		s->unbound = mkdecl(src, Dunbound, nil);
		s->unbound->sym = s;
	}
	t->decl = s->unbound;
	return t;
}

/*
 * make a qualified type for t->s
 */
Type*
mkarrowtype(Line *start, Line *stop, Type *t, Sym *s)
{
	Src src;

	src.start = *start;
	src.stop = *stop;
	t = mktype(start, stop, Tarrow, t, nil);
	if(s->unbound == nil){
		s->unbound = mkdecl(&src, Dunbound, nil);
		s->unbound->sym = s;
	}
	t->decl = s->unbound;
	return t;
}

/*
 * make a qualified type for t.s
 */
Type*
mkdottype(Line *start, Line *stop, Type *t, Sym *s)
{
	Src src;

	src.start = *start;
	src.stop = *stop;
	t = mktype(start, stop, Tdot, t, nil);
	if(s->unbound == nil){
		s->unbound = mkdecl(&src, Dunbound, nil);
		s->unbound->sym = s;
	}
	t->decl = s->unbound;
	return t;
}

Type*
mkinsttype(Src* src, Type *tt, Typelist *tl)
{
	Type *t;

	t = mktype(&src->start, &src->stop, Tinst, tt, nil);
	t->u.tlist = tl;
	return t;
}

/*
 * look up the name f in the fields of a module, adt, or tuple
 */
Decl*
namedot(Decl *ids, Sym *s)
{
	for(; ids != nil; ids = ids->next)
		if(ids->sym == s)
			return ids;
	return nil;
}

/*
 * complete the declaration of an adt
 * methods frames get sized in module definition or during function definition
 * place the methods at the end of the field list
 */
void
adtdefd(Type *t)
{
	Decl *d, *id, *next, *aux, *store, *auxhd, *tagnext;
	int seentags;

	if(debug['x'])
		print("adt %T defd\n", t);
	d = t->decl;
	tagnext = nil;
	store = nil;
	for(id = t->polys; id != nil; id = id->next){
		id->store = Dtype;
		id->ty = verifytypes(id->ty, d, nil);
	}
	for(id = t->ids; id != nil; id = next){
		if(id->store == Dtag){
			if(t->tags != nil)
				error(id->src.start, "only one set of pick fields allowed");
			tagnext = pickdefd(t, id);
			next = tagnext;
			if(store != nil)
				store->next = next;
			else
				t->ids = next;
			continue;
		}else{
			id->dot = d;
			next = id->next;
			store = id;
		}
	}
	aux = nil;
	store = nil;
	auxhd = nil;
	seentags = 0;
	for(id = t->ids; id != nil; id = next){
		if(id == tagnext)
			seentags = 1;

		next = id->next;
		id->dot = d;
		id->ty = topvartype(verifytypes(id->ty, d, nil), id, 1, 1);
		if(id->store == Dfield && id->ty->kind == Tfn)
			id->store = Dfn;
		if(id->store == Dfn || id->store == Dconst){
			if(store != nil)
				store->next = next;
			else
				t->ids = next;
			if(aux != nil)
				aux->next = id;
			else
				auxhd = id;
			aux = id;
		}else{
			if(seentags)
				error(id->src.start, "pick fields must be the last data fields in an adt");
			store = id;
		}
	}
	if(aux != nil)
		aux->next = nil;
	if(store != nil)
		store->next = auxhd;
	else
		t->ids = auxhd;

	for(id = t->tags; id != nil; id = id->next){
		id->ty = verifytypes(id->ty, d, nil);
		if(id->ty->tof == nil)
			id->ty->tof = mkadtpickcon(t, id->ty);
	}
}

/*
 * assemble the data structure for an adt with a pick clause.
 * since the scoping rules for adt pick fields are strange,
 * we have a customized check for overlapping definitions.
 */
Decl*
pickdefd(Type *t, Decl *tg)
{
	Decl *id, *xid, *lasttg, *d;
	Type *tt;
	int tag;

	lasttg = nil;
	d = t->decl;
	t->tags = tg;
	tag = 0;
	while(tg != nil){
		tt = tg->ty;
		if(tt->kind != Tadtpick || tg->tag != tag)
			break;
		tt->decl = tg;
		lasttg = tg;
		for(; tg != nil; tg = tg->next){
			if(tg->ty != tt)
				break;
			tag++;
			lasttg = tg;
			tg->dot = d;
		}
		for(id = tt->ids; id != nil; id = id->next){
			xid = namedot(t->ids, id->sym);
			if(xid != nil)
				error(id->src.start, "redeclaration of %K, previously declared as %k on line %L",
					id, xid, xid->src.start);
			id->dot = d;
		}
	}
	if(lasttg == nil){
		error(t->src.start, "empty pick field declaration in %T", t);
		t->tags = nil;
	}else
		lasttg->next = nil;
	d->tag = tag;
	return tg;
}

Node*
moddecl(Decl *ids, Node *fields)
{
	Node *n;
	Type *t;

	n = mkn(Omoddecl, mkn(Oseq, nil, nil), nil);
	t = mktype(&ids->src.start, &ids->src.stop, Tmodule, nil, nil);
	n->decl = ids;
	n->left = fields;
	n->ty = t;
	return n;
}

void
moddecled(Node *n)
{
	Decl *d, *ids, *im, *dot;
	Type *t;
	Sym *s;
	char buf[StrSize];
	int isimp;
	Dlist *dm, *dl;

	d = n->decl;
	installids(Dtype, d);
	isimp = 0;
	for(ids = d; ids != nil; ids = ids->next){
		for(im = impmods; im != nil; im = im->next){
			if(ids->sym == im->sym){
				isimp = 1;
				d = ids;
				dm = malloc(sizeof(Dlist));
				dm->d = ids;
				dm->next = nil;
				if(impdecls == nil)
					impdecls = dm;
				else{
					for(dl = impdecls; dl->next != nil; dl = dl->next)
						;
					dl->next = dm;
				}
			}
		}
		ids->ty = n->ty;
	}
	pushscope(nil, Sother);
	fielddecled(n->left);

	d->ty->ids = popscope();

	/*
	 * make the current module the -> parent of all contained decls->
	 */
	for(ids = d->ty->ids; ids != nil; ids = ids->next)
		ids->dot = d;

	t = d->ty;
	t->decl = d;
	if(debug['m'])
		print("declare module %s\n", d->sym->name);

	/*
	 * add the iface declaration in case it's needed later
	 */
	seprint(buf, buf+sizeof(buf), ".m.%s", d->sym->name);
	installids(Dglobal, mkids(&d->src, enter(buf, 0), tnone, nil));

	if(isimp){
		for(ids = d->ty->ids; ids != nil; ids = ids->next){
			s = ids->sym;
			if(s->decl != nil && s->decl->scope >= scope){
				dot = s->decl->dot;
				if(s->decl->store != Dwundef && dot != nil && dot != d && isimpmod(dot->sym) && dequal(ids, s->decl, 0))
					continue;
				redecl(ids);
				ids->old = s->decl->old;
			}else
				ids->old = s->decl;
			s->decl = ids;
			ids->scope = scope;
		}
	}
}

/*
 * for each module in id,
 * link by field ext all of the decls for
 * functions needed in external linkage table
 * collect globals and make a tuple for all of them
 */
Type*
mkiface(Decl *m)
{
	Decl *iface, *last, *globals, *glast, *id, *d;
	Type *t;
	char buf[StrSize];

	iface = last = allocmem(sizeof(Decl));
	globals = glast = mkdecl(&m->src, Dglobal, mktype(&m->src.start, &m->src.stop, Tadt, nil, nil));
	for(id = m->ty->ids; id != nil; id = id->next){
		switch(id->store){
		case Dglobal:
			glast = glast->next = dupdecl(id);
			id->iface = globals;
			glast->iface = id;
			break;
		case Dfn:
			id->iface = last = last->next = dupdecl(id);
			last->iface = id;
			break;
		case Dtype:
			if(id->ty->kind != Tadt)
				break;
			for(d = id->ty->ids; d != nil; d = d->next){
				if(d->store == Dfn){
					d->iface = last = last->next = dupdecl(d);
					last->iface = d;
				}
			}
			break;
		}
	}
	last->next = nil;
	iface = namesort(iface->next);

	if(globals->next != nil){
		glast->next = nil;
		globals->ty->ids = namesort(globals->next);
		globals->ty->decl = globals;
		globals->sym = enter(".mp", 0);
		globals->dot = m;
		globals->next = iface;
		iface = globals;
	}

	/*
	 * make the interface type and install an identifier for it
	 * the iface has a ref count if it is loaded
	 */
	t = mktype(&m->src.start, &m->src.stop, Tiface, nil, iface);
	seprint(buf, buf+sizeof(buf), ".m.%s", m->sym->name);
	id = enter(buf, 0)->decl;
	t->decl = id;
	id->ty = t;

	/*
	 * dummy node so the interface is initialized
	 */
	id->init = mkn(Onothing, nil, nil);
	id->init->ty = t;
	id->init->decl = id;
	return t;
}

void
joiniface(Type *mt, Type *t)
{
	Decl *id, *d, *iface, *globals;

	iface = t->ids;
	globals = iface;
	if(iface != nil && iface->store == Dglobal)
		iface = iface->next;
	for(id = mt->tof->ids; id != nil; id = id->next){
		switch(id->store){
		case Dglobal:
			for(d = id->ty->ids; d != nil; d = d->next)
				d->iface->iface = globals;
			break;
		case Dfn:
			id->iface->iface = iface;
			iface = iface->next;
			break;
		default:
			fatal("unknown store %k in joiniface", id);
			break;
		}
	}
	if(iface != nil)
		fatal("join iface not matched");
	mt->tof = t;
}

void
addiface(Decl *m, Decl *d)
{
	Type *t;
	Decl *id, *last, *dd, *lastorig;
	Dlist *dl;

	if(d == nil || !local(d))
		return;
	modrefable(d->ty);
	if(m == nil){
		if(impdecls->next != nil)
			for(dl = impdecls; dl != nil; dl = dl->next)
				if(dl->d->ty->tof != impdecl->ty->tof)	/* impdecl last */
					addiface(dl->d, d);
		addiface(impdecl, d);
		return;
	}
	t = m->ty->tof;
	last = nil;
	lastorig = nil;
	for(id = t->ids; id != nil; id = id->next){
		if(d == id || d == id->iface)
			return;
		last = id;
		if(id->tag == 0)
			lastorig = id;
	}
	dd = dupdecl(d);
	if(d->dot == nil)
		d->dot = dd->dot = m;
	d->iface = dd;
	dd->iface = d;
if(debug['v']) print("addiface %p %p\n", d, dd);
	if(last == nil)
		t->ids = dd;
	else
		last->next = dd;
	dd->tag = 1;	/* mark so not signed */
	if(lastorig == nil)
		t->ids = namesort(t->ids);
	else
		lastorig->next = namesort(lastorig->next);
}

/*
 * eliminate unused declarations from interfaces
 * label offset within interface
 */
void
narrowmods(void)
{
	Teq *eq;
	Decl *id, *last;
	Type *t;
	long offset;

	for(eq = modclass(); eq != nil; eq = eq->eq){
		t = eq->ty->tof;

		if(t->linkall == 0){
			last = nil;
			for(id = t->ids; id != nil; id = id->next){
				if(id->refs == 0){
					if(last == nil)
						t->ids = id->next;
					else
						last->next = id->next;
				}else
					last = id;
			}

			/*
			 * need to resize smaller interfaces
			 */
			resizetype(t);
		}

		offset = 0;
		for(id = t->ids; id != nil; id = id->next)
			id->offset = offset++;

		/*
		 * rathole to stuff number of entries in interface
		 */
		t->decl->init->val = offset;
	}
}

/*
 * check to see if any data field of module m if referenced.
 * if so, mark all data in m
 */
void
moddataref(void)
{
	Teq *eq;
	Decl *id;

	for(eq = modclass(); eq != nil; eq = eq->eq){
		id = eq->ty->tof->ids;
		if(id != nil && id->store == Dglobal && id->refs)
			for(id = eq->ty->ids; id != nil; id = id->next)
				if(id->store == Dglobal)
					modrefable(id->ty);
	}
}

/*
 * move the global declarations in interface to the front
 */
Decl*
modglobals(Decl *mod, Decl *globals)
{
	Decl *id, *head, *last;

	/*
	 * make a copy of all the global declarations
	 * 	used for making a type descriptor for globals ONLY
	 * note we now have two declarations for the same variables,
	 * which is apt to cause problems if code changes
	 *
	 * here we fix up the offsets for the real declarations
	 */
	idoffsets(mod->ty->ids, 0, 1);

	last = head = allocmem(sizeof(Decl));
	for(id = mod->ty->ids; id != nil; id = id->next)
		if(id->store == Dglobal)
			last = last->next = dupdecl(id);

	last->next = globals;
	return head->next;
}

/*
 * snap all id type names to the actual type
 * check that all types are completely defined
 * verify that the types look ok
 */
Type*
validtype(Type *t, Decl *inadt)
{
	if(t == nil)
		return t;
	bindtypes(t);
	t = verifytypes(t, inadt, nil);
	cycsizetype(t);
	teqclass(t);
	return t;
}

Type*
usetype(Type *t)
{
	if(t == nil)
		return t;
	t = validtype(t, nil);
	reftype(t);
	return t;
}

Type*
internaltype(Type *t)
{
	bindtypes(t);
	t->ok = OKverify;
	sizetype(t);
	t->ok = OKmask;
	return t;
}

/*
 * checks that t is a valid top-level type
 */
Type*
topvartype(Type *t, Decl *id, int tyok, int polyok)
{
	if(t->kind == Tadt && t->tags != nil || t->kind == Tadtpick)
		error(id->src.start, "cannot declare %s with type %T", id->sym->name, t);
	if(!tyok && t->kind == Tfn)
		error(id->src.start, "cannot declare %s to be a function", id->sym->name);
	if(!polyok && (t->kind == Tadt || t->kind == Tadtpick) && ispolyadt(t))
		error(id->src.start, "cannot declare %s of a polymorphic type", id->sym->name);
	return t;
}

Type*
toptype(Src *src, Type *t)
{
	if(t->kind == Tadt && t->tags != nil || t->kind == Tadtpick)
		error(src->start, "%T, an adt with pick fields, must be used with ref", t);
	if(t->kind == Tfn)
		error(src->start, "data cannot have a fn type like %T", t);
	return t;
}

static Type*
comtype(Src *src, Type *t, Decl* adtd)
{
	if(adtd == nil && (t->kind == Tadt || t->kind == Tadtpick) && ispolyadt(t))
		error(src->start, "polymorphic type %T illegal here", t);
	return t;
}

void
usedty(Type *t)
{
	if(t != nil && (t->ok | OKmodref) != OKmask)
		fatal("used ty %t %2.2ux", t, t->ok);
}

void
bindtypes(Type *t)
{
	Decl *id;
	Typelist *tl;

	if(t == nil)
		return;
	if((t->ok & OKbind) == OKbind)
		return;
	t->ok |= OKbind;
	switch(t->kind){
	case Tadt:
		if(t->polys != nil){
			pushscope(nil, Sother);
			installids(Dtype, t->polys);
		}
		if(t->val != nil)
			mergepolydecs(t);
		if(t->polys != nil){
			popscope();
			for(id = t->polys; id != nil; id = id->next)
				bindtypes(id->ty);
		}
		break;
	case Tadtpick:
	case Tmodule:
	case Terror:
	case Tint:
	case Tbig:
	case Tstring:
	case Treal:
	case Tbyte:
	case Tnone:
	case Tany:
	case Tiface:
	case Tainit:
	case Talt:
	case Tcase:
	case Tcasel:
	case Tcasec:
	case Tgoto:
	case Texcept:
	case Tfix:
	case Tpoly:
		break;
	case Tarray:
	case Tarrow:
	case Tchan:
	case Tdot:
	case Tlist:
	case Tref:
		bindtypes(t->tof);
		break;
	case Tid:
		id = t->decl->sym->decl;
		if(id == nil)
			id = undefed(&t->src, t->decl->sym);
		/* save a little space */
		id->sym->unbound = nil;
		t->decl = id;
		break;
	case Ttuple:
	case Texception:
		for(id = t->ids; id != nil; id = id->next)
			bindtypes(id->ty);
		break;
	case Tfn:
		if(t->polys != nil){
			pushscope(nil, Sother);
			installids(Dtype, t->polys);
		}
		for(id = t->ids; id != nil; id = id->next)
			bindtypes(id->ty);
		bindtypes(t->tof);
		if(t->val != nil)
			mergepolydecs(t);
		if(t->polys != nil){
			popscope();
			for(id = t->polys; id != nil; id = id->next)
				bindtypes(id->ty);
		}
		break;
	case Tinst:
		bindtypes(t->tof);
		for(tl = t->u.tlist; tl != nil; tl = tl->nxt)
			bindtypes(tl->t);
		break;
	default:
		fatal("bindtypes: unknown type kind %d", t->kind);
	}
}

/*
 * walk the type checking for validity
 */
Type*
verifytypes(Type *t, Decl *adtt, Decl *poly)
{
	Node *n;
	Decl *id, *id1, *last;
	char buf[32];
	int i, cyc;
	Ok ok, ok1;
	double max;
	Typelist *tl;

	if(t == nil)
		return nil;
	if((t->ok & OKverify) == OKverify)
		return t;
	t->ok |= OKverify;
if((t->ok & (OKverify|OKbind)) != (OKverify|OKbind))
fatal("verifytypes bogus ok for %t", t);
	cyc = t->flags&CYCLIC;
	switch(t->kind){
	case Terror:
	case Tint:
	case Tbig:
	case Tstring:
	case Treal:
	case Tbyte:
	case Tnone:
	case Tany:
	case Tiface:
	case Tainit:
	case Talt:
	case Tcase:
	case Tcasel:
	case Tcasec:
	case Tgoto:
	case Texcept:
		break;
	case Tfix:
		n = t->val;
		max = 0.0;
		if(n->op == Oseq){
			ok = echeck(n->left, 0, 0, n);
			ok1 = echeck(n->right, 0, 0, n);
			if(!ok.ok || !ok1.ok)
				return terror;
			if(n->left->ty != treal || n->right->ty != treal){
				error(t->src.start, "fixed point scale/maximum not real");
				return terror;
			}
			n->right = fold(n->right);
			if(n->right->op != Oconst){
				error(t->src.start, "fixed point maximum not constant");
				return terror;
			}
			if((max = n->right->rval) <= 0){
				error(t->src.start, "non-positive fixed point maximum");
				return terror;
			}
			n = n->left;
		}
		else{
			ok = echeck(n, 0, 0, nil);
			if(!ok.ok)
				return terror;
			if(n->ty != treal){
				error(t->src.start, "fixed point scale not real");
				return terror;
			}
		}
		n = t->val = fold(n);
		if(n->op != Oconst){
			error(t->src.start, "fixed point scale not constant");
			return terror;
		}
		if(n->rval <= 0){
			error(t->src.start, "non-positive fixed point scale");
			return terror;
		}
		ckfix(t, max);
		break;
	case Tref:
		t->tof = comtype(&t->src, verifytypes(t->tof, adtt, nil), adtt);
		if(t->tof != nil && !tattr[t->tof->kind].refable){
			error(t->src.start, "cannot have a ref %T", t->tof);
			return terror;
		}
		if(0 && t->tof->kind == Tfn && t->tof->ids != nil && t->tof->ids->implicit)
			error(t->src.start, "function references cannot have a self argument");
		if(0 && t->tof->kind == Tfn && t->polys != nil)
			error(t->src.start, "function references cannot be polymorphic");
		break;
	case Tchan:
	case Tarray:
	case Tlist:
		t->tof = comtype(&t->src, toptype(&t->src, verifytypes(t->tof, adtt, nil)), adtt);
		break;
	case Tid:
		t->ok &= ~OKverify;
		t = verifytypes(idtype(t), adtt, nil);
		break;
	case Tarrow:
		t->ok &= ~OKverify;
		t = verifytypes(arrowtype(t, adtt), adtt, nil);
		break;
	case Tdot:
		/*
		 * verify the parent adt & lookup the tag fields
		 */
		t->ok &= ~OKverify;
		t = verifytypes(dottype(t, adtt), adtt, nil);
		break;
	case Tadt:
		/*
		 * this is where Tadt may get tag fields added
		 */
		adtdefd(t);
		break;
	case Tadtpick:
		for(id = t->ids; id != nil; id = id->next){
			id->ty = topvartype(verifytypes(id->ty, id->dot, nil), id, 0, 1);
			if(id->store == Dconst)
				error(t->src.start, "pick fields cannot be a con like %s", id->sym->name);
		}
		verifytypes(t->decl->dot->ty, nil, nil);
		break;
	case Tmodule:
		for(id = t->ids; id != nil; id = id->next){
			id->ty = verifytypes(id->ty, nil, nil);
			if(id->store == Dglobal && id->ty->kind == Tfn)
				id->store = Dfn;
			if(id->store != Dtype && id->store != Dfn)
				topvartype(id->ty, id, 0, 0);
		}
 		break;
	case Ttuple:
	case Texception:
		if(t->decl == nil){
			t->decl = mkdecl(&t->src, Dtype, t);
			t->decl->sym = enter(".tuple", 0);
		}
		i = 0;
		for(id = t->ids; id != nil; id = id->next){
			id->store = Dfield;
			if(id->sym == nil){
				seprint(buf, buf+sizeof(buf), "t%d", i);
				id->sym = enter(buf, 0);
			}
			i++;
			id->ty = toptype(&id->src, verifytypes(id->ty, adtt, nil));
			/* id->ty = comtype(&id->src, toptype(&id->src, verifytypes(id->ty, adtt, nil)), adtt); */
		}
		break;
	case Tfn:
		last = nil;
		for(id = t->ids; id != nil; id = id->next){
			id->store = Darg;
			id->ty = topvartype(verifytypes(id->ty, adtt, nil), id, 0, 1);
			if(id->implicit){
				Decl *selfd;

				selfd = poly ? poly : adtt;
				if(selfd == nil)
					error(t->src.start, "function is not a member of an adt, so can't use self");
				else if(id != t->ids)
					error(id->src.start, "only the first argument can use self");
				else if(id->ty != selfd->ty && (id->ty->kind != Tref || id->ty->tof != selfd->ty))
					error(id->src.start, "self argument's type must be %s or ref %s",
						selfd->sym->name, selfd->sym->name);
			}
			last = id;
		}
		for(id = t->polys; id != nil; id = id->next){
			if(adtt != nil){
				for(id1 = adtt->ty->polys; id1 != nil; id1 = id1->next){
					if(id1->sym == id->sym)
						id->ty = id1->ty;
				}
			}
			id->store = Dtype;
			id->ty = verifytypes(id->ty, adtt, nil);
		}
		t->tof = comtype(&t->src, toptype(&t->src, verifytypes(t->tof, adtt, nil)), adtt);
		if(t->varargs && (last == nil || last->ty != tstring))
			error(t->src.start, "variable arguments must be preceded by a string");
		if(t->varargs && t->polys != nil)
			error(t->src.start, "polymorphic functions must not have variable arguments");
		break;
	case Tpoly:
		for(id = t->ids; id != nil; id = id->next){
			id->store = Dfn;
			id->ty = verifytypes(id->ty, adtt, t->decl);
		}
		break;
	case Tinst:
		t->ok &= ~OKverify;
		t->tof = verifytypes(t->tof, adtt, nil);
		for(tl = t->u.tlist; tl != nil; tl = tl->nxt)
			tl->t = verifytypes(tl->t, adtt, nil);
		t = verifytypes(insttype(t, adtt, nil), adtt, nil);
		break;
	default:
		fatal("verifytypes: unknown type kind %d", t->kind);
	}
	if(cyc)
		t->flags |= CYCLIC;
	return t;
}

/*
 * resolve an id type
 */
Type*
idtype(Type *t)
{
	Decl *id;
	Type *tt;

	id = t->decl;
	if(id->store == Dunbound)
		fatal("idtype: unbound decl");
	tt = id->ty;
	if(id->store != Dtype && id->store != Dtag){
		if(id->store == Dundef){
			id->store = Dwundef;
			error(t->src.start, "%s is not declared", id->sym->name);
		}else if(id->store == Dimport){
			id->store = Dwundef;
			error(t->src.start, "%s's type cannot be determined", id->sym->name);
		}else if(id->store != Dwundef)
			error(t->src.start, "%s is not a type", id->sym->name);
		return terror;
	}
	if(tt == nil){
		error(t->src.start, "%t not fully defined", t);
		return terror;
	}
	return tt;
}

/*
 * resolve a -> qualified type
 */
Type*
arrowtype(Type *t, Decl *adtt)
{
	Type *tt;
	Decl *id;

	id = t->decl;
	if(id->ty != nil){
		if(id->store == Dunbound)
			fatal("arrowtype: unbound decl has a type");
		return id->ty;
	}

	/*
	 * special hack to allow module variables to derive other types
	 */ 
	tt = t->tof;
	if(tt->kind == Tid){
		id = tt->decl;
		if(id->store == Dunbound)
			fatal("arrowtype: Tid's decl unbound");
		if(id->store == Dimport){
			id->store = Dwundef;
			error(t->src.start, "%s's type cannot be determined", id->sym->name);
			return terror;
		}

		/*
		 * forward references to module variables can't be resolved
		 */
		if(id->store != Dtype && !(id->ty->ok & OKbind)){
			error(t->src.start, "%s's type cannot be determined", id->sym->name);
			return terror;
		}

		if(id->store == Dwundef)
			return terror;
		tt = id->ty = verifytypes(id->ty, adtt, nil);
		if(tt == nil){
			error(t->tof->src.start, "%T is not a module", t->tof);
			return terror;
		}
	}else
		tt = verifytypes(t->tof, adtt, nil);
	t->tof = tt;
	if(tt == terror)
		return terror;
	if(tt->kind != Tmodule){
		error(t->src.start, "%T is not a module", tt);
		return terror;
	}
	id = namedot(tt->ids, t->decl->sym);
	if(id == nil){
		error(t->src.start, "%s is not a member of %T", t->decl->sym->name, tt);
		return terror;
	}
	if(id->store == Dtype && id->ty != nil){
		t->decl = id;
		return id->ty;
	}
	error(t->src.start, "%T is not a type", t);
	return terror;
}

/*
 * resolve a . qualified type
 */
Type*
dottype(Type *t, Decl *adtt)
{
	Type *tt;
	Decl *id;

	if(t->decl->ty != nil){
		if(t->decl->store == Dunbound)
			fatal("dottype: unbound decl has a type");
		return t->decl->ty;
	}
	t->tof = tt = verifytypes(t->tof, adtt, nil);
	if(tt == terror)
		return terror;
	if(tt->kind != Tadt){
		error(t->src.start, "%T is not an adt", tt);
		return terror;
	}
	id = namedot(tt->tags, t->decl->sym);
	if(id != nil && id->ty != nil){
		t->decl = id;
		return id->ty;
	}
	error(t->src.start, "%s is not a pick tag of %T", t->decl->sym->name, tt);
	return terror;
}

Type*
insttype(Type *t, Decl *adtt, Tpair **tp)
{
	Type *tt;
	Typelist *tl;
	Decl *ids;
	Tpair *tp1, *tp2;
	Src src;

	src = t->src;
	if(tp == nil){
		tp2 = nil;
		tp = &tp2;
	}
	if(t->tof->kind != Tadt && t->tof->kind != Tadtpick){
		error(src.start, "%T is not an adt", t->tof);
		return terror;
	}
	if(t->tof->kind == Tadt)
		ids = t->tof->polys;
	else
		ids = t->tof->decl->dot->ty->polys;
	if(ids == nil){
		error(src.start, "%T is not a polymorphic adt", t->tof);
		return terror;
	}
	for(tl = t->u.tlist; tl != nil && ids != nil; tl = tl->nxt, ids = ids->next){
		tt = tl->t;
		if(!tattr[tt->kind].isptr){
			error(src.start, "%T is not a pointer type", tt);
			return terror;
		}
		unifysrc = src;
		if(!tunify(ids->ty, tt, &tp1)){
			error(src.start, "type %T does not match %T", tt, ids->ty);
			return terror;
		}
		/* usetype(tt); */
		tt = verifytypes(tt, adtt, nil);
		addtmap(ids->ty, tt, tp);
	}
	if(tl != nil){
		error(src.start, "too many actual types in instantiation");
		return terror;
	}
	if(ids != nil){
		error(src.start, "too few actual types in instantiation");
		return terror;
	}
	tp1 = *tp;
	tt = t->tof;
	t = expandtype(tt, t, adtt, tp);
	if(t == tt && adtt == nil)
		t = duptype(t);
	if(t != tt){
		t->u.tmap = tp1;
		if(debug['w']){
			print("tmap for %T: ", t);
			for( ; tp1!=nil; tp1=tp1->nxt)
				print("%T -> %T ", tp1->t1, tp1->t2);
			print("\n");
		}
	}
	t->src = src;
	return t;
}

/*
 * walk a type, putting all adts, modules, and tuples into equivalence classes
 */
void
teqclass(Type *t)
{
	Decl *id, *tg;
	Teq *teq;

	if(t == nil || (t->ok & OKclass) == OKclass)
		return;
	t->ok |= OKclass;
	switch(t->kind){
	case Terror:
	case Tint:
	case Tbig:
	case Tstring:
	case Treal:
	case Tbyte:
	case Tnone:
	case Tany:
	case Tiface:
	case Tainit:
	case Talt:
	case Tcase:
	case Tcasel:
	case Tcasec:
	case Tgoto:
	case Texcept:
	case Tfix:
	case Tpoly:
		return;
	case Tref:
		teqclass(t->tof);
		return;
	case Tchan:
	case Tarray:
	case Tlist:
		teqclass(t->tof);
		if(!debug['Z'])
			return;
		break;
	case Tadt:
	case Tadtpick:
	case Ttuple:
	case Texception:
		for(id = t->ids; id != nil; id = id->next)
			teqclass(id->ty);
		for(tg = t->tags; tg != nil; tg = tg->next)
			teqclass(tg->ty);
		for(id = t->polys; id != nil; id = id->next)
			teqclass(id->ty);
		break;
	case Tmodule:
		t->tof = mkiface(t->decl);
		for(id = t->ids; id != nil; id = id->next)
			teqclass(id->ty);
		break;
	case Tfn:
		for(id = t->ids; id != nil; id = id->next)
			teqclass(id->ty);
		for(id = t->polys; id != nil; id = id->next)
			teqclass(id->ty);
		teqclass(t->tof);
		return;
	default:
		fatal("teqclass: unknown type kind %d", t->kind);
		return;
	}

	/*
	 * find an equivalent type
	 * stupid linear lookup could be made faster
	 */
	if((t->ok & OKsized) != OKsized)
		fatal("eqclass type not sized: %t", t);

	for(teq = eqclass[t->kind]; teq != nil; teq = teq->eq){
		if(t->size == teq->ty->size && tequal(t, teq->ty)){
			t->eq = teq;
			if(t->kind == Tmodule)
				joiniface(t, t->eq->ty->tof);
			return;
		}
	}

	/*
	 * if no equiv type, make one
	 */
	t->eq = allocmem(sizeof(Teq));
	t->eq->id = 0;
	t->eq->ty = t;
	t->eq->eq = eqclass[t->kind];
	eqclass[t->kind] = t->eq;
}

/*
 * record that we've used the type
 * using a type uses all types reachable from that type
 */
void
reftype(Type *t)
{
	Decl *id, *tg;

	if(t == nil || (t->ok & OKref) == OKref)
		return;
	t->ok |= OKref;
	if(t->decl != nil && t->decl->refs == 0)
		t->decl->refs++;
	switch(t->kind){
	case Terror:
	case Tint:
	case Tbig:
	case Tstring:
	case Treal:
	case Tbyte:
	case Tnone:
	case Tany:
	case Tiface:
	case Tainit:
	case Talt:
	case Tcase:
	case Tcasel:
	case Tcasec:
	case Tgoto:
	case Texcept:
	case Tfix:
	case Tpoly:
		break;
	case Tref:
	case Tchan:
	case Tarray:
	case Tlist:
		if(t->decl != nil){
			if(nadts >= lenadts){
				lenadts = nadts + 32;
				adts = reallocmem(adts, lenadts * sizeof *adts);
			}
			adts[nadts++] = t->decl;
		}
		reftype(t->tof);
		break;
	case Tadt:
	case Tadtpick:
	case Ttuple:
	case Texception:
		if(t->kind == Tadt || t->kind == Ttuple && t->decl->sym != anontupsym){
			if(nadts >= lenadts){
				lenadts = nadts + 32;
				adts = reallocmem(adts, lenadts * sizeof *adts);
			}
			adts[nadts++] = t->decl;
		}
		for(id = t->ids; id != nil; id = id->next)
			if(id->store != Dfn)
				reftype(id->ty);
		for(tg = t->tags; tg != nil; tg = tg->next)
			reftype(tg->ty);
		for(id = t->polys; id != nil; id = id->next)
			reftype(id->ty);
		if(t->kind == Tadtpick)
			reftype(t->decl->dot->ty);
		break;
	case Tmodule:
		/*
		 * a module's elements should get used individually
		 * but do the globals for any sbl file
		 */
		if(bsym != nil)
			for(id = t->ids; id != nil; id = id->next)
				if(id->store == Dglobal)
					reftype(id->ty);
		break;
	case Tfn:
		for(id = t->ids; id != nil; id = id->next)
			reftype(id->ty);
		for(id = t->polys; id != nil; id = id->next)
			reftype(id->ty);
		reftype(t->tof);
		break;
	default:
		fatal("reftype: unknown type kind %d", t->kind);
		break;
	}
}

/*
 * check all reachable types for cycles and illegal forward references
 * find the size of all the types
 */
void
cycsizetype(Type *t)
{
	Decl *id, *tg;

	if(t == nil || (t->ok & (OKcycsize|OKcyc|OKsized)) == (OKcycsize|OKcyc|OKsized))
		return;
	t->ok |= OKcycsize;
	switch(t->kind){
	case Terror:
	case Tint:
	case Tbig:
	case Tstring:
	case Treal:
	case Tbyte:
	case Tnone:
	case Tany:
	case Tiface:
	case Tainit:
	case Talt:
	case Tcase:
	case Tcasel:
	case Tcasec:
	case Tgoto:
	case Texcept:
	case Tfix:
	case Tpoly:
		t->ok |= OKcyc;
		sizetype(t);
		break;
	case Tref:
	case Tchan:
	case Tarray:
	case Tlist:
		cyctype(t);
		sizetype(t);
		cycsizetype(t->tof);
		break;
	case Tadt:
	case Ttuple:
	case Texception:
		cyctype(t);
		sizetype(t);
		for(id = t->ids; id != nil; id = id->next)
			cycsizetype(id->ty);
		for(tg = t->tags; tg != nil; tg = tg->next){
			if((tg->ty->ok & (OKcycsize|OKcyc|OKsized)) == (OKcycsize|OKcyc|OKsized))
				continue;
			tg->ty->ok |= (OKcycsize|OKcyc|OKsized);
			for(id = tg->ty->ids; id != nil; id = id->next)
				cycsizetype(id->ty);
		}
		for(id = t->polys; id != nil; id = id->next)
			cycsizetype(id->ty);
		break;
	case Tadtpick:
		t->ok &= ~OKcycsize;
		cycsizetype(t->decl->dot->ty);
		break;
	case Tmodule:
		cyctype(t);
		sizetype(t);
		for(id = t->ids; id != nil; id = id->next)
			cycsizetype(id->ty);
		sizeids(t->ids, 0);
		break;
	case Tfn:
		cyctype(t);
		sizetype(t);
		for(id = t->ids; id != nil; id = id->next)
			cycsizetype(id->ty);
		for(id = t->polys; id != nil; id = id->next)
			cycsizetype(id->ty);
		cycsizetype(t->tof);
		sizeids(t->ids, MaxTemp);
		break;
	default:
		fatal("cycsizetype: unknown type kind %d", t->kind);
		break;
	}
}

/* check for circularity in type declarations
 * - has to be called before verifytypes
 */
void
tcycle(Type *t)
{
	Decl *id;
	Type *tt;
	Typelist *tl;

	if(t == nil)
		return;
	switch(t->kind){
	default:
		break;
	case Tchan:
	case Tarray:
	case Tref:
	case Tlist:
	case Tdot:
		tcycle(t->tof);
		break;
	case Tfn:
	case Ttuple:
		tcycle(t->tof);
		for(id = t->ids; id != nil; id = id->next)
			tcycle(id->ty);
		break;
	case Tarrow:
		if(t->rec&TRvis){
			error(t->src.start, "circularity in definition of %T", t);
			*t = *terror;	/* break the cycle */
			return;
		}
		tt = t->tof;
		t->rec |= TRvis;
		tcycle(tt);
		if(tt->kind == Tid)
			tt = tt->decl->ty;
		id = namedot(tt->ids, t->decl->sym);
		if(id != nil)
			tcycle(id->ty);
		t->rec &= ~TRvis;
		break;
	case Tid:
		if(t->rec&TRvis){
			error(t->src.start, "circularity in definition of %T", t);
			*t = *terror;	/* break the cycle */
			return;
		}
		t->rec |= TRvis;
		tcycle(t->decl->ty);
		t->rec &= ~TRvis;
		break;
	case Tinst:
		tcycle(t->tof);
		for(tl = t->u.tlist; tl != nil; tl = tl->nxt)
			tcycle(tl->t);
		break;
	}
}

/*
 * marks for checking for arcs
 */
enum
{
	ArcValue	= 1 << 0,
	ArcList		= 1 << 1,
	ArcArray	= 1 << 2,
	ArcRef		= 1 << 3,
	ArcCyc		= 1 << 4,		/* cycle found */
	ArcPolycyc	= 1 << 5,
};

void
cyctype(Type *t)
{
	Decl *id, *tg;

	if((t->ok & OKcyc) == OKcyc)
		return;
	t->ok |= OKcyc;
	t->rec |= TRcyc;
	switch(t->kind){
	case Terror:
	case Tint:
	case Tbig:
	case Tstring:
	case Treal:
	case Tbyte:
	case Tnone:
	case Tany:
	case Tfn:
	case Tchan:
	case Tarray:
	case Tref:
	case Tlist:
	case Tfix:
	case Tpoly:
		break;
	case Tadt:
	case Tmodule:
	case Ttuple:
	case Texception:
		for(id = t->ids; id != nil; id = id->next)
			cycfield(t, id);
		for(tg = t->tags; tg != nil; tg = tg->next){
			if((tg->ty->ok & OKcyc) == OKcyc)
				continue;
			tg->ty->ok |= OKcyc;
			for(id = tg->ty->ids; id != nil; id = id->next)
				cycfield(t, id);
		}
		break;
	default:
		fatal("checktype: unknown type kind %d", t->kind);
		break;
	}
	t->rec &= ~TRcyc;
}

void
cycfield(Type *base, Decl *id)
{
	int arc;

	if(!storespace[id->store])
		return;
	arc = cycarc(base, id->ty);

	if((arc & (ArcCyc|ArcValue)) == (ArcCyc|ArcValue)){
		if(id->cycerr == 0)
			error(base->src.start, "illegal type cycle without a reference in field %s of %t",
				id->sym->name, base);
		id->cycerr = 1;
	}else if(arc & ArcCyc){
		if((arc & ArcArray) && oldcycles && id->cyc == 0 && !(arc & ArcPolycyc)){
			if(id->cycerr == 0)
				error(base->src.start, "illegal circular reference to type %T in field %s of %t",
					id->ty, id->sym->name, base);
			id->cycerr = 1;
		}
		id->cycle = 1;
	}else if(id->cyc != 0){
		if(id->cycerr == 0)
			error(id->src.start, "spurious cyclic qualifier for field %s of %t", id->sym->name, base);
		id->cycerr = 1;
	}
}

int
cycarc(Type *base, Type *t)
{
	Decl *id, *tg;
	int me, arc;

	if(t == nil)
		return 0;
	if(t->rec & TRcyc){
		if(tequal(t, base)){
			if(t->kind == Tmodule)
				return ArcCyc | ArcRef;
			else
				return ArcCyc | ArcValue;
		}
		return 0;
	}
	t->rec |= TRcyc;
	me = 0;
	switch(t->kind){
	case Terror:
	case Tint:
	case Tbig:
	case Tstring:
	case Treal:
	case Tbyte:
	case Tnone:
	case Tany:
	case Tchan:
	case Tfn:
	case Tfix:
	case Tpoly:
		break;
	case Tarray:
		me = cycarc(base, t->tof) & ~ArcValue | ArcArray;
		break;
	case Tref:
		me = cycarc(base, t->tof) & ~ArcValue | ArcRef;
		break;
	case Tlist:
		me = cycarc(base, t->tof) & ~ArcValue | ArcList;
		break;
	case Tadt:
	case Tadtpick:
	case Tmodule:
	case Ttuple:
	case Texception:
		me = 0;
		for(id = t->ids; id != nil; id = id->next){
			if(!storespace[id->store])
				continue;
			arc = cycarc(base, id->ty);
			if((arc & ArcCyc) && id->cycerr == 0)
				me |= arc;
		}
		for(tg = t->tags; tg != nil; tg = tg->next){
			arc = cycarc(base, tg->ty);
			if((arc & ArcCyc) && tg->cycerr == 0)
				me |= arc;
		}

		if(t->kind == Tmodule)
			me = me & ArcCyc | ArcRef | ArcPolycyc;
		else
			me &= ArcCyc | ArcValue | ArcPolycyc;
		break;
	default:
		fatal("cycarc: unknown type kind %d", t->kind);
		break;
	}
	t->rec &= ~TRcyc;
	if(t->flags&CYCLIC)
		me |= ArcPolycyc;
	return me;
}

/*
 * set the sizes and field offsets for t
 * look only as deeply as needed to size this type.
 * cycsize type will clean up the rest.
 */
void
sizetype(Type *t)
{
	Decl *id, *tg;
	Szal szal;
	long sz, al, a;

	if(t == nil)
		return;
	if((t->ok & OKsized) == OKsized)
		return;
	t->ok |= OKsized;
if((t->ok & (OKverify|OKsized)) != (OKverify|OKsized))
fatal("sizetype bogus ok for %t", t);
	switch(t->kind){
	default:
		fatal("sizetype: unknown type kind %d", t->kind);
		break;
	case Terror:
	case Tnone:
	case Tbyte:
	case Tint:
	case Tbig:
	case Tstring:
	case Tany:
	case Treal:
		fatal("%T should have a size", t);
		break;
	case Tref:
	case Tchan:
	case Tarray:
	case Tlist:
	case Tmodule:
	case Tfix:
	case Tpoly:
		t->size = t->align = IBY2WD;
		break;
	case Ttuple:
	case Tadt:
	case Texception:
		if(t->tags == nil){
			if(!debug['z']){
				szal = sizeids(t->ids, 0);
				t->size = align(szal.size, szal.align);
				t->align = szal.align;
			}else{
				szal = sizeids(t->ids, 0);
				t->align = IBY2LG;
				t->size = align(szal.size, IBY2LG);
			}
			return;
		}
		if(!debug['z']){
			szal = sizeids(t->ids, IBY2WD);
			sz = szal.size;
			al = szal.align;
			if(al < IBY2WD)
				al = IBY2WD;
		}else{
			szal = sizeids(t->ids, IBY2WD);
			sz = szal.size;
			al = IBY2LG;
		}
		for(tg = t->tags; tg != nil; tg = tg->next){
			if((tg->ty->ok & OKsized) == OKsized)
				continue;
			tg->ty->ok |= OKsized;
			if(!debug['z']){
				szal = sizeids(tg->ty->ids, sz);
				a = szal.align;
				if(a < al)
					a = al;
				tg->ty->size = align(szal.size, a);
				tg->ty->align = a;
			}else{
				szal = sizeids(tg->ty->ids, sz);
				tg->ty->size = align(szal.size, IBY2LG);
				tg->ty->align = IBY2LG;
			}			
		}
		break;
	case Tfn:
		t->size = 0;
		t->align = 1;
		break;
	case Tainit:
		t->size = 0;
		t->align = 1;
		break;
	case Talt:
		t->size = t->cse->nlab * 2*IBY2WD + 2*IBY2WD;
		t->align = IBY2WD;
		break;
	case Tcase:
	case Tcasec:
		t->size = t->cse->nlab * 3*IBY2WD + 2*IBY2WD;
		t->align = IBY2WD;
		break;
	case Tcasel:
		t->size = t->cse->nlab * 6*IBY2WD + 3*IBY2WD;
		t->align = IBY2LG;
		break;
	case Tgoto:
		t->size = t->cse->nlab * IBY2WD + IBY2WD;
		if(t->cse->iwild != nil)
			t->size += IBY2WD;
		t->align = IBY2WD;
		break;
	case Tiface:
		sz = IBY2WD;
		for(id = t->ids; id != nil; id = id->next){
			sz = align(sz, IBY2WD) + IBY2WD;
			sz += id->sym->len + 1;
			if(id->dot->ty->kind == Tadt)
				sz += id->dot->sym->len + 1;
		}
		t->size = sz;
		t->align = IBY2WD;
		break;
	case Texcept:
		t->size = 0;
		t->align = IBY2WD;
		break;
	}
}

Szal
sizeids(Decl *id, long off)
{
	Szal szal;
	int a, al;

	al = 1;
	for(; id != nil; id = id->next){
		if(storespace[id->store]){
			sizetype(id->ty);
			/*
			 * alignment can be 0 if we have
			 * illegal forward declarations.
			 * just patch a; other code will flag an error
			 */
			a = id->ty->align;
			if(a == 0)
				a = 1;

			if(a > al)
				al = a;

			off = align(off, a);
			id->offset = off;
			off += id->ty->size;
		}
	}
	szal.size = off;
	szal.align = al;
	return szal;
}

long
align(long off, int align)
{
	if(align == 0)
		fatal("align 0");
	while(off % align)
		off++;
	return off;
}

/*
 * recalculate a type's size
 */
void
resizetype(Type *t)
{
	if((t->ok & OKsized) == OKsized){
		t->ok &= ~OKsized;
		cycsizetype(t);
	}
}

/*
 * check if a module is accessable from t
 * if so, mark that module interface
 */
void
modrefable(Type *t)
{
	Decl *id, *m, *tg;

	if(t == nil || (t->ok & OKmodref) == OKmodref)
		return;
	if((t->ok & OKverify) != OKverify)
		fatal("modrefable unused type %t", t);
	t->ok |= OKmodref;
	switch(t->kind){
	case Terror:
	case Tint:
	case Tbig:
	case Tstring:
	case Treal:
	case Tbyte:
	case Tnone:
	case Tany:
	case Tfix:
	case Tpoly:
		break;
	case Tchan:
	case Tref:
	case Tarray:
	case Tlist:
		modrefable(t->tof);
		break;
	case Tmodule:
		t->tof->linkall = 1;
		t->decl->refs++;
		for(id = t->ids; id != nil; id = id->next){
			switch(id->store){
			case Dglobal:
			case Dfn:
				modrefable(id->ty);
				break;
			case Dtype:
				if(id->ty->kind != Tadt)
					break;
				for(m = id->ty->ids; m != nil; m = m->next)
					if(m->store == Dfn)
						modrefable(m->ty);
				break;
			}
		}
		break;
	case Tfn:
	case Tadt:
	case Ttuple:
	case Texception:
		for(id = t->ids; id != nil; id = id->next)
			if(id->store != Dfn)
				modrefable(id->ty);
		for(tg = t->tags; tg != nil; tg = tg->next){
/*
			if((tg->ty->ok & OKmodref) == OKmodref)
				continue;
*/
			tg->ty->ok |= OKmodref;
			for(id = tg->ty->ids; id != nil; id = id->next)
				modrefable(id->ty);
		}
		for(id = t->polys; id != nil; id = id->next)
			modrefable(id->ty);
		modrefable(t->tof);
		break;
	case Tadtpick:
		modrefable(t->decl->dot->ty);
		break;
	default:
		fatal("unknown type kind %d", t->kind);
		break;
	}
}

Desc*
gendesc(Decl *d, long size, Decl *decls)
{
	Desc *desc;

	if(debug['D'])
		print("generate desc for %D\n", d);
	if(ispoly(d))
		addfnptrs(d, 0);
	desc = usedesc(mkdesc(size, decls));
	return desc;
}

Desc*
mkdesc(long size, Decl *d)
{
	uchar *pmap;
	long len, n;

	len = (size+8*IBY2WD-1) / (8*IBY2WD);
	pmap = allocmem(len);
	memset(pmap, 0, len);
	n = descmap(d, pmap, 0);
	if(n >= 0)
		n = n / (8*IBY2WD) + 1;
	else
		n = 0;
	if(n > len)
		fatal("wrote off end of decl map: %ld %ld", n, len);
	return enterdesc(pmap, size, n);
}

Desc*
mktdesc(Type *t)
{
	Desc *d;
	uchar *pmap;
	long len, n;

usedty(t);
	if(debug['D'])
		print("generate desc for %T\n", t);
	if(t->decl == nil){
		t->decl = mkdecl(&t->src, Dtype, t);
		t->decl->sym = enter("_mktdesc_", 0);
	}
	if(t->decl->desc != nil)
		return t->decl->desc;
	len = (t->size+8*IBY2WD-1) / (8*IBY2WD);
	pmap = allocmem(len);
	memset(pmap, 0, len);
	n = tdescmap(t, pmap, 0);
	if(n >= 0)
		n = n / (8*IBY2WD) + 1;
	else
		n = 0;
	if(n > len)
		fatal("wrote off end of type map for %T: %ld %ld 0x%2.2ux", t, n, len, t->ok);
	d = enterdesc(pmap, t->size, n);
	t->decl->desc = d;
	if(debug['j']){
		uchar *m, *e;

		print("generate desc for %T\n", t);
		print("\tdesc\t$%d,%lud,\"", d->id, d->size);
		e = d->map + d->nmap;
		for(m = d->map; m < e; m++)
			print("%.2x", *m);
		print("\"\n");
	}
	return d;
}

Desc*
enterdesc(uchar *map, long size, long nmap)
{
	Desc *d, *last;
	int c;

	last = nil;
	for(d = descriptors; d != nil; d = d->next){
		if(d->size > size || d->size == size && d->nmap > nmap)
			break;
		if(d->size == size && d->nmap == nmap){
			c = memcmp(d->map, map, nmap);
			if(c == 0){
				free(map);
				return d;
			}
			if(c > 0)
				break;
		}
		last = d;
	}
	d = allocmem(sizeof *d);
	d->id = -1;
	d->used = 0;
	d->map = map;
	d->size = size;
	d->nmap = nmap;
	if(last == nil){
		d->next = descriptors;
		descriptors = d;
	}else{
		d->next = last->next;
		last->next = d;
	}
	return d;
}

Desc*
usedesc(Desc *d)
{
	d->used = 1;
	return d;
}

/*
 * create the pointer description byte map for every type in decls
 * each bit corresponds to a word, and is 1 if occupied by a pointer
 * the high bit in the byte maps the first word
 */
long
descmap(Decl *decls, uchar *map, long start)
{
	Decl *d;
	long last, m;

	if(debug['D'])
		print("descmap offset %ld\n", start);
	last = -1;
	for(d = decls; d != nil; d = d->next){
		if(d->store == Dtype && d->ty->kind == Tmodule
		|| d->store == Dfn
		|| d->store == Dconst)
			continue;
		if(d->store == Dlocal && d->link != nil)
			continue;
		m = tdescmap(d->ty, map, d->offset + start);
		if(debug['D']){
			if(d->sym != nil)
				print("descmap %s type %T offset %ld returns %ld\n",
					d->sym->name, d->ty, d->offset+start, m);
			else
				print("descmap type %T offset %ld returns %ld\n", d->ty, d->offset+start, m);
		}
		if(m >= 0)
			last = m;
	}
	return last;
}

long
tdescmap(Type *t, uchar *map, long offset)
{
	Label *lab;
	long i, e, m;
	int bit;

	if(t == nil)
		return -1;

	m = -1;
	if(t->kind == Talt){
		lab = t->cse->labs;
		e = t->cse->nlab;
		offset += IBY2WD * 2;
		for(i = 0; i < e; i++){
			if(lab[i].isptr){
				bit = offset / IBY2WD % 8;
				map[offset / (8*IBY2WD)] |= 1 << (7 - bit);
				m = offset;
			}
			offset += 2*IBY2WD;
		}
		return m;
	}
	if(t->kind == Tcasec){
		e = t->cse->nlab;
		offset += IBY2WD;
		for(i = 0; i < e; i++){
			bit = offset / IBY2WD % 8;
			map[offset / (8*IBY2WD)] |= 1 << (7 - bit);
			offset += IBY2WD;
			bit = offset / IBY2WD % 8;
			map[offset / (8*IBY2WD)] |= 1 << (7 - bit);
			m = offset;
			offset += 2*IBY2WD;
		}
		return m;
	}

	if(tattr[t->kind].isptr){
		bit = offset / IBY2WD % 8;
		map[offset / (8*IBY2WD)] |= 1 << (7 - bit);
		return offset;
	}
	if(t->kind == Tadtpick)
		t = t->tof;
	if(t->kind == Ttuple || t->kind == Tadt || t->kind == Texception){
		if(debug['D'])
			print("descmap adt offset %ld\n", offset);
		if(t->rec != 0)
			fatal("illegal cyclic type %t in tdescmap", t);
		t->rec = 1;
		offset = descmap(t->ids, map, offset);
		t->rec = 0;
		return offset;
	}

	return -1;
}

/*
 * can a t2 be assigned to a t1?
 * any means Tany matches all types,
 * not just references
 */
int
tcompat(Type *t1, Type *t2, int any)
{
	int ok, v;

	if(t1 == t2)
		return 1;
	if(t1 == nil || t2 == nil)
		return 0;
	if(t2->kind == Texception && t1->kind != Texception)
		t2 = mkextuptype(t2);
	tcomset = 0;
	ok = rtcompat(t1, t2, any, 0);
	v = cleartcomrec(t1) + cleartcomrec(t2);
	if(v != tcomset)
		fatal("recid t1 %t and t2 %t not balanced in tcompat: %d v %d", t1, t2, v, tcomset);
	return ok;
}

static int
rtcompat(Type *t1, Type *t2, int any, int inaorc)
{
	if(t1 == t2)
		return 1;
	if(t1 == nil || t2 == nil)
		return 0;
	if(t1->kind == Terror || t2->kind == Terror)
		return 1;
	if(t2->kind == Texception && t1->kind != Texception)
		t2 = mkextuptype(t2);

	if(debug['x'])
		print("rtcompat: %t and %t\n", t1, t2);

	t1->rec |= TRcom;
	t2->rec |= TRcom;
	switch(t1->kind){
	default:
		fatal("unknown type %t v %t in rtcompat", t1, t2);
	case Tstring:
		return t2->kind == Tstring || t2->kind == Tany;
	case Texception:
		if(t2->kind == Texception && t1->cons == t2->cons){
			if(assumetcom(t1, t2))
				return 1;
			return idcompat(t1->ids, t2->ids, 0, inaorc);
		}
		return 0;
	case Tnone:
	case Tint:
	case Tbig:
	case Tbyte:
	case Treal:
		return t1->kind == t2->kind;
	case Tfix:
		return t1->kind == t2->kind && sametree(t1->val, t2->val);
	case Tany:
		if(tattr[t2->kind].isptr)
			return 1;
		return any;
	case Tref:
	case Tlist:
	case Tarray:
	case Tchan:
		if(t1->kind != t2->kind){
			if(t2->kind == Tany)
				return 1;
			return 0;
		}
		if(t1->kind != Tref && assumetcom(t1, t2))
			return 1;
		return rtcompat(t1->tof, t2->tof, 0, t1->kind == Tarray || t1->kind == Tchan || inaorc);
	case Tfn:
		break;
	case Ttuple:
		if(t2->kind == Tadt && t2->tags == nil
		|| t2->kind == Ttuple){
			if(assumetcom(t1, t2))
				return 1;
			return idcompat(t1->ids, t2->ids, any, inaorc);
		}
		if(t2->kind == Tadtpick){
			t2->tof->rec |= TRcom;
			if(assumetcom(t1, t2->tof))
				return 1;
			return idcompat(t1->ids, t2->tof->ids->next, any, inaorc);
		}
		return 0;
	case Tadt:
		if(t2->kind == Ttuple && t1->tags == nil){
			if(assumetcom(t1, t2))
				return 1;
			return idcompat(t1->ids, t2->ids, any, inaorc);
		}
		if(t1->tags != nil && t2->kind == Tadtpick && !inaorc)
			t2 = t2->decl->dot->ty;
		break;
	case Tadtpick:
/*
		if(t2->kind == Ttuple)
			return idcompat(t1->tof->ids->next, t2->ids, any, inaorc);
*/
		break;
	case Tmodule:
		if(t2->kind == Tany)
			return 1;
		break;
	case Tpoly:
		if(t2->kind == Tany)
			return 1;
		break;
	}
	return tequal(t1, t2);
}

/*
 * add the assumption that t1 and t2 are compatable
 */
static int
assumetcom(Type *t1, Type *t2)
{
	Type *r1, *r2;

	if(t1->tcom == nil && t2->tcom == nil){
		tcomset += 2;
		t1->tcom = t2->tcom = t1;
	}else{
		if(t1->tcom == nil){
			r1 = t1;
			t1 = t2;
			t2 = r1;
		}
		for(r1 = t1->tcom; r1 != r1->tcom; r1 = r1->tcom)
			;
		for(r2 = t2->tcom; r2 != nil && r2 != r2->tcom; r2 = r2->tcom)
			;
		if(r1 == r2)
			return 1;
		if(r2 == nil)
			tcomset++;
		t2->tcom = t1;
		for(; t2 != r1; t2 = r2){
			r2 = t2->tcom;
			t2->tcom = r1;
		}
	}
	return 0;
}

static int
cleartcomrec(Type *t)
{
	Decl *id;
	int n;

	n = 0;
	for(; t != nil && (t->rec & TRcom) == TRcom; t = t->tof){
		t->rec &= ~TRcom;
		if(t->tcom != nil){
			t->tcom = nil;
			n++;
		}
		if(t->kind == Tadtpick)
			n += cleartcomrec(t->tof);
		if(t->kind == Tmodule)
			t = t->tof;
		for(id = t->ids; id != nil; id = id->next)
			n += cleartcomrec(id->ty);
		for(id = t->tags; id != nil; id = id->next)
			n += cleartcomrec(id->ty);
		for(id = t->polys; id != nil; id = id->next)
			n += cleartcomrec(id->ty);
	}
	return n;
}

/*
 * id1 and id2 are the fields in an adt or tuple
 * simple structural check; ignore names
 */
static int
idcompat(Decl *id1, Decl *id2, int any, int inaorc)
{
	for(; id1 != nil; id1 = id1->next){
		if(id1->store != Dfield)
			continue;
		while(id2 != nil && id2->store != Dfield)
			id2 = id2->next;
		if(id2 == nil
		|| id1->store != id2->store
		|| !rtcompat(id1->ty, id2->ty, any, inaorc))
			return 0;
		id2 = id2->next;
	}
	while(id2 != nil && id2->store != Dfield)
		id2 = id2->next;
	return id2 == nil;
}

int
tequal(Type *t1, Type *t2)
{
	int ok, v;

	eqrec = 0;
	eqset = 0;
	ok = rtequal(t1, t2);
	v = cleareqrec(t1) + cleareqrec(t2);
	if(v != eqset && 0)
		fatal("recid t1 %t and t2 %t not balanced in tequal: %d %d", t1, t2, v, eqset);
	eqset = 0;
	return ok;
}

/*
 * structural equality on types
 */
static int
rtequal(Type *t1, Type *t2)
{
	/*
	 * this is just a shortcut
	 */
	if(t1 == t2)
		return 1;

	if(t1 == nil || t2 == nil)
		return 0;
	if(t1->kind == Terror || t2->kind == Terror)
		return 1;

	if(t1->kind != t2->kind)
		return 0;

	if(t1->eq != nil && t2->eq != nil)
		return t1->eq == t2->eq;

	if(debug['x'])
		print("rtequal: %t and %t\n", t1, t2);

	t1->rec |= TReq;
	t2->rec |= TReq;
	switch(t1->kind){
	default:
		fatal("unknown type %t v %t in rtequal", t1, t2);
	case Tnone:
	case Tbig:
	case Tbyte:
	case Treal:
	case Tint:
	case Tstring:
		/*
		 * this should always be caught by t1 == t2 check
		 */
		fatal("bogus value type %t vs %t in rtequal", t1, t2);
		return 1;
	case Tfix:
		return sametree(t1->val, t2->val);
	case Tref:
	case Tlist:
	case Tarray:
	case Tchan:
		if(t1->kind != Tref && assumeteq(t1, t2))
			return 1;
		return rtequal(t1->tof, t2->tof);
	case Tfn:
		if(t1->varargs != t2->varargs)
			return 0;
		if(!idequal(t1->ids, t2->ids, 0, storespace))
			return 0;
		/* if(!idequal(t1->polys, t2->polys, 1, nil)) */
		if(!pyequal(t1, t2))
			return 0;
		return rtequal(t1->tof, t2->tof);
	case Ttuple:
	case Texception:
		if(t1->kind != t2->kind || t1->cons != t2->cons)
			return 0;
		if(assumeteq(t1, t2))
			return 1;
		return idequal(t1->ids, t2->ids, 0, storespace);
	case Tadt:
	case Tadtpick:
	case Tmodule:
		if(assumeteq(t1, t2))
			return 1;
		/*
		 * compare interfaces when comparing modules
		 */
		if(t1->kind == Tmodule)
			return idequal(t1->tof->ids, t2->tof->ids, 1, nil);

		/*
		 * picked adts; check parent,
		 * assuming equiv picked fields,
		 * then check picked fields are equiv
		 */
		if(t1->kind == Tadtpick && !rtequal(t1->decl->dot->ty, t2->decl->dot->ty))
			return 0;

		/*
		 * adts with pick tags: check picked fields for equality
		 */
		if(!idequal(t1->tags, t2->tags, 1, nil))
			return 0;

		/* if(!idequal(t1->polys, t2->polys, 1, nil)) */
		if(!pyequal(t1, t2))
			return 0;
		return idequal(t1->ids, t2->ids, 1, storespace);
	case Tpoly:
		if(assumeteq(t1, t2))
			return 1;
		if(t1->decl->sym != t2->decl->sym)
			return 0;
		return idequal(t1->ids, t2->ids, 1, nil);
	}
}

static int
assumeteq(Type *t1, Type *t2)
{
	Type *r1, *r2;

	if(t1->teq == nil && t2->teq == nil){
		eqrec++;
		eqset += 2;
		t1->teq = t2->teq = t1;
	}else{
		if(t1->teq == nil){
			r1 = t1;
			t1 = t2;
			t2 = r1;
		}
		for(r1 = t1->teq; r1 != r1->teq; r1 = r1->teq)
			;
		for(r2 = t2->teq; r2 != nil && r2 != r2->teq; r2 = r2->teq)
			;
		if(r1 == r2)
			return 1;
		if(r2 == nil)
			eqset++;
		t2->teq = t1;
		for(; t2 != r1; t2 = r2){
			r2 = t2->teq;
			t2->teq = r1;
		}
	}
	return 0;
}

/*
 * checking structural equality for adts, tuples, and fns
 */
static int
idequal(Decl *id1, Decl *id2, int usenames, int *storeok)
{
	/*
	 * this is just a shortcut
	 */
	if(id1 == id2)
		return 1;

	for(; id1 != nil; id1 = id1->next){
		if(storeok != nil && !storeok[id1->store])
			continue;
		while(id2 != nil && storeok != nil && !storeok[id2->store])
			id2 = id2->next;
		if(id2 == nil
		|| usenames && id1->sym != id2->sym
		|| id1->store != id2->store
		|| id1->implicit != id2->implicit
		|| id1->cyc != id2->cyc
		|| (id1->dot == nil) != (id2->dot == nil)
		|| id1->dot != nil && id2->dot != nil && id1->dot->ty->kind != id2->dot->ty->kind
		|| !rtequal(id1->ty, id2->ty))
			return 0;
		id2 = id2->next;
	}
	while(id2 != nil && storeok != nil && !storeok[id2->store])
		id2 = id2->next;
	return id1 == nil && id2 == nil;
}

static int
pyequal(Type *t1, Type *t2)
{
	Type *pt1, *pt2;
	Decl *id1, *id2;

	if(t1 == t2)
		return 1;
	id1 = t1->polys;
	id2 = t2->polys;
	for(; id1 != nil; id1 = id1->next){
		if(id2 == nil)
			return 0;
		pt1 = id1->ty;
		pt2 = id2->ty;
		if(!rtequal(pt1, pt2)){
			if(t1->u.tmap != nil)
				pt1 = valtmap(pt1, t1->u.tmap);
			if(t2->u.tmap != nil)
				pt2 = valtmap(pt2, t2->u.tmap);
			if(!rtequal(pt1, pt2))
				return 0;
		}
		id2 = id2->next;
	}
	return id1 == nil && id2 == nil;
}

static int
cleareqrec(Type *t)
{
	Decl *id;
	int n;

	n = 0;
	for(; t != nil && (t->rec & TReq) == TReq; t = t->tof){
		t->rec &= ~TReq;
		if(t->teq != nil){
			t->teq = nil;
			n++;
		}
		if(t->kind == Tadtpick)
			n += cleareqrec(t->decl->dot->ty);
		if(t->kind == Tmodule)
			t = t->tof;
		for(id = t->ids; id != nil; id = id->next)
			n += cleareqrec(id->ty);
		for(id = t->tags; id != nil; id = id->next)
			n += cleareqrec(id->ty);
		for(id = t->polys; id != nil; id = id->next)
			n += cleareqrec(id->ty);
	}
	return n;
}

int
raisescompat(Node *n1, Node *n2)
{
	if(n1 == n2)
		return 1;
	if(n2 == nil)
		return 1;	/* no need to repeat in definition if given in declaration */
	if(n1 == nil)
		return 0;
	for(n1 = n1->left, n2 = n2->left; n1 != nil && n2 != nil; n1 = n1->right, n2 = n2->right){
		if(n1->left->decl != n2->left->decl)
			return 0;
	}
	return n1 == n2;
}

/* t1 a polymorphic type */
static int
fnunify(Type *t1, Type *t2, Tpair **tp, int swapped)
{
	Decl *id, *ids;
	Sym *sym;

	for(ids = t1->ids; ids != nil; ids = ids->next){
		sym = ids->sym;
		id = fnlookup(sym, t2, nil);
		if(id != nil)
			usetype(id->ty);
		if(id == nil){
			if(dowarn)
				error(unifysrc.start, "type %T does not have a '%s' function", t2, sym->name);
			return 0;
		}
		else if(id->ty->kind != Tfn){
			if(dowarn)
				error(unifysrc.start, "%T is not a function", id->ty);
			return 0;
		}
		else if(!rtunify(ids->ty, id->ty, tp, !swapped)){
			if(dowarn)
				error(unifysrc.start, "%T and %T are not compatible wrt %s", ids->ty, id->ty, sym->name);
			return 0;
		}
	}
	return 1;
}

static int
fncleareqrec(Type *t1, Type *t2)
{
	Decl *id, *ids;
	int n;

	n = 0;
	n += cleareqrec(t1);
	n += cleareqrec(t2);
	for(ids = t1->ids; ids != nil; ids = ids->next){
		id = fnlookup(ids->sym, t2, nil);
		if(id == nil)
			continue;
		else{
			n += cleareqrec(ids->ty);
			n += cleareqrec(id->ty);
		}
	}
	return n;
}
int
tunify(Type *t1, Type *t2, Tpair **tp)
{
	int ok, v;
	Tpair *p;

	*tp = nil;
	eqrec = 0;
	eqset = 0;
	ok = rtunify(t1, t2, tp, 0);
	v = cleareqrec(t1) + cleareqrec(t2);
	for(p = *tp; p != nil; p = p->nxt)
		v += fncleareqrec(p->t1, p->t2);
	if(0 && v != eqset)
		fatal("recid t1 %t and t2 %t not balanced in tunify: %d %d", t1, t2, v, eqset);
	return ok;
}

static int
rtunify(Type *t1, Type *t2, Tpair **tp, int swapped)
{
	Type *tmp;

if(debug['w']) print("rtunifya - %T %T\n", t1, t2);
	t1 = valtmap(t1, *tp);
	t2 = valtmap(t2, *tp);
if(debug['w']) print("rtunifyb - %T %T\n", t1, t2);
	if(t1 == t2)
		return 1;
	if(t1 == nil || t2 == nil)
		return 0;
	if(t1->kind == Terror || t2->kind == Terror)
		return 1;
	if(t1->kind != Tpoly && t2->kind == Tpoly){
		tmp = t1;
		t1 = t2;
		t2 = tmp;
		swapped = !swapped;
	}
	if(t1->kind == Tpoly){
/*
		if(typein(t1, t2))
			 return 0;
*/
		if(!tattr[t2->kind].isptr)
			return 0;
		if(t2->kind != Tany)
			addtmap(t1, t2, tp);
		return fnunify(t1, t2, tp, swapped);
	}
	if(t1->kind != Tany && t2->kind == Tany){
		tmp = t1;
		t1 = t2;
		t2 = tmp;
		swapped = !swapped;
	}
	if(t1->kind == Tadt && t1->tags != nil && t2->kind == Tadtpick && !swapped)
		t2 = t2->decl->dot->ty;
	if(t2->kind == Tadt && t2->tags != nil && t1->kind == Tadtpick && swapped)
		t1 = t1->decl->dot->ty;
	if(t1->kind != Tany && t1->kind != t2->kind)
		return 0;
	t1->rec |= TReq;
	t2->rec |= TReq;
	switch(t1->kind){
	default:
		return tequal(t1, t2);
	case Tany:
		return tattr[t2->kind].isptr;
	case Tref:
	case Tlist:
	case Tarray:
	case Tchan:
		if(t1->kind != Tref && assumeteq(t1, t2))
			return 1;
		return rtunify(t1->tof, t2->tof, tp, swapped);
	case Tfn:
		if(!idunify(t1->ids, t2->ids, tp, swapped))
			return 0;
		if(!idunify(t1->polys, t2->polys, tp, swapped))
			return 0;
		return rtunify(t1->tof, t2->tof, tp, swapped);
	case Ttuple:
		if(assumeteq(t1, t2))
			return 1;
		return idunify(t1->ids, t2->ids, tp, swapped);
	case Tadt:
	case Tadtpick:
		if(assumeteq(t1, t2))
			return 1;
		if(!idunify(t1->polys, t2->polys, tp, swapped))
			return 0;
		if(!idunify(t1->tags, t2->tags, tp, swapped))
			return 0;
		return idunify(t1->ids, t2->ids, tp, swapped);
	case Tmodule:
		if(assumeteq(t1, t2))
			return 1;
		return idunify(t1->tof->ids, t2->tof->ids, tp, swapped);
	case Tpoly:
		return t1 == t2;
	}
}

static int
idunify(Decl *id1, Decl *id2, Tpair **tp, int swapped)
{
	if(id1 == id2)
		return 1;
	for(; id1 != nil; id1 = id1->next){
		if(id2 == nil || !rtunify(id1->ty, id2->ty, tp, swapped))
			return 0;
		id2 = id2->next;
	}
	return id1 == nil && id2 == nil;
}

int
polyequal(Decl *id1, Decl *id2)
{
	int ck2;
	Decl *d;

	/* allow id2 list to have an optional for clause */
	ck2 = 0;
	for(d = id2; d != nil; d = d->next)
		if(d->ty->ids != nil)
			ck2 = 1;
	for( ; id1 != nil; id1 = id1->next){
		if(id2 == nil
		|| id1->sym != id2->sym
		|| id1->ty->decl != nil && id2->ty->decl != nil && id1->ty->decl->sym != id2->ty->decl->sym)
			return 0;
		if(ck2 && !idequal(id1->ty->ids, id2->ty->ids, 1, nil))
			return 0;
		id2 = id2->next;
	}
	return id1 == nil && id2 == nil;
}

Type*
calltype(Type *f, Node *a, Type *rt)
{
	Type *t;
	Decl *id, *first, *last;

	first = last = nil;
	t = mktype(&f->src.start, &f->src.stop, Tfn, rt, nil);
	t->polys = f->kind == Tref ? f->tof->polys : f->polys;
	for( ; a != nil; a = a->right){
		id = mkdecl(&f->src, Darg, a->left->ty);
		if(last == nil)
			first = id;
		else
			last->next = id;
		last = id;
	}
	t->ids = first;
	if(f->kind == Tref)
		t = mktype(&f->src.start, &f->src.stop, Tref, t, nil);
	return t;
}

static Type*
duptype(Type *t)
{
	Type *nt;

	nt = allocmem(sizeof(*nt));
	*nt = *t;
	nt->ok &= ~(OKverify|OKref|OKclass|OKsized|OKcycsize|OKcyc);
	nt->flags |= INST;
	nt->eq = nil;
	nt->sbl = -1;
	if(t->decl != nil && (nt->kind == Tadt || nt->kind == Tadtpick || nt->kind == Ttuple)){
		nt->decl = dupdecl(t->decl);
		nt->decl->ty = nt;
		nt->decl->link = t->decl;
		if(t->decl->dot != nil){
			nt->decl->dot = dupdecl(t->decl->dot);
			nt->decl->dot->link = t->decl->dot;
		}
	}
	else
		nt->decl = nil;
	return nt;
}

static int
dpolys(Decl *ids)
{
	Decl *p;

	for(p = ids; p != nil; p = p->next)
		if(tpolys(p->ty))
			return 1;
	return 0;
}

static int
tpolys(Type *t)
{
	int v;
	Typelist *tl;

	if(t == nil)
		return 0;
	if(t->flags&(POLY|NOPOLY))
		return t->flags&POLY;
	switch(t->kind){
	default:
		v = 0;
		break;
	case Tarrow:
	case Tdot:
	case Tpoly:
		v = 1;
		break;
	case Tref:
	case Tlist:
	case Tarray:
	case Tchan:
		v = tpolys(t->tof);
		break;
	case Tid:
		v = tpolys(t->decl->ty);
		break;
	case Tinst:
		v = 0;
		for(tl = t->u.tlist; tl != nil; tl = tl->nxt)
			if(tpolys(tl->t)){
				v = 1;
				break;
			}
		if(v == 0)
			v = tpolys(t->tof);
		break;
	case Tfn:
	case Tadt:
	case Tadtpick:
	case Ttuple:
	case Texception:
		if(t->polys != nil){
			v = 1;
			break;
		}
		if(t->rec&TRvis)
			return 0;
		t->rec |= TRvis;
		v = tpolys(t->tof) || dpolys(t->polys) || dpolys(t->ids) || dpolys(t->tags);
		t->rec &= ~TRvis;
		if(t->kind == Tadtpick && v == 0)
			v = tpolys(t->decl->dot->ty);
		break;
	}
	if(v)
		t->flags |= POLY;
	else
		t->flags |= NOPOLY;
	return v;
}

static int
doccurs(Decl *ids, Tpair **tp)
{
	Decl *p;

	for(p = ids; p != nil; p = p->next)
		if(toccurs(p->ty, tp))
			return 1;
	return 0;
}

static int
toccurs(Type *t, Tpair **tp)
{
	int o;
	Typelist *tl;

	if(t == nil)
		return 0;
	if(!(t->flags&(POLY|NOPOLY)))
		tpolys(t);
	if(t->flags&NOPOLY)
		return 0;
	switch(t->kind){
		default:
			fatal("unknown type %t in toccurs", t);
		case Tnone:
		case Tbig:
		case Tbyte:
		case Treal:
		case Tint:
		case Tstring:
		case Tfix:
		case Tmodule:
		case Terror:
			return 0;
		case Tarrow:
		case Tdot:
			return 1;
		case Tpoly:
			return valtmap(t, *tp) != t;
		case Tref:
		case Tlist:
		case Tarray:
		case Tchan:
			return toccurs(t->tof, tp);
		case Tid:
			return toccurs(t->decl->ty, tp);
		case Tinst:
			for(tl = t->u.tlist; tl != nil; tl = tl->nxt)
				if(toccurs(tl->t, tp))
					return 1;
			return toccurs(t->tof, tp);
		case Tfn:
		case Tadt:
		case Tadtpick:
		case Ttuple:
		case Texception:
			if(t->rec&TRvis)
				return 0;
			t->rec |= TRvis;
			o = toccurs(t->tof, tp) || doccurs(t->polys, tp) || doccurs(t->ids, tp) || doccurs(t->tags, tp);
			t->rec &= ~TRvis;
			if(t->kind == Tadtpick && o == 0)
				o = toccurs(t->decl->dot->ty, tp);
			return o;
	}
}

static Decl*
expandids(Decl *ids, Decl *adtt, Tpair **tp, int sym)
{
	Decl *p, *q, *nids, *last;

	nids = last = nil;
	for(p = ids; p != nil; p = p->next){
		q = dupdecl(p);
		q->ty = expandtype(p->ty, nil, adtt, tp);
		if(sym && q->ty->decl != nil)
			q->sym = q->ty->decl->sym;
		if(q->store == Dfn){
if(debug['v']) print("%p->link = %p\n", q, p);
			q->link = p;
		}
		if(nids == nil)
			nids = q;
		else
			last->next = q;
		last = q;
	}
	return nids;
}

Type*
expandtype(Type *t, Type *instt, Decl *adtt, Tpair **tp)
{
	Type *nt;
	Decl *ids;

	if(t == nil)
		return nil;
if(debug['w']) print("expandtype %d %#p %T\n", t->kind, t, t);
	if(!toccurs(t, tp))
		return t;
if(debug['w']) print("\texpanding\n");
	switch(t->kind){
		default:
			fatal("unknown type %t in expandtype", t);
		case Tpoly:
			return valtmap(t, *tp);
		case Tref:
		case Tlist:
		case Tarray:
		case Tchan:
			nt = duptype(t);
			nt->tof = expandtype(t->tof, nil, adtt, tp);
			return nt;
		case Tid:
			return expandtype(idtype(t), nil, adtt, tp);
		case Tdot:
			return expandtype(dottype(t, adtt), nil, adtt, tp);
		case Tarrow:
			return expandtype(arrowtype(t, adtt), nil, adtt, tp);
		case Tinst:
			if((nt = valtmap(t, *tp)) != t)
				return nt;
			return expandtype(insttype(t, adtt, tp), nil, adtt, tp);
		case Tfn:
		case Tadt:
		case Tadtpick:
		case Ttuple:
		case Texception:
			if((nt = valtmap(t, *tp)) != t)
				return nt;
			if(t->kind == Tadt)
				adtt = t->decl;
			nt = duptype(t);
			addtmap(t, nt, tp);
			if(instt != nil)
				addtmap(instt, nt, tp);
			nt->tof = expandtype(t->tof, nil, adtt, tp);
			nt->polys = expandids(t->polys, adtt, tp, 1);
			nt->ids = expandids(t->ids, adtt, tp, 0);
			nt->tags = expandids(t->tags, adtt, tp, 0);
			if(t->kind == Tadt){
				for(ids = nt->tags; ids != nil; ids = ids->next)
					ids->ty->decl->dot = nt->decl;
			}
			if(t->kind == Tadtpick){
				nt->decl->dot->ty = expandtype(t->decl->dot->ty, nil, adtt, tp);
			}
			if((t->kind == Tadt || t->kind == Tadtpick) && t->u.tmap != nil){
				Tpair *p;

				nt->u.tmap = nil;
				for(p = t->u.tmap; p != nil; p = p->nxt)
					addtmap(valtmap(p->t1, *tp), valtmap(p->t2, *tp), &nt->u.tmap);
				if(debug['w']){
					print("new tmap for %T->%T: ", t, nt);
					for(p=nt->u.tmap;p!=nil;p=p->nxt)print("%T -> %T ", p->t1, p->t2);
					print("\n");
				}
			}
			return nt;
	}
}

/*
 * create type signatures
 * sign the same information used
 * for testing type equality
 */
ulong
sign(Decl *d)
{
	Type *t;
	uchar *sig, md5sig[MD5dlen];
	char buf[StrSize];
	int i, sigend, sigalloc, v;

	t = d->ty;
	if(t->sig != 0)
		return t->sig;

	if(ispoly(d))
		rmfnptrs(d);

	sig = 0;
	sigend = -1;
	sigalloc = 1024;
	while(sigend < 0 || sigend >= sigalloc){
		sigalloc *= 2;
		sig = reallocmem(sig, sigalloc);
		eqrec = 0;
		sigend = rtsign(t, sig, sigalloc, 0);
		v = clearrec(t);
		if(v != eqrec)
			fatal("recid not balanced in sign: %d %d", v, eqrec);
		eqrec = 0;
	}
	sig[sigend] = '\0';

	if(signdump != nil){
		seprint(buf, buf+sizeof(buf), "%D", d);
		if(strcmp(buf, signdump) == 0){
			print("sign %D len %d\n", d, sigend);
			print("%s\n", (char*)sig);
		}
	}

	md5(sig, sigend, md5sig, nil);
	for(i = 0; i < MD5dlen; i += 4)
		t->sig ^= md5sig[i+0] | (md5sig[i+1]<<8) | (md5sig[i+2]<<16) | (md5sig[i+3]<<24);
	if(debug['S'])
		print("signed %D type %T len %d sig %#lux\n", d, t, sigend, t->sig);
	free(sig);
	return t->sig;
}

enum
{
	SIGSELF =	'S',
	SIGVARARGS =	'*',
	SIGCYC =	'y',
	SIGREC =	'@'
};

static int sigkind[Tend] =
{
	/* Tnone */	'n',
	/* Tadt */	'a',
	/* Tadtpick */	'p',
	/* Tarray */	'A',
	/* Tbig */	'B',
	/* Tbyte */	'b',
	/* Tchan */	'C',
	/* Treal */	'r',
	/* Tfn */	'f',
	/* Tint */	'i',
	/* Tlist */	'L',
	/* Tmodule */	'm',
	/* Tref */	'R',
	/* Tstring */	's',
	/* Ttuple */	't',
	/* Texception */	'e',
	/* Tfix */	'x',
	/* Tpoly */	'P',
};

static int
rtsign(Type *t, uchar *sig, int lensig, int spos)
{
	Decl *id, *tg;
	char name[32];
	int kind, lenname;

	if(t == nil)
		return spos;

	if(spos < 0 || spos + 8 >= lensig)
		return -1;

	if(t->eq != nil && t->eq->id){
		if(t->eq->id < 0 || t->eq->id > eqrec)
			fatal("sign rec %T %d %d", t, t->eq->id, eqrec);

		sig[spos++] = SIGREC;
		seprint(name, name+sizeof(name), "%d", t->eq->id);
		lenname = strlen(name);
		if(spos + lenname > lensig)
			return -1;
		strcpy((char*)&sig[spos], name);
		spos += lenname;
		return spos;
	}
	if(t->eq != nil){
		eqrec++;
		t->eq->id = eqrec;
	}

	kind = sigkind[t->kind];
	sig[spos++] = kind;
	if(kind == 0)
		fatal("no sigkind for %t", t);

	t->rec = 1;
	switch(t->kind){
	default:
		fatal("bogus type %t in rtsign", t);
		return -1;
	case Tnone:
	case Tbig:
	case Tbyte:
	case Treal:
	case Tint:
	case Tstring:
	case Tpoly:
		return spos;
	case Tfix:
		seprint(name, name+sizeof(name), "%g", t->val->rval);
		lenname = strlen(name);
		if(spos+lenname-1 >= lensig)
			return -1;
		strcpy((char*)&sig[spos], name);
		spos += lenname;
		return spos;
	case Tref:
	case Tlist:
	case Tarray:
	case Tchan:
		return rtsign(t->tof, sig, lensig, spos);
	case Tfn:
		if(t->varargs != 0)
			sig[spos++] = SIGVARARGS;
		if(t->polys != nil)
			spos = idsign(t->polys, 0, sig, lensig, spos);
		spos = idsign(t->ids, 0, sig, lensig, spos);
		if(t->u.eraises)
			spos = raisessign(t->u.eraises, sig, lensig, spos);
		return rtsign(t->tof, sig, lensig, spos);
	case Ttuple:
		return idsign(t->ids, 0, sig, lensig, spos);
	case Tadt:
		/*
		 * this is a little different than in rtequal,
		 * since we flatten the adt we used to represent the globals
		 */
		if(t->eq == nil){
			if(strcmp(t->decl->sym->name, ".mp") != 0)
				fatal("no t->eq field for %t", t);
			spos--;
			for(id = t->ids; id != nil; id = id->next){
				spos = idsign1(id, 1, sig, lensig, spos);
				if(spos < 0 || spos >= lensig)
					return -1;
				sig[spos++] = ';';
			}
			return spos;
		}
		if(t->polys != nil)
			spos = idsign(t->polys, 0, sig, lensig, spos);
		spos = idsign(t->ids, 1, sig, lensig, spos);
		if(spos < 0 || t->tags == nil)
			return spos;

		/*
		 * convert closing ')' to a ',', then sign any tags
		 */
		sig[spos-1] = ',';
		for(tg = t->tags; tg != nil; tg = tg->next){
			lenname = tg->sym->len;
			if(spos + lenname + 2 >= lensig)
				return -1;
			strcpy((char*)&sig[spos], tg->sym->name);
			spos += lenname;
			sig[spos++] = '=';
			sig[spos++] = '>';

			spos = rtsign(tg->ty, sig, lensig, spos);
			if(spos < 0 || spos >= lensig)
				return -1;

			if(tg->next != nil)
				sig[spos++] = ',';
		}
		if(spos >= lensig)
			return -1;
		sig[spos++] = ')';
		return spos;
	case Tadtpick:
		spos = idsign(t->ids, 1, sig, lensig, spos);
		if(spos < 0)
			return spos;
		return rtsign(t->decl->dot->ty, sig, lensig, spos);
	case Tmodule:
		if(t->tof->linkall == 0)
			fatal("signing a narrowed module");

		if(spos >= lensig)
			return -1;
		sig[spos++] = '{';
		for(id = t->tof->ids; id != nil; id = id->next){
			if(id->tag)
				continue;
			if(strcmp(id->sym->name, ".mp") == 0){
				spos = rtsign(id->ty, sig, lensig, spos);
				if(spos < 0)
					return -1;
				continue;
			}
			spos = idsign1(id, 1, sig, lensig, spos);
			if(spos < 0 || spos >= lensig)
				return -1;
			sig[spos++] = ';';
		}
		if(spos >= lensig)
			return -1;
		sig[spos++] = '}';
		return spos;
	}
}

static int
idsign(Decl *id, int usenames, uchar *sig, int lensig, int spos)
{
	int first;

	if(spos >= lensig)
		return -1;
	sig[spos++] = '(';
	first = 1;
	for(; id != nil; id = id->next){
		if(id->store == Dlocal)
			fatal("local %s in idsign", id->sym->name);

		if(!storespace[id->store])
			continue;

		if(!first){
			if(spos >= lensig)
				return -1;
			sig[spos++] = ',';
		}

		spos = idsign1(id, usenames, sig, lensig, spos);
		if(spos < 0)
			return -1;
		first = 0;
	}
	if(spos >= lensig)
		return -1;
	sig[spos++] = ')';
	return spos;
}

static int
idsign1(Decl *id, int usenames, uchar *sig, int lensig, int spos)
{
	char *name;
	int lenname;

	if(usenames){
		name = id->sym->name;
		lenname = id->sym->len;
		if(spos + lenname + 1 >= lensig)
			return -1;
		strcpy((char*)&sig[spos], name);
		spos += lenname;
		sig[spos++] = ':';
	}

	if(spos + 2 >= lensig)
		return -1;

	if(id->implicit != 0)
		sig[spos++] = SIGSELF;

	if(id->cyc != 0)
		sig[spos++] = SIGCYC;

	return rtsign(id->ty, sig, lensig, spos);
}

static int
raisessign(Node *n, uchar *sig, int lensig, int spos)
{
	int m;
	char *s;
	Node *nn;

	if(spos >= lensig)
		return -1;
	sig[spos++] = '(';
	for(nn = n->left; nn != nil; nn = nn->right){
		s = nn->left->decl->sym->name;
		m = nn->left->decl->sym->len;
		if(spos+m-1 >= lensig)
			return -1;
		strcpy((char*)&sig[spos], s);
		spos += m;
		if(nn->right != nil){
			if(spos >= lensig)
				return -1;
			sig[spos++] = ',';
		}
	}
	if(spos >= lensig)
		return -1;
	sig[spos++] = ')';
	return spos;
}

static int
clearrec(Type *t)
{
	Decl *id;
	int n;

	n = 0;
	for(; t != nil && t->rec; t = t->tof){
		t->rec = 0;
		if(t->eq != nil && t->eq->id != 0){
			t->eq->id = 0;
			n++;
		}
		if(t->kind == Tmodule){
			for(id = t->tof->ids; id != nil; id = id->next)
				n += clearrec(id->ty);
			return n;
		}
		if(t->kind == Tadtpick)
			n += clearrec(t->decl->dot->ty);
		for(id = t->ids; id != nil; id = id->next)
			n += clearrec(id->ty);
		for(id = t->tags; id != nil; id = id->next)
			n += clearrec(id->ty);
		for(id = t->polys; id != nil; id = id->next)
			n += clearrec(id->ty);
	}
	return n;
}

/* must a variable of the given type be zeroed ? (for uninitialized declarations inside loops) */
int
tmustzero(Type *t)
{
	if(t==nil)
		return 0;
	if(tattr[t->kind].isptr)
		return 1;
	if(t->kind == Tadtpick)
		t = t->tof;
	if(t->kind == Ttuple || t->kind == Tadt)
		return mustzero(t->ids);
	return 0;
}

int
mustzero(Decl *decls)
{
	Decl *d;

	for (d = decls; d != nil; d = d->next)
		if (tmustzero(d->ty))
			return 1;
	return 0;
}

int
typeconv(Fmt *f)
{
	Type *t;
	char *p, buf[1024];

	t = va_arg(f->args, Type*);
	if(t == nil){
		p = "nothing";
	}else{
		p = buf;
		buf[0] = 0;
		tprint(buf, buf+sizeof(buf), t);
	}
	return fmtstrcpy(f, p);
}

int
stypeconv(Fmt *f)
{
	Type *t;
	char *p, buf[1024];

	t = va_arg(f->args, Type*);
	if(t == nil){
		p = "nothing";
	}else{
		p = buf;
		buf[0] = 0;
		stprint(buf, buf+sizeof(buf), t);
	}
	return fmtstrcpy(f, p);
}

int
ctypeconv(Fmt *f)
{
	Type *t;
	char buf[1024];

	t = va_arg(f->args, Type*);
	buf[0] = 0;
	ctprint(buf, buf+sizeof(buf), t);
	return fmtstrcpy(f, buf);
}

char*
tprint(char *buf, char *end, Type *t)
{
	Decl *id;
	Typelist *tl;

	if(t == nil)
		return buf;
	if(t->kind >= Tend)
		return seprint(buf, end, "kind %d", t->kind);
	switch(t->kind){
	case Tarrow:
		buf = seprint(buf, end, "%T->%s", t->tof, t->decl->sym->name);
		break;
	case Tdot:
		buf = seprint(buf, end, "%T.%s", t->tof, t->decl->sym->name);
		break;
	case Tid:
	case Tpoly:
		buf = seprint(buf, end, "%s", t->decl->sym->name);
		break;
	case Tinst:
		buf = tprint(buf, end, t->tof);
		buf = secpy(buf ,end, "[");
		for(tl = t->u.tlist; tl != nil; tl = tl->nxt){
			buf = tprint(buf, end, tl->t);
			if(tl->nxt != nil)
				buf = secpy(buf, end, ", ");
		}
		buf = secpy(buf, end, "]");
		break;
	case Tint:
	case Tbig:
	case Tstring:
	case Treal:
	case Tbyte:
	case Tany:
	case Tnone:
	case Terror:
	case Tainit:
	case Talt:
	case Tcase:
	case Tcasel:
	case Tcasec:
	case Tgoto:
	case Tiface:
	case Texception:
	case Texcept:
		buf = secpy(buf, end, kindname[t->kind]);
		break;
	case Tfix:
		buf = seprint(buf, end, "%s(%v)", kindname[t->kind], t->val);
		break;
	case Tref:
		buf = secpy(buf, end, "ref ");
		buf = tprint(buf, end, t->tof);
		break;
	case Tchan:
	case Tarray:
	case Tlist:
		buf = seprint(buf, end, "%s of ", kindname[t->kind]);
		buf = tprint(buf, end, t->tof);
		break;
	case Tadtpick:
		buf = seprint(buf, end, "%s.%s", t->decl->dot->sym->name, t->decl->sym->name);
		break;
	case Tadt:
		if(t->decl->dot != nil && !isimpmod(t->decl->dot->sym))
			buf = seprint(buf, end, "%s->%s", t->decl->dot->sym->name, t->decl->sym->name);
		else
			buf = seprint(buf, end, "%s", t->decl->sym->name);
		if(t->polys != nil){
			buf = secpy(buf ,end, "[");
			for(id = t->polys; id != nil; id = id->next){
				if(t->u.tmap != nil)
					buf = tprint(buf, end, valtmap(id->ty, t->u.tmap));
				else
					buf = seprint(buf, end, "%s", id->sym->name);
				if(id->next != nil)
					buf = secpy(buf, end, ", ");
			}
			buf = secpy(buf, end, "]");
		}
		break;
	case Tmodule:
		buf = seprint(buf, end, "%s", t->decl->sym->name);
		break;
	case Ttuple:
		buf = secpy(buf, end, "(");
		for(id = t->ids; id != nil; id = id->next){
			buf = tprint(buf, end, id->ty);
			if(id->next != nil)
				buf = secpy(buf, end, ", ");
		}
		buf = secpy(buf, end, ")");
		break;
	case Tfn:
		buf = secpy(buf, end, "fn");
		if(t->polys != nil){
			buf = secpy(buf, end, "[");
			for(id = t->polys; id != nil; id = id->next){
				buf = seprint(buf, end, "%s", id->sym->name);
				if(id->next != nil)
					buf = secpy(buf, end, ", ");
			}
			buf = secpy(buf, end, "]");
		}
		buf = secpy(buf, end, "(");
		for(id = t->ids; id != nil; id = id->next){
			if(id->sym == nil)
				buf = secpy(buf, end, "nil: ");
			else
				buf = seprint(buf, end, "%s: ", id->sym->name);
			if(id->implicit)
				buf = secpy(buf, end, "self ");
			buf = tprint(buf, end, id->ty);
			if(id->next != nil)
				buf = secpy(buf, end, ", ");
		}
		if(t->varargs && t->ids != nil)
			buf = secpy(buf, end, ", *");
		else if(t->varargs)
			buf = secpy(buf, end, "*");
		if(t->tof != nil && t->tof->kind != Tnone){
			buf = secpy(buf, end, "): ");
			buf = tprint(buf, end, t->tof);
			break;
		}
		buf = secpy(buf, end, ")");
		break;
	default:
		yyerror("tprint: unknown type kind %d", t->kind);
		break;
	}
	return buf;
}

char*
stprint(char *buf, char *end, Type *t)
{
	if(t == nil)
		return buf;
	switch(t->kind){
	case Tid:
		return seprint(buf, end, "id %s", t->decl->sym->name);
	case Tadt:
	case Tadtpick:
	case Tmodule:
		buf = secpy(buf, end, kindname[t->kind]);
		buf = secpy(buf, end, " ");
		return tprint(buf, end, t);
	}
	return tprint(buf, end, t);
}

/* generalize ref P.A, ref P.B to ref P */

/*
Type*
tparentx(Type *t1, Type* t2)
{
	if(t1 == nil || t2 == nil || t1->kind != Tref || t2->kind != Tref)
		return t1;
	t1 = t1->tof;
	t2 = t2->tof;
	if(t1 == nil || t2 == nil || t1->kind != Tadtpick || t2->kind != Tadtpick)
		return t1;
	t1 = t1->decl->dot->ty;
	t2 = t2->decl->dot->ty;
	if(tequal(t1, t2))
		return mktype(&t1->src.start, &t1->src.stop, Tref, t1, nil);
	return t1;
}
*/

static int
tparent0(Type *t1, Type *t2)
{
	Decl *id1, *id2;

	if(t1 == t2)
		return 1;
	if(t1 == nil || t2 == nil)
		return 0;
	if(t1->kind == Tadt && t2->kind == Tadtpick)
		t2 = t2->decl->dot->ty;
	if(t1->kind == Tadtpick && t2->kind == Tadt)
		t1 = t1->decl->dot->ty;
	if(t1->kind != t2->kind)
		return 0;
	switch(t1->kind){
	default:
		fatal("unknown type %t v %t in tparent", t1, t2);
		break;
	case Terror:
	case Tstring:
	case Tnone:
	case Tint:
	case Tbig:
	case Tbyte:
	case Treal:
	case Tany:
		return 1;
	case Texception:
	case Tfix:
	case Tfn:
	case Tadt:
	case Tmodule:
	case Tpoly:
		return tcompat(t1, t2, 0);
	case Tref:
	case Tlist:
	case Tarray:
	case Tchan:
		return tparent0(t1->tof, t2->tof);
	case Ttuple:
		for(id1 = t1->ids, id2 = t2->ids; id1 != nil && id2 != nil; id1 = id1->next, id2 = id2->next)
			if(!tparent0(id1->ty, id2->ty))
				return 0;
		return id1 == nil && id2 == nil;
	case Tadtpick:
		return tequal(t1->decl->dot->ty, t2->decl->dot->ty);
	}
	return 0;
}

static Type*
tparent1(Type *t1, Type *t2)
{
	Type *t, *nt;
	Decl *id, *id1, *id2, *idt;

	if(t1->kind == Tadt && t2->kind == Tadtpick)
		t2 = t2->decl->dot->ty;
	if(t1->kind == Tadtpick && t2->kind == Tadt)
		t1 = t1->decl->dot->ty;
	switch(t1->kind){
	default:
		return t1;
	case Tref:
	case Tlist:
	case Tarray:
	case Tchan:
		t = tparent1(t1->tof, t2->tof);
		if(t == t1->tof)
			return t1;
		return mktype(&t1->src.start, &t1->src.stop, t1->kind, t, nil);
	case Ttuple:
		nt = nil;
		id = nil;
		for(id1 = t1->ids, id2 = t2->ids; id1 != nil && id2 != nil; id1 = id1->next, id2 = id2->next){
			t = tparent1(id1->ty, id2->ty);
			if(t != id1->ty){
				if(nt == nil){
					nt = mktype(&t1->src.start, &t1->src.stop, Ttuple, nil, dupdecls(t1->ids));
					for(id = nt->ids, idt = t1->ids; idt != id1; id = id->next, idt = idt->next)
						;
				}
				id->ty = t;
			}
			if(id != nil)
				id = id->next;
		}
		if(nt == nil)
			return t1;
		return nt;
	case Tadtpick:
		if(tequal(t1, t2))
			return t1;
		return t1->decl->dot->ty;
	}
}

Type*
tparent(Type *t1, Type *t2)
{
	if(tparent0(t1, t2))
		return tparent1(t1, t2);
	return t1;
}

/*
 * make the tuple type used to initialize an exception type
 */
Type*
mkexbasetype(Type *t)
{
	Decl *id, *new, *last;
	Type *nt;

	if(!t->cons)
		fatal("mkexbasetype on non-constant");
	last = mkids(&t->decl->src, nil, tstring, nil);
	last->store = Dfield;
	nt = mktype(&t->src.start, &t->src.stop, Texception, nil, last);
	nt->cons = 0;
	new = mkids(&t->decl->src, nil, tint, nil);
	new->store = Dfield;
	last->next = new;
	last = new;
	for(id = t->ids; id != nil; id = id->next){
		new = allocmem(sizeof *id);
		*new = *id;
		new->cyc = 0;
		last->next = new;
		last = new;
	}
	last->next = nil;
	return usetype(nt);
}

/*
 * make an instantiated exception type
 */
Type*
mkextype(Type *t)
{
	Type *nt;

	if(!t->cons)
		fatal("mkextype on non-constant");
	if(t->tof != nil)
		return t->tof;
	nt = copytypeids(t);
	nt->cons = 0;
	t->tof = usetype(nt);
	return t->tof;
}

/*
 * convert an instantiated exception type to its underlying type
 */
Type*
mkextuptype(Type *t)
{
	Decl *id;
	Type *nt;

	if(t->cons)
		return t;
	if(t->tof != nil)
		return t->tof;
	id = t->ids;
	if(id == nil)
		nt = t;
	else if(id->next == nil)
		nt = id->ty;
	else{
		nt = copytypeids(t);
		nt->cons = 0;
		nt->kind = Ttuple;
	}
	t->tof = usetype(nt);
	return t->tof;
}

static void
ckfix(Type *t, double max)
{
	int p;
	vlong k, x;
	double s;

	s = t->val->rval;
	if(max == 0.0)
		k = ((vlong)1<<32)-1;
	else
		k = 2*(vlong)(max/s+0.5)+1;
	x = 1;
	for(p = 0; k > x; p++)
		x *= 2;
	if(p == 0 || p > 32){
		error(t->src.start, "cannot fit fixed type into an int");
		return;
	}
	if(p < 32)
		t->val->rval /= (double)(1<<(32-p));
}

double
scale(Type *t)
{
	Node *n;

	if(t->kind == Tint || t->kind == Treal)
		return 1.0;
	if(t->kind != Tfix)
		fatal("scale() on non fixed point type");
	n = t->val;
	if(n->op != Oconst)
		fatal("non constant scale");
	if(n->ty != treal)
		fatal("non real scale");
	return n->rval;
}

double
scale2(Type *f, Type *t)
{
	return scale(f)/scale(t);
}

#define I(x)	((int)(x))
#define V(x)	((Long)(x))
#define D(x)	((double)(x))

/* put x in normal form */
static int
nf(double x, int *mant)
{
	int p;
	double m;

	p = 0;
	m = x;
	while(m >= 1){
		p++;
		m /= 2;
	}
	while(m < 0.5){
		p--;
		m *= 2;
	}
	m *= D(1<<16)*D(1<<15);
	if(m >= D(0x7fffffff) - 0.5){
		*mant = 0x7fffffff;
		return p;
	}
	*mant = I(m+0.5);
	return p;
}

static int
ispow2(double x)
{
	int m;

	nf(x, &m);
	if(m != 1<<30)
		return 0;
	return 1;
}

static int
fround(double x, int n, int *m)
{
	if(n != 31)
		fatal("not 31 in fround");
	return nf(x, m);
}

static int
fixmul2(double sx, double sy, double sr, int *rp, int *ra)
{
	int k, n, a;
	double alpha;

	alpha = (sx*sy)/sr;
	n = 31;
	k = fround(1/alpha, n, &a);
	*rp = 1-k;
	*ra = 0;
	return IMULX;
}

static int
fixdiv2(double sx, double sy, double sr, int *rp, int *ra)
{
	int k, n, b;
	double beta;

	beta = sx/(sy*sr);
	n = 31;
	k = fround(beta, n, &b);
	*rp = k-1;
	*ra = 0;
	return IDIVX;
}

static int
fixmul(double sx, double sy, double sr, int *rp, int *ra)
{
	int k, m, n, a, v;
	vlong W;
	double alpha, eps;

	alpha = (sx*sy)/sr;
	if(ispow2(alpha))
		return fixmul2(sx, sy, sr, rp, ra);
	n = 31;
	k = fround(1/alpha, n, &a);
	m = n-k;
	if(m < -n-1)
		return IMOVW;	/* result is zero whatever the values */
	v = 0;
	W = 0;
	eps = D(1<<m)/(alpha*D(a)) - 1;
	if(eps < 0){
		v = a-1;
		eps = -eps;
	}
	if(m < 0 && D(1<<n)*eps*D(a) >= D(a)-1+D(1<<m))
		W = (V(1)<<(-m)) - 1;
	if(v != 0 || W != 0)
		m = m<<2|(v != 0)<<1|(W != 0);
	*rp = m;
	*ra = a;
	return v == 0 && W == 0 ? IMULX0: IMULX1;
}

static int
fixdiv(double sx, double sy, double sr, int *rp, int *ra)
{
	int k, m, n, b, v;
	vlong W;
	double beta, eps;

	beta = sx/(sy*sr);
	if(ispow2(beta))
		return fixdiv2(sx, sy, sr, rp, ra);
	n = 31;
	k = fround(beta, n, &b);
	m = k-n;
	if(m <= -2*n)
		return IMOVW;	/* result is zero whatever the values */
	v = 0;
	W = 0;
	eps = (D(1<<m)*D(b))/beta - 1;
	if(eps < 0)
		v = 1;
	if(m < 0)
		W = (V(1)<<(-m)) - 1;
	if(v != 0 || W != 0)
		m = m<<2|(v != 0)<<1|(W != 0);
	*rp = m;
	*ra = b;
	return v == 0 && W == 0 ? IDIVX0: IDIVX1;
}

static int
fixcast(double sx, double sr, int *rp, int *ra)
{
	int op;

	op = fixmul(sx, 1.0, sr, rp, ra);
	return op-IMULX+ICVTXX;
}

int
fixop(int op, Type *tx, Type *ty, Type *tr, int *rp, int *ra)
{
	double sx, sy, sr;

	sx = scale(tx);
	sy = scale(ty);
	sr = scale(tr);
	if(op == IMULX)
		op = fixmul(sx, sy, sr, rp, ra);
	else if(op == IDIVX)
		op = fixdiv(sx, sy, sr, rp, ra);
	else
		op = fixcast(sx, sr, rp, ra);
	return op;
}

int
ispoly(Decl *d)
{
	Type *t;

	if(d == nil)
		return 0;
	t = d->ty;
	if(t->kind == Tfn){
		if(t->polys != nil)
			return 1;
		if((d = d->dot) == nil)
			return 0;
		t = d->ty;
		return t->kind == Tadt && t->polys != nil;
	}
	return 0;
}

int
ispolyadt(Type *t)
{
	return (t->kind == Tadt || t->kind == Tadtpick) && t->polys != nil && !(t->flags & INST);
}

Decl*
polydecl(Decl *ids)
{
	Decl *id;
	Type *t;

	for(id = ids; id != nil; id = id->next){
		t = mktype(&id->src.start, &id->src.stop, Tpoly, nil, nil);
		id->ty = t;
		t->decl = id;
	}
	return ids;
}

/* try to convert an expression tree to a type */
Type*
exptotype(Node *n)
{
	Type *t, *tt;
	Decl *d;
	Typelist *tl;
	Src *src;

	if(n == nil)
		return nil;
	t = nil;
	switch(n->op){
		case Oname:
			if((d = n->decl) != nil && d->store == Dtype)
				t = d->ty;
			break;
		case Otype:
		case Ochan:
			t = n->ty;
			break;
		case Oref:
			t = exptotype(n->left);
			if(t != nil)
				t = mktype(&n->src.start, &n->src.stop, Tref, t, nil);
			break;
		case Odot:
			t = exptotype(n->left);
			if(t != nil){
				d = namedot(t->tags, n->right->decl->sym);
				if(d == nil)
					t = nil;
				else
					t = d->ty;
			}
			if(t == nil)
				t = exptotype(n->right);
			break;
		case Omdot:
			t = exptotype(n->right);
			break;
		case Oindex:
			t = exptotype(n->left);
			if(t != nil){
				src = &n->src;
				tl = nil;
				for(n = n->right; n != nil; n = n->right){
					if(n->op == Oseq)
						tt = exptotype(n->left);
					else
						tt = exptotype(n);
					if(tt == nil)
						return nil;
					tl = addtype(tt, tl);
					if(n->op != Oseq)
						break;
				}
				t = mkinsttype(src, t, tl);
			}
			break;
	}
	return t;
}

static char*
uname(Decl *im)
{
	Decl *p;
	int n;
	char *s;

	n = 0;
	for(p = im; p != nil; p = p->next)
		n += strlen(p->sym->name)+1;
	s = allocmem(n);
	strcpy(s, "");
	for(p = im; p != nil; p = p->next){
		strcat(s, p->sym->name);
		if(p->next != nil)
			strcat(s, "+");
	}
	return s;
}

/* check all implementation modules have consistent declarations 
 * and create their union if needed
 */
Decl*
modimp(Dlist *dl, Decl *im)
{
	Decl *u, *d, *dd, *ids, *dot, *last;
	Sym *s;
	Dlist *dl0;
	long sg, sg0;
	char buf[StrSize], *un;

	if(dl->next == nil)
		return dl->d;
	dl0 = dl;
	sg0 = 0;
	un = uname(im);
	seprint(buf, buf+sizeof(buf), ".m.%s", un);
	installids(Dglobal, mkids(&dl->d->src, enter(buf, 0), tnone, nil));
	u = dupdecl(dl->d);
	u->sym = enter(un, 0);
	u->sym->decl = u;
	u->ty = mktype(&u->src.start, &u->src.stop, Tmodule, nil, nil);
	u->ty->decl = u;
	last = nil;
	for( ; dl != nil; dl = dl->next){
		d = dl->d;
		ids = d->ty->tof->ids;	/* iface */
		if(ids != nil && ids->store == Dglobal)	/* .mp */
			sg = sign(ids);
		else
			sg = 0;
		if(dl == dl0)
			sg0 = sg;
		else if(sg != sg0)
			error(d->src.start, "%s's module data not consistent with that of %s\n", d->sym->name, dl0->d->sym->name);
		for(ids = d->ty->ids; ids != nil; ids = ids->next){
			s = ids->sym;
			if(s->decl != nil && s->decl->scope >= scope){
				if(ids == s->decl){
					dd = dupdecl(ids);
					if(u->ty->ids == nil)
						u->ty->ids = dd;
					else
						last->next = dd;
					last = dd;
					continue;
				}
				dot = s->decl->dot;
				if(s->decl->store != Dwundef && dot != nil && dot != d && isimpmod(dot->sym) && dequal(ids, s->decl, 1))
					ids->refs = s->decl->refs;
				else
					redecl(ids);
				ids->init = s->decl->init;
			}
		}
	}
	u->ty = usetype(u->ty);
	return u;
}

static void
modres(Decl *d)
{
	Decl *ids, *id, *n, *i;
	Type *t;

	for(ids = d->ty->ids; ids != nil; ids = ids->next){
		id = ids->sym->decl;
		if(ids != id){
			n = ids->next;
			i = ids->iface;
			t = ids->ty;
			*ids = *id;
			ids->next = n;
			ids->iface = i;
			ids->ty = t;
		}
	}
}

/* update the fields of duplicate declarations in other implementation modules
 * and their union
 */	
void
modresolve(void)
{
	Dlist *dl;

	dl = impdecls;
	if(dl->next == nil)
		return;
	for( ; dl != nil; dl = dl->next)
		modres(dl->d);
	modres(impdecl);
}
