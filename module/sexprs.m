Sexprs: module
{
	PATH:	con "/dis/lib/sexprs.dis";

	Sexp: adt {
		pick {
		String =>
			s: string;
			hint:	string;
		Binary =>
			data:	array of byte;
			hint: string;
		List =>
			l:	cyclic list of ref Sexp;
		}

		read:	fn[T](b: T): (ref Sexp, string) for {
				T =>
					getb:	fn(nil: self T): int;
					ungetb:	fn(nil: self T): int;
					offset:	fn(nil: self T): big;
				};
		parse:	fn(s: string): (ref Sexp, string, string);
		unpack:	fn(a: array of byte): (ref Sexp, array of byte, string);
		text:	fn(e: self ref Sexp): string;
		packedsize:	fn(e: self ref Sexp): int;
		pack:	fn(e: self ref Sexp): array of byte;
		b64text:	fn(e: self ref Sexp): string;

		islist:	fn(e: self ref Sexp): int;
		els:	fn(e: self ref Sexp): list of ref Sexp;
		op:	fn(e: self ref Sexp): string;
		args:	fn(e: self ref Sexp): list of ref Sexp;
		eq:	fn(e: self ref Sexp, t: ref Sexp): int;
		copy:	fn(e: self ref Sexp): ref Sexp;
		asdata:	fn(e: self ref Sexp): array of byte;
		astext:	fn(e: self ref Sexp): string;
	};

	init:	fn();
};
