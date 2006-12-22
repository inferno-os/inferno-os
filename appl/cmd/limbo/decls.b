
storename := array[Dend] of
{
	Dtype =>	"type",
	Dfn =>		"function",
	Dglobal =>	"global",
	Darg =>		"argument",
	Dlocal =>	"local",
	Dconst =>	"con",
	Dfield =>	"field",
	Dtag =>		"pick tag",
	Dimport =>	"import",
	Dunbound =>	"unbound",
	Dundef =>	"undefined",
	Dwundef =>	"undefined",
};

storeart := array[Dend] of
{
	Dtype =>	"a ",
	Dfn =>		"a ",
	Dglobal =>	"a ",
	Darg =>		"an ",
	Dlocal =>	"a ",
	Dconst =>	"a ",
	Dfield =>	"a ",
	Dtag =>		"a ",
	Dimport =>	"an ",
	Dunbound =>	"",
	Dundef =>	"",
	Dwundef =>	"",
};

storespace := array[Dend] of
{
	Dtype =>	0,
	Dfn =>		0,
	Dglobal =>	1,
	Darg =>		1,
	Dlocal =>	1,
	Dconst =>	0,
	Dfield =>	1,
	Dtag =>		0,
	Dimport =>	0,
	Dunbound =>	0,
	Dundef =>	0,
	Dwundef =>	0,
};

impdecl:	ref Decl;
impdecls:	ref Dlist;
scopes :=	array[MaxScope] of ref Decl;
tails :=	array[MaxScope] of ref Decl;
scopekind := 	array[MaxScope] of byte;
scopenode :=	array[MaxScope] of ref Node;
iota:		ref Decl;
zdecl:		Decl;

popscopes()
{
	d: ref Decl;

	#
	# clear out any decls left in syms
	#
	while(scope >= ScopeBuiltin){
		for(d = scopes[scope--]; d != nil; d = d.next){
			if(d.sym != nil){
				d.sym.decl = d.old;
				d.old = nil;
			}
		}
	}

	for(id := impdecls; id != nil; id = id.next){
		for(d = id.d.ty.ids; d != nil; d = d.next){
			d.sym.decl = nil;
			d.old = nil;
		}
	}
	impdecls = nil;

	scope = ScopeBuiltin;
	scopes[ScopeBuiltin] = nil;
	tails[ScopeBuiltin] = nil;
}

declstart()
{
	iota = mkids(nosrc, enter("iota", 0), tint, nil);
	iota.init = mkconst(nosrc, big 0);

	scope = ScopeNils;
	scopes[ScopeNils] = nil;
	tails[ScopeNils] = nil;

	nildecl = mkdecl(nosrc, Dglobal, tany);
	nildecl.sym = enter("nil", 0);
	installids(Dglobal, nildecl);
	d := mkdecl(nosrc, Dglobal, tstring);
	d.sym = enterstring("");
	installids(Dglobal, d);

	scope = ScopeGlobal;
	scopes[ScopeGlobal] = nil;
	tails[ScopeGlobal] = nil;
}

redecl(d: ref Decl)
{
	old := d.sym.decl;
	if(old.store == Dwundef)
		return;
	error(d.src.start, "redeclaration of "+declconv(d)+", previously declared as "+storeconv(old)+" on line "+
		lineconv(old.src.start));
}

checkrefs(d: ref Decl)
{
	id, m: ref Decl;
	refs: int;

	for(; d != nil; d = d.next){
		if(d.das != byte 0)
			d.refs--;
		case d.store{
		Dtype =>
			refs = d.refs;
			if(d.ty.kind == Tadt){
				for(id = d.ty.ids; id != nil; id = id.next){
					d.refs += id.refs;
					if(id.store != Dfn)
						continue;
					if(id.init == nil && id.link == nil && d.importid == nil)
						error(d.src.start, "function "+d.sym.name+"."+id.sym.name+" not defined");
					if(superwarn && !id.refs && d.importid == nil)
						warn(d.src.start, "function "+d.sym.name+"."+id.sym.name+" not referenced");
				}
			}
			if(d.ty.kind == Tmodule){
				for(id = d.ty.ids; id != nil; id = id.next){
					refs += id.refs;
					if(id.iface != nil)
						id.iface.refs += id.refs;
					if(id.store == Dtype){
						for(m = id.ty.ids; m != nil; m = m.next){
							refs += m.refs;
							if(m.iface != nil)
								m.iface.refs += m.refs;
						}
					}
				}
				d.refs = refs;
			}
			if(superwarn && !refs && d.importid == nil)
				warn(d.src.start, declconv(d)+" not referenced");
		Dglobal =>
			if(superwarn && !d.refs && d.sym != nil && d.sym.name[0] != '.')
				warn(d.src.start, declconv(d)+" not referenced");
		Dlocal or
		Darg =>
			if(!d.refs && d.sym != nil && d.sym.name != nil && d.sym.name[0] != '.')
				warn(d.src.start, declconv(d)+" not referenced");
		Dconst =>
			if(superwarn && !d.refs && d.sym != nil)
				warn(d.src.start, declconv(d)+" not referenced");
		Dfn =>
			if(d.init == nil && d.importid == nil)
				error(d.src.start, declconv(d)+" not defined");
			if(superwarn && !d.refs)
				warn(d.src.start, declconv(d)+" not referenced");
		Dimport =>
			if(superwarn && !d.refs)
				warn(d.src.start, declconv(d)+" not referenced");
		}
		if(d.das != byte 0)
			d.refs++;
	}
}

vardecl(ids: ref Decl, t: ref Type): ref Node
{
	n := mkn(Ovardecl, mkn(Oseq, nil, nil), nil);
	n.decl = ids;
	n.ty = t;
	return n;
}

vardecled(n: ref Node)
{
	store := Dlocal;
	if(scope == ScopeGlobal)
		store = Dglobal;
	if(n.ty.kind == Texception && n.ty.cons == byte 1){
		store = Dconst;
		fatal("Texception in vardecled");
	}
	ids := n.decl;
	installids(store, ids);
	t := n.ty;
	for(last := ids; ids != nil; ids = ids.next){
		ids.ty = t;
		last = ids;
	}
	n.left.decl = last;
}

condecl(ids: ref Decl, init: ref Node): ref Node
{
	n := mkn(Ocondecl, mkn(Oseq, nil, nil), init);
	n.decl = ids;
	return n;
}

condecled(n: ref Node)
{
	ids := n.decl;
	installids(Dconst, ids);
	for(last := ids; ids != nil; ids = ids.next){
		ids.ty = tunknown;
		last = ids;
	}
	n.left.decl = last;
}

exdecl(ids: ref Decl, tids: ref Decl): ref Node
{
	n: ref Node;
	t: ref Type;

	t = mktype(ids.src.start, ids.src.stop, Texception, nil, tids);
	t.cons = byte 1;
	n = mkn(Oexdecl, mkn(Oseq, nil, nil), nil);
	n.decl = ids;
	n.ty = t;
	return n;
}

exdecled(n: ref Node)
{
	ids, last: ref Decl;
	t: ref Type;

	ids = n.decl;
	installids(Dconst, ids);
	t = n.ty;
	for(last = ids; ids != nil; ids = ids.next){
		ids.ty = t;
		last = ids;
	}
	n.left.decl = last;
}

importdecl(m: ref Node, ids: ref Decl): ref Node
{
	n := mkn(Oimport, mkn(Oseq, nil, nil), m);
	n.decl = ids;
	return n;
}

importdecled(n: ref Node)
{
	ids := n.decl;
	installids(Dimport, ids);
	for(last := ids; ids != nil; ids = ids.next){
		ids.ty = tunknown;
		last = ids;
	}
	n.left.decl = last;
}

mkscope(body: ref Node): ref Node
{
	n := mkn(Oscope, nil, body);
	if(body != nil)
		n.src = body.src;
	return n;
}

fndecl(n: ref Node, t: ref Type, body: ref Node): ref Node
{
	n = mkbin(Ofunc, n, body);
	n.ty = t;
	return n;
}

fndecled(n: ref Node)
{
	left := n.left;
	if(left.op == Oname){
		d := left.decl.sym.decl;
		if(d == nil || d.store == Dimport){
			d = mkids(left.src, left.decl.sym, n.ty, nil);
			installids(Dfn, d);
		}
		left.decl = d;
		d.refs++;
	}
	if(left.op == Odot)
		pushscope(nil, Sother);
	if(n.ty.polys != nil){
		pushscope(nil, Sother);
		installids(Dtype, n.ty.polys);
	}
	pushscope(nil, Sother);
	installids(Darg, n.ty.ids);
	n.ty.ids = popscope();
	if(n.ty.val != nil)
		mergepolydecs(n.ty);
	if(n.ty.polys != nil)
		n.ty.polys = popscope();
	if(left.op == Odot)
		popscope();
}

#
# check the function declaration only
# the body will be type checked later by fncheck
#
fnchk(n: ref Node): ref Decl
{
	bad := 0;
	d := n.left.decl;
	if(n.left.op == Odot)
		d = n.left.right.decl;
	if(d == nil)
		fatal("decl() fnchk nil");
	n.left.decl = d;
	if(d.store == Dglobal || d.store == Dfield)
		d.store = Dfn;
	if(d.store != Dfn || d.init != nil){
		nerror(n, "redeclaration of function "+dotconv(d)+", previously declared as "
			+storeconv(d)+" on line "+lineconv(d.src.start));
		if(d.store == Dfn && d.init != nil)
			bad = 1;
	}
	d.init = n;

	t := n.ty;
	inadt := d.dot;
	if(inadt != nil && (inadt.store != Dtype || inadt.ty.kind != Tadt))
		inadt = nil;
	if(n.left.op == Odot){
		pushscope(nil, Sother);
		adtp := outerpolys(n.left);
		if(adtp != nil)
			installids(Dtype, adtp);
		if(!polyequal(adtp, n.decl))
			nerror(n, "adt polymorphic type mismatch");
		n.decl = nil;
	}
	t = validtype(t, inadt);
	if(n.left.op == Odot)
		popscope();
	if(debug['d'])
		print("declare function %s ty %s newty %s\n", dotconv(d), typeconv(d.ty), typeconv(t));
	t = usetype(t);

	if(!polyequal(d.ty.polys, t.polys))
		nerror(n, "function polymorphic type mismatch");
	if(!tcompat(d.ty, t, 0))
		nerror(n, "type mismatch: "+dotconv(d)+" defined as "
			+typeconv(t)+" declared as "+typeconv(d.ty)+" on line "+lineconv(d.src.start));
	else if(!raisescompat(d.ty.eraises, t.eraises))
		nerror(n, "raises mismatch: " + dotconv(d));
	if(t.varargs != byte 0)
		nerror(n, "cannot define functions with a '*' argument, such as "+dotconv(d));

	t.eraises = d.ty.eraises;

	d.ty = t;
	d.offset = idoffsets(t.ids, MaxTemp, IBY2WD);
	d.src = n.src;

	d.locals = nil;

	n.ty = t;

	if(bad)
		return nil;
	return d;
}

globalas(dst: ref Node, v: ref Node, valok: int): ref Node
{
	if(v == nil)
		return nil;
	if(v.op == Oas || v.op == Odas){
		v = globalas(v.left, v.right, valok);
		if(v == nil)
			return nil;
	}else if(valok && !initable(dst, v, 0))
		return nil;
	case dst.op{
	Oname =>
		if(dst.decl.init != nil)
			nerror(dst, "duplicate assignment to "+expconv(dst)+", previously assigned on line "
				+lineconv(dst.decl.init.src.start));
		if(valok)
			dst.decl.init = v;
		return v;
	Otuple =>
		if(valok && v.op != Otuple)
			fatal("can't deal with "+nodeconv(v)+" in tuple case of globalas");
		tv := v.left;
		for(dst = dst.left; dst != nil; dst = dst.right){
			globalas(dst.left, tv.left, valok);
			if(valok)
				tv = tv.right;
		}
		return v;
	}
	fatal("can't deal with "+nodeconv(dst)+" in globalas");
	return nil;
}

needsstore(d: ref Decl): int
{
	if(!d.refs)
		return 0;
	if(d.importid != nil)
		return 0;
	if(storespace[d.store])
		return 1;
	return 0;
}

#
# return the list of all referenced storage variables
#
vars(d: ref Decl): ref Decl
{
	while(d != nil && !needsstore(d))
		d = d.next;
	for(v := d; v != nil; v = v.next){
		while(v.next != nil){
			n := v.next;
			if(needsstore(n))
				break;
			v.next = n.next;
		}
	}
	return d;
}

#
# declare variables from the left side of a := statement
#
recdasdecl(n: ref Node, store: int, nid: int): (int, int)
{
	r: int;

	case n.op{
	Otuple =>
		ok := 1;
		for(n = n.left; n != nil; n = n.right){
			(r, nid) = recdasdecl(n.left, store, nid);
			ok &= r;
		}
		return (ok, nid);
	Oname =>
		if(n.decl == nildecl)
			return (1, -1);
		d := mkids(n.src, n.decl.sym, nil, nil);
		installids(store, d);
		n.decl = d;
		old := d.old;
		if(old != nil
		&& old.store != Dfn
		&& old.store != Dwundef
		&& old.store != Dundef)
			warn(d.src.start, "redeclaration of "+declconv(d)+", previously declared as "
				+storeconv(old)+" on line "+lineconv(old.src.start));
		d.refs++;
		d.das = byte 1;
		if(nid >= 0)
			nid++;
		return (1, nid);
	}
	return (0, nid);
}

recmark(n: ref Node, nid: int): int
{
	case(n.op){
	Otuple =>
		for(n = n.left; n != nil; n = n.right)
			nid = recmark(n.left, nid);
	Oname =>
		n.decl.nid = byte nid;
		nid = 0;
	}
	return nid;
}

dasdecl(n: ref Node): int
{
	ok: int;

	nid := 0;
	store := Dlocal;
	if(scope == ScopeGlobal)
		store = Dglobal;

	(ok, nid) = recdasdecl(n, store, nid);
	if(!ok)
		nerror(n, "illegal declaration expression "+expconv(n));
	if(ok && store == Dlocal && nid > 1)
		recmark(n, nid);
	return ok;
}

#
# declare global variables in nested := expressions
#
gdasdecl(n: ref Node)
{
	if(n == nil)
		return;

	if(n.op == Odas){
		gdasdecl(n.right);
		dasdecl(n.left);
	}else{
		gdasdecl(n.left);
		gdasdecl(n.right);
	}
}

undefed(src: Src, s: ref Sym): ref Decl
{
	d := mkids(src, s, tnone, nil);
	error(src.start, s.name+" is not declared");
	installids(Dwundef, d);
	return d;
}

# inloop() : int
# {
#	for (i := scope; i > 0; i--)
#		if (int scopekind[i] == Sloop)
#			return 1;
#	return 0;
# }

nested() : int
{
	for (i := scope; i > 0; i--)
		if (int scopekind[i] == Sscope || int scopekind[i] == Sloop)
			return 1;
	return 0;
}

decltozero(n : ref Node)
{
	if ((scop := scopenode[scope]) != nil) {
		if (n.right != nil && errors == 0)
			fatal("Ovardecl/Oname/Otuple has right field\n");
		n.right = scop.left;
		scop.left = n;
	}
}

pushscope(scp : ref Node, kind : int)
{
	if(scope >= MaxScope)
		fatal("scope too deep");
	scope++;
	scopes[scope] = nil;
	tails[scope] = nil;
	scopenode[scope] = scp;
	scopekind[scope] = byte kind;
}

curscope(): ref Decl
{
	return scopes[scope];
}

#
# revert to old declarations for each symbol in the currect scope.
# remove the effects of any imported adt types
# whenever the adt is imported from a module,
# we record in the type's decl the module to use
# when calling members.  the process is reversed here.
#
popscope(): ref Decl
{
	for(id := scopes[scope]; id != nil; id = id.next){
		if(id.sym != nil){
			id.sym.decl = id.old;
			id.old = nil;
		}
		if(id.importid != nil)
			id.importid.refs += id.refs;
		t := id.ty;
		if(id.store == Dtype
		&& t.decl != nil
		&& t.decl.timport == id)
			t.decl.timport = id.timport;
		if(id.store == Dlocal)
			freeloc(id);
	}
	return scopes[scope--];
}

#
# make a new scope,
# preinstalled with some previously installed identifiers
# don't add the identifiers to the scope chain,
# so they remain separate from any newly installed ids
#
# these routines assume no ids are imports
#
repushids(ids: ref Decl)
{
	if(scope >= MaxScope)
		fatal("scope too deep");
	scope++;
	scopes[scope] = nil;
	tails[scope] = nil;
	scopenode[scope] = nil;
	scopekind[scope] = byte Sother;

	for(; ids != nil; ids = ids.next){
		if(ids.scope != scope
		&& (ids.dot == nil || !isimpmod(ids.dot.sym)
			|| ids.scope != ScopeGlobal || scope != ScopeGlobal + 1))
			fatal("repushids scope mismatch");
		s := ids.sym;
		if(s != nil && ids.store != Dtag){
			if(s.decl != nil && s.decl.scope >= scope)
				ids.old = s.decl.old;
			else
				ids.old = s.decl;
			s.decl = ids;
		}
	}
}

#
# pop a scope which was started with repushids
# return any newly installed ids
#
popids(ids: ref Decl): ref Decl
{
	for(; ids != nil; ids = ids.next){
		if(ids.sym != nil && ids.store != Dtag){
			ids.sym.decl = ids.old;
			ids.old = nil;
		}
	}
	return popscope();
}

installids(store: int, ids: ref Decl)
{
	last : ref Decl = nil;
	for(d := ids; d != nil; d = d.next){
		d.scope = scope;
		if(d.store == Dundef)
			d.store = store;
		s := d.sym;
		if(s != nil){
			if(s.decl != nil && s.decl.scope >= scope){
				redecl(d);
				d.old = s.decl.old;
			}else
				d.old = s.decl;
			s.decl = d;
		}
		last = d;
	}
	if(ids != nil){
		d = tails[scope];
		if(d == nil)
			scopes[scope] = ids;
		else
			d.next = ids;
		tails[scope] = last;
	}
}

lookup(sym: ref Sym): ref Decl
{
	s: int;
	d: ref Decl;

	for(s = scope; s >= ScopeBuiltin; s--){
		for(d = scopes[s]; d != nil; d = d.next){
			if(d.sym == sym)
				return d;
		}
	}
	return nil;
}

mkids(src: Src, s: ref Sym, t: ref Type, next: ref Decl): ref Decl
{
	d := ref zdecl;
	d.src = src;
	d.store = Dundef;
	d.ty = t;
	d.next = next;
	d.sym = s;
	d.nid = byte 1;
	return d;
}

mkdecl(src: Src, store: int, t: ref Type): ref Decl
{
	d := ref zdecl;
	d.src = src;
	d.store = store;
	d.ty = t;
	d.nid = byte 1;
	return d;
}

dupdecl(old: ref Decl): ref Decl
{
	d := ref *old;
	d.next = nil;
	return d;
}

dupdecls(old: ref Decl): ref Decl
{
	d, nd, first, last: ref Decl;

	first = last = nil;
	for(d = old; d != nil; d = d.next){
		nd = dupdecl(d);
		if(first == nil)
			first = nd;
		else
			last.next = nd;
		last = nd;
	}
	return first;
}

appdecls(d: ref Decl, dd: ref Decl): ref Decl
{
	if(d == nil)
		return dd;
	for(t := d; t.next != nil; t = t.next)
		;
	t.next = dd;
	return d;
}

revids(id: ref Decl): ref Decl
{
	next : ref Decl;
	d : ref Decl = nil;
	for(; id != nil; id = next){
		next = id.next;
		id.next = d;
		d = id;
	}
	return d;
}

idoffsets(id: ref Decl, offset: int, al: int): int
{
	algn := 1;
	for(; id != nil; id = id.next){
		if(storespace[id.store]){
usedty(id.ty);
			if(id.store == Dlocal && id.link != nil){
				# id.nid always 1
				id.offset = id.link.offset;
				continue;
			}
			a := id.ty.align;
			if(id.nid > byte 1){
				for(d := id.next; d != nil && d.nid == byte 0; d = d.next)
					if(d.ty.align > a)
						a = d.ty.align;
				algn = a;
			}
			offset = align(offset, a);
			id.offset = offset;
			offset += id.ty.size;
			if(id.nid == byte 0 && (id.next == nil || id.next.nid != byte 0))
				offset = align(offset, algn);
		}
	}
	return align(offset, al);
}

idindices(id: ref Decl): int
{
	i := 0;
	for(; id != nil; id = id.next){
		if(storespace[id.store]){
			usedty(id.ty);
			id.offset = i++;
		}
	}
	return i;
}

declconv(d: ref Decl): string
{
	if(d.sym == nil)
		return storename[d.store] + " " + "<???>";
	return storename[d.store] + " " + d.sym.name;
}

storeconv(d: ref Decl): string
{
	return storeart[d.store] + storename[d.store];
}

dotconv(d: ref Decl): string
{
	s: string;

	if(d.dot != nil && !isimpmod(d.dot.sym)){
		s = dotconv(d.dot);
		if(d.dot.ty != nil && d.dot.ty.kind == Tmodule)
			s += ".";
		else
			s += ".";
	}
	s += d.sym.name;
	return s;
}

#
# merge together two sorted lists, yielding a sorted list
#
namemerge(e, f: ref Decl): ref Decl
{
	d := rock := ref Decl;
	while(e != nil && f != nil){
		if(e.sym.name <= f.sym.name){
			d.next = e;
			e = e.next;
		}else{
			d.next = f;
			f = f.next;
		}
		d = d.next;
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
recnamesort(d: ref Decl, n: int): ref Decl
{
	if(n <= 1)
		return d;
	m := n / 2 - 1;
	dd := d;
	for(i := 0; i < m; i++)
		dd = dd.next;
	r := dd.next;
	dd.next = nil;
	return namemerge(recnamesort(d, n / 2),
			recnamesort(r, (n + 1) / 2));
}

#
# sort the ids by name
#
namesort(d: ref Decl): ref Decl
{
	n := 0;
	for(dd := d; dd != nil; dd = dd.next)
		n++;
	return recnamesort(d, n);
}

printdecls(d: ref Decl)
{
	for(; d != nil; d = d.next)
		print("%d: %s %s ref %d\n", d.offset, declconv(d), typeconv(d.ty), d.refs);
}

mergepolydecs(t: ref Type)
{
	n, nn: ref Node;
	id, ids, ids1: ref Decl;

	for(n = t.val; n != nil; n = n.right){
		nn = n.left;
		for(ids = nn.decl; ids != nil; ids = ids.next){
			id = ids.sym.decl;
			if(id == nil){
				undefed(ids.src, ids.sym);
				break;
			}
			if(id.store != Dtype){
				error(ids.src.start, declconv(id) + " is not a type");
				break;
			}
			if(id.ty.kind != Tpoly){
				error(ids.src.start, declconv(id) + " is not a polymorphic type");
				break;
			}
			if(id.ty.ids != nil)
				error(ids.src.start, declconv(id) + " redefined");
			pushscope(nil, Sother);
			fielddecled(nn.left);
			id.ty.ids = popscope();
			for(ids1 = id.ty.ids; ids1 != nil; ids1 = ids1.next){
				ids1.dot = id;
				bindtypes(ids1.ty);
				if(ids1.ty.kind != Tfn){
					error(ids1.src.start, "only function types expected");
					id.ty.ids = nil;
				}
			}
		}
	}
	t.val = nil;
}

adjfnptrs(d: ref Decl, polys1: ref Decl, polys2: ref Decl)
{
	n: int;
	id, idt, idf, arg: ref Decl;

	n = 0;
	for(id = d.ty.ids; id != nil; id = id.next)
		n++;
	for(idt = polys1; idt != nil; idt = idt.next)
		for(idf = idt.ty.ids; idf != nil; idf = idf.next)
			n -= 2;
	for(idt = polys2; idt != nil; idt = idt.next)
		for(idf = idt.ty.ids; idf != nil; idf = idf.next)
			n -= 2;
	for(arg = d.ty.ids; --n >= 0; arg = arg.next)
		;
	for(idt = polys1; idt != nil; idt = idt.next){
		for(idf = idt.ty.ids; idf != nil; idf = idf.next){
			idf.link = arg;
			arg = arg.next.next;
		}
	}
	for(idt = polys2; idt != nil; idt = idt.next){
		for(idf = idt.ty.ids; idf != nil; idf = idf.next){
			idf.link = arg;
			arg = arg.next.next;
		}
	}
}

addptrs(polys: ref Decl, fps: ref Decl, last: ref Decl, link: int, src: Src): (ref Decl, ref Decl)
{
	for(idt := polys; idt != nil; idt = idt.next){
		for(idf := idt.ty.ids; idf != nil; idf = idf.next){
			fp := mkdecl(src, Darg, tany);
			fp.sym = idf.sym;
			if(link)
				idf.link = fp;
			if(fps == nil)
				fps = fp;
			else
				last.next = fp;
			last = fp;
			fp = mkdecl(src, Darg, tint);
			fp.sym = idf.sym;
			last.next = fp;
			last = fp;
		}
	}
	return (fps, last);
}

addfnptrs(d: ref Decl, link: int)
{
	fps, last, polys: ref Decl;

	polys = encpolys(d);
	if(int(d.ty.flags&FULLARGS)){
		if(link)
			adjfnptrs(d, d.ty.polys, polys);
		return;
	}
	d.ty.flags |= FULLARGS;
	fps = last = nil;
	(fps, last) = addptrs(d.ty.polys, fps, last, link, d.src);
	(fps, last) = addptrs(polys, fps, last, link, d.src);
	for(last = d.ty.ids; last != nil && last.next != nil; last = last.next)
		;
	if(last != nil)
		last.next = fps;
	else
		d.ty.ids = fps;
	d.offset = idoffsets(d.ty.ids, MaxTemp, IBY2WD);
}

rmfnptrs(d: ref Decl)
{
	n: int;
	id, idt, idf: ref Decl;

	if(int(d.ty.flags&FULLARGS))
		d.ty.flags &= ~FULLARGS;
	else
		return;
	n = 0;
	for(id = d.ty.ids; id != nil; id = id.next)
		n++;
	for(idt = d.ty.polys; idt != nil; idt = idt.next)
		for(idf = idt.ty.ids; idf != nil; idf = idf.next)
			n -= 2;
	for(idt = encpolys(d); idt != nil; idt = idt.next)
		for(idf = idt.ty.ids; idf != nil; idf = idf.next)
			n -= 2;
	if(n == 0){
		d.ty.ids = nil;
		return;
	}
	for(id = d.ty.ids; --n > 0; id = id.next)
		;
	id.next = nil;
	d.offset = idoffsets(d.ty.ids, MaxTemp, IBY2WD);
}

local(d: ref Decl): int
{
	for(d = d.dot; d != nil; d = d.dot)
		if(d.store == Dtype && d.ty.kind == Tmodule)
			return 0;
	return 1;
}

lmodule(d: ref Decl): ref Decl
{
	for(d = d.dot; d != nil; d = d.dot)
		if(d.store == Dtype && d.ty.kind == Tmodule)
			return d;
	return nil;
}

outerpolys(n: ref Node): ref Decl
{
	d: ref Decl;

	if(n.op == Odot){
		d = n.right.decl;
		if(d == nil)
			fatal("decl() outeradt nil");
		d = d.dot;
		if(d != nil && d.store == Dtype && d.ty.kind == Tadt)
			return d.ty.polys;
	}
	return nil;
}

encpolys(d: ref Decl): ref Decl
{
	if((d = d.dot) == nil)
		return nil;
	return d.ty.polys;
}

fnlookup(s: ref Sym, t: ref Type): (ref Decl, ref Node)
{
	id: ref Decl;
	mod: ref Node;

	id = nil;
	mod = nil;
	if(t.kind == Tpoly || t.kind == Tmodule)
		id = namedot(t.ids, s);
	else if(t.kind == Tref){
		t = t.tof;
		if(t.kind == Tadt){
			id = namedot(t.ids, s);
			if(t.decl != nil && t.decl.timport != nil)
				mod = t.decl.timport.eimport;
		}
		else if(t.kind == Tadtpick){
			id = namedot(t.ids, s);
			if(t.decl != nil && t.decl.timport != nil)
				mod = t.decl.timport.eimport;
			t = t.decl.dot.ty;
			if(id == nil)
				id = namedot(t.ids, s);
			if(t.decl != nil && t.decl.timport != nil)
				mod = t.decl.timport.eimport;	
		}
	}
	if(id == nil){
		id = lookup(s);
		if(id != nil)
			mod = id.eimport;
	}
	return (id, mod);
}

isimpmod(s: ref Sym): int
{
	d: ref Decl;

	for(d = impmods; d != nil; d = d.next)
		if(d.sym == s)
			return 1;
	return 0;
}

dequal(d1: ref Decl, d2: ref Decl, full: int): int
{
	return	d1.sym == d2.sym &&
			d1.store == d2.store &&
			d1.implicit == d2.implicit &&
			d1.cyc == d2.cyc &&
			(!full || tequal(d1.ty, d2.ty)) &&
			(!full || d1.store == Dfn || sametree(d1.init, d2.init));
}

tzero(t: ref Type): int
{
	return t.kind == Texception || tmustzero(t);
}

isptr(t: ref Type): int
{
	return t.kind == Texception || tattr[t.kind].isptr;
}

# can d share the same stack location as another local ?
shareloc(d: ref Decl)
{
	z: int;
	t, tt: ref Type;
	dd, res: ref Decl;

	if(d.store != Dlocal || d.nid != byte 1)
		return;
	t = d.ty;
	res = nil;
	for(dd = fndecls; dd != nil; dd = dd.next){
		if(d == dd)
			fatal("d==dd in shareloc");
		if(dd.store != Dlocal || dd.nid != byte 1 || dd.link != nil || dd.tref != 0)
			continue;
		tt = dd.ty;
		if(t.size != tt.size || t.align != tt.align)
			continue;
		z = tzero(t)+tzero(tt);
		if(z > 0)
			continue;	# for now
		if(t == tt || tequal(t, tt))
			res = dd;
		else{
			if(z == 1)
				continue;
			if(z == 0 || isptr(t) || isptr(tt) || mktdesc(t) == mktdesc(tt))
				res = dd;
		}
		if(res != nil){
			d.link = res;
			res.tref = 1;
			return;
		}
	}
	return;
}

freeloc(d: ref Decl)
{
	if(d.link != nil)
		d.link.tref = 0;
}
