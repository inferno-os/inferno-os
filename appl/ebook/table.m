Table: module {
	PATH: con "/dis/ebook/table.dis";
	Cell: adt {
		w: string;
		span: Draw->Point;
		sizereq: Draw->Point;
	};
	init:	fn();
	newcell:	fn(w: string, span: Draw->Point): ref Cell;
	layout: fn(cells: array of array of ref Cell, win: ref Tk->Toplevel, w: string);
};
