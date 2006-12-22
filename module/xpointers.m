Xpointers: module
{
	PATH: con "/dis/lib/w3c/xpointers.dis";

	One, Ole, Oge, Omul, Odiv, Omod, Oand, Oor, Oneg,
	Onodetype, Onametest, Ofilter, Opath: con 'A'+iota;

	# axis types
	Aancestor,
	Aancestor_or_self,
	Aattribute,
	Achild,
	Adescendant,
	Adescendant_or_self,
	Afollowing,
	Afollowing_sibling,
	Anamespace,
	Aparent,
	Apreceding,
	Apreceding_sibling,
	Aself: con iota;

	Xstep: adt {
		axis:	int;	# Aancestor, ... (above)
		op:	int;	# Onametest or Onodetype
		ns:	string;
		name:	string;
		arg:	string;	# optional parameter to processing-instruction
		preds:	cyclic list of ref Xpath;

		text:	fn(nil: self ref Xstep): string;
		axisname:	fn(i: int): string;
	};

	Xpath: adt {
		pick{
		E =>
			op: int;
			l, r: cyclic ref Xpath;
		Fn =>
			ns:	string;
			name:	string;
			args:	cyclic list of ref Xpath;
		Var =>
			ns: string;
			name: string;
		Path =>
			abs:	int;
			steps:	list of ref Xstep;
		Int =>
			val: big;
		Real =>
			val: real;
		Str =>
			s: string;
		}
		text:	fn(nil: self ref Xpath): string;
	};

	init:	fn();
	framework:	fn(s: string): (string, list of (string, string, string), string);

	# predefined schemes
	element:	fn(s: string): (string, list of int, string);
	xmlns:	fn(s: string): (string, string, string);
	xpointer:	fn(s: string): (ref Xpath, string);
};
