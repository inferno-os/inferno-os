Dictionary: module {
	PATH: con "/dis/lib/dict.dis";

	Dict: adt {
		entries: list of (string, string);

		add:	fn( d: self ref Dict, e: (string, string) );
		delete:	fn( d: self ref Dict, k: string );
		lookup:	fn( d: self ref Dict, k: string ) :string;
		keys:	fn( d: self ref Dict ): list of string;
	};


};