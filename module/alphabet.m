Alphabet: module {
	PATH: con "/dis/alphabet/alphabet.dis";
	ONDEMAND, CHECK: con 1<<iota;

	init:	fn();
	copy: fn(): Alphabet;
	quit: fn();
	loadtypeset: fn(qname: string, c: chan of ref Proxy->Typescmd[ref Value], errorc: chan of string): string;
	declare: fn(qname: string, sig: string, flags: int): string;
	undeclare: fn(name: string): string;
	importmodule: fn(qname: string): string;
	importtype: fn(qname: string): string;
	importvalue: fn(v: ref Value, qname: string): (ref Value, string);
	autoconvert: fn(src, dst: string, transform: ref Sh->Cmd, errorc: chan of string): string;
	define: fn(name: string, expr: ref Sh->Cmd, errorc: chan of string): string;
	setautodeclare: fn(on: int);

	Decltypeset: adt {
		name: string;
		alphabet: string;
		types: array of string;
		mods: array of (string, string);
	};
	Declarations: adt {
		typesets: array of Decltypeset;
		defs: array of (string, string);
	};
#	getdecls: fn(): ref Declarations;
#	getexprdecls: fn(e: ref Sh->Cmd): ref Declarations;
#	declcompat: fn(d0, d1: ref Declarations): int;

	getmodule: fn(name: string): (string, string, ref Sh->Cmd);
	gettypesets: fn(): list of string;
	getmodules: fn(): list of string;
	gettypesetmodules: fn(tsname: string): chan of string;
	gettypes: fn(typeset: string): list of string;
	getautoconversions: fn(): list of (string, string, ref Sh->Cmd);
	typecompat: fn(t0, t1: string): (int, string);
	show: fn();

	mkqname: fn(typeset, name: string): string;
	canon: fn(qname: string): string;
	splitqname: fn(qname: string): (string, string);
	parse: fn(expr: string): (ref Sh->Cmd, string);

	eval: fn(expr: ref Sh->Cmd,
			drawctxt: ref Draw->Context,
			args: list of ref Value): string;
	eval0: fn(expr: ref Sh->Cmd,
			dsttype: string,
			drawctxt: ref Draw->Context,
			report: ref Reports->Report,
			errorc: chan of string,
			args: list of ref Value,
			vc: chan of ref Value);
	rewrite: fn(expr: ref Sh->Cmd, dsttype: string,
			errorc: chan of string): (ref Sh->Cmd, string);
	
	Value: adt {
		free:		fn(v: self ref Value, used: int);
		dup:		fn(v: self ref Value): ref Value;
		gets:		fn(v: self ref Value): string;
		isstring:	fn(v: self ref Value): int;
		type2s:	fn(tc: int): string;
		typec:	fn(v: self ref Value): int;
		typename: fn(v: self ref Value): string;

		c: fn(v: self ref Value): ref Value.Vc;
		s: fn(v: self ref Value): ref Value.Vs;
		r: fn(v: self ref Value): ref Value.Vr;
		f: fn(v: self ref Value): ref Value.Vf;
		w: fn(v: self ref Value): ref Value.Vw;
		d: fn(v: self ref Value): ref Value.Vd;
		z: fn(v: self ref Value): ref Value.Vz;

		pick{
		Vc =>
			i: ref Sh->Cmd;
		Vs =>
			i: string;
		Vr =>
			i: chan of string;
		Vf or
		Vw =>
			i: chan of ref Sys->FD;
		Vd =>
			i: Datachan;
		Vz =>
			i: Proxyval;		# a proxy for the actual value, held by another process
		}
	};

	Proxyval: adt {
		typec: int;
		id: int;
	};

	Datachan: adt {
		d: chan of array of byte;
		stop: chan of int;
	};
};

Mainmodule: module {
	typesig: fn(): string;
	init:	fn();
	quit: fn();
	run: fn(ctxt: ref Draw->Context, r: ref Reports->Report, errorc: chan of string,
		opts: list of (int, list of ref Alphabet->Value), args: list of ref Alphabet->Value): ref Alphabet->Value;
};

# evaluate an expression
Eval: module {
	PATH: con "/dis/alphabet/eval.dis";
	init: fn();

	Context: adt[V, M, Ectxt]
		for {
		V =>
			dup:		fn(t: self V): V;
			free:		fn(v: self V, used: int);
			isstring:	fn(v: self V): int;
			gets:		fn(t: self V): string;
			type2s:	fn(tc: int): string;
			typec:	fn(t: self V): int;
		M =>
			find:		fn(c: Ectxt, s: string): (M, string);
			typesig:	fn(m: self M): string;
			run:		fn(m: self M, c: Ectxt, errorc: chan of string,
						opts: list of (int, list of V), args: list of V): V;
			mks:		fn(c: Ectxt, s: string): V;
			mkc:		fn(c: Ectxt, cmd: ref Sh->Cmd): V;
			typename2c: fn(s: string): int;
			cvt:		fn(c: Ectxt, v: V, tc: int, errorc: chan of string): V;
		}
	{
		eval: fn(
			expr: ref Sh->Cmd,
			ctxt: Ectxt,
			errorc: chan of string,
			args: list of V
		): V;
	};
	cmdusage: fn[V](nil: V, sig: string): string
		for {
		V =>
			type2s:	fn(tc: int): string;
		};
	usage2sig: fn[V](nil: V, u: string): (string, string)
		for{
		V =>
			typename2c: fn(s: string): int;
		};
	blocksig: fn[M, Ectxt](nil: M, ctxt: Ectxt, c: ref Sh->Cmd): (string, string)
		for{
		M =>
			typename2c: fn(s: string): int;
			find:	fn(c: Ectxt, s: string): (M, string);
			typesig: fn(m: self M): string;
		};
	typecompat: fn(t0, t1: string): int;
	splittype: fn(t: string): (int, string, string);
};

Extvalues: module {
	PATH: con "/dis/alphabet/extvalues.dis";
	Values: adt[V] {
		lock: chan of int;
		v: array of (int, V);
		freeids: list of int;
		new: fn(): ref Values[V];
		add: fn(vals: self ref Values, v: V): int;
		inc: fn(vals: self ref Values, id: int);
		del: fn(vals: self ref Values, id: int);
	};
};

# generic proxy implementation:
Proxy: module {
	PATH: con "/dis/alphabet/proxy.dis";

	# operators on a type system
	Typescmd: adt[V] {
		pick {
		Load =>
			cmd: string;
			reply: chan of (chan of ref Modulecmd[V], string);
		Dup =>
			v: V;
			reply: chan of V;
		Free =>
			v: V;
			used: int;
			reply: chan of int;
		Alphabet =>
			reply: chan of string;
		Type2s =>
			tc: int;
			reply: chan of string;
		Loadtypes =>
			name: string;
			reply: chan of (chan of ref Typescmd[V], string);
		Modules =>
			reply: chan of string;
		}
	};
	
	# proxy for a loaded module.
	Modulecmd: adt[V] {
		pick {
		Typesig =>
			reply: chan of string;
		Run =>
			ctxt: ref Draw->Context;
			report: ref Reports->Report;
			errorc: chan of string;
#			stopc: chan of int;
			opts: list of (int, list of V);
			args: list of V;
			reply: chan of V;
		}
	};

	proxy: fn[Ctxt,Cvt,M,V,EV](ctxt: Ctxt): (
			chan of ref Proxy->Typescmd[EV],
			chan of (string, chan of ref Proxy->Typescmd[V])
		) for {
		M =>
			typesig: fn(m: self M): string;
			run: fn(m: self M, ctxt: ref Draw->Context, r: ref Reports->Report, errorc: chan of string,
					opts: list of (int, list of V), args: list of V): V;
			quit: fn(m: self M);
		Ctxt =>
			loadtypes: fn(ctxt: self Ctxt, name: string): (chan of ref Proxy->Typescmd[V], string);
			type2s: fn(ctxt: self Ctxt, tc: int): string;
			alphabet: fn(ctxt: self Ctxt): string;
			modules: fn(ctxt: self Ctxt, r: chan of string);
			find: fn(ctxt: self Ctxt, s: string): (M, string);
			getcvt: fn(ctxt: self Ctxt): Cvt;
		Cvt =>
			int2ext: fn(cvt: self Cvt, v: V): EV;
			ext2int: fn(cvt: self Cvt, ev: EV): V;
			free: fn(cvt: self Cvt, v: EV, used: int);
			dup:	fn(cvt: self Cvt, v: EV): EV;
	};
};
