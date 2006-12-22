Fslib: module {
	PATH: con "/dis/lib/fslib.dis";
	Value: adt {
		x:	fn(v: self ref Value): ref Value.X;
		p:	fn(v: self ref Value): ref Value.P;
		s:	fn(v: self ref Value): ref Value.S;
		c:	fn(v: self ref Value): ref Value.C;
		t:	fn(v: self ref Value): ref Value.T;
		v:	fn(v: self ref Value): ref Value.V;
		m:	fn(v: self ref Value): ref Value.M;
		typec: fn(v: self ref Value): int;
		discard: fn(v: self ref Value);
		pick {
		X =>
			i: Fschan;
		T =>
			i: Entrychan;
		P =>
			i: Gatechan;
		C =>
			i: ref Sh->Cmd;
		S =>
			i: string;
		V =>
			i: chan of int;		# sync channel for void-valued processes
		M =>
			i: Cmpchan;
		}
	};
	init:			fn();
	typecompat:	fn(t, act: string): int;
	sendnulldir:	fn(c: Fschan): int;
	quit:			fn(errorc: chan of string);
	report:		fn(errorc: chan of string, err: string);
	copy:		fn(src, dst: Fschan): int;

	cmdusage:	fn(cmd, t: string): string;
	type2s:		fn(t: int): string;
	opttypes:		fn(opt: int, opts: string): (int, string);
	splittype:		fn(t: string): (int, string, string);

	Report: adt {

		reportc: chan of string;
		startc: chan of (string, chan of string);
		enablec: chan of int;
	
		new:		fn(): ref Report;
		enable:	fn(r: self ref Report);
		start:		fn(r: self ref Report, name: string): chan of string;
	};
	Option: adt {
		opt: int;
		args: list of ref Value;
	};
	Entrychan: adt {
		sync: chan of int;
		c: chan of Entry;
	};
	Cmpchan: type chan of (ref Sys->Dir, ref Sys->Dir, chan of int);
	Entry: type (ref Sys->Dir, string, int);
	Gatequery: type (Entry, chan of int);
	Gatechan: type chan of Gatequery;
	Fsdata: adt {
		dir: ref Sys->Dir;
		data: array of byte;
	};
	Fschan: type chan of (Fsdata, chan of int);
	Next, Down, Skip, Quit: con iota;

	Nilentry: con (nil, nil, 0);
};

Fsmodule: module {
	types: fn(): string;
	init:	fn();
	run: fn(ctxt: ref Draw->Context, r: ref Fslib->Report,
		opts: list of Fslib->Option, args: list of ref Fslib->Value): ref Fslib->Value;
};

Fsfilter: module {
	PATH: con "/dis/lib/fsfilter.dis";
	filter: fn[T](t: T, src, dst: Fslib->Fschan)
		for{
		T =>
			query: fn(t: self T, d: ref Sys->Dir, name: string, depth: int): int;
		};
};
