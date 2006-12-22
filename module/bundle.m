Bundle: module {
	PATH: con "/dis/fs/bundle.dis";

	types: fn(): string;
	init: fn();
	run: fn(nil: ref Draw->Context, report: ref Fslib->Report,
			nil: list of Fslib->Option, args: list of ref Fslib->Value): ref Fslib->Value;
	bundle:	fn(r: ref Fslib->Report, iob: ref Bufio->Iobuf, c: Fslib->Fschan): chan of int;
};
