Cfg : module {
	PATH : con "/dis/lib/cfg.dis";

	Attr : adt {
		name : string;
		value : string;
	};

	Tuple : adt {
		lnum : int;
		attrs : list of Attr;
		lookup: fn (t : self ref Tuple, name : string) : string;
	};

	Record : adt {
		tuples : list of ref Tuple;
		lookup : fn (r : self ref Record, name : string) : (string, ref Tuple);
	};

	init : fn (path : string) : string;
	reset:	fn();
	lookup : fn (name : string) : list of (string, ref Record);
	getkeys : fn () : list of string;
	parseline:	fn(s: string, lno: int): (ref Tuple, string);
};
