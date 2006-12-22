#
# CSS parsing module
#
# CSS2.1 style sheets
#
# Copyright © 2001, 2005 Vita Nuova Holdings Limited.  All rights reserved.
#
CSS: module
{
	PATH:	con "/dis/lib/w3c/css.dis";

	Stylesheet: adt {
		charset:	string;
		imports:	list of ref Import;
		statements:	list of ref Statement;
	};

	Import: adt {
		name:	string;
		media:	list of string;
	};

	Statement: adt {
		pick{
		Media =>
			media:	list of string;
			rules:	list of ref Statement.Ruleset;
		Page =>
			pseudo:	string;
			decls:	list of ref Decl;
		Ruleset =>
			selectors:	list of Selector;
			decls:	list of ref Decl;
		}
	};

	Decl: adt {
		property:	string;
		values:	list of ref Value;
		important:	int;
	};

	Selector:	type list of (int, Simplesel);	# int is combinator from [ >+]
	Simplesel: type list of ref Select;

	Select: adt {
		name:	string;
		pick{
		Element or ID or Any or Class or Pseudo =>
		Attrib =>
			op:	string;	# "=" "~=" "|="
			value:	ref Value;	# optional Ident or String
		Pseudofn =>
			arg:	string;
		}
	};

	Value: adt {
		sep:	int;	# which operator of [ ,/] preceded this value in list
		pick{
		String or
		Number or
		Percentage or
		Url or
		Unicoderange =>
			value:	string;
		Hexcolour =>
			value:	string;	# as given
			rgb:	(int, int, int);	# converted
		RGB =>
			args:	cyclic list of ref Value;	# as given
			rgb:	(int, int, int);		# converted
		Ident =>
			name:	string;
		Unit =>
			value:	string;	# int or float
			units:	string;	# suffix giving units ("cm", "khz", and so on, always lower case)
		Function =>
			name:	string;
			args:		cyclic list of ref Value;
		}
	};

	init:	fn(diag: int);
	parse:	fn(s: string): (ref Stylesheet, string);
	parsedecl:	fn(s: string): (list of ref Decl, string);
#	unescape:	fn(s: string): string;
};
