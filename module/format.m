Format: module {
	PATH: con "/dis/lib/format.dis";
	Fmtspec: adt {
		name: string;
		fields: cyclic array of Fmtspec;
	};
	Fmt: adt {
		kind: int;
		fields: cyclic array of Fmt;
	};
	Fmtval: adt {
		val: ref Sexprs->Sexp;
		recs: cyclic array of array of Fmtval;

		text: fn(v: self Fmtval): string;
	};
	Fmtfile: adt {
		spec: array of Fmtspec;
		descr: array of byte;
	
		new: fn(spec: array of Fmtspec): Fmtfile;
		open: fn(f: self Fmtfile, name: string): ref Bufio->Iobuf;
		read: fn(f: self Fmtfile, iob: ref Bufio->Iobuf): (array of Fmtval, string);
	};
	init: fn();
	spec2se: fn(spec: array of Fmtspec): list of ref Sexprs->Sexp;
	spec2fmt: fn(spec: array of Fmtspec): array of Fmt;
	se2fmt: fn(spec: array of Fmtspec, se: ref Sexprs->Sexp): (array of Fmt, string);
	rec2val: fn(spec: array of Fmtspec, rec: ref Sexprs->Sexp): (array of Fmtval, string);
};
