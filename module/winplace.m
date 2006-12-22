Winplace: module {
	PATH: con "/dis/lib/winplace.dis";
	init: fn();
	place: fn(wins: list of Draw->Rect, scr, lastrect: Draw->Rect, minsize: Draw->Point): Draw->Rect;
	find: fn(wins: list of Draw->Rect, scr: Draw->Rect): list of Draw->Rect;
};
