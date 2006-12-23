Xml: module {
	PATH: con "/dis/lib/xml.dis";
	Item: adt {
		fileoffset:	int;
		pick {
		Tag =>
			name:	string;
			attrs:		Attributes;
		Text =>
			ch:		string;
			ws1, ws2: int;
		Process =>
			target:	string;
			data:		string;
		Doctype =>
			name:	string;
			public:	int;
			params:	list of string;
		Stylesheet =>
			attrs:		Attributes;
		Error =>
			loc:		Locator;
			msg:		string;
		}
	};

	Locator: adt {
		line:				int;
		systemid:			string;
		publicid:			string;
	};

	Attribute: adt {
		name:			string;
		value:			string;
	};

	Attributes: adt {
		attrs:			list of Attribute;

		all:			fn(a: self Attributes): list of Attribute;
		get:			fn(a: self Attributes, name: string): string;
	};

	Mark: adt {
		estack:	list of string;
		line:		int;
		offset:	int;
		readdepth:	int;

		str:		fn(m: self ref Mark): string;	
	};

	Parser: adt {
		in:		ref Bufio->Iobuf;
		eof:		int;
		lastnl:	int;
		estack:	list of string;
		loc:		Locator;
		warning:	chan of (Locator, string);
		errormsg:	string;
		actdepth:	int;
		readdepth:	int;
		fileoffset:	int;
		preelem:	string;
		ispre:	int;

		next:		fn(p: self ref Parser): ref Item;
		up:		fn(p: self ref Parser);
		down:	fn(p: self ref Parser);
		mark:	fn(p: self ref Parser): ref Mark;
		atmark:	fn(p: self ref Parser, m: ref Mark): int;
		goto:	fn(p: self ref Parser, m: ref Mark);
		str2mark:	fn(p: self ref Parser, s: string): ref Mark;
	};
	init:	fn(): string;
	open: fn(f: string, warning: chan of (Locator, string), preelem: string): (ref Parser, string);
	fopen:	fn(f: ref Bufio->Iobuf, srcname: string, warning: chan of (Locator, string), preelem: string): (ref Parser, string);
};
