Columnm : module {
	PATH : con "/dis/acme/col.dis";

	init : fn(mods : ref Dat->Mods);

	Column : adt {
		r : Draw->Rect;
		tag : cyclic ref Textm->Text;
		row : cyclic ref Rowm->Row;
		w : cyclic array of ref Windowm->Window;
		nw : int;
		safe : int;

		init : fn (c : self ref Column, r : Draw->Rect);
		add : fn (c : self ref Column, w : ref Windowm->Window, w0 : ref Windowm->Window, n : int) : ref Windowm->Window;
		close : fn (c : self ref Column, w : ref Windowm->Window, n : int);
		closeall : fn (c : self ref Column);
		reshape : fn (c : self ref Column, r : Draw->Rect);
		which : fn (c : self ref Column, p : Draw->Point) : ref Textm->Text;
		dragwin : fn (c : self ref Column, w : ref Windowm->Window, n : int);
		grow : fn (c : self ref Column, w : ref Windowm->Window, m, n : int);
		clean : fn (c : self ref Column, exiting : int) : int;
		sort : fn (c : self ref Column);
		mousebut : fn (c : self ref Column);
	};
};
