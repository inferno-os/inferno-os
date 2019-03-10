
kindname := array [Tend] of
{
	Tnone =>	"no type",
	Tadt =>		"adt",
	Tadtpick =>	"adt",
	Tarray =>	"array",
	Tbig =>		"big",
	Tbyte =>	"byte",
	Tchan =>	"chan",
	Treal =>	"real",
	Tfn =>		"fn",
	Tint =>		"int",
	Tlist =>	"list",
	Tmodule =>	"module",
	Tref =>		"ref",
	Tstring =>	"string",
	Ttuple =>	"tuple",
	Texception => "exception",
	Tfix => "fixed point",
	Tpoly => "polymorphic",

	Tainit =>	"array initializers",
	Talt =>		"alt channels",
	Tany =>		"polymorphic type",
	Tarrow =>	"->",
	Tcase =>	"case int labels",
	Tcasel =>	"case big labels",
	Tcasec =>	"case string labels",
	Tdot =>		".",
	Terror =>	"type error",
	Tgoto =>	"goto labels",
	Tid =>		"id",
	Tiface =>	"module interface",
	Texcept =>	"exception handler table",
	Tinst =>	"instantiated type",
};

tattr = array[Tend] of
{
	#		     isptr	refable	conable	big	vis
	Tnone =>	Tattr(0,	0,	0,	0,	0),
	Tadt =>		Tattr(0,	1,	1,	1,	1),
	Tadtpick =>	Tattr(0,	1,	0,	1,	1),
	Tarray =>	Tattr(1,	0,	0,	0,	1),
	Tbig =>		Tattr(0,	0,	1,	1,	1),
	Tbyte =>	Tattr(0,	0,	1,	0,	1),
	Tchan =>	Tattr(1,	0,	0,	0,	1),
	Treal =>	Tattr(0,	0,	1,	1,	1),
	Tfn =>		Tattr(0,	1,	0,	0,	1),
	Tint =>		Tattr(0,	0,	1,	0,	1),
	Tlist =>	Tattr(1,	0,	0,	0,	1),
	Tmodule =>	Tattr(1,	0,	0,	0,	1),
	Tref =>		Tattr(1,	0,	0,	0,	1),
	Tstring =>	Tattr(1,	0,	1,	0,	1),
	Ttuple =>	Tattr(0,	1,	1,	1,	1),
	Texception => Tattr(0,	0,	0,	1,	1),
	Tfix =>		Tattr(0,	0,	1,	0,	1),
	Tpoly =>	Tattr(1,	0,	0,	0,	1),

	Tainit =>	Tattr(0,	0,	0,	1,	0),
	Talt =>		Tattr(0,	0,	0,	1,	0),
	Tany =>		Tattr(1,	0,	0,	0,	0),
	Tarrow =>	Tattr(0,	0,	0,	0,	1),
	Tcase =>	Tattr(0,	0,	0,	1,	0),
	Tcasel =>	Tattr(0,	0,	0,	1,	0),
	Tcasec =>	Tattr(0,	0,	0,	1,	0),
	Tdot =>		Tattr(0,	0,	0,	0,	1),
	Terror =>	Tattr(0,	1,	1,	0,	0),
	Tgoto =>	Tattr(0,	0,	0,	1,	0),
	Tid =>		Tattr(0,	0,	0,	0,	1),
	Tiface =>	Tattr(0,	0,	0,	1,	0),
	Texcept =>	Tattr(0,	0,	0,	1,	0),
	Tinst =>	Tattr(0,	1,	1,	1,	1),
};

eqclass:	array of ref Teq;

ztype:		Type;
eqrec:		int;
eqset:		int;
adts:		array of ref Decl;
nadts:		int;
anontupsym:	ref Sym;
unifysrc:	Src;

addtmap(t1: ref Type, t2: ref Type, tph: ref Tpair): ref Tpair
{
	tp: ref Tpair;

	tp = ref Tpair;
	tp.t1 = t1;
	tp.t2 = t2;
	tp.nxt = tph;
	return tp;
}

valtmap(t: ref Type, tp: ref Tpair): ref Type
{
	for( ; tp != nil; tp = tp.nxt)
		if(tp.t1 == t)
			return tp.t2;
	return t;
}

addtype(t: ref Type, hdl: ref Typelist): ref Typelist
{
	tll := ref Typelist;
	tll.t = t;
	tll.nxt = nil;
	if(hdl == nil)
		return tll;
	for(p := hdl; p.nxt != nil; p = p.nxt)
		;
	p.nxt = tll;
	return hdl;
}

typeinit()
{
	anontupsym = enter(".tuple", 0);

	ztype.sbl = -1;
	ztype.ok = byte 0;
	ztype.rec = byte 0;

	tbig = mktype(noline, noline, Tbig, nil, nil);
	tbig.size = IBY2LG;
	tbig.align = IBY2LG;
	tbig.ok = OKmask;

	tbyte = mktype(noline, noline, Tbyte, nil, nil);
	tbyte.size = 1;
	tbyte.align = 1;
	tbyte.ok = OKmask;

	tint = mktype(noline, noline, Tint, nil, nil);
	tint.size = IBY2WD;
	tint.align = IBY2WD;
	tint.ok = OKmask;

	treal = mktype(noline, noline, Treal, nil, nil);
	treal.size = IBY2FT;
	treal.align = IBY2FT;
	treal.ok = OKmask;

	tstring = mktype(noline, noline, Tstring, nil, nil);
	tstring.size = IBY2WD;
	tstring.align = IBY2WD;
	tstring.ok = OKmask;

	texception = mktype(noline, noline, Texception, nil, nil);
	texception.size = IBY2WD;
	texception.align = IBY2WD;
	texception.ok = OKmask;

	tany = mktype(noline, noline, Tany, nil, nil);
	tany.size = IBY2WD;
	tany.align = IBY2WD;
	tany.ok = OKmask;

	tnone = mktype(noline, noline, Tnone, nil, nil);
	tnone.size = 0;
	tnone.align = 1;
	tnone.ok = OKmask;

	terror = mktype(noline, noline, Terror, nil, nil);
	terror.size = 0;
	terror.align = 1;
	terror.ok = OKmask;

	tunknown = mktype(noline, noline, Terror, nil, nil);
	tunknown.size = 0;
	tunknown.align = 1;
	tunknown.ok = OKmask;

	tfnptr = mktype(noline, noline, Ttuple, nil, nil);
	id := tfnptr.ids = mkids(nosrc, nil, tany, nil);
	id.store = Dfield;
	id.offset = 0;
	id.sym = enter("t0", 0);
	id.src = Src(0, 0);
	id = tfnptr.ids.next = mkids(nosrc, nil, tint, nil);
	id.store = Dfield;
	id.offset = IBY2WD;
	id.sym = enter("t1", 0);
	id.src = Src(0, 0);

	rtexception = mktype(noline, noline, Tref, texception, nil);
	rtexception.size = IBY2WD;
	rtexception.align = IBY2WD;
	rtexception.ok = OKmask;
}

typestart()
{
	descriptors = nil;
	nfns = 0;
	adts = nil;
	nadts = 0;
	selfdecl = nil;
	if(tfnptr.decl != nil)
		tfnptr.decl.desc = nil;

	eqclass = array[Tend] of ref Teq;

	typebuiltin(mkids(nosrc, enter("int", 0), nil, nil), tint);
	typebuiltin(mkids(nosrc, enter("big", 0), nil, nil), tbig);
	typebuiltin(mkids(nosrc, enter("byte", 0), nil, nil), tbyte);
	typebuiltin(mkids(nosrc, enter("string", 0), nil, nil), tstring);
	typebuiltin(mkids(nosrc, enter("real", 0), nil, nil), treal);
}

modclass(): ref Teq
{
	return eqclass[Tmodule];
}

mktype(start: Line, stop: Line, kind: int, tof: ref Type, args: ref Decl): ref Type
{
	t := ref ztype;
	t.src.start = start;
	t.src.stop = stop;
	t.kind = kind;
	t.tof = tof;
	t.ids = args;
	return t;
}

nalt: int;
mktalt(c: ref Case): ref Type
{
	t := mktype(noline, noline, Talt, nil, nil);
	t.decl = mkdecl(nosrc, Dtype, t);
	t.decl.sym = enter(".a"+string nalt++, 0);
	t.cse = c;
	return usetype(t);
}

#
# copy t and the top level of ids
#
copytypeids(t: ref Type): ref Type
{
	last: ref Decl;

	nt := ref *t;
	for(id := t.ids; id != nil; id = id.next){
		new := ref *id;
		if(last == nil)
			nt.ids = new;
		else
			last.next = new;
		last = new;
	}
	return nt;
}

#
# make each of the ids have type t
#
typeids(ids: ref Decl, t: ref Type): ref Decl
{
	if(ids == nil)
		return nil;

	ids.ty = t;
	for(id := ids.next; id != nil; id = id.next)
		id.ty = t;
	return ids;
}

typebuiltin(d: ref Decl, t: ref Type)
{
	d.ty = t;
	t.decl = d;
	installids(Dtype, d);
}

fielddecl(store: int, ids: ref Decl): ref Node
{
	n := mkn(Ofielddecl, nil, nil);
	n.decl = ids;
	for(; ids != nil; ids = ids.next)
		ids.store = store;
	return n;
}

typedecl(ids: ref Decl, t: ref Type): ref Node
{
	if(t.decl == nil)
		t.decl = ids;
	n := mkn(Otypedecl, nil, nil);
	n.decl = ids;
	n.ty = t;
	for(; ids != nil; ids = ids.next)
		ids.ty = t;
	return n;
}

typedecled(n: ref Node)
{
	installids(Dtype, n.decl);
}

adtdecl(ids: ref Decl, fields: ref Node): ref Node
{
	n := mkn(Oadtdecl, nil, nil);
	t := mktype(ids.src.start, ids.src.stop, Tadt, nil, nil);
	n.decl = ids;
	n.left = fields;
	n.ty = t;
	t.decl = ids;
	for(; ids != nil; ids = ids.next)
		ids.ty = t;
	return n;
}

adtdecled(n: ref Node)
{
	d := n.ty.decl;
	installids(Dtype, d);
	if(n.ty.polys != nil){
		pushscope(nil, Sother);
		installids(Dtype, n.ty.polys);
	}
	pushscope(nil, Sother);
	fielddecled(n.left);
	n.ty.ids = popscope();
	if(n.ty.polys != nil)
		n.ty.polys = popscope();
	for(ids := n.ty.ids; ids != nil; ids = ids.next)
		ids.dot = d;
}

fielddecled(n: ref Node)
{
	for(; n != nil; n = n.right){
		case n.op{
		Oseq =>
			fielddecled(n.left);
		Oadtdecl =>
			adtdecled(n);
			return;
		Otypedecl =>
			typedecled(n);
			return;
		Ofielddecl =>
			installids(Dfield, n.decl);
			return;
		Ocondecl =>
			condecled(n);
			gdasdecl(n.right);
			return;
		Oexdecl =>
			exdecled(n);
			return;
		Opickdecl =>
			pickdecled(n);
			return;
		* =>
			fatal("can't deal with "+opname[n.op]+" in fielddecled");
		}
	}
}

pickdecled(n: ref Node): int
{
	if(n == nil)
		return 0;
	tag := pickdecled(n.left);
	pushscope(nil, Sother);
	fielddecled(n.right.right);
	d := n.right.left.decl;
	d.ty.ids = popscope();
	installids(Dtag, d);
	for(; d != nil; d = d.next)
		d.tag = tag++;
	return tag;
}

#
# make the tuple type used to initialize adt t
#
mkadtcon(t: ref Type): ref Type
{
	last: ref Decl;

	nt := ref *t;
	nt.ids = nil;
	nt.kind = Ttuple;
	for(id := t.ids; id != nil; id = id.next){
		if(id.store != Dfield)
			continue;
		new := ref *id;
		new.cyc = byte 0;
		if(last == nil)
			nt.ids = new;
		else
			last.next = new;
		last = new;
	}
	last.next = nil;
	return nt;
}

#
# make the tuple type used to initialize t,
# an adt with pick fields tagged by tg
#
mkadtpickcon(t, tgt: ref Type): ref Type
{
	last := mkids(tgt.decl.src, nil, tint, nil);
	last.store = Dfield;
	nt := mktype(t.src.start, t.src.stop, Ttuple, nil, last);
	for(id := t.ids; id != nil; id = id.next){
		if(id.store != Dfield)
			continue;
		new := ref *id;
		new.cyc = byte 0;
		last.next = new;
		last = new;
	}
	for(id = tgt.ids; id != nil; id = id.next){
		if(id.store != Dfield)
			continue;
		new := ref *id;
		new.cyc = byte 0;
		last.next = new;
		last = new;
	}
	last.next = nil;
	return nt;
}

#
# make an identifier type
#
mkidtype(src: Src, s: ref Sym): ref Type
{
	t := mktype(src.start, src.stop, Tid, nil, nil);
	if(s.unbound == nil){
		s.unbound = mkdecl(src, Dunbound, nil);
		s.unbound.sym = s;
	}
	t.decl = s.unbound;
	return t;
}

#
# make a qualified type for t->s
#
mkarrowtype(start: Line, stop: Line, t: ref Type, s: ref Sym): ref Type
{
	t = mktype(start, stop, Tarrow, t, nil);
	if(s.unbound == nil){
		s.unbound = mkdecl(Src(start, stop), Dunbound, nil);
		s.unbound.sym = s;
	}
	t.decl = s.unbound;
	return t;
}

#
# make a qualified type for t.s
#
mkdottype(start: Line, stop: Line, t: ref Type, s: ref Sym): ref Type
{
	t = mktype(start, stop, Tdot, t, nil);
	if(s.unbound == nil){
		s.unbound = mkdecl(Src(start, stop), Dunbound, nil);
		s.unbound.sym = s;
	}
	t.decl = s.unbound;
	return t;
}

mkinsttype(src: Src, tt: ref Type, tyl: ref Typelist): ref Type
{
	t := mktype(src.start, src.stop, Tinst, tt, nil);
	t.tlist = tyl;
	return t;
}

#
# look up the name f in the fields of a module, adt, or tuple
#
namedot(ids: ref Decl, s: ref Sym): ref Decl
{
	for(; ids != nil; ids = ids.next)
		if(ids.sym == s)
			return ids;
	return nil;
}

#
# complete the declaration of an adt
# methods frames get sized in module definition or during function definition
# place the methods at the end of the field list
#
adtdefd(t: ref Type)
{
	next, aux, store, auxhd, tagnext: ref Decl;

	if(debug['x'])
		print("adt %s defd\n", typeconv(t));
	d := t.decl;
	tagnext = nil;
	store = nil;
	for(id := t.polys; id != nil; id = id.next){
		id.store = Dtype;
		id.ty = verifytypes(id.ty, d, nil);
	}
	for(id = t.ids; id != nil; id = next){
		if(id.store == Dtag){
			if(t.tags != nil)
				error(id.src.start, "only one set of pick fields allowed");
			tagnext = pickdefd(t, id);
			next = tagnext;
			if(store != nil)
				store.next = next;
			else
				t.ids = next;
			continue;
		}else{
			id.dot = d;
			next = id.next;
			store = id;
		}
	}
	aux = nil;
	store = nil;
	auxhd = nil;
	seentags := 0;
	for(id = t.ids; id != nil; id = next){
		if(id == tagnext)
			seentags = 1;

		next = id.next;
		id.dot = d;
		id.ty = topvartype(verifytypes(id.ty, d, nil), id, 1, 1);
		if(id.store == Dfield && id.ty.kind == Tfn)
			id.store = Dfn;
		if(id.store == Dfn || id.store == Dconst){
			if(store != nil)
				store.next = next;
			else
				t.ids = next;
			if(aux != nil)
				aux.next = id;
			else
				auxhd = id;
			aux = id;
		}else{
			if(seentags)
				error(id.src.start, "pick fields must be the last data fields in an adt");
			store = id;
		}
	}
	if(aux != nil)
		aux.next = nil;
	if(store != nil)
		store.next = auxhd;
	else
		t.ids = auxhd;

	for(id = t.tags; id != nil; id = id.next){
		id.ty = verifytypes(id.ty, d, nil);
		if(id.ty.tof == nil)
			id.ty.tof = mkadtpickcon(t, id.ty);
	}
}

#
# assemble the data structure for an adt with a pick clause.
# since the scoping rules for adt pick fields are strange,
# we have a customized check for overlapping definitions.
#
pickdefd(t: ref Type, tg: ref Decl): ref Decl
{
	lasttg : ref Decl = nil;
	d := t.decl;
	t.tags = tg;
	tag := 0;
	while(tg != nil){
		tt := tg.ty;
		if(tt.kind != Tadtpick || tg.tag != tag)
			break;
		tt.decl = tg;
		lasttg = tg;
		for(; tg != nil; tg = tg.next){
			if(tg.ty != tt)
				break;
			tag++;
			lasttg = tg;
			tg.dot = d;
		}
		for(id := tt.ids; id != nil; id = id.next){
			xid := namedot(t.ids, id.sym);
			if(xid != nil)
				error(id.src.start, "redeclaration of "+declconv(id)+
					" previously declared as "+storeconv(xid)+" on line "+lineconv(xid.src.start));
			id.dot = d;
		}
	}
	if(lasttg == nil){
		error(t.src.start, "empty pick field declaration in "+typeconv(t));
		t.tags = nil;
	}else
		lasttg.next = nil;
	d.tag = tag;
	return tg;
}

moddecl(ids: ref Decl, fields: ref Node): ref Node
{
	n := mkn(Omoddecl, mkn(Oseq, nil, nil), nil);
	t := mktype(ids.src.start, ids.src.stop, Tmodule, nil, nil);
	n.decl = ids;
	n.left = fields;
	n.ty = t;
	return n;
}

moddecled(n: ref Node)
{
	d := n.decl;
	installids(Dtype, d);
	isimp := 0;
	for(ids := d; ids != nil; ids = ids.next){
		for(im := impmods; im != nil; im = im.next){
			if(ids.sym == im.sym){
				isimp = 1;
				d = ids;
				dm := ref Dlist;
				dm.d = ids;
				dm.next = nil;
				if(impdecls == nil)
					impdecls = dm;
				else{
					for(dl := impdecls; dl.next != nil; dl = dl.next)
						;
					dl.next = dm;
				}
			}
		}
		ids.ty = n.ty;
	}
	pushscope(nil, Sother);
	fielddecled(n.left);

	d.ty.ids = popscope();

	#
	# make the current module the . parent of all contained decls.
	#
	for(ids = d.ty.ids; ids != nil; ids = ids.next)
		ids.dot = d;

	t := d.ty;
	t.decl = d;
	if(debug['m'])
		print("declare module %s\n", d.sym.name);

	#
	# add the iface declaration in case it's needed later
	#
	installids(Dglobal, mkids(d.src, enter(".m."+d.sym.name, 0), tnone, nil));

	if(isimp){
		for(ids = d.ty.ids; ids != nil; ids = ids.next){
			s := ids.sym;
			if(s.decl != nil && s.decl.scope >= scope){
				dot := s.decl.dot;
				if(s.decl.store != Dwundef && dot != nil && dot != d && isimpmod(dot.sym) && dequal(ids, s.decl, 0))
					continue;
				redecl(ids);
				ids.old = s.decl.old;
			}else
				ids.old = s.decl;
			s.decl = ids;
			ids.scope = scope;
		}
	}
}

#
# for each module in id,
# link by field ext all of the decls for
# functions needed in external linkage table
# collect globals and make a tuple for all of them
#
mkiface(m: ref Decl): ref Type
{
	iface := last := ref Decl;
	globals := glast := mkdecl(m.src, Dglobal, mktype(m.src.start, m.src.stop, Tadt, nil, nil));
	for(id := m.ty.ids; id != nil; id = id.next){
		case id.store{
		Dglobal =>
			glast = glast.next = dupdecl(id);
			id.iface = globals;
			glast.iface = id;
		Dfn =>
			id.iface = last = last.next = dupdecl(id);
			last.iface = id;
		Dtype =>
			if(id.ty.kind != Tadt)
				break;
			for(d := id.ty.ids; d != nil; d = d.next){
				if(d.store == Dfn){
					d.iface = last = last.next = dupdecl(d);
					last.iface = d;
				}
			}
		}
	}
	last.next = nil;
	iface = namesort(iface.next);

	if(globals.next != nil){
		glast.next = nil;
		globals.ty.ids = namesort(globals.next);
		globals.ty.decl = globals;
		globals.sym = enter(".mp", 0);
		globals.dot = m;
		globals.next = iface;
		iface = globals;
	}

	#
	# make the interface type and install an identifier for it
	# the iface has a ref count if it is loaded
	#
	t := mktype(m.src.start, m.src.stop, Tiface, nil, iface);
	id = enter(".m."+m.sym.name, 0).decl;
	t.decl = id;
	id.ty = t;

	#
	# dummy node so the interface is initialized
	#
	id.init = mkn(Onothing, nil, nil);
	id.init.ty = t;
	id.init.decl = id;
	return t;
}

joiniface(mt, t: ref Type)
{
	iface := t.ids;
	globals := iface;
	if(iface != nil && iface.store == Dglobal)
		iface = iface.next;
	for(id := mt.tof.ids; id != nil; id = id.next){
		case id.store{
		Dglobal =>
			for(d := id.ty.ids; d != nil; d = d.next)
				d.iface.iface = globals;
		Dfn =>
			id.iface.iface = iface;
			iface = iface.next;
		* =>
			fatal("unknown store "+storeconv(id)+" in joiniface");
		}
	}
	if(iface != nil)
		fatal("join iface not matched");
	mt.tof = t;
}

addiface(m: ref Decl, d: ref Decl)
{
	t: ref Type;
	id, last, dd, lastorig: ref Decl;

	if(d == nil || !local(d))
		return;
	modrefable(d.ty);
	if(m == nil){
		if(impdecls.next != nil)
			for(dl := impdecls; dl != nil; dl = dl.next)
				if(dl.d.ty.tof != impdecl.ty.tof)	# impdecl last
					addiface(dl.d, d);
		addiface(impdecl, d);
		return;
	}
	t = m.ty.tof;
	last = nil;
	lastorig = nil;
	for(id = t.ids; id != nil; id = id.next){
		if(d == id || d == id.iface)
			return;
		last = id;
		if(id.tag == 0)
			lastorig = id;
	}
	dd = dupdecl(d);
	if(d.dot == nil)
		d.dot = dd.dot = m;
	d.iface = dd;
	dd.iface = d;
	if(last == nil)
		t.ids = dd;
	else
		last.next = dd;
	dd.tag = 1;	# mark so not signed
	if(lastorig == nil)
		t.ids = namesort(t.ids);
	else
		lastorig.next = namesort(lastorig.next);
}

#
# eliminate unused declarations from interfaces
# label offset within interface
#
narrowmods()
{
	id: ref Decl;
	for(eq := modclass(); eq != nil; eq = eq.eq){
		t := eq.ty.tof;

		if(t.linkall == byte 0){
			last : ref Decl = nil;
			for(id = t.ids; id != nil; id = id.next){
				if(id.refs == 0){
					if(last == nil)
						t.ids = id.next;
					else
						last.next = id.next;
				}else
					last = id;
			}

			#
			# need to resize smaller interfaces
			#
			resizetype(t);
		}

		offset := 0;
		for(id = t.ids; id != nil; id = id.next)
			id.offset = offset++;

		#
		# rathole to stuff number of entries in interface
		#
		t.decl.init.c = ref Const;
		t.decl.init.c.val = big offset;
	}
}

#
# check to see if any data field of module m if referenced.
# if so, mark all data in m
#
moddataref()
{
	for(eq := modclass(); eq != nil; eq = eq.eq){
		id := eq.ty.tof.ids;
		if(id != nil && id.store == Dglobal && id.refs)
			for(id = eq.ty.ids; id != nil; id = id.next)
				if(id.store == Dglobal)
					modrefable(id.ty);
	}
}

#
# move the global declarations in interface to the front
#
modglobals(mod, globals: ref Decl): ref Decl
{
	#
	# make a copy of all the global declarations
	# 	used for making a type descriptor for globals ONLY
	# note we now have two declarations for the same variables,
	# which is apt to cause problems if code changes
	#
	# here we fix up the offsets for the real declarations
	#
	idoffsets(mod.ty.ids, 0, 1);

	last := head := ref Decl;
	for(id := mod.ty.ids; id != nil; id = id.next)
		if(id.store == Dglobal)
			last = last.next = dupdecl(id);

	last.next = globals;
	return head.next;
}

#
# snap all id type names to the actual type
# check that all types are completely defined
# verify that the types look ok
#
validtype(t: ref Type, inadt: ref Decl): ref Type
{
	if(t == nil)
		return t;
	bindtypes(t);
	t = verifytypes(t, inadt, nil);
	cycsizetype(t);
	teqclass(t);
	return t;
}

usetype(t: ref Type): ref Type
{
	if(t == nil)
		return t;
	t = validtype(t, nil);
	reftype(t);
	return t;
}

internaltype(t: ref Type): ref Type
{
	bindtypes(t);
	t.ok = OKverify;
	sizetype(t);
	t.ok = OKmask;
	return t;
}

#
# checks that t is a valid top-level type
#
topvartype(t: ref Type, id: ref Decl, tyok: int, polyok: int): ref Type
{
	if(t.kind == Tadt && t.tags != nil || t.kind == Tadtpick)
		error(id.src.start, "cannot declare "+id.sym.name+" with type "+typeconv(t));
	if(!tyok && t.kind == Tfn)
		error(id.src.start, "cannot declare "+id.sym.name+" to be a function");
	if(!polyok && (t.kind == Tadt || t.kind == Tadtpick) && ispolyadt(t))
		error(id.src.start, "cannot declare " + id.sym.name + " of a polymorphic type");
	return t;
}

toptype(src: Src, t: ref Type): ref Type
{
	if(t.kind == Tadt && t.tags != nil || t.kind == Tadtpick)
		error(src.start, typeconv(t)+", an adt with pick fields, must be used with ref");
	if(t.kind == Tfn)
		error(src.start, "data cannot have a fn type like "+typeconv(t));
	return t;
}

comtype(src: Src, t: ref Type, adtd: ref Decl): ref Type
{
	if(adtd == nil && (t.kind == Tadt || t.kind == Tadtpick) && ispolyadt(t))
		error(src.start, "polymorphic type " + typeconv(t) + " illegal here");
	return t;
}

usedty(t: ref Type)
{
	if(t != nil && (t.ok | OKmodref) != OKmask)
		fatal("used ty " + stypeconv(t) + " " + hex(int t.ok, 2));
}

bindtypes(t: ref Type)
{
	id: ref Decl;

	if(t == nil)
		return;
	if((t.ok & OKbind) == OKbind)
		return;
	t.ok |= OKbind;
	case t.kind{
	Tadt =>
		if(t.polys != nil){
			pushscope(nil, Sother);
			installids(Dtype, t.polys);
		}
		if(t.val != nil)
			mergepolydecs(t);
		if(t.polys != nil){
			popscope();
			for(id = t.polys; id != nil; id = id.next)
				bindtypes(id.ty);
		}
	Tadtpick or
	Tmodule or
	Terror or
	Tint or
	Tbig or
	Tstring or
	Treal or
	Tbyte or
	Tnone or
	Tany or
	Tiface or
	Tainit or
	Talt or
	Tcase or
	Tcasel or
	Tcasec or
	Tgoto or
	Texcept or
	Tfix or
	Tpoly =>
		break;
	Tarray or
	Tarrow or
	Tchan or
	Tdot or
	Tlist or
	Tref =>
		bindtypes(t.tof);
	Tid =>
		id = t.decl.sym.decl;
		if(id == nil)
			id = undefed(t.src, t.decl.sym);
		# save a little space
		id.sym.unbound = nil;
		t.decl = id;
	Ttuple or
	Texception =>
		for(id = t.ids; id != nil; id = id.next)
			bindtypes(id.ty);
	Tfn =>
		if(t.polys != nil){
			pushscope(nil, Sother);
			installids(Dtype, t.polys);
		}
		for(id = t.ids; id != nil; id = id.next)
			bindtypes(id.ty);
		bindtypes(t.tof);
		if(t.val != nil)
			mergepolydecs(t);
		if(t.polys != nil){
			popscope();
			for(id = t.polys; id != nil; id = id.next)
				bindtypes(id.ty);
		}
	Tinst =>
		bindtypes(t.tof);
		for(tyl := t.tlist; tyl != nil; tyl = tyl.nxt)
			bindtypes(tyl.t);
	* =>
		fatal("bindtypes: unknown type kind "+string t.kind);
	}
}

#
# walk the type checking for validity
#
verifytypes(t: ref Type, adtt: ref Decl, poly: ref Decl): ref Type
{
	id: ref Decl;

	if(t == nil)
		return nil;
	if((t.ok & OKverify) == OKverify)
		return t;
	t.ok |= OKverify;
if((t.ok & (OKverify|OKbind)) != (OKverify|OKbind))
fatal("verifytypes bogus ok for " + stypeconv(t));
	cyc := t.flags&CYCLIC;
	case t.kind{
	Terror or
	Tint or
	Tbig or
	Tstring or
	Treal or
	Tbyte or
	Tnone or
	Tany or
	Tiface or
	Tainit or
	Talt or
	Tcase or
	Tcasel or
	Tcasec or
	Tgoto or
	Texcept =>
		break;
	Tfix =>
		n := t.val;
		ok: int;
		max := 0.0;
		if(n.op == Oseq){
			(ok, nil) = echeck(n.left, 0, 0, n);
			(ok1, nil) := echeck(n.right, 0, 0, n);
			if(!ok || !ok1)
				return terror;
			if(n.left.ty != treal || n.right.ty != treal){
				error(t.src.start, "fixed point scale/maximum not real");
				return terror;
			}
			n.right = fold(n.right);
			if(n.right.op != Oconst){
				error(t.src.start, "fixed point maximum not constant");
				return terror;
			}
			if((max = n.right.c.rval) <= 0.0){
				error(t.src.start, "non-positive fixed point maximum");
				return terror;
			}
			n = n.left;
		}
		else{
			(ok, nil) = echeck(n, 0, 0, nil);
			if(!ok)
				return terror;
			if(n.ty != treal){
				error(t.src.start, "fixed point scale not real");
				return terror;
			}
		}
		n = t.val = fold(n);
		if(n.op != Oconst){
			error(t.src.start, "fixed point scale not constant");
			return terror;
		}
		if(n.c.rval <= 0.0){
			error(t.src.start, "non-positive fixed point scale");
			return terror;
		}
		ckfix(t, max);
	Tref =>
		t.tof = comtype(t.src, verifytypes(t.tof, adtt, nil), adtt);
		if(t.tof != nil && !tattr[t.tof.kind].refable){
			error(t.src.start, "cannot have a ref " + typeconv(t.tof));
			return terror;
		}
		if(0 && t.tof.kind == Tfn && t.tof.ids != nil && int t.tof.ids.implicit)
			error(t.src.start, "function references cannot have a self argument");
		if(0 && t.tof.kind == Tfn && t.polys != nil)
			error(t.src.start, "function references cannot be polymorphic");
	Tchan or
	Tarray or
	Tlist =>
		t.tof = comtype(t.src, toptype(t.src, verifytypes(t.tof, adtt, nil)), adtt);
	Tid =>
		t.ok &= ~OKverify;
		t = verifytypes(idtype(t), adtt, nil);
	Tarrow =>
		t.ok &= ~OKverify;
		t = verifytypes(arrowtype(t, adtt), adtt, nil);
	Tdot =>
		#
		# verify the parent adt & lookup the tag fields
		#
		t.ok &= ~OKverify;
		t = verifytypes(dottype(t, adtt), adtt, nil);
	Tadt =>
		#
		# this is where Tadt may get tag fields added
		#
		adtdefd(t);
	Tadtpick =>
		for(id = t.ids; id != nil; id = id.next){
			id.ty = topvartype(verifytypes(id.ty, id.dot, nil), id, 0, 1);
			if(id.store == Dconst)
				error(t.src.start, "cannot declare a con like "+id.sym.name+" within a pick");
		}
		verifytypes(t.decl.dot.ty, nil, nil);
	Tmodule =>
		for(id = t.ids; id != nil; id = id.next){
			id.ty = verifytypes(id.ty, nil, nil);
			if(id.store == Dglobal && id.ty.kind == Tfn)
				id.store = Dfn;
			if(id.store != Dtype && id.store != Dfn)
				topvartype(id.ty, id, 0, 0);
		}
	Ttuple or
	Texception =>
		if(t.decl == nil){
			t.decl = mkdecl(t.src, Dtype, t);
			t.decl.sym = anontupsym;
		}
		i := 0;
		for(id = t.ids; id != nil; id = id.next){
			id.store = Dfield;
			if(id.sym == nil)
				id.sym = enter("t"+string i, 0);
			i++;
			id.ty = toptype(id.src, verifytypes(id.ty, adtt, nil));
		}
	Tfn =>
		last : ref Decl = nil;
		for(id = t.ids; id != nil; id = id.next){
			id.store = Darg;
			id.ty = topvartype(verifytypes(id.ty, adtt, nil), id, 0, 1);
			if(id.implicit != byte 0){
				if(poly != nil)
					selfd := poly;
				else
					selfd = adtt;
				if(selfd == nil)
					error(t.src.start, "function is not a member of an adt, so can't use self");
				else if(id != t.ids)
					error(id.src.start, "only the first argument can use self");
				else if(id.ty != selfd.ty && (id.ty.kind != Tref || id.ty.tof != selfd.ty))
					error(id.src.start, "self argument's type must be "+selfd.sym.name+" or ref "+selfd.sym.name);
			}
			last = id;
		}
		for(id = t.polys; id != nil; id = id.next){
			if(adtt != nil){
				for(id1 := adtt.ty.polys; id1 != nil; id1 = id1.next){
					if(id1.sym == id.sym)
						id.ty = id1.ty;
				}
			}
			id.store = Dtype;
			id.ty = verifytypes(id.ty, adtt, nil);
		}
		t.tof = comtype(t.src, toptype(t.src, verifytypes(t.tof, adtt, nil)), adtt);
		if(t.varargs != byte 0 && (last == nil || last.ty != tstring))
			error(t.src.start, "variable arguments must be preceded by a string");
		if(t.varargs != byte 0 && t.polys != nil)
			error(t.src.start, "polymorphic functions must not have variable arguments");
	Tpoly =>
		for(id = t.ids; id != nil; id = id.next){
			id.store = Dfn;
			id.ty = verifytypes(id.ty, adtt, t.decl);
		}
	Tinst =>
		t.ok &= ~OKverify;
		t.tof = verifytypes(t.tof, adtt, nil);
		for(tyl := t.tlist; tyl != nil; tyl = tyl.nxt)
			tyl.t = verifytypes(tyl.t, adtt, nil);
		(t, nil) = insttype(t, adtt, nil);
		t = verifytypes(t, adtt, nil);
	* =>
		fatal("verifytypes: unknown type kind "+string t.kind);
	}
	if(int cyc)
		t.flags |= CYCLIC;
	return t;
}

#
# resolve an id type
#
idtype(t: ref Type): ref Type
{
	id := t.decl;
	if(id.store == Dunbound)
		fatal("idtype: unbound decl");
	tt := id.ty;
	if(id.store != Dtype && id.store != Dtag){
		if(id.store == Dundef){
			id.store = Dwundef;
			error(t.src.start, id.sym.name+" is not declared");
		}else if(id.store == Dimport){
			id.store = Dwundef;
			error(t.src.start, id.sym.name+"'s type cannot be determined");
		}else if(id.store != Dwundef)
			error(t.src.start, id.sym.name+" is not a type");
		return terror;
	}
	if(tt == nil){
		error(t.src.start, stypeconv(t)+" not fully defined");
		return terror;
	}
	return tt;
}

#
# resolve a -> qualified type
#
arrowtype(t: ref Type, adtt: ref Decl): ref Type
{
	id := t.decl;
	if(id.ty != nil){
		if(id.store == Dunbound)
			fatal("arrowtype: unbound decl has a type");
		return id.ty;
	}

	#
	# special hack to allow module variables to derive other types
	# 
	tt := t.tof;
	if(tt.kind == Tid){
		id = tt.decl;
		if(id.store == Dunbound)
			fatal("arrowtype: Tid's decl unbound");
		if(id.store == Dimport){
			id.store = Dwundef;
			error(t.src.start, id.sym.name+"'s type cannot be determined");
			return terror;
		}

		#
		# forward references to module variables can't be resolved
		#
		if(id.store != Dtype && (id.ty.ok & OKbind) != OKbind){
			error(t.src.start, id.sym.name+"'s type cannot be determined");
			return terror;
		}

		if(id.store == Dwundef)
			return terror;
		tt = id.ty = verifytypes(id.ty, adtt, nil);
		if(tt == nil){
			error(t.tof.src.start, typeconv(t.tof)+" is not a module");
			return terror;
		}
	}else
		tt = verifytypes(t.tof, adtt, nil);
	t.tof = tt;
	if(tt == terror)
		return terror;
	if(tt.kind != Tmodule){
		error(t.src.start, typeconv(tt)+" is not a module");
		return terror;
	}
	id = namedot(tt.ids, t.decl.sym);
	if(id == nil){
		error(t.src.start, t.decl.sym.name+" is not a member of "+typeconv(tt));
		return terror;
	}
	if(id.store == Dtype && id.ty != nil){
		t.decl = id;
		return id.ty;
	}
	error(t.src.start, typeconv(t)+" is not a type");
	return terror;
}

#
# resolve a . qualified type
#
dottype(t: ref Type, adtt: ref Decl): ref Type
{
	if(t.decl.ty != nil){
		if(t.decl.store == Dunbound)
			fatal("dottype: unbound decl has a type");
		return t.decl.ty;
	}
	t.tof = tt := verifytypes(t.tof, adtt, nil);
	if(tt == terror)
		return terror;
	if(tt.kind != Tadt){
		error(t.src.start, typeconv(tt)+" is not an adt");
		return terror;
	}
	id := namedot(tt.tags, t.decl.sym);
	if(id != nil && id.ty != nil){
		t.decl = id;
		return id.ty;
	}
	error(t.src.start, t.decl.sym.name+" is not a pick tag of "+typeconv(tt));
	return terror;
}

insttype(t: ref Type, adtt: ref Decl, tp: ref Tpair): (ref Type, ref Tpair)
{
	src := t.src;
	if(t.tof.kind != Tadt && t.tof.kind != Tadtpick){
		error(src.start, typeconv(t.tof) + " is not an adt");
		return (terror, nil);
	}
	if(t.tof.kind == Tadt)
		ids := t.tof.polys;
	else
		ids = t.tof.decl.dot.ty.polys;
	if(ids == nil){
		error(src.start, typeconv(t.tof) + " is not a polymorphic adt");
		return (terror, nil);
	}
	for(tyl := t.tlist; tyl != nil && ids != nil; tyl = tyl.nxt){
		tt := tyl.t;
		if(!tattr[tt.kind].isptr){
			error(src.start, typeconv(tt) + " is not a pointer type");
			return (terror, nil);
		}
		unifysrc = src;
		(ok, nil) := tunify(ids.ty, tt);
		if(!ok){
			error(src.start, "type " + typeconv(tt) + " does not match " + typeconv(ids.ty));
			return (terror, nil);
		}
		# usetype(tt);
		tt = verifytypes(tt, adtt, nil);
		tp = addtmap(ids.ty, tt, tp);
		ids = ids.next;
	}
	if(tyl != nil){
		error(src.start, "too many actual types in instantiation");
		return (terror, nil);
	}
	if(ids != nil){
		error(src.start, "too few actual types in instantiation");
		return (terror, nil);
	}
	tt := t.tof;
	(t, nil) = expandtype(tt, t, adtt, tp);
	if(t == tt && adtt == nil)
		t = duptype(t);
	if(t != tt)
		t.tmap = tp;
	t.src = src;
	return (t, tp);
}

#
# walk a type, putting all adts, modules, and tuples into equivalence classes
#
teqclass(t: ref Type)
{
	id: ref Decl;

	if(t == nil || (t.ok & OKclass) == OKclass)
		return;
	t.ok |= OKclass;
	case t.kind{
	Terror or
	Tint or
	Tbig or
	Tstring or
	Treal or
	Tbyte or
	Tnone or
	Tany or
	Tiface or
	Tainit or
	Talt or
	Tcase or
	Tcasel or
	Tcasec or
	Tgoto or
	Texcept or
	Tfix or
	Tpoly =>
		return;
	Tref =>
		teqclass(t.tof);
		return;
	Tchan or
	Tarray or
	Tlist =>
		teqclass(t.tof);
#ZZZ elim return to fix recursive chans, etc
		if(!debug['Z'])
			return;
	Tadt or
	Tadtpick or
	Ttuple or
	Texception =>
		for(id = t.ids; id != nil; id = id.next)
			teqclass(id.ty);
		for(tg := t.tags; tg != nil; tg = tg.next)
			teqclass(tg.ty);
		for(id = t.polys; id != nil; id = id.next)
			teqclass(id.ty);
	Tmodule =>
		t.tof = mkiface(t.decl);
		for(id = t.ids; id != nil; id = id.next)
			teqclass(id.ty);
	Tfn =>
		for(id = t.ids; id != nil; id = id.next)
			teqclass(id.ty);
		for(id = t.polys; id != nil; id = id.next)
			teqclass(id.ty);
		teqclass(t.tof);
		return;
	* =>
		fatal("teqclass: unknown type kind "+string t.kind);
	}

	#
	# find an equivalent type
	# stupid linear lookup could be made faster
	#
	if((t.ok & OKsized) != OKsized)
		fatal("eqclass type not sized: " + stypeconv(t));

	for(teq := eqclass[t.kind]; teq != nil; teq = teq.eq){
		if(t.size == teq.ty.size && tequal(t, teq.ty)){
			t.eq = teq;
			if(t.kind == Tmodule)
				joiniface(t, t.eq.ty.tof);
			return;
		}
	}

	#
	# if no equiv type, make one
	#
	eqclass[t.kind] = t.eq = ref Teq(0, t, eqclass[t.kind]);
}

#
# record that we've used the type
# using a type uses all types reachable from that type
#
reftype(t: ref Type)
{
	id: ref Decl;

	if(t == nil || (t.ok & OKref) == OKref)
		return;
	t.ok |= OKref;
	if(t.decl != nil && t.decl.refs == 0)
		t.decl.refs++;
	case t.kind{
	Terror or
	Tint or
	Tbig or
	Tstring or
	Treal or
	Tbyte or
	Tnone or
	Tany or
	Tiface or
	Tainit or
	Talt or
	Tcase or
	Tcasel or
	Tcasec or
	Tgoto or
	Texcept or
	Tfix or
	Tpoly =>
		break;
	Tref or
	Tchan or
	Tarray or
	Tlist =>
		if(t.decl != nil){
			if(nadts >= len adts){
				a := array[nadts + 32] of ref Decl;
				a[0:] = adts;
				adts = a;
			}
			adts[nadts++] = t.decl;
		}
		reftype(t.tof);
	Tadt or
	Tadtpick or
	Ttuple or
	Texception =>
		if(t.kind == Tadt || t.kind == Ttuple && t.decl.sym != anontupsym){
			if(nadts >= len adts){
				a := array[nadts + 32] of ref Decl;
				a[0:] = adts;
				adts = a;
			}
			adts[nadts++] = t.decl;
		}
		for(id = t.ids; id != nil; id = id.next)
			if(id.store != Dfn)
				reftype(id.ty);
		for(tg := t.tags; tg != nil; tg = tg.next)
			reftype(tg.ty);
		for(id = t.polys; id != nil; id = id.next)
			reftype(id.ty);
		if(t.kind == Tadtpick)
			reftype(t.decl.dot.ty);
	Tmodule =>
		#
		# a module's elements should get used individually
		# but do the globals for any sbl file
		#
		if(bsym != nil)
			for(id = t.ids; id != nil; id = id.next)
				if(id.store == Dglobal)
					reftype(id.ty);
		break;
	Tfn =>
		for(id = t.ids; id != nil; id = id.next)
			reftype(id.ty);
		for(id = t.polys; id != nil; id = id.next)
			reftype(id.ty);
		reftype(t.tof);
	* =>
		fatal("reftype: unknown type kind "+string t.kind);
	}
}

#
# check all reachable types for cycles and illegal forward references
# find the size of all the types
#
cycsizetype(t: ref Type)
{
	id: ref Decl;

	if(t == nil || (t.ok & (OKcycsize|OKcyc|OKsized)) == (OKcycsize|OKcyc|OKsized))
		return;
	t.ok |= OKcycsize;
	case t.kind{
	Terror or
	Tint or
	Tbig or
	Tstring or
	Treal or
	Tbyte or
	Tnone or
	Tany or
	Tiface or
	Tainit or
	Talt or
	Tcase or
	Tcasel or
	Tcasec or
	Tgoto or
	Texcept or
	Tfix or
	Tpoly =>
		t.ok |= OKcyc;
		sizetype(t);
	Tref or
	Tchan or
	Tarray or
	Tlist =>
		cyctype(t);
		sizetype(t);
		cycsizetype(t.tof);
	Tadt or
	Ttuple or
	Texception =>
		cyctype(t);
		sizetype(t);
		for(id = t.ids; id != nil; id = id.next)
			cycsizetype(id.ty);
		for(tg := t.tags; tg != nil; tg = tg.next){
			if((tg.ty.ok & (OKcycsize|OKcyc|OKsized)) == (OKcycsize|OKcyc|OKsized))
				continue;
			tg.ty.ok |= (OKcycsize|OKcyc|OKsized);
			for(id = tg.ty.ids; id != nil; id = id.next)
				cycsizetype(id.ty);
		}
		for(id = t.polys; id != nil; id = id.next)
			cycsizetype(id.ty);
	Tadtpick =>
		t.ok &= ~OKcycsize;
		cycsizetype(t.decl.dot.ty);
	Tmodule =>
		cyctype(t);
		sizetype(t);
		for(id = t.ids; id != nil; id = id.next)
			cycsizetype(id.ty);
		sizeids(t.ids, 0);
	Tfn =>
		cyctype(t);
		sizetype(t);
		for(id = t.ids; id != nil; id = id.next)
			cycsizetype(id.ty);
		for(id = t.polys; id != nil; id = id.next)
			cycsizetype(id.ty);
		cycsizetype(t.tof);
		sizeids(t.ids, MaxTemp);
#ZZZ need to align?
	* =>
		fatal("cycsizetype: unknown type kind "+string t.kind);
	}
}

# check for circularity in type declarations
# - has to be called before verifytypes
#
tcycle(t: ref Type)
{
	id: ref Decl;
	tt: ref Type;
	tll: ref Typelist;

	if(t == nil)
		return;
	case(t.kind){
	* =>
		;
	Tchan or
	Tarray or
	Tref or
	Tlist or
	Tdot =>
		tcycle(t.tof);
	Tfn or
	Ttuple =>
		tcycle(t.tof);
		for(id = t.ids; id != nil; id = id.next)
			tcycle(id.ty);
	Tarrow =>
		if(int(t.rec&TRvis)){
			error(t.src.start, "circularity in definition of " + typeconv(t));
			*t = *terror;	# break the cycle
			return;
		}
		tt = t.tof;
		t.rec |= TRvis;
		tcycle(tt);
		if(tt.kind == Tid)
			tt = tt.decl.ty;
		id = namedot(tt.ids, t.decl.sym);
		if(id != nil)
			tcycle(id.ty);
		t.rec &= ~TRvis;
	Tid =>
		if(int(t.rec&TRvis)){
			error(t.src.start, "circularity in definition of " + typeconv(t));
			*t = *terror;	# break the cycle
			return;
		}
		t.rec |= TRvis;
		tcycle(t.decl.ty);
		t.rec &= ~TRvis;
	Tinst =>
		tcycle(t.tof);
		for(tll = t.tlist; tll != nil; tll = tll.nxt)
			tcycle(tll.t);
	}
}

#
# marks for checking for arcs
#
	ArcValue,
	ArcList,
	ArcArray,
	ArcRef,
	ArcCyc,			# cycle found
	ArcPolycyc:
		con 1 << iota;

cyctype(t: ref Type)
{
	if((t.ok & OKcyc) == OKcyc)
		return;
	t.ok |= OKcyc;
	t.rec |= TRcyc;
	case t.kind{
	Terror or
	Tint or
	Tbig or
	Tstring or
	Treal or
	Tbyte or
	Tnone or
	Tany or
	Tfn or
	Tchan or
	Tarray or
	Tref or
	Tlist or
	Tfix or
	Tpoly =>
		break;
	Tadt or
	Tmodule or
	Ttuple or
	Texception =>
		for(id := t.ids; id != nil; id = id.next)
			cycfield(t, id);
		for(tg := t.tags; tg != nil; tg = tg.next){
			if((tg.ty.ok & OKcyc) == OKcyc)
				continue;
			tg.ty.ok |= OKcyc;
			for(id = tg.ty.ids; id != nil; id = id.next)
				cycfield(t, id);
		}
	* =>
		fatal("cyctype: unknown type kind "+string t.kind);
	}
	t.rec &= ~TRcyc;
}

cycfield(base: ref Type, id: ref Decl)
{
	if(!storespace[id.store])
		return;
	arc := cycarc(base, id.ty);

	if((arc & (ArcCyc|ArcValue)) == (ArcCyc|ArcValue)){
		if(id.cycerr == byte 0)
			error(base.src.start, "illegal type cycle without a reference in field "
				+id.sym.name+" of "+stypeconv(base));
		id.cycerr = byte 1;
	}else if(arc & ArcCyc){
		if((arc & ArcArray) && oldcycles && id.cyc == byte 0 && !(arc & ArcPolycyc)){
			if(id.cycerr == byte 0)
				error(base.src.start, "illegal circular reference to type "+typeconv(id.ty)
					+" in field "+id.sym.name+" of "+stypeconv(base));
			id.cycerr = byte 1;
		}
		id.cycle = byte 1;
	}else if(id.cyc != byte 0){
		if(id.cycerr == byte 0)
			error(id.src.start, "spurious cyclic qualifier for field "+id.sym.name+" of "+stypeconv(base));
		id.cycerr = byte 1;
	}
}

cycarc(base, t: ref Type): int
{
	if(t == nil)
		return 0;
	if((t.rec & TRcyc) == TRcyc){
		if(tequal(t, base)){
			if(t.kind == Tmodule)
				return ArcCyc | ArcRef;
			else
				return ArcCyc | ArcValue;
		}
		return 0;
	}
	t.rec |= TRcyc;
	me := 0;
	case t.kind{
	Terror or
	Tint or
	Tbig or
	Tstring or
	Treal or
	Tbyte or
	Tnone or
	Tany or
	Tchan or
	Tfn or
	Tfix or
	Tpoly =>
		break;
	Tarray =>
		me = cycarc(base, t.tof) & ~ArcValue | ArcArray;
	Tref =>
		me = cycarc(base, t.tof) & ~ArcValue | ArcRef;
	Tlist =>
		me = cycarc(base, t.tof) & ~ArcValue | ArcList;
	Tadt or
	Tadtpick or
	Tmodule or
	Ttuple or
	Texception =>
		me = 0;
		arc: int;
		for(id := t.ids; id != nil; id = id.next){
			if(!storespace[id.store])
				continue;
			arc = cycarc(base, id.ty);
			if((arc & ArcCyc) && id.cycerr == byte 0)
				me |= arc;
		}
		for(tg := t.tags; tg != nil; tg = tg.next){
			arc = cycarc(base, tg.ty);
			if((arc & ArcCyc) && tg.cycerr == byte 0)
				me |= arc;
		}

		if(t.kind == Tmodule)
			me = me & ArcCyc | ArcRef | ArcPolycyc;
		else
			me &= ArcCyc | ArcValue | ArcPolycyc;
	* =>
		fatal("cycarc: unknown type kind "+string t.kind);
	}
	t.rec &= ~TRcyc;
	if(int (t.flags&CYCLIC))
		me |= ArcPolycyc;
	return me;
}

#
# set the sizes and field offsets for t
# look only as deeply as needed to size this type.
# cycsize type will clean up the rest.
#
sizetype(t: ref Type)
{
	id: ref Decl;
	sz, al, s, a: int;

	if(t == nil)
		return;
	if((t.ok & OKsized) == OKsized)
		return;
	t.ok |= OKsized;
if((t.ok & (OKverify|OKsized)) != (OKverify|OKsized))
fatal("sizetype bogus ok for " + stypeconv(t));
	case t.kind{
	* =>
		fatal("sizetype: unknown type kind "+string t.kind);
	Terror or
	Tnone or
	Tbyte or
	Tint or
	Tbig or
	Tstring or
	Tany or
	Treal =>
		fatal(typeconv(t)+" should have a size");
	Tref or
	Tchan or
	Tarray or
	Tlist or
	Tmodule or
	Tfix or
	Tpoly =>
		t.size = t.align = IBY2WD;
	Tadt or
	Ttuple or
	Texception =>
		if(t.tags == nil){
#ZZZ
			if(!debug['z']){
				(sz, t.align) = sizeids(t.ids, 0);
				t.size = align(sz, t.align);
			}else{
				(sz, nil) = sizeids(t.ids, 0);
				t.align = IBY2LG;
				t.size = align(sz, IBY2LG);
			}
			return;
		}
#ZZZ
		if(!debug['z']){
			(sz, al) = sizeids(t.ids, IBY2WD);
			if(al < IBY2WD)
				al = IBY2WD;
		}else{
			(sz, nil) = sizeids(t.ids, IBY2WD);
			al = IBY2LG;
		}
		for(tg := t.tags; tg != nil; tg = tg.next){
			if((tg.ty.ok & OKsized) == OKsized)
				continue;
			tg.ty.ok |= OKsized;
#ZZZ
			if(!debug['z']){
				(s, a) = sizeids(tg.ty.ids, sz);
				if(a < al)
					a = al;
				tg.ty.size = align(s, a);
				tg.ty.align = a;
			}else{
				(s, nil) = sizeids(tg.ty.ids, sz);
				tg.ty.size = align(s, IBY2LG);
				tg.ty.align = IBY2LG;
			}			
		}
	Tfn =>
		t.size = 0;
		t.align = 1;
	Tainit =>
		t.size = 0;
		t.align = 1;
	Talt =>
		t.size = t.cse.nlab * 2*IBY2WD + 2*IBY2WD;
		t.align = IBY2WD;
	Tcase or
	Tcasec =>
		t.size = t.cse.nlab * 3*IBY2WD + 2*IBY2WD;
		t.align = IBY2WD;
	Tcasel =>
		t.size = t.cse.nlab * 6*IBY2WD + 3*IBY2WD;
		t.align = IBY2LG;
	Tgoto =>
		t.size = t.cse.nlab * IBY2WD + IBY2WD;
		if(t.cse.iwild != nil)
			t.size += IBY2WD;
		t.align = IBY2WD;
	Tiface =>
		sz = IBY2WD;
		for(id = t.ids; id != nil; id = id.next){
			sz = align(sz, IBY2WD) + IBY2WD;
			sz += len array of byte id.sym.name + 1;
			if(id.dot.ty.kind == Tadt)
				sz += len array of byte id.dot.sym.name + 1;
		}
		t.size = sz;
		t.align = IBY2WD;
	Texcept =>
		t.size = 0;
		t.align = IBY2WD;
	}
}

sizeids(id: ref Decl, off: int): (int, int)
{
	al := 1;
	for(; id != nil; id = id.next){
		if(storespace[id.store]){
			sizetype(id.ty);
			#
			# alignment can be 0 if we have
			# illegal forward declarations.
			# just patch a; other code will flag an error
			#
			a := id.ty.align;
			if(a == 0)
				a = 1;

			if(a > al)
				al = a;

			off = align(off, a);
			id.offset = off;
			off += id.ty.size;
		}
	}
	return (off, al);
}

align(off, align: int): int
{
	if(align == 0)
		fatal("align 0");
	while(off % align)
		off++;
	return off;
}

#
# recalculate a type's size
#
resizetype(t: ref Type)
{
	if((t.ok & OKsized) == OKsized){
		t.ok &= ~OKsized;
		cycsizetype(t);
	}
}

#
# check if a module is accessable from t
# if so, mark that module interface
#
modrefable(t: ref Type)
{
	id: ref Decl;

	if(t == nil || (t.ok & OKmodref) == OKmodref)
		return;
	if((t.ok & OKverify) != OKverify)
		fatal("modrefable unused type "+stypeconv(t));
	t.ok |= OKmodref;
	case t.kind{
	Terror or
	Tint or
	Tbig or
	Tstring or
	Treal or
	Tbyte or
	Tnone or
	Tany or
	Tfix or
	Tpoly =>
		break;
	Tchan or
	Tref or
	Tarray or
	Tlist =>
		modrefable(t.tof);
	Tmodule =>
		t.tof.linkall = byte 1;
		t.decl.refs++;
		for(id = t.ids; id != nil; id = id.next){
			case id.store{
			Dglobal or
			Dfn =>
				modrefable(id.ty);
			Dtype =>
				if(id.ty.kind != Tadt)
					break;
				for(m := id.ty.ids; m != nil; m = m.next)
					if(m.store == Dfn)
						modrefable(m.ty);
			}
		}
	Tfn or
	Tadt or
	Ttuple or
	Texception =>
		for(id = t.ids; id != nil; id = id.next)
			if(id.store != Dfn)
				modrefable(id.ty);
		for(tg := t.tags; tg != nil; tg = tg.next){
			# if((tg.ty.ok & OKmodref) == OKmodref)
			#	continue;
			tg.ty.ok |= OKmodref;
			for(id = tg.ty.ids; id != nil; id = id.next)
				modrefable(id.ty);
		}
		for(id = t.polys; id != nil; id = id.next)
			modrefable(id.ty);
		modrefable(t.tof);
	Tadtpick =>
		modrefable(t.decl.dot.ty);
	* =>
		fatal("modrefable: unknown type kind "+string t.kind);
	}
}

gendesc(d: ref Decl, size: int, decls: ref Decl): ref Desc
{
	if(debug['D'])
		print("generate desc for %s\n", dotconv(d));
	if(ispoly(d))
		addfnptrs(d, 0);
	desc := usedesc(mkdesc(size, decls));
	return desc;
}

mkdesc(size: int, d: ref Decl): ref Desc
{
	pmap := array[(size+8*IBY2WD-1) / (8*IBY2WD)] of { * => byte 0 };
	n := descmap(d, pmap, 0);
	if(n >= 0)
		n = n / (8*IBY2WD) + 1;
	else
		n = 0;
	return enterdesc(pmap, size, n);
}

mktdesc(t: ref Type): ref Desc
{
usedty(t);
	if(debug['D'])
		print("generate desc for %s\n", typeconv(t));
	if(t.decl == nil){
		t.decl = mkdecl(t.src, Dtype, t);
		t.decl.sym = enter("_mktdesc_", 0);
	}
	if(t.decl.desc != nil)
		return t.decl.desc;
	pmap := array[(t.size+8*IBY2WD-1) / (8*IBY2WD)] of {* => byte 0};
	n := tdescmap(t, pmap, 0);
	if(n >= 0)
		n = n / (8*IBY2WD) + 1;
	else
		n = 0;
	d := enterdesc(pmap, t.size, n);
	t.decl.desc = d;
	return d;
}

enterdesc(map: array of byte, size, nmap: int): ref Desc
{
	last : ref Desc = nil;
	for(d := descriptors; d != nil; d = d.next){
		if(d.size > size || d.size == size && d.nmap > nmap)
			break;
		if(d.size == size && d.nmap == nmap){
			c := mapcmp(d.map, map, nmap);
			if(c == 0)
				return d;
			if(c > 0)
				break;
		}
		last = d;
	}

	d = ref Desc(-1, 0, map, size, nmap, nil);
	if(last == nil){
		d.next = descriptors;
		descriptors = d;
	}else{
		d.next = last.next;
		last.next = d;
	}
	return d;
}

mapcmp(a, b: array of byte, n: int): int
{
	for(i := 0; i < n; i++)
		if(a[i] != b[i])
			return int a[i] - int b[i];
	return 0;
}

usedesc(d: ref Desc): ref Desc
{
	d.used = 1;
	return d;
}

#
# create the pointer description byte map for every type in decls
# each bit corresponds to a word, and is 1 if occupied by a pointer
# the high bit in the byte maps the first word
#
descmap(decls: ref Decl, map: array of byte, start: int): int
{
	if(debug['D'])
		print("descmap offset %d\n", start);
	last := -1;
	for(d := decls; d != nil; d = d.next){
		if(d.store == Dtype && d.ty.kind == Tmodule
		|| d.store == Dfn
		|| d.store == Dconst)
			continue;
		if(d.store == Dlocal && d.link != nil)
			continue;
		m := tdescmap(d.ty, map, d.offset + start);
		if(debug['D']){
			if(d.sym != nil)
				print("descmap %s type %s offset %d returns %d\n", d.sym.name, typeconv(d.ty), d.offset+start, m);
			else
				print("descmap type %s offset %d returns %d\n", typeconv(d.ty), d.offset+start, m);
		}
		if(m >= 0)
			last = m;
	}
	return last;
}

tdescmap(t: ref Type, map: array of byte, offset: int): int
{
	i, e, bit: int;

	if(t == nil)
		return -1;

	m := -1;
	if(t.kind == Talt){
		lab := t.cse.labs;
		e = t.cse.nlab;
		offset += IBY2WD * 2;
		for(i = 0; i < e; i++){
			if(lab[i].isptr){
				bit = offset / IBY2WD % 8;
				map[offset / (8*IBY2WD)] |= byte 1 << (7 - bit);
				m = offset;
			}
			offset += 2*IBY2WD;
		}
		return m;
	}
	if(t.kind == Tcasec){
		e = t.cse.nlab;
		offset += IBY2WD;
		for(i = 0; i < e; i++){
			bit = offset / IBY2WD % 8;
			map[offset / (8*IBY2WD)] |= byte 1 << (7 - bit);
			offset += IBY2WD;
			bit = offset / IBY2WD % 8;
			map[offset / (8*IBY2WD)] |= byte 1 << (7 - bit);
			m = offset;
			offset += 2*IBY2WD;
		}
		return m;
	}

	if(tattr[t.kind].isptr){
		bit = offset / IBY2WD % 8;
		map[offset / (8*IBY2WD)] |= byte 1 << (7 - bit);
		return offset;
	}
	if(t.kind == Tadtpick)
		t = t.tof;
	if(t.kind == Ttuple || t.kind == Tadt || t.kind == Texception){
		if(debug['D'])
			print("descmap adt offset %d\n", offset);
		if(t.rec != byte 0)
			fatal("illegal cyclic type "+stypeconv(t)+" in tdescmap");
		t.rec = byte 1;
		offset = descmap(t.ids, map, offset);
		t.rec = byte 0;
		return offset;
	}

	return -1;
}

tcomset: int;

#
# can a t2 be assigned to a t1?
# any means Tany matches all types,
# not just references
#
tcompat(t1, t2: ref Type, any: int): int
{
	if(t1 == t2)
		return 1;
	if(t1 == nil || t2 == nil)
		return 0;
	if(t2.kind == Texception && t1.kind != Texception)
		t2 = mkextuptype(t2);
	tcomset = 0;
	ok := rtcompat(t1, t2, any, 0);
	v := cleartcomrec(t1) + cleartcomrec(t2);
	if(v != tcomset)
		fatal("recid t1 "+stypeconv(t1)+" and t2 "+stypeconv(t2)+" not balanced in tcompat: "+string v+" "+string tcomset);
	return ok;
}

rtcompat(t1, t2: ref Type, any: int, inaorc: int): int
{
	if(t1 == t2)
		return 1;
	if(t1 == nil || t2 == nil)
		return 0;
	if(t1.kind == Terror || t2.kind == Terror)
		return 1;
	if(t2.kind == Texception && t1.kind != Texception)
		t2 = mkextuptype(t2);

	t1.rec |= TRcom;
	t2.rec |= TRcom;
	case t1.kind{
	* =>
		fatal("unknown type "+stypeconv(t1)+" v "+stypeconv(t2)+" in rtcompat");
		return 0;
	Tstring =>
		return t2.kind == Tstring || t2.kind == Tany;
	Texception =>
		if(t2.kind == Texception && t1.cons == t2.cons){
			if(assumetcom(t1, t2))
				return 1;
			return idcompat(t1.ids, t2.ids, 0, inaorc);
		}
		return 0;
	Tnone or
	Tint or
	Tbig or
	Tbyte or
	Treal =>
		return t1.kind == t2.kind;
	Tfix =>
		return t1.kind == t2.kind && sametree(t1.val, t2.val);
	Tany =>
		if(tattr[t2.kind].isptr)
			return 1;
		return any;
	Tref or
	Tlist or
	Tarray or
	Tchan =>
		if(t1.kind != t2.kind){
			if(t2.kind == Tany)
				return 1;
			return 0;
		}
		if(t1.kind != Tref && assumetcom(t1, t2))
			return 1;
		return rtcompat(t1.tof, t2.tof, 0, t1.kind == Tarray || t1.kind == Tchan || inaorc);
	Tfn =>
		break;
	Ttuple =>
		if(t2.kind == Tadt && t2.tags == nil
		|| t2.kind == Ttuple){
			if(assumetcom(t1, t2))
				return 1;
			return idcompat(t1.ids, t2.ids, any, inaorc);
		}
		if(t2.kind == Tadtpick){
			t2.tof.rec |= TRcom;
			if(assumetcom(t1, t2.tof))
				return 1;
			return idcompat(t1.ids, t2.tof.ids.next, any, inaorc);
		}
		return 0;
	Tadt =>
		if(t2.kind == Ttuple && t1.tags == nil){
			if(assumetcom(t1, t2))
				return 1;
			return idcompat(t1.ids, t2.ids, any, inaorc);
		}
		if(t1.tags != nil && t2.kind == Tadtpick && !inaorc)
			t2 = t2.decl.dot.ty;
	Tadtpick =>
		#if(t2.kind == Ttuple)
		#	return idcompat(t1.tof.ids.next, t2.ids, any, inaorc);
		break;
	Tmodule =>
		if(t2.kind == Tany)
			return 1;
	Tpoly =>
		if(t2.kind == Tany)
			return 1;
	}
	return tequal(t1, t2);
}

#
# add the assumption that t1 and t2 are compatable
#
assumetcom(t1, t2: ref Type): int
{
	r1, r2: ref Type;

	if(t1.tcom == nil && t2.tcom == nil){
		tcomset += 2;
		t1.tcom = t2.tcom = t1;
	}else{
		if(t1.tcom == nil){
			r1 = t1;
			t1 = t2;
			t2 = r1;
		}
		for(r1 = t1.tcom; r1 != r1.tcom; r1 = r1.tcom)
			;
		for(r2 = t2.tcom; r2 != nil && r2 != r2.tcom; r2 = r2.tcom)
			;
		if(r1 == r2)
			return 1;
		if(r2 == nil)
			tcomset++;
		t2.tcom = t1;
		for(; t2 != r1; t2 = r2){
			r2 = t2.tcom;
			t2.tcom = r1;
		}
	}
	return 0;
}

cleartcomrec(t: ref Type): int
{
	n := 0;
	for(; t != nil && (t.rec & TRcom) == TRcom; t = t.tof){
		t.rec &= ~TRcom;
		if(t.tcom != nil){
			t.tcom = nil;
			n++;
		}
		if(t.kind == Tadtpick)
			n += cleartcomrec(t.tof);
		if(t.kind == Tmodule)
			t = t.tof;
		for(id := t.ids; id != nil; id = id.next)
			n += cleartcomrec(id.ty);
		for(id = t.tags; id != nil; id = id.next)
			n += cleartcomrec(id.ty);
		for(id = t.polys; id != nil; id = id.next)
			n += cleartcomrec(id.ty);
	}
	return n;
}

#
# id1 and id2 are the fields in an adt or tuple
# simple structural check; ignore names
#
idcompat(id1, id2: ref Decl, any: int, inaorc: int): int
{
	for(; id1 != nil; id1 = id1.next){
		if(id1.store != Dfield)
			continue;
		while(id2 != nil && id2.store != Dfield)
			id2 = id2.next;
		if(id2 == nil
		|| id1.store != id2.store
		|| !rtcompat(id1.ty, id2.ty, any, inaorc))
			return 0;
		id2 = id2.next;
	}
	while(id2 != nil && id2.store != Dfield)
		id2 = id2.next;
	return id2 == nil;
}

#
# structural equality on types
# t->recid is used to detect cycles
# t->rec is used to clear t->recid
#
tequal(t1, t2: ref Type): int
{
	eqrec = 0;
	eqset = 0;
	ok := rtequal(t1, t2);
	v := cleareqrec(t1) + cleareqrec(t2);
	if(0 && v != eqset)
		fatal("recid t1 "+stypeconv(t1)+" and t2 "+stypeconv(t2)+" not balanced in tequal: "+string v+" "+string eqset);
	eqset = 0;
	return ok;
}

rtequal(t1, t2: ref Type): int
{
	#
	# this is just a shortcut
	#
	if(t1 == t2)
		return 1;

	if(t1 == nil || t2 == nil)
		return 0;
	if(t1.kind == Terror || t2.kind == Terror)
		return 1;

	if(t1.kind != t2.kind)
		return 0;

	if(t1.eq != nil && t2.eq != nil)
		return t1.eq == t2.eq;

	t1.rec |= TReq;
	t2.rec |= TReq;
	case t1.kind{
	* =>
		fatal("bogus type "+stypeconv(t1)+" vs "+stypeconv(t2)+" in rtequal");
		return 0;
	Tnone or
	Tbig or
	Tbyte or
	Treal or
	Tint or
	Tstring =>
		#
		# this should always be caught by t1 == t2 check
		#
		fatal("bogus value type "+stypeconv(t1)+" vs "+stypeconv(t2)+" in rtequal");
		return 1;
	Tfix =>
		return sametree(t1.val, t2.val);
	Tref or
	Tlist or
	Tarray or
	Tchan =>
		if(t1.kind != Tref && assumeteq(t1, t2))
			return 1;
		return rtequal(t1.tof, t2.tof);
	Tfn =>
		if(t1.varargs != t2.varargs)
			return 0;
		if(!idequal(t1.ids, t2.ids, 0, storespace))
			return 0;
		# if(!idequal(t1.polys, t2.polys, 1, nil))
		if(!pyequal(t1, t2))
			return 0;
		return rtequal(t1.tof, t2.tof);
	Ttuple or
	Texception =>
		if(t1.kind != t2.kind || t1.cons != t2.cons)
			return 0;
		if(assumeteq(t1, t2))
			return 1;
		return idequal(t1.ids, t2.ids, 0, storespace);
	Tadt or
	Tadtpick or
	Tmodule =>
		if(assumeteq(t1, t2))
			return 1;

		#
		# compare interfaces when comparing modules
		#
		if(t1.kind == Tmodule)
			return idequal(t1.tof.ids, t2.tof.ids, 1, nil);

		#
		# picked adts; check parent,
		# assuming equiv picked fields,
		# then check picked fields are equiv
		#
		if(t1.kind == Tadtpick && !rtequal(t1.decl.dot.ty, t2.decl.dot.ty))
			return 0;

		#
		# adts with pick tags: check picked fields for equality
		#
		if(!idequal(t1.tags, t2.tags, 1, nil))
			return 0;

		# if(!idequal(t1.polys, t2.polys, 1, nil))
		if(!pyequal(t1, t2))
			return 0;
		return idequal(t1.ids, t2.ids, 1, storespace);
	Tpoly =>
		if(assumeteq(t1, t2))
			return 1;
		if(t1.decl.sym != t2.decl.sym)
			return 0;
		return idequal(t1.ids, t2.ids, 1, nil);
	}
}

assumeteq(t1, t2: ref Type): int
{
	r1, r2: ref Type;

	if(t1.teq == nil && t2.teq == nil){
		eqrec++;
		eqset += 2;
		t1.teq = t2.teq = t1;
	}else{
		if(t1.teq == nil){
			r1 = t1;
			t1 = t2;
			t2 = r1;
		}
		for(r1 = t1.teq; r1 != r1.teq; r1 = r1.teq)
			;
		for(r2 = t2.teq; r2 != nil && r2 != r2.teq; r2 = r2.teq)
			;
		if(r1 == r2)
			return 1;
		if(r2 == nil)
			eqset++;
		t2.teq = t1;
		for(; t2 != r1; t2 = r2){
			r2 = t2.teq;
			t2.teq = r1;
		}
	}
	return 0;
}

#
# checking structural equality for modules, adts, tuples, and fns
#
idequal(id1, id2: ref Decl, usenames: int, storeok: array of int): int
{
	#
	# this is just a shortcut
	#
	if(id1 == id2)
		return 1;

	for(; id1 != nil; id1 = id1.next){
		if(storeok != nil && !storeok[id1.store])
			continue;
		while(id2 != nil && storeok != nil && !storeok[id2.store])
			id2 = id2.next;
		if(id2 == nil
		|| usenames && id1.sym != id2.sym
		|| id1.store != id2.store
		|| id1.implicit != id2.implicit
		|| id1.cyc != id2.cyc
		|| (id1.dot == nil) != (id2.dot == nil)
		|| id1.dot != nil && id2.dot != nil && id1.dot.ty.kind != id2.dot.ty.kind
		|| !rtequal(id1.ty, id2.ty))
			return 0;
		id2 = id2.next;
	}
	while(id2 != nil && storeok != nil && !storeok[id2.store])
		id2 = id2.next;
	return id1 == nil && id2 == nil;
}


pyequal(t1: ref Type, t2: ref Type): int
{
	pt1, pt2: ref Type;
	id1, id2: ref Decl;

	if(t1 == t2)
		return 1;
	id1 = t1.polys;
	id2 = t2.polys;
	for(; id1 != nil; id1 = id1.next){
		if(id2 == nil)
			return 0;
		pt1 = id1.ty;
		pt2 = id2.ty;
		if(!rtequal(pt1, pt2)){
			if(t1.tmap != nil)
				pt1 = valtmap(pt1, t1.tmap);
			if(t2.tmap != nil)
				pt2 = valtmap(pt2, t2.tmap);
			if(!rtequal(pt1, pt2))
				return 0;
		}
		id2 = id2.next;
	}
	return id1 == nil && id2 == nil;
}

cleareqrec(t: ref Type): int
{
	n := 0;
	for(; t != nil && (t.rec & TReq) == TReq; t = t.tof){
		t.rec &= ~TReq;
		if(t.teq != nil){
			t.teq = nil;
			n++;
		}
		if(t.kind == Tadtpick)
			n += cleareqrec(t.decl.dot.ty);
		if(t.kind == Tmodule)
			t = t.tof;
		for(id := t.ids; id != nil; id = id.next)
			n += cleareqrec(id.ty);
		for(id = t.tags; id != nil; id = id.next)
			n += cleareqrec(id.ty);
		for(id = t.polys; id != nil; id = id.next)
			n += cleareqrec(id.ty);
	}
	return n;
}

raisescompat(n1: ref Node, n2: ref Node): int
{
	if(n1 == n2)
		return 1;
	if(n2 == nil)
		return 1;	# no need to repeat in definition if given in declaration
	if(n1 == nil)
		return 0;
	for((n1, n2) = (n1.left, n2.left); n1 != nil && n2 != nil; (n1, n2) = (n1.right, n2.right)){
		if(n1.left.decl != n2.left.decl)
			return 0;
	}
	return n1 == n2;
}

# t1 a polymorphic type
fnunify(t1: ref Type, t2: ref Type, tp: ref Tpair, swapped: int): (int, ref Tpair)
{
	id, ids: ref Decl;
	sym: ref Sym;
	ok: int;

	for(ids = t1.ids; ids != nil; ids = ids.next){
		sym = ids.sym;
		(id, nil) = fnlookup(sym, t2);
		if(id != nil)
			usetype(id.ty);
		if(id == nil){
			if(dowarn)
				error(unifysrc.start, "type " + typeconv(t2) + " does not have a '" + sym.name + "' function");
			return (0, tp);
		}
		else if(id.ty.kind != Tfn){
			if(dowarn)
				error(unifysrc.start, typeconv(id.ty) + " is not a function");
			return (0, tp);
		}
		else{
			(ok, tp) = rtunify(ids.ty, id.ty, tp, !swapped);
			if(!ok){
				if(dowarn)
					error(unifysrc.start, typeconv(ids.ty) + " and " + typeconv(id.ty) + " are not compatible wrt " + sym.name);
				return (0, tp);
			}
		}
	}
	return (1, tp);
}

fncleareqrec(t1: ref Type, t2: ref Type): int
{
	id, ids: ref Decl;
	n: int;

	n = 0;
	n += cleareqrec(t1);
	n += cleareqrec(t2);
	for(ids = t1.ids; ids != nil; ids = ids.next){
		(id, nil) = fnlookup(ids.sym, t2);
		if(id == nil)
			continue;
		else{
			n += cleareqrec(ids.ty);
			n += cleareqrec(id.ty);
		}
	}
	return n;
}

tunify(t1: ref Type, t2: ref Type): (int, ref Tpair)
{
	v: int;
	p: ref Tpair;

	eqrec = 0;
	eqset = 0;
	(ok, tp) := rtunify(t1, t2, nil, 0);
	v = cleareqrec(t1) + cleareqrec(t2);
	for(p = tp; p != nil; p = p.nxt)
		v += fncleareqrec(p.t1, p.t2);
	if(0 && v != eqset)
		fatal("recid t1 " + stypeconv(t1) + " and t2 " + stypeconv(t2) + " not balanced in tunify: " + string v + " " + string eqset);
	return (ok, tp);
}

rtunify(t1: ref Type, t2: ref Type, tp: ref Tpair, swapped: int): (int, ref Tpair)
{
	ok: int;

	t1 = valtmap(t1, tp);
	t2 = valtmap(t2, tp);
	if(t1 == t2)
		return (1, tp);
	if(t1 == nil || t2 == nil)
		return (0, tp);
	if(t1.kind == Terror || t2.kind == Terror)
		return (1, tp);
	if(t1.kind != Tpoly && t2.kind == Tpoly){
		(t1, t2) = (t2, t1);
		swapped = !swapped;
	}
	if(t1.kind == Tpoly){
		# if(typein(t1, t2))
		# 	 return (0, tp);
		if(!tattr[t2.kind].isptr)
			return (0, tp);
		if(t2.kind != Tany)
			tp = addtmap(t1, t2, tp);
		return fnunify(t1, t2, tp, swapped);
	}
	if(t1.kind != Tany && t2.kind == Tany){
		(t1, t2) = (t2, t1);
		swapped = !swapped;
	}
	if(t1.kind == Tadt && t1.tags != nil && t2.kind == Tadtpick && !swapped)
		t2 = t2.decl.dot.ty;
	if(t2.kind == Tadt && t2.tags != nil && t1.kind == Tadtpick && swapped)
		t1 = t1.decl.dot.ty;
	if(t1.kind != Tany && t1.kind != t2.kind)
		return (0, tp);
	t1.rec |= TReq;
	t2.rec |= TReq;
	case(t1.kind){
	* =>
		return (tequal(t1, t2), tp);
	Tany =>
		return (tattr[t2.kind].isptr, tp);
	Tref or
	Tlist or
	Tarray or
	Tchan =>
		if(t1.kind != Tref && assumeteq(t1, t2))
			return (1, tp);
		return rtunify(t1.tof, t2.tof, tp, swapped);
	Tfn =>
		(ok, tp) = idunify(t1.ids, t2.ids, tp, swapped);
		if(!ok)
			return (0, tp);
		(ok, tp) = idunify(t1.polys, t2.polys, tp, swapped);
		if(!ok)
			return (0, tp);
		return rtunify(t1.tof, t2.tof, tp, swapped);
	Ttuple =>
		if(assumeteq(t1, t2))
			return (1, tp);
		return idunify(t1.ids, t2.ids, tp, swapped);
	Tadt or
	Tadtpick =>
		if(assumeteq(t1, t2))
			return (1, tp);
		(ok, tp) = idunify(t1.polys, t2.polys, tp, swapped);
		if(!ok)
			return (0, tp);
		(ok, tp) = idunify(t1.tags, t2.tags, tp, swapped);
		if(!ok)
			return (0, tp);
		return idunify(t1.ids, t2.ids, tp, swapped);
	Tmodule =>
		if(assumeteq(t1, t2))
			return (1, tp);
		return idunify(t1.tof.ids, t2.tof.ids, tp, swapped);
	Tpoly =>
		return (t1 == t2, tp);
	}
	return (1, tp);
}

idunify(id1: ref Decl, id2: ref Decl, tp: ref Tpair, swapped: int): (int, ref Tpair)
{
	ok: int;

	if(id1 == id2)
		return (1, tp);
	for(; id1 != nil; id1 = id1.next){
		if(id2 == nil)
			return (0, tp);
		(ok, tp) = rtunify(id1.ty, id2.ty, tp, swapped);
		if(!ok)
			return (0, tp);
		id2 = id2.next;
	}
	return (id1 == nil && id2 == nil, tp);
}

polyequal(id1: ref Decl, id2: ref Decl): int
{
	# allow id2 list to have an optional for clause
	ck2 := 0;
	for(d := id2; d != nil; d = d.next)
		if(d.ty.ids != nil)
			ck2 = 1;
	for(; id1 != nil; id1 = id1.next){
		if(id2 == nil
		|| id1.sym != id2.sym
		|| id1.ty.decl != nil && id2.ty.decl != nil && id1.ty.decl.sym != id2.ty.decl.sym)
			return 0;
		if(ck2 && !idequal(id1.ty.ids, id2.ty.ids, 1, nil))
			return 0;
		id2 = id2.next;
	}
	return id1 == nil && id2 == nil;
}

calltype(f: ref Type, a: ref Node, rt: ref Type): ref Type
{
	t: ref Type;
	id, first, last: ref Decl;

	first = last = nil;
	t = mktype(f.src.start, f.src.stop, Tfn, rt, nil);
	if(f.kind == Tref)
		t.polys = f.tof.polys;
	else
		t.polys = f.polys;
	for( ; a != nil; a = a.right){
		id = mkdecl(f.src, Darg, a.left.ty);
		if(last == nil)
			first = id;
		else
			last.next = id;
		last = id;
	}
	t.ids = first;
	if(f.kind == Tref)
		t = mktype(f.src.start, f.src.stop, Tref, t, nil);
	return t;
}

duptype(t: ref Type): ref Type
{
	nt: ref Type;

	nt = ref Type;
	*nt = *t;
	nt.ok &= ~(OKverify|OKref|OKclass|OKsized|OKcycsize|OKcyc);
	nt.flags |= INST;
	nt.eq = nil;
	nt.sbl = -1;
	if(t.decl != nil && (nt.kind == Tadt || nt.kind == Tadtpick || nt.kind == Ttuple)){
		nt.decl = dupdecl(t.decl);
		nt.decl.ty = nt;
		nt.decl.link = t.decl;
		if(t.decl.dot != nil){
			nt.decl.dot = dupdecl(t.decl.dot);
			nt.decl.dot.link = t.decl.dot;
		}
	}
	else
		nt.decl = nil;
	return nt;
}

dpolys(ids: ref Decl): int
{
	p: ref Decl;

	for(p = ids; p != nil; p = p.next)
		if(tpolys(p.ty))
			return 1;
	return 0;
}

tpolys(t: ref Type): int
{
	v: int;
	tyl: ref Typelist;

	if(t == nil)
		return 0;
	if(int(t.flags&(POLY|NOPOLY)))
		return int(t.flags&POLY);
	case(t.kind){
		* =>
			v = 0;
			break;
		Tarrow or
		Tdot or
		Tpoly =>
			v = 1;
			break;
		Tref or
		Tlist or
		Tarray or
		Tchan =>
			v = tpolys(t.tof);
			break;
		Tid =>
			v = tpolys(t.decl.ty);
			break;
		Tinst =>
			for(tyl = t.tlist; tyl != nil; tyl = tyl.nxt)
				if(tpolys(tyl.t)){
					v = 1;
					break;
				}
			v = tpolys(t.tof);
			break;
		Tfn or
		Tadt or
		Tadtpick or
		Ttuple or
		Texception =>
			if(t.polys != nil){
				v = 1;
				break;
			}
			if(int(t.rec&TRvis))
				return 0;
			t.rec |= TRvis;
			v = tpolys(t.tof) || dpolys(t.polys) || dpolys(t.ids) || dpolys(t.tags);
			t.rec &= ~TRvis;
			if(t.kind == Tadtpick && v == 0)
				v = tpolys(t.decl.dot.ty);
			break;
	}
	if(v)
		t.flags |= POLY;
	else
		t.flags |= NOPOLY;
	return v;
}

doccurs(ids: ref Decl, tp: ref Tpair): int
{
	p: ref Decl;

	for(p = ids; p != nil; p = p.next){
		if(toccurs(p.ty, tp))
			return 1;
	}
	return 0;
}

toccurs(t: ref Type, tp: ref Tpair): int
{
	o: int;

	if(t == nil)
		return 0;
	if(!int(t.flags&(POLY|NOPOLY)))
		tpolys(t);
	if(int(t.flags&NOPOLY))
		return 0;
	case(t.kind){
		* =>
			fatal("unknown type " + string t.kind + " in toccurs");
		Tnone or
		Tbig or
		Tbyte or
		Treal or
		Tint or
		Tstring or
		Tfix or
		Tmodule or
		Terror =>
			return 0;
		Tarrow or
		Tdot =>
			return 1;
		Tpoly =>
			return valtmap(t, tp) != t;
		Tref or
		Tlist or
		Tarray or
		Tchan =>
			return toccurs(t.tof, tp);
		Tid =>
			return toccurs(t.decl.ty, tp);
		Tinst =>
			for(tyl := t.tlist; tyl != nil; tyl = tyl.nxt)
				if(toccurs(tyl.t, tp))
					return 1;
			return toccurs(t.tof, tp);
		Tfn or
		Tadt or
		Tadtpick or
		Ttuple or
		Texception =>
			if(int(t.rec&TRvis))
				return 0;
			t.rec |= TRvis;
			o = toccurs(t.tof, tp) || doccurs(t.polys, tp) || doccurs(t.ids, tp) || doccurs(t.tags, tp);
			t.rec &= ~TRvis;
			if(t.kind == Tadtpick && o == 0)
				o = toccurs(t.decl.dot.ty, tp);
			return o;
	}
	return 0;
}

expandids(ids: ref Decl, adtt: ref Decl, tp: ref Tpair, sym: int): (ref Decl, ref Tpair)
{
	p, q, nids, last: ref Decl;

	nids = last = nil;
	for(p = ids; p != nil; p = p.next){
		q = dupdecl(p);
		(q.ty, tp) = expandtype(p.ty, nil, adtt, tp);
		if(sym && q.ty.decl != nil)
			q.sym = q.ty.decl.sym;
		if(q.store == Dfn)
			q.link = p;
		if(nids == nil)
			nids = q;
		else
			last.next = q;
		last = q;
	}
	return (nids, tp);
}

expandtype(t: ref Type, instt: ref Type, adtt: ref Decl, tp: ref Tpair): (ref Type, ref Tpair)
{
	nt: ref Type;

	if(t == nil)
		return (nil, tp);
	if(!toccurs(t, tp))
		return (t, tp);
	case(t.kind){
		* =>
			fatal("unknown type " + string t.kind + " in expandtype");
		Tpoly =>
			return (valtmap(t, tp), tp);
		Tref or
		Tlist or
		Tarray or
		Tchan =>
			nt = duptype(t);
			(nt.tof, tp) = expandtype(t.tof, nil, adtt, tp);
			return (nt, tp);
		Tid =>
			return expandtype(idtype(t), nil, adtt, tp);
		Tdot =>
			return expandtype(dottype(t, adtt), nil, adtt, tp);
		Tarrow =>
			return expandtype(arrowtype(t, adtt), nil, adtt, tp);
		Tinst =>
			if((nt = valtmap(t, tp)) != t)
				return (nt, tp);
			(t, tp) = insttype(t, adtt, tp);
			return expandtype(t, nil, adtt, tp);
		Tfn or
		Tadt or
		Tadtpick or
		Ttuple or
		Texception =>
			if((nt = valtmap(t, tp)) != t)
				return (nt, tp);
			if(t.kind == Tadt)
				adtt = t.decl;
			nt = duptype(t);
			tp = addtmap(t, nt, tp);
			if(instt != nil)
				tp = addtmap(instt, nt, tp);
			(nt.tof, tp) = expandtype(t.tof, nil, adtt, tp);
			(nt.polys, tp) = expandids(t.polys, adtt, tp, 1);
			(nt.ids, tp) = expandids(t.ids, adtt, tp, 0);
			(nt.tags, tp) = expandids(t.tags, adtt, tp, 0);
			if(t.kind == Tadt){
				for(ids := nt.tags; ids != nil; ids = ids.next)
					ids.ty.decl.dot = nt.decl;
			}
			if(t.kind == Tadtpick){
				(nt.decl.dot.ty, tp) = expandtype(t.decl.dot.ty, nil, adtt, tp);
			}
			if(t.tmap != nil){
				nt.tmap = nil;
				for(p := t.tmap; p != nil; p = p.nxt)
					nt.tmap = addtmap(valtmap(p.t1, tp), valtmap(p.t2, tp), nt.tmap);
			}
			return (nt, tp);
	}
	return (nil, tp);
}

#
# create type signatures
# sign the same information used
# for testing type equality
#
sign(d: ref Decl): int
{
	t := d.ty;
	if(t.sig != 0)
		return t.sig;

	if(ispoly(d))
		rmfnptrs(d);

	sigend := -1;
	sigalloc := 1024;
	sig: array of byte;
	while(sigend < 0 || sigend >= sigalloc){
		sigalloc *= 2;
		sig = array[sigalloc] of byte;
		eqrec = 0;
		sigend = rtsign(t, sig, 0);
		v := clearrec(t);
		if(v != eqrec)
			fatal("recid not balanced in sign: "+string v+" "+string eqrec);
		eqrec = 0;
	}

	if(signdump != "" && dotconv(d) == signdump){
		print("sign %s len %d\n", dotconv(d), sigend);
		print("%s\n", string sig[:sigend]);
	}

	md5sig := array[Crypt->MD5dlen] of {* => byte 0};
	md5(sig, sigend, md5sig, nil);

	for(i := 0; i < Crypt->MD5dlen; i += 4)
		t.sig ^= int md5sig[i+0] | (int md5sig[i+1]<<8) | (int md5sig[i+2]<<16) | (int md5sig[i+3]<<24);

	if(debug['S'])
		print("signed %s type %s len %d sig %#ux\n", dotconv(d), typeconv(t), sigend, t.sig);
	return t.sig;
}

SIGSELF:	con byte 'S';
SIGVARARGS:	con byte '*';
SIGCYC:		con byte 'y';
SIGREC:		con byte '@';

sigkind := array[Tend] of
{
	Tnone =>	byte 'n',
	Tadt =>		byte 'a',
	Tadtpick =>	byte 'p',
	Tarray =>	byte 'A',
	Tbig =>		byte 'B',
	Tbyte =>	byte 'b',
	Tchan =>	byte 'C',
	Treal =>	byte 'r',
	Tfn =>		byte 'f',
	Tint =>		byte 'i',
	Tlist =>	byte 'L',
	Tmodule =>	byte 'm',
	Tref =>		byte 'R',
	Tstring =>	byte 's',
	Ttuple =>	byte 't',
	Texception => byte 'e',
	Tfix => byte 'x',
	Tpoly => byte 'P',

	* => 		byte 0,
};

rtsign(t: ref Type, sig: array of byte, spos: int): int
{
	id: ref Decl;

	if(t == nil)
		return spos;

	if(spos < 0 || spos + 8 >= len sig)
		return -1;

	if(t.eq != nil && t.eq.id){
		if(t.eq.id < 0 || t.eq.id > eqrec)
			fatal("sign rec "+typeconv(t)+" "+string t.eq.id+" "+string eqrec);

		sig[spos++] = SIGREC;
		name := array of byte string t.eq.id;
		if(spos + len name > len sig)
			return -1;
		sig[spos:] = name;
		spos += len name;
		return spos;
	}
	if(t.eq != nil){
		eqrec++;
		t.eq.id = eqrec;
	}

	kind := sigkind[t.kind];
	sig[spos++] = kind;
	if(kind == byte 0)
		fatal("no sigkind for "+typeconv(t));

	t.rec = byte 1;
	case t.kind{
	* =>
		fatal("bogus type "+stypeconv(t)+" in rtsign");
		return -1;
	Tnone or
	Tbig or
	Tbyte or
	Treal or
	Tint or
	Tstring or
	Tpoly =>
		return spos;
	Tfix =>
		name := array of byte string t.val.c.rval;
		if(spos + len name - 1 >= len sig)
			return -1;
		sig[spos: ] = name;
		spos += len name;
		return spos;
	Tref or
	Tlist or
	Tarray or
	Tchan =>
		return rtsign(t.tof, sig, spos);
	Tfn =>
		if(t.varargs != byte 0)
			sig[spos++] = SIGVARARGS;
		if(t.polys != nil)
			spos = idsign(t.polys, 0, sig, spos);
		spos = idsign(t.ids, 0, sig, spos);
		if(t.eraises != nil)
			spos = raisessign(t.eraises, sig, spos);
		return rtsign(t.tof, sig, spos);
	Ttuple =>
		return idsign(t.ids, 0, sig, spos);
	Tadt =>
		#
		# this is a little different than in rtequal,
		# since we flatten the adt we used to represent the globals
		#
		if(t.eq == nil){
			if(t.decl.sym.name != ".mp")
				fatal("no t.eq field for "+typeconv(t));
			spos--;
			for(id = t.ids; id != nil; id = id.next){
				spos = idsign1(id, 1, sig, spos);
				if(spos < 0 || spos >= len sig)
					return -1;
				sig[spos++] = byte ';';
			}
			return spos;
		}
		if(t.polys != nil)
			spos = idsign(t.polys, 0, sig, spos);
		spos = idsign(t.ids, 1, sig, spos);
		if(spos < 0 || t.tags == nil)
			return spos;

		#
		# convert closing ')' to a ',', then sign any tags
		#
		sig[spos-1] = byte ',';
		for(tg := t.tags; tg != nil; tg = tg.next){
			name := array of byte (tg.sym.name + "=>");
			if(spos + len name > len sig)
				return -1;
			sig[spos:] = name;
			spos += len name;

			spos = rtsign(tg.ty, sig, spos);
			if(spos < 0 || spos >= len sig)
				return -1;

			if(tg.next != nil)
				sig[spos++] = byte ',';
		}
		if(spos >= len sig)
			return -1;
		sig[spos++] = byte ')';
		return spos;
	Tadtpick =>
		spos = idsign(t.ids, 1, sig, spos);
		if(spos < 0)
			return spos;
		return rtsign(t.decl.dot.ty, sig, spos);
	Tmodule =>
		if(t.tof.linkall == byte 0)
			fatal("signing a narrowed module");

		if(spos >= len sig)
			return -1;
		sig[spos++] = byte '{';
		for(id = t.tof.ids; id != nil; id = id.next){
			if(id.tag)
				continue;
			if(id.sym.name == ".mp"){
				spos = rtsign(id.ty, sig, spos);
				if(spos < 0)
					return -1;
				continue;
			}
			spos = idsign1(id, 1, sig, spos);
			if(spos < 0 || spos >= len sig)
				return -1;
			sig[spos++] = byte ';';
		}
		if(spos >= len sig)
			return -1;
		sig[spos++] = byte '}';
		return spos;
	}
}

idsign(id: ref Decl, usenames: int, sig: array of byte, spos: int): int
{
	if(spos >= len sig)
		return -1;
	sig[spos++] = byte '(';
	first := 1;
	for(; id != nil; id = id.next){
		if(id.store == Dlocal)
			fatal("local "+id.sym.name+" in idsign");

		if(!storespace[id.store])
			continue;

		if(!first){
			if(spos >= len sig)
				return -1;
			sig[spos++] = byte ',';
		}

		spos = idsign1(id, usenames, sig, spos);
		if(spos < 0)
			return -1;
		first = 0;
	}
	if(spos >= len sig)
		return -1;
	sig[spos++] = byte ')';
	return spos;
}

idsign1(id: ref Decl, usenames: int, sig: array of byte, spos: int): int
{
	if(usenames){
		name := array of byte (id.sym.name+":");
		if(spos + len name >= len sig)
			return -1;
		sig[spos:] = name;
		spos += len name;
	}

	if(spos + 2 >= len sig)
		return -1;

	if(id.implicit != byte 0)
		sig[spos++] = SIGSELF;

	if(id.cyc != byte 0)
		sig[spos++] = SIGCYC;

	return rtsign(id.ty, sig, spos);
}

raisessign(n: ref Node, sig: array of byte, spos: int): int
{
	if(spos >= len sig)
		return -1;
	sig[spos++] = byte '(';
	for(nn := n.left; nn != nil; nn = nn.right){
		s := array of byte nn.left.decl.sym.name;
		if(spos+len s - 1 >= len sig)
			return -1;
		sig[spos: ] = s;
		spos += len s;
		if(nn.right != nil){
			if(spos >= len sig)
				return -1;
			sig[spos++] = byte ',';
		}
	}
	if(spos >= len sig)
		return -1;
	sig[spos++] = byte ')';
	return spos;
}

clearrec(t: ref Type): int
{
	id: ref Decl;

	n := 0;
	for(; t != nil && t.rec != byte 0; t = t.tof){
		t.rec = byte 0;
		if(t.eq != nil && t.eq.id != 0){
			t.eq.id = 0;
			n++;
		}
		if(t.kind == Tmodule){
			for(id = t.tof.ids; id != nil; id = id.next)
				n += clearrec(id.ty);
			return n;
		}
		if(t.kind == Tadtpick)
			n += clearrec(t.decl.dot.ty);
		for(id = t.ids; id != nil; id = id.next)
			n += clearrec(id.ty);
		for(id = t.tags; id != nil; id = id.next)
			n += clearrec(id.ty);
		for(id = t.polys; id != nil; id = id.next)
			n += clearrec(id.ty);
	}
	return n;
}

# must a variable of the given type be zeroed ? (for uninitialized declarations inside loops)
tmustzero(t : ref Type) : int
{
	if(t==nil)
		return 0;
	if(tattr[t.kind].isptr)
		return 1;
	if(t.kind == Tadtpick)
		t = t.tof;
	if(t.kind == Ttuple || t.kind == Tadt)
		return mustzero(t.ids);
	return 0;
}

mustzero(decls : ref Decl) : int
{
	d : ref Decl;

	for (d = decls; d != nil; d = d.next)
		if (tmustzero(d.ty))
			return 1;
	return 0;
}

typeconv(t: ref Type): string
{
	if(t == nil)
		return "nothing";
	return tprint(t);
}

stypeconv(t: ref Type): string
{
	if(t == nil)
		return "nothing";
	return stprint(t);
}

tprint(t: ref Type): string
{
	id: ref Decl;

	if(t == nil)
		return "";
	s := "";
	if(t.kind < 0 || t.kind >= Tend){
		s += "kind ";
		s += string t.kind;
		return s;
	}
	if(t.pr != byte 0 && t.decl != nil){
		if(t.decl.dot != nil && !isimpmod(t.decl.dot.sym)){
			s += t.decl.dot.sym.name;
			s += "->";
		}
		s += t.decl.sym.name;
		return s;
	}
	t.pr = byte 1;
	case t.kind{
	Tarrow =>
		s += tprint(t.tof);
		s += "->";
		s += t.decl.sym.name;
	Tdot =>
		s += tprint(t.tof);
		s += ".";
		s += t.decl.sym.name;
	Tid or
	Tpoly =>
		s += t.decl.sym.name;
	Tinst =>
		s += tprint(t.tof);
		s += "[";
		for(tyl := t.tlist; tyl != nil; tyl = tyl.nxt){
			s += tprint(tyl.t);
			if(tyl.nxt != nil)
				s += ", ";
		}
		s += "]";
	Tint or
	Tbig or
	Tstring or
	Treal or
	Tbyte or
	Tany or
	Tnone or
	Terror or
	Tainit or
	Talt or
	Tcase or
	Tcasel or
	Tcasec or
	Tgoto or
	Tiface or
	Texception or
	Texcept =>
		s += kindname[t.kind];
	Tfix =>
		s += kindname[t.kind] + "(" + expconv(t.val) + ")";
	Tref =>
		s += "ref ";
		s += tprint(t.tof);
	Tchan or
	Tarray or
	Tlist =>
		s += kindname[t.kind];
		s += " of ";
		s += tprint(t.tof);
	Tadtpick =>
		s += t.decl.dot.sym.name + "." + t.decl.sym.name;
	Tadt =>
		if(t.decl.dot != nil && !isimpmod(t.decl.dot.sym))
			s += t.decl.dot.sym.name + "->";
		s += t.decl.sym.name;
		if(t.polys != nil){
			s += "[";
			for(id = t.polys; id != nil; id = id.next){
				if(t.tmap != nil)
					s += tprint(valtmap(id.ty, t.tmap));
				else
					s += id.sym.name;
				if(id.next != nil)
					s += ", ";
			}
			s += "]";
		}
	Tmodule =>
		s += t.decl.sym.name;
	Ttuple =>
		s += "(";
		for(id = t.ids; id != nil; id = id.next){
			s += tprint(id.ty);
			if(id.next != nil)
				s += ", ";
		}
		s += ")";
	Tfn =>
		s += "fn";
		if(t.polys != nil){
			s += "[";
			for(id = t.polys; id != nil; id = id.next){
				s += id.sym.name;
				if(id.next != nil)
					s += ", ";
			}
			s += "]";
		}
		s += "(";
		for(id = t.ids; id != nil; id = id.next){
			if(id.sym == nil)
				s += "nil: ";
			else{
				s += id.sym.name;
				s += ": ";
			}
			if(id.implicit != byte 0)
				s += "self ";
			s += tprint(id.ty);
			if(id.next != nil)
				s += ", ";
		}
		if(t.varargs != byte 0 && t.ids != nil)
			s += ", *";
		else if(t.varargs != byte 0)
			s += "*";
		if(t.tof != nil && t.tof.kind != Tnone){
			s += "): ";
			s += tprint(t.tof);
		}else
			s += ")";
	* =>
		yyerror("tprint: unknown type kind "+string t.kind);
	}
	t.pr = byte 0;
	return s;
}

stprint(t: ref Type): string
{
	if(t == nil)
		return "";
	s := "";
	case t.kind{
	Tid =>
		s += "id ";
		s += t.decl.sym.name;
	Tadt or
	Tadtpick or
	Tmodule =>
		return kindname[t.kind] + " " + tprint(t);
	}
	return tprint(t);
}

# generalize ref P.A, ref P.B to ref P

# tparent(t1: ref Type, t2: ref Type): ref Type
# {
# 	if(t1 == nil || t2 == nil || t1.kind != Tref || t2.kind != Tref)
# 		return t1;
# 	t1 = t1.tof;
# 	t2 = t2.tof;
# 	if(t1 == nil || t2 == nil || t1.kind != Tadtpick || t2.kind != Tadtpick)
# 		return t1;
# 	t1 = t1.decl.dot.ty;
# 	t2 = t2.decl.dot.ty;
# 	if(tequal(t1, t2))
# 		return mktype(t1.src.start, t1.src.stop, Tref, t1, nil);
# 	return t1;
# }

tparent0(t1: ref Type, t2: ref Type): int
{
	id1, id2: ref Decl;

	if(t1 == t2)
		return 1;
	if(t1 == nil || t2 == nil)
		return 0;
	if(t1.kind == Tadt && t2.kind == Tadtpick)
		t2 = t2.decl.dot.ty;
	if(t1.kind == Tadtpick && t2.kind == Tadt)
		t1 = t1.decl.dot.ty;
	if(t1.kind != t2.kind)
		return 0;
	case(t1.kind){
	* =>
		fatal("unknown type " + string t1.kind + " v " + string t2.kind + " in tparent");
		break;
	Terror or
	Tstring or
	Tnone or
	Tint or
	Tbig or
	Tbyte or
	Treal or
	Tany =>
		return 1;
	Texception or
	Tfix or
	Tfn or
	Tadt or
	Tmodule or
	Tpoly =>
		return tcompat(t1, t2, 0);
	Tref or
	Tlist or
	Tarray or
	Tchan =>
		return tparent0(t1.tof, t2.tof);
	Ttuple =>
		for((id1, id2) = (t1.ids, t2.ids); id1 != nil && id2 != nil; (id1, id2) = (id1.next, id2.next))
			if(!tparent0(id1.ty, id2.ty))
				return 0;
		return id1 == nil && id2 == nil;
	Tadtpick =>
		return tequal(t1.decl.dot.ty, t2.decl.dot.ty);
	}
	return 0;
}

tparent1(t1: ref Type, t2: ref Type): ref Type
{
	t, nt: ref Type;
	id, id1, id2, idt: ref Decl;

	if(t1.kind == Tadt && t2.kind == Tadtpick)
		t2 = t2.decl.dot.ty;
	if(t1.kind == Tadtpick && t2.kind == Tadt)
		t1 = t1.decl.dot.ty;
	case(t1.kind){
	* =>
		return t1;
	Tref or
	Tlist or
	Tarray or
	Tchan =>
		t = tparent1(t1.tof, t2.tof);
		if(t == t1.tof)
			return t1;
		return mktype(t1.src.start, t1.src.stop, t1.kind, t, nil);
	Ttuple =>
		nt = nil;
		id = nil;
		for((id1, id2) = (t1.ids, t2.ids); id1 != nil && id2 != nil; (id1, id2) = (id1.next, id2.next)){
			t = tparent1(id1.ty, id2.ty);
			if(t != id1.ty){
				if(nt == nil){
					nt = mktype(t1.src.start, t1.src.stop, Ttuple, nil, dupdecls(t1.ids));
					for((id, idt) = (nt.ids, t1.ids); idt != id1; (id, idt) = (id.next, idt.next))
						;
				}
				id.ty = t;
			}
			if(id != nil)
				id = id.next;
		}
		if(nt == nil)
			return t1;
		return nt;
	Tadtpick =>
		if(tequal(t1, t2))
			return t1;
		return t1.decl.dot.ty;
	}
	return t1;
}

tparent(t1: ref Type, t2: ref Type): ref Type
{
	if(tparent0(t1, t2))
		return tparent1(t1, t2);
	return t1;
}

#
# make the tuple type used to initialize an exception type
#
mkexbasetype(t: ref Type): ref Type
{
	if(t.cons == byte 0)
		fatal("mkexbasetype on non-constant");
	last := mkids(t.decl.src, nil, tstring, nil);
	last.store = Dfield;
	nt := mktype(t.src.start, t.src.stop, Texception, nil, last);
	nt.cons = byte 0;
	new := mkids(t.decl.src, nil, tint, nil);
	new.store = Dfield;
	last.next = new;
	last = new;
	for(id := t.ids; id != nil; id = id.next){
		new = ref *id;
		new.cyc = byte 0;
		last.next = new;
		last = new;
	}
	last.next = nil;
	return usetype(nt);
}

#
# make an instantiated exception type
#
mkextype(t: ref Type): ref Type
{
	nt: ref Type;

	if(t.cons == byte 0)
		fatal("mkextype on non-constant");
	if(t.tof != nil)
		return t.tof;
	nt = copytypeids(t);
	nt.cons = byte 0;
	t.tof = usetype(nt);
	return t.tof;
}

#
# convert an instantiated exception type to its underlying type
#
mkextuptype(t: ref Type): ref Type
{
	id: ref Decl;
	nt: ref Type;

	if(int t.cons)
		return t;
	if(t.tof != nil)
		return t.tof;
	id = t.ids;
	if(id == nil)
		nt = t;
	else if(id.next == nil)
		nt = id.ty;
	else{
		nt = copytypeids(t);
		nt.cons = byte 0;
		nt.kind = Ttuple;
	}
	t.tof = usetype(nt);
	return t.tof;
}

ckfix(t: ref Type, max: real)
{
	s := t.val.c.rval;
	if(max == 0.0)
		k := (big 1<<32) - big 1;
	else
		k = big 2 * big (max/s) + big 1;
	x := big 1;
	for(p := 0; k > x; p++)
		x *= big 2;
	if(p == 0 || p > 32){
		error(t.src.start, "cannot fit fixed type into an int");	
		return;
	}
	if(p < 32)
		t.val.c.rval /= real (1<<(32-p));
}

scale(t: ref Type): real
{
	n: ref Node;

	if(t.kind == Tint || t.kind == Treal)
		return 1.0;
	if(t.kind != Tfix)
		fatal("scale() on non fixed point type");
	n = t.val;
	if(n.op != Oconst)
		fatal("non constant scale");
	if(n.ty != treal)
		fatal("non real scale");
	return n.c.rval;
}

scale2(f: ref Type, t: ref Type): real
{
	return scale(f)/scale(t);
}

# put x in normal form
nf(x: real): (int, int)
{
	p: int;
	m: real;

	p = 0;
	m = x;
	while(m >= 1.0){
		p++;
		m /= 2.0;
	}
	while(m < 0.5){
		p--;
		m *= 2.0;
	}
	m *= real (1<<16)*real (1<<15);
	if(m >= real 16r7fffffff - 0.5)
		return (p, 16r7fffffff);
	return (p, int m);
}

ispow2(x: real): int
{
	m: int;

	(nil, m) = nf(x);
	if(m != 1<<30)
		return 0;
	return 1;
}

round(x: real, n: int): (int, int)
{
	if(n != 31)
		fatal("not 31 in round");
	return nf(x);
}

fixmul2(sx: real, sy: real, sr: real): (int, int, int)
{
	k, n, a: int;
	alpha: real;

	alpha = (sx*sy)/sr;
	n = 31;
	(k, a) = round(1.0/alpha, n);
	return (IMULX, 1-k, 0);
}

fixdiv2(sx: real, sy: real, sr: real): (int, int, int)
{
	k, n, b: int;
	beta: real;

	beta = sx/(sy*sr);
	n = 31;
	(k, b) = round(beta, n);
	return (IDIVX, k-1, 0);
}

fixmul(sx: real, sy: real, sr: real): (int, int, int)
{
	k, m, n, a, v: int;
	W: big;
	alpha, eps: real;

	alpha = (sx*sy)/sr;
	if(ispow2(alpha))
		return fixmul2(sx, sy, sr);
	n = 31;
	(k, a) = round(1.0/alpha, n);
	m = n-k;
	if(m < -n-1)
		return (IMOVW, 0, 0);	# result is zero whatever the values
	v = 0;
	W = big 0;
	eps = real(1<<m)/(alpha*real(a)) - 1.0;
	if(eps < 0.0){
		v = a-1;
		eps = -eps;
	}
	if(m < 0 && real(1<<n)*eps*real(a) >= real(a)-1.0+real(1<<m))
		W = (big(1)<<(-m)) - big 1;
	if(v != 0 || W != big 0)
		m = m<<2|(v != 0)<<1|(W != big 0);
	if(v == 0 && W == big 0)
		return (IMULX0, m, a);
	else
		return (IMULX1, m, a);
}

fixdiv(sx: real, sy: real, sr: real): (int, int, int)
{
	k, m, n, b, v: int;
	W: big;
	beta, eps: real;

	beta = sx/(sy*sr);
	if(ispow2(beta))
		return fixdiv2(sx, sy, sr);
	n = 31;
	(k, b) = round(beta, n);
	m = k-n;
	if(m <= -2*n)
		return (IMOVW, 0, 0);	#result is zero whatever the values
	v = 0;
	W = big 0;
	eps = (real(1<<m)*real(b))/beta - 1.0;
	if(eps < 0.0)
		v = 1;
	if(m < 0)
		W = (big(1)<<(-m)) - big 1;
	if(v != 0 || W != big 0)
		m = m<<2|(v != 0)<<1|(W != big 0);
	if(v == 0 && W == big 0)
		return (IDIVX0, m, b);
	else
		return (IDIVX1, m, b);
}

fixcast(sx: real, sr: real): (int, int, int)
{
	(op, p, a) := fixmul(sx, 1.0, sr);
	return (op-IMULX+ICVTXX, p, a);
}

fixop(op: int, tx: ref Type, ty: ref Type, tr: ref Type): (int, int, int)
{
	sx, sy, sr: real;

	sx = scale(tx);
	sy = scale(ty);
	sr = scale(tr);
	if(op == IMULX)
		return fixmul(sx, sy, sr);
	else if(op == IDIVX)
		return fixdiv(sx, sy, sr);
	else
		return fixcast(sx, sr);
}

ispoly(d: ref Decl): int
{
	if(d == nil)
		return 0;
	t := d.ty;
	if(t.kind == Tfn){
		if(t.polys != nil)
			return 1;
		if((d = d.dot) == nil)
			return 0;
		t = d.ty;
		return t.kind == Tadt && t.polys != nil;
	}
	return 0;
}

ispolyadt(t: ref Type): int
{
	return (t.kind == Tadt || t.kind == Tadtpick) && t.polys != nil && (t.flags & INST) == byte 0;
}

polydecl(ids: ref Decl): ref Decl
{
	id: ref Decl;
	t: ref Type;

	for(id = ids; id != nil; id = id.next){
		t = mktype(id.src.start, id.src.stop, Tpoly, nil, nil);
		id.ty = t;
		t.decl = id;
	}
	return ids;
}

# try to convert an expression tree to a type
exptotype(n: ref Node): ref Type
{
	t, tt: ref Type;
	d: ref Decl;
	tll: ref Typelist;
	src: Src;

	if(n == nil)
		return nil;
	t = nil;
	case(n.op){
		Oname =>
			if((d = n.decl) != nil && d.store == Dtype)
				t = d.ty;
		Otype or Ochan =>
			t = n.ty;
		Oref =>
			t = exptotype(n.left);
			if(t != nil)
				t = mktype(n.src.start, n.src.stop, Tref, t, nil);
		Odot =>
			t = exptotype(n.left);
			if(t != nil){
				d = namedot(t.tags, n.right.decl.sym);
				if(d == nil)
					t = nil;
				else
					t = d.ty;
			}
			if(t == nil)
				t = exptotype(n.right);
		Omdot =>
			t = exptotype(n.right);
		Oindex =>
			t = exptotype(n.left);
			if(t != nil){
				src = n.src;
				tll = nil;
				for(n = n.right; n != nil; n = n.right){
					if(n.op == Oseq)
						tt = exptotype(n.left);
					else
						tt = exptotype(n);
					if(tt == nil)
						return nil;
					tll = addtype(tt, tll);
					if(n.op != Oseq)
						break;
				}
				t = mkinsttype(src, t, tll);
			}
	}
	return t;
}

uname(im: ref Decl): string
{
	s := "";
	for(p := im; p != nil; p = p.next){
		s += p.sym.name;
		if(p.next != nil)
			s += "+";
	}
	return s;
}

# check all implementation modules have consistent declarations
# and create their union if needed
#
modimp(dl: ref Dlist, im: ref Decl): ref Decl
{
	u, d, dd, ids, dot, last: ref Decl;
	s: ref Sym;

	if(dl.next == nil)
		return dl.d;
	dl0 := dl;
	sg0 := 0;
	un := uname(im);
	installids(Dglobal, mkids(dl.d.src, enter(".m."+un, 0), tnone, nil));
	u = dupdecl(dl.d);
	u.sym = enter(un, 0);
	u.sym.decl = u;
	u.ty = mktype(u.src.start, u.src.stop, Tmodule, nil, nil);
	u.ty.decl = u;
	for( ; dl != nil; dl = dl.next){
		d = dl.d;
		ids = d.ty.tof.ids;	# iface
		if(ids != nil && ids.store == Dglobal)	# .mp
			sg := sign(ids);
		else
			sg = 0;
		if(dl == dl0)
			sg0 = sg;
		else if(sg != sg0)
			error(d.src.start, d.sym.name + "'s module data not consistent with that of " + dl0.d.sym.name + "\n");
		for(ids = d.ty.ids; ids != nil; ids = ids.next){
			s = ids.sym;
			if(s.decl != nil && s.decl.scope >= scope){
				if(ids == s.decl){
					dd = dupdecl(ids);
					if(u.ty.ids == nil)
						u.ty.ids = dd;
					else
						last.next = dd;
					last = dd;
					continue;
				}
				dot = s.decl.dot;
				if(s.decl.store != Dwundef && dot != nil && dot != d && isimpmod(dot.sym) && dequal(ids, s.decl, 1))
					ids.refs = s.decl.refs;
				else
					redecl(ids);
				ids.init = s.decl.init;
			}
		}
	}
	u.ty = usetype(u.ty);
	return u;
}

modres(d: ref Decl)
{
	ids, id, n, i: ref Decl;
	t: ref Type;

	for(ids = d.ty.ids; ids != nil; ids = ids.next){
		id = ids.sym.decl;
		if(ids != id){
			n = ids.next;
			i = ids.iface;
			t = ids.ty;
			*ids = *id;
			ids.next = n;
			ids.iface = i;
			ids.ty = t;
		}
	}
}

# update the fields of duplicate declarations in other implementation modules
# and their union
#	
modresolve()
{
	dl: ref Dlist;

	dl = impdecls;
	if(dl.next == nil)
		return;
	for( ; dl != nil; dl = dl.next)
		modres(dl.d);
	modres(impdecl);
}
