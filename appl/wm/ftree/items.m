Items: module {
	PATH: con "/dis/lib/ftree/items.dis";

	Item: adt {
		name:	string;	# tag held in common by all canvas items in this Item.
		r:		Rect;		# relative to parent's Item when stored in children
		attach:	Point;	# attachment point relative to r.min
		
		eq:		fn(i: self Item, j: Item): int;
		addpt:	fn(i: self Item, p: Point): Item;
		subpt:	fn(i: self Item, p: Point): Item;
	};

	Expander: adt {
		titleitem:		Item;
		expanded: 	int;
		children: 		array of Item;
		win: 			ref Tk->Toplevel;
		cvs: 			string;
		spotid:		int;
	
		new:			fn(win: ref Tk->Toplevel, cvs: string): ref Expander;
		make:		fn(e: self ref Expander, it: Item): Item;
		event:		fn(e: self ref Expander, it: Item, ev: string): Item;
		childrenchanged:	fn(e: self ref Expander, it: Item): Item;
	};

	init: 		fn();
	maketext:	fn(win: ref Tk->Toplevel, cvs: string, name: string, text: string): Item;
};
