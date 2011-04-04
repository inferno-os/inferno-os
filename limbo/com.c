#include "limbo.h"

static	Inst	**breaks;
static	Inst	**conts;
static	Decl	**labels;
static	Node **bcscps;
static	int	labdep;
static	Inst	nocont;

static	int scp;
static	Node *scps[MaxScope];

static	int trcom(Node*, Node*, int);

static void
pushscp(Node *n)
{
	if (scp >= MaxScope)
		fatal("scope too deep");
	scps[scp++] = n;
}

static void
popscp(void)
{
	scp--;
}

static Node *
curscp(void)
{
	if (scp == 0)
		return nil;
	return scps[scp-1];
}

static void
zeroscopes(Node *stop)
{
	int i;
	Node *cs;

	for (i = scp-1; i >= 0; i--) {
		cs = scps[i];
		if (cs == stop)
			break;
		zcom(cs->left, nil);
	}
}

static void
zeroallscopes(Node *n, Node **nn)
{
	if(n == nil)
		return;
	for(; n != nil; n = n->right){
		switch(n->op){
		case Oscope:
			zeroallscopes(n->right, nn);
			zcom(n->left, nn);
			return;
		case Olabel:
		case Odo:
			zeroallscopes(n->right, nn);
			return;
		case Oif:
		case Ofor:
			zeroallscopes(n->right->left, nn);
			zeroallscopes(n->right->right, nn);
			return;
		case Oalt:
		case Ocase:
		case Opick:
		case Oexcept:
			for(n = n->right; n != nil; n = n->right)
				zeroallscopes(n->left->right, nn);
			return;
		case Oseq:
			zeroallscopes(n->left, nn);
			break;
		case Oexstmt:
			zeroallscopes(n->left, nn);
			zeroallscopes(n->right, nn);
			return;
		default:
			return;
		}
	}
}

static Except *excs;

static void
installexc(Node *en, Inst *p1, Inst *p2, Node *zn)
{
	int i, ne;
	Except *e;
	Case *c;
	Label *lab;

	e = allocmem(sizeof(Except));
	e->p1 = p1;
	e->p2 = p2;
	e->c = en->ty->cse;
	e->d = en->left->decl;
	e->zn = zn;
	e->desc = nil;
	e->next = excs;
	excs = e;

	ne = 0;
	c = e->c;
	for(i = 0; i < c->nlab; i++){
		lab = &c->labs[i];
		if(lab->start->ty->kind == Texception)
			ne++;
	}
	e->ne = ne;
}

static int
inlist(Decl *d, Decl *dd)
{
	for( ; dd != nil; dd = dd->next)
		if(d == dd)
			return 1;
	return 0;
}

static void
excdesc(void)
{
	ulong o, maxo;
	Except *e;
	Node *n;
	Decl *d, *dd, *nd;

	for(e = excs; e != nil; e = e->next){
		if(e->zn != nil){
			/* set up a decl list for gendesc */
			dd = nil;
			maxo = 0;
			for(n = e->zn ; n != nil; n = n->right){
				d = n->decl;
				d->locals = d->next;
				if(!inlist(d, dd)){
					d->next = dd;
					dd = d;
					o = d->offset+d->ty->size;
					if(o > maxo)
						maxo = o;
				}
			}
			e->desc = gendesc(e->d, align(maxo, MaxAlign), dd);
			for(d = dd; d != nil; d = nd){
				nd = d->next;
				d->next = d->locals;
				d->locals = nil;
			}
			e->zn = nil;
		}
	}
}

static Except*
reve(Except *e)
{
	Except *l, *n;

	l = nil;
	for( ; e != nil; e = n){
		n = e->next;
		e->next = l;
		l = e;
	}
	return l;
}

static int
ckinline0(Node *n, Decl *d)
{
	Decl *dd;

	if(n == nil)
		return 1;
	if(n->op == Oname){
		dd = n->decl;
		if(d == dd)
			return 0;
		if(dd->caninline == 1)
			return ckinline0(dd->init->right, d);
		return 1;
	}
	return ckinline0(n->left, d) && ckinline0(n->right, d);
}

static void
ckinline(Decl *d)
{
	d->caninline = ckinline0(d->init->right, d);
}
		
void
modcom(Decl *entry)
{
	Decl *globals, *m, *nils, *d, *ldts;
	long ninst, ndata, ndesc, nlink, offset, ldtoff;
	int ok, i, hints;
	Dlist *dl;

	if(errors)
		return;

	if(emitcode || emitstub || emittab != nil){
		emit(curscope());
		popscope();
		return;
	}

	/*
	 * scom introduces global variables for case statements
	 * and unaddressable constants, so it must be done before
	 * popping the global scope
	 */
	nlabel = 0;
	maxstack = MaxTemp;
	genstart();

	for(i = 0; i < nfns; i++)
		if(fns[i]->caninline == 1)
			ckinline(fns[i]);

	ok = 0;
	for(i = 0; i < nfns; i++){
		d = fns[i];
if(debug['v']) print("fncom: %s %d %p\n", d->sym->name, d->refs, d);
		if(d->refs > 1 && !(d->caninline == 1 && local(d) && d->iface == nil)){
			fns[ok++] = d;
			fncom(d);
		}
	}
	nfns = ok;
	if(blocks != -1)
		fatal("blocks not nested correctly");
	firstinst = firstinst->next;
	if(errors)
		return;

	globals = popscope();
	checkrefs(globals);
	if(errors)
		return;
	globals = vars(globals);
	moddataref();

	nils = popscope();
	m = nil;
	for(d = nils; d != nil; d = d->next){
		if(debug['n'])
			print("nil '%s' ref %d\n", d->sym->name, d->refs);
		if(d->refs && m == nil)
			m = dupdecl(d);
		d->offset = 0;
	}
	globals = appdecls(m, globals);
	globals = namesort(globals);
	globals = modglobals(impdecls->d, globals);
	vcom(globals);
	narrowmods();
	ldts = nil;
	if(LDT)
		globals = resolveldts(globals, &ldts);
	offset = idoffsets(globals, 0, IBY2WD);
	if(LDT)
		ldtoff = idindices(ldts);	/* ldtoff = idoffsets(ldts, 0, IBY2WD); */
	for(d = nils; d != nil; d = d->next){
		if(debug['n'])
			print("nil '%s' ref %d\n", d->sym->name, d->refs);
		if(d->refs)
			d->offset = m->offset;
	}

	if(debug['g']){
		print("globals:\n");
		printdecls(globals);
	}

	ndata = 0;
	for(d = globals; d != nil; d = d->next)
		ndata++;
	ndesc = resolvedesc(impdecls->d, offset, globals);
	ninst = resolvepcs(firstinst);
	modresolve();
	if(impdecls->next != nil)
		for(dl = impdecls; dl != nil; dl = dl->next)
			resolvemod(dl->d);
	nlink = resolvemod(impdecl);

	maxstack *= 10;
	if(fixss != 0)
		maxstack = fixss;

	if(debug['s'])
		print("%ld instructions\n%ld data elements\n%ld type descriptors\n%ld functions exported\n%ld stack size\n",
			ninst, ndata, ndesc, nlink, maxstack);

	excs = reve(excs);

	if(gendis){
		discon(XMAGIC);
		hints = 0;
		if(mustcompile)
			hints |= MUSTCOMPILE;
		if(dontcompile)
			hints |= DONTCOMPILE;
		if(LDT)
			hints |= HASLDT;
		if(excs != nil)
			hints |= HASEXCEPT;
		discon(hints);		/* runtime hints */
		discon(maxstack);	/* minimum stack extent size */
		discon(ninst);
		discon(offset);
		discon(ndesc);
		discon(nlink);
		disentry(entry);
		disinst(firstinst);
		disdesc(descriptors);
		disvar(offset, globals);
		dismod(impdecl);
		if(LDT)
			disldt(ldtoff, ldts);
		if(excs != nil)
			disexc(excs);
		dispath();
	}else{
		asminst(firstinst);
		asmentry(entry);
		asmdesc(descriptors);
		asmvar(offset, globals);
		asmmod(impdecl);
		if(LDT)
			asmldt(ldtoff, ldts);
		if(excs != nil)
			asmexc(excs);
		asmpath();
	}
	if(bsym != nil){
		sblmod(impdecl);

		sblfiles();
		sblinst(firstinst, ninst);
		sblty(adts, nadts);
		sblfn(fns, nfns);
		sblvar(globals);
	}

	firstinst = nil;
	lastinst = nil;

	excs = nil;
}

void
fncom(Decl *decl)
{
	Src src;
	Node *n;
	Decl *loc, *last;
	Inst *in;
	int valued;

	curfn = decl;
	if(ispoly(decl))
		addfnptrs(decl, 1);

	/*
	 * pick up the function body and compile it
	 * this code tries to clean up the parse nodes as fast as possible
	 * function is Ofunc(name, body)
	 */
	decl->pc = nextinst();
	tinit();
	labdep = 0;
	scp = 0;
	breaks = allocmem(maxlabdep * sizeof breaks[0]);
	conts = allocmem(maxlabdep * sizeof conts[0]);
	labels = allocmem(maxlabdep * sizeof labels[0]);
	bcscps = allocmem(maxlabdep * sizeof bcscps[0]);
	n = decl->init;
	if(decl->caninline == 1)
		decl->init = dupn(0, nil, n);
	else
		decl->init = n->left;
	src = n->right->src;
	src.start.line = src.stop.line;
	src.start.pos = src.stop.pos - 1;
	for(n = n->right; n != nil; n = n->right){
		if(n->op != Oseq){
			if(n->op == Ocall && trcom(n, nil, 1))
				break;
			scom(n);
			break;
		}
		if(n->left->op == Ocall && trcom(n->left, n->right, 1)){
			n = n->right;
			if(n == nil || n->op != Oseq)
				break;
		}
		else
			scom(n->left);
	}
	pushblock();
	valued = decl->ty->tof != tnone;
	in = genrawop(&src, valued? IRAISE: IRET, nil, nil, nil);
	popblock();
	reach(decl->pc);
	if(valued && in->reach)
		error(src.start, "no return at end of function %D", decl);
	/* decl->endpc = lastinst; */
	if(labdep != 0)
		fatal("unbalanced label stack");
	free(breaks);
	free(conts);
	free(labels);
	free(bcscps);

	loc = declsort(appdecls(vars(decl->locals), tdecls()));
	decl->offset = idoffsets(loc, decl->offset, MaxAlign);
	for(last = decl->ty->ids; last != nil && last->next != nil; last = last->next)
		;
	if(last != nil)
		last->next = loc;
	else
		decl->ty->ids = loc;

	if(debug['f']){
		print("fn: %s\n", decl->sym->name);
		printdecls(decl->ty->ids);
	}

	decl->desc = gendesc(decl, decl->offset, decl->ty->ids);
	decl->locals = loc;
	excdesc();
	if(decl->offset > maxstack)
		maxstack = decl->offset;
	if(optims)
		optim(decl->pc, decl);
	if(last != nil)
		last->next = nil;
	else
		decl->ty->ids = nil;
}

/*
 * statement compiler
 */
void
scom(Node *n)
{
	Inst *p, *pp, *p1, *p2, *p3;
	Node tret, *left, *zn;

	for(; n != nil; n = n->right){
		switch(n->op){
		case Ocondecl:
		case Otypedecl:
		case Ovardecl:
		case Oimport:
		case Oexdecl:
			return;
		case Ovardecli:
			break;
		case Oscope:
			pushscp(n);
			scom(n->right);
			popscp();
			zcom(n->left, nil);
			return;
		case Olabel:
			scom(n->right);
			return;
		case Oif:
			pushblock();
			left = simplify(n->left);
			if(left->op == Oconst && left->ty == tint){
				if(left->val != 0)
					scom(n->right->left);
				else
					scom(n->right->right);
				popblock();
				return;
			}
			sumark(left);
			pushblock();
			p = bcom(left, 1, nil);
			tfreenow();
			popblock();
			scom(n->right->left);
			if(n->right->right != nil){
				pp = p;
				p = genrawop(&lastinst->src, IJMP, nil, nil, nil);
				patch(pp, nextinst());
				scom(n->right->right);
			}
			patch(p, nextinst());
			popblock();
			return;
		case Ofor:
			n->left = left = simplify(n->left);
			if(left->op == Oconst && left->ty == tint){
				if(left->val == 0)
					return;
				left->op = Onothing;
				left->ty = tnone;
				left->decl = nil;
			}
			pp = nextinst();
			pushblock();
			/* b = pushblock(); */
			sumark(left);
			p = bcom(left, 1, nil);
			tfreenow();
			popblock();

			if(labdep >= maxlabdep)
				fatal("label stack overflow");
			breaks[labdep] = nil;
			conts[labdep] = nil;
			labels[labdep] = n->decl;
			bcscps[labdep] = curscp();
			labdep++;
			scom(n->right->left);
			labdep--;

			patch(conts[labdep], nextinst());
			if(n->right->right != nil){
				pushblock();
				scom(n->right->right);
				popblock();
			}
			repushblock(lastinst->block);	/* was b */
			patch(genrawop(&lastinst->src, IJMP, nil, nil, nil), pp);	/* for cprof: was &left->src */
			popblock();
			patch(p, nextinst());
			patch(breaks[labdep], nextinst());
			return;
		case Odo:
			pp = nextinst();

			if(labdep >= maxlabdep)
				fatal("label stack overflow");
			breaks[labdep] = nil;
			conts[labdep] = nil;
			labels[labdep] = n->decl;
			bcscps[labdep] = curscp();
			labdep++;
			scom(n->right);
			labdep--;

			patch(conts[labdep], nextinst());

			left = simplify(n->left);
			if(left->op == Onothing
			|| left->op == Oconst && left->ty == tint){
				if(left->op == Onothing || left->val != 0){
					pushblock();
					p = genrawop(&left->src, IJMP, nil, nil, nil);
					popblock();
				}else
					p = nil;
			}else{
				pushblock();
				p = bcom(sumark(left), 0, nil);
				tfreenow();
				popblock();
			}
			patch(p, pp);
			patch(breaks[labdep], nextinst());
			return;
		case Oalt:
		case Ocase:
		case Opick:
		case Oexcept:
/* need push/pop blocks for alt guards */
			pushblock();
			if(labdep >= maxlabdep)
				fatal("label stack overflow");
			breaks[labdep] = nil;
			conts[labdep] = &nocont;
			labels[labdep] = n->decl;
			bcscps[labdep] = curscp();
			labdep++;
			switch(n->op){
			case Oalt:
				altcom(n);
				break;
			case Ocase:
			case Opick:
				casecom(n);
				break;
			case Oexcept:
				excom(n);
				break;
			}
			labdep--;
			patch(breaks[labdep], nextinst());
			popblock();
			return;
		case Obreak:
			pushblock();
			bccom(n, breaks);
			popblock();
			break;
		case Ocont:
			pushblock();
			bccom(n, conts);
			popblock();
			break;
		case Oseq:
			if(n->left->op == Ocall && trcom(n->left, n->right, 0)){
				n = n->right;
				if(n == nil || n->op != Oseq)
					return;
			}
			else
				scom(n->left);
			break;
		case Oret:
			if(n->left != nil && n->left->op == Ocall && trcom(n->left, nil, 1))
				return;
			pushblock();
			if(n->left != nil){
				n->left = simplify(n->left);
				sumark(n->left);
				ecom(&n->left->src, retalloc(&tret, n->left), n->left);
				tfreenow();
			}
			genrawop(&n->src, IRET, nil, nil, nil);
			popblock();
			return;
		case Oexit:
			pushblock();
			genrawop(&n->src, IEXIT, nil, nil, nil);
			popblock();
			return;
		case Onothing:
			return;
		case Ofunc:
			fatal("Ofunc");
			return;
		case Oexstmt:
			pushblock();
			pp = genrawop(&n->right->src, IEXC0, nil, nil, nil);	/* marker */
			p1 = nextinst();
			scom(n->left);
			p2 = nextinst();
			p3 = genrawop(&n->right->src, IJMP, nil, nil, nil);
			p = genrawop(&n->right->src, IEXC, nil, nil, nil);	/* marker */
			p->d.decl = mkdecl(&n->src, 0, n->right->ty);
			zn = nil;
			zeroallscopes(n->left, &zn);
			scom(n->right);
			patch(p3, nextinst());
			installexc(n->right, p1, p2, zn);
			patch(pp, p);
			popblock();
			return;
		default:
			pushblock();
			n = simplify(n);
			sumark(n);
			ecom(&n->src, nil, n);
			tfreenow();
			popblock();
			return;
		}
	}
}

/*
 * compile a break, continue
 */
void
bccom(Node *n, Inst **bs)
{
	Sym *s;
	Inst *p;
	int i, ok;

	s = nil;
	if(n->decl != nil)
		s = n->decl->sym;
	ok = -1;
	for(i = 0; i < labdep; i++){
		if(bs[i] == &nocont)
			continue;
		if(s == nil || labels[i] != nil && labels[i]->sym == s)
			ok = i;
	}
	if(ok < 0){
		nerror(n, "no appropriate target for %V", n);
		return;
	}
	zeroscopes(bcscps[ok]);
	p = genrawop(&n->src, IJMP, nil, nil, nil);
	p->branch = bs[ok];
	bs[ok] = p;
}

static int
dogoto(Case *c)
{
	int i, j, k, n, r, q, v;
	Label *l, *nl;
	Src *src;

	l = c->labs;
	n = c->nlab;
	if(n == 0)
		return 0;
	r = l[n-1].stop->val - l[0].start->val+1;
	if(r >= 3 && r <= 3*n){
		if(r != n){
			/* remove ranges, fill in gaps */
			c->nlab = r;
			nl = c->labs = allocmem(r*sizeof(*nl));
			k = 0;
			v = l[0].start->val-1;
			for(i = 0; i < n; i++){
				/* p = l[i].start->val; */
				q = l[i].stop->val;
				src = &l[i].start->src;
				for(j = v+1; j <= q; j++){
					nl[k] = l[i];
					nl[k].start = nl[k].stop = mkconst(src, j);
					k++;
				}
				v = q;
			}
			if(k != r)
				fatal("bad case expansion");
		}
		l = c->labs;
		for(i = 0; i < r; i++)
			l[i].inst = nil;
		return 1;
	}
	return 0;
}

static void
fillrange(Case *c, Node *nn, Inst *in)
{
	int i, j, n, p, q;
	Label *l;

	l = c->labs;
	n = c->nlab;
	p = nn->left->val;
	q = nn->right->val;
	for(i = 0; i < n; i++)
		if(l[i].start->val == p)
			break;
	if(i == n)
		fatal("fillrange fails");
	for(j = p; j <= q; j++)
		l[i++].inst = in;
}

static int
nconstqual(Node *s1)
{
	Node *s2;
	int n;

	n = 0;
	for(; s1 != nil; s1 = s1->right){
		for(s2 = s1->left->left; s2 != nil; s2 = s2->right)
			if(s2->left->op == Oconst)
				n++;
	}
	return n;
}

void
casecom(Node *cn)
{
	Src *src;
	Case *c;
	Decl *d;
	Type *ctype;
	Inst *j, *jmps, *wild, *k, *j1, *j2;
	Node *n, *p, *left, tmp, nto, tmpc;
	Label *labs;
	char buf[32];
	int i, nlab, op, needwild, igoto;

	c = cn->ty->cse;

	needwild = cn->op != Opick || nconstqual(cn->right) != cn->left->right->ty->tof->decl->tag;
	igoto = cn->left->ty == tint && dogoto(c);
	j1 = j2 = nil;

	/*
	 * generate global which has case labels
	 */
	if(igoto){
		seprint(buf, buf+sizeof(buf), ".g%d", nlabel++);
		cn->ty->kind = Tgoto;
	}
	else
		seprint(buf, buf+sizeof(buf), ".c%d", nlabel++);
	d = mkids(&cn->src, enter(buf, 0), cn->ty, nil);
	d->init = mkdeclname(&cn->src, d);

	nto.addable = Rmreg;
	nto.left = nil;
	nto.right = nil;
	nto.op = Oname;
	nto.ty = d->ty;
	nto.decl = d;

	tmp.decl = tmpc.decl = nil;
	left = cn->left;
	left = simplify(left);
	cn->left = left;
	sumark(left);
	if(debug['c'])
		print("case %n\n", left);
	ctype = cn->left->ty;
	if(left->addable >= Rcant){
		if(cn->op == Opick){
			ecom(&left->src, nil, left);
			tfreenow();
			left = mkunary(Oind, dupn(1, &left->src, left->left));
			left->ty = tint;
			sumark(left);
			ctype = tint;
		}else{
			left = eacom(left, &tmp, nil);
			tfreenow();
		}
	}

	labs = c->labs;
	nlab = c->nlab;

	if(igoto){
		if(labs[0].start->val != 0){
			talloc(&tmpc, left->ty, nil);
			if(left->addable == Radr || left->addable == Rmadr){
				genrawop(&left->src, IMOVW, left, nil, &tmpc);
				left = &tmpc;
			}
			genrawop(&left->src, ISUBW, sumark(labs[0].start), left, &tmpc);
			left = &tmpc;
		}
		if(needwild){
			j1 = genrawop(&left->src, IBLTW, left, sumark(mkconst(&left->src, 0)), nil);
			j2 = genrawop(&left->src, IBGTW, left, sumark(mkconst(&left->src, labs[nlab-1].start->val-labs[0].start->val)), nil);
		}
		j = nextinst();
		genrawop(&left->src, IGOTO, left, nil, &nto);
		j->d.reg = IBY2WD;
	}
	else{
		op = ICASE;
		if(ctype == tbig)
			op = ICASEL;
		else if(ctype == tstring)
			op = ICASEC;
		genrawop(&left->src, op, left, nil, &nto);
	}
	tfree(&tmp);
	tfree(&tmpc);

	jmps = nil;
	wild = nil;
	for(n = cn->right; n != nil; n = n->right){
		j = nextinst();
		for(p = n->left->left; p != nil; p = p->right){
			if(debug['c'])
				print("case qualifier %n\n", p->left);
			switch(p->left->op){
			case Oconst:
				labs[findlab(ctype, p->left, labs, nlab)].inst = j;
				break;
			case Orange:
				labs[findlab(ctype, p->left->left, labs, nlab)].inst = j;
				if(igoto)
					fillrange(c, p->left, j);	
				break;
			case Owild:
				if(needwild)
					wild = j;
/*
				else
					nwarn(p->left, "default case redundant");
*/
				break;
			}
		}

		if(debug['c'])
			print("case body for %V: %n\n", n->left->left, n->left->right);

		k = nextinst();
		scom(n->left->right);

		src = &lastinst->src;
		// if(n->left->right == nil || n->left->right->op == Onothing)
		if(k == nextinst())
			src = &n->left->left->src;
		j = genrawop(src, IJMP, nil, nil, nil);
		j->branch = jmps;
		jmps = j;
	}
	patch(jmps, nextinst());
	if(wild == nil && needwild)
		wild = nextinst();

	if(igoto){
		if(needwild){
			patch(j1, wild);
			patch(j2, wild);
		}
		for(i = 0; i < nlab; i++)
			if(labs[i].inst == nil)
				labs[i].inst = wild;
	}

	c->iwild = wild;

	d->ty->cse = c;
	usetype(d->ty);
	installids(Dglobal, d);
}

void
altcom(Node *nalt)
{
	Src altsrc;
	Case *c;
	Decl *d;
	Type *talt;
	Node *n, *p, *left, tab, slot, off, add, which, nto, adr;
	Node **comm, *op, *tmps;
	Inst *j, *tj, *jmps, *me, *wild;
	Label *labs;
	char buf[32];
	int i, is, ir, nlab, nsnd, altop, isptr;
	Inst *pp;

	talt = nalt->ty;
	c = talt->cse;
	nlab = c->nlab;
	nsnd = c->nsnd;
	comm = allocmem(nlab * sizeof *comm);
	labs = allocmem(nlab * sizeof *labs);
	tmps = allocmem(nlab * sizeof *tmps);
	c->labs = labs;

	/*
	 * built the type of the alt channel table
	 * note that we lie to the garbage collector
	 * if we know that another reference exists for the channel
	 */
	is = 0;
	ir = nsnd;
	i = 0;
	for(n = nalt->left; n != nil; n = n->right){
		for(p = n->left->right->left; p != nil; p = p->right){
			left = simplify(p->left);
			p->left = left;
			if(left->op == Owild)
				continue;
			comm[i] = hascomm(left);
			left = comm[i]->left;
			sumark(left);
			isptr = left->addable >= Rcant;
			if(comm[i]->op == Osnd)
				labs[is++].isptr = isptr;
			else
				labs[ir++].isptr = isptr;
			i++;
		}
	}

	talloc(&which, tint, nil);
	talloc(&tab, talt, nil);

	/*
	 * build the node for the address of each channel,
	 * the values to send, and the storage fro values received
	 */
	off = znode;
	off.op = Oconst;
	off.ty = tint;
	off.addable = Rconst;
	adr = znode;
	adr.op = Oadr;
	adr.left = &tab;
	adr.ty = tint;
	add = znode;
	add.op = Oadd;
	add.left = &adr;
	add.right = &off;
	add.ty = tint;
	slot = znode;
	slot.op = Oind;
	slot.left = &add;
	sumark(&slot);

	/*
	 * compile the sending and receiving channels and values
	 */
	is = 2*IBY2WD;
	ir = is + nsnd*2*IBY2WD;
	i = 0;
	for(n = nalt->left; n != nil; n = n->right){
		for(p = n->left->right->left; p != nil; p = p->right){
			if(p->left->op == Owild)
				continue;

			/*
			 * gen channel
			 */
			op = comm[i];
			if(op->op == Osnd){
				off.val = is;
				is += 2*IBY2WD;
			}else{
				off.val = ir;
				ir += 2*IBY2WD;
			}
			left = op->left;

			/*
			 * this sleaze is lying to the garbage collector
			 */
			if(left->addable < Rcant)
				genmove(&left->src, Mas, tint, left, &slot);
			else{
				slot.ty = left->ty;
				ecom(&left->src, &slot, left);
				tfreenow();
				slot.ty = nil;
			}

			/*
			 * gen value
			 */
			off.val += IBY2WD;
			tmps[i].decl = nil;
			p->left = rewritecomm(p->left, comm[i], &tmps[i], &slot);

			i++;
		}
	}

	/*
	 * stuff the number of send & receive channels into the table
	 */
	altsrc = nalt->src;
	altsrc.stop.pos += 3;
	off.val = 0;
	genmove(&altsrc, Mas, tint, sumark(mkconst(&altsrc, nsnd)), &slot);
	off.val += IBY2WD;
	genmove(&altsrc, Mas, tint, sumark(mkconst(&altsrc, nlab-nsnd)), &slot);
	off.val += IBY2WD;

	altop = IALT;
	if(c->wild != nil)
		altop = INBALT;
	pp = genrawop(&altsrc, altop, &tab, nil, &which);
	pp->m.offset = talt->size;	/* for optimizer */

	seprint(buf, buf+sizeof(buf), ".g%d", nlabel++);
	d = mkids(&nalt->src, enter(buf, 0), mktype(&nalt->src.start, &nalt->src.stop, Tgoto, nil, nil), nil);
	d->ty->cse = c;
	d->init = mkdeclname(&nalt->src, d);

	nto.addable = Rmreg;
	nto.left = nil;
	nto.right = nil;
	nto.op = Oname;
	nto.decl = d;
	nto.ty = d->ty;

	me = nextinst();
	genrawop(&altsrc, IGOTO, &which, nil, &nto);
	me->d.reg = IBY2WD;		/* skip the number of cases field */
	tfree(&tab);
	tfree(&which);

	/*
	 * compile the guard expressions and bodies
	 */
	i = 0;
	is = 0;
	ir = nsnd;
	jmps = nil;
	wild = nil;
	for(n = nalt->left; n != nil; n = n->right){
		j = nil;
		for(p = n->left->right->left; p != nil; p = p->right){
			tj = nextinst();
			if(p->left->op == Owild){
				wild = nextinst();
			}else{
				if(comm[i]->op == Osnd)
					labs[is++].inst = tj;
				else{
					labs[ir++].inst = tj;
					tacquire(&tmps[i]);
				}
				sumark(p->left);
				if(debug['a'])
					print("alt guard %n\n", p->left);
				ecom(&p->left->src, nil, p->left);
				tfree(&tmps[i]);
				tfreenow();
				i++;
			}
			if(p->right != nil){
				tj = genrawop(&lastinst->src, IJMP, nil, nil, nil);
				tj->branch = j;
				j = tj;
			}
		}

		patch(j, nextinst());
		if(debug['a'])
			print("alt body %n\n", n->left->right);
		scom(n->left);

		j = genrawop(&lastinst->src, IJMP, nil, nil, nil);
		j->branch = jmps;
		jmps = j;
	}
	patch(jmps, nextinst());
	free(comm);

	c->iwild = wild;

	usetype(d->ty);
	installids(Dglobal, d);
}

void
excom(Node *en)
{
	Src *src;
	Decl *ed;
	Type *qt;
	Case *c;
	Inst *j, *jmps, *wild, *k;
	Node *n, *p;
	Label *labs;
	int nlab;

	ed = en->left->decl;
	ed->ty = rtexception;
	c = en->ty->cse;
	labs = c->labs;
	nlab = c->nlab;
	jmps = nil;
	wild = nil;
	for(n = en->right; n != nil; n = n->right){
		qt = nil;
		j = nextinst();
		for(p = n->left->left; p != nil; p = p->right){
			switch(p->left->op){
			case Oconst:
				labs[findlab(texception, p->left, labs, nlab)].inst = j;
				break;
			case Owild:
				wild = j;
				break;
			}
			if(qt == nil)
				qt = p->left->ty;
			else if(!tequal(qt, p->left->ty))
				qt = texception;
		}
		if(qt != nil)
			ed->ty = qt;
		k = nextinst();
		scom(n->left->right);
		src = &lastinst->src;
		if(k == nextinst())
			src = &n->left->left->src;
		j = genrawop(src, IJMP, nil, nil, nil);
		j->branch = jmps;
		jmps = j;
	}
	ed->ty = rtexception;
	patch(jmps, nextinst());
	c->iwild = wild;
}

/*
 * rewrite the communication operand
 * allocate any temps needed for holding value to send or receive
 */
Node*
rewritecomm(Node *n, Node *comm, Node *tmp, Node *slot)
{
	Node *adr;
	Inst *p;

	if(n == nil)
		return nil;
	adr = nil;
	if(n == comm){
		if(comm->op == Osnd && sumark(n->right)->addable < Rcant)
			adr = n->right;
		else{
			adr = talloc(tmp, n->ty, nil);
			tmp->src = n->src;
			if(comm->op == Osnd){
				ecom(&n->right->src, tmp, n->right);
				tfreenow();
			}
			else
				trelease(tmp);
		}
	}
	if(n->right == comm && n->op == Oas && comm->op == Orcv
	&& sumark(n->left)->addable < Rcant && (n->left->op != Oname || n->left->decl != nildecl))
		adr = n->left;
	if(adr != nil){
		p = genrawop(&comm->left->src, ILEA, adr, nil, slot);
		p->m.offset = adr->ty->size;	/* for optimizer */
		if(comm->op == Osnd)
			p->m.reg = 1;	/* for optimizer */
		return adr;
	}
	n->left = rewritecomm(n->left, comm, tmp, slot);
	n->right = rewritecomm(n->right, comm, tmp, slot);
	return n;
}

/*
 * merge together two sorted lists, yielding a sorted list
 */
static Decl*
declmerge(Decl *e, Decl *f)
{
	Decl rock, *d;
	int es, fs, v;

	d = &rock;
	while(e != nil && f != nil){
		fs = f->ty->size;
		es = e->ty->size;
		/* v = 0; */
		v = (e->link == nil) - (f->link == nil);
		if(v == 0 && (es <= IBY2WD || fs <= IBY2WD))
			v = fs - es;
		if(v == 0)
			v = e->refs - f->refs;
		if(v == 0)
			v = fs - es;
		if(v == 0)
			v = -strcmp(e->sym->name, f->sym->name);
		if(v >= 0){
			d->next = e;
			d = e;
			e = e->next;
			while(e != nil && e->nid == 0){
				d = e;
				e = e->next;
			}
		}else{
			d->next = f;
			d = f;
			f = f->next;
			while(f != nil && f->nid == 0){
				d = f;
				f = f->next;
			}
		}
		/* d = d->next; */
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
recdeclsort(Decl *d, int n)
{
	Decl *r, *dd;
	int i, m;

	if(n <= 1)
		return d;
	m = n / 2 - 1;
	dd = d;
	for(i = 0; i < m; i++){
		dd = dd->next;
		while(dd->nid == 0)
			dd = dd->next;
	}
	r = dd->next;
	while(r->nid == 0){
		dd = r;
		r = r->next;
	}
	dd->next = nil;
	return declmerge(recdeclsort(d, n / 2),
			recdeclsort(r, (n + 1) / 2));
}

/*
 * sort the ids by size and number of references
 */
Decl*
declsort(Decl *d)
{
	Decl *dd;
	int n;

	n = 0;
	for(dd = d; dd != nil; dd = dd->next)
		if(dd->nid > 0)
			n++;
	return recdeclsort(d, n);
}

Src nilsrc;

/* Do we finally
  * 	(a) pick off pointers as in the code below
  *	(b) generate a block move from zeroed memory as in tfree() in gen.b in limbo version
  *	(c) add a new block zero instruction to dis
  *	(d) reorganize the locals/temps in a frame
  */
void
zcom1(Node *n, Node **nn)
{
	Type *ty;
	Decl *d;
	Node *e, *dn;
	Src src;

	ty = n->ty;
	if (!tmustzero(ty))
		return;
	if (n->op == Oname && n->decl->refs == 0)
		return;
	if (nn) {
		if(n->op != Oname)
			nerror(n, "fatal: bad op in zcom1 map");
		n->right = *nn;
		*nn = n;
		return;
	}
	if (debug['Z'])
		print("zcom1 : %n\n", n);
	if (ty->kind == Tadtpick)
		ty = ty->tof;
	if (ty->kind == Ttuple || ty->kind == Tadt) {
		for (d = ty->ids; d != nil; d = d->next) {
			if (tmustzero(d->ty)) {
				if (d->next != nil)
					dn = dupn(0, nil, n);
				else
					dn = n;
				e = mkbin(Odot, dn, mkname(&nilsrc, d->sym));
				e->right->decl = d;
				e->ty = e->right->ty = d->ty;
				zcom1(e, nn);
			}
		}
	}
	else {
		src = n->src;
		n->src = nilsrc;
		e = mkbin(Oas, n, mknil(&nilsrc));
		e->ty = e->right->ty = ty;
/*
		if (debug['Z'])
			print("ecom %n\n", e);
*/
		pushblock();
		e = simplify(e);
		sumark(e);
		ecom(&e->src, nil, e);
		popblock();
		n->src = src;
	}
}

void
zcom0(Decl *id, Node **nn)
{
	Node *e;

	e = mkname(&nilsrc, id->sym);
	e->decl = id;
	e->ty = id->ty;
	zcom1(e, nn);
}

/* end of scope */
void
zcom(Node *n, Node **nn)
{
	Decl *ids, *last;
	Node *r, *nt;

	for ( ; n != nil; n = r) {
		r = n->right;
		n->right = nil;
		switch (n->op) {
			case Ovardecl :
				last = n->left->decl;
				for (ids = n->decl; ids != last->next; ids = ids->next)
					zcom0(ids, nn);
				break;
			case Oname :
				if (n->decl != nildecl)
					zcom1(dupn(0, nil, n), nn);
				break;
			case Otuple :
				for (nt = n->left; nt != nil; nt = nt->right)
					zcom(nt->left, nn);
				break;
			default :
				fatal("bad node in zcom()");
				break;
		}
		n->right = r;
	}
}

static int
ret(Node *n, int nilret)
{
	if(n == nil)
		return nilret;
	if(n->op == Oseq)
		n = n->left;
	return n->op == Oret && n->left == nil;
}

/*
 * tail-recursive call
 */
static int
trcom(Node *e, Node *ne, int nilret)
{
	Decl *d, *id;
	Node *as, *a, *f, *n;
	Inst *p;

	if(1)
		return 0;	/* TO DO: should we enable this? */
	if(e->op != Ocall || e->left->op != Oname)
		return 0;
	d = e->left->decl;
	if(d != curfn || d->handler || ispoly(d))
		return 0;
	if(!ret(ne, nilret))
		return 0;
	pushblock();
	id = d->ty->ids;
	/* evaluate args in same order as normal calls */
	for(as = e->right; as != nil; as = as->right){
		a = as->left;
		if(!(a->op == Oname && id == a->decl)){
			if(occurs(id, as->right)){
				f = talloc(mkn(0, nil, nil), id->ty, nil);
				f->flags |= TEMP;
			}
			else
				f = mkdeclname(&as->src, id);
			n = mkbin(Oas, f, a);
			n->ty = id->ty;
			scom(n);
			if(f->flags&TEMP)
				as->left = f;
		}
		id = id->next;
	}
	id = d->ty->ids;
	for(as = e->right; as != nil; as = as->right){
		a = as->left;
		if(a->flags&TEMP){
			f = mkdeclname(&as->src, id);
			n = mkbin(Oas, f, a);
			n->ty = id->ty;
			scom(n);
			tfree(a);
		}
		id = id->next;
	}
	p = genrawop(&e->src, IJMP, nil, nil, nil);
	patch(p, d->pc);
	popblock();
	return 1;
}
