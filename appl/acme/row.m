Rowm : module {
	PATH : con "/dis/acme/row.dis";

	init : fn(mods : ref Dat->Mods);

	newrow : fn() : ref Row;

	Row : adt {
		qlock : ref Dat->Lock;
		r : Draw->Rect;
		tag : cyclic ref Textm->Text;
		col : cyclic array of ref Columnm->Column;
		ncol : int;

		init : fn(r : self ref Row, re : Draw->Rect);
		add : fn(r : self ref Row, c : ref Columnm->Column, n : int) : ref Columnm->Column;
		close : fn(r : self ref Row, c : ref Columnm->Column, n : int);
		which : fn(r : self ref Row, p : Draw->Point) : ref Textm->Text;
		whichcol : fn(r : self ref Row, p : Draw->Point) : ref Columnm->Column;
		reshape : fn(r : self ref Row, re : Draw->Rect);
		typex : fn(r : self ref Row, ru : int, p : Draw->Point) : ref Textm->Text;
		dragcol : fn(r : self ref Row, c : ref Columnm->Column);
		clean : fn(r : self ref Row, exiting : int) : int;
		dump : fn(r : self ref Row, b : string);
		loadx : fn(r : self ref Row, b : string, n : int);
	};

	allwindows: fn(a0: int, aw: ref Dat->Allwin);
};
