Stylesheet: module {
	PATH: con "/dis/ebook/stylesheet.dis";
	DEFAULT, READER, AUTHOR: con iota;
	init:		fn(stylenames: array of string);

	Style: adt {
		sheet:	ref Sheet;
		attrs:		array of string;		# values
		spec:	array of int;		# specificity

		add:		fn(style: self ref Style, tag, class: string);
		adddecls: fn(style: self ref Style, decls: list of CSSparser->Decl);
		addone:	fn(style: self ref Style, attr: int, origin: int, val: string);
	};

	Sheet: adt {
		new:		fn(): ref Sheet;
		addrules:	fn(sheet: self ref Sheet,
			rules: list of (string, list of CSSparser->Decl), origin: int);
		newstyle:	fn(sheet: self ref Sheet): ref Style;

		# private from here
		rules:	array of list of Rule;
		ruleid:	int;		# sequential ordering of rules

	};

	# private from here

	# declaration as stored internally.
	Ldecl:	adt {
		attrid:		int;
		specificity:	int;
		val:			string;
	};
	
	Rule: adt {
		key:		string;		# hash key: "tagname" or ".classname"
		sub:		string;		# tag name if rule is for a tag-specific class
		decls:	list of Ldecl;
	};
};
