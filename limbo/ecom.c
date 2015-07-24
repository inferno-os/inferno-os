#include "limbo.h"

static Node* putinline(Node*);
static void fpcall(Src*, int, Node*, Node*);

void
optabinit(void)
{
	int i;

	for(i = 0; setisbyteinst[i] >= 0; i++)
		isbyteinst[setisbyteinst[i]] = 1;

	for(i = 0; setisused[i] >= 0; i++)
		isused[setisused[i]] = 1;

	for(i = 0; setsideeffect[i] >= 0; i++)
		sideeffect[setsideeffect[i]] = 1;

	opind[Tbyte] = 1;
	opind[Tint] = 2;
	opind[Tbig] = 3;
	opind[Treal] = 4;
	opind[Tstring] = 5;
	opind[Tfix] = 6;

	opcommute[Oeq] = Oeq;
	opcommute[Oneq] = Oneq;
	opcommute[Olt] = Ogt;
	opcommute[Ogt] = Olt;
	opcommute[Ogeq] = Oleq;
	opcommute[Oleq] = Ogeq;
	opcommute[Oadd] = Oadd;
	opcommute[Omul] = Omul;
	opcommute[Oxor] = Oxor;
	opcommute[Oor] = Oor;
	opcommute[Oand] = Oand;

	oprelinvert[Oeq] = Oneq;
	oprelinvert[Oneq] = Oeq;
	oprelinvert[Olt] = Ogeq;
	oprelinvert[Ogt] = Oleq;
	oprelinvert[Ogeq] = Olt;
	oprelinvert[Oleq] = Ogt;

	isrelop[Oeq] = 1;
	isrelop[Oneq] = 1;
	isrelop[Olt] = 1;
	isrelop[Oleq] = 1;
	isrelop[Ogt] = 1;
	isrelop[Ogeq] = 1;
	isrelop[Oandand] = 1;
	isrelop[Ooror] = 1;
	isrelop[Onot] = 1;

	precasttab[Tstring][Tbyte] = tint;
	precasttab[Tbyte][Tstring] = tint;
	precasttab[Treal][Tbyte] = tint;
	precasttab[Tbyte][Treal] = tint;
	precasttab[Tbig][Tbyte] = tint;
	precasttab[Tbyte][Tbig] = tint;
	precasttab[Tfix][Tbyte] = tint;
	precasttab[Tbyte][Tfix] = tint;
	precasttab[Tbig][Tfix] = treal;
	precasttab[Tfix][Tbig] = treal;
	precasttab[Tstring][Tfix] = treal;
	precasttab[Tfix][Tstring] = treal;

	casttab[Tint][Tint] = IMOVW;
	casttab[Tbig][Tbig] = IMOVL;
	casttab[Treal][Treal] = IMOVF;
	casttab[Tbyte][Tbyte] = IMOVB;
	casttab[Tstring][Tstring] = IMOVP;
	casttab[Tfix][Tfix] = ICVTXX;	/* never same type */

	casttab[Tint][Tbyte] = ICVTWB;
	casttab[Tint][Treal] = ICVTWF;
	casttab[Tint][Tstring] = ICVTWC;
	casttab[Tint][Tfix] = ICVTXX;
	casttab[Tbyte][Tint] = ICVTBW;
	casttab[Treal][Tint] = ICVTFW;
	casttab[Tstring][Tint] = ICVTCW;
	casttab[Tfix][Tint] = ICVTXX;

	casttab[Tint][Tbig] = ICVTWL;
	casttab[Treal][Tbig] = ICVTFL;
	casttab[Tstring][Tbig] = ICVTCL;
	casttab[Tbig][Tint] = ICVTLW;
	casttab[Tbig][Treal] = ICVTLF;
	casttab[Tbig][Tstring] = ICVTLC;

	casttab[Treal][Tstring] = ICVTFC;
	casttab[Tstring][Treal] = ICVTCF;

	casttab[Treal][Tfix] = ICVTFX;
	casttab[Tfix][Treal] = ICVTXF;

	casttab[Tstring][Tarray] = ICVTCA;
	casttab[Tarray][Tstring] = ICVTAC;

	/*
	 * placeholders; fixed in precasttab
	 */
	casttab[Tbyte][Tstring] = 0xff;
	casttab[Tstring][Tbyte] = 0xff;
	casttab[Tbyte][Treal] = 0xff;
	casttab[Treal][Tbyte] = 0xff;
	casttab[Tbyte][Tbig] = 0xff;
	casttab[Tbig][Tbyte] = 0xff;
	casttab[Tfix][Tbyte] = 0xff;
	casttab[Tbyte][Tfix] = 0xff;
	casttab[Tfix][Tbig] = 0xff;
	casttab[Tbig][Tfix] = 0xff;
	casttab[Tfix][Tstring] = 0xff;
	casttab[Tstring][Tfix] = 0xff;
}

/*
 * global variable and constant initialization checking
 */
int
vcom(Decl *ids)
{
	Decl *v;
	int ok;

	ok = 1;
	for(v = ids; v != nil; v = v->next)
		ok &= varcom(v);
	for(v = ids; v != nil; v = v->next)
		v->init = simplify(v->init);
	return ok;
}

Node*
simplify(Node *n)
{
	if(n == nil)
		return nil;
	if(debug['F'])
		print("simplify %n\n", n);
	n = efold(rewrite(n));
	if(debug['F'])
		print("simplified %n\n", n);
	return n;
}

static int
isfix(Node *n)
{
	if(n->ty->kind == Tint || n->ty->kind == Tfix){
		if(n->op == Ocast)
			return n->left->ty->kind == Tint || n->left->ty->kind == Tfix;
		return 1;
	}
	return 0;
}

/*
 * rewrite an expression to make it easiser to compile,
 * or give the correct results
 */
Node*
rewrite(Node *n)
{
	Long v;
	Type *t;
	Decl *d;
	Node *nn, *left, *right;

	if(n == nil)
		return nil;

	left = n->left;
	right = n->right;

	/*
	 * rewrites
	 */
	switch(n->op){
	case Oname:
		d = n->decl;
		if(d->importid != nil){
			left = mkbin(Omdot, dupn(1, &n->src, d->eimport), mkdeclname(&n->src, d->importid));
			left->ty = n->ty;
			return rewrite(left);
		}
		if((t = n->ty)->kind == Texception){
			if(t->cons)
				fatal("cons in rewrite Oname");
			n = mkbin(Oadd, n, mkconst(&n->src, 2*IBY2WD));
			n = mkunary(Oind, n);
			n->ty = t;
			n->left->ty = n->left->left->ty = tint;
			return rewrite(n);
		}
		break;
	case Odas:
		n->op = Oas;
		return rewrite(n);
	case Oneg:
		n->left = rewrite(left);
		if(n->ty == treal)
			break;
		left = n->left;
		n->right = left;
		n->left = mkconst(&n->src, 0);
		n->left->ty = n->ty;
		n->op = Osub;
		break;
	case Ocomp:
		v = 0;
		v = ~v;
		n->right = mkconst(&n->src, v);
		n->right->ty = n->ty;
		n->left = rewrite(left);
		n->op = Oxor;
		break;
	case Oinc:
	case Odec:
	case Opreinc:
	case Opredec:
		n->left = rewrite(left);
		switch(n->ty->kind){
		case Treal:
			n->right = mkrconst(&n->src, 1.0);
			break;
		case Tint:
		case Tbig:
		case Tbyte:
		case Tfix:
			n->right = mkconst(&n->src, 1);
			n->right->ty = n->ty;
			break;
		default:
			fatal("can't rewrite inc/dec %n", n);
			break;
		}
		if(n->op == Opreinc)
			n->op = Oaddas;
		else if(n->op == Opredec)
			n->op = Osubas;
		break;
	case Oslice:
		if(right->left->op == Onothing)
			right->left = mkconst(&right->left->src, 0);
		n->left = rewrite(left);
		n->right = rewrite(right);
		break;
	case Oindex:
		n->op = Oindx;
		n->left = rewrite(left);
		n->right = rewrite(right);
		n = mkunary(Oind, n);
		n->ty = n->left->ty;
		n->left->ty = tint;
		break;
	case Oload:
		n->right = mkn(Oname, nil, nil);
		n->right->src = n->left->src;
		n->right->decl = n->ty->tof->decl;
		n->right->ty = n->ty;
		n->left = rewrite(left);
		break;
	case Ocast:
		if(left->ty->kind == Texception){
			n = rewrite(left);
			break;
		}
		n->op = Ocast;
		t = precasttab[left->ty->kind][n->ty->kind];
		if(t != nil){
			n->left = mkunary(Ocast, left);
			n->left->ty = t;
			return rewrite(n);
		}
		n->left = rewrite(left);
		break;
	case Oraise:
		if(left->ty == tstring)
			{}
		else if(!left->ty->cons)
			break;
		else if(left->op != Ocall || left->left->ty->kind == Tfn){
			left = mkunary(Ocall, left);
			left->ty = left->left->ty;
		}
		n->left = rewrite(left);
		break;
	case Ocall:
		t = left->ty;
		if(t->kind == Tref)
			t = t->tof;
		if(t->kind == Tfn){
if(debug['U']) print("call %n\n", left);
			if(left->ty->kind == Tref){	/* call by function reference */
				n->left = mkunary(Oind, left);
				n->left->ty = t;
				return rewrite(n);
			}
			d = nil;
			if(left->op == Oname)
				d = left->decl;
			else if(left->op == Omdot && left->right->op == Odot)
				d = left->right->right->decl;
			else if(left->op == Omdot || left->op == Odot)
				d = left->right->decl;
			else if(left->op != Oind)
				fatal("cannot deal with call %n in rewrite", n);
			if(ispoly(d))
				addfnptrs(d, 0);
			n->left = rewrite(left);
			if(right != nil)
				n->right = rewrite(right);
			if(d != nil && d->caninline == 1)
				n = simplify(putinline(n));
			break;
		}
		switch(n->ty->kind){
		case Tref:
			n = mkunary(Oref, n);
			n->ty = n->left->ty;
			n->left->ty = n->left->ty->tof;
			n->left->left->ty = n->left->ty;
			return rewrite(n);
		case Tadt:
			n->op = Otuple;
			n->right = nil;
			if(n->ty->tags != nil){
				n->left = nn = mkunary(Oseq, mkconst(&n->src, left->right->decl->tag));
				if(right != nil){
					nn->right = right;
					nn->src.stop = right->src.stop;
				}
				n->ty = left->right->decl->ty->tof;
			}else
				n->left = right;
			return rewrite(n);
		case Tadtpick:
			n->op = Otuple;
			n->right = nil;
			n->left = nn = mkunary(Oseq, mkconst(&n->src, left->right->decl->tag));
			if(right != nil){
				nn->right = right;
				nn->src.stop = right->src.stop;
			}
			n->ty = left->right->decl->ty->tof;
			return rewrite(n);
		case Texception:
			if(!n->ty->cons)
				return n->left;
			if(left->op == Omdot){
				left->right->ty = left->ty;
				left = left->right;
			}
			n->op = Otuple;
			n->right = nil;
			n->left = nn = mkunary(Oseq, left->decl->init);
			nn->right = mkunary(Oseq, mkconst(&n->src, 0));
			nn->right->right = right;
			n->ty = mkexbasetype(n->ty);
			n = mkunary(Oref, n);
			n->ty = internaltype(mktype(&n->src.start, &n->src.stop, Tref, t, nil));
			return rewrite(n);
		default:
			fatal("can't deal with %n in rewrite/Ocall", n);
			break;
		}
		break;
	case Omdot:
		/*
		 * what about side effects from left?
		 */
		d = right->decl;
		switch(d->store){
		case Dfn:
			n->left = rewrite(left);
			if(right->op == Odot){
				n->right = dupn(1, &left->src, right->right);
				n->right->ty = d->ty;
			}
			break;
		case Dconst:
		case Dtag:
		case Dtype:
			/* handled by fold */
			return n;
		case Dglobal:
			right->op = Oconst;
			right->val = d->offset;
			right->ty = tint;

			n->left = left = mkunary(Oind, left);
			left->ty = tint;
			n->op = Oadd;
			n = mkunary(Oind, n);
			n->ty = n->left->ty;
			n->left->ty = tint;
			n->left = rewrite(n->left);
			return n;
		case Darg:
			return n;
		default:
			fatal("can't deal with %n in rewrite/Omdot", n);
			break;
		}
		break;
	case Odot:
		/*
		 * what about side effects from left?
		 */
		d = right->decl;
		switch(d->store){
		case Dfn:
			if(right->left != nil){
				n = mkbin(Omdot, dupn(1, &left->src, right->left), right);
				right->left = nil;
				n->ty = d->ty;
				return rewrite(n);
			}
			if(left->ty->kind == Tpoly){
				n = mkbin(Omdot, mkdeclname(&left->src, d->link), mkdeclname(&left->src, d->link->next));
				n->ty = d->ty;
				return rewrite(n);
			}
			n->op = Oname;
			n->decl = d;
			n->right = nil;
			n->left = nil;
			return n;
		case Dconst:
		case Dtag:
		case Dtype:
			/* handled by fold */
			return n;
		}
		if(istuple(left))
			return n;	/* handled by fold */
		right->op = Oconst;
		right->val = d->offset;
		right->ty = tint;

		if(left->ty->kind != Tref){
			n->left = mkunary(Oadr, left);
			n->left->ty = tint;
		}
		n->op = Oadd;
		n = mkunary(Oind, n);
		n->ty = n->left->ty;
		n->left->ty = tint;
		n->left = rewrite(n->left);
		return n;
	case Oadr:
		left = rewrite(left);
		n->left = left;
		if(left->op == Oind)
			return left->left;
		break;
	case Otagof:
		if(n->decl == nil){
			n->op = Oind;
			return rewrite(n);
		}
		return n;
	case Omul:
	case Odiv:
		left = n->left = rewrite(left);
		right = n->right = rewrite(right);
		if(n->ty->kind == Tfix && isfix(left) && isfix(right)){
			if(left->op == Ocast && tequal(left->ty, n->ty))
				n->left = left->left;
			if(right->op == Ocast && tequal(right->ty, n->ty))
				n->right = right->left;
		}
		break;
	case Oself:
		if(newfnptr)
			return n;
		if(selfdecl == nil){
			d = selfdecl = mkids(&n->src, enter(strdup(".self"), 5), tany, nil);
			installids(Dglobal, d);
			d->refs++;
		}
		nn = mkn(Oload, nil, nil);
		nn->src = n->src;
		nn->left = mksconst(&n->src, enterstring(strdup("$self"), 5));
		nn->ty = impdecl->ty;
		usetype(nn->ty);
		usetype(nn->ty->tof);
		nn = rewrite(nn);
		nn->op = Oself;
		return nn;
	case Ofnptr:
		if(n->flags == 0){
			/* module */
			if(left == nil)
				left = mkn(Oself, nil, nil);
			return rewrite(left);
		}
		right->flags = n->flags;
		n = right;
		d = n->decl;
		if(n->flags == FNPTR2){
			if(left != nil && left->op != Oname)
				fatal("not Oname for addiface");
			if(left == nil){
				addiface(nil, d);
				if(newfnptr)
					n->flags |= FNPTRN;
			}
			else
				addiface(left->decl, d);	/* is this necessary ? */
			n->ty = tint;
			return n;
		}
		if(n->flags == FNPTRA){
			n = mkdeclname(&n->src, d->link);
			n->ty = tany;
			return n;
		}
		if(n->flags == (FNPTRA|FNPTR2)){
			n = mkdeclname(&n->src, d->link->next);
			n->ty = tint;
			return n;
		}
		break;
	case Ochan:
		if(left == nil)
			left = n->left = mkconst(&n->src, 0);
		n->left = rewrite(left);
		break;
	default:
		n->left = rewrite(left);
		n->right = rewrite(right);
		break;
	}

	return n;
}

/*
 * label a node with sethi-ullman numbers and addressablity
 * genaddr interprets addable to generate operands,
 * so a change here mandates a change there.
 *
 * addressable:
 *	const			Rconst	$value		 may also be Roff or Rdesc or Rnoff
 *	Asmall(local)		Rreg	value(FP)
 *	Asmall(global)		Rmreg	value(MP)
 *	ind(Rareg)		Rreg	value(FP)
 *	ind(Ramreg)		Rmreg	value(MP)
 *	ind(Rreg)		Radr	*value(FP)
 *	ind(Rmreg)		Rmadr	*value(MP)
 *	ind(Raadr)		Radr	value(value(FP))
 *	ind(Ramadr)		Rmadr	value(value(MP))
 *
 * almost addressable:
 *	adr(Rreg)		Rareg
 *	adr(Rmreg)		Ramreg
 *	add(const, Rareg)	Rareg
 *	add(const, Ramreg)	Ramreg
 *	add(const, Rreg)	Raadr
 *	add(const, Rmreg)	Ramadr
 *	add(const, Raadr)	Raadr
 *	add(const, Ramadr)	Ramadr
 *	adr(Radr)		Raadr
 *	adr(Rmadr)		Ramadr
 *
 * strangely addressable:
 *	fn			Rpc
 *	mdot(module,exp)	Rmpc
 */
Node*
sumark(Node *n)
{
	Node *left, *right;
	long v;

	if(n == nil)
		return nil;

	n->temps = 0;
	n->addable = Rcant;

	left = n->left;
	right = n->right;
	if(left != nil){
		sumark(left);
		n->temps = left->temps;
	}
	if(right != nil){
		sumark(right);
		if(right->temps == n->temps)
			n->temps++;
		else if(right->temps > n->temps)
			n->temps = right->temps;
	}

	switch(n->op){
	case Oadr:
		switch(left->addable){
		case Rreg:
			n->addable = Rareg;
			break;
		case Rmreg:
			n->addable = Ramreg;
			break;
		case Radr:
			n->addable = Raadr;
			break;
		case Rmadr:
			n->addable = Ramadr;
			break;
		}
		break;
	case Oind:
		switch(left->addable){
		case Rreg:
			n->addable = Radr;
			break;
		case Rmreg:
			n->addable = Rmadr;
			break;
		case Rareg:
			n->addable = Rreg;
			break;
		case Ramreg:
			n->addable = Rmreg;
			break;
		case Raadr:
			n->addable = Radr;
			break;
		case Ramadr:
			n->addable = Rmadr;
			break;
		}
		break;
	case Oname:
		switch(n->decl->store){
		case Darg:
		case Dlocal:
			n->addable = Rreg;
			break;
		case Dglobal:
			n->addable = Rmreg;
			if(LDT && n->decl->ty->kind == Tiface)
				n->addable = Rldt;
			break;
		case Dtype:
			/*
			 * check for inferface to load
			 */
			if(n->decl->ty->kind == Tmodule)
				n->addable = Rmreg;
			break;
		case Dfn:
			if(n->flags & FNPTR){
				if(n->flags == FNPTR2)
					n->addable = Roff;
				else if(n->flags == (FNPTR2|FNPTRN))
					n->addable = Rnoff;
			}
			else
				n->addable = Rpc;
			break;
		default:
			fatal("cannot deal with %K in Oname in %n", n->decl, n);
			break;
		}
		break;
	case Omdot:
		n->addable = Rmpc;
		break;
	case Oconst:
		switch(n->ty->kind){
		case Tint:
		case Tfix:
			v = n->val;
			if(v < 0 && ((v >> 29) & 0x7) != 7
			|| v > 0 && (v >> 29) != 0){
				n->decl = globalconst(n);
				n->addable = Rmreg;
			}else
				n->addable = Rconst;
			break;
		case Tbig:
			n->decl = globalBconst(n);
			n->addable = Rmreg;
			break;
		case Tbyte:
			n->decl = globalbconst(n);
			n->addable = Rmreg;
			break;
		case Treal:
			n->decl = globalfconst(n);
			n->addable = Rmreg;
			break;
		case Tstring:
			n->decl = globalsconst(n);
			n->addable = Rmreg;
			break;
		default:
			fatal("cannot %T const in sumark", n->ty);
			break;
		}
		break;
	case Oadd:
		if(right->addable == Rconst){
			switch(left->addable){
			case Rareg:
				n->addable = Rareg;
				break;
			case Ramreg:
				n->addable = Ramreg;
				break;
			case Rreg:
			case Raadr:
				n->addable = Raadr;
				break;
			case Rmreg:
			case Ramadr:
				n->addable = Ramadr;
				break;
			}
		}
		break;
	}
	if(n->addable < Rcant)
		n->temps = 0;
	else if(n->temps == 0)
		n->temps = 1;
	return n;
}

Node*
mktn(Type *t)
{
	Node *n;

	n = mkn(Oname, nil, nil);
	usedesc(mktdesc(t));
	n->ty = t;
	n->decl = t->decl;
	if(n->decl == nil)
		fatal("mktn t %T nil decl", t);
	n->addable = Rdesc;
	return n;
}

/* does a tuple of the form (a, b, ...) form a contiguous block
 * of memory on the stack when offsets are assigned later
 * - only when (a, b, ...) := rhs and none of the names nil
 * can we guarantee this
 */
static int
tupblk0(Node *n, Decl **dd)
{
	Decl *d;
	int nid;

	switch(n->op){
	case Otuple:
		for(n = n->left; n != nil; n = n->right)
			if(!tupblk0(n->left, dd))
				return 0;
		return 1;
	case Oname:
		if(n->decl == nildecl)
			return 0;
		d = *dd;
		if(d != nil && d->next != n->decl)
			return 0;
		nid = n->decl->nid;
		if(d == nil && nid == 1)
			return 0;
		if(d != nil && nid != 0)
			return 0;
		*dd = n->decl;
		return 1;
	}
	return 0;
}

/* could force locals to be next to each other
 * - need to shuffle locals list
 * - later
 */
static Node*
tupblk(Node *n)
{
	Decl *d;

	if(n->op != Otuple)
		return nil;
	d = nil;
	if(!tupblk0(n, &d))
		return nil;
	while(n->op == Otuple)
		n = n->left->left;
	if(n->op != Oname || n->decl->nid == 1)
		fatal("bad tupblk");
	return n;
}
	
/* for cprof */
#define esrc(src, osrc, nto) (src != nil && nto != nil ? src : osrc)

/*
 * compile an expression with an implicit assignment
 * note: you are not allowed to use to->src
 *
 * need to think carefully about the types used in moves
 * it particular, it would be nice to gen movp rather than movc sometimes.
 */
Node*
ecom(Src *src, Node *nto, Node *n)
{
	Node *left, *right, *tn;
	Node tl, tr, tto, ttn;
	Type *t, *tt;
	Inst *p, *pp;
	int op;

	if(debug['e']){
		print("ecom: %n\n", n);
		if(nto != nil)
			print("ecom to: %n\n", nto);
	}

	if(n->addable < Rcant){
		/*
		 * think carefully about the type used here
		 */
		if(nto != nil)
			genmove(src, Mas, n->ty, n, nto);
		return nto;
	}

	tl.decl = nil;
	tr.decl = nil;
	tto.decl = nil;
	ttn.decl = nil;

	left = n->left;
	right = n->right;
	op = n->op;
	switch(op){
	default:
	case Oadr:
		fatal("can't %n in ecom", n);
		return nto;
	case Oif:
		p = bcom(left, 1, nil);
		ecom(&right->left->src, nto, right->left);
		if(right->right != nil){
			pp = p;
			p = genrawop(&right->left->src, IJMP, nil, nil, nil);
			patch(pp, nextinst());
			ecom(&right->right->src, nto, right->right);
		}
		patch(p, nextinst());
		break;
	case Ocomma:
		tn = left->left;
		ecom(&left->src, nil, left);
		ecom(&right->src, nto, right);
		tfree(tn);
		break;
	case Oname:
		if(n->addable == Rpc){
			if(nto != nil)
				genmove(src, Mas, n->ty, n, nto);
			return nto;
		}
		fatal("can't %n in ecom", n);
		break;
	case Onothing:
		break;
	case Oused:
		if(nto != nil)
			fatal("superfluous used %n to %n", left, nto);
		talloc(&tto, left->ty, nil);
		ecom(&left->src, &tto, left);
		tfree(&tto);
		break;
	case Oas:
		if(right->ty == tany)
			right->ty = n->ty;
		if(left->op == Oname && left->decl->ty == tany){
			if(nto == nil)
				nto = talloc(&tto, right->ty, nil);
			left = nto;
			nto = nil;
		}
		if(left->op == Oinds){
			indsascom(src, nto, n);
			tfree(&tto);
			break;
		}
		if(left->op == Oslice){
			slicelcom(src, nto, n);
			tfree(&tto);
			break;
		}

		if(left->op == Otuple){
			if(!tupsaliased(right, left)){
				if((tn = tupblk(left)) != nil){
					tn->ty = n->ty;
					ecom(&n->right->src, tn, right);
					if(nto != nil)
						genmove(src, Mas, n->ty, tn, nto);
					tfree(&tto);
					break;
				}
				if((tn = tupblk(right)) != nil){
					tn->ty = n->ty;
					tuplcom(tn, left);
					if(nto != nil)
						genmove(src, Mas, n->ty, tn, nto);
					tfree(&tto);
					break;
				}
				if(nto == nil && right->op == Otuple && left->ty->kind != Tadtpick){
					tuplrcom(right, left);
					tfree(&tto);
					break;
				}
			}
			if(right->addable >= Ralways
			|| right->op != Oname
			|| tupaliased(right, left)){
				talloc(&tr, n->ty, nil);
				ecom(&n->right->src, &tr, right);
				right = &tr;
			}
			tuplcom(right, n->left);
			if(nto != nil)
				genmove(src, Mas, n->ty, right, nto);
			tfree(&tr);
			tfree(&tto);
			break;
		}

		/*
		 * check for left/right aliasing and build right into temporary
		 */
		if(right->op == Otuple){
			if(!tupsaliased(left, right) && (tn = tupblk(right)) != nil){
				tn->ty = n->ty;
				right = tn;
			}
			else if(left->op != Oname || tupaliased(left, right))
				right = ecom(&right->src, talloc(&tr, right->ty, nil), right);
		}

		/*
		 * think carefully about types here
		 */
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nto);
		ecom(&n->src, left, right);
		if(nto != nil)
			genmove(src, Mas, nto->ty, left, nto);
		tfree(&tl);
		tfree(&tr);
		tfree(&tto);
		break;
	case Ochan:
		if(left && left->addable >= Rcant)
			left = eacom(left, &tl, nto);
		genchan(src, left, n->ty->tof, nto);
		tfree(&tl);
		break;
	case Oinds:
		if(right->addable < Ralways){
			if(left->addable >= Rcant)
				left = eacom(left, &tl, nil);
		}else if(left->temps <= right->temps){
			right = ecom(&right->src, talloc(&tr, right->ty, nil), right);
			if(left->addable >= Rcant)
				left = eacom(left, &tl, nil);
		}else{
			left = eacom(left, &tl, nil);
			right = ecom(&right->src, talloc(&tr, right->ty, nil), right);
		}
		genop(&n->src, op, left, right, nto);
		tfree(&tl);
		tfree(&tr);
		break;
	case Osnd:
		if(right->addable < Rcant){
			if(left->addable >= Rcant)
				left = eacom(left, &tl, nto);
		}else if(left->temps < right->temps){
			right = eacom(right, &tr, nto);
			if(left->addable >= Rcant)
				left = eacom(left, &tl, nil);
		}else{
			left = eacom(left, &tl, nto);
			right = eacom(right, &tr, nil);
		}
		p = genrawop(&n->src, ISEND, right, nil, left);
		p->m.offset = n->ty->size;	/* for optimizer */
		if(nto != nil)
			genmove(src, Mas, right->ty, right, nto);
		tfree(&tl);
		tfree(&tr);
		break;
	case Orcv:
		if(nto == nil){
			ecom(&n->src, talloc(&tto, n->ty, nil), n);
			tfree(&tto);
			return nil;
		}
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nto);
		if(left->ty->kind == Tchan){
			p = genrawop(src, IRECV, left, nil, nto);
			p->m.offset = n->ty->size;	/* for optimizer */
		}else{
			recvacom(src, nto, n);
		}
		tfree(&tl);
		break;
	case Ocons:
		/*
		 * another temp which can go with analysis
		 */
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nil);
		if(!sameaddr(right, nto)){
			ecom(&right->src, talloc(&tto, n->ty, nto), right);
			genmove(src, Mcons, left->ty, left, &tto);
			if(!sameaddr(&tto, nto))
				genmove(src, Mas, nto->ty, &tto, nto);
		}else
			genmove(src, Mcons, left->ty, left, nto);
		tfree(&tl);
		tfree(&tto);
		break;
	case Ohd:
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nto);
		genmove(src, Mhd, nto->ty, left, nto);
		tfree(&tl);
		break;
	case Otl:
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nto);
		genmove(src, Mtl, left->ty, left, nto);
		tfree(&tl);
		break;
	case Otuple:
		if((tn = tupblk(n)) != nil){
			tn->ty = n->ty;
			genmove(src, Mas, n->ty, tn, nto);
			break;
		}
		tupcom(nto, n);
		break;
	case Oadd:
	case Osub:
	case Omul:
	case Odiv:
	case Omod:
	case Oand:
	case Oor:
	case Oxor:
	case Olsh:
	case Orsh:
	case Oexp:
		/*
		 * check for 2 operand forms
		 */
		if(sameaddr(nto, left)){
			if(right->addable >= Rcant)
				right = eacom(right, &tr, nto);
			genop(src, op, right, nil, nto);
			tfree(&tr);
			break;
		}

		if(opcommute[op] && sameaddr(nto, right) && n->ty != tstring){
			if(left->addable >= Rcant)
				left = eacom(left, &tl, nto);
			genop(src, opcommute[op], left, nil, nto);
			tfree(&tl);
			break;
		}

		if(right->addable < left->addable
		&& opcommute[op]
		&& n->ty != tstring){
			op = opcommute[op];
			left = right;
			right = n->left;
		}
		if(left->addable < Ralways){
			if(right->addable >= Rcant)
				right = eacom(right, &tr, nto);
		}else if(right->temps <= left->temps){
			left = ecom(&left->src, talloc(&tl, left->ty, nto), left);
			if(right->addable >= Rcant)
				right = eacom(right, &tr, nil);
		}else{
			right = eacom(right, &tr, nto);
			left = ecom(&left->src, talloc(&tl, left->ty, nil), left);
		}

		/*
		 * check for 2 operand forms
		 */
		if(sameaddr(nto, left))
			genop(src, op, right, nil, nto);
		else if(opcommute[op] && sameaddr(nto, right) && n->ty != tstring)
			genop(src, opcommute[op], left, nil, nto);
		else
			genop(src, op, right, left, nto);
		tfree(&tl);
		tfree(&tr);
		break;
	case Oaddas:
	case Osubas:
	case Omulas:
	case Odivas:
	case Omodas:
	case Oexpas:
	case Oandas:
	case Ooras:
	case Oxoras:
	case Olshas:
	case Orshas:
		if(left->op == Oinds){
			indsascom(src, nto, n);
			break;
		}
		if(right->addable < Rcant){
			if(left->addable >= Rcant)
				left = eacom(left, &tl, nto);
		}else if(left->temps < right->temps){
			right = eacom(right, &tr, nto);
			if(left->addable >= Rcant)
				left = eacom(left, &tl, nil);
		}else{
			left = eacom(left, &tl, nto);
			right = eacom(right, &tr, nil);
		}
		genop(&n->src, op, right, nil, left);
		if(nto != nil)
			genmove(src, Mas, left->ty, left, nto);
		tfree(&tl);
		tfree(&tr);
		break;
	case Olen:
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nto);
		op = -1;
		t = left->ty;
		if(t == tstring)
			op = ILENC;
		else if(t->kind == Tarray)
			op = ILENA;
		else if(t->kind == Tlist)
			op = ILENL;
		else
			fatal("can't len %n", n);
		genrawop(src, op, left, nil, nto);
		tfree(&tl);
		break;
	case Oneg:
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nto);
		genop(&n->src, op, left, nil, nto);
		tfree(&tl);
		break;
	case Oinc:
	case Odec:
		if(left->op == Oinds){
			indsascom(src, nto, n);
			break;
		}
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nil);
		if(nto != nil)
			genmove(src, Mas, left->ty, left, nto);
		if(right->addable >= Rcant)
			fatal("inc/dec amount not addressable: %n", n);
		genop(&n->src, op, right, nil, left);
		tfree(&tl);
		break;
	case Ospawn:
		if(left->left->op == Oind)
			fpcall(&n->src, op, left, nto);
		else
			callcom(&n->src, op, left, nto);
		break;
	case Oraise:
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nil);
		genrawop(&n->src, IRAISE, left, nil, nil);
		tfree(&tl);
		break;
	case Ocall:
		if(left->op == Oind)
			fpcall(esrc(src, &n->src, nto), op, n, nto);
		else
			callcom(esrc(src, &n->src, nto), op, n, nto);
		break;
	case Oref:
		t = left->ty;
		if(left->op == Oname && left->decl->store == Dfn || left->op == Omdot && left->right->op == Oname && left->right->decl->store == Dfn){	/* create a function reference */
			Decl *d;
			Node *mod, *ind;

			d = left->decl;
			if(left->op == Omdot){
				d = left->right->decl;
				mod = left->left;
			}
			else if(d->eimport != nil)
				mod = d->eimport;
			else{
				mod = rewrite(mkn(Oself, nil, nil));
				addiface(nil, d);
			}
			sumark(mod);
			talloc(&tto, n->ty, nto);
			genrawop(src, INEW, mktn(usetype(tfnptr)), nil, &tto);
			tr.src = *src;
			tr.op = Oind;
			tr.left = &tto;
			tr.right = nil;
			tr.ty = tany;
			sumark(&tr);
			ecom(src, &tr, mod);
			ind = mkunary(Oind, mkbin(Oadd, dupn(0, src, &tto), mkconst(src, IBY2WD)));
			ind->ty = ind->left->ty = ind->left->right->ty = tint;
			tr.op = Oas;
			tr.left = ind;
			tr.right = mkdeclname(src, d);
			tr.ty = tr.right->ty = tint;
			sumark(&tr);
			tr.right->addable = mod->op == Oself && newfnptr ? Rnoff : Roff;
			ecom(src, nil, &tr);
			if(!sameaddr(&tto, nto))
				genmove(src, Mas, n->ty, &tto, nto);
			tfree(&tto);
			break;
		}
		if(left->op == Oname && left->decl->store == Dtype){
			genrawop(src, INEW, mktn(t), nil, nto);
			break;
		}
		if(t->kind == Tadt && t->tags != nil){
			pickdupcom(src, nto, left);
			break;
		}

		tt = t;
		if(left->op == Oconst && left->decl->store == Dtag)
			t = left->decl->ty->tof;
		/*
		 * could eliminate temp if to does not occur
		 * in tuple initializer
		 */
		talloc(&tto, n->ty, nto);
		genrawop(src, INEW, mktn(t), nil, &tto);
		tr.op = Oind;
		tr.left = &tto;
		tr.right = nil;
		tr.ty = tt;
		sumark(&tr);
		ecom(src, &tr, left);
		if(!sameaddr(&tto, nto))
			genmove(src, Mas, n->ty, &tto, nto);
		tfree(&tto);
		break;
	case Oload:
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nto);
		talloc(&tr, tint, nil);
		if(LDT)
			genrawop(src, ILOAD, left, right, nto);
		else{
			genrawop(src, ILEA, right, nil, &tr);
			genrawop(src, ILOAD, left, &tr, nto);
		}
		tfree(&tl);
		tfree(&tr);
		break;
	case Ocast:
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nto);
		t = left->ty;
		if(t->kind == Tfix || n->ty->kind == Tfix){
			op = casttab[t->kind][n->ty->kind];
			if(op == ICVTXX)
				genfixcastop(src, op, left, nto);
			else{
				tn = sumark(mkrconst(src, scale2(t, n->ty)));
				genrawop(src, op, left, tn, nto);
			}
		}
		else
			genrawop(src, casttab[t->kind][n->ty->kind], left, nil, nto);
		tfree(&tl);
		break;
	case Oarray:
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nto);
		genrawop(esrc(src, &left->src, nto), arrayz ? INEWAZ : INEWA, left, mktn(n->ty->tof), nto);
		if(right != nil)
			arraycom(nto, right);
		tfree(&tl);
		break;
	case Oslice:
		tn = right->right;
		right = right->left;

		/*
		 * make the left node of the slice directly addressable
		 * therefore, if it's len is taken (via tn),
		 * left's tree won't be rewritten
		 */
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nil);

		if(tn->op == Onothing){
			tn = mkn(Olen, left, nil);
			tn->src = *src;
			tn->ty = tint;
			sumark(tn);
		}
		if(tn->addable < Ralways){
			if(right->addable >= Rcant)
				right = eacom(right, &tr, nil);
		}else if(right->temps <= tn->temps){
			tn = ecom(&tn->src, talloc(&ttn, tn->ty, nil), tn);
			if(right->addable >= Rcant)
				right = eacom(right, &tr, nil);
		}else{
			right = eacom(right, &tr, nil);
			tn = ecom(&tn->src, talloc(&ttn, tn->ty, nil), tn);
		}
		op = ISLICEA;
		if(nto->ty == tstring)
			op = ISLICEC;

		/*
		 * overwrite the destination last,
		 * since it might be used in computing the slice bounds
		 */
		if(!sameaddr(left, nto))
			ecom(&left->src, nto, left);

		genrawop(src, op, right, tn, nto);
		tfree(&tl);
		tfree(&tr);
		tfree(&ttn);
		break;
	case Oindx:
		if(right->addable < Rcant){
			if(left->addable >= Rcant)
				left = eacom(left, &tl, nto);
		}else if(left->temps < right->temps){
			right = eacom(right, &tr, nto);
			if(left->addable >= Rcant)
				left = eacom(left, &tl, nil);
		}else{
			left = eacom(left, &tl, nto);
			right = eacom(right, &tr, nil);
		}
		if(nto->addable >= Ralways)
			nto = ecom(src, talloc(&tto, nto->ty, nil), nto);
		op = IINDX;
		switch(left->ty->tof->size){
		case IBY2LG:
			op = IINDL;
			if(left->ty->tof == treal)
				op = IINDF;
			break;
		case IBY2WD:
			op = IINDW;
			break;
		case 1:
			op = IINDB;
			break;
		}
		genrawop(src, op, left, nto, right);
		// array[] of {....} [index] frees array too early (before index value used)
		// function(...) [index] frees array too early (before index value used)
		if(tl.decl != nil)
			tfreelater(&tl);
		else
			tfree(&tl);
		tfree(&tr);
		tfree(&tto);
		break;
	case Oind:
		n = eacom(n, &tl, nto);
		genmove(src, Mas, n->ty, n, nto);
		tfree(&tl);
		break;
	case Onot:
	case Oandand:
	case Ooror:
	case Oeq:
	case Oneq:
	case Olt:
	case Oleq:
	case Ogt:
	case Ogeq:
		p = bcom(n, 1, nil);
		genmove(src, Mas, tint, sumark(mkconst(src, 1)), nto);
		pp = genrawop(src, IJMP, nil, nil, nil);
		patch(p, nextinst());
		genmove(src, Mas, tint, sumark(mkconst(src, 0)), nto);
		patch(pp, nextinst());
		break;
	case Oself:
		if(newfnptr){
			if(nto != nil)
				genrawop(src, ISELF, nil, nil, nto);
			break;
		}
		tn = sumark(mkdeclname(src, selfdecl));
		p = genbra(src, Oneq, tn, sumark(mkdeclname(src, nildecl)));
		n->op = Oload;
		ecom(src, tn, n);
		patch(p, nextinst());
		genmove(src, Mas, n->ty, tn, nto);
		break;
	}
	return nto;
}

/*
 * compile exp n to yield an addressable expression
 * use reg to build a temporary; if t is a temp, it is usable
 * if dangle leaves the address dangling, generate into a temporary
 *	this should only happen with arrays
 *
 * note that 0adr's are strange as they are only used
 * for calculating the addresses of fields within adt's.
 * therefore an Oind is the parent or grandparent of the Oadr,
 * and we pick off all of the cases where Oadr's argument is not
 * addressable by looking from the Oind.
 */
Node*
eacom(Node *n, Node *reg, Node *t)
{
	Node *left, *tn;

	if(n->op == Ocomma){
		tn = n->left->left;
		ecom(&n->left->src, nil, n->left);
		n = eacom(n->right, reg, t);
		tfree(tn);
		return n;
	}

	if(debug['e'] || debug['E'])
		print("eacom: %n\n", n);

	left = n->left;
	if(n->op != Oind){
		ecom(&n->src, talloc(reg, n->ty, t), n);
		reg->src = n->src;
		return reg;
	}
		
	if(left->op == Oadd && left->right->op == Oconst){
		if(left->left->op == Oadr){
			left->left->left = eacom(left->left->left, reg, t);
			sumark(n);
			if(n->addable >= Rcant)
				fatal("eacom can't make node addressable: %n", n);
			return n;
		}
		talloc(reg, left->left->ty, t);
		ecom(&left->left->src, reg, left->left);
		left->left->decl = reg->decl;
		left->left->addable = Rreg;
		left->left = reg;
		left->addable = Raadr;
		n->addable = Radr;
	}else if(left->op == Oadr){
		talloc(reg, left->left->ty, t);
		ecom(&left->left->src, reg, left->left);

		/*
		 * sleaze: treat the temp as the type of the field, not the enclosing structure
		 */
		reg->ty = n->ty;
		reg->src = n->src;
		return reg;
	}else{
		talloc(reg, left->ty, t);
		ecom(&left->src, reg, left);
		n->left = reg;
		n->addable = Radr;
	}
	return n;
}

/*
 * compile an assignment to an array slice
 */
Node*
slicelcom(Src *src, Node *nto, Node *n)
{
	Node *left, *right, *v;
	Node tl, tr, tv, tu;

	tl.decl = nil;
	tr.decl = nil;
	tv.decl = nil;
	tu.decl = nil;

	left = n->left->left;
	right = n->left->right->left;
	v = n->right;
	if(right->addable < Ralways){
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nto);
	}else if(left->temps <= right->temps){
		right = ecom(&right->src, talloc(&tr, right->ty, nto), right);
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nil);
	}else{
		left = eacom(left, &tl, nil);		/* dangle on right and v */
		right = ecom(&right->src, talloc(&tr, right->ty, nil), right);
	}

	switch(n->op){
	case Oas:
		if(v->addable >= Rcant)
			v = eacom(v, &tv, nil);
		break;
	}

	genrawop(&n->src, ISLICELA, v, right, left);
	if(nto != nil)
		genmove(src, Mas, n->ty, left, nto);
	tfree(&tl);
	tfree(&tv);
	tfree(&tr);
	tfree(&tu);
	return nto;
}

/*
 * compile an assignment to a string location
 */
Node*
indsascom(Src *src, Node *nto, Node *n)
{
	Node *left, *right, *u, *v;
	Node tl, tr, tv, tu;

	tl.decl = nil;
	tr.decl = nil;
	tv.decl = nil;
	tu.decl = nil;

	left = n->left->left;
	right = n->left->right;
	v = n->right;
	if(right->addable < Ralways){
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nto);
	}else if(left->temps <= right->temps){
		right = ecom(&right->src, talloc(&tr, right->ty, nto), right);
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nil);
	}else{
		left = eacom(left, &tl, nil);		/* dangle on right and v */
		right = ecom(&right->src, talloc(&tr, right->ty, nil), right);
	}

	switch(n->op){
	case Oas:
		if(v->addable >= Rcant)
			v = eacom(v, &tv, nil);
		break;
	case Oinc:
	case Odec:
		if(v->addable >= Rcant)
			fatal("inc/dec amount not addable");
		u = talloc(&tu, tint, nil);
		genop(&n->left->src, Oinds, left, right, u);
		if(nto != nil)
			genmove(src, Mas, n->ty, u, nto);
		nto = nil;
		genop(&n->src, n->op, v, nil, u);
		v = u;
		break;
	case Oaddas:
	case Osubas:
	case Omulas:
	case Odivas:
	case Omodas:
	case Oexpas:
	case Oandas:
	case Ooras:
	case Oxoras:
	case Olshas:
	case Orshas:
		if(v->addable >= Rcant)
			v = eacom(v, &tv, nil);
		u = talloc(&tu, tint, nil);
		genop(&n->left->src, Oinds, left, right, u);
		genop(&n->src, n->op, v, nil, u);
		v = u;
		break;
	}

	genrawop(&n->src, IINSC, v, right, left);
	tfree(&tl);
	tfree(&tv);
	tfree(&tr);
	tfree(&tu);
	if(nto != nil)
		genmove(src, Mas, n->ty, v, nto);
	return nto;
}

void
callcom(Src *src, int op, Node *n, Node *ret)
{
	Node frame, tadd, toff, pass, *a, *mod, *ind, *nfn, *args, tmod, tind, *tn;
	Inst *in,*p;
	Decl *d, *callee;
	long off;
	int iop;

	args = n->right;
	nfn = n->left;
	switch(nfn->op){
		case Odot:
			callee = nfn->right->decl;
			nfn->addable = Rpc;
			break;
		case Omdot:
			callee = nfn->right->decl;
			break;
		case Oname:
			callee = nfn->decl;
			break;
		default:
			callee = nil;
			fatal("bad call op in callcom");
	}
	if(nfn->addable != Rpc && nfn->addable != Rmpc)
		fatal("can't gen call addresses");
	if(nfn->ty->tof != tnone && ret == nil){
		ecom(src, talloc(&tmod, nfn->ty->tof, nil), n);
		tfree(&tmod);
		return;
	}
	if(ispoly(callee))
		addfnptrs(callee, 0);
	if(nfn->ty->varargs){
		nfn->decl = dupdecl(nfn->right->decl);
		nfn->decl->desc = gendesc(nfn->right->decl, idoffsets(nfn->ty->ids, MaxTemp, MaxAlign), nfn->ty->ids);
	}

	talloc(&frame, tint, nil);

	mod = nfn->left;
	ind = nfn->right;
	tmod.decl = tind.decl = nil;
	if(nfn->addable == Rmpc){
		if(mod->addable >= Rcant)
			mod = eacom(mod, &tmod, nil);		/* dangle always */
		if(ind->op != Oname && ind->addable >= Ralways){
			talloc(&tind, ind->ty, nil);
			ecom(&ind->src, &tind, ind);
			ind = &tind;
		}
		else if(ind->decl != nil && ind->decl->store != Darg)
			ind->addable = Roff;
	}

	/*
	 * stop nested uncalled frames
	 * otherwise exception handling very complicated
	 */
	for(a = args; a != nil; a = a->right){
		if(hascall(a->left)){
			tn = mkn(0, nil, nil);
			talloc(tn, a->left->ty, nil);
			ecom(&a->left->src, tn, a->left);
			a->left = tn;
			tn->flags |= TEMP;
		}
	}

	/*
	 * allocate the frame
	 */
	if(nfn->addable == Rmpc && !nfn->ty->varargs){
		genrawop(src, IMFRAME, mod, ind, &frame);
	}else if(nfn->op == Odot){
		genrawop(src, IFRAME, nfn->left, nil, &frame);
	}else{
		in = genrawop(src, IFRAME, nil, nil, &frame);
		in->sm = Adesc;
		in->s.decl = nfn->decl;
	}

	/*
	 * build a fake node for the argument area
	 */
	toff = znode;
	tadd = znode;
	pass = znode;
	toff.op = Oconst;
	toff.addable = Rconst;
	toff.ty = tint;
	tadd.op = Oadd;
	tadd.addable = Raadr;
	tadd.left = &frame;
	tadd.right = &toff;
	tadd.ty = tint;
	pass.op = Oind;
	pass.addable = Radr;
	pass.left = &tadd;

	/*
	 * compile all the args
	 */
	d = nfn->ty->ids;
	off = 0;
	for(a = args; a != nil; a = a->right){
		off = d->offset;
		toff.val = off;
		if(d->ty->kind == Tpoly)
			pass.ty = a->left->ty;
		else
			pass.ty = d->ty;
		ecom(&a->left->src, &pass, a->left);
		d = d->next;
		if(a->left->flags & TEMP)
			tfree(a->left);
	}
	if(off > maxstack)
		maxstack = off;

	/*
	 * pass return value
	 */
	if(ret != nil){
		toff.val = REGRET*IBY2WD;
		pass.ty = nfn->ty->tof;
		p = genrawop(src, ILEA, ret, nil, &pass);
		p->m.offset = ret->ty->size;	/* for optimizer */
	}

	/*
	 * call it
	 */
	if(nfn->addable == Rmpc){
		iop = IMCALL;
		if(op == Ospawn)
			iop = IMSPAWN;
		genrawop(src, iop, &frame, ind, mod);
		tfree(&tmod);
		tfree(&tind);
	}else if(nfn->op == Odot){
		iop = ICALL;
		if(op == Ospawn)
			iop = ISPAWN;
		genrawop(src, iop, &frame, nil, nfn->right);
	}else{
		iop = ICALL;
		if(op == Ospawn)
			iop = ISPAWN;
		in = genrawop(src, iop, &frame, nil, nil);
		in->d.decl = nfn->decl;
		in->dm = Apc;
	}
	tfree(&frame);
}

/*
 * initialization code for arrays
 * a must be addressable (< Rcant)
 */
void
arraycom(Node *a, Node *elems)
{
	Node tindex, fake, tmp, ri, *e, *n, *q, *body, *wild;
	Inst *top, *out;
	/* Case *c; */

	if(debug['A'])
		print("arraycom: %n %n\n", a, elems);

	/* c = elems->ty->cse; */
	/* don't use c->wild in case we've been inlined */
	wild = nil;
	for(e = elems; e != nil; e = e->right)
		for(q = e->left->left; q != nil; q = q->right)
			if(q->left->op == Owild)
				wild = e->left;
	if(wild != nil)
		arraydefault(a, wild->right);

	tindex = znode;
	fake = znode;
	talloc(&tmp, tint, nil);
	tindex.op = Oindx;
	tindex.addable = Rcant;
	tindex.left = a;
	tindex.right = nil;
	tindex.ty = tint;
	fake.op = Oind;
	fake.addable = Radr;
	fake.left = &tmp;
	fake.ty = a->ty->tof;

	for(e = elems; e != nil; e = e->right){
		/*
		 * just duplicate the initializer for Oor
		 */
		for(q = e->left->left; q != nil; q = q->right){
			if(q->left->op == Owild)
				continue;
	
			body = e->left->right;
			if(q->right != nil)
				body = dupn(0, &nosrc, body);
			top = nil;
			out = nil;
			ri.decl = nil;
			if(q->left->op == Orange){
				/*
				 * for(i := q.left.left; i <= q.left.right; i++)
				 */
				talloc(&ri, tint, nil);
				ri.src = q->left->src;
				ecom(&q->left->src, &ri, q->left->left);
	
				/* i <= q.left.right; */
				n = mkn(Oleq, &ri, q->left->right);
				n->src = q->left->src;
				n->ty = tint;
				top = nextinst();
				out = bcom(n, 1, nil);
	
				tindex.right = &ri;
			}else{
				tindex.right = q->left;
			}
	
			tindex.addable = Rcant;
			tindex.src = q->left->src;
			ecom(&tindex.src, &tmp, &tindex);
	
			ecom(&body->src, &fake, body);
	
			if(q->left->op == Orange){
				/* i++ */
				n = mkbin(Oinc, &ri, sumark(mkconst(&ri.src, 1)));
				n->ty = tint;
				n->addable = Rcant;
				ecom(&n->src, nil, n);
	
				/* jump to test */
				patch(genrawop(&q->left->src, IJMP, nil, nil, nil), top);
				patch(out, nextinst());
				tfree(&ri);
			}
		}
	}
	tfree(&tmp);
}

/*
 * default initialization code for arrays.
 * compiles to
 *	n = len a;
 *	while(n){
 *		n--;
 *		a[n] = elem;
 *	}
 */
void
arraydefault(Node *a, Node *elem)
{
	Inst *out, *top;
	Node n, e, *t;

	if(debug['A'])
		print("arraydefault: %n %n\n", a, elem);

	t = mkn(Olen, a, nil);
	t->src = elem->src;
	t->ty = tint;
	t->addable = Rcant;
	talloc(&n, tint, nil);
	n.src = elem->src;
	ecom(&t->src, &n, t);

	top = nextinst();
	out = bcom(&n, 1, nil);

	t = mkbin(Odec, &n, sumark(mkconst(&elem->src, 1)));
	t->ty = tint;
	t->addable = Rcant;
	ecom(&t->src, nil, t);

	e.decl = nil;
	if(elem->addable >= Rcant)
		elem = eacom(elem, &e, nil);

	t = mkn(Oindx, a, &n);
	t->src = elem->src;
	t = mkbin(Oas, mkunary(Oind, t), elem);
	t->ty = elem->ty;
	t->left->ty = elem->ty;
	t->left->left->ty = tint;
	sumark(t);
	ecom(&t->src, nil, t);

	patch(genrawop(&t->src, IJMP, nil, nil, nil), top);

	tfree(&n);
	tfree(&e);
	patch(out, nextinst());
}

void
tupcom(Node *nto, Node *n)
{
	Node tadr, tadd, toff, fake, *e;
	Decl *d;

	if(debug['Y'])
		print("tupcom %n\nto %n\n", n, nto);

	/*
	 * build a fake node for the tuple
	 */
	toff = znode;
	tadd = znode;
	fake = znode;
	tadr = znode;
	toff.op = Oconst;
	toff.ty = tint;
	tadr.op = Oadr;
	tadr.left = nto;
	tadr.ty = tint;
	tadd.op = Oadd;
	tadd.left = &tadr;
	tadd.right = &toff;
	tadd.ty = tint;
	fake.op = Oind;
	fake.left = &tadd;
	sumark(&fake);
	if(fake.addable >= Rcant)
		fatal("tupcom: bad value exp %n", &fake);

	/*
	 * compile all the exps
	 */
	d = n->ty->ids;
	for(e = n->left; e != nil; e = e->right){
		toff.val = d->offset;
		fake.ty = d->ty;
		ecom(&e->left->src, &fake, e->left);
		d = d->next;
	}
}

void
tuplcom(Node *n, Node *nto)
{
	Node tadr, tadd, toff, fake, tas, *e, *as;
	Decl *d;

	if(debug['Y'])
		print("tuplcom %n\nto %n\n", n, nto);

	/*
	 * build a fake node for the tuple
	 */
	toff = znode;
	tadd = znode;
	fake = znode;
	tadr = znode;
	toff.op = Oconst;
	toff.ty = tint;
	tadr.op = Oadr;
	tadr.left = n;
	tadr.ty = tint;
	tadd.op = Oadd;
	tadd.left = &tadr;
	tadd.right = &toff;
	tadd.ty = tint;
	fake.op = Oind;
	fake.left = &tadd;
	sumark(&fake);
	if(fake.addable >= Rcant)
		fatal("tuplcom: bad value exp for %n", &fake);

	/*
	 * compile all the exps
	 */
	d = nto->ty->ids;
	if(nto->ty->kind == Tadtpick)
		d = nto->ty->tof->ids->next;
	for(e = nto->left; e != nil; e = e->right){
		as = e->left;
		if(as->op != Oname || as->decl != nildecl){
			toff.val = d->offset;
			fake.ty = d->ty;
			fake.src = as->src;
			if(as->addable < Rcant)
				genmove(&as->src, Mas, d->ty, &fake, as);
			else{
				tas.op = Oas;
				tas.ty = d->ty;
				tas.src = as->src;
				tas.left = as;
				tas.right = &fake;
				tas.addable = Rcant;
				ecom(&tas.src, nil, &tas);
			}
		}
		d = d->next;
	}
}

void
tuplrcom(Node *n, Node *nto)
{
	Node *s, *d, tas;
	Decl *de;

	de = nto->ty->ids;
	for(s = n->left, d = nto->left; s != nil && d != nil; s = s->right, d = d->right){
		if(d->left->op != Oname || d->left->decl != nildecl){
			tas.op = Oas;
			tas.ty = de->ty;
			tas.src = s->left->src;
			tas.left = d->left;
			tas.right = s->left;
			sumark(&tas);
			ecom(&tas.src, nil, &tas);
		}
		de = de->next;
	}
	if(s != nil || d != nil)
		fatal("tuplrcom");
}

/*
 * boolean compiler
 * fall through when condition == true
 */
Inst*
bcom(Node *n, int iftrue, Inst *b)
{
	Inst *bb;
	Node tl, tr, *t, *left, *right, *tn;
	int op;

	if(n->op == Ocomma){
		tn = n->left->left;
		ecom(&n->left->src, nil, n->left);
		bb = bcom(n->right, iftrue, b);
		tfree(tn);
		return bb;
	}

	if(debug['b'])
		print("bcom %n %d\n", n, iftrue);

	left = n->left;
	right = n->right;
	op = n->op;
	
	switch(op){
	case Onothing:
		return b;
	case Onot:
		return bcom(n->left, !iftrue, b);
	case Oandand:
		if(!iftrue)
			return oror(n, iftrue, b);
		return andand(n, iftrue, b);
	case Ooror:
		if(!iftrue)
			return andand(n, iftrue, b);
		return oror(n, iftrue, b);
	case Ogt:
	case Ogeq:
	case Oneq:
	case Oeq:
	case Olt:
	case Oleq:
		break;
	default:
		if(n->ty->kind == Tint){
			right = mkconst(&n->src, 0);
			right->addable = Rconst;
			left = n;
			op = Oneq;
			break;
		}
		fatal("can't bcom %n", n);
		return b;
	}

	if(iftrue)
		op = oprelinvert[op];

	if(left->addable < right->addable){
		t = left;
		left = right;
		right = t;
		op = opcommute[op];
	}

	tl.decl = nil;
	tr.decl = nil;
	if(right->addable < Ralways){
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nil);
	}else if(left->temps <= right->temps){
		right = ecom(&right->src, talloc(&tr, right->ty, nil), right);
		if(left->addable >= Rcant)
			left = eacom(left, &tl, nil);
	}else{
		left = eacom(left, &tl, nil);
		right = ecom(&right->src, talloc(&tr, right->ty, nil), right);
	}
	bb = genbra(&n->src, op, left, right);
	bb->branch = b;
	tfree(&tl);
	tfree(&tr);
	return bb;
}

Inst*
andand(Node *n, int iftrue, Inst *b)
{
	if(debug['b'])
		print("andand %n\n", n);
	b = bcom(n->left, iftrue, b);
	b = bcom(n->right, iftrue, b);
	return b;
}

Inst*
oror(Node *n, int iftrue, Inst *b)
{
	Inst *bb;

	if(debug['b'])
		print("oror %n\n", n);
	bb = bcom(n->left, !iftrue, nil);
	b = bcom(n->right, iftrue, b);
	patch(bb, nextinst());
	return b;
}

/*
 * generate code for a recva expression
 * this is just a hacked up small alt
 */
void
recvacom(Src *src, Node *nto, Node *n)
{
	Label *labs;
	Case *c;
	Node which, tab, off, add, adr, slot, *left;
	Type *talt;
	Inst *p;

	left = n->left;

	labs = allocmem(1 * sizeof *labs);
	labs[0].isptr = left->addable >= Rcant;
	c = allocmem(sizeof *c);
	c->nlab = 1;
	c->labs = labs;
	talt = mktalt(c);

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
	 * gen the channel
	 * this sleaze is lying to the garbage collector
	 */
	off.val = 2*IBY2WD;
	if(left->addable < Rcant)
		genmove(src, Mas, tint, left, &slot);
	else{
		slot.ty = left->ty;
		ecom(src, &slot, left);
		slot.ty = nil;
	}

	/*
	 * gen the value
	 */
	off.val += IBY2WD;
	p = genrawop(&left->src, ILEA, nto, nil, &slot);
	p->m.offset = nto->ty->size;	/* for optimizer */

	/*
	 * number of senders and receivers
	 */
	off.val = 0;
	genmove(src, Mas, tint, sumark(mkconst(src, 0)), &slot);
	off.val += IBY2WD;
	genmove(src, Mas, tint, sumark(mkconst(src, 1)), &slot);
	off.val += IBY2WD;

	p = genrawop(src, IALT, &tab, nil, &which);
	p->m.offset = talt->size;	/* for optimizer */
	tfree(&which);
	tfree(&tab);
}

/*
 * generate code to duplicate an adt with pick fields
 * this is just a hacked up small pick
 * n is Oind(exp)
 */
void
pickdupcom(Src *src, Node *nto, Node *n)
{
	Node *start, *stop, *node, *orig, *dest, tmp, clab;
	Case *c;
	Inst *j, *jmps, *wild;
	Label *labs;
	Decl *d, *tg, *stg;
	Type *t;
	int i, nlab;
	char buf[32];

	if(n->op != Oind)
		fatal("pickdupcom not Oind: %n" ,n);

	t = n->ty;
	nlab = t->decl->tag;

	/*
	 * generate global which has case labels
	 */
	seprint(buf, buf+sizeof(buf), ".c%d", nlabel++);
	d = mkids(src, enter(buf, 0), mktype(&src->start, &src->stop, Tcase, nil, nil), nil);
	d->init = mkdeclname(src, d);

	clab.addable = Rmreg;
	clab.left = nil;
	clab.right = nil;
	clab.op = Oname;
	clab.ty = d->ty;
	clab.decl = d;

	/*
	 * generate a temp to hold the real value
	 * then generate a case on the tag
	 */
	orig = n->left;
	talloc(&tmp, orig->ty, nil);
	ecom(src, &tmp, orig);
	orig = mkunary(Oind, &tmp);
	orig->ty = tint;
	sumark(orig);

	dest = mkunary(Oind, nto);
	dest->ty = nto->ty->tof;
	sumark(dest);

	genrawop(src, ICASE, orig, nil, &clab);

	labs = allocmem(nlab * sizeof *labs);

	i = 0;
	jmps = nil;
	for(tg = t->tags; tg != nil; tg = tg->next){
		stg = tg;
		for(; tg->next != nil; tg = tg->next)
			if(stg->ty != tg->next->ty)
				break;
		start = sumark(simplify(mkdeclname(src, stg)));
		stop = start;
		node = start;
		if(stg != tg){
			stop = sumark(simplify(mkdeclname(src, tg)));
			node = mkbin(Orange, start, stop);
		}

		labs[i].start = start;
		labs[i].stop = stop;
		labs[i].node = node;
		labs[i++].inst = nextinst();

		genrawop(src, INEW, mktn(tg->ty->tof), nil, nto);
		genmove(src, Mas, tg->ty->tof, orig, dest);

		j = genrawop(src, IJMP, nil, nil, nil);
		j->branch = jmps;
		jmps = j;
	}

	/*
	 * this should really be a runtime error
	 */
	wild = genrawop(src, IJMP, nil, nil, nil);
	patch(wild, wild);

	patch(jmps, nextinst());
	tfree(&tmp);

	if(i > nlab)
		fatal("overflowed label tab for pickdupcom");

	c = allocmem(sizeof *c);
	c->nlab = i;
	c->nsnd = 0;
	c->labs = labs;
	c->iwild = wild;

	d->ty->cse = c;
	usetype(d->ty);
	installids(Dglobal, d);
}

/*
 * see if name n occurs anywhere in e
 */
int
tupaliased(Node *n, Node *e)
{
	for(;;){
		if(e == nil)
			return 0;
		if(e->op == Oname && e->decl == n->decl)
			return 1;
		if(tupaliased(n, e->left))
			return 1;
		e = e->right;
	}
}

/*
 * see if any name in n occurs anywere in e
 */
int
tupsaliased(Node *n, Node *e)
{
	for(;;){
		if(n == nil)
			return 0;
		if(n->op == Oname && tupaliased(n, e))
			return 1;
		if(tupsaliased(n->left, e))
			return 1;
		n = n->right;
	}
}

/*
 * put unaddressable constants in the global data area
 */
Decl*
globalconst(Node *n)
{
	Decl *d;
	Sym *s;
	char buf[32];

	seprint(buf, buf+sizeof(buf), ".i.%.8lux", (long)n->val);
	s = enter(buf, 0);
	d = s->decl;
	if(d == nil){
		d = mkids(&n->src, s, tint, nil);
		installids(Dglobal, d);
		d->init = n;
		d->refs++;
	}
	return d;
}

Decl*
globalBconst(Node *n)
{
	Decl *d;
	Sym *s;
	char buf[32];

	seprint(buf, buf+sizeof(buf), ".B.%.8lux.%8lux", (long)(n->val>>32), (long)n->val);

	s = enter(buf, 0);
	d = s->decl;
	if(d == nil){
		d = mkids(&n->src, s, tbig, nil);
		installids(Dglobal, d);
		d->init = n;
		d->refs++;
	}
	return d;
}

Decl*
globalbconst(Node *n)
{
	Decl *d;
	Sym *s;
	char buf[32];

	seprint(buf, buf+sizeof(buf), ".b.%.2lux", (long)n->val & 0xff);
	s = enter(buf, 0);
	d = s->decl;
	if(d == nil){
		d = mkids(&n->src, s, tbyte, nil);
		installids(Dglobal, d);
		d->init = n;
		d->refs++;
	}
	return d;
}

Decl*
globalfconst(Node *n)
{
	Decl *d;
	Sym *s;
	char buf[32];
	ulong dv[2];

	dtocanon(n->rval, dv);
	seprint(buf, buf+sizeof(buf), ".f.%.8lux.%8lux", dv[0], dv[1]);
	s = enter(buf, 0);
	d = s->decl;
	if(d == nil){
		d = mkids(&n->src, s, treal, nil);
		installids(Dglobal, d);
		d->init = n;
		d->refs++;
	}
	return d;
}

Decl*
globalsconst(Node *n)
{
	Decl *d;
	Sym *s;

	s = n->decl->sym;
	d = s->decl;
	if(d == nil){
		d = mkids(&n->src, s, tstring, nil);
		installids(Dglobal, d);
		d->init = n;
	}
	d->refs++;
	return d;
}

static Node*
subst(Decl *d, Node *e, Node *n)
{
	if(n == nil)
		return nil;
	if(n->op == Oname){
		if(d == n->decl){
			n = dupn(0, nil, e);
			n->ty = d->ty;
		}
		return n;
	}
	n->left = subst(d, e, n->left);
	n->right = subst(d, e, n->right);
	return n;
}

static Node*
putinline(Node *n)
{
	Node *e, *tn;
	Type *t;
	Decl *d;

if(debug['z']) print("inline1: %n\n", n);
	if(n->left->op == Oname)
		d = n->left->decl;
	else
		d = n->left->right->decl;
	e = d->init;
	t = e->ty;
	e = dupn(1, &n->src, e->right->left->left);
	for(d = t->ids, n = n->right; d != nil && n != nil; d = d->next, n = n->right){
		if(hasside(n->left, 0) && occurs(d, e) != 1){
			tn = talloc(mkn(0, nil, nil), d->ty, nil);
			e = mkbin(Ocomma, mkbin(Oas, tn, n->left), subst(d, tn, e));
			e->ty = e->right->ty;
			e->left->ty = d->ty;
		}
		else
			e = subst(d, n->left, e);
	}
	if(d != nil || n != nil)
		fatal("bad arg match in putinline()");
if(debug['z']) print("inline2: %n\n", e);
	return e;
}

static void
fpcall(Src *src, int op, Node *n, Node *ret)
{
	Node tp, *e, *mod, *ind;

	tp.decl = nil;
	e = n->left->left;
	if(e->addable >= Rcant)
		e = eacom(e, &tp, nil);
	mod = mkunary(Oind, e);
	ind = mkunary(Oind, mkbin(Oadd, dupn(0, src, e), mkconst(src, IBY2WD)));
	n->left = mkbin(Omdot, mod, ind);
	n->left->ty = e->ty->tof;
	mod->ty = ind->ty = ind->left->ty = ind->left->right->ty = tint;
	sumark(n);
	callcom(src, op, n, ret);
	tfree(&tp);
}
