Graph : module {
	PATH : con "/dis/acme/graph.dis";

	init : fn(mods : ref Dat->Mods);

	balloc : fn(r : Draw->Rect, c : Draw->Chans, col : int) : ref Draw->Image;
	draw : fn(d : ref Draw->Image, r : Draw->Rect, s : ref Draw->Image, m : ref Draw->Image, p : Draw->Point);
	stringx : fn(d : ref Draw->Image, p : Draw->Point, f : ref Draw->Font, s : string, c : ref Draw->Image);
	cursorset: fn(p : Draw->Point);
	cursorswitch : fn(c : ref Dat->Cursor);
	charwidth : fn(f : ref Draw->Font, c : int) : int;
	strwidth : fn(f : ref Draw->Font, p : string) : int;
	binit : fn();
	bflush : fn();
	berror : fn(s : string);

	font : ref Draw->Font;
};