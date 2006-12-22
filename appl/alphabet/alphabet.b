implement Alphabet, Copy;
include "sys.m";
	sys: Sys;
include "draw.m";
include "readdir.m";
include "sh.m";
	sh: Sh;
	n_BLOCK, n_SEQ, n_LIST, n_ADJ, n_WORD, n_VAR, n_BQ2, n_PIPE: import Sh;
include "sets.m";
	sets: Sets;
	Set: import sets;
include "alphabet/reports.m";
	reports: Reports;
	Report: import reports;
	Modulecmd, Typescmd: import Proxy;
include "alphabet.m";
	evalmod: Eval;
	Context: import evalmod;

Mainsubtypes: module {
	proxy: fn(): chan of ref Proxy->Typescmd[ref Alphabet->Value];
};

# to do:
# - sort out concurrent access to alphabet.
# - if multiple options are given where only one is expected,
#	most modules ignore some values, where they should
#	discard them correctly. this could cause a malicious user
#	to hang up an alphabet expression (waiting for report to end)
# - proper implementation of endpointsrv:
#	- resilience to failures
#	- security of endpoints
#	- no need for write(0)... (or maybe there is)
# - proper implementation of rexecsrv:
#	- should be aware of user

Debug: con 0;
autodeclare := 0;

Module: adt {
	modname:	string;		# used when loading on demand.
	typeset:		ref Typeset;
	sig:			string;
	c:			chan of ref Modulecmd[ref Value];
	m:			Mainmodule;
	def:			ref Sh->Cmd;
	defmods:		ref Strhash[cyclic ref Module];
	refcount:		int;

	find:		fn(ctxt: ref Evalctxt, s: string): (ref Module, string);
	typesig:	fn(m: self ref Module): string;
	run:		fn(m: self ref Module, ctxt: ref Evalctxt,
					errorc: chan of string,
					opts: list of (int, list of ref Value),
					args: list of ref Value): ref Value;
	typename2c:	fn(s: string): int;
	mks:		fn(ctxt: ref Evalctxt, s: string): ref Value;
	mkc:		fn(ctxt: ref Evalctxt, c: ref Sh->Cmd): ref Value;
	ensureloaded:	fn(m: self ref Module): string;
	cvt:		fn(ctxt: ref Evalctxt, v: ref Value, tc: int, errorc: chan of string): ref Value;
};

Evalctxt: adt {
	modules:	ref Strhash[ref Module];
	drawctxt: ref Draw->Context;
	report: ref Report;
#	stopc: chan of int;
};

# used for rewriting expressions.
Rvalue: adt {
	i: ref Sh->Cmd;
	tc: int;
	refcount: int;
	opts: list of (int, list of ref Rvalue);
	args: list of ref Rvalue;

	dup:		fn(t: self ref Rvalue): ref Rvalue;
	free:		fn(v: self ref Rvalue, used: int);
	isstring:	fn(v: self ref Rvalue): int;
	gets:		fn(t: self ref Rvalue): string;
	type2s:	fn(tc: int): string;
	typec:	fn(t: self ref Rvalue): int;
};

Rmodule: adt {
	m: ref Module;

	cvt:		fn(ctxt: ref Revalctxt, v: ref Rvalue, tc: int, errorc: chan of string): ref Rvalue;
	find:		fn(nil: ref Revalctxt, s: string): (ref Rmodule, string);
	typesig:	fn(m: self ref Rmodule): string;
	run:		fn(m: self ref Rmodule, ctxt: ref Revalctxt, errorc: chan of string,
				opts: list of (int, list of ref Rvalue), args: list of ref Rvalue): ref Rvalue;
	mks:		fn(ctxt: ref Revalctxt, s: string): ref Rvalue;
	mkc:		fn(ctxt: ref Revalctxt, c: ref Sh->Cmd): ref Rvalue;
	typename2c:	fn(s: string): int;
};

Revalctxt: adt {
	modules: ref Strhash[ref Module];
	used: ref Strhash[ref Module];
	defs:	int;
	vals: list of ref Rvalue;
};

Renv: adt {
	items: list of ref Rvalue;
	n: int;
};

Typeset: adt {
	name: string;
	c: chan of ref Typescmd[ref Value];
	types: ref Table[cyclic ref Type];		# indexed by external type character
	parent: ref Typeset;

	gettype:	fn(ts: self ref Typeset, tc: int): ref Type;
};

Type: adt {
	id:	int;
	tc:	int;
	transform: list of ref Transform;
	typeset: ref Typeset;
	qname:	string;
	name:	string;
};

Transform: adt {
	dst: int;				# which type we're transforming into.
	all: Set;				# set of all types this transformation can lead to.
	expr: ref Sh->Cmd;		# transformation operation.
};

Table: adt[T] {
	items:	array of list of (int, T);
	nilval:	T;

	new: fn(nslots: int, nilval: T): ref Table[T];
	add:	fn(t: self ref Table, id: int, x: T): int;
	del:	fn(t: self ref Table, id: int): int;
	find:	fn(t: self ref Table, id: int): T;
};

Strhash: adt[T] {
	items:	array of list of (string, T);
	nilval:	T;

	new: fn(nslots: int, nilval: T): ref Strhash[T];
	add:	fn(t: self ref Strhash, id: string, x: T);
	del:	fn(t: self ref Strhash, id: string);
	find:	fn(t: self ref Strhash, id: string): T;
};

Copy: module {
	initcopy: fn(
		typesets: list of ref Typeset,
		roottypeset: ref Typeset,
		modules: ref Strhash[ref Module],
		typebyname: ref Strhash[ref Type],
		typebyc: ref Table[ref Type],
		types: array of ref Type,
		currtypec: int
	): Alphabet;
};

typesets: list of ref Typeset;
roottypeset: ref Typeset;
modules: ref Strhash[ref Module];
typebyname: ref Strhash[ref Type];
typebyc: ref Table[ref Type];	# indexed by internal type character.
types: array of ref Type;		# indexed by id.
currtypec := 16r25a0;		# pretty graphics.

checkload[T](m: T, path: string): T
{
	if(m != nil)
		return m;
	sys->fprint(sys->fildes(2), "alphabet: cannot load %s: %r\n", path);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	sh = load Sh Sh->PATH;
	sets = checkload(load Sets Sets->PATH, Sets->PATH);
	evalmod = checkload(load Eval Eval->PATH, Eval->PATH);
	evalmod->init();
	reports = checkload(load Reports Reports->PATH, Reports->PATH);

	roottypeset = ref Typeset("/", nil, Table[ref Type].new(5, nil), nil);
	typesets = roottypeset :: typesets;
	types = array[] of {
		ref Type(-1, 'c', nil, roottypeset, "/cmd", "cmd"),
		ref Type(-1, 's', nil, roottypeset, "/string", "string"),
		ref Type(-1, 'r', nil, roottypeset, "/status", "status"),
		ref Type(-1, 'f', nil, roottypeset, "/fd", "fd"),
		ref Type(-1, 'w', nil, roottypeset, "/wfd", "wfd"),
		ref Type(-1, 'd', nil, roottypeset, "/data", "data"),
	};
	typebyname = typebyname.new(11, nil);
	typebyc = typebyc.new(11, nil);
	for(i := 0; i < len types; i++){
		types[i].id = i;
		typebyc.add(types[i].tc, types[i]);
		typebyname.add(types[i].qname, types[i]);
		roottypeset.types.add(types[i].tc, types[i]);
	}
#	typebyc.add('a', ref Type(-1, 'a', nil, nil, "/any", "any"));		# not sure about this anymore
	modules = modules.new(3, nil);
}

initcopy(
		xtypesets: list of ref Typeset,
		xroottypeset: ref Typeset,
		xmodules: ref Strhash[ref Module],
		xtypebyname: ref Strhash[ref Type],
		xtypebyc: ref Table[ref Type],
		xtypes: array of ref Type,
		xcurrtypec: int): Alphabet
{
	# XXX must do copy-on-write, and refcounting on typesets.
	typesets = xtypesets;
	roottypeset = xroottypeset;
	modules = xmodules;
	typebyname = xtypebyname;
	typebyc = xtypebyc;
	types = xtypes;
	currtypec = xcurrtypec;
	return load Alphabet "$self";
}

copy(): Alphabet
{
	a := load Copy Alphabet->PATH;
	if(a == nil)
		return nil;
	return a->initcopy(typesets, roottypeset, modules, typebyname, typebyc, types, currtypec);
}

setautodeclare(x: int)
{
	autodeclare = x;
}

quit()
{
	for(ts := typesets; ts != nil; ts = tl ts)
		if((hd ts).c != nil)
			(hd ts).c <-= nil;
	delmods(modules);
}

delmods(mods: ref Strhash[ref Module])
{
	for(i := 0; i < len mods.items; i++){
		for(l := mods.items[i]; l != nil; l = tl l){
			m := (hd l).t1;
			if(--m.refcount == 0){
				if(m.c != nil){
					m.c <-= nil;
					m.c = nil;
				}else if(m.defmods != nil)
					delmods(m.defmods);
				else if(m.m != nil){
					m.m->quit();
					m.m = nil;
				}
			}
		}
	}
}

# XXX could do some more checking to see whether it looks vaguely like
# a valid alphabet expression.
parse(expr: string): (ref Sh->Cmd, string)
{
	return sh->parse(expr);
}

eval(expr: ref Sh->Cmd,
	drawctxt: ref Draw->Context,
	args: list of ref Value): string
{
	spawn reports->reportproc(reportc := chan of string, nil, reply := chan of ref Report);
	r := <-reply;
	reply = nil;
	stderr := sys->fildes(2);
	spawn eval0(expr, "/status", drawctxt, r, reports->r.start("eval"), args, vc := chan of ref Value);
	reports->r.enable();
	v: ref Value;
wait:
	for(;;)alt{
	v = <-vc =>
		if(v != nil)
			v.r().i <-= nil;
	msg := <-reportc =>
		if(msg == nil)
			break wait;
		sys->fprint(stderr, "alphabet: %s\n", msg);
	}
	# we'll always get the value before the report ends.
	if(v == nil)
		return "no value";
	return <-v.r().i;
}

eval0(expr: ref Sh->Cmd,
	dsttype: string,
	drawctxt: ref Draw->Context,
	r: ref Report,
	errorc: chan of string,
	args: list of ref Value,
	vc: chan of ref Value)
{
	c: Eval->Context[ref Value, ref Module, ref Evalctxt];
	ctxt := ref Evalctxt(modules, drawctxt, r);
	tc := -1;
	if(dsttype != nil && (tc = Module.typename2c(dsttype)) == -1){
		report(errorc, "error: unknown type "+dsttype);
		vc <-= nil;
		reports->quit(errorc);
	}

	v := c.eval(expr, ctxt, errorc, args);
	if(tc != -1)
		v = Module.cvt(ctxt, v, tc, errorc);
	vc <-= v;
	reports->quit(errorc);
}

define(name: string, expr: ref Sh->Cmd, errorc: chan of string): string
{
	if(name == nil || name[0] == '/')
		return "bad module name";
	m := modules.find(name);
	if(m != nil)
		return "module already declared";
	sig: string;
	used: ref Strhash[ref Module];
	used = used.new(11, nil);
	(expr, sig) = rewrite0(expr, -1, errorc, used);
	if(sig == nil)
		return "cannot rewrite";
	modules.add(name, ref Module(name, roottypeset, sig, nil, nil, expr, used, 1));
	return nil;
}

typecompat(t0, t1: string): (int, string)
{
	m: ref Module;
	(sig0, err) := evalmod->usage2sig(m, t0);
	if(err != nil)
		return (0, sys->sprint("bad usage %q: %s", t0, err));
	sig1: string;
	(sig1, err) = evalmod->usage2sig(m, t1);
	if(err != nil)
		return (0, sys->sprint("bad usage %q: %s", t1, err));
	return (evalmod->typecompat(sig0, sig1), nil);
}

rewrite(expr: ref Sh->Cmd, dsttype: string, errorc: chan of string): (ref Sh->Cmd, string)
{
	v: ref Value;
	tc := -1;
	if(dsttype != nil){
		tc = Module.typename2c(dsttype);
		if(tc == -1){
			report(errorc, "error: unknown type "+dsttype);
			return (nil, nil);
		}
	}
	sig: string;
	(expr, sig) = rewrite0(expr, tc, errorc, nil);
	if(sig == nil)
		return (nil, nil);

	return (expr, evalmod->cmdusage(v, sig));
}

# XXX different kinds of rewrite:
# could rewrite forcing all names to qualified
# or just leave names as they are.

# return (expr, sig).
# add all modules used by the expression to mods if non-nil.
rewrite0(expr: ref Sh->Cmd, tc: int, errorc: chan of string, used: ref Strhash[ref Module]): (ref Sh->Cmd, string)
{
	m: ref Rmodule;
	ctxt := ref Revalctxt(modules, used, 1, nil);
	(sig, err) := evalmod->blocksig(m, ctxt, expr);
	if(sig == nil){
		report(errorc, "error: cannot get expr type: "+err);
		return (nil, nil);
	}
	args: list of ref Rvalue;
	for(i := len sig - 1; i >= 1; i--)
		args = ref Rvalue(mk(-1, nil, nil), sig[i], 1, nil, nil) :: args;	# N.Vb. cmd node is never used.

	c: Eval->Context[ref Rvalue, ref Rmodule, ref Revalctxt];
	v := c.eval(expr, ctxt, errorc, args);
	if(v != nil && tc != -1)
		v = Rmodule.cvt(ctxt, v, tc, errorc);
	if(v == nil)
		return (nil, nil);
	sig[0] = v.tc;
	v.refcount++;
	expr = gen(v, ref Renv(nil, 0));
	if(len sig > 1){
		t := mkw(Value.type2s(sig[1]));
		for(i = 2; i < len sig; i++)
			t = mk(n_ADJ, t, mkw(Value.type2s(sig[i])));
		expr = mk(n_BLOCK, mk(n_SEQ, mk(n_LIST, t, nil), expr.left), nil);
	}
	return (expr, sig);
}

# generate the expression that gave rise to v.
# it puts in parentenv any values referred to externally.
gen(v: ref Rvalue, parentenv: ref Renv): ref Sh->Cmd
{
	v.refcount--;
	if(v.refcount > 0)
		return mk(n_VAR, mkw(string addenv(parentenv, v)), nil);
	c := v.i;
	(opts, args) := (v.opts, v.args);
	if(opts == nil && args == nil)
		return c;
	env := parentenv;
	if(genblock := needblock(v))
		env = ref Renv(nil, 0);
	for(; opts != nil; opts = tl opts){
		c = mk(n_ADJ, c, mkw(sys->sprint("-%c", (hd opts).t0)));
		for(a := (hd opts).t1; a != nil; a = tl a)
			c = mk(n_ADJ, c, gen(hd a, env));
	}
	if(args != nil && len (hd args).i.word > 1 && (hd args).i.word[0] == '-')
		c = mk(n_ADJ, c, mkw("--"));		# XXX potentially dodgy; some sigs don't interpret "--"?

	# use pipe notation when possible
	arg0: ref Sh->Cmd;
	if(args != nil){
		if((arg0 = gen(hd args, env)).ntype != n_BLOCK){
			c = mk(n_ADJ, c, arg0);
			arg0 = nil;
		}
		args = tl args;
	}
	for(; args != nil; args = tl args)
		c = mk(n_ADJ, c, gen(hd args, env));
	if(arg0 != nil)
		c = mk(n_PIPE, arg0.left, c);
	if(genblock){
		args = rev(env.items);
		m := mkw(Value.type2s((hd args).tc));
		for(a := tl args; a != nil; a = tl a)
			m = mk(n_ADJ, m, mkw(Value.type2s((hd a).tc)));
		c = mk(n_BLOCK, mk(n_SEQ, mk(n_LIST, m, nil), c), nil);
		return gen(ref Rvalue(c, v.tc, 1, nil, args), parentenv);
	}
	return mk(n_BLOCK, c, nil);
}

addenv(env: ref Renv, v: ref Rvalue): int
{
	for(i := env.items; i != nil; i = tl i)
		if(hd i == v)
			return len i;
	env.items = v :: env.items;
	v.refcount++;
	return ++env.n;
}

# need a new block if we have any duplicated values we can resolve locally.
# i.e. for a particular value, if we're the only thing pointing to that value
# and its refcount is > 1 to start with.
needblock(v: ref Rvalue): int
{
	dups := getdups(v, nil);
	for(d := dups; d != nil; d = tl d)
		--(hd d).refcount;
	r := 0;
	for(d = dups; d != nil; d = tl d)
		if((hd d).refcount++ == 0)
			r = 1;
	return r;
}

# find all values which need $ referencing (but don't go any deeper)
getdups(v: ref Rvalue, onto: list of ref Rvalue): list of ref Rvalue
{
	if(v.refcount > 1)
		return v :: onto;
	for(o := v.opts; o != nil; o = tl o)
		for(a := (hd o).t1; a != nil; a = tl a)
			onto = getdups(hd a, onto);
	for(a = v.args; a != nil; a = tl a)
		onto = getdups(hd a, onto);
	return onto;
}

loadtypeset(qname: string, c: chan of ref Typescmd[ref Value], errorc: chan of string): string
{
	tsname := canon(qname);
	if(gettypeset(tsname) != nil)
		return nil;
	(parent, name) := splitqname(tsname);
	if((pts := gettypeset(parent)) == nil)
		return "parent typeset not found";

	if(pts.c != nil){
		if(c != nil)
			return "typecmd channel may only be provided for top-level typesets";
		reply := chan of (chan of ref Typescmd[ref Value], string);
		pts.c <-= ref Typescmd[ref Value].Loadtypes(name, reply);
		err: string;
		(c, err) = <-reply;
		if(c == nil)
			return err;
	}else if(c == nil){
		tsmod := load Mainsubtypes "/dis/alphabet/"+name+"types.dis";
		if(tsmod == nil)
			return sys->sprint("cannot load %q: %r", name+"types.dis");
		c = tsmod->proxy();
	}

	reply := chan of string;
	c <-= ref Typescmd[ref Value].Alphabet(reply);
	a := <-reply;
	ts := ref Typeset(tsname, c, Table[ref Type].new(7, nil), pts);
	typesets = ts :: typesets;
	newtypes: list of ref Type;
	for(i := 0; i < len a; i++){
		tc := a[i];
		if((t := ts.parent.gettype(tc)) == nil){
			t = ref Type(-1, -1, nil, ts, nil, nil);
			sreply := chan of string;
			c <-= ref Typescmd[ref Value].Type2s(tc, sreply);
			t.name = <-sreply;
			# XXX check that type name is syntactically valid.
			t.qname = mkqname(tsname, t.name);
			if(typebyname.find(t.qname) != nil)
				report(errorc, sys->sprint("warning: oops: typename clash on %q", t.qname));
			else
				typebyname.add(t.qname, t);
			newtypes = t :: newtypes;
		}
		ts.types.add(tc, t);
	}
	id := len types;
	types = (array[len types + len newtypes] of ref Type)[0:] = types;
	for(; newtypes != nil; newtypes = tl newtypes){
		types[id] = hd newtypes;
		typebyc.add(currtypec, hd newtypes);
		types[id].tc = currtypec++;
		types[id].id = id;
		id++;
	}
	return nil;
}

autoconvert(src, dst: string, expr: ref Sh->Cmd, errorc: chan of string): string
{
	tdst := typebyname.find(dst);
	if(tdst == nil)
		return "unknown type " + dst;
	tsrc := typebyname.find(src);
	if(tsrc == nil)
		return "unknown type " + src;
	if(tdst.typeset != tsrc.typeset && tdst.typeset != roottypeset && tsrc.typeset != roottypeset)
		return "conversion between incompatible typesets";
	if(expr != nil && expr.ntype == n_WORD){
		# mod -> {(srctype); mod $1}
		expr = mk(n_BLOCK,
			mk(n_SEQ,
				mk(n_LIST, mkw(src), nil),
				mk(n_ADJ,
					mkw(expr.word),
					mk(n_VAR, mkw("1"), nil)
				)
			),
			nil
		);
	}
				
	(e, sig) := rewrite0(expr, tdst.tc, errorc, nil);
	if(sig == nil)
		return "cannot rewrite transformation "+sh->cmd2string(expr);
	if(!evalmod->typecompat(sys->sprint("%c%c", tdst.tc, tsrc.tc), sig))
		return "incompatible module type";
	err := addconversion(tsrc, tdst, e);
	if(err != nil)
		return sys->sprint("bad auto-conversion %s->%s via %s: %s",
					tsrc.qname, tdst.qname, sh->cmd2string(expr), err);
	return nil;
}

mk(ntype: int, left, right: ref Sh->Cmd): ref Sh->Cmd
{
	return ref Sh->Cmd(ntype, left, right, nil, nil);
}
mkw(w: string): ref Sh->Cmd
{
	return ref Sh->Cmd(n_WORD, nil, nil, w, nil);
}

declare(qname: string, usig: string, flags: int): string
{
	return declare0(qname, usig, flags).t1;
}

# declare a module.
# if (flags&ONDEMAND), then we don't need to actually load
# the module (although we do if (flags&CHECK) or if sig==nil,
# in order to check or find out the type signature)
declare0(qname: string, usig: string, flags: int): (ref Module, string)
{
	sig, err: string;
	m: ref Module;
	if(usig != nil){
		(sig, err) = evalmod->usage2sig(m, usig);
		if(sig == nil)
			return (nil, "bad type sig: " + err);
	}
	# if not a qualified name, declare it virtually
	if(qname != nil && qname[0] != '/'){
		if(sig == nil)
			return (nil, "virtual module declaration must include signature");
		m = ref Module(qname, nil, sig, nil, nil, nil, nil, 0);
	}else{
		qname = canon(qname);
		(typeset, mod) := splitqname(qname);
		if((ts := gettypeset(typeset)) == nil)
			return (nil, "unknown typeset");
		if((m = modules.find(qname)) != nil){
			if(m.typeset == ts)
				return (m, nil);
			return (nil, "already imported");
		}
		m = ref Module(mod, ts, sig, nil, nil, nil, nil, 0);
		if(sig == nil || (flags&CHECK) || (flags&ONDEMAND)==0){
			if((e := m.ensureloaded()) != nil)
				return (nil, e);
			if(flags&ONDEMAND){
				if(m.c != nil){
					m.c <-= nil;
					m.c = nil;
				}
				m.m = nil;
			}
		}
	}

	modules.add(qname, m);
	m.refcount++;
	return (m, nil);
}

undeclare(name: string): string
{
	m := modules.find(name);
	if(m == nil)
		return "module not declared";
	modules.del(name);
	if(--m.refcount == 0){
		if(m.c != nil){
			m.c <-= nil;
			m.c = nil;
		}else if(m.defmods != nil){
			delmods(m.defmods);
		}
	}
	return nil;
}

# get info on a module.
# return (qname, usage, def)
getmodule(name: string): (string, string, ref Sh->Cmd)
{
	(qname, sig, def) := getmodule0(name);
	if(sig == nil)
		return (qname, sig, def);
	v: ref Value;
	return (qname, evalmod->cmdusage(v, sig), def);
}

getmodule0(name: string): (string, string, ref Sh->Cmd)
{
	m: ref Module;
	if(name != nil && name[0] != '/'){
		if((m = modules.find(name)) == nil)
			return (nil, nil, nil);
		# XXX could add path searching here.
	}else{
		name = canon(name);
		(typeset, mod) := splitqname(name);
		if((m = modules.find(name)) == nil){
			if(autodeclare == 0)
				return (nil, nil, nil);
			ts := gettypeset(typeset);
			if(ts == nil)
				return (nil, nil, nil);
			m = ref Module(mod, ts, nil, nil, nil, nil, nil, 0);
			if((e := m.ensureloaded()) != nil)
				return (nil, nil, nil);
			if(m.c != nil)
				m.c <-= nil;
		}
	}

	qname := m.modname;
	if(m.def == nil && m.typeset != nil)
		qname = mkqname(m.typeset.name, qname);
	return (qname, m.sig, m.def);
}

getmodules(): list of string
{
	r: list of string;
	for(i := 0; i < len modules.items; i++)
		for(ml := modules.items[i]; ml != nil; ml = tl ml)
			r = (hd ml).t0 :: r;
	return r;
}

#Cmpdeclts: adt {
#	gt: fn(nil: self ref Cmpdeclts, d1, d2: ref Decltypeset): int
#};
#Cmpdeclts.gt(nil: self ref Cmpdeclts, d1, d2: ref Decltypeset)
#{
#	return d1.name > d2.name;
#}
#Cmpstring: adt {
#	gt: fn(nil: self ref Cmpdeclts, d1, d2: string): int
#};
#Cmpstring.gt(nil: self ref Cmpstring, d1, d2: string): int
#{
#	return d1 > d2;
#}
#Cmptype: adt {
#	gt: fn(nil: self ref Cmptype, d1, d2: ref Type): int
#};
#Cmptype.gt(nil: self ref Cmptype, d1, d2: ref Type): int
#{
#	return d1.name > d2.name;
#}
#
#getdecls(): ref Declarations
#{
#	cmptype: ref Cmptype;
#	d := ref Declarations(array[len typesets] of ref Decltypeset);
#	i := 0;
#	ta := array[len types] of ref Type;
#	for(tsl := typesets; tsl != nil; tsl = tl tsl){
#		t := hd tsl;
#		ts := ref Decltypeset;
#		ts.name = t.name;
#
#		# all types in the typeset, in alphabetical order.
#		j := 0;
#		for(k := 0; k < len t.types.items; k++)
#			for(tt := t.types.items[k]; tt != nil; tt = tl tt)
#				ta[j++] = hd tt;
#		sort(cmptype, ta[0:j]);
#		ts.types = array[j] of string;
#		for(k = 0; k < j; k++){
#			ts.types[k] = ta[k].name;
#			ts.alphabet[k] = ta[k].tc;
#		}
#
#		# all modules in the typeset
#		c := gettypesetmodules(ts.name);
#		while((m := <-c) != nil){
#			
#
#	d.types = array[len types] of string;
#	for(i := 0; i < len types; i++){
#		d.alphabet[i] = types[i].tc;
#		d.types[i] = types[i].qname;
#	}
#	

gettypesetmodules(tsname: string): chan of string
{
	ts := gettypeset(tsname);
	if(ts == nil)
		return nil;
	r := chan of string;
	if(ts.c == nil)
		spawn mainmodules(r);
	else
		ts.c <-= ref Typescmd[ref Value].Modules(r);
	return r;
}

mainmodules(r: chan of string)
{
	if((readdir := load Readdir Readdir->PATH) != nil){
		(a, nil) := readdir->init("/dis/alphabet/main", Readdir->NAME|Readdir->COMPACT);
		for(i := 0; i < len a; i++){
			m := a[i].name;
			if((a[i].mode & Sys->DMDIR) == 0 && len m > 4 && m[len m - 4:] == ".dis")
				r <-= m[0:len m - 4];
		}
	}
	r <-= nil;
}

gettypes(ts: string): list of string
{
	r: list of string;
	for(i := 0; i < len types; i++){
		if(ts == nil)
			r = Value.type2s(types[i].tc) :: r;
		else if (types[i].typeset.name == ts)
			r = types[i].name :: r;
	}
	return r;
}

gettypesets(): list of string
{
	r: list of string;
	for(t := typesets; t != nil; t = tl t)
		r = (hd t).name :: r;
	return r;
}

getautoconversions(): list of (string, string, ref Sh->Cmd)
{
	cl: list of (string, string, ref Sh->Cmd);
	for(i := 0; i < len types; i++){
		if(types[i] == nil)
			continue;
		srct := Value.type2s(types[i].tc);
		for(l := types[i].transform; l != nil; l = tl l)
			cl = (srct, Value.type2s(types[(hd l).dst].tc), (hd l).expr) :: cl;
	}
	return cl;
}

importmodule(qname: string): string
{
	qname = canon(qname);
	(typeset, mod) := splitqname(qname);
	if(typeset == nil)
		return "unknown typeset";
	if((m := modules.find(mod)) != nil){
		if(m.typeset == nil)
			return "already defined";
		if(m.typeset.name == typeset)
			return nil;
		return "already imported from "+m.typeset.name;
	}
	if((m = modules.find(qname)) == nil){
		if(autodeclare == 0)
			return "module not declared";
		err: string;
		(m, err) = Module.find(nil, qname);
		if(m == nil)
			return "cannot import: "+ err;
		modules.add(qname, m);
		m.refcount++;
	}
	modules.add(mod, m);
	return nil;
}


gettypeset(name: string): ref Typeset
{
	name = canon(name);
	for(l := typesets; l != nil; l = tl l)
		if((hd l).name == name)
			break;
	if(l == nil)
		return nil;
	return hd l;
}

importtype(qname: string): string
{
	qname = canon(qname);
	(typeset, tname) := splitqname(qname);
	if((ts := gettypeset(typeset)) == nil)
		return "unknown typeset";
	t := typebyname.find(tname);
	if(t != nil){
		if(t.typeset == ts)
			return nil;
		return "type already imported from " + t.typeset.name;
	}
	t = typebyname.find(qname);
	if(t == nil)
		return sys->sprint("%s does not hold type %s", typeset, tname);
	typebyname.add(tname, t);
	return nil;
}

importvalue(v: ref Value, tname: string): (ref Value, string)
{
	if(v == nil || tagof v != tagof Value.Vz)
		return (v, nil);
	if(tname == nil || tname[0] == '/')
		tname = canon(tname);
	t := typebyname.find(tname);
	if(t == nil)
		return (nil, "no such type");
	pick xv := v {
	Vz =>
		if(t.typeset.types.find(xv.i.typec) != t)
			return (nil, "value appears to be of different type");
		xv.i.typec = t.tc;
	}
	return (v, nil);
}

gettype(tc: int): ref Type
{
	return typebyc.find(tc);
}

Typeset.gettype(ts: self ref Typeset, tc: int): ref Type
{
	return ts.types.find(tc);
}

Module.find(ctxt: ref Evalctxt, name: string): (ref Module, string)
{
	mods := modules;
	if(ctxt != nil)
		mods = ctxt.modules;
	m := mods.find(name);
	if(m == nil){
		if(autodeclare == 0 || name == nil || name[0] != '/')
			return (nil, "module not declared");
		err: string;
		(m, err) = declare0(name, nil, 0);
		if(m == nil)
			return (nil, err);
	}else if((err := m.ensureloaded()) != nil)
		return (nil, err);
	return (m, nil);
}

Module.ensureloaded(m: self ref Module): string
{
	if(m.c != nil || m.m != nil || m.def != nil || m.typeset == nil)
		return nil;

	sig: string;
	if(m.typeset.c == nil){
		p := "/dis/alphabet/main/" + m.modname + ".dis";
		mod := load Mainmodule p;
		if(mod == nil)
			return sys->sprint("cannot load %q: %r", p);
		{
			mod->init();
		} exception e {
		"fail:*" =>
			return sys->sprint("init %q failed: %s", m.modname, e[5:]);
		}
		m.m = mod;
		sig = mod->typesig();
	}else{
		reply := chan of (chan of ref Modulecmd[ref Value], string);
		m.typeset.c <-= ref Typescmd[ref Value].Load(m.modname, reply);
		(mc, err) := <-reply;
		if(mc == nil)
			return sys->sprint("cannot load: %s", err);
		m.c = mc;
		sig = gettypesig(m);
	}
	if(m.sig == nil)
		m.sig = sig;
	else if(!evalmod->typecompat(m.sig, sig)){
		v: ref Value;
		if(m.c != nil){
			m.c <-= nil;
			m.c = nil;
		}
		m.m = nil;
		return sys->sprint("%q not compatible with %q (%q vs %q, %d)",
			m.modname+" "+evalmod->cmdusage(v, sig),
			evalmod->cmdusage(v, m.sig), m.sig, sig, m.sig==sig);
	}
	return nil;
}

Module.typesig(m: self ref Module): string
{
	return m.sig;
}

# get the type signature of a module in its native typeset.
# it's not valid to call this on defined or virtually declared modules.
gettypesig(m: ref Module): string
{
	reply := chan of string;
	m.c <-= ref Modulecmd[ref Value].Typesig(reply);
	sig := <-reply;
	origsig := sig;
	for(i := 0; i < len sig; i++){
		tc := sig[i];
		if(tc == '-'){
			i++;
			continue;
		}
		if(tc != '*'){
			t := m.typeset.gettype(sig[i]);
			if(t == nil){
sys->print("no type found for '%c' in sig %q\n", sig[i], origsig);
				return nil;		# XXX is it alright to break here?
			}
			sig[i] = t.tc;
		}
	}
	return sig;
}

Module.run(m: self ref Module, ctxt: ref Evalctxt, errorc: chan of string, opts: list of (int, list of ref Value), args: list of ref Value): ref Value
{
	if(m.c != nil){
		reply := chan of ref Value;
		m.c <-= ref Modulecmd[ref Value].Run(ctxt.drawctxt, ctxt.report, errorc, opts, args, reply);
		if((v := <-reply) != nil){
			pick xv := v {
			Vz =>
				xv.i.typec = m.typeset.types.find(xv.i.typec).tc;
			}
		}
		return v;
	}else if(m.def != nil){
		c: Eval->Context[ref Value, ref Module, ref Evalctxt];
		return c.eval(m.def, ref Evalctxt(m.defmods, ctxt.drawctxt, ctxt.report), errorc, args);
	}else if(m.typeset != nil){
		v := m.m->run(ctxt.drawctxt, ctxt.report, errorc, opts, args);
		free(opts, args, v != nil);
		return v;
	}
	report(errorc, "error: cannot run a virtually declared module");
	return nil;
}

free[V](opts: list of (int, list of V), args: list of V, used: int)
	for{
	V =>
		free: fn(v: self V, used: int);
	}
{
	for(; args != nil; args = tl args)
		(hd args).free(used);
	for(; opts != nil; opts = tl opts)
		for(args = (hd opts).t1; args != nil; args = tl args)
			(hd args).free(used);
}

Module.typename2c(s: string): int
{
	if((t := typebyname.find(s)) == nil)
		return -1;
	return t.tc;
}

Module.cvt(ctxt: ref Evalctxt, v: ref Value, tc: int, errorc: chan of string): ref Value
{
	if(v == nil)
		return nil;
	srctc := v.typec();
	dstid := gettype(tc).id;
	while((vtc := v.typec()) != tc){
		# XXX assumes v always returns a valid typec: might that be dangerous?
		for(l := gettype(vtc).transform; l != nil; l = tl l)
			if((hd l).all.holds(dstid))
				break;
		if(l == nil){
			report(errorc, sys->sprint("error: no way to get from %s to %s", gettype(v.typec()).qname,
					types[dstid].qname));
			v.free(0);
			return nil;		# should only happen the first time.
		}
		t := hd l;
		c: Eval->Context[ref Value, ref Module, ref Evalctxt];
		nv := c.eval(t.expr, ctxt, errorc, v::nil);
		if(nv == nil){
			report(errorc, sys->sprint("error: autoconvert %q failed", sh->cmd2string(t.expr)));
			return nil;
		}
		v = nv;
	}
	return v;
}

Module.mks(nil: ref Evalctxt, s: string): ref Value
{
	return ref Value.Vs(s);
}

Module.mkc(nil: ref Evalctxt, c: ref Sh->Cmd): ref Value
{
	return ref Value.Vc(c);
}

show()
{
	for(i := 0; i < len types; i++){
		if(types[i] == nil)
			continue;
		sys->print("%s =>\n", types[i].qname);
		for(l := types[i].transform; l != nil; l = tl l)
			sys->print("\t%s -> %s {%s}\n", set2s((hd l).all), types[(hd l).dst].qname, sh->cmd2string((hd l).expr));
	}
}

set2s(set: Set): string
{
	s := "{";
	for(i := 0; i < len types; i++){
		if(set.holds(i)){
			if(len s > 1)
				s[len s] = ' ';
			s += types[i].qname;
		}
	}
	return s + "}";
}

Value.dup(v: self ref Value): ref Value
{
	if(v == nil)
		return nil;
	pick xv := v {
	Vr =>
		return nil;
	Vd =>
		return nil;
	Vf or
	Vw =>
		return nil;
	Vz =>
		rc := chan of ref Value;
		gettype(xv.i.typec).typeset.c <-= ref Typescmd[ref Value].Dup(xv, rc);
		nv := <-rc;
		if(nv == nil)
			return nil;
		if(nv == v)
			return v;
		pick nxv := nv {
		Vz =>
			if(nxv.i.typec == xv.i.typec)
				return nxv;
		}
		sys->print("oh dear, invalid duplicated value from typeset %s\n",  gettype(xv.i.typec).typeset.name);
		return nil;
	}
	return v;
}

Value.typec(v: self ref Value): int
{
	pick xv := v {
	Vc =>
		return 'c';
	Vs =>
		return 's';
	Vr =>
		return 'r';
	Vf =>
		return 'f';
	Vw =>
		return 'w';
	Vd =>
		return 'd';
	Vz =>
		return xv.i.typec;
	}
}

Value.typename(v: self ref Value): string
{
	return Value.type2s(v.typec());
}

Value.free(v: self ref Value, used: int)
{
	if(v == nil)
		return;
	pick xv := v {
	Vr =>
		if(!used)
			xv.i <-= "stop";
	Vf or
	Vw=>
		if(!used){
			<-xv.i;
			xv.i <-= nil;
		}
	Vd =>
		if(!used){
			alt{
			xv.i.stop <-= 1 =>
				;
			* =>
				;
			}
		}
	Vz =>
		gettype(xv.i.typec).typeset.c <-= ref Typescmd[ref Value].Free(xv, used, reply := chan of int);
		<-reply;
	}
}

Value.isstring(v: self ref Value): int
{
	return tagof v == tagof Value.Vs;
}
Value.gets(v: self ref Value): string
{
	return v.s().i;
}
Value.c(v: self ref Value): ref Value.Vc
{
	pick xv :=v {Vc => return xv;}
	raise "type error";
}
Value.s(v: self ref Value): ref Value.Vs
{
	pick xv :=v {Vs => return xv;}
	raise "type error";
}
Value.r(v: self ref Value): ref Value.Vr
{
	pick xv :=v {Vr => return xv;}
	raise "type error";
}
Value.f(v: self ref Value): ref Value.Vf
{
	pick xv :=v {Vf => return xv;}
	raise "type error";
}
Value.w(v: self ref Value): ref Value.Vw
{
	pick xv :=v {Vw => return xv;}
	raise "type error";
}
Value.d(v: self ref Value): ref Value.Vd
{
	pick xv :=v {Vd => return xv;}
	raise "type error";
}
Value.z(v: self ref Value): ref Value.Vz
{
	pick xv :=v {Vz => return xv;}
	raise "type error";
}

Value.type2s(tc: int): string
{
	t := gettype(tc);
	if(t == nil)
		return "unknown";
	if(typebyname.find(t.name) == t)
		return t.name;
	return t.qname;
}

Rmodule.find(ctxt: ref Revalctxt, s: string): (ref Rmodule, string)
{
	m := ctxt.modules.find(s);
	if(m == nil){
		if(autodeclare == 0 || s == nil || s[0] != '/')
			return (nil, "module not declared");
		if(ctxt.modules != modules)
			return (nil, "shouldn't happen: module not found in defined block");
		err: string;
		(m, err) = declare0(s, nil, ONDEMAND);
		if(m == nil)
			return (nil, err);
	}
	return (ref Rmodule(m), nil);
}

Rmodule.cvt(ctxt: ref Revalctxt, v: ref Rvalue, tc: int, errorc: chan of string): ref Rvalue
{
	if(v == nil)
		return nil;
	srctc := v.typec();
	dstid := gettype(tc).id;
	while((vtc := v.typec()) != tc){
		# XXX assumes v always returns a valid typec: might that be dangerous?
		for(l := gettype(vtc).transform; l != nil; l = tl l)
			if((hd l).all.holds(dstid))
				break;
		if(l == nil){
			report(errorc, sys->sprint("error: no way to get from %s to %s", gettype(v.typec()).qname,
					types[dstid].qname));
			return nil;		# should only happen the first time.
		}
		t := hd l;
		c: Eval->Context[ref Rvalue, ref Rmodule, ref Revalctxt];
		v = c.eval(t.expr, ctxt, errorc, v::nil);
	}
	return v;
}

Rmodule.typesig(m: self ref Rmodule): string
{
	return m.m.sig;
}

Rmodule.typename2c(name: string): int
{
	return Module.typename2c(name);
}

Rmodule.mks(ctxt: ref Revalctxt, s: string): ref Rvalue
{
	v := ref Rvalue(mkw(s), 's', 0, nil, nil);
	ctxt.vals = v :: ctxt.vals;
	return v;
}

Rmodule.mkc(ctxt: ref Revalctxt, c: ref Sh->Cmd): ref Rvalue
{
	v := ref Rvalue(mk(n_BQ2, c, nil), 'c', 0, nil, nil);
	ctxt.vals = v :: ctxt.vals;
	return v;
}

Rmodule.run(m: self ref Rmodule, ctxt: ref Revalctxt, errorc: chan of string,
		opts: list of (int, list of ref Rvalue), args: list of ref Rvalue): ref Rvalue
{
	if(ctxt.defs && m.m.def != nil){
		c: Eval->Context[ref Rvalue, ref Rmodule, ref Revalctxt];
		nctxt := ref Revalctxt(m.m.defmods, ctxt.used, ctxt.defs, ctxt.vals);
		v := c.eval(m.m.def, nctxt, errorc, args);
		ctxt.vals = nctxt.vals;
		return v;
	}
	name := mkqname(m.m.typeset.name, m.m.modname);
	if(ctxt.used != nil){
		ctxt.used.add(name, m.m);
		m.m.refcount++;
	}
	v := ref Rvalue(mkw(name), m.m.sig[0], 0, opts, args);
	if(args == nil && opts == nil)
		v.i = mk(n_BLOCK, v.i, nil);
	for(; args != nil; args = tl args)
		(hd args).refcount++;
	for(; opts != nil; opts = tl opts)
		for(args = (hd opts).t1; args != nil; args = tl args)
			(hd args).refcount++;
	ctxt.vals = v :: ctxt.vals;
	return v;
}

Rvalue.dup(v: self ref Rvalue): ref Rvalue
{
	return v;
}
	
Rvalue.free(nil: self ref Rvalue, nil: int)
{
	# XXX perhaps there should be some way of finding out whether a particular
	# type will allow duplication of values or not.
}

Rvalue.isstring(v: self ref Rvalue): int
{
	return v.tc == 's';
}

Rvalue.gets(t: self ref Rvalue): string
{
	return t.i.word;
}

Rvalue.type2s(tc: int): string
{
	return Value.type2s(tc);
}

Rvalue.typec(t: self ref Rvalue): int
{
	return t.tc;
}

addconversion(src, dst: ref Type, expr: ref Sh->Cmd): string
{
	# allow the same transform to be added again
	for(l := src.transform; l != nil; l = tl l)
		if((hd l).all.holds(dst.id)){
			if((hd l).dst == dst.id && sh->cmd2string((hd l).expr) == sh->cmd2string(expr))
				return nil;
		}

	reached := array[len types/8+1] of {* => byte 0};
	if((at := ambiguous(dst, reached)) != nil)
		return sys->sprint("ambiguity: %s", at);

	src.transform = ref Transform(dst.id, sets->bytes2set(reached), expr) :: src.transform;
	# check we haven't created ambiguity in nodes that point to src.
	for(i := 0; i < len types; i++){
		for(l = types[i].transform; l != nil; l = tl l){
			if((hd l).all.holds(src.id) && (at = ambiguous(types[i], array[len types/8+1] of {* => byte 0})) != nil){
				src.transform = tl src.transform;
				return sys->sprint("ambiguity: %s", at);
			}
		}
	}
	all := (Sets->None).add(dst.id);
	for(l = types[dst.id].transform; l != nil; l = tl l)
		all = all.X(Sets->A|Sets->B, (hd l).all);
	# add everything pointed to by dst to the all sets of those types
	# that had previously pointed (indirectly) to src
	for(i = 0; i < len types; i++)
		for(l = types[i].transform; l != nil; l = tl l)
			if((hd l).all.holds(src.id))
				(hd l).all = (hd l).all.X(Sets->A|Sets->B, all);
	return nil;
}

ambiguous(t: ref Type, reached: array of byte): string
{
	if((dt := ambiguous1(t, reached)) == nil)
		return nil;
	(nil, at) := findambiguous(t, dt, array[len reached] of {* =>byte 0}, "self "+types[t.id].qname);
	s := hd at;
	for(at = tl at; at != nil; at = tl at)
		s += ", " + hd at;
	return s;
}

# a conversion is ambiguous if there's more than one
# way of reaching the same type.
# return the type at which the ambiguity is found.
ambiguous1(t: ref Type, reached: array of byte): ref Type
{
	if(bsetholds(reached, t.id))
		return t;
	bsetadd(reached, t.id);
	for(l := t.transform; l != nil; l = tl l)
		if((at := ambiguous1(types[(hd l).dst], reached)) != nil)
			return at;
	return nil;
}

findambiguous(t: ref Type, dt: ref Type, reached: array of byte, s: string): (int, list of string)
{
	a: list of string;
	if(t == dt)
		a = s :: nil;
	if(bsetholds(reached, t.id))
		return (1, a);
	bsetadd(reached, t.id);
	for(l := t.transform; l != nil; l = tl l){
		(found, at) := findambiguous(types[(hd l).dst], dt, reached,
				sys->sprint("%s|%s", s, sh->cmd2string((hd l).expr)));	# XXX rewite correctly
		for(; at != nil; at = tl at)
			a = hd at :: a;
		if(found)
			return (1, a);
	}
	return (0, a);
}

bsetholds(x: array of byte, n: int): int
{
	return int x[n >> 3] & (1 << (n & 7));
}

bsetadd(x: array of byte, n: int)
{
	x[n >> 3] |= byte (1 << (n & 7));
}

mkqname(parent, child: string): string
{
	if(parent == "/")
		return parent+child;
	return parent+"/"+child;
}

# splits a canonical qname into typeset and name components.
splitqname(name: string): (string, string)
{
	if(name == nil)
		return (nil, nil);
	for(i := len name - 1; i >= 0; i--)
		if(name[i] == '/')
			break;
	if(i == 0)
		return ("/", name[1:]);
	return (name[0:i], name[i+1:]);
}

# compress multiple slashes into single; remove trailing slashes.
canon(name: string): string
{
	if(name == nil || name[0] != '/')
		return nil;

	slash := nonslash := 0;
	s := "";
	for(i := 0; i < len name; i++){
		c := name[i];
		if(c == '/')
			slash = 1;
		else{
			if(slash){
				s[len s] = '/';
				nonslash++;
				slash = 0;
			}
			s[len s] = c;
		}
	}
	if(slash && !nonslash)
		s[len s] = '/';
	return s;
}

report(errorc: chan of string, s: string)
{
	if(Debug || errorc == nil)
		sys->fprint(sys->fildes(2), "%s\n", s);
	if(errorc != nil)
		errorc <-= s;
}

Table[T].new(nslots: int, nilval: T): ref Table[T]
{
	if(nslots == 0)
		nslots = 13;
	return ref Table[T](array[nslots] of list of (int, T), nilval);
}

Table[T].add(t: self ref Table[T], id: int, x: T): int
{
	slot := id % len t.items;
	for(q := t.items[slot]; q != nil; q = tl q)
		if((hd q).t0 == id)
			return 0;
	t.items[slot] = (id, x) :: t.items[slot];
	return 1;
}

Table[T].del(t: self ref Table[T], id: int): int
{
	slot := id % len t.items;
	
	p: list of (int, T);
	r := 0;
	for(q := t.items[slot]; q != nil; q = tl q){
		if((hd q).t0 == id){
			p = joinip(p, tl q);
			r = 1;
			break;
		}
		p = hd q :: p;
	}
	t.items[slot] = p;
	return r;
}

Table[T].find(t: self ref Table[T], id: int): T
{
	for(p := t.items[id % len t.items]; p != nil; p = tl p)
		if((hd p).t0 == id)
			return (hd p).t1;
	return t.nilval;
}

hashfn(s: string, n: int): int
{
	h := 0;
	m := len s;
	for(i:=0; i<m; i++){
		h = 65599*h+s[i];
	}
	return (h & 16r7fffffff) % n;
}

Strhash[T].new(nslots: int, nilval: T): ref Strhash[T]
{
	if(nslots == 0)
		nslots = 13;
	return ref Strhash[T](array[nslots] of list of (string, T), nilval);
}

Strhash[T].add(t: self ref Strhash, id: string, x: T)
{
	slot := hashfn(id, len t.items);
	t.items[slot] = (id, x) :: t.items[slot];
}

Strhash[T].del(t: self ref Strhash, id: string)
{
	slot := hashfn(id, len t.items);

	p: list of (string, T);
	for(q := t.items[slot]; q != nil; q = tl q)
		if((hd q).t0 != id)
			p = hd q :: p;
	t.items[slot] = p;
}

Strhash[T].find(t: self ref Strhash, id: string): T
{
	for(p := t.items[hashfn(id, len t.items)]; p != nil; p = tl p)
		if((hd p).t0 == id)
			return (hd p).t1;
	return t.nilval;
}

rev[T](x: list of T): list of T
{
	l: list of T;
	for(; x != nil; x = tl x)
		l = hd x :: l;
	return l;
}

# join x to y, leaving result in arbitrary order.
join[T](x, y: list of T): list of T
{
	if(len x > len y)
		(x, y) = (y, x);
	for(; x != nil; x = tl x)
		y = hd x :: y;
	return y;
}

# join x to y, leaving result in arbitrary order.
joinip[T](x, y: list of (int, T)): list of (int, T)
{
	if(len x > len y)
		(x, y) = (y, x);
	for(; x != nil; x = tl x)
		y = hd x :: y;
	return y;
}

sort[S, T](s: S, a: array of T)
	for{
	S =>
		gt: fn(s: self S, x, y: T): int;
	}
{
	mergesort(s, a, array[len a] of T);
}

mergesort[S, T](s: S, a, b: array of T)
	for{
	S =>
		gt: fn(s: self S, x, y: T): int;
	}
{
	r := len a;
	if (r > 1) {
		m := (r-1)/2 + 1;
		mergesort(s, a[0:m], b[0:m]);
		mergesort(s, a[m:], b[m:]);
		b[0:] = a;
		for ((i, j, k) := (0, m, 0); i < m && j < r; k++) {
			if(s.gt(b[i], b[j]))
				a[k] = b[j++];
			else
				a[k] = b[i++];
		}
		if (i < m)
			a[k:] = b[i:m];
		else if (j < r)
			a[k:] = b[j:r];
	}
}
