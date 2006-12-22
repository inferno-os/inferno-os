#include "limbo.h"

char *storename[Dend]=
{
	/* Dtype */	"type",
	/* Dfn */	"function",
	/* Dglobal */	"global",
	/* Darg */	"argument",
	/* Dlocal */	"local",
	/* Dconst */	"con",
	/* Dfield */	"field",
	/* Dtag */	"pick tag",
	/* Dimport */	"import",
	/* Dunbound */	"unbound",
	/* Dundef */	"undefined",
	/* Dwundef */	"undefined",
};

char *storeart[Dend] =
{
	/* Dtype */	"a ",
	/* Dfn */	"a ",
	/* Dglobal */	"a ",
	/* Darg */	"an ",
	/* Dlocal */	"a ",
	/* Dconst */	"a ",
	/* Dfield */	"a ",
	/* Dtag */	"a",
	/* Dimport */	"an ",
	/* Dunbound */	"",
	/* Dundef */	"",
	/* Dwundef */	"",
};

int storespace[Dend] =
{
	/* Dtype */	0,
	/* Dfn */	0,
	/* Dglobal */	1,
	/* Darg */	1,
	/* Dlocal */	1,
	/* Dconst */	0,
	/* Dfield */	1,
	/* Dtag */	0,
	/* Dimport */	0,
	/* Dunbound */	0,
	/* Dundef */	0,
	/* Dwundef */	0,
};

static	Decl	*scopes[MaxScope];
static	Decl	*tails[MaxScope];
static	Node *scopenode[MaxScope];
static	uchar scopekind[MaxScope];
static	Decl	zdecl;

static	void	freeloc(Decl*);

void
popscopes(void)
{
	Decl *d;
	Dlist *id;

	/*
	 * clear out any decls left in syms
	 */
	while(scope >= ScopeBuiltin){
		for(d = scopes[scope--]; d != nil; d = d->next){
			if(d->sym != nil){
				d->sym->decl = d->old;
				d->old = nil;
			}
		}
	}

	for(id = impdecls; id != nil; id = id->next){
		for(d = id->d->ty->ids; d != nil; d = d->next){
			d->sym->decl = nil;
			d->old = nil;
		}
	}
	impdecls = nil;

	scope = ScopeBuiltin;
	scopes[ScopeBuiltin] = nil;
	tails[ScopeBuiltin] = nil;
}

void
declstart(void)
{
	Decl *d;

	iota = mkids(&nosrc, enter("iota", 0), tint, nil);
	iota->init = mkconst(&nosrc, 0);

	scope = ScopeNils;
	scopes[ScopeNils] = nil;
	tails[ScopeNils] = nil;

	nildecl = mkdecl(&nosrc, Dglobal, tany);
	nildecl->sym = enter("nil", 0);
	installids(Dglobal, nildecl);
	d = mkdecl(&nosrc, Dglobal, tstring);
	d->sym = enter("", 0);
	installids(Dglobal, d);

	scope = ScopeGlobal;
	scopes[ScopeGlobal] = nil;
	tails[ScopeGlobal] = nil;
}

void
redecl(Decl *d)
{
	Decl *old;

	old = d->sym->decl;
	if(old->store == Dwundef)
		return;
	error(d->src.start, "redeclaration of %K, previously declared as %k on line %L",
		d, old, old->src.start);
}

void
checkrefs(Decl *d)
{
	Decl *id, *m;
	long refs;

	for(; d != nil; d = d->next){
		if(d->das)
			d->refs--;
		switch(d->store){
		case Dtype:
			refs = d->refs;
			if(d->ty->kind == Tadt){
				for(id = d->ty->ids; id != nil; id = id->next){
					d->refs += id->refs;
					if(id->store != Dfn)
						continue;
					if(id->init == nil && id->link == nil && d->importid == nil)
						error(d->src.start, "function %s.%s not defined", d->sym->name, id->sym->name);
					if(superwarn && !id->refs && d->importid == nil)
						warn(d->src.start, "function %s.%s not referenced", d->sym->name, id->sym->name);
				}
			}
			if(d->ty->kind == Tmodule){
				for(id = d->ty->ids; id != nil; id = id->next){
					refs += id->refs;
					if(id->iface != nil)
						id->iface->refs += id->refs;
					if(id->store == Dtype){
						for(m = id->ty->ids; m != nil; m = m->next){
							refs += m->refs;
							if(m->iface != nil)
								m->iface->refs += m->refs;
						}
					}
				}
				d->refs = refs;
			}
			if(superwarn && !refs && d->importid == nil)
				warn(d->src.start, "%K not referenced", d);
			break;
		case Dglobal:
			if(!superwarn)
				break;
		case Dlocal:
		case Darg:
			if(!d->refs && d->sym != nil
			&& d->sym->name != nil && d->sym->name[0] != '.')
				warn(d->src.start, "%K not referenced", d);
			break;
		case Dconst:
			if(superwarn && !d->refs && d->sym != nil)
				warn(d->src.start, "%K not referenced", d);
			if(d->ty == tstring && d->init != nil)
				d->init->decl->refs += d->refs;
			break;
		case Dfn:
			if(d->init == nil && d->importid == nil)
				error(d->src.start, "%K not defined", d);
			if(superwarn && !d->refs)
				warn(d->src.start, "%K not referenced", d);
			break;
		case Dimport:
			if(superwarn && !d->refs)
				warn(d->src.start, "%K not referenced", d);
			break;
		}
		if(d->das)
			d->refs++;
	}
}

Node*
vardecl(Decl *ids, Type *t)
{
	Node *n;

	n = mkn(Ovardecl, mkn(Oseq, nil, nil), nil);
	n->decl = ids;
	n->ty = t;
	return n;
}

void
vardecled(Node *n)
{
	Decl *ids, *last;
	Type *t;
	int store;

	store = Dlocal;
	if(scope == ScopeGlobal)
		store = Dglobal;
	if(n->ty->kind == Texception && n->ty->cons){
		store = Dconst;
		fatal("Texception in vardecled");
	}
	ids = n->decl;
	installids(store, ids);
	t = n->ty;
	for(last = ids; ids != nil; ids = ids->next){
		ids->ty = t;
		last = ids;
	}
	n->left->decl = last;
}

Node*
condecl(Decl *ids, Node *init)
{
	Node *n;

	n = mkn(Ocondecl, mkn(Oseq, nil, nil), init);
	n->decl = ids;
	return n;
}

void
condecled(Node *n)
{
	Decl *ids, *last;

	ids = n->decl;
	installids(Dconst, ids);
	for(last = ids; ids != nil; ids = ids->next){
		ids->ty = tunknown;
		last = ids;
	}
	n->left->decl = last;
}

Node*
exdecl(Decl *ids, Decl *tids)
{
	Node *n;
	Type *t;

	t = mktype(&ids->src.start, &ids->src.stop, Texception, nil, tids);
	t->cons = 1;
	n = mkn(Oexdecl, mkn(Oseq, nil, nil), nil);
	n->decl = ids;
	n->ty = t;
	return n;
}

void
exdecled(Node *n)
{
	Decl *ids, *last;
	Type *t;

	ids = n->decl;
	installids(Dconst, ids);
	t = n->ty;
	for(last = ids; ids != nil; ids = ids->next){
		ids->ty = t;
		last = ids;
	}
	n->left->decl = last;
}

Node*
importdecl(Node *m, Decl *ids)
{
	Node *n;

	n = mkn(Oimport, mkn(Oseq, nil, nil), m);
	n->decl = ids;
	return n;
}

void
importdecled(Node *n)
{
	Decl *ids, *last;

	ids = n->decl;
	installids(Dimport, ids);
	for(last = ids; ids != nil; ids = ids->next){
		ids->ty = tunknown;
		last = ids;
	}
	n->left->decl = last;
}

Node*
mkscope(Node *body)
{
	Node *n;

	n = mkn(Oscope, nil, body);
	if(body != nil)
		n->src = body->src;
	return n;
}

Node*
fndecl(Node *n, Type *t, Node *body)
{
	n = mkbin(Ofunc, n, body);
	n->ty = t;
	return n;
}

void
fndecled(Node *n)
{
	Decl *d;
	Node *left;

	left = n->left;
	if(left->op == Oname){
		d = left->decl->sym->decl;
		if(d == nil || d->store == Dimport){
			d = mkids(&left->src, left->decl->sym, n->ty, nil);
			installids(Dfn, d);
		}
		left->decl = d;
		d->refs++;
	}
	if(left->op == Odot)
		pushscope(nil, Sother);
	if(n->ty->polys != nil){
		pushscope(nil, Sother);
		installids(Dtype, n->ty->polys);
	}
	pushscope(nil, Sother);
	installids(Darg, n->ty->ids);
	n->ty->ids = popscope();
	if(n->ty->val != nil)
		mergepolydecs(n->ty);
	if(n->ty->polys != nil)
		n->ty->polys = popscope();
	if(left->op == Odot)
		popscope();
}

/*
 * check the function declaration only
 * the body will be type checked later by fncheck
 */
Decl *
fnchk(Node *n)
{
	int bad;
	Decl *d, *inadt, *adtp;
	Type *t;

	bad = 0;
	d = n->left->decl;
	if(n->left->op == Odot)
		d = n->left->right->decl;
	if(d == nil)
		fatal("decl() fnchk nil");
	n->left->decl = d;
	if(d->store == Dglobal || d->store == Dfield)
		d->store = Dfn;
	if(d->store != Dfn || d->init != nil){
		nerror(n, "redeclaration of function %D, previously declared as %k on line %L",
			d, d, d->src.start);
		if(d->store == Dfn && d->init != nil)
			bad = 1;
	}
	d->init = n;

	t = n->ty;
	inadt = d->dot;
	if(inadt != nil && (inadt->store != Dtype || inadt->ty->kind != Tadt))
		inadt = nil;
	if(n->left->op == Odot){
		pushscope(nil, Sother);
		adtp = outerpolys(n->left);
		if(adtp != nil)
			installids(Dtype, adtp);
		if(!polyequal(adtp, n->decl))
			nerror(n, "adt polymorphic type mismatch");
		n->decl = nil;
	}
	t = validtype(t, inadt);
	if(n->left->op == Odot)
		popscope();
	if(debug['d'])
		print("declare function %D ty %T newty %T\n", d, d->ty, t);
	t = usetype(t);

	if(!polyequal(d->ty->polys, t->polys))
		nerror(n, "function polymorphic type mismatch");
	if(!tcompat(d->ty, t, 0))
		nerror(n, "type mismatch: %D defined as %T declared as %T on line %L",
			d, t, d->ty, d->src.start);
	else if(!raisescompat(d->ty->u.eraises, t->u.eraises))
		nerror(n, "raises mismatch: %D", d);
	if(t->varargs != 0)
		nerror(n, "cannot define functions with a '*' argument, such as %D", d);

	t->u.eraises = d->ty->u.eraises;

	d->ty = t;
	d->offset = idoffsets(t->ids, MaxTemp, IBY2WD);
	d->src = n->src;

	d->locals = nil;

	n->ty = t;

	return bad ? nil: d;
}

Node*
globalas(Node *dst, Node *v, int valok)
{
	Node *tv;

	if(v == nil)
		return nil;
	if(v->op == Oas || v->op == Odas){
		v = globalas(v->left, v->right, valok);
		if(v == nil)
			return nil;
	}else if(valok && !initable(dst, v, 0))
		return nil;
	switch(dst->op){
	case Oname:
		if(dst->decl->init != nil)
			nerror(dst, "duplicate assignment to %V, previously assigned on line %L",
				dst, dst->decl->init->src.start);
		if(valok)
			dst->decl->init = v;
		return v;
	case Otuple:
		if(valok && v->op != Otuple)
			fatal("can't deal with %n in tuple case of globalas", v);
		tv = v->left;
		for(dst = dst->left; dst != nil; dst = dst->right){
			globalas(dst->left, tv->left, valok);
			if(valok)
				tv = tv->right;
		}
		return v;
	}
	fatal("can't deal with %n in globalas", dst);
	return nil;
}

int
needsstore(Decl *d)
{
	if(!d->refs)
		return 0;
	if(d->importid != nil)
		return 0;
	if(storespace[d->store])
		return 1;
	return 0;
}

/*
 * return the list of all referenced storage variables
 */
Decl*
vars(Decl *d)
{
	Decl *v, *n;

	while(d != nil && !needsstore(d))
		d = d->next;
	for(v = d; v != nil; v = v->next){
		while(v->next != nil){
			n = v->next;
			if(needsstore(n))
				break;
			v->next = n->next;
		}
	}
	return d;
}

/*
 * declare variables from the left side of a := statement
 */
static int
recdasdecl(Node *n, int store, int *nid)
{
	Decl *d, *old;
	int ok;

	switch(n->op){
	case Otuple:
		ok = 1;
		for(n = n->left; n != nil; n = n->right)
			ok &= recdasdecl(n->left, store, nid);
		return ok;
	case Oname:
		if(n->decl == nildecl){
			*nid = -1;
			return 1;
		}
		d = mkids(&n->src, n->decl->sym, nil, nil);
		installids(store, d);
		old = d->old;
		if(old != nil
		&& old->store != Dfn
		&& old->store != Dwundef
		&& old->store != Dundef)
			warn(d->src.start,  "redeclaration of %K, previously declared as %k on line %L",
				d, old, old->src.start);
		n->decl = d;
		d->refs++;
		d->das = 1;
		if(*nid >= 0)
			(*nid)++;
		return 1;
	}
	return 0;
}

static int
recmark(Node *n, int nid)
{
	switch(n->op){
	case Otuple:
		for(n = n->left; n != nil; n = n->right)
			nid = recmark(n->left, nid);
		break;
	case Oname:
		n->decl->nid = nid;
		nid = 0;
		break;
	}
	return nid;
}

int
dasdecl(Node *n)
{
	int store, ok, nid;

	nid = 0;
	if(scope == ScopeGlobal)
		store = Dglobal;
	else
		store = Dlocal;

	ok = recdasdecl(n, store, &nid);
	if(!ok)
		nerror(n, "illegal declaration expression %V", n);
	if(ok && store == Dlocal && nid > 1)
		recmark(n, nid);
	return ok;
}

/*
 * declare global variables in nested := expressions
 */
void
gdasdecl(Node *n)
{
	if(n == nil)
		return;

	if(n->op == Odas){
		gdasdecl(n->right);
		dasdecl(n->left);
	}else{
		gdasdecl(n->left);
		gdasdecl(n->right);
	}
}

Decl*
undefed(Src *src, Sym *s)
{
	Decl *d;

	d = mkids(src, s, tnone, nil);
	error(src->start, "%s is not declared", s->name);
	installids(Dwundef, d);
	return d;
}

/*
int
inloop()
{
	int i;

	for (i = scope; i > 0; i--)
		if (scopekind[i] == Sloop)
			return 1;
	return 0;
}
*/

int
nested()
{
	int i;

	for (i = scope; i > 0; i--)
		if (scopekind[i] == Sscope || scopekind[i] == Sloop)
			return 1;
	return 0;
}

void
decltozero(Node *n)
{
	Node *scp;

	if ((scp = scopenode[scope]) != nil) {
		/* can happen if we do
		 *	x[i] := ......
		 * which is an error
		 */
		if (n->right != nil && errors == 0)
			fatal("Ovardecl/Oname/Otuple has right field\n");
		n->right = scp->left;
		scp->left = n;
	}
}

void
pushscope(Node *scp, int kind)
{
	if(scope >= MaxScope)
		fatal("scope too deep");
	scope++;
	scopes[scope] = nil;
	tails[scope] = nil;
	scopenode[scope] = scp;
	scopekind[scope] = kind;
}

Decl*
curscope(void)
{
	return scopes[scope];
}

/*
 * revert to old declarations for each symbol in the currect scope.
 * remove the effects of any imported adt types
 * whenever the adt is imported from a module,
 * we record in the type's decl the module to use
 * when calling members.  the process is reversed here.
 */
Decl*
popscope(void)
{
	Decl *id;
	Type *t;

if (debug['X'])
	print("popscope\n");
	for(id = scopes[scope]; id != nil; id = id->next){
		if(id->sym != nil){
if (debug['X'])
	print("%s : %s %d\n", id->sym->name, kindname[id->ty->kind], id->init != nil ? id->init->op : 0);
			id->sym->decl = id->old;
			id->old = nil;
		}
		if(id->importid != nil)
			id->importid->refs += id->refs;
		t = id->ty;
		if(id->store == Dtype
		&& t->decl != nil
		&& t->decl->timport == id)
			t->decl->timport = id->timport;
		if(id->store == Dlocal)
			freeloc(id);
	}
	return scopes[scope--];
}

/*
 * make a new scope,
 * preinstalled with some previously installed identifiers
 * don't add the identifiers to the scope chain,
 * so they remain separate from any newly installed ids
 *
 * these routines assume no ids are imports
 */
void
repushids(Decl *ids)
{
	Sym *s;

	if(scope >= MaxScope)
		fatal("scope too deep");
	scope++;
	scopes[scope] = nil;
	tails[scope] = nil;
	scopenode[scope] = nil;
	scopekind[scope] = Sother;

	for(; ids != nil; ids = ids->next){
		if(ids->scope != scope
		&& (ids->dot == nil || !isimpmod(ids->dot->sym)
			|| ids->scope != ScopeGlobal || scope != ScopeGlobal + 1))
			fatal("repushids scope mismatch");
		s = ids->sym;
		if(s != nil && ids->store != Dtag){
			if(s->decl != nil && s->decl->scope >= scope)
				ids->old = s->decl->old;
			else
				ids->old = s->decl;
			s->decl = ids;
		}
	}
}

/*
 * pop a scope which was started with repushids
 * return any newly installed ids
 */
Decl*
popids(Decl *ids)
{
	for(; ids != nil; ids = ids->next){
		if(ids->sym != nil && ids->store != Dtag){
			ids->sym->decl = ids->old;
			ids->old = nil;
		}
	}
	return popscope();
}

void
installids(int store, Decl *ids)
{
	Decl *d, *last;
	Sym *s;

	last = nil;
	for(d = ids; d != nil; d = d->next){
		d->scope = scope;
		if(d->store == Dundef)
			d->store = store;
		s = d->sym;
		if(s != nil){
			if(s->decl != nil && s->decl->scope >= scope){
				redecl(d);
				d->old = s->decl->old;
			}else
				d->old = s->decl;
			s->decl = d;
		}
		last = d;
	}
	if(ids != nil){
		d = tails[scope];
		if(d == nil)
			scopes[scope] = ids;
		else
			d->next = ids;
		tails[scope] = last;
	}
}

Decl*
lookup(Sym *sym)
{
	int s;
	Decl *d;

	for(s = scope; s >= ScopeBuiltin; s--){
		for(d = scopes[s]; d != nil; d = d->next){
			if(d->sym == sym)
				return d;
		}
	}
	return nil;
}

Decl*
mkids(Src *src, Sym *s, Type *t, Decl *next)
{
	Decl *d;

	d = mkdecl(src, Dundef, t);
	d->next = next;
	d->sym = s;
	return d;
}

Decl*
mkdecl(Src *src, int store, Type *t)
{
	Decl *d;
	static Decl z;

	d = allocmem(sizeof *d);
	*d = z;
	d->src = *src;
	d->store = store;
	d->ty = t;
	d->nid = 1;
	return d;
}

Decl*
dupdecl(Decl *old)
{
	Decl *d;

	d = allocmem(sizeof *d);
	*d = *old;
	d->next = nil;
	return d;
}

Decl*
dupdecls(Decl *old)
{
	Decl *d, *nd, *first, *last;

	first = last = nil;
	for(d = old; d != nil; d = d->next){
		nd = dupdecl(d);
		if(first == nil)
			first = nd;
		else
			last->next = nd;
		last = nd;
	}
	return first;
}
		
Decl*
appdecls(Decl *d, Decl *dd)
{
	Decl *t;

	if(d == nil)
		return dd;
	for(t = d; t->next != nil; t = t->next)
		;
	t->next = dd;
	return d;
}

Decl*
revids(Decl *id)
{
	Decl *d, *next;

	d = nil;
	for(; id != nil; id = next){
		next = id->next;
		id->next = d;
		d = id;
	}
	return d;
}

long
idoffsets(Decl *id, long offset, int al)
{
	int a, algn;
	Decl *d;

	algn = 1;
	for(; id != nil; id = id->next){
		if(storespace[id->store]){
usedty(id->ty);
			if(id->store == Dlocal && id->link != nil){
				/* id->nid always 1 */
				id->offset = id->link->offset;
				continue;
			}
			a = id->ty->align;
			if(id->nid > 1){
				for(d = id->next; d != nil && d->nid == 0; d = d->next)
					if(d->ty->align > a)
						a = d->ty->align;
				algn = a;
			}
			offset = align(offset, a);
			id->offset = offset;
			offset += id->ty->size;
			if(id->nid == 0 && (id->next == nil || id->next->nid != 0))
				offset = align(offset, algn);
		}
	}
	return align(offset, al);
}

long
idindices(Decl *id)
{
	int i;

	i = 0;
	for(; id != nil; id = id->next){
		if(storespace[id->store]){
			usedty(id->ty);
			id->offset = i++;
		}
	}
	return i;
}

int
declconv(Fmt *f)
{
	Decl *d;
	char buf[4096], *s;

	d = va_arg(f->args, Decl*);
	if(d->sym == nil)
		s = "<???>";
	else
		s = d->sym->name;
	seprint(buf, buf+sizeof(buf), "%s %s", storename[d->store], s);
	return fmtstrcpy(f, buf);
}

int
storeconv(Fmt *f)
{
	Decl *d;
	char buf[4096];

	d = va_arg(f->args, Decl*);
	seprint(buf, buf+sizeof(buf), "%s%s", storeart[d->store], storename[d->store]);
	return fmtstrcpy(f, buf);
}

int
dotconv(Fmt *f)
{
	Decl *d;
	char buf[4096], *p, *s;

	d = va_arg(f->args, Decl*);
	buf[0] = 0;
	p = buf;
	if(d->dot != nil && !isimpmod(d->dot->sym)){
		s = ".";
		if(d->dot->ty != nil && d->dot->ty->kind == Tmodule)
			s = "->";
		p = seprint(buf, buf+sizeof(buf), "%D%s", d->dot, s);
	}
	seprint(p, buf+sizeof(buf), "%s", d->sym->name);
	return fmtstrcpy(f, buf);
}

/*
 * merge together two sorted lists, yielding a sorted list
 */
static Decl*
namemerge(Decl *e, Decl *f)
{
	Decl rock, *d;

	d = &rock;
	while(e != nil && f != nil){
		if(strcmp(e->sym->name, f->sym->name) <= 0){
			d->next = e;
			e = e->next;
		}else{
			d->next = f;
			f = f->next;
		}
		d = d->next;
	}
	if(e != nil)
		d->next = e;
	else
		d->next = f;
	return rock.next;
}

/*
 * recursively split lists and remerge them after they are sorted
 */
static Decl*
recnamesort(Decl *d, int n)
{
	Decl *r, *dd;
	int i, m;

	if(n <= 1)
		return d;
	m = n / 2 - 1;
	dd = d;
	for(i = 0; i < m; i++)
		dd = dd->next;
	r = dd->next;
	dd->next = nil;
	return namemerge(recnamesort(d, n / 2),
			recnamesort(r, (n + 1) / 2));
}

/*
 * sort the ids by name
 */
Decl*
namesort(Decl *d)
{
	Decl *dd;
	int n;

	n = 0;
	for(dd = d; dd != nil; dd = dd->next)
		n++;
	return recnamesort(d, n);
}

void
printdecls(Decl *d)
{
	for(; d != nil; d = d->next)
		print("%ld: %K %T ref %d\n", d->offset, d, d->ty, d->refs);
}

void
mergepolydecs(Type *t)
{
	Node *n, *nn;
	Decl *id, *ids, *ids1;

	for(n = t->val; n != nil; n = n->right){
		nn = n->left;
		for(ids = nn->decl; ids != nil; ids = ids->next){
			id = ids->sym->decl;
			if(id == nil){
				undefed(&ids->src, ids->sym);
				break;
			}
			if(id->store != Dtype){
				error(ids->src.start, "%K is not a type", id);
				break;
			}
			if(id->ty->kind != Tpoly){
				error(ids->src.start, "%K is not a polymorphic type", id);
				break;
			}
			if(id->ty->ids != nil)
				error(ids->src.start, "%K redefined", id);
			pushscope(nil, Sother);
			fielddecled(nn->left);
			id->ty->ids = popscope();
			for(ids1 = id->ty->ids; ids1 != nil; ids1 = ids1->next){
				ids1->dot = id;
				bindtypes(ids1->ty);
				if(ids1->ty->kind != Tfn){
					error(ids1->src.start, "only function types expected");
					id->ty->ids = nil;
				}
			}
		}
	}
	t->val = nil;
}

static void
adjfnptrs(Decl *d, Decl *polys1, Decl *polys2)
{
	int n;
	Decl *id, *idt, *idf, *arg;

	if(debug['U'])
		print("adjnptrs %s\n", d->sym->name);
	n = 0;
	for(id = d->ty->ids; id != nil; id = id->next)
		n++;
	for(idt = polys1; idt != nil; idt = idt->next)
		for(idf = idt->ty->ids; idf != nil; idf = idf->next)
			n -= 2;
	for(idt = polys2; idt != nil; idt = idt->next)
		for(idf = idt->ty->ids; idf != nil; idf = idf->next)
			n -= 2;
	for(arg = d->ty->ids; --n >= 0; arg = arg->next)
		;
	for(idt = polys1; idt != nil; idt = idt->next){
		for(idf = idt->ty->ids; idf != nil; idf = idf->next){
			idf->link = arg;
			arg = arg->next->next;
		}
	}
	for(idt = polys2; idt != nil; idt = idt->next){
		for(idf = idt->ty->ids; idf != nil; idf = idf->next){
			idf->link = arg;
			arg = arg->next->next;
		}
	}
}

static void
addptrs(Decl *polys, Decl** fps, Decl **last, int link, Src *src)
{
	Decl *idt, *idf, *fp;

	if(debug['U'])
		print("addptrs\n");
	for(idt = polys; idt != nil; idt = idt->next){
		for(idf = idt->ty->ids; idf != nil; idf = idf->next){
			fp = mkdecl(src, Darg, tany);
			fp->sym = idf->sym;
			if(link)
				idf->link = fp;
			if(*fps == nil)
				*fps = fp;
			else
				(*last)->next = fp;
			*last = fp;
			fp = mkdecl(src, Darg, tint);
			fp->sym = idf->sym;
			(*last)->next = fp;
			*last = fp;
		}
	}
}

void
addfnptrs(Decl *d, int link)
{
	Decl *fps, *last, *polys;

	if(debug['U'])
		print("addfnptrs %s %d\n", d->sym->name, link);
	polys = encpolys(d);
	if(d->ty->flags&FULLARGS){
		if(link)
			adjfnptrs(d, d->ty->polys, polys);
		if(0 && debug['U']){
			for(d = d->ty->ids; d != nil; d = d->next)
				print("%s=%ld(%d) ", d->sym->name, d->offset, tattr[d->ty->kind].isptr);
			print("\n");
		}
		return;
	}
	d->ty->flags |= FULLARGS;
	fps = last = nil;
	addptrs(d->ty->polys, &fps, &last, link, &d->src);
	addptrs(polys, &fps, &last, link, &d->src);
	for(last = d->ty->ids; last != nil && last->next != nil; last = last->next)
		;
	if(last != nil)
		last->next = fps;
	else
		d->ty->ids = fps;
	d->offset = idoffsets(d->ty->ids, MaxTemp, IBY2WD);
	if(0 && debug['U']){
		for(d = d->ty->ids; d != nil; d = d->next)
			print("%s=%ld(%d) ", d->sym->name, d->offset, tattr[d->ty->kind].isptr);
		print("\n");
	}
}

void
rmfnptrs(Decl *d)
{
	int n;
	Decl *id, *idt, *idf;

	if(debug['U'])
		print("rmfnptrs %s\n", d->sym->name);
	if(!(d->ty->flags&FULLARGS))
		return;
	d->ty->flags &= ~FULLARGS;
	n = 0;
	for(id = d->ty->ids; id != nil; id = id->next)
		n++;
	for(idt = d->ty->polys; idt != nil; idt = idt->next)
		for(idf = idt->ty->ids; idf != nil; idf = idf->next)
			n -= 2;
	for(idt = encpolys(d); idt != nil; idt = idt->next)
		for(idf = idt->ty->ids; idf != nil; idf = idf->next)
			n -= 2;
	if(n == 0){
		d->ty->ids = nil;
		return;
	}
	for(id = d->ty->ids; --n > 0; id = id->next)
		;
	id->next = nil;
	d->offset = idoffsets(d->ty->ids, MaxTemp, IBY2WD);
}

int
local(Decl *d)
{
	for(d = d->dot; d != nil; d = d->dot)
		if(d->store == Dtype && d->ty->kind == Tmodule)
			return 0;
	return 1;
}

Decl*
module(Decl *d)
{
	for(d = d->dot; d != nil; d = d->dot)
		if(d->store == Dtype && d->ty->kind == Tmodule)
			return d;
	return nil;
}

Decl*
outerpolys(Node *n)
{
	Decl *d;

	if(n->op == Odot){
		d = n->right->decl;
		if(d == nil)
			fatal("decl() outeradt nil");
		d = d->dot;
		if(d != nil && d->store == Dtype && d->ty->kind == Tadt)
			return d->ty->polys;
	}
	return nil;
}

Decl*
encpolys(Decl *d)
{
	if((d = d->dot) == nil)
		return nil;
	return d->ty->polys;
}

Decl*
fnlookup(Sym *s, Type *t, Node **m)
{
	Decl *id;
	Node *mod;

	id = nil;
	mod = nil;
	if(t->kind == Tpoly || t->kind == Tmodule)
		id = namedot(t->ids, s);
	else if(t->kind == Tref){
		t = t->tof;
		if(t->kind == Tadt){
			id = namedot(t->ids, s);
			if(t->decl != nil && t->decl->timport != nil)
				mod = t->decl->timport->eimport;
		}
		else if(t->kind == Tadtpick){
			id = namedot(t->ids, s);
			if(t->decl != nil && t->decl->timport != nil)
				mod = t->decl->timport->eimport;
			t = t->decl->dot->ty;
			if(id == nil)
				id = namedot(t->ids, s);
			if(t->decl != nil && t->decl->timport != nil)
				mod = t->decl->timport->eimport;	
		}
	}
	if(id == nil){
		id = lookup(s);
		if(id != nil)
			mod = id->eimport;
	}
	if(m != nil)
		*m = mod;
	return id;
}

int
isimpmod(Sym *s)
{
	Decl *d;

	for(d = impmods; d != nil; d = d->next)
		if(d->sym == s)
			return 1;
	return 0;
}

int
dequal(Decl *d1, Decl *d2, int full)
{
	return	d1->sym == d2->sym &&
			d1->store == d2->store &&
			d1->implicit == d2->implicit &&
			d1->cyc == d2->cyc &&
			(!full || tequal(d1->ty, d2->ty)) &&
			(!full || d1->store == Dfn || sametree(d1->init, d2->init));
}

static int
tzero(Type *t)
{
	return t->kind == Texception || tmustzero(t);
}

static int
isptr(Type *t)
{
	return t->kind == Texception || tattr[t->kind].isptr;
}

/* can d share the same stack location as another local ? */
void
shareloc(Decl *d)
{
	int z;
	Type *t, *tt;
	Decl *dd, *res;

	if(d->store != Dlocal || d->nid != 1)
		return;
	t = d->ty;
	res = nil;
	for(dd = fndecls; dd != nil; dd = dd->next){
		if(d == dd)
			fatal("d==dd in shareloc");
		if(dd->store != Dlocal || dd->nid != 1 || dd->link != nil || dd->tref != 0)
			continue;
		tt = dd->ty;
		if(t->size != tt->size || t->align != tt->align)
			continue;
		z = tzero(t)+tzero(tt);
		if(z > 0)
			continue;	/* for now */
		if(t == tt || tequal(t, tt))
			res = dd;
		else{
			if(z == 1)
				continue;
			if(z == 0 || isptr(t) || isptr(tt) || mktdesc(t) == mktdesc(tt))
				res = dd;
		}
		if(res != nil){
			/* print("%L %K share %L %K\n", d->src.start, d, res->src.start, res); */
			d->link = res;
			res->tref = 1;
			return;
		}
	}
	return;
}

static void
freeloc(Decl *d)
{
	if(d->link != nil)
		d->link->tref = 0;
}
