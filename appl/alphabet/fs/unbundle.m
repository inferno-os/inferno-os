Unbundle: module {
	PATH: con "/dis/fs/bundle.dis";

	types: fn(): string;
	init: fn();
	run: fn(nil: ref Draw->Context, report: ref Report,
			nil: list of Option, args: list of ref Value): ref Value;
	unbundle:	fn(r: ref Reports->Report, iob: ref Bufio->Iobuf, seekable: int, blocksize: int): Fs->Fschan;
};
