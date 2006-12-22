ABCStyx: module {
	PATH: con "/dis/alphabet/abcstyx.dis";
	Value: adt {
		c:	fn(v: self ref Value): ref Value.C;	# cmd
		s:	fn(v: self ref Value): ref Value.S;	# string
		w:	fn(v: self ref Value): ref Value.W;	# wfd
		x:	fn(v: self ref Value): ref Value.D;	# styx

		typec: fn(v: self ref Value): int;
		type2s:	fn(t: int): string;
		discard: fn(v: self ref Value);
		reusable:	fn(v: self ref Value): int;

		pick {
		S =>
			i: string;
		C =>
			i: ref Sh->Cmd;
		W =>
			i: chan of ref Sys->FD;
		X =>
			i: (chan of ref Styx->Rmsg, chan of ref Styx->Tmsg);
		}
	};
	init: fn();
};

Styxmodule: module {
	types: fn(): string;
	init: fn();
	run: fn(errorc: chan of string, r: ref Reports->Report,
		opts: list of (int, list of ref ABCStyx->Value), args: list of ref ABCStyx->Value): ref ABCStyx->Value;
};
