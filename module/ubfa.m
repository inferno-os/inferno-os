UBFa: module
{
	PATH:	con "/dis/lib/ubfa.dis";

	UValue: adt {
		pick{
		Atom =>
			name: string;
		Int =>
			value:	int;	# should have big as well?
		String =>
			s: string;
		Binary =>
			a: array of byte;
		Tuple =>
			a: cyclic array of ref UValue;	# tree
		List =>
			l: cyclic list of ref UValue;	# tree
		Tag =>
			name:	string;
			o:	cyclic ref UValue;
		}

		isatom:	fn(o: self ref UValue): int;
		isstring:	fn(o: self ref UValue): int;
		isint:		fn(o: self ref UValue): int;
		istuple:	fn(o: self ref UValue): int;
		isop: 	fn(o: self ref UValue, op: string, arity: int): int;
		islist:		fn(o: self ref UValue): int;
		isbinary:	fn(o: self ref UValue): int;
		istag:	fn(o: self ref UValue): int;
		text:		fn(o: self ref UValue): string;
		eq:		fn(o: self ref UValue, v: ref UValue): int;
		op:		fn(o: self ref UValue, arity: int): string;
		args:		fn(o: self ref UValue, arity: int): array of ref UValue;
		els:		fn(o: self ref UValue): list of ref UValue;
		val:		fn(o: self ref UValue): int;
		binary:	fn(o: self ref UValue): array of byte;
		objtag:	fn(o: self ref UValue): string;
		obj:		fn(o: self ref UValue): ref UValue;
	};

	init:	fn(bufio: Bufio);
	readubf:	fn(input: ref Iobuf): (ref UValue, string);
	writeubf:	fn(out: ref Iobuf, obj: ref UValue): int;
	uniq:	fn(s: string): string;

	# shorthand
	uvatom:	fn(s: string): ref UValue.Atom;
	uvint:	fn(i: int): ref UValue.Int;
	uvbig:	fn(i: big): ref UValue.Int;
	uvstring:	fn(s: string): ref UValue.String;
	uvbinary:	fn(a: array of byte): ref UValue.Binary;
	uvtuple:	fn(a: array of ref UValue): ref UValue.Tuple;
	uvlist:	fn(l: list of ref UValue): ref UValue.List;
	uvtag:	fn(name: string, o: ref UValue): ref UValue.Tag;
};
