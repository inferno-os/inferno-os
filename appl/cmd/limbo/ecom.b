maxstack:	int;				# max size of a stack frame called

precasttab := array[Tend] of array of ref Type;

optabinit()
{
	ct := array[Tend] of ref Type;
	for(i := 0; i < Tend; i++)
		precasttab[i] = ct;
	precasttab[Tstring] = array[Tend] of { Tbyte => tint, Tfix => treal, };
	precasttab[Tbig] = array[Tend] of { Tbyte => tint, Tfix => treal, };
	precasttab[Treal] = array[Tend] of { Tbyte => tint, };
	precasttab[Tfix] = array[Tend] of { Tbyte => tint, Tstring => treal, Tbig => treal, };
	precasttab[Tbyte] = array[Tend] of { Tstring => tint, Tbig => tint, Treal => tint, Tfix => tint, };

	casttab = array[Tend] of { * => array[Tend] of {* => 0}};

	casttab[Tint][Tint] = IMOVW;
	casttab[Tbig][Tbig] = IMOVL;
	casttab[Treal][Treal] = IMOVF;
	casttab[Tbyte][Tbyte] = IMOVB;
	casttab[Tstring][Tstring] = IMOVP;
	casttab[Tfix][Tfix] = ICVTXX;	# never same type

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

	#
	# placeholders; fixed in precasttab
	#
	casttab[Tbyte][Tstring] = 16rff;
	casttab[Tstring][Tbyte] = 16rff;
	casttab[Tbyte][Treal] = 16rff;
	casttab[Treal][Tbyte] = 16rff;
	casttab[Tbyte][Tbig] = 16rff;
	casttab[Tbig][Tbyte] = 16rff;
	casttab[Tfix][Tbyte] = 16rff;
	casttab[Tbyte][Tfix] = 16rff;
	casttab[Tfix][Tbig] = 16rff;
	casttab[Tbig][Tfix] = 16rff;
	casttab[Tfix][Tstring] = 16rff;
	casttab[Tstring][Tfix] = 16rff;
}

#
# global variable and constant initialization checking
#
vcom(ids: ref Decl): int
{
	ok := 1;
	for(v := ids; v != nil; v = v.next)
		ok &= varcom(v);
	for(v = ids; v != nil; v = v.next)
		v.init = simplify(v.init);
	return ok;
}

simplify(n: ref Node): ref Node
{
	if(n == nil)
		return nil;
	if(debug['F'])
		print("simplify %s\n", nodeconv(n));
	n = efold(rewrite(n));
	if(debug['F'])
		print("simplified %s\n", nodeconv(n));
	return n;
}

isfix(n: ref Node): int
{
	if(n.ty.kind == Tint || n.ty.kind == Tfix){
		if(n.op == Ocast)
			return n.left.ty.kind == Tint || n.left.ty.kind == Tfix;
		return 1;
	}
	return 0;
}

#
# rewrite an expression to make it easiser to compile,
# or give the correct results
#
rewrite(n: ref Node): ref Node
{
	v: big;
	t: ref Type;
	d: ref Decl;
	nn: ref Node;

	if(n == nil)
		return nil;

	left := n.left;
	right := n.right;

	#
	# rewrites
	#
	case n.op{
	Oname =>
		d = n.decl;
		if(d.importid != nil){
			left = mkbin(Omdot, dupn(1, n.src, d.eimport), mkdeclname(n.src, d.importid));
			left.ty = n.ty;
			return rewrite(left);
		}
		if((t = n.ty).kind == Texception){
			if(int t.cons)
				fatal("cons in rewrite Oname");
			n = mkbin(Oadd, n, mkconst(n.src, big(2*IBY2WD)));
			n = mkunary(Oind, n);
			n.ty = t;
			n.left.ty = n.left.left.ty = tint;
			return rewrite(n);
		}
	Odas =>
		n.op = Oas;
		return rewrite(n);
	Oneg =>
		n.left = rewrite(left);
		if(n.ty == treal)
			break;
		left = n.left;
		n.right = left;
		n.left = mkconst(n.src, big 0);
		n.left.ty = n.ty;
		n.op = Osub;
	Ocomp =>
		v = big 0;
		v = ~v;
		n.right = mkconst(n.src, v);
		n.right.ty = n.ty;
		n.left = rewrite(left);
		n.op = Oxor;
	Oinc or
	Odec or
	Opreinc or
	Opredec =>
		n.left = rewrite(left);
		case n.ty.kind{
		Treal =>
			n.right = mkrconst(n.src, 1.0);
		Tint or
		Tbig or
		Tbyte or
		Tfix =>
			n.right = mkconst(n.src, big 1);
			n.right.ty = n.ty;
		* =>
			fatal("can't rewrite inc/dec "+nodeconv(n));
		}
		if(n.op == Opreinc)
			n.op = Oaddas;
		else if(n.op == Opredec)
			n.op = Osubas;
	Oslice =>
		if(right.left.op == Onothing)
			right.left = mkconst(right.left.src, big 0);
		n.left = rewrite(left);
		n.right = rewrite(right);
	Oindex =>
		n.op = Oindx;
		n.left = rewrite(left);
		n.right = rewrite(right);
		n = mkunary(Oind, n);
		n.ty = n.left.ty;
		n.left.ty = tint;
	Oload =>
		n.right = mkn(Oname, nil, nil);
		n.right.src = n.left.src;
		n.right.decl = n.ty.tof.decl;
		n.right.ty = n.ty;
		n.left = rewrite(left);
	Ocast =>
		if(left.ty.kind == Texception){
			n = rewrite(left);
			break;
		}
		n.op = Ocast;
		t = precasttab[left.ty.kind][n.ty.kind];
		if(t != nil){
			n.left = mkunary(Ocast, left);
			n.left.ty = t;
			return rewrite(n);
		}
		n.left = rewrite(left);
	Oraise =>
		if(left.ty == tstring)
			;
		else if(left.ty.cons == byte 0)
			break;
		else if(left.op != Ocall || left.left.ty.kind == Tfn){
			left = mkunary(Ocall, left);
			left.ty = left.left.ty;
		}
		n.left = rewrite(left);
	Ocall =>
		t = left.ty;
		if(t.kind == Tref)
			t = t.tof;
		if(t.kind == Tfn){
			if(left.ty.kind == Tref){	# call by function reference
				n.left = mkunary(Oind, left);
				n.left.ty = t;
				return rewrite(n);
			}
			d = nil;
			if(left.op == Oname)
				d = left.decl;
			else if(left.op == Omdot && left.right.op == Odot)
				d = left.right.right.decl;
			else if(left.op == Omdot || left.op == Odot)
				d = left.right.decl;
			else if(left.op != Oind)
				fatal("cannot deal with call " + nodeconv(n) + " in rewrite");
			if(ispoly(d))
				addfnptrs(d, 0);
			n.left = rewrite(left);
			if(right != nil)
				n.right = rewrite(right);
			if(d != nil && int d.inline == 1)
				n = simplify(inline(n));
			break;
		}
		case n.ty.kind{
		Tref =>
			n = mkunary(Oref, n);
			n.ty = n.left.ty;
			n.left.ty = n.left.ty.tof;
			n.left.left.ty = n.left.ty;
			return rewrite(n);
		Tadt =>
			n.op = Otuple;
			n.right = nil;
			if(n.ty.tags != nil){
				n.left = nn = mkunary(Oseq, mkconst(n.src, big left.right.decl.tag));
				if(right != nil){
					nn.right = right;
					nn.src.stop = right.src.stop;
				}
				n.ty = left.right.decl.ty.tof;
			}else
				n.left = right;
			return rewrite(n);
		Tadtpick =>
			n.op = Otuple;
			n.right = nil;
			n.left = nn = mkunary(Oseq, mkconst(n.src, big left.right.decl.tag));
			if(right != nil){
				nn.right = right;
				nn.src.stop = right.src.stop;
			}
			n.ty = left.right.decl.ty.tof;
			return rewrite(n);
		Texception =>
			if(n.ty.cons == byte 0)
				return n.left;
			if(left.op == Omdot){
				left.right.ty = left.ty;
				left = left.right;
			}
			n.op = Otuple;
			n.right = nil;
			n.left = nn = mkunary(Oseq, left.decl.init);
			nn.right = mkunary(Oseq, mkconst(n.src, big 0));
			nn.right.right = right;
			n.ty = mkexbasetype(n.ty);
			n = mkunary(Oref, n);
			n.ty = internaltype(mktype(n.src.start, n.src.stop, Tref, t, nil));
			return rewrite(n);
		* =>
			fatal("can't deal with "+nodeconv(n)+" in rewrite/Ocall");
		}
	Omdot =>
		#
		# what about side effects from left?
		#
		d = right.decl;
		case d.store{
		Dfn =>
			n.left = rewrite(left);
			if(right.op == Odot){
				n.right = dupn(1, left.src, right.right);
				n.right.ty = d.ty;
			}
		Dconst or
		Dtag or
		Dtype =>
			# handled by fold
			return n;
		Dglobal =>
			right.op = Oconst;
			right.c = ref Const(big d.offset, 0.);
			right.ty = tint;

			n.left = left = mkunary(Oind, left);
			left.ty = tint;
			n.op = Oadd;
			n = mkunary(Oind, n);
			n.ty = n.left.ty;
			n.left.ty = tint;
			n.left = rewrite(n.left);
			return n;
		Darg =>
			return n;
		* =>
			fatal("can't deal with "+nodeconv(n)+" in rewrite/Omdot");
		}
	Odot =>
		#
		# what about side effects from left?
		#
		d = right.decl;
		case d.store{
		Dfn =>
			if(right.left != nil){
				n = mkbin(Omdot, dupn(1, left.src, right.left), right);
				right.left = nil;
				n.ty = d.ty;
				return rewrite(n);
			}
			if(left.ty.kind == Tpoly){
				n = mkbin(Omdot, mkdeclname(left.src, d.link), mkdeclname(left.src, d.link.next));
				n.ty = d.ty;
				return rewrite(n);
			}
			n.op = Oname;
			n.decl = d;
			n.right = nil;
			n.left = nil;
			return n;
		Dconst or
		Dtag or
		Dtype =>
			# handled by fold
			return n;
		}
		if(istuple(left))
			return n;	# handled by fold
		right.op = Oconst;
		right.c = ref Const(big d.offset, 0.);
		right.ty = tint;

		if(left.ty.kind != Tref){
			n.left = mkunary(Oadr, left);
			n.left.ty = tint;
		}
		n.op = Oadd;
		n = mkunary(Oind, n);
		n.ty = n.left.ty;
		n.left.ty = tint;
		n.left = rewrite(n.left);
		return n;
	Oadr =>
		left = rewrite(left);
		n.left = left;
		if(left.op == Oind)
			return left.left;
	Otagof =>
		if(n.decl == nil){
			n.op = Oind;
			return rewrite(n);
		}
		return n;
	Omul or
	Odiv =>
		left = n.left = rewrite(left);
		right = n.right = rewrite(right);
		if(n.ty.kind == Tfix && isfix(left) && isfix(right)){
			if(left.op == Ocast && tequal(left.ty, n.ty))
				n.left = left.left;
			if(right.op == Ocast && tequal(right.ty, n.ty))
				n.right = right.left;
		}
	Oself =>
		if(newfnptr)
			return n;
		if(selfdecl == nil){
			d = selfdecl = mkids(n.src, enter(".self", 5), tany, nil);
			installids(Dglobal, d);
			d.refs++;
		}
		nn = mkn(Oload, nil, nil);
		nn.src = n.src;
		nn.left = mksconst(n.src, enterstring("$self"));
		nn.ty = impdecl.ty;
		usetype(nn.ty);
		usetype(nn.ty.tof);
		nn = rewrite(nn);
		nn.op = Oself;
		return nn;
	Ofnptr =>
		if(n.flags == byte 0){
			# module
			if(left == nil)
				left = mkn(Oself, nil, nil);
			return rewrite(left);
		}
		right.flags = n.flags;
		n = right;
		d = n.decl;
		if(int n.flags == FNPTR2){
			if(left != nil && left.op != Oname)
				fatal("not Oname for addiface");
			if(left == nil){
				addiface(nil, d);
				if(newfnptr)
					n.flags |= byte FNPTRN;
			}
			else
				addiface(left.decl, d);
			n.ty = tint;
			return n;
		}
		if(int n.flags == FNPTRA){
			n = mkdeclname(n.src, d.link);
			n.ty = tany;
			return n;
		}
		if(int n.flags == (FNPTRA|FNPTR2)){
			n = mkdeclname(n.src, d.link.next);
			n.ty = tint;
			return n;
		}
	Ochan =>
		if(left == nil)
			left = n.left = mkconst(n.src, big 0);
		n.left = rewrite(left);
	* =>
		n.left = rewrite(left);
		n.right = rewrite(right);
	}

	return n;
}

#
# label a node with sethi-ullman numbers and addressablity
# genaddr interprets addable to generate operands,
# so a change here mandates a change there.
#
# addressable:
#	const			Rconst	$value		 may also be Roff or Rdesc or Rnoff
#	Asmall(local)		Rreg	value(FP)
#	Asmall(global)		Rmreg	value(MP)
#	ind(Rareg)		Rreg	value(FP)
#	ind(Ramreg)		Rmreg	value(MP)
#	ind(Rreg)		Radr	*value(FP)
#	ind(Rmreg)		Rmadr	*value(MP)
#	ind(Raadr)		Radr	value(value(FP))
#	ind(Ramadr)		Rmadr	value(value(MP))
#
# almost addressable:
#	adr(Rreg)		Rareg
#	adr(Rmreg)		Ramreg
#	add(const, Rareg)	Rareg
#	add(const, Ramreg)	Ramreg
#	add(const, Rreg)	Raadr
#	add(const, Rmreg)	Ramadr
#	add(const, Raadr)	Raadr
#	add(const, Ramadr)	Ramadr
#	adr(Radr)		Raadr
#	adr(Rmadr)		Ramadr
#
# strangely addressable:
#	fn			Rpc
#	mdot(module,exp)	Rmpc
#
sumark(n: ref Node): ref Node
{
	if(n == nil)
		return nil;

	n.temps = byte 0;
	n.addable = Rcant;

	left := n.left;
	right := n.right;
	if(left != nil){
		sumark(left);
		n.temps = left.temps;
	}
	if(right != nil){
		sumark(right);
		if(right.temps == n.temps)
			n.temps++;
		else if(right.temps > n.temps)
			n.temps = right.temps;
	}

	case n.op{
	Oadr =>
		case int left.addable{
		int Rreg =>
			n.addable = Rareg;
		int Rmreg =>
			n.addable = Ramreg;
		int Radr =>
			n.addable = Raadr;
		int Rmadr =>
			n.addable = Ramadr;
		}
	Oind =>
		case int left.addable{
		int Rreg =>
			n.addable = Radr;
		int Rmreg =>
			n.addable = Rmadr;
		int Rareg =>
			n.addable = Rreg;
		int Ramreg =>
			n.addable = Rmreg;
		int Raadr =>
			n.addable = Radr;
		int Ramadr =>
			n.addable = Rmadr;
		}
	Oname =>
		case n.decl.store{
		Darg or
		Dlocal =>
			n.addable = Rreg;
		Dglobal =>
			n.addable = Rmreg;
			if(LDT && n.decl.ty.kind == Tiface)
				n.addable = Rldt;
		Dtype =>
			#
			# check for inferface to load
			#
			if(n.decl.ty.kind == Tmodule)
				n.addable = Rmreg;
		Dfn =>
			if(int n.flags & FNPTR){
				if(int n.flags == FNPTR2)
					n.addable = Roff;
				else if(int n.flags == (FNPTR2|FNPTRN))
					n.addable = Rnoff;
			}
			else
				n.addable = Rpc;
		* =>
			fatal("cannot deal with "+declconv(n.decl)+" in Oname in "+nodeconv(n));
		}
	Omdot =>
		n.addable = Rmpc;
	Oconst =>
		case n.ty.kind{
		Tint or
		Tfix =>
			v := int n.c.val;
			if(v < 0 && ((v >> 29) & 7) != 7
			|| v > 0 && (v >> 29) != 0){
				n.decl = globalconst(n);
				n.addable = Rmreg;
			}else
				n.addable = Rconst;
		Tbig =>
			n.decl = globalBconst(n);
			n.addable = Rmreg;
		Tbyte =>
			n.decl = globalbconst(n);
			n.addable = Rmreg;
		Treal =>
			n.decl = globalfconst(n);
			n.addable = Rmreg;
		Tstring =>
			n.decl = globalsconst(n);
			n.addable = Rmreg;
		* =>
			fatal("cannot const in sumark "+typeconv(n.ty));
		}
	Oadd =>
		if(right.addable == Rconst){
			case int left.addable{
			int Rareg =>
				n.addable = Rareg;
			int Ramreg =>
				n.addable = Ramreg;
			int Rreg or
			int Raadr =>
				n.addable = Raadr;
			int Rmreg or
			int Ramadr =>
				n.addable = Ramadr;
			}
		}
	}
	if(n.addable < Rcant)
		n.temps = byte 0;
	else if(n.temps == byte 0)
		n.temps = byte 1;
	return n;
}

mktn(t: ref Type): ref Node
{
	n := mkn(Oname, nil, nil);
	usedesc(mktdesc(t));
	n.ty = t;
	if(t.decl == nil)
		fatal("mktn nil decl t "+typeconv(t));
	n.decl = t.decl;
	n.addable = Rdesc;
	return n;
}

# does a tuple of the form (a, b, ...) form a contiguous block
# of memory on the stack when offsets are assigned later
# - only when (a, b, ...) := rhs and none of the names nil
# can we guarantee this
#
tupblk0(n: ref Node, d: ref Decl): (int, ref Decl)
{
	ok, nid: int;

	case(n.op){
	Otuple =>
		for(n = n.left; n != nil; n = n.right){
			(ok, d) = tupblk0(n.left, d);
			if(!ok)
				return (0, nil);
		}
		return (1, d);
	Oname =>
		if(n.decl == nildecl)
			return (0, nil);
		if(d != nil && d.next != n.decl)
			return (0, nil);
		nid = int n.decl.nid;
		if(d == nil && nid == 1)
			return (0, nil);
		if(d != nil && nid != 0)
			return (0, nil);
		return (1, n.decl);
	}
	return (0, nil);
}

# could force locals to be next to each other
# - need to shuffle locals list
# - later
#
tupblk(n: ref Node): ref Node
{
	ok: int;
	d: ref Decl;

	if(n.op != Otuple)
		return nil;
	d = nil;
	(ok, d) = tupblk0(n, d);
	if(!ok)
		return nil;
	while(n.op == Otuple)
		n = n.left.left;
	if(n.op != Oname || n.decl.nid == byte 1)
		fatal("bad tupblk");
	return n;
}
	
# for cprof
esrc(src: Src, osrc: Src, nto: ref Node): Src
{
	if(nto != nil && src.start != 0 && src.stop != 0)
		return src;
	return osrc;
}

#
# compile an expression with an implicit assignment
# note: you are not allowed to use nto.src
#
# need to think carefully about the types used in moves
#
ecom(src: Src, nto, n: ref Node): ref Node
{
	tleft, tright, tto, ttn: ref Node;
	t: ref Type;
	p: ref Inst;

	if(debug['e']){
		print("ecom: %s\n", nodeconv(n));
		if(nto != nil)
			print("ecom nto: %s\n", nodeconv(nto));
	}

	if(n.addable < Rcant){
		#
		# think carefully about the type used here
		#
		if(nto != nil)
			genmove(src, Mas, n.ty, n, nto);
		return nto;
	}

	left := n.left;
	right := n.right;
	op := n.op;
	case op{
	* =>
		fatal("can't ecom "+nodeconv(n));
		return nto;
	Oif =>
		p = bcom(left, 1, nil);
		ecom(right.left.src, nto, right.left);
		if(right.right != nil){
			pp := p;
			p = genrawop(right.left.src, IJMP, nil, nil, nil);
			patch(pp, nextinst());
			ecom(right.right.src, nto, right.right);
		}
		patch(p, nextinst());
	Ocomma =>
		ttn = left.left;
		ecom(left.src, nil, left);
		ecom(right.src, nto, right);
		tfree(ttn);
	Oname =>
		if(n.addable == Rpc){
			if(nto != nil)
				genmove(src, Mas, n.ty, n, nto);
			return nto;
		}
		fatal("can't ecom "+nodeconv(n));
	Onothing =>
		break;
	Oused =>
		if(nto != nil)
			fatal("superflous used "+nodeconv(left)+" nto "+nodeconv(nto));
		tto = talloc(left.ty, nil);
		ecom(left.src, tto, left);
		tfree(tto);
	Oas =>
		if(right.ty == tany)
			right.ty = n.ty;
		if(left.op == Oname && left.decl.ty == tany){
			if(nto == nil)
				nto = tto = talloc(right.ty, nil);
			left = nto;
			nto = nil;
		}
		if(left.op == Oinds){
			indsascom(src, nto, n);
			tfree(tto);
			break;
		}
		if(left.op == Oslice){
			slicelcom(src, nto, n);
			tfree(tto);
			break;
		}

		if(left.op == Otuple){
			if(!tupsaliased(right, left)){
				if((tn := tupblk(left)) != nil){
					tn.ty = n.ty;
					ecom(n.right.src, tn, right);
					if(nto != nil)
						genmove(src, Mas, n.ty, tn, nto);
					tfree(tto);
					break;
				}
				if((tn = tupblk(right)) != nil){
					tn.ty = n.ty;
					tuplcom(tn, left);
					if(nto != nil)
						genmove(src, Mas, n.ty, tn, nto);
					tfree(tto);
					break;
				}
				if(nto == nil && right.op == Otuple && left.ty.kind != Tadtpick){
					tuplrcom(right, left);
					tfree(tto);
					break;
				}
			}
			if(right.addable >= Ralways
			|| right.op != Oname
			|| tupaliased(right, left)){
				tright = talloc(n.ty, nil);
				ecom(n.right.src, tright, right);
				right = tright;
			}
			tuplcom(right, n.left);
			if(nto != nil)
				genmove(src, Mas, n.ty, right, nto);
			tfree(tright);
			tfree(tto);
			break;
		}

		#
		# check for left/right aliasing and build right into temporary
		#
		if(right.op == Otuple){
			if(!tupsaliased(left, right) && (tn := tupblk(right)) != nil){
				tn.ty = n.ty;
				right = tn;
			}
			else if(left.op != Oname || tupaliased(left, right))
				right = ecom(right.src, tright = talloc(right.ty, nil), right);
		}

		#
		# think carefully about types here
		#
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nto);
		ecom(n.src, left, right);
		if(nto != nil)
			genmove(src, Mas, nto.ty, left, nto);
		tfree(tleft);
		tfree(tright);
		tfree(tto);
	Ochan =>
		if(left != nil && left.addable >= Rcant)
			(left, tleft) = eacom(left, nto);
		genchan(src, left, n.ty.tof, nto);
		tfree(tleft);
	Oinds =>
		if(right.addable < Ralways){
			if(left.addable >= Rcant)
				(left, tleft) = eacom(left, nil);
		}else if(left.temps <= right.temps){
			right = ecom(right.src, tright = talloc(right.ty, nil), right);
			if(left.addable >= Rcant)
				(left, tleft) = eacom(left, nil);
		}else{
			(left, tleft) = eacom(left, nil);
			right = ecom(right.src, tright = talloc(right.ty, nil), right);
		}
		genop(n.src, op, left, right, nto);
		tfree(tleft);
		tfree(tright);
	Osnd =>
		if(right.addable < Rcant){
			if(left.addable >= Rcant)
				(left, tleft) = eacom(left, nto);
		}else if(left.temps < right.temps){
			(right, tright) = eacom(right, nto);
			if(left.addable >= Rcant)
				(left, tleft) = eacom(left, nil);
		}else{
			(left, tleft) = eacom(left, nto);
			(right, tright) = eacom(right, nil);
		}
		p = genrawop(n.src, ISEND, right, nil, left);
		p.m.offset = n.ty.size;	# for optimizer
		if(nto != nil)
			genmove(src, Mas, right.ty, right, nto);
		tfree(tleft);
		tfree(tright);
	Orcv =>
		if(nto == nil){
			ecom(n.src, tto = talloc(n.ty, nil), n);
			tfree(tto);
			return nil;
		}
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nto);
		if(left.ty.kind == Tchan){
			p = genrawop(src, IRECV, left, nil, nto);
			p.m.offset = n.ty.size;	# for optimizer
		}else{
			recvacom(src, nto, n);
		}
		tfree(tleft);
	Ocons =>
		#
		# another temp which can go with analysis
		#
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nil);
		if(!sameaddr(right, nto)){
			ecom(right.src, tto = talloc(n.ty, nto), right);
			genmove(src, Mcons, left.ty, left, tto);
			if(!sameaddr(tto, nto))
				genmove(src, Mas, nto.ty, tto, nto);
		}else
			genmove(src, Mcons, left.ty, left, nto);
		tfree(tleft);
		tfree(tto);
	Ohd =>
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nto);
		genmove(src, Mhd, nto.ty, left, nto);
		tfree(tleft);
	Otl =>
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nto);
		genmove(src, Mtl, left.ty, left, nto);
		tfree(tleft);
	Otuple =>
		if((tn := tupblk(n)) != nil){
			tn.ty = n.ty;
			genmove(src, Mas, n.ty, tn, nto);
			break;
		}
		tupcom(nto, n);
	Oadd or
	Osub or
	Omul or
	Odiv or
	Omod or
	Oand or
	Oor or
	Oxor or
	Olsh or
	Orsh or
	Oexp =>
		#
		# check for 2 operand forms
		#
		if(sameaddr(nto, left)){
			if(right.addable >= Rcant)
				(right, tright) = eacom(right, nto);
			genop(src, op, right, nil, nto);
			tfree(tright);
			break;
		}

		if(opcommute[op] && sameaddr(nto, right) && n.ty != tstring){
			if(left.addable >= Rcant)
				(left, tleft) = eacom(left, nto);
			genop(src, opcommute[op], left, nil, nto);
			tfree(tleft);
			break;
		}

		if(right.addable < left.addable
		&& opcommute[op]
		&& n.ty != tstring){
			op = opcommute[op];
			left = right;
			right = n.left;
		}
		if(left.addable < Ralways){
			if(right.addable >= Rcant)
				(right, tright) = eacom(right, nto);
		}else if(right.temps <= left.temps){
			left = ecom(left.src, tleft = talloc(left.ty, nto), left);
			if(right.addable >= Rcant)
				(right, tright) = eacom(right, nil);
		}else{
			(right, tright) = eacom(right, nto);
			left = ecom(left.src, tleft = talloc(left.ty, nil), left);
		}

		#
		# check for 2 operand forms
		#
		if(sameaddr(nto, left))
			genop(src, op, right, nil, nto);
		else if(opcommute[op] && sameaddr(nto, right) && n.ty != tstring)
			genop(src, opcommute[op], left, nil, nto);
		else
			genop(src, op, right, left, nto);
		tfree(tleft);
		tfree(tright);
	Oaddas or
	Osubas or
	Omulas or
	Odivas or
	Omodas or
	Oexpas or
	Oandas or
	Ooras or
	Oxoras or
	Olshas or
	Orshas =>
		if(left.op == Oinds){
			indsascom(src, nto, n);
			break;
		}
		if(right.addable < Rcant){
			if(left.addable >= Rcant)
				(left, tleft) = eacom(left, nto);
		}else if(left.temps < right.temps){
			(right, tright) = eacom(right, nto);
			if(left.addable >= Rcant)
				(left, tleft) = eacom(left, nil);
		}else{
			(left, tleft) = eacom(left, nto);
			(right, tright) = eacom(right, nil);
		}
		genop(n.src, op, right, nil, left);
		if(nto != nil)
			genmove(src, Mas, left.ty, left, nto);
		tfree(tleft);
		tfree(tright);
	Olen =>
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nto);
		op = -1;
		t = left.ty;
		if(t == tstring)
			op = ILENC;
		else if(t.kind == Tarray)
			op = ILENA;
		else if(t.kind == Tlist)
			op = ILENL;
		else
			fatal("can't len "+nodeconv(n));
		genrawop(src, op, left, nil, nto);
		tfree(tleft);
	Oneg =>
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nto);
		genop(n.src, op, left, nil, nto);
		tfree(tleft);
	Oinc or
	Odec =>
		if(left.op == Oinds){
			indsascom(src, nto, n);
			break;
		}
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nil);
		if(nto != nil)
			genmove(src, Mas, left.ty, left, nto);
		if(right.addable >= Rcant)
			fatal("inc/dec amount not addressable: "+nodeconv(n));
		genop(n.src, op, right, nil, left);
		tfree(tleft);
	Ospawn =>
		if(left.left.op == Oind)
			fpcall(n.src, op, left, nto);
		else
			callcom(n.src, op, left, nto);
	Oraise =>
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nil);
		genrawop(n.src, IRAISE, left, nil, nil);
		tfree(tleft);
	Ocall =>
		if(left.op == Oind)
			fpcall(esrc(src, n.src, nto), op, n, nto);
		else
			callcom(esrc(src, n.src, nto), op, n, nto);
	Oref =>
		t = left.ty;
		if(left.op == Oname && left.decl.store == Dfn || left.op == Omdot && left.right.op == Oname && left.right.decl.store == Dfn){	# create a function reference
			mod, ind: ref Node;

			d := left.decl;
			if(left.op == Omdot){
				d = left.right.decl;
				mod = left.left;
			}
			else if(d.eimport != nil)
				mod = d.eimport;
			else{
				mod = rewrite(mkn(Oself, nil, nil));
				addiface(nil, d);
			}
			sumark(mod);
			tto = talloc(n.ty, nto);
			genrawop(src, INEW, mktn(usetype(tfnptr)), nil, tto);
			tright = ref znode;
			tright.src = src;
			tright.op = Oind;
			tright.left = tto;
			tright.right = nil;
			tright.ty = tany;
			sumark(tright);
			ecom(src, tright, mod);
			ind = mkunary(Oind, mkbin(Oadd, dupn(0, src, tto), mkconst(src, big IBY2WD)));
			ind.ty = ind.left.ty = ind.left.right.ty = tint;
			tright.op = Oas;
			tright.left = ind;
			tright.right = mkdeclname(src, d);
			tright.ty = tright.right.ty = tint;
			sumark(tright);
			if(mod.op == Oself && newfnptr)
				tright.right.addable = Rnoff;
			else
				tright.right.addable = Roff;
			ecom(src, nil, tright);
			if(!sameaddr(tto, nto))
				genmove(src, Mas, n.ty, tto, nto);
			tfree(tto);
			break;
		}
		if(left.op == Oname && left.decl.store == Dtype){
			genrawop(src, INEW, mktn(t), nil, nto);
			break;
		}
		if(t.kind == Tadt && t.tags != nil){
			pickdupcom(src, nto, left);
			break;
		}

		tt := t;
		if(left.op == Oconst && left.decl.store == Dtag)
			t = left.decl.ty.tof;

		#
		# could eliminate temp if nto does not occur
		# in tuple initializer
		#
		tto = talloc(n.ty, nto);
		genrawop(src, INEW, mktn(t), nil, tto);
		tright = ref znode;
		tright.op = Oind;
		tright.left = tto;
		tright.right = nil;
		tright.ty = tt;
		sumark(tright);
		ecom(src, tright, left);
		if(!sameaddr(tto, nto))
			genmove(src, Mas, n.ty, tto, nto);
		tfree(tto);
	Oload =>
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nto);
		tright = talloc(tint, nil);
		if(LDT)
			genrawop(src, ILOAD, left, right, nto);
		else{
			genrawop(src, ILEA, right, nil, tright);
			genrawop(src, ILOAD, left, tright, nto);
		}
		tfree(tleft);
		tfree(tright);
	Ocast =>
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nto);
		t = left.ty;
		if(t.kind == Tfix || n.ty.kind == Tfix){
			op = casttab[t.kind][n.ty.kind];
			if(op == ICVTXX)
				genfixcastop(src, op, left, nto);
			else{
				ttn = sumark(mkrconst(src, scale2(t, n.ty)));
				genrawop(src, op, left, ttn, nto);
			}
		}
		else
			genrawop(src, casttab[t.kind][n.ty.kind], left, nil, nto);
		tfree(tleft);
	Oarray =>
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nto);
		if(arrayz)
			genrawop(esrc(src, left.src, nto), INEWAZ, left, mktn(n.ty.tof), nto);
		else
			genrawop(esrc(src, left.src, nto), INEWA, left, mktn(n.ty.tof), nto);
		if(right != nil)
			arraycom(nto, right);
		tfree(tleft);
	Oslice =>
		tn := right.right;
		right = right.left;

		#
		# make the left node of the slice directly addressable
		# therefore, if it's len is taken (via tn),
		# left's tree won't be rewritten
		#
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nil);

		if(tn.op == Onothing){
			tn = mkn(Olen, left, nil);
			tn.src = src;
			tn.ty = tint;
			sumark(tn);
		}
		if(tn.addable < Ralways){
			if(right.addable >= Rcant)
				(right, tright) = eacom(right, nil);
		}else if(right.temps <= tn.temps){
			tn = ecom(tn.src, ttn = talloc(tn.ty, nil), tn);
			if(right.addable >= Rcant)
				(right, tright) = eacom(right, nil);
		}else{
			(right, tright) = eacom(right, nil);
			tn = ecom(tn.src, ttn = talloc(tn.ty, nil), tn);
		}
		op = ISLICEA;
		if(nto.ty == tstring)
			op = ISLICEC;

		#
		# overwrite the destination last,
		# since it might be used in computing the slice bounds
		#
		if(!sameaddr(left, nto))
			ecom(left.src, nto, left);

		genrawop(src, op, right, tn, nto);
		tfree(tleft);
		tfree(tright);
		tfree(ttn);
	Oindx =>
		if(right.addable < Rcant){
			if(left.addable >= Rcant)
				(left, tleft) = eacom(left, nto);
		}else if(left.temps < right.temps){
			(right, tright) = eacom(right, nto);
			if(left.addable >= Rcant)
				(left, tleft) = eacom(left, nil);
		}else{
			(left, tleft) = eacom(left, nto);
			(right, tright) = eacom(right, nil);
		}
		if(nto.addable >= Ralways)
			nto = ecom(src, tto = talloc(nto.ty, nil), nto);
		op = IINDX;
		case left.ty.tof.size{
		IBY2LG =>
			op = IINDL;
			if(left.ty.tof == treal)
				op = IINDF;
		IBY2WD =>
			op = IINDW;
		1 =>
			op = IINDB;
		}
		genrawop(src, op, left, nto, right);
		if(tleft != nil && tleft.decl != nil)
			tfreelater(tleft);
		else
			tfree(tleft);
		tfree(tright);
		tfree(tto);
	Oind =>
		(n, tleft) = eacom(n, nto);
		genmove(src, Mas, n.ty, n, nto);
		tfree(tleft);
	Onot or
	Oandand or
	Ooror or
	Oeq or
	Oneq or
	Olt or
	Oleq or
	Ogt or
	Ogeq =>
		p = bcom(n, 1, nil);
		genmove(src, Mas, tint, sumark(mkconst(src, big 1)), nto);
		pp := genrawop(src, IJMP, nil, nil, nil);
		patch(p, nextinst());
		genmove(src, Mas, tint, sumark(mkconst(src, big 0)), nto);
		patch(pp, nextinst());
	Oself =>
		if(newfnptr){
			if(nto != nil)
				genrawop(src, ISELF, nil, nil, nto);
			break;
		}
		tn := sumark(mkdeclname(src, selfdecl));
		p = genbra(src, Oneq, tn, sumark(mkdeclname(src, nildecl)));
		n.op = Oload;
		ecom(src, tn, n);
		patch(p, nextinst());
		genmove(src, Mas, n.ty, tn, nto);
	}
	return nto;
}

#
# compile exp n to yield an addressable expression
# use reg to build a temporary; if t is a temp, it is usable
#
# note that 0adr's are strange as they are only used
# for calculating the addresses of fields within adt's.
# therefore an Oind is the parent or grandparent of the Oadr,
# and we pick off all of the cases where Oadr's argument is not
# addressable by looking from the Oind.
#
eacom(n, t: ref Node): (ref Node, ref Node)
{
	reg: ref Node;

	if(n.op == Ocomma){
		tn := n.left.left;
		ecom(n.left.src, nil, n.left);
		nn := eacom(n.right, t);
		tfree(tn);
		return nn;
	}

	if(debug['e'] || debug['E'])
		print("eacom: %s\n", nodeconv(n));

	left := n.left;
	if(n.op != Oind){
		ecom(n.src, reg = talloc(n.ty, t), n);
		reg.src = n.src;
		return (reg, reg);
	}

	if(left.op == Oadd && left.right.op == Oconst){
		if(left.left.op == Oadr){
			(left.left.left, reg) = eacom(left.left.left, t);
			sumark(n);
			if(n.addable >= Rcant)
				fatal("eacom can't make node addressable: "+nodeconv(n));
			return (n, reg);
		}
		reg = talloc(left.left.ty, t);
		ecom(left.left.src, reg, left.left);
		left.left.decl = reg.decl;
		left.left.addable = Rreg;
		left.left = reg;
		left.addable = Raadr;
		n.addable = Radr;
	}else if(left.op == Oadr){
		reg = talloc(left.left.ty, t);
		ecom(left.left.src, reg, left.left);

		#
		# sleaze: treat the temp as the type of the field, not the enclosing structure
		#
		reg.ty = n.ty;
		reg.src = n.src;
		return (reg, reg);
	}else{
		reg = talloc(left.ty, t);
		ecom(left.src, reg, left);
		n.left = reg;
		n.addable = Radr;
	}
	return (n, reg);
}

#
# compile an assignment to an array slice
#
slicelcom(src: Src, nto, n: ref Node): ref Node
{
	tleft, tright, tv: ref Node;

	left := n.left.left;
	right := n.left.right.left;
	v := n.right;
	if(right.addable < Ralways){
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nto);
	}else if(left.temps <= right.temps){
		right = ecom(right.src, tright = talloc(right.ty, nto), right);
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nil);
	}else{
		(left, tleft) = eacom(left, nil);		# dangle on right and v
		right = ecom(right.src, tright = talloc(right.ty, nil), right);
	}

	case n.op{
	Oas =>
		if(v.addable >= Rcant)
			(v, tv) = eacom(v, nil);
	}

	genrawop(n.src, ISLICELA, v, right, left);
	if(nto != nil)
		genmove(src, Mas, n.ty, left, nto);
	tfree(tleft);
	tfree(tv);
	tfree(tright);
	return nto;
}

#
# compile an assignment to a string location
#
indsascom(src: Src, nto, n: ref Node): ref Node
{
	tleft, tright, tv, tu, u: ref Node;

	left := n.left.left;
	right := n.left.right;
	v := n.right;
	if(right.addable < Ralways){
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nto);
	}else if(left.temps <= right.temps){
		right = ecom(right.src, tright = talloc(right.ty, nto), right);
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nil);
	}else{
		(left, tleft) = eacom(left, nil);		# dangle on right and v
		right = ecom(right.src, tright = talloc(right.ty, nil), right);
	}

	case n.op{
	Oas =>
		if(v.addable >= Rcant)
			(v, tv) = eacom(v, nil);
	Oinc or
	Odec =>
		if(v.addable >= Rcant)
			fatal("inc/dec amount not addable");
		u = tu = talloc(tint, nil);
		genop(n.left.src, Oinds, left, right, u);
		if(nto != nil)
			genmove(src, Mas, n.ty, u, nto);
		nto = nil;
		genop(n.src, n.op, v, nil, u);
		v = u;
	Oaddas or
	Osubas or
	Omulas or
	Odivas or
	Omodas or
	Oexpas or
	Oandas or
	Ooras or
	Oxoras or
	Olshas or
	Orshas =>
		if(v.addable >= Rcant)
			(v, tv) = eacom(v, nil);
		u = tu = talloc(tint, nil);
		genop(n.left.src, Oinds, left, right, u);
		genop(n.src, n.op, v, nil, u);
		v = u;
	}

	genrawop(n.src, IINSC, v, right, left);
	tfree(tleft);
	tfree(tv);
	tfree(tright);
	tfree(tu);
	if(nto != nil)
		genmove(src, Mas, n.ty, v, nto);
	return nto;
}

callcom(src: Src, op: int, n, ret: ref Node)
{
	tmod, tind: ref Node;
	callee: ref Decl;

	args := n.right;
	nfn := n.left;
	case(nfn.op){
		Odot =>
			callee = nfn.right.decl;
			nfn.addable = Rpc;
		Omdot =>
			callee = nfn.right.decl;
		Oname =>
			callee = nfn.decl;
		* =>
			callee = nil;
			fatal("bad call op in callcom");
	}
	if(nfn.addable != Rpc && nfn.addable != Rmpc)
		fatal("can't gen call addresses");
	if(nfn.ty.tof != tnone && ret == nil){
		ecom(src, tmod = talloc(nfn.ty.tof, nil), n);
		tfree(tmod);
		return;
	}
	if(ispoly(callee))
		addfnptrs(callee, 0);
	if(nfn.ty.varargs != byte 0){
		d := dupdecl(nfn.right.decl);
		nfn.decl = d;
		d.desc = gendesc(d, idoffsets(nfn.ty.ids, MaxTemp, MaxAlign), nfn.ty.ids);
	}

	frame := talloc(tint, nil);

	mod := nfn.left;
	ind := nfn.right;
	if(nfn.addable == Rmpc){
		if(mod.addable >= Rcant)
			(mod, tmod) = eacom(mod, nil);		# dangle always
		if(ind.op != Oname && ind.addable >= Ralways){
			tind = talloc(ind.ty, nil);
			ecom(ind.src, tind, ind);
			ind = tind;
		}
		else if(ind.decl != nil && ind.decl.store != Darg)
			ind.addable = Roff;
	}

	#
	# stop nested uncalled frames
	# otherwise exception handling very complicated
	#
	for(a := args; a != nil; a = a.right){
		if(hascall(a.left)){
			tn := talloc(a.left.ty, nil);
			ecom(a.left.src, tn, a.left);
			a.left = tn;
			tn.flags |= byte TEMP;
		}
	}

	#
	# allocate the frame
	#
	if(nfn.addable == Rmpc && nfn.ty.varargs == byte 0){
		genrawop(src, IMFRAME, mod, ind, frame);
	}else if(nfn.op == Odot){
		genrawop(src, IFRAME, nfn.left, nil, frame);
	}else{
		in := genrawop(src, IFRAME, nil, nil, frame);
		in.sm = Adesc;
		in.s.decl = nfn.decl;
	}

	#
	# build a fake node for the argument area
	#
	toff := ref znode;
	tadd := ref znode;
	pass := ref znode;
	toff.op = Oconst;
	toff.c = ref Const(big 0, 0.0);	# jrf - added initialization
	toff.addable = Rconst;
	toff.ty = tint;
	tadd.op = Oadd;
	tadd.addable = Raadr;
	tadd.left = frame;
	tadd.right = toff;
	tadd.ty = tint;
	pass.op = Oind;
	pass.addable = Radr;
	pass.left = tadd;

	#
	# compile all the args
	#
	d := nfn.ty.ids;
	off := 0;
	for(a = args; a != nil; a = a.right){
		off = d.offset;
		toff.c.val = big off;
		if(d.ty.kind == Tpoly)
			pass.ty = a.left.ty;
		else
			pass.ty = d.ty;
		ecom(a.left.src, pass, a.left);
		d = d.next;
		if(int a.left.flags & TEMP)
			tfree(a.left);
	}
	if(off > maxstack)
		maxstack = off;

	#
	# pass return value
	#
	if(ret != nil){
		toff.c.val = big(REGRET*IBY2WD);
		pass.ty = nfn.ty.tof;
		p := genrawop(src, ILEA, ret, nil, pass);
		p.m.offset = ret.ty.size;	# for optimizer
	}

	#
	# call it
	#
	iop: int;
	if(nfn.addable == Rmpc){
		iop = IMCALL;
		if(op == Ospawn)
			iop = IMSPAWN;
		genrawop(src, iop, frame, ind, mod);
		tfree(tmod);
		tfree(tind);
	}else if(nfn.op == Odot){
		iop = ICALL;
		if(op == Ospawn)
			iop = ISPAWN;
		genrawop(src, iop, frame, nil, nfn.right);
	}else{
		iop = ICALL;
		if(op == Ospawn)
			iop = ISPAWN;
		in := genrawop(src, iop, frame, nil, nil);
		in.d.decl = nfn.decl;
		in.dm = Apc;
	}
	tfree(frame);
}

#
# initialization code for arrays
# a must be addressable (< Rcant)
#
arraycom(a, elems: ref Node)
{
	top, out: ref Inst;
	ri, n, wild: ref Node;

	if(debug['A'])
		print("arraycom: %s %s\n", nodeconv(a), nodeconv(elems));

	# c := elems.ty.cse;
	# don't use c.wild in case we've been inlined
	wild = nil;
	for(e := elems; e != nil; e = e.right)
		for(q := e.left.left; q != nil; q = q.right)
			if(q.left.op == Owild)
				wild = e.left;
	if(wild != nil)
		arraydefault(a, wild.right);

	tindex := ref znode;
	fake := ref znode;
	tmp := talloc(tint, nil);
	tindex.op = Oindx;
	tindex.addable = Rcant;
	tindex.left = a;
	tindex.right = nil;
	tindex.ty = tint;
	fake.op = Oind;
	fake.addable = Radr;
	fake.left = tmp;
	fake.ty = a.ty.tof;

	for(e = elems; e != nil; e = e.right){
		#
		# just duplicate the initializer for Oor
		#
		for(q = e.left.left; q != nil; q = q.right){
			if(q.left.op == Owild)
				continue;
	
			body := e.left.right;
			if(q.right != nil)
				body = dupn(0, nosrc, body);
			top = nil;
			out = nil;
			ri = nil;
			if(q.left.op == Orange){
				#
				# for(i := q.left.left; i <= q.left.right; i++)
				#
				ri = talloc(tint, nil);
				ri.src = q.left.src;
				ecom(q.left.src, ri, q.left.left);
	
				# i <= q.left.right;
				n = mkn(Oleq, ri, q.left.right);
				n.src = q.left.src;
				n.ty = tint;
				top = nextinst();
				out = bcom(n, 1, nil);
	
				tindex.right = ri;
			}else{
				tindex.right = q.left;
			}
	
			tindex.addable = Rcant;
			tindex.src = q.left.src;
			ecom(tindex.src, tmp, tindex);
	
			ecom(body.src, fake, body);
	
			if(q.left.op == Orange){
				# i++
				n = mkbin(Oinc, ri, sumark(mkconst(ri.src, big 1)));
				n.ty = tint;
				n.addable = Rcant;
				ecom(n.src, nil, n);
	
				# jump to test
				patch(genrawop(q.left.src, IJMP, nil, nil, nil), top);
				patch(out, nextinst());
				tfree(ri);
			}
		}
	}
	tfree(tmp);
}

#
# default initialization code for arrays.
# compiles to
#	n = len a;
#	while(n){
#		n--;
#		a[n] = elem;
#	}
#
arraydefault(a, elem: ref Node)
{
	e: ref Node;

	if(debug['A'])
		print("arraydefault: %s %s\n", nodeconv(a), nodeconv(elem));

	t := mkn(Olen, a, nil);
	t.src = elem.src;
	t.ty = tint;
	t.addable = Rcant;
	n := talloc(tint, nil);
	n.src = elem.src;
	ecom(t.src, n, t);

	top := nextinst();
	out := bcom(n, 1, nil);

	t = mkbin(Odec, n, sumark(mkconst(elem.src, big 1)));
	t.ty = tint;
	t.addable = Rcant;
	ecom(t.src, nil, t);

	if(elem.addable >= Rcant)
		(elem, e) = eacom(elem, nil);

	t = mkn(Oindx, a, n);
	t.src = elem.src;
	t = mkbin(Oas, mkunary(Oind, t), elem);
	t.ty = elem.ty;
	t.left.ty = elem.ty;
	t.left.left.ty = tint;
	sumark(t);
	ecom(t.src, nil, t);

	patch(genrawop(t.src, IJMP, nil, nil, nil), top);

	tfree(n);
	tfree(e);
	patch(out, nextinst());
}

tupcom(nto, n: ref Node)
{
	if(debug['Y'])
		print("tupcom %s\nto %s\n", nodeconv(n), nodeconv(nto));

	#
	# build a fake node for the tuple
	#
	toff := ref znode;
	tadd := ref znode;
	fake := ref znode;
	tadr := ref znode;
	toff.op = Oconst;
	toff.c = ref Const(big 0, 0.0);	# no val => may get fatal error below (jrf)
	toff.ty = tint;
	tadr.op = Oadr;
	tadr.left = nto;
	tadr.ty = tint;
	tadd.op = Oadd;
	tadd.left = tadr;
	tadd.right = toff;
	tadd.ty = tint;
	fake.op = Oind;
	fake.left = tadd;
	sumark(fake);
	if(fake.addable >= Rcant)
		fatal("tupcom: bad value exp "+nodeconv(fake));

	#
	# compile all the exps
	#
	d := n.ty.ids;
	for(e := n.left; e != nil; e = e.right){
		toff.c.val = big d.offset;
		fake.ty = d.ty;
		ecom(e.left.src, fake, e.left);
		d = d.next;
	}
}

tuplcom(n, nto: ref Node)
{
	if(debug['Y'])
		print("tuplcom %s\nto %s\n", nodeconv(n), nodeconv(nto));

	#
	# build a fake node for the tuple
	#
	toff := ref znode;
	tadd := ref znode;
	fake := ref znode;
	tadr := ref znode;
	toff.op = Oconst;
	toff.c = ref Const(big 0, 0.0);	# no val => may get fatal error below (jrf)
	toff.ty = tint;
	tadr.op = Oadr;
	tadr.left = n;
	tadr.ty = tint;
	tadd.op = Oadd;
	tadd.left = tadr;
	tadd.right = toff;
	tadd.ty = tint;
	fake.op = Oind;
	fake.left = tadd;
	sumark(fake);
	if(fake.addable >= Rcant)
		fatal("tuplcom: bad value exp for "+nodeconv(fake));

	#
	# compile all the exps
	#
	tas := ref znode;
	d := nto.ty.ids;
	if(nto.ty.kind == Tadtpick)
		d = nto.ty.tof.ids.next;
	for(e := nto.left; e != nil; e = e.right){
		as := e.left;
		if(as.op != Oname || as.decl != nildecl){
			toff.c.val = big d.offset;
			fake.ty = d.ty;
			fake.src = as.src;
			if(as.addable < Rcant)
				genmove(as.src, Mas, d.ty, fake, as);
			else{
				tas.op = Oas;
				tas.ty = d.ty;
				tas.src = as.src;
				tas.left = as;
				tas.right = fake;
				tas.addable = Rcant;
				ecom(as.src, nil, tas);
			}
		}
		d = d.next;
	}
}

tuplrcom(n: ref Node, nto: ref Node)
{
	s, d, tas: ref Node;
	de: ref Decl;

	tas = ref znode;
	de = nto.ty.ids;
	for((s, d) = (n.left, nto.left); s != nil && d != nil; (s, d) = (s.right, d.right)){
		if(d.left.op != Oname || d.left.decl != nildecl){
			tas.op = Oas;
			tas.ty = de.ty;
			tas.src = s.left.src;
			tas.left = d.left;
			tas.right = s.left;
			sumark(tas);
			ecom(tas.src, nil, tas);
		}
		de = de.next;
	}
	if(s != nil || d != nil)
		fatal("tuplrcom");
}

#
# boolean compiler
# fall through when condition == true
#
bcom(n: ref Node, iftrue: int, b: ref Inst): ref Inst
{
	tleft, tright: ref Node;

	if(n.op == Ocomma){
		tn := n.left.left;
		ecom(n.left.src, nil, n.left);
		b = bcom(n.right, iftrue, b);
		tfree(tn);
		return b;
	}

	if(debug['b'])
		print("bcom %s %d\n", nodeconv(n), iftrue);

	left := n.left;
	right := n.right;
	op := n.op;
	case op{
	Onothing =>
		return b;
	Onot =>
		return bcom(n.left, !iftrue, b);
	Oandand =>
		if(!iftrue)
			return oror(n, iftrue, b);
		return andand(n, iftrue, b);
	Ooror =>
		if(!iftrue)
			return andand(n, iftrue, b);
		return oror(n, iftrue, b);
	Ogt or
	Ogeq or
	Oneq or
	Oeq or
	Olt or
	Oleq =>
		break;
	* =>
		if(n.ty.kind == Tint){
			right = mkconst(n.src, big 0);
			right.addable = Rconst;
			left = n;
			op = Oneq;
			break;
		}
		fatal("can't bcom "+nodeconv(n));
		return b;
	}

	if(iftrue)
		op = oprelinvert[op];

	if(left.addable < right.addable){
		t := left;
		left = right;
		right = t;
		op = opcommute[op];
	}

	if(right.addable < Ralways){
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nil);
	}else if(left.temps <= right.temps){
		right = ecom(right.src, tright = talloc(right.ty, nil), right);
		if(left.addable >= Rcant)
			(left, tleft) = eacom(left, nil);
	}else{
		(left, tleft) = eacom(left, nil);
		right = ecom(right.src, tright = talloc(right.ty, nil), right);
	}
	bb := genbra(n.src, op, left, right);
	bb.branch = b;
	tfree(tleft);
	tfree(tright);
	return bb;
}

andand(n: ref Node, iftrue: int, b: ref Inst): ref Inst
{
	if(debug['b'])
		print("andand %s\n", nodeconv(n));
	b = bcom(n.left, iftrue, b);
	b = bcom(n.right, iftrue, b);
	return b;
}

oror(n: ref Node, iftrue: int, b: ref Inst): ref Inst
{
	if(debug['b'])
		print("oror %s\n", nodeconv(n));
	bb := bcom(n.left, !iftrue, nil);
	b = bcom(n.right, iftrue, b);
	patch(bb, nextinst());
	return b;
}

#
# generate code for a recva expression
# this is just a hacked up small alt
#
recvacom(src: Src, nto, n: ref Node)
{
	p: ref Inst;

	left := n.left;

	labs := array[1] of Label;
	labs[0].isptr = left.addable >= Rcant;
	c := ref Case;
	c.nlab = 1;
	c.nsnd = 0;
	c.offset = 0;
	c.labs = labs;
	talt := mktalt(c);

	which := talloc(tint, nil);
	tab := talloc(talt, nil);

	#
	# build the node for the address of each channel,
	# the values to send, and the storage for values received
	#
	off := ref znode;
	adr := ref znode;
	add := ref znode;
	slot := ref znode;
	off.op = Oconst;
	off.c = ref Const(big 0, 0.0);		# jrf - added initialization
	off.ty = tint;
	off.addable = Rconst;
	adr.op = Oadr;
	adr.left = tab;
	adr.ty = tint;
	add.op = Oadd;
	add.left = adr;
	add.right = off;
	add.ty = tint;
	slot.op = Oind;
	slot.left = add;
	sumark(slot);

	#
	# gen the channel
	# this sleaze is lying to the garbage collector
	#
	off.c.val = big(2*IBY2WD);
	if(left.addable < Rcant)
		genmove(src, Mas, tint, left, slot);
	else{
		slot.ty = left.ty;
		ecom(src, slot, left);
		slot.ty = nil;
	}

	#
	# gen the value
	#
	off.c.val += big IBY2WD;
	p = genrawop(left.src, ILEA, nto, nil, slot);
	p.m.offset = nto.ty.size;	# for optimizer

	#
	# number of senders and receivers
	#
	off.c.val = big 0;
	genmove(src, Mas, tint, sumark(mkconst(src, big 0)), slot);
	off.c.val += big IBY2WD;
	genmove(src, Mas, tint, sumark(mkconst(src, big 1)), slot);
	off.c.val += big IBY2WD;

	p = genrawop(src, IALT, tab, nil, which);
	p.m.offset = talt.size;	# for optimizer
	tfree(which);
	tfree(tab);
}

#
# generate code to duplicate an adt with pick fields
# this is just a hacked up small pick
# n is Oind(exp)
#
pickdupcom(src: Src, nto, n: ref Node)
{
	jmps: ref Inst;

	if(n.op != Oind)
		fatal("pickdupcom not Oind: " + nodeconv(n));

	t := n.ty;
	nlab := t.decl.tag;

	#
	# generate global which has case labels
	#
	d := mkids(src, enter(".c"+string nlabel++, 0), mktype(src.start, src.stop, Tcase, nil, nil), nil);
	d.init = mkdeclname(src, d);

	clab := ref znode;
	clab.addable = Rmreg;
	clab.left = nil;
	clab.right = nil;
	clab.op = Oname;
	clab.ty = d.ty;
	clab.decl = d;

	#
	# generate a temp to hold the real value
	# then generate a case on the tag
	#
	orig := n.left;
	tmp := talloc(orig.ty, nil);
	ecom(src, tmp, orig);
	orig = mkunary(Oind, tmp);
	orig.ty = tint;
	sumark(orig);

	dest := mkunary(Oind, nto);
	dest.ty = nto.ty.tof;
	sumark(dest);

	genrawop(src, ICASE, orig, nil, clab);

	labs := array[nlab] of Label;

	i := 0;
	jmps = nil;
	for(tg := t.tags; tg != nil; tg = tg.next){
		stg := tg;
		for(; tg.next != nil; tg = tg.next)
			if(stg.ty != tg.next.ty)
				break;
		start := sumark(simplify(mkdeclname(src, stg)));
		stop := start;
		node := start;
		if(stg != tg){
			stop = sumark(simplify(mkdeclname(src, tg)));
			node = mkbin(Orange, start, stop);
		}

		labs[i].start = start;
		labs[i].stop = stop;
		labs[i].node = node;
		labs[i++].inst = nextinst();

		genrawop(src, INEW, mktn(tg.ty.tof), nil, nto);
		genmove(src, Mas, tg.ty.tof, orig, dest);

		j := genrawop(src, IJMP, nil, nil, nil);
		j.branch = jmps;
		jmps = j;
	}

	#
	# this should really be a runtime error
	#
	wild := genrawop(src, IJMP, nil, nil, nil);
	patch(wild, wild);

	patch(jmps, nextinst());
	tfree(tmp);

	if(i > nlab)
		fatal("overflowed label tab for pickdupcom");

	c := ref Case;
	c.nlab = i;
	c.nsnd = 0;
	c.labs = labs;
	c.iwild = wild;

	d.ty.cse = c;
	usetype(d.ty);
	installids(Dglobal, d);
}

#
# see if name n occurs anywhere in e
#
tupaliased(n, e: ref Node): int
{
	for(;;){
		if(e == nil)
			return 0;
		if(e.op == Oname && e.decl == n.decl)
			return 1;
		if(tupaliased(n, e.left))
			return 1;
		e = e.right;
	}
	return 0;
}

#
# see if any name in n occurs anywere in e
#
tupsaliased(n, e: ref Node): int
{
	for(;;){
		if(n == nil)
			return 0;
		if(n.op == Oname && tupaliased(n, e))
			return 1;
		if(tupsaliased(n.left, e))
			return 1;
		n = n.right;
	}
	return 0;
}

#
# put unaddressable constants in the global data area
#
globalconst(n: ref Node): ref Decl
{
	s := enter(".i." + hex(int n.c.val, 8), 0);
	d := s.decl;
	if(d == nil){
		d = mkids(n.src, s, tint, nil);
		installids(Dglobal, d);
		d.init = n;
		d.refs++;
	}
	return d;
}

globalBconst(n: ref Node): ref Decl
{
	s := enter(".B." + bhex(n.c.val, 16), 0);
	d := s.decl;
	if(d == nil){
		d = mkids(n.src, s, tbig, nil);
		installids(Dglobal, d);
		d.init = n;
		d.refs++;
	}
	return d;
}

globalbconst(n: ref Node): ref Decl
{
	s := enter(".b." + hex(int n.c.val & 16rff, 2), 0);
	d := s.decl;
	if(d == nil){
		d = mkids(n.src, s, tbyte, nil);
		installids(Dglobal, d);
		d.init = n;
		d.refs++;
	}
	return d;
}

globalfconst(n: ref Node): ref Decl
{
	ba := array[8] of byte;
	export_real(ba, array[] of {n.c.rval});
	fs := ".f.";
	for(i := 0; i < 8; i++)
		fs += hex(int ba[i], 2);
	if(fs != ".f." + bhex(math->realbits64(n.c.rval), 16))
		fatal("bad globalfconst number");
	s := enter(fs, 0);
	d := s.decl;
	if(d == nil){
		d = mkids(n.src, s, treal, nil);
		installids(Dglobal, d);
		d.init = n;
		d.refs++;
	}
	return d;
}

globalsconst(n: ref Node): ref Decl
{
	s := n.decl.sym;
	n.decl = nil;
	d := s.decl;
	if(d == nil){
		d = mkids(n.src, s, tstring, nil);
		installids(Dglobal, d);
		d.init = n;
	}
	d.refs++;
	n.decl = d;
	return d;
}

#
# make a global of type t
# used to make initialized data
#
globalztup(t: ref Type): ref Decl
{
	z := ".z." + string t.size + ".";
	desc := t.decl.desc;
	for(i := 0; i < desc.nmap; i++)
		z += hex(int desc.map[i], 2);
	s := enter(z, 0);
	d := s.decl;
	if(d == nil){
		d = mkids(t.src, s, t, nil);
		installids(Dglobal, d);
		d.init = nil;
	}
	d.refs++;
	return d;
}

subst(d: ref Decl, e: ref Node, n: ref Node): ref Node
{
	if(n == nil)
		return nil;
	if(n.op == Oname){
		if(d == n.decl){
			n = dupn(0, nosrc, e);
			n.ty = d.ty;
		}
		return n;
	}
	n.left = subst(d, e, n.left);
	n.right = subst(d, e, n.right);
	return n;
}

inline(n: ref Node): ref Node
{
	e, tn: ref Node;
	t: ref Type;
	d: ref Decl;

if(debug['z']) sys->print("inline1: %s\n", nodeconv(n));
	if(n.left.op == Oname)
		d = n.left.decl;
	else
		d = n.left.right.decl;
	e = d.init;
	t = e.ty;
	e = dupn(1, n.src, e.right.left.left);
	n = n.right;
	for(d = t.ids; d != nil && n != nil; d = d.next){
		if(hasside(n.left, 0) && occurs(d, e) != 1){
			tn = talloc(d.ty, nil);
			e = mkbin(Ocomma, mkbin(Oas, tn, n.left), subst(d, tn, e));
			e.ty = e.right.ty;
			e.left.ty = d.ty;
		}
		else
			e = subst(d, n.left, e);
		n = n.right;
	}
	if(d != nil || n != nil)
		fatal("bad arg match in inline()");
if(debug['z']) sys->print("inline2: %s\n", nodeconv(e));
	return e;
}

fpcall(src: Src, op: int, n: ref Node, ret: ref Node)
{
	tp, e, mod, ind: ref Node;

	e = n.left.left;
	if(e.addable >= Rcant)
		(e, tp) = eacom(e, nil);
	mod = mkunary(Oind, e);
	ind = mkunary(Oind, mkbin(Oadd, dupn(0, src, e), mkconst(src, big IBY2WD)));
	n.left = mkbin(Omdot, mod, ind);
	n.left.ty = e.ty.tof;
	mod.ty = ind.ty = ind.left.ty = ind.left.right.ty = tint;
	sumark(n);
	callcom(src, op, n, ret);
	tfree(tp);
}
