Bundle: module {
	PATH: con "/dis/fs/bundle.dis";

	types: fn(): string;
	init: fn();
	run: fn(nil: ref Draw->Context, report: ref Reports->Report,
			nil: list of Fs->Option, args: list of ref Fs->Value): ref Fs->Value;
	bundle:	fn(r: ref Reports->Report, iob: ref Bufio->Iobuf, c: Fs->Fschan): chan of string;
};
