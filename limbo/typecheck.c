#include "limbo.h"
#include "y.tab.h"

Node	**labstack;
int	labdep;
static Node* inexcept;
static Decl* fndec;

void checkraises(Node *n);

static void
increfs(Decl *id)
{
	for( ; id != nil; id = id->link)
		id->refs++;
}

static int
fninline(Decl *d)
{
	Node *n, *left, *right;

	left = right = nil;
	n = d->init;
	if(dontinline || d->caninline < 0 || d->locals != nil || ispoly(d) || n->ty->tof->kind == Tnone || nodes(n) >= 100)
		return 0;
	n = n->right;
	if(n->op == Oseq && n->right == nil)
		n = n->left;
	/* 
	  *	inline
	  *		(a) return e;
	  *		(b) if(c) return e1; else return e2;
	  *		(c) if(c) return e1; return e2;
	  */
	switch(n->op){
	case Oret:
		break;
	case Oif:
		right = n->right;
		if(right->right == nil || right->left->op != Oret || right->right->op != Oret || !tequal(right->left->left->ty, right->right->left->ty))
			return 0;
		break;
	case Oseq:
		left = n->left;
		right = n->right;
		if(left->op != Oif || left->right->right != nil || left->right->left->op != Oret || right->op != Oseq || right->right != nil || right->left->op != Oret || !tequal(left->right->left->left->ty, right->left->left->ty))
			return 0;
		break;
	default:
		return 0;
	}
	if(occurs(d, n) || hasasgns(n))
		return 0;
	if(n->op == Oseq){
		left->right->right = right->left;
		n = left;
		right = n->right;
		d->init->right->right = nil;
	}
	if(n->op == Oif){
		n->ty = right->ty = right->left->left->ty;
		right->left = right->left->left;
		right->right = right->right->left;
		d->init->right->left = mkunary(Oret, n);
	}
	return 1;
}

static int
isfnrefty(Type *t)
{
	return t->kind == Tref && t->tof->kind == Tfn;
}

static int
isfnref(Decl *d)
{
	switch(d->store){
	case Dglobal:
	case Darg:
	case Dlocal:
	case Dfield:
	case Dimport:
		return isfnrefty(d->ty);
	}
	return 0;
}

int
argncompat(Node *n, Decl *f, Node *a)
{
	for(; a != nil; a = a->right){
		if(f == nil){
			nerror(n, "%V: too many function arguments", n->left);
			return 0;
		}
		f = f->next;
	}
	if(f != nil){
		nerror(n, "%V: too few function arguments", n->left);
		return 0;
	}
	return 1;
}

static void
rewind(Node *n)
{
	Node *r, *nn;

	r = n;
	nn = n->left;
	for(n = n->right; n != nil; n = n->right){
		if(n->right == nil){
			r->left = nn;
			r->right = n->left;
		}
		else
			nn = mkbin(Oindex, nn, n->left);
	}
}

static void
ckmod(Node *n, Decl *id)
{
	Type *t;
	Decl *d, *idc;
	Node *mod;

	if(id == nil)
		fatal("can't find function: %n", n);
	idc = nil;
	mod = nil;
	if(n->op == Oname){
		idc = id;
		mod = id->eimport;
	}
	else if(n->op == Omdot)
		mod = n->left;
	else if(n->op == Odot){
		idc = id->dot;
		t = n->left->ty;
		if(t->kind == Tref)
			t = t->tof;
		if(t->kind == Tadtpick)
			t = t->decl->dot->ty;
		d = t->decl;
		while(d != nil && d->link != nil)
			d = d->link;
		if(d != nil && d->timport != nil)
			mod = d->timport->eimport;
		n->right->left = mod;
	}
	if(mod != nil && mod->ty->kind != Tmodule){
		nerror(n, "cannot use %V as a function reference", n);
		return;
	}
	if(mod != nil){
		if(valistype(mod)){
			nerror(n, "cannot use %V as a function reference because %V is a module interface", n, mod);
			return;
		}
	}else if(idc != nil && idc->dot != nil && !isimpmod(idc->dot->sym)){
		nerror(n, "cannot use %V without importing %s from a variable", n, idc->sym->name);
		return;
	}
	if(mod != nil)
		modrefable(n->ty);
}

static void
addref(Node *n)
{
	Node *nn;

	nn = mkn(0, nil, nil);
	*nn = *n;
	n->op = Oref;
	n->left = nn;
	n->right = nil;
	n->decl = nil;
	n->ty = usetype(mktype(&n->src.start, &n->src.stop, Tref, nn->ty, nil));
}

static void
fnref(Node *n, Decl *id)
{
	id->caninline = -1;
	ckmod(n, id);
	addref(n);
	while(id->link != nil)
		id = id->link;
	if(ispoly(id) && encpolys(id) != nil)
		nerror(n, "cannot have a polymorphic adt function reference %s", id->sym->name);
}

Decl*
typecheck(int checkimp)
{
	Decl *entry, *m, *d;
	Sym *s;
	int i;

	if(errors)
		return nil;

	/*
	 * generate the set of all functions
	 * compile one function at a time
	 */
	gdecl(tree);
	gbind(tree);
	fns = allocmem(nfns * sizeof(Decl));
	i = gcheck(tree, fns, 0);
	if(i != nfns)
		fatal("wrong number of functions found in gcheck");

	maxlabdep = 0;
	for(i = 0; i < nfns; i++){
		d = fns[i];
		if(d != nil)
			fndec = d;
		if(d != nil)
			fncheck(d);
		fndec = nil;
	}

	if(errors)
		return nil;

	entry = nil;
	if(checkimp){
		Decl *im;
		Dlist *dm;

		if(impmods == nil){
			yyerror("no implementation module");
			return nil;
		}
		for(im = impmods; im != nil; im = im->next){
			for(dm = impdecls; dm != nil; dm = dm->next)
				if(dm->d->sym == im->sym)
					break;
			if(dm == nil || dm->d->ty == nil){
				yyerror("no definition for implementation module %s", im->sym->name);
				return nil;
			}
		}
	
		/*
		 * can't check the module spec until all types and imports are determined,
		 * which happens in scheck
		 */
		for(dm = impdecls; dm != nil; dm = dm->next){
			im = dm->d;
			im->refs++;
			im->ty = usetype(im->ty);
			if(im->store != Dtype || im->ty->kind != Tmodule){
				error(im->src.start, "cannot implement %K", im);
				return nil;
			}
		}
	
		/* now check any multiple implementations */
		impdecl = modimp(impdecls, impmods);

		s = enter("init", 0);
		entry = nil;
		for(dm = impdecls; dm != nil; dm = dm->next){
			im = dm->d;
			for(m = im->ty->ids; m != nil; m = m->next){
				m->ty = usetype(m->ty);
				m->refs++;
	
				if(m->sym == s && m->ty->kind == Tfn && entry == nil)
					entry = m;
	
				if(m->store == Dglobal || m->store == Dfn)
					modrefable(m->ty);
	
				if(m->store == Dtype && m->ty->kind == Tadt){
					for(d = m->ty->ids; d != nil; d = d->next){
						d->ty = usetype(d->ty);
						modrefable(d->ty);
						d->refs++;
					}
				}
			}
			checkrefs(im->ty->ids);
		}
	}

	if(errors)
		return nil;
	gsort(tree);
	tree = nil;
	return entry;
}
	
/*
 * introduce all global declarations
 * also adds all fields to adts and modules
 * note the complications due to nested Odas expressions
 */
void
gdecl(Node *n)
{
	for(;;){
		if(n == nil)
			return;
		if(n->op != Oseq)
			break;
		gdecl(n->left);
		n = n->right;
	}
	switch(n->op){
	case Oimport:
		importdecled(n);
		gdasdecl(n->right);
		break;
	case Oadtdecl:
		adtdecled(n);
		break;
	case Ocondecl:
		condecled(n);
		gdasdecl(n->right);
		break;
	case Oexdecl:
		exdecled(n);
		break;
	case Omoddecl:
		moddecled(n);
		break;
	case Otypedecl:
		typedecled(n);
		break;
	case Ovardecl:
		vardecled(n);
		break;
	case Ovardecli:
		vardecled(n->left);
		gdasdecl(n->right);
		break;
	case Ofunc:
		fndecled(n);
		break;
	case Oas:
	case Odas:
	case Onothing:
		gdasdecl(n);
		break;
	default:
		fatal("can't deal with %O in gdecl", n->op);
	}
}

/*
 * bind all global type ids,
 * including those nested inside modules
 * this needs to be done, since we may use such
 * a type later in a nested scope, so if we bound
 * the type ids then, the type could get bound
 * to a nested declaration
 */
void
gbind(Node *n)
{
	Decl *d, *ids;

	for(;;){
		if(n == nil)
			return;
		if(n->op != Oseq)
			break;
		gbind(n->left);
		n = n->right;
	}
	switch(n->op){
	case Oas:
	case Ocondecl:
	case Odas:
	case Oexdecl:
	case Ofunc:
	case Oimport:
	case Onothing:
	case Ovardecl:
	case Ovardecli:
		break;
	case Ofielddecl:
		bindtypes(n->decl->ty);
		break;
	case Otypedecl:
		bindtypes(n->decl->ty);
		if(n->left != nil)
			gbind(n->left);
		break;
	case Opickdecl:
		gbind(n->left);
		d = n->right->left->decl;
		bindtypes(d->ty);
		repushids(d->ty->ids);
		gbind(n->right->right);
		/* get new ids for undefined types; propagate outwards */
		ids = popids(d->ty->ids);
		if(ids != nil)
			installids(Dundef, ids);
		break;
	case Oadtdecl:
	case Omoddecl:
		bindtypes(n->ty);
		if(n->ty->polys != nil)
			repushids(n->ty->polys);
		repushids(n->ty->ids);
		gbind(n->left);
		/* get new ids for undefined types; propagate outwards */
		ids = popids(n->ty->ids);
		if(ids != nil)
			installids(Dundef, ids);
		if(n->ty->polys != nil)
			popids(n->ty->polys);
		break;
	default:
		fatal("can't deal with %O in gbind", n->op);
	}
}

/*
 * check all of the > declarations
 * bind all type ids referred to within types at the global level
 * record decls for defined functions
 */
int
gcheck(Node *n, Decl **fns, int nfns)
{
	Ok rok;
	Decl *d;

	for(;;){
		if(n == nil)
			return nfns;
		if(n->op != Oseq)
			break;
		nfns = gcheck(n->left, fns, nfns);
		n = n->right;
	}

	switch(n->op){
	case Ofielddecl:
		if(n->decl->ty->u.eraises)
			raisescheck(n->decl->ty);
		break;
	case Onothing:
	case Opickdecl:
		break;
	case Otypedecl:
		tcycle(n->ty);
		break;
	case Oadtdecl:
	case Omoddecl:
		if(n->ty->polys != nil)
			repushids(n->ty->polys);
		repushids(n->ty->ids);
		if(gcheck(n->left, nil, 0))
			fatal("gcheck fn decls nested in modules or adts");
		if(popids(n->ty->ids) != nil)
			fatal("gcheck installs new ids in a module or adt");
		if(n->ty->polys != nil)
			popids(n->ty->polys);
		break;
	case Ovardecl:
		varcheck(n, 1);
		break;
	case Ocondecl:
		concheck(n, 1);
		break;
	case Oexdecl:
		excheck(n, 1);
		break;
	case Oimport:
		importcheck(n, 1);
		break;
	case Ovardecli:
		varcheck(n->left, 1);
		rok = echeck(n->right, 0, 1, nil);
		if(rok.ok){
			if(rok.allok)
				n->right = fold(n->right);
			globalas(n->right->left, n->right->right, rok.allok);
		}
		break;
	case Oas:
	case Odas:
		rok = echeck(n, 0, 1, nil);
		if(rok.ok){
			if(rok.allok)
				n = fold(n);
			globalas(n->left, n->right, rok.allok);
		}
		break;
	case Ofunc:
		rok = echeck(n->left, 0, 1, n);
		if(rok.ok && n->ty->u.eraises)
			raisescheck(n->ty);
		d = nil;
		if(rok.ok)
			d = fnchk(n);
		fns[nfns++] = d;
		break;
	default:
		fatal("can't deal with %O in gcheck", n->op);
	}
	return nfns;
}

/*
 * check for unused expression results
 * make sure the any calculated expression has
 * a destination
 */
Node*
checkused(Node *n)
{
	Type *t;
	Node *nn;

	/*
	 * only nil; and nil = nil; should have type tany
	 */
	if(n->ty == tany){
		if(n->op == Oname)
			return n;
		if(n->op == Oas)
			return checkused(n->right);
		fatal("line %L checkused %n", n->src.start, n);
	}

	if(n->op == Ocall && n->left->ty->kind == Tfn && n->left->ty->tof != tnone){
		n = mkunary(Oused, n);
		n->ty = n->left->ty;
		return n;
	}
	if(n->op == Ocall && isfnrefty(n->left->ty)){
		if(n->left->ty->tof->tof != tnone){
			n = mkunary(Oused, n);
			n->ty = n->left->ty;
		}
		return n;
	}
	if(isused[n->op] && (n->op != Ocall || n->left->ty->kind == Tfn))
		return n;
	t = n->ty;
	if(t->kind == Tfn)
		nerror(n, "function %V not called", n);
	else if(t->kind == Tadt && t->tags != nil || t->kind == Tadtpick)
		nerror(n, "expressions cannot have type %T", t);
	else if(n->op == Otuple){
		for(nn = n->left; nn != nil; nn = nn->right)
			checkused(nn->left);
	}
	else
		nwarn(n, "result of expression %V not used", n);
	n = mkunary(Oused, n);
	n->ty = n->left->ty;
	return n;
}

void
fncheck(Decl *d)
{
	Node *n;
	Decl *adtp;

	n = d->init;
	if(debug['t'])
		print("typecheck tree: %n\n", n);

	fndecls = nil;
	adtp = outerpolys(n->left);
	if(n->left->op == Odot)
		repushids(adtp);
	if(d->ty->polys != nil)
		repushids(d->ty->polys);
	repushids(d->ty->ids);

	labdep = 0;
	labstack = allocmem(maxlabdep * sizeof *labstack);
	n->right = scheck(n->right, d->ty->tof, Sother);
	if(labdep != 0)
		fatal("unbalanced label stack in fncheck");
	free(labstack);

	d->locals = appdecls(popids(d->ty->ids), fndecls);
	if(d->ty->polys != nil)
		popids(d->ty->polys);
	if(n->left->op == Odot)
		popids(adtp);
	fndecls = nil;

	checkrefs(d->ty->ids);
	checkrefs(d->ty->polys);
	checkrefs(d->locals);

	checkraises(n);

	d->caninline = fninline(d);
}

Node*
scheck(Node *n, Type *ret, int kind)
{
	Node *left, *right, *last, *top;
	Decl *d;
	Sym *s;
	Ok rok;
	int i;

	top = n;
	last = nil;
	for(; n != nil; n = n->right){
		left = n->left;
		right = n->right;
		switch(n->op){
		case Ovardecl:
			vardecled(n);
			varcheck(n, 0);
			if (nested() && tmustzero(n->decl->ty))
				decltozero(n);
/*
			else if (inloop() && tmustzero(n->decl->ty))
				decltozero(n);
*/
			return top;
		case Ovardecli:
			vardecled(left);
			varcheck(left, 0);
			echeck(right, 0, 0, nil);
			if (nested() && tmustzero(left->decl->ty))
				decltozero(left);
			return top;
		case Otypedecl:
			typedecled(n);
			bindtypes(n->ty);
			tcycle(n->ty);
			return top;
		case Ocondecl:
			condecled(n);
			concheck(n, 0);
			return top;
		case Oexdecl:
			exdecled(n);
			excheck(n, 0);
			return top;
		case Oimport:
			importdecled(n);
			importcheck(n, 0);
			return top;
		case Ofunc:
			fatal("scheck func");
		case Oscope:
			pushscope(n, kind == Sother ? Sscope : kind);
			if (left != nil)
				fatal("Oscope has left field");
			echeck(left, 0, 0, nil);
			n->right = scheck(right, ret, Sother);
			d = popscope();
			fndecls = appdecls(fndecls, d);
			return top;
		case Olabel:
			echeck(left, 0, 0, nil);
			n->right = scheck(right, ret, Sother);
			return top;
		case Oseq:
			n->left = scheck(left, ret, Sother);
			/* next time will check n->right */
			break;
		case Oif:
			rok = echeck(left, 0, 0, nil);
			if(rok.ok && left->op != Onothing && left->ty != tint)
				nerror(n, "if conditional must be an int, not %Q", left);
			right->left = scheck(right->left, ret, Sother);
			/* next time will check n->right->right */
			n = right;
			break;
		case Ofor:
			rok = echeck(left, 0, 0, nil);
			if(rok.ok && left->op != Onothing && left->ty != tint)
				nerror(n, "for conditional must be an int, not %Q", left);
			/*
			 * do the continue clause before the body
			 * this reflects the ordering of declarations
			 */
			pushlabel(n);
			right->right = scheck(right->right, ret, Sother);
			right->left = scheck(right->left, ret, Sloop);
			labdep--;
			if(n->decl != nil && !n->decl->refs)
				nwarn(n, "label %s never referenced", n->decl->sym->name);
			return top;
		case Odo:
			rok = echeck(left, 0, 0, nil);
			if(rok.ok && left->op != Onothing && left->ty != tint)
				nerror(n, "do conditional must be an int, not %Q", left);
			pushlabel(n);
			n->right = scheck(n->right, ret, Sloop);
			labdep--;
			if(n->decl != nil && !n->decl->refs)
				nwarn(n, "label %s never referenced", n->decl->sym->name);
			return top;
		case Oalt:
		case Ocase:
		case Opick:
		case Oexcept:
			pushlabel(n);
			switch(n->op){
			case Oalt:
				altcheck(n, ret);
				break;
			case Ocase:
				casecheck(n, ret);
				break;
			case Opick:
				pickcheck(n, ret);
				break;
			case Oexcept:
				exccheck(n, ret);
				break;
			}
			labdep--;
			if(n->decl != nil && !n->decl->refs)
				nwarn(n, "label %s never referenced", n->decl->sym->name);
			return top;
		case Oret:
			rok = echeck(left, 0, 0, nil);
			if(!rok.ok)
				return top;
			if(left == nil){
				if(ret != tnone)
					nerror(n, "return of nothing from a fn of %T", ret);
			}else if(ret == tnone){
				if(left->ty != tnone)
					nerror(n, "return %Q from a fn with no return type", left);
			}else if(!tcompat(ret, left->ty, 0))
				nerror(n, "return %Q from a fn of %T", left, ret);
			return top;
		case Obreak:
		case Ocont:
			s = nil;
			if(n->decl != nil)
				s = n->decl->sym;
			for(i = 0; i < labdep; i++){
				if(s == nil || labstack[i]->decl != nil && labstack[i]->decl->sym == s){
					if(n->op == Ocont
					&& labstack[i]->op != Ofor && labstack[i]->op != Odo)
						continue;
					if(s != nil)
						labstack[i]->decl->refs++;
					return top;
				}
			}
			nerror(n, "no appropriate target for %V", n);
			return top;
		case Oexit:
		case Onothing:
			return top;
		case Oexstmt:
			fndec->handler = 1;
			n->left = scheck(left, ret, Sother);
			n->right = scheck(right, ret, Sother);
			return top;
		default:
			rok = echeck(n, 0, 0, nil);
			if(rok.allok)
				n = checkused(n);
			if(last == nil)
				return n;
			last->right = n;
			return top;
		}
		last = n;
	}
	return top;
}

void
pushlabel(Node *n)
{
	Sym *s;
	int i;

	if(labdep >= maxlabdep){
		maxlabdep += MaxScope;
		labstack = reallocmem(labstack, maxlabdep * sizeof *labstack);
	}
	if(n->decl != nil){
		s = n->decl->sym;
		n->decl->refs = 0;
		for(i = 0; i < labdep; i++)
			if(labstack[i]->decl != nil && labstack[i]->decl->sym == s)
				nerror(n, "label %s duplicated on line %L", s->name, labstack[i]->decl->src.start);
	}
	labstack[labdep++] = n;
}

void
varcheck(Node *n, int isglobal)
{
	Type *t;
	Decl *ids, *last;

	t = validtype(n->ty, nil);
	t = topvartype(t, n->decl, isglobal, 0);
	last = n->left->decl;
	for(ids = n->decl; ids != last->next; ids = ids->next){
		ids->ty = t;
		shareloc(ids);
	}
	if(t->u.eraises)
		raisescheck(t);
}

void
concheck(Node *n, int isglobal)
{
	Decl *ids, *last;
	Type *t;
	Node *init;
	Ok rok;
	int i;

	pushscope(nil, Sother);
	installids(Dconst, iota);
	rok = echeck(n->right, 0, isglobal, nil);
	popscope();

	init = n->right;
	if(!rok.ok){
		t = terror;
	}else{
		t = init->ty;
		if(!tattr[t->kind].conable){
			nerror(init, "cannot have a %T constant", t);
			rok.allok = 0;
		}
	}

	last = n->left->decl;
	for(ids = n->decl; ids != last->next; ids = ids->next)
		ids->ty = t;

	if(!rok.allok)
		return;

	i = 0;
	for(ids = n->decl; ids != last->next; ids = ids->next){
		if(rok.ok){
			iota->init->val = i;
			ids->init = dupn(0, &nosrc, init);
			if(!varcom(ids))
				rok.ok = 0;
		}
		i++;
	}
}

static char*
exname(Decl *d)
{
	int n;
	Sym *m;
	char *s;
	char buf[16];

	n = 0;
	sprint(buf, "%d", scope-ScopeGlobal);
	m = impmods->sym;
	if(d->dot)
		m = d->dot->sym;
	if(m)
		n += strlen(m->name)+1;
	if(fndec)
		n += strlen(fndec->sym->name)+1;
	n += strlen(buf)+1+strlen(d->sym->name)+1;
	s = malloc(n);
	strcpy(s, "");
	if(m){
		strcat(s, m->name);
		strcat(s, ".");
	}
	if(fndec){
		strcat(s, fndec->sym->name);
		strcat(s, ".");
	}
	strcat(s, buf);
	strcat(s, ".");
	strcat(s, d->sym->name);
	return s;
}

void
excheck(Node *n, int isglobal)
{
	char *nm;
	Type *t;
	Decl *ids, *last;

	t = validtype(n->ty, nil);
	t = topvartype(t, n->decl, isglobal, 0);
	last = n->left->decl;
	for(ids = n->decl; ids != last->next; ids = ids->next){
		ids->ty = t;
		nm = exname(ids);
		ids->init = mksconst(&n->src, enterstring(nm, strlen(nm)));
		/* ids->init = mksconst(&n->src, enterstring(strdup(ids->sym->name), strlen(ids->sym->name))); */
	}
}

void
importcheck(Node *n, int isglobal)
{
	Node *m;
	Decl *id, *last, *v;
	Type *t;
	Ok rok;

	rok = echeck(n->right, 1, isglobal, nil);
	if(!rok.ok)
		return;

	m = n->right;
	if(m->ty->kind != Tmodule || m->op != Oname){
		nerror(n, "cannot import from %Q", m);
		return;
	}

	last = n->left->decl;
	for(id = n->decl; id != last->next; id = id->next){
		v = namedot(m->ty->ids, id->sym);
		if(v == nil){
			error(id->src.start, "%s is not a member of %V", id->sym->name, m);
			id->store = Dwundef;
			continue;
		}
		id->store = v->store;
		v->ty = validtype(v->ty, nil);
		id->ty = t = v->ty;
		if(id->store == Dtype && t->decl != nil){
			id->timport = t->decl->timport;
			t->decl->timport = id;
		}
		id->init = v->init;
		id->importid = v;
		id->eimport = m;
	}
}

static Decl*
rewcall(Node *n, Decl *d)
{
	/* put original function back now we're type checked */
	while(d->link != nil)
		d = d->link;
	if(n->op == Odot)
		n->right->decl = d;
	else if(n->op == Omdot){
		n->right->right->decl = d;
		n->right->right->ty = d->ty;
	}
	else
		fatal("bad op in Ocall rewcall");
	n->ty = n->right->ty = d->ty;
	d->refs++;
	usetype(d->ty);
	return d;
}

/*
 * annotate the expression with types
 */
Ok
echeck(Node *n, int typeok, int isglobal, Node *par)
{
	Type *t, *tt;
	Node *left, *right, *mod, *nn;
	Decl *tg, *id, *callee;
	Sym *s;
	int max, nocheck;
	Ok ok, rok, kidsok;
	static int tagopt;

	ok.ok = ok.allok = 1;
	if(n == nil)
		return ok;
	
	/* avoid deep recursions */
	if(n->op == Oseq){
		for( ; n != nil && n->op == Oseq; n = n->right){
			rok = echeck(n->left, typeok == 2, isglobal, n);
			ok.ok &= rok.ok;
			ok.allok &= rok.allok;
			n->ty = tnone;
		}
		if(n == nil)
			return ok;
	}

	left = n->left;
	right = n->right;

	nocheck = 0;
	if(n->op == Odot || n->op == Omdot || n->op == Ocall || n->op == Oref || n->op == Otagof || n->op == Oindex)
		nocheck = 1;
	if(n->op != Odas		/* special case */
	&& n->op != Oload)		/* can have better error recovery */
		ok = echeck(left, nocheck, isglobal, n);
	if(n->op != Odas		/* special case */
	&& n->op != Odot		/* special check */
	&& n->op != Omdot		/* special check */
	&& n->op != Ocall		/* can have better error recovery */
	&& n->op != Oindex){
		rok = echeck(right, 0, isglobal, n);
		ok.ok &= rok.ok;
		ok.allok &= rok.allok;
	}
	if(!ok.ok){
		n->ty = terror;
		ok.allok = 0;
		return ok;
	}

	switch(n->op){
	case Odas:
		kidsok = echeck(right, 0, isglobal, n);
		if(!kidsok.ok)
			right->ty = terror;
		if(!isglobal && !dasdecl(left)){
			kidsok.ok = 0;
		}else if(!specific(right->ty) || !declasinfer(left, right->ty)){
			nerror(n, "cannot declare %V from %Q", left, right);
			declaserr(left);
			kidsok.ok = 0;
		}
		if(right->ty->kind == Texception)
			left->ty = n->ty = mkextuptype(right->ty);
		else{
			left->ty = n->ty = right->ty;
			usedty(n->ty);
		}
		kidsok.allok &= kidsok.ok;
		if (nested() && tmustzero(left->ty))
			decltozero(left);
		return kidsok;
	case Oseq:
	case Onothing:
		n->ty = tnone;
		break;
	case Owild:
		n->ty = tint;
		break;
	case Ocast:
		t = usetype(n->ty);
		n->ty = t;
		tt = left->ty;
		if(tcompat(t, tt, 0)){
			left->ty = t;
			break;
		}
		if(tt->kind == Tarray){
			if(tt->tof == tbyte && t == tstring)
				break;
		}else if(t->kind == Tarray){
			if(t->tof == tbyte && tt == tstring)
				break;
		}else if(casttab[tt->kind][t->kind]){
			break;
		}
		nerror(n, "cannot make a %T from %Q", n->ty, left);
		ok.ok = ok.allok = 0;
		return ok;
	case Ochan:
		n->ty = usetype(n->ty);
		if(left && left->ty->kind != Tint){
			nerror(n, "channel size %Q is not an int", left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		break;
	case Oload:
		n->ty = usetype(n->ty);
		kidsok = echeck(left, 0, isglobal, n);
		if(n->ty->kind != Tmodule){
			nerror(n, "cannot load a %T, ", n->ty);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(!kidsok.allok){
			ok.allok = 0;
			break;
		}
		if(left->ty != tstring){
			nerror(n, "cannot load a module from %Q", left);
			ok.allok = 0;
			break;
		}
if(n->ty->tof->decl->refs != 0)
n->ty->tof->decl->refs++;
n->ty->decl->refs++;
		usetype(n->ty->tof);
		break;
	case Oref:
		t = left->ty;
		if(t->kind != Tadt && t->kind != Tadtpick && t->kind != Tfn && t->kind != Ttuple){
			nerror(n, "cannot make a ref from %Q", left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(!tagopt && t->kind == Tadt && t->tags != nil && valistype(left)){
			nerror(n, "instances of ref %V must be qualified with a pick tag", left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(t->kind == Tadtpick)
			t->tof = usetype(t->tof);
		n->ty = usetype(mktype(&n->src.start, &n->src.stop, Tref, t, nil));
		break;
	case Oarray:
		max = 0;
		if(right != nil){
			max = assignindices(n);
			if(max < 0){
				ok.ok = ok.allok = 0;
				return ok;
			}
			if(!specific(right->left->ty)){
				nerror(n, "type for array not specific");
				ok.ok = ok.allok = 0;
				return ok;
			}
			n->ty = mktype(&n->src.start, &n->src.stop, Tarray, right->left->ty, nil);
		}
		n->ty = usetype(n->ty);

		if(left->op == Onothing)
			n->left = left = mkconst(&n->left->src, max);

		if(left->ty->kind != Tint){
			nerror(n, "array size %Q is not an int", left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		break;
	case Oelem:
		n->ty = right->ty;
		break;
	case Orange:
		if(left->ty != right->ty
		|| left->ty != tint && left->ty != tstring){
			nerror(left, "range %Q to %Q is not an int or string range", left, right);
			ok.ok = ok.allok = 0;
			return ok;
		}
		n->ty = left->ty;
		break;
	case Oname:
		id = n->decl;
		if(id == nil){
			nerror(n, "name with no declaration");
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(id->store == Dunbound){
			s = id->sym;
			id = s->decl;
			if(id == nil)
				id = undefed(&n->src, s);
			/* save a little space */
			s->unbound = nil;
			n->decl = id;
			id->refs++;
		}
		n->ty = id->ty = usetype(id->ty);
		switch(id->store){
		case Dfn:
		case Dglobal:
		case Darg:
		case Dlocal:
		case Dimport:
		case Dfield:
		case Dtag:
			break;
		case Dundef:
			nerror(n, "%s is not declared", id->sym->name);
			id->store = Dwundef;
			ok.ok = ok.allok = 0;
			return ok;
		case Dwundef:
			ok.ok = ok.allok = 0;
			return ok;
		case Dconst:
			if(id->init == nil){
				nerror(n, "%s's value cannot be determined", id->sym->name);
				id->store = Dwundef;
				ok.ok = ok.allok = 0;
				return ok;
			}
			break;
		case Dtype:
			if(typeok)
				break;
			nerror(n, "%K is not a variable", id);
			ok.ok = ok.allok = 0;
			return ok;
		default:
			fatal("echeck: unknown symbol storage");
		}
		
		if(n->ty == nil){
			nerror(n, "%K's type is not fully defined", id);
			id->store = Dwundef;
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(id->importid != nil && valistype(id->eimport)
		&& id->store != Dconst && id->store != Dtype && id->store != Dfn){
			nerror(n, "cannot use %V because %V is a module interface", n, id->eimport);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(n->ty->kind == Texception && !n->ty->cons && par != nil && par->op != Oraise && par->op != Odot){
			nn = mkn(0, nil, nil);
			*nn = *n;
			n->op = Ocast;
			n->left = nn;
			n->decl = nil;
			n->ty = usetype(mkextuptype(n->ty));
		}
		/* function name as function reference */
		if(id->store == Dfn && (par == nil || (par->op != Odot && par->op != Omdot && par->op != Ocall && par->op != Ofunc)))
			fnref(n, id);
		break;
	case Oconst:
		if(n->ty == nil){
			nerror(n, "no type in %V", n);
			ok.ok = ok.allok = 0;
			return ok;
		}
		break;
	case Oas:
		t = right->ty;
		if(t->kind == Texception)
			t = mkextuptype(t);
		if(!tcompat(left->ty, t, 1)){
			nerror(n, "type clash in %Q = %Q", left, right);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(t == tany)
			t = left->ty;
		n->ty = t;
		left->ty = t;
		if(t->kind == Tadt && t->tags != nil || t->kind == Tadtpick)
		if(left->ty->kind != Tadtpick || right->ty->kind != Tadtpick)
			nerror(n, "expressions cannot have type %T", t);
		if(left->ty->kind == Texception){
			nerror(n, "cannot assign to an exception");
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(islval(left))
			break;
		ok.ok = ok.allok = 0;
		return ok;
	case Osnd:
		if(left->ty->kind != Tchan){
			nerror(n, "cannot send on %Q", left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(!tcompat(left->ty->tof, right->ty, 0)){
			nerror(n, "type clash in %Q <-= %Q", left, right);
			ok.ok = ok.allok = 0;
			return ok;
		}
		t = right->ty;
		if(t == tany)
			t = left->ty->tof;
		n->ty = t;
		break;
	case Orcv:
		t = left->ty;
		if(t->kind == Tarray)
			t = t->tof;
		if(t->kind != Tchan){
			nerror(n, "cannot receive on %Q", left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(left->ty->kind == Tarray)
			n->ty = usetype(mktype(&n->src.start, &n->src.stop, Ttuple, nil,
					mkids(&n->src, nil, tint, mkids(&n->src, nil, t->tof, nil))));
		else
			n->ty = t->tof;
		break;
	case Ocons:
		if(right->ty->kind != Tlist && right->ty != tany){
			nerror(n, "cannot :: to %Q", right);
			ok.ok = ok.allok = 0;
			return ok;
		}
		n->ty = right->ty;
		if(right->ty == tany)
			n->ty = usetype(mktype(&n->src.start, &n->src.stop, Tlist, left->ty, nil));
		else if(!tcompat(right->ty->tof, left->ty, 0)){
			t = tparent(right->ty->tof, left->ty);
			if(!tcompat(t, left->ty, 0)){
				nerror(n, "type clash in %Q :: %Q", left, right);
				ok.ok = ok.allok = 0;
				return ok;
			}
			else
				n->ty = usetype(mktype(&n->src.start, &n->src.stop, Tlist, t, nil));
		}
		break;
	case Ohd:
	case Otl:
		if(left->ty->kind != Tlist || left->ty->tof == nil){
			nerror(n, "cannot %O %Q", n->op, left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(n->op == Ohd)
			n->ty = left->ty->tof;
		else
			n->ty = left->ty;
		break;
	case Otuple:
		n->ty = usetype(mktype(&n->src.start, &n->src.stop, Ttuple, nil, tuplefields(left)));
		break;
	case Ospawn:
		if(left->op != Ocall || left->left->ty->kind != Tfn && !isfnrefty(left->left->ty)){
			nerror(left, "cannot spawn %V", left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(left->ty != tnone){
			nerror(left, "cannot spawn functions which return values, such as %Q", left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		break;
	case Oraise:
		if(left->op == Onothing){
			if(inexcept == nil){
				nerror(n, "%V: empty raise not in exception handler", n);
				ok.ok = ok.allok = 0;
				return ok;
			}
			n->left = dupn(1, &n->src, inexcept);
			break;
		}
		if(left->ty != tstring && left->ty->kind != Texception){
			nerror(n, "%V: raise argument %Q is not a string or exception", n, left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if((left->op != Ocall || left->left->ty->kind == Tfn) && left->ty->ids != nil && left->ty->cons){
			nerror(n, "too few exception arguments");
			ok.ok = ok.allok = 0;
			return ok;
		}
		break;
	case Ocall:{
		int pure;

		kidsok = echeck(right, 0, isglobal, nil);
		t = left->ty;
		usedty(t);
		pure = 1;
		if(t->kind == Tref){
			pure = 0;
			t = t->tof;
		}
		if(t->kind != Tfn)
			return callcast(n, kidsok.allok, ok.allok);
		n->ty = t->tof;
		if(!kidsok.allok){
			ok.allok = 0;
			break;
		}

		/*
		 * get the name to call and any associated module
		 */
		mod = nil;
		callee = nil;
		id = nil;
		tt = nil;
		if(left->op == Odot){
			Decl *dd;
			Type *ttt;

			callee = left->right->decl;
			id = callee->dot;
			right = passimplicit(left, right);
			n->right = right;
			tt = left->left->ty;
			if(tt->kind == Tref)
				tt = tt->tof;
			ttt = tt;
			if(tt->kind == Tadtpick)
				ttt = tt->decl->dot->ty;
			dd = ttt->decl;
			while(dd != nil && dd->link != nil)
				dd = dd->link;
			if(dd != nil && dd->timport != nil)
				mod = dd->timport->eimport;
			/*
			 * stash the import module under a rock,
			 * because we won't be able to get it later
			 * after scopes are popped
			 */
			left->right->left = mod;
		}else if(left->op == Omdot){
			if(left->right->op == Odot){
				callee = left->right->right->decl;
				right = passimplicit(left->right, right);
				n->right = right;
				tt = left->right->left->ty;
				if(tt->kind == Tref)
					tt = tt->tof;
			}else
				callee = left->right->decl;
			mod = left->left;
		}else if(left->op == Oname){
			callee = left->decl;
			id = callee;
			mod = id->eimport;
		}else if(pure){
			nerror(left, "%V is not a function name", left);
			ok.allok = 0;
			break;
		}
		if(pure && callee == nil)
			fatal("can't find called function: %n", left);
		if(callee != nil && callee->store != Dfn && !isfnref(callee)){
			nerror(left, "%V is not a function or function reference", left);
			ok.allok = 0;
			break;
		}
		if(mod != nil && mod->ty->kind != Tmodule){
			nerror(left, "cannot call %V", left);
			ok.allok = 0;
			break;
		}
		if(mod != nil){
			if(valistype(mod)){
				nerror(left, "cannot call %V because %V is a module interface", left, mod);
				ok.allok = 0;
				break;
			}
		}else if(id != nil && id->dot != nil && !isimpmod(id->dot->sym)){
			nerror(left, "cannot call %V without importing %s from a variable", left, id->sym->name);
			ok.allok = 0;
			break;
		}
		if(mod != nil)
			modrefable(left->ty);
		if(callee != nil && callee->store != Dfn)
			callee = nil;
		if(t->varargs != 0){
			t = mkvarargs(left, right);
			if(left->ty->kind == Tref)
				left->ty = usetype(mktype(&t->src.start, &t->src.stop, Tref, t, nil));
			else
				left->ty = t;
		}
		else if(ispoly(callee) || isfnrefty(left->ty) && left->ty->tof->polys != nil){
			Tpair *tp;

			unifysrc = n->src;
			if(!argncompat(n, t->ids, right))
				ok.allok = 0;
			else if(!tunify(left->ty, calltype(left->ty, right, n->ty), &tp)){
				nerror(n, "function call type mismatch");
				ok.allok = 0;
			}
			else{
				n->ty = usetype(expandtype(n->ty, nil, nil, &tp));
				if(ispoly(callee) && tt != nil && (tt->kind == Tadt || tt->kind == Tadtpick) && (tt->flags&INST))
					callee = rewcall(left, callee);
				n->right = passfns(&n->src, callee, left, right, tt, tp);
			}
		}
		else if(!argcompat(n, t->ids, right))
			ok.allok = 0;
		break;
	}
	case Odot:
		t = left->ty;
		if(t->kind == Tref)
			t = t->tof;
		switch(t->kind){
		case Tadt:
		case Tadtpick:
		case Ttuple:
		case Texception:
		case Tpoly:
			id = namedot(t->ids, right->decl->sym);
			if(id == nil){
				id = namedot(t->tags, right->decl->sym);
				if(id != nil && !valistype(left)){
					nerror(n, "%V is not a type", left);
					ok.ok = ok.allok = 0;
					return ok;
				}
			}
			if(id == nil){
				id = namedot(t->polys, right->decl->sym);
				if(id != nil && !valistype(left)){
					nerror(n, "%V is not a type", left);
					ok.ok = ok.allok = 0;
					return ok;
				}
			}
			if(id == nil && t->kind == Tadtpick)
				id = namedot(t->decl->dot->ty->ids, right->decl->sym);
			if(id == nil){
				for(tg = t->tags; tg != nil; tg = tg->next){
					id = namedot(tg->ty->ids, right->decl->sym);
					if(id != nil)
						break;
				}
				if(id != nil){
					nerror(n, "cannot yet index field %s of %Q", right->decl->sym->name, left);
					ok.ok = ok.allok = 0;
					return ok;
				}
			}
			if(id == nil)
				break;
			if(id->store == Dfield && valistype(left)){
				nerror(n, "%V is not a value", left);
				ok.ok = ok.allok = 0;
				return ok;
			}
			id->ty = validtype(id->ty, t->decl);
			id->ty = usetype(id->ty);
			break;
		default:
			nerror(left, "%Q cannot be qualified with .", left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(id == nil){
			nerror(n, "%V is not a member of %Q", right, left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(id->ty == tunknown){
			nerror(n, "illegal forward reference to %V", n);
			ok.ok = ok.allok = 0;
			return ok;
		}

		increfs(id);
		right->decl = id;
		n->ty = id->ty;
		if((id->store == Dconst || id->store == Dtag) && hasside(left, 1))
			nwarn(left, "result of expression %Q ignored", left);
		/* function name as function reference */
		if(id->store == Dfn && (par == nil || (par->op != Omdot && par->op != Ocall && par->op != Ofunc)))
			fnref(n, id);
		break;
	case Omdot:
		t = left->ty;
		if(t->kind != Tmodule){
			nerror(left, "%Q cannot be qualified with ->", left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		id = nil;
		if(right->op == Oname){
			id = namedot(t->ids, right->decl->sym);
		}else if(right->op == Odot){
			kidsok = echeck(right, 0, isglobal, n);
			ok.ok = kidsok.ok;
			ok.allok &= kidsok.allok;
			if(!ok.ok){
				ok.allok = 0;
				return ok;
			}
			tt = right->left->ty;
			if(tt->kind == Tref)
				tt = tt->tof;
			if(right->ty->kind == Tfn
			&& tt->kind == Tadt
			&& tt->decl->dot == t->decl)
				id = right->right->decl;
		}
		if(id == nil){
			nerror(n, "%V is not a member of %Q", right, left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(id->store != Dconst && id->store != Dtype && id->store != Dtag){
			if(valistype(left)){
				nerror(n, "%V is not a value", left);
				ok.ok = ok.allok = 0;
				return ok;
			}
		}else if(hasside(left, 1))
			nwarn(left, "result of expression %Q ignored", left);
		if(!typeok && id->store == Dtype){
			nerror(n, "%V is a type, not a value", n);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(id->ty == tunknown){
			nerror(n, "illegal forward reference to %V", n);
			ok.ok = ok.allok = 0;
			return ok;
		}
		id->refs++;
		right->decl = id;
		n->ty = id->ty = usetype(id->ty);
		if(id->store == Dglobal)
			modrefable(id->ty);
		/* function name as function reference */
		if(id->store == Dfn && (par == nil || (par->op != Ocall && par->op != Ofunc)))
			fnref(n, id);
		break;
	case Otagof:
		n->ty = tint;
		t = left->ty;
		if(t->kind == Tref)
			t = t->tof;
		id = nil;
		switch(left->op){
		case Oname:
			id = left->decl;
			break;
		case Odot:
			id = left->right->decl;
			break;
		case Omdot:
			if(left->right->op == Odot)
				id = left->right->right->decl;
			break;
		}
		if(id != nil && id->store == Dtag
		|| id != nil && id->store == Dtype && t->kind == Tadt && t->tags != nil)
			n->decl = id;
		else if(t->kind == Tadt && t->tags != nil || t->kind == Tadtpick)
			n->decl = nil;
		else{
			nerror(n, "cannot get the tag value for %Q", left);
			ok.ok = 1;
			ok.allok = 0;
			return ok;
		}
		break;
	case Oind:
		t = left->ty;
		if(t->kind != Tref || (t->tof->kind != Tadt && t->tof->kind != Tadtpick && t->tof->kind != Ttuple)){
			nerror(n, "cannot * %Q", left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		n->ty = t->tof;
		for(tg = t->tof->tags; tg != nil; tg = tg->next)
			tg->ty->tof = usetype(tg->ty->tof);
		break;
	case Oindex:
		if(valistype(left)){
			tagopt = 1;
			kidsok = echeck(right, 2, isglobal, n);
			tagopt = 0;
			if(!kidsok.allok){
				ok.ok = ok.allok = 0;
				return ok;
			}
			if((t = exptotype(n)) == nil){
				nerror(n, "%V is not a type list", right);
				ok.ok = ok.allok = 0;
				return ok;
			}
			if(!typeok){
				nerror(n, "%Q is not a variable", left);
				ok.ok = ok.allok = 0;
				return ok;
			}
			*n = *(n->left);
			n->ty = usetype(t);
			break;
		}
		if(0 && right->op == Oseq){	/* a[e1, e2, ...] */
			/* array creation to do before we allow this */
			rewind(n);
			return echeck(n, typeok, isglobal, par);
		}
		t = left->ty;
		kidsok = echeck(right, 0, isglobal, n);
		if(t->kind != Tarray && t != tstring){
			nerror(n, "cannot index %Q", left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(t == tstring){
			n->op = Oinds;
			n->ty = tint;
		}else{
			n->ty = t->tof;
		}
		if(!kidsok.allok){
			ok.allok = 0;
			break;
		}
		if(right->ty != tint){
			nerror(n, "cannot index %Q with %Q", left, right);
			ok.allok = 0;
			break;
		}
		break;
	case Oslice:
		t = n->ty = left->ty;
		if(t->kind != Tarray && t != tstring){
			nerror(n, "cannot slice %Q with '%v:%v'", left, right->left, right->right);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(right->left->ty != tint && right->left->op != Onothing
		|| right->right->ty != tint && right->right->op != Onothing){
			nerror(n, "cannot slice %Q with '%v:%v'", left, right->left, right->right);
			ok.allok = 0;
			return ok;
		}
		break;
	case Olen:
		t = left->ty;
		n->ty = tint;
		if(t->kind != Tarray && t->kind != Tlist && t != tstring){
			nerror(n, "len requires an array, string or list in %Q", left);
			ok.allok = 0;
			return ok;
		}
		break;
	case Ocomp:
	case Onot:
	case Oneg:
		n->ty = left->ty;
		usedty(n->ty);
		switch(left->ty->kind){
		case Tint:
			return ok;
		case Treal:
		case Tfix:
			if(n->op == Oneg)
				return ok;
			break;
		case Tbig:
		case Tbyte:
			if(n->op == Oneg || n->op == Ocomp)
				return ok;
			break;
		}
		nerror(n, "cannot apply %O to %Q", n->op, left);
		ok.ok = ok.allok = 0;
		return ok;
	case Oinc:
	case Odec:
	case Opreinc:
	case Opredec:
		n->ty = left->ty;
		switch(left->ty->kind){
		case Tint:
		case Tbig:
		case Tbyte:
		case Treal:
			break;
		default:
			nerror(n, "cannot apply %O to %Q", n->op, left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(islval(left))
			break;
		ok.ok = ok.allok = 0;
		return ok;
	case Oadd:
	case Odiv:
	case Omul:
	case Osub:
		if(mathchk(n, 1))
			break;
		ok.ok = ok.allok = 0;
		return ok;
	case Oexp:
	case Oexpas:
		n->ty = left->ty;
		if(n->ty != tint && n->ty != tbig && n->ty != treal){
			nerror(n, "exponend %Q is not int, big or real", left);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(right->ty != tint){
			nerror(n, "exponent %Q is not int", right);
			ok.ok = ok.allok = 0;
			return ok;
		}
		if(n->op == Oexpas && !islval(left)){
			ok.ok = ok.allok = 0;
			return ok;
		}
		break;
/*
		if(mathchk(n, 0)){
			if(n->ty != tint){
				nerror(n, "exponentiation operands not int");
				ok.ok = ok.allok = 0;
				return ok;
			}
			break;
		}
		ok.ok = ok.allok = 0;
		return ok;
*/
	case Olsh:
	case Orsh:
		if(shiftchk(n))
			break;
		ok.ok = ok.allok = 0;
		return ok;
	case Oandand:
	case Ooror:
		if(left->ty != tint){
			nerror(n, "%O's left operand is not an int: %Q", n->op, left);
			ok.allok = 0;
		}
		if(right->ty != tint){
			nerror(n, "%O's right operand is not an int: %Q", n->op, right);
			ok.allok = 0;
		}
		n->ty = tint;
		break;
	case Oand:
	case Omod:
	case Oor:
	case Oxor:
		if(mathchk(n, 0))
			break;
		ok.ok = ok.allok = 0;
		return ok;
	case Oaddas:
	case Odivas:
	case Omulas:
	case Osubas:
		if(mathchk(n, 1) && islval(left))
			break;
		ok.ok = ok.allok = 0;
		return ok;
	case Olshas:
	case Orshas:
		if(shiftchk(n) && islval(left))
			break;
		ok.ok = ok.allok = 0;
		return ok;
	case Oandas:
	case Omodas:
	case Oxoras:
	case Ooras:
		if(mathchk(n, 0) && islval(left))
			break;
		ok.ok = ok.allok = 0;
		return ok;
	case Olt:
	case Oleq:
	case Ogt:
	case Ogeq:
		if(!mathchk(n, 1)){
			ok.ok = ok.allok = 0;
			return ok;
		}
		n->ty = tint;
		break;
	case Oeq:
	case Oneq:
		switch(left->ty->kind){
		case Tint:
		case Tbig:
		case Tbyte:
		case Treal:
		case Tstring:
		case Tref:
		case Tlist:
		case Tarray:
		case Tchan:
		case Tany:
		case Tmodule:
		case Tfix:
		case Tpoly:
			if(!tcompat(left->ty, right->ty, 0) && !tcompat(right->ty, left->ty, 0))
				break;
			t = left->ty;
			if(t == tany)
				t = right->ty;
			if(t == tany)
				t = tint;
			if(left->ty == tany)
				left->ty = t;
			if(right->ty == tany)
				right->ty = t;
			n->ty = tint;
			return ok;
		}
		nerror(n, "cannot compare %Q to %Q", left, right);
		usedty(n->ty);
		ok.ok = ok.allok = 0;
		return ok;
	case Otype:
		if(!typeok){
			nerror(n, "%Q is not a variable", n);
			ok.ok = ok.allok = 0;
			return ok;
		}
		n->ty = usetype(n->ty);
		break;
	default:
		fatal("unknown op in typecheck: %O", n->op);
	}
	usedty(n->ty);
	return ok;
}

/*
 * n is syntactically a call, but n->left is not a fn
 * check if it's the contructor for an adt
 */
Ok
callcast(Node *n, int kidsok, int allok)
{
	Node *left, *right;
	Decl *id;
	Type *t, *tt;
	Ok ok;

	left = n->left;
	right = n->right;
	id = nil;
	switch(left->op){
	case Oname:
		id = left->decl;
		break;
	case Omdot:
		if(left->right->op == Odot)
			id = left->right->right->decl;
		else
			id = left->right->decl;
		break;
	case Odot:
		id = left->right->decl;
		break;
	}
/*
	(chan of int)(nil) looks awkward since both sets of brackets needed
	if(id == nil && right != nil && right->right == nil && (t = exptotype(left)) != nil){
		n->op = Ocast;
		n->left = right->left;
		n->right = nil;
		n->ty = t;
		return echeck(n, 0, 0, nil);
	}
*/
	if(id == nil || (id->store != Dtype && id->store != Dtag && id->ty->kind != Texception)){
		nerror(left, "%V is not a function or type name", left);
		ok.ok = ok.allok = 0;
		return ok;
	}
	if(id->store == Dtag)
		return tagcast(n, left, right, id, kidsok, allok);
	t = left->ty;
	n->ty = t;
	if(!kidsok){
		ok.ok = 1;
		ok.allok = 0;
		return ok;
	}

	if(t->kind == Tref)
		t = t->tof;
	tt = mktype(&n->src.start, &n->src.stop, Ttuple, nil, tuplefields(right));
	if(t->kind == Tadt && tcompat(t, tt, 1)){
		if(right == nil)
			*n = *n->left;
		ok.ok = 1;
		ok.allok = allok;
		return ok;
	}

	/* try an exception with args */
	tt = mktype(&n->src.start, &n->src.stop, Texception, nil, tuplefields(right));
	tt->cons = 1;
	if(t->kind == Texception && t->cons && tcompat(t, tt, 1)){
		if(right == nil)
			*n = *n->left;
		ok.ok = 1;
		ok.allok = allok;
		return ok;
	}

	/* try a cast */
	if(t->kind != Texception && right != nil && right->right == nil){	/* Oseq but single expression */
		right = right->left;
		n->op = Ocast;
		n->left = right;
		n->right = nil;
		n->ty = mkidtype(&n->src, id->sym);
		return echeck(n, 0, 0, nil);
	}

	nerror(left, "cannot make a %V from '(%v)'", left, right);
	ok.ok = ok.allok = 0;
	return ok;
}

Ok
tagcast(Node *n, Node *left, Node *right, Decl *id, int kidsok, int allok)
{
	Type *tt;
	Ok ok;

	left->ty = id->ty;
	if(left->op == Omdot)
		left->right->ty = id->ty;
	n->ty = id->ty;
	if(!kidsok){
		ok.ok = 1;
		ok.allok = 0;
		return ok;
	}
	id->ty->tof = usetype(id->ty->tof);
	if(right != nil)
		right->ty = id->ty->tof;
	tt = mktype(&n->src.start, &n->src.stop, Ttuple, nil, mkids(&nosrc, nil, tint, tuplefields(right)));
	tt->ids->store = Dfield;
	if(tcompat(id->ty->tof, tt, 1)){
		ok.ok = 1;
		ok.allok = allok;
		return ok;
	}

	nerror(left, "cannot make a %V from '(%v)'", left, right);
	ok.ok = ok.allok = 0;
	return ok;
}

int
valistype(Node *n)
{
	switch(n->op){
	case Oname:
		if(n->decl->store == Dtype)
			return 1;
		break;
	case Omdot:
		return valistype(n->right);
	}
	return 0;
}

int
islval(Node *n)
{
	int s;

	s = marklval(n);
	if(s == 1)
		return 1;
	if(s == 0)
		nerror(n, "cannot assign to %V", n);
	else
		circlval(n, n);
	return 0;
}

/*
 * check to see if n is an lval
 * mark the lval name as set
 */
int
marklval(Node *n)
{
	Decl *id;
	Node *nn;
	int s;

	if(n == nil)
		return 0;
	switch(n->op){
	case Oname:
		return storespace[n->decl->store] && n->ty->kind != Texception; /*ZZZZ && n->decl->tagged == nil;*/
	case Odot:
		if(n->right->decl->store != Dfield)
			return 0;
		if(n->right->decl->cycle && !n->right->decl->cyc)
			return -1;
		if(n->left->ty->kind != Tref && marklval(n->left) == 0)
			nwarn(n, "assignment to %Q ignored", n);
		return 1;
	case Omdot:
		if(n->right->decl->store == Dglobal)
			return 1;
		return 0;
	case Oind:
		for(id = n->ty->ids; id != nil; id = id->next)
			if(id->cycle && !id->cyc)
				return -1;
		return 1;
	case Oslice:
		if(n->right->right->op != Onothing || n->ty == tstring)
			return 0;
		return 1;
	case Oinds:
		/*
		 * make sure we don't change a string constant
		 */
		switch(n->left->op){
		case Oconst:
			return 0;
		case Oname:
			return storespace[n->left->decl->store];
		case Odot:
		case Omdot:
			if(n->left->right->decl != nil)
				return storespace[n->left->right->decl->store];
			break;
		}
		return 1;
	case Oindex:
	case Oindx:
		return 1;
	case Otuple:
		for(nn = n->left; nn != nil; nn = nn->right){
			s = marklval(nn->left);
			if(s != 1)
				return s;
		}
		return 1;
	default:
		return 0;
	}
	return 0;
}

/*
 * n has a circular field assignment.
 * find it and print an error message.
 */
int
circlval(Node *n, Node *lval)
{
	Decl *id;
	Node *nn;
	int s;

	if(n == nil)
		return 0;
	switch(n->op){
	case Oname:
		break;
	case Odot:
		if(n->right->decl->cycle && !n->right->decl->cyc){
			nerror(lval, "cannot assign to %V because field '%s' of %V could complete a cycle to %V",
				lval, n->right->decl->sym->name, n->left, n->left);
			return -1;
		}
		return 1;
	case Oind:
		for(id = n->ty->ids; id != nil; id = id->next){
			if(id->cycle && !id->cyc){
				nerror(lval, "cannot assign to %V because field '%s' of %V could complete a cycle to %V",
					lval, id->sym->name, n, n);
				return -1;
			}
		}
		return 1;
	case Oslice:
		if(n->right->right->op != Onothing || n->ty == tstring)
			return 0;
		return 1;
	case Oindex:
	case Oinds:
	case Oindx:
		return 1;
	case Otuple:
		for(nn = n->left; nn != nil; nn = nn->right){
			s = circlval(nn->left, lval);
			if(s != 1)
				return s;
		}
		return 1;
	default:
		return 0;
	}
	return 0;
}

int
mathchk(Node *n, int realok)
{
	Type *tr, *tl;

	tl = n->left->ty;
	tr = n->right->ty;
	if(tr != tl && !tequal(tl, tr)){
		nerror(n, "type clash in %Q %O %Q", n->left, n->op, n->right);
		return 0;
	}
	n->ty = tr;
	switch(tr->kind){
	case Tint:
	case Tbig:
	case Tbyte:
		return 1;
	case Tstring:
		switch(n->op){
		case Oadd:
		case Oaddas:
		case Ogt:
		case Ogeq:
		case Olt:
		case Oleq:
			return 1;
		}
		break;
	case Treal:
	case Tfix:
		if(realok)
			return 1;
		break;
	}
	nerror(n, "cannot %O %Q and %Q", n->op, n->left, n->right);
	return 0;
}

int
shiftchk(Node *n)
{
	Node *left, *right;

	right = n->right;
	left = n->left;
	n->ty = left->ty;
	switch(n->ty->kind){
	case Tint:
	case Tbyte:
	case Tbig:
		if(right->ty->kind != Tint){
			nerror(n, "shift %Q is not an int", right);
			return 0;
		}
		return 1;
	}
	nerror(n, "cannot %Q %O %Q", left, n->op, right);
	return 0;
}

/*
 * check for any tany's in t
 */
int
specific(Type *t)
{
	Decl *d;

	if(t == nil)
		return 0;
	switch(t->kind){
	case Terror:
	case Tnone:
	case Tint:
	case Tbig:
	case Tstring:
	case Tbyte:
	case Treal:
	case Tfn:
	case Tadt:
	case Tadtpick:
	case Tmodule:
	case Tfix:
		return 1;
	case Tany:
		return 0;
	case Tpoly:
		return 1;
	case Tref:
	case Tlist:
	case Tarray:
	case Tchan:
		return specific(t->tof);
	case Ttuple:
	case Texception:
		for(d = t->ids; d != nil; d = d->next)
			if(!specific(d->ty))
				return 0;
		return 1;
	}
	fatal("unknown type %T in specific", t);
	return 0;
}

/*
 * infer the type of all variable in n from t
 * n is the left-hand exp of a := exp
 */
int
declasinfer(Node *n, Type *t)
{
	Decl *ids;
	int ok;

	if(t->kind == Texception){
		if(t->cons)
			return 0;
		t = mkextuptype(t);
	}
	switch(n->op){
	case Otuple:
		if(t->kind != Ttuple && t->kind != Tadt && t->kind != Tadtpick)
			return 0;
		ok = 1;
		n->ty = t;
		n = n->left;
		ids = t->ids;
		if(t->kind == Tadtpick)
			ids = t->tof->ids->next;
		for(; n != nil && ids != nil; ids = ids->next){
			if(ids->store != Dfield)
				continue;
			ok &= declasinfer(n->left, ids->ty);
			n = n->right;
		}
		for(; ids != nil; ids = ids->next)
			if(ids->store == Dfield)
				break;
		if(n != nil || ids != nil)
			return 0;
		return ok;
	case Oname:
		topvartype(t, n->decl, 0, 0);
		if(n->decl == nildecl)
			return 1;
		n->decl->ty = t;
		n->ty = t;
		shareloc(n->decl);
		return 1;
	}
	fatal("unknown op %n in declasinfer", n);
	return 0;
}

/*
 * an error occured in declaring n;
 * set all decl identifiers to Dwundef
 * so further errors are squashed.
 */
void
declaserr(Node *n)
{
	switch(n->op){
	case Otuple:
		for(n = n->left; n != nil; n = n->right)
			declaserr(n->left);
		return;
	case Oname:
		if(n->decl != nildecl)
			n->decl->store = Dwundef;
		return;
	}
	fatal("unknown op %n in declaserr", n);
}

int
argcompat(Node *n, Decl *f, Node *a)
{
	for(; a != nil; a = a->right){
		if(f == nil){
			nerror(n, "%V: too many function arguments", n->left);
			return 0;
		}
		if(!tcompat(f->ty, a->left->ty, 0)){
			nerror(n, "%V: argument type mismatch: expected %T saw %Q",
				n->left, f->ty, a->left);
			return 0;
		}
		if(a->left->ty == tany)
			a->left->ty = f->ty;
		f = f->next;
	}
	if(f != nil){
		nerror(n, "%V: too few function arguments", n->left);
		return 0;
	}
	return 1;
}

/*
 * fn is Odot(adt, methid)
 * pass adt implicitly if needed
 * if not, any side effect of adt will be ingored
 */
Node*
passimplicit(Node *fn, Node *args)
{
	Node *n;
	Type *t;

	t = fn->ty;
	if(t->ids == nil || !t->ids->implicit){
		if(hasside(fn->left, 1))
			nwarn(fn, "result of expression %V ignored", fn->left);
		return args;
	}
	n = fn->left;
	if(n->op == Oname && n->decl->store == Dtype){
		nerror(n, "%V is a type and cannot be a self argument", n);
		n = mkn(Onothing, nil, nil);
		n->src = fn->src;
		n->ty = t->ids->ty;
	}
	args = mkn(Oseq, n, args);
	args->src = n->src;
	return args;
}

static int
mem(Type *t, Decl *d)
{
	for( ; d != nil; d = d->next)
		if(d->ty == t)	/* was if(d->ty == t || tequal(d->ty, t)) */
			return 1;
	return 0;
}

static int
memp(Type *t, Decl *f)
{
	return mem(t, f->ty->polys) || mem(t, encpolys(f));
}

static void
passfns0(Src *src, Decl *fn, Node *args0, Node **args, Node **a, Tpair *tp, Decl *polys)
{
	Decl *id, *idt, *idf, *dot;
	Type *tt;
	Sym *sym;
	Node *n, *na, *mod;
	Tpair *p;

if(debug['w']){
	print("polys: ");
	for(id=polys; id!=nil; id=id->next) print("%s ", id->sym->name);
	print("\nmap: ");
	for(p=tp; p!=nil; p=p->nxt) print("%T -> %T ", p->t1, p->t2);
	print("\n");
}
	for(idt = polys; idt != nil; idt = idt->next){
		tt = valtmap(idt->ty, tp);
		if(tt->kind == Tpoly && fndec != nil && !memp(tt, fndec))
			error(src->start, "cannot determine the instantiated type of %T", tt);
		for(idf = idt->ty->ids; idf != nil; idf = idf->next){
			sym = idf->sym;
			id = fnlookup(sym, tt, &mod);
			while(id != nil && id->link != nil)
				id = id->link;
if(debug['v']) print("fnlookup: %p\n", id);
			if(id == nil)	/* error flagged already */
				continue;
			id->refs++;
			id->caninline = -1;
			if(tt->kind == Tmodule){	/* mod an actual parameter */
				for(;;){
					if(args0 != nil && tequal(tt, args0->left->ty)){
						mod = args0->left;
						break;
					}
					if(args0 != nil)
						args0 = args0->right;
				}
			}
			if(mod == nil && (dot = module(id)) != nil && !isimpmod(dot->sym))
				error(src->start, "cannot use %s without importing %s from a variable", id->sym->name, id->dot->sym->name);

if(debug['U']) print("fp: %s %s %s\n", fn->sym->name, mod ? mod->decl->sym->name : "nil", id->sym->name);
			n = mkn(Ofnptr, mod, mkdeclname(src, id));
			n->src = *src;
			n->decl = fn;
			if(tt->kind == Tpoly)
				n->flags = FNPTRA;
			else
				n->flags = 0;
			na = mkn(Oseq, n, nil);
			if(*a == nil)
				*args = na;
			else
				(*a)->right = na;
			
			n = mkn(Ofnptr, mod, mkdeclname(src, id));
			n->src = *src;
			n->decl = fn;
			if(tt->kind == Tpoly)
				n->flags = FNPTRA|FNPTR2;
			else
				n->flags = FNPTR2;
			*a = na->right = mkn(Oseq, n, nil);
		}
		if(args0 != nil)
			args0 = args0->right;
	}
}

Node*
passfns(Src *src, Decl *fn, Node *left, Node *args, Type *adt, Tpair *tp)
{
	Node *a, *args0;

	a = nil;
	args0 = args;
	if(args != nil)
		for(a = args; a->right != nil; a = a->right)
			;
	passfns0(src, fn, args0, &args, &a, tp, ispoly(fn) ? fn->ty->polys : left->ty->tof->polys);
	if(adt != nil)
		passfns0(src, fn, args0, &args, &a, adt->u.tmap, ispoly(fn) ? encpolys(fn) : nil);
	return args;	
}

/*
 * check the types for a function with a variable number of arguments
 * last typed argument must be a constant string, and must use the
 * print format for describing arguments.
 */
Type*
mkvarargs(Node *n, Node *args)
{
	Node *s, *a;
	Decl *f, *last, *va;
	Type *nt;

	nt = copytypeids(n->ty);
	n->ty = nt;
	f = n->ty->ids;
	last = nil;
	if(f == nil){
		nerror(n, "%V's type is illegal", n);
		return nt;
	}
	s = args;
	for(a = args; a != nil; a = a->right){
		if(f == nil)
			break;
		if(!tcompat(f->ty, a->left->ty, 0)){
			nerror(n, "%V: argument type mismatch: expected %T saw %Q",
				n, f->ty, a->left);
			return nt;
		}
		if(a->left->ty == tany)
			a->left->ty = f->ty;
		last = f;
		f = f->next;
		s = a;
	}
	if(f != nil){
		nerror(n, "%V: too few function arguments", n);
		return nt;
	}

	s->left = fold(s->left);
	s = s->left;
	if(s->ty != tstring || s->op != Oconst){
		nerror(args, "%V: format argument %Q is not a string constant", n, s);
		return nt;
	}
	fmtcheck(n, s, a);
	va = tuplefields(a);
	if(last == nil)
		nt->ids = va;
	else
		last->next = va;
	return nt;
}

/*
 * check that a print style format string matches it's arguments
 */
void
fmtcheck(Node *f, Node *fmtarg, Node *va)
{
	Sym *fmt;
	Rune r;
	char *s, flags[10];
	int i, c, n1, n2, dot, verb, flag, ns, lens, fmtstart;
	Type *ty;

	fmt = fmtarg->decl->sym;
	s = fmt->name;
	lens = fmt->len;
	ns = 0;
	while(ns < lens){
		c = s[ns++];
		if(c != '%')
			continue;

		verb = -1;
		n1 = 0;
		n2 = 0;
		dot = 0;
		flag = 0;
		fmtstart = ns - 1;
		while(ns < lens && verb < 0){
			c = s[ns++];
			switch(c){
			default:
				chartorune(&r, &s[ns-1]);
				nerror(f, "%V: invalid character %C in format '%.*s'", f, r, ns-fmtstart, &s[fmtstart]);
				return;
			case '.':
				if(dot){
					nerror(f, "%V: invalid format '%.*s'", f, ns-fmtstart, &s[fmtstart]);
					return;
				}
				n1 = 1;
				dot = 1;
				continue;
			case '*':
				if(!n1)
					n1 = 1;
				else if(!n2 && dot)
					n2 = 1;
				else{
					nerror(f, "%V: invalid format '%.*s'", f, ns-fmtstart, &s[fmtstart]);
					return;
				}
				if(va == nil){
					nerror(f, "%V: too few arguments for format '%.*s'",
						f, ns-fmtstart, &s[fmtstart]);
					return;
				}
				if(va->left->ty->kind != Tint){
					nerror(f, "%V: format '%.*s' incompatible with argument %Q",
						f, ns-fmtstart, &s[fmtstart], va->left);
					return;
				}
				va = va->right;
				break;
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7': case '8': case '9':
				while(ns < lens && s[ns] >= '0' && s[ns] <= '9')
					ns++;
				if(!n1)
					n1 = 1;
				else if(!n2 && dot)
					n2 = 1;
				else{
					nerror(f, "%V: invalid format '%.*s'", f, ns-fmtstart, &s[fmtstart]);
					return;
				}
				break;
			case '+':
			case '-':
			case '#':
			case ',':
			case 'b':
			case 'u':
				for(i = 0; i < flag; i++){
					if(flags[i] == c){
						nerror(f, "%V: duplicate flag %c in format '%.*s'",
							f, c, ns-fmtstart, &s[fmtstart]);
						return;
					}
				}
				flags[flag++] = c;
				if(flag >= sizeof flags){
					nerror(f, "too many flags in format '%.*s'", ns-fmtstart, &s[fmtstart]);
					return;
				}
				break;
			case '%':
			case 'r':
				verb = Tnone;
				break;
			case 'H':
				verb = Tany;
				break;
			case 'c':
				verb = Tint;
				break;
			case 'd':
			case 'o':
			case 'x':
			case 'X':
				verb = Tint;
				for(i = 0; i < flag; i++){
					if(flags[i] == 'b'){
						verb = Tbig;
						break;
					}
				}
				break;
			case 'e':
			case 'f':
			case 'g':
			case 'E':
			case 'G':
				verb = Treal;
				break;
			case 's':
			case 'q':
				verb = Tstring;
				break;
			}
		}
		if(verb != Tnone){
			if(verb < 0){
				nerror(f, "%V: incomplete format '%.*s'", f, ns-fmtstart, &s[fmtstart]);
				return;
			}
			if(va == nil){
				nerror(f, "%V: too few arguments for format '%.*s'", f, ns-fmtstart, &s[fmtstart]);
				return;
			}
			ty = va->left->ty;
			if(ty->kind == Texception)
				ty = mkextuptype(ty);
			switch(verb){
			case Tint:
				switch(ty->kind){
				case Tstring:
				case Tarray:
				case Tref:
				case Tchan:
				case Tlist:
				case Tmodule:
					if(c == 'x' || c == 'X')
						verb = ty->kind;
					break;
				}
				break;
			case Tany:
				if(tattr[ty->kind].isptr)
					verb = ty->kind;
				break;
			}
			if(verb != ty->kind){
				nerror(f, "%V: format '%.*s' incompatible with argument %Q", f, ns-fmtstart, &s[fmtstart], va->left);
				return;
			}
			va = va->right;
		}
	}
	if(va != nil)
		nerror(f, "%V: more arguments than formats", f);
}

Decl*
tuplefields(Node *n)
{
	Decl *d, *h, **last;

	h = nil;
	last = &h;
	for(; n != nil; n = n->right){
		d = mkdecl(&n->left->src, Dfield, n->left->ty);
		*last = d;
		last = &d->next;
	}
	return h;
}

/*
 * make explicit indices for every element in an array initializer
 * return the maximum index
 * sort the indices and check for duplicates
 */
int
assignindices(Node *ar)
{
	Node *wild, *off, *size, *inits, *n, *q;
	Type *t;
	Case *c;
	int amax, max, last, nlab, ok;

	amax = 0x7fffffff;
	size = dupn(0, &nosrc, ar->left);
	if(size->ty == tint){
		size = fold(size);
		if(size->op == Oconst)
			amax = size->val;
	}

	inits = ar->right;
	max = -1;
	last = -1;
	t = inits->left->ty;
	wild = nil;
	nlab = 0;
	ok = 1;
	for(n = inits; n != nil; n = n->right){
		if(!tcompat(t,  n->left->ty, 0)){
			t = tparent(t, n->left->ty);
			if(!tcompat(t, n->left->ty, 0)){
				nerror(n->left, "inconsistent types %T and %T and in array initializer", t, n->left->ty);
				return -1;
			}
			else
				inits->left->ty = t;
		}
		if(t == tany)
			t = n->left->ty;

		/*
		 * make up an index if there isn't one
		 */
		if(n->left->left == nil)
			n->left->left = mkn(Oseq, mkconst(&n->left->right->src, last + 1), nil);

		for(q = n->left->left; q != nil; q = q->right){
			off = q->left;
			if(off->ty != tint){
				nerror(off, "array index %Q is not an int", off);
				ok = 0;
				continue;
			}
			off = fold(off);
			switch(off->op){
			case Owild:
				if(wild != nil)
					nerror(off, "array index * duplicated on line %L", wild->src.start);
				wild = off;
				continue;
			case Orange:
				if(off->left->op != Oconst || off->right->op != Oconst){
					nerror(off, "range %V is not constant", off);
					off = nil;
				}else if(off->left->val < 0 || off->right->val >= amax){
					nerror(off, "array index %V out of bounds", off);
					off = nil;
				}else
					last = off->right->val;
				break;
			case Oconst:
				last = off->val;
				if(off->val < 0 || off->val >= amax){
					nerror(off, "array index %V out of bounds", off);
					off = nil;
				}
				break;
			case Onothing:
				/* get here from a syntax error */
				off = nil;
				break;
			default:
				nerror(off, "array index %V is not constant", off);
				off = nil;
				break;
			}

			nlab++;
			if(off == nil){
				off = mkconst(&n->left->right->src, last);
				ok = 0;
			}
			if(last > max)
				max = last;
			q->left = off;
		}
	}

	/*
	 * fix up types of nil elements
	 */
	for(n = inits; n != nil; n = n->right)
		if(n->left->ty == tany)
			n->left->ty = t;

	if(!ok)
		return -1;


	c = checklabels(inits, tint, nlab, "array index");
	t = mktype(&inits->src.start, &inits->src.stop, Tainit, nil, nil);
	inits->ty = t;
	t->cse = c;

	return max + 1;
}

/*
 * check the labels of a case statment
 */
void
casecheck(Node *cn, Type *ret)
{
	Node *n, *q, *wild, *left, *arg;
	Type *t;
	Case *c;
	Ok rok;
	int nlab, ok, op;

	rok = echeck(cn->left, 0, 0, nil);
	cn->right = scheck(cn->right, ret, Sother);
	if(!rok.ok)
		return;
	arg = cn->left;

	t = arg->ty;
	if(t != tint && t != tbig && t != tstring){
		nerror(cn, "case argument %Q is not an int or big or string", arg);
		return;
	}

	wild = nil;
	nlab= 0;
	ok = 1;
	for(n = cn->right; n != nil; n = n->right){
		q = n->left->left;
		if(n->left->right->right == nil)
			nwarn(q, "no body for case qualifier %V", q);
		for(; q != nil; q = q->right){
			left = fold(q->left);
			q->left = left;
			switch(left->op){
			case Owild:
				if(wild != nil)
					nerror(left, "case qualifier * duplicated on line %L", wild->src.start);
				wild = left;
				break;
			case Orange:
				if(left->ty != t)
					nerror(left, "case qualifier %Q clashes with %Q", left, arg);
				else if(left->left->op != Oconst || left->right->op != Oconst){
					nerror(left, "case range %V is not constant", left);
					ok = 0;
				}
				nlab++;
				break;
			default:
				if(left->ty != t){
					nerror(left, "case qualifier %Q clashes with %Q", left, arg);
					ok = 0;
				}else if(left->op != Oconst){
					nerror(left, "case qualifier %V is not constant", left);
					ok = 0;
				}
				nlab++;
				break;
			}
		}
	}

	if(!ok)
		return;

	c = checklabels(cn->right, t, nlab, "case qualifier");
	op = Tcase;
	if(t == tbig)
		op = Tcasel;
	else if(t == tstring)
		op = Tcasec;
	t = mktype(&cn->src.start, &cn->src.stop, op, nil, nil);
	cn->ty = t;
	t->cse = c;
}

/*
 * check the labels and bodies of a pick statment
 */
void
pickcheck(Node *n, Type *ret)
{
	Node *w, *arg, *qs, *q, *qt, *left, **tags;
	Decl *id, *d;
	Type *t, *argty;
	Case *c;
	Ok rok;
	int ok, nlab;

	arg = n->left->right;
	rok = echeck(arg, 0, 0, nil);
	if(!rok.allok)
		return;
	t = arg->ty;
	if(t->kind == Tref)
		t = t->tof;
	if(arg->ty->kind != Tref || t->kind != Tadt || t->tags == nil){
		nerror(arg, "pick argument %Q is not a ref adt with pick tags", arg);
		return;
	}
	argty = usetype(mktype(&arg->ty->src.start, &arg->ty->src.stop, Tref, t, nil));

	arg = n->left->left;
	pushscope(nil, Sother);
	dasdecl(arg);
	arg->decl->ty = argty;
	arg->ty = argty;

	tags = allocmem(t->decl->tag * sizeof *tags);
	memset(tags, 0, t->decl->tag * sizeof *tags);
	w = nil;
	ok = 1;
	nlab = 0;
	for(qs = n->right; qs != nil; qs = qs->right){
		qt = nil;
		for(q = qs->left->left; q != nil; q = q->right){
			left = q->left;
			switch(left->op){
			case Owild:
				/* left->ty = tnone; */
				left->ty = t;
				if(w != nil)
					nerror(left, "pick qualifier * duplicated on line %L", w->src.start);
				w = left;
				break;
			case Oname:
				id = namedot(t->tags, left->decl->sym);
				if(id == nil){
					nerror(left, "pick qualifier %V is not a member of %Q", left, arg);
					ok = 0;
					continue;
				}

				left->decl = id;
				left->ty = id->ty;

				if(tags[id->tag] != nil){
					nerror(left, "pick qualifier %V duplicated on line %L",
						left, tags[id->tag]->src.start);
					ok = 0;
				}
				tags[id->tag] = left;
				nlab++;
				break;
			default:
				fatal("pickcheck can't handle %n", q);
				break;
			}

			if(qt == nil)
				qt = left;
			else if(!tequal(qt->ty, left->ty))
				nerror(left, "type clash in pick qualifiers %Q and %Q", qt, left);
		}

		argty->tof = t;
		if(qt != nil)
			argty->tof = qt->ty;
		qs->left->right = scheck(qs->left->right, ret, Sother);
		if(qs->left->right == nil)
			nwarn(qs->left->left, "no body for pick qualifier %V", qs->left->left);
	}
	argty->tof = t;
	for(qs = n->right; qs != nil; qs = qs->right)
		for(q = qs->left->left; q != nil; q = q->right)
			q->left = fold(q->left);

	d = popscope();
	d->refs++;
	if(d->next != nil)
		fatal("pickcheck: installing more than one id");
	fndecls = appdecls(fndecls, d);

	if(!ok)
		return;

	c = checklabels(n->right, tint, nlab, "pick qualifier");
	t = mktype(&n->src.start, &n->src.stop, Tcase, nil, nil);
	n->ty = t;
	t->cse = c;
}

void
exccheck(Node *en, Type *ret)
{
	Decl *ed;
	Node *n, *q, *wild, *left, *oinexcept;
	Type *t, *qt;
	Case *c;
	int nlab, ok;
	Ok rok;
	char buf[32];
	static int nexc;

	pushscope(nil, Sother);
	if(en->left == nil){
		seprint(buf, buf+sizeof(buf), ".ex%d", nexc++);
		en->left = mkdeclname(&en->src, mkids(&en->src, enter(buf, 0), texception, nil));
	}
	oinexcept = inexcept;
	inexcept = en->left;
	dasdecl(en->left);
	en->left->ty = en->left->decl->ty = texception;
	ed = en->left->decl;
	/* en->right = scheck(en->right, ret, Sother); */
	t = tstring;
	wild = nil;
	nlab = 0;
	ok = 1;
	for(n = en->right; n != nil; n = n->right){
		qt = nil;
		for(q = n->left->left; q != nil; q = q->right){
			left = q->left;
			switch(left->op){
			case Owild:
				left->ty = texception;
				if(wild != nil)
					nerror(left, "exception qualifier * duplicated on line %L", wild->src.start);
				wild = left;
				break;
			case Orange:
				left->ty = tnone;
				nerror(left, "exception qualifier %V is illegal", left);
				ok = 0;
				break;
			default:
				rok = echeck(left, 0, 0, nil);
				if(!rok.ok){
					ok = 0;
					break;
				}
				left = q->left = fold(left);
				if(left->ty != t && left->ty->kind != Texception){
					nerror(left, "exception qualifier %Q is not a string or exception", left);
					ok = 0;
				}else if(left->op != Oconst){
					nerror(left, "exception qualifier %V is not constant", left);
					ok = 0;
				}
				else if(left->ty != t)
					left->ty = mkextype(left->ty);
				nlab++;
				break;
			}

			if(qt == nil)
				qt = left->ty;
			else if(!tequal(qt, left->ty))
				qt = texception;
		}

		if(qt != nil)
			ed->ty = qt;
		n->left->right = scheck(n->left->right, ret, Sother);
		if(n->left->right->right == nil)
			nwarn(n->left->left, "no body for exception qualifier %V", n->left->left);
	}
	ed->ty = texception;
	inexcept = oinexcept;
	if(!ok)
		return;
	c = checklabels(en->right, texception, nlab, "exception qualifier");
	t = mktype(&en->src.start, &en->src.stop, Texcept, nil, nil);
	en->ty = t;
	t->cse = c;
	ed = popscope();
	fndecls = appdecls(fndecls, ed);
}

/*
 * check array and case labels for validity
 */
Case *
checklabels(Node *inits, Type *ctype, int nlab, char *title)
{
	Node *n, *p, *q, *wild;
	Label *labs, *aux;
	Case *c;
	char buf[256], buf1[256];
	int i, e;

	labs = allocmem(nlab * sizeof *labs);
	i = 0;
	wild = nil;
	for(n = inits; n != nil; n = n->right){
		for(q = n->left->left; q != nil; q = q->right){
			switch(q->left->op){
			case Oconst:
				labs[i].start = q->left;
				labs[i].stop = q->left;
				labs[i++].node = n->left;
				break;
			case Orange:
				labs[i].start = q->left->left;
				labs[i].stop = q->left->right;
				labs[i++].node = n->left;
				break;
			case Owild:
				wild = n->left;
				break;
			default:
				fatal("bogus index in checklabels");
				break;
			}
		}
	}

	if(i != nlab)
		fatal("bad label count: %d then %d", nlab, i);

	aux = allocmem(nlab * sizeof *aux);
	casesort(ctype, aux, labs, 0, nlab);
	for(i = 0; i < nlab; i++){
		p = labs[i].stop;
		if(casecmp(ctype, labs[i].start, p) > 0)
			nerror(labs[i].start, "unmatchable %s %V", title, labs[i].node);
		for(e = i + 1; e < nlab; e++){
			if(casecmp(ctype, labs[e].start, p) <= 0){
				eprintlist(buf, buf+sizeof(buf), labs[e].node->left, " or ");
				eprintlist(buf1, buf1+sizeof(buf1), labs[e-1].node->left, " or ");
				nerror(labs[e].start,"%s '%s' overlaps with '%s' on line %L",
					title, buf, buf1, p->src.start);
			}

			/*
			 * check for merging case labels
			 */
			if(ctype != tint
			|| labs[e].start->val != p->val+1
			|| labs[e].node != labs[i].node)
				break;
			p = labs[e].stop;
		}
		if(e != i + 1){
			labs[i].stop = p;
			memmove(&labs[i+1], &labs[e], (nlab-e) * sizeof *labs);
			nlab -= e - (i + 1);
		}
	}
	free(aux);

	c = allocmem(sizeof *c);
	c->nlab = nlab;
	c->nsnd = 0;
	c->labs = labs;
	c->wild = wild;

	return c;
}

static int
matchcmp(Node *na, Node *nb)
{
	Sym *a, *b;
	int sa, sb;

	a = na->decl->sym;
	b = nb->decl->sym;
	sa = a->len > 0 && a->name[a->len-1] == '*';
	sb = b->len > 0 && b->name[b->len-1] == '*';
	if(sa){
		if(sb){
			if(a->len == b->len)
				return symcmp(a, b);
			return b->len-a->len;
		}
		else
			return 1;
	}
	else{
		if(sb)
			return -1;
		else{
			if(na->ty == tstring){
				if(nb->ty == tstring)
					return symcmp(a, b);
				else
					return 1;
			}
			else{
				if(nb->ty == tstring)
					return -1;
				else
					return symcmp(a, b);
			}
		}
	}
}

int
casecmp(Type *ty, Node *a, Node *b)
{
	if(ty == tint || ty == tbig){
		if(a->val < b->val)
			return -1;
		if(a->val > b->val)
			return 1;
		return 0;
	}
	if(ty == texception)
		return matchcmp(a, b);
	return symcmp(a->decl->sym, b->decl->sym);
}

void
casesort(Type *t, Label *aux, Label *labs, int start, int stop)
{
	int n, top, mid, base;

	n = stop - start;
	if(n <= 1)
		return;
	top = mid = start + n / 2;

	casesort(t, aux, labs, start, top);
	casesort(t, aux, labs, mid, stop);

	/*
	 * merge together two sorted label arrays, yielding a sorted array
	 */
	n = 0;
	base = start;
	while(base < top && mid < stop){
		if(casecmp(t, labs[base].start, labs[mid].start) <= 0)
			aux[n++] = labs[base++];
		else
			aux[n++] = labs[mid++];
	}
	if(base < top)
		memmove(&aux[n], &labs[base], (top-base) * sizeof *aux);
	else if(mid < stop)
		memmove(&aux[n], &labs[mid], (stop-mid) * sizeof *aux);
	memmove(&labs[start], &aux[0], (stop-start) * sizeof *labs);
}

/*
 * binary search for the label corresponding to a given value
 */
int
findlab(Type *ty, Node *v, Label *labs, int nlab)
{
	int l, r, m;

	if(nlab <= 1)
		return 0;
	l = 1;
	r = nlab - 1;
	while(l <= r){
		m = (r + l) / 2;
		if(casecmp(ty, labs[m].start, v) <= 0)
			l = m + 1;
		else
			r = m - 1;
	}
	m = l - 1;
	if(casecmp(ty, labs[m].start, v) > 0
	|| casecmp(ty, labs[m].stop, v) < 0)
		fatal("findlab out of range");
	return m;
}

void
altcheck(Node *an, Type *ret)
{
	Node *n, *q, *left, *op, *wild;
	Case *c;
	int ok, nsnd, nrcv;

	an->left = scheck(an->left, ret, Sother);

	ok = 1;
	nsnd = 0;
	nrcv = 0;
	wild = nil;
	for(n = an->left; n != nil; n = n->right){
		q = n->left->right->left;
		if(n->left->right->right == nil)
			nwarn(q, "no body for alt guard %V", q);
		for(; q != nil; q = q->right){
			left = q->left;
			switch(left->op){
			case Owild:
				if(wild != nil)
					nerror(left, "alt guard * duplicated on line %L", wild->src.start);
				wild = left;
				break;
			case Orange:
				nerror(left, "alt guard %V is illegal", left);
				ok = 0;
				break;
			default:
				op = hascomm(left);
				if(op == nil){
					nerror(left, "alt guard %V has no communication", left);
					ok = 0;
					break;
				}
				if(op->op == Osnd)
					nsnd++;
				else
					nrcv++;
				break;
			}
		}
	}

	if(!ok)
		return;

	c = allocmem(sizeof *c);
	c->nlab = nsnd + nrcv;
	c->nsnd = nsnd;
	c->wild = wild;

	an->ty = mktalt(c);
}

Node*
hascomm(Node *n)
{
	Node *r;

	if(n == nil)
		return nil;
	if(n->op == Osnd || n->op == Orcv)
		return n;
	r = hascomm(n->left);
	if(r != nil)
		return r;
	return hascomm(n->right);
}

void
raisescheck(Type *t)
{
	Node *n, *nn;
	Ok ok;

	if(t->kind != Tfn)
		return;
	n = t->u.eraises;
	for(nn = n->left; nn != nil; nn = nn->right){
		ok = echeck(nn->left, 0, 0, nil);
		if(ok.ok && nn->left->ty->kind != Texception)
			nerror(n, "%V: illegal raises expression", nn->left);
	}
}

typedef struct Elist Elist;

struct Elist{
	Decl *d;
	Elist *nxt;
};

static Elist*
emerge(Elist *el1, Elist *el2)
{
	int f;
	Elist *el, *nxt;

	for( ; el1 != nil; el1 = nxt){
		f = 0;
		for(el = el2; el != nil; el = el->nxt){
			if(el1->d == el->d){
				f = 1;
				break;
			}
		}
		nxt = el1->nxt;
		if(!f){
			el1->nxt = el2;
			el2 = el1;
		}
	}
	return el2;
}

static Elist*
equals(Node *n)
{
	Node *q, *nn;
	Elist *e, *el;

	el = nil;
	for(q = n->left->left; q != nil; q = q->right){
		nn = q->left;
		if(nn->op == Owild)
			return nil;
		if(nn->ty->kind != Texception)
			continue;
		e = (Elist*)malloc(sizeof(Elist));
		e->d = nn->decl;
		e->nxt = el;
		el = e;
	}
	return el;
}

static int
caught(Decl *d, Node *n)
{
	Node *q, *nn;

	for(n = n->right; n != nil; n = n->right){
		for(q = n->left->left; q != nil; q = q->right){
			nn = q->left;
			if(nn->op == Owild)
				return 1;
			if(nn->ty->kind != Texception)
				continue;
			if(d == nn->decl)
				return 1;
		}
	}
	return 0;
}

static Elist*
raisecheck(Node *n, Elist *ql)
{
	int exc;
	Node *e;
	Elist *el, *nel, *nxt;

	if(n == nil)
		return nil;
	el = nil;
	for(; n != nil; n = n->right){
		switch(n->op){
		case Oscope:
			return raisecheck(n->right, ql);
		case Olabel:
		case Odo:
			return raisecheck(n->right, ql);
		case Oif:
		case Ofor:
			return emerge(raisecheck(n->right->left, ql),
					        raisecheck(n->right->right, ql));
		case Oalt:
		case Ocase:
		case Opick:
		case Oexcept:
			exc = n->op == Oexcept;
			for(n = n->right; n != nil; n = n->right){
				ql = nil;
				if(exc)
					ql = equals(n);
				el = emerge(raisecheck(n->left->right, ql), el);
			}
			return el;
		case Oseq:
			el = emerge(raisecheck(n->left, ql), el);
			break;
		case Oexstmt:
			el = raisecheck(n->left, ql);
			nel = nil;
			for( ; el != nil; el = nxt){
				nxt = el->nxt;
				if(!caught(el->d, n->right)){
					el->nxt = nel;
					nel = el;
				}
			}		
			return emerge(nel, raisecheck(n->right, ql));
		case Oraise:
			e = n->left;
			if(e->ty && e->ty->kind == Texception){
				if(!e->ty->cons)
					return ql;
				if(e->op == Ocall)
					e = e->left;
				if(e->op == Omdot)
					e = e->right;
				if(e->op != Oname)
					fatal("exception %n not a name", e);
				el = (Elist*)malloc(sizeof(Elist));
				el->d = e->decl;
				el->nxt = nil;
				return el;
			}
			return nil;
		default:
			return nil;
		}
	}
	return el;
}

void
checkraises(Node *n)
{
	int f;
	Decl *d;
	Elist *e, *el;
	Node *es, *nn;

	el = raisecheck(n->right, nil);
	es = n->ty->u.eraises;
	if(es != nil){
		for(nn = es->left; nn != nil; nn = nn->right){
			d = nn->left->decl;
			f = 0;
			for(e = el; e != nil; e = e->nxt){
				if(d == e->d){
					f = 1;
					e->d = nil;
					break;
				}
			}
			if(!f)
				nwarn(n, "function %V does not raise %s but declared", n->left, d->sym->name);
		}
	}
	for(e = el; e != nil; e = e->nxt)
		if(e->d != nil)
			nwarn(n, "function %V raises %s but not declared", n->left, e->d->sym->name);
}

/* sort all globals in modules now that we've finished with 'last' pointers
 * and before any code generation
 */
void
gsort(Node *n)
{
	for(;;){
		if(n == nil)
			return;
		if(n->op != Oseq)
			break;
		gsort(n->left);
		n = n->right;
	}
	if(n->op == Omoddecl && n->ty->ok & OKverify){
		n->ty->ids = namesort(n->ty->ids);
		sizeids(n->ty->ids, 0);
	}
}
