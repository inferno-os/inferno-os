#
# Copyright © 2000 Vita Nuova Limited
#
Translate: module
{
	PATH:	con "/dis/lib/translate.dis";

	Dict: adt {
		texts:	array of list of ref Phrase;
		notes:	array of list of ref Phrase;

		new:		fn(): ref Dict;
		add:		fn(d: self ref Dict, file: string): string;
		xlate:	fn(d: self ref Dict, nil: string): string;
		xlaten:	fn(d: self ref Dict, nil: string, note: string): string;
	};

	Phrase: adt {
		key:	string;
		text:	string;	# nil for a note
		hash:	int;
		n:	int;
		note:	int;
	};

	init:	fn();
	opendict:	fn(file: string): (ref Dict, string);
	opendicts: fn(files: list of string): (ref Dict, string);
	mkdictname:	fn(locale, app: string): string;
};
