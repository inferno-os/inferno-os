Paginate: module {
	PATH: con "/dis/charon/paginate.dis";

	init: fn(layout: Layout, draw: Draw, display: ref Draw->Display): string;

	Pageset: adt {
		printer: ref Print->Printer;
		frame: ref Layout->Frame;
		pages: list of int;
	};

	PORTRAIT, LANDSCAPE: con iota;

	paginate: fn(frame: ref Layout->Frame, orient: int, pagenums, cancel: chan of int, result: chan of (string, ref Pageset));
	printpageset: fn(pages: ref Pageset, pagenums, cancel: chan of int);
};
