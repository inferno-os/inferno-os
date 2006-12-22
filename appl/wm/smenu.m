Smenu: module
{
	PATH: con "/dis/wm/smenu.dis";

	Scrollmenu: adt{
		# private data
		m, n, o: int;
		timer: int;
		name: string;
		labs: array of string;
		c: chan of string;
		t: ref Tk->Toplevel;

		new: fn(t: ref Tk->Toplevel, name: string, labs: array of string, entries: int, origin: int): ref Scrollmenu;
		post: fn(m: self ref Scrollmenu, x: int, y: int, resc: chan of string, prefix: string);
		destroy: fn(m: self ref Scrollmenu);
	};
};