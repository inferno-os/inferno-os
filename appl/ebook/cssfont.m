CSSfont: module {
	PATH: con "/dis/ebook/cssfont.dis";
	Spec: adt {
		family, style, weight, size: string;
	};

	init:		fn(displ: ref Draw->Display);
	getfont:	fn(spec: Spec, parentem, parentex: int): (string, int, int);
};
