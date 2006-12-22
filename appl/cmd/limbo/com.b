# back end

breaks:		array of ref Inst;
conts:		array of ref Inst;
labels:		array of ref Decl;
bcscps:		array of ref Node;
labdep:		int;
nocont:		ref Inst;
nlabel:		int;

scp:			int;
scps:=		array[MaxScope] of ref Node;

curfn:	ref Decl;

pushscp(n : ref Node)
{
	if (scp >= MaxScope)
		fatal("scope too deep");
	scps[scp++] = n;
}

popscp()
{
	scp--;
}

curscp() : ref Node
{
	if (scp == 0)
		return nil;
	return scps[scp-1];
}

zeroscopes(stop : ref Node)
{
	i : int;
	cs : ref Node;

	for (i = scp-1; i >= 0; i--) {
		cs = scps[i];
		if (cs == stop)
			break;
		zcom(cs.left, nil);
	}
}

zeroallscopes(n: ref Node, nn: array of ref Node)
{
	if(n == nil)
		return;
	for(; n != nil; n = n.right){
		case(n.op){
		Oscope =>
			zeroallscopes(n.right, nn);
			zcom(n.left, nn);
			return;
		Olabel or
		Odo =>
			zeroallscopes(n.right, nn);
			return;
		Oif or
		Ofor =>
			zeroallscopes(n.right.left, nn);
			zeroallscopes(n.right.right, nn);
			return;
		Oalt or
		Ocase or
		Opick or
		Oexcept =>
			for(n = n.right; n != nil; n = n.right)
				zeroallscopes(n.left.right, nn);
			return;
		Oseq =>
			zeroallscopes(n.left, nn);
			break;
		Oexstmt =>
			zeroallscopes(n.left, nn);
			zeroallscopes(n.right, nn);
			return;
		* =>
			return;
		}
	}
}

excs: ref Except;

installexc(en: ref Node, p1: ref Inst, p2: ref Inst, zn: ref Node)
{
	e := ref Except;
	e.p1 = p1;
	e.p2 = p2;
	e.c = en.ty.cse;
	e.d = en.left.decl;
	e.zn = zn;
	e.next = excs;
	excs = e;

	ne := 0;
	c := e.c;
	for(i := 0; i < c.nlab; i++){
		lab := c.labs[i];
		if(lab.start.ty.kind == Texception)
			ne++;
	}
	e.ne = ne;
}

inlist(d: ref Decl, dd: ref Decl): int
{
	for( ; dd != nil; dd = dd.next)
		if(d == dd)
			return 1;
	return 0;
}

excdesc()
{
	dd, nd: ref Decl;

	for(e := excs; e != nil; e = e.next){
		if(e.zn != nil){
			dd = nil;
			maxo := 0;
			for(n := e.zn ; n != nil; n = n.right){
				d := n.decl;
				d.locals = d.next;
				if(!inlist(d, dd)){
					d.next = dd;
					dd = d;
					o := d.offset+d.ty.size;
					if(o > maxo)
						maxo = o;
				}
			}
			e.desc = gendesc(e.d, align(maxo, MaxAlign), dd);
			for(d := dd; d != nil; d = nd){
				nd = d.next;
				d.next = d.locals;
				d.locals = nil;
			}
			e.zn = nil;
		}
	}
}

reve(e: ref Except): ref Except
{
	l, n: ref Except;

	l = nil;
	for( ; e != nil; e = n){
		n = e.next;
		e.next = l;
		l = e;
	}
	return l;
}

ckinline0(n: ref Node, d: ref Decl): int
{
	dd: ref Decl;

	if(n == nil)
		return 1;
	if(n.op == Oname){
		dd = n.decl;
		if(d == dd)
			return 0;
		if(int dd.inline == 1)
			return ckinline0(dd.init.right, d);
		return 1;
	}
	return ckinline0(n.left, d) && ckinline0(n.right, d);
}

ckinline(d: ref Decl)
{
	d.inline = byte ckinline0(d.init.right, d);
}

modcom(entry: ref Decl)
{
	d, m: ref Decl;

	if(errors)
		return;

	if(emitcode != "" || emitstub || emittab != "" || emitsbl != ""){
		emit(curscope());
		popscope();
		return;
	}

	#
	# scom introduces global variables for case statements
	# and unaddressable constants, so it must be done before
	# popping the global scope
	#
	gent = sys->millisec();
	nlabel = 0;
	maxstack = MaxTemp;
	nocont = ref Inst;
	genstart();

	for(i := 0; i < nfns; i++)
		if(int fns[i].inline == 1)
			ckinline(fns[i]);

	ok := 0;
	for(i = 0; i < nfns; i++){
		d = fns[i];
		if(d.refs > 1 && !(int d.inline == 1 && local(d) && d.iface == nil)){
			fns[ok++] = d;
			fncom(d);
		}
	}
	fns = fns[:ok];
	nfns = ok;
	if(blocks != -1)
		fatal("blocks not nested correctly");
	firstinst = firstinst.next;
	if(errors)
		return;

	globals := popscope();
	checkrefs(globals);
	if(errors)
		return;
	globals = vars(globals);
	moddataref();

	nils := popscope();
	m = nil;
	for(d = nils; d != nil; d = d.next){
		if(debug['n'])
			print("nil '%s' ref %d\n", d.sym.name, d.refs);
		if(d.refs && m == nil)
			m = dupdecl(d);
		d.offset = 0;
	}
	globals = appdecls(m, globals);
	globals = namesort(globals);
	globals = modglobals(impdecls.d, globals);
	vcom(globals);
	narrowmods();
	ldts: ref Decl;
	if(LDT)
		(globals, ldts) = resolveldts(globals);
	offset := idoffsets(globals, 0, IBY2WD);
	if(LDT)
		ldtoff := idindices(ldts);	# idoffsets(ldts, 0, IBY2WD);
	for(d = nils; d != nil; d = d.next){
		if(debug['n'])
			print("nil '%s' ref %d\n", d.sym.name, d.refs);
		if(d.refs)
			d.offset = m.offset;
	}

	if(debug['g']){
		print("globals:\n");
		printdecls(globals);
	}

	ndata := 0;
	for(d = globals; d != nil; d = d.next)
		ndata++;
	ndesc := resolvedesc(impdecls.d, offset, globals);
	ninst := resolvepcs(firstinst);
	modresolve();
	if(impdecls.next != nil)
		for(dl := impdecls; dl != nil; dl = dl.next)
			resolvemod(dl.d);
	nlink := resolvemod(impdecl);
	gent = sys->millisec() - gent;

	maxstack *= 10;
	if(fixss != 0)
		maxstack = fixss;

	if(debug['s'])
		print("%d instructions\n%d data elements\n%d type descriptors\n%d functions exported\n%d stack size\n",
			ninst, ndata, ndesc, nlink, maxstack);

	excs = reve(excs);

	writet = sys->millisec();
	if(gendis){
		discon(XMAGIC);
		hints := 0;
		if(mustcompile)
			hints |= MUSTCOMPILE;
		if(dontcompile)
			hints |= DONTCOMPILE;
		if(LDT)
			hints |= HASLDT;
		if(excs != nil)
			hints |= HASEXCEPT;
		discon(hints);		# runtime hints
		discon(maxstack);	# minimum stack extent size
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
	writet = sys->millisec() - writet;

	symt = sys->millisec();
	if(bsym != nil){
		sblmod(impdecl);

		sblfiles();
		sblinst(firstinst, ninst);
		sblty(adts, nadts);
		sblfn(fns, nfns);
		sblvar(globals);
	}
	symt = sys->millisec() - symt;

	firstinst = nil;
	lastinst = nil;

	excs = nil;
}

fncom(decl: ref Decl)
{
	curfn = decl;
	if(ispoly(decl))
		addfnptrs(decl, 1);

	#
	# pick up the function body and compile it
	# this code tries to clean up the parse nodes as fast as possible
	# function is Ofunc(name, body)
	#
	decl.pc = nextinst();
	tinit();
	labdep = 0;
	scp = 0;
	breaks = array[maxlabdep] of ref Inst;
	conts = array[maxlabdep] of ref Inst;
	labels = array[maxlabdep] of ref Decl;
	bcscps = array[maxlabdep] of ref Node;
	
	n := decl.init;
	if(int decl.inline == 1)
		decl.init = dupn(0, nosrc, n);
	else
		decl.init = n.left;
	src := n.right.src;
	src.start = src.stop - 1;
	for(n = n.right; n != nil; n = n.right){
		if(n.op != Oseq){
			if(n.op == Ocall && trcom(n, nil, 1))
				break;
			scom(n);
			break;
		}
		if(n.left.op == Ocall && trcom(n.left, n.right, 1)){
			n = n.right;
			if(n == nil || n.op != Oseq)
				break;
		}
		else
			scom(n.left);
	}
	pushblock();
	in := genrawop(src, IRET, nil, nil, nil);
	popblock();
	reach(decl.pc);
	if(in.reach != byte 0 && decl.ty.tof != tnone)
		error(src.start, "no return at end of function " + dotconv(decl));
	# decl.endpc = lastinst;
	if(labdep != 0)
		fatal("unbalanced label stack");
	breaks = nil;
	conts = nil;
	labels = nil;
	bcscps = nil;

	loc := declsort(appdecls(vars(decl.locals), tdecls()));

	decl.offset = idoffsets(loc, decl.offset, MaxAlign);
	for(last := decl.ty.ids; last != nil && last.next != nil; last = last.next)
		;
	if(last != nil)
		last.next = loc;
	else
		decl.ty.ids = loc;

	if(debug['f']){
		print("fn: %s\n", decl.sym.name);
		printdecls(decl.ty.ids);
	}

	decl.desc = gendesc(decl, decl.offset, decl.ty.ids);
	decl.locals = loc;
	excdesc();
	if(decl.offset > maxstack)
		maxstack = decl.offset;
	if(optims)
		optim(decl.pc, decl);
	if(last != nil)
		last.next = nil;
	else
		decl.ty.ids = nil;
}

#
# statement compiler
#
scom(n: ref Node)
{
	b: int;
	p, pp: ref Inst;
	left: ref Node;

	for(; n != nil; n = n.right){
		case n.op{
		Ocondecl or
		Otypedecl or
		Ovardecl or
		Oimport or
		Oexdecl =>
			return;
		Ovardecli =>
			break;
		Oscope =>
			pushscp(n);
			scom(n.right);
			popscp();
			zcom(n.left, nil);
			return;
		Olabel =>
			scom(n.right);
			return;
		Oif =>
			pushblock();
			left = simplify(n.left);
			if(left.op == Oconst && left.ty == tint){
				if(left.c.val != big 0)
					scom(n.right.left);
				else
					scom(n.right.right);
				popblock();
				return;
			}
			sumark(left);
			pushblock();
			p = bcom(left, 1, nil);
			tfreenow();
			popblock();
			scom(n.right.left);
			if(n.right.right != nil){
				pp = p;
				p = genrawop(lastinst.src, IJMP, nil, nil, nil);
				patch(pp, nextinst());
				scom(n.right.right);
			}
			patch(p, nextinst());
			popblock();
			return;
		Ofor =>
			n.left = left = simplify(n.left);
			if(left.op == Oconst && left.ty == tint){
				if(left.c.val == big 0)
					return;
				left.op = Onothing;
				left.ty = tnone;
				left.decl = nil;
			}
			pp = nextinst();
			b = pushblock();
			sumark(left);
			p = bcom(left, 1, nil);
			tfreenow();
			popblock();

			if(labdep >= maxlabdep)
				fatal("label stack overflow");
			breaks[labdep] = nil;
			conts[labdep] = nil;
			labels[labdep] = n.decl;
			bcscps[labdep] = curscp();
			labdep++;
			scom(n.right.left);
			labdep--;

			patch(conts[labdep], nextinst());
			if(n.right.right != nil){
				pushblock();
				scom(n.right.right);
				popblock();
			}
			repushblock(lastinst.block);	# was b
			patch(genrawop(lastinst.src, IJMP, nil, nil, nil), pp);	# for cprof: was left.src
			popblock();
			patch(p, nextinst());
			patch(breaks[labdep], nextinst());
			return;
		Odo =>
			pp = nextinst();

			if(labdep >= maxlabdep)
				fatal("label stack overflow");
			breaks[labdep] = nil;
			conts[labdep] = nil;
			labels[labdep] = n.decl;
			bcscps[labdep] = curscp();
			labdep++;
			scom(n.right);
			labdep--;

			patch(conts[labdep], nextinst());

			left = simplify(n.left);
			if(left.op == Onothing
			|| left.op == Oconst && left.ty == tint){
				if(left.op == Onothing || left.c.val != big 0){
					pushblock();
					p = genrawop(left.src, IJMP, nil, nil, nil);
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
		Ocase or
		Opick or
		Oalt or
		Oexcept =>
			pushblock();
			if(labdep >= maxlabdep)
				fatal("label stack overflow");
			breaks[labdep] = nil;
			conts[labdep] = nocont;
			labels[labdep] = n.decl;
			bcscps[labdep] = curscp();
			labdep++;
			case n.op{
			Oalt =>
				altcom(n);
			Ocase or
			Opick =>
				casecom(n);
			Oexcept =>
				excom(n);
			}
			labdep--;
			patch(breaks[labdep], nextinst());
			popblock();
			return;
		Obreak =>
			pushblock();
			bccom(n, breaks);
			popblock();
		Ocont =>
			pushblock();
			bccom(n, conts);
			popblock();
		Oseq =>
			if(n.left.op == Ocall && trcom(n.left, n.right, 0)){
				n = n.right;
				if(n == nil || n.op != Oseq)
					return;
			}
			else
				scom(n.left);
		Oret =>
			if(n.left != nil && n.left.op == Ocall && trcom(n.left, nil, 1))
				return;
			pushblock();
			if(n.left != nil){
				n.left = simplify(n.left);
				sumark(n.left);
				ecom(n.left.src, retalloc(ref Node, n.left), n.left);
				tfreenow();
			}
			genrawop(n.src, IRET, nil, nil, nil);
			popblock();
			return;
		Oexit =>
			pushblock();
			genrawop(n.src, IEXIT, nil, nil, nil);
			popblock();
			return;
		Onothing =>
			return;
		Ofunc =>
			fatal("Ofunc");
			return;
		Oexstmt =>
			pushblock();
			pp = genrawop(n.right.src, IEXC0, nil, nil, nil);	# marker
			p1 := nextinst();
			scom(n.left);
			p2 := nextinst();
			p3 := genrawop(n.right.src, IJMP, nil, nil, nil);
			p = genrawop(n.right.src, IEXC, nil, nil, nil);	# marker
			p.d.decl = mkdecl(n.src, 0, n.right.ty);
			zn := array[1] of ref Node;
			zeroallscopes(n.left, zn);
			scom(n.right);
			patch(p3, nextinst());
			installexc(n.right, p1, p2, zn[0]);
			patch(pp, p);
			popblock();
			return;
		* =>
			pushblock();
			n = simplify(n);
			sumark(n);
			ecom(n.src, nil, n);
			tfreenow();
			popblock();
			return;
		}
	}
}

#
# compile a break, continue
#
bccom(n: ref Node, bs: array of ref Inst)
{
	s: ref Sym;

	s = nil;
	if(n.decl != nil)
		s = n.decl.sym;
	ok := -1;
	for(i := 0; i < labdep; i++){
		if(bs[i] == nocont)
			continue;
		if(s == nil || labels[i] != nil && labels[i].sym == s)
			ok = i;
	}
	if(ok < 0)
		fatal("didn't find break or continue");
	zeroscopes(bcscps[ok]);
	p := genrawop(n.src, IJMP, nil, nil, nil);
	p.branch = bs[ok];
	bs[ok] = p;
}

dogoto(c: ref Case): int
{
	i, j, k, n, r, q, v: int;
	l, nl: array of Label;
	src: Src;

	l = c.labs;
	n = c.nlab;
	if(n == 0)
		return 0;
	r = int l[n-1].stop.c.val - int l[0].start.c.val+1;
	if(r >= 3 && r <= 3*n){
		if(r != n){
			# remove ranges, fill in gaps
			c.nlab = r;
			nl = c.labs = array[r] of Label;
			k = 0;
			v = int l[0].start.c.val-1;
			for(i = 0; i < n; i++){
				# p = int l[i].start.c.val;
				q = int l[i].stop.c.val;
				src = l[i].start.src;
				for(j = v+1; j <= q; j++){
					nl[k] = l[i];
					nl[k].start = nl[k].stop = mkconst(src, big j);
					k++;
				}
				v = q;
			}
			if(k != r)
				fatal("bad case expansion");
		}
		l = c.labs;
		for(i = 0; i < r; i++)
			l[i].inst = nil;
		return 1;
	}
	return 0;
}

fillrange(c: ref Case, nn: ref Node, in: ref Inst)
{
	i, j, n, p, q: int;
	l: array of Label;

	l = c.labs;
	n = c.nlab;
	p = int nn.left.c.val;
	q = int nn.right.c.val;
	for(i = 0; i < n; i++)
		if(int l[i].start.c.val == p)
			break;
	if(i == n)
		fatal("fillrange fails");
	for(j = p; j <= q; j++)
		l[i++].inst = in;
}

casecom(cn: ref Node)
{
	d: ref Decl;
	left, p, tmp, tmpc: ref Node;
	jmps, wild, j1, j2: ref Inst;

	c := cn.ty.cse;

	needwild := cn.op != Opick || c.nlab != cn.left.right.ty.tof.decl.tag;
	igoto := cn.left.ty == tint && dogoto(c);

	#
	# generate global which has case labels
	#
	if(igoto){
		d = mkids(cn.src, enter(".g"+string nlabel++, 0), cn.ty, nil);
		cn.ty.kind = Tgoto;
	}
	else
		d = mkids(cn.src, enter(".c"+string nlabel++, 0), cn.ty, nil);
	d.init = mkdeclname(cn.src, d);
	nto := ref znode;
	nto.addable = Rmreg;
	nto.left = nil;
	nto.right = nil;
	nto.op = Oname;
	nto.ty = d.ty;
	nto.decl = d;

	tmp = nil;
	left = cn.left;
	left = simplify(left);
	cn.left = left;
	sumark(left);
	if(debug['c'])
		print("case %s\n", nodeconv(left));
	ctype := cn.left.ty;
	if(left.addable >= Rcant){
		if(cn.op == Opick){
			ecom(left.src, nil, left);
			tfreenow();
			left = mkunary(Oind, dupn(1, left.src, left.left));
			left.ty = tint;
			sumark(left);
			ctype = tint;
		}else{
			(left, tmp) = eacom(left, nil);
			tfreenow();
		}
	}

	labs := c.labs;
	nlab := c.nlab;

	if(igoto){
		if(labs[0].start.c.val != big 0){
			tmpc = talloc(left.ty, nil);
			if(left.addable == Radr || left.addable == Rmadr){
				genrawop(left.src, IMOVW, left, nil, tmpc);
				left = tmpc;
			}
			genrawop(left.src, ISUBW, sumark(labs[0].start), left, tmpc);
			left = tmpc;
		}
		if(needwild){
			j1 = genrawop(left.src, IBLTW, left, sumark(mkconst(left.src, big 0)), nil);
			j2 = genrawop(left.src, IBGTW, left, sumark(mkconst(left.src, labs[nlab-1].start.c.val-labs[0].start.c.val)), nil);
		}
		j := nextinst();
		genrawop(left.src, IGOTO, left, nil, nto);
		j.d.reg = IBY2WD;
	}
	else{
		op := ICASE;
		if(ctype == tbig)
			op = ICASEL;
		else if(ctype == tstring)
			op = ICASEC;
		genrawop(left.src, op, left, nil, nto);
	}
	tfree(tmp);
	tfree(tmpc);

	jmps = nil;
	wild = nil;
	for(n := cn.right; n != nil; n = n.right){
		j := nextinst();
		for(p = n.left.left; p != nil; p = p.right){
			if(debug['c'])
				print("case qualifier %s\n", nodeconv(p.left));
			case p.left.op{
			Oconst =>
				labs[findlab(ctype, p.left, labs, nlab)].inst = j;
			Orange =>
				labs[findlab(ctype, p.left.left, labs, nlab)].inst = j;
				if(igoto)
					fillrange(c, p.left, j);
			Owild =>
				if(needwild)
					wild = j;
				# else
				#	nwarn(p.left, "default case redundant");
			}
		}

		if(debug['c'])
			print("case body for %s: %s\n", expconv(n.left.left), nodeconv(n.left.right));

		k := nextinst();
		scom(n.left.right);

		src := lastinst.src;
		# if(n.left.right == nil || n.left.right.op == Onothing)
		if(k == nextinst())
			src = n.left.left.src;
		j = genrawop(src, IJMP, nil, nil, nil);
		j.branch = jmps;
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
		for(i := 0; i < nlab; i++)
			if(labs[i].inst == nil)
				labs[i].inst = wild;
	}

	c.iwild = wild;

	d.ty.cse = c;
	usetype(d.ty);
	installids(Dglobal, d);
}

altcom(nalt: ref Node)
{
	p, op, left: ref Node;
	jmps, wild, j: ref Inst = nil;

	talt := nalt.ty;
	c := talt.cse;
	nlab := c.nlab;
	nsnd := c.nsnd;
	comm := array[nlab] of ref Node;
	labs := array[nlab] of Label;
	tmps := array[nlab] of ref Node;
	c.labs = labs;

	#
	# built the type of the alt channel table
	# note that we lie to the garbage collector
	# if we know that another reference exists for the channel
	#
	is := 0;
	ir := nsnd;
	i := 0;
	for(n := nalt.left; n != nil; n = n.right){
		for(p = n.left.right.left; p != nil; p = p.right){
			left = simplify(p.left);
			p.left = left;
			if(left.op == Owild)
				continue;
			comm[i] = hascomm(left);
			left = comm[i].left;
			sumark(left);
			isptr := left.addable >= Rcant;
			if(comm[i].op == Osnd)
				labs[is++].isptr = isptr;
			else
				labs[ir++].isptr = isptr;
			i++;
		}
	}

	which := talloc(tint, nil);
	tab := talloc(talt, nil);

	#
	# build the node for the address of each channel,
	# the values to send, and the storage fro values received
	#
	off := ref znode;
	adr := ref znode;
	add := ref znode;
	slot := ref znode;
	off.op = Oconst;
	off.c = ref Const(big 0, 0.0);	# jrf - added initialization
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
	# compile the sending and receiving channels and values
	#
	is = 2*IBY2WD;
	ir = is + nsnd*2*IBY2WD;
	i = 0;
	for(n = nalt.left; n != nil; n = n.right){
		for(p = n.left.right.left; p != nil; p = p.right){
			if(p.left.op == Owild)
				continue;

			#
			# gen channel
			#
			op = comm[i];
			if(op.op == Osnd){
				off.c.val = big is;
				is += 2*IBY2WD;
			}else{
				off.c.val = big ir;
				ir += 2*IBY2WD;
			}
			left = op.left;

			#
			# this sleaze is lying to the garbage collector
			#
			if(left.addable < Rcant)
				genmove(left.src, Mas, tint, left, slot);
			else{
				slot.ty = left.ty;
				ecom(left.src, slot, left);
				tfreenow();
				slot.ty = nil;
			}

			#
			# gen value
			#
			off.c.val += big IBY2WD;
			(p.left, tmps[i]) = rewritecomm(p.left, comm[i], slot);

			i++;
		}
	}

	#
	# stuff the number of send & receive channels into the table
	#
	altsrc := nalt.src;
	altsrc.stop = (altsrc.stop & ~PosMask) | ((altsrc.stop + 3) & PosMask);
	off.c.val = big 0;
	genmove(altsrc, Mas, tint, sumark(mkconst(altsrc, big nsnd)), slot);
	off.c.val += big IBY2WD;
	genmove(altsrc, Mas, tint, sumark(mkconst(altsrc, big(nlab-nsnd))), slot);
	off.c.val += big IBY2WD;

	altop := IALT;
	if(c.wild != nil)
		altop = INBALT;
	pp := genrawop(altsrc, altop, tab, nil, which);
	pp.m.offset = talt.size;	# for optimizer

	d := mkids(nalt.src, enter(".g"+string nlabel++, 0), mktype(nalt.src.start, nalt.src.stop, Tgoto, nil, nil), nil);
	d.ty.cse = c;
	d.init = mkdeclname(nalt.src, d);

	nto := ref znode;
	nto.addable = Rmreg;
	nto.left = nil;
	nto.right = nil;
	nto.op = Oname;
	nto.decl = d;
	nto.ty = d.ty;

	me := genrawop(altsrc, IGOTO, which, nil, nto);
	me.d.reg = IBY2WD;		# skip the number of cases field
	tfree(tab);
	tfree(which);

	#
	# compile the guard expressions and bodies
	#
	i = 0;
	is = 0;
	ir = nsnd;
	jmps = nil;
	wild = nil;
	for(n = nalt.left; n != nil; n = n.right){
		j = nil;
		for(p = n.left.right.left; p != nil; p = p.right){
			tj := nextinst();
			if(p.left.op == Owild){
				wild = nextinst();
			}else{
				if(comm[i].op == Osnd)
					labs[is++].inst = tj;
				else{
					labs[ir++].inst = tj;
					tacquire(tmps[i]);
				}
				sumark(p.left);
				if(debug['a'])
					print("alt guard %s\n", nodeconv(p.left));
				ecom(p.left.src, nil, p.left);
				tfree(tmps[i]);
				tfreenow();
				i++;
			}
			if(p.right != nil){
				tj = genrawop(lastinst.src, IJMP, nil, nil, nil);
				tj.branch = j;
				j = tj;
			}
		}

		patch(j, nextinst());
		if(debug['a'])
			print("alt body %s\n", nodeconv(n.left.right));
		scom(n.left);

		j = genrawop(lastinst.src, IJMP, nil, nil, nil);
		j.branch = jmps;
		jmps = j;
	}
	patch(jmps, nextinst());
	comm = nil;

	c.iwild = wild;

	usetype(d.ty);
	installids(Dglobal, d);
}

excom(en: ref Node)
{
	ed: ref Decl;
	p: ref Node;
	jmps, wild: ref Inst;

	ed = en.left.decl;
	ed.ty = rtexception;
	c := en.ty.cse;
	labs := c.labs;
	nlab := c.nlab;
	jmps = nil;
	wild = nil;
	for(n := en.right; n != nil; n = n.right){
		qt: ref Type = nil;
		j := nextinst();
		for(p = n.left.left; p != nil; p = p.right){
			case p.left.op{
			Oconst =>
				labs[findlab(texception, p.left, labs, nlab)].inst = j;
			Owild =>
				wild = j;
			}
			if(qt == nil)
				qt = p.left.ty;
			else if(!tequal(qt, p.left.ty))
				qt = texception;
		}
		if(qt != nil)
			ed.ty = qt;
		k := nextinst();
		scom(n.left.right);
		src := lastinst.src;
		if(k == nextinst())
			src = n.left.left.src;
		j = genrawop(src, IJMP, nil, nil, nil);
		j.branch = jmps;
		jmps = j;
	}
	ed.ty = rtexception;
	patch(jmps, nextinst());
	c.iwild = wild;
}

#
# rewrite the communication operand
# allocate any temps needed for holding value to send or receive
#
rewritecomm(n, comm, slot: ref Node): (ref Node, ref Node)
{
	adr, tmp: ref Node;

	if(n == nil)
		return (nil, nil);
	adr = nil;
	if(n == comm){
		if(comm.op == Osnd && sumark(n.right).addable < Rcant)
			adr = n.right;
		else{
			adr = tmp = talloc(n.ty, nil);
			tmp.src = n.src;
			if(comm.op == Osnd){
				ecom(n.right.src, tmp, n.right);
				tfreenow();
			}
			else
				trelease(tmp);
		}
	}
	if(n.right == comm && n.op == Oas && comm.op == Orcv
	&& sumark(n.left).addable < Rcant)
		adr = n.left;
	if(adr != nil){
		p := genrawop(comm.left.src, ILEA, adr, nil, slot);
		p.m.offset = adr.ty.size;	# for optimizer
		if(comm.op == Osnd)
			p.m.reg = 1;	# for optimizer
		return (adr, tmp);
	}
	(n.left, tmp) = rewritecomm(n.left, comm, slot);
	if(tmp == nil)
		(n.right, tmp) = rewritecomm(n.right, comm, slot);
	return (n, tmp);
}

#
# merge together two sorted lists, yielding a sorted list
#
declmerge(e, f: ref Decl): ref Decl
{
	d := rock := ref Decl;
	while(e != nil && f != nil){
		fs := f.ty.size;
		es := e.ty.size;
		# v := 0;
		v := (e.link == nil) - (f.link == nil);
		if(v == 0 && (es <= IBY2WD || fs <= IBY2WD))
			v = fs - es;
		if(v == 0)
			v = e.refs - f.refs;
		if(v == 0)
			v = fs - es;
		if(v == 0 && e.sym.name > f.sym.name)
			v = -1;
		if(v >= 0){
			d.next = e;
			d = e;
			e = e.next;
			while(e != nil && e.nid == byte 0){
				d = e;
				e = e.next;
			}
		}else{
			d.next = f;
			d = f;
			f = f.next;
			while(f != nil && f.nid == byte 0){
				d = f;
				f = f.next;
			}
		}
		# d = d.next;
	}
	if(e != nil)
		d.next = e;
	else
		d.next = f;
	return rock.next;
}

#
# recursively split lists and remerge them after they are sorted
#
recdeclsort(d: ref Decl, n: int): ref Decl
{
	if(n <= 1)
		return d;
	m := n / 2 - 1;
	dd := d;
	for(i := 0; i < m; i++){
		dd = dd.next;
		while(dd.nid == byte 0)
			dd = dd.next;
	}
	r := dd.next;
	while(r.nid == byte 0){
		dd = r;
		r = r.next;
	}
	dd.next = nil;
	return declmerge(recdeclsort(d, n / 2),
			recdeclsort(r, (n + 1) / 2));
}

#
# sort the ids by size and number of references
#
declsort(d: ref Decl): ref Decl
{
	n := 0;
	for(dd := d; dd != nil; dd = dd.next)
		if(dd.nid > byte 0)
			n++;
	return recdeclsort(d, n);
}

nilsrc : Src;

zcom1(n : ref Node, nn: array of ref Node)
{
	ty : ref Type;
	d : ref Decl;
	e : ref Node;

	ty = n.ty;
	if (!tmustzero(ty))
		return;
	if (n.op == Oname && n.decl.refs == 0)
		return;
	if (nn != nil) {
		if(n.op != Oname)
			error(n.src.start, "fatal: bad op in zcom1 map");
		n.right = nn[0];
		nn[0] = n;
		return;
	}
	if (ty.kind == Tadtpick)
		ty = ty.tof;
	if (ty.kind == Ttuple || ty.kind == Tadt) {
		for (d = ty.ids; d != nil; d = d.next) {
			if (tmustzero(d.ty)) {
				dn := n;
				if (d.next != nil)
					dn = dupn(0, nilsrc, n);
				e = mkbin(Odot, dn, mkname(nilsrc, d.sym));
				e.right.decl = d;
				e.ty = e.right.ty = d.ty;
				zcom1(e, nn);
			}
		}
	}
	else {
		src := n.src;
		n.src = nilsrc;
		e = mkbin(Oas, n, mknil(nilsrc));
		e.ty = e.right.ty = ty;
		if (debug['Z'])
			print("ecom %s\n", nodeconv(e));
		pushblock();
		e = simplify(e);
		sumark(e);
		ecom(e.src, nil, e);
		popblock();
		n.src = src;
		e = nil;
	}
}

zcom0(id : ref Decl, nn: array of ref Node)
{
	e := mkname(nilsrc, id.sym);
	e.decl = id;
	e.ty = id.ty;
	zcom1(e, nn);
}

zcom(n : ref Node, nn: array of ref Node)
{
	r : ref Node;

	for ( ; n != nil; n = r) {
		r = n.right;
		n.right = nil;
		case (n.op) {
			Ovardecl =>
				last := n.left.decl;
				for (ids := n.decl; ids != last.next; ids = ids.next)
					zcom0(ids, nn);
				break;
			Oname =>
				if (n.decl != nildecl)
					zcom1(dupn(0, nilsrc, n), nn);
				break;
			Otuple =>
				for (nt := n.left; nt != nil; nt = nt.right)
					zcom(nt.left, nn);
				break;
			* =>
				fatal("bad node in zcom()");
				break;
		}
		n.right = r;
	}
}

ret(n: ref Node, nilret: int): int
{
	if(n == nil)
		return nilret;
	if(n.op == Oseq)
		n = n.left;
	return n.op == Oret && n.left == nil;
}

trcom(e: ref Node, ne: ref Node, nilret: int): int
{
	d, id: ref Decl;
	as, a, f, n: ref Node;
	p: ref Inst;

return 0;	# TBS
	if(e.op != Ocall || e.left.op != Oname)
		return 0;
	d = e.left.decl;
	if(d != curfn || int d.handler || ispoly(d))
		return 0;
	if(!ret(ne, nilret))
		return 0;
	pushblock();
	id = d.ty.ids;
	# evaluate args in same order as normal calls
	for(as = e.right; as != nil; as = as.right){
		a = as.left;
		if(!(a.op == Oname && id == a.decl)){
			if(occurs(id, as.right)){
				f = talloc(id.ty, nil);
				f.flags |= byte TEMP;
			}
			else
				f = mkdeclname(as.src, id);
			n = mkbin(Oas, f, a);
			n.ty = id.ty;
			scom(n);
			if(int f.flags&TEMP)
				as.left = f;
		}
		id = id.next;
	}
	id = d.ty.ids;
	for(as = e.right; as != nil; as = as.right){
		a = as.left;
		if(int a.flags&TEMP){
			f = mkdeclname(as.src, id);
			n = mkbin(Oas, f, a);
			n.ty = id.ty;
			scom(n);
			tfree(a);
		}
		id = id.next;
	}
	p = genrawop(e.src, IJMP, nil, nil, nil);
	patch(p, d.pc);
	popblock();
	return 1;
}
