include "opname.m";

znode:	Node;

isused = array[Oend] of
{
	Oas =>		1,
	Odas =>		1,
	Oaddas =>	1,
	Osubas =>	1,
	Omulas =>	1,
	Odivas =>	1,
	Omodas =>	1,
	Oexpas =>	1,
	Oandas =>	1,
	Ooras =>	1,
	Oxoras =>	1,
	Olshas =>	1,
	Onothing =>	1,
	Orshas =>	1,
	Oinc =>		1,
	Odec =>		1,
	Opreinc =>	1,
	Opredec =>	1,
	Ocall =>	1,
	Oraise =>	1,
	Ospawn =>	1,
	Osnd =>		1,
	Orcv =>		1,

	* =>		0
};

sideeffect := array[Oend] of
{
	Oas =>		1,
	Odas =>		1,
	Oaddas =>	1,
	Osubas =>	1,
	Omulas =>	1,
	Odivas =>	1,
	Omodas =>	1,
	Oexpas =>	1,
	Oandas =>	1,
	Ooras =>	1,
	Oxoras =>	1,
	Olshas =>	1,
	Orshas =>	1,
	Oinc =>		1,
	Odec =>		1,
	Opreinc =>	1,
	Opredec =>	1,
	Ocall =>	1,
	Oraise =>	1,
	Ospawn =>	1,
	Osnd =>		1,
	Orcv =>		1,

	Oadr =>		1,
	Oarray =>	1,
	Ocast =>	1,
	Ochan =>	1,
	Ocons =>	1,
	Odiv =>		1,
	Odot =>		1,
	Oind =>		1,
	Oindex =>	1,
	Oinds =>	1,
	Oindx =>	1,
	Olen =>		1,
	Oload =>	1,
	Omod =>		1,
	Oref =>		1,

	* =>		0
};

opcommute = array[Oend] of
{
	Oeq =>		Oeq,
	Oneq =>		Oneq,
	Olt =>		Ogt,
	Ogt =>		Olt,
	Ogeq =>		Oleq,
	Oleq =>		Ogeq,
	Oadd =>		Oadd,
	Omul =>		Omul,
	Oxor =>		Oxor,
	Oor =>		Oor,
	Oand =>		Oand,

	* =>		0
};

oprelinvert = array[Oend] of
{

	Oeq =>		Oneq,
	Oneq =>		Oeq,
	Olt =>		Ogeq,
	Ogt =>		Oleq,
	Ogeq =>		Olt,
	Oleq =>		Ogt,

	* =>		0
};

isrelop := array[Oend] of
{

	Oeq =>		1,
	Oneq =>		1,
	Olt =>		1,
	Oleq =>		1,
	Ogt =>		1,
	Ogeq =>		1,
	Oandand =>	1,
	Ooror =>	1,
	Onot =>		1,

	* =>		0
};

ipow(x: big, n: int): big
{
	inv: int;
	r: big;

	inv = 0;
	if(n < 0){
		n = -n;
		inv = 1;
	}
	r = big 1;
	for(;;){
		if(n&1)
			r *= x;
		if((n >>= 1) == 0)
			break;
		x *= x;
	}
	if(inv)
		r = big 1/r;
	return r;
}

rpow(x: real, n: int): real
{
	inv: int;
	r: real;

	inv = 0;
	if(n < 0){
		n = -n;
		inv = 1;
	}
	r = 1.0;
	for(;;){
		if(n&1)
			r *= x;
		if((n >>= 1) == 0)
			break;
		x *= x;
	}
	if(inv)
		r = 1.0/r;
	return r;
}

real2fix(v: real, t: ref Type): big
{
	return big(v/scale(t));
}

fix2fix(v: big, f: ref Type, t: ref Type): big
{
	return big(real v * (scale(f)/scale(t)));
}

fix2real(v: big, f: ref Type): real
{
	return real v * scale(f);
}

istuple(n: ref Node): int
{
	d: ref Decl;

	case(n.op){
	Otuple =>
		return 1;
	Oname =>
		d = n.decl;
		if(d.importid != nil)
			d = d.importid;
		return d.store == Dconst && (n.ty.kind == Ttuple || n.ty.kind == Tadt);
	Odot =>
		return 0;	# istuple(n.left);
	}
	return 0;
}

tuplemem(n: ref Node, d: ref Decl): ref Node
{
	ty: ref Type;
	ids: ref Decl;

	ty = n.ty;
	n = n.left;
	for(ids = ty.ids; ids != nil; ids = ids.next){
		if(ids.sym == d.sym)
			break;
		else
			n = n.right;
	}
	if(n == nil)
		fatal("tuplemem cannot cope !\n");
	return n.left;
}

varcom(v: ref Decl): int
{
	n := v.init;
	n = fold(n);
	v.init = n;
	if(debug['v'])
		print("variable '%s' val %s\n", v.sym.name, expconv(n));
	if(n == nil)
		return 1;

	tn := ref znode;
	tn.op = Oname;
	tn.decl = v;
	tn.src = v.src;
	tn.ty = v.ty;
	return initable(tn, n, 0);
}

initable(v, n: ref Node, allocdep: int): int
{
	case n.ty.kind{
	Tiface or
	Tgoto or
	Tcase or
	Tcasel or
	Tcasec or
	Talt or
	Texcept =>
		return 1;
	Tint or
	Tbig or
	Tbyte or
	Treal or
	Tstring or
	Tfix =>
		if(n.op != Oconst)
			break;
		return 1;
	Tadt or
	Tadtpick or
	Ttuple =>
		if(n.op == Otuple)
			n = n.left;
		else if(n.op == Ocall)
			n = n.right;
		else
			break;
		for(; n != nil; n = n.right)
			if(!initable(v, n.left, allocdep))
				return 0;
		return 1;
	Tarray =>
		if(n.op != Oarray)
			break;
		if(allocdep >= DADEPTH){
			nerror(v, expconv(v)+"s initializer has arrays nested more than "+string allocdep+" deep");
			return 0;
		}
		allocdep++;
		usedesc(mktdesc(n.ty.tof));
		if(n.left.op != Oconst){
			nerror(v, expconv(v)+"s size is not a constant");
			return 0;
		}
		for(e := n.right; e != nil; e = e.right)
			if(!initable(v, e.left.right, allocdep))
				return 0;
		return 1;
	Tany =>
		return 1;
	Tref or
	Tlist or
	Tpoly or
	* =>
		nerror(v, "can't initialize "+etconv(v));
		return 0;
	}
	nerror(v, expconv(v)+"s initializer, "+expconv(n)+", is not a constant expression");
	return 0;
}

#
# merge together two sorted lists, yielding a sorted list
#
elemmerge(e, f: ref Node): ref Node
{
	r := rock := ref Node;
	while(e != nil && f != nil){
		if(e.left.left.c.val <= f.left.left.c.val){
			r.right = e;
			e = e.right;
		}else{
			r.right = f;
			f = f.right;
		}
		r = r.right;
	}
	if(e != nil)
		r.right = e;
	else
		r.right = f;
	return rock.right;
}

#
# recursively split lists and remerge them after they are sorted
#
recelemsort(e: ref Node, n: int): ref Node
{
	if(n <= 1)
		return e;
	m := n / 2 - 1;
	ee := e;
	for(i := 0; i < m; i++)
		ee = ee.right;
	r := ee.right;
	ee.right = nil;
	return elemmerge(recelemsort(e, n / 2),
			recelemsort(r, (n + 1) / 2));
}

#
# sort the elems by index; wild card is first
#
elemsort(e: ref Node): ref Node
{
	n := 0;
	for(ee := e; ee != nil; ee = ee.right){
		if(ee.left.left.op == Owild)
			ee.left.left.c = ref Const(big -1, 0.);
		n++;
	}
	return recelemsort(e, n);
}

sametree(n1: ref Node, n2: ref Node): int
{
	if(n1 == n2)
		return 1;
	if(n1 == nil || n2 == nil)
		return 0;
	if(n1.op != n2.op || n1.ty != n2.ty)
		return 0;
	if(n1.op == Oconst){
		case(n1.ty.kind){
		Tbig or
		Tbyte or
		Tint =>
			return n1.c.val == n2.c.val;
		Treal =>
			return n1.c.rval == n2.c.rval;
		Tfix =>
			return n1.c.val == n2.c.val && tequal(n1.ty, n2.ty);
		Tstring =>
			return n1.decl.sym == n2.decl.sym;
		}
		return 0;
	}
	return n1.decl == n2.decl && sametree(n1.left, n2.left) && sametree(n1.right, n2.right);
}

occurs(d: ref Decl, n: ref Node): int
{
	if(n == nil)
		return 0;
	if(n.op == Oname){
		if(d == n.decl)
			return 1;
		return 0;
	}
	return occurs(d, n.left) + occurs(d, n.right);
}

#
# left and right subtrees the same
#
folds(n: ref Node): ref Node
{
	if(hasside(n, 1))
		return n;
	case(n.op){
	Oeq or
	Oleq or
	Ogeq =>
		n.c = ref Const(big 1, 0.0);
	Osub =>
		n.c = ref Const(big 0, 0.0);
	Oxor or
	Oneq or
	Olt or
	Ogt =>
		n.c = ref Const(big 0, 0.0);
	Oand or
	Oor or
	Oandand or
	Ooror =>
		return n.left;
	* =>
		return n;
	}
	n.op = Oconst;
	n.left = n.right = nil;
	n.decl = nil;
	return n;
}

#
# constant folding for typechecked expressions
#
fold(n: ref Node): ref Node
{
	if(n == nil)
		return nil;
	if(debug['F'])
		print("fold %s\n", nodeconv(n));
	n = efold(n);
	if(debug['F'])
		print("folded %s\n", nodeconv(n));
	return n;
}

efold(n: ref Node): ref Node
{
	d: ref Decl;

	if(n == nil)
		return nil;

	left := n.left;
	right := n.right;
	case n.op{
	Oname =>
		d = n.decl;
		if(d.importid != nil)
			d = d.importid;
		if(d.store != Dconst){
			if(d.store == Dtag){
				n.op = Oconst;
				n.ty = tint;
				n.c = ref Const(big d.tag, 0.);
			}
			break;
		}
		case n.ty.kind{
		Tbig =>
			n.op = Oconst;
			n.c = ref Const(d.init.c.val, 0.);
		Tbyte =>
			n.op = Oconst;
			n.c = ref Const(big byte d.init.c.val, 0.);
		Tint or
		Tfix =>
			n.op = Oconst;
			n.c = ref Const(big int d.init.c.val, 0.);
		Treal =>
			n.op = Oconst;
			n.c = ref Const(big 0, d.init.c.rval);
		Tstring =>
			n.op = Oconst;
			n.decl = d.init.decl;
		Ttuple =>
			*n = *d.init;
		Tadt =>
			*n = *d.init;
			n = rewrite(n);	# was call
		Texception =>
			if(n.ty.cons == byte 0)
				fatal("non-const exception type in efold");
			n.op = Oconst;
		* =>
			fatal("unknown const type "+typeconv(n.ty)+" in efold");
		}
	Oadd =>
		left = efold(left);
		right = efold(right);
		n.left = left;
		n.right = right;
		if(n.ty == tstring && right.op == Oconst){
			if(left.op == Oconst)
				n = mksconst(n.src, stringcat(left.decl.sym, right.decl.sym));
			else if(left.op == Oadd && left.ty == tstring && left.right.op == Oconst){
				left.right = mksconst(n.src, stringcat(left.right.decl.sym, right.decl.sym));
				n = left;
			}
		}
	Olen =>
		left = efold(left);
		n.left = left;
		if(left.ty == tstring && left.op == Oconst)
			n = mkconst(n.src, big len left.decl.sym.name);
	Oslice =>
		if(right.left.op == Onothing)
			right.left = mkconst(right.left.src, big 0);
		n.left = efold(left);
		n.right = efold(right);
	Oinds =>
		n.left = left = efold(left);
		n.right = right = efold(right);
		if(right.op == Oconst && left.op == Oconst){
			;
		}
	Ocast =>
		n.op = Ocast;
		left = efold(left);
		n.left = left;
		if(n.ty == left.ty || n.ty.kind == Tfix && tequal(n.ty, left.ty))
			return left;
		if(left.op == Oconst)
			return foldcast(n, left);
	Odot or
	Omdot =>
		#
		# what about side effects from left?
		#
		d = right.decl;
		case d.store{
		Dconst or
		Dtag or
		Dtype =>
			#
			# set it up as a name and let that case do the hard work
			#
			n.op = Oname;
			n.decl = d;
			n.left = nil;
			n.right = nil;
			return efold(n);
		}
		n.left = efold(left);
		if(n.left.op == Otuple)
			n = tuplemem(n.left, d);
		else
			n.right = efold(right);
	Otagof =>
		if(n.decl != nil){
			n.op = Oconst;
			n.left = nil;
			n.right = nil;
			n.c = ref Const(big n.decl.tag, 0.);			
			return efold(n);
		}
		n.left = efold(left);
	Oif =>
		n.left = left = efold(left);
		n.right = right = efold(right);
		if(left.op == Oconst){
			if(left.c.val != big 0)
				return right.left;
			else
				return right.right;
		}
	* =>
		n.left = efold(left);
		n.right = efold(right);
	}

	left = n.left;
	right = n.right;
	if(left == nil)
		return n;

	if(right == nil){
		if(left.op == Oconst){
			if(left.ty == tint || left.ty == tbyte || left.ty == tbig)
				return foldc(n);
			if(left.ty == treal)
				return foldr(n);
		}
		return n;
	}

	if(left.op == Oconst){
		case n.op{
		Olsh or
		Orsh =>
			if(left.c.val == big 0 && !hasside(right, 1))
				return left;
		Ooror =>
			if(left.ty == tint || left.ty == tbyte || left.ty == tbig){
				if(left.c.val == big 0){
					n = mkbin(Oneq, right, mkconst(right.src, big 0));
					n.ty = right.ty;
					n.left.ty = right.ty;
					return efold(n);
				}
				left.c.val = big 1;
				return left;
			}
		Oandand =>
			if(left.ty == tint || left.ty == tbyte || left.ty == tbig){
				if(left.c.val == big 0)
					return left;
				n = mkbin(Oneq, right, mkconst(right.src, big 0));
				n.ty = right.ty;
				n.left.ty = right.ty;
				return efold(n);
			}
		}
	}
	if(left.op == Oconst && right.op != Oconst
	&& opcommute[n.op]
	&& n.ty != tstring){
		n.op = opcommute[n.op];
		n.left = right;
		n.right = left;
		left = right;
		right = n.right;
	}
	if(right.op == Oconst && left.op == n.op && left.right.op == Oconst
	&& (n.op == Oadd || n.op == Omul || n.op == Oor || n.op == Oxor || n.op == Oand)
	&& n.ty != tstring){
		n.left = left.left;
		left.left = right;
		right = efold(left);
		n.right = right;
		left = n.left;
	}
	if(right.op == Oconst){
		if(n.op == Oexp && left.ty == treal){
			if(left.op == Oconst)
				return foldr(n);
			return n;
		}
		if(right.ty == tint || right.ty == tbyte || left.ty == tbig){
			if(left.op == Oconst)
				return foldc(n);
			return foldvc(n);
		}
		if(right.ty == treal && left.op == Oconst)
			return foldr(n);
	}
	if(sametree(left, right))
		return folds(n);
	return n;
}

#
# does evaluating the node have any side effects?
#
hasside(n: ref Node, strict: int): int
{
	for(; n != nil; n = n.right){
		if(sideeffect[n.op] && (strict || n.op != Oadr && n.op != Oind))
			return 1;
		if(hasside(n.left, strict))
			return 1;
	}
	return 0;
}

hascall(n: ref Node): int
{
	for(; n != nil; n = n.right){
		if(n.op == Ocall || n.op == Ospawn)
			return 1;
		if(hascall(n.left))
			return 1;
	}
	return 0;
}

hasasgns(n: ref Node): int
{
	if(n == nil)
		return 0;
	if(n.op != Ocall && isused[n.op] && n.op != Onothing)
		return 1;
	return hasasgns(n.left) || hasasgns(n.right);
}

nodes(n: ref Node): int
{
	if(n == nil)
		return 0;
	return 1+nodes(n.left)+nodes(n.right);
}
	
foldcast(n, left: ref Node): ref Node
{
	case left.ty.kind{
	Tint =>
		left.c.val = big int left.c.val;
		return foldcasti(n, left);
	Tbyte =>
		left.c.val = big byte left.c.val;
		return foldcasti(n, left);
	Tbig =>
		return foldcasti(n, left);
	Treal =>
		case n.ty.kind{
		Tint or
		Tbyte or
		Tbig =>
			left.c.val = big left.c.rval;
		Tfix =>
			left.c.val = real2fix(left.c.rval, n.ty);
		Tstring =>
			return mksconst(n.src, enterstring(string left.c.rval));
		* =>
			return n;
		}
	Tfix =>
		case n.ty.kind{
		Tint or
		Tbyte or
		Tbig =>
			left.c.val = big fix2real(left.c.val, left.ty);
		Treal =>
			left.c.rval = fix2real(left.c.val, left.ty);
		Tfix =>
			if(tequal(left.ty, n.ty))
				return left;
			left.c.val = fix2fix(left.c.val, left.ty, n.ty);
		Tstring =>
			return mksconst(n.src, enterstring(string fix2real(left.c.val, left.ty)));
		* =>
			return n;
		}
		break;
	Tstring =>
		case n.ty.kind{
		Tint or
		Tbyte or
		Tbig =>
			left.c = ref Const(big left.decl.sym.name, 0.);
		Treal =>
			left.c = ref Const(big 0, real left.decl.sym.name);
		Tfix =>
			left.c = ref Const(real2fix(real left.decl.sym.name, n.ty), 0.);
		* =>
			return n;
		}
	* =>
		return n;
	}
	left.ty = n.ty;
	left.src = n.src;
	return left;
}

#
# left is some kind of int type
#
foldcasti(n, left: ref Node): ref Node
{
	case n.ty.kind{
	Tint =>
		left.c.val = big int left.c.val;
	Tbyte =>
		left.c.val = big byte left.c.val;
	Tbig =>
		;
	Treal =>
		left.c.rval = real left.c.val;
	Tfix =>
		left.c.val = real2fix(real left.c.val, n.ty);
	Tstring =>
		return mksconst(n.src, enterstring(string left.c.val));
	* =>
		return n;
	}
	left.ty = n.ty;
	left.src = n.src;
	return left;
}

#
# right is a const int
#
foldvc(n: ref Node): ref Node
{
	left := n.left;
	right := n.right;
	case n.op{
	Oadd or
	Osub or
	Oor or
	Oxor or
	Olsh or
	Orsh or
	Ooror =>
		if(right.c.val == big 0)
			return left;
		if(n.op == Ooror && !hasside(left, 1))
			return right;
	Oand =>
		if(right.c.val == big 0 && !hasside(left, 1))
			return right;
	Omul =>
		if(right.c.val == big 1)
			return left;
		if(right.c.val == big 0 && !hasside(left, 1))
			return right;
	Odiv =>
		if(right.c.val == big 1)
			return left;
	Omod =>
		if(right.c.val == big 1 && !hasside(left, 1)){
			right.c.val = big 0;
			return right;
		}
	Oexp =>
		if(right.c.val == big 0){
			right.c.val = big 1;
			return right;
		}
		if(right.c.val == big 1)
			return left;
	Oandand =>
		if(right.c.val != big 0)
			return left;
		if(!hasside(left, 1))
			return right;
	Oneq =>
		if(!isrelop[left.op])
			return n;
		if(right.c.val == big 0)
			return left;
		n.op = Onot;
		n.right = nil;
	Oeq =>
		if(!isrelop[left.op])
			return n;
		if(right.c.val != big 0)
			return left;
		n.op = Onot;
		n.right = nil;
	}
	return n;
}

#
# left and right are const ints
#
foldc(n: ref Node): ref Node
{
	v: big;
	rv, nb: int;

	left := n.left;
	right := n.right;
	case n.op{
	Oadd =>
		v = left.c.val + right.c.val;
	Osub =>
		v = left.c.val - right.c.val;
	Omul =>
		v = left.c.val * right.c.val;
	Odiv =>
		if(right.c.val == big 0){
			nerror(n, "divide by 0 in constant expression");
			return n;
		}
		v = left.c.val / right.c.val;
	Omod =>
		if(right.c.val == big 0){
			nerror(n, "mod by 0 in constant expression");
			return n;
		}
		v = left.c.val % right.c.val;
	Oexp =>
		if(left.c.val == big 0 && right.c.val < big 0){
			nerror(n, "0 to negative power in constant expression");
			return n;
		}
		v = ipow(left.c.val, int right.c.val);
	Oand =>
		v = left.c.val & right.c.val;
	Oor =>
		v = left.c.val | right.c.val;
	Oxor =>
		v = left.c.val ^ right.c.val;
	Olsh =>
		v = left.c.val;
		rv = int right.c.val;
		if(rv < 0 || rv >= n.ty.size * 8){
			nwarn(n, "shift amount "+string rv+" out of range");
			rv = 0;
		}
		if(rv == 0)
			break;
		v <<= rv;
	Orsh =>
		v = left.c.val;
		rv = int right.c.val;
		nb = n.ty.size * 8;
		if(rv < 0 || rv >= nb){
			nwarn(n, "shift amount "+string rv+" out of range");
			rv = 0;
		}
		if(rv == 0)
			break;
		v >>= rv;
	Oneg =>
		v = -left.c.val;
	Ocomp =>
		v = ~left.c.val;
	Oeq =>
		v = big(left.c.val == right.c.val);
	Oneq =>
		v = big(left.c.val != right.c.val);
	Ogt =>
		v = big(left.c.val > right.c.val);
	Ogeq =>
		v = big(left.c.val >= right.c.val);
	Olt =>
		v = big(left.c.val < right.c.val);
	Oleq =>
		v = big(left.c.val <= right.c.val);
	Oandand =>
		v = big(int left.c.val && int right.c.val);
	Ooror =>
		v = big(int left.c.val || int right.c.val);
	Onot =>
		v = big(left.c.val == big 0);
	* =>
		return n;
	}
	if(n.ty == tint)
		v = big int v;
	else if(n.ty == tbyte)
		v = big byte v;
	n.left = nil;
	n.right = nil;
	n.decl = nil;
	n.op = Oconst;
	n.c = ref Const(v, 0.);
	return n;
}

#
# left and right are const reals
#
foldr(n: ref Node): ref Node
{
	rv := 0.;
	v := big 0;

	left := n.left;
	right := n.right;
	case n.op{
	Ocast =>
		return n;
	Oadd =>
		rv = left.c.rval + right.c.rval;
	Osub =>
		rv = left.c.rval - right.c.rval;
	Omul =>
		rv = left.c.rval * right.c.rval;
	Odiv =>
		rv = left.c.rval / right.c.rval;
	Oexp =>
		rv = rpow(left.c.rval, int right.c.val);
	Oneg =>
		rv = -left.c.rval;
	Oinv =>
		if(left.c.rval == 0.0){
			error(n.src.start, "divide by 0 in fixed point type");
			return n;
		}
		rv = 1.0/left.c.rval;
	Oeq =>
		v = big(left.c.rval == right.c.rval);
	Oneq =>
		v = big(left.c.rval != right.c.rval);
	Ogt =>
		v = big(left.c.rval > right.c.rval);
	Ogeq =>
		v = big(left.c.rval >= right.c.rval);
	Olt =>
		v = big(left.c.rval < right.c.rval);
	Oleq =>
		v = big(left.c.rval <= right.c.rval);
	* =>
		return n;
	}
	n.left = nil;
	n.right = nil;
	n.op = Oconst;

	if(isnan(rv))
		rv = canonnan;

	n.c = ref Const(v, rv);
	return n;
}

varinit(d: ref Decl, e: ref Node): ref Node
{
	n := mkdeclname(e.src, d);
	if(d.next == nil)
		return mkbin(Oas, n, e);
	return mkbin(Oas, n, varinit(d.next, e));
}

#
# given: an Oseq list with left == next or the last child
# make a list with the right == next
# ie: Oseq(Oseq(a, b),c) ==> Oseq(a, Oseq(b, Oseq(c, nil))))
#
rotater(e: ref Node): ref Node
{
	if(e == nil)
		return e;
	if(e.op != Oseq)
		return mkunary(Oseq, e);
	e.right = mkunary(Oseq, e.right);
	while(e.left.op == Oseq){
		left := e.left;
		e.left = left.right;
		left.right = e;
		e = left;
	}
	return e;
}

#
# reverse the case labels list
#
caselist(s, nr: ref Node): ref Node
{
	r := s.right;
	s.right = nr;
	if(r == nil)
		return s;
	return caselist(r, s);
}

#
# e is a seq of expressions; make into cons's to build a list
#
etolist(e: ref Node): ref Node
{
	if(e == nil)
		return nil;
	n := mknil(e.src);
	n.src.start = n.src.stop;
	if(e.op != Oseq)
		return mkbin(Ocons, e, n);
	e.right = mkbin(Ocons, e.right, n);
	while(e.left.op == Oseq){
		e.op = Ocons;
		left := e.left;
		e.left = left.right;
		left.right = e;
		e = left;
	}
	e.op = Ocons;
	return e;
}

dupn(resrc: int, src: Src, n: ref Node): ref Node
{
	nn := ref *n;
	if(resrc)
		nn.src = src;
	if(nn.left != nil)
		nn.left = dupn(resrc, src, nn.left);
	if(nn.right != nil)
		nn.right = dupn(resrc, src, nn.right);
	return nn;
}

mkn(op: int, left, right: ref Node): ref Node
{
	n := ref Node;
	n.op = op;
	n.flags = byte 0;
	n.left = left;
	n.right = right;
	return n;
}

mkunary(op: int, left: ref Node): ref Node
{
	n := ref Node;
	n.src = left.src;
	n.op = op;
	n.flags = byte 0;
	n.left = left;
	return n;
}

mkbin(op: int, left, right: ref Node): ref Node
{
	n := ref Node;
	n.src.start = left.src.start;
	n.src.stop = right.src.stop;
	n.op = op;
	n.flags = byte 0;
	n.left = left;
	n.right = right;
	return n;
}

mkdeclname(src: Src, d: ref Decl): ref Node
{
	n := ref Node;
	n.src = src;
	n.op = Oname;
	n.flags = byte 0;
	n.decl = d;
	n.ty = d.ty;
	d.refs++;
	return n;
}

mknil(src: Src): ref Node
{
	return mkdeclname(src, nildecl);
}

mkname(src: Src, s: ref Sym): ref Node
{
	n := ref Node;
	n.src = src;
	n.op = Oname;
	n.flags = byte 0;
	if(s.unbound == nil){
		s.unbound = mkdecl(src, Dunbound, nil);
		s.unbound.sym = s;
	}
	n.decl = s.unbound;
	return n;
}

mkconst(src: Src, v: big): ref Node
{
	n := ref Node;
	n.src = src;
	n.op = Oconst;
	n.flags = byte 0;
	n.ty = tint;
	n.c = ref Const(v, 0.);
	return n;
}

mkrconst(src: Src, v: real): ref Node
{
	n := ref Node;
	n.src = src;
	n.op = Oconst;
	n.flags = byte 0;
	n.ty = treal;
	n.c = ref Const(big 0, v);
	return n;
}

mksconst(src: Src, s: ref Sym): ref Node
{
	n := ref Node;
	n.src = src;
	n.op = Oconst;
	n.flags = byte 0;
	n.ty = tstring;
	n.decl = mkdecl(src, Dconst, tstring);
	n.decl.sym = s;
	return n;
}

opconv(op: int): string
{
	if(op < 0 || op > Oend)
		return "op "+string op;
	return opname[op];
}

etconv(n: ref Node): string
{
	s := expconv(n);
	if(n.ty == tany || n.ty == tnone || n.ty == terror)
		return s;
	s += " of type ";
	s += typeconv(n.ty);
	return s;
}

expconv(n: ref Node): string
{
	return "'" + subexpconv(n) + "'";
}

subexpconv(n: ref Node): string
{
	if(n == nil)
		return "";
	s := "";
	if(int n.flags & PARENS)
		s[len s] = '(';
	case n.op{
	Obreak or
	Ocont =>
		s += opname[n.op];
		if(n.decl != nil)
			s += " "+n.decl.sym.name;
	Oexit or
	Owild =>
		s += opname[n.op];
	Onothing =>
		;
	Oadr or
	Oused =>
		s += subexpconv(n.left);
	Oseq =>
		s += eprintlist(n, ", ");
	Oname =>
		if(n.decl == nil)
			s += "<nil>";
		else
			s += n.decl.sym.name;
	Oconst =>
		if(n.ty.kind == Tstring){
			s += stringpr(n.decl.sym);
			break;
		}
		if(n.decl != nil && n.decl.sym != nil){
			s += n.decl.sym.name;
			break;
		}
		case n.ty.kind{
		Tbig or
		Tint or
		Tbyte =>
			s += string n.c.val;
		Treal =>
			s += string n.c.rval;
		Tfix =>
			s += string n.c.val + "(" + string n.ty.val.c.rval + ")";
		* =>
			s += opname[n.op];
		}
	Ocast =>
		s += typeconv(n.ty);
		s[len s] = ' ';
		s += subexpconv(n.left);
	Otuple =>
		if(n.ty != nil && n.ty.kind == Tadt)
			s += n.ty.decl.sym.name;
		s[len s] = '(';
		s += eprintlist(n.left, ", ");
		s[len s] = ')';
	Ochan =>
		if(n.left != nil){
			s += "chan [";
			s += subexpconv(n.left);
			s += "] of ";
			s += typeconv(n.ty.tof);
		}
		else
			s += "chan of "+typeconv(n.ty.tof);
	Oarray =>
		s += "array [";
		if(n.left != nil)
			s += subexpconv(n.left);
		s += "] of ";
		if(n.right != nil){
			s += "{";
			s += eprintlist(n.right, ", ");
			s += "}";
		}else{
			s += typeconv(n.ty.tof);
		}
	Oelem or
	Olabel =>
		if(n.left != nil){
			s += eprintlist(n.left, " or ");
			s += " =>";
		}
		s += subexpconv(n.right);
	Orange =>
		s += subexpconv(n.left);
		s += " to ";
		s += subexpconv(n.right);
	Ospawn =>
		s += "spawn ";
		s += subexpconv(n.left);
	Oraise =>
		s += "raise ";
		s += subexpconv(n.left);
	Ocall =>
		s += subexpconv(n.left);
		s += "(";
		s += eprintlist(n.right, ", ");
		s += ")";
	Oinc or
	Odec =>
		s += subexpconv(n.left);
		s += opname[n.op];
	Oindex or
	Oindx or
	Oinds =>
		s += subexpconv(n.left);
		s += "[";
		s += subexpconv(n.right);
		s += "]";
	Oslice =>
		s += subexpconv(n.left);
		s += "[";
		s += subexpconv(n.right.left);
		s += ":";
		s += subexpconv(n.right.right);
		s += "]";
	Oload =>
		s += "load ";
		s += typeconv(n.ty);
		s += " ";
		s += subexpconv(n.left);
	Oref or
	Olen or
	Ohd or
	Otl or
	Otagof =>
		s += opname[n.op];
		s[len s] = ' ';
		s += subexpconv(n.left);
	* =>
		if(n.right == nil){
			s += opname[n.op];
			s += subexpconv(n.left);
		}else{
			s += subexpconv(n.left);
			s += opname[n.op];
			s += subexpconv(n.right);
		}
	}
	if(int n.flags & PARENS)
		s[len s] = ')';
	return s;
}

eprintlist(elist: ref Node, sep: string): string
{
	if(elist == nil)
		return "";
	s := "";
	for(; elist.right != nil; elist = elist.right){
		if(elist.op == Onothing)
			continue;
		if(elist.left.op == Ofnptr)
			return s;
		s += subexpconv(elist.left);
		if(elist.right.left.op != Ofnptr)
			s += sep;
	}
	s += subexpconv(elist.left);
	return s;
}

nodeconv(n: ref Node): string
{
	return nprint(n, 0);
}

nprint(n: ref Node, indent: int): string
{
	if(n == nil)
		return "";
	s := "\n";
	for(i := 0; i < indent; i++)
		s[len s] = ' ';
	case n.op{
	Oname =>
		if(n.decl == nil)
			s += "<nil>";
		else
			s += n.decl.sym.name;
	Oconst =>
		if(n.decl != nil && n.decl.sym != nil)
			s += n.decl.sym.name;
		else
			s += opconv(n.op);
		if(n.ty == tint || n.ty == tbyte || n.ty == tbig)
			s += " (" + string n.c.val + ")";
	* =>
		s += opconv(n.op);
	}
	s += " " + typeconv(n.ty) + " " + string n.addable + " " + string n.temps;
	indent += 2;
	s += nprint(n.left, indent);
	s += nprint(n.right, indent);
	return s;
}
